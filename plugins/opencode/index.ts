import type { Plugin } from "@opencode-ai/plugin";
import { readFileSync, writeFileSync, existsSync } from "fs";
import { join } from "path";
import { createHash } from "crypto";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface LoopState {
  active: boolean;
  sessionId: string | null;
  iteration: number;
  maxIterationsPerSession: number;
  totalIterations: number;
  maxTotalIterations: number;
  startedAt: string;
  lastContinuedAt: string;
  lastStateHash: string;
  stallCount: number;
  stallThreshold: number;
  batchSize: number;
  reviewBatchSize: number;
  pendingSaveProgress: boolean;
}

interface AgentTestState {
  meta: {
    project: string;
    base_url: string;
    created_at: string;
    last_updated: string;
    total_routes: number;
    tested: number;
    pending: number;
    failed: number;
    review_pending: number;
    review_complete: number;
    status?: string;
    blocked_reason?: string;
  };
  completed: Array<{
    route: string;
    tested_at: string;
    status: string;
    bugs_count: number;
    operations_count: {
      total: number;
      passed: number;
      failed: number;
      disabled: number;
    };
    screenshots_dir: string;
    report_file: string;
    summary: string;
    review_status: string;
    bug_report_file: string | null;
  }>;
  failed: Array<{
    route: string;
    failed_at: string;
    error: string;
    retry_count: number;
    last_error: string;
  }>;
  pending: string[];
}

type Phase = "testing" | "review" | "final_report" | "done" | "blocked" | "inactive";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const STATE_FILE = ".monkey-test-state.json";
const LOOP_STATE_FILE = ".monkey-test-loop-state.json";
const FINAL_REPORT_FILE = "monkey-test-reports/FINAL-REPORT.md";
const SERVICE_NAME = "monkey-test-loop";
const DEBOUNCE_MS = 2000;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function hashContent(content: string): string {
  return createHash("sha256").update(content).digest("hex").slice(0, 16);
}

function defaultLoopState(): LoopState {
  return {
    active: true,
    sessionId: null,
    iteration: 0,
    maxIterationsPerSession: 10,
    totalIterations: 0,
    maxTotalIterations: 100,
    startedAt: new Date().toISOString(),
    lastContinuedAt: "",
    lastStateHash: "",
    stallCount: 0,
    stallThreshold: 3,
    batchSize: 3,
    reviewBatchSize: 5,
    pendingSaveProgress: false,
  };
}

