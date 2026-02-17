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

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fail() { printf '[FAIL] %s\n' "$*" >&2; }
pass() { printf '[PASS] %s\n' "$*"; }

print_usage() {
    cat <<'EOF'
Usage: ./test.sh [options]

Runs the pre-ship validation sequence:
  1) bash syntax check for ralphie.sh
  2) tests/durability/run-durability-suite.sh
  3) tests/durability/run-claude-phase-stress.sh
  4) tests/durability/run-live-smoke.sh (optional, controlled by flags)

Options:
  --live-engine codex|claude     Live smoke engine (default: claude)
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

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --live-engine)
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
                LIVE_TIMEOUT_SECONDS="${2:-}"
                shift 2
                ;;
            --stress-scenarios)
                STRESS_SCENARIOS="${2:-}"
                shift 2
                ;;
            --discord-webhook-url)
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

    if [ "$EXERCISE_TTS_FALLBACK" = "true" ] && [ -z "$DISCORD_WEBHOOK_URL" ]; then
        fail "--exercise-tts-fallback requires --discord-webhook-url"
        exit 1
    fi
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

    run_step "bash -n ralphie.sh" bash -n ./ralphie.sh
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
