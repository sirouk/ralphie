# 003 - Consensus Concurrency And Output Contract Hardening

## Context

Remaining build-readiness blockers are in:
- `check_build_prerequisites` plan-quality semantics
- `extract_tag_value` fallback parsing behavior
- Claude output/log handling in `run_agent_with_prompt`
- missing explicit proof of `SWARM_MAX_PARALLEL` enforcement in `run_swarm_consensus`

## Requirements

- Enforce semantic build-prerequisite validation.
- Preserve required plan tags under noisy output conditions.
- Separate Claude runtime logs from primary output artifacts.
- Prove reviewer execution is bounded by configured parallelism.
- Preserve neutral orchestration across Codex and Claude.

## Acceptance Criteria (Testable)

1. `check_build_prerequisites` passes for semantically actionable plans even without open checkboxes.
2. `check_build_prerequisites` fails for shallow plans and emits a build-prereq reason code.
3. `extract_tag_value` parses ordered file candidates and returns the first valid tag match.
4. `confidence`, `needs_human`, and `human_question` parse correctly when tags are present only in fallback files.
5. Claude execution path no longer writes runtime stream and final output to the same artifact file.
6. Tests prove active reviewer jobs never exceed `SWARM_MAX_PARALLEL`.
7. Existing consensus-failure-threshold behavior remains green.
8. One-iteration plan smoke checks pass for both `--engine codex` and `--engine claude`.

## Verification Steps

1. Run `bash tests/ralphie_shell_tests.sh`.
2. Run `./ralphie.sh --doctor`.
3. Run `./ralphie.sh --engine codex plan --max 1`.
4. Run `./ralphie.sh --engine claude plan --max 1`.
5. Inspect output artifacts for required tags and transcript-leakage absence.

## Status: COMPLETE
