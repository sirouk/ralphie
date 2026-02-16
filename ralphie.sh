#!/usr/bin/env bash
#
# Ralphie - Unified autonomous loop for Codex and Claude Code.
# One script handles first-run setup, prompt generation, and iterative execution.
#

# Stream bootstrap:
# When executed via stdin (for example: curl ... | bash), persist the script into
# the current directory and re-exec from disk so relative paths work consistently.
if [ "${RALPHIE_LIB:-0}" != "1" ] && [ -z "${BASH_SOURCE[0]:-}" ]; then
    rb_target_script="$(pwd)/ralphie.sh"
    rb_tmp_script="${rb_target_script}.tmp.$$"
    if {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' '#'
        printf '%s\n' '# Ralphie - Unified autonomous loop for Codex and Claude Code.'
        printf '%s\n' '# Installed from stdin stream.'
        printf '%s\n' '#'
        cat
    } > "$rb_tmp_script"; then
        chmod +x "$rb_tmp_script" 2>/dev/null || true
        mv "$rb_tmp_script" "$rb_target_script"
        echo "Installed ralphie.sh to $rb_target_script"
        exec env RALPHIE_SKIP_AUTO_UPDATE=1 "$rb_target_script" "$@"
    else
        echo "Failed to persist streamed ralphie.sh to $rb_target_script" >&2
        rm -f "$rb_tmp_script"
        exit 1
    fi
fi

set -euo pipefail

SCRIPT_VERSION="1.0.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

CONFIG_DIR="$PROJECT_DIR/.ralphie"
CONFIG_FILE="$CONFIG_DIR/config.env"
LOCK_FILE="$CONFIG_DIR/run.lock"
REASON_LOG_FILE="$CONFIG_DIR/reasons.log"
GATE_FEEDBACK_FILE="$CONFIG_DIR/last_gate_feedback.md"
STATE_FILE="$CONFIG_DIR/state.env"
DEFAULT_AUTO_UPDATE_URL="https://raw.githubusercontent.com/sirouk/ralphie/refs/heads/master/ralphie.sh"

SPECIFY_DIR="$PROJECT_DIR/.specify/memory"
CONSTITUTION_FILE="$SPECIFY_DIR/constitution.md"
SPECS_DIR="$PROJECT_DIR/specs"
RESEARCH_DIR="$PROJECT_DIR/research"
RESEARCH_SUMMARY_FILE="$RESEARCH_DIR/RESEARCH_SUMMARY.md"
CONSENSUS_DIR="$PROJECT_DIR/consensus"
LOG_DIR="$PROJECT_DIR/logs"
COMPLETION_LOG_DIR="$PROJECT_DIR/completion_log"
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
SETUP_SUBREPOS_SCRIPT="$PROJECT_DIR/scripts/setup-agent-subrepos.sh"

PROMPT_BUILD_FILE="$PROJECT_DIR/PROMPT_build.md"
PROMPT_PLAN_FILE="$PROJECT_DIR/PROMPT_plan.md"
PROMPT_TEST_FILE="$PROJECT_DIR/PROMPT_test.md"
PROMPT_REFACTOR_FILE="$PROJECT_DIR/PROMPT_refactor.md"
PROMPT_LINT_FILE="$PROJECT_DIR/PROMPT_lint.md"
PROMPT_DOCUMENT_FILE="$PROJECT_DIR/PROMPT_document.md"
PLAN_FILE="$PROJECT_DIR/IMPLEMENTATION_PLAN.md"

# Shared logic for interactive questions and formatting.
err() { echo -e "\033[1;31m$*\033[0m" >&2; }
warn() { echo -e "\033[1;33m$*\033[0m" >&2; }
info() { echo -e "\033[0;34m$*\033[0m"; }
success() { echo -e "\033[0;32m$*\033[0m"; }
ok() { success "$@"; }

# Logging reasons for failures (doctrinal/state/inference)
log_reason_code() {
    local code="$1"
    local msg="$2"
    mkdir -p "$(dirname "$REASON_LOG_FILE")"
    echo "reason_code=$code message=\"$msg\"" >> "$REASON_LOG_FILE"
}

path_for_display() {
    local p="${1:-}"
    [ -z "$p" ] && echo "unknown" && return 0
    echo "${p#./}"
}

