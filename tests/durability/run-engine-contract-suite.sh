#!/usr/bin/env bash
# Engine/configuration contracts. All CLI calls use test-owned offline fixtures.
set -euo pipefail

ENGINE_SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Reuse the frozen-source harness and strict engine mocks, without its main.
source "$ENGINE_SUITE_DIR/run-continuation-suite.sh"

test_engine_alias_environment_precedence() {
    local ws
    ws="$(new_continuation_workspace)"
    cp "$RALPHIE_FILE" "$ws/project with spaces/ralphie.sh"
    cat > "$ws/project with spaces/.ralphie/config.env" <<'EOF_CONFIG'
RALPHIE_MAX_SESSION_CYCLES=0
RALPHIE_COMMAND_TIMEOUT_SECONDS=99
RALPHIE_CODEX_MODEL=config-model
RALPHIE_PRIME_MODEL=config-prime
EOF_CONFIG
    env -i PATH="$PATH" HOME="$ws/home" MAX_SESSION_CYCLES=1 COMMAND_TIMEOUT_SECONDS=08 \
        CODEX_MODEL=env-model PRIME_MODEL=env-prime /bin/bash -s -- "$ws/project with spaces/ralphie.sh" <<'EOF_ASSERT'
source "$1"
[ "$MAX_SESSION_CYCLES" = 1 ]
[ "$COMMAND_TIMEOUT_SECONDS" = 08 ]
[ "$CODEX_MODEL" = env-model ]
[ "$PRIME_MODEL" = env-prime ]
validate_effective_engine_config
[ "$COMMAND_TIMEOUT_SECONDS" = 8 ]
EOF_ASSERT
    cat > "$ws/project with spaces/.ralphie/config.env" <<'EOF_CONFIG'
MAX_SESSION_CYCLES=0
COMMAND_TIMEOUT_SECONDS=99
CODEX_MODEL=config-model
PRIME_MODEL=config-prime
EOF_CONFIG
    env -i PATH="$PATH" HOME="$ws/home" RALPHIE_MAX_SESSION_CYCLES=2 RALPHIE_COMMAND_TIMEOUT_SECONDS=7 \
        RALPHIE_CODEX_MODEL=env-model RALPHIE_PRIME_MODEL=env-prime /bin/bash -s -- "$ws/project with spaces/ralphie.sh" <<'EOF_ASSERT'
source "$1"
[ "$MAX_SESSION_CYCLES" = 2 ]
[ "$COMMAND_TIMEOUT_SECONDS" = 7 ]
[ "$CODEX_MODEL" = env-model ]
[ "$PRIME_MODEL" = env-prime ]
EOF_ASSERT
}

test_engine_config_literal_round_trip_and_multiline_refusal() {
    local ws value result
    ws="$(new_continuation_workspace)"
    configure_prime_adapter_fixture "$ws"
    CONFIG_FILE="$CONFIG_DIR/config.env"
    for value in 'two\\slashes' 'slash\"quote' '$(touch NEVER_EXECUTE)' 'cost $HOME and `literal`' $'literal\ttab'; do
        upsert_config_env_value RALPHIE_PRIME_MODEL "$value"
        RALPHIE_PRIME_MODEL=''
        load_config_file_safe "$CONFIG_FILE"
        [ "$RALPHIE_PRIME_MODEL" = "$value" ]
    done
    [ ! -e NEVER_EXECUTE ]
    cp "$CONFIG_FILE" "$ws/config.before"
    set +e
    upsert_config_env_value RALPHIE_PRIME_MODEL $'first\nsecond' > "$ws/refusal.out" 2>&1
    result=$?
    set -e
    [ "$result" -ne 0 ]
    cmp "$CONFIG_FILE" "$ws/config.before"
    printf 'RALPHIE_PRIME_MODEL="unterminated\nsecond"\n' > "$ws/invalid.env"
    set +e
    load_config_file_safe "$ws/invalid.env" > "$ws/refusal.out" 2>&1
    result=$?
    set -e
    [ "$result" -ne 0 ]
    grep -q 'multiline or unterminated' "$ws/refusal.out"
}

test_engine_raw_awk_paths_and_allowlist_regex() {
    local ws literal_dir
    ws="$(new_continuation_workspace)"
    configure_prime_adapter_fixture "$ws"
    literal_dir="$ws/project\\new"
    mkdir "$literal_dir"
    printf 'literal output\n' | stream_engine_output "$literal_dir/log" "$literal_dir/answer" yes > "$ws/console"
    printf 'literal output\n' > "$ws/expected"
    cmp "$ws/expected" "$literal_dir/log"
    cmp "$ws/expected" "$literal_dir/answer"
    cmp "$ws/expected" "$ws/console"
    MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX='^/Users/alice/project\.txt$'
    awk_regex_is_valid "$MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX"
    printf '/Users/alice/project.txt\n' > "$ws/exact.md"
    printf '/Users/alice/projectXtxt\n' > "$ws/lookalike.md"
    if file_has_local_identity_leakage "$ws/exact.md"; then return 1; fi
    file_has_local_identity_leakage "$ws/lookalike.md"
    sanitize_markdown_artifact_file "$ws/lookalike.md"
    if grep -q '/Users/alice/' "$ws/lookalike.md"; then return 1; fi
}

