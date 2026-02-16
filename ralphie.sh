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
STACK_SNAPSHOT_FILE="$RESEARCH_DIR/STACK_SNAPSHOT.md"
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
SETUP_SUBREPOS_SCRIPT="$PROJECT_DIR/engines/setup-agent-subrepos.sh"

PROMPT_BUILD_FILE="$PROJECT_DIR/PROMPT_build.md"
PROMPT_PLAN_FILE="$PROJECT_DIR/PROMPT_plan.md"
PROMPT_TEST_FILE="$PROJECT_DIR/PROMPT_test.md"
PROMPT_REFACTOR_FILE="$PROJECT_DIR/PROMPT_refactor.md"
PROMPT_LINT_FILE="$PROJECT_DIR/PROMPT_lint.md"
PROMPT_DOCUMENT_FILE="$PROJECT_DIR/PROMPT_document.md"
PLAN_FILE="$PROJECT_DIR/IMPLEMENTATION_PLAN.md"
PROJECT_BOOTSTRAP_FILE="$CONFIG_DIR/project-bootstrap.md"

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

is_bool_like() {
    case "${1:-}" in
        true|TRUE|True|false|FALSE|False|1|0|yes|YES|no|NO|on|ON|off|OFF|y|Y|n|N) return 0 ;;
        *) return 1 ;;
    esac
}

is_number() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

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

to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
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
            [ "$PHASE_NOOP_POLICY_PLAN_EXPLICIT" != "true" ] && PHASE_NOOP_POLICY_PLAN="none"
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
            [ "$PHASE_NOOP_POLICY_DOCUMENT_EXPLICIT" != "true" ] && PHASE_NOOP_POLICY_DOCUMENT="hard"
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
  --resume                               Resume from previous persisted session state (default: true)
  --no-resume                            Force fresh start; ignore persisted state
  --rebootstrap                          Rebuild project bootstrap context (project type/objective/build consent)
  --max-session-cycles N                 Max total inference attempts in this session (0 = unlimited)
  --session-token-budget N                Max session token budget (0 = unlimited)
  --session-token-rate-cents-per-million N  Cost rate in cents per million tokens
  --session-cost-budget-cents N           Max estimated cost budget in cents (0 = unlimited)
  --max-phase-completion-attempts N       Max completion-signal retries per phase
  --phase-completion-retry-delay-seconds N Delay in seconds between completion retries
  --phase-completion-retry-verbose bool   Verbose phase completion retry logging (true|false)
  --run-agent-max-attempts N              Max inference retries per agent run
  --run-agent-retry-delay-seconds N       Delay in seconds between inference retries
  --run-agent-retry-verbose bool          Verbose inference retry logging (true|false)
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
  --help, -h                             Show this help and exit

All options may also be set through config.env (eg. SESSION_TOKEN_BUDGET, MAX_SESSION_CYCLES, etc).
EOF
}

require_non_negative_int() {
    local name="$1"
    local value="$2"
    if ! is_number "$value"; then
        err "Invalid numeric value for $name: $value"
        exit 1
    fi
    if [ "$value" -lt 0 ]; then
        err "Negative values are not supported for $name: $value"
        exit 1
    fi
}

parse_arg_value() {
    local arg_name="$1"
    local arg_value="$2"
    if [ -z "$arg_value" ] || [[ "$arg_value" == --* ]]; then
        err "Missing value for $arg_name"
        exit 1
    fi
    echo "$arg_value"
}

parse_args() {
    while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h)
            print_usage
            exit 0
            ;;
            --resume)
                RESUME_REQUESTED=true
                shift
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
                if [ "$PHASE_COMPLETION_MAX_ATTEMPTS" -eq 0 ]; then
                    PHASE_COMPLETION_MAX_ATTEMPTS=1
                fi
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
                PHASE_NOOP_PROFILE_EXPLICIT=true
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
}

# Global Registry for Background Processes (for atomic cleanup)
declare -a RALPHIE_BG_PIDS=()
INTERRUPT_MENU_ACTIVE="false"
MARKDOWN_ARTIFACTS_CLEANED_LIST=""

# Configuration defaults
DEFAULT_ENGINE="claude"
DEFAULT_CODEX_CMD="codex"
DEFAULT_CLAUDE_CMD="claude"
DEFAULT_YOLO="true"
DEFAULT_AUTO_UPDATE="true"
DEFAULT_COMMAND_TIMEOUT_SECONDS=0 # 0 means disabled
DEFAULT_MAX_ITERATIONS=0          # 0 means infinite
DEFAULT_MAX_SESSION_CYCLES=0      # 0 means infinite across all phases
DEFAULT_RALPHIE_QUALITY_LEVEL="standard" # minimal|standard|high
DEFAULT_RUN_AGENT_MAX_ATTEMPTS=3
DEFAULT_RUN_AGENT_RETRY_DELAY_SECONDS=5
DEFAULT_RUN_AGENT_RETRY_VERBOSE="true"
DEFAULT_RESUME_REQUESTED="true"
DEFAULT_REBOOTSTRAP_REQUESTED="false"
DEFAULT_STRICT_VALIDATION_NOOP="false"
DEFAULT_PHASE_COMPLETION_MAX_ATTEMPTS=3 # bounded retries per phase (0 = one attempt)
DEFAULT_PHASE_COMPLETION_RETRY_DELAY_SECONDS=5
DEFAULT_PHASE_COMPLETION_RETRY_VERBOSE="true"
DEFAULT_ENGINE_OUTPUT_TO_STDOUT="true"
ENGINE_OUTPUT_TO_STDOUT_EXPLICIT="false"
ENGINE_OUTPUT_TO_STDOUT_OVERRIDE=""
DEFAULT_PHASE_NOOP_POLICY_PLAN="none"
DEFAULT_PHASE_NOOP_POLICY_BUILD="hard"
DEFAULT_PHASE_NOOP_POLICY_TEST="soft"
DEFAULT_PHASE_NOOP_POLICY_REFACTOR="hard"
DEFAULT_PHASE_NOOP_POLICY_LINT="soft"
DEFAULT_PHASE_NOOP_POLICY_DOCUMENT="hard"
DEFAULT_PHASE_NOOP_PROFILE="balanced"
PHASE_NOOP_PROFILE_EXPLICIT=false
PHASE_NOOP_POLICY_PLAN_EXPLICIT=false
PHASE_NOOP_POLICY_BUILD_EXPLICIT=false
PHASE_NOOP_POLICY_TEST_EXPLICIT=false
PHASE_NOOP_POLICY_REFACTOR_EXPLICIT=false
PHASE_NOOP_POLICY_LINT_EXPLICIT=false
PHASE_NOOP_POLICY_DOCUMENT_EXPLICIT=false
DEFAULT_SESSION_TOKEN_BUDGET=0               # 0 means unlimited
DEFAULT_SESSION_TOKEN_RATE_CENTS_PER_MILLION=0 # 0 means no cost accounting
DEFAULT_SESSION_COST_BUDGET_CENTS=0           # 0 means unlimited
DEFAULT_AUTO_REPAIR_MARKDOWN_ARTIFACTS="true" # sanitize common local/engine leaks when gate blocked

# Load configuration from environment or file.
COMMAND_TIMEOUT_SECONDS="${COMMAND_TIMEOUT_SECONDS:-$DEFAULT_COMMAND_TIMEOUT_SECONDS}"
MAX_ITERATIONS="${MAX_ITERATIONS:-$DEFAULT_MAX_ITERATIONS}"
MAX_SESSION_CYCLES="${MAX_SESSION_CYCLES:-$DEFAULT_MAX_SESSION_CYCLES}"
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
ENGINE_OUTPUT_TO_STDOUT="${ENGINE_OUTPUT_TO_STDOUT:-$DEFAULT_ENGINE_OUTPUT_TO_STDOUT}"
STRICT_VALIDATION_NOOP="${STRICT_VALIDATION_NOOP:-$DEFAULT_STRICT_VALIDATION_NOOP}"
PHASE_COMPLETION_MAX_ATTEMPTS="${PHASE_COMPLETION_MAX_ATTEMPTS:-$DEFAULT_PHASE_COMPLETION_MAX_ATTEMPTS}"
PHASE_COMPLETION_RETRY_DELAY_SECONDS="${PHASE_COMPLETION_RETRY_DELAY_SECONDS:-$DEFAULT_PHASE_COMPLETION_RETRY_DELAY_SECONDS}"
PHASE_COMPLETION_RETRY_VERBOSE="${PHASE_COMPLETION_RETRY_VERBOSE:-$DEFAULT_PHASE_COMPLETION_RETRY_VERBOSE}"
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

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

# Override with environment variables if present.
ACTIVE_ENGINE="${RALPHIE_ENGINE:-$DEFAULT_ENGINE}"
CODEX_CMD="${CODEX_ENGINE_CMD:-$DEFAULT_CODEX_CMD}"
CLAUDE_CMD="${CLAUDE_ENGINE_CMD:-$DEFAULT_CLAUDE_CMD}"
RESUME_REQUESTED="${RALPHIE_RESUME_REQUESTED:-$DEFAULT_RESUME_REQUESTED}"
REBOOTSTRAP_REQUESTED="${RALPHIE_REBOOTSTRAP_REQUESTED:-$DEFAULT_REBOOTSTRAP_REQUESTED}"
ENGINE_OUTPUT_TO_STDOUT="${RALPHIE_ENGINE_OUTPUT_TO_STDOUT:-$ENGINE_OUTPUT_TO_STDOUT}"
YOLO="${RALPHIE_YOLO:-$YOLO}"
AUTO_UPDATE="${RALPHIE_AUTO_UPDATE:-$AUTO_UPDATE}"
AUTO_UPDATE_URL="${RALPHIE_AUTO_UPDATE_URL:-$DEFAULT_AUTO_UPDATE_URL}"
PHASE_NOOP_PROFILE="${RALPHIE_PHASE_NOOP_PROFILE:-$PHASE_NOOP_PROFILE}"
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
CURRENT_PHASE_INDEX=0
ITERATION_COUNT=0
SESSION_ID="$(date +%Y%m%d_%H%M%S)"
SESSION_ATTEMPT_COUNT=0
SESSION_TOKEN_COUNT=0
SESSION_COST_CENTS=0
LAST_RUN_TOKEN_COUNT=0
LAST_CONSENSUS_SCORE=0
LAST_CONSENSUS_PASS=false
LAST_CONSENSUS_DIR=""
LAST_CONSENSUS_SUMMARY=""

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
    local file="$1"
    local checksum_cmd

    checksum_cmd="$(sha256sum_command)" || {
        warn "No SHA-256 command available for file checksum calculation."
        return 1
    }

    if [ "$checksum_cmd" = "sha256sum" ]; then
        "$checksum_cmd" "$file" | cut -d' ' -f1
    else
        "$checksum_cmd" -a 256 "$file" | cut -d' ' -f1
    fi
}

save_state() {
    mkdir -p "$(dirname "$STATE_FILE")"
    local checksum

    cat <<EOF > "$STATE_FILE"
CURRENT_PHASE="$CURRENT_PHASE"
CURRENT_PHASE_INDEX="$CURRENT_PHASE_INDEX"
ITERATION_COUNT="$ITERATION_COUNT"
SESSION_ID="$SESSION_ID"
SESSION_ATTEMPT_COUNT="$SESSION_ATTEMPT_COUNT"
SESSION_TOKEN_COUNT="$SESSION_TOKEN_COUNT"
SESSION_COST_CENTS="$SESSION_COST_CENTS"
LAST_RUN_TOKEN_COUNT="$LAST_RUN_TOKEN_COUNT"
ENGINE_OUTPUT_TO_STDOUT="$ENGINE_OUTPUT_TO_STDOUT"
EOF
    # Append SHA-256 checksum to the end
    if checksum="$(sha256_file_sum "$STATE_FILE")"; then
        echo "STATE_CHECKSUM=\"$checksum\"" >> "$STATE_FILE"
    else
        warn "Could not calculate state checksum; continuing without integrity metadata."
    fi
}

