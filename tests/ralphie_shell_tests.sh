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
    {
        echo "$$"
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

    {
        echo "$$"
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

main() {
    test_confidence_parsing
    test_prepare_tag_detection
    test_prepare_tag_fallback_parsing
    test_completion_signal_detection
    test_fallback_engine_selection
    test_effective_lock_wait_seconds
    test_prompt_yes_no_eof_defaults
    test_interrupt_handler_non_interactive_path
    test_prompt_file_mapping
    test_stream_install_bootstrap
    test_idle_plan_refresh_from_build
    test_lock_failure_reason_codes_and_diagnostics
    test_lock_diagnostics_fallback_and_stale_cleanup
    test_clean_recursive_artifacts
    test_clean_deep_artifacts
    test_prerequisite_quality_gate
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
