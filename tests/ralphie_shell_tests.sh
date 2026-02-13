#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export RALPHIE_LIB=1
# shellcheck disable=SC1091
source "$ROOT_DIR/ralphie.sh"

# Isolate runtime/config artifacts from the repo's real .ralphie/ directory.
TEST_TMP_ROOT="$(mktemp -d)"
CONFIG_DIR="$TEST_TMP_ROOT/.ralphie"
CONFIG_FILE="$CONFIG_DIR/config.env"
LOCK_FILE="$CONFIG_DIR/run.lock"
REASON_LOG_FILE="$CONFIG_DIR/reasons.log"
GATE_FEEDBACK_FILE="$CONFIG_DIR/last_gate_feedback.md"
STATE_FILE="$CONFIG_DIR/state.env"
READY_ARCHIVE_DIR="$CONFIG_DIR/ready-archives"
mkdir -p "$CONFIG_DIR" "$READY_ARCHIVE_DIR"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

FAILURES=0

pass() {
    echo "PASS: $1"
}

fail() {
    echo "FAIL: $1"
    FAILURES=$((FAILURES + 1))
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local label="$3"
    if [ "$expected" = "$actual" ]; then
        pass "$label"
    else
        fail "$label (expected='$expected' actual='$actual')"
    fi
}

assert_true() {
    local label="$1"
    shift
    if "$@"; then
        pass "$label"
    else
        fail "$label"
    fi
}

assert_false() {
    local label="$1"
    shift
    if "$@"; then
        fail "$label"
    else
        pass "$label"
    fi
}

test_confidence_parsing() {
    local tmp
    tmp="$(mktemp)"
    cat > "$tmp" <<'EOF'
<confidence>150</confidence>
<needs_human>false</needs_human>
<human_question></human_question>
EOF
    assert_eq "100" "$(extract_confidence_value "$tmp" "$tmp")" "confidence clamps to 100"

    cat > "$tmp" <<'EOF'
<confidence>12</confidence>
EOF
    assert_eq "12" "$(extract_confidence_value "$tmp" "$tmp")" "confidence parses normal value"

    cat > "$tmp" <<'EOF'
no tags
EOF
    assert_eq "0" "$(extract_confidence_value "$tmp" "$tmp")" "confidence defaults to 0 when missing"
    rm -f "$tmp"
}

test_prepare_tag_detection() {
    local tmp
    tmp="$(mktemp)"
    cat > "$tmp" <<'EOF'
<confidence>88</confidence>
<needs_human>false</needs_human>
<human_question></human_question>
EOF
    assert_true "prepare status tags detected" output_has_prepare_status_tags "$tmp"

    cat > "$tmp" <<'EOF'
<confidence>88</confidence>
EOF
    assert_false "prepare status tags reject incomplete tags" output_has_prepare_status_tags "$tmp"
    rm -f "$tmp"
}

test_prepare_tag_fallback_parsing() {
    local tmp_out tmp_log
    tmp_out="$(mktemp)"
    tmp_log="$(mktemp)"

    cat > "$tmp_out" <<'EOF'
no tags here
EOF
    cat > "$tmp_log" <<'EOF'
<confidence>77</confidence>
<needs_human>true</needs_human>
<human_question>Need input?</human_question>
EOF
    assert_eq "77" "$(extract_confidence_value "$tmp_out" "$tmp_log")" "confidence falls back to log file tags"
    assert_eq "true" "$(extract_needs_human_flag "$tmp_out" "$tmp_log")" "needs_human falls back to log file tags"
    assert_eq "Need input?" "$(extract_human_question "$tmp_out" "$tmp_log")" "human_question falls back to log file tags"

    cat > "$tmp_out" <<'EOF'
<confidence>55</confidence>
EOF
    assert_eq "55" "$(extract_tag_value "confidence" "$tmp_out" "$tmp_log")" "extract_tag_value honors ordered candidates"

    rm -f "$tmp_out" "$tmp_log"
}

test_completion_signal_detection() {
    local tmp_log tmp_out
    tmp_log="$(mktemp)"
    tmp_out="$(mktemp)"

    cat > "$tmp_out" <<'EOF'
<promise>DONE</promise>
EOF
    assert_eq "<promise>DONE</promise>" "$(detect_completion_signal "$tmp_log" "$tmp_out")" "completion signal detected from output file"

    cat > "$tmp_out" <<'EOF'
prefix <promise>DONE</promise> suffix
EOF
    assert_eq "" "$(detect_completion_signal "$tmp_log" "$tmp_out")" "completion signal rejects non-line-anchored tag"

    rm -f "$tmp_log" "$tmp_out"
}

test_fallback_engine_selection() {
    local tmpbin old_path
    tmpbin="$(mktemp -d)"
    old_path="$PATH"

    cat > "$tmpbin/codex-mock" <<'EOF'
#!/usr/bin/env bash
echo codex-mock
EOF
    cat > "$tmpbin/claude-mock" <<'EOF'
#!/usr/bin/env bash
echo claude-mock
EOF
    chmod +x "$tmpbin/codex-mock" "$tmpbin/claude-mock"

    PATH="$tmpbin:$PATH"
    CODEX_CMD="codex-mock"
    CLAUDE_CMD="claude-mock"

    assert_eq "claude" "$(pick_fallback_engine "prepare" "codex")" "fallback picks claude from codex"
    assert_eq "codex" "$(pick_fallback_engine "prepare" "claude")" "fallback picks codex from claude"

    PATH="$old_path"
    rm -rf "$tmpbin"
}

test_effective_lock_wait_seconds() {
    local old_lock_wait old_timeout old_normal_wait
    old_lock_wait="${LOCK_WAIT_SECONDS:-0}"
    old_timeout="${COMMAND_TIMEOUT_SECONDS:-0}"
    old_normal_wait="${NORMAL_WAIT:-2}"

    LOCK_WAIT_SECONDS=30
    COMMAND_TIMEOUT_SECONDS=120
    NORMAL_WAIT=2
    assert_eq "127" "$(effective_lock_wait_seconds)" "lock wait auto-bumps above configured timeout"

    LOCK_WAIT_SECONDS=180
    COMMAND_TIMEOUT_SECONDS=120
    NORMAL_WAIT=2
    assert_eq "180" "$(effective_lock_wait_seconds)" "lock wait keeps larger configured value"

    LOCK_WAIT_SECONDS=0
    COMMAND_TIMEOUT_SECONDS=120
    NORMAL_WAIT=2
    assert_eq "0" "$(effective_lock_wait_seconds)" "lock wait remains disabled when set to zero"

    LOCK_WAIT_SECONDS="$old_lock_wait"
    COMMAND_TIMEOUT_SECONDS="$old_timeout"
    NORMAL_WAIT="$old_normal_wait"
}

test_prompt_yes_no_eof_defaults() {
    local result
    result="$(prompt_yes_no "EOF defaults to yes" "y" </dev/null)"
    assert_eq "true" "$result" "prompt_yes_no returns true on EOF with yes default"

    result="$(prompt_yes_no "EOF defaults to no" "n" </dev/null)"
    assert_eq "false" "$result" "prompt_yes_no returns false on EOF with no default"
}

test_prompt_line_eof_defaults() {
    local result
    result="$(prompt_line "EOF defaults line" "default" </dev/null)"
    assert_eq "default" "$result" "prompt_line returns default on EOF"
}

test_prompt_optional_line_eof_defaults() {
    local result
    result="$(prompt_optional_line "EOF defaults optional line" "default" </dev/null)"
    assert_eq "default" "$result" "prompt_optional_line returns default on EOF"

    result="$(prompt_optional_line "EOF defaults optional line empty" "" </dev/null)"
    assert_eq "" "$result" "prompt_optional_line returns empty default on EOF"
}

test_interrupt_handler_non_interactive_path() {
    local old_non_interactive old_interrupt_menu old_lock_file old_config_dir
    old_non_interactive="$NON_INTERACTIVE"
    old_interrupt_menu="$INTERRUPT_MENU_ENABLED"
    old_lock_file="$LOCK_FILE"
    old_config_dir="$CONFIG_DIR"

    local tmpdir
    tmpdir="$(mktemp -d)"
    CONFIG_DIR="$tmpdir/.ralphie"
    LOCK_FILE="$CONFIG_DIR/run.lock"
    mkdir -p "$CONFIG_DIR"

    NON_INTERACTIVE=true
    INTERRUPT_MENU_ENABLED=true

    local output rc
    set +e
    output="$( ( handle_interrupt ) 2>&1 )"
    rc=$?
    set -e

    assert_eq "130" "$rc" "interrupt handler exits in non-interactive mode"
    assert_true "interrupt handler emits interrupted message" rg -q "Interrupted. Releasing lock and exiting." <<<"$output"

    NON_INTERACTIVE="$old_non_interactive"
    INTERRUPT_MENU_ENABLED="$old_interrupt_menu"
    LOCK_FILE="$old_lock_file"
    CONFIG_DIR="$old_config_dir"
    rm -rf "$tmpdir"
}

test_prompt_file_mapping() {
    assert_eq "$PROMPT_BUILD_FILE" "$(prompt_file_for_mode build)" "prompt mapping build"
    assert_eq "$PROMPT_PLAN_FILE" "$(prompt_file_for_mode plan)" "prompt mapping plan"
    assert_eq "$PROMPT_PREPARE_FILE" "$(prompt_file_for_mode prepare)" "prompt mapping prepare"
    assert_eq "$PROMPT_TEST_FILE" "$(prompt_file_for_mode test)" "prompt mapping test"
    assert_eq "$PROMPT_REFACTOR_FILE" "$(prompt_file_for_mode refactor)" "prompt mapping refactor"
    assert_eq "$PROMPT_LINT_FILE" "$(prompt_file_for_mode lint)" "prompt mapping lint"
    assert_eq "$PROMPT_DOCUMENT_FILE" "$(prompt_file_for_mode document)" "prompt mapping document"
    assert_eq "" "$(prompt_file_for_mode unknown)" "prompt mapping unknown"
}

