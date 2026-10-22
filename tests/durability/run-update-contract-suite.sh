#!/usr/bin/env bash
set -euo pipefail

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/durability/run-durability-suite.sh
source "$SUITE_DIR/run-durability-suite.sh"

new_update_workspace() {
    local ws
    ws="$(make_workspace)"
    mkdir -p "$ws/home" "$ws/project" "$ws/bin"
    cat > "$ws/candidate.sh" <<'EOF_CANDIDATE'
#!/usr/bin/env bash
# Ralphie - Autonomous lifecycle orchestration update fixture.
# update-contract-candidate
set -euo pipefail
SCRIPT_VERSION="999.0.0"
parse_args() { :; }
ensure_project_bootstrap() { :; }
run_swarm_consensus() { :; }
enforce_terminal_done_requirements() { :; }
self_update_check_and_reexec() { :; }
main() {
    local -a phases=("plan" "build" "test" "refactor" "lint" "document")
    parse_args "$@"
    self_update_check_and_reexec "$@"
    [ "${RALPHIE_SKIP_AUTO_UPDATE:-}" = 1 ]
    if [ "${UPDATE_TEST_RELATIVE:-false}" = true ]; then
        [ "$1" = --project ] && [ "$2" = project ] && cd "$2"
        [ "$3" = --spec ] && [ "$4" = seed.md ]
        [ "$(cat ../seed.md)" = 'exact seed bytes' ]
    fi
    printf 'UPDATE_CANDIDATE_OK\n'
}
main "$@"
EOF_CANDIDATE
    printf 'exact seed bytes\n' > "$ws/seed.md"
    printf '%s' "$ws"
}

run_update_fixture() {
    local ws="$1"
    shift
    env -i PATH="$ws/bin:$PATH" HOME="$ws/home" \
        RALPHIE_SELF_UPDATE_TEST=1 AUTO_UPDATE=true AUTO_UPDATE_LOCK_TIMEOUT_SECONDS=0 \
        AUTO_UPDATE_URL="file://$ws/candidate.sh" UPDATE_TEST_RELATIVE="${UPDATE_TEST_RELATIVE:-false}" \
        /bin/bash "$ws/ralphie.sh" "$@"
}

test_update_preserves_relative_arguments_and_nonexecutable_mode() {
    local ws
    ws="$(new_update_workspace)"
    chmod 644 "$ws/ralphie.sh"
    (
        cd "$ws"
        UPDATE_TEST_RELATIVE=true run_update_fixture "$ws" --project project --spec seed.md > result.log 2>&1
        grep -q '^UPDATE_CANDIDATE_OK$' result.log
        grep -q '^# update-contract-candidate$' ralphie.sh
        [ ! -x ralphie.sh ]
        [ ! -e ralphie.sh.update.lock ]
        [ "$(find . -name 'ralphie.sh.update.*' -type f | wc -l | tr -d ' ')" = 0 ]
    )
}

test_update_backup_alias_cannot_overwrite_external_file() {
    local ws
    ws="$(new_update_workspace)"
    mkdir -p "$ws/.ralphie/self-update"
    printf 'external sentinel\n' > "$ws/external"
    ln -s "$ws/external" "$ws/.ralphie/self-update/ralphie.sh.20261022_130000.bak"
    cat > "$ws/bin/date" <<'EOF_DATE'
#!/usr/bin/env bash
if [ "${1:-}" = '+%Y%m%d_%H%M%S' ]; then printf '20261022_130000\n'; else exec /bin/date "$@"; fi
EOF_DATE
    chmod +x "$ws/bin/date"
    cp "$ws/ralphie.sh" "$ws/original"
    run_update_fixture "$ws" > "$ws/result.log" 2>&1
    grep -q '^UPDATE_CANDIDATE_OK$' "$ws/result.log"
    [ "$(cat "$ws/external")" = 'external sentinel' ]
    [ -L "$ws/.ralphie/self-update/ralphie.sh.20261022_130000.bak" ]
    local backup
    backup="$(find "$ws/.ralphie/self-update" -type f -name 'ralphie.sh.backup.*' | head -n 1)"
    [ -n "$backup" ]
    cmp "$ws/original" "$backup"
}

test_update_refuses_symlink_launcher_and_abandoned_claim() {
    local ws
    ws="$(new_update_workspace)"
    mv "$ws/ralphie.sh" "$ws/actual.sh"
    ln -s actual.sh "$ws/ralphie.sh"
    run_update_fixture "$ws" > "$ws/link.log" 2>&1
    [ -L "$ws/ralphie.sh" ]
    grep -q 'Auto-update skipped' "$ws/link.log"
    grep -q '^RALPHIE_SELF_UPDATE_CURRENT_OK$' "$ws/link.log"
    rm "$ws/ralphie.sh"
    cp "$ws/actual.sh" "$ws/ralphie.sh"
    mkdir "$ws/ralphie.sh.update.lock"
    printf 'retained abandoned claim\n' > "$ws/ralphie.sh.update.lock/witness"
    run_update_fixture "$ws" > "$ws/lock.log" 2>&1
    cmp "$ws/actual.sh" "$ws/ralphie.sh"
    grep -q 'another Ralphie self-update' "$ws/lock.log"
    grep -q '^retained abandoned claim$' "$ws/ralphie.sh.update.lock/witness"
}

