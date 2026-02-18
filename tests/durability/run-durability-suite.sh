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
    if "$@"; then
        rc=0
    else
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

test_unit_bootstrap_dense_reflection_and_personas() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "$RALPHIE_FILE"
        assert_unit_runtime_isolated

        local token dense_line dense_line_manual
        local -a persona_lines=()
        local -a persona_assessments=()
        local -a persona_blockers=()
        local -a missing_loose=()
        local -a missing_strict=()
        local assessment
        local tmpd_valid

        token="$(bootstrap_dense_token $'Goal line\nwith\tspaces' "fallback" 30)"
        [ "$token" = "Goal_line_with_spaces" ]
        [ "$(bootstrap_dense_token "" "fallback_value" 30)" = "fallback_value" ]

        dense_line="$(bootstrap_dense_reflection_line "existing" "Ship API quickly" "no cloud vendor lockin" "phase gates pass" "true" "svc+cli" "go+postgres")"
        printf '%s' "$dense_line" | grep -q 'g=Ship_API_quickly'
        printf '%s' "$dense_line" | grep -q '|tp=existing|'
        printf '%s' "$dense_line" | grep -q '|ar=svc+cli|'
        printf '%s' "$dense_line" | grep -q '|st=go+postgres|'
        printf '%s' "$dense_line" | grep -q '|b=ab$'

        dense_line_manual="$(bootstrap_dense_reflection_line "existing" "Ship API quickly" "no cloud vendor lockin" "phase gates pass" "false" "svc+cli" "go+postgres")"
        printf '%s' "$dense_line_manual" | grep -q '|b=mb$'

        mapfile -t persona_lines < <(bootstrap_persona_feedback_lines "existing" "Ship API quickly" "no cloud vendor lockin" "phase gates pass" "true" "svc+cli" "go+postgres")
        [ "${#persona_lines[@]}" -eq 6 ]
        printf '%s\n' "${persona_lines[@]}" | grep -q '^Architect>'
        printf '%s\n' "${persona_lines[@]}" | grep -q '^Skeptic>'
        printf '%s\n' "${persona_lines[@]}" | grep -q '^Execution>'
        printf '%s\n' "${persona_lines[@]}" | grep -q '^Safety>'
        printf '%s\n' "${persona_lines[@]}" | grep -q '^Operations>'
        printf '%s\n' "${persona_lines[@]}" | grep -q '^Quality>'

        mapfile -t missing_loose < <(
            bootstrap_schema_missing_fields_from_values \
                "existing" \
                "brief" \
                "No explicit constraints provided." \
                "No explicit success criteria provided." \
                "true" \
                "No explicit structure preference provided." \
                "No explicit technology preference provided." \
                "true" \
                "false"
        )
        [ "${#missing_loose[@]}" -eq 0 ]

        mapfile -t missing_strict < <(
            bootstrap_schema_missing_fields_from_values \
                "existing" \
                "brief" \
                "No explicit constraints provided." \
                "No explicit success criteria provided." \
                "true" \
                "No explicit structure preference provided." \
                "No explicit technology preference provided." \
                "true" \
                "true"
        )
        printf '%s\n' "${missing_strict[@]}" | grep -q '^constraints$'
        printf '%s\n' "${missing_strict[@]}" | grep -q '^success_criteria$'
        printf '%s\n' "${missing_strict[@]}" | grep -q '^architecture_shape$'
        printf '%s\n' "${missing_strict[@]}" | grep -q '^technology_choices$'

        mapfile -t persona_assessments < <(
            bootstrap_persona_assessment_lines \
                "existing" \
                "brief" \
                "No explicit constraints provided." \
                "No explicit success criteria provided." \
                "true" \
                "No explicit structure preference provided." \
                "No explicit technology preference provided."
        )
        [ "${#persona_assessments[@]}" -eq 6 ]
        for assessment in "${persona_assessments[@]}"; do
            printf '%s' "$assessment" | grep -q 'persona='
            printf '%s' "$assessment" | grep -q 'risk='
            printf '%s' "$assessment" | grep -q 'confidence='
            printf '%s' "$assessment" | grep -q 'blocking='
            printf '%s' "$assessment" | grep -q 'recommendation='
            [ -n "$(bootstrap_persona_field "$assessment" "persona" "")" ]
        done
        mapfile -t persona_blockers < <(bootstrap_persona_blocking_names "${persona_assessments[@]}")
        [ "${#persona_blockers[@]}" -gt 0 ]

        tmpd_valid="$(mktemp -d /tmp/ralphie-bootstrap-validity-unit.XXXXXX)"
        PROJECT_BOOTSTRAP_FILE="$tmpd_valid/project-bootstrap.md"
        PROJECT_GOALS_FILE="$tmpd_valid/project-goals.md"

        write_bootstrap_context_file \
            "existing" \
            "brief" \
            "true" \
            "true" \
            "No explicit constraints provided." \
            "No explicit success criteria provided." \
            "false" \
            "" \
            "No explicit structure preference provided." \
            "No explicit technology preference provided."
        if bootstrap_context_is_valid; then
            return 1
        fi

        write_bootstrap_context_file \
            "existing" \
            "brief" \
            "true" \
            "false" \
            "No explicit constraints provided." \
            "No explicit success criteria provided." \
            "false" \
            "" \
            "No explicit structure preference provided." \
            "No explicit technology preference provided."
        bootstrap_context_is_valid
    )
}

