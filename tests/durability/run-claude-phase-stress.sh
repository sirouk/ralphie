#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RALPHIE_SOURCE="$ROOT_DIR/ralphie.sh"
MOCK_CLAUDE_SOURCE="$ROOT_DIR/tests/durability/mock-claude-control.sh"
ARTIFACTS_BASE="$ROOT_DIR/tests/durability/artifacts"
RALPHIE_SOURCE_SHA256=""
REPO_GIT_AVAILABLE=false
REPO_TRACKED_STATUS_BASELINE=""

RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
RUN_DIR="$ARTIFACTS_BASE/claude-phase-stress-$RUN_ID"

SCENARIOS="full,retry,resume"
DISCORD_WEBHOOK_URL=""
KEEP_WORKSPACES="false"
PER_SCENARIO_TIMEOUT_SECONDS=120
EXERCISE_TTS_FALLBACK="false"

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0
FAILED_SCENARIOS=()

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fail() { printf '[FAIL] %s\n' "$*" >&2; }
pass() { printf '[PASS] %s\n' "$*"; }

file_sha256() {
    local target="$1"
    shasum -a 256 "$target" | awk '{print $1}'
}

capture_repo_tracked_status_baseline() {
    if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        REPO_GIT_AVAILABLE=true
        REPO_TRACKED_STATUS_BASELINE="$(git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=no --ignore-submodules=all || true)"
    else
        REPO_GIT_AVAILABLE=false
        REPO_TRACKED_STATUS_BASELINE=""
    fi
}

assert_repo_tracked_status_unchanged() {
    local current_status=""
    [ "$REPO_GIT_AVAILABLE" = true ] || return 0
    current_status="$(git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=no --ignore-submodules=all || true)"
    [ "$current_status" = "$REPO_TRACKED_STATUS_BASELINE" ]
}

capture_source_integrity() {
    RALPHIE_SOURCE_SHA256="$(file_sha256 "$RALPHIE_SOURCE")"
}

assert_source_integrity() {
    local current_hash
    current_hash="$(file_sha256 "$RALPHIE_SOURCE")"
    [ "$current_hash" = "$RALPHIE_SOURCE_SHA256" ]
}

json_escape() {
    local s="${1:-}"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    printf '%s' "$s"
}

send_discord() {
    local message="$1"
    [ -n "$DISCORD_WEBHOOK_URL" ] || return 0
    local escaped
    escaped="$(json_escape "$message")"
    curl -sS -X POST "$DISCORD_WEBHOOK_URL" \
        -H 'Content-Type: application/json' \
        -d "{\"content\":\"$escaped\"}" >/dev/null || true
}

print_usage() {
    cat <<'EOF_USAGE'
Usage: tests/durability/run-claude-phase-stress.sh [options]

Options:
  --scenarios LIST              Comma-separated: full,retry,resume (default: all)
  --discord-webhook-url URL     Optional Discord webhook for high-signal run notifications
  --timeout-seconds N           Per-scenario timeout (default: 120)
  --exercise-tts-fallback       Enable Ralphie TTS path but force fail-fast TTS generation; verifies Discord text fallback
  --keep-workspaces             Keep per-scenario temp workspaces for forensic debugging
  --help                        Show this help
EOF_USAGE
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --scenarios)
                SCENARIOS="${2:-}"
                shift 2
                ;;
            --discord-webhook-url)
                DISCORD_WEBHOOK_URL="${2:-}"
                shift 2
                ;;
            --timeout-seconds)
                PER_SCENARIO_TIMEOUT_SECONDS="${2:-120}"
                shift 2
                ;;
            --exercise-tts-fallback)
                EXERCISE_TTS_FALLBACK="true"
                shift
                ;;
            --keep-workspaces)
                KEEP_WORKSPACES="true"
                shift
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            *)
                fail "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

is_number() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

get_timeout_cmd() {
    if command -v timeout >/dev/null 2>&1; then
        echo "timeout"
        return 0
    fi
    if command -v gtimeout >/dev/null 2>&1; then
        echo "gtimeout"
        return 0
    fi
    echo ""
}

