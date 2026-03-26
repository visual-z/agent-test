# agent-test

Autonomous UI agent testing powered by AI coding agents. Drop it into **Claude Code** or **OpenCode** — it discovers every route, clicks every button, screenshots every state, and writes a bug report. You start it and walk away.

![Version](https://img.shields.io/badge/version-0.1.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Claude%20Code%20%7C%20OpenCode-purple)

**[中文文档](README.zh-CN.md)** | AI Agents: read **[AGENTS.md](AGENTS.md)**

---

## What is this?

agent-test is a skill + plugin package that turns an AI coding agent into an autonomous QA tester. It:

1. **Discovers** every navigable route in your web application
2. **Tests** each route using a depth-first "click everything" algorithm
3. **Screenshots** every state transition
4. **Reviews** all screenshots for bugs (visual, functional, UX)
5. **Produces** structured, severity-ranked bug reports

The entire pipeline runs unattended after you give the initial command. An external **Ralph Loop** harness (a community pattern by Geoffrey Huntley) drives the agent through each phase by reading a state file and injecting continuation prompts — the agent never controls its own loop.

## How It Works

```
Phase 1: Setup        Route discovery → user picks scope → state file created
Phase 2: Testing      Batch routes → spawn subagents → DFS click-all → screenshots + reports
Phase 3: Review       Batch review → examine screenshots → per-route bug reports
Phase 4: Summary      Aggregate all bug reports → FINAL-REPORT.md → done
```

The Ralph Loop harness (a Claude Code hook or OpenCode plugin) detects when the agent goes idle, reads `.monkey-test-state.json`, and decides what to do next:

| State Condition | Action |
|---|---|
| `pending > 0` | Continue testing |
| `pending == 0`, `review_pending > 0` | Continue reviewing |
| All reviews done, no `FINAL-REPORT.md` | Generate final report |
| `FINAL-REPORT.md` exists | Done — agent stops |
| State unchanged 3 iterations | Stall — agent stops |

The state file is the single source of truth. The agent never needs to emit special tags or control its own loop.

## Quick Start

### Prerequisites

- **jq** — required for JSON parsing (`brew install jq` on macOS, `apt install jq` on Linux)
- **Agent Browser** — the headless browser used by testing subagents. Install via `npm install -g agent-browser` (see [agent-browser on GitHub](https://github.com/vercel-labs/agent-browser) for details)
- **Claude Code** or **OpenCode** — with plugin/hook support

### Claude Code

**One-liner install (from the agent-test repo):**

```bash
bash install/install-claude-code.sh --project
```

This copies the plugin, skills, prompts, and reference docs into your project's `.claude/` directory and registers the plugin with Claude Code.

**Other install options:**

```bash
# Interactive (prompts for project vs global)
bash install/install-claude-code.sh

# Global install (available in all projects)
bash install/install-claude-code.sh --global

# Via npm scripts
npm run install:claude-code
npm run install:claude-code:project
npm run install:claude-code:global

# Development: load directly without copying
claude --plugin-dir ./plugins/claude-code
```

Then open Claude Code and say: **"Run agent test on this project"**

### OpenCode

**One-liner install (from the agent-test repo):**

```bash
bash install/install-opencode.sh --project
```

This copies the plugin, skills, prompts, and reference docs into your project's `.opencode/` directory.

**Other install options:**

```bash
# Interactive (prompts for project vs global)
bash install/install-opencode.sh

# Global install (available in all projects)
bash install/install-opencode.sh --global

# Via npm scripts
npm run install:opencode
npm run install:opencode:project
npm run install:opencode:global
```

Then open OpenCode and say: **"Run agent test on this project"**

### Manual Install

If you prefer not to use the install scripts:

**Claude Code:**
```bash
# Plugin (official plugin format)
mkdir -p .claude/plugins/monkey-test/{.claude-plugin,hooks,scripts}
cp plugins/claude-code/.claude-plugin/plugin.json .claude/plugins/monkey-test/.claude-plugin/
cp plugins/claude-code/hooks/hooks.json .claude/plugins/monkey-test/hooks/
cp plugins/claude-code/scripts/ralph-loop.sh .claude/plugins/monkey-test/scripts/
chmod +x .claude/plugins/monkey-test/scripts/ralph-loop.sh

# Register the plugin (required — without this, Claude Code won't load it)
claude plugin install .claude/plugins/monkey-test --scope project

# Skills, prompts, reference docs
mkdir -p .claude/skills/monkey-test
cp SKILL.md .claude/skills/monkey-test/
cp -R skills/ .claude/skills/monkey-test/skills/
cp -R prompts/ .claude/skills/monkey-test/prompts/
cp -R reference/ .claude/skills/monkey-test/reference/
```

**OpenCode:**
```bash
# Plugin
mkdir -p .opencode/plugins
cp plugins/opencode/index.ts .opencode/plugins/monkey-test-loop.ts

# Skills, prompts, reference docs
mkdir -p .opencode/skills/monkey-test
cp SKILL.md .opencode/skills/monkey-test/
cp -R skills/ .opencode/skills/monkey-test/skills/
cp -R prompts/ .opencode/skills/monkey-test/prompts/
cp -R reference/ .opencode/skills/monkey-test/reference/
```

## Configuration

The agent asks for these at startup:

| Setting | Default | Description |
|---|---|---|
| `base_url` | *(required)* | Your app's URL (e.g., `http://localhost:3000`) |
| `credentials` | *(optional)* | Login username/password if auth is required |
| `batch_size` | `3` | Routes tested per iteration |
| `review_batch_size` | `5` | Routes reviewed per iteration |
| `safe_to_mutate` | `false` | Allow destructive actions (create, delete, submit forms) |
| `max_iterations` | `100` | Max Ralph Loop iterations before forced stop |

### Environment Variables

Set these in your shell or `.env` before starting the agent:

```bash
MONKEY_TEST_BASE_URL="http://localhost:3000"
MONKEY_TEST_USERNAME="admin"
MONKEY_TEST_PASSWORD="password"
MONKEY_TEST_BATCH_SIZE=5
MONKEY_TEST_SAFE_TO_MUTATE=false
```

### Ralph Loop Limits

The harness enforces safety limits to prevent runaway execution:

| Variable | Default | Description |
|---|---|---|
| `MONKEY_TEST_MAX_ITERATIONS_PER_SESSION` | `10` | Iterations before the session ends (prevents context overflow). Start a new session to continue. |
| `MONKEY_TEST_MAX_TOTAL_ITERATIONS` | `100` | Absolute cap across all sessions. |

## Monitoring Progress

### Live state

```bash
jq '.meta' .monkey-test-state.json
```

### Loop state

```bash
jq '.' .monkey-test-loop-state.json
```

### Resuming

If a session ends mid-test, start a new session and say **"resume agent test"**. The agent reads the state file and picks up where it left off.

## Stopping the Loop

| Method | How |
|---|---|
| **Let it finish** | The loop stops automatically when `FINAL-REPORT.md` is generated |
| **Pause** | `mv .monkey-test-state.json .monkey-test-state.json.paused` — rename back to resume |
| **Reset counters** | `rm .monkey-test-loop-state.json` — resets iteration counters |
| **Uninstall** | `bash install/install-claude-code.sh --uninstall` or `bash install/install-opencode.sh --uninstall` |

## Output

After a full test run, your project contains:

```
project-root/
├── ROUTE_MAP.md                          # All discovered routes
├── .monkey-test-state.json               # Progress tracking
├── monkey-test-screenshots/
│   ├── settings_general/
│   │   ├── 00-login-success.png
│   │   ├── 01-table-page.png
│   │   ├── 02-toolbar-create.png
│   │   └── ...
│   └── products_inventory/
│       └── ...
└── monkey-test-reports/
    ├── settings_general.json                # Test report (structured action tree)
    ├── settings_general-bugs.md             # Bug analysis (reviewer output)
    ├── products_inventory.json
    ├── products_inventory-bugs.md
    └── FINAL-REPORT.md                   # Consolidated summary
```

## Project Structure

```
agent-test/
├── SKILL.md                              # Main orchestrator skill
├── AGENTS.md                             # AI agent instructions
├── README.md                             # This file
├── package.json
├── skills/
│   ├── page-testing/SKILL.md             # DFS click-all algorithm
│   ├── route-discovery/SKILL.md          # Route discovery strategies
│   ├── screenshot-protocol/SKILL.md      # Screenshot timing & naming
│   └── state-management/SKILL.md         # State file operations
├── prompts/
│   ├── page-tester-agent.md              # Testing subagent template
│   ├── report-reviewer-agent.md          # Review subagent template
│   └── ralph-loop-harness.md             # Continuation prompt templates
├── reference/
│   ├── state-schema.md                   # State JSON schema
│   ├── report-format.md                  # Test report JSON schema
│   ├── bug-report-format.md              # Bug report Markdown schema
│   └── testing-reference.md              # Result classification guide
├── plugins/
│   ├── claude-code/                      # Claude Code Stop hook plugin
│   │   ├── .claude-plugin/plugin.json
│   │   ├── hooks/hooks.json
│   │   ├── scripts/ralph-loop.sh
│   │   └── README.md
│   └── opencode/                         # OpenCode event plugin
│       ├── index.ts
│       ├── package.json
│       └── README.md
└── install/
    ├── install-claude-code.sh            # One-click Claude Code installer
    └── install-opencode.sh               # One-click OpenCode installer
```

## FAQ

**Does this modify my application?**
Only if you set `safe_to_mutate=true`. By default, the agent avoids create/delete/submit actions. It still clicks into dialogs and forms but does not confirm destructive operations.

**How long does a full test take?**
Depends on route count and complexity. A 50-route app typically takes 20-40 iterations at batch size 3, each running 2-5 minutes. Total: 1-3 hours unattended.

**What browsers does it use?**
Agent Browser (`agent-browser`) — a headless browser for AI agent environments by Vercel. Install via `npm install -g agent-browser` (see [GitHub](https://github.com/vercel-labs/agent-browser)). No Playwright, Puppeteer, or Selenium required.

**Can I test only specific pages?**
Yes. During setup, the agent presents discovered routes and asks you to choose: all, specific categories, or individual pages.

**What if my app requires login?**
Provide credentials during setup. Each subagent logs in independently at the start of its session.

**Does it work with any web framework?**
Yes. Route discovery supports React Router, Vue Router, Angular, Next.js, Nuxt, and generic route files. The browser-based testing works with any web application.

**Can I resume a partial test?**
Yes. The state file tracks progress. Start a new session and say "resume agent test."

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-improvement`
3. Make your changes — keep skills, prompts, and reference docs as Markdown
4. Test the install scripts on both platforms if you modify them
5. Submit a pull request

**Guidelines:**
- Skills must be **platform-agnostic** — they work on any AI agent that supports subagent dispatch
- Plugins are **platform-specific** — one per supported environment
- The Ralph Loop contract (state file + continuation prompts + phase detection) is the integration boundary

## License

MIT
