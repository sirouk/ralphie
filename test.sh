#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

LIVE_ENGINE="${LIVE_ENGINE:-claude}"
LIVE_MODE="auto" # auto|on|off
LIVE_TIMEOUT_SECONDS="${LIVE_TIMEOUT_SECONDS:-120}"
STRESS_SCENARIOS="${STRESS_SCENARIOS:-full,retry,resume}"
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"
EXERCISE_TTS_FALLBACK="false"
VALID_STRESS_SCENARIOS="full,retry,resume"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fail() { printf '[FAIL] %s\n' "$*" >&2; }
pass() { printf '[PASS] %s\n' "$*"; }

print_usage() {
    cat <<'EOF'
Usage: ./test.sh [options]

Runs the pre-ship validation sequence:
  1) bash syntax checks for ralphie.sh and support scripts
  2) shellcheck support scripts when available
  3) offline setup-agent-subrepos fixture check
  4) tests/durability/run-durability-suite.sh
  5) tests/durability/run-claude-phase-stress.sh
  6) tests/durability/run-live-smoke.sh (optional, controlled by flags)

Options:
  --live-engine codex|claude     Live smoke provider API path (default: claude)
  --live                         Require and run live smoke (fail if creds missing)
  --auto-live                    Run live smoke only when creds are available (default)
  --skip-live                    Skip live smoke
  --live-timeout-seconds N       Timeout wrapper for live smoke (default: 120)
  --stress-scenarios LIST        Stress scenarios (default: full,retry,resume)
  --discord-webhook-url URL      Optional Discord webhook for stress run notifications
  --exercise-tts-fallback        Pass through to phase stress (requires webhook)
  --help, -h                     Show this help

Environment variables (optional):
  LIVE_ENGINE, LIVE_MODE, LIVE_TIMEOUT_SECONDS, STRESS_SCENARIOS, DISCORD_WEBHOOK_URL
EOF
}

is_number() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

require_arg_value() {
    local flag="$1"
    local value="${2:-}"
    if [ -z "$value" ] || [[ "$value" == --* ]]; then
        fail "$flag requires a value"
        exit 1
    fi
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

stress_scenario_is_valid() {
    case "${1:-}" in
        full|retry|resume) return 0 ;;
        *) return 1 ;;
    esac
}

validate_stress_scenarios() {
    local raw="${1:-}"
    local -a scenario_values=()
    local old_ifs scenario

    if [ -z "$raw" ]; then
        fail "Invalid --stress-scenarios value: empty (expected: $VALID_STRESS_SCENARIOS)"
        exit 1
    fi
    case "$raw" in
        ,*|*,|*,,*)
            fail "Invalid --stress-scenarios value '$raw' (expected comma-separated names: $VALID_STRESS_SCENARIOS)"
            exit 1
            ;;
    esac

    old_ifs="$IFS"
    IFS=,
    read -r -a scenario_values <<< "$raw"
    IFS="$old_ifs"

    for scenario in "${scenario_values[@]}"; do
        if ! stress_scenario_is_valid "$scenario"; then
            fail "Invalid stress scenario '$scenario' (expected one of: $VALID_STRESS_SCENARIOS)"
            exit 1
        fi
    done
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --live-engine)
                require_arg_value "--live-engine" "${2:-}"
                LIVE_ENGINE="${2:-}"
                shift 2
                ;;
            --live)
                LIVE_MODE="on"
                shift
                ;;
            --auto-live)
                LIVE_MODE="auto"
                shift
                ;;
            --skip-live)
                LIVE_MODE="off"
                shift
                ;;
            --live-timeout-seconds)
                require_arg_value "--live-timeout-seconds" "${2:-}"
                LIVE_TIMEOUT_SECONDS="${2:-}"
                shift 2
                ;;
            --stress-scenarios)
                require_arg_value "--stress-scenarios" "${2:-}"
                STRESS_SCENARIOS="${2:-}"
                shift 2
                ;;
            --discord-webhook-url)
                require_arg_value "--discord-webhook-url" "${2:-}"
                DISCORD_WEBHOOK_URL="${2:-}"
                shift 2
                ;;
            --exercise-tts-fallback)
                EXERCISE_TTS_FALLBACK="true"
                shift
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            *)
                fail "Unknown argument: $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