# Boolean helper
is_true() {
    case "${1:-}" in
        1|[Yy]|[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|ON|on) return 0 ;;
        *) return 1 ;;
    esac
}

is_number() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Global Registry for Background Processes (for atomic cleanup)
declare -a RALPHIE_BG_PIDS=()

# Configuration defaults
DEFAULT_ENGINE="claude"
DEFAULT_CODEX_CMD="codex"
DEFAULT_CLAUDE_CMD="claude"
DEFAULT_YOLO="true"
DEFAULT_AUTO_UPDATE="true"
DEFAULT_COMMAND_TIMEOUT_SECONDS=0 # 0 means disabled
DEFAULT_MAX_ITERATIONS=0          # 0 means infinite
DEFAULT_RALPHIE_QUALITY_LEVEL="standard" # minimal|standard|high
DEFAULT_RUN_AGENT_MAX_ATTEMPTS=3
DEFAULT_RUN_AGENT_RETRY_DELAY_SECONDS=5
DEFAULT_RUN_AGENT_RETRY_VERBOSE="true"
DEFAULT_PHASE_COMPLETION_MAX_ATTEMPTS=3
DEFAULT_PHASE_COMPLETION_RETRY_DELAY_SECONDS=5
DEFAULT_PHASE_COMPLETION_RETRY_VERBOSE="true"

# Load configuration from environment or file.
COMMAND_TIMEOUT_SECONDS="${COMMAND_TIMEOUT_SECONDS:-$DEFAULT_COMMAND_TIMEOUT_SECONDS}"
MAX_ITERATIONS="${MAX_ITERATIONS:-$DEFAULT_MAX_ITERATIONS}"
YOLO="${YOLO:-$DEFAULT_YOLO}"
AUTO_UPDATE="${AUTO_UPDATE:-$DEFAULT_AUTO_UPDATE}"
RALPHIE_QUALITY_LEVEL="${RALPHIE_QUALITY_LEVEL:-$DEFAULT_RALPHIE_QUALITY_LEVEL}"
SWARM_MAX_PARALLEL="${SWARM_MAX_PARALLEL:-2}"
CONFIDENCE_TARGET="${CONFIDENCE_TARGET:-85}"
CONFIDENCE_STAGNATION_LIMIT="${CONFIDENCE_STAGNATION_LIMIT:-3}"
AUTO_PLAN_BACKFILL_ON_IDLE_BUILD="${AUTO_PLAN_BACKFILL_ON_IDLE_BUILD:-true}"
RUN_AGENT_MAX_ATTEMPTS="${RUN_AGENT_MAX_ATTEMPTS:-$DEFAULT_RUN_AGENT_MAX_ATTEMPTS}"
RUN_AGENT_RETRY_DELAY_SECONDS="${RUN_AGENT_RETRY_DELAY_SECONDS:-$DEFAULT_RUN_AGENT_RETRY_DELAY_SECONDS}"
RUN_AGENT_RETRY_VERBOSE="${RUN_AGENT_RETRY_VERBOSE:-$DEFAULT_RUN_AGENT_RETRY_VERBOSE}"
PHASE_COMPLETION_MAX_ATTEMPTS="${PHASE_COMPLETION_MAX_ATTEMPTS:-$DEFAULT_PHASE_COMPLETION_MAX_ATTEMPTS}"
PHASE_COMPLETION_RETRY_DELAY_SECONDS="${PHASE_COMPLETION_RETRY_DELAY_SECONDS:-$DEFAULT_PHASE_COMPLETION_RETRY_DELAY_SECONDS}"
PHASE_COMPLETION_RETRY_VERBOSE="${PHASE_COMPLETION_RETRY_VERBOSE:-$DEFAULT_PHASE_COMPLETION_RETRY_VERBOSE}"

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

# Override with environment variables if present.
ACTIVE_ENGINE="${RALPHIE_ENGINE:-$DEFAULT_ENGINE}"
CODEX_CMD="${CODEX_ENGINE_CMD:-$DEFAULT_CODEX_CMD}"
CLAUDE_CMD="${CLAUDE_ENGINE_CMD:-$DEFAULT_CLAUDE_CMD}"
YOLO="${RALPHIE_YOLO:-$YOLO}"
AUTO_UPDATE="${RALPHIE_AUTO_UPDATE:-$AUTO_UPDATE}"
AUTO_UPDATE_URL="${RALPHIE_AUTO_UPDATE_URL:-$DEFAULT_AUTO_UPDATE_URL}"
if [ "$ACTIVE_ENGINE" = "codex" ]; then
    ACTIVE_CMD="$CODEX_CMD"