function readJsonSafe<T>(filePath: string): T | null {
  try {
    if (!existsSync(filePath)) return null;
    const raw = readFileSync(filePath, "utf-8");
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

function writeJsonSafe(filePath: string, data: unknown): boolean {
  try {
    writeFileSync(filePath, JSON.stringify(data, null, 2) + "\n", "utf-8");
    return true;
  } catch {
    return false;
  }
}

function determinePhase(state: AgentTestState, directory: string): Phase {
  // Check for blocked status first — takes priority over all other phases
  if (state.meta.status === "blocked") {
    return "blocked";
  }

  const { pending, review_pending } = state.meta;

  if (pending > 0) {
    return "testing";
  }

  if (review_pending > 0) {
    return "review";
  }

  // All testing and reviews done - check if final report exists
  const finalReportPath = join(directory, FINAL_REPORT_FILE);
  if (!existsSync(finalReportPath)) {
    return "final_report";
  }

  return "done";
}

// ---------------------------------------------------------------------------
// Prompt Builders
// ---------------------------------------------------------------------------

function buildTestingPrompt(loop: LoopState, state: AgentTestState): string {
  return [
    `## Agent Test \u2014 Continue (Iteration ${loop.iteration}/${loop.maxIterationsPerSession}, Total ${loop.totalIterations}/${loop.maxTotalIterations})`,
    "",
    `Phase: TESTING | Progress: ${state.meta.tested}/${state.meta.total_routes} tested, ${state.meta.pending} pending, ${state.meta.failed} failed`,
    "",
    `Read \`.monkey-test-state.json\`. Pick next batch of pending routes (up to ${loop.batchSize}).`,
    "Dispatch fresh subagents (one new Task per route, no task_id reuse).",
    "Collect results, write reports, update state.",
    "",
    "Pipeline: Phase 2 (test) \u2192 Phase 3 (review) \u2192 Phase 4 (FINAL-REPORT.md) \u2192 DONE.",
    "Update the state file after each batch. The harness reads it to determine next steps.",
  ].join("\n");
}

function buildReviewPrompt(loop: LoopState, state: AgentTestState): string {
  return [
    `## Agent Test \u2014 Continue (Iteration ${loop.iteration}/${loop.maxIterationsPerSession}, Total ${loop.totalIterations}/${loop.maxTotalIterations})`,
    "",
    `Phase: REVIEW | Progress: ${state.meta.review_pending} routes need review, ${state.meta.review_complete} reviewed`,
    "",
    `Read \`.monkey-test-state.json\`. Pick next batch of routes with review_status "review_pending" (up to ${loop.reviewBatchSize}).`,
    "Dispatch fresh review subagents. Collect bug reports, update state file.",
  ].join("\n");
}

function buildFinalReportPrompt(loop: LoopState, state: AgentTestState): string {
  return [
    "## Agent Test \u2014 Generate Final Report",
    "",
    `All testing and reviews complete. ${state.meta.tested} routes tested, ${state.meta.review_complete} reviewed.`,
    "",
    "Generate FINAL-REPORT.md:",
    "1. Read all bug reports from monkey-test-reports/",
    "2. Aggregate statistics from .monkey-test-state.json",
    "3. Write consolidated report to monkey-test-reports/FINAL-REPORT.md",
  ].join("\n");
}

function buildSaveProgressPrompt(loop: LoopState): string {
  return [
    "## Agent Test \u2014 Session Iteration Limit Reached",
    "",
    `You have reached ${loop.maxIterationsPerSession} iterations in this session.`,
    "To manage context length, please:",
    "",
    "1. Ensure \`.monkey-test-state.json\` is fully up to date with all batch results",
    "2. Confirm all reports are written to disk",
    "3. The harness will detect the saved state and resume in a fresh session",
    "",
    "Do NOT start a new batch. Just verify state is saved.",
  ].join("\n");
}

// ---------------------------------------------------------------------------
// Plugin Export
// ---------------------------------------------------------------------------

export const AgentTestLoop: Plugin = async ({ client, $, directory }) => {
  const stateFilePath = join(directory, STATE_FILE);
  const loopStatePath = join(directory, LOOP_STATE_FILE);

  // -----------------------------------------------------------------------
  // Internal helpers bound to plugin context
  // -----------------------------------------------------------------------

  function log(
    level: "info" | "warn" | "error",
    message: string,
    extra?: Record<string, unknown>,
  ): void {
    try {
      client.app.log({
        body: {
          service: SERVICE_NAME,
          level,
          message,
          extra: extra ?? {},
        },
      });
    } catch {
      // If logging itself fails, silently ignore so the plugin never crashes
    }
  }

  function getLoopState(): LoopState {
    const existing = readJsonSafe<LoopState>(loopStatePath);
    if (existing && typeof existing.active === "boolean") {
      return existing;
    }
    const fresh = defaultLoopState();
    writeJsonSafe(loopStatePath, fresh);
    return fresh;
  }

  function saveLoopState(state: LoopState): void {
    if (!writeJsonSafe(loopStatePath, state)) {
      log("error", "Failed to write loop state file");
    }
  }

  function shouldDebounce(loop: LoopState): boolean {
    if (!loop.lastContinuedAt) return false;
    const elapsed = Date.now() - new Date(loop.lastContinuedAt).getTime();
    return elapsed < DEBOUNCE_MS;
  }

  function detectStall(loop: LoopState, currentHash: string): boolean {
    if (loop.lastStateHash === currentHash) {
      loop.stallCount += 1;
    } else {
      loop.stallCount = 0;
      loop.lastStateHash = currentHash;
    }
    return loop.stallCount >= loop.stallThreshold;
  }

  async function injectPrompt(sessionId: string, content: string): Promise<void> {
    await client.session.prompt({
      path: { id: sessionId },
      body: {
        parts: [{ type: "text", text: content }],
      },
    });
  }

  async function injectContextOnly(sessionId: string, content: string): Promise<void> {
    await client.session.prompt({
      path: { id: sessionId },
      body: {
        noReply: true,
        parts: [{ type: "text", text: content }],
      },
    });
  }

  // -----------------------------------------------------------------------
  // Event handler
  // -----------------------------------------------------------------------

  return {
    event: async ({ event }) => {
      try {
        // -----------------------------------------------------------------
        // SESSION CREATED - track session, reset per-session counter
        // -----------------------------------------------------------------
        if (event.type === "session.created") {
          const loop = getLoopState();
          const newSessionId = (event as any).properties?.sessionID ?? null;
          // Always rebind on session.created — if old session crashed without
          // firing session.deleted, this prevents the loop from "sticking dead"
          if (newSessionId) {
            loop.sessionId = newSessionId;
          }
          loop.iteration = 0;
          loop.pendingSaveProgress = false;
          saveLoopState(loop);
          log("info", "Session created, per-session iteration counter reset", {
            sessionId: loop.sessionId,
            totalIterations: loop.totalIterations,
          });
          return;
        }

        // -----------------------------------------------------------------
        // SESSION DELETED - clean up tracked session
        // -----------------------------------------------------------------
        if (event.type === "session.deleted") {
          const loop = getLoopState();
          const deletedId = (event as any).properties?.sessionID ?? null;
          if (deletedId && deletedId === loop.sessionId) {
            loop.sessionId = null;
            saveLoopState(loop);
            log("info", "Tracked session deleted", { sessionId: deletedId });
          }
          return;
        }

        // -----------------------------------------------------------------
        // SESSION ERROR - log, don't auto-deactivate
        // -----------------------------------------------------------------
        if (event.type === "session.error") {
          const loop = getLoopState();
          const errorMsg = (event as any).properties?.error ?? (event as any).properties?.message ?? "unknown error";
          log("error", "Session error detected", {
            sessionId: loop.sessionId,
            error: errorMsg,
          });
          return;
        }

        // -----------------------------------------------------------------
        // SESSION IDLE - the core Ralph Loop driver
        // -----------------------------------------------------------------
        if (event.type === "session.idle") {
          // Guard: agent test state file must exist
          if (!existsSync(stateFilePath)) {
            return; // Not an agent test workspace - silently skip
          }

          const loop = getLoopState();

          // Guard: loop must be active — but auto-reactivate if new work detected
          if (!loop.active) {
            // Check if the state file has been re-initialized with new work
            const reactivateState = readJsonSafe<AgentTestState>(stateFilePath);
            if (
              reactivateState?.meta &&
              (reactivateState.meta.pending > 0 || reactivateState.meta.review_pending > 0)
            ) {
              // New test run detected — reactivate the loop
              loop.active = true;
              loop.iteration = 0;
              loop.totalIterations = 0;
              loop.stallCount = 0;
              loop.lastStateHash = "";
              loop.startedAt = new Date().toISOString();
              saveLoopState(loop);
              log("info", "Auto-reactivated: new pending work detected in state file", {
                pending: reactivateState.meta.pending,
                review_pending: reactivateState.meta.review_pending,
              });
              // Fall through to normal processing
            } else {
              log("info", "Loop is inactive, skipping idle event");
              return;
            }
          }

          // Guard: resolve session ID — bind to first session, reject others
          const eventSessionId = (event as any).properties?.sessionID ?? null;
          if (!eventSessionId && !loop.sessionId) {
            log("warn", "No session ID available, skipping idle event");
            return;
          }

          // If we have a bound session, only accept events from that session
          if (loop.sessionId && eventSessionId && eventSessionId !== loop.sessionId) {
            log("info", "Idle event from different session, skipping", {
              boundSession: loop.sessionId,
              eventSession: eventSessionId,
            });
            return;
          }

          // Bind to this session if not yet bound
          const sessionId = eventSessionId ?? loop.sessionId!;
          if (!loop.sessionId) {
            loop.sessionId = sessionId;
            log("info", "Bound to session", { sessionId });
          }

          // Guard: debounce rapid idle events
          if (shouldDebounce(loop)) {
            log("info", "Debounce active, skipping idle event", {
              lastContinuedAt: loop.lastContinuedAt,
            });
            return;
          }

          // Guard: if we already asked agent to save progress, wait for
          // a new session (session.created resets the flag)
          if (loop.pendingSaveProgress) {
            log("info", "Waiting for agent to save progress and session to recycle");
            return;
          }

          // Read the agent test state file
          let rawState: string;
          try {
            rawState = readFileSync(stateFilePath, "utf-8");
          } catch (e) {
            log("error", "Failed to read agent test state file", {
              error: String(e),
            });
            return;
          }

          let agentState: AgentTestState;
          try {
            agentState = JSON.parse(rawState) as AgentTestState;
          } catch (e) {
            log("error", "Failed to parse agent test state file", {
              error: String(e),
            });
            return;
          }

          // Validate minimal structure
          if (!agentState.meta || typeof agentState.meta.pending !== "number") {
            log("error", "Agent test state file has invalid structure");
            return;
          }

          // Determine current phase
          const phase = determinePhase(agentState, directory);
          log("info", `Phase detected: ${phase}`, {
            pending: agentState.meta.pending,
            review_pending: agentState.meta.review_pending,
            tested: agentState.meta.tested,
            failed: agentState.meta.failed,
            total: agentState.meta.total_routes,
          });

          // If blocked, log and stop (don't inject continuation)
          if (phase === "blocked") {
            const reason = agentState.meta.blocked_reason ?? "unknown reason";
            log("warn", `State is blocked: ${reason}. Stopping loop.`, {
              blocked_reason: reason,
            });
            // Don't deactivate — blocked may be transient. Just don't inject.
            saveLoopState(loop);
            return;
          }

          // If done, deactivate the loop
          if (phase === "done") {
            loop.active = false;
            saveLoopState(loop);
            log("info", "All phases complete. Loop deactivated.", {
              totalIterations: loop.totalIterations,
              tested: agentState.meta.tested,
              failed: agentState.meta.failed,
              reviewed: agentState.meta.review_complete,
            });
            return;
          }

          // Stall detection: hash the raw state content
          const currentHash = hashContent(rawState);
          if (detectStall(loop, currentHash)) {
            loop.active = false;
            saveLoopState(loop);
            log(
              "error",
              `Stall detected: state unchanged for ${loop.stallThreshold} consecutive iterations. Loop deactivated.`,
              { stallCount: loop.stallCount, hash: currentHash },
            );
            // Best-effort notification to the agent
            try {
              await injectContextOnly(
                sessionId,
                [
                  "## Agent Test \u2014 STALLED",
                  "",
                  `The Ralph Loop harness detected no state change for ${loop.stallThreshold} consecutive iterations.`,
                  "The loop has been deactivated to prevent infinite cycling.",
                  "",
                  "Investigate why \`.monkey-test-state.json\` is not being updated.",
                  "To restart: delete \`.monkey-test-loop-state.json\` and trigger a new session.",
                ].join("\n"),
              );
            } catch {
              // Best-effort notification
            }
            return;
          }

          // Total iteration limit
          if (loop.totalIterations >= loop.maxTotalIterations) {
            loop.active = false;
            saveLoopState(loop);
            log(
              "warn",
              `Total iteration limit reached (${loop.maxTotalIterations}). Loop deactivated.`,
              { totalIterations: loop.totalIterations },
            );
            return;
          }

          // Per-session iteration limit - ask agent to save progress
          if (loop.iteration >= loop.maxIterationsPerSession) {
            loop.pendingSaveProgress = true;
            loop.lastContinuedAt = new Date().toISOString();
            saveLoopState(loop);
            log(
              "info",
              `Per-session limit reached (${loop.maxIterationsPerSession}). Asking agent to save progress.`,
              { sessionIteration: loop.iteration },
            );
            try {
              await injectPrompt(sessionId, buildSaveProgressPrompt(loop));
            } catch (e) {
              log("error", "Failed to inject save-progress prompt", {
                error: String(e),
              });
            }
            return;
          }

          // -----------------------------------------------------------------
          // All guards passed - inject continuation prompt
          // -----------------------------------------------------------------

          // Increment counters
          loop.iteration += 1;
          loop.totalIterations += 1;
          loop.lastContinuedAt = new Date().toISOString();

          // Build phase-appropriate prompt
          let prompt: string;
          switch (phase) {
            case "testing":
              prompt = buildTestingPrompt(loop, agentState);
              break;
            case "review":
              prompt = buildReviewPrompt(loop, agentState);
              break;
            case "final_report":
              prompt = buildFinalReportPrompt(loop, agentState);
              break;
            default:
              log("warn", `Unexpected phase: ${phase}`);
              saveLoopState(loop);
              return;
          }

          // Persist state BEFORE injection (crash safety: if injection fails,
          // we roll back counters below; if we crash after injection, the
          // counters are already saved and we won't double-fire)
          saveLoopState(loop);

          log("info", `Injecting ${phase} prompt`, {
            iteration: loop.iteration,
            totalIterations: loop.totalIterations,
            sessionId,
            phase,
          });

          try {
            await injectPrompt(sessionId, prompt);
          } catch (e) {
            log("error", "Failed to inject continuation prompt", {
              error: String(e),
              phase,
              iteration: loop.iteration,
            });
            // Roll back counters so the next idle event can retry
            loop.iteration -= 1;
            loop.totalIterations -= 1;
            loop.lastContinuedAt = "";
            saveLoopState(loop);
          }

          return;
        }
      } catch (e) {
        // Top-level safety net - the plugin must never crash the host
        try {
          log("error", "Unhandled exception in AgentTestLoop plugin", {
            error: String(e),
            stack: (e as Error)?.stack ?? "",
          });
        } catch {
          // Absolute last resort - swallow silently
        }
      }
    },
  };
};

export default AgentTestLoop;
