---
name: agent-test:page-testing
description: Use when a subagent needs to perform DFS click-all agent testing on a single route. Defines the maze-traversal algorithm that clicks every interactive element and backtracks when blocked.
---

# Page Testing — DFS Click-All Algorithm

## Overview

Each subagent tests **one route**. The algorithm treats the page as a maze: click into every interactive element depth-first, screenshot each state, backtrack when blocked, until every reachable node is visited.

## Browser Rules

**CRITICAL — These rules are non-negotiable:**

1. **Agent Browser only** — Use `agent-browser` for ALL browser interactions. Do NOT install Playwright, Puppeteer, Selenium, or any other browser automation tool.
2. **Headless mode** — Agent Browser is headless by default. Do not use non-existent `launch` commands.
3. **Independent session** — Each subagent MUST use its own browser session. NEVER reuse or share a browser instance across subagents. This prevents operation mutex conflicts.
4. **No code file access** — Subagents MUST NOT read project source code. Only interact with the running application through the browser.
5. **Ephemeral lifecycle** — Each subagent tests ONE route, returns its report, and terminates. The orchestrator NEVER reuses a subagent for a second route. Each batch gets fresh Task calls without `task_id`.

### Agent Browser Session Setup

Every subagent MUST start with:

```
agent-browser open {url}
```

This creates an isolated browser instance for this subagent and navigates to the given URL. After all testing completes:

```
agent-browser close
```

**CRITICAL — Browser cleanup is MANDATORY regardless of outcome:**

The `agent-browser close` command MUST be executed even if:
- The test encounters errors or exceptions
- Login fails
- The page is unreachable
- A click causes a crash
- The subagent is about to report `status: "fail"`

Treat every test as a try/finally block:

```
agent-browser open {base_url}
try:
    ... all testing steps ...
finally:
    agent-browser close    ← ALWAYS execute this, no exceptions
```

Failure to close the browser will leak `agent-browser` daemon processes and Chrome child processes. Over a full test run (50+ routes), this can accumulate hundreds of orphaned processes and exhaust system resources.

## The DFS Algorithm

The page is a tree of interactive elements. Each element is a "node". Clicking a node may reveal children (dialogs, dropdowns, wizard steps, sub-menus). The algorithm exhaustively visits every node.

**Snapshot budget:** `snapshot -i` is called only at **decision points** — when the agent needs to discover new elements or verify state changes. Normal clicks with known outcomes get `screenshot` only. See `screenshot-protocol` for the full decision-point table.

```
DFS-CLICK-ALL(page):
    anchor = current_page_state
    elements = discover_all_interactive_elements()  ← requires snapshot -i

    for each element in elements:
        if element.state == "disabled":
            record(element, "disabled", screenshot)        ← screenshot only
            continue

        click(element)
        wait_and_screenshot()                              ← always screenshot
        
        result = classify_result()
        
        if result == "dialog_opened" or result == "dropdown_opened":
            snapshot()                                     ← DECISION POINT: discover children
            children = discover_children()
            DFS-CLICK-ALL(children)
            close_or_escape()
            wait_and_screenshot()
            snapshot()                                     ← DECISION POINT: re-discover after backtrack
        
        elif result == "submenu_opened":
            snapshot()                                     ← DECISION POINT: enumerate submenu
            submenu_items = discover_submenu_items()
            for each item in submenu_items:
                click(item)
                wait_and_screenshot()
                sub_result = classify_result()
                if sub_result needs_discovery:
                    snapshot()                             ← DECISION POINT
                handle_result(sub_result)
                backtrack_to(anchor)
                snapshot()                                 ← DECISION POINT: re-discover
                re_open_submenu(element)
            close_or_escape()
            wait_and_screenshot()
        
        elif result == "page_navigated":
            snapshot()                                     ← DECISION POINT: verify new page
            record(element, "navigated", screenshot)
            navigate_back_to(anchor)
            wait_and_screenshot()
            snapshot()                                     ← DECISION POINT: re-discover after backtrack
        
        elif result == "wizard_opened":
            snapshot()                                     ← DECISION POINT: discover wizard steps
            walk_wizard_steps()
            close_wizard()
            wait_and_screenshot()
            snapshot()                                     ← DECISION POINT: re-discover after backtrack
        
        elif result == "no_response":
            record(element, "no_response")                 ← screenshot already taken, NO snapshot
        
        elif result == "error":
            snapshot()                                     ← DECISION POINT: read error details
            record(element, "error", screenshot)
        
        # Only re-discover if page may have changed and we haven't already snapshotted
        if page_may_have_changed and not already_snapshotted:
            snapshot()                                     ← DECISION POINT: re-discover
```