load_state() {
    if [ ! -f "$STATE_FILE" ]; then return 1; fi

    CURRENT_PHASE="plan"
    CURRENT_PHASE_INDEX=0
    ITERATION_COUNT=0
    SESSION_ID=""
    SESSION_ATTEMPT_COUNT=0
    SESSION_TOKEN_COUNT=0
    SESSION_COST_CENTS=0
    LAST_RUN_TOKEN_COUNT=0
    ENGINE_OUTPUT_TO_STDOUT="$DEFAULT_ENGINE_OUTPUT_TO_STDOUT"
    
    # Verify checksum if present
    if grep -q "STATE_CHECKSUM=" "$STATE_FILE"; then
        local expected actual state_body_file
        expected="$(grep "STATE_CHECKSUM=" "$STATE_FILE" | head -n 1 | cut -d'"' -f2)"
        state_body_file="$(mktemp "$CONFIG_DIR/state-body.XXXXXX")"
        if grep -v "^STATE_CHECKSUM=" "$STATE_FILE" > "$state_body_file" 2>/dev/null && actual="$(sha256_file_sum "$state_body_file")"; then
            if [ -n "$expected" ] && [ "$expected" != "$actual" ]; then
                warn "State file checksum mismatch! Corruption detected. Forcing clean state."
                log_reason_code "RB_STATE_CORRUPTION" "checksum mismatch in state file"
                rm -f "$state_body_file"
                return 1
            fi
        else
            warn "Unable to validate state checksum. Proceeding without enforcing integrity."
        fi
        rm -f "$state_body_file"
    fi

    while IFS='=' read -r key value; do
        [ -z "$key" ] && continue
        value="${value%\"}"
        value="${value#\"}"
        case "$key" in
            CURRENT_PHASE) CURRENT_PHASE="$value" ;;
            CURRENT_PHASE_INDEX) is_number "$value" && CURRENT_PHASE_INDEX="$value" ;;
            ITERATION_COUNT) is_number "$value" && ITERATION_COUNT="$value" ;;
            SESSION_ID) SESSION_ID="$value" ;;
            SESSION_ATTEMPT_COUNT) is_number "$value" && SESSION_ATTEMPT_COUNT="$value" ;;
            SESSION_TOKEN_COUNT) is_number "$value" && SESSION_TOKEN_COUNT="$value" ;;
            SESSION_COST_CENTS) is_number "$value" && SESSION_COST_CENTS="$value" ;;
            LAST_RUN_TOKEN_COUNT) is_number "$value" && LAST_RUN_TOKEN_COUNT="$value" ;;
            ENGINE_OUTPUT_TO_STDOUT) [ -n "$value" ] && ENGINE_OUTPUT_TO_STDOUT="$value" ;;
            STATE_CHECKSUM=*) ;;
            *) ;;
        esac
    done < "$STATE_FILE"

    if ! is_number "$CURRENT_PHASE_INDEX"; then
        CURRENT_PHASE_INDEX=0
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
    echo $(( (bytes + 3) / 4 ))
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
    tokens="$(( prompt_tokens + log_tokens + output_tokens ))"
    echo "$tokens"
}

charge_session_budget() {
    local tokens="$1"
    if ! is_number "$tokens"; then
        tokens=0
    fi
    SESSION_ATTEMPT_COUNT=$((SESSION_ATTEMPT_COUNT + 1))
    SESSION_TOKEN_COUNT=$((SESSION_TOKEN_COUNT + tokens))

    if is_number "$SESSION_TOKEN_RATE_CENTS_PER_MILLION" && [ "$SESSION_TOKEN_RATE_CENTS_PER_MILLION" -gt 0 ]; then
        local run_cost
        run_cost=$(( tokens * SESSION_TOKEN_RATE_CENTS_PER_MILLION / 1000000 ))
        SESSION_COST_CENTS=$((SESSION_COST_CENTS + run_cost))
    fi

    LAST_RUN_TOKEN_COUNT="$tokens"
}

enforce_session_budget() {
    local reason_prefix="${1:-run}"
    if is_number "$MAX_SESSION_CYCLES" && [ "$MAX_SESSION_CYCLES" -gt 0 ] && [ "$SESSION_ATTEMPT_COUNT" -ge "$MAX_SESSION_CYCLES" ]; then
        log_reason_code "RB_SESSION_CYCLE_BUDGET_EXCEEDED" "$reason_prefix: session cycle budget exceeded at $SESSION_ATTEMPT_COUNT/$MAX_SESSION_CYCLES attempts"
        return 1
    fi
    if is_number "$SESSION_TOKEN_BUDGET" && [ "$SESSION_TOKEN_BUDGET" -gt 0 ] && [ "$SESSION_TOKEN_COUNT" -gt "$SESSION_TOKEN_BUDGET" ]; then
        log_reason_code "RB_SESSION_TOKEN_BUDGET_EXCEEDED" "$reason_prefix: session token budget exceeded at $SESSION_TOKEN_COUNT/$SESSION_TOKEN_BUDGET"
        return 1
    fi
    if is_number "$SESSION_COST_BUDGET_CENTS" && [ "$SESSION_COST_BUDGET_CENTS" -gt 0 ] && [ "$SESSION_COST_CENTS" -gt "$SESSION_COST_BUDGET_CENTS" ]; then
        log_reason_code "RB_SESSION_COST_BUDGET_EXCEEDED" "$reason_prefix: session cost budget exceeded at $SESSION_COST_CENTS/$SESSION_COST_BUDGET_CENTS cents"
        return 1
    fi
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
is_tty_input_available() {
    if [ -t 0 ]; then
        return 0
    fi
    [ -r /dev/tty ] && [ -w /dev/tty ]
}

prompt_read_line() {
    local prompt="$1"
    local default="$2"
    local response=""

    if [ -t 0 ]; then
        read -rp "$prompt" response
        echo "${response:-$default}"
        return 0
    fi

    if [ -r /dev/tty ] && [ -w /dev/tty ]; then
        read -rp "$prompt" response < /dev/tty > /dev/tty
        echo "${response:-$default}"
        return 0
    fi

    echo "$default"
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

    response="$(prompt_read_line "$prompt $default_marker: " "$default")"
    case "${response}" in
        [Yy]*) echo "true"; return 0 ;;
        *) echo "false"; return 1 ;;
    esac
}

prompt_line() {
    local prompt="$1"
    local default="$2"
    prompt_read_line "$prompt [$default]: " "$default"
}

prompt_optional_line() {
    local prompt="$1"
    local default="${2:-}"
    prompt_read_line "$prompt: " "$default"
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

bootstrap_context_is_valid() {
    local project_type objective build_consent interactive_prompted
    project_type="$(bootstrap_prompt_value "project_type" 2>/dev/null || true)"
    objective="$(bootstrap_prompt_value "objective" 2>/dev/null || true)"
    build_consent="$(bootstrap_prompt_value "build_consent" 2>/dev/null || true)"
    interactive_prompted="$(bootstrap_prompt_value "interactive_prompted" 2>/dev/null || true)"

    if [ -z "$project_type" ] || [ -z "$objective" ] || [ -z "$build_consent" ] || [ -z "$interactive_prompted" ]; then
        return 1
    fi
    case "$project_type" in
        new|existing) ;;
        *) return 1 ;;
    esac
    if ! is_bool_like "$build_consent"; then
        return 1
    fi
    if ! is_bool_like "$interactive_prompted"; then
        return 1
    fi
    return 0
}

write_bootstrap_context_file() {
    local project_type="$1"
    local objective="$2"
    local build_consent="$3"
    local interactive_source="$4"

    cat > "$PROJECT_BOOTSTRAP_FILE" <<EOF
# Ralphie Project Bootstrap
project_type: $project_type
build_consent: $build_consent
objective: $objective
interactive_prompted: $interactive_source
captured_at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
EOF
}

ensure_project_bootstrap() {
    local project_type objective build_consent interactive_source
    project_type="existing"
    objective="Improve project with a deterministic, evidence-first implementation path."
    build_consent="true"
    interactive_source="false"

    mkdir -p "$(dirname "$PROJECT_BOOTSTRAP_FILE")"
    local existing_project_type=""
    local existing_objective=""
    local existing_build_consent=""
    local existing_interactive_prompted=""
    local needs_prompt="false"

    if [ -f "$PROJECT_BOOTSTRAP_FILE" ]; then
        existing_project_type="$(bootstrap_prompt_value "project_type" 2>/dev/null || true)"
        existing_objective="$(bootstrap_prompt_value "objective" 2>/dev/null || true)"
        existing_build_consent="$(bootstrap_prompt_value "build_consent" 2>/dev/null || true)"
        existing_interactive_prompted="$(bootstrap_prompt_value "interactive_prompted" 2>/dev/null || true)"

        if [ -n "$existing_project_type" ]; then
            project_type="$existing_project_type"
        fi
        if [ -n "$existing_objective" ]; then
            objective="$existing_objective"
        fi
        if [ -n "$existing_build_consent" ]; then
            build_consent="$existing_build_consent"
        fi
        if [ "$existing_interactive_prompted" = "true" ]; then
            interactive_source="true"
        fi
    fi

    if [ "$REBOOTSTRAP_REQUESTED" = true ] || [ ! -f "$PROJECT_BOOTSTRAP_FILE" ] || ! bootstrap_context_is_valid; then
        needs_prompt="true"
    fi
    if is_tty_input_available && [ "$existing_interactive_prompted" = "false" ] && [ -f "$PROJECT_BOOTSTRAP_FILE" ]; then
        needs_prompt="true"
    fi

    if [ "$needs_prompt" = "true" ]; then
        if [ -f "$PROJECT_BOOTSTRAP_FILE" ] && ! bootstrap_context_is_valid; then
            warn "Existing project bootstrap file is invalid or incomplete. Rebuilding context."
        elif [ "$REBOOTSTRAP_REQUESTED" = true ]; then
            warn "Rebuilding project bootstrap context due to --rebootstrap request."
        elif is_tty_input_available && [ "$existing_interactive_prompted" = "false" ]; then
            info "Previous bootstrap was collected non-interactively; refreshing bootstrap context now."
        fi
    fi

    if is_true "$needs_prompt" && is_tty_input_available; then
        interactive_source="true"
        if [ "$REBOOTSTRAP_REQUESTED" = true ] || ! bootstrap_context_is_valid || [ "$existing_interactive_prompted" = "false" ] || [ ! -f "$PROJECT_BOOTSTRAP_FILE" ]; then
            if [ "$(prompt_yes_no "Is this a new project (no established implementation yet)?" "n")" = "true" ]; then
                project_type="new"
            fi
            objective="$(prompt_optional_line "What is the primary objective for this session" "$objective")"
            if [ "$(prompt_yes_no "Proceed automatically from PLAN -> BUILD when all gates pass" "y")" = "true" ]; then
                build_consent="true"
            else
                build_consent="false"
            fi
            info "Project bootstrap captured from interactive input."
        fi
    fi

    if ! is_true "$needs_prompt" && [ -f "$PROJECT_BOOTSTRAP_FILE" ] && is_tty_input_available; then
        info "Loaded existing project bootstrap context: $(path_for_display "$PROJECT_BOOTSTRAP_FILE")"
        info "   - project_type: $project_type"
        info "   - objective: $objective"
        info "   - build_consent: $build_consent"
        return 0
    fi

    if is_true "$needs_prompt" && ! is_tty_input_available; then
        info "Non-interactive bootstrap fallback retained: objective and build consent defaults were applied."
    fi

    write_bootstrap_context_file "$project_type" "$objective" "$build_consent" "$interactive_source"
    info "Captured project bootstrap context: $(path_for_display "$PROJECT_BOOTSTRAP_FILE")"
    REBOOTSTRAP_REQUESTED=false
}