test_plan_task_detection_accepts_numbered_tasks() {
    local tmpdir old_plan_file old_has_plan_tasks
    tmpdir="$(mktemp -d)"
    old_plan_file="$PLAN_FILE"
    old_has_plan_tasks="$HAS_PLAN_TASKS"

    PLAN_FILE="$tmpdir/IMPLEMENTATION_PLAN.md"
    cat >"$PLAN_FILE" <<'EOF'
# Implementation Plan

## Goal
Improve reliability.

## Validation
1. Run tests.

1. Implement thing
2. Verify thing
EOF

    HAS_PLAN_TASKS=false
    check_plan_tasks
    assert_eq "true" "$HAS_PLAN_TASKS" "plan task detection accepts numbered tasks"

    PLAN_FILE="$old_plan_file"
    HAS_PLAN_TASKS="$old_has_plan_tasks"
    rm -rf "$tmpdir"
}

test_count_pending_human_requests_missing_file() {
    local tmpdir old_human_instructions_file old_human_instructions_rel
    tmpdir="$(mktemp -d)"
    old_human_instructions_file="$HUMAN_INSTRUCTIONS_FILE"
    old_human_instructions_rel="$HUMAN_INSTRUCTIONS_REL"

    HUMAN_INSTRUCTIONS_REL="HUMAN_INSTRUCTIONS.md"
    HUMAN_INSTRUCTIONS_FILE="$tmpdir/HUMAN_INSTRUCTIONS.md"

    assert_eq "0" "$(count_pending_human_requests)" "pending human requests returns 0 when file missing"

    HUMAN_INSTRUCTIONS_FILE="$old_human_instructions_file"
    HUMAN_INSTRUCTIONS_REL="$old_human_instructions_rel"
    rm -rf "$tmpdir"
}

test_count_pending_human_requests_case_insensitive() {
    local tmpdir old_human_instructions_file old_human_instructions_rel
    tmpdir="$(mktemp -d)"
    old_human_instructions_file="$HUMAN_INSTRUCTIONS_FILE"
    old_human_instructions_rel="$HUMAN_INSTRUCTIONS_REL"

    HUMAN_INSTRUCTIONS_REL="HUMAN_INSTRUCTIONS.md"
    HUMAN_INSTRUCTIONS_FILE="$tmpdir/HUMAN_INSTRUCTIONS.md"
    cat >"$HUMAN_INSTRUCTIONS_FILE" <<'EOF'
# Human Instructions Queue

## 2026-02-13 00:00:00
- Request: A
- Status: NEW

## 2026-02-13 00:00:01
- Request: B
- status: new

## 2026-02-13 00:00:02
- Request: C
- STATUS :   NEW

## 2026-02-13 00:00:03
- Request: D
- Status: DONE
EOF

    assert_eq "3" "$(count_pending_human_requests)" "pending human requests count is case-insensitive and whitespace tolerant"

    HUMAN_INSTRUCTIONS_FILE="$old_human_instructions_file"
    HUMAN_INSTRUCTIONS_REL="$old_human_instructions_rel"
    rm -rf "$tmpdir"
}

test_check_human_requests_sets_flag() {
    local tmpdir old_human_instructions_file old_human_instructions_rel old_has_human_requests
    tmpdir="$(mktemp -d)"
    old_human_instructions_file="$HUMAN_INSTRUCTIONS_FILE"
    old_human_instructions_rel="$HUMAN_INSTRUCTIONS_REL"
    old_has_human_requests="$HAS_HUMAN_REQUESTS"

    HUMAN_INSTRUCTIONS_REL="HUMAN_INSTRUCTIONS.md"
    HUMAN_INSTRUCTIONS_FILE="$tmpdir/HUMAN_INSTRUCTIONS.md"
    cat >"$HUMAN_INSTRUCTIONS_FILE" <<'EOF'
- Status: NEW
EOF

    check_human_requests
    assert_eq "true" "$HAS_HUMAN_REQUESTS" "human request detection sets HAS_HUMAN_REQUESTS when pending requests exist"

    HUMAN_INSTRUCTIONS_FILE="$old_human_instructions_file"
    HUMAN_INSTRUCTIONS_REL="$old_human_instructions_rel"
    HAS_HUMAN_REQUESTS="$old_has_human_requests"
    rm -rf "$tmpdir"
}

test_prepare_prompt_for_iteration_injects_human_queue_when_present() {
    local tmpdir old_log_dir old_human_instructions_file old_human_instructions_rel old_agent_source_map_file old_binary_steering_map_file old_gate_feedback_file old_context_file old_mode
    tmpdir="$(mktemp -d)"
    old_log_dir="$LOG_DIR"
    old_human_instructions_file="$HUMAN_INSTRUCTIONS_FILE"
    old_human_instructions_rel="$HUMAN_INSTRUCTIONS_REL"
    old_agent_source_map_file="$AGENT_SOURCE_MAP_FILE"
    old_binary_steering_map_file="$BINARY_STEERING_MAP_FILE"
    old_gate_feedback_file="$GATE_FEEDBACK_FILE"
    old_context_file="${CONTEXT_FILE:-}"
    old_mode="$MODE"

    LOG_DIR="$tmpdir/logs"
    mkdir -p "$LOG_DIR"

    local base_prompt human_file out_path
    base_prompt="$tmpdir/base_prompt.md"
    human_file="$tmpdir/HUMAN_INSTRUCTIONS.md"

    cat >"$base_prompt" <<'EOF'
# Base prompt
EOF
    cat >"$human_file" <<'EOF'
# Human Instructions Queue
## 2026-02-13 00:00:00
- Request: Test prompt injection
- Priority: high
- Status: NEW

SENTINEL_HUMAN_QUEUE_LINE
EOF

    HUMAN_INSTRUCTIONS_REL="HUMAN_INSTRUCTIONS.md"
    HUMAN_INSTRUCTIONS_FILE="$human_file"
    CONTEXT_FILE=""
    AGENT_SOURCE_MAP_FILE="$tmpdir/no-agent-source-map.yaml"
    BINARY_STEERING_MAP_FILE="$tmpdir/no-binary-steering-map.yaml"
    GATE_FEEDBACK_FILE="$tmpdir/no-gate-feedback.md"
    MODE="build"

    out_path="$(prepare_prompt_for_iteration "$base_prompt" "human-queue")"

    assert_true "prompt injection writes augmented prompt" test -f "$out_path"
    assert_true "prompt injection includes human queue header" rg -q "## Human Priority Queue" "$out_path"
    assert_true "prompt injection includes human queue contents" rg -q "SENTINEL_HUMAN_QUEUE_LINE" "$out_path"

    LOG_DIR="$old_log_dir"
    HUMAN_INSTRUCTIONS_FILE="$old_human_instructions_file"
    HUMAN_INSTRUCTIONS_REL="$old_human_instructions_rel"
    AGENT_SOURCE_MAP_FILE="$old_agent_source_map_file"
    BINARY_STEERING_MAP_FILE="$old_binary_steering_map_file"
    GATE_FEEDBACK_FILE="$old_gate_feedback_file"
    CONTEXT_FILE="$old_context_file"
    MODE="$old_mode"
    rm -rf "$tmpdir"
}

test_prepare_prompt_for_iteration_skips_human_queue_when_missing() {
    local tmpdir old_human_instructions_file old_human_instructions_rel old_agent_source_map_file old_binary_steering_map_file old_gate_feedback_file old_context_file old_mode
    tmpdir="$(mktemp -d)"
    old_human_instructions_file="$HUMAN_INSTRUCTIONS_FILE"
    old_human_instructions_rel="$HUMAN_INSTRUCTIONS_REL"
    old_agent_source_map_file="$AGENT_SOURCE_MAP_FILE"
    old_binary_steering_map_file="$BINARY_STEERING_MAP_FILE"
    old_gate_feedback_file="$GATE_FEEDBACK_FILE"
    old_context_file="${CONTEXT_FILE:-}"
    old_mode="$MODE"

    local base_prompt out_path
    base_prompt="$tmpdir/base_prompt.md"
    cat >"$base_prompt" <<'EOF'
# Base prompt
EOF

    HUMAN_INSTRUCTIONS_REL="HUMAN_INSTRUCTIONS.md"
    HUMAN_INSTRUCTIONS_FILE="$tmpdir/missing-human-instructions.md"
    CONTEXT_FILE=""
    AGENT_SOURCE_MAP_FILE="$tmpdir/no-agent-source-map.yaml"
    BINARY_STEERING_MAP_FILE="$tmpdir/no-binary-steering-map.yaml"
    GATE_FEEDBACK_FILE="$tmpdir/no-gate-feedback.md"
    MODE="build"

    out_path="$(prepare_prompt_for_iteration "$base_prompt" "no-human")"

    assert_eq "$base_prompt" "$out_path" "prompt injection returns base prompt when no augmentation is needed"
    assert_false "prompt injection does not include human queue header when missing" rg -q "## Human Priority Queue" "$out_path"

    HUMAN_INSTRUCTIONS_FILE="$old_human_instructions_file"
    HUMAN_INSTRUCTIONS_REL="$old_human_instructions_rel"
    AGENT_SOURCE_MAP_FILE="$old_agent_source_map_file"
    BINARY_STEERING_MAP_FILE="$old_binary_steering_map_file"
    GATE_FEEDBACK_FILE="$old_gate_feedback_file"
    CONTEXT_FILE="$old_context_file"
    MODE="$old_mode"
    rm -rf "$tmpdir"
}