test_update_fetch_is_bounded_and_preserves_current_script() {
    local ws
    ws="$(new_update_workspace)"
    cp "$ws/ralphie.sh" "$ws/original"
    (
        source "$ws/ralphie.sh"
        AUTO_UPDATE_URL=https://fixture.invalid/ralphie.sh
        AUTO_UPDATE_TIMEOUT_SECONDS=1
        self_update_download_stream() { while :; do printf '# trickle\n'; sleep 0.1; done; }
        if self_update_transaction "$ws/ralphie.sh" "$AUTO_UPDATE_URL" > "$ws/fetch.log" 2>&1; then exit 1; fi
        cmp "$ws/original" "$ws/ralphie.sh"
        [ ! -e "$ws/ralphie.sh.update.lock" ]
        [ "$(find "$ws" -maxdepth 1 -type f -name 'ralphie.sh.update.*' | wc -l | tr -d ' ')" = 0 ]
        grep -q 'deadline reached' "$ws/fetch.log"
    )
}

test_stream_install_uses_unique_temp_and_checks_target_type() {
    local ws
    ws="$(make_workspace)"
    cp "$ws/ralphie.sh" "$ws/input.sh"
    rm "$ws/ralphie.sh"
    printf 'external sentinel\n' > "$ws/external"
    (
        cd "$ws"
        /bin/bash -c 'ln -s "$PWD/external" "$PWD/ralphie.sh.tmp.$$"; exec /bin/bash -s -- --help' < input.sh > install.log 2>&1
        [ "$(cat external)" = 'external sentinel' ]
        [ -f ralphie.sh ] && [ ! -L ralphie.sh ]
        grep -q 'Installed ralphie.sh' install.log
        rm ralphie.sh
        mkdir ralphie.sh
        if /bin/bash -s -- --help < input.sh > directory.log 2>&1; then exit 1; fi
        [ "$(find ralphie.sh -type f | wc -l | tr -d ' ')" = 0 ]
        rmdir ralphie.sh
        ln -s external ralphie.sh
        if /bin/bash -s -- --help < input.sh > symlink.log 2>&1; then exit 1; fi
        [ -L ralphie.sh ]
        [ "$(cat external)" = 'external sentinel' ]
    )
}

test_stream_truncation_cannot_replace_current_script() {
    local ws
    ws="$(make_workspace)"
    cp "$ws/ralphie.sh" "$ws/original"
    sed '$d' "$ws/original" > "$ws/truncated"
    (
        cd "$ws"
        if /bin/bash -s -- --help < truncated > install.log 2>&1; then exit 1; fi
        cmp original ralphie.sh
        [ "$(find . -maxdepth 1 -type f -name 'ralphie.sh.install.*' | wc -l | tr -d ' ')" = 0 ]
    )
}

test_json_escapes_all_controls_and_preserves_unicode() {
    (
        source "$RALPHIE_FILE"
        local input encoded
        input=$'\001\b\f\033\n\t\r"\\雪'
        encoded="$(json_escape_string "$input")"
        [ "$encoded" = '\u0001\u0008\u000c\u001b\u000a\u0009\u000d\"\\雪' ]
        if printf '%s' "$encoded" | LC_ALL=C grep -q $'[\001-\037]'; then exit 1; fi
    )
}

test_telegram_discovery_stdout_is_only_identifier() {
    (
        source "$RALPHIE_FILE"
        telegram_get_updates_raw() { printf '%s' '{"ok":true,"result":[{"message":{"chat":{"id":-123}}}]}'; }
        [ "$(telegram_suggest_chat_id_raw fixture-token 2>/dev/null)" = -123 ]
    )
}

test_tts_http_error_is_not_audio() {
    (
        source "$RALPHIE_FILE"
        local ws
        ws="$(make_workspace)"
        curl() {
            local fail_http=false output="" arg previous=""
            for arg in "$@"; do
                [ "$previous" != --output ] || output="$arg"
                case "$arg" in -f*|--fail) fail_http=true ;; esac
                previous="$arg"
            done
            [ -n "$output" ]
            printf '{"error":"HTTP 500 fixture"}\n' > "$output"
            [ "$fail_http" = false ] || return 22
        }
        if generate_chutes_tts_audio_file_raw fixture-key https://fixture.invalid voice 1 text "$ws/audio"; then exit 1; fi
    )
}

main() {
    prepare_isolated_target
    trap 'cleanup_isolated_target; cleanup_offline_test_guards' EXIT
    capture_repo_tracked_status_baseline
    local name
    for name in \
        update_preserves_relative_arguments_and_nonexecutable_mode \
        update_backup_alias_cannot_overwrite_external_file \
        update_refuses_symlink_launcher_and_abandoned_claim \
        update_fetch_is_bounded_and_preserves_current_script \
        stream_install_uses_unique_temp_and_checks_target_type \
        stream_truncation_cannot_replace_current_script \
        json_escapes_all_controls_and_preserves_unicode \
        telegram_discovery_stdout_is_only_identifier \
        tts_http_error_is_not_audio; do
        if [ -n "${1:-}" ] && [[ "$name" != *"$1"* ]]; then continue; fi
        run_case "$name" "test_$name"
    done
    info "Update/input total: $TOTAL_COUNT | Passed: $PASS_COUNT | Failed: $FAIL_COUNT | Skipped: $SKIP_COUNT"
    [ "$TOTAL_COUNT" -gt 0 ]
    [ "$TOTAL_COUNT" -eq "$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))" ]
    [ "$FAIL_COUNT" -eq 0 ]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
