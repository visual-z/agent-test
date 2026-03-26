# Claude Code Plugin — Agent Test Ralph Loop

A Claude Code **Stop hook plugin** that drives autonomous agent testing without relying on agent-emitted promise tags. The hook reads `.monkey-test-state.json` after every agent response, determines whether work remains, and injects a continuation prompt to keep the pipeline running.

## How It Works

```
Agent finishes responding
        │
        ▼
   Stop hook fires
        │
        ▼
scripts/ralph-loop.sh reads .monkey-test-state.json
        │
        ├── pending > 0 ──────────────▶ Block with TESTING prompt
        ├── review_pending > 0 ────────▶ Block with REVIEW prompt
        ├── no FINAL-REPORT.md ────────▶ Block with FINAL_REPORT prompt
        └── FINAL-REPORT.md exists ────▶ Exit 0 (agent stops, work is done)
```

The agent never controls its own loop. The hook is the sole driver of iteration.

## Prerequisites

- **jq** — required for JSON parsing. Install via `brew install jq` (macOS) or `apt-get install jq` (Linux). The hook exits silently if jq is missing.
- **Claude Code** — with plugin support (Stop hooks).

## Installation

### Option A: Install as a plugin (recommended)

Use `claude plugin install` with the path to this plugin directory:

```bash
claude plugin install ./plugins/claude-code
```

Or pass it at launch time:

```bash
claude --plugin-dir ./plugins/claude-code
```

Claude Code reads `.claude-plugin/plugin.json` (the plugin manifest), which declares `hooks/hooks.json` as the hook entry point via the `hooks` field. The hook command uses `${CLAUDE_PLUGIN_ROOT}` to resolve `scripts/ralph-loop.sh` relative to the plugin directory, making paths fully portable — no hardcoded absolute paths needed.

### Option B: Install from a remote path or different location

If the plugin directory lives outside your project:

```bash
claude plugin install /absolute/path/to/plugins/claude-code
```

`${CLAUDE_PLUGIN_ROOT}` resolves automatically to wherever the plugin is installed, so the hook script is always found regardless of where you install it from.

## Configuration

All configuration is via environment variables. Defaults work out of the box.

| Variable | Default | Description |
|----------|---------|-------------|
| `MONKEY_TEST_MAX_ITERATIONS_PER_SESSION` | `10` | Max iterations before the hook lets the session end. Prevents context overflow. Start a new session to continue. |
| `MONKEY_TEST_MAX_TOTAL_ITERATIONS` | `100` | Absolute safety limit across all sessions. Prevents runaway loops. |

Set them in your shell profile or before launching Claude Code:

```bash
export MONKEY_TEST_MAX_ITERATIONS_PER_SESSION=15
export MONKEY_TEST_MAX_TOTAL_ITERATIONS=200
```

## Starting an Agent Test Session

1. **Initialize the state file.** Run the agent-test skill's Phase 1 setup (route discovery, route selection, state initialization). This creates `.monkey-test-state.json` with your selected routes in the `pending` array.

2. **Start Claude Code.** The hook fires automatically after every agent response. As long as `.monkey-test-state.json` exists and has pending work, the loop runs.

3. **Give the first instruction.** Tell the agent to start testing:

   ```
   Read .monkey-test-state.json and begin agent testing. Pick the first batch of pending routes and dispatch subagents.
   ```

4. **Walk away.** The hook drives the rest.

## Monitoring Progress

### Live state

Check the state file at any time:

```bash
jq '.meta' .monkey-test-state.json
```

Output:

```json
{
  "total_routes": 120,
  "tested": 45,
  "pending": 70,
  "failed": 5,
  "review_pending": 40,
  "review_complete": 5
}
```

### Loop state

Check the hook's internal state:

```bash
jq '.' .monkey-test-loop-state.json
```

Output:

```json
{
  "session_id": "abc123",
  "iteration": 7,
  "max_iterations_per_session": 10,
  "total_iterations": 32,
  "max_total_iterations": 100,
  "started_at": "2026-03-26T10:00:00Z",
  "last_continued_at": "2026-03-26T10:45:00Z",
  "last_state_fingerprint": "a1b2c3...",
  "stall_count": 0
}
```

