# Implementation Plan

Date: 2026-02-13
Scope: Close remaining medium-severity coverage gaps after completing specs `005`-`007`.

## Goal

Raise confidence in autonomous operation by adding test coverage and (where necessary) small refactors for the remaining uncovered runtime surfaces identified in `research/COVERAGE_MATRIX.md`.

## Done Criteria (Validation / Definition Of Done)

- `bash tests/ralphie_shell_tests.sh` passes.
- `research/COVERAGE_MATRIX.md` shows concrete progress on at least one medium gap (`S6`, `S7`, or `S8`) with a linked spec and test coverage notes.
- New/updated specs include clear Acceptance Criteria sections.

## Phase 1: Human Queue Ingestion Coverage (S6)

- [x] Add a dedicated spec for human queue ingestion and escalation behavior: `specs/008-human-queue-ingestion/spec.md`.
- [x] Add focused shell tests for:
  - parsing of `Status: NEW` requests
  - prompt injection of the human queue when `HUMAN_INSTRUCTIONS.md` exists
  - non-interactive behavior (no prompts; deterministic result)
  - idempotence (NEW -> processed/acknowledged flow, if supported)

## Phase 2: Notification Behavior Coverage (S7)

- [x] Add a dedicated spec for `notify_human` channel behavior and failure modes: `specs/009-notification-channels/spec.md`.
- [x] Add focused shell tests for:
  - `terminal` channel output path
  - `telegram` and `discord` channel selection with missing env vars (deterministic failure without leaking secrets)
  - `none` channel is a no-op

## Phase 3: Setup/Subrepo Refresh Harness (S8)

- [x] Add a dedicated spec for `scripts/setup-agent-subrepos.sh` covering partially-initialized subrepo states: `specs/010-setup-agent-subrepos-refresh/spec.md`.
- [x] Add a test harness strategy:
  - prefer mocked `git` in `PATH` to simulate failure modes deterministically, or
  - introduce a `--dry-run`/`--no-network` mode that exercises logic without fetching.
- [x] Add one focused test proving the script handles the partial-init case without leaving the repo in a broken state.

## Phase 4: Documentation And Gate Alignment

- [x] Update `research/CODEBASE_MAP.md` and `research/RISKS_AND_MITIGATIONS.md` for any behavioral changes.
- [x] Ensure new artifacts comply with the markdown privacy/transcript gate (`markdown_artifacts_are_clean`).

## Notes

- Build-gate blockers from `consensus/build-gate_20260213_103835_consensus.md` were closed by completing specs `005`-`007` and validating via the shell test suite.
