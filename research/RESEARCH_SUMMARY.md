# Research Summary

Date: 2026-02-13
Mode: Prepare (Research + Plan + Spec)
Iteration: 5 (current prepare cycle)

## Repository Mapping Findings

- Repository runtime is centered in a single orchestrator: `ralphie.sh`.
- Supporting executable surfaces are limited to `scripts/setup-agent-subrepos.sh` and `tests/ralphie_shell_tests.sh`.
- Durable planning artifacts now include:
  - `IMPLEMENTATION_PLAN.md`
  - `specs/`
  - `research/` (including map/dependency/coverage docs)
- Human queue input file `HUMAN_INSTRUCTIONS.md` is not currently present.
- `subrepos/` is present, but in this workspace `git -C subrepos/<name>` fails due to missing submodule gitdir targets; map refresh should be treated as "best-effort" unless repaired.

## First-Principles Assessment

- Two top reliability risks are now clear:
  - Lock acquisition is not atomic (`acquire_lock` is check-then-write), so simultaneous starts can race.
  - Bash process substitution (`>(...)`) may be blocked in restricted shells, which can break session logging and Claude output capture.
- Verified evidence (this environment): `bash tests/ralphie_shell_tests.sh` passes end-to-end (including Claude output/log separation).
- Verified evidence (this repo): `check_build_prerequisites` passes with current durable artifacts.
- Additional policy-compliance risk discovered: the self-heal path (`self_heal_codex_reasoning_effort_xhigh`) appends absolute paths to `research/SELF_IMPROVEMENT_LOG.md`, which can trip the markdown privacy gate.

## Architecture Proposal

- Keep single-file orchestration (`ralphie.sh`).
- Next build scope: atomic lock acquisition (spec `005`) with deterministic reason codes and engine-neutral behavior.
- Follow-up scope: remove process substitution usage (spec `006`) to harden portability in restricted shells.
- Follow-up scope: enforce markdown artifact path redaction for self-heal/self-improvement logging (spec `007`).
- Keep engine-specific behavior isolated to invocation boundaries (`run_agent_with_prompt`, capability probes).

## Self-Critique

- Prior artifacts treated spec `003` as COMPLETE, but did not account for environments where Bash process substitution is disallowed.
- Earlier prioritization of spec `006` assumed a local test failure that was not reproduced; ordering is updated to reflect verified test results.
- YAML fallback-order parsing in `mode_fallback_order` is string-based and brittle; this remains a medium risk.
- `flock` is not guaranteed to exist (it is absent in this environment), so spec `005` must include a portable atomic fallback backend.

## Plan Improvements Applied

- Updated `IMPLEMENTATION_PLAN.md` to scope the next build cycle to spec `005`.
- Added new incomplete spec: `specs/007-self-improvement-log-redaction/spec.md` (policy guard: no absolute paths/local identity in markdown artifacts).
- Refined the spec `005` approach notes with a concrete atomic fallback strategy (temp-file metadata + atomic publish via `link(2)`/`ln`) and `flock` truncation hazards.
- Expanded `research/DEPENDENCY_RESEARCH.md` with primary references for atomic lock primitives and Bash redirection semantics.
- Re-validated `bash tests/ralphie_shell_tests.sh` passes in this environment to ground planning claims in executable evidence.
- Removed example home-directory absolute-path strings from markdown artifacts to align with the project output policy (avoid absolute workstation paths in committed docs).

## External Research Per Major Dependency/Module

Dependency-by-dependency primary references are listed in `research/DEPENDENCY_RESEARCH.md`.
Key external docs for Codex/Claude/Bash/coreutils/man-pages were re-validated for availability on 2026-02-13; local subrepo sources remain the strongest evidence for flag/behavior alignment.

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

Decision: prioritize lock correctness (spec `005`) next; keep portability hardening (spec `006`) queued after correctness is proven.

## Confidence By Component

- Constitution and policy compliance: 99
- Codebase surface mapping completeness: 96
- External dependency verification quality: 94
- Cross-engine parity posture: 95
- Lock correctness readiness (after planning, before implementation): 78
- Process-substitution portability readiness (after planning, before implementation): 70
- Self-improvement log privacy readiness (after planning, before implementation): 62
- Overall build-readiness confidence: 87

## Readiness Judgment

Preparation is complete for a bounded implementation cycle focused on atomic lock acquisition (correctness), with portability and markdown privacy hardening queued next.

<confidence>87</confidence>
<needs_human>false</needs_human>
<human_question></human_question>