validate_args() {
    case "$LIVE_ENGINE" in
        codex|claude) ;;
        *)
            fail "Invalid --live-engine value '$LIVE_ENGINE' (expected: codex|claude)"
            exit 1
            ;;
    esac

    case "$LIVE_MODE" in
        on|off|auto) ;;
        *)
            fail "Invalid live mode '$LIVE_MODE' (expected: on|off|auto)"
            exit 1
            ;;
    esac

    if ! is_number "$LIVE_TIMEOUT_SECONDS" || [ "$LIVE_TIMEOUT_SECONDS" -lt 10 ]; then
        fail "Invalid --live-timeout-seconds value '$LIVE_TIMEOUT_SECONDS' (expected integer >= 10)"
        exit 1
    fi

    validate_stress_scenarios "$STRESS_SCENARIOS"

    if [ "$EXERCISE_TTS_FALLBACK" = "true" ] && [ -z "$DISCORD_WEBHOOK_URL" ]; then
        fail "--exercise-tts-fallback requires --discord-webhook-url"
        exit 1
    fi
}

run_support_bash_syntax_checks() {
    local -a shell_files=(
        ./ralphie.sh
        ./test.sh
        ./tests/durability/run-claude-phase-stress.sh
        ./tests/durability/run-live-smoke.sh
        ./tests/durability/mock-claude-control.sh
        ./engines/setup-agent-subrepos.sh
    )
    local file

    for file in "${shell_files[@]}"; do
        bash -n "$file"
    done
}

run_support_shellcheck_if_available() {
    local -a shell_files=(
        ./test.sh
        ./tests/durability/run-claude-phase-stress.sh
        ./tests/durability/run-live-smoke.sh
        ./tests/durability/mock-claude-control.sh
        ./engines/setup-agent-subrepos.sh
    )

    if ! command -v shellcheck >/dev/null 2>&1; then
        warn "shellcheck skipped (not installed)."
        return 0
    fi

    shellcheck "${shell_files[@]}"
}

run_setup_agent_subrepos_fixture_check() {
    local tmpd rc=0
    tmpd="$(mktemp -d /tmp/ralphie-setup-agent-fixture.XXXXXX)"

    set +e
    (
        set -euo pipefail

        mkdir -p "$tmpd/repo/engines" "$tmpd/bin"
        cp ./engines/setup-agent-subrepos.sh "$tmpd/repo/engines/setup-agent-subrepos.sh"

        cat > "$tmpd/bin/git" <<'EOF_GIT'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "-C" ]; then
    shift 2
fi

case "${1:-}" in
    clone)
        dest=""
        for arg in "$@"; do
            dest="$arg"
        done
        [ -n "$dest" ]
        mkdir -p "$dest/.git"
        ;;
    rev-parse)
        case "${2:-}" in
            HEAD) echo "0123456789abcdef0123456789abcdef01234567" ;;
            --is-inside-work-tree) echo "true" ;;
        esac
        ;;
    *)
        ;;
esac
EOF_GIT
        chmod +x "$tmpd/bin/git" "$tmpd/repo/engines/setup-agent-subrepos.sh"

        PATH="$tmpd/bin:$PATH" "$tmpd/repo/engines/setup-agent-subrepos.sh" --mode clone \
            >"$tmpd/setup.out" 2>"$tmpd/setup.err"

        [ -f "$tmpd/repo/maps/agent-source-map.yaml" ]
        [ -f "$tmpd/repo/maps/binary-steering-map.yaml" ]

        local plan_count
        plan_count="$(grep -c '^  plan:' "$tmpd/repo/maps/binary-steering-map.yaml" || true)"
        [ "$plan_count" -eq 1 ]
    )
    rc=$?
    set -e

    rm -rf "$tmpd"
    return "$rc"
}

