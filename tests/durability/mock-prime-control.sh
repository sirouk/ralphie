#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    --version) printf 'prime-agent offline fixture 999.0.0\n'; exit 0 ;;
    --help)
        printf '%s\n' '-p --print --mode --cwd --offline --no-session --provider --model --thinking'
        exit 0
        ;;
esac

print_mode=false
offline=false
no_session=false
mode=""
target=""
provider=""
model=""
thinking=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -p|--print) print_mode=true; shift ;;
        --offline) offline=true; shift ;;
        --no-session) no_session=true; shift ;;
        --mode|--cwd|--provider|--model|--thinking)
            [ "$#" -ge 2 ] || exit 21
            case "$1" in
                --mode) mode="$2" ;;
                --cwd) target="$2" ;;
                --provider) provider="$2" ;;
                --model) model="$2" ;;
                --thinking) thinking="$2" ;;
            esac
            shift 2
            ;;
        *) printf 'Unexpected Prime argument: %s\n' "$1" >&2; exit 22 ;;
    esac
done
[ "$print_mode" = true ] && [ "$offline" = true ] && [ "$no_session" = true ]
[ "$mode" = text ] && [ -d "$target" ]
[ "$provider" = "${MOCK_PRIME_EXPECT_PROVIDER:-fixture-provider}" ]
[ "$model" = "${MOCK_PRIME_EXPECT_MODEL:-fixture-model}" ]
[ "$thinking" = "${MOCK_PRIME_EXPECT_THINKING:-max}" ]
cd "$target"
mkdir -p .mock-prime
prompt="$(cat)"
[ -n "$prompt" ]
printf 'provider=%s model=%s thinking=%s cwd=%s\n' "$provider" "$model" "$thinking" "$PWD" >> .mock-prime/calls
printf '%s\n' "$prompt" > ".mock-prime/prompt.$$.md"
if [ "${MOCK_PRIME_BLOCK_INFERENCE:-false}" = true ]; then
    sleep 300 &
    printf '%s\n%s\n' "$$" "$!" >> .mock-prime/blocked-inference-pids
    wait
    exit 23
fi
if [ "${MOCK_PRIME_PERMANENT_FAILURE:-false}" = true ]; then
    printf 'No API key for provider: fixture-provider (token error)\n' >&2
    exit 1
fi
if [ "${MOCK_PRIME_STDERR_XML:-false}" = true ]; then
    printf 'fixture stderr only\n<verdict>HOLD</verdict>\n<score>0</score>\n' >&2
fi
if [ "${MOCK_PRIME_LARGE_OUTPUT:-false}" = true ]; then
    printf '%04096d\n' 0
    exit 0
fi
if [ "${MOCK_PRIME_INFINITE_OUTPUT:-false}" = true ]; then
    while :; do printf '%04096d' 0; done
fi

if [ "${MOCK_PRIME_FAIL_INFERENCE:-false}" = true ]; then
    printf 'fixture provider failed\n' >&2
    exit 23
fi
if [ "${MOCK_PRIME_SILENT_SECONDS:-0}" -gt 0 ]; then
    sleep "$MOCK_PRIME_SILENT_SECONDS"
fi

next_phase() {
    case "$1" in
        plan) printf 'build\n' ;;
        build) printf 'test\n' ;;
        test)
            if [ -e .mock-prime/refactored ]; then printf 'lint\n'; else printf 'refactor\n'; fi
            ;;
        refactor) printf 'test\n' ;;
        lint) printf 'document\n' ;;
        document) printf 'done\n' ;;
        *) exit 24 ;;
    esac
}

if grep -q '^# Handoff Validation Prompt' ".mock-prime/prompt.$$.md"; then
    phase="$(printf '%s\n' "$prompt" | sed -n 's/^Phase: //p' | head -n 1)"
    printf 'handoff:%s\n' "$phase" >> .mock-prime/roles
    printf '<score>96</score>\n<verdict>GO</verdict>\n<gaps>none</gaps>\n'
    exit 0