### Backtracking Rules

| Situation | Backtrack Method |
|-----------|-----------------|
| Dialog/modal opened | Click Cancel / Close / X / press Escape |
| Dropdown opened | Press Escape or click outside |
| Wizard opened | Click Cancel on any step, or press Escape |
| Page navigated away | `agent-browser back` or re-navigate to route URL |
| Confirmation dialog | Screenshot it, then click Cancel (do NOT confirm destructive actions by default) |
| Sub-menu appeared (click) | Press Escape to close |
| Nothing happened | Log "no_response", move to next element |

### Element Re-discovery

After backtracking, the page state may have changed (e.g., a row was added/removed). Always re-snapshot to discover current elements before continuing.

## Testing Phases

### Phase 0: Launch & Login

```
agent-browser open {base_url}
agent-browser wait --load networkidle
agent-browser snapshot -i                              ← DECISION POINT: find login form
# Identify login form from snapshot
agent-browser fill <username_ref> "{username}"
agent-browser fill <password_ref> "{password}"
agent-browser click <login_btn_ref>
agent-browser wait --load networkidle
agent-browser wait 2000
agent-browser screenshot {screenshots_dir}/00-login-success.png
agent-browser snapshot -i                              ← DECISION POINT: verify login, find nav
# Verify: URL no longer /login
```

### Phase 1: Navigate to Route

```
agent-browser open {base_url}{route}
agent-browser wait --load networkidle
agent-browser wait 3000
agent-browser screenshot {screenshots_dir}/01-table-page.png
agent-browser snapshot -i                              ← DECISION POINT: discover all page elements
# Record: page title, table presence, row count, column headers
agent-browser errors
# Record any console errors
```

### Screenshot Baseline Requirement

For each route, always keep the baseline evidence chain:

1. `00-login-success.png` (post-login baseline)
2. `01-table-page.png` (route landing baseline)

These two baseline screenshots are mandatory even if the route has very few actions.

### Phase 2: Toolbar Actions (DFS)

The toolbar area (above the table) contains primary actions: Create, Batch Operations, Filter, Export, Tabs, etc.

For EACH toolbar element:

1. Record label and type
2. Click it
3. Follow screenshot protocol (wait + screenshot)
4. Classify result:
   - If result opens something new (dialog, dropdown, wizard, submenu) → `snapshot -i` (decision point), then recurse into children
   - If result is `no_response`, `toast_notification`, or `disabled` → screenshot only, no snapshot
   - If result is `error` → `snapshot -i` (decision point) to read error details
5. Backtrack to list page state
6. `snapshot -i` after backtracking (decision point — re-discover elements)

### Phase 3: Row Actions (DFS)

If table has rows, test the first row's action menu:

1. Find action trigger (dropdown button, "..." icon, "Actions" column)
2. Click to open action dropdown
3. Screenshot the dropdown showing all actions
4. For EACH action item:
   a. Click the action
   b. Follow screenshot protocol
   c. Classify result (dialog, confirmation, sub-menu, etc.)
   d. Recurse into children if any
   e. Backtrack: close dialog/modal, re-open dropdown
   f. Re-snapshot to find next action

**Sub-menu handling:** If an action reveals a sub-menu, enumerate ALL sub-menu items and test each one individually. Click the parent item, then click each sub-menu item. Always screenshot the open sub-menu before clicking individual items.

### Phase 4: Detail Page

If list rows have clickable names/links:

