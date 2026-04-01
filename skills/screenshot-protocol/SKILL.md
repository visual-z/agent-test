---
name: agent-test:screenshot-protocol
description: Use when taking screenshots during agent testing. Defines wait-before-screenshot protocol, snapshot-at-decision-points optimization, naming conventions, and screenshot-to-step correlation.
---

# Screenshot Protocol

## Overview

Every action in agent testing MUST produce a screenshot. This skill defines the mandatory wait-before-screenshot sequence, naming conventions, and how screenshots correlate to report steps.

**Tool:** All screenshots use `agent-browser screenshot` (Agent Browser). Browser sessions start with `agent-browser open <url>` (headless is the default). Each subagent uses its own independent browser session.

## Snapshot Budget — Decision Points Only

`snapshot -i` returns the full DOM accessibility tree to the agent's context. This is **expensive** — it consumes tokens and slows iteration. Only call `snapshot -i` when the agent needs to **decide what to do next** (discover elements, read revealed content, verify state after navigation).

**Every action MUST produce a `screenshot`.** But `snapshot -i` is reserved for decision points.

### Decision Points (screenshot + snapshot -i)

| Situation | Why snapshot needed |
|-----------|-------------------|
| After login | Verify login state, find navigation |
| After navigating to route | Discover all page elements for DFS |
| Click opened dialog/dropdown/wizard/submenu | Discover children for DFS recursion |
| After backtracking (close dialog, navigate back) | Re-discover page elements — DOM may have changed |
| After page navigation (URL changed) | Verify new page state before recording |
| On error (error page, crash, unexpected state) | Read error message for bug report |

### Non-Decision Points (screenshot only, NO snapshot -i)

| Situation | Why snapshot NOT needed |
|-----------|----------------------|
| Click produced `no_response` | Nothing changed — screenshot is evidence enough |
| Click produced `toast_notification` | Toast is visible in screenshot — no DOM discovery needed |
| Disabled element recorded | Just visual evidence |
| Clicking Cancel / X / Escape to backtrack | Backtrack result gets a snapshot (see above), but the dismiss click itself doesn't |
| Clicking a tab (content swap, no new interactive elements to discover) | Screenshot the tab content; only snapshot if the tab reveals a complex sub-form |

### Sequences

**Decision point — click opens something new:**

```
agent-browser click <element_ref>
agent-browser wait --load networkidle
agent-browser wait 2000
agent-browser screenshot <path>/<step_name>.png
agent-browser snapshot -i
```

**Non-decision point — click with known/simple outcome:**

```
agent-browser click <element_ref>
agent-browser wait --load networkidle
agent-browser wait 2000
agent-browser screenshot <path>/<step_name>.png
```

**Slow pages (wizards, detail pages):** Use `wait 3000` instead of `wait 2000`. Snapshot rules still apply — only at decision points.

**Rule of thumb:** If you need to read the DOM to decide your next action, `snapshot -i`. If you already know what to do next (backtrack, move to next element, record and continue), screenshot only.

## Naming Convention

```
monkey-test-screenshots/{route_slug}/{phase}-{action}.png
```

## Minimum Evidence Set (Required)

To keep screenshot volume controlled while preserving review quality, every route MUST include this minimum evidence set:

1. **Entry baseline screenshots**
   - `00-login-success.png` (post-login baseline)
   - `01-table-page.png` (route landing baseline)
2. **Action result screenshots**
   - One screenshot after each executed action/click result
3. **State-transition screenshots**
   - When an action opens dialog/dropdown/wizard/submenu
   - After returning/backtracking to the parent state
4. **Error evidence screenshots**
   - Any error page/toast/failure state must have a dedicated screenshot (`*-error.png`)
5. **Route final screenshot**
   - `07-final-state.png` at the end of the route test

This is the minimum set. Additional screenshots are allowed when needed for bug evidence, but do not add random duplicates.

### Phase Prefixes

| Prefix | Phase | Example |
|--------|-------|---------|
| `00` | Login | `00-login-success.png` |
| `01` | Table/list page load | `01-table-page.png` |
| `02` | Toolbar actions | `02-toolbar-create.png` |
| `03` | Row actions | `03-row-action-edit.png` |
| `04` | Detail page load | `04-detail-page.png` |
| `05` | Detail header actions | `05-detail-action-start.png` |
| `06` | Detail tabs | `06-tab-overview.png` |
| `07` | Return to list | `07-back-to-list.png` |
| `08` | Sub-interactions (nested dialogs, wizard steps) | `08-sub-wizard-step2.png` |

### Action Name Rules

- Use lowercase with hyphens: `create`, `batch-ops`, `edit-name`
- For submenus, chain with `-`: `export-csv`, `bulk-update`
- For results after action: append `-result`: `02-toolbar-create-result.png`
- For disabled elements: append `-disabled`: `03-row-action-delete-disabled.png`
- For errors: append `-error`: `03-row-action-bond-error.png`

## Screenshot-to-Step Correlation

Every screenshot filename MUST appear in the route report's action tree. The report references screenshots by filename only (no path prefix), since the directory is known from the route slug.

```json
{
  "label": "Create",
  "screenshot": "02-toolbar-create.png",
  "children": [
    {
      "label": "Step 1",
      "screenshot": "02-toolbar-create-step1.png"
    }
  ]
}
```

## Checklist

- [ ] Wait sequence executed before every screenshot (normally 2000ms; 3000ms for slower pages)
- [ ] `snapshot -i` used ONLY at decision points (dialog/dropdown/wizard opened, after backtrack, after navigation, on error)
- [ ] `snapshot -i` NOT used for no_response, toast, disabled, Cancel/Escape clicks
- [ ] Phase prefix matches the current testing phase
- [ ] Action name is descriptive and matches report label
- [ ] Every screenshot has a corresponding entry in the action tree
- [ ] Minimum evidence set covered: baseline (`00`, `01`), action results, transition points, error evidence, final (`07`)
- [ ] No orphan screenshots (screenshot without report entry)
- [ ] No orphan report entries (report entry without screenshot)
