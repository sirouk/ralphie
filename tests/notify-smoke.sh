#!/usr/bin/env bash
#
# notify-smoke.sh
# Minimal communication/connectivity tester for Ralphie notifications.
# Includes the same communication onboarding flow as ralphie.sh:
# Telegram, Discord webhook, optional Chutes TTS.
#
# Usage examples:
#   ./notify-smoke.sh
#   ./notify-smoke.sh --telegram
#   ./notify-smoke.sh --discord
#   ./notify-smoke.sh --message "hello world from smoke test"
#   ./notify-smoke.sh --onboard
#   ./notify-smoke.sh --no-onboard
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$PROJECT_DIR/.ralphie/config.env"
REPO_GIT_AVAILABLE=false
REPO_TRACKED_STATUS_BASELINE=""

MODE="all"               # all|telegram|discord
MESSAGE=""
USE_MARKDOWN="true"      # true|false
LOAD_CONFIG="true"       # true|false
ONBOARD_MODE="auto"      # auto|always|never

DEFAULT_CHUTES_TTS_URL="https://chutes-kokoro.chutes.ai/speak"
DEFAULT_CHUTES_VOICE="am_puck"
DEFAULT_CHUTES_SPEED="1.24"

NOTIFICATIONS_ENABLED="false"
NOTIFY_TELEGRAM_ENABLED="false"
NOTIFY_DISCORD_ENABLED="false"
NOTIFY_TTS_ENABLED="false"
TG_BOT_TOKEN=""
TG_CHAT_ID=""
DISCORD_WEBHOOK=""
CHUTES_API_KEY=""
CHUTES_TTS_URL="$DEFAULT_CHUTES_TTS_URL"
CHUTES_VOICE="$DEFAULT_CHUTES_VOICE"
CHUTES_SPEED="$DEFAULT_CHUTES_SPEED"

err() { echo -e "\033[1;31m$*\033[0m" >&2; }
warn() { echo -e "\033[1;33m$*\033[0m" >&2; }
info() { echo -e "\033[0;34m$*\033[0m"; }
success() { echo -e "\033[0;32m$*\033[0m"; }

capture_repo_tracked_status_baseline() {
    if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        REPO_GIT_AVAILABLE=true
        REPO_TRACKED_STATUS_BASELINE="$(git -C "$PROJECT_DIR" status --porcelain=v1 --untracked-files=no --ignore-submodules=all || true)"
    else
        REPO_GIT_AVAILABLE=false
        REPO_TRACKED_STATUS_BASELINE=""
    fi
}

assert_repo_tracked_status_unchanged() {
    local current_status=""
    [ "$REPO_GIT_AVAILABLE" = true ] || return 0
    current_status="$(git -C "$PROJECT_DIR" status --porcelain=v1 --untracked-files=no --ignore-submodules=all || true)"
    [ "$current_status" = "$REPO_TRACKED_STATUS_BASELINE" ]
}

repo_integrity_exit_guard() {
    local rc=$?
    trap - EXIT
    if ! assert_repo_tracked_status_unchanged; then
        err "Tracked repository files changed during notify smoke; refusing pass because repo isolation was violated."
        rc=1
    fi
    exit "$rc"
}

to_lower() {
    printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

is_true() {
    case "${1:-}" in
        1|[Yy]|[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|ON|on) return 0 ;;
        *) return 1 ;;
    esac
}