test_engine_decimal_boolean_and_option_value_normalization() {
    local ws n result
    ws="$(new_continuation_workspace)"
    configure_prime_adapter_fixture "$ws"
    [ "$(normalize_non_negative_decimal 00008)" = 8 ]
    [ "$(normalize_non_negative_decimal 000)" = 0 ]
    [ "$(normalize_non_negative_decimal 9223372036854775807)" = 9223372036854775807 ]
    for n in -1 1.5 bad 9223372036854775808 100000000000000000000000000; do
        if normalize_non_negative_decimal "$n" >/dev/null; then return 1; fi
    done
    [ "$(parse_arg_value --prime-model -n)" = -n ]
    [ "$(engine_retry_delay 0 100)" = 0 ]
    RUN_AGENT_RETRY_DELAY_SECONDS=08
    SESSION_TOKEN_RATE_CENTS_PER_MILLION=08
    ENGINE_OUTPUT_TO_STDOUT=yes
    ENGINE_OUTPUT_TO_STDOUT_EXPLICIT=true
    CODEX_USE_RESPONSES_SCHEMA=0
    validate_effective_engine_config
    [ "$RUN_AGENT_RETRY_DELAY_SECONDS" = 8 ]
    [ "$SESSION_TOKEN_RATE_CENTS_PER_MILLION" = 8 ]
    [ "$ENGINE_OUTPUT_TO_STDOUT" = true ]
    [ "$ENGINE_OUTPUT_TO_STDOUT_OVERRIDE" = true ]
    [ "$CODEX_USE_RESPONSES_SCHEMA" = false ]
    RUN_AGENT_MAX_ATTEMPTS=0
    if validate_effective_engine_config > "$ws/invalid.out" 2>&1; then return 1; fi
    RUN_AGENT_MAX_ATTEMPTS=1
    ENGINE_HEALTH_MAX_ATTEMPTS=0
    if validate_effective_engine_config > "$ws/invalid.out" 2>&1; then return 1; fi
}

test_engine_invalid_limits_refuse_before_inference() {
    local ws setting status
    for setting in 'RALPHIE_MAX_SESSION_CYCLES=bad' 'RALPHIE_MAX_SESSION_CYCLES=9223372036854775808' \
        'RALPHIE_SESSION_TOKEN_BUDGET=9999999999999999999999' 'RALPHIE_ENGINE_OUTPUT_MAX_BYTES=9223372036854775807' \
        'RALPHIE_AUTO_UPDATE_TIMEOUT_SECONDS=bad' 'RALPHIE_AUTO_UPDATE_LOCK_TIMEOUT_SECONDS=-1' \
        'RALPHIE_ENGINE_OUTPUT_TO_STDOUT=perhaps' 'RALPHIE_CODEX_USE_RESPONSES_SCHEMA=perhaps' \
        'RALPHIE_SESSION_COST_BUDGET_CENTS=1'; do
        ws="$(new_continuation_workspace)"
        printf '%s\n' "$setting" > "$ws/project with spaces/.ralphie/config.env"
        set +e
        run_continuation_fixture "$ws" --objective 'Reject invalid limits' --plan-only > "$ws/run.out" 2>&1
        status=$?
        set -e
        [ "$status" -ne 0 ]
        [ ! -e "$ws/project with spaces/.mock-prime/calls" ]
        grep -qE 'Invalid |positive session cost budget' "$ws/run.out"
    done
    ws="$(new_continuation_workspace)"
    set +e
    run_continuation_fixture "$ws" --objective 'Reject overflow CLI cap' --plan-only \
        --max-session-cycles 9223372036854775808 > "$ws/run.out" 2>&1
    status=$?
    set -e
    [ "$status" -ne 0 ]
    [ ! -e "$ws/project with spaces/.mock-prime/calls" ]
}

test_engine_cost_rounds_up_and_overflow_refuses() {
    local ws i status
    ws="$(new_continuation_workspace)"
    configure_prime_adapter_fixture "$ws"
    SESSION_TOKEN_RATE_CENTS_PER_MILLION=500
    for i in 1 2 3 4 5; do charge_session_budget 1000; done
    [ "$SESSION_TOKEN_COUNT" = 5000 ]
    [ "$SESSION_COST_CENTS" = 5 ]
    SESSION_COST_BUDGET_CENTS=5
    if admit_session_attempt 'cost cap proof'; then return 1; fi
    [ "$SESSION_ATTEMPT_COUNT" = 0 ]
    ENGINE_BUDGET_EXHAUSTED=false
    SESSION_COST_BUDGET_CENTS=0
    SESSION_TOKEN_RATE_CENTS_PER_MILLION=9223372036854775807
    set +e
    charge_session_budget 2 > "$ws/overflow.out" 2>&1
    status=$?
    set -e
    [ "$status" -eq 75 ]
    [ "$SESSION_TOKEN_COUNT" = 5000 ]
    [ "$SESSION_COST_CENTS" = 5 ]
    ENGINE_BUDGET_EXHAUSTED=false
    SESSION_TOKEN_RATE_CENTS_PER_MILLION=0
    SESSION_ATTEMPT_COUNT=9223372036854775807
    set +e
    admit_session_attempt 'attempt overflow proof' > "$ws/overflow.out" 2>&1
    status=$?
    set -e
    [ "$status" -eq 75 ]
    [ "$SESSION_ATTEMPT_COUNT" = 9223372036854775807 ]
    [ "$ENGINE_BUDGET_EXHAUSTED" = true ]
}

install_engine_metadata_mock() {
    local ws="$1"
    cat > "$ws/bin/metadata" <<'EOF_METADATA'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in --version|--help) ;; *) exit 29;; esac
printf '%s\n' "$1" >> "$METADATA_RECEIPT"
case "$METADATA_MODE" in
    normal) printf 'offline metadata 999.0.0\n' ;;
    sleep) exec sleep 30 ;;
    large) head -c 70000 /dev/zero | tr '\000' x ;;
    *) exit 30;;
esac
EOF_METADATA
    chmod +x "$ws/bin/metadata"
}