1. Click first row's name to enter detail page
2. Screenshot detail page
3. **Phase 4A: Header Actions** — DFS through all header buttons and "More Actions" dropdown
4. **Phase 4B: Tabs** — Click every tab, screenshot each tab's content
5. Navigate back to list page

### Phase 5: Final

```
agent-browser errors
# Record accumulated console errors
agent-browser screenshot {screenshots_dir}/07-final-state.png
agent-browser close
```

`07-final-state.png` is mandatory for every route and serves as the route end-state evidence.

### Crash Cleanup

If an error occurs at ANY point before Phase 5, **you MUST still run `agent-browser close`** before returning your report. The sequence is:

```
# Error occurred during testing...
# 1. Try to capture evidence
agent-browser screenshot {screenshots_dir}/XX-crash-state.png    (best effort, may fail)
# 2. ALWAYS close the browser
agent-browser close
# 3. Return report with status: "fail" and the error details
```

Never return from a failed test without closing the browser.

## Result Classification

After each click, classify the outcome:

| Result | Indicators |
|--------|-----------|
| `dialog_opened` | Modal/overlay appeared with form fields or content |
| `dropdown_opened` | Floating menu with action items appeared |
| `wizard_opened` | Multi-step form/wizard appeared |
| `confirmation_dialog` | Simple confirm/cancel dialog appeared |
| `page_navigated` | URL changed, different page loaded |
| `toast_notification` | Toast/snackbar appeared (success or error) |
| `no_response` | Nothing visible changed after click |
| `error` | Error message, error page, or console error |
| `disabled` | Element was disabled/greyed out, could not click |
| `submenu_opened` | Nested menu appeared from click |

## Bug Detection

Report a bug if:

- Blank/white screen after full load
- Error page (500, 404, "error", "exception")
- Console errors from `agent-browser errors`
- Table expected but not rendered
- Button exists but no response on click (and not disabled)
- Modal expected but nothing opens
- Detail page fails to load
- Session expired unexpectedly (redirect to login)
- Broken layout (overlapping, missing text)
- Action causes error toast/notification
- Crash or unrecoverable state

## Action Safety

| Safe to Execute | Approach |
|-----------------|----------|
| Open dialogs/forms | Click to open, screenshot, then Cancel |
| Open dropdowns | Click to open, screenshot, then Escape |
| Switch tabs | Click tab, screenshot content |
| Navigate wizard steps | Click Next through all steps, screenshot each, then Cancel |
| Toggle enable/disable | Safe in test environments |

| Potentially Destructive | Approach |
|------------------------|----------|
| Delete/Remove | Screenshot confirmation dialog, then Cancel by default |
| Submit/Create | If test env is explicitly safe, can submit; otherwise Cancel |
| Batch operations | Screenshot options, then Cancel |

**Default behavior:** Open everything, screenshot everything, Cancel/Escape to backtrack. Only confirm destructive actions if the orchestrator explicitly marks the environment as safe-to-mutate.

## Checklist

- [ ] `agent-browser open {url}` at start
- [ ] Independent session (not shared with other subagents)
- [ ] Login verified before navigation
- [ ] Baseline screenshots present: `00-login-success.png`, `01-table-page.png`
- [ ] Every interactive element clicked (toolbar, row actions, detail actions, tabs)
- [ ] Every click/action followed by wait + screenshot
- [ ] Transition screenshots captured when opening and closing dialog/dropdown/wizard/submenu
- [ ] Error states captured with dedicated `*-error.png` evidence
- [ ] `snapshot -i` used ONLY at decision points (dialog/dropdown/wizard opened, after backtrack, on error, after navigation)
- [ ] `snapshot -i` NOT used for no_response, toast, disabled, Cancel/Escape clicks
- [ ] Sub-menus fully enumerated (click-triggered)
- [ ] DFS backtracking after each interaction
- [ ] All results classified and recorded in action tree
- [ ] Bugs detected and documented with screenshots
- [ ] `agent-browser close` at end **(even if test failed — this is the #1 cause of process leaks)**
- [ ] Final screenshot present: `07-final-state.png`
- [ ] Report JSON produced with full action tree