else
    ACTIVE_CMD="$CLAUDE_CMD"
fi

if [ "$ACTIVE_ENGINE" = "auto" ]; then
    if command -v "$CODEX_CMD" >/dev/null 2>&1; then
        ACTIVE_ENGINE="codex"
        ACTIVE_CMD="$CODEX_CMD"
    elif command -v "$CLAUDE_CMD" >/dev/null 2>&1; then
        ACTIVE_ENGINE="claude"
        ACTIVE_CMD="$CLAUDE_CMD"
    fi
fi

# Runtime State variables (these change during the loop)
CURRENT_PHASE="plan"
ITERATION_COUNT=0
SESSION_ID="$(date +%Y%m%d_%H%M%S)"

# Capability Probing results (populated by probe_engine_capabilities)
CLAUDE_CAP_PRINT=0
CLAUDE_CAP_YOLO_FLAG=""
CODEX_CAP_OUTPUT_LAST_MESSAGE=0
CODEX_CAP_YOLO_FLAG=0

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
save_state() {
    mkdir -p "$(dirname "$STATE_FILE")"
    cat <<EOF > "$STATE_FILE"
CURRENT_PHASE="$CURRENT_PHASE"
ITERATION_COUNT="$ITERATION_COUNT"
SESSION_ID="$SESSION_ID"
EOF
    # Append SHA-256 checksum to the end
    local checksum
    checksum="$(shasum -a 256 "$STATE_FILE" | cut -d' ' -f1)"
    echo "STATE_CHECKSUM=\"$checksum\"" >> "$STATE_FILE"
}

load_state() {
    if [ ! -f "$STATE_FILE" ]; then return 1; fi
    
    # Verify checksum if present
    if grep -q "STATE_CHECKSUM=" "$STATE_FILE"; then
        local expected
        expected="$(grep "STATE_CHECKSUM=" "$STATE_FILE" | cut -d'"' -f2)"
        local actual
        actual="$(grep -v "STATE_CHECKSUM=" "$STATE_FILE" | shasum -a 256 | cut -d' ' -f1)"
        if [ "$expected" != "$actual" ]; then
            warn "State file checksum mismatch! Corruption detected. Forcing clean state."
            log_reason_code "RB_STATE_CORRUPTION" "checksum mismatch in state file"
            return 1
        fi
    fi

    # shellcheck disable=SC1090
    source "$STATE_FILE"
    return 0
}

# Tag Extraction Helpers
extract_tag_value() {
    local tag="$1"
    local output_file="$2"
    local log_file="$3"
    local value=""
    
    if [ -f "$output_file" ]; then
        value="$(grep -oE "<$tag>.*</$tag>" "$output_file" | sed -E "s/<\/?$tag>//g" | tail -n1)"
    fi
    if [ -z "$value" ] && [ -f "$log_file" ]; then
        value="$(grep -oE "<$tag>.*</$tag>" "$log_file" | sed -E "s/<\/?$tag>//g" | tail -n1)"
    fi
    echo "$value"
}

extract_confidence_value() {
    local val
    val="$(extract_tag_value "confidence" "$1" "$2")"
    if ! is_number "$val"; then echo "0"; return; fi
    if [ "$val" -gt 100 ]; then echo "100"; else echo "$val"; fi
}

extract_needs_human_flag() {
    extract_tag_value "needs_human" "$1" "$2"
}

extract_human_question() {
    extract_tag_value "human_question" "$1" "$2"
}

output_has_plan_status_tags() {
    local output_file="$1"
    [ -f "$output_file" ] || return 1
    grep -q "<confidence>" "$output_file" && grep -q "<needs_human>" "$output_file" && grep -q "<human_question>" "$output_file"
}

# Interactive Questions
prompt_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local response
    if [ -t 0 ]; then
        read -rp "$prompt [Y/n]: " response
    else
        response=""
    fi
    case "${response:-$default}" in
        [Yy]*) echo "true"; return 0 ;;
        *) echo "false"; return 1 ;;
    esac
}

