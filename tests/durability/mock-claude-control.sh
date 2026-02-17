#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${MOCK_CLAUDE_STATE_DIR:-.mock-claude}"
mkdir -p "$STATE_DIR"

is_true() {
    case "${1:-}" in
        1|[Yy]|[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

default_next_phase() {
    case "${1:-}" in
        plan) echo "build" ;;
        build) echo "test" ;;
        test) echo "refactor" ;;
        refactor) echo "lint" ;;
        lint) echo "document" ;;
        document) echo "done" ;;
        *) echo "done" ;;
    esac
}

emit_help() {
    cat <<'HELP'
Usage: claude [options] [prompt]
  -p, --print                              Print mode
  --dangerously-skip-permissions           Skip permissions (mock)
  --model <model>                          Model selector (mock)
  --settings <json>                        Settings payload (mock)
This mock advertises read/write/tool capabilities for orchestrator probing.
HELP
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "help" ]; then
    emit_help
    exit 0
fi
if [ "${1:-}" = "--version" ] || [ "${1:-}" = "version" ]; then
    echo "mock-claude-control 1.0.0"
    exit 0
fi

prompt=""
if [ ! -t 0 ]; then
    prompt="$(cat)"
fi

# Handle engine smoke canary prompts.
canary_token="$(printf '%s\n' "$prompt" | sed -n 's/.*Reply with ONLY this exact token[^:]*: \([^[:space:]]*\).*/\1/p' | head -n 1)"
if [ -n "$canary_token" ]; then
    echo "$canary_token"
    exit 0
fi

# Handoff validator behavior.
if printf '%s' "$prompt" | grep -q '^# Handoff Validation Prompt'; then
    if is_true "${MOCK_CLAUDE_INJECT_HANDOFF_HOLD_ONCE:-false}" && [ ! -f "$STATE_DIR/handoff_hold_once.done" ]; then
        : > "$STATE_DIR/handoff_hold_once.done"
        cat <<'EOF_HOLD'
<score>55</score>
<verdict>HOLD</verdict>
<gaps>simulated_handoff_hold_once</gaps>
EOF_HOLD
    else
        cat <<'EOF_GO'
<score>96</score>
<verdict>GO</verdict>
<gaps>none</gaps>
EOF_GO
    fi
    exit 0
fi

# Consensus reviewer behavior.
if printf '%s' "$prompt" | grep -q '^# Consensus Review:'; then
    stage="$(printf '%s\n' "$prompt" | sed -n 's/^# Consensus Review: //p' | head -n 1)"
    base_stage="${stage%-gate}"
    next_phase="$(default_next_phase "$base_stage")"

    if is_true "${MOCK_CLAUDE_INJECT_CONSENSUS_HOLD_ONCE:-false}" && [ ! -f "$STATE_DIR/consensus_hold_once.done" ]; then
        : > "$STATE_DIR/consensus_hold_once.done"
        cat <<'EOF_CONS_HOLD'
<score>52</score>
<verdict>HOLD</verdict>
<next_phase>plan</next_phase>
<next_phase_reason>simulated_consensus_hold_once</next_phase_reason>
<gaps>simulated_consensus_hold_once</gaps>
EOF_CONS_HOLD
    else
        cat <<EOF_CONS_GO
<score>94</score>
<verdict>GO</verdict>
<next_phase>${next_phase}</next_phase>
<next_phase_reason>controlled_mock_consensus</next_phase_reason>
<gaps>none</gaps>
EOF_CONS_GO
    fi
    exit 0
fi

