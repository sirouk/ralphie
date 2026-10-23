#!/usr/bin/env bash
#
# Ralphie - Autonomous lifecycle orchestration for Prime Agent, Codex and Claude Code.
# One script handles first-run setup, prompt generation, and iterative execution.
#

# Root paths pass through line-oriented operating-system tools. Reject CR/LF
# before any canonicalization can trim them into a different existing path.
validate_root_path() {
    case "$1" in
        *$'\r'*|*$'\n'*)
            printf '%s cannot contain CR or LF path bytes.\n' "${2:-Runtime root}" >&2
            return 1
            ;;
    esac
    return 0
}

canonical_root_path() {
    local directory="$1" label="${2:-Runtime root}" physical
    validate_root_path "$directory" "$label" || return 1
    # A sentinel preserves the actual trailing bytes produced by pwd. Remove
    # its separator only after capturing; then validate the physical root too.
    if ! physical="$(cd -- "$directory" 2>/dev/null && pwd -P && printf '.')"; then
        printf 'Cannot open %s directory.\n' "$label" >&2
        return 1
    fi
    physical="${physical%.}"
    physical="${physical%$'\n'}"
    validate_root_path "$physical" "$label" || return 1
    printf '%s' "$physical"
}

validate_root_path "${TMPDIR:-/tmp}" "Temporary runtime root" || exit 1

# Stream bootstrap:
# When executed via stdin (for example: curl ... | bash), persist the script into
# the current directory and re-exec from disk so relative paths work consistently.
if [ "${RALPHIE_LIB:-0}" != "1" ] && [ -z "${BASH_SOURCE[0]:-}" ]; then
    rb_stream_dir="$(canonical_root_path . "Stream install root")" || exit 1
    rb_target_script="$rb_stream_dir/ralphie.sh"
    if [ -L "$rb_target_script" ] || { [ -e "$rb_target_script" ] && [ ! -f "$rb_target_script" ]; }; then
        printf 'Refusing to replace a symlink or non-file: %s\n' "$rb_target_script" >&2
        exit 1
    fi
    rb_tmp_script="$(mktemp "${rb_target_script}.install.XXXXXX")" || exit 1
    trap 'rm -f "$rb_tmp_script"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    if {
        printf '%s\n' '#!/usr/bin/env bash' '#' \
            '# Ralphie - Autonomous lifecycle orchestration for Prime Agent, Codex and Claude Code.' \
            '# Installed from stdin stream.' '#' &&
        # The persisted tail starts below this bootstrap block. Retain the
        # early path validators it needs, and check every header write.
        declare -f validate_root_path canonical_root_path &&
        printf '%s\n' 'validate_root_path "${TMPDIR:-/tmp}" "Temporary runtime root" || exit 1' &&
        head -c 2000001
    } > "$rb_tmp_script" &&
        [ "$(wc -c < "$rb_tmp_script" | tr -d ' ')" -le 2000000 ] &&
        grep -q '^SCRIPT_VERSION="[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*"$' "$rb_tmp_script" &&
        grep -q '^[[:space:]]*main "\$@"$' "$rb_tmp_script" &&
        "$BASH" -n "$rb_tmp_script" &&
        chmod +x "$rb_tmp_script" &&
        [ ! -L "$rb_target_script" ] &&
        { [ ! -e "$rb_target_script" ] || [ -f "$rb_target_script" ]; } &&
        mv "$rb_tmp_script" "$rb_target_script"; then
        echo "Installed ralphie.sh to $rb_target_script"
        trap - EXIT INT TERM HUP
        exec env RALPHIE_SKIP_AUTO_UPDATE=1 "$BASH" "$rb_target_script" "$@"
    else
        echo "Failed to persist streamed ralphie.sh to $rb_target_script" >&2
        rm -f "$rb_tmp_script"
        exit 1
    fi
fi

set -euo pipefail

SCRIPT_VERSION="2.0.0"

validate_root_path "${BASH_SOURCE[0]}" "Script path" || exit 1
rb_source_parent="${BASH_SOURCE[0]}"
case "$rb_source_parent" in
    */*) rb_source_parent="${rb_source_parent%/*}"; [ -n "$rb_source_parent" ] || rb_source_parent=/ ;;
    *) rb_source_parent=. ;;
esac
SCRIPT_DIR="$(canonical_root_path "$rb_source_parent" "Script root")" || exit 1
INVOCATION_DIR="$(canonical_root_path . "Invocation root")" || exit 1
unset rb_source_parent
PROJECT_DIR="$SCRIPT_DIR"
# Project binding precedes every runtime path and config read. Library sourcing
# keeps its fixture/source root; executable invocations may target any existing root.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Hooks and launchers export repository-local Git paths. They must not
    # redirect a --project operation into another repository or index.
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
        GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_SHALLOW_FILE \
        GIT_GRAFT_FILE GIT_IMPLICIT_WORK_TREE GIT_PREFIX
    rb_early_args=("$@")
    rb_early_index=0
    while [ "$rb_early_index" -lt "${#rb_early_args[@]}" ]; do
        rb_project_arg="${rb_early_args[$rb_early_index]}"
        case "$rb_project_arg" in
            --project)
                rb_early_index=$((rb_early_index + 1))
                rb_project_arg="${rb_early_args[$rb_early_index]:-}"
                [ -n "$rb_project_arg" ] || { printf '%s\n' '--project requires an existing directory' >&2; exit 1; }
                if ! PROJECT_DIR="$(canonical_root_path "$rb_project_arg" "Project root")"; then
                    printf 'Cannot open project directory: %s\n' "$rb_project_arg" >&2
                    exit 1
                fi
                ;;
            --objective|--spec|--accept|--request|--request-file|--archive-request|--engine|--prime-provider|--prime-model|--prime-thinking|--auto-engine-preference|--command|--prime-agent-command|--prime-agent-model|--prime-agent-reasoning|--prime-agent-provider|--prime-agent-url|--claude-command|--codex-command|--codex-model|--codex-reasoning|--gate-timeout-seconds)
                rb_early_index=$((rb_early_index + 1)) ;;
            --) break ;;
        esac
        rb_early_index=$((rb_early_index + 1))
    done
    unset rb_early_args rb_early_index rb_project_arg
    # Git paths and the index belong to the whole worktree. A nested target
    # would misbind raw paths and could commit staged work outside its scope.
    if rb_git_root="$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
        rb_git_root="$(cd -- "$rb_git_root" && pwd -P)" || exit 1
        if [ "$rb_git_root" != "$PROJECT_DIR" ]; then
            printf 'Ralphie requires the Git project root. Target %s is inside %s; use --project "%s".\n' "$PROJECT_DIR" "$rb_git_root" "$rb_git_root" >&2
            exit 1
        fi
    fi
    unset rb_git_root
fi

CONFIG_DIR="$PROJECT_DIR/.ralphie"
CONFIG_FILE="$CONFIG_DIR/config.env"
LOCK_FILE="$CONFIG_DIR/run.lock"
REASON_LOG_FILE="$CONFIG_DIR/reasons.log"
NOTIFICATION_LOG_FILE="$CONFIG_DIR/notifications.log"
GATE_FEEDBACK_FILE="$CONFIG_DIR/last_gate_feedback.md"
STATE_FILE="$CONFIG_DIR/state.env"
REQUESTS_DIR="$CONFIG_DIR/requests"
REQUEST_CLAIM_DIR="$CONFIG_DIR/requests.lock"
REQUEST_COMMAND=""
REQUEST_TEXT=""
REQUEST_FILE=""
REQUEST_ARCHIVE_ID=""
REQUESTS_ENABLED=false
REQUEST_LOCK_TOKEN=""
REQUEST_FROZEN_FINGERPRINT=""
REQUEST_REVIEWED_FINGERPRINT=""
REQUEST_CONTEXT_FILE=""
REQUEST_SNAPSHOT_IDS=""
REQUEST_ROLE=worker
REQUEST_REFRESH_REQUIRED=false
MISSION_OBJECTIVE_FILE="$CONFIG_DIR/OBJECTIVE.md"
OWNED_PATHS_FILE="$CONFIG_DIR/owned-paths.nul"
SHELL_GATES_FILE="$CONFIG_DIR/gates"
SHELL_VERIFICATION_LOG="$CONFIG_DIR/verification.jsonl"
OBJECTIVE_TEXT=""
SPEC_FILE=""
PLAN_ONLY=false
NO_TERMINAL_INPUT=false
ACCEPT_COMMANDS=()
MISSION_SEED_SHA=""
OWNED_PATHS_SHA=""
SHELL_GATES_FINGERPRINT=""
SHELL_GATES_STATUS=absent
SHELL_GATES_FAILURE=""
SHELL_LOCAL_WORK_SEEN=false
SHELL_DEVELOPMENT_PHASE_STARTED=false
SHELL_NO_LOCAL_WORK_WITNESS_READY=false
RUNTIME_GUARD_DIR=""
ACTIVE_PHASE_MANIFEST_BEFORE=""
SESSION_INITIAL_HEAD=""
PHASE_SAVE_REQUIRED=false
PHASE_SAVE_OK=true
PHASE_SAVE_REASON=""
GATE_TIMEOUT_SECONDS="${RALPHIE_GATE_TIMEOUT_SECONDS:-900}"
SPECIFY_DIR="$PROJECT_DIR/.specify/memory"
CONSTITUTION_FILE="$SPECIFY_DIR/constitution.md"
SPECS_DIR="$PROJECT_DIR/specs"
RESEARCH_DIR="$PROJECT_DIR/research"
RESEARCH_SUMMARY_FILE="$RESEARCH_DIR/RESEARCH_SUMMARY.md"
STACK_SNAPSHOT_FILE="$RESEARCH_DIR/STACK_SNAPSHOT.md"
CONSENSUS_DIR="$PROJECT_DIR/consensus"
LOG_DIR="$PROJECT_DIR/logs"
COMPLETION_LOG_DIR="$PROJECT_DIR/completion_log"
MARKDOWN_REPAIR_ARTIFACT_DIR="$LOG_DIR/markdown-repair"
MAPS_DIR="$PROJECT_DIR/maps"
SUBREPOS_DIR_REL="subrepos"
AGENT_SOURCE_MAP_REL="maps/agent-source-map.yaml"
BINARY_STEERING_MAP_REL="maps/binary-steering-map.yaml"
SELF_IMPROVEMENT_LOG_REL="research/SELF_IMPROVEMENT_LOG.md"
SUBREPOS_DIR="$PROJECT_DIR/$SUBREPOS_DIR_REL"
AGENT_SOURCE_MAP_FILE="$PROJECT_DIR/$AGENT_SOURCE_MAP_REL"
BINARY_STEERING_MAP_FILE="$PROJECT_DIR/$BINARY_STEERING_MAP_REL"
SELF_IMPROVEMENT_LOG_FILE="$PROJECT_DIR/$SELF_IMPROVEMENT_LOG_REL"
READY_ARCHIVE_DIR="$CONFIG_DIR/ready-archives"
SETUP_SUBREPOS_SCRIPT="$PROJECT_DIR/engines/setup-agent-subrepos.sh"

PROMPT_BUILD_FILE="$PROJECT_DIR/PROMPT_build.md"
PROMPT_PLAN_FILE="$PROJECT_DIR/PROMPT_plan.md"
PROMPT_TEST_FILE="$PROJECT_DIR/PROMPT_test.md"
PROMPT_REFACTOR_FILE="$PROJECT_DIR/PROMPT_refactor.md"
PROMPT_LINT_FILE="$PROJECT_DIR/PROMPT_lint.md"
PROMPT_DOCUMENT_FILE="$PROJECT_DIR/PROMPT_document.md"
PLAN_FILE="$PROJECT_DIR/IMPLEMENTATION_PLAN.md"
PROJECT_BOOTSTRAP_FILE="$CONFIG_DIR/project-bootstrap.md"
PROJECT_GOALS_FILE="$CONFIG_DIR/project-goals.md"
SESSION_CHANGED_PATHS_FILE="$CONFIG_DIR/session-changed-paths.txt"

# Shared logic for interactive questions and formatting.
err() { if [ -t 2 ] && [ "${TERM:-dumb}" != dumb ] && [ -z "${NO_COLOR+x}" ]; then printf '\033[1;31m%s\033[0m\n' "$*" >&2; else printf '%s\n' "$*" >&2; fi; }
warn() { if [ -t 2 ] && [ "${TERM:-dumb}" != dumb ] && [ -z "${NO_COLOR+x}" ]; then printf '\033[1;33m%s\033[0m\n' "$*" >&2; else printf '%s\n' "$*" >&2; fi; }
info() { if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] && [ -z "${NO_COLOR+x}" ]; then printf '\033[0;34m%s\033[0m\n' "$*"; else printf '%s\n' "$*"; fi; }
success() { if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] && [ -z "${NO_COLOR+x}" ]; then printf '\033[0;32m%s\033[0m\n' "$*"; else printf '%s\n' "$*"; fi; }
ok() { success "$@"; }

# Logging reasons for failures (doctrinal/state/inference)
log_reason_code() {
    local code="$1"
    local msg="$2"
    local safe_msg
    ensure_runtime_file "$REASON_LOG_FILE" || return 1
    ensure_runtime_directory "$(dirname "$REASON_LOG_FILE")" || return 1
    safe_msg="$(sanitize_text_for_log "$msg" | cut -c 1-2000 | sed 's/\\/\\\\/g; s/"/\\"/g')"
    echo "reason_code=$code message=\"$safe_msg\"" >> "$REASON_LOG_FILE"
}

path_for_display() {
    local p="${1:-}"
    [ -z "$p" ] && echo "unknown" && return 0
    echo "${p#./}"
}

# Runtime outputs belong to their selected project, even when an engine has
# replaced a parent directory. Validate before creating or writing anything.
validate_runtime_directory() {
    local path="${1%/}" anchor current root
    validate_root_path "$1" "Owned runtime directory" || return 1
    [ -n "$path" ] || path=/
    anchor="$path"
    for root in "${PROJECT_DIR:-}" "${SCRIPT_DIR:-}" "${CONFIG_DIR:-}"; do
        [ -n "$root" ] || continue
        case "$path" in "$root"|"$root"/*) anchor="$root"; break;; esac
    done
    current="$path"
    while :; do
        if [ -L "$current" ] || { [ -e "$current" ] && [ ! -d "$current" ]; }; then
            err "Refusing unsafe runtime directory: $(path_for_display "$current")"
            return 1
        fi
        [ "$current" != "$anchor" ] || break
        current="$(dirname "$current")"
    done
    return 0
}

ensure_runtime_directory() {
    validate_runtime_directory "$1" || return 1
    mkdir -p "$1"
}

ensure_runtime_file() {
    local path="$1" parent
    # dirname through command substitution would trim a parent's final LF
    # before the runtime-root validator could refuse the original bytes.
    case "$path" in
        */*) parent="${path%/*}"; [ -n "$parent" ] || parent=/ ;;
        *) parent=. ;;
    esac
    validate_runtime_directory "$parent" || return 1
    if [ -L "$path" ] || { [ -e "$path" ] && [ ! -f "$path" ]; }; then
        err "Refusing unsafe runtime file: $(path_for_display "$path")"
        return 1
    fi
    [ ! -e "$path" ] || [ -r "$path" ] || return 1
    return 0
}

validate_owned_runtime_paths() {
    local path
    for path in "$CONFIG_DIR" "$LOG_DIR" "$COMPLETION_LOG_DIR" "$CONSENSUS_DIR" \
        "$RESEARCH_DIR" "$SPECS_DIR" "$SPECIFY_DIR" "$READY_ARCHIVE_DIR"; do
        validate_runtime_directory "$path" || return 1
    done
    for path in "$CONFIG_FILE" "$LOCK_FILE" "$REASON_LOG_FILE" "$NOTIFICATION_LOG_FILE" \
        "$STATE_FILE" "$MISSION_OBJECTIVE_FILE" "$OWNED_PATHS_FILE" "$SHELL_GATES_FILE" \
        "$SHELL_VERIFICATION_LOG" "$GATE_FEEDBACK_FILE" "$PROJECT_BOOTSTRAP_FILE" \
        "$PROJECT_GOALS_FILE" "$SESSION_CHANGED_PATHS_FILE" "$CONSTITUTION_FILE" \
        "$PLAN_FILE" "$PROMPT_PLAN_FILE" "$PROMPT_BUILD_FILE" "$PROMPT_TEST_FILE" \
        "$PROMPT_REFACTOR_FILE" "$PROMPT_LINT_FILE" "$PROMPT_DOCUMENT_FILE" \
        "$RESEARCH_SUMMARY_FILE" "$STACK_SNAPSHOT_FILE" "$PROJECT_DIR/.gitignore" \
        "$CONFIG_DIR/no-local-work.manifest" "$CONFIG_DIR/no-local-work.binding"; do
        ensure_runtime_file "$path" || return 1
    done
    return 0
}

redact_endpoint_for_log() {
    local endpoint="${1:-}"
    if [ -z "$endpoint" ]; then
        echo "<default>"
        return 0
    fi

    # Keep logs safe: show protocol + host[:port] only, strip userinfo/path/query.
    if [[ "$endpoint" =~ ^[A-Za-z][A-Za-z0-9+.-]*:// ]]; then
        local scheme rest host
        scheme="${endpoint%%://*}://"
        rest="${endpoint#*://}"
        rest="${rest#*@}"
        rest="${rest%%/*}"
        rest="${rest%%\?*}"
        rest="${rest%%\#*}"
        host="$rest"
        if [ -n "$host" ]; then
            echo "${scheme}${host}"
            return 0
        fi
    fi

    echo "<custom-set>"
}

redact_secret_for_log() {
    local value="${1:-}"
    if [ -z "$value" ]; then
        echo "<unset>"
        return 0
    fi
    echo "<set:${#value} chars>"
}

json_escape_string() {
    local value="${1:-}"
    local code character escaped
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    # JSON forbids every raw C0 control, including bytes outside log redaction.
    # Bash strings cannot hold NUL; printf -v preserves newline for this loop.
    for ((code=1; code<32; code++)); do
        printf -v escaped '\\%03o' "$code"
        printf -v character '%b' "$escaped"
        printf -v escaped '\\u%04x' "$code"
        value="${value//"$character"/$escaped}"
    done
    printf '%s' "$value"
}

# Boolean helper
is_true() {
    case "${1:-}" in
        1|[Yy]|[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|ON|on) return 0 ;;
        *) return 1 ;;
    esac
}

is_bool_like() {
    case "${1:-}" in
        true|TRUE|True|false|FALSE|False|1|0|yes|YES|no|NO|on|ON|off|OFF|y|Y|n|N) return 0 ;;
        *) return 1 ;;
    esac
}

is_number() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

# Shell arithmetic is signed. Normalize decimal input before it reaches $(( )).
normalize_non_negative_decimal() {
    local value="${1:-}" maximum="${2:-9223372036854775807}" LC_ALL=C
    is_number "$value" || return 1
    value="${value#"${value%%[!0]*}"}"
    [ -n "$value" ] || value=0
    [ "${#value}" -le "${#maximum}" ] || return 1
    # Equal-length canonical decimals compare lexically without overflowing.
    # shellcheck disable=SC2071
    if [ "${#value}" -eq "${#maximum}" ] && [[ "$value" > "$maximum" ]]; then return 1; fi
    printf '%s' "$value"
}

checked_decimal_add() {
    local left right
    left="$(normalize_non_negative_decimal "${1:-}")" || return 1
    right="$(normalize_non_negative_decimal "${2:-}")" || return 1
    [ "$left" -le "$((9223372036854775807 - right))" ] || return 1
    printf '%s' "$((left + right))"
}

normalize_integer_setting() {
    local name="$1" minimum="${2:-0}" maximum="${3:-9223372036854775807}" value
    if ! value="$(normalize_non_negative_decimal "${!name}" "$maximum")" || [ "$value" -lt "$minimum" ]; then
        err "Invalid $name: expected a decimal integer from $minimum through $maximum."
        return 1
    fi
    printf -v "$name" '%s' "$value"
}

normalize_boolean_setting() {
    local name="$1" value
    value="${!name}"
    is_bool_like "$value" || { err "Invalid boolean value for $name."; return 1; }
    if is_true "$value"; then value=true; else value=false; fi
    printf -v "$name" '%s' "$value"
}

config_scalar_is_supported() {
    case "${1:-}" in *$'\n'*|*$'\r'*) return 1;; esac
    return 0
}

sanitize_text_for_log() {
    local value="${1:-}"
    value="$(printf '%s' "$value" | LC_ALL=C tr -d '\000-\010\013\014\016-\037\177')"
    value="$(printf '%s' "$value" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g' | sed 's/^ *//; s/ *$//')"
    printf '%s' "$value"
}

sanitize_review_score() {
    local score
    if ! score="$(normalize_non_negative_decimal "${1:-}" 100)"; then
        echo 0
        return 0
    fi
    echo "$score"
}

is_decimal_number() {
    [[ "${1:-}" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

version_score_from_text() {
    local text="${1:-}"
    local major=0
    local minor=0
    local patch=0

    if [[ "$text" =~ ([0-9]+)[.]([0-9]+)[.]([0-9]+) ]]; then
        major="$(normalize_non_negative_decimal "${BASH_REMATCH[1]}" 999999)" || return 1
        minor="$(normalize_non_negative_decimal "${BASH_REMATCH[2]}" 999)" || return 1
        patch="$(normalize_non_negative_decimal "${BASH_REMATCH[3]}" 999)" || return 1
    fi

    echo $((major * 1000000 + minor * 1000 + patch))
}

discover_versioned_command_default() {
    local command_name="$1"
    shift
    local -a candidates=()
    local candidate resolved version score
    local best_cmd="$command_name"
    local best_score=-1
    local seen_paths=$'\n'

    while IFS= read -r candidate; do
        [ -n "$candidate" ] && candidates+=("$candidate")
    done < <(type -a -p "$command_name" 2>/dev/null || true)

    for candidate in "$@"; do
        [ -n "$candidate" ] && candidates+=("$candidate")
    done
    candidates+=("$command_name")

    for candidate in "${candidates[@]}"; do
        if [ "$candidate" = "$command_name" ]; then
            resolved="$(command -v "$command_name" 2>/dev/null || true)"
        else
            resolved="$candidate"
        fi
        [ -n "$resolved" ] || continue
        case "$seen_paths" in
            *$'\n'"$resolved"$'\n'*) continue ;;
        esac
        seen_paths="${seen_paths}${resolved}"$'\n'
        [ -x "$resolved" ] || continue

        version="$(run_bounded_engine_metadata "$resolved" --version 2>/dev/null | head -n 1 || true)"
        score="$(version_score_from_text "$version")" || continue
        if [ "$score" -gt "$best_score" ]; then
            best_cmd="$resolved"
            best_score="$score"
        fi
    done

    echo "$best_cmd"
}

discover_codex_command_default() {
    discover_versioned_command_default \
        "codex" \
        "/opt/homebrew/bin/codex" \
        "/usr/local/bin/codex" \
        "${HOME:-}/.local/bin/codex"
}

discover_prime_command_default() {
    discover_versioned_command_default \
        "prime-agent" \
        "${HOME:-}/.local/bin/prime-agent" \
        "/opt/homebrew/bin/prime-agent" \
        "/usr/local/bin/prime-agent"
}

discover_claude_command_default() {
    discover_versioned_command_default \
        "claude" \
        "${HOME:-}/.local/bin/claude" \
        "/opt/homebrew/bin/claude" \
        "/usr/local/bin/claude"
}

extract_xml_value() {
    local file="$1"
    local tag="$2"
    local default="${3:-}"
    local value=""

    [ -f "$file" ] || { echo "$default"; return 0; }

    value="$(
        awk -v tag="$tag" '
            BEGIN {
                open_tag = "<" tag ">"
                close_tag = "</" tag ">"
                in_tag = 0
                current = ""
                last = ""
            }
            {
                line = $0
                while (length(line) > 0) {
                    if (!in_tag) {
                        start = index(line, open_tag)
                        if (start == 0) {
                            break
                        }
                        line = substr(line, start + length(open_tag))
                        current = ""
                        in_tag = 1
                    }

                    stop = index(line, close_tag)
                    if (stop > 0) {
                        current = current substr(line, 1, stop - 1)
                        last = current
                        line = substr(line, stop + length(close_tag))
                        current = ""
                        in_tag = 0
                    } else {
                        current = current line "\n"
                        break
                    }
                }
            }
            END {
                if (last != "") {
                    printf "%s", last
                }
            }
        ' "$file" 2>/dev/null
    )"
    value="$(sanitize_text_for_log "$value")"
    if [ -z "$value" ]; then
        echo "$default"
        return 0
    fi
    echo "$value"
}

xml_tag_count() {
    local file="$1"
    local tag="$2"
    [ -f "$file" ] || { echo "0"; return 0; }
    awk -v tag="$tag" '
        BEGIN { open_tag = "<" tag ">"; count = 0 }
        {
            line = $0
            while (length(line) > 0) {
                start = index(line, open_tag)
                if (start == 0) {
                    break
                }
                count++
                line = substr(line, start + length(open_tag))
            }
        }
        END { print count }
    ' "$file" 2>/dev/null || echo "0"
}

review_gaps_are_blocking() {
    local gaps="${1:-}"
    local normalized

    normalized="$(sanitize_text_for_log "$gaps" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    normalized="$(printf '%s' "$normalized" | sed 's/[[:space:]][[:space:]]*/ /g')"
    normalized="$(printf '%s' "$normalized" | sed 's/[[:space:]]*[.,;:][[:space:]]*$//')"
    case "$normalized" in
        ""|none|n/a|na|"not applicable"|"no gaps"|"no blockers"|"no blocking gaps"|"none blocking"|"no explicit gaps"|"no explicit blockers")
            return 1
            ;;
    esac
    return 0
}

consensus_clean_go_relaxation_allowed() {
    is_true "${CONSENSUS_SCORE_THRESHOLD_EXPLICIT:-false}" && return 1
    is_number "${CONSENSUS_SCORE_THRESHOLD:-}" || return 1
    is_number "${CONSENSUS_CLEAN_GO_SCORE_FLOOR:-}" || return 1
    [ "$CONSENSUS_SCORE_THRESHOLD" -gt "$CONSENSUS_CLEAN_GO_SCORE_FLOOR" ] || return 1
    return 0
}

review_score_passes_threshold() {
    local score="${1:-0}"
    local clean_go="${2:-false}"

    is_number "$score" || return 1
    if [ "$score" -ge "$CONSENSUS_SCORE_THRESHOLD" ]; then
        return 0
    fi
    if is_true "$clean_go" && consensus_clean_go_relaxation_allowed && [ "$score" -ge "$CONSENSUS_CLEAN_GO_SCORE_FLOOR" ]; then
        return 0
    fi
    return 1
}

extract_review_score() {
    local file="$1"
    local score
    score="$(extract_xml_value "$file" "score" "")"
    if ! is_number "$score"; then
        score=0
    fi
    sanitize_review_score "$score"
}

extract_review_verdict() {
    local file="$1"
    local verdict
    verdict="$(extract_xml_value "$file" "verdict" "")"
    case "$verdict" in
        GO|HOLD)
            echo "$verdict"
            return 0
            ;;
    esac

    verdict="$(extract_xml_value "$file" "decision" "")"
    case "$verdict" in
        GO|HOLD) echo "$verdict" ;;
        *) echo "HOLD" ;;
    esac
}

extract_review_gaps() {
    local file="$1"
    local limit="${2:-180}"
    local gaps
    gaps="$(extract_xml_value "$file" "gaps" "")"
    gaps="$(sanitize_text_for_log "$gaps" | cut -c 1-"$limit")"
    [ -n "$gaps" ] || gaps="no explicit gaps"
    echo "$gaps"
}

file_looks_like_auth_or_html_challenge() {
    local file="$1"
    [ -f "$file" ] || return 1
    grep -qiE '<!doctype html|<html[ >]|</html>|cf_chl|challenge-platform|challenge-error-text|enable javascript and cookies|authrequired|missing or invalid access token|invalid_token|window\._cf_chl_opt|cdn-cgi/challenge|cloudflare ray id|attention required! \| cloudflare' "$file" 2>/dev/null
}

review_fields_are_well_formed() {
    # Known fields are flat pairs. Counting tags alone accepts reversed or
    # crossing fields and lets an incomplete gaps value disappear as empty.
    # Compare raw bytes before log redaction. BSD awk cannot reliably match
    # NUL in a regex; a stream comparison also keeps it out of shell variables.
    LC_ALL=C tr -d '\000-\010\013\014\016-\037\177' < "$1" | cmp -s "$1" - || return 1
    LC_ALL=C awk '
        BEGIN { opened = ""; invalid = 0 }
        {
            line = $0
            while (match(line, /<\/?(score|verdict|gaps|next_phase|next_phase_reason)>/)) {
                token = substr(line, RSTART, RLENGTH)
                line = substr(line, RSTART + RLENGTH)
                closing = substr(token, 2, 1) == "/"
                offset = closing ? 3 : 2
                field = substr(token, offset, length(token) - offset)
                if (closing) {
                    if (opened != field) { invalid = 1; exit 1 }
                    opened = ""
                } else {
                    if (opened != "" || seen[field]) { invalid = 1; exit 1 }
                    seen[field] = 1
                    opened = field
                }
            }
        }
        END { if (invalid || opened != "") exit 1 }
    ' "$1"
}

review_output_invalid_reason() {
    local file="$1"
    local mode="${2:-consensus}"
    local score verdict next_phase gaps tag tag_count

    [ -s "$file" ] || { echo "missing reviewer output"; return 0; }

    if file_looks_like_auth_or_html_challenge "$file"; then
        echo "provider auth/challenge HTML or token error"
        return 0
    fi

    for tag in score verdict gaps next_phase; do
        if [ "$tag" = next_phase ] && [ "$mode" = handoff ]; then
            continue
        fi
        tag_count="$(xml_tag_count "$file" "$tag")"
        if ! is_number "$tag_count" || [ "$tag_count" -ne 1 ]; then
            echo "expected exactly one <$tag> tag, found ${tag_count:-0}"
            return 0
        fi
        tag_count="$(xml_tag_count "$file" "/$tag")"
        if ! is_number "$tag_count" || [ "$tag_count" -ne 1 ]; then
            echo "expected exactly one </$tag> tag, found ${tag_count:-0}"
            return 0
        fi
    done

    if ! review_fields_are_well_formed "$file"; then
        echo "review fields must be ordered, paired and nonnested"
        return 0
    fi

    score="$(extract_xml_value "$file" "score" "")"
    if ! score="$(normalize_non_negative_decimal "$score" 100)"; then
        echo "missing or invalid <score>"
        return 0
    fi

    verdict="$(extract_xml_value "$file" "verdict" "")"
    case "$verdict" in
        GO|HOLD) : ;;
        *)
            echo "missing or invalid <verdict>"
            return 0
            ;;
    esac

    gaps="$(extract_xml_value "$file" "gaps" "")"
    if [ "$verdict" = GO ] && review_gaps_are_blocking "$gaps"; then
        echo "blocking <gaps>: $(sanitize_text_for_log "$gaps" | cut -c 1-160)"
        return 0
    fi

    if [ "$mode" != "handoff" ]; then
        next_phase="$(extract_xml_value "$file" "next_phase" "")"
        next_phase="$(to_lower "$next_phase")"
        if ! is_phase_or_done "$next_phase"; then
            echo "missing or invalid <next_phase>"
            return 0
        fi
    fi

    echo ""
}

write_invalid_reviewer_output_placeholder() {
    local output_file="$1"
    local reason="$2"
    local raw_file="$3"

    reason="$(sanitize_text_for_log "$reason")"
    {
        echo "Reviewer output was rejected by Ralphie before consensus parsing."
        echo "reason: ${reason:-invalid reviewer output}"
        if [ -n "$raw_file" ]; then
            echo "raw_output_artifact: $(path_for_display "$raw_file")"
        fi
        echo "The raw output was not used for score, verdict, or phase routing."
    } > "$output_file"
}

safe_print_file_head() {
    local file="$1"
    local lines="${2:-80}"
    is_number "$lines" || lines=80
    if [ ! -f "$file" ]; then
        echo "- not available"
        return 0
    fi
    if file_looks_like_auth_or_html_challenge "$file"; then
        echo "- redacted: provider auth/challenge HTML or token-error output"
        return 0
    fi
    sed -n "1,${lines}p" "$file"
}

safe_print_file_tail() {
    local file="$1"
    local lines="${2:-40}"
    is_number "$lines" || lines=40
    if [ ! -f "$file" ]; then
        echo "- not available"
        return 0
    fi
    if file_looks_like_auth_or_html_challenge "$file"; then
        echo "- redacted: provider auth/challenge HTML or token-error output"
        return 0
    fi
    tail -n "$lines" "$file"
}

mark_engine_capture_failed() {
    # Removing a precreated empty witness needs no data write after ENOSPC.
    [ -z "${capture_recording_marker:-}" ] || rm -f -- "$capture_recording_marker" || return 74
    return 0
}

stream_engine_output() (
    local log_file="$1"
    local output_file="${2:-}"
    local stdout_enabled="${3:-true}"
    if is_true "$stdout_enabled"; then stdout_enabled=true; else stdout_enabled=false; fi
    local ceiling capture="" stream_exit captured_bytes copy_status
    local capture_error_pipe="" capture_error_pid="" capture_error_byte capture_cleanup_status
    trap '
        capture_cleanup_status=$?
        if [ "$capture_cleanup_status" -eq 74 ]; then mark_engine_capture_failed || true; fi
        if [ -n "$capture_error_pid" ]; then
            kill "$capture_error_pid" 2>/dev/null || true
            wait "$capture_error_pid" 2>/dev/null || true
        fi
        [ -z "$capture_error_pipe" ] || rm -f -- "$capture_error_pipe"
        [ -z "$capture" ] || rm -f -- "$capture"
    ' EXIT
    trap 'exit 143' HUP INT TERM
    ensure_runtime_file "$log_file" || return 74
    [ -z "$output_file" ] || ensure_runtime_file "$output_file" || return 74
    ceiling="${ENGINE_OUTPUT_MAX_BYTES:-16777216}"
    is_number "$ceiling" && [ "$ceiling" -gt 0 ] || ceiling=16777216
    capture="$(mktemp "${engine_scratch_dir:-${TMPDIR:-/tmp}}/capture.XXXXXX")" || return 74
    stream_exit=0

    if [ -n "$output_file" ]; then
        : > "$output_file" || return 74
    fi

    # tee may report a write error and keep reading. Signal that error before
    # either tee or its producer finishes, including when the producer pauses.
    capture_error_pipe="$capture.errors"
    mkfifo "$capture_error_pipe" || return 74
    (
        if IFS= read -r -n 1 capture_error_byte; then
            mark_engine_capture_failed || exit 74
            cat >/dev/null || exit 74
        fi
        exit 0
    ) < "$capture_error_pipe" &
    capture_error_pid=$!

    # Bound bytes before line parsing: even an endless line cannot fill the
    # log or awk's buffer. Drain excess so the child can finish or be timed out.
    {
        copy_status=0
        if head -c "$((ceiling + 1))" | {
            if tee "$capture" 2> "$capture_error_pipe"; then :; else
                mark_engine_capture_failed || exit 74
                exit 74
            fi
        }; then :; else copy_status=74; fi
        if captured_bytes="$(wc -c < "$capture" | tr -d ' ')" && is_number "$captured_bytes"; then
            if [ "$captured_bytes" -gt "$ceiling" ] && [ -n "${capture_limit_marker:-}" ]; then
                : > "$capture_limit_marker" || copy_status=74
            fi
        else
            copy_status=74
        fi
        if [ "$copy_status" -ne 0 ]; then mark_engine_capture_failed || exit 74; exit 74; fi
        cat >/dev/null || { mark_engine_capture_failed || exit 74; exit 74; }
    } | {
        if RB_CAPTURE_LOG="$log_file" RB_CAPTURE_OUTPUT="$output_file" RB_CAPTURE_STDOUT="$stdout_enabled" \
        RB_CAPTURE_PERMANENT="${capture_permanent_marker:-}" awk '
        function emit(line) {
            if (stdout_enabled == "true") {
                print line
            }
            print line >> log_file
            if (output_file != "") {
                print line >> output_file
            }
            if (stdout_enabled == "true") {
                fflush()
            }
            fflush(log_file)
            if (output_file != "") {
                fflush(output_file)
            }
        }
        function clear_buffer() {
            buffer_count = 0
        }
        function flush_buffer(    i) {
            for (i = 1; i <= buffer_count; i++) {
                emit(buffer[i])
            }
            clear_buffer()
        }
        function push_buffer(line,    i) {
            buffer_count++
            buffer[buffer_count] = line
            if (buffer_count > max_buffer) {
                emit(buffer[1])
                for (i = 1; i < buffer_count; i++) {
                    buffer[i] = buffer[i + 1]
                }
                buffer_count--
            }
        }
        function looks_like_challenge(line) {
            lower = tolower(line)
            return lower ~ /<!doctype html|<html[ >]|<\/html>|cf_chl|challenge-platform|challenge-error-text|enable javascript and cookies|auth required|missing or invalid access token|invalid_token|window\._cf_chl_opt|cdn-cgi\/challenge|cloudflare ray id|attention required! \| cloudflare/
        }
        function looks_like_engine_reentry(line) {
            return line ~ /^(OpenAI Codex|Claude|workdir:|model:|provider:|approval:|sandbox:|reasoning effort:|reasoning summaries:|session id:|tokens used|--------)/
        }
        BEGIN {
            log_file=ENVIRON["RB_CAPTURE_LOG"]; output_file=ENVIRON["RB_CAPTURE_OUTPUT"]
            stdout_enabled=ENVIRON["RB_CAPTURE_STDOUT"]; permanent_file=ENVIRON["RB_CAPTURE_PERMANENT"]
            max_buffer = 80
            buffer_count = 0
            redacting = 0
            redacting_count = 0
            redacted_once = 0
        }
        {
            lower = tolower($0)
            # Keep only a category marker, before sensitive diagnostics disappear.
            if (permanent_file != "" && lower ~ /invalid.*api.?key|no api.?key|missing api.?key|authentication.*failed|not authenticated|permission.*denied|unknown provider|model.*not.*found|no models available|no model selected|insufficient.*quota|auth required|missing or invalid access token|invalid_token|unauthorized|authentication_error/) {
                print "configuration" > permanent_file; close(permanent_file)
            }
            if (redacting) {
                if (lower ~ /<\/html>/) {
                    redacting = 0
                    redacting_count = 0
                    next
                }
                if (looks_like_engine_reentry($0)) {
                    redacting = 0
                    redacting_count = 0
                    push_buffer($0)
                    next
                }
                redacting_count++
                if (redacting_count % 80 == 0) {
                    emit("[ralphie still redacting provider auth/challenge output]")
                }
                next
            }
            if (looks_like_challenge($0)) {
                clear_buffer()
                if (!redacted_once) {
                    emit("[ralphie redacted provider auth/challenge output]")
                    redacted_once = 1
                }
                if (lower !~ /<\/html>/) {
                    redacting = 1
                    redacting_count = 0
                }
                next
            }
            push_buffer($0)
        }
        END {
            if (!redacting) {
                flush_buffer()
            }
        }
        '; then exit 0; fi
        mark_engine_capture_failed || exit 74
        exit 74
    } || stream_exit=$?
    if wait "$capture_error_pid"; then :; else stream_exit=74; fi
    capture_error_pid=""
    captured_bytes="$(wc -c < "$capture" | tr -d ' ')" && is_number "$captured_bytes" || return 74
    rm -f "$capture"
    if [ "$captured_bytes" -gt "$ceiling" ]; then
        warn "Engine output exceeded ${ceiling} bytes; this attempt is not accepted."
        [ -z "$output_file" ] || : > "$output_file"
        return 125
    fi
    # Conditional callers disable errexit inside functions. A local recording
    # failure must survive the drain and must never become provider retry fuel.
    [ "$stream_exit" -eq 0 ] || return 74
    return 0
)

is_phase_or_done() {
    case "$1" in
        plan|build|test|refactor|lint|document|done) return 0 ;;
        *) return 1 ;;
    esac
}

normalize_phase_name() {
    local phase="${1:-}"
    phase="$(to_lower "$phase")"
    case "$phase" in
        plan) phase="plan" ;;
        build) phase="build" ;;
        test) phase="test" ;;
        refactor) phase="refactor" ;;
        lint) phase="lint" ;;
        document) phase="document" ;;
        done) phase="done" ;;
        *)
            warn "Unrecognized phase name '$phase', defaulting to 'plan'"
            phase="plan"
            ;;
    esac
    echo "$phase"
}

normalize_next_phase_recommendation() {
    local candidate="${1:-}"
    local current_phase="${2:-}"
    local fallback="${3:-done}"

    candidate="$(to_lower "$candidate")"
    current_phase="$(normalize_phase_name "$current_phase")"

    case "$candidate" in
        plan|build|test|refactor|lint|document|done) echo "$candidate" ; return 0 ;;
        next|forward|proceed|continue) echo "$fallback" ; return 0 ;;
        same|retry|retry_current|hold|stay) echo "$current_phase" ; return 0 ;;
        complete|completed|finished|finish|success|goal) echo "done" ; return 0 ;;
        stop|abort|halt) echo "done" ; return 0 ;;
        *)
            echo "$fallback"
            return 1
            ;;
    esac
}

print_array_lines() {
    local -a lines=("$@")
    local line

    [ "${#lines[@]}" -eq 0 ] && return 0
    [ "${#lines[@]}" -eq 1 ] && [ -z "${lines[0]}" ] && return 0
    for line in "${lines[@]}"; do
        printf '%s\n' "$line"
    done
}

# Compatibility layer for environments that still run Bash 3.x (for example, macOS
# default Bash), which lack the `mapfile` builtin used throughout this script.
if ! command -v mapfile >/dev/null 2>&1; then
    mapfile() {
        if [[ "${1:-}" == -t ]]; then
            shift
        fi

        local var_name="${1:-MAPFILE}"
        if [ -z "$var_name" ]; then
            return 1
        fi
        if [[ ! "$var_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            return 1
        fi

        # Safer alternative to eval: use nameref if available (Bash 4.3+),
        # otherwise fall back to a temp file approach
        local __mapfile_idx=0
        local __mapfile_line
        local __mapfile_escaped
        # Reset the target array
        eval "${var_name}=()"

        while IFS= read -r __mapfile_line || [ -n "$__mapfile_line" ]; do
            # Use printf %q for safe escaping of arbitrary content
            printf -v __mapfile_escaped '%q' "$__mapfile_line" 2>/dev/null || __mapfile_escaped="$__mapfile_line"
            eval "${var_name}[${__mapfile_idx}]=${__mapfile_escaped}"
            __mapfile_idx=$((__mapfile_idx + 1))
        done

        return 0
    }
fi

is_phase_noop_policy() {
    case "${1:-}" in
        hard|soft|none) return 0 ;;
        *) return 1 ;;
    esac
}

normalize_phase_noop_policy() {
    local policy="${1:-none}"
    case "$policy" in
        hard|soft|none) echo "$policy" ;;
        *) echo "none" ;;
    esac
}

is_phase_manifest_mode() {
    case "$(to_lower "${1:-}")" in
        light|deep) return 0 ;;
        *) return 1 ;;
    esac
}

normalize_phase_manifest_mode() {
    local mode
    mode="$(to_lower "${1:-$DEFAULT_PHASE_MANIFEST_MODE}")"
    case "$mode" in
        light|deep) echo "$mode" ;;
        *)
            warn "Invalid PHASE_MANIFEST_MODE '$mode'. Falling back to '$DEFAULT_PHASE_MANIFEST_MODE'."
            echo "$DEFAULT_PHASE_MANIFEST_MODE"
            ;;
    esac
}

to_lower() {
    printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]'
}

normalize_engine_name() {
    config_scalar_is_supported "${1:-}" || { err 'Unsupported multiline engine name.'; return 1; }
    case "$(to_lower "${1:-}")" in
        prime) printf 'prime-agent' ;;
        *) to_lower "${1:-}" ;;
    esac
}

engine_auto_order() {
    local preferred name
    preferred="$(normalize_engine_name "${AUTO_ENGINE_PREFERENCE:-prime-agent}")"
    printf '%s\n' "$preferred"
    for name in prime-agent codex claude; do
        [ "$name" = "$preferred" ] || printf '%s\n' "$name"
    done
}

awk_regex_is_valid() {
    local regex="${1:-}"
    [ -z "$regex" ] && return 0
    RB_AWK_REGEX="$regex" awk 'BEGIN { re=ENVIRON["RB_AWK_REGEX"]; if ("" ~ re) { } }' >/dev/null 2>&1
}

is_allowed_config_key() {
    local key="${1:-}"
    case "$key" in
        RALPHIE_ENGINE|RALPHIE_QUALITY_LEVEL|RALPHIE_GATE_TIMEOUT_SECONDS|RALPHIE_RESUME_REQUESTED|RALPHIE_REBOOTSTRAP_REQUESTED)
            return 0
            ;;
        RALPHIE_*)
            # A namespace is not permission to replace process bookkeeping.
            key="${key#RALPHIE_}"
            ;;
    esac
    case "$key" in
        # Explicitly supported non-prefixed compatibility keys.
        COMMAND_TIMEOUT_SECONDS|MAX_ITERATIONS|MAX_SESSION_CYCLES|YOLO|AUTO_UPDATE|AUTO_UPDATE_URL|\
        AUTO_UPDATE_ALLOW_DIRTY|AUTO_UPDATE_ALLOW_INSECURE|AUTO_UPDATE_TIMEOUT_SECONDS|AUTO_UPDATE_LOCK_TIMEOUT_SECONDS|\
        SWARM_MAX_PARALLEL|CONFIDENCE_TARGET|CONFIDENCE_STAGNATION_LIMIT|\
        AUTO_PLAN_BACKFILL_ON_IDLE_BUILD|AUTO_ENGINE_PREFERENCE|AUTO_INIT_GIT_IF_MISSING|\
        AUTO_COMMIT_ON_PHASE_PASS|CODEX_ENDPOINT|CODEX_USE_RESPONSES_SCHEMA|\
        CODEX_RESPONSES_SCHEMA_FILE|CODEX_THINKING_OVERRIDE|CLAUDE_ENDPOINT|CLAUDE_THINKING_OVERRIDE|\
        RUN_AGENT_MAX_ATTEMPTS|RUN_AGENT_RETRY_DELAY_SECONDS|RUN_AGENT_RETRY_VERBOSE|\
        ENGINE_OUTPUT_TO_STDOUT|ENGINE_IDLE_OUTPUT_TIMEOUT_SECONDS|STRICT_VALIDATION_NOOP|PHASE_COMPLETION_MAX_ATTEMPTS|\
        PHASE_COMPLETION_RETRY_DELAY_SECONDS|PHASE_COMPLETION_RETRY_VERBOSE|\
        MAX_CONSENSUS_ROUTING_ATTEMPTS|PHASE_PAIR_CYCLE_LIMIT|REQUIRE_LINT_BEFORE_DONE|REQUIRE_DOCUMENT_BEFORE_DONE|\
        REQUIRE_PLAN_BACKLOG_CLEAR_BEFORE_DONE|REQUIRE_PLAN_FRESHNESS_FOR_BUILD|BACKLOG_SOURCES|\
        PHASE_NOOP_POLICY_PLAN|PHASE_NOOP_POLICY_BUILD|\
        PHASE_NOOP_POLICY_TEST|PHASE_NOOP_POLICY_REFACTOR|PHASE_NOOP_POLICY_LINT|\
        PHASE_NOOP_POLICY_DOCUMENT|PHASE_NOOP_PROFILE|SESSION_TOKEN_BUDGET|\
        SESSION_TOKEN_RATE_CENTS_PER_MILLION|SESSION_COST_BUDGET_CENTS|AUTO_REPAIR_MARKDOWN_ARTIFACTS|\
        AUTO_REPAIR_MARKDOWN_DRY_RUN|AUTO_REPAIR_MARKDOWN_BACKUP|AUTO_REPAIR_MARKDOWN_ONLY_SESSION_CHANGED|\
        MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX|PHASE_MANIFEST_MODE|\
        SWARM_CONSENSUS_TIMEOUT|CONSENSUS_SCORE_THRESHOLD|CONSENSUS_CLEAN_GO_SCORE_FLOOR|ENGINE_HEALTH_MAX_ATTEMPTS|\
        ENGINE_HEALTH_RETRY_DELAY_SECONDS|ENGINE_HEALTH_RETRY_VERBOSE|ENGINE_SMOKE_TEST_TIMEOUT|\
        STARTUP_OPERATIONAL_PROBE|ENGINE_OVERRIDES_BOOTSTRAPPED|NOTIFICATIONS_ENABLED|\
        NOTIFY_TELEGRAM_ENABLED|NOTIFY_DISCORD_ENABLED|NOTIFY_DISCORD_WEBHOOK_URL|\
        NOTIFY_TTS_ENABLED|NOTIFY_TTS_STYLE|NOTIFY_CHUTES_TTS_URL|NOTIFY_CHUTES_VOICE|NOTIFY_CHUTES_SPEED|\
        NOTIFY_EVENT_DEDUP_WINDOW_SECONDS|NOTIFY_INCIDENT_REMINDER_MINUTES|\
        NOTIFICATION_WIZARD_BOOTSTRAPPED|TG_BOT_TOKEN|TG_CHAT_ID|CHUTES_API_KEY|\
        CODEX_ENGINE_CMD|CLAUDE_ENGINE_CMD|CODEX_MODEL|CLAUDE_MODEL|PHASE_WALLCLOCK_LIMIT_SECONDS|\
        PRIME_ENGINE_CMD|PRIME_PROVIDER|PRIME_MODEL|PRIME_THINKING_OVERRIDE|ENGINE_OUTPUT_MAX_BYTES)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

mark_phase_noop_policy_explicit_by_key() {
    case "${1:-}" in
        PHASE_NOOP_POLICY_PLAN|RALPHIE_PHASE_NOOP_POLICY_PLAN) PHASE_NOOP_POLICY_PLAN_EXPLICIT=true ;;
        PHASE_NOOP_POLICY_BUILD|RALPHIE_PHASE_NOOP_POLICY_BUILD) PHASE_NOOP_POLICY_BUILD_EXPLICIT=true ;;
        PHASE_NOOP_POLICY_TEST|RALPHIE_PHASE_NOOP_POLICY_TEST) PHASE_NOOP_POLICY_TEST_EXPLICIT=true ;;
        PHASE_NOOP_POLICY_REFACTOR|RALPHIE_PHASE_NOOP_POLICY_REFACTOR) PHASE_NOOP_POLICY_REFACTOR_EXPLICIT=true ;;
        PHASE_NOOP_POLICY_LINT|RALPHIE_PHASE_NOOP_POLICY_LINT) PHASE_NOOP_POLICY_LINT_EXPLICIT=true ;;
        PHASE_NOOP_POLICY_DOCUMENT|RALPHIE_PHASE_NOOP_POLICY_DOCUMENT) PHASE_NOOP_POLICY_DOCUMENT_EXPLICIT=true ;;
        *) ;;
    esac
}

# Portable pseudo-random number (0..32767). Uses $RANDOM when available (interactive
# bash), falls back to /dev/urandom or PID-seeded arithmetic for non-interactive shells.
portable_random() {
    if [ -n "${RANDOM+x}" ]; then
        echo "$RANDOM"
    elif [ -n "${BASH_VERSION:-}" ]; then
        # In some shells $RANDOM may appear unset until first use.
        # Force initialization once, then use it.
        : "${RANDOM:=0}"
        echo "$RANDOM"
    elif [ -r /dev/urandom ]; then
        od -An -tu2 -N2 /dev/urandom 2>/dev/null | tr -d ' \n' || echo 0
    else
        # Last resort: deterministic but varies per PID and second
        echo $(( ($$ * $(date +%s)) % 32768 ))
    fi
}

load_config_file_safe() {
    local file="$1"
    local file_display
    local line
    local key
    local raw_value
    local value
    local line_no=0

    [ -f "$file" ] || return 0
    file_display="$(path_for_display "$file")"

    while IFS= read -r line || [ -n "$line" ]; do
        line_no=$((line_no + 1))
        line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [ -z "$line" ] && continue
        [[ "$line" == \#* ]] && continue

        if [[ ! "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            warn "Skipping invalid config line $line_no in $file_display: $line"
            continue
        fi

        key="${BASH_REMATCH[1]}"
        raw_value="${BASH_REMATCH[2]}"
        raw_value="$(printf '%s' "$raw_value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

        # Backward-compatibility aliases for legacy config keys.
        case "$key" in
            AUTO_UPDATE_ENABLED) key="AUTO_UPDATE" ;;
            AUTO_PREPARE_BACKFILL_ON_IDLE_BUILD) key="AUTO_PLAN_BACKFILL_ON_IDLE_BUILD" ;;
        esac

        case "$key" in
            AUTO_UPDATE|RALPHIE_AUTO_UPDATE|RALPHIE_UPDATE_URL|AUTO_UPDATE_URL|RALPHIE_AUTO_UPDATE_URL|AUTO_UPDATE_ALLOW_DIRTY|RALPHIE_AUTO_UPDATE_ALLOW_DIRTY|AUTO_UPDATE_ALLOW_INSECURE|RALPHIE_AUTO_UPDATE_ALLOW_INSECURE)
                warn "Ignoring operator-only update setting '$key' in $file_display."
                continue
                ;;
        esac
        # Prevent config files from mutating critical shell interpreter behavior.
        case "$key" in
            BASH_ENV|ENV|SHELLOPTS|BASHOPTS|BASH_XTRACEFD|IFS|PATH|CDPATH|GLOBIGNORE|PROMPT_COMMAND|PS4)
                warn "Ignoring unsafe config key '$key' in $file_display."
                continue
                ;;
        esac
        if ! is_allowed_config_key "$key"; then
            warn "Ignoring unsupported config key '$key' in $file_display."
            continue
        fi
        # Preserve exported environment precedence over config file values.
        # This keeps layering deterministic: defaults -> config.env -> env -> CLI.
        if printenv "$key" >/dev/null 2>&1; then
            continue
        fi
        local compatibility_key="${key#RALPHIE_}" alias_key=""
        case "$compatibility_key" in
            CODEX_ENGINE_CMD|CLAUDE_ENGINE_CMD) ;;
            *)
                if is_allowed_config_key "$compatibility_key"; then
                    if [ "$key" = "$compatibility_key" ]; then alias_key="RALPHIE_$key"; else alias_key="$compatibility_key"; fi
                fi ;;
        esac
        if [ -n "$alias_key" ] && printenv "$alias_key" >/dev/null 2>&1; then continue; fi

        # For unquoted values, allow trailing comments using '#'.
        if [[ ! "$raw_value" =~ ^\".*\"$ ]] && [[ ! "$raw_value" =~ ^\'.*\'$ ]]; then
            # Strip inline comments only when '#' is preceded by whitespace,
            # preserving literal '#' in tokens (for example API keys/URLs).
            raw_value="$(printf '%s' "$raw_value" | sed 's/[[:space:]]#.*$//; s/[[:space:]]*$//')"
        fi

        value="$raw_value"
        case "$value" in
            \"*) [[ "$value" =~ ^\".*\"$ ]] || { err "Unsupported multiline or unterminated config value for $key."; return 1; } ;;
            \'*) [[ "$value" =~ ^\'.*\'$ ]] || { err "Unsupported multiline or unterminated config value for $key."; return 1; } ;;
        esac
        config_scalar_is_supported "$value" || { err "Unsupported multiline config value for $key."; return 1; }
        if [[ "$value" =~ ^\".*\"$ ]] && [ "${#value}" -ge 2 ]; then
            value="${value:1:${#value}-2}"
            value="${value//\\\"/\"}"
            value="${value//\\\\/\\}"
        elif [[ "$value" =~ ^\'.*\'$ ]] && [ "${#value}" -ge 2 ]; then
            value="${value:1:${#value}-2}"
        fi

        # Literal assignment (no command or parameter expansion).
        if ! printf -v "$key" '%s' "$value" 2>/dev/null; then
            warn "Ignoring config key '$key' in $file_display: assignment failed (readonly or invalid target)."
            continue
        fi
        mark_phase_noop_policy_explicit_by_key "$key"
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
    local escaped
    local tmp_config_file

    if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        warn "Refusing to persist invalid config key '$key'."
        return 1
    fi
    if ! is_allowed_config_key "$key"; then
        warn "Refusing to persist unsupported config key '$key'."
        return 1
    fi

    config_scalar_is_supported "$value" || { err "Cannot persist multiline config value for $key."; return 1; }
    ensure_runtime_file "$CONFIG_FILE" || return 1
    ensure_runtime_directory "$(dirname "$CONFIG_FILE")" || return 1
    touch "$CONFIG_FILE" || return 1
    escaped="$(config_escape_double_quotes "$value")"
    tmp_config_file="$(mktemp "$CONFIG_DIR/config-upsert.XXXXXX")" || return 1

    if ! RB_CONFIG_KEY="$key" RB_CONFIG_VALUE="$escaped" awk '
        BEGIN {
            key=ENVIRON["RB_CONFIG_KEY"]; value=ENVIRON["RB_CONFIG_VALUE"]
            found=0
        }
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
    ' "$CONFIG_FILE" > "$tmp_config_file"; then
        rm -f "$tmp_config_file"
        return 1
    fi

    if ! mv "$tmp_config_file" "$CONFIG_FILE"; then
        rm -f "$tmp_config_file"
        return 1
    fi
    return 0
}

normalize_phase_noop_profile() {
    local profile="${1:-balanced}"
    case "$profile" in
        strict|balanced|custom) ;;
        read-only-first|read_only_first|readonly)
            profile="read-only-first"
            ;;
        *) profile="custom" ;;
    esac
    echo "$profile"
}

is_phase_noop_profile() {
    case "${1:-}" in
        strict|balanced|read-only-first|read_only_first|readonly|custom) return 0 ;;
        *) return 1 ;;
    esac
}

apply_phase_noop_profile() {
    local profile
    profile="$(normalize_phase_noop_profile "$PHASE_NOOP_PROFILE")"
    PHASE_NOOP_PROFILE="$profile"

    case "$profile" in
        strict)
            [ "$PHASE_NOOP_POLICY_PLAN_EXPLICIT" != "true" ] && PHASE_NOOP_POLICY_PLAN="hard"
            [ "$PHASE_NOOP_POLICY_BUILD_EXPLICIT" != "true" ] && PHASE_NOOP_POLICY_BUILD="hard"
            [ "$PHASE_NOOP_POLICY_TEST_EXPLICIT" != "true" ] && PHASE_NOOP_POLICY_TEST="hard"
            [ "$PHASE_NOOP_POLICY_REFACTOR_EXPLICIT" != "true" ] && PHASE_NOOP_POLICY_REFACTOR="hard"
            [ "$PHASE_NOOP_POLICY_LINT_EXPLICIT" != "true" ] && PHASE_NOOP_POLICY_LINT="hard"
            [ "$PHASE_NOOP_POLICY_DOCUMENT_EXPLICIT" != "true" ] && PHASE_NOOP_POLICY_DOCUMENT="hard"
            ;;
        read-only-first|read_only_first|readonly)
            [ "$PHASE_NOOP_POLICY_PLAN_EXPLICIT" != "true" ] && PHASE_NOOP_POLICY_PLAN="none"
            [ "$PHASE_NOOP_POLICY_BUILD_EXPLICIT" != "true" ] && PHASE_NOOP_POLICY_BUILD="hard"
            [ "$PHASE_NOOP_POLICY_TEST_EXPLICIT" != "true" ] && PHASE_NOOP_POLICY_TEST="soft"
            [ "$PHASE_NOOP_POLICY_REFACTOR_EXPLICIT" != "true" ] && PHASE_NOOP_POLICY_REFACTOR="none"
            [ "$PHASE_NOOP_POLICY_LINT_EXPLICIT" != "true" ] && PHASE_NOOP_POLICY_LINT="soft"
            [ "$PHASE_NOOP_POLICY_DOCUMENT_EXPLICIT" != "true" ] && PHASE_NOOP_POLICY_DOCUMENT="none"
            ;;
        balanced|custom|"")
            [ "$PHASE_NOOP_POLICY_PLAN_EXPLICIT" != "true" ] && PHASE_NOOP_POLICY_PLAN="none"
            [ "$PHASE_NOOP_POLICY_BUILD_EXPLICIT" != "true" ] && PHASE_NOOP_POLICY_BUILD="hard"
            [ "$PHASE_NOOP_POLICY_TEST_EXPLICIT" != "true" ] && PHASE_NOOP_POLICY_TEST="soft"
            [ "$PHASE_NOOP_POLICY_REFACTOR_EXPLICIT" != "true" ] && PHASE_NOOP_POLICY_REFACTOR="hard"
            [ "$PHASE_NOOP_POLICY_LINT_EXPLICIT" != "true" ] && PHASE_NOOP_POLICY_LINT="soft"
            [ "$PHASE_NOOP_POLICY_DOCUMENT_EXPLICIT" != "true" ] && PHASE_NOOP_POLICY_DOCUMENT="soft"
            ;;
        *)
            :
            ;;
    esac

    PHASE_NOOP_POLICY_PLAN="$(normalize_phase_noop_policy "$PHASE_NOOP_POLICY_PLAN")"
    PHASE_NOOP_POLICY_BUILD="$(normalize_phase_noop_policy "$PHASE_NOOP_POLICY_BUILD")"
    PHASE_NOOP_POLICY_TEST="$(normalize_phase_noop_policy "$PHASE_NOOP_POLICY_TEST")"
    PHASE_NOOP_POLICY_REFACTOR="$(normalize_phase_noop_policy "$PHASE_NOOP_POLICY_REFACTOR")"
    PHASE_NOOP_POLICY_LINT="$(normalize_phase_noop_policy "$PHASE_NOOP_POLICY_LINT")"
    PHASE_NOOP_POLICY_DOCUMENT="$(normalize_phase_noop_policy "$PHASE_NOOP_POLICY_DOCUMENT")"
}

finalize_phase_noop_profile_config() {
    PHASE_NOOP_PROFILE="${PHASE_NOOP_PROFILE:-$DEFAULT_PHASE_NOOP_PROFILE}"
    PHASE_NOOP_POLICY_PLAN="${PHASE_NOOP_POLICY_PLAN:-$DEFAULT_PHASE_NOOP_POLICY_PLAN}"
    PHASE_NOOP_POLICY_BUILD="${PHASE_NOOP_POLICY_BUILD:-$DEFAULT_PHASE_NOOP_POLICY_BUILD}"
    PHASE_NOOP_POLICY_TEST="${PHASE_NOOP_POLICY_TEST:-$DEFAULT_PHASE_NOOP_POLICY_TEST}"
    PHASE_NOOP_POLICY_REFACTOR="${PHASE_NOOP_POLICY_REFACTOR:-$DEFAULT_PHASE_NOOP_POLICY_REFACTOR}"
    PHASE_NOOP_POLICY_LINT="${PHASE_NOOP_POLICY_LINT:-$DEFAULT_PHASE_NOOP_POLICY_LINT}"
    PHASE_NOOP_POLICY_DOCUMENT="${PHASE_NOOP_POLICY_DOCUMENT:-$DEFAULT_PHASE_NOOP_POLICY_DOCUMENT}"

    PHASE_NOOP_PROFILE="$(to_lower "$PHASE_NOOP_PROFILE")"
    if ! is_phase_noop_profile "$PHASE_NOOP_PROFILE"; then
        PHASE_NOOP_PROFILE="$DEFAULT_PHASE_NOOP_PROFILE"
    fi
    PHASE_NOOP_PROFILE="$(normalize_phase_noop_profile "$PHASE_NOOP_PROFILE")"
    PHASE_NOOP_POLICY_PLAN="$(normalize_phase_noop_policy "$(to_lower "$PHASE_NOOP_POLICY_PLAN")")"
    PHASE_NOOP_POLICY_BUILD="$(normalize_phase_noop_policy "$(to_lower "$PHASE_NOOP_POLICY_BUILD")")"
    PHASE_NOOP_POLICY_TEST="$(normalize_phase_noop_policy "$(to_lower "$PHASE_NOOP_POLICY_TEST")")"
    PHASE_NOOP_POLICY_REFACTOR="$(normalize_phase_noop_policy "$(to_lower "$PHASE_NOOP_POLICY_REFACTOR")")"
    PHASE_NOOP_POLICY_LINT="$(normalize_phase_noop_policy "$(to_lower "$PHASE_NOOP_POLICY_LINT")")"
    PHASE_NOOP_POLICY_DOCUMENT="$(normalize_phase_noop_policy "$(to_lower "$PHASE_NOOP_POLICY_DOCUMENT")")"

    apply_phase_noop_profile

    if is_true "$STRICT_VALIDATION_NOOP"; then
        PHASE_NOOP_POLICY_TEST="hard"
        PHASE_NOOP_POLICY_LINT="hard"
    fi

    PHASE_NOOP_POLICY_PLAN="$(normalize_phase_noop_policy "$PHASE_NOOP_POLICY_PLAN")"
    PHASE_NOOP_POLICY_BUILD="$(normalize_phase_noop_policy "$PHASE_NOOP_POLICY_BUILD")"
    PHASE_NOOP_POLICY_TEST="$(normalize_phase_noop_policy "$PHASE_NOOP_POLICY_TEST")"
    PHASE_NOOP_POLICY_REFACTOR="$(normalize_phase_noop_policy "$PHASE_NOOP_POLICY_REFACTOR")"
    PHASE_NOOP_POLICY_LINT="$(normalize_phase_noop_policy "$PHASE_NOOP_POLICY_LINT")"
    PHASE_NOOP_POLICY_DOCUMENT="$(normalize_phase_noop_policy "$PHASE_NOOP_POLICY_DOCUMENT")"
    PHASE_NOOP_PROFILE="$(normalize_phase_noop_profile "$PHASE_NOOP_PROFILE")"
}

print_usage() {
    cat <<'EOF'
Usage: ./ralphie.sh [options]

Core options:
  --engine auto|prime-agent|codex|claude  Select an engine; an explicit choice never falls back
  --prime-provider NAME                  Prime provider (uses its configured default when unset)
  --prime-model ID                       Prime model (uses its configured default when unset)
  --prime-thinking LEVEL                 Prime reasoning: off|minimal|low|medium|high|xhigh|max
  --resume                               Resume from previous persisted session state (default: true)
  --project DIR                          Manage an existing directory (default: script directory)
  --objective TEXT                       Explicit mission seed; authorize the local lifecycle
  --spec FILE                            Exact specification/context file, relative to invocation cwd
  --plan-only                            Complete approved planning without authorizing build
  --accept CMD                           Add one shell-owned project check (repeatable)
  --gate-timeout-seconds N                Hard deadline per project check (default: 900)
  --no-resume                            Force fresh start; ignore persisted state
  --rebootstrap                          Rebuild project bootstrap context (project type/objective/build consent)
  --max-session-cycles N                 Max total inference attempts in this session (0 = unlimited)
  --session-token-budget N                Max session token budget (0 = unlimited)
  --session-token-rate-cents-per-million N  Cost rate in cents per million tokens
  --session-cost-budget-cents N           Max estimated cost in cents; positive cap requires positive rate (0 = unlimited)
  --max-phase-completion-attempts N       Max completion-signal retries per phase (0=unlimited with stagnation guard)
  --phase-wallclock-limit-seconds N       Wall-clock limit per phase attempt (0 = disabled)
  --phase-completion-retry-delay-seconds N Delay in seconds between completion retries
  --phase-completion-retry-verbose bool   Verbose phase completion retry logging (true|false)
  --max-consensus-routing-attempts N      Max adaptive backtracking reroutes per run (0=unlimited)
  --phase-pair-cycle-limit N             Stop after N consecutive routes across the same phase pair (0=disabled)
  --consensus-score-threshold N           Minimum consensus/handoff pass score (0-100)
  --run-agent-max-attempts N              Max inference attempts per agent run (N >= 1)
  --run-agent-retry-delay-seconds N       Delay in seconds between inference retries
  --run-agent-retry-verbose bool          Verbose inference retry logging (true|false)
  --auto-init-git-if-missing bool         Initialize git repository at startup when missing (true|false)
  --auto-commit-on-phase-pass bool        Auto-commit local changes after phase gate pass (true|false, no push)
  --auto-update bool                      Check and replace ralphie.sh from remote before startup (true|false)
  --auto-update-url URL                   Compatible continuation source; default: published sirouk/ralphie main
  --auto-update-allow-insecure bool       Allow non-HTTPS HTTP auto-update URLs (true|false; default false)
  --auto-update-lock-timeout-seconds N    Seconds to wait for another Ralphie self-update to finish
  --auto-engine-preference ENGINE        Preferred AUTO engine (default: prime-agent)
  --engine-output-to-stdout bool          Show or suppress live engine output stream (true|false)
  --auto-repair-markdown-artifacts bool    Auto-sanitize markdown artifacts when gate-blocked (true|false)
  --strict-validation-noop bool           Require worktree mutation for test/lint phases too (true|false)
  --phase-noop-profile strict|balanced|read-only-first|custom
  --phase-noop-policy-plan hard|soft|none  Phase worktree mutation policy for plan
  --phase-noop-policy-build hard|soft|none Phase worktree mutation policy for build
  --phase-noop-policy-test hard|soft|none  Phase worktree mutation policy for test
  --phase-noop-policy-refactor hard|soft|none Phase worktree mutation policy for refactor
  --phase-noop-policy-lint hard|soft|none  Phase worktree mutation policy for lint
  --phase-noop-policy-document hard|soft|none  Phase worktree mutation policy for document
  --require-plan-backlog-clear-before-done bool  Block terminal done while local unchecked backlog tasks remain
  --require-plan-freshness-for-build bool  Remap to plan when configured backlog sources changed after plan
  --backlog-sources PATHS                 Comma-separated markdown backlog files (default: IMPLEMENTATION_PLAN.md)
  --help, -h                             Show this help and exit

Durable steering (choose one; an initialized mission is required):
  --request TEXT                        Queue 1-4096 exact bytes for the active mission
  --request-file FILE                   Queue exact file bytes; relative to invocation directory
  --requests                            List queued, presented and archived requests
  --requests-json                       Emit stable request JSON (schema 1)
  --archive-request ID|all               Archive requests only while the worker is stopped

Requests are repeated in worker, handoff and gate-review prompts. A late request
invalidates stale approval and returns to PLAN. Queued/presented is not completed.
These controls do not launch an engine, initialize a mission or change its settings.
Completed missions reject new requests. Do not combine steering with mission input.

Project settings may also use config.env. Update enablement, source and trust options are operator-only.
Output is plain when redirected, with TERM=dumb, or when NO_COLOR is set (even empty).

Additional runtime env knobs:
  RALPHIE_ENGINE                        Engine selection: auto|prime-agent|codex|claude (prime is an alias)
  RALPHIE_PRIME_ENGINE_CMD              Prime executable path (compatibility key: PRIME_ENGINE_CMD)
  RALPHIE_PRIME_PROVIDER                Prime provider (compatibility key: PRIME_PROVIDER)
  RALPHIE_PRIME_MODEL                   Prime model ID (compatibility key: PRIME_MODEL)
  RALPHIE_PRIME_THINKING_OVERRIDE       Prime reasoning level (compatibility key: PRIME_THINKING_OVERRIDE)
  RALPHIE_ENGINE_OUTPUT_MAX_BYTES       Maximum captured engine output per attempt (default: 16777216)
  RALPHIE_CODEX_ENDPOINT                 Optional OPENAI_BASE_URL override for codex calls
  RALPHIE_CODEX_USE_RESPONSES_SCHEMA     Whether to pass codex --output-schema (true|false)
  RALPHIE_CODEX_RESPONSES_SCHEMA_FILE    JSON schema file path for codex --output-schema
  RALPHIE_CODEX_THINKING_OVERRIDE        Codex reasoning override: none|minimal|low|medium|high|xhigh
  RALPHIE_CLAUDE_ENDPOINT                Optional ANTHROPIC_BASE_URL override for claude calls
  RALPHIE_CLAUDE_THINKING_OVERRIDE       Claude thinking override: none|off|low|medium|high|xhigh
  RALPHIE_ENGINE_IDLE_OUTPUT_TIMEOUT_SECONDS  Silence timeout for streaming engines; Prime/Claude print are buffered
  RALPHIE_AUTO_INIT_GIT_IF_MISSING       Initialize git repo at startup when missing (true|false)
  RALPHIE_AUTO_COMMIT_ON_PHASE_PASS      Auto-commit phase-approved changes (true|false)
  RALPHIE_AUTO_UPDATE                    Enable pre-run single-file self-update (true|false)
  RALPHIE_UPDATE_URL                     Preferred operator-only compatible continuation update source
  RALPHIE_AUTO_UPDATE_URL                Compatibility alias for RALPHIE_UPDATE_URL
  RALPHIE_GATE_TIMEOUT_SECONDS           Hard deadline per project check (default: 900)
  RALPHIE_AUTO_UPDATE_ALLOW_DIRTY        Allow replacing a locally modified ralphie.sh (true|false)
  RALPHIE_AUTO_UPDATE_ALLOW_INSECURE     Allow http:// auto-update URLs (true|false)
  RALPHIE_AUTO_UPDATE_TIMEOUT_SECONDS    Fetch timeout for single-file self-update
  RALPHIE_AUTO_UPDATE_LOCK_TIMEOUT_SECONDS  Seconds to wait for concurrent self-update lock
  RALPHIE_PHASE_MANIFEST_MODE            Worktree manifest mode: light|deep
  RALPHIE_SWARM_MAX_PARALLEL             Max parallel reviewer lanes where supported
  RALPHIE_CONFIDENCE_TARGET              Target confidence score for agent prompts
  RALPHIE_SWARM_CONSENSUS_TIMEOUT        Reviewer timeout in seconds
  RALPHIE_CONFIDENCE_STAGNATION_LIMIT    Repeated unchanged signature limit before stopping
  RALPHIE_CONSENSUS_SCORE_THRESHOLD      Minimum consensus/handoff pass score (0-100)
  RALPHIE_CONSENSUS_CLEAN_GO_SCORE_FLOOR Clean GO floor for non-explicit high thresholds (0-100)
  RALPHIE_AUTO_REPAIR_MARKDOWN_DRY_RUN   Preview markdown repairs without mutating files (true|false)
  RALPHIE_AUTO_REPAIR_MARKDOWN_BACKUP    Save markdown backup+diff artifacts before mutation (true|false)
  RALPHIE_AUTO_REPAIR_MARKDOWN_ONLY_SESSION_CHANGED  Restrict markdown repair targets to this-session changed files
  RALPHIE_MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX  ERE for intentional documented paths in markdown hygiene
  RALPHIE_STARTUP_OPERATIONAL_PROBE      Run startup operational self-checks (true|false)
  RALPHIE_ENGINE_OVERRIDES_BOOTSTRAPPED  First-deploy engine override prompt sentinel (true|false)
  RALPHIE_NOTIFICATIONS_ENABLED          Master notifications toggle (true|false)
  RALPHIE_NOTIFY_TELEGRAM_ENABLED        Enable Telegram notifications (true|false)
  TG_BOT_TOKEN                           Telegram bot token
  TG_CHAT_ID                             Telegram chat/channel id
  RALPHIE_NOTIFY_DISCORD_ENABLED         Enable Discord webhook notifications (true|false)
  RALPHIE_NOTIFY_DISCORD_WEBHOOK_URL     Discord incoming webhook URL
  RALPHIE_NOTIFY_TTS_ENABLED             Enable Chutes TTS voice notifications for Telegram/Discord (true|false)
  RALPHIE_NOTIFY_TTS_STYLE               TTS narration text style (not voice id): standard|friendly|ralph_wiggum
  CHUTES_API_KEY                         Chutes API key for TTS
  RALPHIE_NOTIFY_CHUTES_TTS_URL          Chutes TTS endpoint URL
  RALPHIE_NOTIFY_CHUTES_VOICE            Chutes TTS voice id (example: am_michael)
  RALPHIE_NOTIFY_CHUTES_SPEED            Chutes TTS speed (example: 1.0)
  RALPHIE_NOTIFY_EVENT_DEDUP_WINDOW_SECONDS  Suppress duplicate notification events within N seconds
  RALPHIE_NOTIFY_INCIDENT_REMINDER_MINUTES   Reminder cadence (minutes) for sustained incident series
  RALPHIE_NOTIFICATION_WIZARD_BOOTSTRAPPED  First-deploy notification setup prompt sentinel (true|false)
  RALPHIE_PHASE_WALLCLOCK_LIMIT_SECONDS     Wall-clock limit per phase attempt (seconds, 0=disabled)
  RALPHIE_PHASE_PAIR_CYCLE_LIMIT             Same-pair phase bounce limit (0=disabled)
  RALPHIE_REQUIRE_LINT_BEFORE_DONE          Require at least one passed lint phase before terminal done routing
  RALPHIE_REQUIRE_DOCUMENT_BEFORE_DONE      Require at least one passed document phase before terminal done routing
  RALPHIE_REQUIRE_PLAN_BACKLOG_CLEAR_BEFORE_DONE  Require local configured backlog sources to be clear before terminal done routing
  RALPHIE_REQUIRE_PLAN_FRESHNESS_FOR_BUILD  Require plan refresh when configured backlog sources change before build/done routing
  RALPHIE_BACKLOG_SOURCES                   Comma-separated markdown backlog files evaluated for local unchecked tasks
EOF
}

require_non_negative_int() {
    normalize_integer_setting "$1" 0 || exit 1
}

parse_arg_value() {
    local arg_name="$1"
    local arg_value="$2"
    if [ -z "$arg_value" ] || [[ "$arg_value" == --* ]]; then
        err "Missing value for $arg_name"
        exit 1
    fi
    printf '%s\n' "$arg_value"
}

parse_args() {
    local request_has_run_options=false
    while [ "$#" -gt 0 ]; do
    case "$1" in
        --objective|--spec|--accept|--plan-only|--no-resume|--rebootstrap) request_has_run_options=true ;;
    esac
    case "$1" in
        --help|-h)
            print_usage
            exit 0
            ;;
        --engine)
            parse_arg_value "--engine" "${2:-}" >/dev/null
            ENGINE_SELECTION_REQUESTED="$(normalize_engine_name "$2")" || return 1
            ACTIVE_ENGINE="$ENGINE_SELECTION_REQUESTED"
            ENGINE_SELECTION_EXPLICIT=true
            shift 2
            ;;
        --prime-provider)
            parse_arg_value "--prime-provider" "${2:-}" >/dev/null
            PRIME_PROVIDER="$2"
            PRIME_OPTIONS_EXPLICIT=true
            shift 2
            ;;
        --prime-model)
            parse_arg_value "--prime-model" "${2:-}" >/dev/null
            PRIME_MODEL="$2"
            PRIME_OPTIONS_EXPLICIT=true
            shift 2
            ;;
        --prime-thinking)
            parse_arg_value "--prime-thinking" "${2:-}" >/dev/null
            PRIME_THINKING_OVERRIDE="$2"
            PRIME_OPTIONS_EXPLICIT=true
            shift 2
            ;;
            --resume)
                RESUME_REQUESTED=true
                shift
                ;;
        --project)
            parse_arg_value "--project" "${2:-}" >/dev/null
            shift 2
            ;;
        --request|--request-file|--archive-request)
            [ -z "$REQUEST_COMMAND" ] || { err 'Choose exactly one durable steering control.'; return 1; }
            [ "$#" -ge 2 ] && [ -n "$2" ] || { err "Missing value for $1"; return 1; }
            case "$1" in
                --request) REQUEST_COMMAND=publish-text; REQUEST_TEXT="$2" ;;
                --request-file) REQUEST_COMMAND=publish-file; REQUEST_FILE="$2" ;;
                --archive-request) REQUEST_COMMAND=archive; REQUEST_ARCHIVE_ID="$2" ;;
            esac
            NO_TERMINAL_INPUT=true
            shift 2
            ;;
        --requests|--requests-json)
            [ -z "$REQUEST_COMMAND" ] || { err 'Choose exactly one durable steering control.'; return 1; }
            case "$1" in --requests) REQUEST_COMMAND=list ;; --requests-json) REQUEST_COMMAND=json ;; esac
            NO_TERMINAL_INPUT=true
            shift
            ;;
        --objective)
            parse_arg_value "--objective" "${2:-}" >/dev/null
            OBJECTIVE_TEXT="${2:-}"
            NO_TERMINAL_INPUT=true
            shift 2
            ;;
        --spec)
            parse_arg_value "--spec" "${2:-}" >/dev/null
            SPEC_FILE="${2:-}"
            NO_TERMINAL_INPUT=true
            shift 2
            ;;
        --plan-only)
            PLAN_ONLY=true
            NO_TERMINAL_INPUT=true
            shift
            ;;
        --accept)
            local accept_command
            parse_arg_value "--accept" "${2:-}" >/dev/null
            accept_command="${2:-}"
            case "$accept_command" in *$'\n'*|*$'\r'*) err '--accept requires one physical command line'; exit 1;; esac
            ACCEPT_COMMANDS+=("$accept_command")
            shift 2
            ;;
        --gate-timeout-seconds)
            GATE_TIMEOUT_SECONDS="$(parse_arg_value "--gate-timeout-seconds" "${2:-}")"
            require_non_negative_int "GATE_TIMEOUT_SECONDS" "$GATE_TIMEOUT_SECONDS"
            [ "$GATE_TIMEOUT_SECONDS" -gt 0 ] || { err 'Gate timeout must be positive'; exit 1; }
            shift 2
            ;;
        --no-resume)
            RESUME_REQUESTED=false
            shift
            ;;
        --rebootstrap)
            REBOOTSTRAP_REQUESTED=true
            shift
            ;;
        --max-session-cycles)
            MAX_SESSION_CYCLES="$(parse_arg_value "--max-session-cycles" "${2:-}")"
                require_non_negative_int "MAX_SESSION_CYCLES" "$MAX_SESSION_CYCLES"
                shift 2
                ;;
            --session-token-budget)
                SESSION_TOKEN_BUDGET="$(parse_arg_value "--session-token-budget" "${2:-}")"
                require_non_negative_int "SESSION_TOKEN_BUDGET" "$SESSION_TOKEN_BUDGET"
                shift 2
                ;;
            --session-token-rate-cents-per-million)
                SESSION_TOKEN_RATE_CENTS_PER_MILLION="$(parse_arg_value "--session-token-rate-cents-per-million" "${2:-}")"
                require_non_negative_int "SESSION_TOKEN_RATE_CENTS_PER_MILLION" "$SESSION_TOKEN_RATE_CENTS_PER_MILLION"
                shift 2
                ;;
            --session-cost-budget-cents)
                SESSION_COST_BUDGET_CENTS="$(parse_arg_value "--session-cost-budget-cents" "${2:-}")"
                require_non_negative_int "SESSION_COST_BUDGET_CENTS" "$SESSION_COST_BUDGET_CENTS"
                shift 2
                ;;
        --max-phase-completion-attempts)
            PHASE_COMPLETION_MAX_ATTEMPTS="$(parse_arg_value "--max-phase-completion-attempts" "${2:-}")"
            require_non_negative_int "PHASE_COMPLETION_MAX_ATTEMPTS" "$PHASE_COMPLETION_MAX_ATTEMPTS"
            shift 2
            ;;
        --phase-wallclock-limit-seconds)
            PHASE_WALLCLOCK_LIMIT_SECONDS="$(parse_arg_value "--phase-wallclock-limit-seconds" "${2:-}")"
            require_non_negative_int "PHASE_WALLCLOCK_LIMIT_SECONDS" "$PHASE_WALLCLOCK_LIMIT_SECONDS"
            shift 2
            ;;
        --phase-completion-retry-delay-seconds)
            PHASE_COMPLETION_RETRY_DELAY_SECONDS="$(parse_arg_value "--phase-completion-retry-delay-seconds" "${2:-}")"
            require_non_negative_int "PHASE_COMPLETION_RETRY_DELAY_SECONDS" "$PHASE_COMPLETION_RETRY_DELAY_SECONDS"
            shift 2
            ;;
            --phase-completion-retry-verbose)
                PHASE_COMPLETION_RETRY_VERBOSE="$(parse_arg_value "--phase-completion-retry-verbose" "${2:-}")"
                if ! is_bool_like "$PHASE_COMPLETION_RETRY_VERBOSE"; then
                    err "Invalid boolean value for --phase-completion-retry-verbose: $PHASE_COMPLETION_RETRY_VERBOSE"
                    exit 1
                fi
                shift 2
                ;;
            --max-consensus-routing-attempts)
                MAX_CONSENSUS_ROUTING_ATTEMPTS="$(parse_arg_value "--max-consensus-routing-attempts" "${2:-}")"
                require_non_negative_int "MAX_CONSENSUS_ROUTING_ATTEMPTS" "$MAX_CONSENSUS_ROUTING_ATTEMPTS"
                shift 2
                ;;
            --phase-pair-cycle-limit)
                PHASE_PAIR_CYCLE_LIMIT="$(parse_arg_value "--phase-pair-cycle-limit" "${2:-}")"
                require_non_negative_int "PHASE_PAIR_CYCLE_LIMIT" "$PHASE_PAIR_CYCLE_LIMIT"
                shift 2
                ;;
            --consensus-score-threshold)
                CONSENSUS_SCORE_THRESHOLD="$(parse_arg_value "--consensus-score-threshold" "${2:-}")"
                CONSENSUS_SCORE_THRESHOLD_EXPLICIT=true
                require_non_negative_int "CONSENSUS_SCORE_THRESHOLD" "$CONSENSUS_SCORE_THRESHOLD"
                if [ "$CONSENSUS_SCORE_THRESHOLD" -gt 100 ]; then
                    err "Invalid value for --consensus-score-threshold: $CONSENSUS_SCORE_THRESHOLD (expected 0-100)"
                    exit 1
                fi
                shift 2
                ;;
            --run-agent-max-attempts)
                RUN_AGENT_MAX_ATTEMPTS="$(parse_arg_value "--run-agent-max-attempts" "${2:-}")"
                require_non_negative_int "RUN_AGENT_MAX_ATTEMPTS" "$RUN_AGENT_MAX_ATTEMPTS"
                shift 2
                ;;
            --run-agent-retry-delay-seconds)
                RUN_AGENT_RETRY_DELAY_SECONDS="$(parse_arg_value "--run-agent-retry-delay-seconds" "${2:-}")"
                require_non_negative_int "RUN_AGENT_RETRY_DELAY_SECONDS" "$RUN_AGENT_RETRY_DELAY_SECONDS"
                shift 2
                ;;
            --run-agent-retry-verbose)
                RUN_AGENT_RETRY_VERBOSE="$(parse_arg_value "--run-agent-retry-verbose" "${2:-}")"
                if ! is_bool_like "$RUN_AGENT_RETRY_VERBOSE"; then
                    err "Invalid boolean value for --run-agent-retry-verbose: $RUN_AGENT_RETRY_VERBOSE"
                    exit 1
                fi
                shift 2
                ;;
            --auto-init-git-if-missing)
                AUTO_INIT_GIT_IF_MISSING="$(parse_arg_value "--auto-init-git-if-missing" "${2:-}")"
                if ! is_bool_like "$AUTO_INIT_GIT_IF_MISSING"; then
                    err "Invalid boolean value for --auto-init-git-if-missing: $AUTO_INIT_GIT_IF_MISSING"
                    exit 1
                fi
                shift 2
                ;;
            --auto-commit-on-phase-pass)
                AUTO_COMMIT_ON_PHASE_PASS="$(parse_arg_value "--auto-commit-on-phase-pass" "${2:-}")"
                if ! is_bool_like "$AUTO_COMMIT_ON_PHASE_PASS"; then
                    err "Invalid boolean value for --auto-commit-on-phase-pass: $AUTO_COMMIT_ON_PHASE_PASS"
                    exit 1
                fi
                shift 2
                ;;
            --auto-update)
                AUTO_UPDATE="$(parse_arg_value "--auto-update" "${2:-}")"
                if ! is_bool_like "$AUTO_UPDATE"; then
                    err "Invalid boolean value for --auto-update: $AUTO_UPDATE"
                    exit 1
                fi
                shift 2
                ;;
            --auto-update-url)
                AUTO_UPDATE_URL="$(parse_arg_value "--auto-update-url" "${2:-}")"
                if [ -z "$(sanitize_text_for_log "$AUTO_UPDATE_URL")" ]; then
                    err "Invalid empty value for --auto-update-url"
                    exit 1
                fi
                shift 2
                ;;
            --auto-update-allow-insecure)
                AUTO_UPDATE_ALLOW_INSECURE="$(parse_arg_value "--auto-update-allow-insecure" "${2:-}")"
                if ! is_bool_like "$AUTO_UPDATE_ALLOW_INSECURE"; then
                    err "Invalid boolean value for --auto-update-allow-insecure: $AUTO_UPDATE_ALLOW_INSECURE"
                    exit 1
                fi
                shift 2
                ;;
            --auto-update-lock-timeout-seconds)
                AUTO_UPDATE_LOCK_TIMEOUT_SECONDS="$(parse_arg_value "--auto-update-lock-timeout-seconds" "${2:-}")"
                require_non_negative_int "AUTO_UPDATE_LOCK_TIMEOUT_SECONDS" "$AUTO_UPDATE_LOCK_TIMEOUT_SECONDS"
                shift 2
                ;;
            --auto-engine-preference)
                parse_arg_value "--auto-engine-preference" "${2:-}" >/dev/null
                AUTO_ENGINE_PREFERENCE="$(normalize_engine_name "$2")" || return 1
                ENGINE_SELECTION_EXPLICIT=true
                case "$AUTO_ENGINE_PREFERENCE" in
                    prime-agent|codex|claude) ;;
                    *)
                        err "Invalid value for --auto-engine-preference: $AUTO_ENGINE_PREFERENCE (expected prime-agent|codex|claude)"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --engine-output-to-stdout)
                ENGINE_OUTPUT_TO_STDOUT="$(parse_arg_value "--engine-output-to-stdout" "${2:-}")"
                if ! is_bool_like "$ENGINE_OUTPUT_TO_STDOUT"; then
                    err "Invalid boolean value for --engine-output-to-stdout: $ENGINE_OUTPUT_TO_STDOUT"
                    exit 1
                fi
                ENGINE_OUTPUT_TO_STDOUT_EXPLICIT="true"
                ENGINE_OUTPUT_TO_STDOUT_OVERRIDE="$ENGINE_OUTPUT_TO_STDOUT"
                shift 2
                ;;
            --auto-repair-markdown-artifacts)
                AUTO_REPAIR_MARKDOWN_ARTIFACTS="$(parse_arg_value "--auto-repair-markdown-artifacts" "${2:-}")"
                if ! is_bool_like "$AUTO_REPAIR_MARKDOWN_ARTIFACTS"; then
                    err "Invalid boolean value for --auto-repair-markdown-artifacts: $AUTO_REPAIR_MARKDOWN_ARTIFACTS"
                    exit 1
                fi
                shift 2
                ;;
            --strict-validation-noop)
                STRICT_VALIDATION_NOOP="$(parse_arg_value "--strict-validation-noop" "${2:-}")"
                if ! is_bool_like "$STRICT_VALIDATION_NOOP"; then
                    err "Invalid boolean value for --strict-validation-noop: $STRICT_VALIDATION_NOOP"
                    exit 1
                fi
                shift 2
                ;;
            --phase-noop-profile)
                local profile_candidate
                profile_candidate="$(to_lower "$(parse_arg_value "--phase-noop-profile" "${2:-}")")"
                if ! is_phase_noop_profile "$profile_candidate"; then
                    err "Invalid phase noop profile: $profile_candidate"
                    exit 1
                fi
                PHASE_NOOP_PROFILE="$(normalize_phase_noop_profile "$profile_candidate")"
                shift 2
                ;;
            --phase-noop-policy-plan)
                PHASE_NOOP_POLICY_PLAN="$(to_lower "$(parse_arg_value "--phase-noop-policy-plan" "${2:-}")")"
                if ! is_phase_noop_policy "$PHASE_NOOP_POLICY_PLAN"; then
                    err "Invalid policy for --phase-noop-policy-plan: $PHASE_NOOP_POLICY_PLAN"
                    exit 1
                fi
                PHASE_NOOP_POLICY_PLAN_EXPLICIT=true
                shift 2
                ;;
            --phase-noop-policy-build)
                PHASE_NOOP_POLICY_BUILD="$(to_lower "$(parse_arg_value "--phase-noop-policy-build" "${2:-}")")"
                if ! is_phase_noop_policy "$PHASE_NOOP_POLICY_BUILD"; then
                    err "Invalid policy for --phase-noop-policy-build: $PHASE_NOOP_POLICY_BUILD"
                    exit 1
                fi
                PHASE_NOOP_POLICY_BUILD_EXPLICIT=true
                shift 2
                ;;
            --phase-noop-policy-test)
                PHASE_NOOP_POLICY_TEST="$(to_lower "$(parse_arg_value "--phase-noop-policy-test" "${2:-}")")"
                if ! is_phase_noop_policy "$PHASE_NOOP_POLICY_TEST"; then
                    err "Invalid policy for --phase-noop-policy-test: $PHASE_NOOP_POLICY_TEST"
                    exit 1
                fi
                PHASE_NOOP_POLICY_TEST_EXPLICIT=true
                shift 2
                ;;
            --phase-noop-policy-refactor)
                PHASE_NOOP_POLICY_REFACTOR="$(to_lower "$(parse_arg_value "--phase-noop-policy-refactor" "${2:-}")")"
                if ! is_phase_noop_policy "$PHASE_NOOP_POLICY_REFACTOR"; then
                    err "Invalid policy for --phase-noop-policy-refactor: $PHASE_NOOP_POLICY_REFACTOR"
                    exit 1
                fi
                PHASE_NOOP_POLICY_REFACTOR_EXPLICIT=true
                shift 2
                ;;
            --phase-noop-policy-lint)
                PHASE_NOOP_POLICY_LINT="$(to_lower "$(parse_arg_value "--phase-noop-policy-lint" "${2:-}")")"
                if ! is_phase_noop_policy "$PHASE_NOOP_POLICY_LINT"; then
                    err "Invalid policy for --phase-noop-policy-lint: $PHASE_NOOP_POLICY_LINT"
                    exit 1
                fi
                PHASE_NOOP_POLICY_LINT_EXPLICIT=true
                shift 2
                ;;
            --phase-noop-policy-document)
                PHASE_NOOP_POLICY_DOCUMENT="$(to_lower "$(parse_arg_value "--phase-noop-policy-document" "${2:-}")")"
                if ! is_phase_noop_policy "$PHASE_NOOP_POLICY_DOCUMENT"; then
                    err "Invalid policy for --phase-noop-policy-document: $PHASE_NOOP_POLICY_DOCUMENT"
                    exit 1
                fi
                PHASE_NOOP_POLICY_DOCUMENT_EXPLICIT=true
                shift 2
                ;;
            --require-plan-backlog-clear-before-done)
                REQUIRE_PLAN_BACKLOG_CLEAR_BEFORE_DONE="$(parse_arg_value "--require-plan-backlog-clear-before-done" "${2:-}")"
                if ! is_bool_like "$REQUIRE_PLAN_BACKLOG_CLEAR_BEFORE_DONE"; then
                    err "Invalid boolean value for --require-plan-backlog-clear-before-done: $REQUIRE_PLAN_BACKLOG_CLEAR_BEFORE_DONE"
                    exit 1
                fi
                shift 2
                ;;
            --require-plan-freshness-for-build)
                REQUIRE_PLAN_FRESHNESS_FOR_BUILD="$(parse_arg_value "--require-plan-freshness-for-build" "${2:-}")"
                if ! is_bool_like "$REQUIRE_PLAN_FRESHNESS_FOR_BUILD"; then
                    err "Invalid boolean value for --require-plan-freshness-for-build: $REQUIRE_PLAN_FRESHNESS_FOR_BUILD"
                    exit 1
                fi
                shift 2
                ;;
            --backlog-sources)
                BACKLOG_SOURCES="$(parse_arg_value "--backlog-sources" "${2:-}")"
                shift 2
                ;;
            --max-iterations)
                MAX_ITERATIONS="$(parse_arg_value "--max-iterations" "${2:-}")"
                require_non_negative_int "MAX_ITERATIONS" "$MAX_ITERATIONS"
                shift 2
                ;;
            *)
                err "Unknown argument: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    if [ -n "$REQUEST_COMMAND" ] && is_true "$request_has_run_options"; then
        err 'Durable steering controls cannot be combined with mission input or fresh-start options.'
        return 1
    fi
    return 0
}

# Sideband controls use their own short transaction, never the worker's
# cleanup/state-saving traps. Mutation holds worker admission so owner
# capability/stopped checks cannot race a different worker starting.
request_control() (
    local request_control_status=0 request_worker_claim_token='' request_body_tmp=''
    local request_input='' request_holder_pid='' request_holder_token='' request_lock_dir="${LOCK_FILE}.d"
    trap '
        request_control_status=$?
        if [ -n "$REQUEST_LOCK_TOKEN" ]; then request_unlock || request_control_status=1; fi
        if [ -n "$request_worker_claim_token" ]; then
            release_lock_claim "${LOCK_FILE}.claim" "$request_worker_claim_token" || request_control_status=1
        fi
        if [ -n "$request_body_tmp" ]; then rm -f "$request_body_tmp" || request_control_status=1; fi
        exit "$request_control_status"
    ' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP

    if [ ! -d "$CONFIG_DIR" ] || [ -L "$CONFIG_DIR" ] || [ ! -f "$STATE_FILE" ]; then
        err 'Durable steering requires an initialized saved mission; start Ralphie with an objective or specification first.'
        return 1
    fi
    validate_runtime_directory "$CONFIG_DIR" && ensure_runtime_file "$STATE_FILE" || return 1
    if [ "$REQUEST_COMMAND" = archive ] || [ "$REQUEST_COMMAND" = publish-text ] || [ "$REQUEST_COMMAND" = publish-file ]; then
        acquire_lock_claim "${LOCK_FILE}.claim" 2 || return 1
        request_worker_claim_token="$LOCK_CLAIM_TOKEN"
        validate_runtime_directory "$request_lock_dir" && ensure_runtime_file "$LOCK_FILE" || return 1
        if [ -d "$request_lock_dir" ] || [ -e "$LOCK_FILE" ]; then
            ensure_runtime_file "$request_lock_dir/owner" || return 1
            if [ ! -d "$request_lock_dir" ] || [ ! -f "$request_lock_dir/owner" ] || [ ! -f "$LOCK_FILE" ]; then
                err 'Worker lock ownership is incomplete; inspect it with all launchers stopped before changing requests.'
                return 1
            fi
            request_holder_pid="$(sed -n 's/^pid=//p' "$request_lock_dir/owner")"
            request_holder_token="$(sed -n 's/^token=//p' "$request_lock_dir/owner")"
            if ! is_number "$request_holder_pid" || [ "$request_holder_pid" -le 1 ] \
                || [ -z "$request_holder_token" ] \
                || [ "$request_holder_pid" != "$(head -n 1 "$LOCK_FILE")" ] \
                || ! grep -Fxq -- "token=$request_holder_token" "$LOCK_FILE"; then
                err 'Worker lock ownership cannot be verified; inspect it with all launchers stopped before changing requests.'
                return 1
            fi
            if kill -0 "$request_holder_pid" 2>/dev/null; then
                if [ "$REQUEST_COMMAND" = archive ]; then
                    err 'Requests can be archived only after the worker has stopped.'
                    return 1
                fi
                if ! grep -Fxq -- 'request_consumer=1' "$request_lock_dir/owner"; then
                    err 'The live worker does not support durable requests. Stop it, then resume with this Ralphie version before submitting instructions.'
                    return 1
                fi
            fi
        fi
    fi
    # Never wait for a worker's queue claim while holding its admission claim:
    # cleanup publishes state under the queue claim before releasing the worker.
    if [ -n "$request_worker_claim_token" ]; then
        request_lock 0 || return 1
    else
        request_lock || return 1
    fi
    if ! load_state || [ -z "$SESSION_ID" ] || ! request_validate_mission; then
        err 'Saved mission or request binding is invalid; no engine was invoked.'
        return 1
    fi
    case "$REQUEST_COMMAND" in
        publish-text|publish-file)
            if [ "$CURRENT_PHASE" = done ]; then
                err 'The saved mission is completed; start a reviewed new mission before submitting another request.'
                return 1
            fi
            if [ "$REQUEST_COMMAND" = publish-text ]; then
                request_body_tmp="$(mktemp "${TMPDIR:-/tmp}/ralphie-request.XXXXXX")" || return 1
                printf '%s' "$REQUEST_TEXT" > "$request_body_tmp" || return 1
                request_input="$request_body_tmp"
            else
                request_input="$REQUEST_FILE"
                case "$request_input" in /*) ;; *) request_input="$INVOCATION_DIR/$request_input" ;; esac
            fi
            request_publish_file "$request_input" || return 1
            ;;
        list) request_render_list human || return 1 ;;
        json) request_render_list json || return 1 ;;
        archive) request_archive "$REQUEST_ARCHIVE_ID" || return 1 ;;
        *) err 'Unknown durable steering control.'; return 1 ;;
    esac
    return 0
)

# Global Registry for Background Processes (for atomic cleanup)
declare -a RALPHIE_BG_PIDS=()
INTERRUPT_MENU_ACTIVE="false"
MARKDOWN_ARTIFACTS_CLEANED_LIST=""
MARKDOWN_ARTIFACTS_PREVIEW_LIST=""
MARKDOWN_ARTIFACTS_BACKUP_LIST=""
TIMEOUT_BINARY_WARNING_EMITTED="false"
LOCK_ACQUIRED="false"
LOCK_OWNER_TOKEN=""
RALPHIE_CLEANUP_STATE_ENABLED="false"
RALPHIE_CLEANUP_IN_PROGRESS="false"
RALPHIE_TRAPS_INSTALLED="false"
AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE=""

# Configuration defaults
DEFAULT_ENGINE="auto"
# Resolve only engines needed by readiness, after --help and explicit choices.
DEFAULT_PRIME_CMD="prime-agent"
DEFAULT_CODEX_CMD="codex"
DEFAULT_CLAUDE_CMD="claude"
DEFAULT_AUTO_ENGINE_PREFERENCE="prime-agent"  # configured preference, then other available engines
DEFAULT_CODEX_ENDPOINT=""                     # empty = do not override OPENAI_BASE_URL
DEFAULT_CODEX_USE_RESPONSES_SCHEMA="false"    # false = skip codex --output-schema
DEFAULT_CODEX_RESPONSES_SCHEMA_FILE=""        # path passed to codex --output-schema when enabled
DEFAULT_CODEX_THINKING_OVERRIDE="high"        # none|minimal|low|medium|high|xhigh
DEFAULT_CLAUDE_ENDPOINT=""                    # empty = do not override ANTHROPIC_BASE_URL
DEFAULT_CLAUDE_THINKING_OVERRIDE="high"       # none|off|low|medium|high|xhigh
DEFAULT_AUTO_INIT_GIT_IF_MISSING="true"       # initialize git repo at startup when missing
DEFAULT_AUTO_COMMIT_ON_PHASE_PASS="true"      # commit phase-approved local changes (no push)
DEFAULT_YOLO="true"
DEFAULT_AUTO_UPDATE="false"                  # self-update is an explicit operator action
DEFAULT_AUTO_UPDATE_URL="https://raw.githubusercontent.com/sirouk/ralphie/main/ralphie.sh"
DEFAULT_AUTO_UPDATE_ALLOW_DIRTY="false"      # refuse to overwrite local ralphie.sh edits by default
DEFAULT_AUTO_UPDATE_ALLOW_INSECURE="false"   # refuse plaintext HTTP update URLs by default
DEFAULT_RALPHIE_QUALITY_LEVEL="standard"    # minimal|standard|high
DEFAULT_RUN_AGENT_RETRY_VERBOSE="true"
DEFAULT_RESUME_REQUESTED="true"
DEFAULT_REBOOTSTRAP_REQUESTED="false"
DEFAULT_STRICT_VALIDATION_NOOP="false"
DEFAULT_PHASE_COMPLETION_RETRY_VERBOSE="true"
DEFAULT_ENGINE_OUTPUT_TO_STDOUT="true"
ENGINE_OUTPUT_TO_STDOUT_EXPLICIT="false"
ENGINE_OUTPUT_TO_STDOUT_OVERRIDE=""
DEFAULT_PHASE_NOOP_POLICY_PLAN="none"
DEFAULT_PHASE_NOOP_POLICY_BUILD="hard"
DEFAULT_PHASE_NOOP_POLICY_TEST="soft"
DEFAULT_PHASE_NOOP_POLICY_REFACTOR="hard"
DEFAULT_PHASE_NOOP_POLICY_LINT="soft"
DEFAULT_PHASE_NOOP_POLICY_DOCUMENT="soft"
DEFAULT_PHASE_NOOP_PROFILE="balanced"
PHASE_NOOP_POLICY_PLAN_EXPLICIT=false
PHASE_NOOP_POLICY_BUILD_EXPLICIT=false
PHASE_NOOP_POLICY_TEST_EXPLICIT=false
PHASE_NOOP_POLICY_REFACTOR_EXPLICIT=false
PHASE_NOOP_POLICY_LINT_EXPLICIT=false
PHASE_NOOP_POLICY_DOCUMENT_EXPLICIT=false
CONSENSUS_SCORE_THRESHOLD_EXPLICIT=false
DEFAULT_AUTO_REPAIR_MARKDOWN_ARTIFACTS="true" # sanitize common local/engine leaks when gate blocked
DEFAULT_AUTO_REPAIR_MARKDOWN_DRY_RUN="false"  # preview-only remediation mode (no file mutations)
DEFAULT_AUTO_REPAIR_MARKDOWN_BACKUP="true"    # write backup+diff artifacts before markdown mutation
DEFAULT_AUTO_REPAIR_MARKDOWN_ONLY_SESSION_CHANGED="false" # optional scope limiter for markdown remediation
DEFAULT_MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX="" # optional ERE for intentional documented paths
DEFAULT_PHASE_MANIFEST_MODE="light"           # light|deep manifest capture strategy
DEFAULT_REQUIRE_LINT_BEFORE_DONE="true"          # terminal guard: require lint pass before done
DEFAULT_REQUIRE_DOCUMENT_BEFORE_DONE="true"      # terminal guard: require document pass before done
DEFAULT_REQUIRE_PLAN_BACKLOG_CLEAR_BEFORE_DONE="true" # terminal guard: block done while local unchecked backlog tasks remain
DEFAULT_REQUIRE_PLAN_FRESHNESS_FOR_BUILD="true"  # route guard: stale plan vs backlog sources must remap to plan
DEFAULT_BACKLOG_SOURCES="IMPLEMENTATION_PLAN.md" # comma-separated markdown backlog sources
DEFAULT_ENGINE_HEALTH_RETRY_VERBOSE="true"        # log retry activity at startup/loop boundaries
DEFAULT_STARTUP_OPERATIONAL_PROBE="true"          # run startup self-checks for runtime confidence
DEFAULT_ENGINE_OVERRIDES_BOOTSTRAPPED="false"     # first-deploy interactive engine override prompt sentinel
DEFAULT_NOTIFICATIONS_ENABLED="false"              # master notifications toggle
DEFAULT_NOTIFY_TELEGRAM_ENABLED="false"            # send status messages to Telegram bot/chat
DEFAULT_NOTIFY_DISCORD_ENABLED="false"             # send status messages to Discord webhook
DEFAULT_NOTIFY_TTS_ENABLED="false"                 # enable Chutes TTS voice notifications via Telegram/Discord
DEFAULT_NOTIFY_TTS_STYLE="ralph_wiggum"            # narration text style (ralph alias supported)
DEFAULT_NOTIFY_CHUTES_TTS_URL="https://chutes-kokoro.chutes.ai/speak"
DEFAULT_NOTIFY_CHUTES_VOICE="am_puck"
DEFAULT_NOTIFY_CHUTES_SPEED="1.24"
DEFAULT_NOTIFICATION_WIZARD_BOOTSTRAPPED="false"  # first-deploy notification setup prompt sentinel

# Mission limits, budgets, watchdogs, and quality thresholds.
# Defaults favor patient unattended work. A value of 0 means unlimited/disabled
# only where noted; loop and stagnation guards stay finite by default.
DEFAULT_COMMAND_TIMEOUT_SECONDS=0                  # 0 disables whole-command timeout
DEFAULT_MAX_ITERATIONS=0                           # 0 means infinite
DEFAULT_MAX_SESSION_CYCLES=0                       # 0 means infinite across all phases
DEFAULT_SESSION_TOKEN_BUDGET=0                     # 0 means unlimited
DEFAULT_SESSION_TOKEN_RATE_CENTS_PER_MILLION=0     # 0 means no cost accounting
DEFAULT_SESSION_COST_BUDGET_CENTS=0                # 0 means unlimited
DEFAULT_PHASE_WALLCLOCK_LIMIT_SECONDS=0            # 0 disables phase wall-clock limit
DEFAULT_AUTO_UPDATE_TIMEOUT_SECONDS=45             # network timeout for single-file self-update fetch
DEFAULT_AUTO_UPDATE_LOCK_TIMEOUT_SECONDS=60        # wait for concurrent startup self-update
DEFAULT_RUN_AGENT_MAX_ATTEMPTS=6                   # transient engine hiccup retries per agent run
DEFAULT_RUN_AGENT_RETRY_DELAY_SECONDS=8            # exponential backoff base for inference retries
DEFAULT_ENGINE_IDLE_OUTPUT_TIMEOUT_SECONDS=900     # recycle hung engine runs after prolonged no-output stalls (0=disabled)
DEFAULT_ENGINE_OUTPUT_MAX_BYTES=16777216           # bound each engine's captured stdout/stderr
DEFAULT_PHASE_COMPLETION_MAX_ATTEMPTS=5            # phase-local completion attempts before backtracking/blocking
DEFAULT_PHASE_COMPLETION_RETRY_DELAY_SECONDS=10
DEFAULT_MAX_CONSENSUS_ROUTING_ATTEMPTS=0           # 0 means unlimited adaptive backtracking reroutes
DEFAULT_PHASE_PAIR_CYCLE_LIMIT=10                  # stop repeated A<->B phase bounces after this many consecutive crossings
DEFAULT_CONFIDENCE_STAGNATION_LIMIT=10             # stop unchanged retry/routing signatures after this many repeats
DEFAULT_SWARM_MAX_PARALLEL=2
DEFAULT_CONFIDENCE_TARGET=85
DEFAULT_SWARM_CONSENSUS_TIMEOUT=600                # reviewer timeout; explicit CI presets can lower it
DEFAULT_CONSENSUS_SCORE_THRESHOLD=70               # minimum avg score for consensus/handoff to pass
DEFAULT_CONSENSUS_CLEAN_GO_SCORE_FLOOR=80          # non-explicit high thresholds may relax to this on clean unanimous GO
DEFAULT_ENGINE_HEALTH_MAX_ATTEMPTS=6               # startup/loop readiness attempts before refusing to proceed
DEFAULT_ENGINE_HEALTH_RETRY_DELAY_SECONDS=5        # exponential backoff base
DEFAULT_ENGINE_SMOKE_TEST_TIMEOUT=20               # seconds to wait for smoke-test canary response
DEFAULT_NOTIFY_EVENT_DEDUP_WINDOW_SECONDS=90       # suppress duplicate notification events in a short window
DEFAULT_NOTIFY_INCIDENT_REMINDER_MINUTES=10        # reminder cadence for ongoing incident series
# Preset hints (not enforced):
#   CI_SAFE: PHASE_COMPLETION_MAX_ATTEMPTS=2, PHASE_WALLCLOCK_LIMIT_SECONDS=900, COMMAND_TIMEOUT_SECONDS=600, SWARM_CONSENSUS_TIMEOUT=240
#   IMPATIENT: PHASE_COMPLETION_MAX_ATTEMPTS=1, PHASE_WALLCLOCK_LIMIT_SECONDS=300, COMMAND_TIMEOUT_SECONDS=300, PHASE_COMPLETION_RETRY_DELAY_SECONDS=5
#   LEGACY_LENIENT: PHASE_COMPLETION_MAX_ATTEMPTS=3, PHASE_WALLCLOCK_LIMIT_SECONDS=0, COMMAND_TIMEOUT_SECONDS=0, SWARM_CONSENSUS_TIMEOUT=600

# Load configuration from environment or file.
COMMAND_TIMEOUT_SECONDS="${COMMAND_TIMEOUT_SECONDS:-$DEFAULT_COMMAND_TIMEOUT_SECONDS}"
MAX_ITERATIONS="${MAX_ITERATIONS:-$DEFAULT_MAX_ITERATIONS}"
MAX_SESSION_CYCLES="${MAX_SESSION_CYCLES:-$DEFAULT_MAX_SESSION_CYCLES}"
YOLO="${YOLO:-$DEFAULT_YOLO}"
AUTO_UPDATE="${AUTO_UPDATE:-$DEFAULT_AUTO_UPDATE}"
AUTO_UPDATE_URL="${AUTO_UPDATE_URL:-$DEFAULT_AUTO_UPDATE_URL}"
AUTO_UPDATE_ALLOW_DIRTY="${AUTO_UPDATE_ALLOW_DIRTY:-$DEFAULT_AUTO_UPDATE_ALLOW_DIRTY}"
AUTO_UPDATE_ALLOW_INSECURE="${AUTO_UPDATE_ALLOW_INSECURE:-$DEFAULT_AUTO_UPDATE_ALLOW_INSECURE}"
AUTO_UPDATE_TIMEOUT_SECONDS="${AUTO_UPDATE_TIMEOUT_SECONDS:-$DEFAULT_AUTO_UPDATE_TIMEOUT_SECONDS}"
AUTO_UPDATE_LOCK_TIMEOUT_SECONDS="${AUTO_UPDATE_LOCK_TIMEOUT_SECONDS:-$DEFAULT_AUTO_UPDATE_LOCK_TIMEOUT_SECONDS}"
PHASE_WALLCLOCK_LIMIT_SECONDS="${PHASE_WALLCLOCK_LIMIT_SECONDS:-$DEFAULT_PHASE_WALLCLOCK_LIMIT_SECONDS}"
RALPHIE_QUALITY_LEVEL="${RALPHIE_QUALITY_LEVEL:-$DEFAULT_RALPHIE_QUALITY_LEVEL}"
SWARM_MAX_PARALLEL="${SWARM_MAX_PARALLEL:-$DEFAULT_SWARM_MAX_PARALLEL}"
CONFIDENCE_TARGET="${CONFIDENCE_TARGET:-$DEFAULT_CONFIDENCE_TARGET}"
CONFIDENCE_STAGNATION_LIMIT="${CONFIDENCE_STAGNATION_LIMIT:-$DEFAULT_CONFIDENCE_STAGNATION_LIMIT}"
AUTO_PLAN_BACKFILL_ON_IDLE_BUILD="${AUTO_PLAN_BACKFILL_ON_IDLE_BUILD:-true}"
AUTO_ENGINE_PREFERENCE="${AUTO_ENGINE_PREFERENCE:-$DEFAULT_AUTO_ENGINE_PREFERENCE}"
AUTO_INIT_GIT_IF_MISSING="${AUTO_INIT_GIT_IF_MISSING:-$DEFAULT_AUTO_INIT_GIT_IF_MISSING}"
AUTO_COMMIT_ON_PHASE_PASS="${AUTO_COMMIT_ON_PHASE_PASS:-$DEFAULT_AUTO_COMMIT_ON_PHASE_PASS}"
CODEX_ENDPOINT="${CODEX_ENDPOINT:-$DEFAULT_CODEX_ENDPOINT}"
CODEX_USE_RESPONSES_SCHEMA="${CODEX_USE_RESPONSES_SCHEMA:-$DEFAULT_CODEX_USE_RESPONSES_SCHEMA}"
CODEX_RESPONSES_SCHEMA_FILE="${CODEX_RESPONSES_SCHEMA_FILE:-$DEFAULT_CODEX_RESPONSES_SCHEMA_FILE}"
CODEX_THINKING_OVERRIDE="${CODEX_THINKING_OVERRIDE:-$DEFAULT_CODEX_THINKING_OVERRIDE}"
CLAUDE_ENDPOINT="${CLAUDE_ENDPOINT:-$DEFAULT_CLAUDE_ENDPOINT}"
CLAUDE_THINKING_OVERRIDE="${CLAUDE_THINKING_OVERRIDE:-$DEFAULT_CLAUDE_THINKING_OVERRIDE}"
RUN_AGENT_MAX_ATTEMPTS="${RUN_AGENT_MAX_ATTEMPTS:-$DEFAULT_RUN_AGENT_MAX_ATTEMPTS}"
RUN_AGENT_RETRY_DELAY_SECONDS="${RUN_AGENT_RETRY_DELAY_SECONDS:-$DEFAULT_RUN_AGENT_RETRY_DELAY_SECONDS}"
RUN_AGENT_RETRY_VERBOSE="${RUN_AGENT_RETRY_VERBOSE:-$DEFAULT_RUN_AGENT_RETRY_VERBOSE}"
ENGINE_IDLE_OUTPUT_TIMEOUT_SECONDS="${ENGINE_IDLE_OUTPUT_TIMEOUT_SECONDS:-$DEFAULT_ENGINE_IDLE_OUTPUT_TIMEOUT_SECONDS}"
ENGINE_OUTPUT_MAX_BYTES="${ENGINE_OUTPUT_MAX_BYTES:-$DEFAULT_ENGINE_OUTPUT_MAX_BYTES}"
ENGINE_OUTPUT_TO_STDOUT="${ENGINE_OUTPUT_TO_STDOUT:-$DEFAULT_ENGINE_OUTPUT_TO_STDOUT}"
STRICT_VALIDATION_NOOP="${STRICT_VALIDATION_NOOP:-$DEFAULT_STRICT_VALIDATION_NOOP}"
PHASE_COMPLETION_MAX_ATTEMPTS="${PHASE_COMPLETION_MAX_ATTEMPTS:-$DEFAULT_PHASE_COMPLETION_MAX_ATTEMPTS}"
PHASE_COMPLETION_RETRY_DELAY_SECONDS="${PHASE_COMPLETION_RETRY_DELAY_SECONDS:-$DEFAULT_PHASE_COMPLETION_RETRY_DELAY_SECONDS}"
PHASE_COMPLETION_RETRY_VERBOSE="${PHASE_COMPLETION_RETRY_VERBOSE:-$DEFAULT_PHASE_COMPLETION_RETRY_VERBOSE}"
MAX_CONSENSUS_ROUTING_ATTEMPTS="${MAX_CONSENSUS_ROUTING_ATTEMPTS:-$DEFAULT_MAX_CONSENSUS_ROUTING_ATTEMPTS}"
PHASE_PAIR_CYCLE_LIMIT="${PHASE_PAIR_CYCLE_LIMIT:-$DEFAULT_PHASE_PAIR_CYCLE_LIMIT}"
REQUIRE_LINT_BEFORE_DONE="${REQUIRE_LINT_BEFORE_DONE:-$DEFAULT_REQUIRE_LINT_BEFORE_DONE}"
REQUIRE_DOCUMENT_BEFORE_DONE="${REQUIRE_DOCUMENT_BEFORE_DONE:-$DEFAULT_REQUIRE_DOCUMENT_BEFORE_DONE}"
REQUIRE_PLAN_BACKLOG_CLEAR_BEFORE_DONE="${REQUIRE_PLAN_BACKLOG_CLEAR_BEFORE_DONE:-$DEFAULT_REQUIRE_PLAN_BACKLOG_CLEAR_BEFORE_DONE}"
REQUIRE_PLAN_FRESHNESS_FOR_BUILD="${REQUIRE_PLAN_FRESHNESS_FOR_BUILD:-$DEFAULT_REQUIRE_PLAN_FRESHNESS_FOR_BUILD}"
BACKLOG_SOURCES="${BACKLOG_SOURCES:-$DEFAULT_BACKLOG_SOURCES}"
PHASE_NOOP_POLICY_PLAN="${PHASE_NOOP_POLICY_PLAN:-$DEFAULT_PHASE_NOOP_POLICY_PLAN}"
PHASE_NOOP_POLICY_BUILD="${PHASE_NOOP_POLICY_BUILD:-$DEFAULT_PHASE_NOOP_POLICY_BUILD}"
PHASE_NOOP_POLICY_TEST="${PHASE_NOOP_POLICY_TEST:-$DEFAULT_PHASE_NOOP_POLICY_TEST}"
PHASE_NOOP_POLICY_REFACTOR="${PHASE_NOOP_POLICY_REFACTOR:-$DEFAULT_PHASE_NOOP_POLICY_REFACTOR}"
PHASE_NOOP_POLICY_LINT="${PHASE_NOOP_POLICY_LINT:-$DEFAULT_PHASE_NOOP_POLICY_LINT}"
PHASE_NOOP_POLICY_DOCUMENT="${PHASE_NOOP_POLICY_DOCUMENT:-$DEFAULT_PHASE_NOOP_POLICY_DOCUMENT}"
PHASE_NOOP_PROFILE="${PHASE_NOOP_PROFILE:-$DEFAULT_PHASE_NOOP_PROFILE}"
SESSION_TOKEN_BUDGET="${SESSION_TOKEN_BUDGET:-$DEFAULT_SESSION_TOKEN_BUDGET}"
SESSION_TOKEN_RATE_CENTS_PER_MILLION="${SESSION_TOKEN_RATE_CENTS_PER_MILLION:-$DEFAULT_SESSION_TOKEN_RATE_CENTS_PER_MILLION}"
SESSION_COST_BUDGET_CENTS="${SESSION_COST_BUDGET_CENTS:-$DEFAULT_SESSION_COST_BUDGET_CENTS}"
AUTO_REPAIR_MARKDOWN_ARTIFACTS="${AUTO_REPAIR_MARKDOWN_ARTIFACTS:-$DEFAULT_AUTO_REPAIR_MARKDOWN_ARTIFACTS}"
AUTO_REPAIR_MARKDOWN_DRY_RUN="${AUTO_REPAIR_MARKDOWN_DRY_RUN:-$DEFAULT_AUTO_REPAIR_MARKDOWN_DRY_RUN}"
AUTO_REPAIR_MARKDOWN_BACKUP="${AUTO_REPAIR_MARKDOWN_BACKUP:-$DEFAULT_AUTO_REPAIR_MARKDOWN_BACKUP}"
AUTO_REPAIR_MARKDOWN_ONLY_SESSION_CHANGED="${AUTO_REPAIR_MARKDOWN_ONLY_SESSION_CHANGED:-$DEFAULT_AUTO_REPAIR_MARKDOWN_ONLY_SESSION_CHANGED}"
MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX="${MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX:-$DEFAULT_MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX}"
PHASE_MANIFEST_MODE="${PHASE_MANIFEST_MODE:-$DEFAULT_PHASE_MANIFEST_MODE}"
SWARM_CONSENSUS_TIMEOUT="${SWARM_CONSENSUS_TIMEOUT:-$DEFAULT_SWARM_CONSENSUS_TIMEOUT}"
CONSENSUS_SCORE_THRESHOLD="${CONSENSUS_SCORE_THRESHOLD:-$DEFAULT_CONSENSUS_SCORE_THRESHOLD}"
CONSENSUS_CLEAN_GO_SCORE_FLOOR="${CONSENSUS_CLEAN_GO_SCORE_FLOOR:-$DEFAULT_CONSENSUS_CLEAN_GO_SCORE_FLOOR}"
ENGINE_HEALTH_MAX_ATTEMPTS="${ENGINE_HEALTH_MAX_ATTEMPTS:-$DEFAULT_ENGINE_HEALTH_MAX_ATTEMPTS}"
ENGINE_HEALTH_RETRY_DELAY_SECONDS="${ENGINE_HEALTH_RETRY_DELAY_SECONDS:-$DEFAULT_ENGINE_HEALTH_RETRY_DELAY_SECONDS}"
ENGINE_HEALTH_RETRY_VERBOSE="${ENGINE_HEALTH_RETRY_VERBOSE:-$DEFAULT_ENGINE_HEALTH_RETRY_VERBOSE}"
ENGINE_SMOKE_TEST_TIMEOUT="${ENGINE_SMOKE_TEST_TIMEOUT:-$DEFAULT_ENGINE_SMOKE_TEST_TIMEOUT}"
STARTUP_OPERATIONAL_PROBE="${STARTUP_OPERATIONAL_PROBE:-$DEFAULT_STARTUP_OPERATIONAL_PROBE}"
ENGINE_OVERRIDES_BOOTSTRAPPED="${ENGINE_OVERRIDES_BOOTSTRAPPED:-$DEFAULT_ENGINE_OVERRIDES_BOOTSTRAPPED}"
NOTIFICATIONS_ENABLED="${NOTIFICATIONS_ENABLED:-$DEFAULT_NOTIFICATIONS_ENABLED}"
NOTIFY_TELEGRAM_ENABLED="${NOTIFY_TELEGRAM_ENABLED:-$DEFAULT_NOTIFY_TELEGRAM_ENABLED}"
NOTIFY_DISCORD_ENABLED="${NOTIFY_DISCORD_ENABLED:-$DEFAULT_NOTIFY_DISCORD_ENABLED}"
NOTIFY_DISCORD_WEBHOOK_URL="${NOTIFY_DISCORD_WEBHOOK_URL:-}"
NOTIFY_TTS_ENABLED="${NOTIFY_TTS_ENABLED:-$DEFAULT_NOTIFY_TTS_ENABLED}"
NOTIFY_TTS_STYLE="${NOTIFY_TTS_STYLE:-$DEFAULT_NOTIFY_TTS_STYLE}"
NOTIFY_CHUTES_TTS_URL="${NOTIFY_CHUTES_TTS_URL:-$DEFAULT_NOTIFY_CHUTES_TTS_URL}"
NOTIFY_CHUTES_VOICE="${NOTIFY_CHUTES_VOICE:-$DEFAULT_NOTIFY_CHUTES_VOICE}"
NOTIFY_CHUTES_SPEED="${NOTIFY_CHUTES_SPEED:-$DEFAULT_NOTIFY_CHUTES_SPEED}"
NOTIFY_EVENT_DEDUP_WINDOW_SECONDS="${NOTIFY_EVENT_DEDUP_WINDOW_SECONDS:-$DEFAULT_NOTIFY_EVENT_DEDUP_WINDOW_SECONDS}"
NOTIFY_INCIDENT_REMINDER_MINUTES="${NOTIFY_INCIDENT_REMINDER_MINUTES:-$DEFAULT_NOTIFY_INCIDENT_REMINDER_MINUTES}"
NOTIFICATION_WIZARD_BOOTSTRAPPED="${NOTIFICATION_WIZARD_BOOTSTRAPPED:-$DEFAULT_NOTIFICATION_WIZARD_BOOTSTRAPPED}"
TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"
TG_CHAT_ID="${TG_CHAT_ID:-}"
CHUTES_API_KEY="${CHUTES_API_KEY:-}"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_owned_runtime_paths || exit 1
fi

if [ -f "$CONFIG_FILE" ]; then
    if grep -Eq '^[[:space:]]*(export[[:space:]]+)?(RALPHIE_)?CONSENSUS_SCORE_THRESHOLD[[:space:]]*=' "$CONFIG_FILE" 2>/dev/null; then
        CONSENSUS_SCORE_THRESHOLD_EXPLICIT=true
    fi
    load_config_file_safe "$CONFIG_FILE"
fi

# Override with environment variables if present.
ACTIVE_ENGINE="${RALPHIE_ENGINE:-$DEFAULT_ENGINE}"
PRIME_CMD="${RALPHIE_PRIME_ENGINE_CMD:-${PRIME_ENGINE_CMD:-$DEFAULT_PRIME_CMD}}"
CODEX_CMD="${CODEX_ENGINE_CMD:-$DEFAULT_CODEX_CMD}"
CLAUDE_CMD="${CLAUDE_ENGINE_CMD:-$DEFAULT_CLAUDE_CMD}"
PRIME_COMMAND_RESOLVED=false
CODEX_COMMAND_RESOLVED=false
CLAUDE_COMMAND_RESOLVED=false
[ -z "${RALPHIE_PRIME_ENGINE_CMD:-${PRIME_ENGINE_CMD:-}}" ] || PRIME_COMMAND_RESOLVED=true
[ -z "${CODEX_ENGINE_CMD:-}" ] || CODEX_COMMAND_RESOLVED=true
[ -z "${CLAUDE_ENGINE_CMD:-}" ] || CLAUDE_COMMAND_RESOLVED=true
COMMAND_TIMEOUT_SECONDS="${RALPHIE_COMMAND_TIMEOUT_SECONDS:-$COMMAND_TIMEOUT_SECONDS}"
MAX_ITERATIONS="${RALPHIE_MAX_ITERATIONS:-$MAX_ITERATIONS}"
MAX_SESSION_CYCLES="${RALPHIE_MAX_SESSION_CYCLES:-$MAX_SESSION_CYCLES}"
SESSION_TOKEN_BUDGET="${RALPHIE_SESSION_TOKEN_BUDGET:-$SESSION_TOKEN_BUDGET}"
SESSION_TOKEN_RATE_CENTS_PER_MILLION="${RALPHIE_SESSION_TOKEN_RATE_CENTS_PER_MILLION:-$SESSION_TOKEN_RATE_CENTS_PER_MILLION}"
SESSION_COST_BUDGET_CENTS="${RALPHIE_SESSION_COST_BUDGET_CENTS:-$SESSION_COST_BUDGET_CENTS}"
RUN_AGENT_MAX_ATTEMPTS="${RALPHIE_RUN_AGENT_MAX_ATTEMPTS:-$RUN_AGENT_MAX_ATTEMPTS}"
RUN_AGENT_RETRY_DELAY_SECONDS="${RALPHIE_RUN_AGENT_RETRY_DELAY_SECONDS:-$RUN_AGENT_RETRY_DELAY_SECONDS}"
RUN_AGENT_RETRY_VERBOSE="${RALPHIE_RUN_AGENT_RETRY_VERBOSE:-$RUN_AGENT_RETRY_VERBOSE}"
ENGINE_IDLE_OUTPUT_TIMEOUT_SECONDS="${RALPHIE_ENGINE_IDLE_OUTPUT_TIMEOUT_SECONDS:-$ENGINE_IDLE_OUTPUT_TIMEOUT_SECONDS}"
ENGINE_OUTPUT_MAX_BYTES="${RALPHIE_ENGINE_OUTPUT_MAX_BYTES:-$ENGINE_OUTPUT_MAX_BYTES}"
PHASE_COMPLETION_MAX_ATTEMPTS="${RALPHIE_PHASE_COMPLETION_MAX_ATTEMPTS:-$PHASE_COMPLETION_MAX_ATTEMPTS}"
PHASE_COMPLETION_RETRY_DELAY_SECONDS="${RALPHIE_PHASE_COMPLETION_RETRY_DELAY_SECONDS:-$PHASE_COMPLETION_RETRY_DELAY_SECONDS}"
PHASE_COMPLETION_RETRY_VERBOSE="${RALPHIE_PHASE_COMPLETION_RETRY_VERBOSE:-$PHASE_COMPLETION_RETRY_VERBOSE}"
MAX_CONSENSUS_ROUTING_ATTEMPTS="${RALPHIE_MAX_CONSENSUS_ROUTING_ATTEMPTS:-$MAX_CONSENSUS_ROUTING_ATTEMPTS}"
PHASE_PAIR_CYCLE_LIMIT="${RALPHIE_PHASE_PAIR_CYCLE_LIMIT:-$PHASE_PAIR_CYCLE_LIMIT}"
REQUIRE_LINT_BEFORE_DONE="${RALPHIE_REQUIRE_LINT_BEFORE_DONE:-$REQUIRE_LINT_BEFORE_DONE}"
REQUIRE_DOCUMENT_BEFORE_DONE="${RALPHIE_REQUIRE_DOCUMENT_BEFORE_DONE:-$REQUIRE_DOCUMENT_BEFORE_DONE}"
REQUIRE_PLAN_BACKLOG_CLEAR_BEFORE_DONE="${RALPHIE_REQUIRE_PLAN_BACKLOG_CLEAR_BEFORE_DONE:-$REQUIRE_PLAN_BACKLOG_CLEAR_BEFORE_DONE}"
REQUIRE_PLAN_FRESHNESS_FOR_BUILD="${RALPHIE_REQUIRE_PLAN_FRESHNESS_FOR_BUILD:-$REQUIRE_PLAN_FRESHNESS_FOR_BUILD}"
BACKLOG_SOURCES="${RALPHIE_BACKLOG_SOURCES:-$BACKLOG_SOURCES}"
SWARM_MAX_PARALLEL="${RALPHIE_SWARM_MAX_PARALLEL:-$SWARM_MAX_PARALLEL}"
CONFIDENCE_TARGET="${RALPHIE_CONFIDENCE_TARGET:-$CONFIDENCE_TARGET}"
CONFIDENCE_STAGNATION_LIMIT="${RALPHIE_CONFIDENCE_STAGNATION_LIMIT:-$CONFIDENCE_STAGNATION_LIMIT}"
SWARM_CONSENSUS_TIMEOUT="${RALPHIE_SWARM_CONSENSUS_TIMEOUT:-$SWARM_CONSENSUS_TIMEOUT}"
ENGINE_HEALTH_MAX_ATTEMPTS="${RALPHIE_ENGINE_HEALTH_MAX_ATTEMPTS:-$ENGINE_HEALTH_MAX_ATTEMPTS}"
ENGINE_HEALTH_RETRY_DELAY_SECONDS="${RALPHIE_ENGINE_HEALTH_RETRY_DELAY_SECONDS:-$ENGINE_HEALTH_RETRY_DELAY_SECONDS}"
ENGINE_HEALTH_RETRY_VERBOSE="${RALPHIE_ENGINE_HEALTH_RETRY_VERBOSE:-$ENGINE_HEALTH_RETRY_VERBOSE}"
ENGINE_SMOKE_TEST_TIMEOUT="${RALPHIE_ENGINE_SMOKE_TEST_TIMEOUT:-$ENGINE_SMOKE_TEST_TIMEOUT}"
RESUME_REQUESTED="${RALPHIE_RESUME_REQUESTED:-$DEFAULT_RESUME_REQUESTED}"
REBOOTSTRAP_REQUESTED="${RALPHIE_REBOOTSTRAP_REQUESTED:-$DEFAULT_REBOOTSTRAP_REQUESTED}"
ENGINE_OUTPUT_TO_STDOUT="${RALPHIE_ENGINE_OUTPUT_TO_STDOUT:-$ENGINE_OUTPUT_TO_STDOUT}"
YOLO="${RALPHIE_YOLO:-$YOLO}"
AUTO_UPDATE="${RALPHIE_AUTO_UPDATE:-$AUTO_UPDATE}"
PHASE_WALLCLOCK_LIMIT_SECONDS="${RALPHIE_PHASE_WALLCLOCK_LIMIT_SECONDS:-$PHASE_WALLCLOCK_LIMIT_SECONDS}"
PHASE_NOOP_PROFILE="${RALPHIE_PHASE_NOOP_PROFILE:-$PHASE_NOOP_PROFILE}"
PHASE_NOOP_POLICY_PLAN="${RALPHIE_PHASE_NOOP_POLICY_PLAN:-$PHASE_NOOP_POLICY_PLAN}"
PHASE_NOOP_POLICY_BUILD="${RALPHIE_PHASE_NOOP_POLICY_BUILD:-$PHASE_NOOP_POLICY_BUILD}"
PHASE_NOOP_POLICY_TEST="${RALPHIE_PHASE_NOOP_POLICY_TEST:-$PHASE_NOOP_POLICY_TEST}"
PHASE_NOOP_POLICY_REFACTOR="${RALPHIE_PHASE_NOOP_POLICY_REFACTOR:-$PHASE_NOOP_POLICY_REFACTOR}"
PHASE_NOOP_POLICY_LINT="${RALPHIE_PHASE_NOOP_POLICY_LINT:-$PHASE_NOOP_POLICY_LINT}"
PHASE_NOOP_POLICY_DOCUMENT="${RALPHIE_PHASE_NOOP_POLICY_DOCUMENT:-$PHASE_NOOP_POLICY_DOCUMENT}"
STRICT_VALIDATION_NOOP="${RALPHIE_STRICT_VALIDATION_NOOP:-$STRICT_VALIDATION_NOOP}"
AUTO_REPAIR_MARKDOWN_ARTIFACTS="${RALPHIE_AUTO_REPAIR_MARKDOWN_ARTIFACTS:-$AUTO_REPAIR_MARKDOWN_ARTIFACTS}"
AUTO_REPAIR_MARKDOWN_DRY_RUN="${RALPHIE_AUTO_REPAIR_MARKDOWN_DRY_RUN:-$AUTO_REPAIR_MARKDOWN_DRY_RUN}"
AUTO_REPAIR_MARKDOWN_BACKUP="${RALPHIE_AUTO_REPAIR_MARKDOWN_BACKUP:-$AUTO_REPAIR_MARKDOWN_BACKUP}"
AUTO_REPAIR_MARKDOWN_ONLY_SESSION_CHANGED="${RALPHIE_AUTO_REPAIR_MARKDOWN_ONLY_SESSION_CHANGED:-$AUTO_REPAIR_MARKDOWN_ONLY_SESSION_CHANGED}"
MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX="${RALPHIE_MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX:-$MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX}"
PHASE_MANIFEST_MODE="${RALPHIE_PHASE_MANIFEST_MODE:-$PHASE_MANIFEST_MODE}"
AUTO_PLAN_BACKFILL_ON_IDLE_BUILD="${RALPHIE_AUTO_PLAN_BACKFILL_ON_IDLE_BUILD:-$AUTO_PLAN_BACKFILL_ON_IDLE_BUILD}"
AUTO_ENGINE_PREFERENCE="${RALPHIE_AUTO_ENGINE_PREFERENCE:-$AUTO_ENGINE_PREFERENCE}"
AUTO_INIT_GIT_IF_MISSING="${RALPHIE_AUTO_INIT_GIT_IF_MISSING:-$AUTO_INIT_GIT_IF_MISSING}"
AUTO_COMMIT_ON_PHASE_PASS="${RALPHIE_AUTO_COMMIT_ON_PHASE_PASS:-$AUTO_COMMIT_ON_PHASE_PASS}"
AUTO_UPDATE="${RALPHIE_AUTO_UPDATE:-$AUTO_UPDATE}"
AUTO_UPDATE_URL="${RALPHIE_UPDATE_URL:-${RALPHIE_AUTO_UPDATE_URL:-$AUTO_UPDATE_URL}}"
GATE_TIMEOUT_SECONDS="${RALPHIE_GATE_TIMEOUT_SECONDS:-$GATE_TIMEOUT_SECONDS}"
AUTO_UPDATE_ALLOW_DIRTY="${RALPHIE_AUTO_UPDATE_ALLOW_DIRTY:-$AUTO_UPDATE_ALLOW_DIRTY}"
AUTO_UPDATE_ALLOW_INSECURE="${RALPHIE_AUTO_UPDATE_ALLOW_INSECURE:-$AUTO_UPDATE_ALLOW_INSECURE}"
AUTO_UPDATE_TIMEOUT_SECONDS="${RALPHIE_AUTO_UPDATE_TIMEOUT_SECONDS:-$AUTO_UPDATE_TIMEOUT_SECONDS}"
AUTO_UPDATE_LOCK_TIMEOUT_SECONDS="${RALPHIE_AUTO_UPDATE_LOCK_TIMEOUT_SECONDS:-$AUTO_UPDATE_LOCK_TIMEOUT_SECONDS}"
CODEX_ENDPOINT="${RALPHIE_CODEX_ENDPOINT:-$CODEX_ENDPOINT}"
PRIME_PROVIDER="${RALPHIE_PRIME_PROVIDER:-${PRIME_PROVIDER:-}}"
PRIME_MODEL="${RALPHIE_PRIME_MODEL:-${PRIME_MODEL:-}}"
PRIME_THINKING_OVERRIDE="${RALPHIE_PRIME_THINKING_OVERRIDE:-${PRIME_THINKING_OVERRIDE:-}}"
CODEX_MODEL="${RALPHIE_CODEX_MODEL:-${CODEX_MODEL:-}}"
CODEX_USE_RESPONSES_SCHEMA="${RALPHIE_CODEX_USE_RESPONSES_SCHEMA:-$CODEX_USE_RESPONSES_SCHEMA}"
CODEX_RESPONSES_SCHEMA_FILE="${RALPHIE_CODEX_RESPONSES_SCHEMA_FILE:-$CODEX_RESPONSES_SCHEMA_FILE}"
CODEX_THINKING_OVERRIDE="${RALPHIE_CODEX_THINKING_OVERRIDE:-$CODEX_THINKING_OVERRIDE}"
CLAUDE_ENDPOINT="${RALPHIE_CLAUDE_ENDPOINT:-$CLAUDE_ENDPOINT}"
CLAUDE_MODEL="${RALPHIE_CLAUDE_MODEL:-${CLAUDE_MODEL:-}}"
CLAUDE_THINKING_OVERRIDE="${RALPHIE_CLAUDE_THINKING_OVERRIDE:-$CLAUDE_THINKING_OVERRIDE}"
STARTUP_OPERATIONAL_PROBE="${RALPHIE_STARTUP_OPERATIONAL_PROBE:-$STARTUP_OPERATIONAL_PROBE}"
CONSENSUS_SCORE_THRESHOLD="${RALPHIE_CONSENSUS_SCORE_THRESHOLD:-$CONSENSUS_SCORE_THRESHOLD}"
CONSENSUS_CLEAN_GO_SCORE_FLOOR="${RALPHIE_CONSENSUS_CLEAN_GO_SCORE_FLOOR:-$CONSENSUS_CLEAN_GO_SCORE_FLOOR}"
ENGINE_OVERRIDES_BOOTSTRAPPED="${RALPHIE_ENGINE_OVERRIDES_BOOTSTRAPPED:-$ENGINE_OVERRIDES_BOOTSTRAPPED}"
NOTIFICATIONS_ENABLED="${RALPHIE_NOTIFICATIONS_ENABLED:-$NOTIFICATIONS_ENABLED}"
NOTIFY_TELEGRAM_ENABLED="${RALPHIE_NOTIFY_TELEGRAM_ENABLED:-$NOTIFY_TELEGRAM_ENABLED}"
NOTIFY_DISCORD_ENABLED="${RALPHIE_NOTIFY_DISCORD_ENABLED:-$NOTIFY_DISCORD_ENABLED}"
NOTIFY_DISCORD_WEBHOOK_URL="${RALPHIE_NOTIFY_DISCORD_WEBHOOK_URL:-$NOTIFY_DISCORD_WEBHOOK_URL}"
NOTIFY_TTS_ENABLED="${RALPHIE_NOTIFY_TTS_ENABLED:-$NOTIFY_TTS_ENABLED}"
NOTIFY_TTS_STYLE="${RALPHIE_NOTIFY_TTS_STYLE:-$NOTIFY_TTS_STYLE}"
NOTIFY_CHUTES_TTS_URL="${RALPHIE_NOTIFY_CHUTES_TTS_URL:-$NOTIFY_CHUTES_TTS_URL}"
NOTIFY_CHUTES_VOICE="${RALPHIE_NOTIFY_CHUTES_VOICE:-$NOTIFY_CHUTES_VOICE}"
NOTIFY_CHUTES_SPEED="${RALPHIE_NOTIFY_CHUTES_SPEED:-$NOTIFY_CHUTES_SPEED}"
NOTIFY_EVENT_DEDUP_WINDOW_SECONDS="${RALPHIE_NOTIFY_EVENT_DEDUP_WINDOW_SECONDS:-$NOTIFY_EVENT_DEDUP_WINDOW_SECONDS}"
NOTIFY_INCIDENT_REMINDER_MINUTES="${RALPHIE_NOTIFY_INCIDENT_REMINDER_MINUTES:-$NOTIFY_INCIDENT_REMINDER_MINUTES}"
NOTIFICATION_WIZARD_BOOTSTRAPPED="${RALPHIE_NOTIFICATION_WIZARD_BOOTSTRAPPED:-$NOTIFICATION_WIZARD_BOOTSTRAPPED}"
TG_BOT_TOKEN="${RALPHIE_TG_BOT_TOKEN:-$TG_BOT_TOKEN}"
TG_CHAT_ID="${RALPHIE_TG_CHAT_ID:-$TG_CHAT_ID}"
CHUTES_API_KEY="${RALPHIE_CHUTES_API_KEY:-$CHUTES_API_KEY}"

# Treat env-provided phase no-op policies as explicit user intent so profile
# application does not overwrite them.
if printenv PHASE_NOOP_POLICY_PLAN >/dev/null 2>&1 || printenv RALPHIE_PHASE_NOOP_POLICY_PLAN >/dev/null 2>&1; then PHASE_NOOP_POLICY_PLAN_EXPLICIT=true; fi
if printenv PHASE_NOOP_POLICY_BUILD >/dev/null 2>&1 || printenv RALPHIE_PHASE_NOOP_POLICY_BUILD >/dev/null 2>&1; then PHASE_NOOP_POLICY_BUILD_EXPLICIT=true; fi
if printenv PHASE_NOOP_POLICY_TEST >/dev/null 2>&1 || printenv RALPHIE_PHASE_NOOP_POLICY_TEST >/dev/null 2>&1; then PHASE_NOOP_POLICY_TEST_EXPLICIT=true; fi
if printenv PHASE_NOOP_POLICY_REFACTOR >/dev/null 2>&1 || printenv RALPHIE_PHASE_NOOP_POLICY_REFACTOR >/dev/null 2>&1; then PHASE_NOOP_POLICY_REFACTOR_EXPLICIT=true; fi
if printenv PHASE_NOOP_POLICY_LINT >/dev/null 2>&1 || printenv RALPHIE_PHASE_NOOP_POLICY_LINT >/dev/null 2>&1; then PHASE_NOOP_POLICY_LINT_EXPLICIT=true; fi
if printenv PHASE_NOOP_POLICY_DOCUMENT >/dev/null 2>&1 || printenv RALPHIE_PHASE_NOOP_POLICY_DOCUMENT >/dev/null 2>&1; then PHASE_NOOP_POLICY_DOCUMENT_EXPLICIT=true; fi
if printenv CONSENSUS_SCORE_THRESHOLD >/dev/null 2>&1 || printenv RALPHIE_CONSENSUS_SCORE_THRESHOLD >/dev/null 2>&1; then CONSENSUS_SCORE_THRESHOLD_EXPLICIT=true; fi

# Validate engine selection
ENGINE_SELECTION_REQUESTED="$(normalize_engine_name "$ACTIVE_ENGINE")"
ENGINE_SELECTION_EXPLICIT=false
[ "$ENGINE_SELECTION_REQUESTED" = auto ] || ENGINE_SELECTION_EXPLICIT=true
if printenv AUTO_ENGINE_PREFERENCE >/dev/null 2>&1 || printenv RALPHIE_AUTO_ENGINE_PREFERENCE >/dev/null 2>&1; then ENGINE_SELECTION_EXPLICIT=true; fi
PRIME_OPTIONS_EXPLICIT=false
if [ -n "$PRIME_PROVIDER$PRIME_MODEL$PRIME_THINKING_OVERRIDE" ]; then PRIME_OPTIONS_EXPLICIT=true; fi
AUTO_ENGINE_PREFERENCE="$(normalize_engine_name "$AUTO_ENGINE_PREFERENCE")"

if [ -n "$MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX" ] && ! awk_regex_is_valid "$MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX"; then
    warn "Invalid MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX; disabling markdown path allowlist."
    MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX="$DEFAULT_MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX"
fi

PHASE_MANIFEST_MODE="$(normalize_phase_manifest_mode "$PHASE_MANIFEST_MODE")"


if [ -z "$(sanitize_text_for_log "$BACKLOG_SOURCES")" ]; then
    BACKLOG_SOURCES="$DEFAULT_BACKLOG_SOURCES"
fi

NOTIFY_TTS_STYLE="$(to_lower "$NOTIFY_TTS_STYLE")"
case "$NOTIFY_TTS_STYLE" in
    standard|friendly|ralph_wiggum) ;;
    ralph) NOTIFY_TTS_STYLE="ralph_wiggum" ;;
    *)
        warn "Invalid NOTIFY_TTS_STYLE '$NOTIFY_TTS_STYLE'. Falling back to '$DEFAULT_NOTIFY_TTS_STYLE'."
        NOTIFY_TTS_STYLE="$DEFAULT_NOTIFY_TTS_STYLE"
        ;;
esac

if ! is_decimal_number "$NOTIFY_CHUTES_SPEED"; then
    warn "Invalid NOTIFY_CHUTES_SPEED '$NOTIFY_CHUTES_SPEED'. Falling back to '$DEFAULT_NOTIFY_CHUTES_SPEED'."
    NOTIFY_CHUTES_SPEED="$DEFAULT_NOTIFY_CHUTES_SPEED"
fi
if [ -z "$NOTIFY_CHUTES_TTS_URL" ]; then
    NOTIFY_CHUTES_TTS_URL="$DEFAULT_NOTIFY_CHUTES_TTS_URL"
fi
if [ -z "$NOTIFY_CHUTES_VOICE" ]; then
    NOTIFY_CHUTES_VOICE="$DEFAULT_NOTIFY_CHUTES_VOICE"
fi

# Derive optional channel availability only after validating operator choices.
apply_notification_prerequisites() {
    if ! command -v curl >/dev/null 2>&1 && is_true "$NOTIFICATIONS_ENABLED"; then
        warn "Notifications requested but 'curl' is unavailable. Disabling notifications."
        NOTIFICATIONS_ENABLED="false"
    fi

    if is_true "$NOTIFY_TELEGRAM_ENABLED"; then
        if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
            warn "Telegram notifications enabled but TG_BOT_TOKEN/TG_CHAT_ID are incomplete. Disabling Telegram channel."
            NOTIFY_TELEGRAM_ENABLED="false"
        fi
    fi
    if is_true "$NOTIFY_DISCORD_ENABLED" && [ -z "$NOTIFY_DISCORD_WEBHOOK_URL" ]; then
        warn "Discord notifications enabled but webhook URL is empty. Disabling Discord channel."
        NOTIFY_DISCORD_ENABLED="false"
    fi
    if is_true "$NOTIFY_TTS_ENABLED"; then
        if ! is_true "$NOTIFY_TELEGRAM_ENABLED" && ! is_true "$NOTIFY_DISCORD_ENABLED"; then
            warn "TTS notifications require Telegram or Discord notifications. Disabling TTS channel."
            NOTIFY_TTS_ENABLED="false"
        elif [ -z "$CHUTES_API_KEY" ]; then
            warn "TTS notifications enabled but CHUTES_API_KEY is empty. Disabling TTS channel."
            NOTIFY_TTS_ENABLED="false"
        fi
    fi

    if [ "$NOTIFY_TELEGRAM_ENABLED" != "true" ] && [ "$NOTIFY_DISCORD_ENABLED" != "true" ]; then
        NOTIFICATIONS_ENABLED="false"
    fi
    return 0
}


if [ "$ENGINE_SELECTION_REQUESTED" = "prime-agent" ]; then
    ACTIVE_ENGINE="prime-agent"
    ACTIVE_CMD="$PRIME_CMD"
elif [ "$ENGINE_SELECTION_REQUESTED" = "codex" ]; then
    ACTIVE_ENGINE="codex"
    ACTIVE_CMD="$CODEX_CMD"
elif [ "$ENGINE_SELECTION_REQUESTED" = "claude" ]; then
    ACTIVE_ENGINE="claude"
    ACTIVE_CMD="$CLAUDE_CMD"
else
    # Keep auto as the requested mode; resolve_active_engine will select the
    # active runtime engine each loop based on health/capabilities.
    ACTIVE_ENGINE="auto"
    if [ "$AUTO_ENGINE_PREFERENCE" = "prime-agent" ]; then
        ACTIVE_CMD="$PRIME_CMD"
    elif [ "$AUTO_ENGINE_PREFERENCE" = "claude" ]; then
        if command -v "$CLAUDE_CMD" >/dev/null 2>&1; then
            ACTIVE_CMD="$CLAUDE_CMD"
        elif command -v "$CODEX_CMD" >/dev/null 2>&1; then
            ACTIVE_CMD="$CODEX_CMD"
        else
            ACTIVE_CMD="$CLAUDE_CMD"
        fi
    else
        if command -v "$CODEX_CMD" >/dev/null 2>&1; then
            ACTIVE_CMD="$CODEX_CMD"
        elif command -v "$CLAUDE_CMD" >/dev/null 2>&1; then
            ACTIVE_CMD="$CLAUDE_CMD"
        else
            ACTIVE_CMD="$CODEX_CMD"
        fi
    fi
fi

# Runtime State variables (these change during the loop)
CURRENT_PHASE="plan"
CURRENT_PHASE_INDEX=0
ITERATION_COUNT=0
SESSION_ID="$(date +%Y%m%d_%H%M%S)_$(printf '%s' "${EPOCHREALTIME:-$(date +%s)}" | tr -d '.')_$$_$(portable_random)"
SESSION_ATTEMPT_COUNT=0
SESSION_TOKEN_COUNT=0
SESSION_COST_CENTS=0
LAST_RUN_TOKEN_COUNT=0
SESSION_BUDGET_RECEIPT_FILE=""
SWARM_BUDGET_RECEIPT_DIR=""
SWARM_BUDGET_BASE_ATTEMPTS=0
SWARM_BUDGET_BASE_TOKENS=0
SWARM_BUDGET_BASE_COST=0
ENGINE_BUDGET_EXHAUSTED=false
ENGINE_BUDGET_FAILURE_REASON=""
LAST_CONSENSUS_SCORE=0
LAST_CONSENSUS_PASS=false
LAST_CONSENSUS_DIR=""
LAST_CONSENSUS_SUMMARY=""
LAST_CONSENSUS_NEXT_PHASE="done"
LAST_CONSENSUS_NEXT_PHASE_REASON="no consensus recommendation"
LAST_CONSENSUS_RESPONDED_VOTES=0
LAST_CONSENSUS_NEXT_PHASE_VOTES=0
LAST_CONSENSUS_GO_VOTES=0
LAST_CONSENSUS_BLOCKING_GAP_VOTES=0
LAST_CONSENSUS_FAILURE_KIND="none"
LAST_CONSENSUS_FAILURE_REASON=""
LAST_DONE_GUARD_REASON=""
LAST_DONE_GUARD_NEXT_PHASE="done"
LAST_PHASE_ROUTE_GUARD_REASON=""
LAST_PHASE_ROUTE_GUARD_NEXT_PHASE="done"
LAST_BACKLOG_STALE_SOURCES=""
PLAN_FRESHNESS_FINGERPRINT=""
LAST_GATE_DECISION_RECORDED_AT=""
LAST_GATE_DECISION_PHASE=""
LAST_GATE_DECISION_ATTEMPT=0
LAST_GATE_DECISION_STAGE=""
LAST_GATE_DECISION_OUTCOME=""
LAST_GATE_DECISION_SCORE=0
LAST_GATE_DECISION_PASS=false
LAST_GATE_DECISION_RESPONDED_VOTES=0
LAST_GATE_DECISION_NEXT_PHASE=""
LAST_GATE_DECISION_SUMMARY=""
LAST_HANDOFF_SCORE=0
LAST_HANDOFF_VERDICT="HOLD"
LAST_HANDOFF_GAPS="no explicit gaps"
PHASE_TRANSITION_HISTORY=()
CONSENSUS_NO_ENGINES=false
CURRENT_PHASE_ATTEMPT=1
PHASE_ATTEMPT_IN_PROGRESS="false"
AUTO_COMMIT_SESSION_ENABLED="false"
GIT_IDENTITY_READY="unknown"
GIT_IDENTITY_SOURCE="unknown"
NOTIFY_LAST_EVENT_SIGNATURE=""
NOTIFY_LAST_EVENT_SENT_AT=0
NOTIFY_INCIDENT_SERIES_ACTIVE="false"
NOTIFY_INCIDENT_SERIES_KEY=""
NOTIFY_INCIDENT_SERIES_STARTED_AT=0
NOTIFY_INCIDENT_LAST_SENT_AT=0
NOTIFY_INCIDENT_REPEAT_COUNT=0

# Capability Probing results (populated by probe_engine_capabilities)
PRIME_CAP_PRINT=0
PRIME_CAP_NOTE=""
PRIME_HEALTHY="false"
CLAUDE_CAP_PRINT=0
CLAUDE_CAP_YOLO_FLAG=""
CODEX_CAP_OUTPUT_LAST_MESSAGE=0
CODEX_CAP_YOLO_FLAG=0
ENGINE_CAPABILITIES_PROBED=false
CODEX_CAP_NOTE=""
CLAUDE_CAP_NOTE=""
CODEX_HEALTHY="false"
CLAUDE_HEALTHY="false"
CODEX_SMOKE_PASS="false"
CLAUDE_SMOKE_PASS="false"
CODEX_SMOKE_PERMANENT_FAILURE=false
CLAUDE_SMOKE_PERMANENT_FAILURE=false
LAST_ENGINE_SELECTION_BLOCK_REASON=""
ENGINE_PERMANENT_FAILURE=false
ENGINE_PERMANENT_FAILURE_REASON=""

# Resilience Dial implementation
get_reviewer_count() {
    case "$RALPHIE_QUALITY_LEVEL" in
        minimal) echo 1 ;;
        standard) echo 3 ;;
        high) echo 5 ;;
        *) echo 3 ;;
    esac
}

get_parallel_reviewer_count() {
    case "$RALPHIE_QUALITY_LEVEL" in
        minimal) echo 1 ;;
        standard) echo 2 ;;
        high) echo 4 ;;
        *) echo 2 ;;
    esac
}

get_reviewer_max_retries() {
    case "$RALPHIE_QUALITY_LEVEL" in
        minimal) echo 0 ;;
        standard) echo 1 ;;
        high) echo 2 ;;
        *) echo 1 ;;
    esac
}

# State Management with Integrity Checks
# Returns the highest-preferred available command for SHA-256 checksums.
sha256sum_command() {
    if command -v sha256sum >/dev/null 2>&1; then
        echo "sha256sum"
        return 0
    fi
    if command -v shasum >/dev/null 2>&1; then
        echo "shasum"
        return 0
    fi
    return 1
}

sha256_file_sum() {
    # Hash stdin so checksum tools never append or escape a delimiter-bearing
    # filename in their output (GNU sha256sum and BSD shasum differ here).
    sha256_stream_sum < "$1"
}

sha256_stream_sum() {
    local checksum_cmd

    checksum_cmd="$(sha256sum_command)" || return 1

    if [ "$checksum_cmd" = "sha256sum" ]; then
        "$checksum_cmd" | awk '{print $1}'
    else
        "$checksum_cmd" -a 256 | awk '{print $1}'
    fi
}

self_update_current_script_path() {
    printf '%s/%s' "$SCRIPT_DIR" "$(basename "${BASH_SOURCE[0]}")"
}

self_update_acquire_lock() {
    local lock_dir="$1"
    local timeout_seconds="${2:-30}"
    acquire_lock_claim "$lock_dir" "$timeout_seconds" || return 1
    SELF_UPDATE_LOCK_TOKEN="$LOCK_CLAIM_TOKEN"
    return 0
}

self_update_release_lock() {
    local lock_dir="${1:-}"
    [ -n "$lock_dir" ] && [ -n "${SELF_UPDATE_LOCK_TOKEN:-}" ] || return 0
    release_lock_claim "$lock_dir" "$SELF_UPDATE_LOCK_TOKEN"
}

self_update_url_escape_path() {
    local value="${1:-}"
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$value" <<'PY' 2>/dev/null && return 0
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe="/"))
PY
    fi
    printf '%s' "$value" | sed 's/ /%20/g'
}

self_update_derive_github_raw_url() {
    command -v git >/dev/null 2>&1 || return 1

    local self_path git_root rel_path remote_url branch repo_path owner repo encoded_path
    self_path="$(self_update_current_script_path)"
    git_root="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$git_root" ] || return 1
    case "$self_path" in
        "$git_root"/*) rel_path="${self_path#"$git_root"/}" ;;
        *) return 1 ;;
    esac

    remote_url="$(git -C "$git_root" config --get remote.origin.url 2>/dev/null || true)"
    [ -n "$remote_url" ] || return 1
    branch="$(git -C "$git_root" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    if [ -z "$branch" ]; then
        branch="$(git -C "$git_root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    fi
    [ -n "$branch" ] && [ "$branch" != "HEAD" ] || return 1

    case "$remote_url" in
        https://github.com/*) repo_path="${remote_url#https://github.com/}" ;;
        http://github.com/*) repo_path="${remote_url#http://github.com/}" ;;
        git@github.com:*) repo_path="${remote_url#git@github.com:}" ;;
        ssh://git@github.com/*) repo_path="${remote_url#ssh://git@github.com/}" ;;
        *) return 1 ;;
    esac
    repo_path="${repo_path%.git}"
    owner="${repo_path%%/*}"
    repo="${repo_path#*/}"
    repo="${repo%%/*}"
    repo="${repo%.git}"
    [ -n "$owner" ] && [ -n "$repo" ] && [ "$repo" != "$repo_path" ] || return 1

    encoded_path="$(self_update_url_escape_path "$rel_path")"
    printf 'https://raw.githubusercontent.com/%s/%s/%s/%s\n' "$owner" "$repo" "$branch" "$encoded_path"
}

self_update_url_is_allowed() {
    local url="${1:-}"
    case "$url" in
        https://*) return 0 ;;
        file://*|/*|./*|../*) return 0 ;;
        http://*)
            is_true "${AUTO_UPDATE_ALLOW_INSECURE:-false}" && return 0
            return 1
            ;;
        *) return 1 ;;
    esac
}

self_update_download_stream() {
    local url="$1"
    local timeout_seconds="$2"
    local local_path=""
    local protocols='=https'
    is_true "${AUTO_UPDATE_ALLOW_INSECURE:-false}" && protocols='=http,https'

    case "$url" in
        file://*)
            local_path="${url#file://}"
            [ -f "$local_path" ] || return 1
            cat -- "$local_path"
            return $?
            ;;
        /*|./*|../*)
            [ -f "$url" ] || return 1
            cat -- "$url"
            return $?
            ;;
    esac

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 0 --connect-timeout "$timeout_seconds" --max-time "$timeout_seconds" \
            --proto "$protocols" --proto-redir "$protocols" -- "$url"
        return $?
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$url" "$timeout_seconds" "${AUTO_UPDATE_ALLOW_INSECURE:-false}" <<'PY'
import sys
import urllib.request
from urllib.parse import urlsplit

url, timeout, insecure = sys.argv[1], int(sys.argv[2]), sys.argv[3].lower()
allowed = {"https", "http"} if insecure in {"1", "y", "yes", "true", "on"} else {"https"}
class SecureRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        if urlsplit(newurl).scheme not in allowed:
            raise ValueError("auto-update redirect uses a disallowed protocol")
        return super().redirect_request(request, fp, code, msg, headers, newurl)
with urllib.request.build_opener(SecureRedirect()).open(url, timeout=timeout) as response:
    sys.stdout.buffer.write(response.read(2000001))
PY
        return $?
    fi
    if command -v wget >/dev/null 2>&1; then
        # Without curl/Python, refuse redirects rather than permit an HTTPS
        # source to downgrade silently. The outer watchdog bounds trickle reads.
        wget -q -T "$timeout_seconds" --tries=1 --max-redirect=0 -O - -- "$url"
        return $?
    fi
    return 1
}

self_update_download_to_file() {
    local url="$1" dest="$2" timeout_seconds="${3:-20}"
    local child status
    local COMMAND_TIMEOUT_SECONDS="$timeout_seconds"
    (
        set -o pipefail
        self_update_download_stream "$url" "$timeout_seconds" | head -c 2000001 > "$dest"
    ) &
    child=$!
    register_managed_pid "$child"
    if wait_for_process_with_idle_output_watchdog "$child" 0 'self-update fetch' "$dest"; then status=0; else status=$?; fi
    unregister_managed_pid "$child"
    [ "$status" -eq 0 ] && [ "$(file_size_bytes_safe "$dest")" -le 2000000 ]
}

self_update_candidate_is_valid() {
    local candidate="$1"
    local bytes=""
    [ -f "$candidate" ] || return 1
    bytes="$(wc -c < "$candidate" | tr -d ' ')"
    is_number "$bytes" || return 1
    [ "$bytes" -ge 200 ] && [ "$bytes" -le 2000000 ] || return 1
    head -n 1 "$candidate" | grep -qE '^#!.*(bash|env[[:space:]]+bash)' || return 1
    if LC_ALL=C grep -q "$(printf '\r')" "$candidate"; then
        return 1
    fi
    grep -q 'Ralphie - ' "$candidate" || return 1
    # The published source may belong to a different harness architecture. A
    # compatible May continuation must retain this entry and phase contract;
    # never execute a downloaded candidate merely to inspect it.
    [ "$(grep -cE '^SCRIPT_VERSION="[0-9]+\.[0-9]+\.[0-9]+"$' "$candidate")" = 1 ] || return 1
    grep -q '^ensure_project_bootstrap()' "$candidate" || return 1
    grep -q '^run_swarm_consensus()' "$candidate" || return 1
    grep -q '^enforce_terminal_done_requirements()' "$candidate" || return 1
    grep -q 'local -a phases=("plan" "build" "test" "refactor" "lint" "document")' "$candidate" || return 1
    grep -q 'parse_args "$@"' "$candidate" || return 1
    grep -q 'self_update_check_and_reexec "$@"' "$candidate" || return 1
    grep -q 'RALPHIE_SKIP_AUTO_UPDATE' "$candidate" || return 1
    grep -q 'main "$@"' "$candidate" || return 1
    "$BASH" -n "$candidate" >/dev/null 2>&1
}

self_update_script_is_dirty() {
    command -v git >/dev/null 2>&1 || return 1

    local self_path git_root git_prefix rel_path
    self_path="$(self_update_current_script_path)"
    git_root="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$git_root" ] || return 1
    git_prefix="$(git -C "$SCRIPT_DIR" rev-parse --show-prefix 2>/dev/null || true)"
    rel_path="${git_prefix}$(basename "$self_path")"
    git -C "$git_root" ls-files --error-unmatch -- "$rel_path" >/dev/null 2>&1 || return 0
    [ -n "$(git -C "$git_root" status --porcelain -- "$rel_path" 2>/dev/null || true)" ] && return 0
    return 1
}

self_update_transaction() (
    local self_path="$1" update_url="$2"
    local update_dir update_lock_dir tmp_candidate="" backup_path current_hash candidate_hash mode
    local SELF_UPDATE_LOCK_TOKEN=""
    local -a RALPHIE_BG_PIDS=()
    update_dir="$CONFIG_DIR/self-update"
    ensure_runtime_directory "$update_dir" || {
        warn "Auto-update skipped: could not create $(path_for_display "$update_dir")."
        return 1
    }
    chmod 700 "$update_dir" || return 1
    # The installed file may serve many projects. Its transaction lock and
    # replacement staging must share that file's directory, not a project.
    update_lock_dir="${self_path}.update.lock"
    if ! self_update_acquire_lock "$update_lock_dir" "${AUTO_UPDATE_LOCK_TIMEOUT_SECONDS:-$DEFAULT_AUTO_UPDATE_LOCK_TIMEOUT_SECONDS}"; then
        warn "Auto-update skipped: another Ralphie self-update is still in progress."
        return 1
    fi
    trap 'cleanup_managed_processes; [ -z "$tmp_candidate" ] || rm -f "$tmp_candidate"; self_update_release_lock "$update_lock_dir"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    if ! is_true "${AUTO_UPDATE_ALLOW_DIRTY:-false}" && self_update_script_is_dirty; then
        warn "Auto-update skipped: local ralphie.sh has uncommitted changes. Set AUTO_UPDATE_ALLOW_DIRTY=true to override."
        return 1
    fi
    current_hash="$(sha256_file_sum "$self_path")" || return 1
    tmp_candidate="$(mktemp "${self_path}.update.XXXXXX")" || {
        warn "Auto-update skipped: could not create temporary update file."
        return 1
    }

    info "Auto-update: checking remote ralphie.sh from $(redact_endpoint_for_log "$update_url")."
    if ! self_update_download_to_file "$update_url" "$tmp_candidate" "${AUTO_UPDATE_TIMEOUT_SECONDS:-$DEFAULT_AUTO_UPDATE_TIMEOUT_SECONDS}"; then
        warn "Auto-update skipped: failed to fetch remote ralphie.sh."
        return 1
    fi
    if ! self_update_candidate_is_valid "$tmp_candidate"; then
        warn "Auto-update skipped: remote ralphie.sh failed validation."
        return 1
    fi
    if cmp -s "$self_path" "$tmp_candidate"; then
        info "Auto-update: current ralphie.sh already matches remote."
        return 1
    fi

    candidate_hash="$(sha256_file_sum "$tmp_candidate")" || return 1
    backup_path="$(mktemp "$update_dir/ralphie.sh.backup.XXXXXX")" || return 1
    if ! cp -p "$self_path" "$backup_path" || ! cmp -s "$self_path" "$backup_path" ||
        [ "$(sha256_file_sum "$backup_path")" != "$current_hash" ]; then
        warn "Auto-update skipped: could not write backup before replacing ralphie.sh."
        return 1
    fi

    mode="$(stat -c '%a' "$self_path" 2>/dev/null || stat -f '%Lp' "$self_path" 2>/dev/null)" || return 1
    chmod "$mode" "$tmp_candidate" || return 1
    [ ! -L "$self_path" ] && [ -f "$self_path" ] && cmp -s "$self_path" "$backup_path" || {
        warn 'Auto-update skipped: installed script changed during the update.'
        return 1
    }
    if ! mv "$tmp_candidate" "$self_path"; then
        warn "Auto-update failed: could not atomically replace ralphie.sh. Backup remains at $(path_for_display "$backup_path")."
        return 1
    fi

    success "Auto-update: replaced ralphie.sh ($current_hash -> $candidate_hash). Backup: $(path_for_display "$backup_path")."
    return 0
)

self_update_check_and_reexec() {
    is_true "${AUTO_UPDATE:-false}" || return 0
    [ "${RALPHIE_SKIP_AUTO_UPDATE:-}" != "1" ] || return 0
    [ "${RALPHIE_SELF_UPDATE_REEXECED:-}" != "1" ] || return 0
    local self_path update_url
    self_path="$(self_update_current_script_path)"
    if [ -L "$self_path" ] || [ ! -f "$self_path" ]; then
        warn 'Auto-update skipped: launch from a regular script file, not a symlink.'
        return 0
    fi
    update_url="${AUTO_UPDATE_URL:-$DEFAULT_AUTO_UPDATE_URL}"
    if ! self_update_url_is_allowed "$update_url"; then
        warn 'Auto-update skipped: update URL must be https://, file://, or a local path. Set AUTO_UPDATE_ALLOW_INSECURE=true only for trusted http:// origins.'
        return 0
    fi
    case "$update_url" in
        ./*|../*) update_url="$INVOCATION_DIR/$update_url" ;;
        file://./*|file://../*) update_url="file://$INVOCATION_DIR/${update_url#file://}" ;;
    esac
    if self_update_transaction "$self_path" "$update_url"; then
        # Original arguments retain their original base directory. The same
        # interpreter also supports an installed script launched as bash FILE.
        cd "$INVOCATION_DIR" || return 1
        exec env RALPHIE_SKIP_AUTO_UPDATE=1 RALPHIE_SELF_UPDATE_REEXECED=1 "$BASH" "$self_path" "$@"
    fi
    return 0
}

state_blob_encode() {
    local payload="${1:-}"
    if command -v base64 >/dev/null 2>&1; then
        printf '%s' "$payload" | base64 | tr -d '\n'
        return "${PIPESTATUS[1]:-$?}"
    fi
    if command -v openssl >/dev/null 2>&1; then
        printf '%s' "$payload" | openssl base64 -A 2>/dev/null
        return "${PIPESTATUS[1]:-$?}"
    fi
    return 1
}

state_blob_decode() {
    local payload="${1:-}"
    [ -z "$payload" ] && { echo ""; return 0; }

    if command -v base64 >/dev/null 2>&1; then
        printf '%s' "$payload" | base64 --decode 2>/dev/null && return 0
        printf '%s' "$payload" | base64 -d 2>/dev/null && return 0
        printf '%s' "$payload" | base64 -D 2>/dev/null && return 0
    fi
    if command -v openssl >/dev/null 2>&1; then
        printf '%s' "$payload" | openssl base64 -d -A 2>/dev/null && return 0
    fi
    return 1
}

state_escape_value() {
    # State records carry multiline text; config values use literal scalars.
    local value="${1:-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}

state_unescape_value() {
    local value="${1:-}"
    local bslash_sentinel=$'\001'

    value="${value//\\\\/$bslash_sentinel}"
    value="${value//\\n/$'\n'}"
    value="${value//\\r/$'\r'}"
    value="${value//\\t/$'\t'}"
    value="${value//\\\"/\"}"
    value="${value//$bslash_sentinel/\\}"
    printf '%s' "$value"
}

gate_decision_trim_text() {
    local value="${1:-}"
    local limit="${2:-1200}"

    is_number "$limit" || limit=1200
    value="$(sanitize_text_for_log "$value")"
    if [ "$limit" -gt 0 ]; then
        value="$(printf '%s' "$value" | cut -c 1-"$limit")"
    fi
    printf '%s' "$value"
}

record_gate_decision() {
    local phase="${1:-unknown}"
    local attempt="${2:-0}"
    local stage="${3:-phase-gate}"
    local outcome="${4:-unknown}"
    local next_phase="${5:-${LAST_CONSENSUS_NEXT_PHASE:-unknown}}"
    local explainer="${6:-${LAST_CONSENSUS_NEXT_PHASE_REASON:-no explicit routing rationale}}"
    local voting_summary
    local handoff_summary
    local failure_summary=""

    voting_summary="$(gate_decision_trim_text "${LAST_CONSENSUS_SUMMARY:-no reviewer summary}" 1400)"
    [ -n "$voting_summary" ] || voting_summary="no reviewer summary"
    explainer="$(gate_decision_trim_text "$explainer" 900)"
    [ -n "$explainer" ] || explainer="no explicit routing rationale"
    handoff_summary="$(gate_decision_trim_text "handoff verdict=${LAST_HANDOFF_VERDICT:-unknown} score=${LAST_HANDOFF_SCORE:-0} gaps=${LAST_HANDOFF_GAPS:-none}" 500)"
    if [ "${LAST_CONSENSUS_FAILURE_KIND:-none}" != "none" ] || [ -n "${LAST_CONSENSUS_FAILURE_REASON:-}" ]; then
        failure_summary="$(gate_decision_trim_text "failure=${LAST_CONSENSUS_FAILURE_KIND:-unknown}: ${LAST_CONSENSUS_FAILURE_REASON:-unspecified}" 500)"
    fi

    LAST_GATE_DECISION_RECORDED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)"
    LAST_GATE_DECISION_PHASE="$phase"
    LAST_GATE_DECISION_ATTEMPT="$attempt"
    LAST_GATE_DECISION_STAGE="$stage"
    LAST_GATE_DECISION_OUTCOME="$outcome"
    LAST_GATE_DECISION_SCORE="${LAST_CONSENSUS_SCORE:-0}"
    LAST_GATE_DECISION_PASS="${LAST_CONSENSUS_PASS:-false}"
    LAST_GATE_DECISION_RESPONDED_VOTES="${LAST_CONSENSUS_RESPONDED_VOTES:-0}"
    LAST_GATE_DECISION_NEXT_PHASE="$next_phase"
    LAST_GATE_DECISION_SUMMARY="$(printf 'score=%s pass=%s votes=%s next=%s outcome=%s\nvoting: %s\nexplainer: %s\n%s' \
        "$LAST_GATE_DECISION_SCORE" \
        "$LAST_GATE_DECISION_PASS" \
        "$LAST_GATE_DECISION_RESPONDED_VOTES" \
        "$LAST_GATE_DECISION_NEXT_PHASE" \
        "$LAST_GATE_DECISION_OUTCOME" \
        "$voting_summary" \
        "$explainer" \
        "$handoff_summary")"
    if [ -n "$failure_summary" ]; then
        LAST_GATE_DECISION_SUMMARY="${LAST_GATE_DECISION_SUMMARY}
$failure_summary"
    fi
}

save_state() {
    ensure_runtime_file "$STATE_FILE" || return 1
    ensure_runtime_directory "$(dirname "$STATE_FILE")" || return 1
    local checksum
    local tmp_state_file
    local history_payload=""
    local history_encoded=""

    if [ "${#PHASE_TRANSITION_HISTORY[@]}" -gt 0 ]; then
        history_payload="$(printf '%s\n' "${PHASE_TRANSITION_HISTORY[@]}")"
        history_encoded="$(state_blob_encode "$history_payload" 2>/dev/null || true)"
        if [ -z "$history_encoded" ]; then
            warn "Could not encode phase transition history for state persistence."
            return 1
        fi
    fi

    tmp_state_file="$(mktemp "$CONFIG_DIR/state.tmp.XXXXXX")" || {
        warn "Could not create temporary state file in $(path_for_display "$CONFIG_DIR")."
        return 1
    }

    # One checked write covers every record. A compound writer's final
    # successful command must not conceal an earlier serialization failure.
    if ! printf '%s="%s"\n' \
        MISSION_SEED_SHA "$(state_escape_value "${MISSION_SEED_SHA:-}")" \
        REQUEST_REVIEWED_FINGERPRINT "$(state_escape_value "${REQUEST_REVIEWED_FINGERPRINT:-}")" \
        OWNED_PATHS_SHA "$(state_escape_value "${OWNED_PATHS_SHA:-}")" \
        SHELL_GATES_FINGERPRINT "$(state_escape_value "${SHELL_GATES_FINGERPRINT:-}")" \
        SHELL_LOCAL_WORK_SEEN "$(state_escape_value "${SHELL_LOCAL_WORK_SEEN:-}")" \
        SHELL_DEVELOPMENT_PHASE_STARTED "$(state_escape_value "${SHELL_DEVELOPMENT_PHASE_STARTED:-}")" \
        SESSION_INITIAL_HEAD "$(state_escape_value "${SESSION_INITIAL_HEAD:-}")" \
        CURRENT_PHASE "$(state_escape_value "$CURRENT_PHASE")" \
        CURRENT_PHASE_INDEX "$(state_escape_value "$CURRENT_PHASE_INDEX")" \
        CURRENT_PHASE_ATTEMPT "$(state_escape_value "$CURRENT_PHASE_ATTEMPT")" \
        PHASE_ATTEMPT_IN_PROGRESS "$(state_escape_value "$PHASE_ATTEMPT_IN_PROGRESS")" \
        ITERATION_COUNT "$(state_escape_value "$ITERATION_COUNT")" \
        SESSION_ID "$(state_escape_value "$SESSION_ID")" \
        SESSION_ATTEMPT_COUNT "$(state_escape_value "$SESSION_ATTEMPT_COUNT")" \
        SESSION_TOKEN_COUNT "$(state_escape_value "$SESSION_TOKEN_COUNT")" \
        SESSION_COST_CENTS "$(state_escape_value "$SESSION_COST_CENTS")" \
        LAST_RUN_TOKEN_COUNT "$(state_escape_value "$LAST_RUN_TOKEN_COUNT")" \
        ENGINE_OUTPUT_TO_STDOUT "$(state_escape_value "$ENGINE_OUTPUT_TO_STDOUT")" \
        PHASE_TRANSITION_HISTORY_B64 "$(state_escape_value "$history_encoded")" \
        PLAN_FRESHNESS_FINGERPRINT "$(state_escape_value "$PLAN_FRESHNESS_FINGERPRINT")" \
        GIT_IDENTITY_READY "$(state_escape_value "$GIT_IDENTITY_READY")" \
        GIT_IDENTITY_SOURCE "$(state_escape_value "$GIT_IDENTITY_SOURCE")" \
        LAST_GATE_DECISION_RECORDED_AT "$(state_escape_value "$LAST_GATE_DECISION_RECORDED_AT")" \
        LAST_GATE_DECISION_PHASE "$(state_escape_value "$LAST_GATE_DECISION_PHASE")" \
        LAST_GATE_DECISION_ATTEMPT "$(state_escape_value "$LAST_GATE_DECISION_ATTEMPT")" \
        LAST_GATE_DECISION_STAGE "$(state_escape_value "$LAST_GATE_DECISION_STAGE")" \
        LAST_GATE_DECISION_OUTCOME "$(state_escape_value "$LAST_GATE_DECISION_OUTCOME")" \
        LAST_GATE_DECISION_SCORE "$(state_escape_value "$LAST_GATE_DECISION_SCORE")" \
        LAST_GATE_DECISION_PASS "$(state_escape_value "$LAST_GATE_DECISION_PASS")" \
        LAST_GATE_DECISION_RESPONDED_VOTES "$(state_escape_value "$LAST_GATE_DECISION_RESPONDED_VOTES")" \
        LAST_GATE_DECISION_NEXT_PHASE "$(state_escape_value "$LAST_GATE_DECISION_NEXT_PHASE")" \
        LAST_GATE_DECISION_SUMMARY "$(state_escape_value "$LAST_GATE_DECISION_SUMMARY")" > "$tmp_state_file"; then
        warn "Could not serialize state; preserving the previous snapshot."
        rm -f "$tmp_state_file"
        return 1
    fi
    if ! checksum="$(sha256_file_sum "$tmp_state_file")" \
        || ! printf 'STATE_CHECKSUM="%s"\n' "$checksum" >> "$tmp_state_file"; then
        warn "Could not seal state; preserving the previous snapshot."
        rm -f "$tmp_state_file"
        return 1
    fi

    if ! mv "$tmp_state_file" "$STATE_FILE"; then
        warn "Could not atomically update state file: $(path_for_display "$STATE_FILE")"
        rm -f "$tmp_state_file"
        return 1
    fi
    return 0
}

save_state_or_exit() {
    local checkpoint="${1:-unspecified checkpoint}"
    if save_state; then
        return 0
    fi

    err "Failed to persist state at checkpoint: $checkpoint"
    log_reason_code "RB_STATE_SAVE_FAILED" "state persistence failed at checkpoint: $checkpoint"
    notify_event "session_error" "state_persist_failed" "checkpoint=$checkpoint" || true
    release_lock
    exit 1
}

load_state() {
    if [ ! -f "$STATE_FILE" ]; then return 1; fi

    REQUEST_REVIEWED_FINGERPRINT=""
    CURRENT_PHASE="plan"
    CURRENT_PHASE_INDEX=0
    CURRENT_PHASE_ATTEMPT=1
    PHASE_ATTEMPT_IN_PROGRESS="false"
    ITERATION_COUNT=0
    SESSION_ID=""
    SESSION_ATTEMPT_COUNT=0
    SESSION_TOKEN_COUNT=0
    SESSION_COST_CENTS=0
    LAST_RUN_TOKEN_COUNT=0
    ENGINE_OUTPUT_TO_STDOUT="$DEFAULT_ENGINE_OUTPUT_TO_STDOUT"
    PHASE_TRANSITION_HISTORY=()
    PLAN_FRESHNESS_FINGERPRINT=""
    LAST_GATE_DECISION_RECORDED_AT=""
    LAST_GATE_DECISION_PHASE=""
    LAST_GATE_DECISION_ATTEMPT=0
    LAST_GATE_DECISION_STAGE=""
    LAST_GATE_DECISION_OUTCOME=""
    LAST_GATE_DECISION_SCORE=0
    LAST_GATE_DECISION_PASS=false
    LAST_GATE_DECISION_RESPONDED_VOTES=0
    LAST_GATE_DECISION_NEXT_PHASE=""
    LAST_GATE_DECISION_SUMMARY=""
    GIT_IDENTITY_READY="unknown"
    GIT_IDENTITY_SOURCE="unknown"
    local phase_transition_history_b64=""

    ensure_runtime_file "$STATE_FILE" || return 1
    local expected actual state_body_file checksum_count
    checksum_count="$(grep -c '^STATE_CHECKSUM=' "$STATE_FILE" || true)"
    [ "$checksum_count" = 1 ] || { err 'Saved state requires exactly one checksum; restore it or explicitly start with --no-resume.'; return 1; }
    expected="$(sed -n 's/^STATE_CHECKSUM="\([0-9a-f][0-9a-f]*\)"$/\1/p' "$STATE_FILE")"
    [ "${#expected}" -eq 64 ] || { err 'Saved state checksum is malformed.'; return 1; }
    state_body_file="$(mktemp "$CONFIG_DIR/state-body.XXXXXX")" || return 1
    if ! grep -v '^STATE_CHECKSUM=' "$STATE_FILE" > "$state_body_file" \
        || ! actual="$(sha256_file_sum "$state_body_file")"; then
        rm -f "$state_body_file"
        err 'Unable to validate saved state; refusing to reset mission counters.'
        return 1
    fi
    rm -f "$state_body_file"
    if [ "$expected" != "$actual" ]; then
        err 'State file checksum mismatch; restore it or explicitly start with --no-resume.'
        log_reason_code RB_STATE_CORRUPTION 'checksum mismatch in state file'
        return 1
    fi

    while IFS='=' read -r key value; do
        [ -z "$key" ] && continue
        value="${value%\"}"
        value="${value#\"}"
        # Keep decoded final newlines: command substitution strips them when
        # the decoded value itself is the last output byte.
        value="$(state_unescape_value "$value"; printf '.')"
        value="${value%.}"
        case "$key" in
            CURRENT_PHASE_INDEX|CURRENT_PHASE_ATTEMPT|ITERATION_COUNT|SESSION_ATTEMPT_COUNT|SESSION_TOKEN_COUNT|SESSION_COST_CENTS|LAST_RUN_TOKEN_COUNT|LAST_GATE_DECISION_ATTEMPT|LAST_GATE_DECISION_SCORE|LAST_GATE_DECISION_RESPONDED_VOTES)
                if ! value="$(normalize_non_negative_decimal "$value")"; then
                    err "Saved state has an invalid $key; restore it or explicitly start with --no-resume."
                    return 1
                fi
                ;;
        esac
        case "$key" in
            MISSION_SEED_SHA) MISSION_SEED_SHA="$value" ;;
            REQUEST_REVIEWED_FINGERPRINT)
                if [ -n "$value" ] && { [ "${#value}" -ne 64 ] || [[ "$value" == *[!0-9a-f]* ]]; }; then
                    err 'Saved human-request generation is invalid.'
                    return 1
                fi
                REQUEST_REVIEWED_FINGERPRINT="$value"
                ;;
            OWNED_PATHS_SHA) OWNED_PATHS_SHA="$value" ;;
            SHELL_GATES_FINGERPRINT) SHELL_GATES_FINGERPRINT="$value" ;;
            SHELL_LOCAL_WORK_SEEN) SHELL_LOCAL_WORK_SEEN="$value" ;;
            SHELL_DEVELOPMENT_PHASE_STARTED) SHELL_DEVELOPMENT_PHASE_STARTED="$value" ;;
            SESSION_INITIAL_HEAD) SESSION_INITIAL_HEAD="$value" ;;
            CURRENT_PHASE) CURRENT_PHASE="$value" ;;
            CURRENT_PHASE_INDEX) is_number "$value" && CURRENT_PHASE_INDEX="$value" ;;
            CURRENT_PHASE_ATTEMPT) is_number "$value" && CURRENT_PHASE_ATTEMPT="$value" ;;
            PHASE_ATTEMPT_IN_PROGRESS) is_bool_like "$value" && PHASE_ATTEMPT_IN_PROGRESS="$value" ;;
            ITERATION_COUNT) is_number "$value" && ITERATION_COUNT="$value" ;;
            SESSION_ID) SESSION_ID="$value" ;;
            SESSION_ATTEMPT_COUNT) is_number "$value" && SESSION_ATTEMPT_COUNT="$value" ;;
            SESSION_TOKEN_COUNT) is_number "$value" && SESSION_TOKEN_COUNT="$value" ;;
            SESSION_COST_CENTS) is_number "$value" && SESSION_COST_CENTS="$value" ;;
            LAST_RUN_TOKEN_COUNT) is_number "$value" && LAST_RUN_TOKEN_COUNT="$value" ;;
            ENGINE_OUTPUT_TO_STDOUT) [ -n "$value" ] && ENGINE_OUTPUT_TO_STDOUT="$value" ;;
            PHASE_TRANSITION_HISTORY_B64) phase_transition_history_b64="$value" ;;
            PLAN_FRESHNESS_FINGERPRINT) PLAN_FRESHNESS_FINGERPRINT="$value" ;;
            GIT_IDENTITY_READY) is_bool_like "$value" && GIT_IDENTITY_READY="$value" ;;
            GIT_IDENTITY_SOURCE) [ -n "$value" ] && GIT_IDENTITY_SOURCE="$value" ;;
            LAST_GATE_DECISION_RECORDED_AT) LAST_GATE_DECISION_RECORDED_AT="$value" ;;
            LAST_GATE_DECISION_PHASE) LAST_GATE_DECISION_PHASE="$value" ;;
            LAST_GATE_DECISION_ATTEMPT) is_number "$value" && LAST_GATE_DECISION_ATTEMPT="$value" ;;
            LAST_GATE_DECISION_STAGE) LAST_GATE_DECISION_STAGE="$value" ;;
            LAST_GATE_DECISION_OUTCOME) LAST_GATE_DECISION_OUTCOME="$value" ;;
            LAST_GATE_DECISION_SCORE) is_number "$value" && LAST_GATE_DECISION_SCORE="$value" ;;
            LAST_GATE_DECISION_PASS) is_bool_like "$value" && LAST_GATE_DECISION_PASS="$value" ;;
            LAST_GATE_DECISION_RESPONDED_VOTES) is_number "$value" && LAST_GATE_DECISION_RESPONDED_VOTES="$value" ;;
            LAST_GATE_DECISION_NEXT_PHASE) LAST_GATE_DECISION_NEXT_PHASE="$value" ;;
            LAST_GATE_DECISION_SUMMARY) LAST_GATE_DECISION_SUMMARY="$value" ;;
            STATE_CHECKSUM) ;;
            *) ;;
        esac
    done < "$STATE_FILE"

    if ! is_number "$CURRENT_PHASE_INDEX"; then
        CURRENT_PHASE_INDEX=0
    fi
    CURRENT_PHASE="$(normalize_phase_name "$CURRENT_PHASE")"
    local derived_phase_index
    derived_phase_index="$(phase_index_or_done "$CURRENT_PHASE" 2>/dev/null || echo 0)"
    if is_number "$derived_phase_index" && [ "$derived_phase_index" -ge 0 ] && [ "$derived_phase_index" -ne "$CURRENT_PHASE_INDEX" ]; then
        warn "Persisted state mismatch: CURRENT_PHASE='$CURRENT_PHASE' but CURRENT_PHASE_INDEX='$CURRENT_PHASE_INDEX'. Correcting index to '$derived_phase_index'."
        CURRENT_PHASE_INDEX="$derived_phase_index"
    fi
    if ! is_number "$CURRENT_PHASE_ATTEMPT" || [ "$CURRENT_PHASE_ATTEMPT" -lt 1 ]; then
        CURRENT_PHASE_ATTEMPT=1
    fi
    if ! is_bool_like "$PHASE_ATTEMPT_IN_PROGRESS"; then
        PHASE_ATTEMPT_IN_PROGRESS="false"
    fi
    if [ -n "$phase_transition_history_b64" ]; then
        local decoded_phase_history
        decoded_phase_history="$(state_blob_decode "$phase_transition_history_b64" 2>/dev/null || true)"
        if [ -n "$decoded_phase_history" ]; then
            mapfile -t PHASE_TRANSITION_HISTORY <<< "$decoded_phase_history"
        else
            PHASE_TRANSITION_HISTORY=()
            warn "Phase transition history could not be decoded from persisted state."
        fi
    fi
    return 0
}

estimate_file_token_count() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo 0
        return 0
    fi

    local bytes
    bytes="$(wc -c < "$file" 2>/dev/null | tr -d ' ' || echo 0)"
    if ! is_number "$bytes"; then
        echo 0
        return 0
    fi
    bytes="$(normalize_non_negative_decimal "$bytes")" || return 1
    echo $((bytes / 4 + (bytes % 4 != 0)))
}

estimate_run_tokens() {
    local prompt_file="$1"
    local log_file="$2"
    local output_file="$3"

    local tokens
    local prompt_tokens
    local log_tokens
    local output_tokens
    prompt_tokens="$(estimate_file_token_count "$prompt_file")"
    log_tokens="$(estimate_file_token_count "$log_file")"
    output_tokens="$(estimate_file_token_count "$output_file")"
    tokens="$(checked_decimal_add "$prompt_tokens" "$log_tokens")" || return 1
    checked_decimal_add "$tokens" "$output_tokens"
}

reject_engine_budget_accounting() {
    ENGINE_BUDGET_EXHAUSTED=true
    ENGINE_BUDGET_FAILURE_REASON="${1:-Inference accounting is invalid or exceeds supported integer range.}"
    err "$ENGINE_BUDGET_FAILURE_REASON"
    return 75
}

charge_session_budget() {
    local tokens next_tokens next_cost product run_cost=0
    tokens="$(normalize_non_negative_decimal "${1:-}")" || { reject_engine_budget_accounting; return 75; }
    validate_engine_budget_settings || { reject_engine_budget_accounting; return 75; }
    next_tokens="$(checked_decimal_add "$SESSION_TOKEN_COUNT" "$tokens")" || { reject_engine_budget_accounting; return 75; }
    if [ "$SESSION_TOKEN_RATE_CENTS_PER_MILLION" -gt 0 ]; then
        if [ "$tokens" -gt "$((9223372036854775807 / SESSION_TOKEN_RATE_CENTS_PER_MILLION))" ]; then
            reject_engine_budget_accounting 'Estimated inference cost exceeds supported integer range.'
            return 75
        fi
        product=$((tokens * SESSION_TOKEN_RATE_CENTS_PER_MILLION))
        run_cost=$((product / 1000000))
        # Round each request upward: small calls must not disappear from a cap.
        [ "$((product % 1000000))" -eq 0 ] || run_cost=$((run_cost + 1))
    fi
    next_cost="$(checked_decimal_add "$SESSION_COST_CENTS" "$run_cost")" || { reject_engine_budget_accounting; return 75; }
    SESSION_TOKEN_COUNT="$next_tokens"
    SESSION_COST_CENTS="$next_cost"
    LAST_RUN_TOKEN_COUNT="$tokens"
    write_session_budget_receipt
}

enforce_session_budget() {
    local reason_prefix="${1:-run}"
    local reason_code=""
    local reason="" name
    validate_engine_budget_settings || { reject_engine_budget_accounting; return 1; }
    for name in SESSION_ATTEMPT_COUNT SESSION_TOKEN_COUNT SESSION_COST_CENTS; do
        normalize_integer_setting "$name" 0 || { reject_engine_budget_accounting; return 1; }
    done
    if is_number "$MAX_SESSION_CYCLES" && [ "$MAX_SESSION_CYCLES" -gt 0 ] && [ "$SESSION_ATTEMPT_COUNT" -ge "$MAX_SESSION_CYCLES" ]; then
        reason_code=RB_SESSION_CYCLE_BUDGET_EXCEEDED
        reason="session cycle budget reached at $SESSION_ATTEMPT_COUNT/$MAX_SESSION_CYCLES attempts"
    elif is_number "$SESSION_TOKEN_BUDGET" && [ "$SESSION_TOKEN_BUDGET" -gt 0 ] && [ "$SESSION_TOKEN_COUNT" -ge "$SESSION_TOKEN_BUDGET" ]; then
        reason_code=RB_SESSION_TOKEN_BUDGET_EXCEEDED
        reason="session token budget reached at $SESSION_TOKEN_COUNT/$SESSION_TOKEN_BUDGET"
    elif is_number "$SESSION_COST_BUDGET_CENTS" && [ "$SESSION_COST_BUDGET_CENTS" -gt 0 ] && [ "$SESSION_COST_CENTS" -ge "$SESSION_COST_BUDGET_CENTS" ]; then
        reason_code=RB_SESSION_COST_BUDGET_EXCEEDED
        reason="session cost budget reached at $SESSION_COST_CENTS/$SESSION_COST_BUDGET_CENTS cents"
    fi
    if [ -n "$reason_code" ]; then
        ENGINE_BUDGET_EXHAUSTED=true
        ENGINE_BUDGET_FAILURE_REASON="$reason_prefix: $reason"
        log_reason_code "$reason_code" "$ENGINE_BUDGET_FAILURE_REASON"
        return 1
    fi
    return 0
}

finite_session_budget() {
    local limit
    for limit in "$MAX_SESSION_CYCLES" "$SESSION_TOKEN_BUDGET" "$SESSION_COST_BUDGET_CENTS"; do
        if is_number "$limit" && [ "$limit" -gt 0 ]; then return 0; fi
    done
    return 1
}

write_session_budget_receipt() {
    [ -n "${SESSION_BUDGET_RECEIPT_FILE:-}" ] || return 0
    if printf '%s %s %s\n' "$SESSION_ATTEMPT_COUNT" "$SESSION_TOKEN_COUNT" "$SESSION_COST_CENTS" > "$SESSION_BUDGET_RECEIPT_FILE.tmp" \
        && mv "$SESSION_BUDGET_RECEIPT_FILE.tmp" "$SESSION_BUDGET_RECEIPT_FILE"; then
        return 0
    fi
    ENGINE_BUDGET_EXHAUSTED=true
    ENGINE_BUDGET_FAILURE_REASON="Could not record inference budget usage."
    err "$ENGINE_BUDGET_FAILURE_REASON"
    return 1
}

admit_session_attempt() {
    if is_true "${ENGINE_BUDGET_EXHAUSTED:-false}"; then return 75; fi
    enforce_session_budget "${1:-inference admission}" || return 75
    # Count admission before launching so an interrupted call still consumes it.
    local next_attempt_count
    next_attempt_count="$(checked_decimal_add "$SESSION_ATTEMPT_COUNT" 1)" || { reject_engine_budget_accounting; return 75; }
    SESSION_ATTEMPT_COUNT="$next_attempt_count"
    write_session_budget_receipt || return 75
    if finite_session_budget && [ -z "${SESSION_BUDGET_RECEIPT_FILE:-}" ] && is_true "${RALPHIE_CLEANUP_STATE_ENABLED:-false}"; then
        # A killed parent cannot run cleanup. Persist finite admission before
        # inference so same-session resume cannot spend that allowance again.
        if ! save_state; then
            ENGINE_BUDGET_EXHAUSTED=true
            ENGINE_BUDGET_FAILURE_REASON="Could not checkpoint inference admission; no engine call was launched."
            err "$ENGINE_BUDGET_FAILURE_REASON"
            return 75
        fi
    fi
    return 0
}

import_swarm_session_budget() {
    [ -n "${SWARM_BUDGET_RECEIPT_DIR:-}" ] || return 0
    local attempts=0 tokens=0 cost=0 receipt a t c extra
    for receipt in "$SWARM_BUDGET_RECEIPT_DIR"/reviewer_*.usage; do
        [ -f "$receipt" ] || continue
        a=""; t=""; c=""; extra=""
        if ! IFS=' ' read -r a t c extra < "$receipt" || ! is_number "$a" || ! is_number "$t" || ! is_number "$c" || [ -n "$extra" ]; then
            ENGINE_BUDGET_EXHAUSTED=true
            ENGINE_BUDGET_FAILURE_REASON="Invalid reviewer inference usage receipt."
            err "$ENGINE_BUDGET_FAILURE_REASON"
            return 1
        fi
        attempts="$(checked_decimal_add "$attempts" "$a")" && tokens="$(checked_decimal_add "$tokens" "$t")" && cost="$(checked_decimal_add "$cost" "$c")" || { reject_engine_budget_accounting; return 1; }
    done
    # Re-importing while cleaning up must never charge a child twice.
    local next_attempts next_tokens next_cost
    next_attempts="$(checked_decimal_add "$SWARM_BUDGET_BASE_ATTEMPTS" "$attempts")" && next_tokens="$(checked_decimal_add "$SWARM_BUDGET_BASE_TOKENS" "$tokens")" && next_cost="$(checked_decimal_add "$SWARM_BUDGET_BASE_COST" "$cost")" || { reject_engine_budget_accounting; return 1; }
    SESSION_ATTEMPT_COUNT="$next_attempts"
    SESSION_TOKEN_COUNT="$next_tokens"
    SESSION_COST_CENTS="$next_cost"
    return 0
}

finish_swarm_session_budget() {
    import_swarm_session_budget || return 1
    if [ -n "${SWARM_BUDGET_RECEIPT_DIR:-}" ]; then
        rm -f -- "$SWARM_BUDGET_RECEIPT_DIR"/reviewer_*.usage "$SWARM_BUDGET_RECEIPT_DIR"/reviewer_*.usage.tmp
        rmdir "$SWARM_BUDGET_RECEIPT_DIR" || return 1
        SWARM_BUDGET_RECEIPT_DIR=""
    fi
    return 0
}

# Interactive Questions
is_tty_input_available() {
    is_true "${NO_TERMINAL_INPUT:-false}" && return 1
    if [ -t 0 ]; then
        return 0
    fi
    [ -e /dev/tty ] && { : < /dev/tty > /dev/tty; } 2>/dev/null
}

prompt_read_line() {
    local prompt="$1"
    local default="$2"
    local secret="${3:-false}"
    local response=""
    local -a read_options=(-r)

    if is_true "${NO_TERMINAL_INPUT:-false}"; then
        printf '%s\n' "$default"
        return 0
    fi
    if is_true "$secret"; then
        read_options+=(-s)
    elif [ "${TERM:-dumb}" != dumb ]; then
        read_options+=(-e)
    fi
    if is_tty_input_available; then
        if { exec 9<>/dev/tty; } 2>/dev/null; then
            # Bash 3.2 Readline ignores -u; redirect stdin so a piped script
            # remains untouched while editing reads the controlling terminal.
            if IFS= read "${read_options[@]}" -p "$prompt" response <&9 2>&9; then
                if is_true "$secret"; then printf '\n' >&9 || { exec 9>&- 9<&-; return 130; }; fi
                exec 9>&- 9<&-
                printf '%s\n' "${response:-$default}"
                return 0
            fi
            if is_true "$secret"; then printf '\n' >&9 || true; fi
            exec 9>&- 9<&-
        elif [ -t 0 ]; then
            if IFS= read "${read_options[@]}" -p "$prompt" response; then
                if is_true "$secret"; then printf '\n' >&2 || return 130; fi
                printf '%s\n' "${response:-$default}"
                return 0
            fi
            if is_true "$secret"; then printf '\n' >&2 || true; fi
        fi
    fi
    warn "Input closed; no default was accepted."
    return 130
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local response
    local default_marker="[Y/n]"

    case "$(to_lower "$default")" in
        n|no|false|0) default_marker="[y/N]" ;;
        *) default_marker="[Y/n]" ;;
    esac

    while true; do
        response="$(prompt_read_line "$prompt $default_marker: " "$default")" || return 130
        case "$(to_lower "$response")" in
            y|yes|true|on|1) printf '%s\n' true; return 0 ;;
            n|no|false|off|0) printf '%s\n' false; return 0 ;;
            *) warn "Please enter yes or no; Enter accepts the displayed default." ;;
        esac
    done
}

prompt_line() {
    local prompt="$1"
    local default="$2"
    prompt_read_line "$prompt [$default]: " "$default"
}

prompt_optional_line() {
    local prompt="$1"
    local default="${2:-}"
    if [ -n "$default" ]; then
        prompt_read_line "$prompt [$default]: " "$default"
    else
        prompt_read_line "$prompt [optional, Enter=skip]: " ""
    fi
}

prompt_multiline_block() {
    if is_true "${NO_TERMINAL_INPUT:-false}"; then printf '%s' "${2:-}"; return 0; fi
    local prompt="$1"
    local default="${2:-}"
    local sentinel="${3:-EOF}"
    local line=""
    local result=""
    local finished="false"

    if ! { exec 9<>/dev/tty; } 2>/dev/null; then
        warn "Input closed; goals paste cancelled."
        return 130
    fi

    {
        printf '%s\n' "$prompt"
        printf 'Paste multi-line input, then end with a line containing only %s (or press Ctrl+D).\n' "$sentinel"
        printf 'Press Enter immediately to keep current/default.\n'
        printf '> '
    } >&9

    while IFS= read -r -u 9 line; do
        if [ -z "$result" ] && [ -z "$line" ]; then
            exec 9>&- 9<&-
            printf '%s' "$default"
            return 0
        fi
        if [ "$line" = "$sentinel" ]; then
            finished="true"
            break
        fi
        result="${result}${result:+$'\n'}$line"
        printf '> ' >&9
    done
    exec 9>&- 9<&-

    if [ -z "$result" ]; then
        if is_true "$finished"; then
            printf '%s' "$default"
        else
            warn "Input closed; goals paste cancelled."
            return 130
        fi
    else
        printf '%s' "$result"
    fi
}

prompt_override_value() {
    local label="$1"
    local current="${2:-}"
    local secret="${3:-false}"
    local current_display="${current:-<default>}"
    local response=""

    if is_true "$secret"; then
        current_display="<unset>"
        [ -z "$current" ] || current_display="[configured]"
        response="$(prompt_read_line "$label [current: $current_display, Enter=keep, -=clear; input hidden]: " "" true)" || return 130
    else
        response="$(prompt_read_line "$label [current: $current_display, Enter=keep, -=clear]: " "")" || return 130
    fi
    if [ -z "$response" ]; then
        printf '%s\n' "$current"
        return 0
    fi
    if [ "$response" = "-" ]; then
        printf '\n'
        return 0
    fi
    printf '%s\n' "$response"
}

bootstrap_prompt_value() {
    local key="$1"
    [ -f "$PROJECT_BOOTSTRAP_FILE" ] || return 1
    awk -F': ' -v key="$key" '
        $1 == key {
            value=$0
            sub(/^"?"/, "", value)
            sub(/^"?[^:]+: /, "", value)
            sub(/"$/, "", value)
            print value
            exit
        }
    ' "$PROJECT_BOOTSTRAP_FILE"
}

bootstrap_required_text_value_is_set() {
    local value="${1:-}"
    local normalized=""

    normalized="$(sanitize_text_for_log "$value")"
    [ -n "$normalized" ] || return 1

    case "$(to_lower "$normalized")" in
        no\ explicit*|unspecified*|none|none\ stated|na|n/a|-)
            return 1
            ;;
    esac
    return 0
}

bootstrap_text_value_is_present() {
    local value="${1:-}"
    local normalized=""
    normalized="$(sanitize_text_for_log "$value")"
    [ -n "$normalized" ]
}

bootstrap_schema_missing_fields_from_values() {
    local project_type="${1:-}"
    local objective="${2:-}"
    local constraints="${3:-}"
    local success_criteria="${4:-}"
    local build_consent="${5:-}"
    local architecture_shape="${6:-}"
    local technology_choices="${7:-}"
    local interactive_prompted="${8:-}"
    local strict_mode="${9:-false}"

    case "$project_type" in
        new|existing) ;;
        *) echo "project_type" ;;
    esac

    if is_true "$strict_mode"; then
        bootstrap_required_text_value_is_set "$objective" || echo "objective"
        bootstrap_required_text_value_is_set "$constraints" || echo "constraints"
        bootstrap_required_text_value_is_set "$success_criteria" || echo "success_criteria"
        bootstrap_required_text_value_is_set "$architecture_shape" || echo "architecture_shape"
        bootstrap_required_text_value_is_set "$technology_choices" || echo "technology_choices"
    else
        bootstrap_text_value_is_present "$objective" || echo "objective"
        bootstrap_text_value_is_present "$constraints" || echo "constraints"
        bootstrap_text_value_is_present "$success_criteria" || echo "success_criteria"
        bootstrap_text_value_is_present "$architecture_shape" || echo "architecture_shape"
        bootstrap_text_value_is_present "$technology_choices" || echo "technology_choices"
    fi
    is_bool_like "$build_consent" || echo "build_consent"

    if [ -n "$interactive_prompted" ]; then
        is_bool_like "$interactive_prompted" || echo "interactive_prompted"
    fi
}

bootstrap_schema_missing_fields_from_file() {
    local strict_mode="${1:-false}"
    local project_type objective constraints success_criteria build_consent architecture_shape technology_choices interactive_prompted

    project_type="$(bootstrap_prompt_value "project_type" 2>/dev/null || true)"
    objective="$(bootstrap_prompt_value "objective" 2>/dev/null || true)"
    constraints="$(bootstrap_prompt_value "constraints" 2>/dev/null || true)"
    success_criteria="$(bootstrap_prompt_value "success_criteria" 2>/dev/null || true)"
    build_consent="$(bootstrap_prompt_value "build_consent" 2>/dev/null || true)"
    architecture_shape="$(bootstrap_prompt_value "architecture_shape" 2>/dev/null || true)"
    technology_choices="$(bootstrap_prompt_value "technology_choices" 2>/dev/null || true)"
    interactive_prompted="$(bootstrap_prompt_value "interactive_prompted" 2>/dev/null || true)"

    bootstrap_schema_missing_fields_from_values \
        "$project_type" \
        "$objective" \
        "$constraints" \
        "$success_criteria" \
        "$build_consent" \
        "$architecture_shape" \
        "$technology_choices" \
        "$interactive_prompted" \
        "$strict_mode"
}

bootstrap_alignment_state_fingerprint() {
    local project_type="${1:-}"
    local objective="${2:-}"
    local constraints="${3:-}"
    local success_criteria="${4:-}"
    local build_consent="${5:-}"
    local architecture_shape="${6:-}"
    local technology_choices="${7:-}"
    local goals_text="${8:-}"
    local payload checksum

    payload="$(
        cat <<EOF
project_type=$project_type
objective=$objective
constraints=$constraints
success_criteria=$success_criteria
build_consent=$build_consent
architecture_shape=$architecture_shape
technology_choices=$technology_choices
goals_text=$goals_text
EOF
    )"

    if checksum="$(printf '%s' "$payload" | sha256_stream_sum 2>/dev/null)"; then
        printf '%s' "$checksum"
        return 0
    fi

    printf '%s' "$(bootstrap_dense_token "$payload" "state" 96)"
}

bootstrap_clamp_percent() {
    local value="${1:-0}"
    if ! is_number "$value"; then
        echo 0
        return 0
    fi
    if [ "$value" -lt 0 ]; then
        echo 0
        return 0
    fi
    if [ "$value" -gt 100 ]; then
        echo 100
        return 0
    fi
    echo "$value"
}

bootstrap_context_is_valid() {
    local interactive_prompted=""
    local strict_mode="false"
    local -a missing_fields=()

    interactive_prompted="$(bootstrap_prompt_value "interactive_prompted" 2>/dev/null || true)"
    if is_true "$interactive_prompted"; then
        strict_mode="true"
    fi

    mapfile -t missing_fields < <(bootstrap_schema_missing_fields_from_file "$strict_mode")
    [ "${#missing_fields[@]}" -eq 0 ]
}

write_bootstrap_context_file() {
    local project_type="$1"
    local objective="$2"
    local build_consent="$3"
    local interactive_source="$4"
    local constraints="${5:-No explicit constraints provided.}"
    local success_criteria="${6:-All required phase gates pass and deliverables match project objectives.}"
    local goals_doc_present="${7:-false}"
    local goals_doc_url="${8:-}"
    local architecture_shape="${9:-No explicit structure preference provided.}"
    local technology_choices="${10:-No explicit technology preference provided.}"
    ensure_runtime_file "$PROJECT_BOOTSTRAP_FILE" || return 1
    ensure_runtime_directory "$(dirname "$PROJECT_BOOTSTRAP_FILE")" || return 1

    cat > "$PROJECT_BOOTSTRAP_FILE" <<EOF
# Ralphie Project Bootstrap
project_type: $project_type
build_consent: $build_consent
objective: $objective
constraints: $constraints
success_criteria: $success_criteria
architecture_shape: $architecture_shape
technology_choices: $technology_choices
goals_document_present: $goals_doc_present
goals_document_url: $goals_doc_url
interactive_prompted: $interactive_source
captured_at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
EOF
}

write_project_goals_file() {
    local goals_text="${1:-}"
    ensure_runtime_file "$PROJECT_GOALS_FILE" || return 1
    if [ -z "$goals_text" ]; then
        rm -f "$PROJECT_GOALS_FILE" 2>/dev/null || true
        return 0
    fi

    ensure_runtime_directory "$(dirname "$PROJECT_GOALS_FILE")" || return 1
    cat > "$PROJECT_GOALS_FILE" <<EOF
# Project Goals Document

$goals_text
EOF
}

bootstrap_dense_token() {
    local raw_value="${1:-}"
    local fallback="${2:-na}"
    local max_len="${3:-42}"
    local value=""

    if ! is_number "$max_len" || [ "$max_len" -lt 8 ]; then
        max_len=42
    fi

    value="$(sanitize_text_for_log "$raw_value")"
    [ -n "$value" ] || value="$fallback"
    value="$(printf '%s' "$value" | sed 's/[[:space:]][[:space:]]*/_/g')"
    if [ "${#value}" -gt "$max_len" ]; then
        value="${value:0:$max_len}"
    fi
    printf '%s' "$value"
}

bootstrap_dense_reflection_line() {
    local project_type="${1:-existing}"
    local objective="${2:-}"
    local constraints="${3:-}"
    local success_criteria="${4:-}"
    local build_consent="${5:-true}"
    local architecture_shape="${6:-}"
    local technology_choices="${7:-}"
    local build_mode="mb"

    if is_true "$build_consent"; then
        build_mode="ab"
    fi

    printf 'g=%s|tp=%s|ok=%s|ng=%s|ar=%s|st=%s|b=%s' \
        "$(bootstrap_dense_token "$objective" "unspecified_goal" 64)" \
        "$(bootstrap_dense_token "$project_type" "existing" 12)" \
        "$(bootstrap_dense_token "$success_criteria" "unspecified_done" 56)" \
        "$(bootstrap_dense_token "$constraints" "none" 52)" \
        "$(bootstrap_dense_token "$architecture_shape" "unspecified_arch" 42)" \
        "$(bootstrap_dense_token "$technology_choices" "unspecified_tech" 42)" \
        "$build_mode"
}

bootstrap_persona_assessment_lines() {
    local project_type="${1:-existing}"
    local objective="${2:-}"
    local constraints="${3:-}"
    local success_criteria="${4:-}"
    local build_consent="${5:-true}"
    local architecture_shape="${6:-}"
    local technology_choices="${7:-}"
    local -a missing_fields=()
    local missing_count=0
    local missing_csv="none"
    local obj_token constr_token success_token
    local obj_len constr_len success_len
    local base_risk=20
    local has_missing_objective=false
    local has_missing_constraints=false
    local has_missing_success=false
    local has_missing_arch=false
    local has_missing_tech=false
    local missing_objective_weight=0
    local missing_constraints_weight=0
    local missing_success_weight=0
    local missing_arch_weight=0
    local missing_tech_weight=0
    local field
    local common_unknowns="none"

    mapfile -t missing_fields < <(
        bootstrap_schema_missing_fields_from_values \
            "$project_type" \
            "$objective" \
            "$constraints" \
            "$success_criteria" \
            "$build_consent" \
            "$architecture_shape" \
            "$technology_choices" \
            "" \
            "true"
    )
    missing_count="${#missing_fields[@]}"
    if [ "$missing_count" -gt 0 ]; then
        missing_csv=""
        for field in "${missing_fields[@]}"; do
            [ -n "$field" ] || continue
            missing_csv="${missing_csv}${missing_csv:+,}${field}"
        done
        [ -n "$missing_csv" ] || missing_csv="none"
    fi

    case ",$missing_csv," in *",objective,"*) has_missing_objective=true ;; esac
    case ",$missing_csv," in *",constraints,"*) has_missing_constraints=true ;; esac
    case ",$missing_csv," in *",success_criteria,"*) has_missing_success=true ;; esac
    case ",$missing_csv," in *",architecture_shape,"*) has_missing_arch=true ;; esac
    case ",$missing_csv," in *",technology_choices,"*) has_missing_tech=true ;; esac
    [ "$has_missing_objective" = "true" ] && missing_objective_weight=1
    [ "$has_missing_constraints" = "true" ] && missing_constraints_weight=1
    [ "$has_missing_success" = "true" ] && missing_success_weight=1
    [ "$has_missing_arch" = "true" ] && missing_arch_weight=1
    [ "$has_missing_tech" = "true" ] && missing_tech_weight=1

    obj_token="$(bootstrap_dense_token "$objective" "unspecified_goal" 42)"
    constr_token="$(bootstrap_dense_token "$constraints" "none" 34)"
    success_token="$(bootstrap_dense_token "$success_criteria" "unspecified_done" 38)"
    obj_len="${#obj_token}"
    constr_len="${#constr_token}"
    success_len="${#success_token}"

    [ "$obj_len" -lt 20 ] && base_risk=$((base_risk + 12))
    [ "$constr_len" -lt 16 ] && base_risk=$((base_risk + 10))
    [ "$success_len" -lt 16 ] && base_risk=$((base_risk + 10))
    base_risk=$((base_risk + missing_count * 12))
    if ! is_true "$build_consent"; then
        base_risk=$((base_risk + 5))
    fi

    if [ "$missing_count" -gt 0 ]; then
        common_unknowns="missing:${missing_csv}"
    elif [ "$obj_len" -lt 20 ]; then
        common_unknowns="objective_too_brief"
    fi

    bootstrap_emit_persona_assessment() {
        local persona="$1"
        local risk="$2"
        local focus="$3"
        local confidence blocking recommendation unknowns

        risk="$(bootstrap_clamp_percent "$risk")"
        confidence="$(bootstrap_clamp_percent "$((100 - risk))")"
        blocking="false"
        if [ "$risk" -ge 80 ] || [ "$missing_count" -gt 0 ]; then
            blocking="true"
        fi
        recommendation="proceed"
        [ "$blocking" = "true" ] && recommendation="revise"
        unknowns="$(bootstrap_dense_token "$common_unknowns" "none" 60)"

        printf '%s\n' "persona=${persona}|risk=${risk}|confidence=${confidence}|blocking=${blocking}|unknowns=${unknowns}|recommendation=${recommendation}|focus=${focus}"
    }

    bootstrap_emit_persona_assessment "Architect" "$((base_risk + missing_arch_weight * 18))" "structure_scope_fit"
    bootstrap_emit_persona_assessment "Skeptic" "$((base_risk + 12))" "ambiguity_risk_scan"
    bootstrap_emit_persona_assessment "Execution" "$((base_risk + missing_success_weight * 18 + missing_objective_weight * 10))" "deliverable_route"
    bootstrap_emit_persona_assessment "Safety" "$((base_risk + missing_constraints_weight * 16))" "guardrails_compliance"
    bootstrap_emit_persona_assessment "Operations" "$((base_risk + missing_arch_weight * 10 + missing_tech_weight * 12))" "rollback_runtime"
    bootstrap_emit_persona_assessment "Quality" "$((base_risk + missing_success_weight * 15 + missing_objective_weight * 12))" "acceptance_bar"
}

bootstrap_persona_field() {
    local line="${1:-}"
    local key="${2:-}"
    local default="${3:-}"
    local part
    local -a parts=()

    [ -n "$line" ] || { echo "$default"; return 0; }
    [ -n "$key" ] || { echo "$default"; return 0; }

    IFS='|' read -r -a parts <<< "$line"
    for part in "${parts[@]}"; do
        if [[ "$part" == "$key="* ]]; then
            echo "${part#*=}"
            return 0
        fi
    done
    echo "$default"
}

bootstrap_persona_display_line() {
    local assessment="${1:-}"
    local persona risk confidence blocking recommendation unknowns focus blocking_label

    persona="$(bootstrap_persona_field "$assessment" "persona" "Persona")"
    risk="$(bootstrap_persona_field "$assessment" "risk" "0")"
    confidence="$(bootstrap_persona_field "$assessment" "confidence" "0")"
    blocking="$(bootstrap_persona_field "$assessment" "blocking" "false")"
    recommendation="$(bootstrap_persona_field "$assessment" "recommendation" "proceed")"
    unknowns="$(bootstrap_persona_field "$assessment" "unknowns" "none")"
    focus="$(bootstrap_persona_field "$assessment" "focus" "none")"
    blocking_label="n"
    [ "$blocking" = "true" ] && blocking_label="y"

    printf '%s\n' "${persona}>r=${risk},c=${confidence},blk=${blocking_label},rec=${recommendation},unk=${unknowns},fx=${focus}" | cut -c 1-220
}

bootstrap_persona_blocking_names() {
    local assessment persona blocking
    for assessment in "$@"; do
        [ -n "$assessment" ] || continue
        persona="$(bootstrap_persona_field "$assessment" "persona" "")"
        blocking="$(bootstrap_persona_field "$assessment" "blocking" "false")"
        if [ "$blocking" = "true" ] && [ -n "$persona" ]; then
            echo "$persona"
        fi
    done
}

bootstrap_persona_feedback_lines() {
    local project_type="${1:-existing}"
    local objective="${2:-}"
    local constraints="${3:-}"
    local success_criteria="${4:-}"
    local build_consent="${5:-true}"
    local architecture_shape="${6:-}"
    local technology_choices="${7:-}"
    local assessment
    local -a assessments=()

    mapfile -t assessments < <(
        bootstrap_persona_assessment_lines \
            "$project_type" \
            "$objective" \
            "$constraints" \
            "$success_criteria" \
            "$build_consent" \
            "$architecture_shape" \
            "$technology_choices"
    )
    for assessment in "${assessments[@]}"; do
        [ -n "$assessment" ] || continue
        bootstrap_persona_display_line "$assessment"
    done
}

ensure_project_bootstrap() {
    local prompt_response
    local alignment_blocked=false
    local project_type objective build_consent interactive_source constraints success_criteria goals_text goals_doc_url architecture_shape technology_choices
    project_type="existing"
    objective="Improve project with a deterministic, evidence-first implementation path."
    build_consent="false"
    interactive_source="false"
    constraints="No explicit constraints provided."
    success_criteria="All required phase gates pass and deliverables match project objectives."
    goals_text=""
    goals_doc_url=""
    architecture_shape="No explicit structure preference provided."
    technology_choices="No explicit technology preference provided."

    ensure_runtime_directory "$(dirname "$PROJECT_BOOTSTRAP_FILE")" || return 1
    local existing_project_type=""
    local existing_objective=""
    local existing_build_consent=""
    local existing_interactive_prompted=""
    local existing_constraints=""
    local existing_success_criteria=""
    local existing_goals_doc_url=""
    local existing_architecture_shape=""
    local existing_technology_choices=""
    local needs_prompt="false"

    if [ -f "$PROJECT_BOOTSTRAP_FILE" ]; then
        existing_project_type="$(bootstrap_prompt_value "project_type" 2>/dev/null || true)"
        existing_objective="$(bootstrap_prompt_value "objective" 2>/dev/null || true)"
        existing_build_consent="$(bootstrap_prompt_value "build_consent" 2>/dev/null || true)"
        existing_interactive_prompted="$(bootstrap_prompt_value "interactive_prompted" 2>/dev/null || true)"
        existing_constraints="$(bootstrap_prompt_value "constraints" 2>/dev/null || true)"
        existing_success_criteria="$(bootstrap_prompt_value "success_criteria" 2>/dev/null || true)"
        existing_goals_doc_url="$(bootstrap_prompt_value "goals_document_url" 2>/dev/null || true)"
        existing_architecture_shape="$(bootstrap_prompt_value "architecture_shape" 2>/dev/null || true)"
        existing_technology_choices="$(bootstrap_prompt_value "technology_choices" 2>/dev/null || true)"

        if [ -n "$existing_project_type" ]; then
            project_type="$existing_project_type"
        fi
        if [ -n "$existing_objective" ]; then
            objective="$existing_objective"
        fi
        if [ -n "$existing_build_consent" ]; then
            build_consent="$existing_build_consent"
        fi
        if [ -n "$existing_constraints" ]; then
            constraints="$existing_constraints"
        fi
        if [ -n "$existing_success_criteria" ]; then
            success_criteria="$existing_success_criteria"
        fi
        if [ -n "$existing_goals_doc_url" ]; then
            goals_doc_url="$existing_goals_doc_url"
        fi
        if [ -n "$existing_architecture_shape" ]; then
            architecture_shape="$existing_architecture_shape"
        fi
        if [ -n "$existing_technology_choices" ]; then
            technology_choices="$existing_technology_choices"
        fi
        if [ "$existing_interactive_prompted" = "true" ]; then
            interactive_source="true"
        fi
    fi
    if [ -f "$PROJECT_GOALS_FILE" ]; then
        goals_text="$(cat "$PROJECT_GOALS_FILE" 2>/dev/null || true)"
    fi

    if [ "$REBOOTSTRAP_REQUESTED" = true ] || [ ! -f "$PROJECT_BOOTSTRAP_FILE" ] || ! bootstrap_context_is_valid; then
        needs_prompt="true"
    fi

    if [ "$needs_prompt" = "true" ]; then
        if [ -f "$PROJECT_BOOTSTRAP_FILE" ] && ! bootstrap_context_is_valid; then
            warn "Existing project bootstrap file is invalid or incomplete. Rebuilding context."
        elif [ "$REBOOTSTRAP_REQUESTED" = true ]; then
            warn "Rebuilding project bootstrap context due to --rebootstrap request."
        fi
    fi

    if is_true "$needs_prompt" && is_tty_input_available; then
        interactive_source="true"
        if [ "$REBOOTSTRAP_REQUESTED" = true ] || ! bootstrap_context_is_valid || [ ! -f "$PROJECT_BOOTSTRAP_FILE" ]; then
            info "Project setup: Enter keeps the displayed value. Ctrl-D cancels without starting work."
            prompt_response="$(prompt_yes_no "Is this a new project (no established implementation yet)?" "n")" || return 130
            if [ "$prompt_response" = "true" ]; then
                project_type="new"
            else
                project_type="existing"
            fi
            objective="$(prompt_optional_line "What is the primary objective for this session (single line)" "$objective")" || return 130
            constraints="$(prompt_optional_line "Key constraints or non-goals (single line, optional)" "$constraints")" || return 130
            success_criteria="$(prompt_optional_line "Success criteria / definition of done (single line, optional)" "$success_criteria")" || return 130
            goals_doc_url="$(prompt_optional_line "Project goals document URL (optional)" "$goals_doc_url")" || return 130

            prompt_response="$(prompt_yes_no "Paste a project goals document/URL block now?" "n")" || return 130
            if [ "$prompt_response" = "true" ]; then
                goals_text="$(prompt_multiline_block "Project goals/context input" "$goals_text" "EOF")" || return 130
            fi

            architecture_shape="$(prompt_optional_line "Preferred project structure / architecture (single line, optional)" "$architecture_shape")" || return 130
            technology_choices="$(prompt_optional_line "Preferred technology choices (single line, optional)" "$technology_choices")" || return 130

            prompt_response="$(prompt_yes_no "Proceed automatically from PLAN -> BUILD when all gates pass" "y")" || return 130
            if [ "$prompt_response" = "true" ]; then
                build_consent="true"
            else
                build_consent="false"
            fi

            local alignment_round=0
            local alignment_max_rounds=12
            local no_change_rounds=0

            while true; do
                local alignment_action modify_target extra_context
                local schema_field needs_arch_clarifier needs_tech_clarifier
                local round_state_before round_state_after
                local persona_assessment persona_display
                local -a schema_missing_fields=()
                local -a persona_assessments=()
                local -a blocking_personas=()
                alignment_round=$((alignment_round + 1))
                round_state_before="$(bootstrap_alignment_state_fingerprint "$project_type" "$objective" "$constraints" "$success_criteria" "$build_consent" "$architecture_shape" "$technology_choices" "$goals_text")"

                mapfile -t schema_missing_fields < <(
                    bootstrap_schema_missing_fields_from_values \
                        "$project_type" \
                        "$objective" \
                        "$constraints" \
                        "$success_criteria" \
                        "$build_consent" \
                        "$architecture_shape" \
                        "$technology_choices" \
                        "" \
                        "true"
                )
                mapfile -t persona_assessments < <(
                    bootstrap_persona_assessment_lines \
                        "$project_type" \
                        "$objective" \
                        "$constraints" \
                        "$success_criteria" \
                        "$build_consent" \
                        "$architecture_shape" \
                        "$technology_choices"
                )
                mapfile -t blocking_personas < <(bootstrap_persona_blocking_names "${persona_assessments[@]+"${persona_assessments[@]}"}")

                info "Bootstrap alignment reflection (ultra concise):"
                info "  $(bootstrap_dense_reflection_line "$project_type" "$objective" "$constraints" "$success_criteria" "$build_consent" "$architecture_shape" "$technology_choices")"
                info "Persona inputs (dense):"
                for persona_assessment in "${persona_assessments[@]}"; do
                    [ -n "$persona_assessment" ] || continue
                    persona_display="$(bootstrap_persona_display_line "$persona_assessment")"
                    [ -n "$persona_display" ] && info "  - $persona_display"
                done
                if [ "${#schema_missing_fields[@]}" -gt 0 ]; then
                    info "Schema gaps: $(join_with_commas "${schema_missing_fields[@]+"${schema_missing_fields[@]}"}")"
                fi
                if [ "${#blocking_personas[@]}" -gt 0 ]; then
                    info "Persona blockers: $(join_with_commas "${blocking_personas[@]+"${blocking_personas[@]}"}")"
                fi

                alignment_action="$(prompt_read_line "Alignment action [a=accept,m=modify,r=rerun,d=dismiss] (round ${alignment_round}/${alignment_max_rounds}): " "a")" || return 130
                alignment_action="$(to_lower "$alignment_action")"
                case "$alignment_action" in
                    a|accept|ok|yes|y|"")
                        if [ "${#schema_missing_fields[@]}" -gt 0 ] || [ "${#blocking_personas[@]}" -gt 0 ]; then
                            warn "Accept blocked: missing fields=$(join_with_commas "${schema_missing_fields[@]+"${schema_missing_fields[@]}"}"), blockers=$(join_with_commas "${blocking_personas[@]+"${blocking_personas[@]}"}")."
                            info "Focused clarifiers required before accept:"
                            objective="$(prompt_optional_line "Clarify primary user/workflow (single line)" "$objective")" || return 130
                            constraints="$(prompt_optional_line "Clarify highest risk/non-goal (single line)" "$constraints")" || return 130
                            success_criteria="$(prompt_optional_line "Clarify measurable done signal (single line)" "$success_criteria")" || return 130
                            needs_arch_clarifier="false"
                            needs_tech_clarifier="false"
                            for schema_field in "${schema_missing_fields[@]}"; do
                                case "$schema_field" in
                                    architecture_shape) needs_arch_clarifier="true" ;;
                                    technology_choices) needs_tech_clarifier="true" ;;
                                    *) ;;
                                esac
                            done
                            if [ "$needs_arch_clarifier" = "true" ]; then
                                architecture_shape="$(prompt_optional_line "Clarify target structure/architecture (single line)" "$architecture_shape")" || return 130
                            fi
                            if [ "$needs_tech_clarifier" = "true" ]; then
                                technology_choices="$(prompt_optional_line "Clarify target technology choices (single line)" "$technology_choices")" || return 130
                            fi
                        fi
                        [ "${#schema_missing_fields[@]}" -eq 0 ] && [ "${#blocking_personas[@]}" -eq 0 ] && break
                        ;;
                    d|dismiss|skip|good_enough)
                        info "Alignment loop dismissed as good enough."
                        break
                        ;;
                    r|rerun|again|loop)
                        extra_context="$(prompt_optional_line "Add or correct context before rerun (optional)" "")" || return 130
                        if [ -n "$extra_context" ]; then
                            goals_text="${goals_text}${goals_text:+$'\n'}$extra_context"
                        fi
                        ;;
                    m|modify|edit)
                        modify_target="$(prompt_read_line "Modify field [goal|constraints|success|arch|tech|goals|type|build|all]: " "goal")" || return 130
                        modify_target="$(to_lower "$modify_target")"
                        case "$modify_target" in
                            goal|objective)
                                objective="$(prompt_optional_line "Primary objective (single line)" "$objective")" || return 130
                                ;;
                            constraints|constraint|non-goals|nongoals)
                                constraints="$(prompt_optional_line "Constraints or non-goals (single line)" "$constraints")" || return 130
                                ;;
                            success|done|criteria|success_criteria)
                                success_criteria="$(prompt_optional_line "Success criteria / done (single line)" "$success_criteria")" || return 130
                                ;;
                            arch|architecture|structure)
                                architecture_shape="$(prompt_optional_line "Project structure / architecture (single line)" "$architecture_shape")" || return 130
                                ;;
                            tech|stack|technology|technology_choices)
                                technology_choices="$(prompt_optional_line "Technology choices (single line)" "$technology_choices")" || return 130
                                ;;
                            goals|goals_doc|goals_document)
                                goals_text="$(prompt_multiline_block "Project goals/context input" "$goals_text" "EOF")" || return 130
                                ;;
                            type|project_type)
                                prompt_response="$(prompt_yes_no "Is this a new project (no established implementation yet)?" "$( [ "$project_type" = "new" ] && echo y || echo n )")" || return 130
                                if [ "$prompt_response" = "true" ]; then
                                    project_type="new"
                                else
                                    project_type="existing"
                                fi
                                ;;
                            build|build_consent|autobuild)
                                prompt_response="$(prompt_yes_no "Proceed automatically from PLAN -> BUILD when all gates pass" "$(is_true "$build_consent" && echo y || echo n)")" || return 130
                                if [ "$prompt_response" = "true" ]; then
                                    build_consent="true"
                                else
                                    build_consent="false"
                                fi
                                ;;
                            all)
                                prompt_response="$(prompt_yes_no "Is this a new project (no established implementation yet)?" "$( [ "$project_type" = "new" ] && echo y || echo n )")" || return 130
                                if [ "$prompt_response" = "true" ]; then
                                    project_type="new"
                                else
                                    project_type="existing"
                                fi
                                objective="$(prompt_optional_line "Primary objective (single line)" "$objective")" || return 130
                                constraints="$(prompt_optional_line "Constraints or non-goals (single line)" "$constraints")" || return 130
                                success_criteria="$(prompt_optional_line "Success criteria / done (single line)" "$success_criteria")" || return 130
                                architecture_shape="$(prompt_optional_line "Project structure / architecture (single line)" "$architecture_shape")" || return 130
                                technology_choices="$(prompt_optional_line "Technology choices (single line)" "$technology_choices")" || return 130
                                goals_doc_url="$(prompt_optional_line "Project goals document URL (optional)" "$goals_doc_url")" || return 130
                                goals_text="$(prompt_multiline_block "Project goals/context input" "$goals_text" "EOF")" || return 130
                                prompt_response="$(prompt_yes_no "Proceed automatically from PLAN -> BUILD when all gates pass" "$(is_true "$build_consent" && echo y || echo n)")" || return 130
                                if [ "$prompt_response" = "true" ]; then
                                    build_consent="true"
                                else
                                    build_consent="false"
                                fi
                                ;;
                            *)
                                warn "Unknown field '$modify_target'."
                                ;;
                        esac
                        ;;
                    *)
                        warn "Unknown alignment action '$alignment_action'."
                        ;;
                esac

                round_state_after="$(bootstrap_alignment_state_fingerprint "$project_type" "$objective" "$constraints" "$success_criteria" "$build_consent" "$architecture_shape" "$technology_choices" "$goals_text")"
                if [ "$round_state_after" = "$round_state_before" ]; then
                    no_change_rounds=$((no_change_rounds + 1))
                else
                    no_change_rounds=0
                fi

                if [ "$alignment_round" -ge "$alignment_max_rounds" ] || [ "$no_change_rounds" -ge 2 ]; then
                    warn "Alignment paused after $alignment_round rounds without an accepted outcome."
                    build_consent="false"
                    alignment_blocked=true
                    break
                fi
            done
            info "Project bootstrap captured from interactive input."
        fi
    fi

    if ! is_true "$needs_prompt" && [ -f "$PROJECT_BOOTSTRAP_FILE" ] && is_tty_input_available; then
        info "Loaded existing project bootstrap context: $(path_for_display "$PROJECT_BOOTSTRAP_FILE")"
        info "   - project_type: $project_type"
        info "   - objective: $objective"
        info "   - build_consent: $build_consent"
        info "   - architecture_shape: $architecture_shape"
        info "   - technology_choices: $technology_choices"
        return 0
    fi

    if is_true "$needs_prompt" && ! is_tty_input_available; then
        info "Non-interactive bootstrap fallback retained: objective defaults were applied and build consent remains false."
    fi

    write_project_goals_file "$goals_text" || return 1
    write_bootstrap_context_file "$project_type" "$objective" "$build_consent" "$interactive_source" "$constraints" "$success_criteria" "$([ -s "$PROJECT_GOALS_FILE" ] && echo true || echo false)" "$goals_doc_url" "$architecture_shape" "$technology_choices" || return 1
    info "Captured project bootstrap context: $(path_for_display "$PROJECT_BOOTSTRAP_FILE")"
    if [ -s "$PROJECT_GOALS_FILE" ]; then
        info "Captured project goals document: $(path_for_display "$PROJECT_GOALS_FILE")"
    fi
    REBOOTSTRAP_REQUESTED=false
    if is_true "$alignment_blocked"; then
        err "Bootstrap context was saved with BUILD consent disabled. Run --rebootstrap to finish alignment."
        return 1
    fi
    return 0
}

append_bootstrap_context_to_plan_prompt() {
    local source_prompt="$1"
    local target_prompt="$2"
    ensure_runtime_file "$target_prompt" || return 1
    ensure_runtime_directory "$(dirname "$target_prompt")" || return 1
    local project_type objective build_consent constraints success_criteria goals_doc_url architecture_shape technology_choices

    if [ ! -f "$source_prompt" ]; then
        warn "Plan prompt source missing: $(path_for_display "$source_prompt")"
        return 1
    fi

    if [ ! -f "$PROJECT_BOOTSTRAP_FILE" ]; then
        cp "$source_prompt" "$target_prompt" 2>/dev/null || return 1
        return 0
    fi

    project_type="$(bootstrap_prompt_value "project_type")"
    objective="$(bootstrap_prompt_value "objective")"
    build_consent="$(bootstrap_prompt_value "build_consent")"
    constraints="$(bootstrap_prompt_value "constraints")"
    success_criteria="$(bootstrap_prompt_value "success_criteria")"
    goals_doc_url="$(bootstrap_prompt_value "goals_document_url")"
    architecture_shape="$(bootstrap_prompt_value "architecture_shape")"
    technology_choices="$(bootstrap_prompt_value "technology_choices")"

    cat > "$target_prompt" <<EOF
$(cat "$source_prompt")

## Project Bootstrap Context
- Project type: ${project_type:-existing}
- Objective: ${objective:-unspecified}
- Constraints / non-goals: ${constraints:-none stated}
- Success criteria: ${success_criteria:-none stated}
- Preferred architecture / structure: ${architecture_shape:-none stated}
- Preferred technology choices: ${technology_choices:-none stated}
- Goals document URL: ${goals_doc_url:-not provided}
- Build consent after plan: ${build_consent:-true}

EOF

    if [ -s "$PROJECT_GOALS_FILE" ]; then
        {
            echo "## Project Goals Document (User-Provided)"
            echo ""
            cat "$PROJECT_GOALS_FILE"
            echo ""
        } >> "$target_prompt"
    fi
}

append_bootstrap_context_to_phase_prompt() {
    append_bootstrap_context_to_plan_prompt "$@"
}

build_is_preapproved() {
    local consent
    consent="$(bootstrap_prompt_value "build_consent" 2>/dev/null)"
    [ "$consent" = "true" ]
}

healthy_engines_for_display() {
    local engines=""
    if [ "$PRIME_HEALTHY" = "true" ]; then
        engines="prime-agent"
    fi
    if [ "$CODEX_HEALTHY" = "true" ]; then
        engines="${engines}${engines:+, }codex"
    fi
    if [ "$CLAUDE_HEALTHY" = "true" ]; then
        engines="${engines}${engines:+, }claude"
    fi
    if [ -z "$engines" ]; then
        engines="none"
    fi
    printf '%s' "$engines"
}

notification_channels_for_display() {
    local channels=""
    if is_true "$NOTIFY_TELEGRAM_ENABLED"; then
        channels="telegram"
    fi
    if is_true "$NOTIFY_DISCORD_ENABLED"; then
        channels="${channels}${channels:+, }discord"
    fi
    if is_true "$NOTIFY_TTS_ENABLED"; then
        if is_true "$NOTIFY_TELEGRAM_ENABLED"; then
            channels="${channels/telegram/telegram+tts}"
        fi
        if is_true "$NOTIFY_DISCORD_ENABLED"; then
            channels="${channels/discord/discord+tts}"
        fi
    fi
    if [ -z "$channels" ]; then
        channels="none"
    fi
    printf '%s' "$channels"
}

notification_now_epoch() {
    local now
    now="$(date +%s 2>/dev/null || echo 0)"
    if ! is_number "$now"; then
        now=0
    fi
    printf '%s' "$now"
}

notification_event_is_high_signal() {
    case "${1:-}" in
        notification_setup|session_start|phase_decision|phase_complete|phase_blocked|session_done|session_error) return 0 ;;
        *) return 1 ;;
    esac
}

phase_attempt_limit_display() {
    local limit="${1:-0}"
    if ! is_number "$limit" || [ "$limit" -lt 0 ]; then
        echo "inf"
        return 0
    fi
    if [ "$limit" -eq 0 ]; then
        echo "inf"
        return 0
    fi
    echo "$limit"
}

phase_attempt_within_budget() {
    local attempt="$1"
    local limit="$2"
    if ! is_number "$attempt" || [ "$attempt" -lt 1 ]; then
        return 1
    fi
    if ! is_number "$limit" || [ "$limit" -lt 0 ] || [ "$limit" -eq 0 ]; then
        return 0
    fi
    [ "$attempt" -le "$limit" ]
}

phase_failure_signature() {
    local payload=""
    if [ "$#" -gt 0 ]; then
        payload="$(printf '%s\n' "$@")"
    fi
    if [ -z "$payload" ]; then
        echo "none"
        return 0
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$payload" | sha256sum | awk '{print $1}'
        return 0
    fi
    if command -v shasum >/dev/null 2>&1; then
        printf '%s' "$payload" | shasum -a 256 | awk '{print $1}'
        return 0
    fi
    printf '%s' "$payload" | wc -c | tr -d ' '
}

render_status_dashboard() {
    local phase="$1"
    local attempt="$2"
    local attempt_max="$3"
    local iter="$4"
    local max_iter_display
    local wallclock_display
    local cmd_timeout_display
    local consensus_to="$SWARM_CONSENSUS_TIMEOUT"

    max_iter_display="$MAX_ITERATIONS"
    [ "$MAX_ITERATIONS" -eq 0 ] && max_iter_display="inf"

    wallclock_display="${PHASE_WALLCLOCK_LIMIT_SECONDS:-0}"
    [ "$wallclock_display" -eq 0 ] && wallclock_display="inf"

    cmd_timeout_display="${COMMAND_TIMEOUT_SECONDS:-0}"
    [ "$cmd_timeout_display" -eq 0 ] && cmd_timeout_display="inf"

    printf '\n'
    printf '=== Ralphie Run Status ===\n'
    printf 'Phase: %s | Attempt: %s/%s | Iteration: %s/%s | Session: %s\n' \
        "$phase" "$attempt" "$(phase_attempt_limit_display "$attempt_max")" "$iter" "$max_iter_display" "$SESSION_ID"
    printf 'Engine (active/requested): %s (%s) | Consensus timeout: %ss | Phase wallclock: %ss | Cmd timeout: %ss\n' \
        "$ACTIVE_CMD" "$ACTIVE_ENGINE" "$consensus_to" "$wallclock_display" "$cmd_timeout_display"
    printf 'Idle output watchdog: %ss\n' "$(phase_attempt_limit_display "${ENGINE_IDLE_OUTPUT_TIMEOUT_SECONDS:-0}")"
    printf '%s\n' '---------------------------'
}

notification_reset_incident_series() {
    NOTIFY_INCIDENT_SERIES_ACTIVE="false"
    NOTIFY_INCIDENT_SERIES_KEY=""
    NOTIFY_INCIDENT_SERIES_STARTED_AT=0
    NOTIFY_INCIDENT_LAST_SENT_AT=0
    NOTIFY_INCIDENT_REPEAT_COUNT=0
}

notification_log_append() {
    local event="$1"
    local status="$2"
    local delivery="$3"
    local details="${4:-}"
    ensure_runtime_file "$NOTIFICATION_LOG_FILE" || return 1
    ensure_runtime_directory "$(dirname "$NOTIFICATION_LOG_FILE")" || return 1
    printf '%s\tevent=%s\tstatus=%s\tdelivery=%s\tdetails=%s\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        "$event" \
        "$status" \
        "$delivery" \
        "$(printf '%s' "$details" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g' | sed 's/^ *//; s/ *$//')" \
        >> "$NOTIFICATION_LOG_FILE"
}

send_telegram_message_raw() {
    local bot_token="$1"
    local chat_id="$2"
    local message="$3"
    local response=""

    [ -n "$bot_token" ] || return 1
    [ -n "$chat_id" ] || return 1
    command -v curl >/dev/null 2>&1 || return 1

    response="$(curl -sS -m 20 -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
        --data-urlencode "chat_id=${chat_id}" \
        --data-urlencode "text=${message}" 2>/dev/null || true)"
    printf '%s' "$response" | grep -q '"ok":[[:space:]]*true'
}

telegram_get_updates_raw() {
    local bot_token="$1"
    [ -n "$bot_token" ] || return 1
    command -v curl >/dev/null 2>&1 || return 1
    curl -sS -m 20 "https://api.telegram.org/bot${bot_token}/getUpdates" 2>/dev/null || return 1
}

telegram_extract_chat_ids_raw() {
    local payload="${1:-}"
    [ -n "$payload" ] || return 0

    printf '%s' "$payload" | tr -d '\n' | \
        grep -oE '"chat":[[:space:]]*\{[^}]*"id":[[:space:]]*-?[0-9]+' | \
        grep -oE -- '-?[0-9]+$' | awk '!seen[$0]++'
}

telegram_suggest_chat_id_raw() {
    local bot_token="$1"
    local updates chat_ids first_id count

    updates="$(telegram_get_updates_raw "$bot_token" 2>/dev/null || true)"
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

    chat_ids="$(telegram_extract_chat_ids_raw "$updates" || true)"
    count="$(printf '%s\n' "$chat_ids" | sed '/^$/d' | wc -l | tr -d ' ')"
    if ! is_number "$count" || [ "$count" -lt 1 ]; then
        warn "Could not parse chat IDs from getUpdates response."
        printf '%s' ""
        return 0
    fi

    info "Discovered Telegram chat IDs from getUpdates:" >&2
    printf '%s\n' "$chat_ids" | sed '/^$/d' | sed 's/^/  - /' >&2
    first_id="$(printf '%s\n' "$chat_ids" | sed '/^$/d' | head -n 1)"
    printf '%s' "$first_id"
}

send_discord_message_raw() {
    local webhook_url="$1"
    local message="$2"
    local payload=""
    local http_code=""

    [ -n "$webhook_url" ] || return 1
    command -v curl >/dev/null 2>&1 || return 1

    payload="$(json_escape_string "$message")"
    http_code="$(curl -sS -m 20 -o /dev/null -w '%{http_code}' -X POST \
        -H "Content-Type: application/json" \
        -d "{\"content\":\"${payload}\"}" \
        "$webhook_url" 2>/dev/null || true)"
    case "$http_code" in
        200|201|202|204) return 0 ;;
        *) return 1 ;;
    esac
}

generate_chutes_tts_audio_file_raw() {
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
    command -v curl >/dev/null 2>&1 || return 1
    is_decimal_number "$speed" || speed="$DEFAULT_NOTIFY_CHUTES_SPEED"

    escaped_text="$(json_escape_string "$text")"
    escaped_voice="$(json_escape_string "$voice")"

    if ! curl -fsS -m 45 -X POST "$tts_url" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $chutes_api_key" \
        -d "{\"text\":\"${escaped_text}\",\"voice\":\"${escaped_voice}\",\"speed\":${speed}}" \
        --output "$output_file" >/dev/null 2>&1; then
        return 1
    fi
    [ -s "$output_file" ] || return 1
    return 0
}

send_telegram_voice_file_raw() {
    local bot_token="$1"
    local chat_id="$2"
    local file_path="$3"
    local caption="$4"
    local method="$5"
    local field_name="$6"
    local response http_code body

    [ -n "$bot_token" ] || return 1
    [ -n "$chat_id" ] || return 1
    [ -n "$file_path" ] || return 1
    [ -n "$method" ] || return 1
    [ -n "$field_name" ] || return 1
    command -v curl >/dev/null 2>&1 || return 1

    response="$(curl -sS -m 30 -w $'\n%{http_code}' -X POST "https://api.telegram.org/bot${bot_token}/${method}" \
        -F "chat_id=${chat_id}" \
        -F "${field_name}=@${file_path}" \
        -F "caption=${caption}" 2>/dev/null || true)"
    http_code="${response##*$'\n'}"
    body="${response%$'\n'*}"
    [ "$http_code" = "200" ] && printf '%s' "$body" | grep -q '"ok":[[:space:]]*true'
}

send_telegram_tts_raw() {
    local chutes_api_key="$1"
    local tts_url="$2"
    local voice="$3"
    local speed="$4"
    local bot_token="$5"
    local chat_id="$6"
    local text="$7"
    local caption="${8:-Ralphie TTS}"
    local tmp_audio_file=""

    [ -n "$chutes_api_key" ] || return 1
    [ -n "$tts_url" ] || return 1
    [ -n "$voice" ] || return 1
    [ -n "$bot_token" ] || return 1
    [ -n "$chat_id" ] || return 1
    [ -n "$text" ] || return 1
    command -v curl >/dev/null 2>&1 || return 1
    is_decimal_number "$speed" || speed="$DEFAULT_NOTIFY_CHUTES_SPEED"

    tmp_audio_file="$(mktemp "${TMPDIR:-/tmp}/ralphie_tts.XXXXXX")" || return 1
    if ! generate_chutes_tts_audio_file_raw "$chutes_api_key" "$tts_url" "$voice" "$speed" "$text" "$tmp_audio_file"; then
        rm -f "$tmp_audio_file"
        return 1
    fi

    if ! send_telegram_voice_file_raw "$bot_token" "$chat_id" "$tmp_audio_file" "$caption" "sendVoice" "voice" \
        && ! send_telegram_voice_file_raw "$bot_token" "$chat_id" "$tmp_audio_file" "$caption" "sendAudio" "audio" \
        && ! send_telegram_voice_file_raw "$bot_token" "$chat_id" "$tmp_audio_file" "$caption" "sendDocument" "document"; then
            rm -f "$tmp_audio_file"
            return 1
        fi

    rm -f "$tmp_audio_file"
    return 0
}

send_discord_tts_raw() {
    local chutes_api_key="$1"
    local tts_url="$2"
    local voice="$3"
    local speed="$4"
    local webhook_url="$5"
    local text="$6"
    local caption="${7:-Ralphie TTS}"
    local tmp_audio_file=""
    local payload=""
    local http_code=""

    [ -n "$chutes_api_key" ] || return 1
    [ -n "$tts_url" ] || return 1
    [ -n "$voice" ] || return 1
    [ -n "$webhook_url" ] || return 1
    [ -n "$text" ] || return 1
    command -v curl >/dev/null 2>&1 || return 1
    is_decimal_number "$speed" || speed="$DEFAULT_NOTIFY_CHUTES_SPEED"

    tmp_audio_file="$(mktemp "${TMPDIR:-/tmp}/ralphie_discord_tts.XXXXXX")" || return 1
    if ! generate_chutes_tts_audio_file_raw "$chutes_api_key" "$tts_url" "$voice" "$speed" "$text" "$tmp_audio_file"; then
        rm -f "$tmp_audio_file"
        return 1
    fi

    payload="$(json_escape_string "$caption")"
    http_code="$(curl -sS -m 30 -o /dev/null -w '%{http_code}' -X POST \
        -F "payload_json={\"content\":\"${payload}\"}" \
        -F "file=@${tmp_audio_file};filename=ralphie-tts.mp3;type=audio/mpeg" \
        "$webhook_url" 2>/dev/null || true)"

    rm -f "$tmp_audio_file"
    case "$http_code" in
        200|201|202|204) return 0 ;;
        *) return 1 ;;
    esac
}

normalize_notify_tts_style() {
    local style
    style="$(to_lower "${1:-$DEFAULT_NOTIFY_TTS_STYLE}")"
    case "$style" in
        standard|friendly|ralph_wiggum) echo "$style" ;;
        ralph) echo "ralph_wiggum" ;;
        *) echo "$DEFAULT_NOTIFY_TTS_STYLE" ;;
    esac
}

notification_tts_event_summary() {
    local event="${1:-}"
    local status="${2:-}"
    case "$event" in
        notification_setup) echo "notifications are all set" ;;
        session_start) echo "the mission started" ;;
        phase_decision) echo "I made a phase decision" ;;
        phase_complete) echo "a phase is complete" ;;
        phase_blocked) echo "a phase got blocked" ;;
        session_done) echo "the mission is complete" ;;
        session_error)
            if [ "$status" = "hold" ]; then
                echo "I hit a blocker"
            else
                echo "I hit a problem"
            fi
            ;;
        *) echo "here is an update" ;;
    esac
}

build_tts_notification_line() {
    local event="${1:-}"
    local status="${2:-}"
    local details="${3:-none}"
    local style summary normalized_details line

    style="$(normalize_notify_tts_style "${NOTIFY_TTS_STYLE:-$DEFAULT_NOTIFY_TTS_STYLE}")"
    summary="$(notification_tts_event_summary "$event" "$status")"
    normalized_details="$(printf '%s' "$details" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g' | sed 's/^ *//; s/ *$//')"
    normalized_details="$(printf '%s' "$normalized_details" | cut -c 1-140)"
    [ -n "$normalized_details" ] || normalized_details="no extra details"

    case "$style" in
        standard)
            line="Ralphie update. ${summary}. ${normalized_details}."
            ;;
        friendly)
            line="Hey friend, Ralphie here. ${summary}. ${normalized_details}."
            ;;
        ralph_wiggum)
            line="Hi, I am Ralphie. ${summary}. ${normalized_details}. Woo hoo!"
            ;;
        *)
            line="Ralphie update. ${summary}. ${normalized_details}."
            ;;
    esac

    printf '%s' "$line" | cut -c 1-220
}

notify_event() {
    local event="$1"
    local status="$2"
    local details="${3:-}"
    local project_name branch_name timestamp_utc phase_value attempt_value iteration_value
    local message=""
    local delivered=false
    local now_epoch dedup_window reminder_minutes reminder_seconds
    local event_signature=""
    local incident_key=""
    local effective_details=""
    local delivery_details=""
    local elapsed_since_last=0
    local elapsed_series_minutes=0
    local tts_attempted=false
    local tts_failed=false

    if ! is_true "$NOTIFICATIONS_ENABLED"; then
        return 0
    fi
    command -v curl >/dev/null 2>&1 || return 0

    details="$(printf '%s' "$details" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g' | sed 's/^ *//; s/ *$//')"
    [ -n "$details" ] || details="none"

    if ! notification_event_is_high_signal "$event"; then
        notification_log_append "$event" "$status" "suppressed" "low-signal event suppressed: $details"
        return 0
    fi

    now_epoch="$(notification_now_epoch)"
    dedup_window="$(normalize_non_negative_decimal "$NOTIFY_EVENT_DEDUP_WINDOW_SECONDS")" || return 1
    reminder_minutes="$(normalize_non_negative_decimal "$NOTIFY_INCIDENT_REMINDER_MINUTES" 153722867280912930)" || return 1
    reminder_seconds=$((reminder_minutes * 60))
    effective_details="$details"

    if [ "$event" = "session_error" ]; then
        incident_key="${event}|${status}"
        if [ "$NOTIFY_INCIDENT_SERIES_ACTIVE" != "true" ] || [ "$NOTIFY_INCIDENT_SERIES_KEY" != "$incident_key" ]; then
            NOTIFY_INCIDENT_SERIES_ACTIVE="true"
            NOTIFY_INCIDENT_SERIES_KEY="$incident_key"
            NOTIFY_INCIDENT_SERIES_STARTED_AT="$now_epoch"
            NOTIFY_INCIDENT_LAST_SENT_AT="$now_epoch"
            NOTIFY_INCIDENT_REPEAT_COUNT=1
        else
            NOTIFY_INCIDENT_REPEAT_COUNT=$((NOTIFY_INCIDENT_REPEAT_COUNT + 1))
            if [ "$reminder_seconds" -eq 0 ]; then
                notification_log_append "$event" "$status" "suppressed" "incident series active (reminders disabled, repeat=$NOTIFY_INCIDENT_REPEAT_COUNT): $details"
                return 0
            fi
            if [ "$now_epoch" -gt 0 ] && [ "$NOTIFY_INCIDENT_LAST_SENT_AT" -gt 0 ]; then
                elapsed_since_last=$((now_epoch - NOTIFY_INCIDENT_LAST_SENT_AT))
            else
                elapsed_since_last=0
            fi
            if [ "$elapsed_since_last" -lt "$reminder_seconds" ]; then
                notification_log_append "$event" "$status" "suppressed" "incident series active (repeat=$NOTIFY_INCIDENT_REPEAT_COUNT): $details"
                return 0
            fi
            if [ "$now_epoch" -gt 0 ] && [ "$NOTIFY_INCIDENT_SERIES_STARTED_AT" -gt 0 ]; then
                elapsed_series_minutes=$(( (now_epoch - NOTIFY_INCIDENT_SERIES_STARTED_AT) / 60 ))
            else
                elapsed_series_minutes=0
            fi
            effective_details="${details}; ongoing=${elapsed_series_minutes}m repeats=${NOTIFY_INCIDENT_REPEAT_COUNT}"
            NOTIFY_INCIDENT_LAST_SENT_AT="$now_epoch"
        fi
    else
        if [ "$NOTIFY_INCIDENT_SERIES_ACTIVE" = "true" ]; then
            notification_reset_incident_series
        fi
        event_signature="${event}|${status}|$(printf '%s' "$details" | cut -c 1-220)"
        if [ "$dedup_window" -gt 0 ] && [ -n "$NOTIFY_LAST_EVENT_SIGNATURE" ] && [ "$event_signature" = "$NOTIFY_LAST_EVENT_SIGNATURE" ] && [ "$now_epoch" -gt 0 ] && [ "$NOTIFY_LAST_EVENT_SENT_AT" -gt 0 ]; then
            elapsed_since_last=$((now_epoch - NOTIFY_LAST_EVENT_SENT_AT))
            if [ "$elapsed_since_last" -lt "$dedup_window" ]; then
                notification_log_append "$event" "$status" "suppressed" "duplicate event within ${dedup_window}s window: $details"
                return 0
            fi
        fi
    fi

    project_name="$(basename "$PROJECT_DIR")"
    branch_name="$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || echo "detached")"
    timestamp_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    phase_value="${CURRENT_PHASE:-unknown}"
    attempt_value="${CURRENT_PHASE_ATTEMPT:-0}"
    iteration_value="${ITERATION_COUNT:-0}"

    message="$(cat <<EOF
[ralphie] event=$event status=$status
project=$project_name branch=$branch_name session=${SESSION_ID:-unknown}
phase=$phase_value attempt=$attempt_value iteration=$iteration_value engine=${ACTIVE_ENGINE:-unknown}
details=$effective_details
timestamp_utc=$timestamp_utc
EOF
)"

    if is_true "$NOTIFY_TELEGRAM_ENABLED" && [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
        if send_telegram_message_raw "$TG_BOT_TOKEN" "$TG_CHAT_ID" "$message"; then
            delivered=true
        fi
        if is_true "$NOTIFY_TTS_ENABLED" && [ -n "$CHUTES_API_KEY" ]; then
            local tts_line
            tts_line="$(build_tts_notification_line "$event" "$status" "$effective_details")"
            tts_attempted=true
            if send_telegram_tts_raw \
                "$CHUTES_API_KEY" \
                "$NOTIFY_CHUTES_TTS_URL" \
                "$NOTIFY_CHUTES_VOICE" \
                "$NOTIFY_CHUTES_SPEED" \
                "$TG_BOT_TOKEN" \
                "$TG_CHAT_ID" \
                "$tts_line" \
                "ralphie $event"; then
                delivered=true
            else
                tts_failed=true
            fi
        fi
    fi

    if is_true "$NOTIFY_DISCORD_ENABLED" && [ -n "$NOTIFY_DISCORD_WEBHOOK_URL" ]; then
        if send_discord_message_raw "$NOTIFY_DISCORD_WEBHOOK_URL" "$message"; then
            delivered=true
        fi
        if is_true "$NOTIFY_TTS_ENABLED" && [ -n "$CHUTES_API_KEY" ]; then
            local discord_tts_line
            discord_tts_line="$(build_tts_notification_line "$event" "$status" "$effective_details")"
            tts_attempted=true
            if send_discord_tts_raw \
                "$CHUTES_API_KEY" \
                "$NOTIFY_CHUTES_TTS_URL" \
                "$NOTIFY_CHUTES_VOICE" \
                "$NOTIFY_CHUTES_SPEED" \
                "$NOTIFY_DISCORD_WEBHOOK_URL" \
                "$discord_tts_line" \
                "ralphie $event"; then
                delivered=true
            else
                tts_failed=true
            fi
        fi
    fi

    if [ "$event" != "session_error" ]; then
        NOTIFY_LAST_EVENT_SIGNATURE="${event_signature:-${event}|${status}|$(printf '%s' "$details" | cut -c 1-220)}"
        NOTIFY_LAST_EVENT_SENT_AT="$now_epoch"
    fi

    delivery_details="$effective_details"
    if [ "$tts_attempted" = true ] && [ "$tts_failed" = true ]; then
        delivery_details="${delivery_details}; tts=fallback_text_only"
    fi
    notification_log_append "$event" "$status" "$([ "$delivered" = true ] && echo "delivered" || echo "failed")" "$delivery_details"
    return 0
}

persist_notification_wizard_bootstrap_flag() {
    NOTIFICATION_WIZARD_BOOTSTRAPPED="true"
    if ! upsert_config_env_value "RALPHIE_NOTIFICATION_WIZARD_BOOTSTRAPPED" "true"; then
        warn "Could not persist RALPHIE_NOTIFICATION_WIZARD_BOOTSTRAPPED to $(path_for_display "$CONFIG_FILE")."
        return 1
    fi
    return 0
}

persist_notification_value() {
    local key="$1"
    local value="${2:-}"
    if ! upsert_config_env_value "$key" "$value"; then
        warn "Could not persist $key to $(path_for_display "$CONFIG_FILE")."
        return 1
    fi
    return 0
}

run_first_deploy_notification_wizard() {
    local prompt_response
    if is_true "$NOTIFICATION_WIZARD_BOOTSTRAPPED"; then
        return 1
    fi
    if ! is_tty_input_available; then
        return 1
    fi
    if ! command -v curl >/dev/null 2>&1; then
        warn "Notification setup skipped: curl is required for Telegram/Discord/Chutes delivery checks."
        persist_notification_wizard_bootstrap_flag || true
        return 1
    fi

    info "First-deploy notification setup is available."
    info "Standardized events: session_start, phase_decision, phase_complete, phase_blocked, session_done, session_error."
    info "Channels supported: Telegram bot, Discord webhook, optional Chutes TTS voice attachments."
    info "Anti-spam policy: only high-signal events are sent; repeated incident alerts are batched with periodic reminders."

    prompt_response="$(prompt_yes_no "Configure notifications now (Telegram/Discord/Chutes TTS)?" "n")" || return 130
    if [ "$prompt_response" != "true" ]; then
        info "Skipping first-deploy notification setup."
        persist_notification_wizard_bootstrap_flag || true
        return 1
    fi

    local telegram_selected="false"
    local discord_selected="false"
    local tts_selected="false"

    info "Telegram setup guide:"
    info "  1) Open Telegram @BotFather, run /newbot, copy bot token."
    info "  2) Send one message to your bot/chat/channel."
    info "  3) Open https://api.telegram.org/bot<token>/getUpdates and copy chat.id (or let Ralphie auto-discover it)."
    prompt_response="$(prompt_yes_no "Configure Telegram notifications?" "$(is_true "$NOTIFY_TELEGRAM_ENABLED" && echo y || echo n)")" || return 130
    if [ "$prompt_response" = "true" ]; then
        local suggested_chat_id=""
        telegram_selected="true"
        TG_BOT_TOKEN="$(prompt_override_value "Telegram bot token (TG_BOT_TOKEN)" "$TG_BOT_TOKEN" true)" || return 130
        if [ -z "$TG_CHAT_ID" ] && [ -n "$TG_BOT_TOKEN" ]; then
            suggested_chat_id="$(telegram_suggest_chat_id_raw "$TG_BOT_TOKEN")"
            if [ -n "$suggested_chat_id" ]; then
                TG_CHAT_ID="$suggested_chat_id"
            fi
        fi
        TG_CHAT_ID="$(prompt_override_value "Telegram chat id (TG_CHAT_ID)" "$TG_CHAT_ID")" || return 130
        if [ -z "$TG_CHAT_ID" ] && [ -n "$TG_BOT_TOKEN" ]; then
            suggested_chat_id="$(telegram_suggest_chat_id_raw "$TG_BOT_TOKEN")"
            if [ -n "$suggested_chat_id" ]; then
                info "Using discovered chat id: $suggested_chat_id"
                TG_CHAT_ID="$suggested_chat_id"
            fi
        fi
        if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
            warn "Telegram credentials are incomplete; disabling Telegram channel."
            telegram_selected="false"
        elif send_telegram_message_raw "$TG_BOT_TOKEN" "$TG_CHAT_ID" "[ralphie] telegram setup test"; then
            success "Telegram test message sent."
        else
            warn "Telegram test failed. Verify bot token/chat id and bot permissions."
        fi
    fi

    info "Discord setup guide:"
    info "  1) Open Server Settings -> Integrations -> Webhooks."
    info "  2) Create webhook, copy URL, and paste it here."
    prompt_response="$(prompt_yes_no "Configure Discord webhook notifications?" "$(is_true "$NOTIFY_DISCORD_ENABLED" && echo y || echo n)")" || return 130
    if [ "$prompt_response" = "true" ]; then
        discord_selected="true"
        NOTIFY_DISCORD_WEBHOOK_URL="$(prompt_override_value "Discord webhook URL" "$NOTIFY_DISCORD_WEBHOOK_URL" true)" || return 130
        if [ -z "$NOTIFY_DISCORD_WEBHOOK_URL" ]; then
            warn "Discord webhook URL is empty; disabling Discord channel."
            discord_selected="false"
        elif send_discord_message_raw "$NOTIFY_DISCORD_WEBHOOK_URL" "[ralphie] discord setup test"; then
            success "Discord test message sent."
        else
            warn "Discord webhook test failed. Verify webhook URL and channel permissions."
        fi
    fi

    if [ "$telegram_selected" = "true" ] || [ "$discord_selected" = "true" ]; then
        info "Optional Chutes TTS setup guide:"
        info "  1) Create API key at https://chutes.ai"
        info "  2) Provide CHUTES_API_KEY to enable voice notifications (Telegram and/or Discord)."
        prompt_response="$(prompt_yes_no "Enable Chutes TTS voice notifications?" "$(is_true "$NOTIFY_TTS_ENABLED" && echo y || echo n)")" || return 130
        if [ "$prompt_response" = "true" ]; then
            tts_selected="true"
            CHUTES_API_KEY="$(prompt_override_value "Chutes API key (CHUTES_API_KEY)" "$CHUTES_API_KEY" true)" || return 130
            NOTIFY_TTS_STYLE="$(prompt_override_value "TTS narration style (standard|friendly|ralph_wiggum)" "$NOTIFY_TTS_STYLE")" || return 130
            NOTIFY_TTS_STYLE="$(normalize_notify_tts_style "$NOTIFY_TTS_STYLE")"
            NOTIFY_CHUTES_VOICE="$(prompt_override_value "Chutes voice id" "$NOTIFY_CHUTES_VOICE")" || return 130
            NOTIFY_CHUTES_SPEED="$(prompt_override_value "Chutes speed (example 1.0)" "$NOTIFY_CHUTES_SPEED")" || return 130
            if ! is_decimal_number "$NOTIFY_CHUTES_SPEED"; then
                warn "Invalid Chutes speed; defaulting to $DEFAULT_NOTIFY_CHUTES_SPEED."
                NOTIFY_CHUTES_SPEED="$DEFAULT_NOTIFY_CHUTES_SPEED"
            fi
            if [ -z "$CHUTES_API_KEY" ]; then
                warn "Chutes API key is empty; disabling TTS channel."
                tts_selected="false"
            else
                if [ "$telegram_selected" = "true" ]; then
                    if send_telegram_tts_raw \
                        "$CHUTES_API_KEY" \
                        "$NOTIFY_CHUTES_TTS_URL" \
                        "$NOTIFY_CHUTES_VOICE" \
                        "$NOTIFY_CHUTES_SPEED" \
                        "$TG_BOT_TOKEN" \
                        "$TG_CHAT_ID" \
                        "ralphie setup test message" \
                        "ralphie tts test"; then
                        success "Telegram TTS test voice sent."
                    else
                        warn "Telegram TTS test failed. Verify CHUTES_API_KEY and Telegram credentials."
                    fi
                fi
                if [ "$discord_selected" = "true" ] && [ -n "$NOTIFY_DISCORD_WEBHOOK_URL" ]; then
                    if send_discord_tts_raw \
                        "$CHUTES_API_KEY" \
                        "$NOTIFY_CHUTES_TTS_URL" \
                        "$NOTIFY_CHUTES_VOICE" \
                        "$NOTIFY_CHUTES_SPEED" \
                        "$NOTIFY_DISCORD_WEBHOOK_URL" \
                        "ralphie setup test message" \
                        "ralphie tts test"; then
                        success "Discord TTS test voice sent."
                    else
                        warn "Discord TTS test failed. Verify CHUTES_API_KEY and webhook permissions."
                    fi
                fi
            fi
        fi
    fi

    prompt_response="$(prompt_yes_no "Adjust anti-spam notification cadence?" "n")" || return 130
    if [ "$prompt_response" = "true" ]; then
        local dedup_candidate reminder_candidate
        dedup_candidate="$(prompt_optional_line "Duplicate-event suppression window seconds (0 disables suppression)" "$NOTIFY_EVENT_DEDUP_WINDOW_SECONDS")" || return 130
        reminder_candidate="$(prompt_optional_line "Incident reminder interval minutes (0 disables reminders)" "$NOTIFY_INCIDENT_REMINDER_MINUTES")" || return 130
        if dedup_candidate="$(normalize_non_negative_decimal "$dedup_candidate")"; then
            NOTIFY_EVENT_DEDUP_WINDOW_SECONDS="$dedup_candidate"
        else
            warn "Invalid dedup window '$dedup_candidate'; keeping ${NOTIFY_EVENT_DEDUP_WINDOW_SECONDS}."
        fi
        if reminder_candidate="$(normalize_non_negative_decimal "$reminder_candidate" 153722867280912930)"; then
            NOTIFY_INCIDENT_REMINDER_MINUTES="$reminder_candidate"
        else
            warn "Invalid incident reminder interval '$reminder_candidate'; keeping ${NOTIFY_INCIDENT_REMINDER_MINUTES}."
        fi
    fi

    NOTIFY_TELEGRAM_ENABLED="$telegram_selected"
    NOTIFY_DISCORD_ENABLED="$discord_selected"
    NOTIFY_TTS_ENABLED="$tts_selected"
    if [ "$NOTIFY_TELEGRAM_ENABLED" = "true" ] || [ "$NOTIFY_DISCORD_ENABLED" = "true" ]; then
        NOTIFICATIONS_ENABLED="true"
    else
        NOTIFICATIONS_ENABLED="false"
        NOTIFY_TTS_ENABLED="false"
    fi
    if [ "$NOTIFY_TELEGRAM_ENABLED" != "true" ] && [ "$NOTIFY_DISCORD_ENABLED" != "true" ]; then
        NOTIFY_TTS_ENABLED="false"
    fi

    persist_notification_value "RALPHIE_NOTIFICATIONS_ENABLED" "$NOTIFICATIONS_ENABLED" || true
    persist_notification_value "RALPHIE_NOTIFY_TELEGRAM_ENABLED" "$NOTIFY_TELEGRAM_ENABLED" || true
    persist_notification_value "TG_BOT_TOKEN" "$TG_BOT_TOKEN" || true
    persist_notification_value "TG_CHAT_ID" "$TG_CHAT_ID" || true
    persist_notification_value "RALPHIE_NOTIFY_DISCORD_ENABLED" "$NOTIFY_DISCORD_ENABLED" || true
    persist_notification_value "RALPHIE_NOTIFY_DISCORD_WEBHOOK_URL" "$NOTIFY_DISCORD_WEBHOOK_URL" || true
    persist_notification_value "RALPHIE_NOTIFY_TTS_ENABLED" "$NOTIFY_TTS_ENABLED" || true
    persist_notification_value "RALPHIE_NOTIFY_TTS_STYLE" "$NOTIFY_TTS_STYLE" || true
    persist_notification_value "CHUTES_API_KEY" "$CHUTES_API_KEY" || true
    persist_notification_value "RALPHIE_NOTIFY_CHUTES_TTS_URL" "$NOTIFY_CHUTES_TTS_URL" || true
    persist_notification_value "RALPHIE_NOTIFY_CHUTES_VOICE" "$NOTIFY_CHUTES_VOICE" || true
    persist_notification_value "RALPHIE_NOTIFY_CHUTES_SPEED" "$NOTIFY_CHUTES_SPEED" || true
    persist_notification_value "RALPHIE_NOTIFY_EVENT_DEDUP_WINDOW_SECONDS" "$NOTIFY_EVENT_DEDUP_WINDOW_SECONDS" || true
    persist_notification_value "RALPHIE_NOTIFY_INCIDENT_REMINDER_MINUTES" "$NOTIFY_INCIDENT_REMINDER_MINUTES" || true
    persist_notification_wizard_bootstrap_flag || true

    info "Notification setup saved to $(path_for_display "$CONFIG_FILE")."
    info "Notification channels configured: $(notification_channels_for_display)"

    if is_true "$NOTIFICATIONS_ENABLED"; then
        notify_event "notification_setup" "ok" "notification channels configured via first-deploy wizard"
        return 0
    fi
    return 1
}

persist_engine_override_bootstrap_flag() {
    ENGINE_OVERRIDES_BOOTSTRAPPED="true"
    if ! upsert_config_env_value "RALPHIE_ENGINE_OVERRIDES_BOOTSTRAPPED" "true"; then
        warn "Could not persist RALPHIE_ENGINE_OVERRIDES_BOOTSTRAPPED to $(path_for_display "$CONFIG_FILE")."
        return 1
    fi
    return 0
}

persist_engine_override_value() {
    local key="$1"
    local value="${2:-}"
    if ! upsert_config_env_value "$key" "$value"; then
        warn "Could not persist $key to $(path_for_display "$CONFIG_FILE")."
        return 1
    fi
    return 0
}

run_first_deploy_engine_override_wizard() {
    local prompt_response
    # A first-run questionnaire must not replace an engine or model the
    # operator already selected in config, environment or this invocation.
    if is_true "${ENGINE_SELECTION_EXPLICIT:-false}" || is_true "${PRIME_OPTIONS_EXPLICIT:-false}"; then
        return 1
    fi
    if is_true "$ENGINE_OVERRIDES_BOOTSTRAPPED"; then
        return 1
    fi
    if ! is_tty_input_available; then
        return 1
    fi

    info "First-deploy engine override setup is available."
    info "Requested engine mode: $ENGINE_SELECTION_REQUESTED (auto preference: $AUTO_ENGINE_PREFERENCE)"
    info "Healthy engines from readiness checks: $(healthy_engines_for_display)"

    prompt_response="$(prompt_yes_no "Configure engine selection and provider/model/thinking overrides now?" "y")" || return 130
    if [ "$prompt_response" != "true" ]; then
        info "Skipping first-deploy engine override setup."
        persist_engine_override_bootstrap_flag || true
        return 1
    fi

    local overrides_changed=false
    local selected_engine_choice preferred_auto_choice
    local codex_endpoint_choice codex_model_choice codex_thinking_choice
    local codex_schema_enabled_choice codex_schema_file_choice
    local claude_endpoint_choice claude_model_choice claude_thinking_choice

    selected_engine_choice="$(prompt_read_line "Engine mode (auto|prime-agent|codex|claude) [current: $ENGINE_SELECTION_REQUESTED]: " "$ENGINE_SELECTION_REQUESTED")" || return 130
    selected_engine_choice="$(normalize_engine_name "$selected_engine_choice")"
    case "$selected_engine_choice" in
        auto|prime-agent|codex|claude) ;;
        *)
            warn "Invalid engine mode '$selected_engine_choice'. Keeping '$ENGINE_SELECTION_REQUESTED'."
            selected_engine_choice="$ENGINE_SELECTION_REQUESTED"
            ;;
    esac
    if [ "$selected_engine_choice" != "$ENGINE_SELECTION_REQUESTED" ]; then
        ENGINE_SELECTION_REQUESTED="$selected_engine_choice"
        overrides_changed=true
    fi
    persist_engine_override_value "RALPHIE_ENGINE" "$ENGINE_SELECTION_REQUESTED" || true

    if [ "$ENGINE_SELECTION_REQUESTED" = "auto" ]; then
        preferred_auto_choice="$(prompt_read_line "AUTO preference (prime-agent|codex|claude) [current: $AUTO_ENGINE_PREFERENCE]: " "$AUTO_ENGINE_PREFERENCE")" || return 130
        preferred_auto_choice="$(normalize_engine_name "$preferred_auto_choice")"
        case "$preferred_auto_choice" in
            prime-agent|codex|claude) ;;
            *)
                warn "Invalid AUTO preference '$preferred_auto_choice'. Keeping '$AUTO_ENGINE_PREFERENCE'."
                preferred_auto_choice="$AUTO_ENGINE_PREFERENCE"
                ;;
        esac
        if [ "$preferred_auto_choice" != "$AUTO_ENGINE_PREFERENCE" ]; then
            AUTO_ENGINE_PREFERENCE="$preferred_auto_choice"
            overrides_changed=true
        fi
        persist_engine_override_value "RALPHIE_AUTO_ENGINE_PREFERENCE" "$AUTO_ENGINE_PREFERENCE" || true
    fi

    if [ "$CODEX_HEALTHY" = "true" ]; then
        prompt_response="$(prompt_yes_no "Configure Codex endpoint/model/thinking/schema overrides?" "n")" || return 130
        if [ "$prompt_response" = "true" ]; then
            codex_endpoint_choice="$(prompt_override_value "Codex endpoint (OPENAI_BASE_URL)" "$CODEX_ENDPOINT")" || return 130
            codex_model_choice="$(prompt_override_value "Codex model" "${CODEX_MODEL:-}")" || return 130
            codex_thinking_choice="$(prompt_override_value "Codex thinking override (none|minimal|low|medium|high|xhigh)" "$CODEX_THINKING_OVERRIDE")" || return 130
            codex_thinking_choice="$(to_lower "$codex_thinking_choice")"
            case "$codex_thinking_choice" in
                none|minimal|low|medium|high|xhigh|"") ;;
                *)
                    warn "Invalid codex thinking override '$codex_thinking_choice'. Keeping '$CODEX_THINKING_OVERRIDE'."
                    codex_thinking_choice="$CODEX_THINKING_OVERRIDE"
                    ;;
            esac

            prompt_response="$(prompt_yes_no "Enable Codex output schema?" "$(is_true "$CODEX_USE_RESPONSES_SCHEMA" && echo y || echo n)")" || return 130
            if [ "$prompt_response" = "true" ]; then
                codex_schema_enabled_choice="true"
                codex_schema_file_choice="$(prompt_override_value "Codex schema file path" "$CODEX_RESPONSES_SCHEMA_FILE")" || return 130
            else
                codex_schema_enabled_choice="false"
                codex_schema_file_choice="$CODEX_RESPONSES_SCHEMA_FILE"
            fi

            [ "$codex_endpoint_choice" = "$CODEX_ENDPOINT" ] || overrides_changed=true
            [ "$codex_model_choice" = "${CODEX_MODEL:-}" ] || overrides_changed=true
            [ "$codex_thinking_choice" = "$CODEX_THINKING_OVERRIDE" ] || overrides_changed=true
            [ "$codex_schema_enabled_choice" = "$CODEX_USE_RESPONSES_SCHEMA" ] || overrides_changed=true
            [ "$codex_schema_file_choice" = "$CODEX_RESPONSES_SCHEMA_FILE" ] || overrides_changed=true

            CODEX_ENDPOINT="$codex_endpoint_choice"
            CODEX_MODEL="$codex_model_choice"
            CODEX_THINKING_OVERRIDE="$codex_thinking_choice"
            CODEX_USE_RESPONSES_SCHEMA="$codex_schema_enabled_choice"
            CODEX_RESPONSES_SCHEMA_FILE="$codex_schema_file_choice"

            persist_engine_override_value "RALPHIE_CODEX_ENDPOINT" "$CODEX_ENDPOINT" || true
            persist_engine_override_value "CODEX_MODEL" "$CODEX_MODEL" || true
            persist_engine_override_value "RALPHIE_CODEX_THINKING_OVERRIDE" "$CODEX_THINKING_OVERRIDE" || true
            persist_engine_override_value "RALPHIE_CODEX_USE_RESPONSES_SCHEMA" "$CODEX_USE_RESPONSES_SCHEMA" || true
            persist_engine_override_value "RALPHIE_CODEX_RESPONSES_SCHEMA_FILE" "$CODEX_RESPONSES_SCHEMA_FILE" || true
        fi
    fi

    if [ "$CLAUDE_HEALTHY" = "true" ]; then
        prompt_response="$(prompt_yes_no "Configure Claude endpoint/model/thinking overrides?" "n")" || return 130
        if [ "$prompt_response" = "true" ]; then
            claude_endpoint_choice="$(prompt_override_value "Claude endpoint (ANTHROPIC_BASE_URL)" "$CLAUDE_ENDPOINT")" || return 130
            claude_model_choice="$(prompt_override_value "Claude model" "${CLAUDE_MODEL:-}")" || return 130
            claude_thinking_choice="$(prompt_override_value "Claude thinking override (none|off|low|medium|high|xhigh)" "$CLAUDE_THINKING_OVERRIDE")" || return 130
            claude_thinking_choice="$(to_lower "$claude_thinking_choice")"
            case "$claude_thinking_choice" in
                none|off|low|medium|high|xhigh|"") ;;
                *)
                    warn "Invalid claude thinking override '$claude_thinking_choice'. Keeping '$CLAUDE_THINKING_OVERRIDE'."
                    claude_thinking_choice="$CLAUDE_THINKING_OVERRIDE"
                    ;;
            esac

            [ "$claude_endpoint_choice" = "$CLAUDE_ENDPOINT" ] || overrides_changed=true
            [ "$claude_model_choice" = "${CLAUDE_MODEL:-}" ] || overrides_changed=true
            [ "$claude_thinking_choice" = "$CLAUDE_THINKING_OVERRIDE" ] || overrides_changed=true

            CLAUDE_ENDPOINT="$claude_endpoint_choice"
            CLAUDE_MODEL="$claude_model_choice"
            CLAUDE_THINKING_OVERRIDE="$claude_thinking_choice"

            persist_engine_override_value "RALPHIE_CLAUDE_ENDPOINT" "$CLAUDE_ENDPOINT" || true
            persist_engine_override_value "CLAUDE_MODEL" "$CLAUDE_MODEL" || true
            persist_engine_override_value "RALPHIE_CLAUDE_THINKING_OVERRIDE" "$CLAUDE_THINKING_OVERRIDE" || true
        fi
    fi

    persist_engine_override_bootstrap_flag || true

    if [ "$overrides_changed" = "true" ]; then
        info "Engine overrides saved to $(path_for_display "$CONFIG_FILE")."
        return 0
    fi
    info "Engine override setup completed with no changes."
    return 1
}

run_command_with_timeout() {
    local timeout_seconds="$1"
    shift

    if ! is_number "$timeout_seconds" || [ "$timeout_seconds" -lt 1 ]; then
        timeout_seconds=15
    fi

    # A shell deadline works on macOS too, without timeout, Perl or a detached
    # alarm process. Explicit stdin preserves prompt input for background jobs.
    local COMMAND_TIMEOUT_SECONDS="$timeout_seconds"
    local cmd_pid cmd_exit
    "$@" <&0 &
    cmd_pid=$!
    register_managed_pid "$cmd_pid"
    if wait_for_process_with_idle_output_watchdog "$cmd_pid" 0 "bounded command"; then
        cmd_exit=0
    else
        cmd_exit=$?
    fi
    unregister_managed_pid "$cmd_pid"
    return "$cmd_exit"
}

run_startup_operational_probe() {
    local -a failures=()
    local cmd
    local probe_file=""
    local timeout_probe_exit=0
    local -a required_cmds=(
        sh sleep mktemp sed awk grep find sort date
        git seq cut head tail wc tr tee comm cmp ps mkfifo
    )

    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            failures+=("missing required command: $cmd")
        fi
    done

    if ! mkdir -p "$CONFIG_DIR" 2>/dev/null; then
        failures+=("unable to create config dir: $(path_for_display "$CONFIG_DIR")")
    else
        probe_file="$(mktemp "$CONFIG_DIR/operational-probe.XXXXXX" 2>/dev/null || true)"
        if [ -z "$probe_file" ]; then
            failures+=("unable to write probe file under $(path_for_display "$CONFIG_DIR")")
        else
            rm -f "$probe_file"
        fi
    fi

    if run_command_with_timeout 1 sh -c 'sleep 2' >/dev/null 2>&1; then
        timeout_probe_exit=0
    else
        timeout_probe_exit=$?
    fi
    if [ "$timeout_probe_exit" -ne 124 ] && [ "$timeout_probe_exit" -ne 142 ] && [ "$timeout_probe_exit" -ne 143 ] && [ "$timeout_probe_exit" -ne 137 ]; then
        failures+=("timeout wrapper probe failed (expected timeout-like exit, got $timeout_probe_exit)")
    fi

    if [ "${#failures[@]}" -gt 0 ]; then
        warn "Startup operational probe failed:"
        for cmd in "${failures[@]}"; do
            warn "  - $cmd"
        done
        log_reason_code "RB_STARTUP_OPERATIONAL_PROBE_FAILED" "$(summarize_blocks_for_log "${failures[@]}")"
        return 1
    fi

    if is_true "$ENGINE_HEALTH_RETRY_VERBOSE"; then
        info "Startup operational probe passed."
    fi
    return 0
}

# Engine Smoke Test — verify an engine can actually respond to a prompt
smoke_test_engine() {
    local engine_cmd="$1" engine_name="$2"
    local timeout_seconds="${ENGINE_SMOKE_TEST_TIMEOUT:-15}"
    local COMMAND_TIMEOUT_SECONDS="$timeout_seconds"
    local -a smoke_prefix=() smoke_args=()
    local engine_scratch_dir capture_limit_marker capture_permanent_marker capture_recording_marker
    local prompt_file output_file log_file stream_output_file canary_token smoke_pid
    local smoke_exit=1 result=1 permanent=false

    request_check_generation || return $?
    [ -n "$engine_cmd" ] && command -v "$engine_cmd" >/dev/null 2>&1 || return 1
    [ "$engine_name" != codex ] || validate_codex_schema_requirement || return 1
    engine_scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/ralphie_engine.XXXXXX")" || return 1
    prompt_file="$engine_scratch_dir/prompt"; output_file="$engine_scratch_dir/answer"; log_file="$engine_scratch_dir/log"
    capture_limit_marker="$engine_scratch_dir/limit"; capture_permanent_marker="$engine_scratch_dir/permanent"
    capture_recording_marker="$engine_scratch_dir/recording-ok"
    if ! : > "$capture_recording_marker"; then
        cleanup_engine_attempt_files "$engine_scratch_dir"
        ENGINE_PERMANENT_FAILURE=true
        ENGINE_PERMANENT_FAILURE_REASON='Could not prepare engine readiness output capture; refusing further inference.'
        return 126
    fi
    stream_output_file="$output_file"
    canary_token="ralphie_smoke_$(date +%s)_${RANDOM:-0}"
    printf 'Reply with ONLY this exact token on a single line, nothing else: %s\n' "$canary_token" > "$prompt_file"
    : > "$output_file"

    if [ "$engine_name" = codex ]; then
        [ -z "$CODEX_ENDPOINT" ] || smoke_prefix=(env "OPENAI_BASE_URL=$CODEX_ENDPOINT")
        smoke_args=("$engine_cmd" exec)
        [ -z "${CODEX_MODEL:-}" ] || smoke_args+=(--model "$CODEX_MODEL")
        [ -z "$CODEX_THINKING_OVERRIDE" ] || smoke_args+=(-c "model_reasoning_effort=\"$CODEX_THINKING_OVERRIDE\"")
        smoke_args+=(--output-last-message "$output_file" -)
        stream_output_file=""
    elif [ "$engine_name" = claude ]; then
        [ -z "$CLAUDE_ENDPOINT" ] || smoke_prefix=(env "ANTHROPIC_BASE_URL=$CLAUDE_ENDPOINT")
        smoke_args=("$engine_cmd" -p)
        [ -z "${CLAUDE_MODEL:-}" ] || smoke_args+=(--model "$CLAUDE_MODEL")
        case "$CLAUDE_THINKING_OVERRIDE" in
            high|xhigh) smoke_args+=(--settings '{"alwaysThinkingEnabled":true}') ;;
            none|off|low) smoke_args+=(--settings '{"alwaysThinkingEnabled":false}') ;;
        esac
    else
        cleanup_engine_attempt_files "$engine_scratch_dir"
        return 1
    fi
    local request_preflight_status=0
    request_check_generation || request_preflight_status=$?
    if [ "$request_preflight_status" -ne 0 ]; then cleanup_engine_attempt_files "$engine_scratch_dir"; return "$request_preflight_status"; fi
    if ! admit_session_attempt "$engine_name readiness canary"; then cleanup_engine_attempt_files "$engine_scratch_dir"; return 75; fi
    (
        trap "$(printf 'cleanup_engine_attempt_files %q; exit 143' "$engine_scratch_dir")" HUP INT TERM
        trap "$(printf 'rm -f -- %q/capture.*' "$engine_scratch_dir")" EXIT
        cd "$PROJECT_DIR" || exit 2
        "${smoke_prefix[@]+"${smoke_prefix[@]}"}" "${smoke_args[@]}" < "$prompt_file" 2>&1 \
            | stream_engine_output "$log_file" "$stream_output_file" false
    ) &
    smoke_pid=$!
    register_managed_pid "$smoke_pid"
    if wait_for_process_with_idle_output_watchdog "$smoke_pid" 0 "$engine_name readiness canary" "$log_file" "$output_file"; then smoke_exit=0; else smoke_exit=$?; fi
    unregister_managed_pid "$smoke_pid"
    if [ "$smoke_exit" -ne 0 ] && [ -f "$capture_permanent_marker" ]; then permanent=true; fi
    if ! charge_session_budget "$(estimate_run_tokens "$prompt_file" "" "$output_file")"; then cleanup_engine_attempt_files "$engine_scratch_dir"; return 75; fi
    if [ "$smoke_exit" -eq 74 ]; then
        cleanup_engine_attempt_files "$engine_scratch_dir"
        ENGINE_PERMANENT_FAILURE=true
        ENGINE_PERMANENT_FAILURE_REASON='Could not record engine readiness output; refusing further inference.'
        err "$ENGINE_PERMANENT_FAILURE_REASON"
        return 126
    fi
    # A token cannot turn an oversized or permanent-failure attempt into PASS.
    if [ "$smoke_exit" -ne 125 ] && ! is_true "$permanent" && [ -s "$output_file" ]; then
        if tr -d '\n\r' < "$output_file" | grep -qF "$canary_token"; then result=0; fi
    fi
    cleanup_engine_attempt_files "$engine_scratch_dir"
    if is_true "$permanent"; then
        case "$engine_name" in codex) CODEX_SMOKE_PERMANENT_FAILURE=true;; claude) CLAUDE_SMOKE_PERMANENT_FAILURE=true;; esac
        if [ "${ENGINE_SELECTION_REQUESTED:-auto}" = "$engine_name" ]; then
            ENGINE_PERMANENT_FAILURE=true
            ENGINE_PERMANENT_FAILURE_REASON="$engine_name readiness failed: permanent provider/model/authentication configuration error."
        fi
        warn "$engine_name readiness failed permanently; not retrying this configuration."
        return 126
    fi
    request_check_generation || return $?
    if is_true "$ENGINE_HEALTH_RETRY_VERBOSE"; then
        if [ "$result" -eq 0 ]; then info "Smoke test $engine_name: PASS"; else warn "Smoke test $engine_name: FAIL (exit=$smoke_exit)"; fi
    fi
    if [ "$result" -ne 0 ] && ! enforce_session_budget "$engine_name readiness canary"; then return 75; fi
    return "$result"
}

validate_engine_budget_settings() {
    local name
    for name in MAX_SESSION_CYCLES SESSION_TOKEN_BUDGET SESSION_TOKEN_RATE_CENTS_PER_MILLION SESSION_COST_BUDGET_CENTS; do
        normalize_integer_setting "$name" 0 || return 1
    done
    if [ "$SESSION_COST_BUDGET_CENTS" -gt 0 ] && [ "$SESSION_TOKEN_RATE_CENTS_PER_MILLION" -eq 0 ]; then
        err 'A positive session cost budget requires a positive token rate.'
        return 1
    fi
    return 0
}

validate_effective_engine_config() {
    local name
    validate_engine_budget_settings || return 1
    normalize_integer_setting AUTO_UPDATE_TIMEOUT_SECONDS 1 || return 1
    normalize_integer_setting AUTO_UPDATE_LOCK_TIMEOUT_SECONDS 0 || return 1
    normalize_integer_setting NOTIFY_EVENT_DEDUP_WINDOW_SECONDS 0 || return 1
    normalize_integer_setting NOTIFY_INCIDENT_REMINDER_MINUTES 0 153722867280912930 || return 1
    for name in COMMAND_TIMEOUT_SECONDS MAX_ITERATIONS ENGINE_IDLE_OUTPUT_TIMEOUT_SECONDS RUN_AGENT_RETRY_DELAY_SECONDS \
        ENGINE_HEALTH_RETRY_DELAY_SECONDS PHASE_WALLCLOCK_LIMIT_SECONDS PHASE_COMPLETION_MAX_ATTEMPTS \
        PHASE_COMPLETION_RETRY_DELAY_SECONDS MAX_CONSENSUS_ROUTING_ATTEMPTS PHASE_PAIR_CYCLE_LIMIT; do
        normalize_integer_setting "$name" 0 || return 1
    done
    for name in RUN_AGENT_MAX_ATTEMPTS ENGINE_HEALTH_MAX_ATTEMPTS ENGINE_SMOKE_TEST_TIMEOUT SWARM_CONSENSUS_TIMEOUT \
        SWARM_MAX_PARALLEL CONFIDENCE_STAGNATION_LIMIT; do
        normalize_integer_setting "$name" 1 || return 1
    done
    normalize_integer_setting ENGINE_OUTPUT_MAX_BYTES 1 9223372036854775806 || return 1
    for name in CONFIDENCE_TARGET CONSENSUS_SCORE_THRESHOLD CONSENSUS_CLEAN_GO_SCORE_FLOOR; do
        normalize_integer_setting "$name" 0 100 || return 1
    done
    for name in ENGINE_OUTPUT_TO_STDOUT YOLO RUN_AGENT_RETRY_VERBOSE ENGINE_HEALTH_RETRY_VERBOSE CODEX_USE_RESPONSES_SCHEMA \
        AUTO_COMMIT_ON_PHASE_PASS AUTO_UPDATE AUTO_UPDATE_ALLOW_DIRTY AUTO_UPDATE_ALLOW_INSECURE AUTO_INIT_GIT_IF_MISSING \
        AUTO_PLAN_BACKFILL_ON_IDLE_BUILD AUTO_REPAIR_MARKDOWN_ARTIFACTS AUTO_REPAIR_MARKDOWN_DRY_RUN AUTO_REPAIR_MARKDOWN_BACKUP \
        AUTO_REPAIR_MARKDOWN_ONLY_SESSION_CHANGED REQUIRE_LINT_BEFORE_DONE REQUIRE_DOCUMENT_BEFORE_DONE \
        REQUIRE_PLAN_BACKLOG_CLEAR_BEFORE_DONE REQUIRE_PLAN_FRESHNESS_FOR_BUILD ENGINE_OVERRIDES_BOOTSTRAPPED \
        NOTIFICATIONS_ENABLED NOTIFY_TELEGRAM_ENABLED NOTIFY_DISCORD_ENABLED NOTIFY_TTS_ENABLED NOTIFICATION_WIZARD_BOOTSTRAPPED \
        RESUME_REQUESTED REBOOTSTRAP_REQUESTED STARTUP_OPERATIONAL_PROBE STRICT_VALIDATION_NOOP PHASE_COMPLETION_RETRY_VERBOSE; do
        normalize_boolean_setting "$name" || return 1
    done
    if is_true "$ENGINE_OUTPUT_TO_STDOUT_EXPLICIT"; then ENGINE_OUTPUT_TO_STDOUT_OVERRIDE="$ENGINE_OUTPUT_TO_STDOUT"; fi
    for name in PRIME_CMD CODEX_CMD CLAUDE_CMD PRIME_PROVIDER PRIME_MODEL PRIME_THINKING_OVERRIDE \
        CODEX_MODEL CLAUDE_MODEL CODEX_ENDPOINT CLAUDE_ENDPOINT CODEX_RESPONSES_SCHEMA_FILE \
        CODEX_THINKING_OVERRIDE CLAUDE_THINKING_OVERRIDE; do
        config_scalar_is_supported "${!name}" || { err "Unsupported multiline value for $name."; return 1; }
    done
    CODEX_THINKING_OVERRIDE="$(to_lower "$CODEX_THINKING_OVERRIDE")"
    case "$CODEX_THINKING_OVERRIDE" in
        none|minimal|low|medium|high|xhigh|"") ;;
        *) err "Unsupported CODEX_THINKING_OVERRIDE '$CODEX_THINKING_OVERRIDE'."; return 1 ;;
    esac
    CLAUDE_THINKING_OVERRIDE="$(to_lower "$CLAUDE_THINKING_OVERRIDE")"
    case "$CLAUDE_THINKING_OVERRIDE" in
        none|off|low|medium|high|xhigh|"") ;;
        *) err "Unsupported CLAUDE_THINKING_OVERRIDE '$CLAUDE_THINKING_OVERRIDE'."; return 1 ;;
    esac
    return 0
}

validate_codex_schema_requirement() {
    if is_true "$CODEX_USE_RESPONSES_SCHEMA" && { [ -z "$CODEX_RESPONSES_SCHEMA_FILE" ] || [ ! -f "$CODEX_RESPONSES_SCHEMA_FILE" ] || [ ! -r "$CODEX_RESPONSES_SCHEMA_FILE" ]; }; then
        err 'CODEX_USE_RESPONSES_SCHEMA requires a readable regular CODEX_RESPONSES_SCHEMA_FILE.'
        return 1
    fi
    return 0
}

# Free CLI metadata has independent, fixed bounds and never spends admission.
run_bounded_engine_metadata() (
    local metadata_dir metadata_pid="" status=0
    local COMMAND_TIMEOUT_SECONDS=3 ENGINE_OUTPUT_MAX_BYTES=65536
    metadata_dir="$(mktemp -d "${TMPDIR:-/tmp}/ralphie_metadata.XXXXXX")" || return 1
    local capture_limit_marker="$metadata_dir/limit"
    local capture_recording_marker="$metadata_dir/recording-ok"
    trap 'if [ -n "$metadata_pid" ] && kill -0 "$metadata_pid" 2>/dev/null; then stop_process_tree "$metadata_pid"; fi; rm -f "$metadata_dir/output" "$metadata_dir/limit" "$metadata_dir/recording-ok"; rmdir "$metadata_dir" 2>/dev/null || true' EXIT
    trap 'exit 143' HUP INT TERM
    : > "$capture_recording_marker" || return 74
    (
        "$@" 2>&1 | {
            metadata_copy_status=0
            head -c 65537 > "$metadata_dir/output" || metadata_copy_status=74
            if metadata_bytes="$(wc -c < "$metadata_dir/output" | tr -d ' ')" && is_number "$metadata_bytes"; then
                if [ "$metadata_bytes" -gt 65536 ]; then : > "$capture_limit_marker" || metadata_copy_status=74; fi
            else
                metadata_copy_status=74
            fi
            if [ "$metadata_copy_status" -ne 0 ]; then mark_engine_capture_failed || exit 74; exit 74; fi
            cat >/dev/null || { mark_engine_capture_failed || exit 74; exit 74; }
        }
    ) &
    metadata_pid=$!
    wait_for_process_with_idle_output_watchdog "$metadata_pid" 0 'CLI metadata' "$metadata_dir/output" >/dev/null 2>&1 || status=$?
    metadata_pid=""
    [ "$status" -eq 0 ] || return "$status"
    cat "$metadata_dir/output"
)

resolve_default_engine_command() {
    case "$1" in
        prime-agent)
            if ! is_true "$PRIME_COMMAND_RESOLVED" && [ "$PRIME_CMD" = "$DEFAULT_PRIME_CMD" ]; then PRIME_CMD="$(discover_prime_command_default)"; fi
            PRIME_COMMAND_RESOLVED=true ;;
        codex)
            if ! is_true "$CODEX_COMMAND_RESOLVED" && [ "$CODEX_CMD" = "$DEFAULT_CODEX_CMD" ]; then CODEX_CMD="$(discover_codex_command_default)"; fi
            CODEX_COMMAND_RESOLVED=true ;;
        claude)
            if ! is_true "$CLAUDE_COMMAND_RESOLVED" && [ "$CLAUDE_CMD" = "$DEFAULT_CLAUDE_CMD" ]; then CLAUDE_CMD="$(discover_claude_command_default)"; fi
            CLAUDE_COMMAND_RESOLVED=true ;;
    esac
    return 0
}

engine_retry_delay() {
    local base="$1" attempt="$2" delay jitter
    if [ "$base" -eq 0 ]; then printf 0; return 0; fi
    if [ "$base" -ge 120 ] || [ "$attempt" -ge 8 ]; then delay=120; else delay=$((base * (1 << (attempt - 1)))); fi
    [ "$delay" -le 120 ] || delay=120
    [ "$base" -le 120 ] || base=120
    jitter=$(( $(portable_random) % (base + 1) ))
    delay=$((delay + jitter))
    [ "$delay" -le 120 ] || delay=120
    printf '%s' "$delay"
}

validate_engine_options() {
    ENGINE_SELECTION_REQUESTED="$(normalize_engine_name "$ENGINE_SELECTION_REQUESTED")"
    AUTO_ENGINE_PREFERENCE="$(normalize_engine_name "$AUTO_ENGINE_PREFERENCE")"
    case "$ENGINE_SELECTION_REQUESTED" in
        auto|prime-agent|codex|claude) ;;
        *) err "Unsupported engine '$ENGINE_SELECTION_REQUESTED'; choose prime-agent, codex, claude or auto."; return 1 ;;
    esac
    case "$AUTO_ENGINE_PREFERENCE" in
        prime-agent|codex|claude) ;;
        *) err "Unsupported AUTO preference '$AUTO_ENGINE_PREFERENCE'."; return 1 ;;
    esac
    PRIME_THINKING_OVERRIDE="$(to_lower "$PRIME_THINKING_OVERRIDE")"
    case "$PRIME_THINKING_OVERRIDE" in
        off|minimal|low|medium|high|xhigh|max|"") ;;
        *) err "Unsupported Prime thinking level '$PRIME_THINKING_OVERRIDE'."; return 1 ;;
    esac
    [ "$ENGINE_SELECTION_REQUESTED" != codex ] || validate_codex_schema_requirement || return 1
    ACTIVE_ENGINE="$ENGINE_SELECTION_REQUESTED"
    if [ "$ACTIVE_ENGINE" = auto ]; then
        ACTIVE_CMD="$(engine_command_for_name "$AUTO_ENGINE_PREFERENCE")"
    else
        ACTIVE_CMD="$(engine_command_for_name "$ACTIVE_ENGINE")"
    fi
    return 0
}

engine_command_for_name() {
    case "$1" in
        prime-agent) printf '%s' "$PRIME_CMD" ;;
        codex) printf '%s' "$CODEX_CMD" ;;
        claude) printf '%s' "$CLAUDE_CMD" ;;
        *) return 1 ;;
    esac
}

engine_name_for_command() {
    case "$1" in
        "$PRIME_CMD") printf 'prime-agent' ;;
        "$CODEX_CMD") printf 'codex' ;;
        "$CLAUDE_CMD") printf 'claude' ;;
        *) return 1 ;;
    esac
}

engine_is_healthy() {
    case "$1" in
        prime-agent) [ "$PRIME_HEALTHY" = true ] || return 1 ;;
        codex) [ "$CODEX_HEALTHY" = true ] || return 1 ;;
        claude) [ "$CLAUDE_HEALTHY" = true ] || return 1 ;;
        *) return 1 ;;
    esac
    command -v "$(engine_command_for_name "$1")" >/dev/null 2>&1
}

# Multi-Agent Capability Detection
probe_engine_capabilities() {
    local force_reprobe="${1:-false}"
    local probe_scope="${2:-${ENGINE_SELECTION_REQUESTED:-auto}}"
    local probe_codex="true"
    local probe_claude="true"
    local probe_prime="true"

    is_true "${ENGINE_BUDGET_EXHAUSTED:-false}" && return 75
    if is_true "$ENGINE_CAPABILITIES_PROBED" && ! is_true "$force_reprobe"; then
        return 0
    fi
    probe_scope="$(to_lower "$probe_scope")"
    if [ "$probe_scope" = auto ] && is_true "${PRIME_OPTIONS_EXPLICIT:-false}"; then probe_scope=prime-agent; fi
    case "$probe_scope" in
        codex)
            probe_claude="false"
            probe_prime="false"
            ;;
        claude)
            probe_codex="false"
            probe_prime="false"
            ;;
        prime-agent|prime)
            probe_codex="false"
            probe_claude="false"
            ;;
        auto|"")
            ;;
        *)
            probe_scope="auto"
            ;;
    esac

    CODEX_CAP_OUTPUT_LAST_MESSAGE=0
    CODEX_CAP_YOLO_FLAG=0
    CODEX_CAP_NOTE=""
    CLAUDE_CAP_NOTE=""
    CLAUDE_CAP_PRINT=0
    CLAUDE_CAP_YOLO_FLAG=""
    CODEX_HEALTHY="false"
    CLAUDE_HEALTHY="false"
    CODEX_SMOKE_PASS="false"
    CLAUDE_SMOKE_PASS="false"
    PRIME_CAP_PRINT=0
    PRIME_CAP_NOTE=""
    PRIME_HEALTHY="false"

    # Readiness proves the installed CLI contract. A paid model request belongs
    # to the actual phase, not an extra startup canary repeated at every gate.
    if ! is_true "$probe_prime"; then
        PRIME_CAP_NOTE="not probed for requested engine scope '$probe_scope'"
    elif resolve_default_engine_command prime-agent && command -v "$PRIME_CMD" >/dev/null 2>&1; then
        local prime_help prime_flag
        prime_help="$(run_bounded_engine_metadata "$PRIME_CMD" --help 2>/dev/null || true)"
        for prime_flag in --print --mode --cwd --offline --no-session --provider --model --thinking; do
            if ! printf '%s\n' "$prime_help" | grep -F -- "$prime_flag" >/dev/null; then
                PRIME_CAP_NOTE="missing required option $prime_flag"
                break
            fi
        done
        if [ -z "$PRIME_CAP_NOTE" ]; then
            PRIME_CAP_PRINT=1
            PRIME_HEALTHY=true
        fi
    else
        PRIME_CAP_NOTE="command not found: $PRIME_CMD"
    fi
    if [ "$probe_scope" = auto ] && [ "$AUTO_ENGINE_PREFERENCE" = prime-agent ] && [ "$PRIME_HEALTHY" = true ]; then
        probe_codex=false
        probe_claude=false
    fi

    # Probing Claude Code
    if ! is_true "$probe_claude"; then
        CLAUDE_CAP_NOTE="not probed for requested engine scope '$probe_scope'"
    elif is_true "$CLAUDE_SMOKE_PERMANENT_FAILURE"; then
        CLAUDE_CAP_NOTE='permanent provider/model/authentication configuration error'
        if [ "$probe_scope" = claude ]; then ENGINE_PERMANENT_FAILURE=true; ENGINE_PERMANENT_FAILURE_REASON="claude: $CLAUDE_CAP_NOTE"; return 126; fi
    elif resolve_default_engine_command claude && command -v "$CLAUDE_CMD" >/dev/null 2>&1; then
        local claude_help
        claude_help="$(run_bounded_engine_metadata "$CLAUDE_CMD" --help 2>/dev/null || true)"
        if echo "$claude_help" | grep -qE -- "-p, --print"; then
            CLAUDE_CAP_PRINT=1
        else
            CLAUDE_CAP_NOTE="missing required --print mode"
        fi

        if echo "$claude_help" | grep -qE -- "--dangerously-skip-permissions"; then
            CLAUDE_CAP_YOLO_FLAG="--dangerously-skip-permissions"
        fi

        if ! echo "$claude_help" | grep -qiE "read|write|tool|file|edit|command"; then
            if is_true "$ENGINE_HEALTH_RETRY_VERBOSE"; then
                warn "Claude help output lacks read/write/tool hints; relying on functional smoke test."
            fi
        fi

        # Functional smoke test: verify engine actually responds
        if [ -z "$CLAUDE_CAP_NOTE" ]; then
            if smoke_test_engine "$CLAUDE_CMD" "claude"; then
                CLAUDE_SMOKE_PASS="true"
            else
                is_true "${ENGINE_BUDGET_EXHAUSTED:-false}" && return 75
                is_true "${ENGINE_PERMANENT_FAILURE:-false}" && return 126
                is_true "$REQUEST_REFRESH_REQUIRED" && return 76
                CLAUDE_CAP_NOTE="smoke test failed: engine unresponsive or returned wrong output"
                CLAUDE_SMOKE_PASS="false"
            fi
        fi

        [ -z "$CLAUDE_CAP_NOTE" ] && CLAUDE_HEALTHY="true"
    else
        CLAUDE_CAP_NOTE="command not found: $CLAUDE_CMD"
    fi

    # Probing Codex
    if ! is_true "$probe_codex"; then
        CODEX_CAP_NOTE="not probed for requested engine scope '$probe_scope'"
    elif is_true "$CODEX_SMOKE_PERMANENT_FAILURE"; then
        CODEX_CAP_NOTE='permanent provider/model/authentication configuration error'
        if [ "$probe_scope" = codex ]; then ENGINE_PERMANENT_FAILURE=true; ENGINE_PERMANENT_FAILURE_REASON="codex: $CODEX_CAP_NOTE"; return 126; fi
    elif resolve_default_engine_command codex && command -v "$CODEX_CMD" >/dev/null 2>&1; then
        local codex_help
        codex_help="$(run_bounded_engine_metadata "$CODEX_CMD" exec --help 2>/dev/null || true)"
        if echo "$codex_help" | grep -qE -- "--output-last-message"; then
            CODEX_CAP_OUTPUT_LAST_MESSAGE=1
        else
            CODEX_CAP_NOTE="missing required --output-last-message"
        fi

        if echo "$codex_help" | grep -qE -- "--dangerously-bypass-approvals-and-sandbox"; then
            CODEX_CAP_YOLO_FLAG=1
        fi

        if ! echo "$codex_help" | grep -qiE "read|write|tool|file|edit|command|exec"; then
            if is_true "$ENGINE_HEALTH_RETRY_VERBOSE"; then
                warn "Codex help output lacks read/write/tool hints; relying on functional smoke test."
            fi
        fi

        # Functional smoke test: verify engine actually responds
        if [ -z "$CODEX_CAP_NOTE" ]; then
            if smoke_test_engine "$CODEX_CMD" "codex"; then
                CODEX_SMOKE_PASS="true"
            else
                is_true "${ENGINE_BUDGET_EXHAUSTED:-false}" && return 75
                is_true "${ENGINE_PERMANENT_FAILURE:-false}" && return 126
                is_true "$REQUEST_REFRESH_REQUIRED" && return 76
                CODEX_CAP_NOTE="smoke test failed: engine unresponsive or returned wrong output"
                CODEX_SMOKE_PASS="false"
            fi
        fi

        [ -z "$CODEX_CAP_NOTE" ] && CODEX_HEALTHY="true"
    else
        CODEX_CAP_NOTE="command not found: $CODEX_CMD"
    fi

    ENGINE_CAPABILITIES_PROBED=true
}

log_engine_health_summary() {
    local prime_line
    local codex_line
    local claude_line
    if [ "$CODEX_HEALTHY" = "true" ]; then
        codex_line="codex: healthy (smoke=${CODEX_SMOKE_PASS})"
    else
        codex_line="codex: unhealthy (${CODEX_CAP_NOTE:-unknown})"
    fi
    if [ "$CLAUDE_HEALTHY" = "true" ]; then
        claude_line="claude: healthy (smoke=${CLAUDE_SMOKE_PASS})"
    else
        claude_line="claude: unhealthy (${CLAUDE_CAP_NOTE:-unknown})"
    fi
    if [ "$PRIME_HEALTHY" = true ]; then
        prime_line="prime-agent: CLI ready (provider connectivity not probed)"
    else
        prime_line="prime-agent: unavailable (${PRIME_CAP_NOTE:-unknown})"
    fi
    info "Engine health: $prime_line | $codex_line | $claude_line"
}

resolve_active_engine() {
    local requested_engine name note
    requested_engine="$(normalize_engine_name "$1")"
    LAST_ENGINE_SELECTION_BLOCK_REASON=""
    if [ "$requested_engine" = auto ]; then
        # A Prime-specific model/provider request cannot be satisfied by
        # borrowing another engine with a different model namespace.
        if is_true "${PRIME_OPTIONS_EXPLICIT:-false}"; then
            requested_engine=prime-agent
        else
            while IFS= read -r name; do
                if engine_is_healthy "$name"; then
                    ACTIVE_ENGINE="$name"
                    ACTIVE_CMD="$(engine_command_for_name "$name")"
                    return 0
                fi
            done < <(engine_auto_order)
            LAST_ENGINE_SELECTION_BLOCK_REASON="AUTO requested but no supported engine is ready."
            return 1
        fi
    fi
    if engine_is_healthy "$requested_engine"; then
        ACTIVE_ENGINE="$requested_engine"
        ACTIVE_CMD="$(engine_command_for_name "$requested_engine")"
        return 0
    fi
    case "$requested_engine" in
        prime-agent) note="$PRIME_CAP_NOTE" ;;
        codex) note="$CODEX_CAP_NOTE" ;;
        claude) note="$CLAUDE_CAP_NOTE" ;;
        *) note="unsupported engine" ;;
    esac
    LAST_ENGINE_SELECTION_BLOCK_REASON="Selected engine '$requested_engine' is unavailable (${note:-unknown}); no engine substitution."
    return 1
}

reviewer_command_candidates() {
    local requested name
    requested="$(normalize_engine_name "${ENGINE_SELECTION_REQUESTED:-auto}")"
    if [ "$requested" = auto ] && is_true "${PRIME_OPTIONS_EXPLICIT:-false}"; then requested=prime-agent; fi
    if [ "$requested" != auto ]; then
        engine_is_healthy "$requested" || return 1
        engine_command_for_name "$requested"
        printf '\n'
        return 0
    fi
    while IFS= read -r name; do
        if engine_is_healthy "$name"; then
            engine_command_for_name "$name"
            printf '\n'
        fi
    done < <(engine_auto_order)
    return 0
}

ensure_engines_ready() {
    local requested_engine="$1"
    local max_attempts="$ENGINE_HEALTH_MAX_ATTEMPTS"
    local base_delay="$ENGINE_HEALTH_RETRY_DELAY_SECONDS"
    local attempt=1
    local preferred_auto_engine="${AUTO_ENGINE_PREFERENCE:-$DEFAULT_AUTO_ENGINE_PREFERENCE}"
    preferred_auto_engine="$(to_lower "$preferred_auto_engine")"
    case "$preferred_auto_engine" in
        prime-agent|codex|claude) ;;
        *) preferred_auto_engine="$DEFAULT_AUTO_ENGINE_PREFERENCE" ;;
    esac

    if ! is_number "$max_attempts" || [ "$max_attempts" -lt 1 ]; then
        max_attempts=1
    fi
    if ! is_number "$base_delay" || [ "$base_delay" -lt 0 ]; then
        base_delay=5
    fi

    while [ "$attempt" -le "$max_attempts" ]; do
        if is_true "$ENGINE_HEALTH_RETRY_VERBOSE"; then
            info "Engine readiness check attempt $attempt/$max_attempts..."
        fi

        probe_engine_capabilities "true" "$requested_engine" || return $?
        ENGINE_CAPABILITIES_PROBED=true

        if is_true "$ENGINE_HEALTH_RETRY_VERBOSE"; then
            log_engine_health_summary
        fi

        if resolve_active_engine "$requested_engine"; then
            if [ "$requested_engine" = "auto" ] && [ "$ACTIVE_ENGINE" != "$preferred_auto_engine" ]; then
                warn "AUTO: preferred $preferred_auto_engine unavailable; proceeding with $ACTIVE_ENGINE."
            fi
            if [ "$attempt" -gt 1 ]; then
                notify_event "phase_decision" "engine_outage_recovered" "engine readiness recovered on attempt $attempt/$max_attempts; active_engine=$ACTIVE_ENGINE" || true
            fi
            if is_true "$ENGINE_HEALTH_RETRY_VERBOSE"; then
                info "Engine ready: $ACTIVE_ENGINE selected (prime-agent=$PRIME_HEALTHY, codex=$CODEX_HEALTHY, claude=$CLAUDE_HEALTHY)"
            fi
            return 0
        fi

        if [ "$attempt" -ge "$max_attempts" ]; then
            warn "Engine readiness check failed after $attempt/$max_attempts attempts: $LAST_ENGINE_SELECTION_BLOCK_REASON"
            return 1
        fi

        local backoff_delay
        backoff_delay="$(engine_retry_delay "$base_delay" "$attempt")"
        warn "Engine readiness blocked (${LAST_ENGINE_SELECTION_BLOCK_REASON}); retrying in ${backoff_delay}s..."
        notify_event "session_error" "engine_outage" "engine readiness blocked: ${LAST_ENGINE_SELECTION_BLOCK_REASON}; attempt $attempt/$max_attempts; retry_in=${backoff_delay}s" || true
        sleep "$backoff_delay"
        attempt=$((attempt + 1))
        ENGINE_CAPABILITIES_PROBED=false
    done
}

# Lock Management (atomic via mkdir)
new_lock_owner_token() {
    local random_part
    random_part="$(portable_random 2>/dev/null || echo 0)"
    printf '%s-%s-%s' "$$" "$(date +%s 2>/dev/null || echo 0)" "$random_part"
}

# The short admission claim serializes stale-owner inspection and publication.
# An abandoned claim is never auto-reclaimed: doing so repeats the same race.
# Callers retain the returned token, including across transaction subshells.
acquire_lock_claim() {
    local claim="$1" wait_seconds="${2:-0}" waited=0 token
    LOCK_CLAIM_TOKEN=""
    is_number "$wait_seconds" || return 1
    ensure_runtime_directory "$(dirname "$claim")" || return 1
    while ! mkdir -m 700 "$claim" 2>/dev/null; do
        if [ -L "$claim" ] || { [ -e "$claim" ] && [ ! -d "$claim" ]; }; then
            err "Refusing unsafe lock admission path: $(path_for_display "$claim")"
            return 1
        fi
        if [ "$waited" -ge "$wait_seconds" ]; then
            err "Lock admission is busy or abandoned: $(path_for_display "$claim"). Retry after the other start exits; if abandoned, verify all launchers are stopped before manually removing this claim directory."
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done
    token="$(new_lock_owner_token)" || { rmdir "$claim"; return 1; }
    if ! (set -C; printf 'pid=%s\ntoken=%s\n' "$$" "$token" > "$claim/owner"); then
        err "Could not publish lock admission owner: $(path_for_display "$claim")"
        return 1
    fi
    LOCK_CLAIM_TOKEN="$token"
    return 0
}

release_lock_claim() {
    local claim="$1" token="$2"
    [ -n "$token" ] && [ -d "$claim" ] && [ ! -L "$claim" ] || return 1
    ensure_runtime_file "$claim/owner" || return 1
    [ -f "$claim/owner" ] && grep -Fxq -- "token=$token" "$claim/owner" || return 1
    rm -f "$claim/owner" && rmdir "$claim"
}

# Requests are mission-bound inputs, never completion evidence. Publication and
# the final done checkpoint share this short claim; no engine runs under it.
request_lock() {
    [ -z "$REQUEST_LOCK_TOKEN" ] || { err 'Request claim is already held.'; return 1; }
    acquire_lock_claim "$REQUEST_CLAIM_DIR" "${1:-2}" || return 1
    REQUEST_LOCK_TOKEN="$LOCK_CLAIM_TOKEN"
}

request_unlock() {
    [ -n "$REQUEST_LOCK_TOKEN" ] || return 0
    release_lock_claim "$REQUEST_CLAIM_DIR" "$REQUEST_LOCK_TOKEN" || return 1
    REQUEST_LOCK_TOKEN=""
}

request_read_binding() {
    local path="$1" lines
    ensure_runtime_file "$path" && [ -f "$path" ] || return 1
    lines="$(wc -l < "$path")" || return 1
    [ "$lines" -eq 2 ] && [ "$(file_size_bytes_safe "$path")" -le 256 ] || return 1
    REQUEST_BOUND_SESSION="$(sed -n '1p' "$path")" || return 1
    REQUEST_BOUND_SEED="$(sed -n '2p' "$path")" || return 1
    case "$REQUEST_BOUND_SESSION" in ''|*[!a-zA-Z0-9_.-]*) return 1;; esac
    case "$REQUEST_BOUND_SEED" in *[!0-9a-f]*) return 1;; esac
    [ -z "$REQUEST_BOUND_SEED" ] || [ "${#REQUEST_BOUND_SEED}" -eq 64 ]
}

request_body_valid() {
    local file="$1" bytes invalid
    [ -f "$file" ] && [ -r "$file" ] || return 1
    bytes="$(file_size_bytes_safe "$file")" || return 1
    [ "$bytes" -ge 1 ] && [ "$bytes" -le 4096 ] || {
        err 'A human request must contain 1–4096 bytes.'; return 1;
    }
    invalid="$(LC_ALL=C tr -d '\011\012\015\040-\176\200-\377' < "$file" | wc -c)" || return 1
    [ "$invalid" -eq 0 ] || {
        err 'Human requests cannot contain NUL, unsupported control bytes or DEL.'; return 1;
    }
    # JSON exposes the exact text, so binary or malformed UTF-8 cannot be accepted.
    LC_ALL=C od -An -v -tu1 < "$file" | LC_ALL=C awk '
        { for (i=1; i<=NF; i++) {
            b=$i+0
            if (need) {
                if (b<lo || b>hi) { bad=1; exit }
                need--; lo=128; hi=191
            } else if (b<=127) { continue }
            else if (b>=194 && b<=223) { need=1; lo=128; hi=191 }
            else if (b>=224 && b<=239) { need=2; lo=(b==224?160:128); hi=(b==237?159:191) }
            else if (b>=240 && b<=244) { need=3; lo=(b==240?144:128); hi=(b==244?143:191) }
            else { bad=1; exit }
        }}
        END { if (bad || need) exit 1 }
    ' || { err 'Human requests must contain valid UTF-8 text.'; return 1; }
}

request_record_valid() {
    local record="$1" name expected actual receipt_generation receipt_hash receipt_role
    [ -d "$record" ] && [ ! -L "$record" ] || return 1
    name="${record##*/}"
    case "$name" in req-*) ;; *) return 1;; esac
    case "$name" in *[!a-zA-Z0-9_-]*) return 1;; esac
    for name in "$record"/*; do
        [ -e "$name" ] || [ -L "$name" ] || continue
        case "${name##*/}" in body|binding|sha256|worker|review) ;; *) return 1;; esac
        ensure_runtime_file "$name" && [ -f "$name" ] || return 1
    done
    ensure_runtime_file "$record/body" && request_body_valid "$record/body" || return 1
    request_read_binding "$record/binding" || return 1
    ensure_runtime_file "$record/sha256" && [ -f "$record/sha256" ] || return 1
    expected="$(cat "$record/sha256")" || return 1
    case "$expected" in *[!0-9a-f]*) return 1;; esac
    [ "${#expected}" -eq 64 ] || return 1
    actual="$(sha256_file_sum "$record/body")" || return 1
    [ "$expected" = "$actual" ] || return 1
    REQUEST_RECORD_SHA="$actual"
    for name in worker review; do
        if [ -e "$record/$name" ] || [ -L "$record/$name" ]; then
            ensure_runtime_file "$record/$name" && [ -s "$record/$name" ] \
                && [ "$(file_size_bytes_safe "$record/$name")" -le 512 ] || return 1
            [ "$(wc -l < "$record/$name")" -eq 3 ] || return 1
            receipt_generation="$(sed -n 's/^generation=//p' "$record/$name")" || return 1
            receipt_hash="$(sed -n 's/^prompt_sha256=//p' "$record/$name")" || return 1
            receipt_role="$(sed -n 's/^role=//p' "$record/$name")" || return 1
            [ "${#receipt_generation}" -eq 64 ] && [ "${#receipt_hash}" -eq 64 ] || return 1
            case "$receipt_generation$receipt_hash" in *[!0-9a-f]*) return 1;; esac
            case "$name:$receipt_role" in worker:worker|review:handoff|review:consensus) ;; *) return 1;; esac
        fi
    done
    return 0
}

request_write_inventory() {
    local record bound_session="$1" bound_seed="$2" count=0 LC_ALL=C
    printf 'mission=%s\nseed=%s\n' "$bound_session" "$bound_seed" || return 1
    for record in "$REQUESTS_DIR/active"/*; do
        [ -e "$record" ] || [ -L "$record" ] || continue
        request_record_valid "$record" || return 1
        [ "$REQUEST_BOUND_SESSION" = "$bound_session" ] && [ "$REQUEST_BOUND_SEED" = "$bound_seed" ] || return 1
        count=$((count + 1))
        [ "$count" -le 32 ] || return 1
        printf '%s %s\n' "${record##*/}" "$REQUEST_RECORD_SHA" || return 1
    done
    REQUEST_ACTIVE_COUNT="$count"
}

request_scan() {
    local manifest bound_session bound_seed record
    REQUEST_ACTIVE_COUNT=0
    REQUEST_CURRENT_FINGERPRINT=""
    REQUEST_BOUND_SESSION=""
    REQUEST_BOUND_SEED=""
    validate_runtime_directory "$REQUESTS_DIR" || return 1
    [ -d "$REQUESTS_DIR" ] || return 0
    validate_runtime_directory "$REQUESTS_DIR/active" && validate_runtime_directory "$REQUESTS_DIR/archive" || return 1
    if [ ! -e "$REQUESTS_DIR/mission" ] && [ ! -L "$REQUESTS_DIR/mission" ]; then
        for record in "$REQUESTS_DIR/active"/*; do
            [ ! -e "$record" ] && [ ! -L "$record" ] || return 1
        done
        return 0
    fi
    request_read_binding "$REQUESTS_DIR/mission" || return 1
    bound_session="$REQUEST_BOUND_SESSION"
    bound_seed="$REQUEST_BOUND_SEED"
    manifest="$(mktemp "$REQUESTS_DIR/.inventory.XXXXXX")" || return 1
    if ! request_write_inventory "$bound_session" "$bound_seed" > "$manifest" \
        || ! REQUEST_CURRENT_FINGERPRINT="$(sha256_file_sum "$manifest")"; then
        rm -f "$manifest"
        err 'Human request storage is corrupt or unsafe; refusing to continue.'
        return 1
    fi
    rm -f "$manifest" || return 1
    REQUEST_BOUND_SESSION="$bound_session"
    REQUEST_BOUND_SEED="$bound_seed"
}

request_validate_mission() {
    request_scan || return 1
    [ -n "$REQUEST_CURRENT_FINGERPRINT" ] \
        && [ "$REQUEST_BOUND_SESSION" = "$SESSION_ID" ] \
        && [ "$REQUEST_BOUND_SEED" = "${MISSION_SEED_SHA:-}" ] || {
        err 'Requests require an initialized saved mission; start or resume Ralphie first.'; return 1;
    }
}

request_fresh_start_allowed() {
    request_scan || return 1
    [ "$REQUEST_ACTIVE_COUNT" -eq 0 ] || {
        err 'Active requests belong to the previous mission. Stop the worker and explicitly archive them before --no-resume.'; return 1;
    }
}

request_publish_file() (
    local source="$1" staging="" id hash
    trap 'if [ -n "$staging" ]; then rm -f "$staging/body" "$staging/binding" "$staging/sha256"; rmdir "$staging" 2>/dev/null || true; fi' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    request_validate_mission && request_body_valid "$source" || return 1
    [ "$CURRENT_PHASE" != done ] || { err 'This mission is complete; start a new mission before submitting a request.'; return 1; }
    [ "$REQUEST_ACTIVE_COUNT" -lt 32 ] || { err 'The mission already has 32 active requests; archive requests while the worker is stopped.'; return 1; }
    staging="$(mktemp -d "$REQUESTS_DIR/.pending.XXXXXX")" || return 1
    id="req-$(new_lock_owner_token)"
    if head -c 4097 "$source" > "$staging/body" \
        && request_body_valid "$staging/body" \
        && hash="$(sha256_file_sum "$staging/body")" \
        && printf '%s\n%s\n' "$SESSION_ID" "${MISSION_SEED_SHA:-}" > "$staging/binding" \
        && printf '%s\n' "$hash" > "$staging/sha256" \
        && [ ! -e "$REQUESTS_DIR/active/$id" ] && [ ! -L "$REQUESTS_DIR/active/$id" ] \
        && mv "$staging" "$REQUESTS_DIR/active/$id"; then
        staging=""
        printf 'Queued request %s (pending worker presentation; not completion).\n' "$id"
        return $?
    fi
    rm -f "$staging/body" "$staging/binding" "$staging/sha256"
    rmdir "$staging" 2>/dev/null || true
    return 1
)

request_archive() {
    local selected="$1" record found=false
    request_validate_mission || return 1
    case "$selected" in all|req-*) ;; *) err 'Use a request ID or all.'; return 1;; esac
    case "$selected" in *[!a-zA-Z0-9_-]*) return 1;; esac
    for record in "$REQUESTS_DIR/active"/*; do
        [ -e "$record" ] || [ -L "$record" ] || continue
        [ "$selected" = all ] || [ "${record##*/}" = "$selected" ] || continue
        request_record_valid "$record" || return 1
        [ ! -e "$REQUESTS_DIR/archive/${record##*/}" ] && [ ! -L "$REQUESTS_DIR/archive/${record##*/}" ] || return 1
        mv "$record" "$REQUESTS_DIR/archive/${record##*/}" || return 1
        found=true
    done
    is_true "$found" || [ "$selected" = all ] || { err 'No active request has that ID.'; return 1; }
    printf 'Archived %s; earlier presentation or work is not undone.\n' "$selected"
}

request_render_list() {
    local format="$1" record status worker review text bytes comma="" binding
    request_validate_mission || return 1
    if [ "$format" = json ]; then
        printf '{"schema":1,"mission_id":"%s","requests":[' "$(json_escape_string "$SESSION_ID")" || return 1
    fi
    for record in "$REQUESTS_DIR/active"/* "$REQUESTS_DIR/archive"/*; do
        [ -e "$record" ] || [ -L "$record" ] || continue
        request_record_valid "$record" || return 1
        binding="$REQUEST_BOUND_SESSION"
        status=queued; worker=false; review=false
        [ ! -s "$record/worker" ] || { worker=true; status=presented; }
        [ ! -s "$record/review" ] || review=true
        case "$record" in "$REQUESTS_DIR/archive/"*) status=archived;; esac
        bytes="$(file_size_bytes_safe "$record/body")" || return 1
        text="$(cat "$record/body" && printf '.')" || return 1
        text="${text%.}"
        if [ "$format" = json ]; then
            printf '%s{"id":"%s","mission_id":"%s","status":"%s","bytes":%s,"worker_presented":%s,"review_presented":%s,"text":"%s"}' \
                "$comma" "${record##*/}" "$(json_escape_string "$binding")" "$status" "$bytes" "$worker" "$review" "$(json_escape_string "$text")" || return 1
            comma=,
        else
            printf '%s  %s  worker=%s review=%s  ' "${record##*/}" "$status" "$worker" "$review" || return 1
            LC_ALL=C tr '\n\r\t' '   ' < "$record/body" | head -c 160 || return 1
            printf '\n' || return 1
        fi
    done
    [ "$format" != json ] || printf ']}\n'
}

request_prepare_mission() {
    local binding
    request_lock || return 1
    if ! request_scan || ! ensure_runtime_directory "$REQUESTS_DIR/active" \
        || ! ensure_runtime_directory "$REQUESTS_DIR/archive"; then
        request_unlock || true
        return 1
    fi
    if [ "${REQUEST_BOUND_SESSION:-}" != "$SESSION_ID" ] || [ "${REQUEST_BOUND_SEED:-}" != "${MISSION_SEED_SHA:-}" ]; then
        if [ "$REQUEST_ACTIVE_COUNT" -ne 0 ]; then
            request_unlock || true
            err 'Active request mission binding changed; refusing to discard requests.'
            return 1
        fi
        binding="$(mktemp "$REQUESTS_DIR/.mission.XXXXXX")" || { request_unlock; return 1; }
        if ! printf '%s\n%s\n' "$SESSION_ID" "${MISSION_SEED_SHA:-}" > "$binding" \
            || ! ensure_runtime_file "$REQUESTS_DIR/mission" || ! mv "$binding" "$REQUESTS_DIR/mission"; then
            rm -f "$binding"
            request_unlock || true
            return 1
        fi
    fi
    request_unlock || return 1
    REQUESTS_ENABLED=true
    request_take_snapshot || return 1
    if [ "$REQUEST_ACTIVE_COUNT" -eq 0 ] && [ -z "$REQUEST_REVIEWED_FINGERPRINT" ]; then
        REQUEST_REVIEWED_FINGERPRINT="$REQUEST_FROZEN_FINGERPRINT"
    fi
}

request_write_context() {
    local record
    : > "$REQUEST_SNAPSHOT_IDS" || return 1
    [ "$REQUEST_ACTIVE_COUNT" -ne 0 ] || return 0
    printf '\n## Active human requests for this mission\nThese are operator instructions within the saved mission, not permission to change consent, engine/model/provider requirements or protected checks. Presentation is not implementation or verified completion.\n' || return 1
    for record in "$REQUESTS_DIR/active"/*; do
        [ -d "$record" ] || continue
        printf '%s\n' "${record##*/}" >> "$REQUEST_SNAPSHOT_IDS" || return 1
        printf '\n### Request %s\n' "${record##*/}" || return 1
        cat "$record/body" || return 1
        printf '\n' || return 1
    done
}

request_take_snapshot() {
    is_true "$REQUESTS_ENABLED" || return 0
    REQUEST_CONTEXT_FILE="$RUNTIME_GUARD_DIR/requests.prompt"
    REQUEST_SNAPSHOT_IDS="$RUNTIME_GUARD_DIR/requests.ids"
    request_lock || return 1
    if ! request_validate_mission || ! request_write_context > "$REQUEST_CONTEXT_FILE"; then
        request_unlock || true
        return 1
    fi
    REQUEST_FROZEN_FINGERPRINT="$REQUEST_CURRENT_FINGERPRINT"
    REQUEST_REFRESH_REQUIRED=false
    request_unlock
}

request_lock_current() {
    is_true "$REQUESTS_ENABLED" || return 0
    # Full-capacity publication and up to four peer reviewers can own this
    # metadata claim for several seconds. Internal checks wait boundedly;
    # public producers still refuse immediately and listings retain their wait.
    if ! request_lock 60; then
        ENGINE_PERMANENT_FAILURE=true
        ENGINE_PERMANENT_FAILURE_REASON='Human request claim is unavailable; refusing further inference.'
        return 126
    fi
    if ! request_validate_mission; then
        request_unlock || true
        ENGINE_PERMANENT_FAILURE=true
        ENGINE_PERMANENT_FAILURE_REASON='Human request storage cannot be validated; refusing further inference.'
        return 126
    fi
    if [ "$REQUEST_CURRENT_FINGERPRINT" != "$REQUEST_FROZEN_FINGERPRINT" ]; then
        request_unlock || true
        REQUEST_REFRESH_REQUIRED=true
        return 76
    fi
}

request_check_generation() {
    is_true "$REQUESTS_ENABLED" || return 0
    request_lock_current || return $?
    request_unlock
}

request_record_presentation() {
    local prompt="$1" id record receipt role=review hash
    is_true "$REQUESTS_ENABLED" || return 0
    request_lock_current || return $?
    hash="$(sha256_file_sum "$prompt")" || { request_unlock; return 126; }
    [ "$REQUEST_ROLE" != worker ] || role=worker
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        record="$REQUESTS_DIR/active/$id"
        receipt="$(mktemp "$record/.presented.XXXXXX")" || { request_unlock; return 126; }
        if ! printf 'generation=%s\nprompt_sha256=%s\nrole=%s\n' "$REQUEST_FROZEN_FINGERPRINT" "$hash" "$REQUEST_ROLE" > "$receipt" \
            || ! ensure_runtime_file "$record/$role" || ! mv "$receipt" "$record/$role"; then
            rm -f "$receipt"
            request_unlock || true
            return 126
        fi
    done < "$REQUEST_SNAPSHOT_IDS"
    request_unlock
}

request_checkpoint_plan_refresh() {
    local phase="$1" attempt="$2"
    log_reason_code RB_HUMAN_REQUEST_REFRESH "$phase approval is stale; new human requests require PLAN"
    write_gate_feedback "$phase" 'New human requests arrived; prior approval cannot promote this work. Refreshing PLAN without resetting inference counters.'
    phase_transition_history_append "$phase" "$attempt" plan hold 'human requests changed'
    CURRENT_PHASE=plan
    CURRENT_PHASE_INDEX=0
    CURRENT_PHASE_ATTEMPT=1
    PHASE_ATTEMPT_IN_PROGRESS=false
    save_state_or_exit 'human request PLAN refresh'
}

write_lock_owner_files() {
    local lock_dir="$1"
    local token="$2"
    local owner_tmp created_at
    ensure_runtime_directory "$lock_dir" || return 1
    ensure_runtime_file "$lock_dir/owner" || return 1
    ensure_runtime_file "$LOCK_FILE" || return 1
    owner_tmp="$lock_dir/owner.tmp.$$"
    ensure_runtime_file "$owner_tmp" || return 1
    created_at="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown)"
    printf 'pid=%s\ntoken=%s\ncreated_at=%s\nrequest_consumer=1\n' "$$" "$token" "$created_at" > "$owner_tmp" || return 1
    mv "$owner_tmp" "$lock_dir/owner" || return 1
    printf '%s\n%s\ntoken=%s\n' "$$" "$created_at" "$token" > "$LOCK_FILE"
}

lock_owner_pid() {
    local lock_dir="${LOCK_FILE}.d"
    local owner_file="$lock_dir/owner"
    local pid=""
    if [ -f "$owner_file" ]; then
        pid="$(sed -n 's/^pid=//p' "$owner_file" 2>/dev/null | head -n 1)"
    fi
    if [ -z "$pid" ] && [ -f "$LOCK_FILE" ]; then
        pid="$(head -n 1 "$LOCK_FILE" 2>/dev/null || echo "")"
    fi
    printf '%s' "$pid"
}

lock_owner_token_matches() {
    local lock_dir="${LOCK_FILE}.d"
    local owner_file="$lock_dir/owner"
    local token="${LOCK_OWNER_TOKEN:-}"
    [ -n "$token" ] || return 1
    if [ -f "$owner_file" ] && grep -Fxq "token=$token" "$owner_file" 2>/dev/null; then
        return 0
    fi
    if [ -f "$LOCK_FILE" ] && grep -Fxq "token=$token" "$LOCK_FILE" 2>/dev/null; then
        return 0
    fi
    return 1
}

acquire_lock() {
    local lock_dir="${LOCK_FILE}.d" claim="${LOCK_FILE}.claim" claim_token holder_pid=""
    ensure_runtime_file "$LOCK_FILE" || return 1
    validate_runtime_directory "$lock_dir" || return 1
    acquire_lock_claim "$claim" 0 || return 1
    claim_token="$LOCK_CLAIM_TOKEN"
    if [ -d "$lock_dir" ]; then
        if ! ensure_runtime_file "$lock_dir/owner"; then
            release_lock_claim "$claim" "$claim_token" || true
            return 1
        fi
        holder_pid="$(lock_owner_pid)"
        if [ -n "$holder_pid" ] && { ! is_number "$holder_pid" || kill -0 "$holder_pid" 2>/dev/null; }; then
            err "Orchestrator lock is active or has invalid owner PID: $holder_pid."
            release_lock_claim "$claim" "$claim_token" || true
            return 1
        fi
        warn "Reclaiming stale orchestrator lock under exclusive admission."
        if ! rm -f "$LOCK_FILE" "$lock_dir/owner" || ! rmdir "$lock_dir"; then
            err "Stale lock contains unexpected files; inspect it with all launchers stopped: $(path_for_display "$lock_dir")"
            release_lock_claim "$claim" "$claim_token" || true
            return 1
        fi
    fi
    if ! mkdir -m 700 "$lock_dir"; then
        release_lock_claim "$claim" "$claim_token" || true
        return 1
    fi
    LOCK_OWNER_TOKEN="$(new_lock_owner_token)"
    if ! write_lock_owner_files "$lock_dir" "$LOCK_OWNER_TOKEN"; then
        err 'Failed to write lock owner metadata; inspect the retained lock before retrying.'
        LOCK_OWNER_TOKEN=""
        release_lock_claim "$claim" "$claim_token" || true
        return 1
    fi
    LOCK_ACQUIRED=true
    release_lock_claim "$claim" "$claim_token" || { err 'Could not release lock admission claim.'; return 1; }
    return 0
}

release_lock() {
    is_true "$LOCK_ACQUIRED" || return 0
    local claim="${LOCK_FILE}.claim" claim_token lock_dir="${LOCK_FILE}.d"
    # A full-capacity request publication can legitimately own admission for
    # several seconds; wait boundedly for it before removing our worker owner.
    if ! acquire_lock_claim "$claim" 60; then
        warn 'Lock release could not obtain admission; retaining lock metadata for safe recovery.'
        return 1
    fi
    claim_token="$LOCK_CLAIM_TOKEN"
    if [ -L "$lock_dir" ] || ! ensure_runtime_file "$lock_dir/owner" \
        || [ ! -f "$lock_dir/owner" ] \
        || ! grep -Fxq -- "token=$LOCK_OWNER_TOKEN" "$lock_dir/owner"; then
        warn "Lock release skipped: current process does not own $(path_for_display "$LOCK_FILE")."
    elif ensure_runtime_file "$LOCK_FILE"; then
        rm -f "$LOCK_FILE" "$lock_dir/owner"
        rmdir "$lock_dir" 2>/dev/null || warn 'Lock directory retains unexpected files; manual inspection required.'
    fi
    LOCK_ACQUIRED=false
    LOCK_OWNER_TOKEN=""
    release_lock_claim "$claim" "$claim_token"
}

register_managed_pid() {
    local pid="${1:-}"
    [ -n "$pid" ] || return 0
    RALPHIE_BG_PIDS+=("$pid")
}

unregister_managed_pid() {
    local pid="${1:-}"
    local registered
    local -a kept=()
    [ -n "$pid" ] || return 0
    for registered in "${RALPHIE_BG_PIDS[@]+"${RALPHIE_BG_PIDS[@]}"}"; do
        [ "$registered" = "$pid" ] && continue
        kept+=("$registered")
    done
    RALPHIE_BG_PIDS=("${kept[@]+"${kept[@]}"}")
}

process_tree_snapshot() {
    local root="${1:-}"
    is_number "$root" && [ "$root" -gt 1 ] && [ "$root" != "$$" ] || return 1
    # One finite ps snapshot avoids a live recursive walk and works without
    # pgrep. Children are emitted before their parents.
    ps -A -o pid= -o ppid= | awk -v root="$root" '
        { parent[$1]=$2 }
        END {
            selected[root]=1; order[++n]=root
            do {
                changed=0
                for (pid in parent) {
                    if (!selected[pid] && selected[parent[pid]]) {
                        selected[pid]=1; order[++n]=pid; changed=1
                    }
                }
            } while (changed)
            for (i=n; i>0; i--) print order[i]
        }
    '
}

signal_process_snapshot() {
    local signal="$1" snapshot="$2" pid
    while IFS= read -r pid; do
        is_number "$pid" && [ "$pid" -gt 1 ] && [ "$pid" != "$$" ] || continue
        kill "-$signal" "$pid" 2>/dev/null || true
    done <<< "$snapshot"
}

terminate_process_tree() {
    local snapshot
    snapshot="$(process_tree_snapshot "${1:-}")" || return 1
    signal_process_snapshot "${2:-TERM}" "$snapshot"
}

stop_process_tree() {
    local snapshot
    snapshot="$(process_tree_snapshot "$1")" || return 1
    signal_process_snapshot TERM "$snapshot"
    sleep 2
    # Reuse the original descendants after TERM may have reparented them.
    signal_process_snapshot KILL "$snapshot"
    return 0
}

cleanup_engine_attempt_files() {
    local dir="${1:-}"
    [ -n "$dir" ] || return 0
    rm -f "$dir"/capture.* "$dir/limit" "$dir/permanent" "$dir/recording-ok" "$dir/stderr" "$dir/stderr-input" "$dir/log" "$dir/prompt" "$dir/answer"
    rmdir "$dir" 2>/dev/null || true
}

cleanup_managed_processes() {
    local pid snapshot current
    snapshot=""
    if [ "${#RALPHIE_BG_PIDS[@]}" -gt 0 ]; then
        for pid in "${RALPHIE_BG_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                current="$(process_tree_snapshot "$pid")" || continue
                snapshot="${snapshot}${current}"$'\n'
            fi
        done
        signal_process_snapshot TERM "$snapshot"
        sleep 2
        signal_process_snapshot KILL "$snapshot"
        RALPHIE_BG_PIDS=()
    fi
    cleanup_engine_attempt_files "${engine_scratch_dir:-}"
    cleanup_phase_commit_files "${phase_commit_tmpdir:-}"
}

cleanup_resources() {
    if is_true "$RALPHIE_CLEANUP_IN_PROGRESS"; then
        return 0
    fi
    RALPHIE_CLEANUP_IN_PROGRESS="true"
    cleanup_managed_processes
    finish_swarm_session_budget 2>/dev/null || warn "Could not import interrupted reviewer inference usage."
    cleanup_review_receipts 2>/dev/null || warn "Could not remove private reviewer receipts."
    if [ -n "${RUNTIME_GUARD_DIR:-}" ]; then
        guard_operator_inputs 2>/dev/null || true
        checkpoint_current_phase_worktree 2>/dev/null || warn "Could not checkpoint interrupted phase ownership."
    fi
    if is_true "$RALPHIE_CLEANUP_STATE_ENABLED"; then
        save_state 2>/dev/null || true
    fi
    # An interruption during done publication must keep producers outside the
    # claim until the final in-memory checkpoint has been made durable.
    request_unlock || warn 'Request claim was retained; inspect its owner before recovery.'
    release_lock
    if [ -n "${RUNTIME_GUARD_DIR:-}" ] && [ -d "$RUNTIME_GUARD_DIR" ] && [ ! -L "$RUNTIME_GUARD_DIR" ]; then
        find "$RUNTIME_GUARD_DIR" -maxdepth 1 -type f -delete 2>/dev/null || true
        rmdir "$RUNTIME_GUARD_DIR" 2>/dev/null || true
        RUNTIME_GUARD_DIR=""
    fi
    RALPHIE_CLEANUP_IN_PROGRESS="false"
}

show_interrupt_menu() {
    local choice
    local output_state

    while true; do
        output_state="$(is_true "$ENGINE_OUTPUT_TO_STDOUT" && echo "on" || echo "off")"
        echo
        warn "Ctrl+C received."
        warn "Live engine output: ${output_state}"
        warn "Actions:"
        warn "  [r] resume (default)"
        warn "  [l] toggle live engine output"
        warn "  [p] persist state and pause"
        warn "  [q] immediate stop"
        warn "  [h] help"
        warn "Enter resumes. Ctrl-D saves and pauses. Ctrl-C stops."
        if ! choice="$(prompt_read_line "Action [r/l/p/q/h]: " "r")"; then
            save_state || { err "Could not save paused state."; cleanup_resources; exit 1; }
            info "State saved. Paused because terminal input closed."
            cleanup_resources
            exit 0
        fi
        case "$(to_lower "$choice")" in
            r|"")
                info "Resuming..."
                return 0
                ;;
            l)
                if is_true "$ENGINE_OUTPUT_TO_STDOUT"; then
                    ENGINE_OUTPUT_TO_STDOUT="false"
                else
                    ENGINE_OUTPUT_TO_STDOUT="true"
                fi
                info "Live engine output is now $(is_true "$ENGINE_OUTPUT_TO_STDOUT" && echo enabled || echo suppressed)."
                save_state || { err "Could not save output preference."; cleanup_resources; exit 1; }
                ;;
            p)
                save_state || { err "Could not save paused state."; cleanup_resources; exit 1; }
                info "State saved and paused."
                cleanup_resources
                exit 0
                ;;
            q)
                warn "Immediate stop requested."
                cleanup_resources
                exit 130
                ;;
            h)
                warn "Live logs can be toggled here without restarting. Use 'p' to exit cleanly and resume later."
                ;;
            *)
                warn "Unknown option: $choice"
                ;;
        esac
    done
}

handle_interrupt() {
    if [ -n "$REQUEST_LOCK_TOKEN" ]; then
        warn 'Interrupt received during a request boundary; saving state and stopping.'
        cleanup_resources
        exit 130
    fi
    if [ "$INTERRUPT_MENU_ACTIVE" = "true" ]; then
        warn "Second interrupt received. Exiting immediately."
        cleanup_resources
        exit 130
    fi
    INTERRUPT_MENU_ACTIVE="true"
    if ! is_tty_input_available; then
        warn "Interrupt received in non-interactive context."
        cleanup_resources
        exit 130
    fi
    cleanup_managed_processes
    show_interrupt_menu
    INTERRUPT_MENU_ACTIVE="false"
}

cleanup() {
    info "Received interrupt. Cleaning up..."
    cleanup_resources
    exit 143
}

install_cleanup_traps() {
    if is_true "$RALPHIE_TRAPS_INSTALLED"; then
        return 0
    fi
    trap handle_interrupt SIGINT
    trap cleanup SIGTERM
    trap cleanup_resources EXIT
    RALPHIE_TRAPS_INSTALLED="true"
}

# Unified Agent Run Function with Exponential Backoff Retries
get_timeout_command() {
    if command -v timeout >/dev/null 2>&1; then echo "timeout"; elif command -v gtimeout >/dev/null 2>&1; then echo "gtimeout"; fi
}

warn_timeout_binary_unavailable_if_needed() {
    # Compatibility entry point: the portable watchdog enforces the same
    # deadline whether or not a timeout executable is installed.
    return 0
}

file_size_bytes_safe() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo 0
        return 0
    fi
    wc -c < "$file" 2>/dev/null | tr -d ' ' || echo 0
}

aggregate_output_bytes() {
    local total=0
    local file bytes
    for file in "$@"; do
        [ -n "$file" ] || continue
        bytes="$(file_size_bytes_safe "$file")"
        if ! is_number "$bytes"; then
            bytes=0
        fi
        total=$((total + bytes))
    done
    echo "$total"
}

wait_for_process_with_idle_output_watchdog() {
    local pid="$1"
    local idle_timeout="${2:-0}"
    local label="${3:-process}"
    shift 3 || true
    local -a watch_files=("$@")
    local now
    local last_progress
    local observed_bytes
    local previous_bytes
    local started hard_timeout ceiling file bytes status first_poll
    hard_timeout="${COMMAND_TIMEOUT_SECONDS:-0}"
    is_number "$hard_timeout" || hard_timeout=0
    ceiling="${ENGINE_OUTPUT_MAX_BYTES:-16777216}"
    is_number "$ceiling" && [ "$ceiling" -gt 0 ] || ceiling=16777216

    is_number "$idle_timeout" || idle_timeout=0

    previous_bytes="$(aggregate_output_bytes "${watch_files[@]+"${watch_files[@]}"}")"
    last_progress="$(date +%s 2>/dev/null || echo 0)"
    is_number "$last_progress" || last_progress=0
    started="$last_progress"
    first_poll=true

    while kill -0 "$pid" 2>/dev/null; do
        if is_true "$first_poll"; then
            first_poll=false
            sleep 0.05
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.95
        else
            sleep 1
        fi
        if [ -n "${capture_recording_marker:-}" ] && [ ! -f "$capture_recording_marker" ]; then
            warn "Could not record output for ${label}."
            stop_process_tree "$pid"
            wait "$pid" 2>/dev/null || true
            return 74
        fi
        if [ -n "${capture_limit_marker:-}" ] && [ -f "$capture_limit_marker" ]; then
            warn "Output limit exceeded for ${label} (${ceiling} bytes)."
            stop_process_tree "$pid"
            wait "$pid" 2>/dev/null || true
            return 125
        fi
        observed_bytes="$(aggregate_output_bytes "${watch_files[@]+"${watch_files[@]}"}")"
        if is_number "$observed_bytes" && [ "$observed_bytes" -gt "$previous_bytes" ]; then
            previous_bytes="$observed_bytes"
            last_progress="$(date +%s 2>/dev/null || echo 0)"
            is_number "$last_progress" || last_progress=0
        fi

        now="$(date +%s 2>/dev/null || echo 0)"
        is_number "$now" || now=0
        for file in "${watch_files[@]+"${watch_files[@]}"}"; do
            bytes="$(file_size_bytes_safe "$file")"
            if [ "$bytes" -gt "$ceiling" ]; then
                warn "Output limit exceeded for ${label} (${ceiling} bytes)."
                stop_process_tree "$pid"
                wait "$pid" 2>/dev/null || true
                return 125
            fi
        done
        kill -0 "$pid" 2>/dev/null || break
        if [ "$hard_timeout" -gt 0 ] && [ "$started" -gt 0 ] && [ $((now - started)) -ge "$hard_timeout" ]; then
            warn "Command deadline reached for ${label} (${hard_timeout}s)."
            log_reason_code "RB_COMMAND_TIMEOUT" "${label} reached its ${hard_timeout}s deadline"
            stop_process_tree "$pid"
            wait "$pid" 2>/dev/null || true
            return 124
        fi
        if [ "$idle_timeout" -gt 0 ] && [ "$last_progress" -gt 0 ] && [ "$now" -gt 0 ] && [ $((now - last_progress)) -ge "$idle_timeout" ]; then
            warn "Idle-output watchdog tripped for ${label}: no new output for ${idle_timeout}s. Recycling process."
            log_reason_code "RB_IDLE_OUTPUT_WATCHDOG" "idle output watchdog tripped for ${label} (${idle_timeout}s without new output)"
            stop_process_tree "$pid"
            wait "$pid" 2>/dev/null || true
            return 124
        fi
    done

    if wait "$pid"; then status=0; else status=$?; fi
    if [ -n "${capture_recording_marker:-}" ] && [ ! -f "$capture_recording_marker" ]; then return 74; fi
    if [ -n "${capture_limit_marker:-}" ] && [ -f "$capture_limit_marker" ]; then return 125; fi
    # Fast file-answer producers may exit between polls.
    for file in "${watch_files[@]+"${watch_files[@]}"}"; do
        bytes="$(file_size_bytes_safe "$file")"
        [ "$bytes" -le "$ceiling" ] || return 125
    done
    return "$status"
}

run_agent_with_prompt() {
    local prompt_file="$1"
    local log_file="$2"
    local output_file="$3"
    local yolo_effective="$4"
    local attempt_no="${5:-1}"
    local idle_output_timeout="${ENGINE_IDLE_OUTPUT_TIMEOUT_SECONDS:-0}"
    local exit_code=0
    local -a engine_args=()
    local -a engine_prefix=()
    local stream_output_file="$output_file"
    local stderr_file="" stderr_pipe="" stream_status stderr_status stderr_pid trimmed_log
    local capture_limit_marker="" capture_permanent_marker="" capture_recording_marker="" engine_scratch_dir="" permanent_detected=false
    ensure_runtime_file "$log_file" && ensure_runtime_file "$output_file" || return 2
    ensure_runtime_directory "$(dirname "$log_file")" && ensure_runtime_directory "$(dirname "$output_file")" || return 2

    if is_true "${ENGINE_BUDGET_EXHAUSTED:-false}"; then
        err "${ENGINE_BUDGET_FAILURE_REASON:-Session inference budget exhausted.}"
        : > "$output_file"
        return 75
    fi
    if is_true "${ENGINE_PERMANENT_FAILURE:-false}"; then
        err "${ENGINE_PERMANENT_FAILURE_REASON:-Engine provider/model/authentication configuration failed.}"
        : > "$output_file"
        return 126
    fi
    if [ ! -f "$prompt_file" ]; then
        err "Prompt file not found: $prompt_file"
        return 2
    fi
    request_check_generation || return $?
    if is_true "$REQUESTS_ENABLED" && [ -s "$REQUEST_CONTEXT_FILE" ]; then
        local request_prompt="$log_file.requests.prompt.md"
        if ! ensure_runtime_file "$request_prompt" || ! cat "$prompt_file" "$REQUEST_CONTEXT_FILE" > "$request_prompt"; then
            ENGINE_PERMANENT_FAILURE=true
            ENGINE_PERMANENT_FAILURE_REASON='Could not record the human-request prompt; refusing further inference.'
            return 126
        fi
        prompt_file="$request_prompt"
    fi
    if [ -z "${ACTIVE_CMD:-}" ] || ! command -v "$ACTIVE_CMD" >/dev/null 2>&1; then
        err "Active engine command unavailable: ${ACTIVE_CMD:-<unset>}"
        return 2
    fi
    if [ "$ACTIVE_ENGINE" = "codex" ] && [ "$CODEX_HEALTHY" != "true" ]; then
        err "Selected engine 'codex' is currently marked unhealthy: ${CODEX_CAP_NOTE:-missing required capability state}"
        return 2
    fi
    if [ "$ACTIVE_ENGINE" = "claude" ] && [ "$CLAUDE_HEALTHY" != "true" ]; then
        err "Selected engine 'claude' is currently marked unhealthy: ${CLAUDE_CAP_NOTE:-missing required capability state}"
        return 2
    fi
    if [ "$ACTIVE_ENGINE" = "prime-agent" ] && [ "$PRIME_HEALTHY" != "true" ]; then
        err "Selected engine 'prime-agent' is currently marked unavailable: ${PRIME_CAP_NOTE:-missing required capability state}"
        return 2
    fi
    if ! is_number "$idle_output_timeout" || [ "$idle_output_timeout" -lt 0 ]; then
        idle_output_timeout="$DEFAULT_ENGINE_IDLE_OUTPUT_TIMEOUT_SECONDS"
    fi

    probe_engine_capabilities || return $?

    if [ "$ACTIVE_ENGINE" = "prime-agent" ]; then
        if ! is_true "$PRIME_CAP_PRINT"; then
            err "Prime capability missing: non-interactive print mode is required."
            return 2
        fi
        engine_args=("$ACTIVE_CMD" -p --mode text --cwd "$PROJECT_DIR" --offline --no-session)
        [ -n "$PRIME_PROVIDER" ] && engine_args+=(--provider "$PRIME_PROVIDER")
        [ -n "$PRIME_MODEL" ] && engine_args+=(--model "$PRIME_MODEL")
        [ -n "$PRIME_THINKING_OVERRIDE" ] && engine_args+=(--thinking "$PRIME_THINKING_OVERRIDE")
        idle_output_timeout=0
    elif [ "$ACTIVE_ENGINE" = "codex" ]; then
        if ! is_true "$CODEX_CAP_OUTPUT_LAST_MESSAGE"; then
            err "Codex capability missing: --output-last-message is required."
            return 2
        fi

        if [ -n "$CODEX_ENDPOINT" ]; then
            engine_prefix=("env" "OPENAI_BASE_URL=$CODEX_ENDPOINT")
        fi

        engine_args=("$ACTIVE_CMD" "exec")
        [ -n "${CODEX_MODEL:-}" ] && engine_args+=("--model" "$CODEX_MODEL")
        if [ -n "$CODEX_THINKING_OVERRIDE" ]; then
            engine_args+=("-c" "model_reasoning_effort=\"$CODEX_THINKING_OVERRIDE\"")
        fi
        validate_codex_schema_requirement || return 2
        if is_true "$CODEX_USE_RESPONSES_SCHEMA"; then engine_args+=("--output-schema" "$CODEX_RESPONSES_SCHEMA_FILE"); fi

        if is_true "$yolo_effective" && is_true "$CODEX_CAP_YOLO_FLAG"; then
            engine_args+=("--dangerously-bypass-approvals-and-sandbox")
        fi
        engine_args+=(- --output-last-message "$output_file")
        stream_output_file=""
    elif [ "$ACTIVE_ENGINE" = "claude" ]; then
        if ! is_true "$CLAUDE_CAP_PRINT"; then
            err "Claude capability missing: print mode is required."
            return 2
        fi

        engine_args=("$ACTIVE_CMD" "-p")
        [ -n "${CLAUDE_MODEL:-}" ] && engine_args+=("--model" "$CLAUDE_MODEL")
        case "$CLAUDE_THINKING_OVERRIDE" in
            high|xhigh)
                engine_args+=("--settings" '{"alwaysThinkingEnabled":true}')
                ;;
            none|off|low)
                engine_args+=("--settings" '{"alwaysThinkingEnabled":false}')
                ;;
            medium|"")
                :
                ;;
            *)
                :
                ;;
        esac
        if [ -n "$CLAUDE_ENDPOINT" ]; then
            engine_prefix=("env" "ANTHROPIC_BASE_URL=$CLAUDE_ENDPOINT")
        fi

        if is_true "$yolo_effective"; then
            [ -n "$CLAUDE_CAP_YOLO_FLAG" ] && engine_args+=("$CLAUDE_CAP_YOLO_FLAG")
            if [ "${#engine_prefix[@]}" -eq 0 ]; then
                engine_prefix=("env" "IS_SANDBOX=1")
            else
                engine_prefix+=("IS_SANDBOX=1")
            fi
        fi
        engine_args+=(-)
        # Print mode can legitimately remain silent until the final answer.
        idle_output_timeout=0
    else
        err "Unsupported active engine '$ACTIVE_ENGINE'."
        return 2
    fi

    local attempt=1
    local max_run_attempts="${RUN_AGENT_MAX_ATTEMPTS}"
    local retry_delay="${RUN_AGENT_RETRY_DELAY_SECONDS}"
    if ! is_number "$max_run_attempts" || [ "$max_run_attempts" -lt 1 ]; then
        max_run_attempts="$DEFAULT_RUN_AGENT_MAX_ATTEMPTS"
    fi
    if ! is_number "$retry_delay" || [ "$retry_delay" -lt 0 ]; then
        retry_delay="$DEFAULT_RUN_AGENT_RETRY_DELAY_SECONDS"
    fi

    while [ "$attempt" -le "$max_run_attempts" ]; do
        request_check_generation || return $?
        info "Dispatching ${ACTIVE_ENGINE} for attempt ${attempt}/${max_run_attempts} (phase attempt ${attempt_no}) with prompt $(path_for_display "$prompt_file")."
        : > "$log_file"
        : > "$output_file"
        engine_scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/ralphie_engine.XXXXXX")" || return 1
        capture_limit_marker="$engine_scratch_dir/limit"
        capture_permanent_marker="$engine_scratch_dir/permanent"
        capture_recording_marker="$engine_scratch_dir/recording-ok"
        if ! : > "$capture_recording_marker"; then
            cleanup_engine_attempt_files "$engine_scratch_dir"
            ENGINE_PERMANENT_FAILURE=true
            ENGINE_PERMANENT_FAILURE_REASON='Could not prepare engine output capture; refusing further inference.'
            return 126
        fi
        permanent_detected=false
        if [ "$ACTIVE_ENGINE" = prime-agent ]; then
            stderr_file="$engine_scratch_dir/stderr"
            stderr_pipe="$engine_scratch_dir/stderr-input"
            : > "$stderr_file"
            if ! mkfifo "$stderr_pipe"; then
                cleanup_engine_attempt_files "$engine_scratch_dir"
                return 1
            fi
        fi
        if ! admit_session_attempt "${ACTIVE_ENGINE} attempt ${attempt}/${max_run_attempts}"; then
            cleanup_engine_attempt_files "$engine_scratch_dir"
            return 75
        fi
        local request_presentation_status=0
        request_record_presentation "$prompt_file" || request_presentation_status=$?
        if [ "$request_presentation_status" -ne 0 ]; then
            cleanup_engine_attempt_files "$engine_scratch_dir"
            if [ "$request_presentation_status" -ne 76 ]; then
                ENGINE_PERMANENT_FAILURE=true
                ENGINE_PERMANENT_FAILURE_REASON='Could not record human-request presentation; refusing further inference.'
                return 126
            fi
            return 76
        fi
        if [ "$ACTIVE_ENGINE" = prime-agent ]; then
            (
                trap "$(printf 'cleanup_engine_attempt_files %q; exit 143' "$engine_scratch_dir")" HUP INT TERM
                trap "$(printf 'rm -f -- %q/capture.*' "$engine_scratch_dir")" EXIT
                cd "$PROJECT_DIR" || exit 2
                # Diagnostics never enter Prime's completion/reviewer answer.
                # Wait for their bounded drain as well as the stdout pipeline.
                stream_engine_output "$stderr_file" "" false < "$stderr_pipe" &
                stderr_pid=$!
                if "${engine_args[@]}" 2> "$stderr_pipe" < "$prompt_file" \
                    | stream_engine_output "$log_file" "$output_file" "$ENGINE_OUTPUT_TO_STDOUT"; then
                    stream_status=0
                else
                    stream_status=$?
                fi
                if wait "$stderr_pid"; then stderr_status=0; else stderr_status=$?; fi
                [ "$stream_status" -ne 0 ] || stream_status="$stderr_status"
                exit "$stream_status"
            ) &
        else
            (
                trap "$(printf 'cleanup_engine_attempt_files %q; exit 143' "$engine_scratch_dir")" HUP INT TERM
                trap "$(printf 'rm -f -- %q/capture.*' "$engine_scratch_dir")" EXIT
                cd "$PROJECT_DIR" || exit 2
                "${engine_prefix[@]+"${engine_prefix[@]}"}" "${engine_args[@]}" 2>&1 < "$prompt_file" \
                    | stream_engine_output "$log_file" "$stream_output_file" "$ENGINE_OUTPUT_TO_STDOUT"
            ) &
        fi
        local agent_pid=$!
        register_managed_pid "$agent_pid"
        if wait_for_process_with_idle_output_watchdog "$agent_pid" "$idle_output_timeout" "${ACTIVE_ENGINE} attempt ${attempt}/${max_run_attempts}" "$log_file" "$output_file" "$stderr_file"; then
            exit_code=0
        else
            exit_code=$?
        fi
        unregister_managed_pid "$agent_pid"
        if [ -n "$stderr_file" ] && [ -f "$stderr_file" ]; then
            cat "$stderr_file" >> "$log_file" || exit_code=74
            stderr_file=""
            stderr_pipe=""
            if [ "$(file_size_bytes_safe "$log_file")" -gt "$ENGINE_OUTPUT_MAX_BYTES" ]; then
                [ "$exit_code" -eq 74 ] || exit_code=125
                trimmed_log="$engine_scratch_dir/log"
                if ! head -c "$ENGINE_OUTPUT_MAX_BYTES" "$log_file" > "$trimmed_log" || ! cat "$trimmed_log" > "$log_file"; then
                    exit_code=74
                fi
            fi
        fi
        [ ! -f "$capture_permanent_marker" ] || permanent_detected=true
        cleanup_engine_attempt_files "$engine_scratch_dir"
        engine_scratch_dir=""
        capture_limit_marker=""
        capture_permanent_marker=""
        capture_recording_marker=""
        if ! guard_operator_inputs; then
            charge_session_budget "$(estimate_run_tokens "$prompt_file" "$log_file" "$output_file")" || return 75
            return 1
        fi
        charge_session_budget "$(estimate_run_tokens "$prompt_file" "$log_file" "$output_file")" || return 75
        if [ "$exit_code" -eq 74 ]; then
            ENGINE_PERMANENT_FAILURE=true
            ENGINE_PERMANENT_FAILURE_REASON='Could not record engine output; refusing further inference.'
            : > "$output_file" || true
            err "$ENGINE_PERMANENT_FAILURE_REASON"
            return 126
        fi
        if [ "$exit_code" -eq 0 ] || ! is_true "$permanent_detected"; then
            request_check_generation || return $?
        fi
        if [ "$exit_code" -eq 0 ]; then
            break
        fi
        if [ "$exit_code" -eq 125 ]; then
            : > "$output_file"
            warn "Engine output limit exceeded; not retrying this attempt."
            break
        fi

        local hiccup_detected=false
        local permanent_failure=false
        # Known configuration/authentication failures cannot be repaired by a
        # paid retry, including when their diagnostic also says "token error".
        if [ "$exit_code" -ne 0 ] && is_true "$permanent_detected"; then
            permanent_failure=true
        elif grep -qiE "backend error|token error|timeout|connection refused|overloaded|rate.?limit|503|502|429|ECONNRESET|ETIMEDOUT" "$log_file" 2>/dev/null; then
            hiccup_detected=true
        elif [ "$exit_code" -eq 124 ] || [ "$exit_code" -eq 137 ] || [ "$exit_code" -eq 143 ]; then
            # 124=timeout, 137=SIGKILL, 143=SIGTERM
            hiccup_detected=true
        elif [ "$exit_code" -ne 0 ]; then
            # Unknown non-zero exits may be transient (agent crash, OOM, etc.).
            hiccup_detected=true
        fi

        # If the engine command itself disappeared, mark unhealthy so the next
        # ensure_engines_ready call at the loop boundary can detect and switch.
        if ! is_true "$permanent_failure" && is_true "$hiccup_detected"; then
            if ! command -v "$ACTIVE_CMD" >/dev/null 2>&1; then
                warn "Engine command '$ACTIVE_CMD' no longer available; marking $ACTIVE_ENGINE unhealthy."
                if [ "$ACTIVE_ENGINE" = "prime-agent" ]; then
                    PRIME_HEALTHY="false"
                    PRIME_CAP_NOTE="command disappeared mid-session"
                elif [ "$ACTIVE_ENGINE" = "codex" ]; then
                    CODEX_HEALTHY="false"
                    CODEX_CAP_NOTE="command disappeared mid-session"
                    CODEX_SMOKE_PASS="false"
                else
                    CLAUDE_HEALTHY="false"
                    CLAUDE_CAP_NOTE="command disappeared mid-session"
                    CLAUDE_SMOKE_PASS="false"
                fi
                ENGINE_CAPABILITIES_PROBED=false
            fi
        fi

        if is_true "$permanent_failure"; then
            ENGINE_PERMANENT_FAILURE=true
            ENGINE_PERMANENT_FAILURE_REASON="$ACTIVE_ENGINE provider/model/authentication configuration failed; see $(path_for_display "$log_file")."
            exit_code=126
            : > "$output_file"
            warn "$ENGINE_PERMANENT_FAILURE_REASON Not retrying or changing engines."
            break
        fi

        if ! enforce_session_budget "${ACTIVE_ENGINE} failed attempt"; then
            return 75
        fi
        if is_true "$hiccup_detected" && [ "$attempt" -lt "$max_run_attempts" ]; then
            local backoff_delay
            backoff_delay="$(engine_retry_delay "$retry_delay" "$attempt")"
            if is_true "$RUN_AGENT_RETRY_VERBOSE"; then
                warn "Inference hiccup detected (exit=$exit_code) on attempt $attempt/$max_run_attempts. Retrying in ${backoff_delay}s..."
            fi
            sleep "$backoff_delay"
            attempt=$((attempt + 1))
            continue
        fi
        break
    done

    if [ "$exit_code" -ne 0 ]; then
        log_reason_code "RB_RUN_AGENT_RETRY_EXHAUSTED" "run_agent failed after ${attempt} attempts (limit ${max_run_attempts}) for $(path_for_display "$prompt_file") with last_exit=$exit_code"
    fi

    # 76 is private boundary control only when our generation check returns it.
    # Preserve the engine's observed status above, but never treat its failure
    # as a human request or silently spend a fresh PLAN cycle for it.
    [ "$exit_code" -ne 76 ] || return 1
    return "$exit_code"
}

consensus_reviewer_persona() {
    local stage="${1:-plan}"
    local reviewer_index="${2:-1}"
    local normalized_index

    is_number "$reviewer_index" || reviewer_index=1
    normalized_index=$(( (reviewer_index - 1) % 6 ))
    if [ "$normalized_index" -lt 0 ]; then
        normalized_index=0
    fi

    case "$normalized_index" in
        0) echo "Architect: validate scope integrity, assumptions, and future maintainability for ${stage}." ;;
        1) echo "Skeptic: challenge edge cases, hidden risks, and silent failure modes in ${stage}." ;;
        2) echo "Execution Reviewer: verify concrete evidence and artifact completeness from this attempt." ;;
        3) echo "Safety Reviewer: enforce policy compliance, guardrails, and regression risk containment." ;;
        4) echo "Operations Reviewer: focus on operational impact, deployment readiness, and reversibility." ;;
        5) echo "Quality Reviewer: prioritize signal quality, confidence, and decision consistency." ;;
    esac
}

cleanup_review_receipts() {
    [ -n "${RUNTIME_GUARD_DIR:-}" ] || return 0
    [ -d "$RUNTIME_GUARD_DIR" ] && [ ! -L "$RUNTIME_GUARD_DIR" ] || return 1
    local receipt
    for receipt in "$RUNTIME_GUARD_DIR"/swarm-review.* "$RUNTIME_GUARD_DIR"/handoff-review.*; do
        [ -e "$receipt" ] || [ -L "$receipt" ] || continue
        [ -d "$receipt" ] && [ ! -L "$receipt" ] || return 1
        # find does not follow links; remove only these private receipt trees.
        find "$receipt" -depth -mindepth 1 -delete || return 1
        rmdir "$receipt" || return 1
    done
    return 0
}

write_reviewer_status() {
    local path="$1" reviewer_index="$2" engine="$3" command="$4" exit_code="$5" reason="$6"
    local status=failure failure_kind=''
    [ "$exit_code" -ne 0 ] || status=success
    case "$exit_code" in 75) failure_kind=budget;; 76) failure_kind=request;; 126) failure_kind=permanent;; esac
    printf 'reviewer_index=%s\nengine=%s\ncommand=%s\nexit_code=%s\nfailure_kind=%s\nfailure_reason=%s\nstatus=%s\n' \
        "$reviewer_index" "$engine" "$command" "$exit_code" "$failure_kind" \
        "$(sanitize_text_for_log "$reason")" "$status" > "$path"
}

run_swarm_reviewer() {
    local reviewer_index="$1"
    local prompt_file="$2"
    local log_file="$3"
    local output_file="$4"
    local status_file="$5"
    local primary_cmd="$6"
    local fallback_cmd="$7"
    local receipt_dir="${8:-}"
    local public_output_file="$output_file" public_status_file="$status_file"
    if [ -n "$receipt_dir" ]; then
        ensure_runtime_directory "$receipt_dir" || return 1
        output_file="$receipt_dir/answer"
        status_file="$receipt_dir/status"
    fi
    ensure_runtime_file "$output_file" && ensure_runtime_file "$status_file" || return 1
    local COMMAND_TIMEOUT_SECONDS="${COMMAND_TIMEOUT_SECONDS:-0}"
    local reviewer_timeout="${SWARM_CONSENSUS_TIMEOUT:-600}"
    is_number "$reviewer_timeout" && [ "$reviewer_timeout" -gt 0 ] || reviewer_timeout=600
    if [ "$COMMAND_TIMEOUT_SECONDS" -le 0 ] || [ "$COMMAND_TIMEOUT_SECONDS" -gt "$reviewer_timeout" ]; then
        COMMAND_TIMEOUT_SECONDS="$reviewer_timeout"
    fi

    local -a candidate_cmds=("$primary_cmd")
    [ -n "$fallback_cmd" ] && [ "$fallback_cmd" != "$primary_cmd" ] && candidate_cmds+=("$fallback_cmd")

    rm -f "$status_file" || return 1
    local attempt_cmd
    local attempt_exit=1
    local used_cmd="${primary_cmd}"
    local invalid_reason=""
    local validation_mode="consensus"
    local REQUEST_ROLE=consensus
    ACTIVE_ENGINE="unknown"
    ACTIVE_CMD=""

    if [ "$reviewer_index" = "handoff" ]; then
        validation_mode="handoff"
        REQUEST_ROLE=handoff
    fi

    for attempt_cmd in "${candidate_cmds[@]}"; do
        [ -n "$attempt_cmd" ] || continue
        if ! ACTIVE_ENGINE="$(engine_name_for_command "$attempt_cmd")"; then
            # Guard against custom command aliases unexpectedly routing to the
            # wrong engine mode.
            warn "Reviewer command '$attempt_cmd' did not match configured engines; skipping."
            continue
        fi
        engine_is_healthy "$ACTIVE_ENGINE" || continue
        if [ "${ENGINE_SELECTION_REQUESTED:-auto}" != auto ] && [ "$ACTIVE_ENGINE" != "$ENGINE_SELECTION_REQUESTED" ]; then
            continue
        fi
        if [ "${ENGINE_SELECTION_REQUESTED:-auto}" = auto ] && is_true "${PRIME_OPTIONS_EXPLICIT:-false}" && [ "$ACTIVE_ENGINE" != prime-agent ]; then
            continue
        fi
        ACTIVE_CMD="$attempt_cmd"
        used_cmd="$attempt_cmd"

        rm -f "$output_file" || return 1
        if run_agent_with_prompt "$prompt_file" "$log_file" "$output_file" "false" "$reviewer_index"; then
            invalid_reason="$(review_output_invalid_reason "$output_file" "$validation_mode")"
            if [ -z "$invalid_reason" ]; then
                attempt_exit=0
                break
            fi
            local raw_invalid_output=""
            raw_invalid_output="${public_output_file}.invalid.${ACTIVE_ENGINE}.${reviewer_index}"
            ensure_runtime_file "$raw_invalid_output" && mv "$output_file" "$raw_invalid_output" 2>/dev/null || raw_invalid_output=""
            write_invalid_reviewer_output_placeholder "$output_file" "$invalid_reason" "$raw_invalid_output"
            warn "Reviewer $reviewer_index output from ${ACTIVE_ENGINE:-unknown} was rejected: $invalid_reason"
            attempt_exit=1
            if ! enforce_session_budget "rejected reviewer output"; then
                attempt_exit=75
                break
            fi
            continue
        else
            attempt_exit=$?
            # A provider/model requirement is not authority to try another
            # engine, even for an otherwise automatic reviewer schedule.
            case "$attempt_exit" in 75|76|126) break;; esac
        fi
    done

    if [ -n "$receipt_dir" ]; then
        if [ -f "$output_file" ] && { ! ensure_runtime_file "$public_output_file" || ! cp "$output_file" "$public_output_file"; }; then
            [ "$attempt_exit" -ne 0 ] || attempt_exit=1
            invalid_reason="could not publish reviewer output"
        fi
        if ! ensure_runtime_file "$public_status_file" || ! write_reviewer_status "$public_status_file" "$reviewer_index" "${ACTIVE_ENGINE:-unknown}" "$used_cmd" "$attempt_exit" "$invalid_reason"; then
            [ "$attempt_exit" -ne 0 ] || attempt_exit=1
            invalid_reason="could not publish reviewer status"
        fi
        # Publish complete private receipts last. A failed/partial write cannot
        # leave a success record for the reducer, even inside a conditional call.
        write_reviewer_status "$status_file.tmp" "$reviewer_index" "${ACTIVE_ENGINE:-unknown}" "$used_cmd" "$attempt_exit" "$invalid_reason" || return 1
        mv "$status_file.tmp" "$status_file" || return 1
    else
        ensure_runtime_file "$status_file" || return 1
        write_reviewer_status "$status_file" "$reviewer_index" "${ACTIVE_ENGINE:-unknown}" "$used_cmd" "$attempt_exit" "$invalid_reason" || return 1
    fi
    return "$attempt_exit"
}

build_consensus_evidence_context() {
    local phase="$1"
    local attempt="$2"
    local output_file="$3"
    local log_file="$4"
    local handoff_output_file="$5"
    local handoff_status_file="$6"
    local manifest_before_file="$7"
    local manifest_after_file="$8"
    local delta_preview="$9"
    local warning_text="${10}"
    local previous_output="${11}"
    local prior_output_display="none"

    [ -f "$previous_output" ] && prior_output_display="$(path_for_display "$previous_output")"

    {
        echo "Current phase artifacts:"
        echo "- phase: $phase"
        echo "- attempt: $attempt"
        echo "- completion output: $(path_for_display "$output_file")"
        echo "- execution log: $(path_for_display "$log_file")"
        echo "- handoff status: $(path_for_display "$handoff_status_file")"
        echo "- handoff output: $(path_for_display "$handoff_output_file")"
        echo "- previous completion output: $prior_output_display"
        echo "- manifest before: $(path_for_display "$manifest_before_file")"
        echo "- manifest after: $(path_for_display "$manifest_after_file")"
        echo ""
        echo "Worktree delta preview:"
        if [ -n "$delta_preview" ]; then
            while IFS= read -r delta_line; do
                [ -n "$delta_line" ] || continue
                echo "- $delta_line"
            done <<< "$delta_preview"
        else
            echo "- no visible delta preview"
        fi
        echo ""
        echo "Phase warnings:"
        if [ -n "$warning_text" ]; then
            printf '%s\n' "$warning_text" | sed 's/^/- /'
        else
            echo "- none"
        fi
        echo ""
        echo "Completion output snippet:"
        safe_print_file_head "$output_file" 120
        echo ""
        echo "Execution log tail:"
        safe_print_file_tail "$log_file" 40
        echo ""
        echo "Handoff validator status:"
        if [ -f "$handoff_status_file" ]; then
            sed -n '1,20p' "$handoff_status_file"
        else
            echo "- not available"
        fi
        echo ""
        echo "Handoff validator output snippet:"
        safe_print_file_head "$handoff_output_file" 60
    }
}

run_swarm_consensus() {
    local stage="$1"
    local history_context="${2:-}"
    local evidence_context="${3:-}"
    local count
    local parallel
    count="$(get_reviewer_count)"
    parallel="$(get_parallel_reviewer_count)"
    local base_stage="${stage%-gate}"
    CONSENSUS_NO_ENGINES=false
    local default_next_phase
    local next_phase_vote_plan=0
    local next_phase_vote_build=0
    local next_phase_vote_test=0
    local next_phase_vote_refactor=0
    local next_phase_vote_lint=0
    local next_phase_vote_document=0
    local next_phase_vote_done=0
    local total_next_votes=0

    # Preserve global engine state before swarm (reviewers run in subshells
    # but run_swarm_reviewer also modifies globals in the parent fallback path)
    local saved_engine="$ACTIVE_ENGINE"
    local saved_cmd="$ACTIVE_CMD"

    default_next_phase="$(phase_default_next "$base_stage")"
    info "Running deep consensus swarm for '$stage'..."
    local consensus_dir="$CONSENSUS_DIR/$stage/$SESSION_ID"
    LAST_CONSENSUS_DIR="$consensus_dir"
    LAST_CONSENSUS_SUMMARY=""
    LAST_CONSENSUS_NEXT_PHASE="$default_next_phase"
    LAST_CONSENSUS_NEXT_PHASE_REASON="insufficient consensus responses"
    LAST_CONSENSUS_RESPONDED_VOTES=0
    LAST_CONSENSUS_NEXT_PHASE_VOTES=0
    LAST_CONSENSUS_GO_VOTES=0
    LAST_CONSENSUS_BLOCKING_GAP_VOTES=0
    LAST_CONSENSUS_FAILURE_KIND="none"
    LAST_CONSENSUS_FAILURE_REASON=""
    ensure_runtime_directory "$consensus_dir" || return 1
    runtime_guard_prepare || return 1
    local review_receipts_dir
    cleanup_review_receipts || return 1
    review_receipts_dir="$(mktemp -d "$RUNTIME_GUARD_DIR/swarm-review.XXXXXX")" || return 1

    local -a prompts=() logs=() outputs=() status_files=() review_outputs=() review_status_files=()
    local -a primary_cmds=() fallback_cmds=() summary_lines=()
    local reviewer_engine_request="${ENGINE_SELECTION_REQUESTED:-$DEFAULT_ENGINE}"
    local reviewer_engine_policy="mixed:auto"
    local available_cmd
    local -a available_cmds=()
    if [ "$reviewer_engine_request" != auto ]; then
        reviewer_engine_policy="pinned:${reviewer_engine_request}"
    elif is_true "${PRIME_OPTIONS_EXPLICIT:-false}"; then
        reviewer_engine_policy="pinned:prime-agent"
    fi
    while IFS= read -r available_cmd; do
        [ -n "$available_cmd" ] && available_cmds+=("$available_cmd")
    done < <(reviewer_command_candidates)
    info "Consensus reviewer policy: $reviewer_engine_policy"
    if [ "${#available_cmds[@]}" -eq 0 ]; then
        warn "No ready reviewer engine satisfies '$reviewer_engine_policy'."
        LAST_CONSENSUS_SCORE=0
        LAST_CONSENSUS_PASS=false
        LAST_CONSENSUS_NEXT_PHASE="$default_next_phase"
        LAST_CONSENSUS_NEXT_PHASE_REASON="no ready reviewer engine for requested policy"
        LAST_CONSENSUS_RESPONDED_VOTES=0
        LAST_CONSENSUS_NEXT_PHASE_VOTES=0
        LAST_CONSENSUS_FAILURE_KIND="infra"
        LAST_CONSENSUS_FAILURE_REASON="no ready reviewer engine for '$reviewer_engine_policy'"
        CONSENSUS_NO_ENGINES=true
        ACTIVE_ENGINE="$saved_engine"
        ACTIVE_CMD="$saved_cmd"
        return 1
    fi

    local i
    for i in $(seq 1 "$count"); do
        local primary_cmd fallback_cmd candidate_index
        candidate_index=$(( (i - 1) % ${#available_cmds[@]} ))
        primary_cmd="${available_cmds[$candidate_index]}"
        fallback_cmd=""
        if [ "${#available_cmds[@]}" -gt 1 ]; then
            candidate_index=$(( (candidate_index + 1) % ${#available_cmds[@]} ))
            fallback_cmd="${available_cmds[$candidate_index]}"
        fi

        prompts+=("$consensus_dir/reviewer_${i}_prompt.md")
        logs+=("$consensus_dir/reviewer_${i}.log")
        outputs+=("$consensus_dir/reviewer_${i}.out")
        status_files+=("$consensus_dir/reviewer_${i}.status")
        review_outputs+=("$review_receipts_dir/reviewer_${i}/answer")
        review_status_files+=("$review_receipts_dir/reviewer_${i}/status")
        ensure_runtime_file "${prompts[$((i - 1))]}" && ensure_runtime_file "${logs[$((i - 1))]}" \
            && ensure_runtime_file "${outputs[$((i - 1))]}" && ensure_runtime_file "${status_files[$((i - 1))]}" || return 1
        primary_cmds+=("$primary_cmd")
        fallback_cmds+=("$fallback_cmd")

        {
            echo "# Consensus Review: $stage"
            consensus_prompt_for_stage "$base_stage" "$history_context" "$evidence_context" "$(consensus_reviewer_persona "$base_stage" "$i")"
        } > "${prompts[$((i - 1))]}"
    done

    local active=0
    if finite_session_budget; then
        # Admission must see the preceding review's usage before another paid
        # request starts. A parallel ceiling does not require concurrency.
        for i in $(seq 0 $((count - 1))); do
            local reviewer_exit=0
            run_swarm_reviewer \
                "$((i + 1))" \
                "${prompts[$i]}" \
                "${logs[$i]}" \
                "${outputs[$i]}" \
                "${status_files[$i]}" \
                "${primary_cmds[$i]}" \
                "${fallback_cmds[$i]}" \
                "$review_receipts_dir/reviewer_$((i + 1))" || reviewer_exit=$?
            case "$reviewer_exit" in 75|76|126) break;; esac
        done
    else
        runtime_guard_prepare || return 1
        SWARM_BUDGET_RECEIPT_DIR="$(mktemp -d "$RUNTIME_GUARD_DIR/swarm-budget.XXXXXX")" || return 1
        SWARM_BUDGET_BASE_ATTEMPTS="$SESSION_ATTEMPT_COUNT"
        SWARM_BUDGET_BASE_TOKENS="$SESSION_TOKEN_COUNT"
        SWARM_BUDGET_BASE_COST="$SESSION_COST_CENTS"
        for i in $(seq 0 $((count - 1))); do
            (
                SESSION_ATTEMPT_COUNT=0
                SESSION_TOKEN_COUNT=0
                SESSION_COST_CENTS=0
                SESSION_BUDGET_RECEIPT_FILE="$SWARM_BUDGET_RECEIPT_DIR/reviewer_${i}.usage"
                run_swarm_reviewer \
                    "$((i + 1))" \
                    "${prompts[$i]}" \
                    "${logs[$i]}" \
                    "${outputs[$i]}" \
                    "${status_files[$i]}" \
                    "${primary_cmds[$i]}" \
                    "${fallback_cmds[$i]}" \
                    "$review_receipts_dir/reviewer_$((i + 1))"
            ) &
            register_managed_pid "$!"
            active=$((active + 1))
            if [ "$active" -ge "$parallel" ] || [ "$i" -eq $((count - 1)) ]; then
                # wait -n requires Bash 4.3+; use portable fallback
                if [ "${BASH_VERSINFO[0]:-3}" -gt 4 ] || { [ "${BASH_VERSINFO[0]:-3}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -ge 3 ]; }; then
                    wait -n 2>/dev/null || true
                else
                    # Portable: poll only swarm PIDs until at least one finishes
                    while true; do
                        local __alive=0
                        for __pid in "${RALPHIE_BG_PIDS[@]+"${RALPHIE_BG_PIDS[@]}"}"; do
                            kill -0 "$__pid" 2>/dev/null && __alive=$((__alive + 1))
                        done
                        [ "$__alive" -lt "$active" ] && break
                        sleep 0.2 2>/dev/null || sleep 1
                    done
                fi
                active=$((active - 1))
            fi
        done
    fi
    # Wait for all reviewers with a safety timeout to prevent infinite hangs
    local swarm_timeout="${SWARM_CONSENSUS_TIMEOUT:-$DEFAULT_SWARM_CONSENSUS_TIMEOUT}"
    is_number "$swarm_timeout" || swarm_timeout=600
    local swarm_start swarm_elapsed
    swarm_start="$(date +%s)"
    local swarm_timed_out=false
    while true; do
        local running_jobs=0
        local __active_jobs=()
            for __pid in "${RALPHIE_BG_PIDS[@]+"${RALPHIE_BG_PIDS[@]}"}"; do
                if kill -0 "$__pid" 2>/dev/null; then
                    __active_jobs+=("$__pid")
                    running_jobs=$((running_jobs + 1))
                fi
            done
            RALPHIE_BG_PIDS=("${__active_jobs[@]+"${__active_jobs[@]}"}")
            [ "${running_jobs:-0}" -eq 0 ] && break
            swarm_elapsed=$(( $(date +%s) - swarm_start ))
            if [ "$swarm_elapsed" -ge "$swarm_timeout" ]; then
                warn "Swarm consensus timeout after ${swarm_timeout}s. Killing hung reviewers."
                swarm_timed_out=true
                cleanup_managed_processes
                break
            fi
        sleep 1
    done
    wait 2>/dev/null || true
    # Clean PID registry to prevent stale accumulation
    RALPHIE_BG_PIDS=()
    finish_swarm_session_budget || return 75
    if is_true "${ENGINE_BUDGET_EXHAUSTED:-false}"; then
        LAST_CONSENSUS_FAILURE_KIND=budget
        LAST_CONSENSUS_FAILURE_REASON="$ENGINE_BUDGET_FAILURE_REASON"
        ACTIVE_ENGINE="$saved_engine"
        ACTIVE_CMD="$saved_cmd"
        return 75
    fi
    local request_status_file
    for request_status_file in "${review_status_files[@]}"; do
        if [ -f "$request_status_file" ] && grep -qx 'exit_code=126' "$request_status_file"; then
            ENGINE_PERMANENT_FAILURE=true
            ENGINE_PERMANENT_FAILURE_REASON='Reviewer failed permanently; refusing further inference.'
            LAST_CONSENSUS_FAILURE_KIND=permanent
            LAST_CONSENSUS_FAILURE_REASON="$ENGINE_PERMANENT_FAILURE_REASON"
            ACTIVE_ENGINE="$saved_engine"
            ACTIVE_CMD="$saved_cmd"
            return 126
        fi
        if [ -f "$request_status_file" ] && grep -qx 'exit_code=76' "$request_status_file"; then
            REQUEST_REFRESH_REQUIRED=true
        fi
    done
    if is_true "$REQUEST_REFRESH_REQUIRED"; then
        LAST_CONSENSUS_FAILURE_KIND=request
        LAST_CONSENSUS_FAILURE_REASON='Human requests changed during consensus; refresh PLAN.'
        ACTIVE_ENGINE="$saved_engine"
        ACTIVE_CMD="$saved_cmd"
        return 76
    fi
    if [ "$swarm_timed_out" = true ]; then
        log_reason_code "RB_SWARM_TIMEOUT" "consensus reviewers exceeded timeout (${swarm_timeout}s) for stage $stage"
        LAST_CONSENSUS_FAILURE_KIND="infra"
        LAST_CONSENSUS_FAILURE_REASON="consensus swarm timeout after ${swarm_timeout}s"
    fi

    local total_score=0
    local go_votes=0
    local blocking_gap_votes=0
    local responded_votes=0
    local required_votes="$count"
    local avg_score=0
    local next_phase_vote_reason=""

    local idx=0
    local status_file status engine failure_reason verdict score verdict_gaps next_phase next_phase_reason
    local recommended_next="$default_next_phase"
    local highest_next_votes=0
    local candidate_votes=0
    for ofile in "${review_outputs[@]}"; do
        status="failure"
        engine="unknown"
        failure_reason=""
        verdict="HOLD"
        score="0"
        verdict_gaps="no explicit gaps"
        next_phase="$default_next_phase"
        next_phase_reason=""

        status_file="${review_status_files[$idx]}"
        if [ -f "$status_file" ]; then
            if grep -qx 'exit_code=75' "$status_file"; then
                ENGINE_BUDGET_EXHAUSTED=true
                ENGINE_BUDGET_FAILURE_REASON="Reviewer inference budget could not admit another call."
                LAST_CONSENSUS_FAILURE_KIND=budget
                LAST_CONSENSUS_FAILURE_REASON="$ENGINE_BUDGET_FAILURE_REASON"
                ACTIVE_ENGINE="$saved_engine"
                ACTIVE_CMD="$saved_cmd"
                return 75
            fi
            if grep -qx 'exit_code=126' "$status_file"; then
                ENGINE_PERMANENT_FAILURE=true
                ENGINE_PERMANENT_FAILURE_REASON="Reviewer failed permanently; see $(path_for_display "${status_files[$idx]}")."
                LAST_CONSENSUS_FAILURE_KIND=permanent
                LAST_CONSENSUS_FAILURE_REASON="$ENGINE_PERMANENT_FAILURE_REASON"
                ACTIVE_ENGINE="$saved_engine"
                ACTIVE_CMD="$saved_cmd"
                return 126
            fi
            status="$(grep -E "^status=" "$status_file" | head -n 1 | cut -d'=' -f2-)"
            engine="$(grep -E "^engine=" "$status_file" | head -n 1 | cut -d'=' -f2-)"
            engine="$(sanitize_text_for_log "$engine" | cut -c 1-40)"
            failure_reason="$(grep -E "^failure_reason=" "$status_file" | head -n 1 | cut -d'=' -f2- || true)"
            failure_reason="$(sanitize_text_for_log "$failure_reason" | cut -c 1-180)"
            [ "$status" = "success" ] || status="failure"
        fi

        if [ "$status" = "success" ] && [ -f "$ofile" ]; then
            score="$(extract_review_score "$ofile")"
            verdict="$(extract_review_verdict "$ofile")"

            next_phase="$(extract_xml_value "$ofile" "next_phase" "$default_next_phase")"
            next_phase="$(normalize_next_phase_recommendation "$next_phase" "$base_stage" "$default_next_phase")"
            next_phase_reason="$(extract_xml_value "$ofile" "next_phase_reason" "")"
            verdict_gaps="$(extract_review_gaps "$ofile" 180)"
            next_phase_reason="$(sanitize_text_for_log "$next_phase_reason")"
            [ -n "$next_phase_reason" ] || next_phase_reason="no explicit phase-routing rationale"
        else
            if [ -n "$failure_reason" ]; then
                verdict_gaps="reviewer failure: $failure_reason"
                next_phase_reason="reviewer failure: $failure_reason"
            else
                verdict_gaps="no valid output artifact"
                next_phase_reason="no valid output artifact"
            fi
        fi

        [ "$status" = "success" ] && responded_votes=$((responded_votes + 1))
        [ "$status" = "success" ] && total_score=$((total_score + score))
        if [ "$status" = "success" ] && is_phase_or_done "$next_phase"; then
            total_next_votes=$((total_next_votes + 1))
            case "$next_phase" in
                plan) next_phase_vote_plan=$((next_phase_vote_plan + 1)) ;;
                build) next_phase_vote_build=$((next_phase_vote_build + 1)) ;;
                test) next_phase_vote_test=$((next_phase_vote_test + 1)) ;;
                refactor) next_phase_vote_refactor=$((next_phase_vote_refactor + 1)) ;;
                lint) next_phase_vote_lint=$((next_phase_vote_lint + 1)) ;;
                document) next_phase_vote_document=$((next_phase_vote_document + 1)) ;;
                done) next_phase_vote_done=$((next_phase_vote_done + 1)) ;;
            esac
            if [ -z "$next_phase_vote_reason" ] && [ -n "$next_phase_reason" ]; then
                next_phase_vote_reason="$next_phase_reason"
            fi
        fi

        [ "$status" = "success" ] && [ "$verdict" = "GO" ] && go_votes=$((go_votes + 1))
        if [ "$status" = "success" ] && review_gaps_are_blocking "$verdict_gaps"; then
            blocking_gap_votes=$((blocking_gap_votes + 1))
        fi
        summary_lines+=("reviewer_$((idx + 1)):engine=$engine status=$status score=$score verdict=$verdict next=$next_phase reason=$next_phase_reason gaps=$verdict_gaps")
        idx=$((idx + 1))
    done

    if [ "$responded_votes" -gt 0 ]; then
        avg_score=$((total_score / responded_votes))
    fi

    if [ "$total_next_votes" -gt 0 ]; then
        local -a vote_phases=("plan" "build" "test" "refactor" "lint" "document" "done")
        local -a vote_counts=(
            "$next_phase_vote_plan"
            "$next_phase_vote_build"
            "$next_phase_vote_test"
            "$next_phase_vote_refactor"
            "$next_phase_vote_lint"
            "$next_phase_vote_document"
            "$next_phase_vote_done"
        )
        local -a tied_phases=()
        local vote_index=0
        local tie_summary=""
        local tie_phase=""
        local tie_count=0

        highest_next_votes=0
        for vote_index in "${!vote_counts[@]}"; do
            candidate_votes="${vote_counts[$vote_index]}"
            if [ "$candidate_votes" -gt "$highest_next_votes" ]; then
                highest_next_votes="$candidate_votes"
            fi
        done

        for vote_index in "${!vote_counts[@]}"; do
            candidate_votes="${vote_counts[$vote_index]}"
            if [ "$candidate_votes" -eq "$highest_next_votes" ] && [ "$candidate_votes" -gt 0 ]; then
                tied_phases+=("${vote_phases[$vote_index]}")
            fi
        done

        tie_count="${#tied_phases[@]}"
        local next_phase_required_votes
        next_phase_required_votes=$((responded_votes / 2 + 1))
        if [ "$next_phase_required_votes" -lt 1 ]; then
            next_phase_required_votes=1
        fi
        if [ "$highest_next_votes" -lt "$next_phase_required_votes" ]; then
            recommended_next="$default_next_phase"
            warn "Consensus next-phase vote lacked majority (${highest_next_votes}/${responded_votes}); defaulting to $default_next_phase."
            if [ -n "$next_phase_vote_reason" ]; then
                next_phase_vote_reason="$next_phase_vote_reason (no majority: ${highest_next_votes}/${responded_votes} -> default $default_next_phase)"
            else
                next_phase_vote_reason="no majority on next_phase votes (${highest_next_votes}/${responded_votes}) -> defaulted to $default_next_phase"
            fi
        elif [ "$tie_count" -eq 1 ]; then
            recommended_next="${tied_phases[0]}"
        elif [ "$tie_count" -gt 1 ]; then
            recommended_next="$default_next_phase"
            for tie_phase in "${tied_phases[@]}"; do
                tie_summary="${tie_summary}${tie_summary:+, }$tie_phase"
            done
            warn "Consensus next-phase vote tie ($tie_summary at ${highest_next_votes} votes each); defaulting to $default_next_phase."
            if [ -n "$next_phase_vote_reason" ]; then
                next_phase_vote_reason="$next_phase_vote_reason (tie: $tie_summary -> default $default_next_phase)"
            else
                next_phase_vote_reason="tie on next_phase votes ($tie_summary) -> defaulted to $default_next_phase"
            fi
        fi
    fi

    LAST_CONSENSUS_NEXT_PHASE="$recommended_next"
    [ -n "$next_phase_vote_reason" ] || next_phase_vote_reason="no explicit routing rationale"
    LAST_CONSENSUS_NEXT_PHASE_REASON="$next_phase_vote_reason"
    LAST_CONSENSUS_RESPONDED_VOTES="$responded_votes"
    LAST_CONSENSUS_NEXT_PHASE_VOTES="$highest_next_votes"
    LAST_CONSENSUS_GO_VOTES="$go_votes"
    LAST_CONSENSUS_BLOCKING_GAP_VOTES="$blocking_gap_votes"
    LAST_CONSENSUS_SCORE="$avg_score"
    if [ "${#summary_lines[@]}" -gt 0 ]; then
        LAST_CONSENSUS_SUMMARY="$(printf '%s; ' "${summary_lines[@]}")"
    else
        LAST_CONSENSUS_SUMMARY=""
    fi
    local clean_consensus_go=false
    if [ "$responded_votes" -ge "$required_votes" ] && [ "$go_votes" -ge "$required_votes" ] && [ "$blocking_gap_votes" -eq 0 ]; then
        clean_consensus_go=true
    fi
    if [ "$responded_votes" -ge "$required_votes" ] && [ "$go_votes" -ge "$required_votes" ] && [ "$blocking_gap_votes" -eq 0 ] && review_score_passes_threshold "$avg_score" "$clean_consensus_go"; then
        LAST_CONSENSUS_PASS=true
        LAST_CONSENSUS_FAILURE_KIND="none"
        LAST_CONSENSUS_FAILURE_REASON=""
        ACTIVE_ENGINE="$saved_engine"
        ACTIVE_CMD="$saved_cmd"
        return 0
    fi
    LAST_CONSENSUS_PASS=false
    if [ "$LAST_CONSENSUS_FAILURE_KIND" != "infra" ]; then
        if [ "$responded_votes" -lt "$required_votes" ]; then
            LAST_CONSENSUS_FAILURE_KIND="infra"
            LAST_CONSENSUS_FAILURE_REASON="insufficient reviewer responses ($responded_votes/$required_votes)"
        else
            LAST_CONSENSUS_FAILURE_KIND="quality"
            LAST_CONSENSUS_FAILURE_REASON="consensus HOLD (go_votes=$go_votes/$required_votes, blocking_gaps=$blocking_gap_votes/$responded_votes, avg_score=$avg_score, threshold=$CONSENSUS_SCORE_THRESHOLD)"
        fi
    fi
    ACTIVE_ENGINE="$saved_engine"
    ACTIVE_CMD="$saved_cmd"
    return 1
}

write_handoff_validation_prompt() {
    local phase="$1"
    local attempt="$2"
    local output_file="$3"
    local log_file="$4"
    local prompt_file="$5"
    local manifest_before_file="$6"
    local manifest_after_file="$7"
    local delta_preview="$8"
    local noop_policy="$9"
    local warning_text="${10}"
    local previous_output="${11}"

    local prior_output_display="none"
    [ -f "$previous_output" ] && prior_output_display="$(path_for_display "$previous_output")"

    {
        echo "# Handoff Validation Prompt"
        echo ""
        echo "You are the on-rail handoff validator."
        echo "Phase: $phase"
        echo "Attempt: $attempt"
        echo "Session: $SESSION_ID"
        echo "Iteration: $ITERATION_COUNT"
        echo "Handoff policy: $noop_policy"
        echo "Execution output: $(path_for_display "$output_file")"
        echo "Execution log: $(path_for_display "$log_file")"
        echo "Previous output: $prior_output_display"
        echo "Manifest before: $(path_for_display "$manifest_before_file")"
        echo "Manifest after: $(path_for_display "$manifest_after_file")"
        echo "Delta preview:"
        if [ -n "$delta_preview" ]; then
            while IFS= read -r delta_line; do
                echo "- $delta_line"
            done <<< "$delta_preview"
        else
            echo "- no visible delta preview"
        fi
        echo ""
        echo "Recent warnings:"
        if [ -n "$warning_text" ]; then
            printf '%s\n' "$warning_text" | sed 's/^/- /'
        else
            echo "- none"
        fi
        echo ""
        echo "Rules:"
        echo "- Confirm execution output indicates concrete artifact progress for this phase."
        echo "- Confirm handoff artifacts are coherent and transition intent is explicit."
        echo "- Confirm no policy blockers are hidden."
        echo "- Emit machine-readable signal:"
    echo "  <score>0-100</score>"
    echo "  <verdict>GO|HOLD</verdict>"
    echo "  <gaps>comma-separated blockers or none</gaps>"

    if [ -f "$previous_output" ]; then
        echo "Previous handoff output snippet:"
        safe_print_file_head "$previous_output" 40
    fi

    echo "Current execution output snippet:"
    safe_print_file_head "$output_file" 80

    echo "Current execution log tail:"
    safe_print_file_tail "$log_file" 40
    } > "$prompt_file"
}

read_handoff_review_output() {
    local output_file="$1"
    local score=0
    local verdict="HOLD"
    local gaps="no explicit gaps"

    LAST_HANDOFF_SCORE=0
    LAST_HANDOFF_VERDICT="HOLD"
    LAST_HANDOFF_GAPS="no explicit gaps"

    [ -f "$output_file" ] || return 0

    local invalid_reason
    invalid_reason="$(review_output_invalid_reason "$output_file" "handoff")"
    if [ -n "$invalid_reason" ]; then
        LAST_HANDOFF_GAPS="invalid reviewer output: $(sanitize_text_for_log "$invalid_reason" | cut -c 1-160)"
        return 0
    fi

    score="$(extract_review_score "$output_file")"
    verdict="$(extract_review_verdict "$output_file")"
    gaps="$(extract_review_gaps "$output_file" 180)"

    LAST_HANDOFF_SCORE="$score"
    LAST_HANDOFF_VERDICT="$verdict"
    LAST_HANDOFF_GAPS="$gaps"
}

run_handoff_validation() {
    local phase="$1"
    local prompt_file="$2"
    local log_file="$3"
    local output_file="$4"
    local status_file="$5"
    local primary_cmd="${6:-}"
    local fallback_cmd="${7:-}"

    if [ ! -f "$prompt_file" ]; then
        err "Handoff validation prompt missing: $prompt_file"
        return 1
    fi

    # Preserve engine state — run_swarm_reviewer mutates ACTIVE_ENGINE/ACTIVE_CMD
    local saved_engine="$ACTIVE_ENGINE"
    local saved_cmd="$ACTIVE_CMD"
    local review_receipt_dir reviewer_exit=0
    runtime_guard_prepare || return 1
    cleanup_review_receipts || return 1
    review_receipt_dir="$(mktemp -d "$RUNTIME_GUARD_DIR/handoff-review.XXXXXX")" || return 1

    run_swarm_reviewer \
        "handoff" \
        "$prompt_file" \
        "$log_file" \
        "$output_file" \
        "$status_file" \
        "$primary_cmd" \
        "$fallback_cmd" \
        "$review_receipt_dir" || reviewer_exit=$?
    if [ "$reviewer_exit" -eq 76 ]; then
        REQUEST_REFRESH_REQUIRED=true
        ACTIVE_ENGINE="$saved_engine"
        ACTIVE_CMD="$saved_cmd"
        return 76
    fi
    read_handoff_review_output "$review_receipt_dir/answer"

    # Restore engine state
    ACTIVE_ENGINE="$saved_engine"
    ACTIVE_CMD="$saved_cmd"

    local status="failure"
    if [ "$reviewer_exit" -eq 0 ] && [ -f "$review_receipt_dir/status" ]; then
        status="$(grep -E "^status=" "$review_receipt_dir/status" | head -n 1 | cut -d'=' -f2- || true)"
        [ "$status" = "success" ] || status="failure"
    fi

    local handoff_clean_go=false
    if [ "$LAST_HANDOFF_VERDICT" = "GO" ] && ! review_gaps_are_blocking "$LAST_HANDOFF_GAPS"; then
        handoff_clean_go=true
    fi
    if [ "$status" = "success" ] && is_number "$LAST_HANDOFF_SCORE" && [ "$LAST_HANDOFF_VERDICT" = "GO" ] && ! review_gaps_are_blocking "$LAST_HANDOFF_GAPS" && review_score_passes_threshold "$LAST_HANDOFF_SCORE" "$handoff_clean_go"; then
        return 0
    fi

    log_reason_code "RB_PHASE_HANDOFF_VALIDATOR_HOLD" "Handoff validation failed for $phase (score=${LAST_HANDOFF_SCORE}, verdict=${LAST_HANDOFF_VERDICT}, gaps=${LAST_HANDOFF_GAPS})"
    return 1
}

path_relative_to_project() {
    local value="${1:-}"
    if [ -z "$value" ]; then
        echo ""
        return 0
    fi
    case "$value" in
        "$PROJECT_DIR"/*) echo "${value#"$PROJECT_DIR"/}" ;;
        *) echo "${value#./}" ;;
    esac
}

phase_manifest_file_size_and_mtime() {
    local path="$1"
    if [ ! -e "$path" ]; then
        echo "-1 -1"
        return 0
    fi
    if stat -f '%z %m' "$path" >/dev/null 2>&1; then
        stat -f '%z %m' "$path" 2>/dev/null || echo "-1 -1"
        return 0
    fi
    if stat -c '%s %Y' "$path" >/dev/null 2>&1; then
        stat -c '%s %Y' "$path" 2>/dev/null || echo "-1 -1"
        return 0
    fi
    echo "-1 -1"
}

runtime_file_mode() {
    local mode
    if mode="$(stat -f '%Lp' "$1" 2>/dev/null)"; then :
    elif mode="$(stat -c '%a' "$1" 2>/dev/null)"; then :
    else return 1; fi
    case "$mode" in ''|*[!0-7]*) return 1;; esac
    printf '%s' "$mode"
}

gitlink_tree_signature() (
    local relative="$1" path="$PROJECT_DIR/$1" actual root metadata snapshot head digest
    [ -d "$path" ] && [ ! -L "$path" ] || return 1
    validate_runtime_directory "$path" || return 1
    metadata="$(git --literal-pathspecs -C "$PROJECT_DIR" ls-files --stage -- "$relative")" || return 1
    case "$metadata" in 160000\ *) ;; *) err "Cannot verify unsupported project directory: $(printf '%q' "$relative")"; return 1;; esac
    actual="$(cd "$path" && pwd -P)" || return 1
    root="$(git -C "$actual" rev-parse --show-toplevel 2>/dev/null)" || return 1
    root="$(cd "$root" && pwd -P)" || return 1
    [ "$root" = "$actual" ] || { err "Submodule is not an initialized independent Git root: $(printf '%q' "$relative")"; return 1; }
    head="$(git -C "$actual" rev-parse --verify --quiet HEAD)" || return 1
    snapshot="$(mktemp "$CONFIG_DIR/gitlink-tree.XXXXXX")" || return 1
    trap 'rm -f "$snapshot"' EXIT
    PROJECT_DIR="$actual"
    PHASE_MANIFEST_MODE=deep
    phase_capture_worktree_manifest "$snapshot" || return 1
    digest="$(sha256_file_sum "$snapshot")" || return 1
    printf 'gitlink:%s:%s' "$head" "$digest"
)

phase_manifest_file_signature() {
    local rel_path="$1" mode="$2" abs_path="$PROJECT_DIR/$1"
    local type=missing size=-1 mtime=-1 checksum='' stat_data file_mode=''
    if [ -L "$abs_path" ]; then
        checksum="$(readlink "$abs_path" | sha256_stream_sum)" || return 1
        printf 'type=symlink,target=%s' "$checksum"
        return 0
    elif [ -d "$abs_path" ]; then
        gitlink_tree_signature "$rel_path"
        return $?
    elif [ -f "$abs_path" ]; then
        type=file
        file_mode="$(runtime_file_mode "$abs_path")" || return 1
    elif [ -e "$abs_path" ]; then
        err "Unsupported project file type: $(printf '%q' "$rel_path")"
        return 1
    fi
    stat_data="$(phase_manifest_file_size_and_mtime "$abs_path")"
    size="$(printf '%s' "$stat_data" | awk '{print $1}')"
    mtime="$(printf '%s' "$stat_data" | awk '{print $2}')"
    is_number "$size" || size=-1
    is_number "$mtime" || mtime=-1
    if [ "$mode" = deep ] && [ "$type" = file ]; then
        checksum="$(sha256_file_sum "$abs_path")" || return 1
        printf 'type=%s,mode=%s,size=%s,mtime=%s,hash=%s' "$type" "$file_mode" "$size" "$mtime" "$checksum"
    else
        printf 'type=%s,mode=%s,size=%s,mtime=%s' "$type" "$file_mode" "$size" "$mtime"
    fi
    return 0
}

path_to_hex() {
    LC_ALL=C printf '%s' "$1" | od -An -tx1 | tr -d ' \n'
}

hex_path_to_nul() {
    local hex="$1" decoded='' byte pair
    case "$hex" in *[!0-9a-f]*) return 1;; esac
    [ $(( ${#hex} % 2 )) -eq 0 ] || return 1
    while [ -n "$hex" ]; do
        pair="${hex:0:2}"
        hex="${hex:2}"
        [ "$pair" != 00 ] || return 1
        printf -v byte '%b' "\\x$pair"
        decoded="$decoded$byte"
    done
    printf '%s\0' "$decoded"
}

nul_file_contains() {
    local file="$1" wanted="$2" path
    [ -f "$file" ] || return 1
    while IFS= read -r -d '' path; do
        [ "$path" != "$wanted" ] || return 0
    done < "$file"
    return 1
}

phase_manifest_changed_paths_nul() {
    local before_file="$1" after_file="$2" line
    [ -f "$before_file" ] && [ -f "$after_file" ] || return 1
    while IFS= read -r line; do
        line="${line#$'\t'}"
        case "$line" in
            [PI]\ *$'\t'h:*) hex_path_to_nul "${line#*$'\t'h:}" || return 1 ;;
            [PI]\ *$'\t'*) printf '%s\0' "${line#*$'\t'}" ;;
        esac
    done < <(LC_ALL=C comm -3 "$before_file" "$after_file")
}

owned_path_signature() {
    local path="$PROJECT_DIR/$1" file_mode digest
    if [ -L "$path" ]; then
        digest="$(readlink "$path" | sha256_stream_sum)" || return 1
        printf 'symlink:%s' "$digest"
    elif [ -f "$path" ]; then
        file_mode="$(runtime_file_mode "$path")" || return 1
        digest="$(sha256_file_sum "$path")" || return 1
        printf 'file:mode=%s:%s' "$file_mode" "$digest"
    elif [ -d "$path" ]; then
        gitlink_tree_signature "$1"
    elif [ ! -e "$path" ]; then
        printf missing
    else
        return 1
    fi
}

owned_path_matches() {
    local wanted="$1" path signature current
    [ -f "$OWNED_PATHS_FILE" ] || return 1
    current="$(owned_path_signature "$wanted")" || return 1
    while IFS= read -r -d '' path && IFS= read -r -d '' signature; do
        if [ "$path" = "$wanted" ] && [ "$signature" = "$current" ]; then
            return 0
        fi
    done < "$OWNED_PATHS_FILE"
    return 1
}

capture_operator_baseline() {
    local raw="$RUNTIME_GUARD_DIR/operator-initial.nul" path actual
    local PHASE_MANIFEST_MODE=deep
    AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE="$RUNTIME_GUARD_DIR/operator-dirty.nul"
    : > "$AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE" || return 1
    ensure_runtime_file "$OWNED_PATHS_FILE" || return 1
    if is_true "${RESUME_REQUESTED:-true}" && [ -n "${OWNED_PATHS_SHA:-}" ]; then
        [ -f "$OWNED_PATHS_FILE" ] || { err 'Saved phase ownership is missing; restore it before resuming.'; return 1; }
        actual="$(sha256_file_sum "$OWNED_PATHS_FILE")" || return 1
        [ "$actual" = "$OWNED_PATHS_SHA" ] || { err 'Saved phase ownership changed; review it before resuming.'; return 1; }
    fi
    collect_git_dirty_paths > "$raw" || return 1
    while IFS= read -r -d '' path; do
        case "$path" in .ralphie|.ralphie/*) continue;; esac
        if is_true "${RESUME_REQUESTED:-true}" && [ -n "${OWNED_PATHS_SHA:-}" ] && owned_path_matches "$path"; then
            continue
        fi
        nul_file_contains "$AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE" "$path" || printf '%s\0' "$path" >> "$AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE"
    done < "$raw"
    phase_capture_worktree_manifest "$RUNTIME_GUARD_DIR/original-project.manifest" || return 1
    return 0
}

record_phase_owned_paths() {
    local before="$1" after="$2" path old signature record
    local replacement
    replacement="$(mktemp "$CONFIG_DIR/owned-next.XXXXXX")" || return 1
    local paths="$RUNTIME_GUARD_DIR/owned-current-paths.nul"
    ensure_runtime_file "$OWNED_PATHS_FILE" || return 1
    if [ -f "$OWNED_PATHS_FILE" ]; then cp "$OWNED_PATHS_FILE" "$replacement" || return 1; fi
    phase_manifest_changed_paths_nul "$before" "$after" > "$paths" || return 1
    # Exact current bytes, rather than light manifest timestamps, determine
    # which generated/phase files can be saved and resumed as our own work.
    collect_git_dirty_paths >> "$paths" || return 1
    while IFS= read -r -d '' path; do
        case "$path" in .ralphie|.ralphie/*|.git|.git/*) continue;; esac
        if [ -n "${AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE:-}" ] && nul_file_contains "$AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE" "$path"; then
            continue
        fi
        signature="$(owned_path_signature "$path")" || return 1
        cp "$replacement" "$RUNTIME_GUARD_DIR/owned-previous.nul" || return 1
        : > "$replacement" || return 1
        while IFS= read -r -d '' old && IFS= read -r -d '' record; do
            if [ "$old" != "$path" ]; then
                printf '%s\0%s\0' "$old" "$record" >> "$replacement" || return 1
            fi
        done < "$RUNTIME_GUARD_DIR/owned-previous.nul"
        printf '%s\0%s\0' "$path" "$signature" >> "$replacement" || return 1
    done < "$paths"
    ensure_runtime_file "$OWNED_PATHS_FILE" || return 1
    mv "$replacement" "$OWNED_PATHS_FILE" || return 1
    OWNED_PATHS_SHA="$(sha256_file_sum "$OWNED_PATHS_FILE")" || return 1
    cp "$OWNED_PATHS_FILE" "$RUNTIME_GUARD_DIR/owned-paths.nul" || return 1
    rm -f "$RUNTIME_GUARD_DIR/owned-paths.nul.absent"
    return 0
}

capture_scaffold_ownership() {
    local path signature
    local empty="$RUNTIME_GUARD_DIR/scaffold-before.manifest" current="$RUNTIME_GUARD_DIR/scaffold-after.manifest"
    : > "$empty" || return 1
    phase_capture_worktree_manifest "$current" || return 1
    # The untouched operator baseline was captured before these files existed.
    # Record only generated files, excluding every originally dirty path.
    record_phase_owned_paths "$empty" "$current"
}

checkpoint_current_phase_worktree() {
    [ -n "${RUNTIME_GUARD_DIR:-}" ] && [ -f "${ACTIVE_PHASE_MANIFEST_BEFORE:-}" ] || return 0
    local after="$RUNTIME_GUARD_DIR/interrupted-project.manifest"
    phase_capture_worktree_manifest "$after" || return 1
    shell_note_local_work "$ACTIVE_PHASE_MANIFEST_BEFORE" "$after"
    record_session_changed_paths_from_manifest "$ACTIVE_PHASE_MANIFEST_BEFORE" "$after" || return 1
    record_phase_owned_paths "$ACTIVE_PHASE_MANIFEST_BEFORE" "$after"
}

phase_capture_worktree_manifest() {
    local manifest_file="$1" mode record status_code target_path signature raw index entries seen metadata
    [ -n "$manifest_file" ] || return 1
    ensure_runtime_file "$manifest_file" || return 1
    ensure_runtime_directory "$CONFIG_DIR" || return 1
    git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
    mode="$(normalize_phase_manifest_mode "$PHASE_MANIFEST_MODE")"
    raw="$(mktemp "$CONFIG_DIR/manifest-paths.XXXXXX")" || return 1
    index="$(mktemp "$CONFIG_DIR/manifest-index.XXXXXX")" || { rm -f "$raw"; return 1; }
    entries="$(mktemp "$CONFIG_DIR/manifest-entries.XXXXXX")" || { rm -f "$raw" "$index"; return 1; }
    seen="$(mktemp "$CONFIG_DIR/manifest-seen.XXXXXX")" || { rm -f "$raw" "$index" "$entries"; return 1; }
    if ! git --literal-pathspecs -C "$PROJECT_DIR" -c status.renames=false status --porcelain=v1 -z --untracked-files=all -- . > "$raw" \
        || ! git -C "$PROJECT_DIR" ls-files --stage -z > "$index"; then
        rm -f "$raw" "$index" "$entries" "$seen"
        return 1
    fi
    while IFS= read -r -d '' record; do
        status_code="${record:0:2}"
        target_path="${record:3}"
        if ! signature="$(phase_manifest_file_signature "$target_path" "$mode")"; then
            rm -f "$raw" "$index" "$entries" "$seen"
            return 1
        fi
        printf 'P %s %s\th:%s\n' "$status_code" "$signature" "$(path_to_hex "$target_path")" >> "$entries" || return 1
        printf '%s\0' "$target_path" >> "$seen" || return 1
    done < "$raw"
    # Raw index entries prove staged bytes/modes independently of worktree
    # status. Deep verification also hashes clean tracked paths (Git may hide
    # a mode change or an assume-unchanged path from ordinary status).
    while IFS= read -r -d '' record; do
        metadata="${record%%$'\t'*}"
        target_path="${record#*$'\t'}"
        printf 'I %s\th:%s\n' "$metadata" "$(path_to_hex "$target_path")" >> "$entries" || return 1
        if { [ "$mode" = deep ] || [[ "$metadata" = 160000\ * ]]; } && ! nul_file_contains "$seen" "$target_path"; then
            if ! signature="$(phase_manifest_file_signature "$target_path" "$mode")"; then
                rm -f "$raw" "$index" "$entries" "$seen"
                return 1
            fi
            printf 'P    %s\th:%s\n' "$signature" "$(path_to_hex "$target_path")" >> "$entries" || return 1
            printf '%s\0' "$target_path" >> "$seen" || return 1
        fi
    done < "$index"
    if ! LC_ALL=C sort "$entries" > "$manifest_file"; then
        rm -f "$raw" "$index" "$entries" "$seen"
        return 1
    fi
    rm -f "$raw" "$index" "$entries" "$seen"
    return 0
}

phase_manifest_changed() {
    local before_file="$1"
    local after_file="$2"

    if [ ! -f "$before_file" ] || [ ! -f "$after_file" ]; then
        return 1
    fi

    if cmp -s "$before_file" "$after_file"; then
        return 1
    fi
    return 0
}

phase_manifest_extract_path_from_line() {
    local line="${1:-}" path
    line="${line#$'\t'}"
    case "$line" in
        [PI]\ *$'\t'h:*)
            IFS= read -r -d '' path < <(hex_path_to_nul "${line#*$'\t'h:}") || return 1
            printf '%s\n' "$path"
            ;;
        [PI]\ *$'\t'*) printf '%s\n' "${line#*$'\t'}" ;;
        *) return 1 ;;
    esac
}

phase_manifest_changed_paths() {
    local path
    while IFS= read -r -d '' path; do
        printf '%s\n' "$path"
    done < <(phase_manifest_changed_paths_nul "$1" "$2")
}

record_session_changed_paths_from_manifest() {
    local before_file="$1" after_file="$2" path
    mkdir -p "$(dirname "$SESSION_CHANGED_PATHS_FILE")" || return 1
    ensure_runtime_file "$SESSION_CHANGED_PATHS_FILE" || return 1
    touch "$SESSION_CHANGED_PATHS_FILE" || return 1
    while IFS= read -r -d '' path; do
        nul_file_contains "$SESSION_CHANGED_PATHS_FILE" "$path" || printf '%s\0' "$path" >> "$SESSION_CHANGED_PATHS_FILE"
    done < <(phase_manifest_changed_paths_nul "$before_file" "$after_file")
    return 0
}

session_changed_paths_contains() {
    nul_file_contains "$SESSION_CHANGED_PATHS_FILE" "$1"
}

phase_noop_policy() {
    local phase="$1"
    case "$phase" in
        plan)
            echo "$PHASE_NOOP_POLICY_PLAN"
            ;;
        build)
            echo "$PHASE_NOOP_POLICY_BUILD"
            ;;
        test)
            if is_true "$STRICT_VALIDATION_NOOP"; then
                echo "hard"
            else
                echo "$PHASE_NOOP_POLICY_TEST"
            fi
            ;;
        refactor)
            echo "$PHASE_NOOP_POLICY_REFACTOR"
            ;;
        lint)
            if is_true "$STRICT_VALIDATION_NOOP"; then
                echo "hard"
            else
                echo "$PHASE_NOOP_POLICY_LINT"
            fi
            ;;
        document)
            echo "$PHASE_NOOP_POLICY_DOCUMENT"
            ;;
        *)
            echo "none"
            ;;
    esac
}

phase_requires_command_evidence() {
    case "${1:-}" in
        test|lint) return 0 ;;
        *) return 1 ;;
    esac
}

phase_output_has_command_evidence() {
    local output_file="$1"
    local log_file="$2"
    local evidence_pattern='(`[^`]+`|(^|[[:space:]])(python3?|pytest|tox|nox|uv[[:space:]]+run|npm|pnpm|yarn|node|bash[[:space:]]+-n|shellcheck|ruff|mypy|pytest|go[[:space:]]+test|cargo[[:space:]]+test|make|cmake|gradle|mvn|dotnet[[:space:]]+test|git[[:space:]]+diff[[:space:]]+--check))'

    if [ -f "$output_file" ] && grep -Eiq "$evidence_pattern" "$output_file" 2>/dev/null; then
        return 0
    fi
    if [ -f "$log_file" ] && grep -Eiq "$evidence_pattern" "$log_file" 2>/dev/null; then
        return 0
    fi
    return 1
}

phase_manifest_delta_preview() {
    local before_file="$1"
    local after_file="$2"
    local lines_limit="${3:-8}"
    local emitted=0
    local line
    local label
    local content

    if [ ! -f "$before_file" ] || [ ! -f "$after_file" ]; then
        echo ""
        return 0
    fi

    while IFS= read -r line; do
        if [ "$emitted" -ge "$lines_limit" ]; then
            break
        fi
        if [ "${line:0:1}" = $'\t' ]; then
            label="after"
            content="${line:1}"
        else
            label="before"
            content="$line"
        fi
        printf '%s: %s\n' "$label" "$content"
        emitted=$((emitted + 1))
    done < <(comm -3 "$before_file" "$after_file")
}

git_has_local_changes() {
    if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 1
    fi

    if ! git -C "$PROJECT_DIR" diff --quiet --ignore-submodules -- .; then
        return 0
    fi
    if ! git -C "$PROJECT_DIR" diff --cached --quiet --ignore-submodules -- .; then
        return 0
    fi
    if [ -n "$(git -C "$PROJECT_DIR" ls-files --others --exclude-standard -- . 2>/dev/null | head -n 1)" ]; then
        return 0
    fi
    return 1
}

consensus_clean_terminal_hold_reroute_allowed() {
    local phase="${1:-}"
    local candidate_next="${2:-}"

    [ "$candidate_next" = "done" ] || return 1
    case "${SHELL_GATES_STATUS:-absent}" in failed|timeout|tampered) return 1;; esac
    shell_terminal_verified || return 1
    [ "$phase" != "done" ] || return 1
    is_true "${LAST_CONSENSUS_PASS:-false}" || return 1
    [ "${LAST_CONSENSUS_FAILURE_KIND:-}" = "none" ] || return 1
    is_number "${LAST_CONSENSUS_RESPONDED_VOTES:-0}" || return 1
    is_number "${LAST_CONSENSUS_NEXT_PHASE_VOTES:-0}" || return 1
    is_number "${LAST_CONSENSUS_GO_VOTES:-0}" || return 1
    is_number "${LAST_CONSENSUS_BLOCKING_GAP_VOTES:-0}" || return 1
    [ "${LAST_CONSENSUS_RESPONDED_VOTES:-0}" -eq "$(get_reviewer_count)" ] || return 1
    [ "${LAST_CONSENSUS_GO_VOTES:-0}" -eq "${LAST_CONSENSUS_RESPONDED_VOTES:-0}" ] || return 1
    [ "${LAST_CONSENSUS_BLOCKING_GAP_VOTES:-0}" -eq 0 ] || return 1
    [ "${LAST_CONSENSUS_NEXT_PHASE_VOTES:-0}" -eq "${LAST_CONSENSUS_RESPONDED_VOTES:-0}" ] || return 1

    if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 && git_has_local_changes; then
        return 1
    fi

    return 0
}

detect_git_identity() {
    GIT_IDENTITY_READY="false"
    GIT_IDENTITY_SOURCE="unknown"

    if ! command -v git >/dev/null 2>&1; then
        GIT_IDENTITY_SOURCE="git command unavailable"
        return 1
    fi

    local -a repo_scope=()
    if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        repo_scope=(-C "$PROJECT_DIR")
    fi

    local committer_ident=""
    committer_ident="$(git "${repo_scope[@]+"${repo_scope[@]}"}" var GIT_COMMITTER_IDENT 2>/dev/null || true)"
    if [ -z "$committer_ident" ]; then
        if [ -n "${GIT_COMMITTER_NAME:-}" ] || [ -n "${GIT_COMMITTER_EMAIL:-}" ] || [ -n "${GIT_AUTHOR_NAME:-}" ] || [ -n "${GIT_AUTHOR_EMAIL:-}" ]; then
            GIT_IDENTITY_SOURCE="incomplete identity environment variables"
        else
            GIT_IDENTITY_SOURCE="git user.name/user.email not configured"
        fi
        return 1
    fi

    if [ -n "${GIT_COMMITTER_NAME:-}" ] && [ -n "${GIT_COMMITTER_EMAIL:-}" ]; then
        GIT_IDENTITY_SOURCE="environment (GIT_COMMITTER_*)"
    elif [ -n "${GIT_AUTHOR_NAME:-}" ] && [ -n "${GIT_AUTHOR_EMAIL:-}" ]; then
        GIT_IDENTITY_SOURCE="environment (GIT_AUTHOR_*)"
    else
        local local_name="" local_email="" global_name="" global_email=""
        if [ "${#repo_scope[@]}" -gt 0 ]; then
            local_name="$(git -C "$PROJECT_DIR" config --local --get user.name 2>/dev/null || true)"
            local_email="$(git -C "$PROJECT_DIR" config --local --get user.email 2>/dev/null || true)"
        fi
        global_name="$(git config --global --get user.name 2>/dev/null || true)"
        global_email="$(git config --global --get user.email 2>/dev/null || true)"

        if [ -n "$local_name" ] && [ -n "$local_email" ]; then
            GIT_IDENTITY_SOURCE="local git config"
        elif [ -n "$global_name" ] && [ -n "$global_email" ]; then
            GIT_IDENTITY_SOURCE="global git config"
        else
            GIT_IDENTITY_SOURCE="system git config"
        fi
    fi

    GIT_IDENTITY_READY="true"
    return 0
}

refresh_git_identity_status() {
    if detect_git_identity; then
        info "Git identity status: ready (${GIT_IDENTITY_SOURCE})."
        return 0
    fi
    warn "Git identity status: missing (${GIT_IDENTITY_SOURCE})."
    return 1
}

ensure_git_repository_initialized() {
    if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 0
    fi

    if ! is_true "$AUTO_INIT_GIT_IF_MISSING"; then
        warn "No git repository detected and auto-init is disabled."
        return 0
    fi

    if ! command -v git >/dev/null 2>&1; then
        err "Git is required for auto-init but command is not available."
        log_reason_code "RB_GIT_INIT_FAILED" "git command missing while auto-init-git-if-missing=true"
        return 1
    fi

    warn "No git repository detected. Initializing repository in $(path_for_display "$PROJECT_DIR")."
    if ! git -C "$PROJECT_DIR" init >/dev/null 2>&1; then
        err "Failed to initialize git repository in $(path_for_display "$PROJECT_DIR")."
        log_reason_code "RB_GIT_INIT_FAILED" "git init failed in project dir"
        return 1
    fi

    if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        err "git init completed but repository validation failed."
        log_reason_code "RB_GIT_INIT_FAILED" "git init reported success but rev-parse failed"
        return 1
    fi

    success "Initialized git repository (no remote configured)."
    return 0
}

build_phase_commit_message() {
    local phase="$1"
    local next_phase="${2:-$(phase_default_next "$phase")}"
    local fallback_message
    fallback_message="$(printf '%s' "${phase}->${next_phase}: gate pass" | tr '[:upper:]' '[:lower:]')"

    if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "$fallback_message"
        return 0
    fi

    local paths_file groups_file total_files group_count shown extra
    local groups_summary=""
    paths_file="$(mktemp "$CONFIG_DIR/commit-paths.XXXXXX")" || { echo "$fallback_message"; return 0; }
    groups_file="$(mktemp "$CONFIG_DIR/commit-groups.XXXXXX")" || { rm -f "$paths_file"; echo "$fallback_message"; return 0; }

    if ! git -C "$PROJECT_DIR" diff --cached --name-only -- . > "$paths_file" 2>/dev/null; then
        rm -f "$paths_file" "$groups_file"
        echo "$fallback_message"
        return 0
    fi

    total_files="$(wc -l < "$paths_file" | tr -d ' ')"
    if ! is_number "$total_files" || [ "$total_files" -lt 1 ]; then
        rm -f "$paths_file" "$groups_file"
        echo "$fallback_message"
        return 0
    fi

    awk '
        {
            if ($0 ~ /\//) {
                split($0, a, "/")
                top=a[1]
            } else {
                top="repo"
            }
            print top
        }
    ' "$paths_file" | sort | uniq -c | sort -nr > "$groups_file"

    group_count="$(wc -l < "$groups_file" | tr -d ' ')"
    shown=0
    while read -r count group; do
        [ -n "${group:-}" ] || continue
        group="$(printf '%s' "$group" | tr '[:upper:]' '[:lower:]')"
        groups_summary="${groups_summary}${groups_summary:+,}${group}:${count}"
        shown=$((shown + 1))
        [ "$shown" -ge 3 ] && break
    done < "$groups_file"

    extra=$((group_count - shown))
    if [ "$extra" -gt 0 ]; then
        groups_summary="${groups_summary},+${extra}g"
    fi

    rm -f "$paths_file" "$groups_file"
    if [ -z "$groups_summary" ]; then
        echo "$fallback_message"
        return 0
    fi
    printf '%s' "${phase}->${next_phase}: ${total_files}f ${groups_summary}" | tr '[:upper:]' '[:lower:]'
}

# A private index does not isolate MERGE_HEAD or the sequencer. A plain commit
# would consume the operator's pending operation and publish its history.
phase_git_operation_idle() {
    local name path
    for name in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer; do
        if ! path="$(git -C "$PROJECT_DIR" rev-parse --git-path "$name")"; then
            PHASE_SAVE_REASON='Could not resolve Git operation metadata; automatic save refused.'
            return 1
        fi
        case "$path" in /*) ;; *) path="$PROJECT_DIR/$path";; esac
        if [ -e "$path" ] || [ -L "$path" ]; then
            PHASE_SAVE_REASON="Git operation is pending ($name); finish or abort it outside Ralphie before automatic saves."
            return 1
        fi
    done
    return 0
}

prepare_phase_auto_commit_mode() {
    AUTO_COMMIT_SESSION_ENABLED="false"
    if ! is_true "$AUTO_COMMIT_ON_PHASE_PASS"; then
        info "Phase auto-commit is disabled."
        return 0
    fi

    if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        err "Phase auto-commit requires a Git repository; enable auto-init or explicitly disable auto-commit."
        return 1
    fi

    if ! phase_git_operation_idle; then
        err "$PHASE_SAVE_REASON"
        return 1
    fi

    if ! detect_git_identity; then
        err "Phase auto-commit requires a Git identity (${GIT_IDENTITY_SOURCE})."
        err "Set Git user.name/user.email or explicitly use --auto-commit-on-phase-pass false."
        return 1
    fi

    if [ -z "${AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE:-}" ]; then
        AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE="$(mktemp "$CONFIG_DIR/autocommit-baseline.XXXXXX")" || return 1
        collect_git_dirty_paths > "$AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE" || return 1
    fi
    if [ -n "$AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE" ] && [ -s "$AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE" ]; then
        warn "Auto-commit starting from a dirty worktree; phase commits will be skipped if they overlap pre-existing dirty paths."
    fi

    AUTO_COMMIT_SESSION_ENABLED="true"
    info "Git identity ready for auto-commit (${GIT_IDENTITY_SOURCE})."
    info "Phase auto-commit enabled (local commits only; pushes are disabled)."
}

collect_git_dirty_paths() {
    git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
    git --literal-pathspecs -C "$PROJECT_DIR" diff --no-ext-diff --name-only -z -- . || return 1
    git --literal-pathspecs -C "$PROJECT_DIR" diff --no-ext-diff --cached --name-only -z -- . || return 1
    git --literal-pathspecs -C "$PROJECT_DIR" ls-files --others --exclude-standard -z -- . || return 1
}

collect_manifest_delta_commit_paths() {
    local before_file="$1" after_file="$2" output_file="$3" path
    [ -n "$output_file" ] || return 1
    : > "$output_file" || return 1
    [ -f "$before_file" ] && [ -f "$after_file" ] || return 1
    while IFS= read -r -d '' path; do
        [ -n "$path" ] || continue
        case "$path" in .ralphie|.ralphie/*|.git|.git/*) continue;; esac
        nul_file_contains "$output_file" "$path" || printf '%s\0' "$path" >> "$output_file"
    done < <(phase_manifest_changed_paths_nul "$before_file" "$after_file")
    [ -s "$output_file" ]
}

stage_commit_paths_from_file() {
    local paths_file="$1" path staged_any=false
    [ -f "$paths_file" ] || return 1
    while IFS= read -r -d '' path; do
        [ -n "$path" ] || continue
        if git --literal-pathspecs -C "$PROJECT_DIR" add -A -- "$path"; then
            staged_any=true
        else
            warn "Auto-commit could not stage a phase path: $(printf '%q' "$path")"
            return 1
        fi
    done < "$paths_file"
    is_true "$staged_any"
}

cleanup_phase_commit_files() {
    local dir="${1:-}"
    [ -n "$dir" ] && [ -d "$dir" ] && [ ! -L "$dir" ] || return 0
    rm -f "$dir/index" "$dir/index.lock" "$dir/paths" "$dir/index-before" "$dir/index-now" "$dir/error"
    rmdir "$dir/no-hooks" 2>/dev/null || true
    rmdir "$dir" 2>/dev/null || true
}

save_owned_phase_index() {
    local paths_file="$1" before_head="$2" phase="$3" next_phase="$4" dir="$5"
    local index="$dir/index" hooks="$dir/no-hooks" path current_head commit_message
    mkdir "$hooks" || return 1
    git -C "$PROJECT_DIR" ls-files --stage -z > "$dir/index-before" || return 1
    if [ -n "$before_head" ]; then
        GIT_INDEX_FILE="$index" git -C "$PROJECT_DIR" read-tree "$before_head" || return 1
    else
        GIT_INDEX_FILE="$index" git -C "$PROJECT_DIR" read-tree --empty || return 1
    fi
    if ! GIT_INDEX_FILE="$index" stage_commit_paths_from_file "$paths_file"; then
        PHASE_SAVE_REASON='Git could not stage the approved paths in its private index.'
        return 1
    fi
    GIT_INDEX_FILE="$index" git -C "$PROJECT_DIR" diff --cached --name-only -z -- . > "$dir/paths" || return 1
    [ -s "$dir/paths" ] || { PHASE_SAVE_REASON='No approved changes reached the private commit index.'; return 1; }
    while IFS= read -r -d '' path; do
        if ! nul_file_contains "$paths_file" "$path"; then
            PHASE_SAVE_REASON='The private index includes a path outside the approved phase changes.'
            return 1
        fi
    done < "$dir/paths"
    current_head="$(git -C "$PROJECT_DIR" rev-parse --verify --quiet HEAD 2>/dev/null || true)"
    git -C "$PROJECT_DIR" ls-files --stage -z > "$dir/index-now" || return 1
    if [ "$current_head" != "$before_head" ] || ! cmp -s "$dir/index-before" "$dir/index-now"; then
        PHASE_SAVE_REASON='Git HEAD or the operator index changed before phase publication.'
        return 1
    fi
    commit_message="$(GIT_INDEX_FILE="$index" build_phase_commit_message "$phase" "$next_phase")" || return 1
    phase_git_operation_idle || return 1
    # Automatic saves never run repository hooks: a hook can expand the index
    # after scope validation. Required checks run explicitly through the gates.
    if ! run_command_with_timeout "$GATE_TIMEOUT_SECONDS" env GIT_INDEX_FILE="$index" \
        git -C "$PROJECT_DIR" -c "core.hooksPath=$hooks" commit -m "$commit_message"; then
        PHASE_SAVE_REASON='Git refused the isolated phase commit; the operator index was left untouched.'
        return 1
    fi
    # The real index still describes the previous HEAD. Advance only approved
    # paths; unrelated operator index entries and working bytes remain intact.
    while IFS= read -r -d '' path; do
        if ! git --literal-pathspecs -C "$PROJECT_DIR" reset -q HEAD -- "$path"; then
            PHASE_SAVE_REASON='The phase commit exists, but its approved paths could not be synchronized in the real index.'
            return 1
        fi
    done < "$dir/paths"
    return 0
}

commit_phase_approved_changes() {
    local phase="$1" next_phase="$2" manifest_before="${3:-}" manifest_after="${4:-}"
    local paths_file path before_head after_head commit_message error_file phase_commit_tmpdir=""
    PHASE_SAVE_REQUIRED=false
    PHASE_SAVE_OK=true
    PHASE_SAVE_REASON=''
    is_true "$AUTO_COMMIT_SESSION_ENABLED" || return 0
    paths_file="$(mktemp "$CONFIG_DIR/commit-paths.XXXXXX")" || return 1
    collect_manifest_delta_commit_paths "$manifest_before" "$manifest_after" "$paths_file" || true
    while IFS= read -r -d '' path; do
        case "$path" in .ralphie|.ralphie/*|.git|.git/*) continue;; esac
        if owned_path_matches "$path"; then
            nul_file_contains "$paths_file" "$path" || printf '%s\0' "$path" >> "$paths_file"
        fi
    done < <(collect_git_dirty_paths)
    if [ ! -s "$paths_file" ]; then
        rm -f "$paths_file"
        return 0
    fi
    PHASE_SAVE_REQUIRED=true
    PHASE_SAVE_OK=false
    if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || ! detect_git_identity; then
        PHASE_SAVE_REASON='Git repository or identity is unavailable.'
    elif ! git -C "$PROJECT_DIR" diff --cached --quiet -- .; then
        PHASE_SAVE_REASON='Pre-staged operator changes must be saved separately before an automatic phase commit.'
    else
        while IFS= read -r -d '' path; do
            if [ -n "${AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE:-}" ] && nul_file_contains "$AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE" "$path"; then
                PHASE_SAVE_REASON='Phase changes overlap operator paths dirty before Ralphie started.'
                break
            fi
        done < "$paths_file"
    fi
    if [ -n "$PHASE_SAVE_REASON" ]; then
        warn "$PHASE_SAVE_REASON Work is on disk but was not saved in a phase commit."
        rm -f "$paths_file"
        # The caller owns the acceptance postcondition, including benign no-work
        # and deliberate --auto-commit-on-phase-pass false cases.
        return 0
    fi
    before_head="$(git -C "$PROJECT_DIR" rev-parse --verify --quiet HEAD 2>/dev/null || true)"
    phase_commit_tmpdir="$(mktemp -d "$CONFIG_DIR/phase-save.XXXXXX")" || { rm -f "$paths_file"; return 1; }
    error_file="$phase_commit_tmpdir/error"
    if ! save_owned_phase_index "$paths_file" "$before_head" "$phase" "$next_phase" "$phase_commit_tmpdir" > "$error_file" 2>&1; then
        [ -n "$PHASE_SAVE_REASON" ] || PHASE_SAVE_REASON='Git could not complete the isolated phase save.'
        safe_print_file_tail "$error_file" 12
        cleanup_phase_commit_files "$phase_commit_tmpdir"
        rm -f "$paths_file"
        return 1
    fi
    cleanup_phase_commit_files "$phase_commit_tmpdir"
    phase_commit_tmpdir=""
    after_head="$(git -C "$PROJECT_DIR" rev-parse --verify --quiet HEAD 2>/dev/null || true)"
    if [ -z "$after_head" ] || [ "$after_head" = "$before_head" ]; then
        PHASE_SAVE_REASON='Git reported success but HEAD did not move.'
        err "$PHASE_SAVE_REASON"
        rm -f "$paths_file"
        return 1
    fi
    while IFS= read -r -d '' path; do
        if [ -n "$(git --literal-pathspecs -C "$PROJECT_DIR" status --porcelain --untracked-files=all -- "$path")" ]; then
            PHASE_SAVE_REASON='Phase paths remain unsaved after the commit; review hooks and working-tree changes.'
            rm -f "$paths_file"
            return 1
        fi
    done < "$paths_file"
    rm -f "$paths_file"
    PHASE_SAVE_OK=true
    commit_message="$(git -C "$PROJECT_DIR" log -1 --pretty=%s)"
    info "Phase $phase committed (${after_head:0:8}): $commit_message"
    return 0
}

phase_index_from_name() {
    case "$1" in
        plan) echo 0; return 0 ;;
        build) echo 1; return 0 ;;
        test) echo 2; return 0 ;;
        refactor) echo 3; return 0 ;;
        lint) echo 4; return 0 ;;
        document) echo 5; return 0 ;;
        done) echo 6; return 0 ;;
        *) echo 0; return 1 ;;
    esac
}

phase_name_from_index() {
    local index="$1"
    if ! is_number "$index"; then
        echo ""
        return 1
    fi
    case "$index" in
        0) echo "plan"; return 0 ;;
        1) echo "build"; return 0 ;;
        2) echo "test"; return 0 ;;
        3) echo "refactor"; return 0 ;;
        4) echo "lint"; return 0 ;;
        5) echo "document"; return 0 ;;
        *) echo ""; return 1 ;;
    esac
}

phase_default_next() {
    local phase="$1"
    case "$phase" in
        plan) echo "build" ;;
        build) echo "test" ;;
        test)
            if phase_has_passed_in_history "refactor"; then
                echo "lint"
            else
                echo "refactor"
            fi
            ;;
        refactor) echo "test" ;;
        lint) echo "document" ;;
        document) echo "done" ;;
        *) echo "done" ;;
    esac
}

phase_default_previous() {
    local phase="$1"
    case "$phase" in
        plan) echo "plan" ;;
        build) echo "plan" ;;
        test) echo "build" ;;
        refactor) echo "test" ;;
        lint) echo "refactor" ;;
        document) echo "lint" ;;
        done) echo "document" ;;
        *) echo "plan" ;;
    esac
}

phase_history_entry_passed() {
    local entry="$1" phase="$2" transition outcome
    transition="${entry%%|*}"
    outcome="${entry#*|}"
    outcome="${outcome%%|*}"
    [ "$outcome" = pass ] || return 1
    # Routing explanations are free text, never phase execution evidence.
    case "$transition" in "$phase""(attempt "*")->"*) return 0;; esac
    return 1
}

phase_has_passed_in_history() {
    local phase="${1:-}"
    local entry

    case "$phase" in
        plan|build|test|refactor|lint|document) ;;
        *) return 1 ;;
    esac

    if [ "${#PHASE_TRANSITION_HISTORY[@]}" -eq 0 ]; then
        return 1
    fi

    for entry in "${PHASE_TRANSITION_HISTORY[@]+"${PHASE_TRANSITION_HISTORY[@]}"}"; do
        if phase_history_entry_passed "$entry" "$phase"; then
            return 0
        fi
    done

    return 1
}

phase_has_passed_after_phase() {
    local target_phase="${1:-}"
    local marker_phase="${2:-}"
    local entry
    local marker_seen=false target_seen=false

    case "$target_phase" in
        plan|build|test|refactor|lint|document) ;;
        *) return 1 ;;
    esac
    case "$marker_phase" in
        plan|build|test|refactor|lint|document) ;;
        *) return 1 ;;
    esac

    for entry in "${PHASE_TRANSITION_HISTORY[@]+"${PHASE_TRANSITION_HISTORY[@]}"}"; do
        if phase_history_entry_passed "$entry" "$marker_phase"; then
            marker_seen=true
            target_seen=false
        elif is_true "$marker_seen" && phase_history_entry_passed "$entry" "$target_phase"; then
            target_seen=true
        fi
    done
    is_true "$target_seen"
}

phase_requirement_satisfied() {
    local required_phase="${1:-}"
    local current_phase="${2:-}"
    local current_phase_passed="${3:-false}"

    phase_has_passed_in_history "$required_phase" && return 0
    if is_true "$current_phase_passed" && [ "$current_phase" = "$required_phase" ]; then
        return 0
    fi
    return 1
}

post_refactor_test_satisfied() {
    local current_phase="${1:-}"
    local current_phase_passed="${2:-false}"

    phase_has_passed_in_history "refactor" || return 1
    phase_has_passed_after_phase "test" "refactor" && return 0
    if is_true "$current_phase_passed" && [ "$current_phase" = "test" ] && phase_has_passed_in_history "refactor"; then
        return 0
    fi
    return 1
}

markdown_has_unchecked_local_tasks() {
    local markdown_file="$1"
    local unchecked_lines=""
    [ -f "$markdown_file" ] || return 1

    unchecked_lines="$(
        awk '
            BEGIN { in_code = 0; fence = ""; fence_length = 0; in_external_section = 0 }
            /^[[:space:]]*(```|~~~)/ {
                marker = $0
                sub(/^[[:space:]]*/, "", marker)
                marker_char = substr(marker, 1, 1)
                if (marker_char == "`") { match(marker, /^`+/) }
                else { match(marker, /^~+/) }
                marker_length = RLENGTH
                if (!in_code) {
                    in_code = 1
                    fence = marker_char
                    fence_length = marker_length
                } else if (marker_char == fence && marker_length >= fence_length && substr(marker, marker_length + 1) ~ /^[[:space:]]*$/) {
                    in_code = 0
                }
                next
            }
            in_code { next }
            /^[[:space:]]*#{1,6}[[:space:]]*/ {
                heading = tolower($0)
                if (heading ~ /deferred[[:space:]]+external/ || heading ~ /external-only/ || heading ~ /external[[:space:]]+queue/) {
                    in_external_section = 1
                } else {
                    in_external_section = 0
                }
                next
            }
            /^[[:space:]]*([-+*]|[0-9]+[.)])[[:space:]]+\[[[:space:]]\]([[:space:]]|$)/ {
                if (in_external_section) {
                    next
                }
                lower = tolower($0)
                if (lower ~ /open[[:space:]]*\[[[:space:]]*external[[:space:]]*\]/ || lower ~ /external-only/ || lower ~ /\[[[:space:]]*external[[:space:]]*\]/) {
                    next
                }
                if (lower ~ /operator[[:space:]\/-]*(proof|product|decision|security|risk|window)|authorized.*(credentials|live|proof)|live[[:space:]-]+proof|proof[[:space:]-]+window|policy[[:space:]-]+decision|residual[[:space:]-]+risk|external[[:space:]-]+proof|separate[[:space:]-]+proof[[:space:]-]+window/) {
                    next
                }
                if (lower ~ /future/ && lower ~ /(if|when|after|once|later|exposes?|creates?|requires?)/) {
                    next
                }
                print
            }
        ' "$markdown_file" 2>/dev/null || true
    )"
    [ -n "$unchecked_lines" ] || return 1

    return 0
}

collect_backlog_source_files() {
    local sources_raw="${BACKLOG_SOURCES:-$DEFAULT_BACKLOG_SOURCES}"
    local sources_trimmed item normalized abs_path
    local -a resolved=()

    sources_trimmed="$(sanitize_text_for_log "$sources_raw")"
    if [ -z "$sources_trimmed" ]; then
        sources_trimmed="$DEFAULT_BACKLOG_SOURCES"
    fi

    while IFS= read -r item; do
        normalized="$(printf '%s' "$item" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [ -n "$normalized" ] || continue
        case "$normalized" in
            /*) abs_path="$normalized" ;;
            *) abs_path="$PROJECT_DIR/$normalized" ;;
        esac
        resolved+=("$abs_path")
    done < <(printf '%s\n' "$sources_trimmed" | tr ',' '\n')

    if [ "${#resolved[@]}" -eq 0 ]; then
        resolved+=("$PLAN_FILE")
    fi

    printf '%s\n' "${resolved[@]}" | awk '!seen[$0]++'
}

collect_backlog_freshness_source_files() {
    local source_file

    while IFS= read -r source_file; do
        [ -n "$source_file" ] || continue
        # The plan file is the artifact PLAN produces, not an upstream source
        # that should force PLAN to refresh itself. Keep it in the general
        # backlog list so terminal unchecked-task guards still work, but omit it
        # from freshness fingerprints and stale-source mtimes.
        if [ -n "${PLAN_FILE:-}" ] && [ "$source_file" = "$PLAN_FILE" ]; then
            continue
        fi
        printf '%s\n' "$source_file"
    done < <(collect_backlog_source_files)
}

backlog_source_display_list() {
    local source_file rel_path
    local -a labels=()

    while IFS= read -r source_file; do
        [ -n "$source_file" ] || continue
        rel_path="$(path_relative_to_project "$source_file")"
        if [ -n "$rel_path" ] && [ "$rel_path" != "$source_file" ]; then
            labels+=("$(path_for_display "$rel_path")")
        else
            labels+=("$(path_for_display "$source_file")")
        fi
    done < <(collect_backlog_source_files)

    if [ "${#labels[@]}" -eq 0 ]; then
        printf '%s' "configured backlog sources"
    else
        join_with_commas "${labels[@]}"
    fi
}

backlog_freshness_source_display_list() {
    local source_file rel_path
    local -a labels=()

    while IFS= read -r source_file; do
        [ -n "$source_file" ] || continue
        rel_path="$(path_relative_to_project "$source_file")"
        if [ -n "$rel_path" ] && [ "$rel_path" != "$source_file" ]; then
            labels+=("$(path_for_display "$rel_path")")
        else
            labels+=("$(path_for_display "$source_file")")
        fi
    done < <(collect_backlog_freshness_source_files)

    if [ "${#labels[@]}" -eq 0 ]; then
        printf '%s' "configured external backlog sources"
    else
        join_with_commas "${labels[@]}"
    fi
}

backlog_sources_fingerprint() {
    local source_file rel_path file_hash

    {
        printf 'backlog_sources=%s\n' "${BACKLOG_SOURCES:-$DEFAULT_BACKLOG_SOURCES}"
        while IFS= read -r source_file; do
            [ -n "$source_file" ] || continue
            rel_path="$(path_relative_to_project "$source_file")"
            [ -n "$rel_path" ] || rel_path="$source_file"
            if [ -f "$source_file" ]; then
                file_hash="$(sha256_file_sum "$source_file" 2>/dev/null || printf 'unavailable')"
                printf 'file\t%s\t%s\n' "$rel_path" "$file_hash"
            else
                printf 'missing\t%s\n' "$rel_path"
            fi
        done < <(collect_backlog_freshness_source_files)
    } | sha256_stream_sum
}

record_plan_freshness_checkpoint() {
    local fingerprint

    fingerprint="$(backlog_sources_fingerprint 2>/dev/null || true)"
    if [ -z "$fingerprint" ]; then
        warn "Plan freshness checkpoint skipped: could not fingerprint configured backlog sources."
        return 1
    fi

    PLAN_FRESHNESS_FINGERPRINT="$fingerprint"
    info "Plan freshness checkpoint recorded for $(backlog_freshness_source_display_list)."
    return 0
}

plan_has_unchecked_local_tasks() {
    local plan_file="${1:-$PLAN_FILE}"
    markdown_has_unchecked_local_tasks "$plan_file"
}

plan_has_terminal_or_handoff_intent() {
    local plan_file="${1:-$PLAN_FILE}"
    [ -f "$plan_file" ] || return 1

    grep -qiE '(no[[:space:]]+(local|code|implementation|repository|repo)[[:space:]]+(changes?|tasks?|work|actions?)|no[[:space:]]+actionable[[:space:]]+(local[[:space:]]+)?(tasks?|work|changes?)|nothing[[:space:]]+to[[:space:]]+(build|implement|change)|already[[:space:]]+(complete|done|satisfied)|external[-[:space:]]+only|external[[:space:]]+(handoff|queue|dependency|blocker)|handoff[-[:space:]]+ready|ready[[:space:]]+for[[:space:]]+handoff)' "$plan_file" 2>/dev/null
}

project_terminal_or_handoff_ready() {
    plan_has_terminal_or_handoff_intent "$PLAN_FILE" || return 1
    if is_true "$REQUIRE_PLAN_BACKLOG_CLEAR_BEFORE_DONE" && backlog_has_unchecked_local_tasks; then
        return 1
    fi
    return 0
}

backlog_has_unchecked_local_tasks() {
    local source_file
    while IFS= read -r source_file; do
        [ -n "$source_file" ] || continue
        if markdown_has_unchecked_local_tasks "$source_file"; then
            return 0
        fi
    done < <(collect_backlog_source_files)
    return 1
}

file_mtime_epoch() {
    local target="$1"
    [ -e "$target" ] || { echo "-1"; return 0; }
    if stat -f '%m' "$target" >/dev/null 2>&1; then
        stat -f '%m' "$target" 2>/dev/null || echo "-1"
        return 0
    fi
    if stat -c '%Y' "$target" >/dev/null 2>&1; then
        stat -c '%Y' "$target" 2>/dev/null || echo "-1"
        return 0
    fi
    echo "-1"
}

backlog_sources_newer_than_plan() {
    local plan_file="${1:-$PLAN_FILE}"
    local plan_mtime source_file source_mtime rel_path current_fingerprint
    local -a stale_sources=()

    LAST_BACKLOG_STALE_SOURCES=""

    [ -f "$plan_file" ] || return 1

    if [ -n "${PLAN_FRESHNESS_FINGERPRINT:-}" ]; then
        current_fingerprint="$(backlog_sources_fingerprint 2>/dev/null || true)"
        if [ -n "$current_fingerprint" ]; then
            if [ "$current_fingerprint" = "$PLAN_FRESHNESS_FINGERPRINT" ]; then
                return 1
            fi
            LAST_BACKLOG_STALE_SOURCES="$(backlog_freshness_source_display_list)"
            [ -n "$LAST_BACKLOG_STALE_SOURCES" ] || LAST_BACKLOG_STALE_SOURCES="configured external backlog sources"
            return 0
        fi
    fi

    plan_mtime="$(file_mtime_epoch "$plan_file")"
    is_number "$plan_mtime" || return 1
    [ "$plan_mtime" -ge 0 ] || return 1

    while IFS= read -r source_file; do
        [ -n "$source_file" ] || continue
        [ -f "$source_file" ] || continue
        if [ "$source_file" = "$plan_file" ]; then
            continue
        fi
        source_mtime="$(file_mtime_epoch "$source_file")"
        if is_number "$source_mtime" && [ "$source_mtime" -gt "$plan_mtime" ]; then
            rel_path="$(path_relative_to_project "$source_file")"
            if [ -n "$rel_path" ] && [ "$rel_path" != "$source_file" ]; then
                stale_sources+=("$(path_for_display "$rel_path")")
            else
                stale_sources+=("$(path_for_display "$source_file")")
            fi
        fi
    done < <(collect_backlog_freshness_source_files)

    if [ "${#stale_sources[@]}" -eq 0 ]; then
        return 1
    fi

    LAST_BACKLOG_STALE_SOURCES="$(join_with_commas "${stale_sources[@]+"${stale_sources[@]}"}")"
    return 0
}

enforce_phase_route_prerequisites() {
    local current_phase="${1:-}"
    local candidate_next="${2:-done}"
    local remap_target="$candidate_next"
    local -a reasons=()
    local stale_sources_text=""

    LAST_PHASE_ROUTE_GUARD_REASON=""
    LAST_PHASE_ROUTE_GUARD_NEXT_PHASE="$candidate_next"

    if ! is_phase_or_done "$candidate_next"; then
        LAST_PHASE_ROUTE_GUARD_NEXT_PHASE="$candidate_next"
        echo "$candidate_next"
        return 0
    fi

    if is_true "$REQUIRE_PLAN_FRESHNESS_FOR_BUILD"; then
        if backlog_sources_newer_than_plan "$PLAN_FILE"; then
            stale_sources_text="${LAST_BACKLOG_STALE_SOURCES:-configured backlog sources}"
            case "$candidate_next" in
                build|test|refactor|lint|document|done)
                    remap_target="plan"
                    reasons+=("plan refresh required: backlog sources newer than plan ($stale_sources_text)")
                    ;;
                *)
                    ;;
            esac
        fi
    fi

    LAST_PHASE_ROUTE_GUARD_NEXT_PHASE="$remap_target"
    if [ "${#reasons[@]}" -gt 0 ]; then
        LAST_PHASE_ROUTE_GUARD_REASON="$(join_with_commas "${reasons[@]+"${reasons[@]}"}")"
    fi
    echo "$remap_target"
}

enforce_terminal_done_requirements() {
    local current_phase="${1:-}"
    local candidate_next="${2:-done}"
    local current_phase_passed="${3:-false}"
    local test_satisfied=false
    local refactor_satisfied=false
    local post_refactor_test_ready=false
    local lint_satisfied=false
    local document_satisfied=false
    local -a missing_required=()
    local remap_target=""

    LAST_DONE_GUARD_REASON=""
    LAST_DONE_GUARD_NEXT_PHASE="$candidate_next"
    if [ "$candidate_next" != "done" ]; then
        LAST_DONE_GUARD_NEXT_PHASE="$candidate_next"
        echo "$candidate_next"
        return 0
    fi

    if phase_requirement_satisfied "test" "$current_phase" "$current_phase_passed"; then
        test_satisfied=true
    fi
    if phase_requirement_satisfied "refactor" "$current_phase" "$current_phase_passed"; then
        refactor_satisfied=true
    fi
    if post_refactor_test_satisfied "$current_phase" "$current_phase_passed"; then
        post_refactor_test_ready=true
    fi
    if phase_requirement_satisfied "lint" "$current_phase" "$current_phase_passed"; then
        lint_satisfied=true
    fi
    if phase_requirement_satisfied "document" "$current_phase" "$current_phase_passed"; then
        document_satisfied=true
    fi

    if is_true "$current_phase_passed" && project_terminal_or_handoff_ready && shell_no_local_work_proven; then
        LAST_DONE_GUARD_NEXT_PHASE="done"
        LAST_DONE_GUARD_REASON="terminal guard allowed done: plan declares no local work or handoff-ready state and local backlog is clear"
        echo "done"
        return 0
    fi

    if [ "$test_satisfied" != "true" ]; then
        missing_required+=("test")
    fi
    if [ "$refactor_satisfied" != "true" ]; then
        missing_required+=("refactor")
    fi
    if [ "$refactor_satisfied" = "true" ] && [ "$post_refactor_test_ready" != "true" ]; then
        missing_required+=("post_refactor_test")
    fi
    if is_true "$REQUIRE_LINT_BEFORE_DONE" && [ "$lint_satisfied" != "true" ]; then
        missing_required+=("lint")
    fi
    if is_true "$REQUIRE_DOCUMENT_BEFORE_DONE" && [ "$document_satisfied" != "true" ]; then
        missing_required+=("document")
    fi
    if is_true "$REQUIRE_PLAN_BACKLOG_CLEAR_BEFORE_DONE" && backlog_has_unchecked_local_tasks; then
        missing_required+=("plan_backlog")
    fi

    if [ "${#missing_required[@]}" -eq 0 ] && ! shell_terminal_verified; then
        missing_required+=("test")
        LAST_DONE_GUARD_REASON="terminal verification missing or failed: ${SHELL_GATES_FAILURE:-unknown check outcome}"
    fi
    if [ "${#missing_required[@]}" -eq 0 ]; then
        LAST_DONE_GUARD_NEXT_PHASE="done"
        echo "done"
        return 0
    fi

    if printf '%s\n' "${missing_required[@]}" | grep -Fxq "test"; then
        remap_target="test"
    elif printf '%s\n' "${missing_required[@]}" | grep -Fxq "refactor"; then
        remap_target="refactor"
    elif printf '%s\n' "${missing_required[@]}" | grep -Fxq "post_refactor_test"; then
        remap_target="test"
    elif printf '%s\n' "${missing_required[@]}" | grep -Fxq "lint"; then
        remap_target="lint"
    elif printf '%s\n' "${missing_required[@]}" | grep -Fxq "document"; then
        remap_target="document"
    elif printf '%s\n' "${missing_required[@]}" | grep -Fxq "plan_backlog"; then
        remap_target="plan"
    else
        remap_target="${missing_required[0]}"
    fi

    LAST_DONE_GUARD_REASON="terminal guard remap: done blocked until required phase pass(es): $(join_with_commas "${missing_required[@]+"${missing_required[@]}"}")"
    LAST_DONE_GUARD_NEXT_PHASE="$remap_target"
    echo "$remap_target"
}

phase_index_or_done() {
    case "$1" in
        plan) echo 0; return 0 ;;
        build) echo 1; return 0 ;;
        test) echo 2; return 0 ;;
        refactor) echo 3; return 0 ;;
        lint) echo 4; return 0 ;;
        document) echo 5; return 0 ;;
        done) echo 6; return 0 ;;
        *) echo -1; return 1 ;;
    esac
}

phase_pair_cycle_key() {
    local phase_a="${1:-}"
    local phase_b="${2:-}"
    local index_a index_b

    [ -n "$phase_a" ] && [ -n "$phase_b" ] || return 1
    [ "$phase_a" != "$phase_b" ] || return 1
    [ "$phase_a" != "done" ] && [ "$phase_b" != "done" ] || return 1
    is_phase_or_done "$phase_a" && is_phase_or_done "$phase_b" || return 1

    index_a="$(phase_index_or_done "$phase_a")"
    index_b="$(phase_index_or_done "$phase_b")"
    is_number "$index_a" && is_number "$index_b" || return 1
    [ "$index_a" -ge 0 ] && [ "$index_b" -ge 0 ] || return 1

    if [ "$index_a" -le "$index_b" ]; then
        printf '%s<->%s' "$phase_a" "$phase_b"
    else
        printf '%s<->%s' "$phase_b" "$phase_a"
    fi
}

phase_transition_history_append() {
    local phase="${1:-}"
    local attempt="${2:-?}"
    local next_phase="${3:-$phase}"
    local outcome="${4:-hold}"
    local reason="${5:-no explicit rationale}"
    local normalized_reason

    if [ -z "$phase" ]; then
        return 0
    fi

    normalized_reason="$(printf '%s' "$reason" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g' | sed 's/^ *//; s/ *$//')"
    normalized_reason="${normalized_reason:-no explicit rationale}"
    PHASE_TRANSITION_HISTORY+=("${phase}(attempt ${attempt})->${next_phase}|${outcome}|${normalized_reason}")
}

phase_transition_history_recent() {
    local limit="${1:-8}"
    local start=0
    local i

    if [ "${#PHASE_TRANSITION_HISTORY[@]}" -eq 0 ]; then
        echo "no transitions yet"
        return 0
    fi

    if ! is_number "$limit" || [ "$limit" -lt 1 ]; then
        limit=8
    fi
    if [ "${#PHASE_TRANSITION_HISTORY[@]}" -gt "$limit" ]; then
        start=$(( ${#PHASE_TRANSITION_HISTORY[@]} - limit ))
    fi

    for (( i = start; i < ${#PHASE_TRANSITION_HISTORY[@]}; i++ )); do
        echo "${PHASE_TRANSITION_HISTORY[$i]}"
    done
}

collect_phase_resume_blockers() {
    local phase="$1"
    local -a blockers=()
    local stale_sources_text=""
    case "$phase" in
        plan)
            ;;
        build)
            mapfile -t blockers < <(collect_build_prerequisites_issues)
            ;;
        test|refactor|lint|document)
            if [ ! -f "$PLAN_FILE" ]; then
                blockers+=("test/build prerequisite missing: IMPLEMENTATION_PLAN.md")
            fi
            if [ ! -f "$STACK_SNAPSHOT_FILE" ]; then
                blockers+=("test/build prerequisite missing: research/STACK_SNAPSHOT.md")
            fi
            if [ -f "$PLAN_FILE" ] && ! plan_is_semantically_actionable "$PLAN_FILE"; then
                blockers+=("plan is not semantically actionable")
            fi
            if is_true "$REQUIRE_PLAN_FRESHNESS_FOR_BUILD" && backlog_sources_newer_than_plan "$PLAN_FILE"; then
                stale_sources_text="${LAST_BACKLOG_STALE_SOURCES:-configured backlog sources}"
                blockers+=("plan refresh required before $phase: backlog sources newer than plan ($stale_sources_text)")
            fi
            ;;
        *)
            blockers+=("unknown phase '$phase'")
            ;;
    esac

    print_array_lines "${blockers[@]+"${blockers[@]}"}"
}

summarize_blocks_for_log() {
    local -a blockers=("$@")
    local idx=0
    local output=""
    local item
    if [ "${#blockers[@]}" -eq 0 ]; then
        printf '%s' ""
        return 0
    fi
    for item in "${blockers[@]}"; do
        [ -z "$item" ] && continue
        if [ -z "$output" ]; then
            output="$item"
        else
            output="$output; $item"
        fi
    done
    printf '%s' "$output"
}

# Build gate and artifact validation
gitignore_required_entries() {
    cat <<'EOF'
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
}

gitignore_has_entry() {
    local gitignore_file="$1"
    local entry="$2"
    local escaped_entry

    [ -f "$gitignore_file" ] || return 1
    escaped_entry="$(printf '%s' "$entry" | sed -E 's/[][(){}.^$*+?|\\]/\\&/g')"
    # Tolerate trailing inline comments so existing entries like "logs/ # keep" don't get duplicated.
    grep -qE "^[[:space:]]*${escaped_entry}[[:space:]]*(#.*)?$" "$gitignore_file"
}

gitignore_missing_required_entries() {
    local gitignore_file="$PROJECT_DIR/.gitignore"
    local entry
    if [ ! -f "$gitignore_file" ]; then
        gitignore_required_entries
        return 0
    fi

    local required_entries
    required_entries="$(gitignore_required_entries)"
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        if ! gitignore_has_entry "$gitignore_file" "$entry"; then
            echo "$entry"
        fi
    done <<< "$required_entries"
}

ensure_gitignore_guardrails() {
    local gitignore_file="$PROJECT_DIR/.gitignore"
    local required_entries
    required_entries="$(gitignore_required_entries)"

    ensure_runtime_file "$gitignore_file" || return 1
    ensure_runtime_directory "$(dirname "$gitignore_file")" || return 1
    touch "$gitignore_file" || return 1

    local added=false
    local entry
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        if ! gitignore_has_entry "$gitignore_file" "$entry"; then
            echo "$entry" >> "$gitignore_file"
            added=true
        fi
    done <<< "$required_entries"

    if [ "$added" = true ]; then
        info "Updated .gitignore with required runtime-safety entries."
    fi
}

file_has_local_identity_leakage() {
    local candidate_file="$1"
    if [ ! -f "$candidate_file" ]; then
        return 1
    fi

    local home_dir home_dir_regex
    home_dir="${HOME:-}"
    home_dir_regex="$(printf '%s' "$home_dir" | sed 's/[][(){}.^$*+?|\\/]/\\&/g')"

    if RB_HOME_REGEX="$home_dir_regex" RB_ALLOW_REGEX="${MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX:-}" awk '
        BEGIN { home_re=ENVIRON["RB_HOME_REGEX"]; allow_re=ENVIRON["RB_ALLOW_REGEX"] }
        function scrub(line) {
            if (allow_re != "") {
                gsub(allow_re, "", line)
            }
            return line
        }
        {
            line = scrub($0)
            if (home_re != "" && line ~ ("(^|[^[:alnum:]_.-])" home_re "(/|$)")) {
                found = 1
                exit
            }
            if (line ~ /\/Users\/[A-Za-z0-9._-]+\// || line ~ /\/home\/[A-Za-z0-9._-]+\// || line ~ /\/root\/[A-Za-z0-9._-]+\//) {
                found = 1
                exit
            }
        }
        END { exit found ? 0 : 1 }
    ' "$candidate_file" 2>/dev/null; then
        return 0
    fi
    return 1
}

markdown_artifacts_are_clean() {
    local leakage_pattern='succeeded in [0-9]+ms:|assistant[[:space:]]+to=|recipient_name[[:space:]]*:|tokens used|mcp startup:'
    local file bad=0
    local files=()
    local scoped_files=()

    [ -f "$PLAN_FILE" ] && files+=("$PLAN_FILE")
    [ -f "$PROJECT_DIR/README.md" ] && files+=("$PROJECT_DIR/README.md")

    local research_files spec_files
    research_files="$(find "$RESEARCH_DIR" -maxdepth 2 -type f -name "*.md" 2>/dev/null || true)"
    while IFS= read -r file; do
        [ -n "$file" ] && files+=("$file")
    done <<< "$research_files"

    spec_files="$(find "$SPECS_DIR" -maxdepth 3 -type f -name "*.md" 2>/dev/null || true)"
    while IFS= read -r file; do
        [ -n "$file" ] && files+=("$file")
    done <<< "$spec_files"

    if is_true "$AUTO_REPAIR_MARKDOWN_ONLY_SESSION_CHANGED"; then
        for file in "${files[@]}"; do
            [ -f "$file" ] || continue
            if session_changed_paths_contains "$(path_relative_to_project "$file")"; then
                scoped_files+=("$file")
            fi
        done
        files=("${scoped_files[@]+"${scoped_files[@]}"}")
    fi

    if [ "${#files[@]}" -gt 0 ]; then
        for file in "${files[@]}"; do
            [ -f "$file" ] || continue
            if grep -qiE "$leakage_pattern" "$file" 2>/dev/null; then
                warn "Detected tool transcript leakage in markdown artifact: $(path_for_display "$file")"
                bad=1
            fi
            if file_has_local_identity_leakage "$file"; then
                warn "Detected local identity/path leakage in markdown artifact: $(path_for_display "$file")"
                bad=1
            fi
        done
    fi

    [ "$bad" -eq 0 ]
}

sanitize_markdown_artifact_file() {
    local file="$1"
    [ -f "$file" ] || return 0

    local tmp_file
    tmp_file="$(mktemp "$CONFIG_DIR/markdown-clean.XXXXXX")" || return 1
    local artifact_dir=""
    local artifact_prefix=""
    local diff_artifact=""
    local backup_artifact=""
    local rel_file=""
    rel_file="$(path_for_display "$(path_relative_to_project "$file")")"

    if RB_ALLOW_REGEX="${MARKDOWN_LOCAL_PATH_ALLOWLIST_REGEX:-}" awk '
        BEGIN { allow_re=ENVIRON["RB_ALLOW_REGEX"] }
        function scrub(line) {
            if (allow_re != "") {
                gsub(allow_re, "", line)
            }
            return line
        }
        {
            clean_line = scrub($0)
            if ($0 ~ /succeeded in [0-9][0-9]*ms:/ || $0 ~ /assistant[[:space:]][[:space:]]*to=/ || $0 ~ /recipient_name[[:space:]]*:/ || $0 ~ /tokens used/ || $0 ~ /mcp startup:/) { next }
            if (clean_line ~ /\/Users\/[A-Za-z0-9._-]+\// || clean_line ~ /\/root\/[A-Za-z0-9._-]+\// || clean_line ~ /\/home\/[A-Za-z0-9._-]+\//) { next }
        }
        { print }
    ' "$file" > "$tmp_file"; then
        if ! cmp -s "$file" "$tmp_file"; then
            artifact_dir="$MARKDOWN_REPAIR_ARTIFACT_DIR/$SESSION_ID"
            mkdir -p "$artifact_dir" 2>/dev/null || artifact_dir="$CONFIG_DIR"
            artifact_prefix="$(printf '%s' "$rel_file" | tr '/ ' '__' | tr -cd 'A-Za-z0-9._-')"
            [ -n "$artifact_prefix" ] || artifact_prefix="artifact"

            diff_artifact="$artifact_dir/${artifact_prefix}.diff"
            diff -u "$file" "$tmp_file" > "$diff_artifact" 2>/dev/null || true

            if is_true "$AUTO_REPAIR_MARKDOWN_DRY_RUN"; then
                MARKDOWN_ARTIFACTS_CLEANED_LIST="${MARKDOWN_ARTIFACTS_CLEANED_LIST}${MARKDOWN_ARTIFACTS_CLEANED_LIST:+$'\n'}[dry-run] ${rel_file}"
                MARKDOWN_ARTIFACTS_PREVIEW_LIST="${MARKDOWN_ARTIFACTS_PREVIEW_LIST}${MARKDOWN_ARTIFACTS_PREVIEW_LIST:+$'\n'}$(path_for_display "$diff_artifact")"
                rm -f "$tmp_file"
                return 0
            fi

            if is_true "$AUTO_REPAIR_MARKDOWN_BACKUP"; then
                backup_artifact="$artifact_dir/${artifact_prefix}.bak"
                cp "$file" "$backup_artifact" 2>/dev/null || true
                if [ -f "$backup_artifact" ]; then
                    MARKDOWN_ARTIFACTS_BACKUP_LIST="${MARKDOWN_ARTIFACTS_BACKUP_LIST}${MARKDOWN_ARTIFACTS_BACKUP_LIST:+$'\n'}$(path_for_display "$backup_artifact")"
                fi
            fi
            mv "$tmp_file" "$file"
            MARKDOWN_ARTIFACTS_CLEANED_LIST="${MARKDOWN_ARTIFACTS_CLEANED_LIST}${MARKDOWN_ARTIFACTS_CLEANED_LIST:+$'\n'}$(path_for_display "$file")"
            MARKDOWN_ARTIFACTS_PREVIEW_LIST="${MARKDOWN_ARTIFACTS_PREVIEW_LIST}${MARKDOWN_ARTIFACTS_PREVIEW_LIST:+$'\n'}$(path_for_display "$diff_artifact")"
            return 0
        fi
        rm -f "$tmp_file"
    else
        rm -f "$tmp_file"
        return 1
    fi
}

sanitize_markdown_artifacts() {
    MARKDOWN_ARTIFACTS_CLEANED_LIST=""
    MARKDOWN_ARTIFACTS_PREVIEW_LIST=""
    MARKDOWN_ARTIFACTS_BACKUP_LIST=""
    local file
    local -a targets=("$PLAN_FILE" "$PROJECT_DIR/README.md")
    local -a scoped_targets=()

    if [ -d "$RESEARCH_DIR" ]; then
        while IFS= read -r -d '' file; do
            targets+=("$file")
        done < <(find "$RESEARCH_DIR" -maxdepth 3 -type f -name "*.md" -print0)
    fi

    if [ -d "$SPECS_DIR" ]; then
        while IFS= read -r -d '' file; do
            targets+=("$file")
        done < <(find "$SPECS_DIR" -maxdepth 4 -type f -name "*.md" -print0)
    fi

    if is_true "$AUTO_REPAIR_MARKDOWN_ONLY_SESSION_CHANGED"; then
        for file in "${targets[@]+"${targets[@]}"}"; do
            [ -f "$file" ] || continue
            local rel_target
            rel_target="$(path_relative_to_project "$file")"
            if session_changed_paths_contains "$rel_target"; then
                scoped_targets+=("$file")
            fi
        done
        targets=("${scoped_targets[@]+"${scoped_targets[@]}"}")
    fi

    for file in "${targets[@]+"${targets[@]}"}"; do
        [ -f "$file" ] || continue
        sanitize_markdown_artifact_file "$file" || true
    done

    [ -n "$MARKDOWN_ARTIFACTS_CLEANED_LIST" ]
}

markdown_artifact_cleanup_summary() {
    local summary=""
    if [ -n "$MARKDOWN_ARTIFACTS_CLEANED_LIST" ]; then
        summary="$MARKDOWN_ARTIFACTS_CLEANED_LIST"
    fi
    if [ -n "$MARKDOWN_ARTIFACTS_PREVIEW_LIST" ]; then
        summary="${summary}${summary:+$'\n'}diff artifacts: ${MARKDOWN_ARTIFACTS_PREVIEW_LIST//$'\n'/, }"
    fi
    if [ -n "$MARKDOWN_ARTIFACTS_BACKUP_LIST" ]; then
        summary="${summary}${summary:+$'\n'}backups: ${MARKDOWN_ARTIFACTS_BACKUP_LIST//$'\n'/, }"
    fi
    printf '%s' "$summary"
}

stack_primary_from_snapshot() {
    if [ ! -f "$STACK_SNAPSHOT_FILE" ]; then
        echo "Unknown"
        return 0
    fi

    local primary
    primary="$(awk -F': ' '/^[[:space:]]*-?[[:space:]]*primary_stack:/ { gsub(/^[[:space:]]*-?[[:space:]]*primary_stack:[[:space:]]*/, "", $0); print $0; exit }' "$STACK_SNAPSHOT_FILE")"
    primary="${primary:-Unknown}"
    echo "$primary"
}

join_with_commas() {
    local -a items=("$@")
    local IFS=", "
    if [ "${#items[@]}" -eq 0 ]; then
        echo "-"
        return 0
    fi
    echo "${items[*]}"
}

stack_confidence_label() {
    local score="$1"
    if [ "$score" -ge 80 ]; then
        echo "high"
    elif [ "$score" -ge 60 ]; then
        echo "medium"
    elif [ "$score" -ge 35 ]; then
        echo "low"
    else
        echo "very_low"
    fi
}

run_stack_discovery() {
    mkdir -p "$RESEARCH_DIR"
    info "Running deterministic stack discovery scan."

    local pyproject_hits
    local -a node_signal=()
    local -a python_signal=()
    local -a go_signal=()
    local -a rust_signal=()
    local -a java_signal=()
    local -a dotnet_signal=()
    local -a unknown_signal=()
    local node_score=0 python_score=0 go_score=0
    local rust_score=0 java_score=0 dotnet_score=0 unknown_score=0

    local ts_count go_count java_count cs_count rb_count rs_count js_count
    pyproject_hits="$(find "$PROJECT_DIR" -maxdepth 2 -type f \( -name "*.py" -o -name "*.pyi" -o -name "requirements*.txt" \) 2>/dev/null | wc -l | tr -d ' ')"
    ts_count="$(find "$PROJECT_DIR" -maxdepth 3 -type f -name "*.ts" 2>/dev/null | wc -l | tr -d ' ')"
    go_count="$(find "$PROJECT_DIR" -maxdepth 3 -type f -name "*.go" 2>/dev/null | wc -l | tr -d ' ')"
    java_count="$(find "$PROJECT_DIR" -maxdepth 3 -type f \( -name "*.java" -o -name "*.kt" -o -name "*.gradle" -o -name "*.gradle.kts" \) 2>/dev/null | wc -l | tr -d ' ')"
    cs_count="$(find "$PROJECT_DIR" -maxdepth 3 -type f -name "*.csproj" 2>/dev/null | wc -l | tr -d ' ')"
    rs_count="$(find "$PROJECT_DIR" -maxdepth 3 -type f -name "*.rs" 2>/dev/null | wc -l | tr -d ' ')"
    rb_count="$(find "$PROJECT_DIR" -maxdepth 3 -type f -name "*.rb" 2>/dev/null | wc -l | tr -d ' ')"
    js_count="$(find "$PROJECT_DIR" -maxdepth 3 -type f -name "*.js" 2>/dev/null | wc -l | tr -d ' ')"

    # Node / JS / TS
    [ -f "$PROJECT_DIR/package.json" ] && { node_score=$((node_score + 55)); node_signal+=("package.json"); }
    [ -f "$PROJECT_DIR/package-lock.json" ] && { node_score=$((node_score + 10)); node_signal+=("package-lock.json"); }
    [ -f "$PROJECT_DIR/pnpm-lock.yaml" ] && { node_score=$((node_score + 10)); node_signal+=("pnpm-lock.yaml"); }
    [ -f "$PROJECT_DIR/yarn.lock" ] && { node_score=$((node_score + 10)); node_signal+=("yarn.lock"); }
    [ -f "$PROJECT_DIR/tsconfig.json" ] && { node_score=$((node_score + 12)); node_signal+=("tsconfig.json"); }
    [ -d "$PROJECT_DIR/node_modules" ] && { node_score=$((node_score + 3)); node_signal+=("node_modules"); }
    if is_number "$ts_count" && [ "$ts_count" -gt 0 ]; then node_score=$((node_score + 10)); node_signal+=("${ts_count} TS files"); fi
    if is_number "$js_count" && [ "$js_count" -gt 0 ]; then node_score=$((node_score + 8)); node_signal+=("${js_count} JS files"); fi

    # Python
    [ -f "$PROJECT_DIR/pyproject.toml" ] && { python_score=$((python_score + 60)); python_signal+=("pyproject.toml"); }
    [ -f "$PROJECT_DIR/requirements.txt" ] && { python_score=$((python_score + 20)); python_signal+=("requirements.txt"); }
    [ -f "$PROJECT_DIR/requirements-dev.txt" ] && { python_score=$((python_score + 10)); python_signal+=("requirements-dev.txt"); }
    [ -f "$PROJECT_DIR/setup.py" ] && { python_score=$((python_score + 15)); python_signal+=("setup.py"); }
    [ -f "$PROJECT_DIR/Pipfile" ] && { python_score=$((python_score + 10)); python_signal+=("Pipfile"); }
    if is_number "$pyproject_hits" && [ "$pyproject_hits" -gt 0 ]; then python_score=$((python_score + 8)); python_signal+=("${pyproject_hits} python manifest/files"); fi

    # Go
    [ -f "$PROJECT_DIR/go.mod" ] && { go_score=$((go_score + 70)); go_signal+=("go.mod"); }
    [ -f "$PROJECT_DIR/go.sum" ] && { go_score=$((go_score + 15)); go_signal+=("go.sum"); }
    if is_number "$go_count" && [ "$go_count" -gt 0 ]; then go_score=$((go_score + 10)); go_signal+=("${go_count} Go files"); fi

    # Rust
    [ -f "$PROJECT_DIR/Cargo.toml" ] && { rust_score=$((rust_score + 80)); rust_signal+=("Cargo.toml"); }
    [ -f "$PROJECT_DIR/Cargo.lock" ] && { rust_score=$((rust_score + 12)); rust_signal+=("Cargo.lock"); }
    if is_number "$rs_count" && [ "$rs_count" -gt 0 ]; then rust_score=$((rust_score + 10)); rust_signal+=("${rs_count} Rust files"); fi

    # Java / JVM
    [ -f "$PROJECT_DIR/pom.xml" ] && { java_score=$((java_score + 50)); java_signal+=("pom.xml"); }
    [ -f "$PROJECT_DIR/build.gradle" ] && { java_score=$((java_score + 35)); java_signal+=("build.gradle"); }
    [ -f "$PROJECT_DIR/build.gradle.kts" ] && { java_score=$((java_score + 35)); java_signal+=("build.gradle.kts"); }
    if is_number "$java_count" && [ "$java_count" -gt 0 ]; then java_score=$((java_score + 8)); java_signal+=("${java_count} JVM files"); fi

    # .NET
    [ -f "$PROJECT_DIR/Directory.Build.props" ] && { dotnet_score=$((dotnet_score + 35)); dotnet_signal+=("Directory.Build.props"); }
    if is_number "$cs_count" && [ "$cs_count" -gt 0 ]; then dotnet_score=$((dotnet_score + 12)); dotnet_signal+=("${cs_count} csproj files"); fi

    # Ruby
    [ -f "$PROJECT_DIR/Gemfile" ] && { unknown_score=$((unknown_score + 10)); unknown_signal+=("Gemfile"); }
    if is_number "$rb_count" && [ "$rb_count" -gt 0 ]; then unknown_score=$((unknown_score + 4)); unknown_signal+=("${rb_count} Ruby files"); fi

    local node_signal_summary="-" python_signal_summary="-" go_signal_summary="-"
    local rust_signal_summary="-" java_signal_summary="-" dotnet_signal_summary="-"
    local unknown_signal_summary="-"
    if [ "${#node_signal[@]}" -gt 0 ]; then
        node_signal_summary="$(join_with_commas "${node_signal[@]}")"
    fi
    if [ "${#python_signal[@]}" -gt 0 ]; then
        python_signal_summary="$(join_with_commas "${python_signal[@]}")"
    fi
    if [ "${#go_signal[@]}" -gt 0 ]; then
        go_signal_summary="$(join_with_commas "${go_signal[@]}")"
    fi
    if [ "${#rust_signal[@]}" -gt 0 ]; then
        rust_signal_summary="$(join_with_commas "${rust_signal[@]}")"
    fi
    if [ "${#java_signal[@]}" -gt 0 ]; then
        java_signal_summary="$(join_with_commas "${java_signal[@]}")"
    fi
    if [ "${#dotnet_signal[@]}" -gt 0 ]; then
        dotnet_signal_summary="$(join_with_commas "${dotnet_signal[@]}")"
    fi
    if [ "${#unknown_signal[@]}" -gt 0 ]; then
        unknown_signal_summary="$(join_with_commas "${unknown_signal[@]}")"
    fi

    local ranking_file
    ranking_file="$(mktemp "$CONFIG_DIR/stack-ranking.XXXXXX")" || {
        warn "Unable to create temp file for stack ranking."
        return 1
    }
    {
        printf "%03d|Node.js|%s\n" "$node_score" "$node_signal_summary"
        printf "%03d|Python|%s\n" "$python_score" "$python_signal_summary"
        printf "%03d|Go|%s\n" "$go_score" "$go_signal_summary"
        printf "%03d|Rust|%s\n" "$rust_score" "$rust_signal_summary"
        printf "%03d|Java|%s\n" "$java_score" "$java_signal_summary"
        printf "%03d|.NET|%s\n" "$dotnet_score" "$dotnet_signal_summary"
        printf "%03d|Ruby|%s\n" "$unknown_score" "$unknown_signal_summary"
        printf "%03d|Unknown|-\n" "$unknown_score"
    } > "$ranking_file"

    local -a ranked_candidates=()
    while IFS='|' read -r candidate_score candidate_stack candidate_signal; do
        ranked_candidates+=( "$candidate_score|$candidate_stack|$candidate_signal" )
    done < <(sort -t'|' -k1,1nr "$ranking_file")

    rm -f "$ranking_file"

    local primary_candidate primary_score
    primary_candidate="Unknown"
    primary_score=0
    if [ "${#ranked_candidates[@]}" -gt 0 ]; then
        IFS='|' read -r primary_score primary_candidate _ <<< "${ranked_candidates[0]}"
    fi

    local primary_confidence
    primary_confidence="$(stack_confidence_label "$primary_score")"
    if ! is_number "$primary_score"; then primary_score=0; fi

    {
        echo "# Stack Snapshot"
        echo ""
        echo "- generated_at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "- project_root: ."
        echo "- primary_stack: $primary_candidate"
        echo "- primary_score: $primary_score/100"
        echo "- confidence: $primary_confidence"
        echo ""
        echo "## Project Stack Ranking"
        echo ""
        echo "| rank | stack | score | evidence |"
        echo "| --- | --- | --- | --- |"
        local idx=1
        for entry in "${ranked_candidates[@]}"; do
            if [ -z "$entry" ]; then
                continue
            fi
            IFS='|' read -r score stack evidence <<< "$entry"
            echo "| $idx | $stack | $score | $evidence |"
            idx=$((idx + 1))
        done
        echo ""
        echo "## Deterministic Alternatives Ranking"
        echo "- Candidate evaluation is based on repository-level manifest and source signals only."
        echo "- Primary decision rule: highest score, then explicit manifest precedence."
        echo ""
        echo "### Top 3 stack alternatives (ranked)"
        local alt_idx=1
        for entry in "${ranked_candidates[@]}"; do
            [ "$alt_idx" -gt 3 ] && break
            IFS='|' read -r score stack evidence <<< "$entry"
            if [ "$stack" = "Unknown" ] && [ "$score" -eq 0 ] && [ "$alt_idx" -eq 1 ]; then
                echo "- 1) Unknown (insufficient deterministic signals)"
            else
                echo "- $alt_idx) $stack: score=$score, evidence=[$evidence]"
            fi
            alt_idx=$((alt_idx + 1))
        done
    } > "$STACK_SNAPSHOT_FILE"

    info "Stack snapshot complete: primary stack ${primary_candidate} (${primary_score}/100, ${primary_confidence})."
}

plan_is_semantically_actionable() {
    local plan_file="$1"
    [ -f "$plan_file" ] || return 1

    local has_goal=false
    local has_validation=false
    local has_action_path=false
    local task_count=0

    if grep -qiE '(^|#{1,6}[[:space:]]*)(goal|scope|objectives?|overview|context)\b|^[[:space:]]*(goal|scope|objectives?|overview|context)[[:space:]]*:' "$plan_file" 2>/dev/null; then
        has_goal=true
    fi
    if grep -qiE '(^|#{1,6}[[:space:]]*)(validation|verification|acceptance criteria|success criteria|definition of done|readiness|qa|testing)\b|^[[:space:]]*(validation|verification|acceptance criteria|success criteria|definition of done|readiness|qa|testing)[[:space:]]*:' "$plan_file" 2>/dev/null; then
        has_validation=true
    fi
    if ! is_true "$has_validation" && grep -qiE '^[[:space:]]*([-+*]|[0-9]+[.)])[[:space:]]+\[[ xX✓✔☑☒]\][[:space:]]+.*\b(validation|verify|verification|acceptance|success criteria|definition of done|readiness|qa|testing|test|smoke|gate)\b' "$plan_file" 2>/dev/null; then
        has_validation=true
    fi
    task_count="$(plan_task_count "$plan_file")"
    if [ "${task_count:-0}" -ge 1 ] || plan_has_terminal_or_handoff_intent "$plan_file"; then
        has_action_path=true
    fi

    if is_true "$has_goal" && is_true "$has_validation" && is_true "$has_action_path"; then
        return 0
    fi
    return 1
}

plan_is_fallback_placeholder() {
    local plan_file="$1"
    [ -f "$plan_file" ] || return 1
    grep -q '^ralphie_fallback_placeholder:[[:space:]]*true[[:space:]]*$' "$plan_file" 2>/dev/null
}

plan_task_count() {
    local plan_file="$1"
    if [ ! -f "$plan_file" ]; then
        echo "0"
        return 0
    fi
    local count
    count="$(grep -cE '^[[:space:]]*([0-9]+[.)][[:space:]]+|[-+*][[:space:]]+\[[ xX✓✔☑☒]\]([[:space:]]|$)|[-+*][[:space:]]+(Run|Add|Update|Implement|Fix|Verify|Test|Document|Research|Decide|Refactor|Remove|Deprecate)[[:space:]])' "$plan_file" 2>/dev/null || true)"
    if ! is_number "$count"; then
        count="0"
    fi
    echo "$count"
}

write_gate_feedback() {
    local stage="$1"
    shift
    ensure_runtime_file "$GATE_FEEDBACK_FILE" || return 1
    ensure_runtime_directory "$(dirname "$GATE_FEEDBACK_FILE")" || return 1
    {
        echo "# Ralphie Gate Feedback"
        echo ""
        echo "- Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "- Mode: $stage"
        echo ""
        echo "## Blockers"
        if [ "$#" -eq 0 ]; then
            echo "- None"
        else
            for _entry in "$@"; do
                echo "- $_entry"
            done
        fi
    } > "$GATE_FEEDBACK_FILE"
}

check_build_prerequisites() {
    local -a missing=()
    # Re-apply guardrails on every build-gate check so retries self-heal if
    # prior phase edits removed required .gitignore entries.
    ensure_gitignore_guardrails
    mapfile -t missing < <(collect_build_prerequisites_issues)
    if [ "${#missing[@]}" -gt 0 ]; then
        warn "Build prerequisites are incomplete:"
        local entry
        for entry in "${missing[@]}"; do
            warn "  - $entry"
        done
        log_reason_code "RB_BUILD_PREREQ_MISSING" "one or more build prerequisites failed"
        write_gate_feedback "build-prerequisites" "${missing[@]}"
        return 1
    fi

    rm -f "$GATE_FEEDBACK_FILE" 2>/dev/null || true
    return 0
}

collect_build_prerequisites_issues() {
    local -a missing=()
    if [ ! -d "$SPECS_DIR" ]; then
        missing+=("spec directory missing: specs/")
    fi
    if [ ! -d "$RESEARCH_DIR" ]; then
        missing+=("research directory missing: research/")
    fi
    if [ ! -f "$PLAN_FILE" ]; then
        missing+=("IMPLEMENTATION_PLAN.md missing before build")
    elif plan_is_fallback_placeholder "$PLAN_FILE"; then
        missing+=("IMPLEMENTATION_PLAN.md still contains Ralphie fallback placeholder; run PLAN to replace it with a project-specific plan")
    elif ! plan_is_semantically_actionable "$PLAN_FILE"; then
        missing+=("plan is not semantically actionable")
    fi

    if ! markdown_artifacts_are_clean; then
        missing+=("markdown artifacts must not contain tool transcript leakage or local identity/path leakage")
    fi

    local gitignore_missing_lines
    local -a gitignore_missing=()
    gitignore_missing_lines="$(gitignore_missing_required_entries || true)"
    while IFS= read -r missing_entry; do
        [ -n "$missing_entry" ] && gitignore_missing+=("$missing_entry")
    done <<< "$gitignore_missing_lines"
    if [ "${#gitignore_missing[@]}" -gt 0 ]; then
        local missing_joined
        missing_joined="$(printf '%s,' "${gitignore_missing[@]}" | sed 's/,$//')"
        missing+=(".gitignore must include local/sensitive/runtime guardrails (missing: $missing_joined)")
    fi

    if [ ! -f "$CONSTITUTION_FILE" ]; then
        missing+=("constitution file missing: .specify/memory/constitution.md")
    fi
    if is_true "$REQUIRE_PLAN_FRESHNESS_FOR_BUILD" && backlog_sources_newer_than_plan "$PLAN_FILE"; then
        local stale_sources
        stale_sources="${LAST_BACKLOG_STALE_SOURCES:-configured backlog sources}"
        missing+=("plan refresh required: backlog sources newer than plan ($stale_sources)")
    fi

    print_array_lines "${missing[@]+"${missing[@]}"}"
}

enforce_build_gate() {
    if ! check_build_prerequisites; then
        log_reason_code "RB_BUILD_GATE_PREREQ_FAILED" "build prerequisites failed"
        return 1
    fi
    return 0
}

collect_phase_schema_issues() {
    local phase="$1"
    local log_file="$2"
    local output_file="$3"
    local -a issues=()

    [ -f "$output_file" ] || issues+=("$phase output artifact missing: $output_file")
    [ -f "$log_file" ] || issues+=("$phase log artifact missing: $log_file")
    [ -n "$phase" ] || issues+=("missing phase name for schema check")

    print_array_lines "${issues[@]+"${issues[@]}"}"
}

pick_fallback_engine() { [ "${2:-}" = "claude" ] && echo "codex" || echo "claude"; }
effective_lock_wait_seconds() {
    local wait_seconds="${LOCK_WAIT_SECONDS:-0}"
    echo $(( wait_seconds + 7 ))
}
ensure_prompt_file() {
    local phase="$1"
    local file="$2"
    ensure_runtime_file "$file" || return 1
    ensure_runtime_directory "$(dirname "$file")" || return 1
    if [ -f "$file" ]; then
        return 0
    fi

    local phase_name="$phase"
    case "$phase_name" in
        plan|prepare)
            cat > "$file" <<'EOF'
# Ralphie Plan Phase Prompt
You are the autonomous planning engine for this project.

Goal
- Inspect the repository structure and runtime stack.
- Produce missing research artifacts and a concrete implementation plan.

Outputs (required)
- Research summary in `research/RESEARCH_SUMMARY.md` with `<confidence>`.
- `research/CODEBASE_MAP.md` mapping directories, entrypoints, and architecture assumptions.
- `research/DEPENDENCY_RESEARCH.md` documenting stack components and alternatives.
- `research/COVERAGE_MATRIX.md` with coverage against goals.
- `research/STACK_SNAPSHOT.md` with ranked stack hypotheses, deterministic confidence score, and alternatives.
- `IMPLEMENTATION_PLAN.md` with goal, validation criteria, and actionable tasks; if there is no local implementation work, state the no-local-work or handoff-ready conclusion explicitly.
- If `IMPLEMENTATION_PLAN.md` contains `ralphie_fallback_placeholder: true`, replace it with a project-specific plan and remove that marker before declaring PLAN complete.
- `consensus/build_gate.md` if needed for blockers.

Behavior
- Compare at least two viable implementation paths when uncertainty exists.
- Keep markdown artifacts portable: no local machine paths, no tool transcripts, no timing output.
- Respond with concise completion notes:
  - What artifacts were updated.
  - What assumptions were made.
  - Any blockers or risks that remain.
- Phase is done when this guidance is satisfied and artifacts are genuinely ready for BUILD handoff.
EOF
            ;;
        build)
            cat > "$file" <<'EOF'
# Ralphie Build Phase Prompt
You are the implementation agent.

Goal
- Execute the highest-priority plan tasks from `IMPLEMENTATION_PLAN.md`.
- Keep changes scoped and validated by existing project patterns.

Behavior
- Prefer minimal diffs and avoid unrelated churn.
- Update implementation and tests to satisfy plan acceptance criteria.
- When external alternatives exist, record rationale in implementation notes.
- Do not run live deploy, payment, provider, production infrastructure, or
  credential-mutating commands unless the project bootstrap/goals explicitly
  authorize that exact live operation for this run.
- Provide a concise completion summary:
  - Files changed and why.
  - Verification actions you ran and outcomes.
  - Any known risks before declaring BUILD complete.
EOF
            ;;
        test)
            cat > "$file" <<'EOF'
# Ralphie Test Phase Prompt
You are the verification agent.

Goal
- Exercise new/changed functionality with targeted checks.
- Record exact commands, results, and failures in `completion_log`.

Behavior
- Validate assumptions behind plan items before declaring done.
- Note any skipped checks with reason.
- Return concise test completion findings:
  - What was tested and what was not tested (with reason).
  - Whether acceptance checks passed for changed behavior.
  - Risks introduced, if any.
EOF
            ;;
        refactor)
            cat > "$file" <<'EOF'
# Ralphie Refactor Phase Prompt
You are the refactoring agent.

Goal
- Improve structure and maintainability of changed areas only.
- Keep behavior stable and backward-compatible unless explicitly changing requirements.

Behavior
- Remove duplication where risk is low.
- Preserve API boundaries and update only what is needed.
- Return concise refactor completion notes:
  - Scope changed and why.
  - Concrete risks introduced.
  - Verification checks and outcomes.
EOF
            ;;
        lint)
            cat > "$file" <<'EOF'
# Ralphie Lint Phase Prompt
You are the quality gate agent.

Goal
- Evaluate consistency, style, and likely failure modes in recent changes.
- Suggest precise fixes before build/test progression.

Behavior
- Focus on deterministic checks and policy consistency.
- Return concise lint completion notes:
  - Key quality risks/observed issues.
  - Checks run and their outcomes.
  - Whether code is safe to progress based on observed signal.
EOF
            ;;
        document)
            cat > "$file" <<'EOF'
# Ralphie Document Phase Prompt
You are the documentation agent.

Goal
- Update or add project-facing documentation describing current behavior and rationale.
- Ensure `.md` outputs are reproducible and free of local context.
- Self-direct from repository context. Do not ask the operator what to
  document during the phase.
- Inspect the implementation plan, recent git diff/history, backlog sources,
  and the closest README/AGENTS/docs files before deciding what to update.

Behavior
- Emphasize assumptions, ownership, and runbook changes.
- If documentation is stale or incomplete, update the smallest appropriate
  docs artifact.
- If documentation is already current, produce a concise markdown note in an
  existing completion/research/handoff artifact, or update the phase log,
  explaining which docs were checked and why no user-facing doc change is
  needed.
- Do not include local operator identity, private paths, secrets, command
  transcripts, or machine-only evidence in public docs.
- Return concise documentation completion notes:
  - Files updated and the rationale.
  - Docs inspected when no file update was needed.
  - Open questions or risks introduced.
  - Whether docs are clear enough to proceed.
EOF
            ;;
        *)
            touch "$file"
            ;;
    esac
    info "Wrote fallback prompt file: $(path_for_display "$file")"
}

ensure_core_artifacts() {
    local artifact
    validate_owned_runtime_paths || return 1
    for artifact in "$SPECS_DIR/project_contracts.md" "$RESEARCH_DIR/CODEBASE_MAP.md" \
        "$RESEARCH_DIR/DEPENDENCY_RESEARCH.md" "$RESEARCH_DIR/COVERAGE_MATRIX.md"; do
        ensure_runtime_file "$artifact" || return 1
    done
    for artifact in "$SPECS_DIR" "$RESEARCH_DIR" "$LOG_DIR" "$COMPLETION_LOG_DIR" "$CONSENSUS_DIR" "$READY_ARCHIVE_DIR" "$SPECIFY_DIR"; do
        ensure_runtime_directory "$artifact" || return 1
    done

    ensure_constitution_bootstrap

    [ -f "$PLAN_FILE" ] || cat > "$PLAN_FILE" <<'EOF'
# Implementation Plan
ralphie_fallback_placeholder: true

## Goal
- Produce a project-specific, executable, measurable development plan.

## Research Discovery
- Inspect repository structure, entrypoints, tests, configuration, and runtime stack.
- Map the current user workflow, execution boundaries, and operational constraints.

## Stack
- Determine the canonical workflow/runtime from repository evidence.
- Record alternatives and uncertainty where stack ownership is ambiguous.

## Acceptance Criteria
- `research/RESEARCH_SUMMARY.md` includes a `<confidence>` score and current posture.
- Research artifacts describe codebase shape, dependencies, coverage, and stack signals.
- This placeholder marker is removed by the PLAN phase after a real project-specific plan is written.

## Readiness
- Plan artifacts and build prerequisites remain stable between phase transitions.
- Required artifacts are present and reviewed before build/test gates.

## Risk
- Generic fallback planning can misdirect implementation if not replaced with repository-specific evidence.
- Missing handoff consistency checks may allow phase gates to pass without actionable evidence.

## Actionable Tasks
1. Inspect repository structure and stack dependencies.
2. Generate or update research artifacts (`research/*`).
3. Replace this fallback with a concrete, project-specific implementation plan.
4. Define validation commands and done criteria for the next build/test pass.
EOF

    [ -f "$RESEARCH_SUMMARY_FILE" ] || cat > "$RESEARCH_SUMMARY_FILE" <<'EOF'
# Research Summary

<confidence>0</confidence>
## Current Posture
- Baseline confidence is provisional for a fresh or existing project.
EOF

    [ -f "$RESEARCH_DIR/CODEBASE_MAP.md" ] || cat > "$RESEARCH_DIR/CODEBASE_MAP.md" <<'EOF'
# Codebase Map

## Directory Map
- `.`: Repository root and orchestration script entrypoint
- `./.specify/memory`: governance and constitution context
- `./research`: discovery artifacts and risk signal evidence
- `./specs`: implementation and contract specifications
- `./consensus`: review and arbitration outputs

## Entrypoints
- `ralphie.sh` (root orchestrator entrypoint)
- Additional entrypoints discovered during plan/build phases

## Modules
- orchestration and governance modules mapped during plan execution
- contract and validation surfaces defined in `specs/*.md`

## Architecture
- Module boundaries and ownership are inferred from file structure and explicit contracts.
EOF
    [ -f "$RESEARCH_DIR/DEPENDENCY_RESEARCH.md" ] || cat > "$RESEARCH_DIR/DEPENDENCY_RESEARCH.md" <<'EOF'
# Dependency Research

## Primary Stack Candidates
- Unknown (preliminary until discovery completes)

## Alternatives
- Python (expected orchestration stack)
- Node.js (possible frontend or operational tooling)
- Go (candidate for future performance-sensitive components)

## Risk Register
- Dependency lockfile completeness and version pinning
- Drift between local and committed manifests
- Entrypoint ambiguity across orchestration and scripts

## Dependency Evidence Notes
- Update this file during plan execution with deterministic signal mapping.
- Include rationale and tradeoffs before build gate progression.
EOF
    [ -f "$RESEARCH_DIR/COVERAGE_MATRIX.md" ] || cat > "$RESEARCH_DIR/COVERAGE_MATRIX.md" <<'EOF'
# Coverage Matrix

## Coverage Checklist
- Research coverage for stack and architecture evidence is planned.
- Spec coverage for acceptance criteria is pending.
- Plan readiness gate is tracked by consensus review and transition checks.
EOF
    [ -f "$STACK_SNAPSHOT_FILE" ] || cat > "$STACK_SNAPSHOT_FILE" <<'EOF'
# Stack Snapshot

- generated_at: PLACEHOLDER
- primary_stack: unknown
- primary_score: 0/100
- confidence: unknown

## Project Stack Ranking
| rank | stack | score | evidence |
| --- | --- | --- | --- |
| 1 | Unknown | 0 | no deterministic signals |

## Deterministic Alternatives Ranking
- No deterministic signal snapshot available yet.
EOF

    [ -f "$SPECS_DIR/project_contracts.md" ] || cat > "$SPECS_DIR/project_contracts.md" <<'EOF'
# Project Contracts

## Purpose
- Define the required behavior surface for implementation and validation.

## Acceptance Criteria
- Research artifacts include `RESEARCH_SUMMARY`, `CODEBASE_MAP`, `DEPENDENCY_RESEARCH`, `COVERAGE_MATRIX`, and `STACK_SNAPSHOT`.
- Implementation plan includes semantic actionability and measurable outcomes.

## Quality Gates
- Build gate requires explicit build checks and consensus pass.
- No blocking build prerequisites remain before phase transition.
EOF

}

setup_phase_prompts() {
    ensure_prompt_file "plan" "$PROMPT_PLAN_FILE"
    ensure_prompt_file "build" "$PROMPT_BUILD_FILE"
    ensure_prompt_file "test" "$PROMPT_TEST_FILE"
    ensure_prompt_file "refactor" "$PROMPT_REFACTOR_FILE"
    ensure_prompt_file "lint" "$PROMPT_LINT_FILE"
    ensure_prompt_file "document" "$PROMPT_DOCUMENT_FILE"
}

consensus_prompt_for_stage() {
    local stage="${1%-gate}"
    local loop_context="${2:-}"
    local evidence_context="${3:-}"
    local reviewer_persona="${4:-}"
    local next_phase_choices="plan|build|test|refactor|lint|document|done"
    if [ -n "$loop_context" ] && [ "$loop_context" != "no transitions yet" ]; then
        echo "Recent phase path context:"
        echo "$loop_context"
        echo ""
    fi
    if [ -n "$reviewer_persona" ]; then
        echo "Reviewer Persona: $reviewer_persona"
        echo ""
    fi
    if [ -n "$evidence_context" ]; then
        echo "Evidence context from this attempt:"
        echo "$evidence_context"
        echo ""
    fi
    echo "Use this transition history to decide whether to continue, backtrack, or stop."
    echo "Ground your verdict in the supplied artifacts and snippets; only claim missing evidence when those artifacts are unavailable or contradictory."
    echo ""
    case "$stage" in
        plan)
            cat <<EOF
Review the latest PLAN artifacts and agent output from this cycle.
Focus on whether the phase intent is complete, traceable, and safe.
Do not fail on markdown template exactness; judge based on substantive completion.
- Emit <score>(0-100)</score> and <verdict>(GO|HOLD)</verdict>.
- Emit <next_phase>${next_phase_choices}</next_phase>.
- Emit <next_phase_reason>one-sentence rationale for the phase transition.</next_phase_reason>.
- Include unresolved blockers in <gaps> as a concise comma-separated list.
EOF
            ;;
        build)
            cat <<EOF
Evaluate implementation completion and traceability to the plan.
Verify changed behavior and validation intent are coherent.
Do not require strict evidence-tag formatting; use semantic judgment with the phase outputs.
- Emit <score>(0-100)</score> and <verdict>(GO|HOLD)</verdict>.
- Emit <next_phase>${next_phase_choices}</next_phase>.
- Emit <next_phase_reason>one-sentence rationale for the phase transition.</next_phase_reason>.
- Include unresolved blockers in <gaps> as a concise comma-separated list.
EOF
            ;;
        test)
            cat <<EOF
Review test output quality and whether verification intent appears complete.
Treat concrete behavior changes and rationale as higher priority than exact markers.
- Emit <score>(0-100)</score> and <verdict>(GO|HOLD)</verdict>.
- Emit <next_phase>${next_phase_choices}</next_phase>.
- Emit <next_phase_reason>one-sentence rationale for the phase transition.</next_phase_reason>.
- Include unresolved blockers in <gaps> as a concise comma-separated list.
EOF
            ;;
        refactor)
            cat <<EOF
Review refactor output for risk, stability, and meaningful code improvements.
Prioritize actual refactor effect and safety over strict markdown structure.
Do not require strict evidence-tag formatting; use semantic judgment with the phase outputs.
- Emit <score>(0-100)</score> and <verdict>(GO|HOLD)</verdict>.
- Emit <next_phase>${next_phase_choices}</next_phase>.
- Emit <next_phase_reason>one-sentence rationale for the phase transition.</next_phase_reason>.
- Include unresolved blockers in <gaps> as a concise comma-separated list.
EOF
            ;;
        lint)
            cat <<EOF
Validate linting and quality review completeness from available evidence.
Judge whether issues and outcomes are meaningful, not whether they follow exact tag patterns.
- Emit <score>(0-100)</score> and <verdict>(GO|HOLD)</verdict>.
- Emit <next_phase>${next_phase_choices}</next_phase>.
- Emit <next_phase_reason>one-sentence rationale for the phase transition.</next_phase_reason>.
- Include unresolved blockers in <gaps> as a concise comma-separated list.
EOF
            ;;
        document)
            cat <<EOF
Validate documentation updates and decision clarity for this phase.
Prioritize correctness, completeness, and intent over exact template markers.
- Emit <score>(0-100)</score> and <verdict>(GO|HOLD)</verdict>.
- Emit <next_phase>${next_phase_choices}</next_phase>.
- Emit <next_phase_reason>one-sentence rationale for the phase transition.</next_phase_reason>.
- Include unresolved blockers in <gaps> as a concise comma-separated list.
EOF
            ;;
        *)
            cat <<EOF
Run independent quality review.
Emit <score>(0-100)</score> and <verdict>(GO|HOLD)</verdict>.
Emit <next_phase>${next_phase_choices}</next_phase> and <next_phase_reason>.
Include unresolved blockers in <gaps> as a concise comma-separated list.
EOF
            ;;
    esac
}

prompt_file_for_mode() {
    case "$1" in
        build) echo "$PROMPT_BUILD_FILE" ;;
        plan|prepare) echo "$PROMPT_PLAN_FILE" ;;
        test) echo "$PROMPT_TEST_FILE" ;;
        refactor) echo "$PROMPT_REFACTOR_FILE" ;;
        lint) echo "$PROMPT_LINT_FILE" ;;
        document) echo "$PROMPT_DOCUMENT_FILE" ;;
        *) echo "" ;;
    esac
}

build_phase_prompt_with_feedback() {
    local phase="$1"
    local base_prompt="$2"
    local target_prompt="$3"
    ensure_runtime_file "$target_prompt" || return 1
    ensure_runtime_directory "$(dirname "$target_prompt")" || return 1
    local attempt="$4"
    shift 4
    local -a failures=("$@")

    cp "$base_prompt" "$target_prompt"
    {
        echo ""
        echo "---"
        echo "## Retry Guidance (Attempt $attempt)"
        echo "- This phase did not pass machine checks on prior attempt."
        if [ "${#failures[@]}" -eq 0 ]; then
            echo "- Re-attempt with higher care for phase artifacts and explicit completeness."
        else
            echo "- Address all blockers before re-running:"
            for blocker in "${failures[@]}"; do
                [ -n "$blocker" ] || continue
                echo "- $blocker"
            done
            if [ "$phase" = "plan" ] && printf '%s\n' "${failures[@]}" | grep -qi "plan is not semantically actionable"; then
                echo "- Plan gate contract: include an explicit Goal section, Acceptance Criteria/Validation, and either actionable checklist tasks ('- [ ]') or a clear no-local-work / handoff-ready conclusion."
            fi
        fi
        echo "- Preserve existing work; only generate missing/repairable artifacts and rerun this phase."
        echo "- Provide a concise completion recap with changed artifacts and residual risks."
    } >> "$target_prompt"
}

collect_phase_retry_failures_from_consensus() {
    local -a failures=()
    [ -n "$LAST_CONSENSUS_DIR" ] || { print_array_lines "${failures[@]+"${failures[@]}"}"; return 0; }
    local reviewer_summary ofile
    for ofile in "$LAST_CONSENSUS_DIR"/*.out; do
        [ -f "$ofile" ] || continue
        local score verdict next_phase next_phase_reason
        score="$(extract_review_score "$ofile")"
        verdict="$(extract_review_verdict "$ofile")"
        next_phase="$(extract_xml_value "$ofile" "next_phase" "unknown")"
        next_phase_reason="$(extract_xml_value "$ofile" "next_phase_reason" "")"
        next_phase_reason="$(sanitize_text_for_log "$next_phase_reason")"
        [ -n "$next_phase_reason" ] || next_phase_reason="no explicit phase-routing rationale"
        local gaps
        gaps="$(extract_review_gaps "$ofile" 140)"
        reviewer_summary="$(basename "$ofile"): score=$score verdict=${verdict:-HOLD} next=$next_phase reason=$next_phase_reason gaps=$gaps"
        failures+=("consensus review: $reviewer_summary")
    done
    print_array_lines "${failures[@]+"${failures[@]}"}"
}

ensure_constitution_bootstrap() {
    if [ -f "$CONSTITUTION_FILE" ]; then
        return 0
    fi

    ensure_runtime_file "$CONSTITUTION_FILE" || return 1
    ensure_runtime_directory "$SPECIFY_DIR" || return 1
    cat > "$CONSTITUTION_FILE" <<'EOF'
# Ralphie Constitution

## Purpose
- Establish deterministic, portable, and reproducible control planes for autonomous execution.
- Define behavior for all phases from planning through documentation.

## Governance
- Keep artifacts machine-readable: avoid local absolute paths, avoid command transcript leakage, and keep logs deterministic.
- Validate phase completion through reviewer-intelligence consensus and execution/build gates; keep semantic checks close to code and outputs.
- Treat gate failures as actionable signals, not terminal failure if bounded retries remain.

## Phase Contracts
- **Plan** produces research artifacts, an explicit implementation plan, and a deterministic stack snapshot.
- **Build** executes plan tasks against evidence in IMPLEMENTATION_PLAN.md.
- **Test** verifies behavior changes and documents validation rationale.
- **Refactor** preserves behavior, reduces complexity, and documents rationale.
- **Lint** enforces deterministic quality and cleanup policies.
- **Document** closes the lifecycle with updated user-facing documentation.

## Recovery and Retry Policy
- Every phase attempt that fails consensus or transition checks is retried within
  `PHASE_COMPLETION_MAX_ATTEMPTS` using feedback from prior blockers.
- Hard stop occurs only after bounded retries are exhausted and gate feedback is persisted.

## Evidence Requirements
- Phase completion is judged by reviewer-intelligence consensus plus execution/build-time gates.
- Plan/research artifacts are reviewed for substantive quality but not by rigid template matching.

## Environment Scope
- Repository-relative paths and relative markdown links are preferred.
- External references are allowed only when version/risk tradeoffs are explicitly documented.
EOF
}

plan_prompt_for_iteration() { echo "$1"; }
run_idle_plan_refresh() { return 0; }
runtime_guard_prepare() {
    [ -n "${RUNTIME_GUARD_DIR:-}" ] && return 0
    RUNTIME_GUARD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ralphie-inputs.XXXXXX")" || return 1
    chmod 700 "$RUNTIME_GUARD_DIR" || return 1
    : > "$RUNTIME_GUARD_DIR/tampered"
}

prepare_mission_seed() {
    local resuming="${1:-false}"
    local objective source_spec requested_hash project_type consent
    local candidate="$RUNTIME_GUARD_DIR/seed-goals"
    local objective_candidate="$RUNTIME_GUARD_DIR/seed-objective"
    if [ -z "${OBJECTIVE_TEXT:-}" ] && [ -z "${SPEC_FILE:-}" ]; then
        if [ -n "${MISSION_SEED_SHA:-}" ]; then
            NO_TERMINAL_INPUT=true
            ensure_runtime_file "$MISSION_OBJECTIVE_FILE" || return 1
            ensure_runtime_file "$PROJECT_GOALS_FILE" || return 1
            [ -f "$MISSION_OBJECTIVE_FILE" ] && [ -f "$PROJECT_GOALS_FILE" ] || {
                err "Saved mission seed is missing; restore it or use --no-resume with an explicit seed."
                return 1
            }
            requested_hash="$( { cat "$MISSION_OBJECTIVE_FILE"; printf '\0'; cat "$PROJECT_GOALS_FILE"; } | sha256_stream_sum)" || return 1
            [ "$requested_hash" = "$MISSION_SEED_SHA" ] || {
                err "Saved objective/spec changed; use --no-resume with the intended seed."
                return 1
            }
        fi
        return 0
    fi
    NO_TERMINAL_INPUT=true
    objective="${OBJECTIVE_TEXT:-Complete the project described in the supplied specification.}"
    printf '%s' "$objective" > "$objective_candidate" || return 1
    if [ -n "${SPEC_FILE:-}" ]; then
        source_spec="$SPEC_FILE"
        case "$source_spec" in /*) ;; *) source_spec="$INVOCATION_DIR/$source_spec";; esac
        [ -f "$source_spec" ] && [ -r "$source_spec" ] && [ -s "$source_spec" ] || {
            err "--spec requires a readable, nonempty regular file: $SPEC_FILE"
            return 1
        }
        cp "$source_spec" "$candidate" || return 1
    else
        printf '%s' "$OBJECTIVE_TEXT" > "$candidate" || return 1
    fi
    grep -q '[^[:space:]]' "$candidate" || { err "The mission seed must contain text."; return 1; }
    requested_hash="$( { cat "$objective_candidate"; printf '\0'; cat "$candidate"; } | sha256_stream_sum)" || return 1
    if is_true "$resuming" && [ "$requested_hash" != "${MISSION_SEED_SHA:-}" ]; then
        err "The objective/spec differs from the saved mission. Use --no-resume to start the replacement mission."
        return 1
    fi
    ensure_runtime_file "$MISSION_OBJECTIVE_FILE" || return 1
    ensure_runtime_file "$PROJECT_GOALS_FILE" || return 1
    ensure_runtime_file "$PROJECT_BOOTSTRAP_FILE" || return 1
    cp "$objective_candidate" "$MISSION_OBJECTIVE_FILE" || return 1
    cp "$candidate" "$PROJECT_GOALS_FILE" || return 1
    project_type="existing"
    if [ -z "$(git -C "$PROJECT_DIR" ls-files 2>/dev/null)" ] && [ ! -f "$PROJECT_DIR/package.json" ] && [ ! -d "$PROJECT_DIR/src" ]; then
        project_type="new"
    fi
    consent=true
    is_true "${PLAN_ONLY:-false}" && consent=false
    write_bootstrap_context_file "$project_type" "$(sanitize_text_for_log "$objective")" "$consent" true \
        'Preserve operator work and project instructions; make only changes required by the supplied objective.' \
        'The supplied objective is complete and shell-owned project checks pass.' true '' \
        'Follow the existing project; choose the simplest suitable structure for a new project.' \
        'Follow existing project tooling; research and justify choices needed for a new project.' || return 1
    MISSION_SEED_SHA="$requested_hash"
    REBOOTSTRAP_REQUESTED=false
    info "Loaded explicit mission seed; autonomous lifecycle is $(is_true "$consent" && printf authorized || printf planning-only)."
    return 0
}

snapshot_operator_inputs() {
    local path name
    for path in "$PROJECT_BOOTSTRAP_FILE" "$PROJECT_GOALS_FILE" "$MISSION_OBJECTIVE_FILE" "$OWNED_PATHS_FILE" "$SHELL_VERIFICATION_LOG" "$CONFIG_DIR/no-local-work.manifest" "$CONFIG_DIR/no-local-work.binding"; do
        name="${path##*/}"
        ensure_runtime_file "$path" || return 1
        if [ -f "$path" ]; then
            cp "$path" "$RUNTIME_GUARD_DIR/$name" || return 1
        else
            : > "$RUNTIME_GUARD_DIR/$name.absent"
        fi
    done
    return 0
}

restore_operator_input() {
    local path="$1" snapshot="$2"
    validate_runtime_directory "$CONFIG_DIR" || return 1
    validate_runtime_directory "$(dirname "$path")" || return 1
    if [ -L "$path" ] || { [ -e "$path" ] && [ ! -f "$path" ]; }; then
        # Preserve unexpected replacement objects instead of following a symlink
        # or deleting a directory supplied by the worker.
        mv "$path" "$CONFIG_DIR/rejected-${path##*/}.$$.${RANDOM:-0}" || return 1
    fi
    cp "$snapshot" "$path" || return 1
    chmod u+rw "$path" || return 1
}

guard_operator_inputs() {
    [ -n "${RUNTIME_GUARD_DIR:-}" ] || return 0
    validate_runtime_directory "$CONFIG_DIR" || return 1
    local path name snapshot changed=false
    for path in "$PROJECT_BOOTSTRAP_FILE" "$PROJECT_GOALS_FILE" "$MISSION_OBJECTIVE_FILE" "$SHELL_GATES_FILE" "$OWNED_PATHS_FILE" "$SHELL_VERIFICATION_LOG" "$CONFIG_DIR/no-local-work.manifest" "$CONFIG_DIR/no-local-work.binding"; do
        name="${path##*/}"
        snapshot="$RUNTIME_GUARD_DIR/$name"
        if [ -f "$snapshot" ]; then
            if [ -L "$path" ] || [ ! -f "$path" ] || ! cmp -s "$snapshot" "$path"; then
                printf '%s\n' "$name" >> "$RUNTIME_GUARD_DIR/tampered"
                restore_operator_input "$path" "$snapshot" || return 1
                changed=true
            fi
        elif [ -f "$snapshot.absent" ] && { [ -e "$path" ] || [ -L "$path" ]; }; then
            printf '%s\n' "$name" >> "$RUNTIME_GUARD_DIR/tampered"
            mv "$path" "$CONFIG_DIR/rejected-$name.$$.${RANDOM:-0}" || return 1
            changed=true
        fi
    done
    if is_true "$changed"; then
        err "Operator objective, consent or gate definitions changed during an engine call; restored and rejected."
        return 1
    fi
    [ ! -s "$RUNTIME_GUARD_DIR/tampered" ]
}

shell_gate_commands() {
    [ -f "$SHELL_GATES_FILE" ] || return 0
    sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$SHELL_GATES_FILE"
}

discover_shell_gates() {
    # Fixed project-tool contracts, never shell commands proposed by a model.
    # Tools are project dependencies, not dependencies of Ralphie's loop.
    if [ -f "$PROJECT_DIR/test.sh" ] && [ ! -L "$PROJECT_DIR/test.sh" ]; then
        printf '%s\n' 'bash ./test.sh'
    elif [ -f "$PROJECT_DIR/package.json" ] && command -v node >/dev/null 2>&1; then
        local pm=npm script
        [ ! -f "$PROJECT_DIR/pnpm-lock.yaml" ] || pm=pnpm
        [ ! -f "$PROJECT_DIR/yarn.lock" ] || pm=yarn
        for script in test check typecheck lint; do
            if node -e 'const p=require(process.argv[1]); const s=p.scripts&&p.scripts[process.argv[2]]; process.exit(typeof s === "string" && s.trim() ? 0 : 1)' "$PROJECT_DIR/package.json" "$script" >/dev/null 2>&1; then
                printf '%s run %s\n' "$pm" "$script"
            fi
        done
    elif [ -f "$PROJECT_DIR/go.mod" ]; then
        printf '%s\n' 'go test ./...'
    elif [ -f "$PROJECT_DIR/Cargo.toml" ]; then
        printf '%s\n' 'cargo test --workspace'
    elif [ -f "$PROJECT_DIR/pytest.ini" ] || [ -f "$PROJECT_DIR/pyproject.toml" ] || [ -f "$PROJECT_DIR/setup.py" ]; then
        if [ -x "$PROJECT_DIR/.venv/bin/python" ]; then
            printf '%s\n' './.venv/bin/python -m pytest -q'
        else
            printf '%s\n' 'python3 -m pytest -q'
        fi
    elif [ -f "$PROJECT_DIR/Makefile" ] && grep -qE '^test[[:space:]]*:' "$PROJECT_DIR/Makefile"; then
        printf '%s\n' 'make test'
    fi
    return 0
}

snapshot_shell_gates() {
    cp "$SHELL_GATES_FILE" "$RUNTIME_GUARD_DIR/gates" || return 1
    SHELL_GATES_FINGERPRINT="$(sha256_file_sum "$SHELL_GATES_FILE")" || return 1
}

prepare_shell_gates() {
    ensure_runtime_file "$SHELL_GATES_FILE" || return 1
    local cmd candidate="$RUNTIME_GUARD_DIR/gates-candidate" requested_fingerprint
    local saved_fingerprint="${SHELL_GATES_FINGERPRINT:-}"
    if [ -f "$SHELL_GATES_FILE" ]; then cp "$SHELL_GATES_FILE" "$candidate" || return 1; else : > "$candidate"; fi
    for cmd in "${ACCEPT_COMMANDS[@]+"${ACCEPT_COMMANDS[@]}"}"; do
        grep -qxF -- "$cmd" "$candidate" || printf '\n%s\n' "$cmd" >> "$candidate"
    done
    if [ -z "$(sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$candidate")" ]; then
        discover_shell_gates >> "$candidate" || return 1
    fi
    requested_fingerprint="$(sha256_file_sum "$candidate")" || return 1
    if is_true "${RESUME_REQUESTED:-true}" && [ -n "$saved_fingerprint" ] && [ "$saved_fingerprint" != "$requested_fingerprint" ]; then
        err "Gate definitions differ from the saved mission. Use --no-resume after reviewing the new checks."
        return 1
    fi
    cp "$candidate" "$SHELL_GATES_FILE" || return 1
    snapshot_shell_gates || return 1
    return 0
}

refresh_shell_gates() {
    [ -n "${RUNTIME_GUARD_DIR:-}" ] && [ -d "$RUNTIME_GUARD_DIR" ] || return 1
    guard_operator_inputs || return 1
    if [ -z "$(shell_gate_commands)" ]; then
        discover_shell_gates >> "$SHELL_GATES_FILE" || return 1
        snapshot_shell_gates || return 1
        save_state_or_exit "discovered verification gate checkpoint"
    fi
    return 0
}

run_shell_gates() {
    [ -n "${RUNTIME_GUARD_DIR:-}" ] && [ -d "$RUNTIME_GUARD_DIR" ] || return 1
    local phase="${1:-verification}" cmd rc n=0 output head_before head_after
    local before="$RUNTIME_GUARD_DIR/gate-before.manifest" after="$RUNTIME_GUARD_DIR/gate-after.manifest"
    local COMMAND_TIMEOUT_SECONDS="$GATE_TIMEOUT_SECONDS" gate_pid
    local PHASE_MANIFEST_MODE=deep
    local capture_limit_marker="$RUNTIME_GUARD_DIR/gate-overflow"
    SHELL_GATES_STATUS=absent
    SHELL_GATES_FAILURE='No executable project checks exist; add a real test/check command with --accept or .ralphie/gates.'
    guard_operator_inputs || { SHELL_GATES_STATUS=tampered; SHELL_GATES_FAILURE='Protected operator inputs changed during execution.'; return 1; }
    while IFS= read -r cmd || [ -n "$cmd" ]; do
        [ -n "$cmd" ] || continue
        if ! request_check_generation; then
            SHELL_GATES_STATUS=request
            SHELL_GATES_FAILURE='Human requests changed before a project check; refresh PLAN.'
            return 76
        fi
        n=$((n + 1))
        output="$RUNTIME_GUARD_DIR/gate-$n.log"
        phase_capture_worktree_manifest "$before" || return 1
        head_before="$(git -C "$PROJECT_DIR" rev-parse --verify --quiet HEAD 2>/dev/null || true)"
        rm -f "$capture_limit_marker"
        (
            cd "$PROJECT_DIR" || exit 1
            set -o pipefail
            "$BASH" -o pipefail -c "$cmd" < /dev/null 2>&1 | stream_engine_output "$output" "" false
        ) &
        gate_pid=$!
        register_managed_pid "$gate_pid"
        if wait_for_process_with_idle_output_watchdog "$gate_pid" 0 "project check" "$output"; then
            rc=0
        else
            rc=$?
        fi
        unregister_managed_pid "$gate_pid"
        rm -f "$capture_limit_marker"
        if ! guard_operator_inputs; then
            SHELL_GATES_STATUS=tampered
            SHELL_GATES_FAILURE='A project check changed protected operator inputs.'
            return 1
        fi
        ensure_runtime_file "$SHELL_VERIFICATION_LOG" || return 1
        printf '{"at":"%s","phase":"%s","command":"%s","exit":%s}\n' \
            "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(json_escape_string "$phase")" "$(json_escape_string "$cmd")" "$rc" >> "$SHELL_VERIFICATION_LOG" || return 1
        cp "$SHELL_VERIFICATION_LOG" "$RUNTIME_GUARD_DIR/verification.jsonl" || return 1
        rm -f "$RUNTIME_GUARD_DIR/verification.jsonl.absent"
        if ! request_check_generation; then
            SHELL_GATES_STATUS=request
            SHELL_GATES_FAILURE='Human requests changed during a project check; refresh PLAN.'
            return 76
        fi
        if ! guard_operator_inputs; then
            SHELL_GATES_STATUS=tampered
            SHELL_GATES_FAILURE='A project check changed protected operator inputs.'
            return 1
        fi
        phase_capture_worktree_manifest "$after" || return 1
        head_after="$(git -C "$PROJECT_DIR" rev-parse --verify --quiet HEAD 2>/dev/null || true)"
        if [ "$head_before" != "$head_after" ] || ! cmp -s "$before" "$after"; then
            SHELL_GATES_STATUS=failed
            SHELL_GATES_FAILURE="Shell check changed the nonignored project tree; verification must examine a stable tree: $cmd"
            warn "$SHELL_GATES_FAILURE"
            return 1
        fi
        if [ "$rc" -ne 0 ]; then
            SHELL_GATES_STATUS=failed
            [ "$rc" -ne 124 ] || SHELL_GATES_STATUS=timeout
            SHELL_GATES_FAILURE="Shell check failed (exit $rc): $cmd"
            warn "$SHELL_GATES_FAILURE"
            safe_print_file_tail "$output" 24
            return 1
        fi
    done < <(shell_gate_commands)
    [ "$n" -gt 0 ] || return 1
    SHELL_GATES_STATUS=pass
    SHELL_GATES_FAILURE=''
    info "Shell verification passed ($n check(s), $phase)."
    return 0
}

shell_note_local_work() {
    local before="$1" after="$2" path
    while IFS= read -r -d '' path; do
        case "$path" in
            .ralphie/*|logs/*|completion_log/*|consensus/*|research/*|specs/*|.specify/*|PROMPT_*.md|IMPLEMENTATION_PLAN.md|*.md|.gitignore) ;;
            *) SHELL_LOCAL_WORK_SEEN=true ;;
        esac
    done < <(phase_manifest_changed_paths_nul "$before" "$after")
    if [ -n "${SESSION_INITIAL_HEAD:-}" ]; then
        while IFS= read -r -d '' path; do
            case "$path" in
                .ralphie/*|logs/*|completion_log/*|consensus/*|research/*|specs/*|.specify/*|PROMPT_*.md|IMPLEMENTATION_PLAN.md|*.md|.gitignore) ;;
                *) SHELL_LOCAL_WORK_SEEN=true ;;
            esac
        done < <(git --literal-pathspecs -C "$PROJECT_DIR" diff --no-ext-diff --name-only -z "$SESSION_INITIAL_HEAD" HEAD -- . 2>/dev/null)
    elif git -C "$PROJECT_DIR" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
        # An initially unborn repository may have been committed by the engine.
        while IFS= read -r -d '' path; do
            case "$path" in
                .ralphie/*|logs/*|completion_log/*|consensus/*|research/*|specs/*|.specify/*|PROMPT_*.md|IMPLEMENTATION_PLAN.md|*.md|.gitignore) ;;
                *) SHELL_LOCAL_WORK_SEEN=true ;;
            esac
        done < <(git -C "$PROJECT_DIR" ls-files -z)
    fi
}

no_local_work_artifact_path() {
    # These are Ralphie artifact contracts, not a general Markdown/ignore rule.
    case "$1" in
        .git|.git/*|.ralphie|.ralphie/*|logs|logs/*|completion_log|completion_log/*|consensus|consensus/*|IMPLEMENTATION_PLAN.md|PROMPT_plan.md|PROMPT_build.md|PROMPT_test.md|PROMPT_refactor.md|PROMPT_lint.md|PROMPT_document.md|research/RESEARCH_SUMMARY.md|research/CODEBASE_MAP.md|research/DEPENDENCY_RESEARCH.md|research/COVERAGE_MATRIX.md|research/STACK_SNAPSHOT.md|research/SELF_IMPROVEMENT_LOG.md|research/HUMAN_FEEDBACK.md|specs/*.md|.specify/memory/constitution.md) return 0;;
    esac
    return 1
}

capture_no_local_work_tree() {
    local destination="$1" path permissions signature
    local paths="$RUNTIME_GUARD_DIR/no-local-work-paths.nul"
    local unsorted="$RUNTIME_GUARD_DIR/no-local-work-unsorted"
    : > "$unsorted" || return 1
    # Git status deliberately omits ignored files. That is useful for checks
    # producing caches, but cannot prove that no implementation was performed.
    ( cd "$PROJECT_DIR" && find . -name .git -prune -o -print0 ) > "$paths" || return 1
    while IFS= read -r -d '' path; do
        path="${path#./}"
        [ "$path" != . ] || continue
        no_local_work_artifact_path "$path" && continue
        if ! permissions="$(stat -f '%Lp' "$PROJECT_DIR/$path" 2>/dev/null)"; then
            permissions="$(stat -c '%a' "$PROJECT_DIR/$path" 2>/dev/null)" || return 1
        fi
        case "$permissions" in ''|*[!0-7]*) return 1;; esac
        if [ -L "$PROJECT_DIR/$path" ]; then
            signature="link:$permissions:$(readlink "$PROJECT_DIR/$path" | sha256_stream_sum)" || return 1
        elif [ -f "$PROJECT_DIR/$path" ]; then
            signature="file:$permissions:$(sha256_file_sum "$PROJECT_DIR/$path")" || return 1
        elif [ -d "$PROJECT_DIR/$path" ]; then
            signature="dir:$permissions"
        else
            return 1
        fi
        printf '%s\th:%s\n' "$signature" "$(path_to_hex "$path")" >> "$unsorted" || return 1
    done < "$paths"
    LC_ALL=C sort "$unsorted" > "$destination"
}

no_local_work_mission_binding() {
    {
        printf 'raw-tree-v1\0project=%s\0seed=%s\0' "$PROJECT_DIR" "${MISSION_SEED_SHA:-}"
        if [ -z "${MISSION_SEED_SHA:-}" ]; then
            # Legacy missions have no explicit seed digest. Bind their captured
            # intent, rather than treating every unseeded mission as identical.
            [ ! -f "$PROJECT_BOOTSTRAP_FILE" ] || cat "$PROJECT_BOOTSTRAP_FILE"
            printf '\0'
            [ ! -f "$PROJECT_GOALS_FILE" ] || cat "$PROJECT_GOALS_FILE"
        fi
    } | sha256_stream_sum
}

prepare_no_local_work_witness() {
    local resuming="${1:-false}" mission manifest_hash
    local manifest="$CONFIG_DIR/no-local-work.manifest" binding="$CONFIG_DIR/no-local-work.binding"
    local candidate="$RUNTIME_GUARD_DIR/no-local-work-current" expected="$RUNTIME_GUARD_DIR/no-local-work-expected"
    SHELL_NO_LOCAL_WORK_WITNESS_READY=false
    ensure_runtime_file "$manifest" && ensure_runtime_file "$binding" || return 1
    mission="$(no_local_work_mission_binding)" || return 1
    if is_true "$resuming" || { is_true "${RESUME_REQUESTED:-true}" && { [ -e "$manifest" ] || [ -e "$binding" ]; }; }; then
        if [ ! -f "$manifest" ] || [ ! -f "$binding" ]; then
            warn 'Original no-local-work proof is missing; completing without project checks is disabled.'
            return 0
        fi
        manifest_hash="$(sha256_file_sum "$manifest")" || return 1
        printf 'mission=%s\nmanifest=%s\n' "$mission" "$manifest_hash" > "$expected" || return 1
        if ! cmp -s "$expected" "$binding"; then
            warn 'Original no-local-work proof does not match this mission; completing without project checks is disabled.'
            return 0
        fi
    else
        if ! capture_no_local_work_tree "$candidate"; then
            warn 'Could not capture an independent project tree; completing without project checks is disabled.'
            return 0
        fi
        manifest_hash="$(sha256_file_sum "$candidate")" || return 1
        printf 'mission=%s\nmanifest=%s\n' "$mission" "$manifest_hash" > "$expected" || return 1
        cp "$candidate" "$manifest" && cp "$expected" "$binding" || return 1
    fi
    cp "$manifest" "$RUNTIME_GUARD_DIR/no-local-work.manifest" || return 1
    SHELL_NO_LOCAL_WORK_WITNESS_READY=true
    return 0
}

shell_no_local_work_proven() {
    [ -n "${RUNTIME_GUARD_DIR:-}" ] || return 1
    is_true "${SHELL_DEVELOPMENT_PHASE_STARTED:-false}" && return 1
    is_true "${SHELL_LOCAL_WORK_SEEN:-false}" && return 1
    project_terminal_or_handoff_ready || return 1
    is_true "${SHELL_NO_LOCAL_WORK_WITNESS_READY:-false}" || return 1
    guard_operator_inputs || return 1
    local current="$RUNTIME_GUARD_DIR/handoff-project.manifest"
    [ -f "$RUNTIME_GUARD_DIR/no-local-work.manifest" ] || return 1
    capture_no_local_work_tree "$current" || return 1
    cmp -s "$RUNTIME_GUARD_DIR/no-local-work.manifest" "$current"
}

session_work_is_saved() {
    is_true "${AUTO_COMMIT_SESSION_ENABLED:-false}" || return 0
    local path paths="$RUNTIME_GUARD_DIR/final-dirty.nul"
    collect_git_dirty_paths > "$paths" || return 1
    while IFS= read -r -d '' path; do
        case "$path" in .ralphie|.ralphie/*|.git|.git/*) continue;; esac
        if [ -n "${AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE:-}" ] && nul_file_contains "$AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE" "$path"; then
            continue
        fi
        SHELL_GATES_STATUS=failed
        SHELL_GATES_FAILURE="Verified project work is still unsaved: $(printf '%q' "$path")"
        return 1
    done < "$paths"
    return 0
}

shell_terminal_verified() {
    refresh_shell_gates || return 1
    if [ -z "$(shell_gate_commands)" ] && shell_no_local_work_proven; then
        session_work_is_saved || return 1
        info "No local implementation was performed; completing the reviewed planning/document handoff without claiming tested software."
        return 0
    fi
    run_shell_gates final || return 1
    session_work_is_saved
}

print_session_config_banner() {
    info "=== Ralphie Session Budget & Retry Configuration ==="
    info "script_version: ${SCRIPT_VERSION}"
    info "auto_update: ${AUTO_UPDATE:-$DEFAULT_AUTO_UPDATE} (pre-run single-file update)"
    info "auto_update_url: $(redact_endpoint_for_log "$AUTO_UPDATE_URL")"
    info "auto_update_allow_dirty: ${AUTO_UPDATE_ALLOW_DIRTY:-$DEFAULT_AUTO_UPDATE_ALLOW_DIRTY}"
    info "auto_update_allow_insecure: ${AUTO_UPDATE_ALLOW_INSECURE:-$DEFAULT_AUTO_UPDATE_ALLOW_INSECURE}"
    info "auto_update_timeout_seconds: ${AUTO_UPDATE_TIMEOUT_SECONDS:-$DEFAULT_AUTO_UPDATE_TIMEOUT_SECONDS}"
    info "auto_update_lock_timeout_seconds: ${AUTO_UPDATE_LOCK_TIMEOUT_SECONDS:-$DEFAULT_AUTO_UPDATE_LOCK_TIMEOUT_SECONDS}"
    info "max_session_cycles: ${MAX_SESSION_CYCLES:-0} (0=unlimited)"
    info "session_token_budget: ${SESSION_TOKEN_BUDGET:-0} (0=unlimited)"
    info "session_token_rate_cents_per_million: ${SESSION_TOKEN_RATE_CENTS_PER_MILLION:-0}"
    info "session_cost_budget_cents: ${SESSION_COST_BUDGET_CENTS:-0} (0=unlimited)"
    info "session token/cost accounting is heuristic (byte-based estimation, not invoice-accurate)"
    info "phase_completion_max_attempts: $(phase_attempt_limit_display "${PHASE_COMPLETION_MAX_ATTEMPTS:-0}")"
    info "phase_completion_retry_delay_seconds: ${PHASE_COMPLETION_RETRY_DELAY_SECONDS:-0}"
    info "phase_completion_retry_verbose: ${PHASE_COMPLETION_RETRY_VERBOSE:-false}"
    info "run_agent_max_attempts: ${RUN_AGENT_MAX_ATTEMPTS:-0}"
    info "run_agent_retry_delay_seconds: ${RUN_AGENT_RETRY_DELAY_SECONDS:-0}"
    info "run_agent_retry_verbose: ${RUN_AGENT_RETRY_VERBOSE:-false}"
    info "engine_idle_output_timeout_seconds: $(phase_attempt_limit_display "${ENGINE_IDLE_OUTPUT_TIMEOUT_SECONDS:-0}")"
    info "engine_health_max_attempts: ${ENGINE_HEALTH_MAX_ATTEMPTS:-$DEFAULT_ENGINE_HEALTH_MAX_ATTEMPTS}"
    info "engine_health_retry_delay_seconds: ${ENGINE_HEALTH_RETRY_DELAY_SECONDS:-$DEFAULT_ENGINE_HEALTH_RETRY_DELAY_SECONDS}"
    info "engine_smoke_test_timeout: ${ENGINE_SMOKE_TEST_TIMEOUT:-$DEFAULT_ENGINE_SMOKE_TEST_TIMEOUT}"
    info "auto_init_git_if_missing: ${AUTO_INIT_GIT_IF_MISSING:-false}"
    info "auto_commit_on_phase_pass: ${AUTO_COMMIT_ON_PHASE_PASS:-false}"
    info "auto_engine_preference: ${AUTO_ENGINE_PREFERENCE:-$DEFAULT_AUTO_ENGINE_PREFERENCE}"
    info "codex_endpoint: $(redact_endpoint_for_log "$CODEX_ENDPOINT")"
    info "prime_provider: ${PRIME_PROVIDER:-<default>}"
    info "prime_model: ${PRIME_MODEL:-<default>}"
    info "prime_thinking_override: ${PRIME_THINKING_OVERRIDE:-<default>}"
    info "engine_output_max_bytes: ${ENGINE_OUTPUT_MAX_BYTES:-$DEFAULT_ENGINE_OUTPUT_MAX_BYTES}"
    info "codex_model: ${CODEX_MODEL:-<default>}"
    info "codex_use_responses_schema: ${CODEX_USE_RESPONSES_SCHEMA:-false}"
    info "codex_responses_schema_file: ${CODEX_RESPONSES_SCHEMA_FILE:-<unset>}"
    info "codex_thinking_override: ${CODEX_THINKING_OVERRIDE:-<unset>}"
    info "claude_endpoint: $(redact_endpoint_for_log "$CLAUDE_ENDPOINT")"
    info "claude_model: ${CLAUDE_MODEL:-<default>}"
    info "claude_thinking_override: ${CLAUDE_THINKING_OVERRIDE:-<unset>}"
    info "engine_selection_requested: ${ENGINE_SELECTION_REQUESTED:-$DEFAULT_ENGINE}"
    info "active_engine_bootstrap: ${ACTIVE_ENGINE:-unknown} (${ACTIVE_CMD:-unset})"
    info "engine_overrides_bootstrapped: ${ENGINE_OVERRIDES_BOOTSTRAPPED:-$DEFAULT_ENGINE_OVERRIDES_BOOTSTRAPPED}"
    info "notifications_enabled: ${NOTIFICATIONS_ENABLED:-$DEFAULT_NOTIFICATIONS_ENABLED}"
    info "notification_channels: $(notification_channels_for_display)"
    info "notification_wizard_bootstrapped: ${NOTIFICATION_WIZARD_BOOTSTRAPPED:-$DEFAULT_NOTIFICATION_WIZARD_BOOTSTRAPPED}"
    info "telegram_bot_token: $(redact_secret_for_log "$TG_BOT_TOKEN")"
    info "telegram_chat_id: $(redact_secret_for_log "$TG_CHAT_ID")"
    info "discord_webhook: $(redact_endpoint_for_log "$NOTIFY_DISCORD_WEBHOOK_URL")"
    info "tts_enabled: ${NOTIFY_TTS_ENABLED:-$DEFAULT_NOTIFY_TTS_ENABLED}"
    info "tts_style: ${NOTIFY_TTS_STYLE:-$DEFAULT_NOTIFY_TTS_STYLE}"
    info "notify_event_dedup_window_seconds: ${NOTIFY_EVENT_DEDUP_WINDOW_SECONDS:-$DEFAULT_NOTIFY_EVENT_DEDUP_WINDOW_SECONDS}"
    info "notify_incident_reminder_minutes: ${NOTIFY_INCIDENT_REMINDER_MINUTES:-$DEFAULT_NOTIFY_INCIDENT_REMINDER_MINUTES}"
    info "chutes_api_key: $(redact_secret_for_log "$CHUTES_API_KEY")"
    info "chutes_tts_url: $(redact_endpoint_for_log "$NOTIFY_CHUTES_TTS_URL")"
    info "chutes_voice: ${NOTIFY_CHUTES_VOICE:-$DEFAULT_NOTIFY_CHUTES_VOICE}"
    info "chutes_speed: ${NOTIFY_CHUTES_SPEED:-$DEFAULT_NOTIFY_CHUTES_SPEED}"
    info "startup_operational_probe: ${STARTUP_OPERATIONAL_PROBE:-$DEFAULT_STARTUP_OPERATIONAL_PROBE}"
    info "engine_output_to_stdout: ${ENGINE_OUTPUT_TO_STDOUT:-true}"
    info "max_consensus_routing_attempts: ${MAX_CONSENSUS_ROUTING_ATTEMPTS:-0} (0=unlimited backtracking reroutes)"
    info "phase_pair_cycle_limit: ${PHASE_PAIR_CYCLE_LIMIT:-$DEFAULT_PHASE_PAIR_CYCLE_LIMIT} (0=disabled)"
    info "confidence_stagnation_limit: ${CONFIDENCE_STAGNATION_LIMIT:-$DEFAULT_CONFIDENCE_STAGNATION_LIMIT}"
    info "swarm_consensus_timeout: ${SWARM_CONSENSUS_TIMEOUT:-$DEFAULT_SWARM_CONSENSUS_TIMEOUT}"
    info "swarm_max_parallel: ${SWARM_MAX_PARALLEL:-$DEFAULT_SWARM_MAX_PARALLEL}"
    info "confidence_target: ${CONFIDENCE_TARGET:-$DEFAULT_CONFIDENCE_TARGET}"
    info "consensus_score_threshold: ${CONSENSUS_SCORE_THRESHOLD:-$DEFAULT_CONSENSUS_SCORE_THRESHOLD}"
    info "consensus_clean_go_score_floor: ${CONSENSUS_CLEAN_GO_SCORE_FLOOR:-$DEFAULT_CONSENSUS_CLEAN_GO_SCORE_FLOOR} (threshold_explicit=${CONSENSUS_SCORE_THRESHOLD_EXPLICIT:-false})"
    info "require_lint_before_done: ${REQUIRE_LINT_BEFORE_DONE:-$DEFAULT_REQUIRE_LINT_BEFORE_DONE}"
    info "require_document_before_done: ${REQUIRE_DOCUMENT_BEFORE_DONE:-$DEFAULT_REQUIRE_DOCUMENT_BEFORE_DONE}"
    info "require_plan_backlog_clear_before_done: ${REQUIRE_PLAN_BACKLOG_CLEAR_BEFORE_DONE:-$DEFAULT_REQUIRE_PLAN_BACKLOG_CLEAR_BEFORE_DONE}"
    info "require_plan_freshness_for_build: ${REQUIRE_PLAN_FRESHNESS_FOR_BUILD:-$DEFAULT_REQUIRE_PLAN_FRESHNESS_FOR_BUILD}"
    info "backlog_sources: ${BACKLOG_SOURCES:-$DEFAULT_BACKLOG_SOURCES}"
    info "phase_noop_profile: ${PHASE_NOOP_PROFILE:-$DEFAULT_PHASE_NOOP_PROFILE}"
    info "strict_validation_noop: ${STRICT_VALIDATION_NOOP:-false}"
    info "auto_repair_markdown_artifacts: ${AUTO_REPAIR_MARKDOWN_ARTIFACTS:-false}"
    info "auto_repair_markdown_dry_run: ${AUTO_REPAIR_MARKDOWN_DRY_RUN:-false}"
    info "auto_repair_markdown_backup: ${AUTO_REPAIR_MARKDOWN_BACKUP:-false}"
    info "auto_repair_markdown_only_session_changed: ${AUTO_REPAIR_MARKDOWN_ONLY_SESSION_CHANGED:-false}"
    info "phase_manifest_mode: ${PHASE_MANIFEST_MODE:-$DEFAULT_PHASE_MANIFEST_MODE}"
    info "phase noop policies: plan=${PHASE_NOOP_POLICY_PLAN}, build=${PHASE_NOOP_POLICY_BUILD}, test=${PHASE_NOOP_POLICY_TEST}, refactor=${PHASE_NOOP_POLICY_REFACTOR}, lint=${PHASE_NOOP_POLICY_LINT}, document=${PHASE_NOOP_POLICY_DOCUMENT}"
    info "maps_dir: $(path_for_display "$MAPS_DIR")"
    info "subrepos_dir: $(path_for_display "$SUBREPOS_DIR")"
    info "agent_source_map: $(path_for_display "$AGENT_SOURCE_MAP_FILE")"
    info "binary_steering_map: $(path_for_display "$BINARY_STEERING_MAP_FILE")"
    info "self_improvement_log: $(path_for_display "$SELF_IMPROVEMENT_LOG_FILE")"
    info "setup_subrepos_script: $(path_for_display "$SETUP_SUBREPOS_SCRIPT")"
}

emit_phase_transition_banner() {
    local phase="$1"
    local noop_policy
    noop_policy="$(phase_noop_policy "$phase")"
    info ">>> Entering phase '$phase' <<<"
    info "phase completion attempts remaining: $(phase_attempt_limit_display "${PHASE_COMPLETION_MAX_ATTEMPTS:-0}")"
    if [ "$noop_policy" = "hard" ]; then
        info "worktree mutation policy: hard (attempt must mutate repository contents)"
    elif [ "$noop_policy" = "soft" ]; then
        info "worktree mutation policy: soft (no mutation is allowed but surfaced)"
    else
        info "worktree mutation policy: none"
    fi
}

format_retry_budget_block_reason() {
    local phase="$1"
    local attempt="$2"
    local limit="$3"
    log_reason_code "RB_PHASE_COMPLETION_RETRY_EXHAUSTED" "$phase completion signal exhausted after $attempt/$limit attempts"
}

main() {
    parse_args "$@" || return $?
    if [ -n "$REQUEST_COMMAND" ]; then
        request_control
        return $?
    fi
    validate_effective_engine_config || return 1
    apply_notification_prerequisites
    normalize_integer_setting GATE_TIMEOUT_SECONDS 1 || return 1
    cd "$PROJECT_DIR" || return 1
    is_number "$GATE_TIMEOUT_SECONDS" && [ "$GATE_TIMEOUT_SECONDS" -gt 0 ] || { err 'Gate timeout must be a positive integer'; return 1; }
    validate_engine_options || return 1
    self_update_check_and_reexec "$@"
    if [ "${RALPHIE_SELF_UPDATE_TEST:-}" = "1" ]; then
        echo "RALPHIE_SELF_UPDATE_CURRENT_OK"
        return 0
    fi
    finalize_phase_noop_profile_config

    validate_owned_runtime_paths || return 1
    acquire_lock || exit 1
    install_cleanup_traps

    request_lock || return 1
    local resume_reentry_pending="false"
    if is_true "$RESUME_REQUESTED" && { [ -e "$STATE_FILE" ] || [ -L "$STATE_FILE" ]; }; then
        if ! load_state; then
            err 'Existing mission state is invalid. Restore it, or review the mission and use --no-resume; no engine was invoked.'
            return 1
        fi
        resume_reentry_pending="true"
        success "Resuming mission..."
        RALPHIE_CLEANUP_STATE_ENABLED="true"
    else
        request_fresh_start_allowed || { request_unlock; return 1; }
        rm -f "$SESSION_CHANGED_PATHS_FILE" 2>/dev/null || true
        save_state_or_exit "session bootstrap initialization"
        RALPHIE_CLEANUP_STATE_ENABLED="true"
    fi
    request_unlock || return 1
    if is_true "$ENGINE_OUTPUT_TO_STDOUT_EXPLICIT"; then
        ENGINE_OUTPUT_TO_STDOUT="$ENGINE_OUTPUT_TO_STDOUT_OVERRIDE"
    fi

    if ! is_number "$MAX_SESSION_CYCLES" || [ "$MAX_SESSION_CYCLES" -lt 0 ]; then
        MAX_SESSION_CYCLES=0
    fi
    if ! is_number "$PHASE_COMPLETION_MAX_ATTEMPTS" || [ "$PHASE_COMPLETION_MAX_ATTEMPTS" -lt 0 ]; then
        PHASE_COMPLETION_MAX_ATTEMPTS="$DEFAULT_PHASE_COMPLETION_MAX_ATTEMPTS"
    fi
    if ! is_number "$PHASE_COMPLETION_RETRY_DELAY_SECONDS" || [ "$PHASE_COMPLETION_RETRY_DELAY_SECONDS" -lt 0 ]; then
        PHASE_COMPLETION_RETRY_DELAY_SECONDS="$DEFAULT_PHASE_COMPLETION_RETRY_DELAY_SECONDS"
    fi
    if ! is_number "$RUN_AGENT_MAX_ATTEMPTS" || [ "$RUN_AGENT_MAX_ATTEMPTS" -lt 1 ]; then
        RUN_AGENT_MAX_ATTEMPTS="$DEFAULT_RUN_AGENT_MAX_ATTEMPTS"
    fi
    if ! is_number "$RUN_AGENT_RETRY_DELAY_SECONDS" || [ "$RUN_AGENT_RETRY_DELAY_SECONDS" -lt 0 ]; then
        RUN_AGENT_RETRY_DELAY_SECONDS="$DEFAULT_RUN_AGENT_RETRY_DELAY_SECONDS"
    fi
    if ! is_number "$ENGINE_HEALTH_MAX_ATTEMPTS" || [ "$ENGINE_HEALTH_MAX_ATTEMPTS" -lt 1 ]; then
        ENGINE_HEALTH_MAX_ATTEMPTS="$DEFAULT_ENGINE_HEALTH_MAX_ATTEMPTS"
    fi
    if ! is_number "$ENGINE_HEALTH_RETRY_DELAY_SECONDS" || [ "$ENGINE_HEALTH_RETRY_DELAY_SECONDS" -lt 0 ]; then
        ENGINE_HEALTH_RETRY_DELAY_SECONDS="$DEFAULT_ENGINE_HEALTH_RETRY_DELAY_SECONDS"
    fi
    if ! is_number "$SWARM_MAX_PARALLEL" || [ "$SWARM_MAX_PARALLEL" -lt 1 ]; then
        SWARM_MAX_PARALLEL="$DEFAULT_SWARM_MAX_PARALLEL"
    fi
    if ! is_number "$CONFIDENCE_TARGET" || [ "$CONFIDENCE_TARGET" -lt 0 ] || [ "$CONFIDENCE_TARGET" -gt 100 ]; then
        CONFIDENCE_TARGET="$DEFAULT_CONFIDENCE_TARGET"
    fi
    if ! is_number "$CONFIDENCE_STAGNATION_LIMIT" || [ "$CONFIDENCE_STAGNATION_LIMIT" -lt 1 ]; then
        CONFIDENCE_STAGNATION_LIMIT="$DEFAULT_CONFIDENCE_STAGNATION_LIMIT"
    fi
    if ! is_number "$MAX_CONSENSUS_ROUTING_ATTEMPTS" || [ "$MAX_CONSENSUS_ROUTING_ATTEMPTS" -lt 0 ]; then
        MAX_CONSENSUS_ROUTING_ATTEMPTS="$DEFAULT_MAX_CONSENSUS_ROUTING_ATTEMPTS"
    fi
    if ! is_number "$PHASE_PAIR_CYCLE_LIMIT" || [ "$PHASE_PAIR_CYCLE_LIMIT" -lt 0 ]; then
        PHASE_PAIR_CYCLE_LIMIT="$DEFAULT_PHASE_PAIR_CYCLE_LIMIT"
    fi
    if ! is_number "$MAX_ITERATIONS" || [ "$MAX_ITERATIONS" -lt 0 ]; then
        MAX_ITERATIONS=0
    fi
    if ! is_number "$COMMAND_TIMEOUT_SECONDS" || [ "$COMMAND_TIMEOUT_SECONDS" -lt 0 ]; then
        COMMAND_TIMEOUT_SECONDS="$DEFAULT_COMMAND_TIMEOUT_SECONDS"
    fi
    if ! is_number "$ENGINE_OUTPUT_MAX_BYTES" || [ "$ENGINE_OUTPUT_MAX_BYTES" -lt 1 ]; then
        err "ENGINE_OUTPUT_MAX_BYTES must be a positive integer."
        return 1
    fi
    warn_timeout_binary_unavailable_if_needed
    if ! is_number "$SWARM_CONSENSUS_TIMEOUT" || [ "$SWARM_CONSENSUS_TIMEOUT" -lt 1 ]; then
        SWARM_CONSENSUS_TIMEOUT="$DEFAULT_SWARM_CONSENSUS_TIMEOUT"
    fi
    if ! is_number "$ENGINE_SMOKE_TEST_TIMEOUT" || [ "$ENGINE_SMOKE_TEST_TIMEOUT" -lt 1 ]; then
        ENGINE_SMOKE_TEST_TIMEOUT="$DEFAULT_ENGINE_SMOKE_TEST_TIMEOUT"
    fi

    local should_exit="false"
    # A saved completion is rechecked by the shell below, without inference.
    # A spent inference allowance cannot prevent that local verification.
    if [ "$resume_reentry_pending" != true ] || [ "$CURRENT_PHASE" != done ] || is_true "$PLAN_ONLY"; then
        if ! enforce_session_budget "session init"; then
            should_exit="true"
        fi
    fi
    if is_true "$should_exit"; then
        save_state_or_exit "session budget preflight failure"
        release_lock
        exit 1
    fi

    runtime_guard_prepare || return 1
    prepare_mission_seed "$resume_reentry_pending" || return 1
    if is_true "$PLAN_ONLY" && [ -z "${MISSION_SEED_SHA:-}" ] && [ ! -f "$PROJECT_BOOTSTRAP_FILE" ]; then
        err '--plan-only requires --objective, --spec, or a saved bootstrap objective.'
        return 1
    fi
    if ! ensure_git_repository_initialized; then
        release_lock
        return 1
    fi
    capture_operator_baseline || return 1
    [ -n "$SESSION_INITIAL_HEAD" ] || SESSION_INITIAL_HEAD="$(git -C "$PROJECT_DIR" rev-parse --verify --quiet HEAD 2>/dev/null || true)"
    print_session_config_banner
    if is_true "$STARTUP_OPERATIONAL_PROBE"; then
        if ! run_startup_operational_probe; then
            release_lock
            exit 1
        fi
    fi
    ensure_core_artifacts
    setup_phase_prompts
    ensure_gitignore_guardrails
    if [ -z "${MISSION_SEED_SHA:-}" ]; then
        ensure_project_bootstrap || return $?
    fi
    prepare_shell_gates || return 1
    capture_scaffold_ownership || return 1
    prepare_no_local_work_witness "$resume_reentry_pending" || return 1
    snapshot_operator_inputs || return 1
    request_prepare_mission || return 1
    refresh_git_identity_status || true
    prepare_phase_auto_commit_mode || return 1
    save_state_or_exit "post-startup bootstrap"

    local plan_only_completed=false
    local -a phases=("plan" "build" "test" "refactor" "lint" "document")
    local phase_index=0
    local start_phase_index=0
    local start_phase_name="plan"
    local -a phase_resume_blockers=()
    local done_phase_index="${#phases[@]}"
    if is_true "$RESUME_REQUESTED"; then
        if [ "${CURRENT_PHASE:-}" = "done" ]; then
            start_phase_index="$done_phase_index"
        else
        start_phase_index="$CURRENT_PHASE_INDEX"
        if ! is_number "$start_phase_index" || [ "$start_phase_index" -lt 0 ] || [ "$start_phase_index" -ge "${#phases[@]}" ]; then
            start_phase_index="$(phase_index_from_name "$CURRENT_PHASE")" || start_phase_index=0
            if ! is_number "$start_phase_index" || [ "$start_phase_index" -lt 0 ] || [ "$start_phase_index" -ge "${#phases[@]}" ]; then
                start_phase_index=0
            fi
        fi
        fi
        start_phase_name="$(phase_name_from_index "$start_phase_index")" || start_phase_name="plan"
        if [ "$start_phase_index" -lt "${#phases[@]}" ]; then
            mapfile -t phase_resume_blockers < <(collect_phase_resume_blockers "$start_phase_name")
        else
            phase_resume_blockers=()
        fi
        if [ "${#phase_resume_blockers[@]}" -gt 0 ]; then
            local resume_blockers_summary
            resume_blockers_summary="$(summarize_blocks_for_log "${phase_resume_blockers[@]}")"
            warn "Resumption into '$start_phase_name' is blocked by unmet preconditions: $resume_blockers_summary"
            warn "Falling back to plan phase to rebuild required artifacts and references."
            log_reason_code "RB_PHASE_RESUME_FALLBACK" "resume to $start_phase_name blocked: $resume_blockers_summary"
            write_gate_feedback "resume-recovery" "resumption fallback to plan" "${phase_resume_blockers[@]}"
            start_phase_name="plan"
            start_phase_index=0
            CURRENT_PHASE="$start_phase_name"
            CURRENT_PHASE_INDEX="$start_phase_index"
            CURRENT_PHASE_ATTEMPT=1
            PHASE_ATTEMPT_IN_PROGRESS="false"
            save_state_or_exit "resume fallback to plan checkpoint"
        fi
    fi

    if is_true "$PLAN_ONLY"; then
        start_phase_index=0
        CURRENT_PHASE=plan
        CURRENT_PHASE_INDEX=0
        PHASE_ATTEMPT_IN_PROGRESS=false
    fi
    local consensus_route_count=0
    local routing_stagnation_signature=""
    local routing_stagnation_count=0
    local routing_pair_cycle_key=""
    local routing_pair_cycle_count=0
    local engine_override_bootstrap_checked="false"
    local notification_wizard_bootstrap_checked="false"
    local session_start_notified="false"
    while true; do
        request_take_snapshot || return 1
        if [ "$start_phase_index" -gt 0 ] \
            && [ "$REQUEST_FROZEN_FINGERPRINT" != "$REQUEST_REVIEWED_FINGERPRINT" ] \
            && { [ "$start_phase_index" -lt "${#phases[@]}" ] || [ "$REQUEST_ACTIVE_COUNT" -gt 0 ]; }; then
            request_checkpoint_plan_refresh "$CURRENT_PHASE" "$CURRENT_PHASE_ATTEMPT"
            start_phase_index=0
            resume_reentry_pending=false
        fi
        if [ "$start_phase_index" -lt "${#phases[@]}" ]; then
        ENGINE_CAPABILITIES_PROBED=false  # force fresh probe (including smoke test) each iteration
        if ! ensure_engines_ready "$ENGINE_SELECTION_REQUESTED"; then
            if is_true "$REQUEST_REFRESH_REQUIRED"; then
                request_checkpoint_plan_refresh "$CURRENT_PHASE" "$CURRENT_PHASE_ATTEMPT"
                start_phase_index=0
                continue
            fi
            should_exit="true"
            log_reason_code "RB_ENGINE_SELECTION_FAILED" "$LAST_ENGINE_SELECTION_BLOCK_REASON"
            notify_event "session_error" "engine_selection_failed" "$LAST_ENGINE_SELECTION_BLOCK_REASON" || true
            break
        fi
        if [ "$engine_override_bootstrap_checked" = "false" ]; then
            engine_override_bootstrap_checked="true"
            if run_first_deploy_engine_override_wizard; then
                ENGINE_CAPABILITIES_PROBED=false
                if ! ensure_engines_ready "$ENGINE_SELECTION_REQUESTED"; then
                    if is_true "$REQUEST_REFRESH_REQUIRED"; then
                        request_checkpoint_plan_refresh "$CURRENT_PHASE" "$CURRENT_PHASE_ATTEMPT"
                        start_phase_index=0
                        continue
                    fi
                    should_exit="true"
                    log_reason_code "RB_ENGINE_SELECTION_FAILED" "$LAST_ENGINE_SELECTION_BLOCK_REASON"
                    notify_event "session_error" "engine_selection_failed" "$LAST_ENGINE_SELECTION_BLOCK_REASON" || true
                    break
                fi
            else
                local wizard_status=$?
                [ "$wizard_status" -ne 130 ] || return 130
            fi
        fi
        if [ "$notification_wizard_bootstrap_checked" = "false" ]; then
            notification_wizard_bootstrap_checked="true"
            local notification_wizard_status=0
            run_first_deploy_notification_wizard || notification_wizard_status=$?
            [ "$notification_wizard_status" -ne 130 ] || return 130
        fi
        if [ "$session_start_notified" = "false" ]; then
            session_start_notified="true"
            notify_event "session_start" "ok" "engine_request=$ENGINE_SELECTION_REQUESTED active_engine=$ACTIVE_ENGINE channels=$(notification_channels_for_display)" || true
        fi
        fi
        for ((phase_index = start_phase_index; phase_index < ${#phases[@]}; phase_index++)); do
            local phase="${phases[$phase_index]}"
            local reentering_in_progress_phase="false"
            if is_true "$should_exit"; then break 2; fi
            CURRENT_PHASE_INDEX="$phase_index"
            CURRENT_PHASE="$phase"
            if [ "$resume_reentry_pending" = "true" ] && [ "$phase_index" -eq "$start_phase_index" ] && is_true "$PHASE_ATTEMPT_IN_PROGRESS"; then
                reentering_in_progress_phase="true"
                info "Resuming in-progress phase '$phase' at iteration ${ITERATION_COUNT} attempt ${CURRENT_PHASE_ATTEMPT}."
            else
                if [ "$MAX_ITERATIONS" -gt 0 ] && [ "$ITERATION_COUNT" -ge "$MAX_ITERATIONS" ]; then
                    log_reason_code "RB_ITERATION_BUDGET_REACHED" "run iteration budget reached before phase $phase at $ITERATION_COUNT/$MAX_ITERATIONS"
                    notify_event "session_error" "iteration_budget_reached" "iteration budget reached before phase=$phase at $ITERATION_COUNT/$MAX_ITERATIONS" || true
                    should_exit="true"
                    break 2
                fi
                ITERATION_COUNT=$((ITERATION_COUNT + 1))
            fi
            if [ "$reentering_in_progress_phase" != "true" ]; then
                CURRENT_PHASE_ATTEMPT=1
                PHASE_ATTEMPT_IN_PROGRESS="false"
            fi
            resume_reentry_pending="false"
            save_state_or_exit "phase entry checkpoint ($phase)"

            local pfile
            pfile="$(prompt_file_for_mode "$phase")"
            ensure_runtime_directory "$LOG_DIR" && ensure_runtime_directory "$COMPLETION_LOG_DIR" || return 1
            if ! enforce_session_budget "session loop"; then
                should_exit="true"
                break
            fi
            case "$phase" in build|test|refactor|lint) SHELL_DEVELOPMENT_PHASE_STARTED=true;; esac
            emit_phase_transition_banner "$phase"
            if [ ! -f "$pfile" ]; then
                ensure_prompt_file "$phase" "$pfile"
            fi
            if [ "$phase" != "plan" ] && ! build_is_preapproved; then
                warn "Post-plan execution ($phase) was not pre-approved in project bootstrap context."
                warn "Edit $(path_for_display "$PROJECT_BOOTSTRAP_FILE") and set build_consent: true to continue automatically into BUILD."
                log_reason_code "RB_BUILD_CONSENT_REQUIRED" "$phase blocked because bootstrap build_consent is false"
                notify_event "session_error" "build_consent_missing" "$phase phase blocked because bootstrap build_consent=false" || true
                should_exit="true"
                break 2
            fi
            if [ "$phase" = "plan" ]; then
                run_stack_discovery
                if [ ! -f "$STACK_SNAPSHOT_FILE" ] || ! grep -qE '^##[[:space:]]*Project Stack Ranking' "$STACK_SNAPSHOT_FILE" 2>/dev/null; then
                    warn "Stack discovery could not generate a valid ranking snapshot."
                    log_reason_code "RB_STACK_DISCOVERY_FAILED" "could not generate deterministic stack snapshot"
                    notify_event "session_error" "stack_discovery_failed" "deterministic stack snapshot generation failed" || true
                    should_exit="true"
                    break
                fi
                save_state_or_exit "plan stack discovery checkpoint"
            fi

            local phase_attempt=1
            if [ "$reentering_in_progress_phase" = "true" ] && is_number "$CURRENT_PHASE_ATTEMPT" && [ "$CURRENT_PHASE_ATTEMPT" -ge 1 ]; then
                phase_attempt="$CURRENT_PHASE_ATTEMPT"
            fi
            if ! is_number "$phase_attempt" || [ "$phase_attempt" -lt 1 ] || { [ "$PHASE_COMPLETION_MAX_ATTEMPTS" -gt 0 ] && [ "$phase_attempt" -gt "$PHASE_COMPLETION_MAX_ATTEMPTS" ]; }; then
                warn "Recovered invalid persisted phase attempt '$phase_attempt' for phase '$phase'; resetting to attempt 1."
                phase_attempt=1
            fi
            local -a cumulative_phase_failures=()
            local phase_next_target="$phase"
            local phase_route="false"
            local phase_route_reason=""
            local phase_stagnation_signature=""
            local phase_stagnation_count=0
            while phase_attempt_within_budget "$phase_attempt" "$PHASE_COMPLETION_MAX_ATTEMPTS"; do
                request_take_snapshot || return 1
                if [ "$phase" != plan ] && [ "$REQUEST_FROZEN_FINGERPRINT" != "$REQUEST_REVIEWED_FINGERPRINT" ]; then
                    phase_next_target=plan
                    phase_route=true
                    phase_route_reason='human requests changed; refresh PLAN'
                    request_checkpoint_plan_refresh "$phase" "$phase_attempt"
                    break
                fi
                CURRENT_PHASE="$phase"
                CURRENT_PHASE_INDEX="$phase_index"
                CURRENT_PHASE_ATTEMPT="$phase_attempt"
                PHASE_ATTEMPT_IN_PROGRESS="true"
                save_state_or_exit "phase attempt start checkpoint ($phase attempt $phase_attempt)"
                phase_attempt_started_at="$(date +%s 2>/dev/null || echo 0)"

                local lfile="$LOG_DIR/${phase}_${SESSION_ID}_${ITERATION_COUNT}_attempt_${phase_attempt}.log"
                local ofile="$COMPLETION_LOG_DIR/${phase}_${SESSION_ID}_${ITERATION_COUNT}_attempt_${phase_attempt}.out"
                local active_prompt="$pfile"
                local -a phase_failures=()
                local -a phase_warnings=()
                local consensus_evaluated="false"
                local attempt_feedback_file="$LOG_DIR/${phase}_${SESSION_ID}_${ITERATION_COUNT}_attempt_${phase_attempt}.prompt.md"
                local bootstrap_prompt_file="$LOG_DIR/${phase}_${SESSION_ID}_${ITERATION_COUNT}_attempt_${phase_attempt}.bootstrap.prompt.md"
                local previous_attempt_output_hash=""
                local previous_attempt_output_file=""
                local phase_noop_mode manifest_before_file manifest_after_file
                phase_noop_mode="$(phase_noop_policy "$phase")"
                local phase_delta_preview=""
                local handoff_validator_prompt="$LOG_DIR/${phase}_${SESSION_ID}_${ITERATION_COUNT}_attempt_${phase_attempt}.handoff.prompt.md"
                local handoff_validator_log="$LOG_DIR/${phase}_${SESSION_ID}_${ITERATION_COUNT}_attempt_${phase_attempt}.handoff.log"
                local handoff_validator_out="$COMPLETION_LOG_DIR/${phase}_${SESSION_ID}_${ITERATION_COUNT}_attempt_${phase_attempt}.handoff.out"
                local handoff_validator_status="$COMPLETION_LOG_DIR/${phase}_${SESSION_ID}_${ITERATION_COUNT}_attempt_${phase_attempt}.handoff.status"
                local handoff_validator_primary=""
                local handoff_validator_fallback=""
                local phase_warnings_text=""
                local consensus_evidence_context=""
                local -a consensus_failures=()
                local phase_commit_target=""

                manifest_before_file="$LOG_DIR/${phase}_${SESSION_ID}_${ITERATION_COUNT}_attempt_${phase_attempt}_manifest_before.txt"
                manifest_after_file="$LOG_DIR/${phase}_${SESSION_ID}_${ITERATION_COUNT}_attempt_${phase_attempt}_manifest_after.txt"
                if ! phase_capture_worktree_manifest "$manifest_before_file"; then
                    err "Could not snapshot the project before phase execution."
                    should_exit=true
                    PHASE_ATTEMPT_IN_PROGRESS=false
                    break
                fi
                ACTIVE_PHASE_MANIFEST_BEFORE="$manifest_before_file"
                render_status_dashboard "$phase" "$phase_attempt" "$PHASE_COMPLETION_MAX_ATTEMPTS" "$ITERATION_COUNT"

                if [ "$phase_attempt" -gt 1 ]; then
                    local previous_attempt_file="$COMPLETION_LOG_DIR/${phase}_${SESSION_ID}_${ITERATION_COUNT}_attempt_$((phase_attempt - 1)).out"
                    if [ -f "$previous_attempt_file" ]; then
                        previous_attempt_output_hash="$(sha256_file_sum "$previous_attempt_file" 2>/dev/null || echo "")"
                        previous_attempt_output_file="$previous_attempt_file"
                    fi
                fi

                if [ "$phase" = "plan" ] || [ "$phase" = "build" ]; then
                    if append_bootstrap_context_to_phase_prompt "$pfile" "$bootstrap_prompt_file"; then
                        active_prompt="$bootstrap_prompt_file"
                    else
                        phase_failures+=("failed to assemble $phase prompt with bootstrap context")
                    fi
                fi

                if [ "$phase_attempt" -gt 1 ]; then
                    if [ "${#cumulative_phase_failures[@]}" -gt 0 ]; then
                        build_phase_prompt_with_feedback "$phase" "$active_prompt" "$attempt_feedback_file" "$phase_attempt" "${cumulative_phase_failures[@]}"
                    else
                        build_phase_prompt_with_feedback "$phase" "$active_prompt" "$attempt_feedback_file" "$phase_attempt"
                    fi
                    active_prompt="$attempt_feedback_file"
                fi

                if [ "$phase" = "build" ] && ! enforce_build_gate; then
                    local -a gate_issues=()
                    mapfile -t gate_issues < <(collect_build_prerequisites_issues)
                    local repair_summary=""
                    if is_true "$AUTO_REPAIR_MARKDOWN_ARTIFACTS" && ! markdown_artifacts_are_clean; then
                        if sanitize_markdown_artifacts; then
                            repair_summary="$(markdown_artifact_cleanup_summary)"
                            if [ -n "$repair_summary" ]; then
                                phase_warnings+=("pre-build markdown remediation: ${repair_summary//$'\\n'/; }")
                            fi
                        fi
                        if [ -n "$repair_summary" ] && enforce_build_gate; then
                            gate_issues=()
                            phase_warnings+=("build gate passed after markdown artifact remediation")
                        fi
                    fi
                    if [ "${#gate_issues[@]}" -gt 0 ] && [ -n "$repair_summary" ]; then
                        phase_failures+=("pre-build markdown remediation applied before retry")
                        phase_failures+=("pre-build markdown remediation summary: ${repair_summary//$'\\n'/; }")
                    fi
                    if [ "${#gate_issues[@]}" -gt 0 ]; then
                        local gate_requires_plan_refresh=false
                        local gate_has_non_plan_refresh=false
                        for issue in "${gate_issues[@]}"; do
                            case "$issue" in
                                "plan refresh required:"*) gate_requires_plan_refresh=true ;;
                                *) gate_has_non_plan_refresh=true ;;
                            esac
                        done
                        if is_true "$gate_requires_plan_refresh" && ! is_true "$gate_has_non_plan_refresh"; then
                            phase_next_target="plan"
                            phase_route="true"
                            phase_route_reason="${gate_issues[0]}"
                            phase_transition_history_append "$phase" "$phase_attempt" "$phase_next_target" "hold" "$phase_route_reason"
                            write_gate_feedback "$phase" "${gate_issues[@]}" "auto-reroute triggered: build -> plan for backlog freshness"
                            warn "Build gate requires plan refresh; auto-routing build -> plan instead of retrying build."
                            notify_event "phase_decision" "reroute_hold" "phase=$phase attempt=$phase_attempt rerouted_to=$phase_next_target reason=${phase_route_reason:-none}" || true
                            log_reason_code "RB_BUILD_GATE_PLAN_REFRESH_REROUTE" "$phase attempt $phase_attempt rerouted to plan after backlog freshness gate"
                            PHASE_ATTEMPT_IN_PROGRESS="false"
                            CURRENT_PHASE_ATTEMPT=1
                            save_state_or_exit "build gate plan-refresh reroute checkpoint"
                            break
                        fi
                        for issue in "${gate_issues[@]}"; do
                            phase_failures+=("build gate blocked before build execution: $issue")
                        done
                    fi
                fi

                : > "$RUNTIME_GUARD_DIR/tampered"
                PHASE_SAVE_REQUIRED=false
                PHASE_SAVE_OK=true
                PHASE_SAVE_REASON=''
                local agent_run_ok=false
                if [ "${#phase_failures[@]}" -eq 0 ]; then
                    local saved_command_timeout_for_phase="$COMMAND_TIMEOUT_SECONDS"
                    if is_number "$PHASE_WALLCLOCK_LIMIT_SECONDS" && [ "$PHASE_WALLCLOCK_LIMIT_SECONDS" -gt 0 ] && is_number "${phase_attempt_started_at:-0}" && [ "${phase_attempt_started_at:-0}" -gt 0 ]; then
                        local now_for_timeout elapsed_for_timeout remaining_for_timeout
                        now_for_timeout="$(date +%s 2>/dev/null || echo 0)"
                        elapsed_for_timeout=$(( now_for_timeout - phase_attempt_started_at ))
                        remaining_for_timeout=$(( PHASE_WALLCLOCK_LIMIT_SECONDS - elapsed_for_timeout ))
                        if [ "$remaining_for_timeout" -le 0 ]; then
                            phase_failures+=("phase wall-clock limit reached before agent execution")
                        elif ! is_number "$COMMAND_TIMEOUT_SECONDS" || [ "$COMMAND_TIMEOUT_SECONDS" -eq 0 ] || [ "$COMMAND_TIMEOUT_SECONDS" -gt "$remaining_for_timeout" ]; then
                            COMMAND_TIMEOUT_SECONDS="$remaining_for_timeout"
                        fi
                    fi
                    if [ "${#phase_failures[@]}" -eq 0 ] && run_agent_with_prompt "$active_prompt" "$lfile" "$ofile" "$YOLO" "$phase_attempt"; then
                        agent_run_ok=true
                    fi
                    COMMAND_TIMEOUT_SECONDS="$saved_command_timeout_for_phase"
                fi
                if ! checkpoint_current_phase_worktree; then
                    phase_failures+=("could not persist returned phase ownership")
                fi
                save_state_or_exit "post-dispatch ownership checkpoint"
                if is_true "${ENGINE_PERMANENT_FAILURE:-false}"; then
                    err "${ENGINE_PERMANENT_FAILURE_REASON:-Engine configuration needs operator repair.}"
                    should_exit=true
                    PHASE_ATTEMPT_IN_PROGRESS=false
                    log_reason_code RB_ENGINE_CONFIGURATION_FAILED "${ENGINE_PERMANENT_FAILURE_REASON:-engine configuration failure}"
                    save_state_or_exit "permanent engine configuration failure"
                    break
                fi
                if is_true "${ENGINE_BUDGET_EXHAUSTED:-false}"; then
                    err "${ENGINE_BUDGET_FAILURE_REASON:-Session inference budget exhausted.}"
                    should_exit=true
                    PHASE_ATTEMPT_IN_PROGRESS=false
                    save_state_or_exit "engine budget exhausted"
                    break
                fi
                if [ "${#phase_failures[@]}" -eq 0 ] && is_true "$agent_run_ok"; then
                    # Verify agent produced meaningful output
                    if [ ! -f "$ofile" ] || [ ! -s "$ofile" ]; then
                        phase_failures+=("agent completed with exit 0 but produced no output artifact")
                    fi
                    # Worker prose can describe its work; only run_shell_gates
                    # supplies deterministic execution evidence below.

                    if [ -n "$previous_attempt_output_hash" ] && [ "${#phase_failures[@]}" -eq 0 ]; then
                        local phase_output_hash
                        phase_output_hash="$(sha256_file_sum "$ofile" 2>/dev/null || echo "")"
                        if [ -n "$previous_attempt_output_hash" ] && [ -n "$phase_output_hash" ] && [ "$previous_attempt_output_hash" = "$phase_output_hash" ]; then
                            phase_failures+=("phase output did not materially change from prior attempt")
                        fi
                    fi

                    if [ "$phase" = "plan" ]; then
                        local -a post_plan_gate_issues=()
                        local -a post_plan_actionable_gate_issues=()
                        local post_plan_issue
                        local post_plan_freshness_pending="false"
                        mapfile -t post_plan_gate_issues < <(collect_build_prerequisites_issues)
                        local post_plan_repair_summary=""
                        if is_true "$AUTO_REPAIR_MARKDOWN_ARTIFACTS" && ! markdown_artifacts_are_clean; then
                            if sanitize_markdown_artifacts; then
                                post_plan_repair_summary="$(markdown_artifact_cleanup_summary)"
                                mapfile -t post_plan_gate_issues < <(collect_build_prerequisites_issues)
                                [ -n "$post_plan_repair_summary" ] && phase_warnings+=("post-plan markdown remediation: ${post_plan_repair_summary//$'\\n'/; }")
                            fi
                        fi
                        if [ "${#post_plan_gate_issues[@]}" -gt 0 ]; then
                            for post_plan_issue in "${post_plan_gate_issues[@]}"; do
                                case "$post_plan_issue" in
                                    "plan refresh required:"*)
                                        post_plan_freshness_pending="true"
                                        ;;
                                    *)
                                        post_plan_actionable_gate_issues+=("$post_plan_issue")
                                        ;;
                                esac
                            done
                        fi
                        if is_true "$post_plan_freshness_pending" && [ "${#post_plan_actionable_gate_issues[@]}" -eq 0 ]; then
                            if record_plan_freshness_checkpoint; then
                                post_plan_freshness_pending="false"
                                mapfile -t post_plan_gate_issues < <(collect_build_prerequisites_issues)
                                for post_plan_issue in "${post_plan_gate_issues[@]}"; do
                                    case "$post_plan_issue" in
                                        "plan refresh required:"*)
                                            post_plan_actionable_gate_issues+=("plan freshness checkpoint remained stale after recording")
                                            ;;
                                        *)
                                            post_plan_actionable_gate_issues+=("$post_plan_issue")
                                            ;;
                                    esac
                                done
                            else
                                post_plan_actionable_gate_issues+=("plan freshness checkpoint could not be recorded after plan")
                            fi
                        fi
                        if [ "${#post_plan_actionable_gate_issues[@]}" -eq 0 ] && [ -n "$post_plan_repair_summary" ]; then
                            info "Build gate passed after post-plan markdown remediation."
                        fi
                        if [ "${#post_plan_actionable_gate_issues[@]}" -gt 0 ]; then
                            phase_failures+=("build gate failed after plan->build transition")
                            [ -n "$post_plan_repair_summary" ] && phase_failures+=("post-plan markdown remediation summary: ${post_plan_repair_summary//$'\\n'/; }")
                            for issue in "${post_plan_actionable_gate_issues[@]}"; do
                                phase_failures+=("build gate: $issue")
                            done
                        fi
                    fi

                    phase_capture_worktree_manifest "$manifest_after_file" || true
                    if [ -f "$manifest_before_file" ] && [ -f "$manifest_after_file" ]; then
                        shell_note_local_work "$manifest_before_file" "$manifest_after_file"
                        if phase_manifest_changed "$manifest_before_file" "$manifest_after_file"; then
                            record_session_changed_paths_from_manifest "$manifest_before_file" "$manifest_after_file" || true
                            phase_delta_preview="$(phase_manifest_delta_preview "$manifest_before_file" "$manifest_after_file" 8)"
                            if [ -n "$phase_delta_preview" ]; then
                                phase_delta_preview="$(printf '%s' "$phase_delta_preview" | tr '\n' '; ')"
                                if [ "$phase_noop_mode" != "none" ]; then
                                    phase_warnings+=("manifest delta preview: $phase_delta_preview")
                                fi
                            fi
                        else
                            if [ "$phase_noop_mode" = "hard" ]; then
                                phase_failures+=("$phase completed with no worktree mutation for phase '$phase'")
                            elif [ "$phase_noop_mode" = "soft" ]; then
                                phase_warnings+=("soft no-op signal: $phase completed without visible worktree mutation; acceptable for validation-only phases when run outputs are present")
                            fi
                        fi
                    elif [ "$phase_noop_mode" != "none" ]; then
                        phase_warnings+=("phase no-op check skipped: could not capture a reliable manifest snapshot for this attempt")
                    fi

                    phase_warnings_text="$(printf '%s\n' "${phase_warnings[@]+"${phase_warnings[@]}"}")"
                    write_handoff_validation_prompt \
                        "$phase" \
                        "$phase_attempt" \
                        "$ofile" \
                        "$lfile" \
                        "$handoff_validator_prompt" \
                        "$manifest_before_file" \
                        "$manifest_after_file" \
                        "$phase_delta_preview" \
                        "$phase_noop_mode" \
                        "$phase_warnings_text" \
                        "$previous_attempt_output_file"

                    local handoff_candidate
                    handoff_validator_primary=""
                    handoff_validator_fallback=""
                    while IFS= read -r handoff_candidate; do
                        [ -n "$handoff_candidate" ] || continue
                        if [ -z "$handoff_validator_primary" ]; then
                            handoff_validator_primary="$handoff_candidate"
                        elif [ -z "$handoff_validator_fallback" ]; then
                            handoff_validator_fallback="$handoff_candidate"
                        fi
                    done < <(reviewer_command_candidates)
                    # In AUTO, a different available engine gets the first look.
                    # Explicit engine/model choices return only one candidate.
                    if [ "$handoff_validator_primary" = "$ACTIVE_CMD" ] && [ -n "$handoff_validator_fallback" ]; then
                        handoff_candidate="$handoff_validator_primary"
                        handoff_validator_primary="$handoff_validator_fallback"
                        handoff_validator_fallback="$handoff_candidate"
                    fi
                    info "Handoff reviewer policy: ${ENGINE_SELECTION_REQUESTED:-auto}"

                    if ! run_handoff_validation \
                        "$phase" \
                        "$handoff_validator_prompt" \
                        "$handoff_validator_log" \
                        "$handoff_validator_out" \
                        "$handoff_validator_status" \
                        "$handoff_validator_primary" \
                        "$handoff_validator_fallback"; then
                        phase_failures+=("handoff validation failed after $phase")
                        phase_failures+=("handoff review: verdict=$LAST_HANDOFF_VERDICT score=$LAST_HANDOFF_SCORE gaps=$LAST_HANDOFF_GAPS")
                    fi
                    if is_true "${ENGINE_PERMANENT_FAILURE:-false}"; then
                        err "${ENGINE_PERMANENT_FAILURE_REASON:-Reviewer configuration needs operator repair.}"
                        should_exit=true
                        PHASE_ATTEMPT_IN_PROGRESS=false
                        log_reason_code RB_ENGINE_CONFIGURATION_FAILED "${ENGINE_PERMANENT_FAILURE_REASON:-reviewer configuration failure}"
                        save_state_or_exit "permanent handoff reviewer configuration failure"
                        break
                    fi
                    if is_true "${ENGINE_BUDGET_EXHAUSTED:-false}"; then
                        err "${ENGINE_BUDGET_FAILURE_REASON:-Session inference budget exhausted.}"
                        should_exit=true
                        PHASE_ATTEMPT_IN_PROGRESS=false
                        save_state_or_exit "handoff reviewer budget exhausted"
                        break
                    fi

                    if ! is_true "$REQUEST_REFRESH_REQUIRED"; then
                    consensus_evaluated="true"
                    local consensus_infra_retry_streak=0
                    local consensus_infra_signature=""
                    consensus_evidence_context="$(build_consensus_evidence_context \
                        "$phase" \
                        "$phase_attempt" \
                        "$ofile" \
                        "$lfile" \
                        "$handoff_validator_out" \
                        "$handoff_validator_status" \
                        "$manifest_before_file" \
                        "$manifest_after_file" \
                        "$phase_delta_preview" \
                        "$phase_warnings_text" \
                        "$previous_attempt_output_file")"
                    while true; do
                        if run_swarm_consensus "$phase-gate" "$(phase_transition_history_recent 8)" "$consensus_evidence_context"; then
                            record_gate_decision "$phase" "$phase_attempt" "$phase-gate" "pass"
                            break
                        fi
                        is_true "${ENGINE_PERMANENT_FAILURE:-false}" && break
                        is_true "${ENGINE_BUDGET_EXHAUSTED:-false}" && break
                        is_true "$REQUEST_REFRESH_REQUIRED" && break
                        record_gate_decision "$phase" "$phase_attempt" "$phase-gate" "hold"

                        if [ "$LAST_CONSENSUS_FAILURE_KIND" = "infra" ]; then
                            local consensus_failure_reason
                            local consensus_stagnation_limit
                            consensus_failure_reason="${LAST_CONSENSUS_FAILURE_REASON:-infrastructure failure}"
                            consensus_stagnation_limit="${CONFIDENCE_STAGNATION_LIMIT:-$DEFAULT_CONFIDENCE_STAGNATION_LIMIT}"
                            is_number "$consensus_stagnation_limit" || consensus_stagnation_limit="$DEFAULT_CONFIDENCE_STAGNATION_LIMIT"
                            if [ "$consensus_stagnation_limit" -lt 1 ]; then
                                consensus_stagnation_limit=1
                            fi

                            local current_consensus_signature
                            current_consensus_signature="$(phase_failure_signature "$LAST_CONSENSUS_FAILURE_KIND" "$consensus_failure_reason" "${LAST_CONSENSUS_RESPONDED_VOTES:-0}")"
                            if [ "$current_consensus_signature" = "$consensus_infra_signature" ]; then
                                consensus_infra_retry_streak=$((consensus_infra_retry_streak + 1))
                            else
                                consensus_infra_signature="$current_consensus_signature"
                                consensus_infra_retry_streak=1
                            fi

                            if [ "$consensus_infra_retry_streak" -ge "$consensus_stagnation_limit" ]; then
                                phase_failures+=("intelligence validation infra failure persisted after ${consensus_infra_retry_streak} retries: $consensus_failure_reason")
                                break
                            fi

                            warn "Consensus infrastructure issue detected ($consensus_failure_reason). Retrying consensus without consuming phase attempt."
                            notify_event "phase_blocked" "hold" "phase=$phase attempt=$phase_attempt reason=consensus_infra_retry retry=$consensus_infra_retry_streak/$consensus_stagnation_limit" || true
                            sleep "$PHASE_COMPLETION_RETRY_DELAY_SECONDS"
                            continue
                        fi

                        phase_failures+=("intelligence validation failed after $phase")
                        phase_failures+=("consensus score/verdict: score=${LAST_CONSENSUS_SCORE} pass=${LAST_CONSENSUS_PASS}")
                        mapfile -t consensus_failures < <(collect_phase_retry_failures_from_consensus)
                        for issue in "${consensus_failures[@]+"${consensus_failures[@]}"}"; do
                            phase_failures+=("consensus: $issue")
                        done
                        if [ -n "$LAST_CONSENSUS_SUMMARY" ]; then
                            phase_failures+=("consensus summary: $LAST_CONSENSUS_SUMMARY")
                        fi
                        break
                    done
                    fi
                else
                    if [ "${#phase_failures[@]}" -eq 0 ]; then
                        phase_failures+=("agent execution failed in $phase")
                    fi
                fi

                if is_true "${ENGINE_PERMANENT_FAILURE:-false}"; then
                    err "${ENGINE_PERMANENT_FAILURE_REASON:-Reviewer configuration needs operator repair.}"
                    should_exit=true
                    PHASE_ATTEMPT_IN_PROGRESS=false
                    log_reason_code RB_ENGINE_CONFIGURATION_FAILED "${ENGINE_PERMANENT_FAILURE_REASON:-reviewer configuration failure}"
                    save_state_or_exit "permanent consensus reviewer configuration failure"
                    break
                fi
                if is_true "${ENGINE_BUDGET_EXHAUSTED:-false}"; then
                    err "${ENGINE_BUDGET_FAILURE_REASON:-Session inference budget exhausted.}"
                    should_exit=true
                    PHASE_ATTEMPT_IN_PROGRESS=false
                    save_state_or_exit "consensus reviewer budget exhausted"
                    break
                fi

                request_check_generation || true
                if is_true "${ENGINE_PERMANENT_FAILURE:-false}"; then
                    err "$ENGINE_PERMANENT_FAILURE_REASON"
                    should_exit=true
                    PHASE_ATTEMPT_IN_PROGRESS=false
                    break
                fi
                if is_true "$REQUEST_REFRESH_REQUIRED"; then
                    phase_next_target=plan
                    phase_route=true
                    phase_route_reason='human requests changed; refresh PLAN'
                    request_checkpoint_plan_refresh "$phase" "$phase_attempt"
                    break
                fi

                if [ "${#phase_failures[@]}" -eq 0 ]; then
                    if ! guard_operator_inputs; then
                        phase_failures+=("protected operator objective, consent or gate definitions changed")
                    elif ! phase_capture_worktree_manifest "$manifest_after_file"; then
                        phase_failures+=("could not capture the final reviewed tree")
                    else
                        shell_note_local_work "$manifest_before_file" "$manifest_after_file"
                        record_phase_owned_paths "$manifest_before_file" "$manifest_after_file" || phase_failures+=("could not persist reviewed phase ownership")
                        if [ "$phase" != plan ]; then
                            if ! refresh_shell_gates; then
                                phase_failures+=("protected verification inputs changed")
                            elif ! run_shell_gates "$phase"; then
                                if [ "$SHELL_GATES_STATUS" != absent ] || [ "$phase" != build ]; then
                                    phase_failures+=("${SHELL_GATES_FAILURE:-shell verification failed}")
                                fi
                            fi
                        fi
                    fi
                fi

                request_check_generation || true
                if is_true "${ENGINE_PERMANENT_FAILURE:-false}"; then
                    err "$ENGINE_PERMANENT_FAILURE_REASON"
                    should_exit=true
                    PHASE_ATTEMPT_IN_PROGRESS=false
                    break
                fi
                if is_true "$REQUEST_REFRESH_REQUIRED"; then
                    phase_next_target=plan
                    phase_route=true
                    phase_route_reason='human requests changed; refresh PLAN'
                    request_checkpoint_plan_refresh "$phase" "$phase_attempt"
                    break
                fi

                if [ "${#phase_failures[@]}" -eq 0 ] && is_true "$AUTO_COMMIT_SESSION_ENABLED"; then
                    phase_commit_target="${LAST_CONSENSUS_NEXT_PHASE:-$(phase_default_next "$phase")}"
                    [ -n "$phase_commit_target" ] || phase_commit_target="$(phase_default_next "$phase")"
                    if ! commit_phase_approved_changes "$phase" "$phase_commit_target" "$manifest_before_file" "$manifest_after_file"; then
                        phase_failures+=("auto commit failed after $phase gate approval")
                        phase_failures+=("configure git user.name/user.email or disable auto commit")
                    fi
                    if ! session_work_is_saved; then
                        PHASE_SAVE_REQUIRED=true
                        PHASE_SAVE_OK=false
                        PHASE_SAVE_REASON="$SHELL_GATES_FAILURE"
                    fi
                    if is_true "$PHASE_SAVE_REQUIRED" && ! is_true "$PHASE_SAVE_OK"; then
                        warn "Phase $phase was verified but not saved: $PHASE_SAVE_REASON"
                        write_gate_feedback "$phase" "phase work was not saved: $PHASE_SAVE_REASON"
                        log_reason_code RB_PHASE_UNSAVED "$phase: $PHASE_SAVE_REASON"
                        should_exit=true
                        PHASE_ATTEMPT_IN_PROGRESS=false
                        save_state_or_exit "unsaved phase checkpoint"
                        break
                    fi
                fi

                request_check_generation || true
                if is_true "${ENGINE_PERMANENT_FAILURE:-false}"; then
                    err "$ENGINE_PERMANENT_FAILURE_REASON"
                    should_exit=true
                    PHASE_ATTEMPT_IN_PROGRESS=false
                    break
                fi
                if is_true "$REQUEST_REFRESH_REQUIRED"; then
                    phase_next_target=plan
                    phase_route=true
                    phase_route_reason='human requests changed; refresh PLAN'
                    request_checkpoint_plan_refresh "$phase" "$phase_attempt"
                    break
                fi

                if [ "${#phase_failures[@]}" -gt 0 ]; then
                    cumulative_phase_failures=("${phase_failures[@]}")
                    if is_true "$CONSENSUS_NO_ENGINES"; then
                        warn "Consensus unavailable: no healthy reviewer engines; will retry within phase budget."
                        log_reason_code "RB_CONSENSUS_ENGINES_UNAVAILABLE" "no healthy reviewer engines for consensus in phase $phase"
                        notify_event "phase_blocked" "hold" "phase=$phase attempt=$phase_attempt reason=consensus_engines_unavailable" || true
                    fi
                    if [ "$consensus_evaluated" = "true" ] && [ "${LAST_CONSENSUS_RESPONDED_VOTES:-0}" -gt 0 ] && is_phase_or_done "$LAST_CONSENSUS_NEXT_PHASE" && [ "$LAST_CONSENSUS_NEXT_PHASE" != "$phase" ]; then
                        local phase_route_candidate phase_route_candidate_index
                        phase_route_candidate="$LAST_CONSENSUS_NEXT_PHASE"
                        phase_route_candidate_index="$(phase_index_or_done "$phase_route_candidate")"
                        # On failed attempts, only allow backtracking reroutes by default.
                        # A terminal reroute is allowed only when all successful reviewers
                        # unanimously say the project is done and the worktree is clean; the
                        # usual done prerequisites below can still remap it to lint/document/plan.
                        if consensus_clean_terminal_hold_reroute_allowed "$phase" "$phase_route_candidate"; then
                            local guarded_route_candidate
                            local raw_guarded_route_candidate
                            guarded_route_candidate="$phase_route_candidate"
                            raw_guarded_route_candidate="$guarded_route_candidate"
                            enforce_phase_route_prerequisites "$phase" "$guarded_route_candidate" >/dev/null
                            guarded_route_candidate="${LAST_PHASE_ROUTE_GUARD_NEXT_PHASE:-$guarded_route_candidate}"
                            if [ -n "${LAST_PHASE_ROUTE_GUARD_REASON:-}" ] && [ "$guarded_route_candidate" != "$raw_guarded_route_candidate" ]; then
                                phase_route_reason="${LAST_PHASE_ROUTE_GUARD_REASON:-phase route guard remap}"
                            else
                                phase_route_reason="${LAST_CONSENSUS_NEXT_PHASE_REASON:-no explicit phase-routing rationale}"
                            fi
                            enforce_terminal_done_requirements "$phase" "$guarded_route_candidate" >/dev/null
                            phase_next_target="${LAST_DONE_GUARD_NEXT_PHASE:-$guarded_route_candidate}"
                            if [ "$phase_next_target" != "$guarded_route_candidate" ]; then
                                if [ -n "$phase_route_reason" ]; then
                                    phase_route_reason="${phase_route_reason}; ${LAST_DONE_GUARD_REASON:-terminal guard remap}"
                                else
                                    phase_route_reason="${LAST_DONE_GUARD_REASON:-terminal guard remap}"
                                fi
                            fi
                            phase_route="true"
                            record_gate_decision "$phase" "$phase_attempt" "$phase-gate" "reroute-terminal" "$phase_next_target" "$phase_route_reason"
                            phase_transition_history_append "$phase" "$phase_attempt" "$phase_next_target" "hold" "$phase_route_reason"
                            info "Allowing clean terminal reroute recommendation '$phase_route_candidate' from phase '$phase' after unanimous reviewer agreement."
                            notify_event "phase_decision" "reroute_terminal" "phase=$phase attempt=$phase_attempt rerouted_to=$phase_next_target reason=${phase_route_reason:-none}" || true
                            PHASE_ATTEMPT_IN_PROGRESS="false"
                            CURRENT_PHASE_ATTEMPT=1
                            save_state_or_exit "phase terminal reroute checkpoint ($phase->$phase_next_target)"
                            break
                        elif is_number "$phase_route_candidate_index" && [ "$phase_route_candidate_index" -ge 0 ] && [ "$phase_route_candidate_index" -lt "$phase_index" ]; then
                            phase_next_target="$phase_route_candidate"
                            phase_route="true"
                            phase_route_reason="${LAST_CONSENSUS_NEXT_PHASE_REASON:-no explicit phase-routing rationale}"
                            record_gate_decision "$phase" "$phase_attempt" "$phase-gate" "reroute-hold" "$phase_next_target" "$phase_route_reason"
                            phase_transition_history_append "$phase" "$phase_attempt" "$phase_next_target" "hold" "$phase_route_reason"
                            notify_event "phase_decision" "reroute_hold" "phase=$phase attempt=$phase_attempt rerouted_to=$phase_next_target reason=${phase_route_reason:-none}" || true
                            PHASE_ATTEMPT_IN_PROGRESS="false"
                            CURRENT_PHASE_ATTEMPT=1
                            save_state_or_exit "phase reroute-hold checkpoint ($phase->$phase_next_target)"
                            break
                        fi
                        phase_warnings+=("ignoring non-backtracking reroute recommendation '$phase_route_candidate' while phase '$phase' has unresolved failures")
                    fi
                    if [ "$phase" = "build" ] && [ "$phase_route" != "true" ] && is_true "$AUTO_PLAN_BACKFILL_ON_IDLE_BUILD" && [ "$PHASE_COMPLETION_MAX_ATTEMPTS" -gt 0 ] && [ "$phase_attempt" -ge "$PHASE_COMPLETION_MAX_ATTEMPTS" ]; then
                        local build_consensus_hold_detected="false"
                        local build_hold_reason="consensus HOLD"
                        # Prefer state booleans over log-string matching to detect consensus HOLD.
                        if [ "$consensus_evaluated" != "true" ]; then
                            build_consensus_hold_detected="true"
                            build_hold_reason="consensus not run"
                        elif is_true "$CONSENSUS_NO_ENGINES"; then
                            build_consensus_hold_detected="true"
                            build_hold_reason="no reviewer engines available"
                        elif [ "$LAST_CONSENSUS_PASS" = "false" ]; then
                            build_consensus_hold_detected="true"
                            build_hold_reason="consensus HOLD"
                        elif printf '%s\n' "${phase_failures[@]}" | grep -qiE '^consensus score/verdict: .*pass=false'; then
                            build_consensus_hold_detected="true"
                            build_hold_reason="consensus HOLD (log)"
                        fi
                        if is_true "$build_consensus_hold_detected"; then
                            phase_next_target="plan"
                            phase_route="true"
                            phase_route_reason="auto-backtrack: build exhausted retries on $build_hold_reason; refreshing plan scope"
                            record_gate_decision "$phase" "$phase_attempt" "$phase-gate" "reroute-hold" "$phase_next_target" "$phase_route_reason"
                            phase_transition_history_append "$phase" "$phase_attempt" "$phase_next_target" "hold" "$phase_route_reason"
                            write_gate_feedback "$phase" "${phase_failures[@]}" "auto-backtrack triggered: rerouting build -> plan"
                            warn "Build retries exhausted ($build_hold_reason); auto-backtracking to plan for scope refresh."
                            notify_event "phase_decision" "reroute_hold" "phase=$phase attempt=$phase_attempt rerouted_to=$phase_next_target reason=${phase_route_reason:-none}" || true
                            log_reason_code "RB_BUILD_AUTO_BACKTRACK_TO_PLAN" "$phase attempt $phase_attempt/$PHASE_COMPLETION_MAX_ATTEMPTS rerouted to plan after $build_hold_reason"
                            PHASE_ATTEMPT_IN_PROGRESS="false"
                            CURRENT_PHASE_ATTEMPT=1
                            save_state_or_exit "build auto-backtrack checkpoint"
                            break
                        fi
                    fi
                    write_gate_feedback "$phase" "${phase_failures[@]}"
                    for issue in "${phase_failures[@]}"; do
                        warn "$issue"
                    done
                    if [ "${#phase_warnings[@]}" -gt 0 ]; then
                        for issue in "${phase_warnings[@]+"${phase_warnings[@]}"}"; do
                            info "note: $issue"
                        done
                    fi
                    if is_number "$PHASE_WALLCLOCK_LIMIT_SECONDS" && [ "$PHASE_WALLCLOCK_LIMIT_SECONDS" -gt 0 ] && is_number "${phase_attempt_started_at:-0}" && [ "${phase_attempt_started_at:-0}" -gt 0 ]; then
                        local now elapsed
                        now="$(date +%s 2>/dev/null || echo 0)"
                        elapsed=$(( now - phase_attempt_started_at ))
                        if [ "$elapsed" -ge "$PHASE_WALLCLOCK_LIMIT_SECONDS" ]; then
                            warn "Phase $phase wall-clock guard (${PHASE_WALLCLOCK_LIMIT_SECONDS}s) tripped on attempt $phase_attempt; stopping retries."
                            log_reason_code "RB_PHASE_WALLCLOCK_EXCEEDED" "phase $phase attempt $phase_attempt exceeded wall-clock limit ${PHASE_WALLCLOCK_LIMIT_SECONDS}s (elapsed ${elapsed}s)"
                            notify_event "phase_blocked" "hold" "phase=$phase wallclock=${PHASE_WALLCLOCK_LIMIT_SECONDS}s elapsed=${elapsed}s" || true
                            PHASE_ATTEMPT_IN_PROGRESS="false"
                            save_state_or_exit "phase wallclock guard checkpoint ($phase)"
                            should_exit="true"
                            break
                        fi
                    fi
                    local failure_signature
                    local phase_stagnation_limit
                    failure_signature="$(phase_failure_signature "${phase_failures[@]+"${phase_failures[@]}"}")"
                    if [ "$failure_signature" = "$phase_stagnation_signature" ]; then
                        phase_stagnation_count=$((phase_stagnation_count + 1))
                    else
                        phase_stagnation_signature="$failure_signature"
                        phase_stagnation_count=1
                    fi
                    phase_stagnation_limit="${CONFIDENCE_STAGNATION_LIMIT:-$DEFAULT_CONFIDENCE_STAGNATION_LIMIT}"
                    is_number "$phase_stagnation_limit" || phase_stagnation_limit="$DEFAULT_CONFIDENCE_STAGNATION_LIMIT"
                    if [ "$phase_stagnation_limit" -lt 1 ]; then
                        phase_stagnation_limit=1
                    fi

                    log_reason_code "RB_PHASE_RETRYABLE_FAIL" "$phase attempt $phase_attempt/$(phase_attempt_limit_display "$PHASE_COMPLETION_MAX_ATTEMPTS"): ${phase_failures[*]}"
                    if [ "$PHASE_COMPLETION_MAX_ATTEMPTS" -eq 0 ] && [ "$phase_stagnation_count" -ge "$phase_stagnation_limit" ]; then
                        warn "Phase $phase stagnated for ${phase_stagnation_count} retries with no material failure signature change; stopping unlimited retry loop."
                        log_reason_code "RB_PHASE_RETRY_STAGNATION" "phase $phase stagnated after ${phase_stagnation_count} unlimited retries"
                        notify_event "phase_blocked" "hold" "phase=$phase unlimited retries stagnated after ${phase_stagnation_count} attempts" || true
                        should_exit="true"
                        PHASE_ATTEMPT_IN_PROGRESS="false"
                        save_state_or_exit "phase stagnation checkpoint ($phase)"
                        break
                    fi

                    phase_attempt=$((phase_attempt + 1))
                    if [ "$PHASE_COMPLETION_MAX_ATTEMPTS" -gt 0 ] && [ "$phase_attempt" -gt "$PHASE_COMPLETION_MAX_ATTEMPTS" ]; then
                        local auto_backtrack_target=""
                        local exhausted_attempt_count="$((phase_attempt - 1))"
                        if [ "$phase_route" != "true" ] && [ "$phase" != "plan" ]; then
                            auto_backtrack_target="$(phase_default_previous "$phase")"
                        fi
                        if [ -n "$auto_backtrack_target" ] && [ "$auto_backtrack_target" != "$phase" ]; then
                            phase_next_target="$auto_backtrack_target"
                            phase_route="true"
                            phase_route_reason="auto-backtrack: $phase exhausted retries (${exhausted_attempt_count}/${PHASE_COMPLETION_MAX_ATTEMPTS}); rerouting to $auto_backtrack_target for blocker resolution"
                            phase_transition_history_append "$phase" "$exhausted_attempt_count" "$phase_next_target" "hold" "$phase_route_reason"
                            write_gate_feedback "$phase" "${phase_failures[@]}" "auto-backtrack triggered: rerouting $phase -> $phase_next_target"
                            warn "Phase $phase exhausted retries (${exhausted_attempt_count}/${PHASE_COMPLETION_MAX_ATTEMPTS}); auto-backtracking to $phase_next_target."
                            notify_event "phase_decision" "reroute_hold" "phase=$phase attempt=$exhausted_attempt_count rerouted_to=$phase_next_target reason=${phase_route_reason:-none}" || true
                            log_reason_code "RB_PHASE_AUTO_BACKTRACK_RETRY_EXHAUSTED" "$phase attempt $exhausted_attempt_count/$PHASE_COMPLETION_MAX_ATTEMPTS rerouted to $phase_next_target after retry exhaustion"
                            PHASE_ATTEMPT_IN_PROGRESS="false"
                            CURRENT_PHASE_ATTEMPT=1
                            save_state_or_exit "phase retry exhaustion auto-backtrack checkpoint ($phase->$phase_next_target)"
                            break
                        fi
                        warn "Phase $phase blocked after ${PHASE_COMPLETION_MAX_ATTEMPTS} attempts."
                        format_retry_budget_block_reason "$phase" "$exhausted_attempt_count" "$PHASE_COMPLETION_MAX_ATTEMPTS"
                        notify_event "phase_blocked" "hold" "phase=$phase exhausted completion retries (${PHASE_COMPLETION_MAX_ATTEMPTS})" || true
                        should_exit="true"
                        PHASE_ATTEMPT_IN_PROGRESS="false"
                        CURRENT_PHASE_ATTEMPT="$PHASE_COMPLETION_MAX_ATTEMPTS"
                        save_state_or_exit "phase retry budget exhausted checkpoint ($phase)"
                        break
                    fi
                    CURRENT_PHASE_ATTEMPT="$phase_attempt"
                    PHASE_ATTEMPT_IN_PROGRESS="true"
                    save_state_or_exit "phase retry scheduling checkpoint ($phase attempt $phase_attempt)"
                    if is_true "$PHASE_COMPLETION_RETRY_VERBOSE"; then
                        warn "Phase $phase retrying in ${PHASE_COMPLETION_RETRY_DELAY_SECONDS}s (attempt ${phase_attempt}/$(phase_attempt_limit_display "$PHASE_COMPLETION_MAX_ATTEMPTS"))."
                    fi
                    sleep "$PHASE_COMPLETION_RETRY_DELAY_SECONDS"
                    continue
                fi

                if [ "${#phase_warnings[@]}" -gt 0 ]; then
                    for issue in "${phase_warnings[@]+"${phase_warnings[@]}"}"; do
                        info "note: $issue"
                    done
                fi

                if [ "$phase" = "plan" ]; then
                    record_plan_freshness_checkpoint || phase_warnings+=("plan freshness checkpoint could not be recorded; mtime fallback remains active")
                fi

                if is_number "$PHASE_WALLCLOCK_LIMIT_SECONDS" && [ "$PHASE_WALLCLOCK_LIMIT_SECONDS" -gt 0 ] && is_number "${phase_attempt_started_at:-0}" && [ "${phase_attempt_started_at:-0}" -gt 0 ]; then
                    local now elapsed
                    now="$(date +%s 2>/dev/null || echo 0)"
                    elapsed=$(( now - phase_attempt_started_at ))
                    if [ "$elapsed" -ge "$PHASE_WALLCLOCK_LIMIT_SECONDS" ]; then
                        warn "Phase $phase wall-clock guard (${PHASE_WALLCLOCK_LIMIT_SECONDS}s) tripped after successful attempt $phase_attempt; stopping before routing."
                        log_reason_code "RB_PHASE_WALLCLOCK_EXCEEDED" "phase $phase attempt $phase_attempt exceeded wall-clock limit ${PHASE_WALLCLOCK_LIMIT_SECONDS}s (elapsed ${elapsed}s)"
                        notify_event "phase_blocked" "hold" "phase=$phase wallclock=${PHASE_WALLCLOCK_LIMIT_SECONDS}s elapsed=${elapsed}s" || true
                        PHASE_ATTEMPT_IN_PROGRESS="false"
                        save_state_or_exit "phase wallclock guard checkpoint ($phase)"
                        should_exit="true"
                        break
                    fi
                fi

                local phase_requested_next
                local raw_phase_requested_next
                phase_requested_next="${LAST_CONSENSUS_NEXT_PHASE:-$(phase_default_next "$phase")}"
                [ -n "$phase_requested_next" ] || phase_requested_next="$(phase_default_next "$phase")"
                raw_phase_requested_next="$phase_requested_next"
                enforce_phase_route_prerequisites "$phase" "$phase_requested_next" >/dev/null
                phase_requested_next="${LAST_PHASE_ROUTE_GUARD_NEXT_PHASE:-$phase_requested_next}"
                if [ -n "${LAST_PHASE_ROUTE_GUARD_REASON:-}" ] && [ "$phase_requested_next" != "$raw_phase_requested_next" ]; then
                    local route_guard_reason
                    route_guard_reason="${LAST_PHASE_ROUTE_GUARD_REASON:-phase route guard remap}"
                    warn "Phase route guard remapped next phase: ${raw_phase_requested_next} -> ${phase_requested_next} (${route_guard_reason})."
                    notify_event "phase_decision" "route_guard_remap" "phase=$phase requested_next=${raw_phase_requested_next} remapped_next=${phase_requested_next} reason=${route_guard_reason}" || true
                    if [ -n "$phase_route_reason" ]; then
                        phase_route_reason="${phase_route_reason}; ${route_guard_reason}"
                    else
                        phase_route_reason="$route_guard_reason"
                    fi
                fi
                enforce_terminal_done_requirements "$phase" "$phase_requested_next" true >/dev/null
                phase_next_target="${LAST_DONE_GUARD_NEXT_PHASE:-$phase_requested_next}"
                if [ "$phase_next_target" != "$phase_requested_next" ]; then
                    local done_guard_reason
                    done_guard_reason="${LAST_DONE_GUARD_REASON:-terminal guard remap}"
                    warn "Terminal guard remapped next phase: ${phase_requested_next} -> ${phase_next_target} (${done_guard_reason})."
                    notify_event "phase_decision" "terminal_guard_remap" "phase=$phase requested_next=${phase_requested_next} remapped_next=${phase_next_target} reason=${done_guard_reason}" || true
                    if [ -n "$phase_route_reason" ]; then
                        phase_route_reason="${phase_route_reason}; ${done_guard_reason}"
                    else
                        phase_route_reason="$done_guard_reason"
                    fi
                fi
                if is_phase_or_done "$phase_next_target"; then
                    phase_route="true"
                    if [ -z "${phase_route_reason:-}" ]; then
                        phase_route_reason="${LAST_CONSENSUS_NEXT_PHASE_REASON:-no explicit phase-routing rationale}"
                    fi
                elif [ -z "$phase_route_reason" ]; then
                    phase_route_reason="no explicit phase-routing rationale"
                fi
                if ! request_lock_current; then
                    if is_true "$REQUEST_REFRESH_REQUIRED"; then
                        phase_next_target=plan
                        phase_route=true
                        phase_route_reason='human requests changed; refresh PLAN'
                        request_checkpoint_plan_refresh "$phase" "$phase_attempt"
                    else
                        err "${ENGINE_PERMANENT_FAILURE_REASON:-Could not validate the human-request queue.}"
                        should_exit=true
                        PHASE_ATTEMPT_IN_PROGRESS=false
                    fi
                    break
                fi
                record_gate_decision "$phase" "$phase_attempt" "$phase-gate" "pass" "$phase_next_target" "$phase_route_reason"
                phase_transition_history_append "$phase" "$phase_attempt" "$phase_next_target" "pass" "$phase_route_reason"
                REQUEST_REVIEWED_FINGERPRINT="$REQUEST_FROZEN_FINGERPRINT"
                PHASE_ATTEMPT_IN_PROGRESS="false"
                CURRENT_PHASE_ATTEMPT=1
                save_state_or_exit "phase completion checkpoint ($phase)"
                request_unlock || return 1
                ACTIVE_PHASE_MANIFEST_BEFORE=""

                success "Phase $phase completed."
                if is_true "$PLAN_ONLY" && [ "$phase" = plan ] && [ "$phase_next_target" != plan ]; then
                    CURRENT_PHASE=build
                    CURRENT_PHASE_INDEX=1
                    CURRENT_PHASE_ATTEMPT=1
                    PHASE_ATTEMPT_IN_PROGRESS=false
                    plan_only_completed=true
                    save_state_or_exit "planning-only completion checkpoint"
                    info "Planning complete; build was not authorized."
                    break 2
                fi
                notify_event "phase_complete" "go" "phase=$phase next=${phase_next_target:-unknown} route_reason=${phase_route_reason:-none}" || true
                break
            done
            if [ "$phase_route" = "true" ] && is_phase_or_done "$phase_next_target"; then
                local route_index
                local expected_next_phase expected_route_index
                expected_next_phase="$(phase_default_next "$phase")"
                expected_route_index="$(phase_index_or_done "$expected_next_phase")"
                route_index="$(phase_index_or_done "$phase_next_target")"
                if [ "$route_index" = "-1" ] || [ -z "$route_index" ]; then
                    route_index="$((phase_index + 1))"
                fi
                if [ "$phase_next_target" = "done" ] || [ "$route_index" -ne "$expected_route_index" ]; then
                    notify_event "phase_decision" "reroute_pass" "phase=$phase rerouted_to=$phase_next_target reason=${phase_route_reason:-none}" || true
                fi
                local route_is_plan_freshness
                route_is_plan_freshness="false"
                case "${phase_route_reason:-}" in
                    "plan refresh required:"*) route_is_plan_freshness="true" ;;
                esac
                if is_true "$route_is_plan_freshness"; then
                    routing_pair_cycle_key=""
                    routing_pair_cycle_count=0
                else
                    local current_pair_cycle_key
                    current_pair_cycle_key="$(phase_pair_cycle_key "$phase" "$phase_next_target" 2>/dev/null || true)"
                    if [ -n "$current_pair_cycle_key" ]; then
                        if [ "$current_pair_cycle_key" = "$routing_pair_cycle_key" ]; then
                            routing_pair_cycle_count=$((routing_pair_cycle_count + 1))
                        else
                            routing_pair_cycle_key="$current_pair_cycle_key"
                            routing_pair_cycle_count=1
                        fi
                        if [ "$PHASE_PAIR_CYCLE_LIMIT" -gt 0 ] && [ "$routing_pair_cycle_count" -ge "$PHASE_PAIR_CYCLE_LIMIT" ]; then
                            warn "PHASE ROUTING LOOP DETECTED: Ralphie crossed ${routing_pair_cycle_key} ${routing_pair_cycle_count} consecutive times."
                            warn "Stopping instead of spinning. Resolve the blocker causing ${phase} -> ${phase_next_target}, then resume."
                            log_reason_code "RB_PHASE_PAIR_ROUTING_LOOP" "phase pair ${routing_pair_cycle_key} repeated ${routing_pair_cycle_count}/${PHASE_PAIR_CYCLE_LIMIT} consecutive crossings; last route ${phase}->${phase_next_target}: ${phase_route_reason:-no explicit rationale}"
                            write_gate_feedback "$phase" "phase-pair routing loop detected: ${routing_pair_cycle_key} repeated ${routing_pair_cycle_count}/${PHASE_PAIR_CYCLE_LIMIT}" "last route: ${phase} -> ${phase_next_target}" "reason: ${phase_route_reason:-no explicit rationale}"
                            notify_event "session_error" "phase_pair_routing_loop" "pair=${routing_pair_cycle_key} count=${routing_pair_cycle_count}/${PHASE_PAIR_CYCLE_LIMIT} last=${phase}->${phase_next_target}" || true
                            should_exit="true"
                            PHASE_ATTEMPT_IN_PROGRESS="false"
                            save_state_or_exit "phase-pair routing loop checkpoint ($phase->$phase_next_target)"
                            break
                        fi
                    else
                        routing_pair_cycle_key=""
                        routing_pair_cycle_count=0
                    fi
                fi
                if [ "$route_index" -le "$phase_index" ]; then
                    if is_true "$route_is_plan_freshness"; then
                        routing_stagnation_signature=""
                        routing_stagnation_count=0
                        info "Plan freshness reroute will not count as consensus routing stagnation."
                    else
                        consensus_route_count=$((consensus_route_count + 1))
                        local routing_signature
                        routing_signature="$(phase_failure_signature "$phase" "$phase_next_target" "${phase_route_reason:-none}")"
                        if [ "$routing_signature" = "$routing_stagnation_signature" ]; then
                            routing_stagnation_count=$((routing_stagnation_count + 1))
                        else
                            routing_stagnation_signature="$routing_signature"
                            routing_stagnation_count=1
                        fi
                        if [ "$MAX_CONSENSUS_ROUTING_ATTEMPTS" -gt 0 ] && [ "$consensus_route_count" -gt "$MAX_CONSENSUS_ROUTING_ATTEMPTS" ]; then
                            warn "Consensus routing attempts exceeded limit ($consensus_route_count/$MAX_CONSENSUS_ROUTING_ATTEMPTS)."
                            log_reason_code "RB_ROUTING_BUDGET_EXCEEDED" "consensus routing attempts exceeded limit ($consensus_route_count/$MAX_CONSENSUS_ROUTING_ATTEMPTS)"
                            notify_event "session_error" "routing_budget_exceeded" "consensus routing attempts exceeded limit ($consensus_route_count/$MAX_CONSENSUS_ROUTING_ATTEMPTS)" || true
                            should_exit="true"
                            PHASE_ATTEMPT_IN_PROGRESS="false"
                            save_state_or_exit "routing budget checkpoint ($phase->$phase_next_target)"
                            break
                        fi
                        if [ "$MAX_CONSENSUS_ROUTING_ATTEMPTS" -eq 0 ] && [ "$routing_stagnation_count" -ge "$CONFIDENCE_STAGNATION_LIMIT" ]; then
                            warn "Consensus routing stagnated for ${routing_stagnation_count} backtracks with unchanged route signature."
                            log_reason_code "RB_ROUTING_STAGNATION" "unlimited routing stagnated after ${routing_stagnation_count} backtracks ($phase->$phase_next_target)"
                            notify_event "session_error" "routing_stagnation" "unlimited routing stagnated after ${routing_stagnation_count} backtracks" || true
                            should_exit="true"
                            PHASE_ATTEMPT_IN_PROGRESS="false"
                            save_state_or_exit "routing stagnation checkpoint ($phase->$phase_next_target)"
                            break
                        fi
                    fi
                fi
                if [ "$phase_next_target" = "done" ] || [ "$route_index" -ge "${#phases[@]}" ]; then
                    start_phase_index="${#phases[@]}"
                    phase_index="${#phases[@]}"
                else
                    warn "Adaptive phase routing: $phase -> $phase_next_target (${phase_route_reason:-no explicit rationale})."
                    start_phase_index="$route_index"
                    phase_index=$((route_index - 1))
                fi
            fi
        done
        # If the phase loop naturally reached the end without an explicit reroute,
        # mark terminal completion so the outer loop exits deterministically.
        if ! is_true "$should_exit" && [ "$phase_index" -ge "${#phases[@]}" ] && [ "$start_phase_index" -lt "${#phases[@]}" ]; then
            start_phase_index="${#phases[@]}"
        fi
        if is_true "$should_exit" || is_true "$plan_only_completed"; then
            break
        fi
        # If start_phase_index is past all phases (consensus routed to "done"
        # or natural completion of all phases), exit the outer loop
        if [ "$start_phase_index" -ge "${#phases[@]}" ]; then
            if ! shell_terminal_verified; then
                if is_true "$REQUEST_REFRESH_REQUIRED" && ! is_true "${ENGINE_PERMANENT_FAILURE:-false}"; then
                    request_checkpoint_plan_refresh "$CURRENT_PHASE" "$CURRENT_PHASE_ATTEMPT"
                    start_phase_index=0
                    continue
                fi
                err "Final accepted tree is not verified: ${SHELL_GATES_FAILURE:-protected input changed}"
                log_reason_code RB_FINAL_VERIFICATION_FAILED "${SHELL_GATES_FAILURE:-protected input changed}"
                should_exit=true
                CURRENT_PHASE=test
                CURRENT_PHASE_INDEX=2
                PHASE_ATTEMPT_IN_PROGRESS=false
                break
            fi
            if ! request_lock_current; then
                if is_true "$REQUEST_REFRESH_REQUIRED"; then
                    request_checkpoint_plan_refresh "$CURRENT_PHASE" "$CURRENT_PHASE_ATTEMPT"
                    start_phase_index=0
                    continue
                fi
                err "${ENGINE_PERMANENT_FAILURE_REASON:-Could not validate the human-request queue.}"
                should_exit=true
                break
            fi
            CURRENT_PHASE="done"
            CURRENT_PHASE_INDEX="${#phases[@]}"
            CURRENT_PHASE_ATTEMPT=1
            PHASE_ATTEMPT_IN_PROGRESS="false"
            save_state_or_exit "session completion checkpoint"
            request_unlock || return 1
            info "All phases completed. Session done."
            notify_event "session_done" "ok" "all phases completed successfully" || true
            break
        fi
        if [ "$MAX_ITERATIONS" -gt 0 ] && [ "$ITERATION_COUNT" -ge "$MAX_ITERATIONS" ]; then
            log_reason_code "RB_ITERATION_BUDGET_REACHED" "run iteration budget reached at $ITERATION_COUNT"
            notify_event "session_error" "iteration_budget_reached" "iteration budget reached at $ITERATION_COUNT/$MAX_ITERATIONS" || true
            break
        fi
    done

    if is_true "$should_exit"; then
        notify_event "session_error" "stopped" "session exited before full completion; see $(path_for_display "$REASON_LOG_FILE")" || true
    fi
    save_state_or_exit "final session checkpoint"
    release_lock
    is_true "$plan_only_completed" && return 0
    [ "$CURRENT_PHASE" = done ] && ! is_true "$should_exit"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