test_engine_free_metadata_is_lazy_and_bounded() {
    local ws status start elapsed
    ws="$(new_continuation_workspace)"
    install_engine_metadata_mock "$ws"
    METADATA_RECEIPT="$ws/metadata.calls"
    METADATA_MODE=sleep
    export METADATA_RECEIPT METADATA_MODE
    # Public help must not execute even an installed, explicitly configured CLI.
    env CODEX_ENGINE_CMD="$ws/bin/metadata" CLAUDE_ENGINE_CMD="$ws/bin/metadata" \
        PRIME_ENGINE_CMD="$ws/bin/metadata" /bin/bash "$ws/ralphie.sh" --project "$ws/project with spaces" --help > "$ws/help.out"
    [ ! -e "$METADATA_RECEIPT" ]
    configure_prime_adapter_fixture "$ws"
    start="$(date +%s)"
    set +e
    run_bounded_engine_metadata "$ws/bin/metadata" --version > "$ws/metadata.out"
    status=$?
    set -e
    elapsed=$(($(date +%s) - start))
    [ "$status" -eq 124 ]
    [ "$elapsed" -le 8 ]
    [ ! -s "$ws/metadata.out" ]
    METADATA_MODE=large
    set +e
    run_bounded_engine_metadata "$ws/bin/metadata" --help > "$ws/metadata.out"
    status=$?
    set -e
    [ "$status" -eq 125 ]
    [ ! -s "$ws/metadata.out" ]
    [ "$SESSION_ATTEMPT_COUNT" = 0 ]
    [ -z "$(find "$ws/engine-scratch" -mindepth 1 -print -quit)" ]
}

test_engine_redacted_auth_stops_paid_retries() {
    local ws status
    ws="$(new_continuation_workspace)"
    mv "$ws/bin/prime-agent" "$ws/bin/prime-fixture"
    cat > "$ws/bin/prime-agent" <<'EOF_AUTH_PRIME'
#!/usr/bin/env bash
set -euo pipefail
fixture="$(cd "$(dirname "$0")" && pwd)/prime-fixture"
case "${1:-}" in --version|--help) exec "$fixture" "$@";; esac
# The strict fixture validates every argument and records one attempted call.
MOCK_PRIME_PERMANENT_FAILURE=true "$fixture" "$@" >/dev/null 2>/dev/null || true
printf 'Missing or invalid access token SECRET_DO_NOT_RETAIN\n' >&2
exit 1
EOF_AUTH_PRIME
    chmod +x "$ws/bin/prime-agent"
    configure_prime_adapter_fixture "$ws"
    RUN_AGENT_MAX_ATTEMPTS=3
    set +e
    run_agent_with_prompt "$ws/prompt.md" "$ws/run.log" "$ws/answer" true 1 > "$ws/dispatch.out" 2>&1
    status=$?
    set -e
    [ "$status" -eq 126 ]
    [ "$ENGINE_PERMANENT_FAILURE" = true ]
    [ "$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')" = 1 ]
    [ "$SESSION_ATTEMPT_COUNT" = 1 ]
    grep -q 'redacted provider auth' "$ws/run.log"
    if grep -q SECRET_DO_NOT_RETAIN "$ws/run.log" "$ws/answer" "$ws/dispatch.out"; then return 1; fi
    [ ! -s "$ws/answer" ]
    [ -z "$(find "$ws/engine-scratch" -mindepth 1 -print -quit)" ]
}

install_engine_canary_mock() {
    local ws="$1"
    cat > "$ws/bin/canary" <<'EOF_CANARY'
#!/usr/bin/env bash
set -euo pipefail
engine="${0##*/}"
case "${1:-}" in
    --version) printf 'offline canary 999.0.0\n'; exit 0;;
    --help) printf '%s\n' '-p, --print --dangerously-skip-permissions tool read write'; exit 0;;
esac
if [ "${1:-}" = exec ] && [ "${2:-}" = --help ]; then
    printf '%s\n' '--output-last-message --dangerously-bypass-approvals-and-sandbox tool read write'
    exit 0
fi
answer_path=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        exec|-p|-) shift;;
        --output-last-message) answer_path="$2"; shift 2;;
        --model|-c|--settings) [ "$#" -ge 2 ]; shift 2;;
        *) printf 'Unexpected canary argument: %s\n' "$1" >&2; exit 28;;
    esac
done
receipt="$CANARY_RECEIPT_DIR/$$"
cat > "$receipt.prompt"
grep -q '^Reply with ONLY this exact token on a single line, nothing else: ralphie_smoke_' "$receipt.prompt"
printf '%s\n' "$engine" >> "$CANARY_RECEIPT_DIR/calls"
case "$ENGINE_TEST_CANARY_MODE" in
    auth) printf 'Missing or invalid access token SECRET_CANARY\n' >&2; exit 1;;
    normal|large) sed -n 's/^Reply with ONLY this exact token on a single line, nothing else: //p' "$receipt.prompt" > "$receipt.answer";;
    *) exit 30;;
esac
if [ "$ENGINE_TEST_CANARY_MODE" = large ]; then head -c 1024 /dev/zero | tr '\000' x >> "$receipt.answer"; fi
if [ -n "$answer_path" ]; then cp "$receipt.answer" "$answer_path"; else cat "$receipt.answer"; fi
EOF_CANARY
    cp "$ws/bin/canary" "$ws/bin/codex"
    cp "$ws/bin/canary" "$ws/bin/claude"
    chmod +x "$ws/bin/codex" "$ws/bin/claude"
}