test_capture_human_priorities_fails_non_interactive_with_reason_code() {
    local tmpdir old_non_interactive old_config_dir old_reason_log_file old_human_instructions_file old_human_instructions_rel
    tmpdir="$(mktemp -d)"
    old_non_interactive="$NON_INTERACTIVE"
    old_config_dir="$CONFIG_DIR"
    old_reason_log_file="$REASON_LOG_FILE"
    old_human_instructions_file="$HUMAN_INSTRUCTIONS_FILE"
    old_human_instructions_rel="$HUMAN_INSTRUCTIONS_REL"

    CONFIG_DIR="$tmpdir/.ralphie"
    REASON_LOG_FILE="$CONFIG_DIR/reasons.log"
    mkdir -p "$CONFIG_DIR"

    HUMAN_INSTRUCTIONS_REL="HUMAN_INSTRUCTIONS.md"
    HUMAN_INSTRUCTIONS_FILE="$tmpdir/HUMAN_INSTRUCTIONS.md"
    NON_INTERACTIVE=true

    local output rc
    set +e
    output="$(capture_human_priorities 2>&1)"
    rc=$?
    set -e

    assert_eq "1" "$rc" "human capture exits non-zero in non-interactive mode"
    assert_true "human capture emits deterministic reason code" rg -q "reason_code=RB_HUMAN_MODE_NON_INTERACTIVE" <<<"$output"
    assert_false "human capture does not create a queue file in non-interactive mode" test -f "$HUMAN_INSTRUCTIONS_FILE"
    assert_true "reason log records non-interactive failure code" rg -q "reason_code=RB_HUMAN_MODE_NON_INTERACTIVE" "$REASON_LOG_FILE"

    NON_INTERACTIVE="$old_non_interactive"
    CONFIG_DIR="$old_config_dir"
    REASON_LOG_FILE="$old_reason_log_file"
    HUMAN_INSTRUCTIONS_FILE="$old_human_instructions_file"
    HUMAN_INSTRUCTIONS_REL="$old_human_instructions_rel"
    rm -rf "$tmpdir"
}

test_notify_human_none_is_noop() {
    local old_channel old_token old_chat old_webhook
    old_channel="$HUMAN_NOTIFY_CHANNEL"
    old_token="$TELEGRAM_BOT_TOKEN"
    old_chat="$TELEGRAM_CHAT_ID"
    old_webhook="$DISCORD_WEBHOOK_URL"

    HUMAN_NOTIFY_CHANNEL="NoNe"
    TELEGRAM_BOT_TOKEN="TEST_TELEGRAM_TOKEN_SHOULD_NOT_APPEAR"
    TELEGRAM_CHAT_ID="123"
    DISCORD_WEBHOOK_URL="https://example.invalid/TEST_DISCORD_WEBHOOK_SHOULD_NOT_APPEAR"

    local output rc
    set +e
    output="$(notify_human "noop-title" "noop-body" 2>&1)"
    rc=$?
    set -e

    assert_eq "0" "$rc" "notify_human none returns success"
    assert_eq "" "$output" "notify_human none emits no output"

    HUMAN_NOTIFY_CHANNEL="$old_channel"
    TELEGRAM_BOT_TOKEN="$old_token"
    TELEGRAM_CHAT_ID="$old_chat"
    DISCORD_WEBHOOK_URL="$old_webhook"
}

test_notify_human_terminal_emits_messages() {
    local old_channel
    old_channel="$HUMAN_NOTIFY_CHANNEL"

    HUMAN_NOTIFY_CHANNEL="TeRmInAl"

    local output rc
    set +e
    output="$(notify_human "TITLE_SENTINEL" "BODY_SENTINEL" 2>&1)"
    rc=$?
    set -e

    assert_eq "0" "$rc" "notify_human terminal returns success"
    assert_true "notify_human terminal emits title" rg -qF "TITLE_SENTINEL" <<<"$output"
    assert_true "notify_human terminal emits body" rg -qF "BODY_SENTINEL" <<<"$output"

    HUMAN_NOTIFY_CHANNEL="$old_channel"
}

test_notify_human_telegram_missing_env_fails() {
    local old_channel old_token old_chat
    old_channel="$HUMAN_NOTIFY_CHANNEL"
    old_token="$TELEGRAM_BOT_TOKEN"
    old_chat="$TELEGRAM_CHAT_ID"

    HUMAN_NOTIFY_CHANNEL="TeLeGrAm"

    TELEGRAM_BOT_TOKEN=""
    TELEGRAM_CHAT_ID="123"
    local output rc
    set +e
    output="$(notify_human "t" "b" 2>&1)"
    rc=$?
    set -e
    assert_eq "1" "$rc" "notify_human telegram fails when TELEGRAM_BOT_TOKEN is missing"
    assert_true "notify_human telegram warns missing env vars" rg -q "Telegram notify selected, but TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID are missing" <<<"$output"

    TELEGRAM_BOT_TOKEN="TEST_TELEGRAM_TOKEN_SHOULD_NOT_APPEAR"
    TELEGRAM_CHAT_ID=""
    set +e
    output="$(notify_human "t" "b" 2>&1)"
    rc=$?
    set -e
    assert_eq "1" "$rc" "notify_human telegram fails when TELEGRAM_CHAT_ID is missing"
    assert_true "notify_human telegram warns missing env vars (chat id missing)" rg -q "Telegram notify selected, but TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID are missing" <<<"$output"
    assert_false "notify_human telegram missing env does not leak token" rg -qF "TEST_TELEGRAM_TOKEN_SHOULD_NOT_APPEAR" <<<"$output"

    HUMAN_NOTIFY_CHANNEL="$old_channel"
    TELEGRAM_BOT_TOKEN="$old_token"
    TELEGRAM_CHAT_ID="$old_chat"
}

test_notify_human_discord_missing_env_fails() {
    local old_channel old_webhook
    old_channel="$HUMAN_NOTIFY_CHANNEL"
    old_webhook="$DISCORD_WEBHOOK_URL"

    HUMAN_NOTIFY_CHANNEL="DiScOrD"
    DISCORD_WEBHOOK_URL=""

    local output rc
    set +e
    output="$(notify_human "t" "b" 2>&1)"
    rc=$?
    set -e

    assert_eq "1" "$rc" "notify_human discord fails when DISCORD_WEBHOOK_URL is missing"
    assert_true "notify_human discord warns missing webhook env var" rg -q "Discord notify selected, but DISCORD_WEBHOOK_URL is missing" <<<"$output"

    HUMAN_NOTIFY_CHANNEL="$old_channel"
    DISCORD_WEBHOOK_URL="$old_webhook"
}

test_notify_human_fails_when_curl_missing_from_path() {
    local tmpdir
    tmpdir="$(mktemp -d)"

    local token webhook tr_bin
    token="TEST_TELEGRAM_TOKEN_SHOULD_NOT_APPEAR"
    webhook="https://example.invalid/TEST_DISCORD_WEBHOOK_SHOULD_NOT_APPEAR"
    tr_bin="$(command -v tr 2>/dev/null || true)"

    if [ -z "$tr_bin" ]; then
        fail "notify_human curl-missing tests require tr"
        rm -rf "$tmpdir"
        return
    fi

    local output rc
    set +e
    output="$(
        (
            to_lower() { printf '%s' "${1:-}" | "$tr_bin" '[:upper:]' '[:lower:]'; }
            PATH="$tmpdir/empty"
            HUMAN_NOTIFY_CHANNEL="telegram"
            TELEGRAM_BOT_TOKEN="$token"
            TELEGRAM_CHAT_ID="123"
            DISCORD_WEBHOOK_URL="$webhook"
            notify_human "t" "b"
        ) 2>&1
    )"
    rc=$?
    set -e
    assert_eq "1" "$rc" "notify_human telegram fails when curl is missing from PATH"
    assert_true "notify_human telegram warns curl required" rg -q "curl is required for Telegram notifications" <<<"$output"
    assert_false "notify_human telegram curl-missing does not leak token" rg -qF "$token" <<<"$output"

    set +e
    output="$(
        (
            to_lower() { printf '%s' "${1:-}" | "$tr_bin" '[:upper:]' '[:lower:]'; }
            PATH="$tmpdir/empty"
            HUMAN_NOTIFY_CHANNEL="discord"
            TELEGRAM_BOT_TOKEN="$token"
            TELEGRAM_CHAT_ID="123"
            DISCORD_WEBHOOK_URL="$webhook"
            notify_human "t" "b"
        ) 2>&1
    )"
    rc=$?
    set -e
    assert_eq "1" "$rc" "notify_human discord fails when curl is missing from PATH"
    assert_true "notify_human discord warns curl required" rg -q "curl is required for Discord notifications" <<<"$output"
    assert_false "notify_human discord curl-missing does not leak webhook" rg -qF "$webhook" <<<"$output"

    rm -rf "$tmpdir"
}

test_notify_human_mocked_curl_failure_does_not_leak_secrets() {
    local tmpdir tmpbin curl_log old_path
    tmpdir="$(mktemp -d)"
    tmpbin="$tmpdir/bin"
    curl_log="$tmpdir/curl_calls.log"
    old_path="$PATH"
    mkdir -p "$tmpbin"

    cat > "$tmpbin/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$curl_log"
exit 22
EOF
    chmod +x "$tmpbin/curl"

    local token webhook output rc
    token="TEST_TELEGRAM_TOKEN_SHOULD_NOT_APPEAR"
    webhook="https://example.invalid/TEST_DISCORD_WEBHOOK_SHOULD_NOT_APPEAR"

    set +e
    output="$(PATH="$tmpbin:$old_path" HUMAN_NOTIFY_CHANNEL=telegram TELEGRAM_BOT_TOKEN="$token" TELEGRAM_CHAT_ID="123" DISCORD_WEBHOOK_URL="$webhook" notify_human "t" "b" 2>&1)"
    rc=$?
    set -e
    assert_eq "1" "$rc" "notify_human telegram returns non-zero when curl fails"
    assert_true "notify_human telegram emits failure warning when curl fails" rg -q "Failed to send Telegram notification" <<<"$output"
    assert_false "notify_human telegram curl failure does not leak token" rg -qF "$token" <<<"$output"
    assert_true "mocked curl invoked for telegram" test -s "$curl_log"

    : > "$curl_log"
    set +e
    output="$(PATH="$tmpbin:$old_path" HUMAN_NOTIFY_CHANNEL=discord TELEGRAM_BOT_TOKEN="$token" TELEGRAM_CHAT_ID="123" DISCORD_WEBHOOK_URL="$webhook" notify_human "t" "b" 2>&1)"
    rc=$?
    set -e
    assert_eq "1" "$rc" "notify_human discord returns non-zero when curl fails"
    assert_true "notify_human discord emits failure warning when curl fails" rg -q "Failed to send Discord notification" <<<"$output"
    assert_false "notify_human discord curl failure does not leak webhook" rg -qF "$webhook" <<<"$output"
    assert_true "mocked curl invoked for discord" test -s "$curl_log"

    rm -rf "$tmpdir"
}

