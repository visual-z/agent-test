# Bug Report Format Reference

## Per-Route Bug Report: `monkey-test-reports/{route_slug}-bugs.md`

Each review subagent produces one Markdown bug report per sub-route.

## Structure

```markdown
# Bug Report: {route}

**Route:** `{route_path}`
**Tested at:** {ISO-8601 from test report}
**Test Status:** {pass|partial|fail}
**Reviewed at:** {ISO-8601 of review}

## Summary
{2-3 sentences: route health, bug count, severity breakdown}

## Page Overview
- **Title:** {page title}
- **Has Table:** {yes/no} ({row_count} rows, {column_count} columns)
- **Tabs:** {comma-separated tab names}
- **Console Errors:** {count} errors

## Bugs Found

### Critical
#### BUG-{ROUTE_SLUG}-C{N}: {Short title}
- **Severity:** Critical
- **Location:** {Phase and element}
- **Screenshot:** `{filename}`
- **Description:** {What went wrong}
- **Expected:** {Expected behavior}
- **Actual:** {Actual behavior}
- **Source:** {tester-reported | reviewer-found}

### Major
{Same format per bug, or "None"}

### Minor
{Same format per bug, or "None"}

## Console Errors
{List all console errors with context}

## Action Coverage Summary
| Area | Elements Found | Tested | Errors | Disabled |
|------|---------------|--------|--------|----------|
| Toolbar | n | n | n | n |
| Row Actions | n | n | n | n |
| Detail Header | n | n | n | n |
| Detail Tabs | n | n | n | n |
| **Total** | **n** | **n** | **n** | **n** |

## Notes
{Additional observations, patterns, UX suggestions}
```

## Bug ID Convention

Format: `BUG-{ROUTE_SLUG}-{SEVERITY_LETTER}{NUMBER}`

| Component | Rule |
|-----------|------|
| `ROUTE_SLUG` | Same slug used for screenshot directories (e.g., `settings_general`) |
| Severity letter | `C` = critical, `M` = major, `m` = minor |
| Number | Sequential within severity level, starting from 1 |

Examples: `BUG-settings_general-C1`, `BUG-products_inventory-M2`, `BUG-users_roles-m1`

## Severity Criteria

| Level | Criteria | Examples |
|-------|----------|---------|
| `critical` | Feature completely broken, data loss, unrecoverable state, security issue | Page crash, blank screen, session expired mid-test, infinite loop, data corruption |
| `major` | Feature partially broken, important functionality impaired | Button does nothing when it should, dialog opens empty, error toast on valid action, wrong data displayed, table not rendering |
| `minor` | Cosmetic issue, non-blocking UX problem, environmental noise | Layout slightly misaligned, tooltip missing, console warning (not error), disabled element with no visible reason, minor text truncation |

## Bug Source Field

| Value | Meaning |
|-------|---------|
| `tester-reported` | Bug was already in the testing subagent's `bugs` array |
| `reviewer-found` | Bug was discovered by the review subagent during screenshot analysis (tester missed it) |

## Final Summary Report: `monkey-test-reports/FINAL-REPORT.md`

The orchestrator (not the review subagent) generates this after ALL per-route reviews complete.

```markdown
# Agent Test — Final Bug Report

**Project:** {project name}
**Base URL:** {base_url}
**Test Date:** {date range}
**Total Routes Tested:** {N}

## Executive Summary
{3-5 sentences: overall quality, critical issues, most affected areas}

## Bug Statistics

| Severity | Count |
|----------|-------|
| Critical | {n} |
| Major | {n} |
| Minor | {n} |
| **Total** | **{n}** |

## Route Health Overview

| Route | Status | Critical | Major | Minor | Total Bugs |
|-------|--------|----------|-------|-------|------------|
| /settings/general | pass | 0 | 0 | 0 | 0 |
| /products/inventory | partial | 1 | 2 | 1 | 4 |
| ... | ... | ... | ... | ... | ... |

## Critical Bugs (All Routes)

{Consolidated list of ALL critical bugs across all routes, with route context}

### BUG-{slug}-C{N}: {title}
- **Route:** `{route}`
- **Location:** {phase and element}
- **Screenshot:** `{screenshots_dir}/{filename}`
- **Description:** {description}

## Major Bugs (All Routes)

{Same format, consolidated}

## Routes Without Issues
{List of routes that passed with no bugs — these are healthy}

## Recommendations
{Priority-ordered list of what to fix first}
```

## Output Directory Structure

After the review phase completes:

```
monkey-test-reports/
├── settings_general.json              # Test report (from testing phase)
├── settings_general-bugs.md           # Bug report (from review phase)
├── products_inventory.json
├── products_inventory-bugs.md
├── ...
└── FINAL-REPORT.md                 # Consolidated summary (from orchestrator)
```

## Correlation Rules

1. Every route in `.monkey-test-state.json` with `review_status: "review_complete"` MUST have a corresponding `{route_slug}-bugs.md` file
2. Every bug in a per-route bug report MUST reference a screenshot that exists in the route's screenshot directory
3. The FINAL-REPORT.md bug counts MUST match the sum of bugs across all per-route reports
4. Bug IDs MUST be globally unique (the route slug prefix guarantees this)