is_decimal_number() {
    [[ "${1:-}" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

is_tty_input_available() {
    [ -t 0 ]
}

print_usage() {
    cat <<'EOF'
Usage: ./notify-smoke.sh [options]

Options:
  --all                     Test all configured channels (default)
  --telegram                Test Telegram only
  --discord                 Test Discord only
  --message "text"          Override test message text
  --markdown                Use Markdown-formatted hello world message (default)
  --plain                   Use plain-text hello world message
  --config PATH             Load config from PATH instead of .ralphie/config.env
  --no-config               Do not load config file; use environment only
  --onboard                 Force onboarding prompt flow
  --no-onboard              Skip onboarding prompt flow
  --help, -h                Show help

Required credentials:
  Telegram:
    TG_BOT_TOKEN
    TG_CHAT_ID
  Discord:
    RALPHIE_NOTIFY_DISCORD_WEBHOOK_URL (or DISCORD_WEBHOOK_URL)
  TTS (optional, Telegram and/or Discord):
    CHUTES_API_KEY
EOF
}

parse_arg_value() {
    local arg_name="$1"
    local arg_value="${2:-}"
    if [ -z "$arg_value" ] || [[ "$arg_value" == --* ]]; then
        err "Missing value for $arg_name"
        exit 1
    fi
    printf '%s' "$arg_value"
}

load_config_file_safe() {
    local file="$1"
    local line key raw_value value

    [ -f "$file" ] || return 0

    while IFS= read -r line || [ -n "$line" ]; do
        line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [ -z "$line" ] && continue
        [[ "$line" == \#* ]] && continue

        if [[ ! "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            continue
        fi

        key="${BASH_REMATCH[1]}"
        raw_value="${BASH_REMATCH[2]}"
        raw_value="$(printf '%s' "$raw_value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

        if [[ ! "$raw_value" =~ ^\".*\"$ ]] && [[ ! "$raw_value" =~ ^\'.*\'$ ]]; then
            raw_value="$(printf '%s' "$raw_value" | sed 's/[[:space:]]#.*$//; s/[[:space:]]*$//')"
        fi

        value="$raw_value"
        if [[ "$value" =~ ^\".*\"$ ]] && [ "${#value}" -ge 2 ]; then
            value="${value:1:${#value}-2}"
            value="${value//\\\"/\"}"
            value="${value//\\\\/\\}"
        elif [[ "$value" =~ ^\'.*\'$ ]] && [ "${#value}" -ge 2 ]; then
            value="${value:1:${#value}-2}"
        fi

        printf -v "$key" '%s' "$value"
    done < "$file"
}

config_escape_double_quotes() {
    local value="${1:-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

upsert_config_env_value() {
    local key="$1"
    local value="${2:-}"
    local escaped tmp_file

    if [ "$LOAD_CONFIG" != "true" ]; then
        return 0
    fi
    mkdir -p "$(dirname "$CONFIG_FILE")"
    touch "$CONFIG_FILE"

    escaped="$(config_escape_double_quotes "$value")"
    tmp_file="$(mktemp "${TMPDIR:-/tmp}/notify-smoke-config.XXXXXX")" || return 1

    if ! awk -v key="$key" -v value="$escaped" '
        BEGIN { found=0 }
        {
            if ($0 ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=/) {
                line=$0
                sub(/^[[:space:]]*/, "", line)
                split(line, parts, "=")
                if (parts[1] == key) {
                    print key "=\"" value "\""
                    found=1
                    next
                }
            }
            print
        }
        END {
            if (!found) {
                print key "=\"" value "\""
            }
        }
    ' "$CONFIG_FILE" > "$tmp_file"; then
        rm -f "$tmp_file"
        return 1
    fi

    if ! mv "$tmp_file" "$CONFIG_FILE"; then
        rm -f "$tmp_file"
        return 1
    fi
    return 0
}

persist_notification_values() {
    upsert_config_env_value "RALPHIE_NOTIFICATIONS_ENABLED" "$NOTIFICATIONS_ENABLED" || true
    upsert_config_env_value "RALPHIE_NOTIFY_TELEGRAM_ENABLED" "$NOTIFY_TELEGRAM_ENABLED" || true
    upsert_config_env_value "TG_BOT_TOKEN" "$TG_BOT_TOKEN" || true
    upsert_config_env_value "TG_CHAT_ID" "$TG_CHAT_ID" || true
    upsert_config_env_value "RALPHIE_NOTIFY_DISCORD_ENABLED" "$NOTIFY_DISCORD_ENABLED" || true
    upsert_config_env_value "RALPHIE_NOTIFY_DISCORD_WEBHOOK_URL" "$DISCORD_WEBHOOK" || true
    upsert_config_env_value "RALPHIE_NOTIFY_TTS_ENABLED" "$NOTIFY_TTS_ENABLED" || true
    upsert_config_env_value "CHUTES_API_KEY" "$CHUTES_API_KEY" || true
    upsert_config_env_value "RALPHIE_NOTIFY_CHUTES_TTS_URL" "$CHUTES_TTS_URL" || true
    upsert_config_env_value "RALPHIE_NOTIFY_CHUTES_VOICE" "$CHUTES_VOICE" || true
    upsert_config_env_value "RALPHIE_NOTIFY_CHUTES_SPEED" "$CHUTES_SPEED" || true
    upsert_config_env_value "RALPHIE_NOTIFICATION_WIZARD_BOOTSTRAPPED" "true" || true
}

prompt_read_line() {
    local prompt="$1"
    local default="${2:-}"
    local response=""

    if [ -t 0 ]; then
        read -rp "$prompt" response
        printf '%s' "${response:-$default}"
        return 0
    fi
    if [ -r /dev/tty ] && [ -w /dev/tty ]; then
        read -rp "$prompt" response < /dev/tty > /dev/tty 2>/dev/null
        printf '%s' "${response:-$default}"
        return 0
    fi
    printf '%s' "$default"
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local marker="[Y/n]"
    local response

    case "$(to_lower "$default")" in
        n|no|false|0) marker="[y/N]" ;;
        *) marker="[Y/n]" ;;
    esac
    response="$(prompt_read_line "$prompt $marker: " "$default")"
    case "$response" in
        [Yy]*) echo "true" ;;
        *) echo "false" ;;
    esac
}

prompt_override_value() {
    local label="$1"
    local current="${2:-}"
    local display="${current:-<unset>}"
    local response

    response="$(prompt_read_line "$label [current: $display, enter=keep, -=clear]: " "")"
    if [ -z "$response" ]; then
        printf '%s' "$current"
        return 0
    fi
    if [ "$response" = "-" ]; then
        printf '%s' ""
        return 0
    fi
    printf '%s' "$response"
}

json_escape_string() {
    local value="${1:-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}

send_telegram_message() {
    local token="$1"
    local chat_id="$2"
    local text="$3"
    local parse_mode="${4:-}"
    local response http_code body
    local -a curl_args=()

    curl_args=(-sS -m 20 -w $'\n%{http_code}' -X POST "https://api.telegram.org/bot${token}/sendMessage")
    curl_args+=(--data-urlencode "chat_id=${chat_id}")
    curl_args+=(--data-urlencode "text=${text}")
    [ -n "$parse_mode" ] && curl_args+=(--data-urlencode "parse_mode=${parse_mode}")

    response="$(curl "${curl_args[@]}" 2>/dev/null || true)"
    http_code="${response##*$'\n'}"
    body="${response%$'\n'*}"

    if [ "$http_code" = "200" ] && printf '%s' "$body" | grep -q '"ok":[[:space:]]*true'; then
        return 0
    fi
    return 1
}

telegram_get_updates_raw() {
    local token="$1"
    [ -n "$token" ] || return 1
    curl -sS -m 20 "https://api.telegram.org/bot${token}/getUpdates" 2>/dev/null || return 1
}

telegram_extract_chat_ids() {
    local payload="${1:-}"
    [ -n "$payload" ] || return 0

    printf '%s' "$payload" | tr -d '\n' | \
        grep -oE '"chat":[[:space:]]*\{[^}]*"id":[[:space:]]*-?[0-9]+' | \
        grep -oE -- '-?[0-9]+$' | awk '!seen[$0]++'
}

telegram_suggest_chat_id() {
    local token="$1"
    local updates ids first_id count

    updates="$(telegram_get_updates_raw "$token" 2>/dev/null || true)"
    if [ -z "$updates" ]; then
        warn "Could not query Telegram getUpdates right now."
        printf '%s' ""
        return 0
    fi
    if ! printf '%s' "$updates" | grep -q '"ok":[[:space:]]*true'; then
        warn "Telegram getUpdates did not return ok=true. Verify bot token."
        printf '%s' ""
        return 0
    fi
    if printf '%s' "$updates" | grep -q '"result":[[:space:]]*\[\]'; then
        warn "Telegram getUpdates is empty. Send a message to your bot/chat first, then retry."
        printf '%s' ""
        return 0
    fi

    ids="$(telegram_extract_chat_ids "$updates" || true)"
    count="$(printf '%s\n' "$ids" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [ "${count:-0}" -lt 1 ]; then
        warn "Could not parse chat IDs from getUpdates response."
        printf '%s' ""
        return 0
    fi

    info "Discovered Telegram chat IDs from getUpdates:"
    printf '%s\n' "$ids" | sed '/^$/d' | sed 's/^/  - /'
    first_id="$(printf '%s\n' "$ids" | sed '/^$/d' | head -n 1)"
    printf '%s' "$first_id"
}

send_discord_message() {
    local webhook_url="$1"
    local text="$2"
    local payload http_code

    payload="$(json_escape_string "$text")"
    http_code="$(curl -sS -m 20 -o /dev/null -w '%{http_code}' \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"content\":\"${payload}\"}" \
        "$webhook_url" 2>/dev/null || true)"

    case "$http_code" in
        200|201|202|204) return 0 ;;
        *) return 1 ;;
    esac
}

generate_chutes_tts_audio_file() {
    local chutes_api_key="$1"
    local tts_url="$2"
    local voice="$3"
    local speed="$4"
    local text="$5"
    local output_file="$6"
    local escaped_text escaped_voice

    [ -n "$chutes_api_key" ] || return 1
    [ -n "$tts_url" ] || return 1
    [ -n "$voice" ] || return 1
    [ -n "$text" ] || return 1
    [ -n "$output_file" ] || return 1
    is_decimal_number "$speed" || speed="$DEFAULT_CHUTES_SPEED"

    escaped_text="$(json_escape_string "$text")"
    escaped_voice="$(json_escape_string "$voice")"

    if ! curl -sS -m 45 -X POST "$tts_url" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $chutes_api_key" \
        -d "{\"text\":\"${escaped_text}\",\"voice\":\"${escaped_voice}\",\"speed\":${speed}}" \
        --output "$output_file" >/dev/null 2>&1; then
        return 1
    fi
    [ -s "$output_file" ] || return 1
    return 0
}

send_telegram_voice_file() {
    local token="$1"
    local chat_id="$2"
    local file_path="$3"
    local caption="$4"
    local method="$5"
    local field_name="$6"
    local response http_code body

    [ -n "$token" ] || return 1
    [ -n "$chat_id" ] || return 1
    [ -n "$file_path" ] || return 1
    [ -n "$method" ] || return 1
    [ -n "$field_name" ] || return 1

    response="$(curl -sS -m 30 -w $'\n%{http_code}' -X POST "https://api.telegram.org/bot${token}/${method}" \
        -F "chat_id=${chat_id}" \
        -F "${field_name}=@${file_path}" \
        -F "caption=${caption}" 2>/dev/null || true)"
    http_code="${response##*$'\n'}"
    body="${response%$'\n'*}"
    [ "$http_code" = "200" ] && printf '%s' "$body" | grep -q '"ok":[[:space:]]*true'
}

send_telegram_tts() {
    local chutes_api_key="$1"
    local tts_url="$2"
    local voice="$3"
    local speed="$4"
    local token="$5"
    local chat_id="$6"
    local text="$7"
    local caption="${8:-notify smoke tts test}"
    local tmp_audio

    [ -n "$chutes_api_key" ] || return 1
    [ -n "$tts_url" ] || return 1
    [ -n "$voice" ] || return 1
    [ -n "$token" ] || return 1
    [ -n "$chat_id" ] || return 1
    [ -n "$text" ] || return 1
    is_decimal_number "$speed" || speed="$DEFAULT_CHUTES_SPEED"

    tmp_audio="$(mktemp "${TMPDIR:-/tmp}/notify-smoke-tts.XXXXXX")" || return 1

    if ! generate_chutes_tts_audio_file "$chutes_api_key" "$tts_url" "$voice" "$speed" "$text" "$tmp_audio"; then
        rm -f "$tmp_audio"
        return 1
    fi

    if ! send_telegram_voice_file "$token" "$chat_id" "$tmp_audio" "$caption" "sendVoice" "voice" \
        && ! send_telegram_voice_file "$token" "$chat_id" "$tmp_audio" "$caption" "sendAudio" "audio" \
        && ! send_telegram_voice_file "$token" "$chat_id" "$tmp_audio" "$caption" "sendDocument" "document"; then
            rm -f "$tmp_audio"
            return 1
        fi

    rm -f "$tmp_audio"
    return 0
}

send_discord_tts() {
    local chutes_api_key="$1"
    local tts_url="$2"
    local voice="$3"
    local speed="$4"
    local webhook_url="$5"
    local text="$6"
    local caption="${7:-notify smoke tts test}"
    local tmp_audio content_json http_code

    [ -n "$webhook_url" ] || return 1
    [ -n "$text" ] || return 1
    is_decimal_number "$speed" || speed="$DEFAULT_CHUTES_SPEED"

    tmp_audio="$(mktemp "${TMPDIR:-/tmp}/notify-smoke-discord-tts.XXXXXX")" || return 1
    if ! generate_chutes_tts_audio_file "$chutes_api_key" "$tts_url" "$voice" "$speed" "$text" "$tmp_audio"; then
        rm -f "$tmp_audio"
        return 1
    fi

    content_json="$(json_escape_string "$caption")"
    http_code="$(curl -sS -m 30 -o /dev/null -w '%{http_code}' -X POST \
        -F "payload_json={\"content\":\"${content_json}\"}" \
        -F "file=@${tmp_audio};filename=ralphie-tts.mp3;type=audio/mpeg" \
        "$webhook_url" 2>/dev/null || true)"

    rm -f "$tmp_audio"
    case "$http_code" in
        200|201|202|204) return 0 ;;
        *) return 1 ;;
    esac
}

normalize_boolean_settings() {
    NOTIFICATIONS_ENABLED="$(to_lower "$NOTIFICATIONS_ENABLED")"
    NOTIFY_TELEGRAM_ENABLED="$(to_lower "$NOTIFY_TELEGRAM_ENABLED")"
    NOTIFY_DISCORD_ENABLED="$(to_lower "$NOTIFY_DISCORD_ENABLED")"
    NOTIFY_TTS_ENABLED="$(to_lower "$NOTIFY_TTS_ENABLED")"

    is_true "$NOTIFICATIONS_ENABLED" && NOTIFICATIONS_ENABLED="true" || NOTIFICATIONS_ENABLED="false"
    is_true "$NOTIFY_TELEGRAM_ENABLED" && NOTIFY_TELEGRAM_ENABLED="true" || NOTIFY_TELEGRAM_ENABLED="false"
    is_true "$NOTIFY_DISCORD_ENABLED" && NOTIFY_DISCORD_ENABLED="true" || NOTIFY_DISCORD_ENABLED="false"
    is_true "$NOTIFY_TTS_ENABLED" && NOTIFY_TTS_ENABLED="true" || NOTIFY_TTS_ENABLED="false"

    [ -n "$CHUTES_TTS_URL" ] || CHUTES_TTS_URL="$DEFAULT_CHUTES_TTS_URL"
    [ -n "$CHUTES_VOICE" ] || CHUTES_VOICE="$DEFAULT_CHUTES_VOICE"
    is_decimal_number "$CHUTES_SPEED" || CHUTES_SPEED="$DEFAULT_CHUTES_SPEED"
}

hydrate_notification_settings() {
    NOTIFICATIONS_ENABLED="${RALPHIE_NOTIFICATIONS_ENABLED:-${NOTIFICATIONS_ENABLED:-false}}"
    NOTIFY_TELEGRAM_ENABLED="${RALPHIE_NOTIFY_TELEGRAM_ENABLED:-${NOTIFY_TELEGRAM_ENABLED:-false}}"
    NOTIFY_DISCORD_ENABLED="${RALPHIE_NOTIFY_DISCORD_ENABLED:-${NOTIFY_DISCORD_ENABLED:-false}}"
    NOTIFY_TTS_ENABLED="${RALPHIE_NOTIFY_TTS_ENABLED:-${NOTIFY_TTS_ENABLED:-false}}"

    TG_BOT_TOKEN="${TG_BOT_TOKEN:-${RALPHIE_TG_BOT_TOKEN:-}}"
    TG_CHAT_ID="${TG_CHAT_ID:-${RALPHIE_TG_CHAT_ID:-}}"
    DISCORD_WEBHOOK="${RALPHIE_NOTIFY_DISCORD_WEBHOOK_URL:-${DISCORD_WEBHOOK_URL:-${NOTIFY_DISCORD_WEBHOOK_URL:-}}}"
    CHUTES_API_KEY="${CHUTES_API_KEY:-${RALPHIE_CHUTES_API_KEY:-}}"
    CHUTES_TTS_URL="${RALPHIE_NOTIFY_CHUTES_TTS_URL:-${CHUTES_TTS_URL:-$DEFAULT_CHUTES_TTS_URL}}"
    CHUTES_VOICE="${RALPHIE_NOTIFY_CHUTES_VOICE:-${CHUTES_VOICE:-$DEFAULT_CHUTES_VOICE}}"
    CHUTES_SPEED="${RALPHIE_NOTIFY_CHUTES_SPEED:-${CHUTES_SPEED:-$DEFAULT_CHUTES_SPEED}}"

    normalize_boolean_settings
}

should_offer_onboarding() {
    local has_tg has_discord default_yes
    has_tg="false"
    has_discord="false"
    default_yes="n"

    [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ] && has_tg="true"
    [ -n "$DISCORD_WEBHOOK" ] && has_discord="true"

    case "$ONBOARD_MODE" in
        always) return 0 ;;
        never) return 1 ;;
    esac

    is_tty_input_available || return 1

    case "$MODE" in
        telegram)
            [ "$has_tg" = "false" ] && default_yes="y"
            ;;
        discord)
            [ "$has_discord" = "false" ] && default_yes="y"
            ;;
        all)
            if [ "$has_tg" = "false" ] || [ "$has_discord" = "false" ]; then
                default_yes="y"
            fi
            ;;
    esac

    if [ "$(prompt_yes_no "Run communication onboarding wizard (Telegram/Discord/Chutes TTS)?" "$default_yes")" = "true" ]; then
        return 0
    fi
    return 1
}

run_communication_onboarding_wizard() {
    local telegram_selected discord_selected tts_selected

    info "Communication onboarding (same flow as ralphie notification setup)."
    info "Standardized events: session_start, phase_complete, phase_blocked, session_done, session_error."

    telegram_selected="$NOTIFY_TELEGRAM_ENABLED"
    discord_selected="$NOTIFY_DISCORD_ENABLED"
    tts_selected="$NOTIFY_TTS_ENABLED"

    info "Telegram setup guide:"
    info "  1) Open Telegram @BotFather and run /newbot."
    info "  2) Copy bot token."
    info "  3) Message your bot/chat/channel once."
    info "  4) Open https://api.telegram.org/bot<token>/getUpdates and copy chat.id."
    if [ "$(prompt_yes_no "Configure Telegram notifications?" "$(is_true "$telegram_selected" && echo y || echo n)")" = "true" ]; then
        local suggested_chat_id=""
        telegram_selected="true"
        TG_BOT_TOKEN="$(prompt_override_value "Telegram bot token (TG_BOT_TOKEN)" "$TG_BOT_TOKEN")"
        if [ -z "$TG_CHAT_ID" ] && [ -n "$TG_BOT_TOKEN" ]; then
            suggested_chat_id="$(telegram_suggest_chat_id "$TG_BOT_TOKEN")"
        fi
        if [ -n "$suggested_chat_id" ] && [ -z "$TG_CHAT_ID" ]; then
            TG_CHAT_ID="$suggested_chat_id"
        fi
        TG_CHAT_ID="$(prompt_override_value "Telegram chat id (TG_CHAT_ID)" "$TG_CHAT_ID")"
        if [ -z "$TG_CHAT_ID" ] && [ -n "$TG_BOT_TOKEN" ]; then
            suggested_chat_id="$(telegram_suggest_chat_id "$TG_BOT_TOKEN")"
            if [ -n "$suggested_chat_id" ]; then
                info "Using discovered chat id: $suggested_chat_id"
                TG_CHAT_ID="$suggested_chat_id"
            fi
        fi
        if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
            if send_telegram_message "$TG_BOT_TOKEN" "$TG_CHAT_ID" "[notify-smoke] telegram setup test" ""; then
                success "Telegram test send: OK"
            else
                warn "Telegram test send failed. Verify token/chat id and permissions."
            fi
        else
            warn "Telegram credentials incomplete; channel will be disabled."
            telegram_selected="false"
        fi
    else
        telegram_selected="false"
    fi

    info "Discord setup guide:"
    info "  1) Server Settings -> Integrations -> Webhooks."
    info "  2) Create webhook and copy URL."
    if [ "$(prompt_yes_no "Configure Discord webhook notifications?" "$(is_true "$discord_selected" && echo y || echo n)")" = "true" ]; then
        discord_selected="true"
        DISCORD_WEBHOOK="$(prompt_override_value "Discord webhook URL" "$DISCORD_WEBHOOK")"
        if [ -n "$DISCORD_WEBHOOK" ]; then
            if send_discord_message "$DISCORD_WEBHOOK" "[notify-smoke] discord setup test"; then
                success "Discord test send: OK"
            else
                warn "Discord test send failed. Verify webhook URL."
            fi
        else
            warn "Discord webhook is empty; channel will be disabled."
            discord_selected="false"
        fi
    else
        discord_selected="false"
    fi

    if [ "$telegram_selected" = "true" ] || [ "$discord_selected" = "true" ]; then
        info "Optional Chutes TTS setup:"
        info "  1) Create API key at https://chutes.ai"
        info "  2) Provide key to enable TTS voice notifications (Telegram and/or Discord)."
        if [ "$(prompt_yes_no "Enable Chutes TTS voice notifications?" "$(is_true "$tts_selected" && echo y || echo n)")" = "true" ]; then
            tts_selected="true"
            CHUTES_API_KEY="$(prompt_override_value "Chutes API key (CHUTES_API_KEY)" "$CHUTES_API_KEY")"
            CHUTES_VOICE="$(prompt_override_value "Chutes voice id" "$CHUTES_VOICE")"
            CHUTES_SPEED="$(prompt_override_value "Chutes speed (example 1.24)" "$CHUTES_SPEED")"
            is_decimal_number "$CHUTES_SPEED" || CHUTES_SPEED="$DEFAULT_CHUTES_SPEED"
            if [ -n "$CHUTES_API_KEY" ]; then
                if [ "$telegram_selected" = "true" ]; then
                    if send_telegram_tts "$CHUTES_API_KEY" "$CHUTES_TTS_URL" "$CHUTES_VOICE" "$CHUTES_SPEED" "$TG_BOT_TOKEN" "$TG_CHAT_ID" "notify smoke tts test" "notify smoke tts"; then
                        success "Telegram TTS test send: OK"
                    else
                        warn "Telegram TTS test failed. Verify CHUTES_API_KEY or TTS availability."
                    fi
                fi
                if [ "$discord_selected" = "true" ] && [ -n "$DISCORD_WEBHOOK" ]; then
                    if send_discord_tts "$CHUTES_API_KEY" "$CHUTES_TTS_URL" "$CHUTES_VOICE" "$CHUTES_SPEED" "$DISCORD_WEBHOOK" "notify smoke tts test" "notify smoke tts"; then
                        success "Discord TTS test send: OK"
                    else
                        warn "Discord TTS test failed. Verify CHUTES_API_KEY, webhook, or TTS availability."
                    fi
                fi
            else
                warn "Chutes API key empty; TTS will be disabled."
                tts_selected="false"
            fi
        else
            tts_selected="false"
        fi
    else
        tts_selected="false"
    fi

    NOTIFY_TELEGRAM_ENABLED="$telegram_selected"
    NOTIFY_DISCORD_ENABLED="$discord_selected"
    NOTIFY_TTS_ENABLED="$tts_selected"
    if [ "$NOTIFY_TELEGRAM_ENABLED" = "true" ] || [ "$NOTIFY_DISCORD_ENABLED" = "true" ]; then
        NOTIFICATIONS_ENABLED="true"
    else
        NOTIFICATIONS_ENABLED="false"
    fi
    if [ "$NOTIFY_TELEGRAM_ENABLED" != "true" ] && [ "$NOTIFY_DISCORD_ENABLED" != "true" ]; then
        NOTIFY_TTS_ENABLED="false"
    fi
    normalize_boolean_settings

    persist_notification_values
    if [ "$LOAD_CONFIG" = "true" ]; then
        success "Saved communication settings to ${CONFIG_FILE#./}."
    fi
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --all)
                MODE="all"
                shift
                ;;
            --telegram)
                MODE="telegram"
                shift
                ;;
            --discord)
                MODE="discord"
                shift
                ;;
            --message)
                MESSAGE="$(parse_arg_value "--message" "${2:-}")"
                shift 2
                ;;
            --markdown)
                USE_MARKDOWN="true"
                shift
                ;;
            --plain)
                USE_MARKDOWN="false"
                shift
                ;;
            --config)
                CONFIG_FILE="$(parse_arg_value "--config" "${2:-}")"
                shift 2
                ;;
            --no-config)
                LOAD_CONFIG="false"
                shift
                ;;
            --onboard)
                ONBOARD_MODE="always"
                shift
                ;;
            --no-onboard)
                ONBOARD_MODE="never"
                shift
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            *)
                err "Unknown argument: $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