prompt_line() {
    local prompt="$1"
    local default="$2"
    local response
    if [ -t 0 ]; then
        read -rp "$prompt [$default]: " response
    else
        response=""
    fi
    echo "${response:-$default}"
}

prompt_optional_line() {
    local prompt="$1"
    local default="${2:-}"
    local response
    if [ -t 0 ]; then
        read -rp "$prompt: " response
    else
        response=""
    fi
    echo "${response:-$default}"
}

# Multi-Agent Capability Detection
probe_engine_capabilities() {
    # Probing Claude Code
    if command -v "$CLAUDE_CMD" >/dev/null 2>&1; then
        local claude_help
        claude_help="$("$CLAUDE_CMD" --help 2>&1 || true)"
        if echo "$claude_help" | grep -qE -- "-p, --print"; then
            CLAUDE_CAP_PRINT=1
        fi
        if echo "$claude_help" | grep -qE -- "--dangerously-skip-permissions"; then
            CLAUDE_CAP_YOLO_FLAG="--dangerously-skip-permissions"
        fi
    fi

    # Probing Codex
    if command -v "$CODEX_CMD" >/dev/null 2>&1; then
        local codex_help
        codex_help="$("$CODEX_CMD" exec --help 2>&1 || true)"
        if echo "$codex_help" | grep -qE -- "--output-last-message"; then
            CODEX_CAP_OUTPUT_LAST_MESSAGE=1
        fi
        if echo "$codex_help" | grep -qE -- "--dangerously-bypass-approvals-and-sandbox"; then
            CODEX_CAP_YOLO_FLAG=1
        fi
    fi
}

# Lock Management
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local holder_pid
        holder_pid="$(cat "$LOCK_FILE" | head -n1)"
        if [ -n "$holder_pid" ] && kill -0 "$holder_pid" 2>/dev/null; then
            err "Orchestrator already running with PID $holder_pid."
            log_reason_code "RB_LOCK_ALREADY_HELD" "pid $holder_pid active"
            return 1
        else
            warn "Stale lock file found. Reclaiming."
        fi
    fi
    mkdir -p "$(dirname "$LOCK_FILE")"
    echo "$$" > "$LOCK_FILE"
    date '+%Y-%m-%d %H:%M:%S' >> "$LOCK_FILE"
    return 0
}

release_lock() {
    rm -f "$LOCK_FILE"
}

# Interrupt handling
cleanup() {
    info "Received interrupt. Cleaning up background processes..."
    for pid in ${RALPHIE_BG_PIDS[@]+"${RALPHIE_BG_PIDS[@]}"}; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
    release_lock
    exit 0
}
trap cleanup SIGINT SIGTERM

# Unified Agent Run Function with Exponential Backoff Retries
get_timeout_command() {
    if command -v timeout >/dev/null 2>&1; then echo "timeout"; elif command -v gtimeout >/dev/null 2>&1; then echo "gtimeout"; fi
}