configure_engine_canary_fixture() {
    local ws="$1"
    install_engine_canary_mock "$ws"
    configure_prime_adapter_fixture "$ws"
    PRIME_CMD="$ws/bin/unavailable-prime"
    CODEX_CMD="$ws/bin/codex"
    CLAUDE_CMD="$ws/bin/claude"
    PRIME_OPTIONS_EXPLICIT=false
    ENGINE_CAPABILITIES_PROBED=false
    CODEX_USE_RESPONSES_SCHEMA=false
    CODEX_MODEL=fixture-codex
    CLAUDE_MODEL=fixture-claude
    CODEX_ENDPOINT=''
    CLAUDE_ENDPOINT=''
    ENGINE_HEALTH_MAX_ATTEMPTS=3
    ENGINE_HEALTH_RETRY_DELAY_SECONDS=0
    ENGINE_HEALTH_RETRY_VERBOSE=false
    ENGINE_SMOKE_TEST_TIMEOUT=3
    CANARY_RECEIPT_DIR="$ws/canary-receipts"
    mkdir "$CANARY_RECEIPT_DIR"
    export CANARY_RECEIPT_DIR
}

test_engine_permanent_canary_failure_is_not_retried() {
    local ws engine status
    for engine in codex claude; do
        (
            ws="$(new_continuation_workspace)"
            configure_engine_canary_fixture "$ws"
            ENGINE_SELECTION_REQUESTED="$engine"
            ENGINE_TEST_CANARY_MODE=auth
            export ENGINE_TEST_CANARY_MODE
            set +e
            ensure_engines_ready "$engine" > "$ws/readiness.out" 2>&1
            status=$?
            set -e
            [ "$status" -eq 126 ]
            [ "$ENGINE_PERMANENT_FAILURE" = true ]
            [ "$(wc -l < "$CANARY_RECEIPT_DIR/calls" | tr -d ' ')" = 1 ]
            [ "$SESSION_ATTEMPT_COUNT" = 1 ]
            if grep -q SECRET_CANARY "$ws/readiness.out"; then return 1; fi
            [ -z "$(find "$ws/engine-scratch" -mindepth 1 -print -quit)" ]
        )
    done
    (
        ws="$(new_continuation_workspace)"
        configure_engine_canary_fixture "$ws"
        ENGINE_SELECTION_REQUESTED=auto
        ENGINE_TEST_CANARY_MODE=auth
        export ENGINE_TEST_CANARY_MODE
        set +e
        ensure_engines_ready auto > "$ws/readiness.out" 2>&1
        status=$?
        set -e
        [ "$status" -ne 0 ]
        [ "$(wc -l < "$CANARY_RECEIPT_DIR/calls" | tr -d ' ')" = 2 ]
        [ "$SESSION_ATTEMPT_COUNT" = 2 ]
        [ "$CODEX_SMOKE_PERMANENT_FAILURE" = true ]
        [ "$CLAUDE_SMOKE_PERMANENT_FAILURE" = true ]
    )
}

test_engine_oversized_canary_cannot_report_healthy() {
    local ws engine status
    for engine in codex claude; do
        (
            ws="$(new_continuation_workspace)"
            configure_engine_canary_fixture "$ws"
            ENGINE_SELECTION_REQUESTED="$engine"
            ENGINE_TEST_CANARY_MODE=large
            ENGINE_OUTPUT_MAX_BYTES=128
            export ENGINE_TEST_CANARY_MODE
            set +e
            probe_engine_capabilities true "$engine" > "$ws/readiness.out" 2>&1
            status=$?
            set -e
            [ "$status" -eq 0 ]
            if engine_is_healthy "$engine"; then return 1; fi
            [ "$(wc -l < "$CANARY_RECEIPT_DIR/calls" | tr -d ' ')" = 1 ]
            [ "$SESSION_ATTEMPT_COUNT" = 1 ]
            [ -z "$(find "$ws/engine-scratch" -mindepth 1 -print -quit)" ]
        )
    done
}

test_engine_explicit_missing_codex_schema_refuses_without_calls() {
    local ws status
    ws="$(new_continuation_workspace)"
    configure_engine_canary_fixture "$ws"
    CODEX_USE_RESPONSES_SCHEMA=true
    CODEX_RESPONSES_SCHEMA_FILE="$ws/no-such-schema.json"
    ENGINE_SELECTION_REQUESTED=codex
    if validate_engine_options > "$ws/schema.out" 2>&1; then return 1; fi
    set +e
    smoke_test_engine "$CODEX_CMD" codex >> "$ws/schema.out" 2>&1
    status=$?
    set -e
    [ "$status" -ne 0 ]
    [ "$SESSION_ATTEMPT_COUNT" = 0 ]
    [ ! -e "$CANARY_RECEIPT_DIR/calls" ]
    ENGINE_SELECTION_REQUESTED=prime-agent
    validate_engine_options
}

operator_boolean_setting_names() {
    printf '%s\n' ENGINE_OUTPUT_TO_STDOUT YOLO RUN_AGENT_RETRY_VERBOSE ENGINE_HEALTH_RETRY_VERBOSE CODEX_USE_RESPONSES_SCHEMA \
        AUTO_COMMIT_ON_PHASE_PASS AUTO_UPDATE AUTO_UPDATE_ALLOW_DIRTY AUTO_UPDATE_ALLOW_INSECURE AUTO_INIT_GIT_IF_MISSING \
        AUTO_PLAN_BACKFILL_ON_IDLE_BUILD AUTO_REPAIR_MARKDOWN_ARTIFACTS AUTO_REPAIR_MARKDOWN_DRY_RUN AUTO_REPAIR_MARKDOWN_BACKUP \
        AUTO_REPAIR_MARKDOWN_ONLY_SESSION_CHANGED REQUIRE_LINT_BEFORE_DONE REQUIRE_DOCUMENT_BEFORE_DONE \
        REQUIRE_PLAN_BACKLOG_CLEAR_BEFORE_DONE REQUIRE_PLAN_FRESHNESS_FOR_BUILD ENGINE_OVERRIDES_BOOTSTRAPPED \
        NOTIFICATIONS_ENABLED NOTIFY_TELEGRAM_ENABLED NOTIFY_DISCORD_ENABLED NOTIFY_TTS_ENABLED NOTIFICATION_WIZARD_BOOTSTRAPPED \
        RESUME_REQUESTED REBOOTSTRAP_REQUESTED STARTUP_OPERATIONAL_PROBE STRICT_VALIDATION_NOOP PHASE_COMPLETION_RETRY_VERBOSE
}