append_bootstrap_context_to_plan_prompt() {
    local source_prompt="$1"
    local target_prompt="$2"
    local project_type objective build_consent

    if [ ! -f "$source_prompt" ] || [ ! -f "$PROJECT_BOOTSTRAP_FILE" ]; then
        cp "$source_prompt" "$target_prompt"
        return 0
    fi

    project_type="$(bootstrap_prompt_value "project_type")"
    objective="$(bootstrap_prompt_value "objective")"
    build_consent="$(bootstrap_prompt_value "build_consent")"

    cat > "$target_prompt" <<EOF
$(cat "$source_prompt")

## Project Bootstrap Context
- Project type: ${project_type:-existing}
- Objective: ${objective:-unspecified}
- Build consent after plan: ${build_consent:-true}

EOF
}

build_is_preapproved() {
    local consent
    consent="$(bootstrap_prompt_value "build_consent" 2>/dev/null)"
    [ "$consent" = "true" ]
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
cleanup_managed_processes() {
    for pid in ${RALPHIE_BG_PIDS[@]+"${RALPHIE_BG_PIDS[@]}"}; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
}

cleanup_resources() {
    cleanup_managed_processes
    release_lock
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
        choice="$(prompt_read_line "Action [r/l/p/q/h]: " "r")"
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
                save_state
                ;;
            p)
                info "Persisted state and paused."
                save_state
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
    exit 0
}
trap handle_interrupt SIGINT
trap cleanup SIGTERM
trap cleanup_resources EXIT

# Unified Agent Run Function with Exponential Backoff Retries
get_timeout_command() {
    if command -v timeout >/dev/null 2>&1; then echo "timeout"; elif command -v gtimeout >/dev/null 2>&1; then echo "gtimeout"; fi
}

run_agent_with_prompt() {
    local prompt_file="$1"
    local log_file="$2"
    local output_file="$3"
    local yolo_effective="$4"
    local attempt_no="${5:-1}"
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
        info "Dispatching ${ACTIVE_ENGINE} for attempt ${attempt}/${max_run_attempts} (phase attempt ${attempt_no}) with prompt $(path_for_display "$prompt_file")."
        if [ "$ACTIVE_ENGINE" = "codex" ]; then
            if [ -n "$timeout_cmd" ]; then
                if is_true "$ENGINE_OUTPUT_TO_STDOUT"; then
                    if "$timeout_cmd" "$COMMAND_TIMEOUT_SECONDS" "${engine_args[@]}" - --output-last-message "$output_file" 2>&1 < "$prompt_file" | tee "$log_file"; then
                        exit_code=0
                    else
                        exit_code=$?
                    fi
                else
                    if "$timeout_cmd" "$COMMAND_TIMEOUT_SECONDS" "${engine_args[@]}" - --output-last-message "$output_file" >> "$log_file" 2>&1 < "$prompt_file"; then
                        exit_code=0
                    else
                        exit_code=$?
                    fi
                fi
            else
                if is_true "$ENGINE_OUTPUT_TO_STDOUT"; then
                    if "${engine_args[@]}" - --output-last-message "$output_file" 2>&1 < "$prompt_file" | tee "$log_file"; then
                        exit_code=0
                    else
                        exit_code=$?
                    fi
                else
                    if "${engine_args[@]}" - --output-last-message "$output_file" >> "$log_file" 2>&1 < "$prompt_file"; then
                        exit_code=0
                    else
                        exit_code=$?
                    fi
                fi
            fi
        else
            if [ -n "$timeout_cmd" ]; then
                if is_true "$ENGINE_OUTPUT_TO_STDOUT"; then
                    if "$timeout_cmd" "$COMMAND_TIMEOUT_SECONDS" ${yolo_prefix[@]+"${yolo_prefix[@]}"} "${engine_args[@]}" - 2>>"$log_file" < "$prompt_file" | tee "$output_file" >> "$log_file"; then
                        exit_code=0
                    else
                        exit_code=$?
                    fi
                else
                    if "$timeout_cmd" "$COMMAND_TIMEOUT_SECONDS" ${yolo_prefix[@]+"${yolo_prefix[@]}"} "${engine_args[@]}" - > "$output_file" 2>>"$log_file" < "$prompt_file"; then
                        exit_code=0
                    else
                        exit_code=$?
                    fi
                fi
            else
                if is_true "$ENGINE_OUTPUT_TO_STDOUT"; then
                    if ${yolo_prefix[@]+"${yolo_prefix[@]}"} "${engine_args[@]}" - 2>>"$log_file" < "$prompt_file" | tee "$output_file" >> "$log_file"; then
                        exit_code=0
                    else
                        exit_code=$?
                    fi
                else
                    if ${yolo_prefix[@]+"${yolo_prefix[@]}"} "${engine_args[@]}" - > "$output_file" 2>>"$log_file" < "$prompt_file"; then
                        exit_code=0
                    else
                        exit_code=$?
                    fi
                fi
            fi
        fi
        if [ "$exit_code" -eq 0 ]; then
            charge_session_budget "$(estimate_run_tokens "$prompt_file" "$log_file" "$output_file")"
            if ! enforce_session_budget "agent attempt"; then
                return 1
            fi
            break
        fi
        charge_session_budget "$(estimate_run_tokens "$prompt_file" "$log_file" "$output_file")"
        if ! enforce_session_budget "agent attempt"; then
            return 1
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

    if [ "$exit_code" -ne 0 ]; then
        log_reason_code "RB_RUN_AGENT_RETRY_EXHAUSTED" "run_agent exceeded ${max_run_attempts} attempts for $(path_for_display "$prompt_file") with last_exit=$exit_code"
    fi

    return "$exit_code"
}

run_swarm_reviewer() {
    local reviewer_index="$1"
    local prompt_file="$2"
    local log_file="$3"
    local output_file="$4"
    local status_file="$5"
    local primary_cmd="$6"
    local fallback_cmd="$7"

    local -a candidate_cmds=("$primary_cmd")
    [ -n "$fallback_cmd" ] && [ "$fallback_cmd" != "$primary_cmd" ] && candidate_cmds+=("$fallback_cmd")

    rm -f "$status_file"
    local attempt_cmd
    local attempt_exit=1
    local used_cmd="${primary_cmd}"
    ACTIVE_ENGINE="unknown"
    ACTIVE_CMD=""

    for attempt_cmd in "${candidate_cmds[@]}"; do
        [ -n "$attempt_cmd" ] || continue
        command -v "$attempt_cmd" >/dev/null 2>&1 || continue

        if [[ "$attempt_cmd" == *"codex"* ]]; then
            ACTIVE_ENGINE="codex"
        else
            ACTIVE_ENGINE="claude"
        fi
        ACTIVE_CMD="$attempt_cmd"
        used_cmd="$attempt_cmd"

        if run_agent_with_prompt "$prompt_file" "$log_file" "$output_file" "false" "$reviewer_index"; then
            attempt_exit=0
            break
        fi
    done

    {
        echo "reviewer_index=$reviewer_index"
        echo "engine=${ACTIVE_ENGINE:-unknown}"
        echo "command=$used_cmd"
        if [ "$attempt_exit" -eq 0 ]; then
            echo "status=success"
            echo "exit_code=0"
        else
            echo "status=failure"
            echo "exit_code=1"
        fi
    } > "$status_file"
    return "$attempt_exit"
}

run_swarm_consensus() {
    local stage="$1"
    local count="$(get_reviewer_count)"
    local parallel="$(get_parallel_reviewer_count)"
    local base_stage="${stage%-gate}"

    info "Running deep consensus swarm for '$stage'..."
    local consensus_dir="$CONSENSUS_DIR/$stage/$SESSION_ID"
    LAST_CONSENSUS_DIR="$consensus_dir"
    LAST_CONSENSUS_SUMMARY=""
    mkdir -p "$consensus_dir"

    local -a prompts=() logs=() outputs=() status_files=()
    local -a primary_cmds=() fallback_cmds=() summary_lines=()
    local claude_available=false
    local codex_available=false
    if command -v "$CLAUDE_CMD" >/dev/null 2>&1; then
        claude_available=true
    fi
    if command -v "$CODEX_CMD" >/dev/null 2>&1; then
        codex_available=true
    fi
    if [ "$claude_available" = false ] && [ "$codex_available" = false ]; then
        warn "No reviewer engines available for consensus."
        LAST_CONSENSUS_SCORE=0
        LAST_CONSENSUS_PASS=false
        return 1
    fi

    local i
    for i in $(seq 1 "$count"); do
        local primary_cmd="$CLAUDE_CMD"
        local fallback_cmd=""

        if [ "$claude_available" = false ] && [ "$codex_available" = true ]; then
            primary_cmd="$CODEX_CMD"
        elif [ "$codex_available" = true ] && [ $((i % 2)) -eq 1 ]; then
            primary_cmd="$CODEX_CMD"
        fi

        if [ "$primary_cmd" = "$CODEX_CMD" ] && [ "$claude_available" = true ]; then
            fallback_cmd="$CLAUDE_CMD"
        fi
        if [ "$primary_cmd" = "$CLAUDE_CMD" ] && [ "$codex_available" = true ]; then
            fallback_cmd="$CODEX_CMD"
        fi

        prompts+=("$consensus_dir/reviewer_${i}_prompt.md")
        logs+=("$consensus_dir/reviewer_${i}.log")
        outputs+=("$consensus_dir/reviewer_${i}.out")
        status_files+=("$consensus_dir/reviewer_${i}.status")
        primary_cmds+=("$primary_cmd")
        fallback_cmds+=("$fallback_cmd")

        {
            echo "# Consensus Review: $stage"
            echo ""
            consensus_prompt_for_stage "$base_stage"
        } > "${prompts[$((i - 1))]}"
    done

    local active=0
    for i in $(seq 0 $((count - 1))); do
        (
            run_swarm_reviewer \
                "$((i + 1))" \
                "${prompts[$i]}" \
                "${logs[$i]}" \
                "${outputs[$i]}" \
                "${status_files[$i]}" \
                "${primary_cmds[$i]}" \
                "${fallback_cmds[$i]}"
        ) &
        RALPHIE_BG_PIDS+=($!)
        active=$((active + 1))
        if [ "$active" -ge "$parallel" ] || [ "$i" -eq $((count - 1)) ]; then
            wait -n 2>/dev/null || true
            active=$((active - 1))
        fi
    done
    wait

    local total_score=0
    local go_votes=0
    local responded_votes=0
    local required_votes=$((count / 2 + 1))
    local avg_score=0

    local idx=0
    local status_file status engine verdict score verdict_gaps
    for ofile in "${outputs[@]}"; do
        status="failure"
        engine="unknown"
        verdict="HOLD"
        score="0"
        verdict_gaps="no explicit gaps"

        status_file="${status_files[$idx]}"
        if [ -f "$status_file" ]; then
            status="$(grep -E "^status=" "$status_file" | head -n 1 | cut -d'=' -f2-)"
            engine="$(grep -E "^engine=" "$status_file" | head -n 1 | cut -d'=' -f2-)"
            [ "$status" = "success" ] || status="failure"
        fi

        if [ -f "$ofile" ]; then
            score="$(grep -oE "<score>[0-9]{1,3}</score>" "$ofile" | sed 's/[^0-9]//g' | tail -n 1)"
            is_number "$score" || score="0"
            if grep -qE "<verdict>(GO|HOLD)</verdict>" "$ofile" 2>/dev/null; then
                verdict="$(grep -oE "<verdict>(GO|HOLD)</verdict>" "$ofile" | tail -n 1 | sed -E 's/<\/?verdict>//g' )"
            elif grep -qE "<decision>(GO|HOLD)</decision>" "$ofile" 2>/dev/null; then
                verdict="$(grep -oE "<decision>(GO|HOLD)</decision>" "$ofile" | tail -n 1 | sed -E 's/<\/?decision>//g' )"
            else
                verdict="HOLD"
            fi

            if grep -q "<gaps>" "$ofile" 2>/dev/null; then
                verdict_gaps="$(sed -n 's/.*<gaps>\(.*\)<\/gaps>.*/\1/p' "$ofile" | head -n 1)"
            fi
            verdict_gaps="$(echo "$verdict_gaps" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c 1-180)"
        else
            verdict_gaps="no output artifact"
        fi

        [ "$status" = "success" ] && responded_votes=$((responded_votes + 1))
        [ "$status" = "success" ] && total_score=$((total_score + score))

        [ "$verdict" = "GO" ] && go_votes=$((go_votes + 1))
        summary_lines+=("reviewer_$((idx + 1)):engine=$engine status=$status score=$score verdict=$verdict gaps=$verdict_gaps")
        idx=$((idx + 1))
    done

    if [ "$responded_votes" -gt 0 ]; then
        avg_score=$((total_score / responded_votes))
    fi

    LAST_CONSENSUS_SCORE="$avg_score"
    LAST_CONSENSUS_SUMMARY="$(printf '%s; ' "${summary_lines[@]}")"
    if [ "$responded_votes" -ge "$required_votes" ] && [ "$go_votes" -ge "$required_votes" ] && [ "$avg_score" -ge 70 ]; then
        LAST_CONSENSUS_PASS=true
        return 0
    fi
    LAST_CONSENSUS_PASS=false
    return 1
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

phase_capture_worktree_manifest() {
    local manifest_file="$1"
    [ -n "$manifest_file" ] || return 1
    : > "$manifest_file"

    if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 1
    fi

    {
        git -C "$PROJECT_DIR" diff --name-status --cached -- . | sed 's/^/C /'
        git -C "$PROJECT_DIR" diff --name-status -- . | sed 's/^/W /'
        git -C "$PROJECT_DIR" ls-files --others --exclude-standard -- . | sed 's/^/U /'
    } | sort > "$manifest_file"
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

phase_requires_mutation() {
    case "$1" in
        build|refactor|document|test|lint)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
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

phase_manifest_delta_preview() {
    local before_file="$1"
    local after_file="$2"
    local lines_limit="${3:-8}"

    if [ ! -f "$before_file" ] || [ ! -f "$after_file" ]; then
        echo ""
        return 0
    fi

    comm -3 "$before_file" "$after_file" | sed 's/^[[:space:]]*//' | head -n "$lines_limit"
}

phase_index_from_name() {
    case "$1" in
        plan) echo 0; return 0 ;;
        build) echo 1; return 0 ;;
        test) echo 2; return 0 ;;
        refactor) echo 3; return 0 ;;
        lint) echo 4; return 0 ;;
        document) echo 5; return 0 ;;
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