run_agent_with_prompt() {
    local prompt_file="$1"
    local log_file="$2"
    local output_file="$3"
    local yolo_effective="$4"
    local timeout_cmd=""
    local exit_code=0
    local -a engine_args=()
    local -a yolo_prefix=()

    if [ ! -f "$prompt_file" ]; then
        err "Prompt file not found: $prompt_file"
        return 2
    fi
    if [ -z "${ACTIVE_CMD:-}" ] || ! command -v "$ACTIVE_CMD" >/dev/null 2>&1; then
        err "Active engine command unavailable: ${ACTIVE_CMD:-<unset>}"
        return 2
    fi

    if [ "$COMMAND_TIMEOUT_SECONDS" -gt 0 ]; then
        timeout_cmd="$(get_timeout_command)"
    fi

    probe_engine_capabilities

    if [ "$ACTIVE_ENGINE" = "codex" ]; then
        if ! is_true "$CODEX_CAP_OUTPUT_LAST_MESSAGE"; then
            err "Codex capability missing: --output-last-message is required."
            return 2
        fi

        engine_args=("$ACTIVE_CMD" "exec")
        [ -n "${CODEX_MODEL:-}" ] && engine_args+=("--model" "$CODEX_MODEL")
        
        if is_true "$yolo_effective" && is_true "$CODEX_CAP_YOLO_FLAG"; then
            engine_args+=("--dangerously-bypass-approvals-and-sandbox")
        fi
    else
        if ! is_true "$CLAUDE_CAP_PRINT"; then
            err "Claude capability missing: print mode is required."
            return 2
        fi

        engine_args=("$ACTIVE_CMD" "-p")
        [ -n "${CLAUDE_MODEL:-}" ] && engine_args+=("--model" "$CLAUDE_MODEL")
        
        if is_true "$yolo_effective"; then
            [ -n "$CLAUDE_CAP_YOLO_FLAG" ] && engine_args+=("$CLAUDE_CAP_YOLO_FLAG")
            yolo_prefix=("env" "IS_SANDBOX=1")
        fi
    fi

    local attempt=1
    local max_run_attempts="${RUN_AGENT_MAX_ATTEMPTS}"
    local retry_delay="${RUN_AGENT_RETRY_DELAY_SECONDS}"
    if ! is_number "$max_run_attempts" || [ "$max_run_attempts" -lt 1 ]; then
        max_run_attempts=3
    fi
    if ! is_number "$retry_delay" || [ "$retry_delay" -lt 0 ]; then
        retry_delay=5
    fi

    while [ "$attempt" -le "$max_run_attempts" ]; do
        if [ "$ACTIVE_ENGINE" = "codex" ]; then
            if [ -n "$timeout_cmd" ]; then
                if cat "$prompt_file" | "$timeout_cmd" "$COMMAND_TIMEOUT_SECONDS" "${engine_args[@]}" - --output-last-message "$output_file" 2>&1 | tee "$log_file"; then
                    exit_code=0; break
                else
                    exit_code=$?
                fi
            else
                if cat "$prompt_file" | "${engine_args[@]}" - --output-last-message "$output_file" 2>&1 | tee "$log_file"; then
                    exit_code=0; break
                else
                    exit_code=$?
                fi
            fi
        else
            if [ -n "$timeout_cmd" ]; then
                if cat "$prompt_file" | "$timeout_cmd" "$COMMAND_TIMEOUT_SECONDS" ${yolo_prefix[@]+"${yolo_prefix[@]}"} "${engine_args[@]}" - 2>>"$log_file" | tee "$output_file" >> "$log_file"; then
                    exit_code=0; break
                else
                    exit_code=$?
                fi
            else
                if cat "$prompt_file" | ${yolo_prefix[@]+"${yolo_prefix[@]}"} "${engine_args[@]}" - 2>>"$log_file" | tee "$output_file" >> "$log_file"; then
                    exit_code=0; break
                else
                    exit_code=$?
                fi
            fi
        fi
        
        local hiccup_detected=false
        if grep -qiE "backend error|token error|timeout|connection refused|overloaded" "$log_file" 2>/dev/null; then
            hiccup_detected=true
        elif [ "$exit_code" -eq 124 ] || [ "$exit_code" -eq 137 ]; then
            hiccup_detected=true
        fi

        if is_true "$hiccup_detected" && [ "$attempt" -lt "$max_run_attempts" ]; then
            if is_true "$RUN_AGENT_RETRY_VERBOSE"; then
                warn "Inference hiccup detected on attempt $attempt/$max_run_attempts. Retrying in ${retry_delay}s..."
            fi
            sleep "$retry_delay"
            attempt=$((attempt + 1))
            continue
        fi
        break
    done

    return "$exit_code"
}

