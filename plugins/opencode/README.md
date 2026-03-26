# Agent Test — OpenCode Ralph Loop Plugin

External harness that drives autonomous agent testing by injecting continuation prompts when the agent goes idle. Eliminates reliance on the agent remembering to self-prompt via `<promise>` tags.

## How It Works

```
┌─────────────┐     session.idle      ┌──────────────────┐
│   OpenCode   │ ──────────────────▶  │  AgentTestLoop      │
│   Runtime    │                       │     Plugin        │
└─────────────┘                       └──────┬───────────┘
                                              │
                                    ┌─────────▼─────────┐
                                    │ Read state file    │
                                    │ Determine phase    │
                                    │ Safety guards      │
                                    └─────────┬─────────┘
                                              │
                                    ┌─────────▼─────────┐
                                    │ Inject prompt      │
                                    │ (testing/review/   │
                                    │  final report)     │
                                    └───────────────────┘
```

1. Agent finishes a batch → OpenCode fires `session.idle`
2. Plugin reads `.monkey-test-state.json` to determine current phase
3. Plugin injects the appropriate continuation prompt
4. Agent wakes up and processes the next batch
5. Repeat until all phases complete (testing → review → final report)

## Installation

### Option A: Single-file install

Copy `index.ts` into your OpenCode plugins directory:

```bash
cp plugins/opencode/index.ts .opencode/plugins/monkey-test-loop.ts
```

### Option B: Package reference

Add to your `opencode.json`:

```json
{
  "plugin": ["agent-test-opencode-plugin"]
}
```

Then install:

```bash
cd plugins/opencode && bun install
```

## Configuration

The plugin uses sensible defaults. Override by editing `.monkey-test-loop-state.json` at the project root:

| Field | Default | Description |
|-------|---------|-------------|
| `active` | `true` | Whether the loop is running |
| `maxIterationsPerSession` | `10` | Iterations before asking agent to save progress (context management) |
| `maxTotalIterations` | `100` | Hard cap across all sessions |
| `stallThreshold` | `3` | Consecutive unchanged-state iterations before auto-stop |
| `batchSize` | `3` | Routes per testing batch (passed to continuation prompt) |
| `reviewBatchSize` | `5` | Routes per review batch |

### Example override

```json
{
  "active": true,
  "maxIterationsPerSession": 15,
  "maxTotalIterations": 200,
  "stallThreshold": 5,
  "batchSize": 5,
  "reviewBatchSize": 8
}
```

## Phase Detection

The plugin reads `.monkey-test-state.json` and decides what to do:

```
meta.pending > 0                          → TESTING phase
meta.pending == 0 && meta.review_pending > 0  → REVIEW phase
meta.pending == 0 && meta.review_pending == 0
  └─ FINAL-REPORT.md missing              → FINAL_REPORT phase
  └─ FINAL-REPORT.md exists               → DONE (loop deactivates)
```

## Safety Guards

### Anti-infinite-loop

| Guard | Behavior |
|-------|----------|
| **Per-session limit** | After N iterations, injects "save progress" prompt instead of continuation. Next `session.created` resets the counter. |
| **Total iteration cap** | Hard stop at N total iterations across all sessions. |
| **Stall detection** | SHA-256 hash of state file. If unchanged for N consecutive iterations, loop auto-stops and notifies the agent. |
| **Debounce** | Ignores `session.idle` events within 2 seconds of last injection (prevents rapid re-firing). |

### Crash safety

- Every handler is wrapped in try/catch — the plugin never crashes the host
- Loop state is persisted to disk before prompt injection
- If injection fails, counters roll back so the next idle can retry
- If the state file is missing or malformed, the plugin silently skips

## Monitoring

All activity is logged via `client.app.log()` with service `monkey-test-loop`:

```
[monkey-test-loop] [info]  Phase detected: testing  { pending: 85, tested: 15, total: 100 }
[monkey-test-loop] [info]  Injecting testing prompt { iteration: 3, totalIterations: 12 }
[monkey-test-loop] [warn]  Per-session limit reached (10). Asking agent to save progress.
[monkey-test-loop] [error] Stall detected: state unchanged for 3 consecutive iterations.
```

## Starting the Loop

1. Ensure `.monkey-test-state.json` exists at the project root (initialized by the route-discovery skill)
2. Start or resume an OpenCode session in the project directory
3. Give the agent an initial instruction to begin testing
4. The plugin takes over on every subsequent idle event

## Stopping the Loop

### Graceful stop

Edit `.monkey-test-loop-state.json`:

```json
{ "active": false }
```

The plugin checks this flag on every idle event and will stop injecting prompts.

### Emergency stop

Delete `.monkey-test-loop-state.json`. The plugin will recreate it with defaults on next idle, but you can also delete `.monkey-test-state.json` to prevent any further activity.

### Auto-stop conditions

The loop auto-stops when:
- All phases complete (testing + review + final report generated)
- Total iteration limit reached
- Stall detected (state unchanged for N iterations)

## File Layout

```
project-root/
├── .monkey-test-state.json          # Test progress (read by plugin)
├── .monkey-test-loop-state.json     # Loop control state (managed by plugin)
├── monkey-test-reports/
│   ├── settings_general.json         # Per-route test reports
│   ├── settings_general-bugs.md     # Per-route bug reports
│   └── FINAL-REPORT.md              # Generated when all phases complete
├── monkey-test-screenshots/
│   └── settings_general/             # Per-route screenshots
└── plugins/
    └── opencode/
        ├── index.ts                 # This plugin
        ├── package.json
        └── README.md
```

## Comparison with Claude Code Hooks

| Feature | Claude Code (hooks.json) | OpenCode (this plugin) |
|---------|--------------------------|------------------------|
| Trigger | `Stop` hook (bash script) | `session.idle` event |
| Detection | Reads state file directly | Reads state file directly |
| Injection | Pipes text to stdin | `client.session.prompt()` API |
| State hashing | In bash script | Native `crypto.createHash` |
| Context management | Session restart via CLI | Per-session iteration limit |
| Logging | File-based | Structured `client.app.log()` |

Both plugins use the same state-file-driven approach — they read `.monkey-test-state.json` to determine phase and inject the appropriate continuation prompt.