test_setup_agent_subrepos_repairs_partial_init_submodule_mode() {
    local tmpdir tmprepo tmpbin git_log old_path output rc
    tmpdir="$(mktemp -d)"
    tmprepo="$tmpdir/repo"
    tmpbin="$tmpdir/bin"
    git_log="$tmpdir/git.log"
    mkdir -p "$tmprepo/scripts" "$tmprepo/subrepos/codex" "$tmprepo/subrepos/claude-code" "$tmprepo/maps" "$tmprepo/.git" "$tmpbin"

    cp "$ROOT_DIR/scripts/setup-agent-subrepos.sh" "$tmprepo/scripts/setup-agent-subrepos.sh"
    chmod +x "$tmprepo/scripts/setup-agent-subrepos.sh"

    cat > "$tmprepo/.gitmodules" <<'EOF'
[submodule "subrepos/codex"]
  path = subrepos/codex
  url = https://github.com/openai/codex.git
[submodule "subrepos/claude-code"]
  path = subrepos/claude-code
  url = https://github.com/anthropics/claude-code.git
EOF

    cat > "$tmprepo/subrepos/codex/.git" <<'EOF'
gitdir: ../../.git/modules/subrepos/codex
EOF
    cat > "$tmprepo/subrepos/claude-code/.git" <<'EOF'
gitdir: ../../.git/modules/subrepos/claude-code
EOF

    cat > "$tmpbin/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail
echo "\$*" >> "$git_log"

repo=""
if [ "\${1:-}" = "-C" ]; then
  repo="\${2:-}"
  shift 2
fi

cmd="\${1:-}"
shift || true

case "\$cmd" in
  submodule)
    subcmd="\${1:-}"
    shift || true
    if [ "\$subcmd" = "update" ]; then
      rel="\${!#}"
      mkdir -p "\$repo/\$rel"
      mkdir -p "\$repo/.git/modules/\$rel"
      printf '%s\n' "gitdir: ../../.git/modules/\$rel" > "\$repo/\$rel/.git"
      echo "ref: refs/heads/main" > "\$repo/.git/modules/\$rel/HEAD"
      exit 0
    fi
    exit 0
    ;;
  rev-parse)
    if [ "\${1:-}" = "HEAD" ]; then
      if [ -d "\$repo/.git" ]; then
        echo 1111111111111111111111111111111111111111
        exit 0
	      fi
	      if [ -f "\$repo/.git" ]; then
	        gitdir="\$(sed -n 's/^gitdir: //p' "\$repo/.git" | head -1)"
	        if [ -n "\$gitdir" ] && [ -d "\$repo/\$gitdir" ]; then
	          echo 1111111111111111111111111111111111111111
	          exit 0
	        fi
      fi
      exit 1
    fi
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
    chmod +x "$tmpbin/git"

    old_path="$PATH"
    set +e
    output="$(cd "$tmprepo" && PATH="$tmpbin:$old_path" bash scripts/setup-agent-subrepos.sh --mode submodule 2>&1)"
    rc=$?
    set -e

    assert_eq "0" "$rc" "setup-agent-subrepos repairs partial init in submodule mode"
    assert_true "setup-agent-subrepos emits ok message" rg -q "^\\[ok\\] Source map:" <<<"$output"
    assert_true "codex gitdir directory exists after repair" test -d "$tmprepo/.git/modules/subrepos/codex"
    assert_true "claude gitdir directory exists after repair" test -d "$tmprepo/.git/modules/subrepos/claude-code"

    assert_true "agent source map emitted" test -f "$tmprepo/maps/agent-source-map.yaml"
    assert_true "agent source map uses repo-relative codex path" rg -q 'local_path: "subrepos/codex"' "$tmprepo/maps/agent-source-map.yaml"
    assert_true "agent source map uses repo-relative claude path" rg -q 'local_path: "subrepos/claude-code"' "$tmprepo/maps/agent-source-map.yaml"
    assert_false "agent source map does not contain temp absolute path" rg -qF "$tmprepo" "$tmprepo/maps/agent-source-map.yaml"

    assert_true "binary steering map emitted" test -f "$tmprepo/maps/binary-steering-map.yaml"
    assert_false "binary steering map does not contain temp absolute path" rg -qF "$tmprepo" "$tmprepo/maps/binary-steering-map.yaml"

    rm -rf "$tmpdir"
}

test_setup_agent_subrepos_invalid_mode_fails() {
    local tmpdir tmprepo output rc
    tmpdir="$(mktemp -d)"
    tmprepo="$tmpdir/repo"
    mkdir -p "$tmprepo/scripts"
    cp "$ROOT_DIR/scripts/setup-agent-subrepos.sh" "$tmprepo/scripts/setup-agent-subrepos.sh"
    chmod +x "$tmprepo/scripts/setup-agent-subrepos.sh"

    set +e
    output="$(cd "$tmprepo" && bash scripts/setup-agent-subrepos.sh --mode nope 2>&1)"
    rc=$?
    set -e

    assert_eq "1" "$rc" "setup-agent-subrepos invalid mode exits non-zero"
    assert_true "setup-agent-subrepos invalid mode emits error" rg -q "\\[error\\] --mode must be 'submodule' or 'clone'" <<<"$output"

    rm -rf "$tmpdir"
}

test_stream_install_bootstrap() {
    local tmpdir
    tmpdir="$(mktemp -d)"

    local output rc
    set +e
    output="$(cd "$tmpdir" && cat "$ROOT_DIR/ralphie.sh" | env -u RALPHIE_LIB bash -s -- --doctor 2>&1)"
    rc=$?
    set -e

    local installed_path
    installed_path="$(printf '%s\n' "$output" | sed -n 's/^Installed ralphie.sh to //p' | head -1)"
    if [ -z "$installed_path" ]; then
        installed_path="$tmpdir/ralphie.sh"
    fi

    assert_eq "0" "$rc" "stream install bootstrap exits successfully"
    assert_true "stream install targets current working directory" rg -q "$tmpdir/ralphie.sh" <<<"$output"
    assert_true "stream install creates script file" test -f "$installed_path"
    assert_true "stream install creates executable script" test -x "$installed_path"
    assert_true "stream install re-executes script" rg -q "Ralphie Doctor" <<<"$output"

    rm -rf "$tmpdir"
}

test_idle_plan_refresh_from_build() {
    local tmpdir
    tmpdir="$(mktemp -d)"

    local old_log_dir old_prompt_plan_file old_plan_file old_context_file old_agent_source_map_file old_binary_steering_map_file
    old_log_dir="$LOG_DIR"
    old_prompt_plan_file="$PROMPT_PLAN_FILE"
    old_plan_file="$PLAN_FILE"
    old_context_file="${CONTEXT_FILE:-}"
    old_agent_source_map_file="$AGENT_SOURCE_MAP_FILE"
    old_binary_steering_map_file="$BINARY_STEERING_MAP_FILE"

    LOG_DIR="$tmpdir/logs"
    PROMPT_PLAN_FILE="$tmpdir/PROMPT_plan.md"
    PLAN_FILE="$tmpdir/IMPLEMENTATION_PLAN.md"
    CONTEXT_FILE=""
    AGENT_SOURCE_MAP_FILE="$tmpdir/no-agent-map.yaml"
    BINARY_STEERING_MAP_FILE="$tmpdir/no-binary-map.yaml"
    mkdir -p "$LOG_DIR"
    cat > "$PROMPT_PLAN_FILE" <<'EOF'
# Plan prompt
EOF

    local rc
    set +e
    (
        run_agent_with_prompt() {
            local _prompt_file="$1"
            local _log_file="$2"
            local _out_file="$3"
            local _yolo="$4"
            : > "$_prompt_file"
            : > "$_log_file"
            cat > "$PLAN_FILE" <<'EOF'
# Implementation Plan
- [ ] new-task
EOF
            cat > "$_out_file" <<'EOF'
<promise>DONE</promise>
EOF
            return 0
        }
        run_idle_plan_refresh "false" "7"
    )
    rc=$?
    set -e
    assert_eq "0" "$rc" "idle plan refresh succeeds with completion signal"
    assert_true "idle plan refresh writes plan tasks" rg -q '^- \[ \] new-task' "$PLAN_FILE"

    set +e
    (
        run_agent_with_prompt() {
            local _prompt_file="$1"
            local _log_file="$2"
            local _out_file="$3"
            local _yolo="$4"
            : > "$_prompt_file"
            : > "$_log_file"
            cat > "$PLAN_FILE" <<'EOF'
# Implementation Plan
- [ ] still-task
EOF
            cat > "$_out_file" <<'EOF'
no completion signal
EOF
            return 0
        }
        run_idle_plan_refresh "false" "8"
    )
    rc=$?
    set -e
    assert_eq "1" "$rc" "idle plan refresh fails without completion signal"

    LOG_DIR="$old_log_dir"
    PROMPT_PLAN_FILE="$old_prompt_plan_file"
    PLAN_FILE="$old_plan_file"
    CONTEXT_FILE="$old_context_file"
    AGENT_SOURCE_MAP_FILE="$old_agent_source_map_file"
    BINARY_STEERING_MAP_FILE="$old_binary_steering_map_file"

    rm -rf "$tmpdir"
}