test_operator_booleans_reject_malformed_and_normalize_aliases() {
    local ws setting original token expected
    ws="$(new_continuation_workspace)"
    configure_prime_adapter_fixture "$ws"
    while IFS= read -r setting; do
        original="${!setting}"
        printf -v "$setting" '%s' false-ish
        if validate_effective_engine_config > "$ws/boolean.out" 2>&1; then
            fail "Malformed $setting was accepted."
            return 1
        fi
        grep -q "Invalid boolean value for $setting" "$ws/boolean.out"
        printf -v "$setting" '%s' "$original"
    done < <(operator_boolean_setting_names)
    for token in yes no 1 0; do
        while IFS= read -r setting; do printf -v "$setting" '%s' "$token"; done < <(operator_boolean_setting_names)
        validate_effective_engine_config
        case "$token" in yes|1) expected=true;; *) expected=false;; esac
        while IFS= read -r setting; do [ "${!setting}" = "$expected" ]; done < <(operator_boolean_setting_names)
    done
    [ ! -e "$ws/project with spaces/.mock-prime/calls" ]
}

run_boolean_cli_fixture() {
    local ws="$1"
    shift
    env -i PATH="$ws/bin:$RALPHIE_TEST_GUARD_DIR:/usr/bin:/bin:/usr/sbin:/sbin" HOME="$ws/home" \
        TMPDIR="$ws/engine-scratch" PRIME_ENGINE_CMD="$ws/bin/prime-agent" \
        CODEX_ENGINE_CMD="$RALPHIE_TEST_GUARD_DIR/codex" CLAUDE_ENGINE_CMD="$RALPHIE_TEST_GUARD_DIR/claude" \
        RALPHIE_NOTIFICATIONS_ENABLED=false RALPHIE_STARTUP_OPERATIONAL_PROBE=false \
        RALPHIE_AUTO_UPDATE=true RALPHIE_SELF_UPDATE_TEST=1 BOOLEAN_UPDATE_RECEIPT="$ws/update.calls" \
        "$@" /bin/bash "$ws/ralphie.sh" --project "$ws/project with spaces" --engine prime-agent
}

install_boolean_update_guard() {
    local ws="$1"
    cat > "$ws/bin/curl" <<'EOF_BOOLEAN_UPDATE'
#!/usr/bin/env bash
printf 'unexpected update request\n' >> "$BOOLEAN_UPDATE_RECEIPT"
exit 97
EOF_BOOLEAN_UPDATE
    chmod +x "$ws/bin/curl"
}

assert_boolean_refusal_has_no_runtime_actions() {
    local ws="$1" status="$2" setting="$3"
    [ "$status" -ne 0 ]
    grep -q "Invalid boolean value for $setting" "$ws/run.out"
    [ ! -e "$ws/update.calls" ]
    [ ! -e "$ws/project with spaces/.mock-prime/calls" ]
    [ ! -e "$ws/project with spaces/.ralphie/state.env" ]
    [ ! -e "$ws/project with spaces/.ralphie/run.lock" ]
    [ ! -e "$ws/project with spaces/logs" ]
    [ ! -e "$ws/project with spaces/consensus" ]
}

test_operator_boolean_cli_refuses_before_update_runtime_or_inference() {
    local ws setting status token expected
    local -a settings_env=()
    for setting in AUTO_COMMIT_ON_PHASE_PASS AUTO_INIT_GIT_IF_MISSING REQUIRE_LINT_BEFORE_DONE \
        AUTO_UPDATE AUTO_UPDATE_ALLOW_DIRTY AUTO_UPDATE_ALLOW_INSECURE NOTIFICATIONS_ENABLED RESUME_REQUESTED; do
        ws="$(new_continuation_workspace)"
        install_boolean_update_guard "$ws"
        set +e
        run_boolean_cli_fixture "$ws" "RALPHIE_$setting=false-ish" > "$ws/run.out" 2>&1
        status=$?
        set -e
        assert_boolean_refusal_has_no_runtime_actions "$ws" "$status" "$setting"
    done
    for setting in AUTO_COMMIT_ON_PHASE_PASS AUTO_INIT_GIT_IF_MISSING REQUIRE_DOCUMENT_BEFORE_DONE \
        REQUIRE_PLAN_BACKLOG_CLEAR_BEFORE_DONE REBOOTSTRAP_REQUESTED STRICT_VALIDATION_NOOP; do
        ws="$(new_continuation_workspace)"
        install_boolean_update_guard "$ws"
        printf 'RALPHIE_%s=false-ish\n' "$setting" > "$ws/project with spaces/.ralphie/config.env"
        set +e
        run_boolean_cli_fixture "$ws" > "$ws/run.out" 2>&1
        status=$?
        set -e
        assert_boolean_refusal_has_no_runtime_actions "$ws" "$status" "$setting"
    done
    # The public preflight accepts the documented aliases without any inference.
    for token in yes no 1 0; do
        ws="$(new_continuation_workspace)"
        install_boolean_update_guard "$ws"
        settings_env=(RALPHIE_SKIP_AUTO_UPDATE=1)
        while IFS= read -r setting; do settings_env+=("RALPHIE_$setting=$token"); done < <(operator_boolean_setting_names)
        run_boolean_cli_fixture "$ws" "${settings_env[@]}" > "$ws/run.out" 2>&1
        grep -q RALPHIE_SELF_UPDATE_CURRENT_OK "$ws/run.out"
        [ ! -e "$ws/update.calls" ]
        [ ! -e "$ws/project with spaces/.mock-prime/calls" ]
        [ ! -e "$ws/project with spaces/.ralphie/state.env" ]
    done
}

