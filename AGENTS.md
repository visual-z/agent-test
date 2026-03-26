# AGENTS.md — Instructions for AI Agents

If you are an AI agent (Claude, GPT, Gemini, or any LLM-based coding assistant), this file tells you how to install and run agent-test. Follow these steps exactly.

---

## What agent-test Does

agent-test is a skill + plugin package that makes you an autonomous QA tester. Once installed and triggered, you will:

1. Discover every navigable route in a web application
2. Test each route by clicking every interactive element (DFS "maze algorithm")
3. Screenshot every state transition
4. Review all screenshots for bugs
5. Produce a consolidated bug report

An external **Ralph Loop harness** (a plugin installed alongside the skills) keeps you running across iterations. You do not need to loop yourself. You run one batch, update the state file, and go idle. The harness reads the state file, determines if work remains, and re-invokes you with a continuation prompt.

---

## Step 1: Determine Your Platform

You are running in one of these environments:

| Platform | How to detect |
|---|---|
| **Claude Code** | You have access to `claude` CLI commands. Your hooks system uses `hooks.json`. Your plugin system uses `.claude-plugin/plugin.json` manifests. |
| **OpenCode** | You have access to the `skill` tool, `task` tool, and `todowrite` tool. Your plugin system uses TypeScript files in `.opencode/plugins/`. |

Pick the installation path that matches your platform.

---

## Step 2: Install (Claude Code)

**ALWAYS use the install script.** Run this from the agent-test repo root:

```bash
bash install/install-claude-code.sh --project
```

This is the recommended installation method. It copies all plugin, skill, prompt, and reference files into the project's `.claude/` directory, **and registers the plugin with Claude Code** via `claude plugin install`. Use `--global` instead to install into `~/.claude/` for all projects.

> **Important:** The install script handles plugin registration automatically. If you skip the script and copy files manually, Claude Code will **not** load the plugin unless you also run `claude plugin install`.

**What gets installed:**

| Destination | Contents |
|---|---|
| `.claude/plugins/monkey-test/.claude-plugin/plugin.json` | Plugin manifest |
| `.claude/plugins/monkey-test/hooks/hooks.json` | Stop hook registration |
| `.claude/plugins/monkey-test/scripts/ralph-loop.sh` | Ralph Loop harness script |
| `.claude/skills/monkey-test/SKILL.md` | Main orchestrator skill |
| `.claude/skills/monkey-test/skills/` | Sub-skills (page-testing, route-discovery, screenshot-protocol, state-management) |
| `.claude/skills/monkey-test/prompts/` | Subagent prompt templates |
| `.claude/skills/monkey-test/reference/` | Schema docs and classification guides |