run_markdown_hygiene_fixture_check() {
    local tmpd rc=0
    tmpd="$(mktemp -d /tmp/ralphie-markdown-hygiene.XXXXXX)"

    set +e
    (
        set -euo pipefail

        mkdir -p "$tmpd/research" "$tmpd/specs" "$tmpd/.ralphie" "$tmpd/.specify/memory"
        touch "$tmpd/.specify/memory/constitution.md"
        cp ./ralphie.sh "$tmpd/ralphie.sh"
        cd "$tmpd"

        HOME=/home/operator RALPHIE_MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX='(^|[^[:alnum:]_.-])/home/product(/|$)' bash <<'EOF_MARKDOWN'
set -euo pipefail
source ./ralphie.sh

printf '%s\n' 'Allowed layout: /home/product/app' > allowed.md
if file_has_local_identity_leakage allowed.md; then
    echo "allowlisted documented path was reported as local leakage" >&2
    exit 1
fi

printf '%s\n' 'Local leak: /home/other/private' > leaked.md
if ! file_has_local_identity_leakage leaked.md; then
    echo "non-allowlisted local path was not reported as leakage" >&2
    exit 1
fi

printf '%s\n' \
    'Allowed layout: /home/product/app' \
    'Transcript leak: tokens used' \
    'Other leak: /home/other/private' > README.md
sanitize_markdown_artifact_file README.md
grep -q '/home/product/app' README.md
if grep -q 'tokens used' README.md || grep -q '/home/other/private' README.md; then
    echo "markdown sanitizer did not remove transcript or non-allowlisted path leakage" >&2
    exit 1
fi
EOF_MARKDOWN

        HOME=/home/operator RALPHIE_MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX='[' bash <<'EOF_INVALID'
set -euo pipefail
source ./ralphie.sh
if [ -n "$MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX" ]; then
    echo "invalid markdown path allowlist regex should be disabled" >&2
    exit 1
fi
printf '%s\n' 'Still a leak: /home/product/app' > invalid.md
if ! file_has_local_identity_leakage invalid.md; then
    echo "invalid allowlist regex caused local path detection to fail open" >&2
    exit 1
fi
EOF_INVALID
    )
    rc=$?
    set -e

    rm -rf "$tmpd"
    return "$rc"
}

