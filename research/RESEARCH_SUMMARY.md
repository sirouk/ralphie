# Research Summary

Date: 2026-02-13
Mode: Prepare (Research + Plan + Spec)
Iteration: 6 (current prepare cycle)

## Repository Mapping Findings

- Repository runtime is centered in a single orchestrator: `ralphie.sh`.
- Supporting executable surfaces are limited to `scripts/setup-agent-subrepos.sh` and `tests/ralphie_shell_tests.sh`.
- Durable planning artifacts include:
  - `IMPLEMENTATION_PLAN.md`
  - `specs/`
  - `research/` (including map/dependency/coverage docs)
- Human queue input file `HUMAN_INSTRUCTIONS.md` is not currently present.
- `subrepos/` is present, but in this workspace `subrepos/*` are not valid git work trees (`git -C subrepos/<name>` fails). Treat subrepo content as a source snapshot unless repaired via setup flows.

## First-Principles Assessment

- Previously high-severity build-gate gaps were confirmed and closed:
  - Lock acquisition is atomic and contention diagnostics are deterministic (spec `005` COMPLETE; atomic race + backend fallback fixtures added).
  - Process substitution has been eliminated from core paths to improve portability (spec `006` COMPLETE; no `> >(...)` or `< <(...)` remains; FIFO session logging fixture added).
  - Self-heal/self-improvement logging redacts home paths in markdown artifacts (spec `007` COMPLETE; focused redaction fixture added).
- Verified evidence (this environment):
  - `bash tests/ralphie_shell_tests.sh` passes end-to-end.
  - `check_build_prerequisites` passes with current durable artifacts (covered by the shell test suite).

## Architecture Proposal

- Keep single-file orchestration (`ralphie.sh`).
- Keep engine-specific behavior isolated to invocation boundaries (`run_agent_with_prompt`, capability probes).
- Next scope after clearing build-gate blockers: close medium gaps in `research/COVERAGE_MATRIX.md` (setup-script integration harness, human queue + notification fixtures, prompt-generation policy fixtures).

## Self-Critique

- The initial atomic-lock implementation had a correctness bug in `try_acquire_lock_atomic`: capturing `$?` after an `if ...; then ...; fi` can yield `0` even when the acquisition attempt failed in Bash 3.2. This could incorrectly allow multiple active runners. The fix now captures return codes in the `else` branch and is regression-tested.
- Subrepo evidence remains snapshot-based in this workspace because `subrepos/*` are not valid git work trees; avoid overfitting to assumed submodule behaviors without repairing setup/update flows.
- YAML fallback-order parsing in `mode_fallback_order` remains string-based and brittle (medium risk).

## External Research Per Major Dependency/Module

Dependency-by-dependency primary references are listed in `research/DEPENDENCY_RESEARCH.md`.

## Map-Guided Critique (Required)

Source map active: `maps/agent-source-map.yaml`
Binary steering map active: `maps/binary-steering-map.yaml`

Evidence sampled from both source families:

- Codex:
  - `subrepos/codex/codex-rs/exec/src/cli.rs`
  - `subrepos/codex/sdk/typescript/src/exec.ts`
  - `subrepos/codex/docs/exec.md`
- Claude:
  - `subrepos/claude-code/README.md`
  - `subrepos/claude-code/examples/settings/README.md`
  - `subrepos/claude-code/CHANGELOG.md`

Anti-overfit rules applied:

- No provider-specific parsing assumptions were added.
- Engine-specific flags remain isolated to runtime invocation boundaries.
- Fallback behavior remains required when either CLI is unavailable.

Decision: with build-gate blockers closed, prioritize medium-gap test coverage and setup-script integration hardening next.

## Confidence By Component

- Constitution and policy compliance: 99
- Codebase surface mapping completeness: 96
- External dependency verification quality: 94
- Cross-engine parity posture: 95
- Lock correctness readiness: 95
- Process-substitution portability readiness: 90
- Self-improvement log privacy readiness: 95
- Overall build-readiness confidence: 93

## Readiness Judgment

Build-gate blockers noted in `consensus/build-gate_20260213_103835_consensus.md` are closed and verified by the shell test suite; remaining gaps are medium-severity and tracked in `research/COVERAGE_MATRIX.md`.

<confidence>93</confidence>
<needs_human>false</needs_human>
<human_question></human_question>

