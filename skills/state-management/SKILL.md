---
name: agent-test:state-management
description: Use when initializing, updating, or resuming agent test state across sessions. Manages the global progress file and per-route action trees.
---

# State Management

## Overview

Manages two tiers of state for cross-session agent testing:

1. **Global State** — Tracks which routes are tested/pending/failed and which have been reviewed
2. **Route Action Tree** — Per-route DFS traversal state (the "maze map")

## Global State: `.monkey-test-state.json`

Lives at project root. Tracks overall progress across both testing and review phases.

```json
{
  "meta": {
    "project": "project-name",
    "base_url": "http://example.com:5000",
    "created_at": "ISO-8601",
    "last_updated": "ISO-8601",
    "total_routes": 120,
    "tested": 15,
    "pending": 100,
    "failed": 5,
    "review_pending": 10,
    "review_complete": 5
  },
  "completed": [
    {
      "route": "/settings/general",
      "tested_at": "ISO-8601",
      "status": "pass|partial|fail",
      "bugs_count": 0,
      "operations_count": {"total": 10, "passed": 10, "failed": 0, "disabled": 0},
      "screenshots_dir": "monkey-test-screenshots/settings_general/",
      "report_file": "monkey-test-reports/settings_general.json",
      "summary": "Brief human-readable summary",
      "review_status": "review_pending|review_complete|review_failed",
      "bug_report_file": "monkey-test-reports/settings_general-bugs.md"
    }
  ],
  "failed": [],
  "pending": ["/settings/billing", "/products/inventory", "..."]
}
```

## Route Action Tree: `monkey-test-reports/{route_slug}.json`

Each subagent produces a DFS action tree documenting every clickable element and its outcome. This is the "maze map".

```json
{
  "route": "/products/inventory",
  "tested_at": "ISO-8601",
  "status": "pass|partial|fail",
  "page_info": {
    "title": "Page Title",
    "has_table": true,
    "row_count": 5,
    "column_headers": ["Name", "Status", "..."]
  },
  "action_tree": {
    "toolbar": [
      {
        "label": "Create",
        "type": "button",
        "state": "enabled|disabled",
        "action_result": "dialog_opened|dropdown_opened|page_navigated|no_response|error",
        "screenshot": "02-toolbar-create.png",
        "children": [
          {
            "label": "Step 1 - Basic Info",
            "type": "wizard_step",
            "screenshot": "02-toolbar-create-step1.png",
            "children": []
          }
        ]
      }
    ],
    "row_actions": [
      {
        "label": "Edit",
        "type": "dropdown_item",
        "state": "enabled",
        "action_result": "dialog_opened",
        "screenshot": "03-row-action-edit.png",
        "children": []
      },
      {
        "label": "Delete",
        "type": "dropdown_item",
        "state": "disabled",
        "action_result": "not_clickable",
        "screenshot": "03-row-action-delete-disabled.png",
        "note": "Button was disabled, could not click",
        "children": []
      }
    ],
    "detail_header_actions": [],
    "detail_tabs": []
  },
  "bugs": [],
  "console_errors": []
}
```

## State Operations

### Initialize

After route discovery and user route selection, create the global state:

```
1. Read ROUTE_MAP.md
2. Apply user's route selection (full / selected categories / specific routes)
3. Create .monkey-test-state.json with ONLY selected routes in "pending"
4. Set meta.total_routes = count of selected routes
5. Set meta.tested = 0, meta.pending = total, meta.failed = 0
6. Set meta.review_pending = 0, meta.review_complete = 0
7. Create monkey-test-screenshots/ directory
8. Create monkey-test-reports/ directory
```

If resuming an existing session, do NOT reinitialize — use the Resume operation instead.

### Resume

When continuing a previous session:

```
1. Read .monkey-test-state.json
2. Count pending routes (testing) and review_pending routes (review)
3. If pending > 0: continue testing (select batch from pending)
4. If pending == 0 and review_pending > 0: continue reviewing
5. If pending == 0 and review_pending == 0: generate final report
6. Dispatch subagents for selected routes
7. On completion: update state accordingly
```

### Update After Review

When a review subagent completes:

```
1. Find the route in the completed array
2. Set review_status to "review_complete"
3. Set bug_report_file to the path of the written bug report
4. Update meta.review_pending and meta.review_complete counters
5. Update meta.last_updated
```

### Route Slug Convention

Convert route path to filesystem-safe slug:

```
/settings/general          → settings_general
/products/inventory       → products_inventory
/users/roles    → users_roles
/users/permissions → users_permissions
```

Rule: Replace leading `/` → nothing, remaining `/` → `_`, keep `-` as-is.

## Cross-Session Guarantees

- State file is the **single source of truth**
- Always read before writing (no blind overwrites)
- Always write atomically (build full JSON, then write)
- Never move a route to "completed" without a report file
- If a subagent crashes, route stays in "pending" (safe retry)

## Checklist

- [ ] Global state file created/loaded
- [ ] Output directories exist (screenshots + reports)
- [ ] Route slugs are filesystem-safe
- [ ] State updated after each testing batch completion
- [ ] Routes set to `review_status: "review_pending"` when moved to completed
- [ ] State updated after each review batch completion (`review_status: "review_complete"`)
- [ ] Failed routes tracked with error info for retry
- [ ] Review counters consistent: `review_pending + review_complete == completed.length`