### Phase detection

The hook determines the current phase from the state file:

| Condition | Phase | What happens |
|-----------|-------|-------------|
| `pending > 0` | TESTING | Agent picks next batch of routes to test |
| `pending == 0, review_pending > 0` | REVIEW | Agent picks next batch of routes to review |
| `pending == 0, review_pending == 0, no FINAL-REPORT.md` | FINAL_REPORT | Agent generates the final consolidated report |
| `FINAL-REPORT.md exists` | DONE | Hook exits silently, agent stops |

## Stopping the Loop

### Graceful stop — let it finish

The loop stops automatically when all phases are complete and `monkey-test-reports/FINAL-REPORT.md` exists.

### Session limit

After `MONKEY_TEST_MAX_ITERATIONS_PER_SESSION` iterations (default 10), the hook lets the session end. This prevents context overflow. Start a new Claude Code session to continue — the hook picks up where it left off.

### Manual stop — remove the state file

```bash
mv .monkey-test-state.json .monkey-test-state.json.paused
```

Without the state file, the hook exits silently and the agent stops normally. Rename it back to resume.

### Emergency stop — delete loop state

```bash
rm .monkey-test-loop-state.json
```

This resets all iteration counters. The hook reinitializes on the next run.

### Disable the hook

Uninstall the plugin:

```bash
claude plugin uninstall agent-test
```

Or simply stop passing `--plugin-dir` at launch.

## Safety Guards

The hook implements multiple layers of protection against infinite loops:

| Guard | Behavior |
|-------|----------|
| **Per-session iteration limit** | After N iterations (default 10), the hook lets the session end. Prevents context overflow. The per-session counter resets when a new session starts. |
| **Total iteration limit** | After M total iterations across all sessions (default 100), the hook stops permanently. Hard safety ceiling. |
| **Stall detection** | If `.monkey-test-state.json` is unchanged for 3 consecutive iterations, the hook logs a warning and lets the agent stop. This catches cases where the agent runs but makes no progress. |
| **Missing state file** | If `.monkey-test-state.json` doesn't exist, the hook exits silently. Not an agent-test session. |
| **Invalid state file** | If the state file is empty or contains invalid JSON, the hook exits silently with a warning. |
| **Missing jq** | If `jq` is not installed, the hook exits silently with a warning. |

## File Layout

```
plugins/claude-code/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest (name, version, hooks path)
├── hooks/
│   └── hooks.json           # Hook registration using ${CLAUDE_PLUGIN_ROOT}
├── scripts/
│   └── ralph-loop.sh        # The Stop hook script (main logic)
├── skills/                  # Reserved for skill files (future)
│   └── .gitkeep
└── README.md                # This file

Runtime files (created in project root):
├── .monkey-test-state.json       # Test progress (managed by the agent)
└── .monkey-test-loop-state.json  # Hook iteration tracking (managed by the hook)
```

## Troubleshooting

**Hook doesn't fire:**
- Verify the plugin is installed: `claude plugin list`
- Check that `scripts/ralph-loop.sh` is executable (`chmod +x`)
- Check Claude Code logs for hook errors

**Agent stops unexpectedly:**
- Check `jq` is installed: `which jq`
- Check `.monkey-test-loop-state.json` for iteration limits or stall counts
- Check stderr output: the hook logs all decisions to stderr

**Agent keeps running but makes no progress:**
- The stall detector will catch this after 3 iterations
- Check `.monkey-test-state.json` — are routes moving between arrays?
- Manually inspect agent output for errors

**Session ended due to iteration limit:**
- This is expected behavior. Start a new Claude Code session.
- The hook resets the per-session counter automatically for new sessions.
- To increase the limit: `export MONKEY_TEST_MAX_ITERATIONS_PER_SESSION=20`

**Total iteration limit reached:**
- Reset by editing `.monkey-test-loop-state.json`: set `total_iterations` to 0
- Or delete the file: `rm .monkey-test-loop-state.json`
- Consider whether the test is actually making progress