scenario_in_list() {
    local scenario="$1"
    case ",$SCENARIOS," in
        *",$scenario,"*) return 0 ;;
        *) return 1 ;;
    esac
}

prepare_workspace() {
    local scenario="$1"
    local ws="$RUN_DIR/workspaces/$scenario"

    mkdir -p "$ws/.ralphie" "$ws/tests/durability"
    cp "$RALPHIE_SOURCE" "$ws/ralphie.sh"
    cp "$MOCK_CLAUDE_SOURCE" "$ws/tests/durability/mock-claude-control.sh"
    chmod +x "$ws/ralphie.sh" "$ws/tests/durability/mock-claude-control.sh"

    cat > "$ws/.ralphie/project-bootstrap.md" <<'EOF_BOOT'
# Ralphie Project Bootstrap
project_type: existing
build_consent: true
objective: controlled all-phase orchestration stress test with mock claude
constraints: fail fast and deterministic
success_criteria: all phases complete with CURRENT_PHASE=done
interactive_prompted: false
EOF_BOOT

    local notif_enabled="false"
    local notif_discord_enabled="false"
    local notif_tts_enabled="false"
    local chutes_api_key=""
    local chutes_tts_url=""
    local tts_style="ralph_wiggum"
    if [ -n "$DISCORD_WEBHOOK_URL" ]; then
        notif_enabled="true"
        notif_discord_enabled="true"
    fi
    if [ "$EXERCISE_TTS_FALLBACK" = "true" ]; then
        notif_tts_enabled="true"
        # Force fail-fast local connection refusal to exercise text-only fallback path.
        chutes_api_key="mock_tts_fail_fast"
        chutes_tts_url="http://127.0.0.1:9/speak"
    fi

    cat > "$ws/.ralphie/config.env" <<EOF_CFG
RALPHIE_AUTO_UPDATE=false
RALPHIE_ENGINE=claude
RALPHIE_AUTO_ENGINE_PREFERENCE=claude
CLAUDE_ENGINE_CMD=./tests/durability/mock-claude-control.sh
CODEX_ENGINE_CMD=__missing_codex__
RALPHIE_STARTUP_OPERATIONAL_PROBE=false
RALPHIE_AUTO_INIT_GIT_IF_MISSING=true
RALPHIE_AUTO_COMMIT_ON_PHASE_PASS=false
RALPHIE_ENGINE_OVERRIDES_BOOTSTRAPPED=true
RALPHIE_NOTIFICATION_WIZARD_BOOTSTRAPPED=true
RALPHIE_NOTIFICATIONS_ENABLED=${notif_enabled}
RALPHIE_NOTIFY_DISCORD_ENABLED=${notif_discord_enabled}
RALPHIE_NOTIFY_DISCORD_WEBHOOK_URL=${DISCORD_WEBHOOK_URL}
RALPHIE_NOTIFY_TELEGRAM_ENABLED=false
RALPHIE_NOTIFY_TTS_ENABLED=${notif_tts_enabled}
RALPHIE_NOTIFY_TTS_STYLE=${tts_style}
CHUTES_API_KEY=${chutes_api_key}
RALPHIE_NOTIFY_CHUTES_TTS_URL=${chutes_tts_url}
RALPHIE_PHASE_COMPLETION_MAX_ATTEMPTS=2
RALPHIE_PHASE_COMPLETION_RETRY_DELAY_SECONDS=1
RALPHIE_RUN_AGENT_MAX_ATTEMPTS=1
RALPHIE_RUN_AGENT_RETRY_DELAY_SECONDS=1
RALPHIE_MAX_CONSENSUS_ROUTING_ATTEMPTS=1
RALPHIE_CONSENSUS_SCORE_THRESHOLD=70
RALPHIE_PHASE_NOOP_PROFILE=custom
RALPHIE_PHASE_NOOP_POLICY_PLAN=soft
RALPHIE_PHASE_NOOP_POLICY_BUILD=soft
RALPHIE_PHASE_NOOP_POLICY_TEST=soft
RALPHIE_PHASE_NOOP_POLICY_REFACTOR=soft
RALPHIE_PHASE_NOOP_POLICY_LINT=soft
RALPHIE_PHASE_NOOP_POLICY_DOCUMENT=soft
RALPHIE_STRICT_VALIDATION_NOOP=false
RALPHIE_ENGINE_OUTPUT_TO_STDOUT=false
EOF_CFG

    printf '%s' "$ws"
}

