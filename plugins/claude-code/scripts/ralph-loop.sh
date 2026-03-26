#!/usr/bin/env bash
# ralph-loop.sh — Claude Code Stop hook for agent-test Ralph Loop
#
# Drives autonomous UI testing by intercepting Claude's idle state,
# reading .monkey-test-state.json (never agent output), and injecting
# continuation prompts to keep the testing pipeline running.
#
# Input (stdin): JSON with session_id, stop_hook_active, last_assistant_message,
#                transcript_path, cwd
# Output (stdout): JSON with {decision, reason} — "block" to continue, or silent exit 0 to stop
#
# Exit codes:
#   0 — always (hook protocol requires exit 0)

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
readonly LOOP_STATE_FILE=".monkey-test-loop-state.json"
readonly TEST_STATE_FILE=".monkey-test-state.json"
readonly FINAL_REPORT_PATH="monkey-test-reports/FINAL-REPORT.md"
readonly DEFAULT_MAX_ITERATIONS_PER_SESSION=10
readonly DEFAULT_MAX_TOTAL_ITERATIONS=100
readonly DEFAULT_STALL_LIMIT=3

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() {
    echo "[ralph-loop] $*" >&2
}

die_silent() {
    # Exit cleanly — let the agent stop without blocking
    exit 0
}

require_jq() {
    if ! command -v jq &>/dev/null; then
        log "WARNING: jq is not installed. Cannot drive Ralph Loop without jq. Allowing agent to stop."
        die_silent
    fi
}

# Read a JSON field from stdin data (already captured to a variable)
json_field() {
    local json="$1"
    local field="$2"
    echo "$json" | jq -r "$field // empty" 2>/dev/null
}

json_field_num() {
    local json="$1"
    local field="$2"
    local val
    val=$(echo "$json" | jq -r "$field // 0" 2>/dev/null)
    # Ensure numeric — default to 0 if jq returns empty or non-numeric
    if [[ "$val" =~ ^[0-9]+$ ]]; then
        echo "$val"
    else
        echo "0"
    fi
}

now_iso() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Portable SHA-256 hash — works on macOS, Linux, and minimal containers
portable_hash() {
    if command -v sha256sum &>/dev/null; then
        sha256sum | cut -d' ' -f1
    elif command -v shasum &>/dev/null; then
        shasum -a 256 | cut -d' ' -f1
    elif command -v openssl &>/dev/null; then
        openssl dgst -sha256 | awk '{print $NF}'
    else
        # Last resort — use md5 as fallback (less secure but functional for fingerprinting)
        md5sum 2>/dev/null | cut -d' ' -f1 || md5 2>/dev/null | awk '{print $NF}' || echo "no-hash-available"
    fi
}

# Compute a hash of the meta section for stall detection
state_fingerprint() {
    local state_json="$1"
    echo "$state_json" | jq -cS '.' 2>/dev/null | portable_hash
}

# Output the block decision JSON to stdout and exit
block_with() {
    local reason="$1"
    jq -n --arg reason "$reason" '{"decision": "block", "reason": $reason}'
    exit 0
}

# ---------------------------------------------------------------------------
# Find the state file by searching cwd and parent directories
# ---------------------------------------------------------------------------
find_state_file() {
    local search_dir="$1"
    local current="$search_dir"

    while [[ "$current" != "/" ]]; do
        if [[ -f "$current/$TEST_STATE_FILE" ]]; then
            echo "$current"
            return 0
        fi
        current=$(dirname "$current")
    done

    # Check root as last resort
    if [[ -f "/$TEST_STATE_FILE" ]]; then
        echo "/"
        return 0
    fi

    return 1
}

# ---------------------------------------------------------------------------
# Loop state management
# ---------------------------------------------------------------------------
read_loop_state() {
    local loop_state_path="$1"
    if [[ -f "$loop_state_path" ]]; then
        cat "$loop_state_path"
    else
        echo '{}'
    fi
}

init_loop_state() {
    local session_id="$1"
    local max_per_session="${MONKEY_TEST_MAX_ITERATIONS_PER_SESSION:-$DEFAULT_MAX_ITERATIONS_PER_SESSION}"
    local max_total="${MONKEY_TEST_MAX_TOTAL_ITERATIONS:-$DEFAULT_MAX_TOTAL_ITERATIONS}"

    jq -n \
        --arg sid "$session_id" \
        --argjson mps "$max_per_session" \
        --argjson mt "$max_total" \
        --arg now "$(now_iso)" \
        '{
            session_id: $sid,
            iteration: 0,
            max_iterations_per_session: $mps,
            total_iterations: 0,
            max_total_iterations: $mt,
            started_at: $now,
            last_continued_at: $now,
            last_state_fingerprint: "",
            stall_count: 0
        }'
}

