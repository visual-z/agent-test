# Report Format Reference

## Per-Route Report: `monkey-test-reports/{route_slug}.json`

Each subagent produces one report file after testing a single route.

## Schema

```json
{
  "route": "/path/to/route",
  "tested_at": "2026-03-26T10:30:00Z",
  "status": "pass|partial|fail",

  "page_info": {
    "title": "string — visible page title",
    "has_table": "boolean — whether a data table/grid is present",
    "row_count": "number — rows in the table (0 if no table)",
    "column_headers": ["string array — table column names"],
    "tabs": ["string array — page-level tabs above the table"],
    "console_errors": ["string array — errors from agent-browser errors"]
  },

  "action_tree": {
    "toolbar": [
      {
        "label": "string — visible button/element text",
        "type": "button|dropdown_trigger|tab|filter|toggle|link",
        "state": "enabled|disabled",
        "action_result": "dialog_opened|dropdown_opened|wizard_opened|confirmation_dialog|page_navigated|toast_notification|no_response|error|disabled|submenu_opened",
        "screenshot": "string — filename only (no path prefix)",
        "note": "string — optional human-readable note",
        "children": ["recursive — same structure for nested elements"]
      }
    ],
    "row_actions": [
      {
        "label": "string",
        "type": "dropdown_item|button|link|submenu_trigger",
        "state": "enabled|disabled",
        "action_result": "string — same enum as above",
        "screenshot": "string",
        "note": "string",
        "children": []
      }
    ],
    "detail_header_actions": [
      {
        "label": "string",
        "type": "string",
        "state": "string",
        "action_result": "string",
        "screenshot": "string",
        "note": "string",
        "children": []
      }
    ],
    "detail_tabs": [
      {
        "label": "string — tab name",
        "type": "tab",
        "state": "enabled",
        "action_result": "page_navigated",
        "screenshot": "string",
        "note": "string",
        "children": []
      }
    ]
  },

  "bugs": [
    {
      "severity": "critical|major|minor",
      "description": "string — what went wrong",
      "location": "string — phase and element identifier",
      "expected": "string — expected behavior",
      "actual": "string — actual behavior",
      "screenshot": "string — filename of evidence screenshot"
    }
  ],

  "console_errors": ["string array — all console errors collected during test"],

  "summary": "string — brief human-readable summary of findings"
}
```

## Field Rules

### `status`

| Value | Meaning |
|-------|---------|
| `pass` | No bugs found. All interactive elements tested successfully. |
| `partial` | Some bugs found but testing completed for all phases. |
| `fail` | Critical failure prevented testing (login failed, page crashed, app unreachable). |

### `action_result` Enum

| Value | Description |
|-------|-------------|
| `dialog_opened` | Modal/overlay appeared with form fields or content |
| `dropdown_opened` | Floating menu with clickable items appeared |
| `wizard_opened` | Multi-step form/wizard appeared |
| `confirmation_dialog` | Simple confirm/cancel dialog appeared |
| `page_navigated` | URL changed, different page loaded |
| `toast_notification` | Toast/snackbar appeared |
| `no_response` | Nothing visible changed after click |
| `error` | Error message, error page, or console error |
| `disabled` | Element was disabled/greyed out |
| `submenu_opened` | Nested menu appeared from click |

### `severity` Levels

| Level | Criteria |
|-------|----------|
| `critical` | Page crashes, unrecoverable state, data loss |
| `major` | Feature broken (action causes error page, expected dialog missing) |
| `minor` | Cosmetic or environmental issue (silent action, single-tenant limitation) |

### `screenshot` Field

Always a filename only, never a full path. The directory is known from the route slug: `monkey-test-screenshots/{route_slug}/`.

Example: `"screenshot": "02-toolbar-create.png"` resolves to `monkey-test-screenshots/settings_general/02-toolbar-create.png`.

### Action Tree Structure

The `children` array enables recursive depth. When a toolbar button opens a dialog, the dialog's contents (fields, buttons, wizard steps) become children of that button node:

```json
{
  "label": "Create VM",
  "type": "button",
  "state": "enabled",
  "action_result": "wizard_opened",
  "screenshot": "02-toolbar-create.png",
  "children": [
    {
      "label": "Step 1 - Basic Info",
      "type": "wizard_step",
      "state": "enabled",
      "action_result": "page_navigated",
      "screenshot": "02-toolbar-create-step1.png",
      "children": []
    },
    {
      "label": "Step 2 - Network",
      "type": "wizard_step",
      "state": "enabled",
      "action_result": "page_navigated",
      "screenshot": "02-toolbar-create-step2.png",
      "children": []
    }
  ]
}
```

### Correlation Rule

Every entry in `action_tree` MUST have a `screenshot` field. Every screenshot file in the route's screenshot directory MUST have a corresponding entry in the action tree. No orphans in either direction.