test_unit_bootstrap_alignment_loop_modify_rerun_dismiss() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "$RALPHIE_FILE"
        assert_unit_runtime_isolated

        local tmpd queue_file

        tmpd="$(mktemp -d /tmp/ralphie-bootstrap-loop-unit.XXXXXX)"
        PROJECT_DIR="$tmpd/project"
        CONFIG_DIR="$PROJECT_DIR/.ralphie"
        PROJECT_BOOTSTRAP_FILE="$CONFIG_DIR/project-bootstrap.md"
        PROJECT_GOALS_FILE="$CONFIG_DIR/project-goals.md"
        CONFIG_FILE="$CONFIG_DIR/config.env"
        mkdir -p "$PROJECT_DIR" "$CONFIG_DIR"
        queue_file="$tmpd/read-queue.txt"
        cat > "$queue_file" <<'EOF'
m
tech
r
d
EOF

        REBOOTSTRAP_REQUESTED=true

        is_tty_input_available() { return 0; }
        prompt_yes_no() {
            local prompt="$1"
            case "$prompt" in
                "Is this a new project (no established implementation yet)?") echo "false" ;;
                "Paste a project goals document/URL block now?") echo "false" ;;
                "Proceed automatically from PLAN -> BUILD when all gates pass") echo "true" ;;
                *) echo "false" ;;
            esac
            return 0
        }
        prompt_optional_line() {
            local prompt="$1"
            local default="${2:-}"
            case "$prompt" in
                "What is the primary objective for this session (single line)") echo "ship_bootstrap_alignment" ;;
                "Key constraints or non-goals (single line, optional)") echo "no_vendor_lockin" ;;
                "Success criteria / definition of done (single line, optional)") echo "plan_solid_and_agreed" ;;
                "Project goals document URL (optional)") echo "https://example.test/goals" ;;
                "Preferred project structure / architecture (single line, optional)") echo "svc_cli_modular" ;;
                "Preferred technology choices (single line, optional)") echo "python_fastapi_sqlite" ;;
                "Technology choices (single line)") echo "go_gin_postgres" ;;
                "Add or correct context before rerun (optional)") echo "extra_loop_context" ;;
                *) echo "$default" ;;
            esac
        }
        prompt_read_line() {
            local _prompt="$1"
            local default="${2:-}"
            local value="$default"
            if [ -f "$queue_file" ] && [ -s "$queue_file" ]; then
                value="$(head -n 1 "$queue_file")"
                tail -n +2 "$queue_file" > "${queue_file}.tmp" || true
                mv "${queue_file}.tmp" "$queue_file"
            fi
            echo "$value"
        }
        prompt_multiline_block() {
            local _prompt="$1"
            local default="${2:-}"
            printf '%s' "$default"
        }

        ensure_project_bootstrap

        [ -f "$PROJECT_BOOTSTRAP_FILE" ]
        [ -f "$PROJECT_GOALS_FILE" ]
        grep -q '^project_type: existing$' "$PROJECT_BOOTSTRAP_FILE"
        grep -q '^build_consent: true$' "$PROJECT_BOOTSTRAP_FILE"
        grep -q '^objective: ship_bootstrap_alignment$' "$PROJECT_BOOTSTRAP_FILE"
        grep -q '^constraints: no_vendor_lockin$' "$PROJECT_BOOTSTRAP_FILE"
        grep -q '^success_criteria: plan_solid_and_agreed$' "$PROJECT_BOOTSTRAP_FILE"
        grep -q '^architecture_shape: svc_cli_modular$' "$PROJECT_BOOTSTRAP_FILE"
        grep -q '^technology_choices: go_gin_postgres$' "$PROJECT_BOOTSTRAP_FILE"
        grep -q '^interactive_prompted: true$' "$PROJECT_BOOTSTRAP_FILE"
        grep -q 'extra_loop_context' "$PROJECT_GOALS_FILE"
    )
}

test_unit_bootstrap_accept_gate_and_no_change_guard() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "$RALPHIE_FILE"
        assert_unit_runtime_isolated

        local tmpd action_queue_file clarifier_queue_file
        tmpd="$(mktemp -d /tmp/ralphie-bootstrap-guard-unit.XXXXXX)"
        PROJECT_DIR="$tmpd/project"
        CONFIG_DIR="$PROJECT_DIR/.ralphie"
        PROJECT_BOOTSTRAP_FILE="$CONFIG_DIR/project-bootstrap.md"
        PROJECT_GOALS_FILE="$CONFIG_DIR/project-goals.md"
        CONFIG_FILE="$CONFIG_DIR/config.env"
        mkdir -p "$PROJECT_DIR" "$CONFIG_DIR"

        action_queue_file="$tmpd/action-queue.txt"
        clarifier_queue_file="$tmpd/clarifier-queue.txt"
        cat > "$action_queue_file" <<'EOF'
a
r
r
d
EOF
        cat > "$clarifier_queue_file" <<'EOF'