test_lock_failure_reason_codes_and_diagnostics() {
    local tmpdir
    tmpdir="$(mktemp -d)"

    local old_config_dir old_lock_file old_lock_wait old_timeout
    old_config_dir="$CONFIG_DIR"
    old_lock_file="$LOCK_FILE"
    old_lock_wait="${LOCK_WAIT_SECONDS:-0}"
    old_timeout="${COMMAND_TIMEOUT_SECONDS:-0}"

    CONFIG_DIR="$tmpdir/.ralphie"
    LOCK_FILE="$CONFIG_DIR/run.lock"
    mkdir -p "$CONFIG_DIR"
    local holder_pid
    sleep 60 &
    holder_pid=$!
    {
        echo "$holder_pid"
        date '+%Y-%m-%d %H:%M:%S'
    } > "$LOCK_FILE"

    LOCK_WAIT_SECONDS=0
    COMMAND_TIMEOUT_SECONDS=0
    local output rc
    set +e
    output="$( ( acquire_lock ) 2>&1 )"
    rc=$?
    set -e
    assert_eq "1" "$rc" "immediate lock fail exits non-zero"
    assert_true "immediate lock fail emits reason code" rg -q "reason_code=RB_LOCK_ALREADY_HELD" <<<"$output"
    assert_true "immediate lock fail includes holder command" rg -q "Lock holder command:" <<<"$output"
    assert_true "immediate lock fail includes lock age" rg -q "Lock age:" <<<"$output"

    LOCK_WAIT_SECONDS=1
    COMMAND_TIMEOUT_SECONDS=0
    set +e
    output="$( ( acquire_lock ) 2>&1 )"
    rc=$?
    set -e
    assert_eq "1" "$rc" "timed lock fail exits non-zero"
    assert_true "timed lock fail emits timeout reason code" rg -q "reason_code=RB_LOCK_WAIT_TIMEOUT" <<<"$output"
    assert_true "timed lock fail includes waited seconds" rg -q "waited=1s" <<<"$output"

    kill "$holder_pid" 2>/dev/null || true
    wait "$holder_pid" 2>/dev/null || true

    CONFIG_DIR="$old_config_dir"
    LOCK_FILE="$old_lock_file"
    LOCK_WAIT_SECONDS="$old_lock_wait"
    COMMAND_TIMEOUT_SECONDS="$old_timeout"

    rm -rf "$tmpdir"
}

test_lock_diagnostics_fallback_and_stale_cleanup() {
    local tmpdir
    tmpdir="$(mktemp -d)"

    local old_config_dir old_lock_file old_lock_wait old_timeout old_path
    old_config_dir="$CONFIG_DIR"
    old_lock_file="$LOCK_FILE"
    old_lock_wait="${LOCK_WAIT_SECONDS:-0}"
    old_timeout="${COMMAND_TIMEOUT_SECONDS:-0}"
    old_path="$PATH"

    CONFIG_DIR="$tmpdir/.ralphie"
    LOCK_FILE="$CONFIG_DIR/run.lock"
    mkdir -p "$CONFIG_DIR"

    # Force metadata lookup failure without disabling other commands.
    cat > "$tmpdir/ps" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$tmpdir/ps"
    PATH="$tmpdir:$PATH"

    local holder_pid
    sleep 60 &
    holder_pid=$!
    {
        echo "$holder_pid"
        echo "not-a-timestamp"
    } > "$LOCK_FILE"
    LOCK_WAIT_SECONDS=0
    COMMAND_TIMEOUT_SECONDS=0
    local output rc
    set +e
    output="$( ( acquire_lock ) 2>&1 )"
    rc=$?
    set -e
    assert_eq "1" "$rc" "metadata fallback path still exits non-zero"
    assert_true "metadata fallback keeps deterministic reason code" rg -q "reason_code=RB_LOCK_ALREADY_HELD" <<<"$output"
    assert_true "metadata fallback reports unavailable holder command" rg -q "Lock holder command: unavailable" <<<"$output"
    assert_true "metadata fallback reports lock age parse failure" rg -q "Lock age: unavailable \\(timestamp parse failed:" <<<"$output"

    kill "$holder_pid" 2>/dev/null || true
    wait "$holder_pid" 2>/dev/null || true

    # Dead holder pid should be treated as stale lock and replaced.
    {
        echo "999999"
        date '+%Y-%m-%d %H:%M:%S'
    } > "$LOCK_FILE"
    LOCK_WAIT_SECONDS=0
    COMMAND_TIMEOUT_SECONDS=0
    set +e
    output="$( ( acquire_lock ) 2>&1 )"
    rc=$?
    set -e
    assert_eq "0" "$rc" "stale lock is removed and acquisition succeeds"
    local new_holder_pid
    new_holder_pid="$(sed -n '1p' "$LOCK_FILE")"
    assert_true "stale lock path replaces holder pid" test "$new_holder_pid" != "999999"

    PATH="$old_path"
    CONFIG_DIR="$old_config_dir"
    LOCK_FILE="$old_lock_file"
    LOCK_WAIT_SECONDS="$old_lock_wait"
    COMMAND_TIMEOUT_SECONDS="$old_timeout"

    rm -rf "$tmpdir"
}

test_lock_backend_fallback_when_ln_fails() {
    local tmpdir
    tmpdir="$(mktemp -d)"

    local old_config_dir old_lock_file old_log_dir old_lock_backend old_lock_backend_logged old_lock_wait old_timeout
    old_config_dir="$CONFIG_DIR"
    old_lock_file="$LOCK_FILE"
    old_log_dir="$LOG_DIR"
    old_lock_backend="${LOCK_BACKEND:-}"
    old_lock_backend_logged="${LOCK_BACKEND_LOGGED:-false}"
    old_lock_wait="${LOCK_WAIT_SECONDS:-0}"
    old_timeout="${COMMAND_TIMEOUT_SECONDS:-0}"

    CONFIG_DIR="$tmpdir/.ralphie"
    LOCK_FILE="$CONFIG_DIR/run.lock"
    LOG_DIR="$tmpdir/logs"
    mkdir -p "$CONFIG_DIR" "$LOG_DIR"

    LOCK_WAIT_SECONDS=0
    COMMAND_TIMEOUT_SECONDS=0
    LOCK_BACKEND="link"
    LOCK_BACKEND_LOGGED=false

    local output rc
    set +e
    output="$( ( ln() { return 1; }; acquire_lock ) 2>&1 )"
    rc=$?
    set -e
    assert_eq "0" "$rc" "lock acquisition falls back when ln fails"
    assert_true "fallback logs noclobber backend" rg -q "Lock backend: noclobber" <<<"$output"

    release_lock 2>/dev/null || true

    CONFIG_DIR="$old_config_dir"
    LOCK_FILE="$old_lock_file"
    LOG_DIR="$old_log_dir"
    LOCK_BACKEND="$old_lock_backend"
    LOCK_BACKEND_LOGGED="$old_lock_backend_logged"
    LOCK_WAIT_SECONDS="$old_lock_wait"
    COMMAND_TIMEOUT_SECONDS="$old_timeout"

    rm -rf "$tmpdir"
}

test_lock_atomic_race_allows_single_owner() {
    local tmpdir
    tmpdir="$(mktemp -d)"

    local worker start_file
    worker="$tmpdir/worker.sh"
    start_file="$tmpdir/start"

    cat > "$worker" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

id="$1"
tmpdir="$2"
root_dir="$3"

export RALPHIE_LIB=1
# shellcheck disable=SC1090
source "$root_dir/ralphie.sh"

CONFIG_DIR="$tmpdir/.ralphie"
LOCK_FILE="$CONFIG_DIR/run.lock"
LOG_DIR="$tmpdir/logs"
LOCK_WAIT_SECONDS=0
COMMAND_TIMEOUT_SECONDS=0
MODE="test"

mkdir -p "$CONFIG_DIR" "$LOG_DIR"

echo "ready" > "$tmpdir/ready_$id"
while [ ! -f "$tmpdir/start" ]; do sleep 0.01; done

set +e
( acquire_lock ) >/dev/null 2>&1
rc=$?
set -e

echo "$rc" > "$tmpdir/rc_$id"
if [ "$rc" -eq 0 ]; then
    sleep 1
    release_lock 2>/dev/null || true
fi
exit "$rc"
EOF
    chmod +x "$worker"

    local pids=()
    local i
    for i in 1 2 3 4 5; do
        bash "$worker" "$i" "$tmpdir" "$ROOT_DIR" >/dev/null 2>&1 &
        pids+=("$!")
    done

    local deadline now ready_count f
    deadline=$(( $(date +%s) + 10 ))
    while true; do
        ready_count=0
        for f in "$tmpdir"/ready_*; do
            [ -f "$f" ] || continue
            ready_count=$((ready_count + 1))
        done
        if [ "$ready_count" -ge 5 ]; then
            break
        fi
        now="$(date +%s)"
        if [ "$now" -ge "$deadline" ]; then
            fail "race fixture workers reached ready barrier"
            break
        fi
        sleep 0.05
    done

    : > "$start_file"

    local pid
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    local success=0 rc
    for i in 1 2 3 4 5; do
        if [ ! -f "$tmpdir/rc_$i" ]; then
            fail "race fixture produced rc_$i"
            continue
        fi
        rc="$(cat "$tmpdir/rc_$i")"
        if [ "$rc" = "0" ]; then
            success=$((success + 1))
        fi
    done
    assert_eq "1" "$success" "atomic lock race allows exactly one winner"

    rm -rf "$tmpdir"
}