run_swarm_consensus() {
    local stage="$1"
    local count="$(get_reviewer_count)"
    local parallel="$(get_parallel_reviewer_count)"
    
    info "Running deep consensus swarm for '$stage'..."
    local consensus_dir="$CONSENSUS_DIR/$stage/$SESSION_ID"
    mkdir -p "$consensus_dir"

    local -a prompts=() logs=() outputs=() cmds=()
    for i in $(seq 1 "$count"); do
        prompts+=("$consensus_dir/reviewer_${i}_prompt.md")
        logs+=("$consensus_dir/reviewer_${i}.log")
        outputs+=("$consensus_dir/reviewer_${i}.out")
        local rcmd="$CLAUDE_CMD"
        [ $((i % 2)) -eq 1 ] && command -v "$CODEX_CMD" >/dev/null 2>&1 && rcmd="$CODEX_CMD"
        cmds+=("$rcmd")
        cat <<EOF > "${prompts[$((i-1))]}"
# Consensus Review: $stage
Analyze the recent logs and artifacts.
Produce a <score> (0-100) and a <verdict> (GO|HOLD).
EOF
    done

    local active=0
    for i in $(seq 0 $((count - 1))); do
        (
            ACTIVE_CMD="${cmds[$i]}"
            ACTIVE_ENGINE="$( [[ "${cmds[$i]}" == *"codex"* ]] && echo "codex" || echo "claude" )"
            run_agent_with_prompt "${prompts[$i]}" "${logs[$i]}" "${outputs[$i]}" "false"
        ) &
        RALPHIE_BG_PIDS+=($!)
        active=$((active + 1))
        if [ "$active" -ge "$parallel" ] || [ "$i" -eq $((count - 1)) ]; then
            wait -n 2>/dev/null || true
            active=$((active - 1))
        fi
    done
    wait

    local total_score=0 go_votes=0
    for ofile in "${outputs[@]}"; do
        local s
        local d
        s="$(grep -oE "<score>[0-9]{1,3}</score>" "$ofile" | sed 's/[^0-9]//g' | tail -n 1)"
        is_number "$s" || s="0"
        if grep -qE "<verdict>(GO|HOLD)</verdict>" "$ofile" 2>/dev/null; then
            d="$(grep -oE "<verdict>(GO|HOLD)</verdict>" "$ofile" | tail -n 1 | sed -E 's/<\/?verdict>//g' )"
        elif grep -qE "<decision>(GO|HOLD)</decision>" "$ofile" 2>/dev/null; then
            d="$(grep -oE "<decision>(GO|HOLD)</decision>" "$ofile" | tail -n 1 | sed -E 's/<\/?decision>//g' )"
        else
            d="HOLD"
        fi
        total_score=$((total_score + s))
        [ "$d" = "GO" ] && go_votes=$((go_votes + 1))
    done

    local avg_score=$((total_score / count))
    LAST_CONSENSUS_SCORE="$avg_score"
    if [ "$go_votes" -gt $((count / 2)) ] && [ "$avg_score" -ge 70 ]; then
        LAST_CONSENSUS_PASS=true
        return 0
    else
        LAST_CONSENSUS_PASS=false
        return 1
    fi
}

detect_completion_signal() {
    local log_file="$1"
    local output_file="$2"
    if grep -qiE "<promise>\s*DONE\s*</promise>" "$output_file" 2>/dev/null; then
        echo "<promise>DONE</promise>"; return 0
    fi
    if grep -qiE "<promise>\s*DONE\s*</promise>" "$log_file" 2>/dev/null; then
        echo "<promise>DONE</promise>"; return 0
    fi
    return 1
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
        if ! grep -qxF "$entry" "$gitignore_file"; then
            echo "$entry"
        fi
    done <<< "$required_entries"
}

file_has_local_identity_leakage() {
    local candidate_file="$1"
    if [ ! -f "$candidate_file" ]; then
        return 1
    fi

    local home_dir
    home_dir="${HOME:-}"

    if [ -n "$home_dir" ] && grep -qF "$home_dir" "$candidate_file" 2>/dev/null; then
        return 0
    fi
    if grep -qiE '(/Users/[A-Za-z0-9._-]+/)|(/home/[A-Za-z0-9._-]+/)|(/root/[A-Za-z0-9._-]+/)' "$candidate_file" 2>/dev/null; then
        return 0
    fi
    return 1
}

markdown_artifacts_are_clean() {
    local leakage_pattern='succeeded in [0-9]+ms:|assistant[[:space:]]+to=|recipient_name[[:space:]]*:|tokens used|mcp startup:'
    local file bad=0
    local files=()

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

    [ "$bad" -eq 0 ]
}

plan_is_semantically_actionable() {
    local plan_file="$1"
    [ -f "$plan_file" ] || return 1

    local has_goal=false
    local has_validation=false
    local task_count=0

    if grep -qiE '(^|#{1,6}[[:space:]]*)(goal|scope|objectives?|overview|context)\b|^[[:space:]]*(goal|scope|objectives?|overview|context)[[:space:]]*:' "$plan_file" 2>/dev/null; then
        has_goal=true
    fi
    if grep -qiE '(^|#{1,6}[[:space:]]*)(validation|verification|acceptance criteria|success criteria|definition of done|readiness|qa|testing)\b|^[[:space:]]*(validation|verification|acceptance criteria|success criteria|definition of done|readiness|qa|testing)[[:space:]]*:' "$plan_file" 2>/dev/null; then
        has_validation=true
    fi
    task_count="$(plan_task_count "$plan_file")"

    if is_true "$has_goal" && is_true "$has_validation" && [ "${task_count:-0}" -ge 1 ]; then
        return 0
    fi
    return 1
}

