# State Schema Reference

## Global State: `.monkey-test-state.json`

Lives at project root. Single source of truth for test progress.

## Schema

```json
{
  "meta": {
    "project": "string — project name or identifier",
    "base_url": "string — application URL (e.g., http://localhost:3000)",
    "created_at": "string — ISO-8601 timestamp of state creation",
    "last_updated": "string — ISO-8601 timestamp of last state write",
    "total_routes": "number — total testable routes from ROUTE_MAP.md",
    "tested": "number — count of completed routes",
    "pending": "number — count of pending routes",
    "failed": "number — count of failed routes",
    "review_pending": "number — count of routes awaiting review",
    "review_complete": "number — count of routes with review done",
    "review_failed": "number — count of routes where review failed"
  },

  "completed": [
    {
      "route": "string — route path (e.g., /settings/general)",
      "tested_at": "string — ISO-8601 timestamp",
      "status": "pass|partial|fail",
      "bugs_count": "number — count of bugs found",
      "operations_count": {
        "total": "number",
        "passed": "number",
        "failed": "number",
        "disabled": "number"
      },
      "screenshots_dir": "string — relative path to screenshots directory",
      "report_file": "string — relative path to report JSON",
      "summary": "string — brief human-readable summary",
      "review_status": "review_pending|review_complete|review_failed",
      "bug_report_file": "string|null — relative path to bug report Markdown (null until review completes)"
    }
  ],

  "failed": [
    {
      "route": "string — route path",
      "failed_at": "string — ISO-8601 timestamp",
      "error": "string — reason for failure",
      "retry_count": "number — how many times this route has been retried",
      "last_error": "string — most recent error message"
    }
  ],

  "pending": [
    "string — route paths (e.g., /settings/billing)"
  ]
}
```

## Invariants

1. **Every route appears in exactly one array** — a route is in `completed`, `failed`, OR `pending`, never in multiple.
2. **Counters match arrays** — `meta.tested == completed.length`, `meta.pending == pending.length`, `meta.failed == failed.length`.
3. **Total is constant** — `meta.total_routes == completed.length + failed.length + pending.length`.
4. **No completed without report** — every entry in `completed` MUST have a corresponding report file at the path in `report_file`.
5. **Timestamp ordering** — `meta.last_updated >= max(all tested_at/failed_at timestamps)`.
6. **Review counters match** — `meta.review_pending + meta.review_complete + meta.review_failed == completed.length`. Every completed route has a `review_status`.
7. **No review_complete without bug report** — every completed entry with `review_status: "review_complete"` MUST have a `bug_report_file` that exists.
8. **Initial review_status** — when a route moves from pending to completed, its `review_status` is set to `"review_pending"` and `bug_report_file` is `null`.

## State Operations

### Initialize

```
Input: ROUTE_MAP.md + user's route selection (full / categories / specific routes)
Output: .monkey-test-state.json

1. Parse all testable routes from ROUTE_MAP.md
2. Filter to ONLY the routes the user selected (see SKILL.md Phase 1 Route Selection)
3. Create state with selected routes in "pending"
4. Set meta.total_routes = count of selected routes
5. Set meta.tested = 0, meta.pending = total, meta.failed = 0
6. Set meta.review_pending = 0, meta.review_complete = 0, meta.review_failed = 0
7. Set meta.created_at and meta.last_updated to now
```

### Update After Batch

```
Input: batch results (list of {route, report_json, success boolean})

For each result:
  If success:
    1. Remove route from pending
    2. Add to completed with summary from report
    3. Set review_status to "review_pending", bug_report_file to null
    4. Increment meta.tested, decrement meta.pending
    5. Increment meta.review_pending
  If failure:
    1. Remove route from pending
    2. Add to failed with error info
    3. Increment meta.failed, decrement meta.pending

Update meta.last_updated to now
Write entire state atomically (build full JSON, then write)
```

### Update After Review Batch

```
Input: review results (list of {route, bug_report_markdown, success boolean})

For each result:
  If success:
    1. Find route in completed array
    2. Set review_status to "review_complete"
    3. Set bug_report_file to "monkey-test-reports/{route_slug}-bugs.md"
    4. Decrement meta.review_pending, increment meta.review_complete
  If failure:
    1. Find route in completed array
    2. Set review_status to "review_failed"
    3. Decrement meta.review_pending, increment meta.review_failed

Update meta.last_updated to now
Write entire state atomically
```

### Resume

```
Input: existing .monkey-test-state.json

1. Read state file
2. Validate invariants (counters match arrays)
3. Return pending array for next batch selection
```

### Retry Failed Routes

```
Input: explicit user request to retry

1. Move all failed routes back to pending
2. Increment retry_count on each (keep in a retry tracker)
3. Update counters
```

## Route Slug Convention

Convert route path to filesystem-safe slug for directories and filenames:

| Route | Slug |
|-------|------|
| `/settings/general` | `settings_general` |
| `/products/inventory` | `products_inventory` |
| `/users/roles` | `users_roles` |
| `/users/permissions` | `users_permissions` |

**Rule:** Remove leading `/`. Replace remaining `/` with `_`. Keep `-` as-is.

## Concurrency Safety

- **Always read before writing** — never blind-overwrite the state file
- **Build full JSON then write** — no incremental file edits
- **One writer at a time** — the orchestrator is the only process that writes to this file
- **Subagents never touch state** — they return reports; the orchestrator updates state
- **Crash safety** — if the orchestrator crashes mid-batch, unfinished routes stay in "pending" and are retried on the next session
