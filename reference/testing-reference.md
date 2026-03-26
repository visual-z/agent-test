# Testing Reference

Quick-reference tables for page tester subagents. The subagent prompt tells you to `Read` this file when you need classification or naming details.

## Result Classification

After each click, classify the outcome based on what you see:

| Result | What You See |
|--------|-------------|
| `dialog_opened` | Modal/overlay with form fields or content |
| `dropdown_opened` | Floating menu with action items |
| `wizard_opened` | Multi-step form appeared |
| `confirmation_dialog` | Simple confirm/cancel dialog |
| `page_navigated` | URL changed |
| `toast_notification` | Toast/snackbar appeared |
| `no_response` | Nothing visible changed |
| `error` | Error message, error page, or console error |
| `disabled` | Element greyed out, not clickable |
| `submenu_opened` | Nested menu from click |

**Decision point results** (need `snapshot -i` after screenshot): `dialog_opened`, `dropdown_opened`, `wizard_opened`, `submenu_opened`, `page_navigated`, `error`.

**Non-decision results** (screenshot only, no `snapshot -i`): `no_response`, `toast_notification`, `disabled`, `confirmation_dialog` (screenshot then Cancel).

## Bug Detection Triggers

Report a bug if ANY of these occur:

- Blank/white screen after full load
- Error page (500, 404, "error", "exception")
- Console errors from `agent-browser errors`
- Table expected but not rendered
- Button exists but no response on click (and not disabled)
- Modal expected but nothing opens
- Detail page fails to load
- Redirect to login (session expired)
- Broken layout (overlapping, missing text)
- Action causes error toast
- Unrecoverable state (cannot backtrack)

## Screenshot Naming

### Minimum Required Screenshot Set

For each tested route, ensure at least:

- `00-login-success.png` (post-login baseline)
- `01-table-page.png` (route landing baseline)
- One screenshot for every executed action result
- Transition evidence for open/close cycles (dialog/dropdown/wizard/submenu)
- Dedicated `*-error.png` screenshot for each error state
- `07-final-state.png` (route end-state)

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
| `08` | Nested interactions | `08-sub-wizard-step2.png` |

### Action Name Rules

- Lowercase with hyphens: `create`, `batch-ops`, `edit-name`
- Submenus chain with `-`: `export-csv`, `bulk-update`
- Results after action: append `-result`: `02-toolbar-create-result.png`
- Disabled elements: append `-disabled`: `03-row-action-delete-disabled.png`
- Errors: append `-error`: `03-row-action-bond-error.png`

## Backtracking Methods

| Situation | Method |
|-----------|--------|
| Dialog/modal opened | Click Cancel / Close / X / press Escape |
| Dropdown opened | Press Escape or click outside |
| Wizard opened | Click Cancel on any step, or press Escape |
| Page navigated away | `agent-browser back` or re-navigate to route URL |
| Confirmation dialog | Screenshot it, then click Cancel |
| Sub-menu appeared (click) | Press Escape to close |
| Nothing happened | Log "no_response", move to next element |

## Action Safety

| Safe to Execute | Approach |
|-----------------|----------|
| Open dialogs/forms | Click to open, screenshot, then Cancel |
| Open dropdowns | Click to open, screenshot, then Escape |
| Switch tabs | Click tab, screenshot content |
| Navigate wizard steps | Click Next through all steps, screenshot each, then Cancel |

| Potentially Destructive | Approach |
|------------------------|----------|
| Delete/Remove | Screenshot confirmation dialog, then Cancel by default |
| Submit/Create | If safe_to_mutate is true, can submit; otherwise Cancel |
| Batch operations | Screenshot options, then Cancel |