ensure_plan_artifacts() {
    mkdir -p research specs .specify/memory src tests docs

    cat > research/RESEARCH_SUMMARY.md <<'EOF_RS'
# Research Summary

<confidence>0.91</confidence>

- Controlled-environment mapping completed.
- Primary runtime target confirmed.
EOF_RS

    cat > research/CODEBASE_MAP.md <<'EOF_CM'
# Codebase Map

- `ralphie.sh`: orchestration runtime.
- `tests/`: durability and smoke harnesses.
EOF_CM

    cat > research/DEPENDENCY_RESEARCH.md <<'EOF_DR'
# Dependency Research

- Bash runtime and standard UNIX utilities.
- Optional external engines for orchestration calls.
EOF_DR

    cat > research/COVERAGE_MATRIX.md <<'EOF_COV'
# Coverage Matrix

| gate | status |
| --- | --- |
| plan artifacts | complete |
| build prerequisites | complete |
EOF_COV

    cat > research/STACK_SNAPSHOT.md <<'EOF_SS'
# Stack Snapshot

## Project Stack Ranking
- Node.js
- Bash
EOF_SS

    cat > IMPLEMENTATION_PLAN.md <<'EOF_IP'
# Implementation Plan

## Goal
- Validate all orchestration phases in a controlled harness.

## Validation Criteria
- All phases reach handoff and consensus GO.
- Session ends with `CURRENT_PHASE="done"`.

## Tasks
1. Execute controlled build path.
2. Execute controlled test path.
3. Execute controlled refactor path.
4. Execute controlled lint path.
5. Execute controlled documentation path.
EOF_IP

    cat > specs/project_contracts.md <<'EOF_PC'
# Project Contracts

- Research artifacts must exist before build.
- Plan must remain semantically actionable.
EOF_PC

    cat > .specify/memory/constitution.md <<'EOF_CONS'
# Constitution

- Preserve deterministic and auditable execution.
EOF_CONS
}

emit_phase_completion() {
    local phase="$1"
    local count_file="$STATE_DIR/${phase}.count"
    local call_count=0
    if [ -f "$count_file" ]; then
        call_count="$(cat "$count_file" 2>/dev/null || echo 0)"
    fi
    case "$call_count" in
        ''|*[!0-9]*) call_count=0 ;;
    esac
    call_count=$((call_count + 1))
    printf '%s\n' "$call_count" > "$count_file"

    cat <<EOF_PHASE
Updated artifacts:
- ${phase} phase controlled outputs
- ${phase} attempt marker ${call_count}
Assumptions made:
- controlled mock claude execution
Blockers/risks:
- none
Phase status: ${phase} complete.
EOF_PHASE
}

if printf '%s' "$prompt" | grep -q '^# Ralphie Plan Phase Prompt'; then
    if [ -n "${MOCK_CLAUDE_SLEEP_PLAN_SECONDS:-}" ] && [ "${MOCK_CLAUDE_SLEEP_PLAN_SECONDS:-0}" -gt 0 ] 2>/dev/null; then
        sleep "${MOCK_CLAUDE_SLEEP_PLAN_SECONDS}"
    fi
    ensure_plan_artifacts
    echo "phase=plan" >> "$STATE_DIR/phase_trace.log"
    emit_phase_completion "plan"
    exit 0
fi

if printf '%s' "$prompt" | grep -q '^# Ralphie Build Phase Prompt'; then
    mkdir -p src
    printf 'build artifact generated at %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > src/controlled-build.txt
    echo "phase=build" >> "$STATE_DIR/phase_trace.log"
    emit_phase_completion "build"
    exit 0
fi

if printf '%s' "$prompt" | grep -q '^# Ralphie Test Phase Prompt'; then
    mkdir -p tests
    printf 'test pass marker\n' > tests/controlled-test-report.txt
    echo "phase=test" >> "$STATE_DIR/phase_trace.log"
    emit_phase_completion "test"
    exit 0
fi

if printf '%s' "$prompt" | grep -q '^# Ralphie Refactor Phase Prompt'; then
    mkdir -p src
    printf 'refactor marker\n' >> src/controlled-build.txt
    echo "phase=refactor" >> "$STATE_DIR/phase_trace.log"
    emit_phase_completion "refactor"
    exit 0
fi

if printf '%s' "$prompt" | grep -q '^# Ralphie Lint Phase Prompt'; then
    mkdir -p reports
    printf 'lint=clean\n' > reports/controlled-lint.txt
    echo "phase=lint" >> "$STATE_DIR/phase_trace.log"
    emit_phase_completion "lint"
    exit 0
fi

if printf '%s' "$prompt" | grep -q '^# Ralphie Document Phase Prompt'; then
    mkdir -p docs
    printf '# Controlled Documentation\n\nGenerated by mock claude harness.\n' > docs/CONTROLLED_DOC.md
    echo "phase=document" >> "$STATE_DIR/phase_trace.log"
    emit_phase_completion "document"
    exit 0
fi

cat <<'EOF_DEFAULT'
<score>90</score>
<verdict>GO</verdict>
<gaps>none</gaps>
EOF_DEFAULT
