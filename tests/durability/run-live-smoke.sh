#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENGINE="${LIVE_SMOKE_ENGINE:-codex}"
ENGINE_EXPLICIT=false
PROMPT_MODE="auto"
CANARY_TOKEN="ralphie_live_smoke_$(date +%s)_${RANDOM:-0}"
REPO_GIT_AVAILABLE=false
REPO_TRACKED_STATUS_BASELINE=""

info() { printf '[INFO] %s\n' "$*"; }
pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; }

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

repo_integrity_exit_guard() {
    local rc=$?
    trap - EXIT
    if ! assert_repo_tracked_status_unchanged; then
        fail "Tracked repository files changed during live smoke; refusing pass because repo isolation was violated."
        rc=1
    fi
    exit "$rc"
}

print_usage() {
    cat <<'EOF'
Usage: tests/durability/run-live-smoke.sh [options] [codex|claude]

Options:
  --engine codex|claude  Engine to test (same as positional arg)
  --prompt               Force interactive prompts (engine + temporary overrides)
  --no-prompt            Disable interactive prompts
  --help, -h             Show this help

Behavior:
  - In interactive terminals, if engine was not explicitly provided, the script
    prompts for engine selection and optional temporary overrides.
  - Overrides are in-memory for this run only and are never persisted.
EOF
}

is_tty_interactive() {
    [ -t 0 ] && [ -t 1 ]
}

prompt_with_default() {
    local label="$1"
    local default_value="$2"
    local answer=""
    if [ -n "$default_value" ]; then
        printf '%s [%s]: ' "$label" "$default_value" >&2
    else
        printf '%s: ' "$label" >&2
    fi
    IFS= read -r answer || true
    if [ -z "$answer" ]; then
        printf '%s' "$default_value"
    else
        printf '%s' "$answer"
    fi
}

prompt_secret_override() {
    local key="$1"
    local current_set="no"
    local decision="" lower_decision="" entered=""
    [ -n "${!key:-}" ] && current_set="yes"
    printf '%s currently %s. Override for this run? [y/N]: ' "$key" "$current_set" >&2
    IFS= read -r decision || true
    lower_decision="$(printf '%s' "$decision" | tr '[:upper:]' '[:lower:]')"
    case "$lower_decision" in
        y|yes)
            printf 'Enter %s (leave empty to keep current): ' "$key" >&2
            IFS= read -r -s entered || true
            printf '\n' >&2
            if [ -n "$entered" ]; then
                printf -v "$key" '%s' "$entered"
            fi
            ;;
    esac
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            codex|claude)
                ENGINE="$1"
                ENGINE_EXPLICIT=true
                shift
                ;;
            --engine)
                [ "$#" -ge 2 ] || { fail "Missing value for --engine"; exit 1; }
                case "$2" in
                    codex|claude)
                        ENGINE="$2"
                        ENGINE_EXPLICIT=true
                        ;;
                    *)
                        fail "Unsupported value for --engine: '$2' (expected codex|claude)"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --prompt)
                PROMPT_MODE="on"
                shift
                ;;
            --no-prompt)
                PROMPT_MODE="off"
                shift
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            *)
                fail "Unsupported argument '$1' (use --help)"
                exit 1
                ;;
        esac
    done
}

prompt_engine_and_overrides() {
    local selected="" default_engine
    default_engine="$ENGINE"

    while true; do
        selected="$(prompt_with_default "Select live smoke engine (codex|claude)" "$default_engine")"
        case "$selected" in
            codex|claude)
                ENGINE="$selected"
                break
                ;;
            *)
                printf '[FAIL] Invalid engine "%s" (expected codex|claude)\n' "$selected" >&2
                ;;
        esac
    done

    info "Interactive overrides are temporary for this run only."

    case "$ENGINE" in
        codex)
            prompt_secret_override "OPENAI_API_KEY"
            OPENAI_BASE_URL="$(prompt_with_default "OPENAI_BASE_URL" "${OPENAI_BASE_URL:-https://api.openai.com/v1}")"
            LIVE_SMOKE_CODEX_MODEL="$(prompt_with_default "LIVE_SMOKE_CODEX_MODEL" "${LIVE_SMOKE_CODEX_MODEL:-${CODEX_MODEL:-gpt-4.1-mini}}")"
            info "Using Codex endpoint: ${OPENAI_BASE_URL}"
            info "Using Codex model: ${LIVE_SMOKE_CODEX_MODEL}"
            ;;
        claude)
            prompt_secret_override "ANTHROPIC_API_KEY"
            ANTHROPIC_BASE_URL="$(prompt_with_default "ANTHROPIC_BASE_URL" "${ANTHROPIC_BASE_URL:-https://api.anthropic.com}")"
            LIVE_SMOKE_CLAUDE_MODEL="$(prompt_with_default "LIVE_SMOKE_CLAUDE_MODEL" "${LIVE_SMOKE_CLAUDE_MODEL:-${CLAUDE_MODEL:-claude-3-5-haiku-latest}}")"
            info "Using Claude endpoint: ${ANTHROPIC_BASE_URL}"
            info "Using Claude model: ${LIVE_SMOKE_CLAUDE_MODEL}"
            ;;
    esac
}