test_clean_recursive_artifacts() {
    local tmpdir
    tmpdir="$(mktemp -d)"

    local old_project_dir old_config_dir old_lock_file old_log_dir old_consensus_dir old_completion_log_dir old_ready_archive_dir old_specs_dir old_research_dir old_maps_dir old_specify_dir old_reason_log_file old_gate_feedback_file old_state_file
    old_project_dir="$PROJECT_DIR"
    old_config_dir="$CONFIG_DIR"
    old_lock_file="$LOCK_FILE"
    old_reason_log_file="$REASON_LOG_FILE"
    old_gate_feedback_file="$GATE_FEEDBACK_FILE"
    old_state_file="$STATE_FILE"
    old_log_dir="$LOG_DIR"
    old_consensus_dir="$CONSENSUS_DIR"
    old_completion_log_dir="$COMPLETION_LOG_DIR"
    old_ready_archive_dir="$READY_ARCHIVE_DIR"
    old_specs_dir="$SPECS_DIR"
    old_research_dir="$RESEARCH_DIR"
    old_maps_dir="$MAPS_DIR"
    old_specify_dir="$SPECIFY_DIR"

    PROJECT_DIR="$tmpdir"
    CONFIG_DIR="$tmpdir/.ralphie"
    LOCK_FILE="$CONFIG_DIR/run.lock"
    REASON_LOG_FILE="$CONFIG_DIR/reasons.log"
    GATE_FEEDBACK_FILE="$CONFIG_DIR/last_gate_feedback.md"
    STATE_FILE="$CONFIG_DIR/state.env"
    LOG_DIR="$tmpdir/logs"
    CONSENSUS_DIR="$tmpdir/consensus"
    COMPLETION_LOG_DIR="$tmpdir/completion_log"
    READY_ARCHIVE_DIR="$CONFIG_DIR/ready-archives"
    SPECS_DIR="$tmpdir/specs"
    RESEARCH_DIR="$tmpdir/research"
    MAPS_DIR="$tmpdir/maps"
    SPECIFY_DIR="$tmpdir/.specify/memory"

    mkdir -p "$LOG_DIR" "$CONSENSUS_DIR" "$COMPLETION_LOG_DIR" "$READY_ARCHIVE_DIR" "$SPECS_DIR" "$RESEARCH_DIR"
    echo "runtime" > "$LOG_DIR/a.log"
    echo "runtime" > "$CONSENSUS_DIR/a.md"
    echo "runtime" > "$COMPLETION_LOG_DIR/a.md"
    echo "runtime" > "$READY_ARCHIVE_DIR/a.tgz"
    echo "12345" > "$LOCK_FILE"
    echo "reasons" > "$REASON_LOG_FILE"
    echo "feedback" > "$GATE_FEEDBACK_FILE"
    echo "state" > "$STATE_FILE"
    echo "# durable" > "$SPECS_DIR/spec.md"
    echo "# durable" > "$RESEARCH_DIR/RESEARCH_SUMMARY.md"

    clean_recursive_artifacts

    assert_false "clean removes log artifacts" bash -lc "find \"$LOG_DIR\" -mindepth 1 -print -quit 2>/dev/null | grep -q ."
    assert_false "clean removes consensus artifacts" bash -lc "find \"$CONSENSUS_DIR\" -mindepth 1 -print -quit 2>/dev/null | grep -q ."
    assert_false "clean removes completion artifacts" bash -lc "find \"$COMPLETION_LOG_DIR\" -mindepth 1 -print -quit 2>/dev/null | grep -q ."
    assert_true "clean keeps archive artifacts" bash -lc "find \"$READY_ARCHIVE_DIR\" -mindepth 1 -print -quit 2>/dev/null | grep -q ."
    assert_false "clean removes lock file" test -f "$LOCK_FILE"
    assert_false "clean removes reasons log" test -f "$REASON_LOG_FILE"
    assert_false "clean removes gate feedback" test -f "$GATE_FEEDBACK_FILE"
    assert_false "clean removes state file" test -f "$STATE_FILE"
    assert_true "clean keeps durable specs" test -f "$SPECS_DIR/spec.md"
    assert_true "clean keeps durable research" test -f "$RESEARCH_DIR/RESEARCH_SUMMARY.md"

    PROJECT_DIR="$old_project_dir"
    CONFIG_DIR="$old_config_dir"
    LOCK_FILE="$old_lock_file"
    REASON_LOG_FILE="$old_reason_log_file"
    GATE_FEEDBACK_FILE="$old_gate_feedback_file"
    STATE_FILE="$old_state_file"
    LOG_DIR="$old_log_dir"
    CONSENSUS_DIR="$old_consensus_dir"
    COMPLETION_LOG_DIR="$old_completion_log_dir"
    READY_ARCHIVE_DIR="$old_ready_archive_dir"
    SPECS_DIR="$old_specs_dir"
    RESEARCH_DIR="$old_research_dir"
    MAPS_DIR="$old_maps_dir"
    SPECIFY_DIR="$old_specify_dir"

    rm -rf "$tmpdir"
}

test_clean_deep_artifacts() {
    local tmpdir
    tmpdir="$(mktemp -d)"

    local old_project_dir old_config_dir old_lock_file old_log_dir old_consensus_dir old_completion_log_dir old_ready_archive_dir old_specs_dir old_research_dir old_maps_dir old_specify_dir old_subrepos_dir old_prompt_build_file old_prompt_plan_file old_prompt_prepare_file old_prompt_test_file old_prompt_refactor_file old_prompt_lint_file old_prompt_document_file old_reason_log_file old_gate_feedback_file old_state_file
    old_project_dir="$PROJECT_DIR"
    old_config_dir="$CONFIG_DIR"
    old_lock_file="$LOCK_FILE"
    old_reason_log_file="$REASON_LOG_FILE"
    old_gate_feedback_file="$GATE_FEEDBACK_FILE"
    old_state_file="$STATE_FILE"
    old_log_dir="$LOG_DIR"
    old_consensus_dir="$CONSENSUS_DIR"
    old_completion_log_dir="$COMPLETION_LOG_DIR"
    old_ready_archive_dir="$READY_ARCHIVE_DIR"
    old_specs_dir="$SPECS_DIR"
    old_research_dir="$RESEARCH_DIR"
    old_maps_dir="$MAPS_DIR"
    old_specify_dir="$SPECIFY_DIR"
    old_subrepos_dir="$SUBREPOS_DIR"
    old_prompt_build_file="$PROMPT_BUILD_FILE"
    old_prompt_plan_file="$PROMPT_PLAN_FILE"
    old_prompt_prepare_file="$PROMPT_PREPARE_FILE"
    old_prompt_test_file="$PROMPT_TEST_FILE"
    old_prompt_refactor_file="$PROMPT_REFACTOR_FILE"
    old_prompt_lint_file="$PROMPT_LINT_FILE"
    old_prompt_document_file="$PROMPT_DOCUMENT_FILE"

    PROJECT_DIR="$tmpdir"
    CONFIG_DIR="$tmpdir/.ralphie"
    LOCK_FILE="$CONFIG_DIR/run.lock"
    REASON_LOG_FILE="$CONFIG_DIR/reasons.log"
    GATE_FEEDBACK_FILE="$CONFIG_DIR/last_gate_feedback.md"
    STATE_FILE="$CONFIG_DIR/state.env"
    LOG_DIR="$tmpdir/logs"
    CONSENSUS_DIR="$tmpdir/consensus"
    COMPLETION_LOG_DIR="$tmpdir/completion_log"
    READY_ARCHIVE_DIR="$CONFIG_DIR/ready-archives"
    SPECS_DIR="$tmpdir/specs"
    RESEARCH_DIR="$tmpdir/research"
    MAPS_DIR="$tmpdir/maps"
    SPECIFY_DIR="$tmpdir/.specify/memory"
    SUBREPOS_DIR="$tmpdir/subrepos"
    PROMPT_BUILD_FILE="$tmpdir/PROMPT_build.md"
    PROMPT_PLAN_FILE="$tmpdir/PROMPT_plan.md"
    PROMPT_PREPARE_FILE="$tmpdir/PROMPT_prepare.md"
    PROMPT_TEST_FILE="$tmpdir/PROMPT_test.md"
    PROMPT_REFACTOR_FILE="$tmpdir/PROMPT_refactor.md"
    PROMPT_LINT_FILE="$tmpdir/PROMPT_lint.md"
    PROMPT_DOCUMENT_FILE="$tmpdir/PROMPT_document.md"

    mkdir -p "$LOG_DIR" "$CONSENSUS_DIR" "$COMPLETION_LOG_DIR" "$READY_ARCHIVE_DIR" "$SPECS_DIR" "$RESEARCH_DIR" "$MAPS_DIR" "$SUBREPOS_DIR" "$CONFIG_DIR"
    echo "runtime" > "$LOG_DIR/a.log"
    echo "runtime" > "$CONSENSUS_DIR/a.md"
    echo "runtime" > "$COMPLETION_LOG_DIR/a.md"
    echo "backup" > "$READY_ARCHIVE_DIR/existing.tar.gz"
    echo "12345" > "$LOCK_FILE"
    echo "reasons" > "$REASON_LOG_FILE"
    echo "feedback" > "$GATE_FEEDBACK_FILE"
    echo "state" > "$STATE_FILE"
    echo "# durable" > "$SPECS_DIR/spec.md"
    echo "# durable" > "$RESEARCH_DIR/RESEARCH_SUMMARY.md"
    echo "map" > "$MAPS_DIR/agent-source-map.yaml"
    echo "repo" > "$SUBREPOS_DIR/a.txt"
    echo "prompt" > "$PROMPT_BUILD_FILE"
    echo "prompt" > "$PROMPT_PLAN_FILE"
    echo "prompt" > "$PROMPT_PREPARE_FILE"
    echo "prompt" > "$PROMPT_TEST_FILE"
    echo "prompt" > "$PROMPT_REFACTOR_FILE"
    echo "prompt" > "$PROMPT_LINT_FILE"
    echo "prompt" > "$PROMPT_DOCUMENT_FILE"

    clean_deep_artifacts

    assert_false "clean-deep removes log artifacts" bash -lc "find \"$LOG_DIR\" -mindepth 1 -print -quit 2>/dev/null | grep -q ."
    assert_false "clean-deep removes consensus artifacts" bash -lc "find \"$CONSENSUS_DIR\" -mindepth 1 -print -quit 2>/dev/null | grep -q ."
    assert_false "clean-deep removes completion artifacts" bash -lc "find \"$COMPLETION_LOG_DIR\" -mindepth 1 -print -quit 2>/dev/null | grep -q ."
    assert_false "clean-deep removes specs artifacts" bash -lc "find \"$SPECS_DIR\" -mindepth 1 -print -quit 2>/dev/null | grep -q ."
    assert_false "clean-deep removes research artifacts" bash -lc "find \"$RESEARCH_DIR\" -mindepth 1 -print -quit 2>/dev/null | grep -q ."
    assert_false "clean-deep removes maps artifacts" bash -lc "find \"$MAPS_DIR\" -mindepth 1 -print -quit 2>/dev/null | grep -q ."
    assert_false "clean-deep removes subrepo artifacts" bash -lc "find \"$SUBREPOS_DIR\" -mindepth 1 -print -quit 2>/dev/null | grep -q ."
    assert_false "clean-deep removes build prompt" test -f "$PROMPT_BUILD_FILE"
    assert_false "clean-deep removes plan prompt" test -f "$PROMPT_PLAN_FILE"
    assert_false "clean-deep removes prepare prompt" test -f "$PROMPT_PREPARE_FILE"
    assert_false "clean-deep removes test prompt" test -f "$PROMPT_TEST_FILE"
    assert_false "clean-deep removes refactor prompt" test -f "$PROMPT_REFACTOR_FILE"
    assert_false "clean-deep removes lint prompt" test -f "$PROMPT_LINT_FILE"
    assert_false "clean-deep removes document prompt" test -f "$PROMPT_DOCUMENT_FILE"
    assert_false "clean-deep removes lock file" test -f "$LOCK_FILE"
    assert_false "clean-deep removes reasons log" test -f "$REASON_LOG_FILE"
    assert_false "clean-deep removes gate feedback" test -f "$GATE_FEEDBACK_FILE"
    assert_false "clean-deep removes state file" test -f "$STATE_FILE"
    assert_true "clean-deep keeps preexisting backup tarball" test -f "$READY_ARCHIVE_DIR/existing.tar.gz"
    assert_true "clean-deep keeps backup archive directory populated" bash -lc "find \"$READY_ARCHIVE_DIR\" -mindepth 1 -print -quit 2>/dev/null | grep -q ."

    PROJECT_DIR="$old_project_dir"
    CONFIG_DIR="$old_config_dir"
    LOCK_FILE="$old_lock_file"
    REASON_LOG_FILE="$old_reason_log_file"
    GATE_FEEDBACK_FILE="$old_gate_feedback_file"
    STATE_FILE="$old_state_file"
    LOG_DIR="$old_log_dir"
    CONSENSUS_DIR="$old_consensus_dir"
    COMPLETION_LOG_DIR="$old_completion_log_dir"
    READY_ARCHIVE_DIR="$old_ready_archive_dir"
    SPECS_DIR="$old_specs_dir"
    RESEARCH_DIR="$old_research_dir"
    MAPS_DIR="$old_maps_dir"
    SPECIFY_DIR="$old_specify_dir"
    SUBREPOS_DIR="$old_subrepos_dir"
    PROMPT_BUILD_FILE="$old_prompt_build_file"
    PROMPT_PLAN_FILE="$old_prompt_plan_file"
    PROMPT_PREPARE_FILE="$old_prompt_prepare_file"
    PROMPT_TEST_FILE="$old_prompt_test_file"
    PROMPT_REFACTOR_FILE="$old_prompt_refactor_file"
    PROMPT_LINT_FILE="$old_prompt_lint_file"
    PROMPT_DOCUMENT_FILE="$old_prompt_document_file"

    rm -rf "$tmpdir"
}