collect_phase_resume_blockers() {
    local phase="$1"
    local -a blockers=()
    local -a plan_schema_issues build_schema_issues
    case "$phase" in
        plan)
            ;;
        build)
            mapfile -t blockers < <(collect_build_prerequisites_issues)
            if ! plan_is_semantically_actionable "$PLAN_FILE"; then
                blockers+=("build precondition missing: implementation plan not semantically actionable")
            fi
            ;;
        test|refactor|lint|document)
            if [ ! -f "$PLAN_FILE" ]; then
                blockers+=("test/build prerequisite missing: IMPLEMENTATION_PLAN.md")
            fi
            if [ ! -f "$STACK_SNAPSHOT_FILE" ]; then
                blockers+=("test/build prerequisite missing: research/STACK_SNAPSHOT.md")
            fi
            mapfile -t plan_schema_issues < <(collect_plan_schema_issues)
            if [ "${#plan_schema_issues[@]}" -gt 0 ]; then
                for issue in "${plan_schema_issues[@]}"; do
                    blockers+=("plan schema: $issue")
                done
            fi
            if ! plan_is_semantically_actionable "$PLAN_FILE"; then
                blockers+=("plan is not semantically actionable")
            fi
            ;;
        *)
            blockers+=("unknown phase '$phase'")
            ;;
    esac

    printf '%s\n' "${blockers[@]}"
}