test_engine_internal_config_keys_cannot_replace_process_bookkeeping() {
    local ws status key
    ws="$(new_continuation_workspace)"
    cat > "$ws/project with spaces/.ralphie/config.env" <<'EOF_CONFIG'
RALPHIE_TRAPS_INSTALLED=true
RALPHIE_CLEANUP_IN_PROGRESS=true
RALPHIE_CLEANUP_STATE_ENABLED=true
RALPHIE_BG_PIDS=1
RALPHIE_SELF_UPDATE_TEST=1
RALPHIE_UNKNOWN_SETTING=anything
EOF_CONFIG
    set +e
    run_continuation_fixture "$ws" --objective ' ' --plan-only > "$ws/refusal.out" 2>&1
    status=$?
    set -e
    [ "$status" -ne 0 ]
    [ ! -e "$ws/project with spaces/.mock-prime/calls" ]
    [ ! -e "$ws/project with spaces/.ralphie/run.lock" ]
    [ ! -d "$ws/project with spaces/.ralphie/run.lock.d" ]
    for key in TRAPS_INSTALLED CLEANUP_IN_PROGRESS CLEANUP_STATE_ENABLED BG_PIDS SELF_UPDATE_TEST UNKNOWN_SETTING; do
        grep -q "Ignoring unsupported config key 'RALPHIE_$key'" "$ws/refusal.out"
    done
    env -i PATH="$PATH" HOME="$ws/home" RALPHIE_TRAPS_INSTALLED=true RALPHIE_CLEANUP_IN_PROGRESS=true \
        RALPHIE_CLEANUP_STATE_ENABLED=true RALPHIE_BG_PIDS=1 /bin/bash -s -- "$RALPHIE_FILE" <<'EOF_ASSERT'
source "$1"
[ "$RALPHIE_TRAPS_INSTALLED" = false ]
[ "$RALPHIE_CLEANUP_IN_PROGRESS" = false ]
[ "$RALPHIE_CLEANUP_STATE_ENABLED" = false ]
[ "${#RALPHIE_BG_PIDS[@]}" = 0 ]
is_allowed_config_key RALPHIE_ENGINE
is_allowed_config_key RALPHIE_QUALITY_LEVEL
is_allowed_config_key RALPHIE_GATE_TIMEOUT_SECONDS
is_allowed_config_key RALPHIE_RESUME_REQUESTED
is_allowed_config_key RALPHIE_REBOOTSTRAP_REQUESTED
is_allowed_config_key RALPHIE_PRIME_MODEL
is_allowed_config_key PRIME_MODEL
is_allowed_config_key CODEX_ENGINE_CMD
is_allowed_config_key CLAUDE_ENGINE_CMD
EOF_ASSERT
}

test_engine_cli_scalars_keep_bytes_until_validation() {
    local ws option value status
    for option in --prime-provider --prime-model --prime-thinking --engine --auto-engine-preference; do
        ws="$(new_continuation_workspace)"
        case "$option" in
            --prime-provider) value=$'fixture-provider\n' ;;
            --prime-model) value=$'fixture-model\n' ;;
            --prime-thinking) value=$'max\n' ;;
            --engine|--auto-engine-preference) value=$'prime-agent\n' ;;
        esac
        set +e
        run_continuation_fixture "$ws" --objective 'Refuse multiline engine settings' --plan-only "$option" "$value" > "$ws/refusal.out" 2>&1
        status=$?
        set -e
        [ "$status" -ne 0 ]
        grep -q 'Unsupported multiline' "$ws/refusal.out"
        [ ! -e "$ws/project with spaces/.mock-prime/calls" ]
        [ ! -e "$ws/project with spaces/.ralphie/state.env" ]
    done
    ws="$(new_continuation_workspace)"
    configure_prime_adapter_fixture "$ws"
    parse_args --engine prime --prime-provider '-n' --prime-model $'literal\\model "quotes" and $value'
    [ "$PRIME_PROVIDER" = -n ]
    [ "$PRIME_MODEL" = $'literal\\model "quotes" and $value' ]
    [ "$(to_lower -n)" = -n ]
    [ "$(to_lower -e)" = -e ]
    validate_effective_engine_config
    validate_engine_options
    MOCK_PRIME_EXPECT_PROVIDER="$PRIME_PROVIDER"
    MOCK_PRIME_EXPECT_MODEL="$PRIME_MODEL"
    export MOCK_PRIME_EXPECT_PROVIDER MOCK_PRIME_EXPECT_MODEL
    run_agent_with_prompt "$ws/prompt.md" "$ws/engine.log" "$ws/answer.out" true
    [ "$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')" = 1 ]
    grep -F -- 'provider=-n model=literal\model "quotes" and $value thinking=max cwd=' "$ws/project with spaces/.mock-prime/calls"
    grep -q '<verdict>GO</verdict>' "$ws/answer.out"
}