guarded_objective_round1
avoid_vendor_lockin_round1
done_signal_round1
guarded_objective_round2
avoid_vendor_lockin_round2
done_signal_round2
EOF

        REBOOTSTRAP_REQUESTED=true

        is_tty_input_available() { return 0; }
        prompt_yes_no() {
            local prompt="$1"
            case "$prompt" in
                "Is this a new project (no established implementation yet)?") echo "false" ;;
                "Paste a project goals document/URL block now?") echo "false" ;;
                "Proceed automatically from PLAN -> BUILD when all gates pass") echo "true" ;;
                *) echo "false" ;;
            esac
            return 0
        }
        prompt_optional_line() {
            local prompt="$1"
            local default="${2:-}"
            local value=""
            case "$prompt" in
                "What is the primary objective for this session (single line)") echo "brief" ;;
                "Key constraints or non-goals (single line, optional)") echo "No explicit constraints provided." ;;
                "Success criteria / definition of done (single line, optional)") echo "starter" ;;
                "Project goals document URL (optional)") echo "https://example.test/goals" ;;
                "Preferred project structure / architecture (single line, optional)") echo "svc_cli_modular" ;;
                "Preferred technology choices (single line, optional)") echo "bash_tools" ;;
                "Add or correct context before rerun (optional)") echo "" ;;
                "Clarify primary user/workflow (single line)"|"Clarify highest risk/non-goal (single line)"|"Clarify measurable done signal (single line)")
                    value="$default"
                    if [ -f "$clarifier_queue_file" ] && [ -s "$clarifier_queue_file" ]; then
                        value="$(head -n 1 "$clarifier_queue_file")"
                        tail -n +2 "$clarifier_queue_file" > "${clarifier_queue_file}.tmp" || true
                        mv "${clarifier_queue_file}.tmp" "$clarifier_queue_file"
                    fi
                    echo "$value"
                    ;;
                *)
                    echo "$default"
                    ;;
            esac
        }
        prompt_read_line() {
            local _prompt="$1"
            local default="${2:-}"
            local value="$default"
            if [ -f "$action_queue_file" ] && [ -s "$action_queue_file" ]; then
                value="$(head -n 1 "$action_queue_file")"
                tail -n +2 "$action_queue_file" > "${action_queue_file}.tmp" || true
                mv "${action_queue_file}.tmp" "$action_queue_file"
            fi
            echo "$value"
        }
        prompt_multiline_block() {
            local _prompt="$1"
            local default="${2:-}"
            printf '%s' "$default"
        }

        ensure_project_bootstrap

        [ -f "$PROJECT_BOOTSTRAP_FILE" ]
        grep -q '^objective: guarded_objective_round2$' "$PROJECT_BOOTSTRAP_FILE"
        grep -q '^constraints: avoid_vendor_lockin_round2$' "$PROJECT_BOOTSTRAP_FILE"
        grep -q '^success_criteria: done_signal_round2$' "$PROJECT_BOOTSTRAP_FILE"
        grep -q '^architecture_shape: svc_cli_modular$' "$PROJECT_BOOTSTRAP_FILE"
        grep -q '^technology_choices: bash_tools$' "$PROJECT_BOOTSTRAP_FILE"
    )
}

test_unit_bootstrap_accept_blocked_no_change_guard() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "$RALPHIE_FILE"
        assert_unit_runtime_isolated

        local tmpd action_queue_file clarifier_queue_file
        tmpd="$(mktemp -d /tmp/ralphie-bootstrap-accept-nochange-unit.XXXXXX)"
        PROJECT_DIR="$tmpd/project"
        CONFIG_DIR="$PROJECT_DIR/.ralphie"
        PROJECT_BOOTSTRAP_FILE="$CONFIG_DIR/project-bootstrap.md"
        PROJECT_GOALS_FILE="$CONFIG_DIR/project-goals.md"
        CONFIG_FILE="$CONFIG_DIR/config.env"
        mkdir -p "$PROJECT_DIR" "$CONFIG_DIR"

        action_queue_file="$tmpd/action-queue.txt"
        clarifier_queue_file="$tmpd/clarifier-queue.txt"
        cat > "$action_queue_file" <<'EOF'
a
a
d
EOF
        cat > "$clarifier_queue_file" <<'EOF'