test_prerequisite_quality_gate() {
    local tmpdir
    tmpdir="$(mktemp -d)"

    PROJECT_DIR="$tmpdir"
    SPECS_DIR="$tmpdir/specs"
    RESEARCH_DIR="$tmpdir/research"
    PLAN_FILE="$tmpdir/IMPLEMENTATION_PLAN.md"
    RESEARCH_SUMMARY_FILE="$RESEARCH_DIR/RESEARCH_SUMMARY.md"

    mkdir -p "$SPECS_DIR/001" "$RESEARCH_DIR"
    cat > "$tmpdir/README.md" <<'EOF'
# Test README
EOF
    cat > "$tmpdir/.gitignore" <<'EOF'
.env
.env.*
logs/
consensus/
completion_log/
.ralphie/
HUMAN_INSTRUCTIONS.md
research/HUMAN_FEEDBACK.md
coverage/
.nyc_output/
htmlcov/
EOF
    cat > "$SPECS_DIR/001/spec.md" <<'EOF'
# Spec
## Acceptance Criteria
1. Works.
EOF
    cat > "$PLAN_FILE" <<'EOF'
# Implementation Plan
## Scope
Harden gate quality behavior.
## Assumptions
Shell tests are the validation baseline.
## Phase 1
1. Implement semantic gate checks.
## Validation
1. Run shell tests.
EOF
    cat > "$RESEARCH_SUMMARY_FILE" <<'EOF'
<confidence>80</confidence>
EOF
    cat > "$RESEARCH_DIR/CODEBASE_MAP.md" <<'EOF'
# Codebase Map
EOF
    cat > "$RESEARCH_DIR/DEPENDENCY_RESEARCH.md" <<'EOF'
# Dependency Research
EOF
    cat > "$RESEARCH_DIR/COVERAGE_MATRIX.md" <<'EOF'
# Coverage Matrix
EOF

    assert_true "build prerequisites pass for valid markdown artifacts" check_build_prerequisites

    cat > "$PLAN_FILE" <<'EOF'
just a shallow plan
EOF
    assert_false "build prerequisites fail for non-semantic plan" check_build_prerequisites

    cat > "$PLAN_FILE" <<'EOF'
# Implementation Plan
## Objectives
Improve reliability.
## Assumptions
Tests are available.
## Phase 1
1. Add checks.
## Validation
1. Verify checks.
EOF

    echo "succeeded in 52ms:" >> "$tmpdir/README.md"
    assert_false "build prerequisites fail on transcript leakage" check_build_prerequisites

    cat > "$tmpdir/README.md" <<'EOF'
# Test README
Path reference: /Users/local-machine-user/project
EOF
    assert_false "build prerequisites fail on local identity/path leakage" check_build_prerequisites

    cat > "$tmpdir/README.md" <<'EOF'
# Test README
EOF
    cat > "$tmpdir/.gitignore" <<'EOF'
.env
.env.*
logs/
consensus/
completion_log/
.ralphie/
HUMAN_INSTRUCTIONS.md
research/HUMAN_FEEDBACK.md
coverage/
.nyc_output/
EOF
    assert_false "build prerequisites fail on missing gitignore guardrails" check_build_prerequisites

    rm -rf "$tmpdir"
}

test_claude_output_log_separation() {
    local tmpdir old_path
    tmpdir="$(mktemp -d)"
    old_path="$PATH"

    cat > "$tmpdir/claude-mock" <<'EOF'
#!/usr/bin/env bash
echo "mock stdout"
echo "mock stderr" >&2
EOF
    chmod +x "$tmpdir/claude-mock"

    PATH="$tmpdir:$PATH"
    ACTIVE_ENGINE="claude"
    ACTIVE_CMD="claude-mock"
    COMMAND_TIMEOUT_SECONDS=0
    CAPABILITY_PROBED=true
    CLAUDE_CAP_PRINT=true
    CLAUDE_CAP_YOLO_FLAG=""

    local prompt_file log_file out_file
    prompt_file="$tmpdir/prompt.md"
    log_file="$tmpdir/run.log"
    out_file="$tmpdir/run.out"
    cat > "$prompt_file" <<'EOF'
prompt
EOF

    run_agent_with_prompt "$prompt_file" "$log_file" "$out_file" "false"
    assert_true "claude output artifact includes stdout" rg -q "mock stdout" "$out_file"
    assert_false "claude output artifact excludes stderr" rg -q "mock stderr" "$out_file"
    assert_true "claude log captures stderr" rg -q "mock stderr" "$log_file"

    PATH="$old_path"
    rm -rf "$tmpdir"
}