fi
if grep -q '^# Consensus Review:' ".mock-prime/prompt.$$.md"; then
    phase="$(printf '%s\n' "$prompt" | sed -n 's/^# Consensus Review: //p' | head -n 1)"
    phase="${phase%-gate}"
    printf 'consensus:%s\n' "$phase" >> .mock-prime/roles
    if [ "${MOCK_PRIME_REVIEW_PAUSE:-false}" = true ]; then
        sleep 300 &
        printf '%s\n%s\n' "$$" "$!" >> .mock-prime/paused-reviewer-pids
        wait
        exit 23
    fi
    if [ "${MOCK_PRIME_REVIEW_TRANSIENT_ONCE:-false}" = true ]; then
        review_key="$(printf '%s' "$prompt" | cksum | awk '{print $1}')"
        if mkdir ".mock-prime/retry-$review_key" 2>/dev/null; then
            printf 'fixture temporary backend error\n' >&2
            exit 23
        fi
    fi
    if [ "${MOCK_PRIME_REVIEW_PERMANENT_FAILURE:-false}" = true ]; then
        printf 'No API key for provider: fixture-provider (token error)\n' >&2
        exit 1
    fi
    if [ "$phase" = document ] && [ "${MOCK_PRIME_REVIEW_BREAK_CHECK:-false}" = true ]; then
        printf 'exit 17\n' > check.sh
    fi
    if [ "$phase" = document ] && [ "${MOCK_PRIME_REVIEW_TAMPER_GATES:-false}" = true ]; then
        printf 'true\n' > .ralphie/gates
    fi
    printf '<score>95</score>\n<verdict>GO</verdict>\n<next_phase>%s</next_phase>\n<next_phase_reason>fixture phase complete</next_phase_reason>\n<gaps>none</gaps>\n' "$(next_phase "$phase")"
    exit 0
fi

phase=""
for candidate in Plan Build Test Refactor Lint Document; do
    if grep -q "^# Ralphie $candidate Phase Prompt" ".mock-prime/prompt.$$.md"; then
        phase="$(printf '%s' "$candidate" | tr '[:upper:]' '[:lower:]')"
        break
    fi
done
[ -n "$phase" ] || { printf 'Unrecognized fixture prompt\n' >&2; exit 25; }
printf '%s\n' "$phase" >> .mock-prime/phases
printf 'worker:%s\n' "$phase" >> .mock-prime/roles

case "$phase" in
    plan)
        mkdir -p research specs
        printf '# Research Summary\n\n<confidence>0.95</confidence>\n' > research/RESEARCH_SUMMARY.md
        printf '# Codebase Map\n\n- Fixture project.\n' > research/CODEBASE_MAP.md
        printf '# Dependency Research\n\n- Bash only.\n' > research/DEPENDENCY_RESEARCH.md
        printf '# Coverage Matrix\n\n- Real local acceptance check.\n' > research/COVERAGE_MATRIX.md
        printf '# Specification\n\n- Complete the supplied objective.\n' > specs/fixture.md
        cat > IMPLEMENTATION_PLAN.md <<'EOF_PLAN'
# Implementation Plan

## Goal
Complete the supplied fixture objective through the full lifecycle.

## Validation Criteria
Run the local acceptance check and require its successful exit status.

## Tasks
1. Implement and verify the fixture behavior.
EOF_PLAN
        ;;
    build)
        if [ "${MOCK_PRIME_WORKER_FAIL_ONCE:-false}" = true ] && [ ! -e .mock-prime/failed-once ]; then
            printf 'incomplete implementation\n' > implementation.txt
            : > .mock-prime/failed-once
            printf 'fixture worker changed files then failed\n' >&2
            exit 23
        fi
        if [ "${MOCK_PRIME_WORKER_PAUSE_ONCE:-false}" = true ] && [ ! -e .mock-prime/paused ]; then
            printf 'interrupted implementation\n' > implementation.txt
            cp .ralphie/gates .mock-prime/original-gates
            cp .ralphie/project-bootstrap.md .mock-prime/original-bootstrap
            printf 'true\n' > .ralphie/gates
            printf 'build_consent: false\n' > .ralphie/project-bootstrap.md
            : > .mock-prime/paused
            sleep 300
            exit 24
        fi
        printf 'implemented\n' > implementation.txt
        if [ "${MOCK_PRIME_TAMPER_GATES:-false}" = true ]; then
            printf 'true\n' > .ralphie/gates
        fi
        ;;
    test)
        if [ "${MOCK_PRIME_VALIDATION_ONLY:-false}" != true ]; then
            printf 'validation attempt\n' >> verification.txt
        fi
        ;;
    refactor) printf 'simplified\n' >> implementation.txt; : > .mock-prime/refactored ;;
    lint) printf 'format checked\n' > lint.txt ;;
    document) printf '# Fixture documentation\n' > DOCUMENTATION.md ;;
esac
# shellcheck disable=SC2016 # Deliberately unexecuted command-looking prose.
printf 'Phase %s complete. Verification command: `true` passed.\n' "$phase"