summarize_blocks_for_log() {
    local -a blockers=("$@")
    local idx=0
    local output=""
    local item
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

ensure_gitignore_guardrails() {
    local gitignore_file="$PROJECT_DIR/.gitignore"
    local required_entries
    required_entries="$(gitignore_required_entries)"

    mkdir -p "$(dirname "$gitignore_file")"
    touch "$gitignore_file"

    local added=false
    local entry
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        if ! grep -qxF "$entry" "$gitignore_file" 2>/dev/null; then
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

sanitize_markdown_artifact_file() {
    local file="$1"
    [ -f "$file" ] || return 0

    local tmp_file
    tmp_file="$(mktemp "$CONFIG_DIR/markdown-clean.XXXXXX")"

    if awk '
        $0 ~ /succeeded in [0-9]+ms:/ || $0 ~ /assistant[[:space:]]+to=/ || $0 ~ /recipient_name[[:space:]]*:/ || $0 ~ /tokens used/ || $0 ~ /mcp startup:/ || $0 ~ /\/Users\/[A-Za-z0-9._-]+\// || $0 ~ /\/root\/[A-Za-z0-9._-]+\// || $0 ~ /\/home\/[A-Za-z0-9._-]+\//
        { next }
        { print }
    ' "$file" > "$tmp_file"; then
        if ! cmp -s "$file" "$tmp_file"; then
            mv "$tmp_file" "$file"
            MARKDOWN_ARTIFACTS_CLEANED_LIST="${MARKDOWN_ARTIFACTS_CLEANED_LIST}${MARKDOWN_ARTIFACTS_CLEANED_LIST:+$'\n'}$(path_for_display "$file")"
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
    local file
    local -a targets=("$PLAN_FILE" "$PROJECT_DIR/README.md")

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

    for file in "${targets[@]}"; do
        [ -f "$file" ] || continue
        sanitize_markdown_artifact_file "$file" || true
    done

    [ -n "$MARKDOWN_ARTIFACTS_CLEANED_LIST" ]
}

markdown_artifact_cleanup_summary() {
    printf '%s' "$MARKDOWN_ARTIFACTS_CLEANED_LIST"
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
    local node_score=0 node_signal=()
    local python_score=0 python_signal=()
    local go_score=0 go_signal=()
    local rust_score=0 rust_signal=()
    local java_score=0 java_signal=()
    local dotnet_score=0 dotnet_signal=()
    local unknown_score=0 unknown_signal=()

    local ts_count go_count java_count cs_count py_count rb_count rs_count js_count
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

    local ranking_file
    ranking_file="$(mktemp "$CONFIG_DIR/stack-ranking.XXXXXX")"
    printf "%03d|Node.js|%s\n" "$node_score" "$(join_with_commas "${node_signal[@]}")" >> "$ranking_file"
    printf "%03d|Python|%s\n" "$python_score" "$(join_with_commas "${python_signal[@]}")" >> "$ranking_file"
    printf "%03d|Go|%s\n" "$go_score" "$(join_with_commas "${go_signal[@]}")" >> "$ranking_file"
    printf "%03d|Rust|%s\n" "$rust_score" "$(join_with_commas "${rust_signal[@]}")" >> "$ranking_file"
    printf "%03d|Java|%s\n" "$java_score" "$(join_with_commas "${java_signal[@]}")" >> "$ranking_file"
    printf "%03d|.NET|%s\n" "$dotnet_score" "$(join_with_commas "${dotnet_signal[@]}")" >> "$ranking_file"
    printf "%03d|Ruby|%s\n" "$unknown_score" "$(join_with_commas "${unknown_signal[@]}")" >> "$ranking_file"
    printf "%03d|Unknown|-\n" "$unknown_score" >> "$ranking_file"

    local -a ranked_candidates=()
    while IFS='|' read -r candidate_score candidate_stack candidate_signal; do
        ranked_candidates+=( "$candidate_score|$candidate_stack|$candidate_signal" )
    done < <(sort -t'|' -k1,1nr "$ranking_file")

    rm -f "$ranking_file"

    local primary_candidate primary_score primary_signal
    primary_candidate="Unknown"
    primary_score=0
    primary_signal="-"
    if [ "${#ranked_candidates[@]}" -gt 0 ]; then
        IFS='|' read -r primary_score primary_candidate primary_signal <<< "${ranked_candidates[0]}"
    fi

    local primary_confidence
    primary_confidence="$(stack_confidence_label "$primary_score")"
    if ! is_number "$primary_score"; then primary_score=0; fi

    {
        echo "# Stack Snapshot"
        echo ""
        echo "- generated_at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "- project_root: $PROJECT_DIR"
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

collect_constitution_schema_issues() {
    local -a issues=()
    [ -f "$CONSTITUTION_FILE" ] || issues+=("constitution file missing: .specify/memory/constitution.md")
    if [ -f "$CONSTITUTION_FILE" ]; then
        if ! grep -qE '^##[[:space:]]*Purpose|^##[[:space:]]*Governance|^##[[:space:]]*Phase Contracts|^##[[:space:]]*Recovery and Retry Policy|^##[[:space:]]*Evidence Requirements|^##[[:space:]]*Environment Scope' "$CONSTITUTION_FILE" 2>/dev/null; then
            issues+=("constitution missing required governance sections")
        fi
    fi
    printf '%s\n' "${issues[@]}"
}

extract_evidence_block() {
    local file="$1"
    awk '
        /<evidence>/ {flag = 1; next}
        /<\/evidence>/ {flag = 0; exit}
        flag {print}
    ' "$file" 2>/dev/null || true
}

evidence_field_body() {
    local evidence="$1"
    local field="$2"
    awk -v f="$field" '
        BEGIN {IGNORECASE = 1; in_field = 0}
        $0 ~ "^[[:space:]]*" f "[[:space:]]*:" {
            in_field = 1
            next
        }
        in_field {
            if ($0 ~ "^[[:space:]]*[A-Za-z][A-Za-z0-9_ ]*[[:space:]]*:") {
                exit
            }
            if ($0 ~ /^[[:space:]]*-[[:space:]]+/ || $0 ~ /^[[:space:]]*$/) {
                print
                next
            }
            print
        }
    ' <<< "$evidence" 2>/dev/null
}

evidence_block_has_content_for_field() {
    local evidence="$1"
    local field="$2"
    local field_value
    field_value="$(printf "%s\n" "$evidence" | awk -v f="$field" '
        BEGIN {IGNORECASE = 1}
        $0 ~ "^[[:space:]]*" f "[[:space:]]*:" {
            sub("^[[:space:]]*" f "[[:space:]]*:[[:space:]]*", "", $0)
            if ($0 !~ /^[[:space:]]*$/) { print $0; exit 0 }
            next
        }
        $0 ~ "^[^[:space:]]+[[:space:]]*:" { exit }
        $0 ~ "^[[:space:]]*-[[:space:]]+[^[:space:]]" { print "1"; exit 0 }
        $0 ~ "^[[:space:]]+[^[:space:]]" { print "1"; exit 0 }
    ' || true)"
    if [ -z "$field_value" ]; then
        return 1
    fi
    if evidence_text_has_placeholders "$field_value"; then
        return 1
    fi
    printf "%s" "$field_value" | grep -qE '<[^/][^>]+>' && return 1
    return 0
}

evidence_text_has_placeholders() {
    grep -qiE 'TODO|TBD|placeholder|fill in|fill out|replace me|not yet|unknown' <<< "$1"
}

evidence_list_items_have_status_tokens() {
    local evidence="$1"
    local field="$2"
    local body
    local line
    local has_items=0

    body="$(evidence_field_body "$evidence" "$field")"
    [ -z "$body" ] && return 1

    while IFS= read -r line; do
        if [ -z "$line" ]; then
            continue
        fi
        if ! [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
            continue
        fi
        has_items=1
        if ! printf "%s\n" "$line" | grep -qE '[^[:alnum:]_](PASS_WITH_RISKS|PASS|FAIL|BLOCKED|SKIPPED|WARN|OK)([^[:alnum:]_]|$)'; then
            return 1
        fi
    done <<< "$body"

    [ "$has_items" -eq 1 ] || return 1
    return 0
}

evidence_list_has_real_file_entries() {
    local evidence="$1"
    local field="$2"
    local body
    local line
    local item_count=0
    local valid_count=0

    body="$(evidence_field_body "$evidence" "$field")"
    while IFS= read -r line; do
        if ! [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
            continue
        fi
        item_count=$((item_count + 1))
        line="$(printf "%s" "$line" | sed -E 's/^[[:space:]]*-[[:space:]]+//' | sed -E 's/[[:space:]]+$//')"
        line="$(printf "%s" "$line" | sed -E 's/[[:space:]]*:.*$//')"
        [ -z "$line" ] && continue
        if evidence_text_has_placeholders "$line"; then
            continue
        fi

        if [ -e "$line" ]; then
            valid_count=$((valid_count + 1))
            continue
        fi
        if [ -e "$PROJECT_DIR/$line" ]; then
            valid_count=$((valid_count + 1))
            continue
        fi
    done <<< "$body"

    [ "$item_count" -eq 0 ] && return 1
    [ "$valid_count" -eq 0 ] && return 1
    return 0
}

evidence_field_list_item_count() {
    local evidence="$1"
    local field="$2"
    local body
    body="$(evidence_field_body "$evidence" "$field")"
    printf "%s\n" "$body" | sed '/^[[:space:]]*$/d' | grep -cE '^[[:space:]]*-[[:space:]]+' || true
}

evidence_field_has_list_items() {
    local evidence="$1"
    local field="$2"
    local count
    count="$(evidence_field_list_item_count "$evidence" "$field")"
    if is_number "$count" && [ "$count" -ge 1 ]; then
        return 0
    fi
    return 1
}

evidence_results_are_statusful() {
    local evidence="$1"
    local field="$2"
    local body
    body="$(evidence_field_body "$evidence" "$field")"
    [ -z "$body" ] && return 1

    if printf "%s\n" "$body" | grep -qiE 'PASS_WITH_RISKS|PASS|FAIL|BLOCKED|SKIPPED|WARN|OK'; then
        return 0
    fi
    return 1
}

evidence_enforce_command_result_pattern() {
    local phase="$1"
    local evidence="$2"

    local required_command_list_fields=()
    local required_result_fields=()
    required_command_list_fields+=("commands")

    case "$phase" in
        plan|build|test|refactor|lint|document)
            required_result_fields+=("results")
            ;;
    esac

    local field
    local -a issues=()
    for field in "${required_command_list_fields[@]}"; do
        if ! evidence_field_has_list_items "$evidence" "$field"; then
            return 1
        fi
    done

    for field in "${required_result_fields[@]}"; do
        if ! evidence_field_has_list_items "$evidence" "$field"; then
            return 1
        fi
        if ! evidence_results_are_statusful "$evidence" "$field"; then
            return 1
        fi
        if ! evidence_list_items_have_status_tokens "$evidence" "$field"; then
            return 1
        fi
    done
    return 0
}

collect_phase_validation_schema_issues() {
    local phase="$1"
    local output_file="${2:-}"
    local log_file="${3:-}"
    local evidence_block
    local -a issues=()

    [ -f "$output_file" ] || { issues+=("phase output artifact missing: $output_file"); printf '%s\n' "${issues[@]}"; return 0; }
    evidence_block="$(extract_evidence_block "$output_file")"
    if [ -z "$evidence_block" ]; then
        issues+=("phase requires machine-readable <evidence>...</evidence> block")
    else
        if evidence_text_has_placeholders "$evidence_block"; then
            issues+=("evidence block contains unresolved placeholder content")
        fi
        if ! grep -qiE "^phase:[[:space:]]*$phase" <<< "$evidence_block"; then
            issues+=("evidence block missing: phase: $phase")
        fi
        if ! grep -qiE "^status:[[:space:]]*(DONE|PASS|PASS_WITH_RISKS|BLOCKED)" <<< "$evidence_block"; then
            issues+=("evidence block missing status")
        fi
        if ! evidence_block_has_content_for_field "$evidence_block" "outcome"; then
            issues+=("evidence block missing meaningful 'outcome'")
        fi
    fi

    case "$phase" in
        plan)
            if ! grep -qE '^##[[:space:]]*Research Discovery|^##[[:space:]]*Stack|^##[[:space:]]*Readiness|^##[[:space:]]*Risk' "$PLAN_FILE" 2>/dev/null; then
                issues+=("plan should include research/readiness/risk structured sections")
            fi
            if ! evidence_block_has_content_for_field "$evidence_block" "artifacts"; then
                issues+=("plan requires evidence field: artifacts")
            fi
            if ! evidence_list_has_real_file_entries "$evidence_block" "artifacts"; then
                issues+=("plan artifacts field requires concrete existing paths")
            fi
            if ! evidence_block_has_content_for_field "$evidence_block" "commands"; then
                issues+=("plan requires evidence field: commands")
            fi
            if ! evidence_block_has_content_for_field "$evidence_block" "results"; then
                issues+=("plan requires evidence field: results")
            fi
            if ! evidence_enforce_command_result_pattern "$phase" "$evidence_block"; then
                issues+=("plan requires commands and results list items with status tokens")
            fi
            ;;
        build)
            if ! grep -qiE '^##[[:space:]]*(Acceptance Criteria|Definition of Done|Quality Gates)' "$PLAN_FILE" 2>/dev/null; then
                issues+=("plan acceptance criteria are mandatory before build")
            fi
            if ! evidence_block_has_content_for_field "$evidence_block" "scope"; then
                issues+=("build requires evidence field: scope")
            fi
            if ! evidence_block_has_content_for_field "$evidence_block" "tasks"; then
                issues+=("build requires evidence field: tasks")
            fi
            if ! evidence_block_has_content_for_field "$evidence_block" "files_changed"; then
                issues+=("build requires evidence field: files_changed")
            fi
            if ! evidence_list_has_real_file_entries "$evidence_block" "files_changed"; then
                issues+=("build requires evidence field: files_changed with existing concrete paths")
            fi
            if ! evidence_block_has_content_for_field "$evidence_block" "acceptance_checks"; then
                issues+=("build requires evidence field: acceptance_checks")
            fi
            if ! evidence_block_has_content_for_field "$evidence_block" "commands"; then
                issues+=("build requires evidence field: commands")
            fi
            if ! evidence_block_has_content_for_field "$evidence_block" "results"; then
                issues+=("build requires evidence field: results")
            fi
            if ! evidence_enforce_command_result_pattern "$phase" "$evidence_block"; then
                issues+=("build requires commands and results list items with status tokens")
            fi
            ;;
        test)
            if ! evidence_block_has_content_for_field "$evidence_block" "scope"; then
                issues+=("test requires evidence field: scope")
            fi
            if ! evidence_block_has_content_for_field "$evidence_block" "commands"; then
                issues+=("test requires evidence field: commands")
            fi
            if ! evidence_block_has_content_for_field "$evidence_block" "results"; then
                issues+=("test requires evidence field: results")
            fi
            if ! evidence_block_has_content_for_field "$evidence_block" "evidence"; then
                issues+=("test requires evidence field: evidence")
            fi
            if ! evidence_enforce_command_result_pattern "$phase" "$evidence_block"; then
                issues+=("test requires commands and results list items with status tokens")
            fi
            ;;
        refactor|lint)
            if ! evidence_block_has_content_for_field "$evidence_block" "scope"; then
                issues+=("$phase requires evidence field: scope")
            fi
            if ! evidence_block_has_content_for_field "$evidence_block" "commands"; then
                issues+=("$phase requires evidence field: commands")
            fi
            if ! evidence_block_has_content_for_field "$evidence_block" "results"; then
                issues+=("$phase requires evidence field: results")
            fi
            if ! evidence_block_has_content_for_field "$evidence_block" "outcome"; then
                issues+=("$phase requires evidence field: outcome")
            fi
            if ! evidence_enforce_command_result_pattern "$phase" "$evidence_block"; then
                issues+=("$phase requires commands and results list items with status tokens")
            fi
            if [ "$phase" = "refactor" ] && ! evidence_block_has_content_for_field "$evidence_block" "risk"; then
                issues+=("refactor requires evidence field: risk")
            fi
            if [ "$phase" = "lint" ] && ! evidence_block_has_content_for_field "$evidence_block" "findings"; then
                issues+=("lint requires evidence field: findings")
            fi
            ;;
        document)
            if ! evidence_block_has_content_for_field "$evidence_block" "updated_files"; then
                issues+=("document requires evidence field: updated_files")
            fi
            if ! evidence_list_has_real_file_entries "$evidence_block" "updated_files"; then
                issues+=("document requires evidence field: updated_files with existing paths")
            fi
            if ! evidence_block_has_content_for_field "$evidence_block" "scope"; then
                issues+=("document requires evidence field: scope")
            fi
            if ! evidence_block_has_content_for_field "$evidence_block" "commands"; then
                issues+=("document requires evidence field: commands")
            fi
            if ! evidence_block_has_content_for_field "$evidence_block" "results"; then
                issues+=("document requires evidence field: results")
            fi
            if ! evidence_enforce_command_result_pattern "$phase" "$evidence_block"; then
                issues+=("document requires commands and results list items with status tokens")
            fi
            ;;
    esac
    printf '%s\n' "${issues[@]}"
}

collect_phase_schema_issues() {
    local phase="$1"
    local log_file="$2"
    local output_file="$3"
    local -a issues=()

    [ -f "$output_file" ] || issues+=("$phase output artifact missing: $output_file")
    [ -f "$log_file" ] || issues+=("$phase log artifact missing: $log_file")
    if ! detect_completion_signal "$log_file" "$output_file" >/dev/null; then
        issues+=("$phase completed without machine-readable completion signal")
    fi
    local -a constitution_schema_issues
    mapfile -t constitution_schema_issues < <(collect_constitution_schema_issues)
    for issue in "${constitution_schema_issues[@]}"; do
        issues+=("constitution schema: $issue")
    done

    local -a phase_validation_issues
    mapfile -t phase_validation_issues < <(collect_phase_validation_schema_issues "$phase" "$output_file" "$log_file")
    for issue in "${phase_validation_issues[@]}"; do
        issues+=("phase schema: $issue")
    done
    case "$phase" in
        plan)
            local -a plan_schema_issues research_schema_issues
            mapfile -t research_schema_issues < <(collect_research_schema_issues)
            mapfile -t plan_schema_issues < <(collect_plan_schema_issues)
            for issue in "${research_schema_issues[@]}"; do
                issues+=("research schema: $issue")
            done
            for issue in "${plan_schema_issues[@]}"; do
                issues+=("plan schema: $issue")
            done
            [ -f "$STACK_SNAPSHOT_FILE" ] || issues+=("phase plan requires research/STACK_SNAPSHOT.md")
            ;;
        build)
            [ -f "$PLAN_FILE" ] || issues+=("phase build requires IMPLEMENTATION_PLAN.md")
            local -a build_schema_issues
            mapfile -t build_schema_issues < <(collect_build_schema_issues)
            for issue in "${build_schema_issues[@]}"; do
                issues+=("build schema: $issue")
            done
            ;;
        test|refactor|lint|document)
            [ -f "$PLAN_FILE" ] || issues+=("$phase requires IMPLEMENTATION_PLAN.md")
            [ -f "$STACK_SNAPSHOT_FILE" ] || issues+=("$phase requires research/STACK_SNAPSHOT.md")
            ;;
        *)
            :
            ;;
    esac

    printf '%s\n' "${issues[@]}"
}

collect_build_schema_issues() {
    local -a issues=()
    local has_acceptance=false
    local spec_file spec_candidates
    spec_candidates="$(find "$SPECS_DIR" -maxdepth 3 -type f -name "*.md" 2>/dev/null || true)"
    while IFS= read -r spec_file; do
        [ -n "$spec_file" ] || continue
        if grep -qiE 'acceptance criteria|definition of done|quality gates' "$spec_file" 2>/dev/null; then
            has_acceptance=true
            break
        fi
    done <<< "$spec_candidates"

    if [ "$has_acceptance" = "false" ]; then
        issues+=("specs must include acceptance criteria sections")
    fi
    [ -f "$PLAN_FILE" ] || issues+=("IMPLEMENTATION_PLAN.md missing before build")
    printf '%s\n' "${issues[@]}"
}