__KEEP_DEFAULT__
__KEEP_DEFAULT__
__KEEP_DEFAULT__
__KEEP_DEFAULT__
__KEEP_DEFAULT__
__KEEP_DEFAULT__
guard_fixed_objective
guard_fixed_constraints
guard_fixed_success
EOF

        REBOOTSTRAP_REQUESTED=true

        is_tty_input_available() { return 0; }
        prompt_yes_no() {
            local prompt="$1"
            case "$prompt" in
                "Is this a new project (no established implementation yet)?") echo "false" ;;
                "Paste a project goals document/URL block now?") echo "false" ;;
                "Proceed automatically from PLAN -> BUILD when all gates pass") echo "true" ;;
                *) echo "false" ;;
            esac
            return 0
        }
        prompt_optional_line() {
            local prompt="$1"
            local default="${2:-}"
            case "$prompt" in
                "What is the primary objective for this session (single line)") echo "guard_base_objective" ;;
                "Key constraints or non-goals (single line, optional)") echo "No explicit constraints provided." ;;
                "Success criteria / definition of done (single line, optional)") echo "guard_base_success" ;;
                "Project goals document URL (optional)") echo "https://example.test/goals" ;;
                "Preferred project structure / architecture (single line, optional)") echo "svc_cli_modular" ;;
                "Preferred technology choices (single line, optional)") echo "bash_tools" ;;
                "Clarify primary user/workflow (single line)"|"Clarify highest risk/non-goal (single line)"|"Clarify measurable done signal (single line)")
                    local value="$default"
                    if [ -f "$clarifier_queue_file" ] && [ -s "$clarifier_queue_file" ]; then
                        value="$(head -n 1 "$clarifier_queue_file")"
                        tail -n +2 "$clarifier_queue_file" > "${clarifier_queue_file}.tmp" || true
                        mv "${clarifier_queue_file}.tmp" "$clarifier_queue_file"
                    fi
                    if [ "$value" = "__KEEP_DEFAULT__" ]; then
                        value="$default"
                    fi
                    echo "$value"
                    ;;
                *)
                    echo "$default"
                    ;;
            esac
        }
        prompt_read_line() {
            local _prompt="$1"
            local default="${2:-}"
            local value="$default"
            if [ -f "$action_queue_file" ] && [ -s "$action_queue_file" ]; then
                value="$(head -n 1 "$action_queue_file")"
                tail -n +2 "$action_queue_file" > "${action_queue_file}.tmp" || true
                mv "${action_queue_file}.tmp" "$action_queue_file"
            fi
            echo "$value"
        }
        prompt_multiline_block() {
            local _prompt="$1"
            local default="${2:-}"
            printf '%s' "$default"
        }

        ensure_project_bootstrap

        [ -f "$PROJECT_BOOTSTRAP_FILE" ]
        grep -q '^objective: guard_fixed_objective$' "$PROJECT_BOOTSTRAP_FILE"
        grep -q '^constraints: guard_fixed_constraints$' "$PROJECT_BOOTSTRAP_FILE"
        grep -q '^success_criteria: guard_fixed_success$' "$PROJECT_BOOTSTRAP_FILE"
    )
}

test_unit_append_bootstrap_context_includes_arch_and_tech() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "$RALPHIE_FILE"
        assert_unit_runtime_isolated

        local tmpd source_prompt target_prompt
        tmpd="$(mktemp -d /tmp/ralphie-bootstrap-prompt-unit.XXXXXX)"
        PROJECT_DIR="$tmpd/project"
        CONFIG_DIR="$PROJECT_DIR/.ralphie"
        PROJECT_BOOTSTRAP_FILE="$CONFIG_DIR/project-bootstrap.md"
        PROJECT_GOALS_FILE="$CONFIG_DIR/project-goals.md"
        mkdir -p "$PROJECT_DIR" "$CONFIG_DIR"

        write_bootstrap_context_file \
            "existing" \
            "tight_scope_objective" \
            "true" \
            "true" \
            "no_rewrite" \
            "all_gates_green" \
            "true" \
            "https://example.test/goals" \
            "hex_arch" \
            "rust_axum_postgres"
        write_project_goals_file "goal block line"

        source_prompt="$tmpd/source-plan.md"
        target_prompt="$tmpd/target-plan.md"
        cat > "$source_prompt" <<'EOF'
# Base Prompt
EOF

        append_bootstrap_context_to_plan_prompt "$source_prompt" "$target_prompt"

        [ -f "$target_prompt" ]
        grep -q 'Preferred architecture / structure: hex_arch' "$target_prompt"
        grep -q 'Preferred technology choices: rust_axum_postgres' "$target_prompt"
        grep -q 'Project Goals Document (User-Provided)' "$target_prompt"
    )
}

test_unit_idle_output_watchdog_recycles_hung_process() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "$RALPHIE_FILE"
        assert_unit_runtime_isolated

        local tmpd log_file out_file rc
        tmpd="$(mktemp -d /tmp/ralphie-watchdog-unit.XXXXXX)"
        log_file="$tmpd/agent.log"
        out_file="$tmpd/agent.out"
        : > "$log_file"
        : > "$out_file"

        (
            printf 'boot\n' >> "$log_file"
            sleep 5
            printf 'late\n' >> "$log_file"
        ) &
        local worker_pid=$!

        if wait_for_process_with_idle_output_watchdog "$worker_pid" 1 "unit-watchdog" "$log_file" "$out_file"; then
            return 1
        else
            rc=$?
        fi

        [ "$rc" -eq 124 ]
        if grep -q '^late$' "$log_file"; then
            return 1
        fi
    )
}

test_unit_timeout_warning_without_timeout_binary() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "$RALPHIE_FILE"
        assert_unit_runtime_isolated

        local warning_output warning_file
        COMMAND_TIMEOUT_SECONDS=30
        TIMEOUT_BINARY_WARNING_EMITTED="false"
        get_timeout_command() { echo ""; }
        warning_file="$(mktemp /tmp/ralphie-timeout-warning-unit.XXXXXX)"
        warn_timeout_binary_unavailable_if_needed >"$warning_file" 2>&1 || true
        warning_output="$(cat "$warning_file")"
        rm -f "$warning_file"
        printf '%s' "$warning_output" | grep -q "no timeout wrapper is installed"
        printf '%s' "$warning_output" | grep -q "brew install coreutils"
        [ "$TIMEOUT_BINARY_WARNING_EMITTED" = "true" ]
    )
}