test_model_flags_forwarding() {
    local tmpdir old_path old_codex_model old_claude_model
    tmpdir="$(mktemp -d)"
    old_path="$PATH"
    old_codex_model="${CODEX_MODEL:-}"
    old_claude_model="${CLAUDE_MODEL:-}"

    cat > "$tmpdir/codex-mock" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$RB_ARGS_FILE"
out_file=""
while [ "$#" -gt 0 ]; do
    if [ "$1" = "--output-last-message" ]; then
        shift
        out_file="${1:-}"
        break
    fi
    shift
done
cat >/dev/null
if [ -n "$out_file" ]; then
    echo "<promise>DONE</promise>" > "$out_file"
fi
EOF

    cat > "$tmpdir/claude-mock" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$RB_ARGS_FILE"
cat >/dev/null
echo "ok"
EOF

    chmod +x "$tmpdir/codex-mock" "$tmpdir/claude-mock"
    PATH="$tmpdir:$PATH"
    COMMAND_TIMEOUT_SECONDS=0
    CAPABILITY_PROBED=true
    CODEX_CAP_OUTPUT_LAST_MESSAGE=true
    CODEX_CAP_YOLO_FLAG=false
    CLAUDE_CAP_PRINT=true
    CLAUDE_CAP_YOLO_FLAG=""

    local prompt_file log_file out_file args_file
    prompt_file="$tmpdir/prompt.md"
    log_file="$tmpdir/run.log"
    out_file="$tmpdir/run.out"
    args_file="$tmpdir/args.txt"
    cat > "$prompt_file" <<'EOF'
prompt
EOF

    ACTIVE_ENGINE="codex"
    ACTIVE_CMD="codex-mock"
    CODEX_MODEL="gpt-test-model"
    RB_ARGS_FILE="$args_file" run_agent_with_prompt "$prompt_file" "$log_file" "$out_file" "false"
    assert_true "codex command receives model flag" rg -q -- "--model" "$args_file"
    assert_true "codex command receives configured model value" rg -q -- "gpt-test-model" "$args_file"

    ACTIVE_ENGINE="claude"
    ACTIVE_CMD="claude-mock"
    CLAUDE_MODEL="sonnet-test-model"
    RB_ARGS_FILE="$args_file" run_agent_with_prompt "$prompt_file" "$log_file" "$out_file" "false"
    assert_true "claude command receives model flag" rg -q -- "--model" "$args_file"
    assert_true "claude command receives configured model value" rg -q -- "sonnet-test-model" "$args_file"

    CODEX_MODEL="$old_codex_model"
    CLAUDE_MODEL="$old_claude_model"
    PATH="$old_path"
    rm -rf "$tmpdir"
}

test_consensus_panel_failure_threshold() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    CONSENSUS_DIR="$tmpdir/consensus"
    mkdir -p "$CONSENSUS_DIR"

    SWARM_ENABLED=true
    SWARM_SIZE=3
    SWARM_MAX_PARALLEL=2
    MIN_CONSENSUS_SCORE=80
    CONSENSUS_MAX_REVIEWER_FAILURES=0

    run_agent_with_prompt() {
        local _prompt_file="$1"
        local _log_file="$2"
        local _out_file="$3"
        local _yolo="$4"
        : > "$_log_file"
        if [[ "$_out_file" == *"reviewer_1.out" ]]; then
            return 1
        fi
        cat > "$_out_file" <<'EOF'
<score>95</score>
<verdict>GO</verdict>
<summary>ok</summary>
<gaps>none</gaps>
<promise>DONE</promise>
EOF
        return 0
    }

    run_swarm_consensus "build-gate" "false"
    assert_false "consensus invalidated when reviewer failures exceed threshold" is_true "$LAST_CONSENSUS_PASS"
    assert_eq "1" "$LAST_CONSENSUS_PANEL_FAILURES" "panel failure count tracked"

    rm -rf "$tmpdir"
}

test_consensus_parallel_ceiling() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    CONSENSUS_DIR="$tmpdir/consensus"
    mkdir -p "$CONSENSUS_DIR"

    SWARM_ENABLED=true
    SWARM_SIZE=6
    SWARM_MAX_PARALLEL=2
    MIN_CONSENSUS_SCORE=0
    CONSENSUS_MAX_REVIEWER_FAILURES=6

    local lockdir active_file max_file
    lockdir="$tmpdir/lock"
    active_file="$tmpdir/active"
    max_file="$tmpdir/max"
    echo "0" > "$active_file"
    echo "0" > "$max_file"

    run_agent_with_prompt() {
        local _prompt_file="$1"
        local _log_file="$2"
        local _out_file="$3"
        local _yolo="$4"
        : > "$_log_file"

        while ! mkdir "$lockdir" 2>/dev/null; do sleep 0.01; done
        local active max_seen
        active="$(cat "$active_file")"
        active=$((active + 1))
        echo "$active" > "$active_file"
        max_seen="$(cat "$max_file")"
        if [ "$active" -gt "$max_seen" ]; then
            echo "$active" > "$max_file"
        fi
        rmdir "$lockdir"

        sleep 0.15

        while ! mkdir "$lockdir" 2>/dev/null; do sleep 0.01; done
        active="$(cat "$active_file")"
        active=$((active - 1))
        echo "$active" > "$active_file"
        rmdir "$lockdir"

        cat > "$_out_file" <<'EOF'
<score>90</score>
<verdict>GO</verdict>
<summary>ok</summary>
<gaps>none</gaps>
<promise>DONE</promise>
EOF
        return 0
    }

    run_swarm_consensus "build-gate" "false"
    local observed_max
    observed_max="$(cat "$max_file")"
    if [ "$observed_max" -le "$SWARM_MAX_PARALLEL" ]; then
        pass "reviewer concurrency does not exceed SWARM_MAX_PARALLEL"
    else
        fail "reviewer concurrency exceeded SWARM_MAX_PARALLEL (max=$observed_max limit=$SWARM_MAX_PARALLEL)"
    fi

    rm -rf "$tmpdir"
}

test_session_logging_fifo_writes_to_log_file() {
    local tmpdir
    tmpdir="$(mktemp -d)"

    local log_file
    log_file="$tmpdir/session.log"

    local rc
    set +e
    (
        LOG_DIR="$tmpdir/logs"
        MODE="test"
        mkdir -p "$LOG_DIR"
        start_session_logging "$log_file"
        echo "session-log-fixture"
        cleanup_session_logging
    ) >/dev/null 2>&1
    rc=$?
    set -e

    assert_eq "0" "$rc" "session logging setup and teardown succeeds"
    assert_true "session log file captures orchestrator output" rg -q "session-log-fixture" "$log_file"

    rm -rf "$tmpdir"
}

test_self_heal_log_redacts_home_paths() {
    local tmpdir
    tmpdir="$(mktemp -d)"

    local old_home old_project_dir old_research_dir old_specs_dir old_plan_file old_self_log
    old_home="$HOME"
    old_project_dir="$PROJECT_DIR"
    old_research_dir="$RESEARCH_DIR"
    old_specs_dir="$SPECS_DIR"
    old_plan_file="$PLAN_FILE"
    old_self_log="$SELF_IMPROVEMENT_LOG_FILE"

    HOME="$tmpdir/home"
    PROJECT_DIR="$tmpdir/project"
    RESEARCH_DIR="$PROJECT_DIR/research"
    SPECS_DIR="$PROJECT_DIR/specs"
    PLAN_FILE="$PROJECT_DIR/IMPLEMENTATION_PLAN.md"
    SELF_IMPROVEMENT_LOG_FILE="$RESEARCH_DIR/SELF_IMPROVEMENT_LOG.md"
    mkdir -p "$HOME/.codex" "$RESEARCH_DIR" "$SPECS_DIR" "$PROJECT_DIR"
    cat > "$HOME/.codex/config.toml" <<'EOF'
model_reasoning_effort = "xhigh"
EOF

    local rc
    set +e
    self_heal_codex_reasoning_effort_xhigh >/dev/null 2>&1
    rc=$?
    set -e
    assert_eq "0" "$rc" "self-heal runs and writes self-improvement log"

    assert_false "self-improvement log excludes expanded HOME path" rg -qF "$HOME" "$SELF_IMPROVEMENT_LOG_FILE"
    assert_true "self-improvement log contains redacted backup path" rg -q "Backup: ~/" "$SELF_IMPROVEMENT_LOG_FILE"
    assert_true "markdown artifacts remain clean after self-heal" markdown_artifacts_are_clean

    HOME="$old_home"
    PROJECT_DIR="$old_project_dir"
    RESEARCH_DIR="$old_research_dir"
    SPECS_DIR="$old_specs_dir"
    PLAN_FILE="$old_plan_file"
    SELF_IMPROVEMENT_LOG_FILE="$old_self_log"

    rm -rf "$tmpdir"
}

main() {
    test_confidence_parsing
    test_prepare_tag_detection
    test_prepare_tag_fallback_parsing
    test_completion_signal_detection
    test_fallback_engine_selection
    test_effective_lock_wait_seconds
    test_prompt_yes_no_eof_defaults
    test_prompt_line_eof_defaults
    test_prompt_optional_line_eof_defaults
    test_interrupt_handler_non_interactive_path
    test_prompt_file_mapping
    test_stream_install_bootstrap
    test_count_pending_human_requests_missing_file
    test_count_pending_human_requests_case_insensitive
    test_check_human_requests_sets_flag
    test_prepare_prompt_for_iteration_injects_human_queue_when_present
    test_prepare_prompt_for_iteration_skips_human_queue_when_missing
    test_capture_human_priorities_fails_non_interactive_with_reason_code
    test_notify_human_none_is_noop
    test_notify_human_terminal_emits_messages
    test_notify_human_telegram_missing_env_fails
    test_notify_human_discord_missing_env_fails
    test_notify_human_fails_when_curl_missing_from_path
    test_notify_human_mocked_curl_failure_does_not_leak_secrets
    test_setup_agent_subrepos_repairs_partial_init_submodule_mode
    test_setup_agent_subrepos_invalid_mode_fails
    test_idle_plan_refresh_from_build
    test_lock_failure_reason_codes_and_diagnostics
    test_lock_diagnostics_fallback_and_stale_cleanup
    test_lock_backend_fallback_when_ln_fails
    test_lock_atomic_race_allows_single_owner
    test_clean_recursive_artifacts
    test_clean_deep_artifacts
    test_prerequisite_quality_gate
    test_session_logging_fifo_writes_to_log_file
    test_self_heal_log_redacts_home_paths
    test_claude_output_log_separation
    test_model_flags_forwarding
    test_consensus_panel_failure_threshold
    test_consensus_parallel_ceiling

    if [ "$FAILURES" -gt 0 ]; then
        echo ""
        echo "Tests failed: $FAILURES"
        exit 1
    fi
    echo ""
    echo "All shell tests passed."
}

main "$@"