collect_research_schema_issues() {
    local -a issues=()
    local primary_stack
    primary_stack="$(stack_primary_from_snapshot)"

    if ! [ -f "$RESEARCH_SUMMARY_FILE" ]; then
        issues+=("RESEARCH_SUMMARY.md missing")
    elif ! grep -qE '<confidence>[0-9]{1,3}</confidence>' "$RESEARCH_SUMMARY_FILE" 2>/dev/null; then
        issues+=("RESEARCH_SUMMARY.md missing <confidence> tag")
    fi

    if ! [ -f "$RESEARCH_DIR/CODEBASE_MAP.md" ]; then
        issues+=("research/CODEBASE_MAP.md missing")
    elif ! grep -qiE 'entrypoints?|entry points?|modules?|directory map|architecture' "$RESEARCH_DIR/CODEBASE_MAP.md" 2>/dev/null; then
        issues+=("research/CODEBASE_MAP.md missing architecture/entrypoint mapping")
    fi

    if ! [ -f "$RESEARCH_DIR/DEPENDENCY_RESEARCH.md" ]; then
        issues+=("research/DEPENDENCY_RESEARCH.md missing")
    elif ! grep -qiE 'alternatives|risk register|dependency' "$RESEARCH_DIR/DEPENDENCY_RESEARCH.md" 2>/dev/null; then
        issues+=("research/DEPENDENCY_RESEARCH.md missing alternatives/risk evidence")
    fi

    if [ "$primary_stack" != "Unknown" ] && [ -f "$RESEARCH_DIR/DEPENDENCY_RESEARCH.md" ]; then
        if ! grep -qiF "$primary_stack" "$RESEARCH_DIR/DEPENDENCY_RESEARCH.md" 2>/dev/null; then
            issues+=("dependency research should discuss primary stack '$primary_stack'")
        fi
    fi

    if ! [ -f "$RESEARCH_DIR/COVERAGE_MATRIX.md" ]; then
        issues+=("research/COVERAGE_MATRIX.md missing")
    fi

    if ! [ -f "$STACK_SNAPSHOT_FILE" ]; then
        issues+=("research/STACK_SNAPSHOT.md missing")
    elif ! grep -qE '^##[[:space:]]*Project Stack Ranking' "$STACK_SNAPSHOT_FILE" 2>/dev/null; then
        issues+=("research/STACK_SNAPSHOT.md missing ranking table")
    fi

    printf '%s\n' "${issues[@]}"
}

collect_plan_schema_issues() {
    local -a issues=()

    if ! [ -f "$PLAN_FILE" ]; then
        issues+=("IMPLEMENTATION_PLAN.md missing")
    else
        [ -f "$PLAN_FILE" ] || issues+=("IMPLEMENTATION_PLAN.md missing")
        if ! grep -qE '^##[[:space:]]*Goal' "$PLAN_FILE" 2>/dev/null; then
            issues+=("IMPLEMENTATION_PLAN.md missing Goal section")
        fi
        if ! grep -qiE 'acceptance criteria|definition of done' "$PLAN_FILE" 2>/dev/null; then
            issues+=("IMPLEMENTATION_PLAN.md missing acceptance criteria")
        fi
        if ! grep -qiE '^\s*-[[:space:]]*\[[ xX]\]' "$PLAN_FILE" 2>/dev/null; then
            issues+=("IMPLEMENTATION_PLAN.md missing actionable checklist tasks")
        fi
    fi

    printf '%s\n' "${issues[@]}"
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
    local -a missing
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
    local missing=()
    if [ ! -d "$SPECS_DIR" ]; then
        missing+=("spec directory missing: specs/")
    fi
    if [ ! -d "$RESEARCH_DIR" ]; then
        missing+=("research directory missing: research/")
    fi

    local -a plan_schema_issues
    mapfile -t plan_schema_issues < <(collect_plan_schema_issues)
    if [ "${#plan_schema_issues[@]}" -gt 0 ]; then
        for issue in "${plan_schema_issues[@]}"; do
            missing+=("plan schema: $issue")
        done
    fi

    local -a build_schema_issues
    mapfile -t build_schema_issues < <(collect_build_schema_issues)
    if [ "${#build_schema_issues[@]}" -gt 0 ]; then
        for issue in "${build_schema_issues[@]}"; do
            missing+=("build schema: $issue")
        done
    fi

    if ! plan_is_semantically_actionable "$PLAN_FILE"; then
        missing+=("plan is not semantically actionable")
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

    local -a constitution_issues
    mapfile -t constitution_issues < <(collect_constitution_schema_issues)
    if [ "${#constitution_issues[@]}" -gt 0 ]; then
        for issue in "${constitution_issues[@]}"; do
            missing+=("constitution: $issue")
        done
    fi

    printf '%s\n' "${missing[@]}"
}

enforce_build_gate() {
    if ! check_build_prerequisites; then
        log_reason_code "RB_BUILD_GATE_PREREQ_FAILED" "build prerequisites failed"
        return 1
    fi
    return 0
}

pick_fallback_engine() { [ "${2:-}" = "claude" ] && echo "codex" || echo "claude"; }
effective_lock_wait_seconds() {
    local wait_seconds="${LOCK_WAIT_SECONDS:-0}"
    echo $(( wait_seconds + 7 ))
}
ensure_prompt_file() {
    local phase="$1"
    local file="$2"
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
- `IMPLEMENTATION_PLAN.md` with goal, validation criteria, and actionable tasks.
- `consensus/build_gate.md` if needed for blockers.

Behavior
- Compare at least two viable implementation paths when uncertainty exists.
- Keep markdown artifacts portable: no local machine paths, no tool transcripts, no timing output.
- Emit machine-checkable completion evidence in this exact block:

<evidence>
phase: plan
status: DONE
outcome: completed
scope: plan and discovery
artifacts:
- IMPLEMENTATION_PLAN.md
- research/RESEARCH_SUMMARY.md
- research/CODEBASE_MAP.md
- research/DEPENDENCY_RESEARCH.md
- research/COVERAGE_MATRIX.md
- research/STACK_SNAPSHOT.md
commands:
- inspected repository
- discovered stack and generated stack snapshot
- generated research and plan artifacts
results:
- plan: PASS
- research artifacts: PASS
</evidence>
- Conclude with `<promise>DONE</promise>`.
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
- Emit machine-checkable completion evidence in this exact block:

<evidence>
phase: build
status: DONE
outcome: implemented
scope: implementation and tests
tasks:
- <task ids completed>
files_changed:
- <list changed files>
acceptance_checks:
- <acceptance checks executed>
commands:
- <commands run>
results:
- <validation check>: PASS
</evidence>
- Conclude with `<promise>DONE</promise>`.
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
- Emit machine-checkable completion evidence in this exact block:

<evidence>
phase: test
status: DONE
outcome: verified
scope: changed surfaces
commands:
- <command>
results:
- <command>: PASS/FAIL
evidence:
- <logs/tests/coverage artifacts>
</evidence>
- Conclude with `<promise>DONE</promise>`.
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
- Emit machine-checkable completion evidence in this exact block:

<evidence>
phase: refactor
status: DONE
scope: refactor boundaries and complexity reduction
outcome: completed
risk:
- <identified risks>
commands:
- <commands run>
results:
- <verification summary>: PASS
</evidence>
- Conclude with `<promise>DONE</promise>`.
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
- Emit machine-checkable completion evidence in this exact block:

<evidence>
phase: lint
status: DONE
scope: recent changes and touched modules
outcome: cleaned
findings:
- <policy issues or none>
commands:
- <commands run>
results:
- <lint check>: PASS
</evidence>
- Conclude with `<promise>DONE</promise>`.
EOF
            ;;
        document)
            cat > "$file" <<'EOF'
# Ralphie Document Phase Prompt
You are the documentation agent.

Goal
- Update or add project-facing documentation describing current behavior and rationale.
- Ensure `.md` outputs are reproducible and free of local context.

Behavior
- Emphasize assumptions, ownership, and runbook changes.
- Emit machine-checkable completion evidence in this exact block:

<evidence>
phase: document
status: DONE
scope: docs and runbooks
updated_files:
- <list documentation files updated>
outcome: documented
commands:
- <commands run>
results:
- <documentation artifact>: PASS
</evidence>
- Conclude with `<promise>DONE</promise>`.
EOF
            ;;
        *)
            touch "$file"
            ;;
    esac
    info "Wrote fallback prompt file: $(path_for_display "$file")"
}

ensure_core_artifacts() {
    mkdir -p "$SPECS_DIR" "$RESEARCH_DIR" "$LOG_DIR" "$COMPLETION_LOG_DIR" "$CONSENSUS_DIR" "$READY_ARCHIVE_DIR" "$SPECIFY_DIR"

    ensure_constitution_bootstrap

    [ -f "$PLAN_FILE" ] || cat > "$PLAN_FILE" <<'EOF'
# Implementation Plan

## Goal
- Bring project into an executable, measurable development plan.

## Validation Criteria
- `<confidence>` score present in `research/RESEARCH_SUMMARY.md`.
- Research and specs artifacts updated with acceptance criteria.

## Actionable Tasks
- [ ] Inspect repository structure and stack dependencies.
- [ ] Generate or update research artifacts (`research/*`).
- [ ] Produce a concrete implementation plan.
- [ ] Implement phase-safe iteration and guardrails.
EOF

    [ -f "$RESEARCH_SUMMARY_FILE" ] || cat > "$RESEARCH_SUMMARY_FILE" <<'EOF'
# Research Summary

<confidence>0</confidence>
## Current Posture
- Baseline confidence is provisional for a fresh or existing project.
EOF

    [ -f "$RESEARCH_DIR/CODEBASE_MAP.md" ] || cat > "$RESEARCH_DIR/CODEBASE_MAP.md" <<'EOF'
# Codebase Map
- File map intentionally generated by Ralphie plan phase.
EOF
    [ -f "$RESEARCH_DIR/DEPENDENCY_RESEARCH.md" ] || cat > "$RESEARCH_DIR/DEPENDENCY_RESEARCH.md" <<'EOF'
# Dependency Research
- Runtime and language stack to be discovered during plan/build cycles.
EOF
    [ -f "$RESEARCH_DIR/COVERAGE_MATRIX.md" ] || cat > "$RESEARCH_DIR/COVERAGE_MATRIX.md" <<'EOF'
# Coverage Matrix
- To be populated by plan/build evidence.
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
    case "$stage" in
        plan)
            cat <<'EOF'
Analyze the latest prompt outputs, plan, and artifacts.
Expectations:
- Validate artifacts are complete, deterministic, and reproducible.
- Ensure alternatives were considered where major implementation choices exist.
- Validate `<evidence>` block is present and complete.
- Required evidence fields: phase, status, outcome, scope, artifacts, commands, results.
- `commands` and `results` must be explicit list entries.
- `results` must contain PASS/WARN/FAIL/BLOCKED style status tokens.
- Emit <score>(0-100)</score> and <verdict>(GO|HOLD)</verdict>.
- Include unresolved blockers in <gaps> as a concise comma-separated list.
EOF
            ;;
        build)
            cat <<'EOF'
Evaluate implementation correctness and traceability to plan.
Expectations:
- Verify changed files align to explicit plan tasks.
- Confirm no speculative edits and no obvious correctness regressions.
- Validate `<evidence>` block and required fields.
- Required evidence fields: phase, status, outcome, scope, tasks, files_changed, acceptance_checks, commands, results.
- `commands` and `results` must be explicit list entries.
- `results` must contain PASS/WARN/FAIL/BLOCKED style status tokens.
- Confirm acceptance criteria are explicit in `IMPLEMENTATION_PLAN.md`.
- Emit <score>(0-100)</score> and <verdict>(GO|HOLD)</verdict>.
- Include unresolved blockers in <gaps> as a concise comma-separated list.
EOF
            ;;
        test)
            cat <<'EOF'