assert_scenario_success() {
    local ws="$1"
    local stdout_file="$2"

    grep -q 'All phases completed. Session done.' "$stdout_file"
    grep -q 'CURRENT_PHASE="done"' "$ws/.ralphie/state.env"

    local phase
    for phase in plan build test refactor lint document; do
        ls "$ws/completion_log/${phase}_"*.out >/dev/null 2>&1
        ls "$ws/logs/${phase}_"*.log >/dev/null 2>&1
    done

    local handoff_count
    handoff_count="$(find "$ws/completion_log" -type f -name '*handoff.status' | wc -l | tr -d ' ')"
    if ! is_number "$handoff_count" || [ "$handoff_count" -lt 6 ]; then
        return 1
    fi

    local consensus_count
    consensus_count="$(find "$ws/consensus" -type f -name 'reviewer_*.out' | wc -l | tr -d ' ')"
    if ! is_number "$consensus_count" || [ "$consensus_count" -lt 6 ]; then
        return 1
    fi

    if [ -n "$DISCORD_WEBHOOK_URL" ]; then
        [ -f "$ws/.ralphie/notifications.log" ] || return 1
        grep -q 'event=phase_complete' "$ws/.ralphie/notifications.log"
        grep -q 'delivery=delivered' "$ws/.ralphie/notifications.log"
    fi
}

run_with_timeout() {
    local timeout_cmd="$1"
    local timeout_seconds="$2"
    shift 2

    if [ -n "$timeout_cmd" ]; then
        "$timeout_cmd" "$timeout_seconds" "$@"
    else
        "$@"
    fi
}

run_scenario_full() {
    local ws="$1"
    local timeout_cmd="$2"
    local stdout_file="$3"
    local stderr_file="$4"

    (
        cd "$ws"
        MOCK_CLAUDE_STATE_DIR="$ws/.mock-claude" \
        run_with_timeout "$timeout_cmd" "$PER_SCENARIO_TIMEOUT_SECONDS" ./ralphie.sh --no-resume
    ) >"$stdout_file" 2>"$stderr_file"
}

run_scenario_retry() {
    local ws="$1"
    local timeout_cmd="$2"
    local stdout_file="$3"
    local stderr_file="$4"

    (
        cd "$ws"
        MOCK_CLAUDE_STATE_DIR="$ws/.mock-claude" \
        MOCK_CLAUDE_INJECT_HANDOFF_HOLD_ONCE=true \
        run_with_timeout "$timeout_cmd" "$PER_SCENARIO_TIMEOUT_SECONDS" ./ralphie.sh --no-resume
    ) >"$stdout_file" 2>"$stderr_file"

    grep -q 'retrying in' "$stdout_file" || grep -q 'retrying in' "$stderr_file"
}