test_unit_manifest_modes_light_and_deep() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "$RALPHIE_FILE"
        assert_unit_runtime_isolated

        local tmpd manifest_light manifest_deep
        tmpd="$(mktemp -d /tmp/ralphie-manifest-mode-unit.XXXXXX)"
        PROJECT_DIR="$tmpd/project"
        CONFIG_DIR="$PROJECT_DIR/.ralphie"
        mkdir -p "$PROJECT_DIR" "$CONFIG_DIR"

        git -C "$PROJECT_DIR" init >/dev/null 2>&1
        git -C "$PROJECT_DIR" config user.name "Durability Bot"
        git -C "$PROJECT_DIR" config user.email "durability@example.test"
        printf 'alpha\n' > "$PROJECT_DIR/sample.txt"
        git -C "$PROJECT_DIR" add sample.txt
        git -C "$PROJECT_DIR" commit -m "init" >/dev/null 2>&1
        printf 'beta\n' > "$PROJECT_DIR/sample.txt"

        manifest_light="$tmpd/light.manifest"
        manifest_deep="$tmpd/deep.manifest"

        PHASE_MANIFEST_MODE="light"
        phase_capture_worktree_manifest "$manifest_light"
        [ -s "$manifest_light" ]
        grep -q 'type=file' "$manifest_light"
        if grep -q 'hash=' "$manifest_light"; then
            return 1
        fi

        PHASE_MANIFEST_MODE="deep"
        phase_capture_worktree_manifest "$manifest_deep"
        [ -s "$manifest_deep" ]
        grep -q 'hash=' "$manifest_deep"
    )
}

test_unit_markdown_repair_dry_run_backup_and_scope() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "$RALPHIE_FILE"
        assert_unit_runtime_isolated

        local tmpd readme_file note_file diff_rel diff_path backup_rel backup_path
        tmpd="$(mktemp -d /tmp/ralphie-md-repair-unit.XXXXXX)"
        PROJECT_DIR="$tmpd/project"
        CONFIG_DIR="$PROJECT_DIR/.ralphie"
        LOG_DIR="$PROJECT_DIR/logs"
        MARKDOWN_REPAIR_ARTIFACT_DIR="$LOG_DIR/markdown-repair"
        SESSION_ID="mdrepair_unit"
        PLAN_FILE="$PROJECT_DIR/IMPLEMENTATION_PLAN.md"
        RESEARCH_DIR="$PROJECT_DIR/research"
        SPECS_DIR="$PROJECT_DIR/specs"
        SESSION_CHANGED_PATHS_FILE="$CONFIG_DIR/session-changed-paths.txt"
        mkdir -p "$PROJECT_DIR" "$CONFIG_DIR" "$LOG_DIR" "$RESEARCH_DIR" "$SPECS_DIR"

        readme_file="$PROJECT_DIR/README.md"
        note_file="$RESEARCH_DIR/note.md"
        cat > "$readme_file" <<'EOF'
line
assistant to=functions.exec_command
EOF
        cat > "$note_file" <<'EOF'
