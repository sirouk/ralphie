#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SUBREPO_DIR_INPUT="subrepos"
MAP_FILE_INPUT="maps/agent-source-map.yaml"
MODE="submodule"
STEERING_MAP_BASENAME="binary-steering-map.yaml"

CODEX_REMOTE="https://github.com/openai/codex.git"
CLAUDE_REMOTE="https://github.com/anthropics/claude-code.git"
CODEX_BRANCH="main"
CLAUDE_BRANCH="main"

usage() {
    cat <<'USAGE'
Setup Codex + Claude Code subrepos and emit a heuristic source map.

Usage:
  ./scripts/setup-agent-subrepos.sh [options]

Options:
  --mode submodule|clone      Default: submodule
  --subrepo-dir PATH          Default: subrepos
  --map-file PATH             Default: maps/agent-source-map.yaml
  --help, -h                  Show this help

Examples:
  ./scripts/setup-agent-subrepos.sh
  ./scripts/setup-agent-subrepos.sh --mode clone
USAGE
}

to_abs_path() {
    local path="$1"
    if [ -z "$path" ]; then
        echo "$ROOT_DIR"
        return
    fi
    if [[ "$path" = /* ]]; then
        echo "$path"
    else
        echo "$ROOT_DIR/$path"
    fi
}

to_repo_relative_path() {
    local abs_path="$1"
    if [ "$abs_path" = "$ROOT_DIR" ]; then
        echo "."
        return
    fi
    if [[ "$abs_path" == "$ROOT_DIR/"* ]]; then
        echo "${abs_path#$ROOT_DIR/}"
    else
        echo "$abs_path"
    fi
}

is_within_repo_root() {
    local abs_path="$1"
    if [ "$abs_path" = "$ROOT_DIR" ]; then
        return 0
    fi
    [[ "$abs_path" == "$ROOT_DIR/"* ]]
}

require_within_repo_root() {
    local flag="$1"
    local abs_path="$2"
    if ! is_within_repo_root "$abs_path"; then
        echo "[error] $flag must be within the repository root" >&2
        exit 1
    fi
}

trim_trailing_slash() {
    local value="$1"
    if [ "$value" = "/" ]; then
        echo "/"
    else
        echo "${value%/}"
    fi
}

require_arg_value() {
    local flag="$1"
    local value="${2:-}"
    if [ -z "$value" ] || [[ "$value" == --* ]]; then
        echo "[error] $flag requires a value" >&2
        exit 1
    fi
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --mode)
                require_arg_value "--mode" "${2:-}"
                MODE="${2:-}"
                shift 2
                ;;
            --subrepo-dir)
                require_arg_value "--subrepo-dir" "${2:-}"
                SUBREPO_DIR_INPUT="${2:-}"
                shift 2
                ;;
            --map-file)
                require_arg_value "--map-file" "${2:-}"
                MAP_FILE_INPUT="${2:-}"
                shift 2
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                echo "[error] Unknown argument: $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    case "$MODE" in
        submodule|clone) ;;
        *)
            echo "[error] --mode must be 'submodule' or 'clone'" >&2
            exit 1
            ;;
    esac
}

ensure_git_available() {
    if ! command -v git >/dev/null 2>&1; then
        echo "[error] git is required" >&2
        exit 1
    fi
}

ensure_root_repo_for_submodules() {
    if [ "$MODE" != "submodule" ]; then
        return
    fi
    if [ ! -d "$ROOT_DIR/.git" ]; then
        echo "[info] Initializing git repository at $ROOT_DIR"
        git -C "$ROOT_DIR" init >/dev/null
    fi
}

is_git_repo_path() {
    local path="$1"
    [ -d "$path/.git" ] || [ -f "$path/.git" ]
}

dotgit_gitdir() {
    local dotgit_file="$1"
    sed -n 's/^gitdir: //p' "$dotgit_file" 2>/dev/null | head -1
}

is_broken_dotgit_file() {
    local repo_path="$1"
    local dotgit_file="$repo_path/.git"
    [ -f "$dotgit_file" ] || return 1

    local gitdir
    gitdir="$(dotgit_gitdir "$dotgit_file")"
    if [ -z "$gitdir" ]; then
        return 0
    fi

    local resolved
    if [[ "$gitdir" = /* ]]; then
        resolved="$gitdir"
    else
        resolved="$repo_path/$gitdir"
    fi

    if [ -d "$resolved" ]; then
        return 1
    fi
    return 0
}

is_git_worktree_healthy() {
    local path="$1"
    if ! is_git_repo_path "$path"; then
        return 1
    fi
    if is_broken_dotgit_file "$path"; then
        return 1
    fi
    git -C "$path" rev-parse HEAD >/dev/null 2>&1
}

ensure_clean_target_path() {
    local path="$1"
    if [ -e "$path" ] && ! is_git_repo_path "$path"; then
        if [ -n "$(ls -A "$path" 2>/dev/null || true)" ]; then
            echo "[error] Path exists and is not a git repository: $(to_repo_relative_path "$path")" >&2
            exit 1
        fi
    fi
}

update_repo_checkout() {
    local path="$1"
    local branch="$2"

    git -C "$path" fetch origin "$branch" --tags >/dev/null 2>&1 || true

    if git -C "$path" show-ref --verify --quiet "refs/heads/$branch"; then
        git -C "$path" checkout "$branch" >/dev/null 2>&1 || true
    elif git -C "$path" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        git -C "$path" checkout -B "$branch" "origin/$branch" >/dev/null 2>&1 || true
    fi

    git -C "$path" pull --ff-only origin "$branch" >/dev/null 2>&1 || true
}

install_with_submodule() {
    local remote="$1"
    local branch="$2"
    local rel_path="$3"
    local abs_path="$4"

    ensure_clean_target_path "$abs_path"

    if is_git_repo_path "$abs_path"; then
        if is_git_worktree_healthy "$abs_path"; then
            echo "[info] Updating existing repository at $rel_path"
            update_repo_checkout "$abs_path" "$branch"
            if is_git_worktree_healthy "$abs_path"; then
                return
            fi
        fi
        echo "[info] Repairing invalid git work tree at $rel_path"
        rm -rf "$abs_path"
    fi

    if [ -f "$ROOT_DIR/.gitmodules" ] && grep -q "path = $rel_path" "$ROOT_DIR/.gitmodules"; then
        echo "[info] Initializing registered submodule $rel_path"
        git -C "$ROOT_DIR" submodule update --init --remote --force -- "$rel_path"
        update_repo_checkout "$abs_path" "$branch"
        if ! is_git_worktree_healthy "$abs_path"; then
            echo "[error] Failed to repair registered submodule: $rel_path" >&2
            exit 1
        fi
        return
    fi

    echo "[info] Adding submodule $rel_path"
    git -C "$ROOT_DIR" submodule add --force -b "$branch" "$remote" "$rel_path"
    git -C "$ROOT_DIR" submodule update --init --remote --force -- "$rel_path"
    if ! is_git_worktree_healthy "$abs_path"; then
        echo "[error] Failed to install submodule: $rel_path" >&2
        exit 1
    fi
}

install_with_clone() {
    local remote="$1"
    local branch="$2"
    local abs_path="$3"

    ensure_clean_target_path "$abs_path"

    local rel_path
    rel_path="$(to_repo_relative_path "$abs_path")"

    if is_git_repo_path "$abs_path"; then
        if is_git_worktree_healthy "$abs_path"; then
            echo "[info] Updating existing clone at $rel_path"
            update_repo_checkout "$abs_path" "$branch"
            if is_git_worktree_healthy "$abs_path"; then
                return
            fi
        fi
        echo "[info] Repairing invalid git work tree at $rel_path"
        rm -rf "$abs_path"
    fi

    echo "[info] Cloning $remote into $rel_path"
    git clone --branch "$branch" "$remote" "$abs_path"
    if ! is_git_worktree_healthy "$abs_path"; then
        echo "[error] Clone succeeded but repository is unhealthy: $rel_path" >&2
        rm -rf "$abs_path"
        exit 1
    fi
}

repo_revision() {
    local path="$1"
    git -C "$path" rev-parse HEAD 2>/dev/null || echo "unknown"
}

write_source_map() {
    local map_file="$1"
    local mode="$2"
    local codex_path="$3"
    local claude_path="$4"
    local codex_rev="$5"
    local claude_rev="$6"

    mkdir -p "$(dirname "$map_file")"

    cat > "$map_file" <<EOF_MAP
version: 1
generated_at_utc: "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
intent: "Guide LLM-led improvements to ralphie.sh using Codex and Claude Code sources without overfitting."
monorepo:
  root: "."
  subrepo_mode: "$mode"
  steering_map_file: "maps/$STEERING_MAP_BASENAME"
  subrepos:
    - id: "codex"
      provider: "openai"
      remote: "$CODEX_REMOTE"
      local_path: "$codex_path"
      branch: "$CODEX_BRANCH"
      revision: "$codex_rev"
      key_paths:
        - "AGENTS.md"
        - "README.md"
        - "codex-cli/"
        - "codex-rs/"
        - "docs/"
    - id: "claude-code"
      provider: "anthropic"
      remote: "$CLAUDE_REMOTE"
      local_path: "$claude_path"
      branch: "$CLAUDE_BRANCH"
      revision: "$claude_rev"
      key_paths:
        - "README.md"
        - "CLAUDE.md"
        - "scripts/"
        - "sdk/"
        - "docs/"
self_improvement_target:
  file: "ralphie.sh"
  objective: "Improve orchestration quality, reliability, and portability across Codex and Claude workflows."
heuristic_tools:
  scoring_dimensions:
    - id: "cross_engine_parity"
      weight: 0.35
      rule: "Prefer abstractions that benefit both engines; isolate engine-specific behavior behind explicit checks."
    - id: "reliability_and_recovery"
      weight: 0.25
      rule: "Improve retries, timeout handling, lock safety, and deterministic fallbacks."
    - id: "observability"
      weight: 0.20
      rule: "Improve logs, diagnostics, and decision traceability."
    - id: "prompt_quality"
      weight: 0.20
      rule: "Strengthen prompts with clear completion signals, bounded loops, and explicit acceptance criteria."
  anti_overfit_rules:
    - "Do not optimize for one provider output format alone."
    - "Require evidence from both subrepos before adopting tool-specific patterns."
    - "Keep behavior stable when either CLI is unavailable."
    - "Prefer capability checks and neutral interfaces over vendor-specific assumptions."
  iteration_policy:
    self_improvement_budget_fraction: 0.25
    boost_budget_fraction: 0.50
    boost_when:
      - "Plan confidence stalls for at least 3 loops."
      - "Consensus score is below threshold."
      - "Three consecutive failed or incomplete iterations occur."
    required_artifact: "research/SELF_IMPROVEMENT_LOG.md"
EOF_MAP
}

write_binary_steering_map() {
    local steering_file="$1"
    local codex_path="$2"
    local claude_path="$3"

    mkdir -p "$(dirname "$steering_file")"

    cat > "$steering_file" <<EOF_STEER
version: 1
generated_at_utc: "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
purpose: "Code references and command steering guidance for ralphie.sh engine execution paths."
engine_mode_bindings:
  plan:
    preferred_engine: "auto"
    fallback_order: ["codex", "claude"]
  plan:
    preferred_engine: "auto"
    fallback_order: ["codex", "claude"]
  build:
    preferred_engine: "auto"
    fallback_order: ["codex", "claude"]
binaries:
  codex:
    executable: "codex"
    invocation_patterns:
      default: "cat <prompt_file> | codex exec - --output-last-message <output_file>"
      yolo: "cat <prompt_file> | codex exec --dangerously-bypass-approvals-and-sandbox - --output-last-message <output_file>"
    runtime_probe:
      version: "codex --version"
      help: "codex exec --help"
    steering_constraints:
      - "Use --config overrides for transient tuning before editing the global Codex config file."
      - "Respect compatibility limits for model_reasoning_effort in the installed binary."
      - "Do not assume a specific model provider unless explicitly configured."
    source_references:
      - "$codex_path/docs/exec.md"
      - "$codex_path/docs/config.md"
      - "$codex_path/codex-rs/exec/src/cli.rs"
      - "$codex_path/sdk/typescript/src/exec.ts"
  claude:
    executable: "claude"
    invocation_patterns:
      default: "cat <prompt_file> | claude -p"
      yolo: "cat <prompt_file> | claude -p --dangerously-skip-permissions"
    runtime_probe:
      version: "claude --version"
      help: "claude --help"
    steering_constraints:
      - "Keep permission and sandbox behavior explicit; do not silently assume skip-permissions."
      - "Prefer settings-based safety controls when available."
      - "When in doubt, verify current CLI behavior with runtime --help output."
    source_references:
      - "$claude_path/README.md"
      - "$claude_path/examples/settings/README.md"
      - "$claude_path/examples/settings/settings-strict.json"
      - "$claude_path/examples/settings/settings-bash-sandbox.json"
      - "$claude_path/CHANGELOG.md"
self_heal_signatures:
  - signature: "Error loading config.toml: unknown variant \`xhigh\` ... model_reasoning_effort"
    repair_strategy: "Downgrade the global Codex config file model_reasoning_effort to a supported level (e.g., high) with backup."
EOF_STEER
}

main() {
    parse_args "$@"
    ensure_git_available

    SUBREPO_DIR_INPUT="$(trim_trailing_slash "$SUBREPO_DIR_INPUT")"

    local subrepo_dir_abs map_file_abs
    subrepo_dir_abs="$(to_abs_path "$SUBREPO_DIR_INPUT")"
    map_file_abs="$(to_abs_path "$MAP_FILE_INPUT")"
    require_within_repo_root "--subrepo-dir" "$subrepo_dir_abs"
    require_within_repo_root "--map-file" "$map_file_abs"
    local map_dir_abs steering_map_abs steering_map_rel
    map_dir_abs="$(cd "$(dirname "$map_file_abs")" && pwd)"
    steering_map_abs="$map_dir_abs/$STEERING_MAP_BASENAME"
    steering_map_rel="$(to_repo_relative_path "$steering_map_abs")"
    require_within_repo_root "--map-file" "$map_dir_abs"

    local codex_rel claude_rel codex_abs claude_abs
    codex_abs="$subrepo_dir_abs/codex"
    claude_abs="$subrepo_dir_abs/claude-code"
    codex_rel="$(to_repo_relative_path "$codex_abs")"
    claude_rel="$(to_repo_relative_path "$claude_abs")"

    mkdir -p "$subrepo_dir_abs"
    ensure_root_repo_for_submodules

    if [ "$MODE" = "submodule" ]; then
        install_with_submodule "$CODEX_REMOTE" "$CODEX_BRANCH" "$codex_rel" "$codex_abs"
        install_with_submodule "$CLAUDE_REMOTE" "$CLAUDE_BRANCH" "$claude_rel" "$claude_abs"
    else
        install_with_clone "$CODEX_REMOTE" "$CODEX_BRANCH" "$codex_abs"
        install_with_clone "$CLAUDE_REMOTE" "$CLAUDE_BRANCH" "$claude_abs"
    fi

    local codex_rev claude_rev
    codex_rev="$(repo_revision "$codex_abs")"
    claude_rev="$(repo_revision "$claude_abs")"

    write_source_map "$map_file_abs" "$MODE" "$codex_rel" "$claude_rel" "$codex_rev" "$claude_rev"
    write_binary_steering_map "$steering_map_abs" "$codex_rel" "$claude_rel"

    local map_file_rel
    map_file_rel="$(to_repo_relative_path "$map_file_abs")"
    echo "[ok] Codex source:   $codex_rel ($codex_rev)"
    echo "[ok] Claude source:  $claude_rel ($claude_rev)"
    echo "[ok] Source map:     $map_file_rel"
    echo "[ok] Steering map:   $steering_map_rel"
}

main "$@"