main() {
    capture_repo_tracked_status_baseline
    trap repo_integrity_exit_guard EXIT

    parse_args "$@"

    if ! command -v curl >/dev/null 2>&1; then
        err "'curl' is required but not installed."
        exit 1
    fi

    if [ "$LOAD_CONFIG" = "true" ] && [ -f "$CONFIG_FILE" ]; then
        load_config_file_safe "$CONFIG_FILE"
        info "Loaded config: ${CONFIG_FILE#./}"
    fi
    hydrate_notification_settings

    if should_offer_onboarding; then
        run_communication_onboarding_wizard
    fi

    local default_message
    default_message="hello world from ralphie notification smoke test ($(date -u '+%Y-%m-%dT%H:%M:%SZ'))"
    if [ "$USE_MARKDOWN" = "true" ]; then
        default_message="*hello world* from \`ralphie\` notification smoke test
timestamp: \`$(date -u '+%Y-%m-%dT%H:%M:%SZ')\`"
    fi
    [ -n "$MESSAGE" ] || MESSAGE="$default_message"

    local sent_any=false
    local failed_any=false

    if [ "$MODE" = "all" ] || [ "$MODE" = "telegram" ]; then
        if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
            warn "Telegram skipped: TG_BOT_TOKEN or TG_CHAT_ID is not set."
            [ "$MODE" = "telegram" ] && failed_any=true
        else
            info "Testing Telegram send..."
            if send_telegram_message "$TG_BOT_TOKEN" "$TG_CHAT_ID" "$MESSAGE" "$([ "$USE_MARKDOWN" = "true" ] && echo "Markdown" || echo "")"; then
                success "Telegram send: OK"
                sent_any=true
            elif [ "$USE_MARKDOWN" = "true" ] && send_telegram_message "$TG_BOT_TOKEN" "$TG_CHAT_ID" "$MESSAGE" ""; then
                warn "Telegram markdown parse failed; plain-text fallback succeeded."
                sent_any=true
            else
                err "Telegram send: FAILED"
                failed_any=true
            fi

            if is_true "$NOTIFY_TTS_ENABLED"; then
                if [ -z "$CHUTES_API_KEY" ]; then
                    warn "Telegram TTS skipped: CHUTES_API_KEY is not set."
                    failed_any=true
                else
                    info "Testing Telegram TTS send..."
                    if send_telegram_tts "$CHUTES_API_KEY" "$CHUTES_TTS_URL" "$CHUTES_VOICE" "$CHUTES_SPEED" "$TG_BOT_TOKEN" "$TG_CHAT_ID" "hello world from notify smoke tts" "notify smoke tts"; then
                        success "Telegram TTS send: OK"
                        sent_any=true
                    else
                        err "Telegram TTS send: FAILED"
                        failed_any=true
                    fi
                fi
            fi
        fi
    fi

    if [ "$MODE" = "all" ] || [ "$MODE" = "discord" ]; then
        if [ -z "$DISCORD_WEBHOOK" ]; then
            warn "Discord skipped: RALPHIE_NOTIFY_DISCORD_WEBHOOK_URL (or DISCORD_WEBHOOK_URL) is not set."
            [ "$MODE" = "discord" ] && failed_any=true
        else
            info "Testing Discord send..."
            if send_discord_message "$DISCORD_WEBHOOK" "$MESSAGE"; then
                success "Discord send: OK"
                sent_any=true
            else
                err "Discord send: FAILED"
                failed_any=true
            fi
            if is_true "$NOTIFY_TTS_ENABLED"; then
                if [ -z "$CHUTES_API_KEY" ]; then
                    warn "Discord TTS skipped: CHUTES_API_KEY is not set."
                    failed_any=true
                else
                    info "Testing Discord TTS send..."
                    if send_discord_tts "$CHUTES_API_KEY" "$CHUTES_TTS_URL" "$CHUTES_VOICE" "$CHUTES_SPEED" "$DISCORD_WEBHOOK" "hello world from notify smoke tts" "notify smoke tts"; then
                        success "Discord TTS send: OK"
                        sent_any=true
                    else
                        err "Discord TTS send: FAILED"
                        failed_any=true
                    fi
                fi
            fi
        fi
    fi

    if [ "$sent_any" = true ] && [ "$failed_any" = false ]; then
        success "Notification smoke test completed successfully."
        return 0
    fi
    if [ "$sent_any" = true ] && [ "$failed_any" = true ]; then
        warn "Notification smoke test completed with partial success."
        return 1
    fi

    err "No notification channel was successfully tested."
    return 1
}

main "$@"