line
assistant to=functions.exec_command
EOF
        printf 'README.md\n' > "$SESSION_CHANGED_PATHS_FILE"

        AUTO_REPAIR_MARKDOWN_DRY_RUN=true
        AUTO_REPAIR_MARKDOWN_BACKUP=true
        AUTO_REPAIR_MARKDOWN_ONLY_SESSION_CHANGED=true
        sanitize_markdown_artifacts
        grep -q 'assistant to=functions.exec_command' "$readme_file"
        grep -q 'assistant to=functions.exec_command' "$note_file"
        printf '%s' "$MARKDOWN_ARTIFACTS_CLEANED_LIST" | grep -q '\[dry-run\] README.md'
        if printf '%s' "$MARKDOWN_ARTIFACTS_CLEANED_LIST" | grep -q 'note.md'; then
            return 1
        fi
        [ -n "$MARKDOWN_ARTIFACTS_PREVIEW_LIST" ]
        [ -z "$MARKDOWN_ARTIFACTS_BACKUP_LIST" ]
        diff_rel="$(printf '%s\n' "$MARKDOWN_ARTIFACTS_PREVIEW_LIST" | head -n 1)"
        diff_path="$diff_rel"
        case "$diff_path" in
            /*) ;;
            *) diff_path="$PROJECT_DIR/$diff_path" ;;
        esac
        [ -f "$diff_path" ]

        AUTO_REPAIR_MARKDOWN_DRY_RUN=false
        sanitize_markdown_artifacts
        if grep -q 'assistant to=functions.exec_command' "$readme_file"; then
            return 1
        fi
        grep -q 'assistant to=functions.exec_command' "$note_file"
        [ -n "$MARKDOWN_ARTIFACTS_BACKUP_LIST" ]
        backup_rel="$(printf '%s\n' "$MARKDOWN_ARTIFACTS_BACKUP_LIST" | head -n 1)"
        backup_path="$backup_rel"
        case "$backup_path" in
            /*) ;;
            *) backup_path="$PROJECT_DIR/$backup_path" ;;
        esac
        [ -f "$backup_path" ]
    )
}

test_unit_save_state_or_exit_enforces_stop() {
    (
        set -euo pipefail
        local rc=0
        if (
            set -euo pipefail
            # shellcheck source=/dev/null
            source "$RALPHIE_FILE"
            assert_unit_runtime_isolated
            save_state() { return 1; }
            release_lock() { :; }
            notify_event() { return 0; }
            save_state_or_exit "unit checkpoint"
        ); then
            return 1
        else
            rc=$?
        fi
        [ "$rc" -eq 1 ]
    )
}

test_unit_auto_commit_scoped_to_manifest_delta() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "$RALPHIE_FILE"
        assert_unit_runtime_isolated

        local tmpd manifest_before manifest_after
        tmpd="$(mktemp -d /tmp/ralphie-autocommit-scope-unit.XXXXXX)"
        PROJECT_DIR="$tmpd/project"
        CONFIG_DIR="$PROJECT_DIR/.ralphie"
        LOG_DIR="$PROJECT_DIR/logs"
        mkdir -p "$PROJECT_DIR" "$CONFIG_DIR" "$LOG_DIR"

        git -C "$PROJECT_DIR" init >/dev/null 2>&1
        git -C "$PROJECT_DIR" config user.name "Durability Bot"
        git -C "$PROJECT_DIR" config user.email "durability@example.test"
        printf 'base\n' > "$PROJECT_DIR/phase.txt"
        printf 'base\n' > "$PROJECT_DIR/legacy.txt"
        git -C "$PROJECT_DIR" add phase.txt legacy.txt
        git -C "$PROJECT_DIR" commit -m "init" >/dev/null 2>&1

        printf 'legacy-dirty\n' >> "$PROJECT_DIR/legacy.txt"
        manifest_before="$tmpd/manifest.before"
        manifest_after="$tmpd/manifest.after"
        PHASE_MANIFEST_MODE="light"
        phase_capture_worktree_manifest "$manifest_before"

        printf 'phase-change\n' >> "$PROJECT_DIR/phase.txt"
        phase_capture_worktree_manifest "$manifest_after"

        AUTO_COMMIT_SESSION_ENABLED=true
        AUTO_COMMIT_ON_PHASE_PASS=true
        export GIT_AUTHOR_NAME="Durability Bot"
        export GIT_AUTHOR_EMAIL="durability@example.test"
        export GIT_COMMITTER_NAME="Durability Bot"
        export GIT_COMMITTER_EMAIL="durability@example.test"

        commit_phase_approved_changes "build" "test" "$manifest_before" "$manifest_after"

        git -C "$PROJECT_DIR" show --name-only --pretty=format: HEAD > "$tmpd/head-files.txt"
        grep -q '^phase.txt$' "$tmpd/head-files.txt"
        if grep -q '^legacy.txt$' "$tmpd/head-files.txt"; then
            return 1
        fi
        local subject
        subject="$(git -C "$PROJECT_DIR" log -1 --pretty=%s)"
        if printf '%s' "$subject" | grep -qi 'root:'; then
            return 1
        fi
        printf '%s' "$subject" | grep -qi 'repo:1'
        git -C "$PROJECT_DIR" diff --name-only -- . | grep -q '^legacy.txt$'
    )
}

test_integration_consensus_infra_retry_without_attempt_decrement() {
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
export RALPHIE_PHASE_COMPLETION_MAX_ATTEMPTS=2
export RALPHIE_PHASE_COMPLETION_RETRY_DELAY_SECONDS=0
export CONFIDENCE_STAGNATION_LIMIT=3
source ./ralphie.sh
ensure_engines_ready() { CODEX_HEALTHY=true; CLAUDE_HEALTHY=false; ACTIVE_ENGINE=codex; ACTIVE_CMD=codex; return 0; }
probe_engine_capabilities() { CODEX_CAP_OUTPUT_LAST_MESSAGE=1; CODEX_CAP_YOLO_FLAG=1; CLAUDE_CAP_PRINT=1; ENGINE_CAPABILITIES_PROBED=true; return 0; }
run_first_deploy_engine_override_wizard() { return 0; }
run_first_deploy_notification_wizard() { return 0; }
run_startup_operational_probe() { return 0; }
build_is_preapproved() { return 0; }
__agent_calls=0
run_agent_with_prompt() {
    local _prompt="$1" log_file="$2" output_file="$3"
    __agent_calls=$((__agent_calls + 1))
    printf 'agent-call-%s\n' "$__agent_calls" >> agent-calls.log
    printf 'ok\n' > "$log_file"
    printf 'ok\n' > "$output_file"
    return 0
}
run_handoff_validation() { LAST_HANDOFF_SCORE=95; LAST_HANDOFF_VERDICT=GO; LAST_HANDOFF_GAPS=none; return 0; }
__plan_consensus_calls=0
run_swarm_consensus() {
    local stage="$1"
    local base="${stage%-gate}"
    if [ "$base" = "plan" ] && [ "$__plan_consensus_calls" -lt 2 ]; then
        __plan_consensus_calls=$((__plan_consensus_calls + 1))
        LAST_CONSENSUS_SCORE=0
        LAST_CONSENSUS_PASS=false
        LAST_CONSENSUS_RESPONDED_VOTES=0
        LAST_CONSENSUS_SUMMARY="transient reviewer outage"
        LAST_CONSENSUS_NEXT_PHASE="build"
        LAST_CONSENSUS_NEXT_PHASE_REASON="infra retry"
        LAST_CONSENSUS_FAILURE_KIND="infra"
        LAST_CONSENSUS_FAILURE_REASON="reviewer transport timeout"
        CONSENSUS_NO_ENGINES=true
        return 1
    fi
    LAST_CONSENSUS_SCORE=95
    LAST_CONSENSUS_PASS=true
    LAST_CONSENSUS_RESPONDED_VOTES=3
    LAST_CONSENSUS_SUMMARY="consensus pass"
    LAST_CONSENSUS_NEXT_PHASE="$(phase_default_next "$base")"
    LAST_CONSENSUS_NEXT_PHASE_REASON="pass"
    LAST_CONSENSUS_FAILURE_KIND="none"
    LAST_CONSENSUS_FAILURE_REASON=""
    CONSENSUS_NO_ENGINES=false
    return 0
}
main --no-resume > "$PWD/run.out" 2> "$PWD/run.err"
grep -q "Retrying consensus without consuming phase attempt" "$PWD/run.out" "$PWD/run.err"
grep -q "All phases completed. Session done." "$PWD/run.out"
[ "$(wc -l < "$PWD/agent-calls.log" | tr -d ' ')" -eq 6 ]
EOF
    chmod +x "$ws/harness.sh"
    "$ws/harness.sh"
}

test_integration_unlimited_phase_attempts_stagnation_guard() {
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
export RALPHIE_PHASE_COMPLETION_MAX_ATTEMPTS=0
export RALPHIE_PHASE_COMPLETION_RETRY_DELAY_SECONDS=0
export CONFIDENCE_STAGNATION_LIMIT=2
source ./ralphie.sh
ensure_engines_ready() { CODEX_HEALTHY=true; CLAUDE_HEALTHY=false; ACTIVE_ENGINE=codex; ACTIVE_CMD=codex; return 0; }
probe_engine_capabilities() { CODEX_CAP_OUTPUT_LAST_MESSAGE=1; CODEX_CAP_YOLO_FLAG=1; CLAUDE_CAP_PRINT=1; ENGINE_CAPABILITIES_PROBED=true; return 0; }
run_first_deploy_engine_override_wizard() { return 0; }
run_first_deploy_notification_wizard() { return 0; }
run_startup_operational_probe() { return 0; }
build_is_preapproved() { return 0; }
__agent_calls=0
run_agent_with_prompt() {
    local _prompt="$1" log_file="$2" output_file="$3"
    __agent_calls=$((__agent_calls + 1))
    printf 'agent-call-%s\n' "$__agent_calls" >> agent-calls.log
    printf 'forced failure\n' > "$log_file"
    printf '' > "$output_file"
    return 1
}
run_handoff_validation() { return 1; }
run_swarm_consensus() { return 1; }
main --no-resume > "$PWD/run.out" 2> "$PWD/run.err" || true
grep -q "stagnated for" "$PWD/run.out" "$PWD/run.err"
grep -q "RB_PHASE_RETRY_STAGNATION" "$PWD/.ralphie/reasons.log"
[ "$(wc -l < "$PWD/agent-calls.log" | tr -d ' ')" -eq 2 ]
EOF
    chmod +x "$ws/harness.sh"
    "$ws/harness.sh"
}

test_integration_unlimited_routing_stagnation_guard() {
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
export RALPHIE_MAX_CONSENSUS_ROUTING_ATTEMPTS=0
export CONFIDENCE_STAGNATION_LIMIT=2
export RALPHIE_PHASE_COMPLETION_RETRY_DELAY_SECONDS=0
source ./ralphie.sh
ensure_engines_ready() { CODEX_HEALTHY=true; CLAUDE_HEALTHY=false; ACTIVE_ENGINE=codex; ACTIVE_CMD=codex; return 0; }
probe_engine_capabilities() { CODEX_CAP_OUTPUT_LAST_MESSAGE=1; CODEX_CAP_YOLO_FLAG=1; CLAUDE_CAP_PRINT=1; ENGINE_CAPABILITIES_PROBED=true; return 0; }
run_first_deploy_engine_override_wizard() { return 0; }
run_first_deploy_notification_wizard() { return 0; }
run_startup_operational_probe() { return 0; }
build_is_preapproved() { return 0; }
run_agent_with_prompt() {
    local _prompt="$1" log_file="$2" output_file="$3"
    printf 'ok\n' > "$log_file"
    printf 'ok\n' > "$output_file"
    return 0
}
run_handoff_validation() { LAST_HANDOFF_SCORE=95; LAST_HANDOFF_VERDICT=GO; LAST_HANDOFF_GAPS=none; return 0; }
run_swarm_consensus() {
    local stage="$1"
    local base="${stage%-gate}"
    LAST_CONSENSUS_SCORE=95
    LAST_CONSENSUS_PASS=true
    LAST_CONSENSUS_RESPONDED_VOTES=3
    LAST_CONSENSUS_SUMMARY="routing loop stub"
    if [ "$base" = "build" ]; then
        LAST_CONSENSUS_NEXT_PHASE="plan"
        LAST_CONSENSUS_NEXT_PHASE_REASON="loop"
    else
        LAST_CONSENSUS_NEXT_PHASE="$(phase_default_next "$base")"
        LAST_CONSENSUS_NEXT_PHASE_REASON="forward"
    fi
    return 0
}
main --no-resume > "$PWD/run.out" 2> "$PWD/run.err" || true
grep -q "routing stagnated" "$PWD/run.out" "$PWD/run.err"
grep -q "RB_ROUTING_STAGNATION" "$PWD/.ralphie/reasons.log"
EOF
    chmod +x "$ws/harness.sh"
    "$ws/harness.sh"
}

test_integration_terminal_done_guard_requires_lint_and_document() {
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
export RALPHIE_REQUIRE_LINT_BEFORE_DONE=true
export RALPHIE_REQUIRE_DOCUMENT_BEFORE_DONE=true
source ./ralphie.sh
ensure_engines_ready() { CODEX_HEALTHY=true; CLAUDE_HEALTHY=false; ACTIVE_ENGINE=codex; ACTIVE_CMD=codex; return 0; }
probe_engine_capabilities() { CODEX_CAP_OUTPUT_LAST_MESSAGE=1; CODEX_CAP_YOLO_FLAG=1; CLAUDE_CAP_PRINT=1; ENGINE_CAPABILITIES_PROBED=true; return 0; }
run_first_deploy_engine_override_wizard() { return 0; }
run_first_deploy_notification_wizard() { return 0; }
run_startup_operational_probe() { return 0; }
build_is_preapproved() { return 0; }
run_agent_with_prompt() {
    local _prompt="$1" log_file="$2" output_file="$3"
    local phase_name
    phase_name="$(basename "$log_file" | cut -d'_' -f1)"
    printf '%s\n' "$phase_name" >> "$PWD/phases.log"
    printf 'ok\n' > "$log_file"
    printf 'ok\n' > "$output_file"
    printf '%s-mut\n' "$phase_name" >> "$PWD/mutations.log"
    return 0
}
run_handoff_validation() { LAST_HANDOFF_SCORE=95; LAST_HANDOFF_VERDICT=GO; LAST_HANDOFF_GAPS=none; return 0; }
run_swarm_consensus() {
    local stage="$1"
    local base="${stage%-gate}"
    LAST_CONSENSUS_SCORE=95
    LAST_CONSENSUS_PASS=true
    LAST_CONSENSUS_RESPONDED_VOTES=3
    LAST_CONSENSUS_SUMMARY="terminal done guard stub"
    case "$base" in
        test|lint|document)
            LAST_CONSENSUS_NEXT_PHASE="done"
            LAST_CONSENSUS_NEXT_PHASE_REASON="reviewers said done"
            ;;
        *)
            LAST_CONSENSUS_NEXT_PHASE="$(phase_default_next "$base")"
            LAST_CONSENSUS_NEXT_PHASE_REASON="forward"
            ;;
    esac
    return 0
}
main --no-resume > "$PWD/run.out" 2> "$PWD/run.err"
grep -q "Terminal guard remapped next phase: done -> lint" "$PWD/run.out" "$PWD/run.err"
grep -q "Terminal guard remapped next phase: done -> document" "$PWD/run.out" "$PWD/run.err"
grep -q ">>> Entering phase 'lint' <<<" "$PWD/run.out"
grep -q ">>> Entering phase 'document' <<<" "$PWD/run.out"
grep -q "All phases completed. Session done." "$PWD/run.out"
grep -q 'CURRENT_PHASE="done"' "$PWD/.ralphie/state.env"
if grep -q '^refactor$' "$PWD/phases.log"; then
    exit 1
fi
EOF
    chmod +x "$ws/harness.sh"
    "$ws/harness.sh"
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
    local stage="$1"
    local base="${stage%-gate}"
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
    local stage="$1"
    local base="${stage%-gate}"
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
    local stage="$1"
    local base="${stage%-gate}"
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
    run_case "unit_bootstrap_dense_reflection_and_personas" test_unit_bootstrap_dense_reflection_and_personas
    run_case "unit_bootstrap_alignment_loop_modify_rerun_dismiss" test_unit_bootstrap_alignment_loop_modify_rerun_dismiss
    run_case "unit_bootstrap_accept_gate_and_no_change_guard" test_unit_bootstrap_accept_gate_and_no_change_guard
    run_case "unit_bootstrap_accept_blocked_no_change_guard" test_unit_bootstrap_accept_blocked_no_change_guard
    run_case "unit_append_bootstrap_context_includes_arch_and_tech" test_unit_append_bootstrap_context_includes_arch_and_tech
    run_case "unit_idle_output_watchdog_recycles_hung_process" test_unit_idle_output_watchdog_recycles_hung_process
    run_case "unit_timeout_warning_without_timeout_binary" test_unit_timeout_warning_without_timeout_binary
    run_case "unit_manifest_modes_light_and_deep" test_unit_manifest_modes_light_and_deep
    run_case "unit_markdown_repair_dry_run_backup_and_scope" test_unit_markdown_repair_dry_run_backup_and_scope
    run_case "unit_save_state_or_exit_enforces_stop" test_unit_save_state_or_exit_enforces_stop
    run_case "unit_auto_commit_scoped_to_manifest_delta" test_unit_auto_commit_scoped_to_manifest_delta
    run_case "integration_happy_path" test_integration_happy_path
    run_case "integration_consensus_infra_retry_without_attempt_decrement" test_integration_consensus_infra_retry_without_attempt_decrement
    run_case "integration_unlimited_phase_attempts_stagnation_guard" test_integration_unlimited_phase_attempts_stagnation_guard
    run_case "integration_unlimited_routing_stagnation_guard" test_integration_unlimited_routing_stagnation_guard
    run_case "integration_terminal_done_guard_requires_lint_and_document" test_integration_terminal_done_guard_requires_lint_and_document
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