test_engine_invalid_reasoning_is_not_replaced_with_a_paid_default() {
    local ws status name
    ws="$(new_continuation_workspace)"
    set +e
    run_continuation_fixture "$ws" --objective 'Refuse invalid explicit reasoning' --plan-only --prime-thinking -n > "$ws/refusal.out" 2>&1
    status=$?
    set -e
    [ "$status" -ne 0 ]
    grep -q 'Unsupported Prime thinking' "$ws/refusal.out"
    [ ! -e "$ws/project with spaces/.mock-prime/calls" ]
    [ ! -e "$ws/project with spaces/.ralphie/state.env" ]
    for name in CODEX_THINKING_OVERRIDE CLAUDE_THINKING_OVERRIDE; do
        ws="$(new_continuation_workspace)"
        printf 'RALPHIE_%s="misspelled"\n' "$name" > "$ws/project with spaces/.ralphie/config.env"
        set +e
        run_continuation_fixture "$ws" --objective 'Refuse invalid configured reasoning' --plan-only > "$ws/refusal.out" 2>&1
        status=$?
        set -e
        [ "$status" -ne 0 ]
        grep -q "Unsupported $name" "$ws/refusal.out"
        [ ! -e "$ws/project with spaces/.mock-prime/calls" ]
        [ ! -e "$ws/project with spaces/.ralphie/state.env" ]
    done
}

test_engine_capture_io_failure_is_fatal_without_paid_retry() {
    local ws context
    for context in serial conditional; do
        (
            ws="$(new_continuation_workspace)"
            configure_prime_adapter_fixture "$ws"
            RUN_AGENT_MAX_ATTEMPTS=3
            MOCK_PRIME_LARGE_OUTPUT=true
            export MOCK_PRIME_LARGE_OUTPUT
            (
                trap '' XFSZ
                ulimit -f 1
                set +e
                if [ "$context" = serial ]; then
                    run_agent_with_prompt "$ws/prompt.md" "$ws/engine.log" "$ws/answer.out" true
                    status=$?
                else
                    if run_agent_with_prompt "$ws/prompt.md" "$ws/engine.log" "$ws/answer.out" true; then status=0; else status=$?; fi
                fi
                [ "$status" -eq 126 ] || exit 1
                [ "$ENGINE_PERMANENT_FAILURE" = true ] || exit 1
                case "$ENGINE_PERMANENT_FAILURE_REASON" in *record*|*capture*) ;; *) exit 1;; esac
                [ "$SESSION_ATTEMPT_COUNT" = 1 ] || exit 1
            ) > "$ws/capture.out" 2>&1
            [ "$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')" = 1 ]
            [ ! -s "$ws/answer.out" ]
            [ -z "$(find "$ws/engine-scratch" -mindepth 1 -print -quit)" ]
        )
    done
    (
        ws="$(new_continuation_workspace)"
        configure_engine_canary_fixture "$ws"
        ENGINE_SELECTION_REQUESTED=claude
        cat > "$ws/bin/claude" <<'EOF_CANARY'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
    --version) printf 'offline canary 999.0.0\n'; exit 0;;
    --help) printf '%s\n' '-p, --print --dangerously-skip-permissions tool read write'; exit 0;;
esac
[ "${1:-}" = -p ]
cat >/dev/null
printf 'claude\n' >> "$CANARY_RECEIPT_DIR/calls"
printf '%04096d\n' 0
EOF_CANARY
        (
            trap '' XFSZ
            ulimit -f 1
            if ensure_engines_ready claude; then status=0; else status=$?; fi
            [ "$status" -eq 126 ] || exit 1
            [ "$ENGINE_PERMANENT_FAILURE" = true ] || exit 1
            [ "$SESSION_ATTEMPT_COUNT" = 1 ] || exit 1
        ) > "$ws/capture.out" 2>&1
        [ "$(wc -l < "$CANARY_RECEIPT_DIR/calls" | tr -d ' ')" = 1 ]
        [ -z "$(find "$ws/engine-scratch" -mindepth 1 -print -quit)" ]
    )
}

test_engine_capture_io_failure_stops_open_producers_without_retry() {
    command -v python3 >/dev/null 2>&1 || return 200
    local ws mode
    for mode in endless pause; do
        ws="$(new_continuation_workspace)"
        mv "$ws/bin/prime-agent" "$ws/bin/prime-agent-fixture"
        cat > "$ws/bin/prime-agent" <<'EOF_CAPTURE_PID'
#!/usr/bin/env bash
case "${1:-}" in --help|--version) exec "$CAPTURE_FIXTURE_ENGINE" "$@" ;; esac
printf '%s\n' "$$" > "$CAPTURE_FIXTURE_PID"
if [ "$CAPTURE_FIXTURE_MODE" = pause ]; then
    # Keep stdout open below the cap after the recording write has failed.
    cat >/dev/null
    printf 'fixture inference\n' >> "$CAPTURE_FIXTURE_CALLS"
    printf '%01048576d' 0
    exec sleep 60
fi
exec "$CAPTURE_FIXTURE_ENGINE" "$@"
EOF_CAPTURE_PID
        chmod +x "$ws/bin/prime-agent"
        python3 - "$ENGINE_SUITE_DIR/run-engine-contract-suite.sh" "$ws" "$mode" <<'PY_CAPTURE_IO'
import os
import pathlib
import signal
import subprocess
import sys

suite, workspace, mode = sys.argv[1:]
root = pathlib.Path(workspace)
code = r'''
source "$1"
prepare_isolated_target
trap 'cleanup_isolated_target; cleanup_offline_test_guards' EXIT
configure_prime_adapter_fixture "$2"
COMMAND_TIMEOUT_SECONDS=0
ENGINE_OUTPUT_MAX_BYTES=4096
[ "$3" != pause ] || ENGINE_OUTPUT_MAX_BYTES=16777216
RUN_AGENT_MAX_ATTEMPTS=3
export MOCK_PRIME_INFINITE_OUTPUT=true
export CAPTURE_FIXTURE_ENGINE="$2/bin/prime-agent-fixture"
export CAPTURE_FIXTURE_PID="$2/engine.pid"
export CAPTURE_FIXTURE_CALLS="$2/calls"
export CAPTURE_FIXTURE_MODE="$3"
trap '' XFSZ
ulimit -S -f 1
if run_agent_with_prompt "$2/prompt.md" "$2/engine.log" "$2/answer.out" true; then status=0; else status=$?; fi
[ "$status" -eq 126 ] || exit 1
[ "$ENGINE_PERMANENT_FAILURE" = true ] || exit 1
[ "$SESSION_ATTEMPT_COUNT" -eq 1 ] || exit 1
case "$ENGINE_PERMANENT_FAILURE_REASON" in *record*|*capture*) ;; *) exit 1 ;; esac
'''
process = subprocess.Popen(['/bin/bash', '-c', code, 'capture-io-fixture', suite, workspace, mode],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           start_new_session=True)
try:
    output, _ = process.communicate(timeout=10)