Validate completion signal hygiene and phase-specific quality criteria.
Expectations:
- Confirm no placeholders remain where concrete outputs are required.
- Ensure `<promise>DONE</promise>` quality criteria are met.
- Validate `<evidence>` block and required fields: phase, status, outcome, scope, commands, results, evidence.
- Validate explicit commands/results list entries.
- Results must include status tokens (PASS/WARN/FAIL/BLOCKED).
- Emit <score>(0-100)</score> and <verdict>(GO|HOLD)</verdict>.
- Include unresolved blockers in <gaps> as a concise comma-separated list.
EOF
            ;;
        refactor)
            cat <<'EOF'
Validate completion signal hygiene and refactor-specific quality criteria.
Expectations:
- Confirm no placeholders remain where concrete outputs are required.
- Ensure `<promise>DONE</promise>` quality criteria are met.
- Validate `<evidence>` block and required fields: phase, status, scope, outcome, risk, commands, results.
- Risk and results must contain concrete findings.
- Validate explicit commands/results list entries and status tokens in results.
- Emit <score>(0-100)</score> and <verdict>(GO|HOLD)</verdict>.
- Include unresolved blockers in <gaps> as a concise comma-separated list.
EOF
            ;;
        lint)
            cat <<'EOF'
Validate completion signal hygiene and lint-specific quality criteria.
Expectations:
- Confirm no placeholders remain where concrete outputs are required.
- Ensure `<promise>DONE</promise>` quality criteria are met.
- Validate `<evidence>` block and required fields: phase, status, scope, outcome, findings, commands, results.
- Findings must be concrete and include any risks or "none".
- Validate explicit commands/results list entries and status tokens in results.
- Emit <score>(0-100)</score> and <verdict>(GO|HOLD)</verdict>.
- Include unresolved blockers in <gaps> as a concise comma-separated list.
EOF
            ;;
        document)
            cat <<'EOF'
Validate completion signal hygiene and document-specific quality criteria.
Expectations:
- Confirm no placeholders remain where concrete outputs are required.
- Ensure `<promise>DONE</promise>` quality criteria are met.
- Validate `<evidence>` block and required fields: phase, status, scope, updated_files, commands, results.
- Validate explicit commands/results list entries and status tokens in results.
- Emit <score>(0-100)</score> and <verdict>(GO|HOLD)</verdict>.
- Include unresolved blockers in <gaps> as a concise comma-separated list.
EOF
            ;;
        *)
            cat <<'EOF'
Run independent quality review.
Emit <score>(0-100)</score> and <verdict>(GO|HOLD)</verdict>.
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
        fi
        echo "- Preserve existing work; only generate missing/repairable artifacts and rerun this phase."
        echo "- Conclude with <promise>DONE</promise> when completion is complete."
    } >> "$target_prompt"
}

collect_phase_retry_failures_from_consensus() {
    local -a failures=()
    [ -n "$LAST_CONSENSUS_DIR" ] || { printf '%s\n' "${failures[@]}"; return 0; }
    local reviewer_summary ofile
    for ofile in "$LAST_CONSENSUS_DIR"/*.out; do
        [ -f "$ofile" ] || continue
        local score verdict
        score="$(grep -oE "<score>[0-9]{1,3}</score>" "$ofile" | sed 's/[^0-9]//g' | tail -n 1)"
        is_number "$score" || score="0"
        verdict="$(grep -oE "<verdict>(GO|HOLD)</verdict>" "$ofile" 2>/dev/null | tail -n 1 | sed -E 's/<\/?verdict>//g')"
        [ "$verdict" = "GO" ] || [ "$verdict" = "HOLD" ] || verdict="HOLD"
        local gaps
        if grep -q "<gaps>" "$ofile" 2>/dev/null; then
            gaps="$(sed -n 's/.*<gaps>\(.*\)<\/gaps>.*/\1/p' "$ofile" | head -n 1)"
            gaps="$(echo "$gaps" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c 1-140)"
            [ -z "$gaps" ] && gaps="no explicit gaps"
        else
            gaps="no explicit gaps"
        fi
        reviewer_summary="$(basename "$ofile"): score=$score verdict=${verdict:-HOLD} gaps=${gaps}"
        failures+=("consensus review: $reviewer_summary")
    done
    printf '%s\n' "${failures[@]}"
}

ensure_constitution_bootstrap() {
    [ -f "$CONSTITUTION_FILE" ] || cat > "$CONSTITUTION_FILE" <<'EOF'
# Ralphie Constitution

## Purpose
- Establish deterministic, portable, and reproducible control planes for autonomous execution.
- Define behavior for all phases from planning through documentation.

## Governance
- Keep artifacts machine-readable: avoid local absolute paths, avoid command transcript leakage, and keep logs deterministic.
- Never skip consensus checks or phase schema checks.
- Treat gate failures as actionable signals, not terminal failure if bounded retries remain.

## Phase Contracts
- **Plan** produces research artifacts, an explicit implementation plan, and a deterministic stack snapshot.
- **Build** executes plan tasks against evidence in IMPLEMENTATION_PLAN.md and validates build schema.
- **Test** verifies behavior changes and records validation evidence.
- **Refactor** preserves behavior, reduces complexity, and documents rationale.
- **Lint** enforces deterministic quality and cleanup policies.
- **Document** closes the lifecycle with updated user-facing documentation.

## Recovery and Retry Policy
- Every phase attempt that fails schema, consensus, or transition checks is retried within
  `PHASE_COMPLETION_MAX_ATTEMPTS` using feedback from prior blockers.
- Hard stop occurs only after bounded retries are exhausted and gate feedback is persisted.

## Evidence Requirements
- Each phase writes machine-readable completion signal `<promise>DONE</promise>`.
- Plan/build/test/refactor/lint/document outputs must be reviewed by consensus and schema checks before transition.

## Environment Scope
- Repository-relative paths and relative markdown links are preferred.
- External references are allowed only when version/risk tradeoffs are explicitly documented.
EOF
}

plan_prompt_for_iteration() { echo "$1"; }
run_idle_plan_refresh() { return 0; }
print_session_config_banner() {
    info "=== Ralphie Session Budget & Retry Configuration ==="
    info "max_session_cycles: ${MAX_SESSION_CYCLES:-0} (0=unlimited)"
    info "session_token_budget: ${SESSION_TOKEN_BUDGET:-0} (0=unlimited)"
    info "session_token_rate_cents_per_million: ${SESSION_TOKEN_RATE_CENTS_PER_MILLION:-0}"
    info "session_cost_budget_cents: ${SESSION_COST_BUDGET_CENTS:-0} (0=unlimited)"
    info "session token/cost accounting is heuristic (byte-based estimation, not invoice-accurate)"
    info "phase_completion_max_attempts: ${PHASE_COMPLETION_MAX_ATTEMPTS:-0}"
    info "phase_completion_retry_delay_seconds: ${PHASE_COMPLETION_RETRY_DELAY_SECONDS:-0}"
    info "phase_completion_retry_verbose: ${PHASE_COMPLETION_RETRY_VERBOSE:-false}"
    info "run_agent_max_attempts: ${RUN_AGENT_MAX_ATTEMPTS:-0}"
    info "run_agent_retry_delay_seconds: ${RUN_AGENT_RETRY_DELAY_SECONDS:-0}"
    info "run_agent_retry_verbose: ${RUN_AGENT_RETRY_VERBOSE:-false}"
    info "engine_output_to_stdout: ${ENGINE_OUTPUT_TO_STDOUT:-true}"
    info "phase_noop_profile: ${PHASE_NOOP_PROFILE:-$DEFAULT_PHASE_NOOP_PROFILE}"
    info "strict_validation_noop: ${STRICT_VALIDATION_NOOP:-false}"
    info "auto_repair_markdown_artifacts: ${AUTO_REPAIR_MARKDOWN_ARTIFACTS:-false}"
    info "phase noop policies: plan=${PHASE_NOOP_POLICY_PLAN}, build=${PHASE_NOOP_POLICY_BUILD}, test=${PHASE_NOOP_POLICY_TEST}, refactor=${PHASE_NOOP_POLICY_REFACTOR}, lint=${PHASE_NOOP_POLICY_LINT}, document=${PHASE_NOOP_POLICY_DOCUMENT}"
}

