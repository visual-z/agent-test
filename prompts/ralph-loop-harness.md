# Ralph Loop Harness — Continuation Prompts

Prompt templates injected by the external harness (Claude Code hook or OpenCode plugin) to keep the agent test running autonomously. The harness detects when the agent goes idle, reads `.monkey-test-state.json`, and injects the appropriate continuation prompt based on phase detection.

## State-File-Driven Phase Detection

The harness **never** relies on agent output to determine loop state. The `.monkey-test-state.json` file is the single source of truth.

| Condition | Phase | Harness Action |
|-----------|-------|---------------|
| `meta.pending > 0` | Testing | Inject testing continuation prompt |
| `meta.pending == 0 && meta.review_pending > 0` | Review | Inject review continuation prompt |
| `meta.pending == 0 && meta.review_pending == 0 && no FINAL-REPORT.md` | Final Report | Inject final report prompt |
| `FINAL-REPORT.md exists` | Done | Allow agent to stop |
| `meta.status == "blocked"` | Blocked | Alert user, stop loop |
| State hash unchanged for 3 consecutive iterations | Stalled | Stop loop |

## Template 1: First Iteration

**Trigger:** User starts the loop (state file already initialized).

```
## Agent Test — Start (Iteration 1)

Config: base_url={{BASE_URL}}, credentials={{USERNAME}}/{{PASSWORD}}, batch={{BATCH_SIZE}}, review_batch={{REVIEW_BATCH_SIZE}}, safe_to_mutate={{SAFE_TO_MUTATE}}.
State: .monkey-test-state.json | Screenshots: monkey-test-screenshots/ | Reports: monkey-test-reports/

Read state. Pick first batch of pending routes. Dispatch fresh subagents (one new Task per route, no task_id reuse). Collect results, write reports, update state.
Pipeline: Phase 2 (test) → Phase 3 (review) → Phase 4 (FINAL-REPORT.md) → DONE.
Update the state file after completing each batch. The harness reads the state file to determine next steps.
```

## Template 2: Testing Continuation

**Trigger:** Agent went idle and state shows `pending > 0`.

```
## Agent Test — Testing Continue (Iteration {{ITERATION}} of {{MAX_ITERATIONS}})

State file shows {{PENDING}} routes still pending.
Read `.monkey-test-state.json`. Pick next batch of pending routes (up to {{BATCH_SIZE}}).
Dispatch fresh subagents (one new Task per route, no task_id reuse).
Collect results, write reports, update state file.
```

## Template 3: Review Continuation

**Trigger:** Agent went idle and state shows `pending == 0, review_pending > 0`.

```
## Agent Test — Review Continue (Iteration {{ITERATION}} of {{MAX_ITERATIONS}})

All testing complete. State file shows {{REVIEW_PENDING}} routes awaiting review.
Read `.monkey-test-state.json`. Pick next batch of review_pending routes (up to {{REVIEW_BATCH_SIZE}}).
For each route: count screenshots, dispatch fresh review subagent(s) — slice if >30 screenshots.
Collect review results, write bug reports, update state file.
```

## Template 4: Final Report

**Trigger:** Agent went idle and state shows `pending == 0, review_pending == 0`, but `FINAL-REPORT.md` does not exist.

```
## Agent Test — Generate Final Report (Iteration {{ITERATION}})

All testing and review complete. No FINAL-REPORT.md found.
Read all per-route bug reports from monkey-test-reports/.
Aggregate statistics, generate consolidated FINAL-REPORT.md.
Write to monkey-test-reports/FINAL-REPORT.md and print summary to user.
```

## Template 5: Blocked Recovery

**Trigger:** State file contains `meta.status: "blocked"` with a reason.

```
## Agent Test — Recovery (Iteration {{ITERATION}})

Previous block reason: {{BLOCKED_REASON}}
Verify: open {{BASE_URL}} in agent-browser, test login with {{USERNAME}}/{{PASSWORD}}.
If recovered: set meta.status back to "running", read state, continue next batch.
If still blocked: update state with block reason and stop.
```

## Harness Pseudocode

```
config = read_config()
state_file = ".monkey-test-state.json"
iteration = 0
max_iterations = config.max_iterations || 100
per_session_limit = config.per_session_limit || 10
stall_count = 0
last_state_hash = null

inject(FIRST_ITERATION, config)
wait_for_idle()

loop:
    iteration += 1
    if iteration > max_iterations:
        log("Max iterations reached, stopping")
        break

    state = read_json(state_file)
    current_hash = hash(state)

    # Stall detection
    if current_hash == last_state_hash:
        stall_count += 1
        if stall_count >= 3:
            log("Stall detected — state unchanged for 3 iterations, stopping")
            break
    else:
        stall_count = 0
    last_state_hash = current_hash

    # Phase detection from state file
    if state.meta.status == "blocked":
        if should_retry(state.meta.blocked_reason):
            inject(BLOCKED_RECOVERY, state, iteration)
            wait_for_idle()
        else:
            log("Blocked: " + state.meta.blocked_reason)
            break

    elif state.meta.pending > 0:
        inject(TESTING_CONTINUATION, state, iteration)
        wait_for_idle()

    elif state.meta.review_pending > 0:
        inject(REVIEW_CONTINUATION, state, iteration)
        wait_for_idle()

    elif not file_exists("monkey-test-reports/FINAL-REPORT.md"):
        inject(FINAL_REPORT, state, iteration)
        wait_for_idle()

    else:
        log("DONE — FINAL-REPORT.md exists, all phases complete")
        break
```

**Phase transitions are determined by the state file.** The harness reads the state after each idle and picks the correct continuation prompt. The agent does not need to signal which phase it is in.

## Implementation Notes

**Claude Code:** Uses a Stop hook (`plugins/claude-code/scripts/ralph-loop.sh`). The hook fires when the agent finishes responding, reads the state file, and returns `{"decision": "block", "reason": "<continuation prompt>"}` to prevent stopping and inject the next prompt.

**OpenCode:** Uses a TypeScript plugin (`plugins/opencode/index.ts`). Listens for the `session.idle` event, reads the state file, and calls `client.session.prompt()` to inject the continuation.

Both implementations share the same phase detection logic and continuation prompt templates defined above.