**Prerequisites:**
- `jq` must be installed. Check with `which jq`. If missing: `brew install jq` (macOS) or `apt install jq` (Linux).
- `agent-browser` must be installed. Check with `which agent-browser`. If missing: `npm install -g agent-browser` (see [GitHub](https://github.com/vercel-labs/agent-browser)). This is the headless browser used by testing subagents.

<details>
<summary><strong>Manual install</strong> (only if the install script is unavailable)</summary>

```bash
mkdir -p .claude/plugins/monkey-test/{.claude-plugin,hooks,scripts}
cp plugins/claude-code/.claude-plugin/plugin.json .claude/plugins/monkey-test/.claude-plugin/
cp plugins/claude-code/hooks/hooks.json .claude/plugins/monkey-test/hooks/
cp plugins/claude-code/scripts/ralph-loop.sh .claude/plugins/monkey-test/scripts/
chmod +x .claude/plugins/monkey-test/scripts/ralph-loop.sh

# Register the plugin (required — without this, Claude Code won't load it)
claude plugin install .claude/plugins/monkey-test --scope project

mkdir -p .claude/skills/monkey-test
cp SKILL.md .claude/skills/monkey-test/
cp -R skills/ .claude/skills/monkey-test/skills/
cp -R prompts/ .claude/skills/monkey-test/prompts/
cp -R reference/ .claude/skills/monkey-test/reference/
```

</details>

---

## Step 2: Install (OpenCode)

**ALWAYS use the install script.** Run this from the agent-test repo root:

```bash
bash install/install-opencode.sh --project
```

This is the recommended installation method. It copies all plugin, skill, prompt, and reference files into the project's `.opencode/` directory. OpenCode automatically discovers plugins from `.opencode/plugins/` — no manual registration is needed. Use `--global` instead to install into `~/.config/opencode/` for all projects.

**What gets installed:**

| Destination | Contents |
|---|---|
| `.opencode/plugins/monkey-test-loop.ts` | Ralph Loop harness plugin |
| `.opencode/skills/monkey-test/SKILL.md` | Main orchestrator skill |
| `.opencode/skills/monkey-test/skills/` | Sub-skills |
| `.opencode/skills/monkey-test/prompts/` | Subagent prompt templates |
| `.opencode/skills/monkey-test/reference/` | Schema docs and classification guides |

**Prerequisites:**
- `jq` must be installed. Check with `which jq`. If missing: `brew install jq` (macOS) or `apt install jq` (Linux).
- `agent-browser` must be installed. Check with `which agent-browser`. If missing: `npm install -g agent-browser` (see [GitHub](https://github.com/vercel-labs/agent-browser)). This is the headless browser used by testing subagents.

<details>
<summary><strong>Manual install</strong> (only if the install script is unavailable)</summary>

```bash
mkdir -p .opencode/plugins
cp plugins/opencode/index.ts .opencode/plugins/monkey-test-loop.ts

mkdir -p .opencode/skills/monkey-test
cp SKILL.md .opencode/skills/monkey-test/
cp -R skills/ .opencode/skills/monkey-test/skills/
cp -R prompts/ .opencode/skills/monkey-test/prompts/
cp -R reference/ .opencode/skills/monkey-test/reference/
```

</details>


---

## Step 3: Run agent-test

Once installed, the user will say something like:

- "Run agent test on this project"
- "Agent test this app"
- "Start autonomous UI testing"

When you receive this instruction, load the `monkey-test` skill (the `SKILL.md` file installed above) and follow it exactly. The skill contains the full 4-phase pipeline.

**Quick summary of what you will do:**

### Phase 1: Setup
1. Run route discovery (scan source code or explore the running app in a browser)
2. Present discovered routes to the user and **ask which to test** (all, categories, or specific routes) — never assume "test everything"
3. Collect configuration: `base_url`, credentials, `batch_size`, `safe_to_mutate`
4. Initialize `.monkey-test-state.json` with selected routes as `pending`
5. Create output directories: `monkey-test-screenshots/`, `monkey-test-reports/`

### Phase 2: Test Execution
1. Read `.monkey-test-state.json`
2. Pick next batch of pending routes (default: 3)
3. Dispatch one **fresh** subagent per route (use `Task` tool, never reuse subagents)
4. Each subagent: launches headless browser, navigates to route, runs DFS click-all, screenshots everything, returns JSON report, terminates
5. Collect results, write reports to `monkey-test-reports/{route_slug}.json`
6. Update state file (move routes from `pending` to `completed` or `failed`)
7. Go idle — the harness reads the state file and re-invokes you if pending routes remain

### Phase 3: Bug Report Review
1. Pick batch of routes with `review_status: "review_pending"` (default batch: 5)
2. Dispatch one **fresh** review subagent per route
3. Each reviewer examines screenshots + test report, produces per-route bug report
4. Routes with >30 screenshots are sliced across multiple reviewers
5. Write bug reports to `monkey-test-reports/{route_slug}-bugs.md`
6. Update state file
7. Go idle — harness continues if review_pending routes remain

### Phase 4: Final Summary
1. Read all per-route bug reports
2. Aggregate into `monkey-test-reports/FINAL-REPORT.md`
3. Go idle — harness sees `FINAL-REPORT.md` and lets you stop

---

## Critical Rules

These rules are non-negotiable. Violating them will break the pipeline.

### Subagent Lifecycle
- **Every subagent is ephemeral.** One fresh `Task()` call per route. No `task_id` reuse. Born, do one job, return result, die.
- **Never reuse a subagent for multiple routes.** Accumulated context causes hallucinations and context overflow.
- **Each testing subagent launches its own browser session** with `agent-browser launch --headless` and closes it with `agent-browser close`.
- **Review subagents do not use browsers.** They read files only.

### State File
- `.monkey-test-state.json` is the single source of truth.
- **Only the orchestrator (you) writes to it.** Subagents never touch it.
- **Always read before writing.** Build the full JSON object, then write atomically.
- Every route is in exactly one array: `pending`, `completed`, or `failed`.
- Counters in `meta` must match array lengths.

### Ralph Loop Contract
- You do NOT loop yourself. The external harness handles iteration.
- You do NOT need to emit `<promise>` tags or any special markers.
- After each batch: update the state file, then go idle. That is all.
- The harness reads the state file and decides what to do next.

### Safety
- Default `safe_to_mutate` is `false`. Do not click "Confirm", "Delete", "Submit", or "Create" on destructive actions unless the user explicitly enables mutation.
- If login fails or the app is unreachable, write `status: "blocked"` to the state file with a reason. The harness will stop.

---

## Key Files Reference

After installation, these are the files you need to know about:

| File | Purpose | When to read |
|---|---|---|
| `SKILL.md` | Main orchestrator skill — full pipeline logic | At the start of every agent-test session |
| `skills/page-testing/SKILL.md` | DFS click-all algorithm | Loaded by testing subagents |
| `skills/route-discovery/SKILL.md` | Route discovery strategies | Phase 1 |
| `skills/screenshot-protocol/SKILL.md` | Screenshot timing, naming, budget | Loaded by testing subagents |
| `skills/state-management/SKILL.md` | State file operations | Every phase |
| `prompts/page-tester-agent.md` | Template for testing subagent dispatch | Phase 2 |
| `prompts/report-reviewer-agent.md` | Template for review subagent dispatch | Phase 3 |
| `prompts/ralph-loop-harness.md` | Continuation prompt templates | Used by the harness, not by you |
| `reference/state-schema.md` | `.monkey-test-state.json` schema | When initializing or updating state |
| `reference/report-format.md` | Test report JSON schema | Phase 2 output |
| `reference/bug-report-format.md` | Bug report Markdown schema | Phase 3-4 output |
| `reference/testing-reference.md` | Result classification guide | Loaded on demand by subagents |

---

## Resuming a Partial Test

If the session ended mid-test (context overflow, crash, or session limit), the user will say something like "resume agent test."

1. Read `.monkey-test-state.json`
2. Validate invariants (counters match arrays)
3. Check which phase you are in:
   - `pending > 0` → resume testing
   - `pending == 0, review_pending > 0` → resume reviewing
   - `pending == 0, review_pending == 0, no FINAL-REPORT.md` → generate final report
   - `FINAL-REPORT.md exists` → already done, tell the user
4. Continue from the appropriate phase

---

## Uninstalling

```bash
# Claude Code
bash install/install-claude-code.sh --uninstall

# OpenCode
bash install/install-opencode.sh --uninstall
```

This removes the plugin, skills, prompts, and reference docs from both project and global locations. It does NOT remove test output (screenshots, reports, state file).