run_scenario_resume() {
    local ws="$1"
    local timeout_cmd="$2"
    local stdout_file="$3"
    local stderr_file="$4"

    local first_out="$ws/first_run.out"
    local first_err="$ws/first_run.err"

    (
        cd "$ws"
        MOCK_CLAUDE_STATE_DIR="$ws/.mock-claude" \
        MOCK_CLAUDE_SLEEP_PLAN_SECONDS=15 \
        ./ralphie.sh --no-resume
    ) >"$first_out" 2>"$first_err" &

    local pid="$!"
    local state_file="$ws/.ralphie/state.env"
    local seen_inflight="false"
    local probe_count=0
    while [ "$probe_count" -lt 80 ]; do
        probe_count=$((probe_count + 1))
        if [ -f "$state_file" ] && grep -q 'PHASE_ATTEMPT_IN_PROGRESS="true"' "$state_file" 2>/dev/null; then
            seen_inflight="true"
            break
        fi
        sleep 0.25
    done

    if [ "$seen_inflight" != "true" ]; then
        kill -TERM "$pid" >/dev/null 2>&1 || true
        wait "$pid" >/dev/null 2>&1 || true
        fail "resume scenario: failed to observe in-flight phase state"
        return 1
    fi

    kill -TERM "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
    local lock_pid_file="$ws/.ralphie/run.lock"
    if [ -f "$lock_pid_file" ]; then
        local lock_pid
        lock_pid="$(head -n 1 "$lock_pid_file" 2>/dev/null || true)"
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            kill -TERM "$lock_pid" >/dev/null 2>&1 || true
            sleep 1
            kill -KILL "$lock_pid" >/dev/null 2>&1 || true
        fi
    fi

    (
        cd "$ws"
        MOCK_CLAUDE_STATE_DIR="$ws/.mock-claude" \
        run_with_timeout "$timeout_cmd" "$PER_SCENARIO_TIMEOUT_SECONDS" ./ralphie.sh --resume
    ) >"$stdout_file" 2>"$stderr_file"

    grep -q 'Resuming in-progress phase' "$stdout_file"
}

record_summary_line() {
    local scenario="$1"
    local status="$2"
    local duration_seconds="$3"
    local ws="$4"
    local detail="$5"

    printf '%s\t%s\t%s\t%s\t%s\n' "$scenario" "$status" "$duration_seconds" "$ws" "$detail" >> "$RUN_DIR/summary.tsv"
}

run_one() {
    local scenario="$1"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))

    local ws
    ws="$(prepare_workspace "$scenario")"

    local stdout_file="$RUN_DIR/${scenario}.stdout.log"
    local stderr_file="$RUN_DIR/${scenario}.stderr.log"
    local timeout_cmd
    timeout_cmd="$(get_timeout_cmd)"

    local start_ts end_ts duration
    start_ts="$(date +%s)"

    info "Scenario '$scenario' starting"
    send_discord "[ralphie-stress] scenario '$scenario' started"

    local rc=0
    case "$scenario" in
        full)
            run_scenario_full "$ws" "$timeout_cmd" "$stdout_file" "$stderr_file" || rc=$?
            ;;
        retry)
            run_scenario_retry "$ws" "$timeout_cmd" "$stdout_file" "$stderr_file" || rc=$?
            ;;
        resume)
            run_scenario_resume "$ws" "$timeout_cmd" "$stdout_file" "$stderr_file" || rc=$?
            ;;
        *)
            fail "Unknown scenario '$scenario'"
            rc=1
            ;;
    esac

    if [ "$rc" -eq 0 ]; then
        if ! assert_scenario_success "$ws" "$stdout_file"; then
            rc=1
        fi
    fi

    end_ts="$(date +%s)"
    duration=$((end_ts - start_ts))

    if [ "$rc" -eq 0 ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        pass "Scenario '$scenario' passed (${duration}s)"
        record_summary_line "$scenario" "PASS" "$duration" "$ws" "all checks passed"
        send_discord "[ralphie-stress] scenario '$scenario' passed in ${duration}s"
        if [ "$KEEP_WORKSPACES" != "true" ]; then
            rm -rf "$ws"
        fi
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_SCENARIOS+=("$scenario")
        fail "Scenario '$scenario' failed (${duration}s)"
        record_summary_line "$scenario" "FAIL" "$duration" "$ws" "see ${scenario}.stderr.log"
        send_discord "[ralphie-stress] scenario '$scenario' failed in ${duration}s"
    fi
}