plan_task_count() {
    local plan_file="$1"
    if [ ! -f "$plan_file" ]; then
        echo "0"
        return 0
    fi
    local count
    count="$(grep -cE '^[[:space:]]*([0-9]+\.[[:space:]]|-[[:space:]]\[[ x]\][[:space:]]|-[[:space:]](Run|Add|Update|Implement|Fix|Verify|Test|Document|Research|Decide|Refactor|Remove|Deprecate)[[:space:]])' "$plan_file" 2>/dev/null || true)"
    if ! is_number "$count"; then
        count="0"
    fi
    echo "$count"
}

write_gate_feedback() {
    local stage="$1"
    shift
    mkdir -p "$(dirname "$GATE_FEEDBACK_FILE")"
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
    local missing=()
    local spec_count=0
    local research_count=0
    local has_acceptance=false
    local spec_file missing_entry

    spec_count=$(find "$SPECS_DIR" -maxdepth 3 -type f \( -name "spec.md" -o -name "*.md" \) 2>/dev/null | wc -l | tr -d ' ')
    if [ "${spec_count:-0}" -eq 0 ]; then
        missing+=("spec files under specs/")
    else
        local spec_candidates
        spec_candidates="$(find "$SPECS_DIR" -maxdepth 3 -type f \( -name "spec.md" -o -name "*.md" \) 2>/dev/null || true)"
        while IFS= read -r spec_file; do
            if [ -n "$spec_file" ] && grep -qi 'acceptance criteria' "$spec_file" 2>/dev/null; then
                has_acceptance=true
                break
            fi
        done <<< "$spec_candidates"
        if ! is_true "$has_acceptance"; then
            missing+=("specs must include Acceptance Criteria sections")
        fi
    fi

    if [ ! -f "$PLAN_FILE" ]; then
        missing+=("IMPLEMENTATION_PLAN.md")
    elif ! plan_is_semantically_actionable "$PLAN_FILE"; then
        missing+=("IMPLEMENTATION_PLAN.md must include Goal + validation criteria + actionable tasks")
    fi

    research_count=$(find "$RESEARCH_DIR" -maxdepth 2 -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    if [ ! -f "$RESEARCH_SUMMARY_FILE" ]; then
        missing+=("research notes (e.g. research/RESEARCH_SUMMARY.md)")
    elif ! grep -qE '<confidence>[0-9]{1,3}</confidence>' "$RESEARCH_SUMMARY_FILE"; then
        missing+=("research/RESEARCH_SUMMARY.md must include a <confidence> tag")
    fi
    if [ ! -f "$RESEARCH_DIR/CODEBASE_MAP.md" ]; then
        missing+=("research/CODEBASE_MAP.md")
    fi
    if [ ! -f "$RESEARCH_DIR/DEPENDENCY_RESEARCH.md" ]; then
        missing+=("research/DEPENDENCY_RESEARCH.md")
    fi
    if [ ! -f "$RESEARCH_DIR/COVERAGE_MATRIX.md" ]; then
        missing+=("research/COVERAGE_MATRIX.md")
    fi

    if ! markdown_artifacts_are_clean; then
        missing+=("markdown artifacts must not contain tool transcript leakage or local identity/path leakage")
    fi

    local gitignore_missing_lines
    local -a gitignore_missing
    gitignore_missing_lines="$(gitignore_missing_required_entries || true)"
    while IFS= read -r missing_entry; do
        [ -n "$missing_entry" ] && gitignore_missing+=("$missing_entry")
    done <<< "$gitignore_missing_lines"
    if [ "${#gitignore_missing[@]}" -gt 0 ]; then
        local missing_joined
        missing_joined="$(printf '%s,' "${gitignore_missing[@]}" | sed 's/,$//')"
        missing+=(".gitignore must include local/sensitive/runtime guardrails (missing: $missing_joined)")
    fi

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

enforce_build_gate() {
    if ! check_build_prerequisites; then
        log_reason_code "RB_BUILD_GATE_PREREQ_FAILED" "build prerequisites failed"
        return 1
    fi
    return 0
}

pick_fallback_engine() { [ "$2" = "claude" ] && echo "codex" || echo "claude"; }
effective_lock_wait_seconds() { echo $((LOCK_WAIT_SECONDS + 7)); }
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
plan_prompt_for_iteration() { echo "$1"; }
run_idle_plan_refresh() { return 0; }

main() {
    acquire_lock || exit 1
    
    local resume_requested=false
    if [[ "$*" == *"--resume"* ]]; then resume_requested=true; fi

    if is_true "$resume_requested" && load_state; then
        success "Resuming mission..."
    else
        save_state
    fi

    if ! is_number "$PHASE_COMPLETION_MAX_ATTEMPTS" || [ "$PHASE_COMPLETION_MAX_ATTEMPTS" -lt 1 ]; then
        PHASE_COMPLETION_MAX_ATTEMPTS=3
    fi
    if ! is_number "$PHASE_COMPLETION_RETRY_DELAY_SECONDS" || [ "$PHASE_COMPLETION_RETRY_DELAY_SECONDS" -lt 0 ]; then
        PHASE_COMPLETION_RETRY_DELAY_SECONDS=5
    fi

    local -a phases=("plan" "build" "test" "refactor" "lint" "document")
    local should_exit="false"
    while true; do
        for phase in "${phases[@]}"; do
            if is_true "$should_exit"; then break 2; fi
            CURRENT_PHASE="$phase"
            ITERATION_COUNT=$((ITERATION_COUNT + 1))
            save_state
            
            local pfile="$(prompt_file_for_mode "$phase")"
            local lfile="$LOG_DIR/${phase}_${SESSION_ID}_${ITERATION_COUNT}.log"
            local ofile="$COMPLETION_LOG_DIR/${phase}_${SESSION_ID}_${ITERATION_COUNT}.out"
            mkdir -p "$LOG_DIR" "$COMPLETION_LOG_DIR"

            if [ "$phase" = "build" ] && ! enforce_build_gate "$YOLO"; then
                warn "Build gate blocked before build execution."
                log_reason_code "RB_BUILD_GATE_PREREQ_FAILED" "build prerequisites failed"
                should_exit="true"
                break
            fi

            local phase_attempt=1
            while [ "$phase_attempt" -le "$PHASE_COMPLETION_MAX_ATTEMPTS" ]; do
                if run_agent_with_prompt "$pfile" "$lfile" "$ofile" "$YOLO"; then
                    if detect_completion_signal "$lfile" "$ofile" >/dev/null; then
                        if [ "$phase" = "plan" ] && ! enforce_build_gate "$YOLO"; then
                            warn "Build gate failed after plan phase."
                            log_reason_code "RB_BUILD_GATE_FAILED_AFTER_PLAN" "build gate failed after plan->build transition"
                            should_exit="true"
                            break
                        fi
                        success "Phase $phase completed."
                        run_swarm_consensus "$phase-gate" || {
                            log_reason_code "RB_CONSENSUS_FAILED" "consensus failed after $phase"
                            should_exit="true"
                            break
                        }
                        break
                    else
                        phase_attempt=$((phase_attempt + 1))
                        if [ "$phase_attempt" -gt "$PHASE_COMPLETION_MAX_ATTEMPTS" ]; then
                            warn "Phase $phase no signal after $PHASE_COMPLETION_MAX_ATTEMPTS attempts."
                            should_exit="true"
                            break
                        fi
                        if is_true "$PHASE_COMPLETION_RETRY_VERBOSE"; then
                            warn "Phase $phase no signal on attempt $((phase_attempt - 1))/${PHASE_COMPLETION_MAX_ATTEMPTS}. Retrying in ${PHASE_COMPLETION_RETRY_DELAY_SECONDS}s..."
                        fi
                        sleep "$PHASE_COMPLETION_RETRY_DELAY_SECONDS"
                    fi
                else
                    err "Agent failed in $phase."
                    log_reason_code "RB_AGENT_FAILED" "agent execution failed in $phase"
                    should_exit="true"
                    break
                fi
            done
        done
        if is_true "$should_exit"; then
            break
        fi
        [ "$MAX_ITERATIONS" -gt 0 ] && [ "$ITERATION_COUNT" -ge "$MAX_ITERATIONS" ] && break
    done

    release_lock
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