run_self_update_fixture_check() {
    local tmpd rc=0 timeout_cmd output
    tmpd="$(mktemp -d /tmp/ralphie-self-update.XXXXXX)"
    timeout_cmd="$(get_timeout_cmd)"

    set +e
    (
        set -euo pipefail

        mkdir -p "$tmpd/project" "$tmpd/home"
        cp ./ralphie.sh "$tmpd/project/ralphie.sh"
        chmod +x "$tmpd/project/ralphie.sh"
        cat > "$tmpd/remote-ralphie.sh" <<'EOF_REMOTE'
#!/usr/bin/env bash
#
# Ralphie - Unified autonomous loop for Codex and Claude Code.
# Fixture update used by the self-update regression test.
set -euo pipefail
SCRIPT_VERSION="fixture-self-update"
parse_args() { :; }
self_update_check_and_reexec() { :; }
main() {
    parse_args "$@"
    self_update_check_and_reexec "$@"
    [ "${RALPHIE_SKIP_AUTO_UPDATE:-}" = "1" ] || exit 11
    if [ "${RALPHIE_SELF_UPDATE_TEST:-}" = "1" ]; then
        echo "RALPHIE_SELF_UPDATE_FIXTURE_OK"
        exit 0
    fi
    echo "fixture updated script executed"
}
main "$@"
# Padding keeps this fixture above the self-update minimum-size guard.
# 0123456789 abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ
# 0123456789 abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ
# 0123456789 abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ
EOF_REMOTE
        chmod +x "$tmpd/remote-ralphie.sh"

        mkdir -p "$tmpd/default-on"
        cp ./ralphie.sh "$tmpd/default-on/ralphie.sh"
        chmod +x "$tmpd/default-on/ralphie.sh"
        if [ -n "$timeout_cmd" ]; then
            output="$(env -u AUTO_UPDATE -u RALPHIE_AUTO_UPDATE HOME="$tmpd/home" RALPHIE_SELF_UPDATE_TEST=1 AUTO_UPDATE_URL="file://$tmpd/remote-ralphie.sh" "$timeout_cmd" 20 "$tmpd/default-on/ralphie.sh" --no-resume 2>&1)"
        else
            output="$(env -u AUTO_UPDATE -u RALPHIE_AUTO_UPDATE HOME="$tmpd/home" RALPHIE_SELF_UPDATE_TEST=1 AUTO_UPDATE_URL="file://$tmpd/remote-ralphie.sh" "$tmpd/default-on/ralphie.sh" --no-resume 2>&1)"
        fi
        printf '%s\n' "$output" | grep -q "RALPHIE_SELF_UPDATE_FIXTURE_OK"
        grep -q 'SCRIPT_VERSION="fixture-self-update"' "$tmpd/default-on/ralphie.sh"
        ls "$tmpd/default-on/.ralphie/self-update"/ralphie.sh.*.bak >/dev/null 2>&1
        test ! -e "$tmpd/default-on/.ralphie/self-update/update.lock"

        if [ -n "$timeout_cmd" ]; then
            output="$(HOME="$tmpd/home" RALPHIE_SELF_UPDATE_TEST=1 AUTO_UPDATE=true AUTO_UPDATE_URL="file://$tmpd/remote-ralphie.sh" "$timeout_cmd" 20 "$tmpd/project/ralphie.sh" --no-resume 2>&1)"
        else
            output="$(HOME="$tmpd/home" RALPHIE_SELF_UPDATE_TEST=1 AUTO_UPDATE=true AUTO_UPDATE_URL="file://$tmpd/remote-ralphie.sh" "$tmpd/project/ralphie.sh" --no-resume 2>&1)"
        fi
        printf '%s\n' "$output" | grep -q "RALPHIE_SELF_UPDATE_FIXTURE_OK"
        grep -q 'SCRIPT_VERSION="fixture-self-update"' "$tmpd/project/ralphie.sh"
        ls "$tmpd/project/.ralphie/self-update"/ralphie.sh.*.bak >/dev/null 2>&1
        test ! -e "$tmpd/project/.ralphie/self-update/update.lock"

        mkdir -p "$tmpd/noop"
        cp ./ralphie.sh "$tmpd/noop/ralphie.sh"
        chmod +x "$tmpd/noop/ralphie.sh"
        if [ -n "$timeout_cmd" ]; then
            output="$(HOME="$tmpd/home" RALPHIE_SELF_UPDATE_TEST=1 AUTO_UPDATE=true AUTO_UPDATE_URL="file://$tmpd/noop/ralphie.sh" "$timeout_cmd" 20 "$tmpd/noop/ralphie.sh" --no-resume 2>&1)"
        else
            output="$(HOME="$tmpd/home" RALPHIE_SELF_UPDATE_TEST=1 AUTO_UPDATE=true AUTO_UPDATE_URL="file://$tmpd/noop/ralphie.sh" "$tmpd/noop/ralphie.sh" --no-resume 2>&1)"
        fi
        printf '%s\n' "$output" | grep -q "Auto-update: current ralphie.sh already matches remote."
        printf '%s\n' "$output" | grep -q "RALPHIE_SELF_UPDATE_CURRENT_OK"
        test ! -e "$tmpd/noop/.ralphie/self-update/update.lock"

        mkdir -p "$tmpd/invalid"
        cp ./ralphie.sh "$tmpd/invalid/ralphie.sh"
        chmod +x "$tmpd/invalid/ralphie.sh"
        printf '%s\n' '#!/bin/sh' 'echo nope' > "$tmpd/not-ralphie.sh"
        if [ -n "$timeout_cmd" ]; then
            output="$(HOME="$tmpd/home" RALPHIE_SELF_UPDATE_TEST=1 AUTO_UPDATE=true AUTO_UPDATE_URL="file://$tmpd/not-ralphie.sh" "$timeout_cmd" 20 "$tmpd/invalid/ralphie.sh" --no-resume 2>&1)"
        else
            output="$(HOME="$tmpd/home" RALPHIE_SELF_UPDATE_TEST=1 AUTO_UPDATE=true AUTO_UPDATE_URL="file://$tmpd/not-ralphie.sh" "$tmpd/invalid/ralphie.sh" --no-resume 2>&1)"
        fi
        printf '%s\n' "$output" | grep -q "failed validation"
        printf '%s\n' "$output" | grep -q "RALPHIE_SELF_UPDATE_CURRENT_OK"
        if grep -q 'fixture-self-update' "$tmpd/invalid/ralphie.sh"; then
            return 1
        fi
        test ! -e "$tmpd/invalid/.ralphie/self-update/update.lock"

        mkdir -p "$tmpd/insecure"
        cp ./ralphie.sh "$tmpd/insecure/ralphie.sh"
        chmod +x "$tmpd/insecure/ralphie.sh"
        if [ -n "$timeout_cmd" ]; then
            output="$(HOME="$tmpd/home" RALPHIE_SELF_UPDATE_TEST=1 AUTO_UPDATE=true AUTO_UPDATE_URL="http://example.invalid/ralphie.sh" "$timeout_cmd" 20 "$tmpd/insecure/ralphie.sh" --no-resume 2>&1)"
        else
            output="$(HOME="$tmpd/home" RALPHIE_SELF_UPDATE_TEST=1 AUTO_UPDATE=true AUTO_UPDATE_URL="http://example.invalid/ralphie.sh" "$tmpd/insecure/ralphie.sh" --no-resume 2>&1)"
        fi
        printf '%s\n' "$output" | grep -q "must be https"
        printf '%s\n' "$output" | grep -q "RALPHIE_SELF_UPDATE_CURRENT_OK"

        mkdir -p "$tmpd/locked/.ralphie/self-update/update.lock"
        cp ./ralphie.sh "$tmpd/locked/ralphie.sh"
        chmod +x "$tmpd/locked/ralphie.sh"
        printf '%s\n' "$$" > "$tmpd/locked/.ralphie/self-update/update.lock/pid"
        if [ -n "$timeout_cmd" ]; then
            output="$(HOME="$tmpd/home" RALPHIE_SELF_UPDATE_TEST=1 AUTO_UPDATE=true AUTO_UPDATE_URL="file://$tmpd/remote-ralphie.sh" AUTO_UPDATE_LOCK_TIMEOUT_SECONDS=0 "$timeout_cmd" 20 "$tmpd/locked/ralphie.sh" --no-resume 2>&1)"
        else
            output="$(HOME="$tmpd/home" RALPHIE_SELF_UPDATE_TEST=1 AUTO_UPDATE=true AUTO_UPDATE_URL="file://$tmpd/remote-ralphie.sh" AUTO_UPDATE_LOCK_TIMEOUT_SECONDS=0 "$tmpd/locked/ralphie.sh" --no-resume 2>&1)"
        fi
        printf '%s\n' "$output" | grep -q "another Ralphie self-update is still in progress"
        printf '%s\n' "$output" | grep -q "RALPHIE_SELF_UPDATE_CURRENT_OK"
        if grep -q 'fixture-self-update' "$tmpd/locked/ralphie.sh"; then
            return 1
        fi

        if command -v git >/dev/null 2>&1; then
            mkdir -p "$tmpd/dirty"
            cp ./ralphie.sh "$tmpd/dirty/ralphie.sh"
            chmod +x "$tmpd/dirty/ralphie.sh"
            git -C "$tmpd/dirty" init -q
            git -C "$tmpd/dirty" add ralphie.sh
            if [ -n "$timeout_cmd" ]; then
                output="$(HOME="$tmpd/home" RALPHIE_SELF_UPDATE_TEST=1 AUTO_UPDATE=true AUTO_UPDATE_URL="file://$tmpd/remote-ralphie.sh" "$timeout_cmd" 20 "$tmpd/dirty/ralphie.sh" --no-resume 2>&1)"
            else
                output="$(HOME="$tmpd/home" RALPHIE_SELF_UPDATE_TEST=1 AUTO_UPDATE=true AUTO_UPDATE_URL="file://$tmpd/remote-ralphie.sh" "$tmpd/dirty/ralphie.sh" --no-resume 2>&1)"
            fi
            printf '%s\n' "$output" | grep -q "local ralphie.sh has uncommitted changes"
            printf '%s\n' "$output" | grep -q "RALPHIE_SELF_UPDATE_CURRENT_OK"
            if grep -q 'fixture-self-update' "$tmpd/dirty/ralphie.sh"; then
                return 1
            fi
            test ! -e "$tmpd/dirty/.ralphie/self-update/update.lock"
        fi
    )
    rc=$?
    set -e

    rm -rf "$tmpd"
    return "$rc"
}