except subprocess.TimeoutExpired:
    os.killpg(process.pid, signal.SIGKILL)
    output, _ = process.communicate()
    raise SystemExit('Recording failure did not stop ' + mode + ' producer:\n' + output.decode(errors='replace'))
if process.returncode:
    raise SystemExit('Recording-failure fixture failed:\n' + output.decode(errors='replace'))
calls = root / ('project with spaces/.mock-prime/calls' if mode == 'endless' else 'calls')
assert len(calls.read_text().splitlines()) == 1
assert not (root / 'answer.out').read_bytes()
assert not list((root / 'engine-scratch').iterdir()), 'Engine scratch was not cleaned'
pid = (root / 'engine.pid').read_text().strip()
state = subprocess.run(['ps', '-p', pid, '-o', 'stat='], stdout=subprocess.PIPE, text=True).stdout.strip()
assert not state or 'Z' in state, 'Engine is still running: ' + pid
PY_CAPTURE_IO
    done
}

test_engine_metadata_io_failure_does_not_publish_partial_help() {
    local ws status
    ws="$(new_continuation_workspace)"
    configure_prime_adapter_fixture "$ws"
    (
        ulimit -f 1
        set +e
        if run_bounded_engine_metadata /bin/bash -c 'printf "%05000d\n" 0' > "$ws/metadata.out"; then status=0; else status=$?; fi
        [ "$status" -ne 0 ] || exit 1
    ) > "$ws/probe.out" 2>&1
    [ ! -s "$ws/metadata.out" ]
    [ -z "$(find "$ws/engine-scratch" -mindepth 1 -print -quit)" ]
}

engine_contract_case() {
    local name="$1"
    if [ -n "${ENGINE_CONTRACT_FILTER:-}" ] && [[ "$name" != *"$ENGINE_CONTRACT_FILTER"* ]]; then return 0; fi
    run_case "$name" "$2"
}

engine_contract_main() {
    ENGINE_CONTRACT_FILTER="${1:-}"
    prepare_isolated_target
    trap 'cleanup_isolated_target; cleanup_offline_test_guards' EXIT
    capture_repo_tracked_status_baseline
    engine_contract_case alias_environment_precedence test_engine_alias_environment_precedence
    engine_contract_case config_literal_round_trip_and_multiline_refusal test_engine_config_literal_round_trip_and_multiline_refusal
    engine_contract_case raw_awk_paths_and_allowlist_regex test_engine_raw_awk_paths_and_allowlist_regex
    engine_contract_case decimal_boolean_and_option_value_normalization test_engine_decimal_boolean_and_option_value_normalization
    engine_contract_case invalid_limits_refuse_before_inference test_engine_invalid_limits_refuse_before_inference
    engine_contract_case cost_rounds_up_and_overflow_refuses test_engine_cost_rounds_up_and_overflow_refuses
    engine_contract_case free_metadata_is_lazy_and_bounded test_engine_free_metadata_is_lazy_and_bounded
    engine_contract_case redacted_auth_stops_paid_retries test_engine_redacted_auth_stops_paid_retries
    engine_contract_case permanent_canary_failure_is_not_retried test_engine_permanent_canary_failure_is_not_retried
    engine_contract_case oversized_canary_cannot_report_healthy test_engine_oversized_canary_cannot_report_healthy
    engine_contract_case explicit_missing_codex_schema_refuses_without_calls test_engine_explicit_missing_codex_schema_refuses_without_calls
    engine_contract_case canary_budget_admission test_session_budget_accounts_for_health_canaries_and_blocks_retry
    engine_contract_case operator_booleans_reject_malformed_and_normalize_aliases test_operator_booleans_reject_malformed_and_normalize_aliases
    engine_contract_case operator_boolean_cli_refuses_before_update_runtime_or_inference test_operator_boolean_cli_refuses_before_update_runtime_or_inference
    engine_contract_case internal_config_keys_cannot_replace_process_bookkeeping test_engine_internal_config_keys_cannot_replace_process_bookkeeping
    engine_contract_case cli_scalars_keep_bytes_until_validation test_engine_cli_scalars_keep_bytes_until_validation
    engine_contract_case invalid_reasoning_is_not_replaced_with_a_paid_default test_engine_invalid_reasoning_is_not_replaced_with_a_paid_default
    engine_contract_case capture_io_failure_is_fatal_without_paid_retry test_engine_capture_io_failure_is_fatal_without_paid_retry
    engine_contract_case capture_io_failure_stops_open_producers_without_retry test_engine_capture_io_failure_stops_open_producers_without_retry
    engine_contract_case metadata_io_failure_does_not_publish_partial_help test_engine_metadata_io_failure_does_not_publish_partial_help
    info "Engine contracts total: $TOTAL_COUNT | Passed: $PASS_COUNT | Failed: $FAIL_COUNT | Skipped: $SKIP_COUNT"
    [ "$TOTAL_COUNT" -gt 0 ]
    [ "$TOTAL_COUNT" -eq "$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))" ]
    [ "$FAIL_COUNT" -eq 0 ]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then engine_contract_main "$@"; fi