require_env() {
    local key="$1"
    if [ -z "${!key:-}" ]; then
        fail "Missing required environment variable: $key"
        exit 1
    fi
}

run_codex_live_smoke() {
    require_env "OPENAI_API_KEY"

    local base_url model endpoint body_file status
    base_url="${OPENAI_BASE_URL:-https://api.openai.com/v1}"
    endpoint="${base_url%/}/responses"
    model="${LIVE_SMOKE_CODEX_MODEL:-${CODEX_MODEL:-gpt-4.1-mini}}"
    body_file="$(mktemp /tmp/ralphie-codex-live-smoke.XXXXXX)"

    info "Running live Codex smoke via Responses API"
    status="$(curl -sS -o "$body_file" -w '%{http_code}' \
        -X POST "$endpoint" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H 'Content-Type: application/json' \
        -d @- <<JSON
{
  "model": "${model}",
  "input": [
    {
      "role": "user",
      "content": [
        {
          "type": "text",
          "text": "Reply with ONLY this exact token on one line: ${CANARY_TOKEN}"
        }
      ]
    }
  ],
  "max_output_tokens": 32
}
JSON
)"

    if [ "$status" != "200" ]; then
        fail "Codex live smoke failed with HTTP $status"
        sed -n '1,80p' "$body_file" >&2
        rm -f "$body_file"
        exit 1
    fi

    if grep -Fq "$CANARY_TOKEN" "$body_file"; then
        pass "Codex live smoke passed"
        rm -f "$body_file"
        return 0
    fi

    fail "Codex live smoke response did not contain canary token"
    sed -n '1,80p' "$body_file" >&2
    rm -f "$body_file"
    exit 1
}

run_claude_live_smoke() {
    require_env "ANTHROPIC_API_KEY"

    local base_url model endpoint body_file status
    base_url="${ANTHROPIC_BASE_URL:-https://api.anthropic.com}"
    endpoint="${base_url%/}/v1/messages"
    model="${LIVE_SMOKE_CLAUDE_MODEL:-${CLAUDE_MODEL:-claude-3-5-haiku-latest}}"
    body_file="$(mktemp /tmp/ralphie-claude-live-smoke.XXXXXX)"

    info "Running live Claude smoke via Messages API"
    status="$(curl -sS -o "$body_file" -w '%{http_code}' \
        -X POST "$endpoint" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H 'anthropic-version: 2023-06-01' \
        -H 'content-type: application/json' \
        -d @- <<JSON
{
  "model": "${model}",
  "max_tokens": 32,
  "messages": [
    {
      "role": "user",
      "content": "Reply with ONLY this exact token on one line: ${CANARY_TOKEN}"
    }
  ]
}
JSON
)"

    if [ "$status" != "200" ]; then
        fail "Claude live smoke failed with HTTP $status"
        sed -n '1,80p' "$body_file" >&2
        rm -f "$body_file"
        exit 1
    fi

    if grep -Fq "$CANARY_TOKEN" "$body_file"; then
        pass "Claude live smoke passed"
        rm -f "$body_file"
        return 0
    fi

    # Some Anthropic-compatible providers stream SSE deltas where the token
    # appears fragmented across many text chunks. Reconstruct those chunks.
    local reconstructed_text
    reconstructed_text="$(
        awk -F'"text":"' '
            /"text":"/ {
                split($2, parts, "\"")
                printf "%s", parts[1]
            }
            END { printf "\n" }
        ' "$body_file" || true
    )"
    if printf '%s' "$reconstructed_text" | grep -Fq "$CANARY_TOKEN"; then
        pass "Claude live smoke passed"
        rm -f "$body_file"
        return 0
    fi

    fail "Claude live smoke response did not contain canary token"
    sed -n '1,80p' "$body_file" >&2
    rm -f "$body_file"
    exit 1
}

main() {
    parse_args "$@"
    capture_repo_tracked_status_baseline
    trap repo_integrity_exit_guard EXIT

    if [ "$PROMPT_MODE" = "on" ] || { [ "$PROMPT_MODE" = "auto" ] && [ "$ENGINE_EXPLICIT" = false ] && is_tty_interactive; }; then
        prompt_engine_and_overrides
    fi

    case "$ENGINE" in
        codex)
            run_codex_live_smoke
            ;;
        claude)
            run_claude_live_smoke
            ;;
        *)
            fail "Unsupported engine '$ENGINE' (expected: codex|claude)"
            exit 1
            ;;
    esac
}

main "$@"