run_step() {
    local label="$1"
    shift
    info "Running: $label"
    "$@"
    pass "$label"
}

run_live_smoke_if_enabled() {
    local timeout_cmd missing_creds=false
    timeout_cmd="$(get_timeout_cmd)"

    case "$LIVE_ENGINE" in
        codex)
            [ -n "${OPENAI_API_KEY:-}" ] || missing_creds=true
            ;;
        claude)
            [ -n "${ANTHROPIC_API_KEY:-}" ] || missing_creds=true
            ;;
    esac

    if [ "$LIVE_MODE" = "off" ]; then
        warn "Live smoke skipped (--skip-live)."
        return 0
    fi

    if [ "$missing_creds" = true ]; then
        if [ "$LIVE_MODE" = "on" ]; then
            fail "Live smoke required but credentials are missing for engine '$LIVE_ENGINE'."
            return 1
        fi
        warn "Live smoke skipped (missing credentials for engine '$LIVE_ENGINE')."
        return 0
    fi

    info "Running: live smoke ($LIVE_ENGINE)"
    if [ -n "$timeout_cmd" ]; then
        "$timeout_cmd" "$LIVE_TIMEOUT_SECONDS" ./tests/durability/run-live-smoke.sh "$LIVE_ENGINE" --no-prompt
    else
        ./tests/durability/run-live-smoke.sh "$LIVE_ENGINE" --no-prompt
    fi
    pass "live smoke ($LIVE_ENGINE)"
}

main() {
    parse_args "$@"
    validate_args

    run_step "bash syntax checks" run_support_bash_syntax_checks
    run_step "shellcheck support scripts" run_support_shellcheck_if_available
    run_step "setup-agent-subrepos fixture" run_setup_agent_subrepos_fixture_check
    run_step "markdown hygiene fixture" run_markdown_hygiene_fixture_check
    run_step "self-update fixture" run_self_update_fixture_check
    run_step "durability suite" ./tests/durability/run-durability-suite.sh

    local -a stress_cmd=(./tests/durability/run-claude-phase-stress.sh --scenarios "$STRESS_SCENARIOS")
    if [ -n "$DISCORD_WEBHOOK_URL" ]; then
        stress_cmd+=(--discord-webhook-url "$DISCORD_WEBHOOK_URL")
    fi
    if [ "$EXERCISE_TTS_FALLBACK" = "true" ]; then
        stress_cmd+=(--exercise-tts-fallback)
    fi
    run_step "claude phase stress ($STRESS_SCENARIOS)" "${stress_cmd[@]}"

    run_live_smoke_if_enabled
    pass "pre-ship sequence complete"
}

main "$@"