update_loop_state() {
    local loop_state="$1"
    local session_id="$2"
    local fingerprint="$3"
    local max_per_session="${MONKEY_TEST_MAX_ITERATIONS_PER_SESSION:-$DEFAULT_MAX_ITERATIONS_PER_SESSION}"
    local max_total="${MONKEY_TEST_MAX_TOTAL_ITERATIONS:-$DEFAULT_MAX_TOTAL_ITERATIONS}"

    local current_sid
    current_sid=$(json_field "$loop_state" '.session_id')

    local iteration
    local total_iterations
    local stall_count
    local last_fingerprint
    local started_at

    total_iterations=$(json_field_num "$loop_state" '.total_iterations')
    last_fingerprint=$(json_field "$loop_state" '.last_state_fingerprint')
    started_at=$(json_field "$loop_state" '.started_at')

    # If this is a new session, reset per-session counter
    if [[ "$current_sid" != "$session_id" ]]; then
        iteration=0
        started_at=$(now_iso)
    else
        iteration=$(json_field_num "$loop_state" '.iteration')
    fi

    # Increment counters
    iteration=$((iteration + 1))
    total_iterations=$((total_iterations + 1))

    # Stall detection — compare state fingerprints
    if [[ -n "$last_fingerprint" && "$fingerprint" == "$last_fingerprint" ]]; then
        stall_count=$(json_field_num "$loop_state" '.stall_count')
        stall_count=$((stall_count + 1))
    else
        stall_count=0
    fi

    jq -n \
        --arg sid "$session_id" \
        --argjson iter "$iteration" \
        --argjson mps "$max_per_session" \
        --argjson ti "$total_iterations" \
        --argjson mt "$max_total" \
        --arg started "$started_at" \
        --arg now "$(now_iso)" \
        --arg fp "$fingerprint" \
        --argjson sc "$stall_count" \
        '{
            session_id: $sid,
            iteration: $iter,
            max_iterations_per_session: $mps,
            total_iterations: $ti,
            max_total_iterations: $mt,
            started_at: $started,
            last_continued_at: $now,
            last_state_fingerprint: $fp,
            stall_count: $sc
        }'
}

# ---------------------------------------------------------------------------
# Phase detection
# ---------------------------------------------------------------------------
detect_phase() {
    local state_json="$1"
    local project_root="$2"

    # Check for blocked status first
    local status
    status=$(json_field "$state_json" '.meta.status')
    if [[ "$status" == "blocked" ]]; then
        echo "BLOCKED"
        return
    fi

    local pending
    local review_pending

    pending=$(json_field_num "$state_json" '.meta.pending')
    review_pending=$(json_field_num "$state_json" '.meta.review_pending')

    if [[ "$pending" -gt 0 ]]; then
        echo "TESTING"
    elif [[ "$review_pending" -gt 0 ]]; then
        echo "REVIEW"
    elif [[ ! -f "$project_root/$FINAL_REPORT_PATH" ]]; then
        echo "FINAL_REPORT"
    else
        echo "DONE"
    fi
}

# ---------------------------------------------------------------------------
# Build continuation prompts
# ---------------------------------------------------------------------------
build_continuation_prompt() {
    local phase="$1"
    local state_json="$2"
    local iteration="$3"
    local max_per_session="$4"
    local total_iterations="$5"
    local max_total="$6"

    local total_routes pending tested failed review_pending review_complete
    total_routes=$(json_field_num "$state_json" '.meta.total_routes')
    pending=$(json_field_num "$state_json" '.meta.pending')
    tested=$(json_field_num "$state_json" '.meta.tested')
    failed=$(json_field_num "$state_json" '.meta.failed')
    review_pending=$(json_field_num "$state_json" '.meta.review_pending')
    review_complete=$(json_field_num "$state_json" '.meta.review_complete')

    local header="## Agent Test -- Continue (Iteration ${iteration}/${max_per_session}, Total ${total_iterations}/${max_total})"
    local stats="Progress: ${tested} tested, ${failed} failed, ${pending} pending, ${review_pending} review pending, ${review_complete} review complete (of ${total_routes} total)"

    case "$phase" in
        TESTING)
            cat <<PROMPT
${header}

${stats}