write_report() {
    local report_file="$RUN_DIR/report.md"
    {
        echo "# Claude Phase Stress Report"
        echo
        echo "- run_id: $RUN_ID"
        echo "- scenarios: $SCENARIOS"
        echo "- timeout_seconds_per_scenario: $PER_SCENARIO_TIMEOUT_SECONDS"
        echo "- passed: $PASS_COUNT"
        echo "- failed: $FAIL_COUNT"
        echo
        echo "## Scenario Summary"
        echo
        echo "| scenario | status | duration_s | workspace | detail |"
        echo "| --- | --- | ---: | --- | --- |"
        if [ -f "$RUN_DIR/summary.tsv" ]; then
            while IFS=$'\t' read -r scenario status duration ws detail; do
                echo "| $scenario | $status | $duration | $ws | $detail |"
            done < "$RUN_DIR/summary.tsv"
        fi
        echo
        echo "## Logs"
        echo
        echo "- run directory: $RUN_DIR"
        echo "- stdout logs: $RUN_DIR/*.stdout.log"
        echo "- stderr logs: $RUN_DIR/*.stderr.log"
    } > "$report_file"
}

main() {
    parse_args "$@"

    if [ ! -f "$RALPHIE_SOURCE" ]; then
        fail "Missing ralphie source file: $RALPHIE_SOURCE"
        exit 1
    fi
    if [ ! -f "$MOCK_CLAUDE_SOURCE" ]; then
        fail "Missing mock claude source file: $MOCK_CLAUDE_SOURCE"
        exit 1
    fi
    if ! is_number "$PER_SCENARIO_TIMEOUT_SECONDS" || [ "$PER_SCENARIO_TIMEOUT_SECONDS" -lt 10 ]; then
        fail "Invalid --timeout-seconds value: $PER_SCENARIO_TIMEOUT_SECONDS"
        exit 1
    fi
    if [ "$EXERCISE_TTS_FALLBACK" = "true" ] && [ -z "$DISCORD_WEBHOOK_URL" ]; then
        fail "--exercise-tts-fallback requires --discord-webhook-url so text fallback delivery can be verified."
        exit 1
    fi

    mkdir -p "$RUN_DIR/workspaces"
    : > "$RUN_DIR/summary.tsv"
    capture_source_integrity
    capture_repo_tracked_status_baseline

    info "Run dir: $RUN_DIR"
    send_discord "[ralphie-stress] run '$RUN_ID' started (scenarios=$SCENARIOS)"

    if scenario_in_list "full"; then run_one "full"; fi
    if ! assert_source_integrity; then
        fail "Source ralphie.sh changed during stress run; repo isolation violated."
        FAILED_SCENARIOS+=("full:source-integrity")
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    if ! assert_repo_tracked_status_unchanged; then
        fail "Tracked repository files changed during stress run; repo isolation violated."
        FAILED_SCENARIOS+=("full:tracked-repo-integrity")
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    if scenario_in_list "retry"; then run_one "retry"; fi
    if ! assert_source_integrity; then
        fail "Source ralphie.sh changed during stress run; repo isolation violated."
        FAILED_SCENARIOS+=("retry:source-integrity")
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    if ! assert_repo_tracked_status_unchanged; then
        fail "Tracked repository files changed during stress run; repo isolation violated."
        FAILED_SCENARIOS+=("retry:tracked-repo-integrity")
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    if scenario_in_list "resume"; then run_one "resume"; fi
    if ! assert_source_integrity; then
        fail "Source ralphie.sh changed during stress run; repo isolation violated."
        FAILED_SCENARIOS+=("resume:source-integrity")
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    if ! assert_repo_tracked_status_unchanged; then
        fail "Tracked repository files changed during stress run; repo isolation violated."
        FAILED_SCENARIOS+=("resume:tracked-repo-integrity")
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    write_report

    info "Total: $TOTAL_COUNT | Passed: $PASS_COUNT | Failed: $FAIL_COUNT"
    info "Report: $RUN_DIR/report.md"

    if [ "$FAIL_COUNT" -gt 0 ]; then
        warn "Failed scenarios: ${FAILED_SCENARIOS[*]}"
        send_discord "[ralphie-stress] run '$RUN_ID' failed: ${FAILED_SCENARIOS[*]}"
        exit 1
    fi

    send_discord "[ralphie-stress] run '$RUN_ID' completed successfully"
}

main "$@"