emit_phase_transition_banner() {
    local phase="$1"
    local noop_policy
    noop_policy="$(phase_noop_policy "$phase")"
    info ">>> Entering phase '$phase' <<<"
    info "phase completion attempts remaining: ${PHASE_COMPLETION_MAX_ATTEMPTS:-0}"
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
    parse_args "$@"
    finalize_phase_noop_profile_config
    REBOOTSTRAP_REQUESTED="$(to_lower "${REBOOTSTRAP_REQUESTED:-$DEFAULT_REBOOTSTRAP_REQUESTED}")"
    is_bool_like "$REBOOTSTRAP_REQUESTED" || REBOOTSTRAP_REQUESTED="$DEFAULT_REBOOTSTRAP_REQUESTED"

    acquire_lock || exit 1

    if is_true "$RESUME_REQUESTED" && load_state; then
        success "Resuming mission..."
    else
        save_state
    fi
    if is_true "$ENGINE_OUTPUT_TO_STDOUT_EXPLICIT"; then
        ENGINE_OUTPUT_TO_STDOUT="$ENGINE_OUTPUT_TO_STDOUT_OVERRIDE"
    fi

    if ! is_number "$MAX_SESSION_CYCLES" || [ "$MAX_SESSION_CYCLES" -lt 0 ]; then
        MAX_SESSION_CYCLES=0
    fi
    if ! is_number "$PHASE_COMPLETION_MAX_ATTEMPTS" || [ "$PHASE_COMPLETION_MAX_ATTEMPTS" -lt 1 ]; then
        PHASE_COMPLETION_MAX_ATTEMPTS=3
    fi
    if ! is_number "$PHASE_COMPLETION_RETRY_DELAY_SECONDS" || [ "$PHASE_COMPLETION_RETRY_DELAY_SECONDS" -lt 0 ]; then
        PHASE_COMPLETION_RETRY_DELAY_SECONDS=5
    fi
    if ! is_number "$MAX_ITERATIONS" || [ "$MAX_ITERATIONS" -lt 0 ]; then
        MAX_ITERATIONS=0
    fi

    local should_exit="false"
    if ! enforce_session_budget "session init"; then
        should_exit="true"
    fi
    if is_true "$should_exit"; then
        release_lock
        exit 1
    fi

    print_session_config_banner
    ensure_core_artifacts
    setup_phase_prompts
    ensure_gitignore_guardrails
    ensure_project_bootstrap

    local -a phases=("plan" "build" "test" "refactor" "lint" "document")
    local phase_index=0
    local start_phase_index=0
    local start_phase_name="plan"
    local -a phase_resume_blockers=()
    if is_true "$RESUME_REQUESTED"; then
        start_phase_index="$CURRENT_PHASE_INDEX"
        if ! is_number "$start_phase_index" || [ "$start_phase_index" -lt 0 ] || [ "$start_phase_index" -gt "${#phases[@]}" ]; then
            start_phase_index="$(phase_index_from_name "$CURRENT_PHASE")" || start_phase_index=0
            if ! is_number "$start_phase_index" || [ "$start_phase_index" -lt 0 ] || [ "$start_phase_index" -gt "${#phases[@]}" ]; then
                start_phase_index=0
            fi
        fi
        start_phase_name="$(phase_name_from_index "$start_phase_index")" || start_phase_name="plan"
        mapfile -t phase_resume_blockers < <(collect_phase_resume_blockers "$start_phase_name")
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
            save_state
        fi
    fi

    while true; do
        for ((phase_index = start_phase_index; phase_index < ${#phases[@]}; phase_index++)); do
            local phase="${phases[$phase_index]}"
            CURRENT_PHASE_INDEX="$phase_index"
            if is_true "$should_exit"; then break 2; fi
            CURRENT_PHASE="$phase"
            ITERATION_COUNT=$((ITERATION_COUNT + 1))
            save_state

            local pfile="$(prompt_file_for_mode "$phase")"
            mkdir -p "$LOG_DIR" "$COMPLETION_LOG_DIR"
            if ! enforce_session_budget "session loop"; then
                should_exit="true"
                break
            fi
            emit_phase_transition_banner "$phase"
            if [ ! -f "$pfile" ]; then
                ensure_prompt_file "$phase" "$pfile"
            fi
            if [ "$phase" = "build" ] && ! build_is_preapproved; then
                warn "Build execution was not pre-approved in project bootstrap context."
                warn "Edit $(path_for_display "$PROJECT_BOOTSTRAP_FILE") and set build_consent: true to continue automatically into BUILD."
                log_reason_code "RB_BUILD_CONSENT_REQUIRED" "bootstrap build_consent is false"
                should_exit="true"
                break 2
            fi
            if [ "$phase" = "plan" ]; then
                run_stack_discovery
                if [ ! -f "$STACK_SNAPSHOT_FILE" ] || ! grep -qE '^##[[:space:]]*Project Stack Ranking' "$STACK_SNAPSHOT_FILE" 2>/dev/null; then
                    warn "Stack discovery could not generate a valid ranking snapshot."
                    log_reason_code "RB_STACK_DISCOVERY_FAILED" "could not generate deterministic stack snapshot"
                    should_exit="true"
                    break
                fi
                save_state
            fi

            local phase_attempt=1
            local -a cumulative_phase_failures=()
            while [ "$phase_attempt" -le "$PHASE_COMPLETION_MAX_ATTEMPTS" ]; do
                local lfile="$LOG_DIR/${phase}_${SESSION_ID}_${ITERATION_COUNT}_attempt_${phase_attempt}.log"
                local ofile="$COMPLETION_LOG_DIR/${phase}_${SESSION_ID}_${ITERATION_COUNT}_attempt_${phase_attempt}.out"
                local active_prompt="$pfile"
                local -a phase_failures=("${cumulative_phase_failures[@]}")
                local -a phase_warnings=()
                local attempt_feedback_file="$LOG_DIR/${phase}_${SESSION_ID}_${ITERATION_COUNT}_attempt_${phase_attempt}.prompt.md"
                local bootstrap_prompt_file="$LOG_DIR/${phase}_${SESSION_ID}_${ITERATION_COUNT}_attempt_${phase_attempt}.bootstrap.prompt.md"
                local previous_attempt_output_hash=""
                local phase_noop_mode manifest_before_file manifest_after_file
                phase_noop_mode="$(phase_noop_policy "$phase")"
                local phase_delta_preview=""

                manifest_before_file="$LOG_DIR/${phase}_${SESSION_ID}_${ITERATION_COUNT}_attempt_${phase_attempt}_manifest_before.txt"
                manifest_after_file="$LOG_DIR/${phase}_${SESSION_ID}_${ITERATION_COUNT}_attempt_${phase_attempt}_manifest_after.txt"
                if [ "$phase_noop_mode" != "none" ]; then
                    phase_capture_worktree_manifest "$manifest_before_file" || true
                fi

                if [ "$phase_attempt" -gt 1 ]; then
                    local previous_attempt_file="$COMPLETION_LOG_DIR/${phase}_${SESSION_ID}_${ITERATION_COUNT}_attempt_$((phase_attempt - 1)).out"
                    if [ -f "$previous_attempt_file" ]; then
                        previous_attempt_output_hash="$(shasum -a 256 "$previous_attempt_file" | awk '{print $1}')"
                    fi
                fi

                if [ "$phase" = "plan" ]; then
                    append_bootstrap_context_to_plan_prompt "$pfile" "$bootstrap_prompt_file"
                    active_prompt="$bootstrap_prompt_file"
                fi

                if [ "$phase_attempt" -gt 1 ]; then
                    build_phase_prompt_with_feedback "$phase" "$active_prompt" "$attempt_feedback_file" "$phase_attempt" "${cumulative_phase_failures[@]}"
                    active_prompt="$attempt_feedback_file"
                fi

                if [ "$phase" = "build" ] && ! enforce_build_gate "$YOLO"; then
                    local -a gate_issues
                    mapfile -t gate_issues < <(collect_build_prerequisites_issues)
                    local repair_summary=""
                    if is_true "$AUTO_REPAIR_MARKDOWN_ARTIFACTS" && ! markdown_artifacts_are_clean; then
                        if sanitize_markdown_artifacts; then
                            repair_summary="$(markdown_artifact_cleanup_summary)"
                            if [ -n "$repair_summary" ]; then
                                phase_warnings+=("pre-build markdown remediation: ${repair_summary//$'\\n'/; }")
                            fi
                        fi
                        if [ -n "$repair_summary" ] && enforce_build_gate "$YOLO"; then
                            gate_issues=()
                            phase_warnings+=("build gate passed after markdown artifact remediation")
                        fi
                    fi
                    if [ "${#gate_issues[@]}" -gt 0 ] && [ -n "$repair_summary" ]; then
                        phase_failures+=("pre-build markdown remediation applied before retry")
                        phase_failures+=("pre-build markdown remediation summary: ${repair_summary//$'\\n'/; }")
                    fi
                    for issue in "${gate_issues[@]}"; do
                    phase_failures+=("build gate blocked before build execution: $issue")
                    done
                fi

                if [ "${#phase_failures[@]}" -eq 0 ] && run_agent_with_prompt "$active_prompt" "$lfile" "$ofile" "$YOLO" "$phase_attempt"; then
                    if detect_completion_signal "$lfile" "$ofile" >/dev/null; then
                        if [ -n "$previous_attempt_output_hash" ]; then
                            local phase_output_hash
                            phase_output_hash="$(shasum -a 256 "$ofile" | awk '{print $1}')"
                            if [ "$previous_attempt_output_hash" = "$phase_output_hash" ]; then
                                phase_failures+=("phase output did not materially change from prior attempt")
                            fi
                        fi

                        if [ "$phase" = "plan" ] && ! enforce_build_gate "$YOLO"; then
                            local -a post_plan_gate_issues
                            mapfile -t post_plan_gate_issues < <(collect_build_prerequisites_issues)
                            local post_plan_repair_summary=""
                            if is_true "$AUTO_REPAIR_MARKDOWN_ARTIFACTS" && ! markdown_artifacts_are_clean; then
                                if sanitize_markdown_artifacts; then
                                    post_plan_repair_summary="$(markdown_artifact_cleanup_summary)"
                                    mapfile -t post_plan_gate_issues < <(collect_build_prerequisites_issues)
                                    [ "${#post_plan_gate_issues[@]}" -eq 0 ] && info "Build gate passed after post-plan markdown remediation."
                                    [ -n "$post_plan_repair_summary" ] && phase_warnings+=("post-plan markdown remediation: ${post_plan_repair_summary//$'\\n'/; }")
                                fi
                            fi
                            if [ "${#post_plan_gate_issues[@]}" -gt 0 ]; then
                                phase_failures+=("build gate failed after plan->build transition")
                                [ -n "$post_plan_repair_summary" ] && phase_failures+=("post-plan markdown remediation summary: ${post_plan_repair_summary//$'\\n'/; }")
                                for issue in "${post_plan_gate_issues[@]}"; do
                                    phase_failures+=("build gate: $issue")
                                done
                            fi
                        fi

                        if [ "$phase_noop_mode" != "none" ]; then
                            phase_capture_worktree_manifest "$manifest_after_file" || true
                            if [ -f "$manifest_before_file" ] && [ -f "$manifest_after_file" ]; then
                                if phase_manifest_changed "$manifest_before_file" "$manifest_after_file"; then
                                    phase_delta_preview="$(phase_manifest_delta_preview "$manifest_before_file" "$manifest_after_file" 8)"
                                    if [ -n "$phase_delta_preview" ]; then
                                        phase_delta_preview="$(printf '%s' "$phase_delta_preview" | tr '\n' '; ')"
                                        phase_warnings+=("manifest delta preview: $phase_delta_preview")
                                    fi
                                else
                                    if [ "$phase_noop_mode" = "hard" ]; then
                                        phase_failures+=("$phase completed with no worktree mutation for phase '$phase'")
                                    else
                                        phase_warnings+=("soft no-op signal: $phase completed without visible worktree mutation; acceptable for validation-only phases when run outputs are present")
                                    fi
                                fi
                            else
                                phase_warnings+=("phase no-op check skipped: could not capture a reliable manifest snapshot for this attempt")
                            fi
                        fi

                        local -a phase_schema_issues
                        mapfile -t phase_schema_issues < <(collect_phase_schema_issues "$phase" "$lfile" "$ofile")
                        for issue in "${phase_schema_issues[@]}"; do
                            phase_failures+=("schema: $issue")
                        done

                        if [ "${#phase_schema_issues[@]}" -eq 0 ] && ! run_swarm_consensus "$phase-gate"; then
                            local -a consensus_failures
                            phase_failures+=("consensus failed after $phase")
                            mapfile -t consensus_failures < <(collect_phase_retry_failures_from_consensus)
                            for issue in "${consensus_failures[@]}"; do
                                phase_failures+=("consensus: $issue")
                            done
                            if [ -n "$LAST_CONSENSUS_SUMMARY" ]; then
                                phase_failures+=("consensus summary: $LAST_CONSENSUS_SUMMARY")
                            fi
                        fi
                    else
                        phase_failures+=("missing machine-readable completion signal")
                    fi
                else
                    if [ "${#phase_failures[@]}" -eq 0 ]; then
                        phase_failures+=("agent execution failed in $phase")
                    fi
                fi

                if [ "${#phase_failures[@]}" -gt 0 ]; then
                    cumulative_phase_failures=("${phase_failures[@]}")
                    write_gate_feedback "$phase" "${phase_failures[@]}"
                    for issue in "${phase_failures[@]}"; do
                        warn "$issue"
                    done
                    if [ "${#phase_warnings[@]}" -gt 0 ]; then
                        for issue in "${phase_warnings[@]}"; do
                            info "note: $issue"
                        done
                    fi
                    log_reason_code "RB_PHASE_RETRYABLE_FAIL" "$phase attempt $phase_attempt/$PHASE_COMPLETION_MAX_ATTEMPTS: ${phase_failures[*]}"

                    phase_attempt=$((phase_attempt + 1))
                    if [ "$phase_attempt" -gt "$PHASE_COMPLETION_MAX_ATTEMPTS" ]; then
                        warn "Phase $phase blocked after ${PHASE_COMPLETION_MAX_ATTEMPTS} attempts."
                        format_retry_budget_block_reason "$phase" "$((phase_attempt - 1))" "$PHASE_COMPLETION_MAX_ATTEMPTS"
                        should_exit="true"
                        break
                    fi
                    if is_true "$PHASE_COMPLETION_RETRY_VERBOSE"; then
                        warn "Phase $phase retrying in ${PHASE_COMPLETION_RETRY_DELAY_SECONDS}s (attempt ${phase_attempt}/${PHASE_COMPLETION_MAX_ATTEMPTS})."
                    fi
                    sleep "$PHASE_COMPLETION_RETRY_DELAY_SECONDS"
                    continue
                fi

                if [ "${#phase_warnings[@]}" -gt 0 ]; then
                    for issue in "${phase_warnings[@]}"; do
                        info "note: $issue"
                    done
                fi
                success "Phase $phase completed."
                break
            done
        done
        if is_true "$should_exit"; then
            break
        fi
        if [ "$MAX_ITERATIONS" -gt 0 ] && [ "$ITERATION_COUNT" -ge "$MAX_ITERATIONS" ]; then
            log_reason_code "RB_ITERATION_BUDGET_REACHED" "run iteration budget reached at $ITERATION_COUNT"
            break
        fi
    done

    release_lock
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