Read \`.monkey-test-state.json\`. ${pending} routes remain to test. Pick the next batch of pending routes and dispatch fresh subagents (one new Task per route, no task_id reuse). Collect results, write reports, update state file.
PROMPT
            ;;
        REVIEW)
            cat <<PROMPT
${header}

${stats}

Read \`.monkey-test-state.json\`. All testing complete. ${review_pending} routes need bug report review. Pick the next batch of review_pending routes and dispatch fresh review subagents (one new Task per route, no task_id reuse). Collect reports, update state file.
PROMPT
            ;;
        FINAL_REPORT)
            cat <<PROMPT
${header}

${stats}

All testing and reviews are complete. Generate FINAL-REPORT.md from all bug reports in monkey-test-reports/. Read every *-bugs.md file, aggregate statistics by severity, and write the consolidated report to monkey-test-reports/FINAL-REPORT.md.
PROMPT
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    require_jq

    # 1. Read JSON from stdin
    local stdin_json
    stdin_json=$(cat)

    if [[ -z "$stdin_json" ]]; then
        log "No input received on stdin. Allowing agent to stop."
        die_silent
    fi

    # 2. Parse input fields
    local session_id stop_hook_active cwd
    session_id=$(json_field "$stdin_json" '.session_id')
    stop_hook_active=$(json_field "$stdin_json" '.stop_hook_active')
    cwd=$(json_field "$stdin_json" '.cwd')

    # Default cwd to current directory if not provided
    if [[ -z "$cwd" ]]; then
        cwd="$(pwd)"
    fi

    # 3. Find the agent-test state file
    local project_root
    if ! project_root=$(find_state_file "$cwd"); then
        # No state file found — this is not an agent-test session
        die_silent
    fi

    local test_state_path="$project_root/$TEST_STATE_FILE"
    local loop_state_path="$project_root/$LOOP_STATE_FILE"

    # 4. Read the test state file
    local state_json
    if [[ ! -f "$test_state_path" ]]; then
        die_silent
    fi
    state_json=$(cat "$test_state_path")

    if [[ -z "$state_json" ]] || ! echo "$state_json" | jq empty 2>/dev/null; then
        log "WARNING: State file is empty or invalid JSON. Allowing agent to stop."
        die_silent
    fi

    # 5. Detect phase
    local phase
    phase=$(detect_phase "$state_json" "$project_root")

    if [[ "$phase" == "BLOCKED" ]]; then
        local blocked_reason
        blocked_reason=$(json_field "$state_json" '.meta.blocked_reason')
        log "BLOCKED: ${blocked_reason:-unknown reason}. Allowing agent to stop."
        die_silent
    fi

    if [[ "$phase" == "DONE" ]]; then
        log "All phases complete. FINAL-REPORT.md exists. Allowing agent to stop."
        die_silent
    fi

    # 6. Read/initialize loop state
    local loop_state
    loop_state=$(read_loop_state "$loop_state_path")

    if [[ -z "$session_id" ]]; then
        session_id="unknown-$(date +%s)"
    fi

    # Initialize loop state if empty
    if [[ "$loop_state" == "{}" ]] || [[ -z "$(json_field "$loop_state" '.session_id')" ]]; then
        loop_state=$(init_loop_state "$session_id")
    fi

    # 7. Compute state fingerprint for stall detection
    local fingerprint
    fingerprint=$(state_fingerprint "$state_json")

    # 8. Update loop state (increments counters, detects stalls)
    local updated_loop_state
    updated_loop_state=$(update_loop_state "$loop_state" "$session_id" "$fingerprint")

    # Extract updated values
    local iteration total_iterations max_per_session max_total stall_count
    iteration=$(json_field_num "$updated_loop_state" '.iteration')
    total_iterations=$(json_field_num "$updated_loop_state" '.total_iterations')
    max_per_session=$(json_field_num "$updated_loop_state" '.max_iterations_per_session')
    max_total=$(json_field_num "$updated_loop_state" '.max_total_iterations')
    stall_count=$(json_field_num "$updated_loop_state" '.stall_count')

    # 9. Safety check: total iteration limit
    if [[ "$total_iterations" -gt "$max_total" ]]; then
        log "SAFETY: Total iteration limit reached (${total_iterations}/${max_total}). Allowing agent to stop."
        # Write state so the limit is recorded
        echo "$updated_loop_state" > "$loop_state_path"
        die_silent
    fi

    # 10. Safety check: per-session iteration limit
    #     When stop_hook_active is true, we are already in a continuation chain.
    #     If we've hit the per-session limit, let this session end.
    if [[ "$iteration" -gt "$max_per_session" ]]; then
        log "Session iteration limit reached (${iteration}/${max_per_session}). Start a new session to continue."
        log "Progress: $(json_field_num "$state_json" '.meta.tested') tested, $(json_field_num "$state_json" '.meta.pending') pending, $(json_field_num "$state_json" '.meta.review_pending') review pending."
        # Reset session iteration for next session
        updated_loop_state=$(echo "$updated_loop_state" | jq '.iteration = 0')
        echo "$updated_loop_state" > "$loop_state_path"
        die_silent
    fi

    # 11. Safety check: stall detection
    if [[ "$stall_count" -ge "$DEFAULT_STALL_LIMIT" ]]; then
        log "WARNING: State file unchanged for ${stall_count} consecutive iterations. Possible stall."
        log "Allowing agent to stop. Investigate .monkey-test-state.json manually."
        echo "$updated_loop_state" > "$loop_state_path"
        die_silent
    fi

    # 12. Persist updated loop state
    echo "$updated_loop_state" > "$loop_state_path"

    # 13. Build continuation prompt and block
    local prompt
    prompt=$(build_continuation_prompt "$phase" "$state_json" "$iteration" "$max_per_session" "$total_iterations" "$max_total")

    log "Phase: ${phase} | Iteration: ${iteration}/${max_per_session} | Total: ${total_iterations}/${max_total} | Stalls: ${stall_count}"

    block_with "$prompt"
}

main "$@"
