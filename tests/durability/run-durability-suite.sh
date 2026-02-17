#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_RALPHIE_FILE="$ROOT_DIR/ralphie.sh"
RALPHIE_FILE="$SOURCE_RALPHIE_FILE"
TARGET_SANDBOX_DIR=""
SOURCE_RALPHIE_SHA256=""
REPO_GIT_AVAILABLE=false
REPO_TRACKED_STATUS_BASELINE=""

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TOTAL_COUNT=0
FAILED_CASES=()

info() { printf '[INFO] %s\n' "$*"; }
pass() { printf '[PASS] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fail() { printf '[FAIL] %s\n' "$*" >&2; }

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

prepare_isolated_target() {
    TARGET_SANDBOX_DIR="$(mktemp -d /tmp/ralphie-durability-target.XXXXXX)"
    cp "$SOURCE_RALPHIE_FILE" "$TARGET_SANDBOX_DIR/ralphie.sh"
    chmod +x "$TARGET_SANDBOX_DIR/ralphie.sh"
    RALPHIE_FILE="$TARGET_SANDBOX_DIR/ralphie.sh"
    SOURCE_RALPHIE_SHA256="$(file_sha256 "$SOURCE_RALPHIE_FILE")"
}

cleanup_isolated_target() {
    if [ -n "${TARGET_SANDBOX_DIR:-}" ] && [ -d "$TARGET_SANDBOX_DIR" ]; then
        rm -rf "$TARGET_SANDBOX_DIR"
    fi
}

assert_source_script_unchanged() {
    local current_hash
    current_hash="$(file_sha256 "$SOURCE_RALPHIE_FILE")"
    [ "$current_hash" = "$SOURCE_RALPHIE_SHA256" ]
}

assert_unit_runtime_isolated() {
    local path
    for path in "${PROJECT_DIR:-}" "${CONFIG_DIR:-}" "${LOG_DIR:-}" "${CONSENSUS_DIR:-}" "${RESEARCH_DIR:-}"; do
        case "$path" in
            "$ROOT_DIR"|"$ROOT_DIR"/*)
                fail "Unit test runtime path escaped sandbox and points at repo path: $path"
                return 1
                ;;
        esac
    done
    return 0
}

contains_control_chars() {
    local value="${1:-}"
    printf '%s' "$value" | LC_ALL=C grep -q $'[\001-\010\013\014\016-\037\177]'
}

make_workspace() {
    local ws
    ws="$(mktemp -d /tmp/ralphie-durability.XXXXXX)"
    cp "$RALPHIE_FILE" "$ws/ralphie.sh"
    chmod +x "$ws/ralphie.sh"
    printf '%s' "$ws"
}

run_case() {
    local name="$1"
    shift
    local rc=0
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    info "Running: $name"
    if ! "$@"; then
        rc=$?
    fi

    if ! assert_source_script_unchanged; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_CASES+=("$name:source-integrity")
        fail "$name (source script changed during test case)"
        return 0
    fi
    if ! assert_repo_tracked_status_unchanged; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_CASES+=("$name:tracked-repo-integrity")
        fail "$name (tracked repo files changed during test case)"
        return 0
    fi

    if [ "$rc" -eq 0 ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        pass "$name"
        return 0
    fi
    if [ "$rc" -eq 200 ]; then
        SKIP_COUNT=$((SKIP_COUNT + 1))
        warn "Skipped: $name"
        return 0
    fi
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILED_CASES+=("$name")
    fail "$name"
    return 0
}

test_syntax() {
    bash -n "$RALPHIE_FILE"
}

test_shellcheck() {
    if ! command -v shellcheck >/dev/null 2>&1; then
        return 200
    fi
    shellcheck "$RALPHIE_FILE" >/dev/null
}

test_unit_state_roundtrip_and_checksum() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "$RALPHIE_FILE"
        assert_unit_runtime_isolated

        local tmpd
        tmpd="$(mktemp -d /tmp/ralphie-state-unit.XXXXXX)"
        CONFIG_DIR="$tmpd"
        STATE_FILE="$tmpd/state.env"

        local expected_session_id expected_git_src
        expected_session_id=$'sess"id\\path\nline2\tend'
        expected_git_src=$'git "identity" \\\\source\\\\\nwith\tnewlines'

        CURRENT_PHASE="build"
        CURRENT_PHASE_INDEX=1
        CURRENT_PHASE_ATTEMPT=2
        PHASE_ATTEMPT_IN_PROGRESS="true"
        ITERATION_COUNT=7
        SESSION_ID="$expected_session_id"
        SESSION_ATTEMPT_COUNT=4
        SESSION_TOKEN_COUNT=123
        SESSION_COST_CENTS=88
        LAST_RUN_TOKEN_COUNT=9
        ENGINE_OUTPUT_TO_STDOUT="false"
        PHASE_TRANSITION_HISTORY=("plan(attempt 1)->build|pass|ok")
        GIT_IDENTITY_READY="true"
        GIT_IDENTITY_SOURCE="$expected_git_src"

        save_state

        CURRENT_PHASE=""
        CURRENT_PHASE_INDEX=0
        CURRENT_PHASE_ATTEMPT=1
        PHASE_ATTEMPT_IN_PROGRESS="false"
        ITERATION_COUNT=0
        SESSION_ID=""
        SESSION_ATTEMPT_COUNT=0
        SESSION_TOKEN_COUNT=0
        SESSION_COST_CENTS=0
        LAST_RUN_TOKEN_COUNT=0
        ENGINE_OUTPUT_TO_STDOUT=""
        PHASE_TRANSITION_HISTORY=()
        GIT_IDENTITY_READY="unknown"
        GIT_IDENTITY_SOURCE=""

        load_state

        [ "$SESSION_ID" = "$expected_session_id" ]
        [ "$GIT_IDENTITY_SOURCE" = "$expected_git_src" ]
        [ "$CURRENT_PHASE" = "build" ]
        [ "$CURRENT_PHASE_ATTEMPT" = "2" ]
        grep -q '^STATE_CHECKSUM=' "$STATE_FILE"

        # Tamper with state body to force checksum mismatch and verify clean failure.
        local tampered
        tampered="$(mktemp /tmp/ralphie-state-tampered.XXXXXX)"
        awk '{ gsub(/CURRENT_PHASE="build"/, "CURRENT_PHASE=\"lint\""); print }' "$STATE_FILE" > "$tampered"
        mv "$tampered" "$STATE_FILE"
        if load_state; then
            return 1
        fi
    )
}

test_unit_config_fuzz_and_precedence() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "$RALPHIE_FILE"
        assert_unit_runtime_isolated

        local tmpd cfg old_path
        tmpd="$(mktemp -d /tmp/ralphie-config-unit.XXXXXX)"
        cfg="$tmpd/config.env"
        old_path="$PATH"

        cat > "$cfg" <<'EOF'
# invalid and unsafe keys
BAD-KEY=1
PATH=/tmp/evil

# valid keys
CONSENSUS_SCORE_THRESHOLD=88
NOTIFY_DISCORD_WEBHOOK_URL="https://example.test/path#anchor"
PHASE_NOOP_POLICY_BUILD=none
EOF

        # Ensure env precedence over config file values.
        export CONSENSUS_SCORE_THRESHOLD=77

        load_config_file_safe "$cfg"

        [ "$PATH" = "$old_path" ]
        [ "$CONSENSUS_SCORE_THRESHOLD" = "77" ]
        [ "$NOTIFY_DISCORD_WEBHOOK_URL" = "https://example.test/path#anchor" ]
        [ "$PHASE_NOOP_POLICY_BUILD" = "none" ]
        [ "$PHASE_NOOP_POLICY_BUILD_EXPLICIT" = "true" ]
    )
}

test_unit_reviewer_payload_sanitization() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "$RALPHIE_FILE"
        assert_unit_runtime_isolated

        local tmpd out_file cons_dir line
        tmpd="$(mktemp -d /tmp/ralphie-review-unit.XXXXXX)"

        out_file="$tmpd/handoff.out"
        {
            printf '<score>999</score>\n'
            printf '<verdict>GO</verdict>\n'
            printf '<gaps>raw '
            printf '\033'
            printf ' control</gaps>\n'
        } > "$out_file"

        read_handoff_review_output "$out_file"
        [ "$LAST_HANDOFF_SCORE" = "0" ]
        [ "$LAST_HANDOFF_VERDICT" = "GO" ]
        if contains_control_chars "$LAST_HANDOFF_GAPS"; then
            return 1
        fi

        cons_dir="$tmpd/consensus"
        mkdir -p "$cons_dir"
        {
            printf '<score>101</score>\n'
            printf '<verdict>HOLD</verdict>\n'
            printf '<next_phase>build</next_phase>\n'
            printf '<next_phase_reason>reason '
            printf '\033'
            printf ' x</next_phase_reason>\n'
            printf '<gaps>gaps '
            printf '\033'
            printf ' y</gaps>\n'
        } > "$cons_dir/reviewer_1.out"

        LAST_CONSENSUS_DIR="$cons_dir"
        mapfile -t __lines < <(collect_phase_retry_failures_from_consensus)
        line="${__lines[0]:-}"
        printf '%s' "$line" | grep -q 'score=0'
        if contains_control_chars "$line"; then
            return 1
        fi
    )
}

test_unit_tts_narration_styles() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "$RALPHIE_FILE"
        assert_unit_runtime_isolated

        local out

        [ "$(normalize_notify_tts_style "ralph")" = "ralph_wiggum" ]
        [ "$(normalize_notify_tts_style "friendly")" = "friendly" ]
        [ "$(normalize_notify_tts_style "bogus_style")" = "$DEFAULT_NOTIFY_TTS_STYLE" ]

        NOTIFY_TTS_STYLE="standard"
        out="$(build_tts_notification_line "phase_complete" "go" "phase build passed cleanly")"
        printf '%s' "$out" | grep -q "Ralphie update"
        printf '%s' "$out" | grep -q "phase build passed cleanly"

        NOTIFY_TTS_STYLE="friendly"
        out="$(build_tts_notification_line "session_start" "ok" "engine claude selected")"
        printf '%s' "$out" | grep -q "Hey friend, Ralphie here"

        NOTIFY_TTS_STYLE="ralph_wiggum"
        out="$(build_tts_notification_line "session_done" "ok" "all phases complete")"
        printf '%s' "$out" | grep -q "I am Ralphie"
        printf '%s' "$out" | grep -q "Woo hoo!"
    )
}

test_unit_notify_discord_text_fallback_on_tts_failure() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "$RALPHIE_FILE"
        assert_unit_runtime_isolated

        local tmpd delivery_line
        local text_send_calls=0
        local tts_send_calls=0

        tmpd="$(mktemp -d /tmp/ralphie-notify-fallback-unit.XXXXXX)"
        PROJECT_DIR="$tmpd/project"
        CONFIG_DIR="$tmpd/config"
        NOTIFICATION_LOG_FILE="$tmpd/notifications.log"
        mkdir -p "$PROJECT_DIR" "$CONFIG_DIR"
        : > "$NOTIFICATION_LOG_FILE"

        NOTIFICATIONS_ENABLED=true
        NOTIFY_TELEGRAM_ENABLED=false
        NOTIFY_DISCORD_ENABLED=true
        NOTIFY_DISCORD_WEBHOOK_URL="https://example.invalid/webhook"
        NOTIFY_TTS_ENABLED=true
        CHUTES_API_KEY="dummy_key"
        NOTIFY_EVENT_DEDUP_WINDOW_SECONDS=0
        NOTIFY_INCIDENT_REMINDER_MINUTES=0
        SESSION_ID="notify_fallback_unit"
        CURRENT_PHASE="build"
        CURRENT_PHASE_ATTEMPT=1
        ITERATION_COUNT=1
        ACTIVE_ENGINE="claude"

        send_discord_message_raw() {
            text_send_calls=$((text_send_calls + 1))
            return 0
        }
        send_discord_tts_raw() {
            tts_send_calls=$((tts_send_calls + 1))
            return 1
        }

        notify_event "phase_complete" "go" "fallback to text when tts fails"

        [ "$text_send_calls" -eq 1 ]
        [ "$tts_send_calls" -eq 1 ]
        delivery_line="$(tail -n 1 "$NOTIFICATION_LOG_FILE")"
        printf '%s' "$delivery_line" | grep -q 'event=phase_complete'
        printf '%s' "$delivery_line" | grep -q 'delivery=delivered'
        printf '%s' "$delivery_line" | grep -q 'tts=fallback_text_only'
    )
}

test_unit_stack_discovery() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "$RALPHIE_FILE"
        assert_unit_runtime_isolated

        local tmpd
        tmpd="$(mktemp -d /tmp/ralphie-stack-unit.XXXXXX)"
        PROJECT_DIR="$tmpd/project"
        CONFIG_DIR="$tmpd/config"
        RESEARCH_DIR="$PROJECT_DIR/research"
        STACK_SNAPSHOT_FILE="$RESEARCH_DIR/STACK_SNAPSHOT.md"
        mkdir -p "$PROJECT_DIR"
        mkdir -p "$CONFIG_DIR"

        cat > "$PROJECT_DIR/package.json" <<'EOF'
{"name":"durability-suite","version":"1.0.0"}
EOF

        run_stack_discovery
        [ -f "$STACK_SNAPSHOT_FILE" ]
        grep -q '^## Project Stack Ranking' "$STACK_SNAPSHOT_FILE"
    )
}

test_integration_happy_path() {
    local ws
    ws="$(make_workspace)"
    cat > "$ws/harness.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export RALPHIE_RESUME_REQUESTED=false
export RALPHIE_AUTO_UPDATE=false
export RALPHIE_STARTUP_OPERATIONAL_PROBE=false
export RALPHIE_AUTO_COMMIT_ON_PHASE_PASS=false
export RALPHIE_NOTIFICATIONS_ENABLED=false
export RALPHIE_ENGINE_OVERRIDES_BOOTSTRAPPED=true
export RALPHIE_NOTIFICATION_WIZARD_BOOTSTRAPPED=true
source ./ralphie.sh
ensure_engines_ready() { CODEX_HEALTHY=true; CLAUDE_HEALTHY=false; ACTIVE_ENGINE=codex; ACTIVE_CMD=codex; return 0; }
probe_engine_capabilities() { CODEX_CAP_OUTPUT_LAST_MESSAGE=1; CODEX_CAP_YOLO_FLAG=1; CLAUDE_CAP_PRINT=1; ENGINE_CAPABILITIES_PROBED=true; return 0; }
run_first_deploy_engine_override_wizard() { return 0; }
run_first_deploy_notification_wizard() { return 0; }
run_startup_operational_probe() { return 0; }
build_is_preapproved() { return 0; }
__durability_counter=0
run_agent_with_prompt() {
    local _prompt="$1" log_file="$2" output_file="$3"
    __durability_counter=$((__durability_counter + 1))
    printf 'stub run %s\n' "$__durability_counter" > "$log_file"
    cat > "$output_file" <<MSG
Updated artifacts:
- durability marker $__durability_counter
Assumptions made:
- harness happy path
Blockers/risks:
- none
Phase status: complete.
MSG
    printf 'mutation-%s\n' "$__durability_counter" >> durability-mutation.log
    return 0
}
run_handoff_validation() { LAST_HANDOFF_SCORE=95; LAST_HANDOFF_VERDICT=GO; LAST_HANDOFF_GAPS=none; return 0; }
run_swarm_consensus() {
    local stage="$1" base="${stage%-gate}"
    LAST_CONSENSUS_SCORE=92
    LAST_CONSENSUS_PASS=true
    LAST_CONSENSUS_RESPONDED_VOTES=3
    LAST_CONSENSUS_SUMMARY="durability happy path"
    LAST_CONSENSUS_NEXT_PHASE="$(phase_default_next "$base")"
    LAST_CONSENSUS_NEXT_PHASE_REASON="stub next"
    return 0
}
main --no-resume > "$PWD/run.out" 2> "$PWD/run.err"
grep -q "All phases completed. Session done." "$PWD/run.out"
grep -q 'CURRENT_PHASE="done"' "$PWD/.ralphie/state.env"
EOF
    chmod +x "$ws/harness.sh"
    "$ws/harness.sh"
}

test_integration_forward_reroute_guard() {
    local ws
    ws="$(make_workspace)"
    cat > "$ws/harness.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export RALPHIE_RESUME_REQUESTED=true
export RALPHIE_AUTO_UPDATE=false
export RALPHIE_STARTUP_OPERATIONAL_PROBE=false
export RALPHIE_AUTO_COMMIT_ON_PHASE_PASS=false
export RALPHIE_NOTIFICATIONS_ENABLED=false
export RALPHIE_ENGINE_OVERRIDES_BOOTSTRAPPED=true
export RALPHIE_NOTIFICATION_WIZARD_BOOTSTRAPPED=true
export RALPHIE_PHASE_COMPLETION_MAX_ATTEMPTS=1
source ./ralphie.sh
load_state() {
    CURRENT_PHASE="build"
    CURRENT_PHASE_INDEX=1
    CURRENT_PHASE_ATTEMPT=1
    PHASE_ATTEMPT_IN_PROGRESS=true
    ITERATION_COUNT=1
    SESSION_ATTEMPT_COUNT=0
    return 0
}
ensure_engines_ready() { CODEX_HEALTHY=true; CLAUDE_HEALTHY=false; ACTIVE_ENGINE=codex; ACTIVE_CMD=codex; return 0; }
probe_engine_capabilities() { CODEX_CAP_OUTPUT_LAST_MESSAGE=1; CODEX_CAP_YOLO_FLAG=1; CLAUDE_CAP_PRINT=1; ENGINE_CAPABILITIES_PROBED=true; return 0; }
run_first_deploy_engine_override_wizard() { return 0; }
run_first_deploy_notification_wizard() { return 0; }
run_startup_operational_probe() { return 0; }
build_is_preapproved() { return 0; }
run_agent_with_prompt() {
    local _prompt="$1" log_file="$2" output_file="$3"
    printf 'reroute guard log\n' > "$log_file"
    printf 'reroute guard output\n' > "$output_file"
    printf 'reroute-mutation\n' >> reroute-mutation.log
    return 0
}
run_handoff_validation() { LAST_HANDOFF_SCORE=20; LAST_HANDOFF_VERDICT=HOLD; LAST_HANDOFF_GAPS=forced_hold; return 1; }
run_swarm_consensus() {
    LAST_CONSENSUS_SCORE=90
    LAST_CONSENSUS_PASS=true
    LAST_CONSENSUS_RESPONDED_VOTES=3
    LAST_CONSENSUS_SUMMARY="reroute hold guard"
    LAST_CONSENSUS_NEXT_PHASE="test"
    LAST_CONSENSUS_NEXT_PHASE_REASON="forced forward"
    return 0
}
main --resume > "$PWD/run.out" 2> "$PWD/run.err" || true
grep -q "phase completion attempts remaining: 1" "$PWD/run.out"
grep -q "ignoring non-backtracking reroute recommendation 'test'" "$PWD/run.out" "$PWD/run.err"
EOF
    chmod +x "$ws/harness.sh"
    "$ws/harness.sh"
}

test_integration_resume_done_short_circuit() {
    local ws
    ws="$(make_workspace)"
    cat > "$ws/harness.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export RALPHIE_RESUME_REQUESTED=true
export RALPHIE_AUTO_UPDATE=false
export RALPHIE_STARTUP_OPERATIONAL_PROBE=false
export RALPHIE_AUTO_COMMIT_ON_PHASE_PASS=false
export RALPHIE_NOTIFICATIONS_ENABLED=false
export RALPHIE_ENGINE_OVERRIDES_BOOTSTRAPPED=true
export RALPHIE_NOTIFICATION_WIZARD_BOOTSTRAPPED=true
source ./ralphie.sh
load_state() {
    CURRENT_PHASE="done"
    CURRENT_PHASE_INDEX=6
    CURRENT_PHASE_ATTEMPT=1
    PHASE_ATTEMPT_IN_PROGRESS=false
    ITERATION_COUNT=9
    SESSION_ATTEMPT_COUNT=0
    return 0
}
ensure_engines_ready() { CODEX_HEALTHY=true; CLAUDE_HEALTHY=false; ACTIVE_ENGINE=codex; ACTIVE_CMD=codex; return 0; }
probe_engine_capabilities() { CODEX_CAP_OUTPUT_LAST_MESSAGE=1; CODEX_CAP_YOLO_FLAG=1; CLAUDE_CAP_PRINT=1; ENGINE_CAPABILITIES_PROBED=true; return 0; }
run_first_deploy_engine_override_wizard() { return 0; }
run_first_deploy_notification_wizard() { return 0; }
run_startup_operational_probe() { return 0; }
run_agent_with_prompt() { return 1; }
run_handoff_validation() { return 1; }
run_swarm_consensus() { return 1; }
main --resume > "$PWD/run.out" 2> "$PWD/run.err"
grep -q "All phases completed. Session done." "$PWD/run.out"
if grep -q ">>> Entering phase" "$PWD/run.out"; then
    exit 1
fi
EOF
    chmod +x "$ws/harness.sh"
    "$ws/harness.sh"
}

test_integration_lock_contention() {
    local ws
    ws="$(make_workspace)"
    cat > "$ws/holder.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./ralphie.sh
acquire_lock
sleep 4
release_lock
EOF
    cat > "$ws/contender.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./ralphie.sh
if acquire_lock; then
    release_lock
    exit 1
fi
exit 0
EOF
    chmod +x "$ws/holder.sh" "$ws/contender.sh"
    "$ws/holder.sh" >/dev/null 2>&1 &
    local holder_pid=$!
    sleep 0.7
    "$ws/contender.sh"
    wait "$holder_pid"
}

test_integration_crash_and_resume() {
    local ws
    ws="$(make_workspace)"

    cat > "$ws/harness_crash.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export RALPHIE_RESUME_REQUESTED=false
export RALPHIE_AUTO_UPDATE=false
export RALPHIE_STARTUP_OPERATIONAL_PROBE=false
export RALPHIE_AUTO_COMMIT_ON_PHASE_PASS=false
export RALPHIE_NOTIFICATIONS_ENABLED=false
export RALPHIE_ENGINE_OVERRIDES_BOOTSTRAPPED=true
export RALPHIE_NOTIFICATION_WIZARD_BOOTSTRAPPED=true
source ./ralphie.sh
ensure_engines_ready() { CODEX_HEALTHY=true; CLAUDE_HEALTHY=false; ACTIVE_ENGINE=codex; ACTIVE_CMD=codex; return 0; }
probe_engine_capabilities() { CODEX_CAP_OUTPUT_LAST_MESSAGE=1; CODEX_CAP_YOLO_FLAG=1; CLAUDE_CAP_PRINT=1; ENGINE_CAPABILITIES_PROBED=true; return 0; }
run_first_deploy_engine_override_wizard() { return 0; }
run_first_deploy_notification_wizard() { return 0; }
run_startup_operational_probe() { return 0; }
build_is_preapproved() { return 0; }
run_agent_with_prompt() {
    local _prompt="$1" log_file="$2" output_file="$3"
    printf 'crash run in progress\n' > "$log_file"
    sleep 30
    printf 'should not reach before kill\n' > "$output_file"
    return 0
}
run_handoff_validation() { LAST_HANDOFF_SCORE=95; LAST_HANDOFF_VERDICT=GO; LAST_HANDOFF_GAPS=none; return 0; }
run_swarm_consensus() {
    local stage="$1" base="${stage%-gate}"
    LAST_CONSENSUS_SCORE=90
    LAST_CONSENSUS_PASS=true
    LAST_CONSENSUS_RESPONDED_VOTES=3
    LAST_CONSENSUS_SUMMARY="crash harness"
    LAST_CONSENSUS_NEXT_PHASE="$(phase_default_next "$base")"
    LAST_CONSENSUS_NEXT_PHASE_REASON="stub next"
    return 0
}
main --no-resume > "$PWD/crash.out" 2> "$PWD/crash.err"
EOF

    cat > "$ws/harness_resume.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export RALPHIE_RESUME_REQUESTED=true
export RALPHIE_AUTO_UPDATE=false
export RALPHIE_STARTUP_OPERATIONAL_PROBE=false
export RALPHIE_AUTO_COMMIT_ON_PHASE_PASS=false
export RALPHIE_NOTIFICATIONS_ENABLED=false
export RALPHIE_ENGINE_OVERRIDES_BOOTSTRAPPED=true
export RALPHIE_NOTIFICATION_WIZARD_BOOTSTRAPPED=true
source ./ralphie.sh
ensure_engines_ready() { CODEX_HEALTHY=true; CLAUDE_HEALTHY=false; ACTIVE_ENGINE=codex; ACTIVE_CMD=codex; return 0; }
probe_engine_capabilities() { CODEX_CAP_OUTPUT_LAST_MESSAGE=1; CODEX_CAP_YOLO_FLAG=1; CLAUDE_CAP_PRINT=1; ENGINE_CAPABILITIES_PROBED=true; return 0; }
run_first_deploy_engine_override_wizard() { return 0; }
run_first_deploy_notification_wizard() { return 0; }
run_startup_operational_probe() { return 0; }
build_is_preapproved() { return 0; }
__resume_counter=0
run_agent_with_prompt() {
    local _prompt="$1" log_file="$2" output_file="$3"
    __resume_counter=$((__resume_counter + 1))
    printf 'resume run %s\n' "$__resume_counter" > "$log_file"
    printf 'resume output %s\n' "$__resume_counter" > "$output_file"
    printf 'resume-mutation-%s\n' "$__resume_counter" >> resume-mutation.log
    return 0
}
run_handoff_validation() { LAST_HANDOFF_SCORE=95; LAST_HANDOFF_VERDICT=GO; LAST_HANDOFF_GAPS=none; return 0; }
run_swarm_consensus() {
    local stage="$1" base="${stage%-gate}"
    LAST_CONSENSUS_SCORE=90
    LAST_CONSENSUS_PASS=true
    LAST_CONSENSUS_RESPONDED_VOTES=3
    LAST_CONSENSUS_SUMMARY="resume harness"
    LAST_CONSENSUS_NEXT_PHASE="$(phase_default_next "$base")"
    LAST_CONSENSUS_NEXT_PHASE_REASON="stub next"
    return 0
}
main --resume > "$PWD/resume.out" 2> "$PWD/resume.err"
grep -q "Resuming in-progress phase" "$PWD/resume.out"
grep -q 'CURRENT_PHASE="done"' "$PWD/.ralphie/state.env"
EOF

    chmod +x "$ws/harness_crash.sh" "$ws/harness_resume.sh"

    "$ws/harness_crash.sh" >/dev/null 2>&1 &
    local run_pid=$!
    local state_file="$ws/.ralphie/state.env"
    local found_in_progress=false
    local i
    for i in $(seq 1 80); do
        if [ -f "$state_file" ] && grep -q 'PHASE_ATTEMPT_IN_PROGRESS="true"' "$state_file" 2>/dev/null; then
            found_in_progress=true
            break
        fi
        sleep 0.25
    done
    if [ "$found_in_progress" != true ]; then
        kill -TERM "$run_pid" >/dev/null 2>&1 || true
        wait "$run_pid" >/dev/null 2>&1 || true
        return 1
    fi

    kill -TERM "$run_pid" >/dev/null 2>&1 || true
    wait "$run_pid" >/dev/null 2>&1 || true

    "$ws/harness_resume.sh"
}

main() {
    if [ ! -f "$SOURCE_RALPHIE_FILE" ]; then
        fail "Missing source script: $SOURCE_RALPHIE_FILE"
        exit 1
    fi
    prepare_isolated_target
    trap cleanup_isolated_target EXIT
    capture_repo_tracked_status_baseline

    if [ ! -f "$RALPHIE_FILE" ]; then
        fail "Failed to prepare isolated target script: $RALPHIE_FILE"
        exit 1
    fi

    run_case "syntax" test_syntax
    run_case "shellcheck" test_shellcheck
    run_case "unit_state_roundtrip_and_checksum" test_unit_state_roundtrip_and_checksum
    run_case "unit_config_fuzz_and_precedence" test_unit_config_fuzz_and_precedence
    run_case "unit_reviewer_payload_sanitization" test_unit_reviewer_payload_sanitization
    run_case "unit_tts_narration_styles" test_unit_tts_narration_styles
    run_case "unit_notify_discord_text_fallback_on_tts_failure" test_unit_notify_discord_text_fallback_on_tts_failure
    run_case "unit_stack_discovery" test_unit_stack_discovery
    run_case "integration_happy_path" test_integration_happy_path
    run_case "integration_forward_reroute_guard" test_integration_forward_reroute_guard
    run_case "integration_resume_done_short_circuit" test_integration_resume_done_short_circuit
    run_case "integration_lock_contention" test_integration_lock_contention
    run_case "integration_crash_and_resume" test_integration_crash_and_resume

    printf '\n'
    info "Total: $TOTAL_COUNT | Passed: $PASS_COUNT | Failed: $FAIL_COUNT | Skipped: $SKIP_COUNT"
    if [ "$FAIL_COUNT" -gt 0 ]; then
        warn "Failed cases:"
        local item
        for item in "${FAILED_CASES[@]}"; do
            warn " - $item"
        done
        exit 1
    fi

    if ! assert_source_script_unchanged; then
        fail "Source ralphie.sh changed during durability run; refusing pass because repo isolation was violated."
        exit 1
    fi
    if ! assert_repo_tracked_status_unchanged; then
        fail "Tracked repository files changed during durability run; refusing pass because repo isolation was violated."
        exit 1
    fi
}

main "$@"
