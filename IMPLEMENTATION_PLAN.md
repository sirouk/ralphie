# Implementation Plan

Date: 2026-02-13
Scope: Implement spec `004` (`specs/004-lock-contention-observability/spec.md`).

## Objectives

- Close the final high-impact prepare gap: lock contention diagnosis and deterministic recovery behavior.
- Preserve neutral orchestration and cross-engine parity.
- Improve operator and automation visibility without changing core execution flow.

## Assumptions

- Active concurrent runs are expected in this repo and may hold lock for long periods.
- Shell tests are the fastest reliable guardrail for lock behavior.
- Locking remains file-based for this cycle.

## Phase 1: Lock Failure Reason-Code Completeness

Targets:
- `ralphie.sh`: `acquire_lock`
- `tests/ralphie_shell_tests.sh`

Tasks:
- [x] Add explicit reason code for immediate lock rejection path (`--wait-for-lock 0`).
- [x] Ensure timeout path remains deterministic and includes wait metadata.
- [x] Add tests for both immediate and timeout lock-fail paths.

Validation:
- [x] Tests assert exact reason codes for both paths.

## Phase 2: Lock Observability Hardening

Targets:
- `ralphie.sh`: lock diagnostics helper(s)
- `tests/ralphie_shell_tests.sh`

Tasks:
- [x] Log lock holder pid + best-effort command on failure.
- [x] Log lock age when timestamp is present in lock file.
- [x] Keep safe fallback when metadata lookup fails.

Validation:
- [x] Tests cover metadata present and metadata missing scenarios.

## Phase 3: Verification And Readiness Confirmation

Tasks:
- [x] Run `bash tests/ralphie_shell_tests.sh`.
- [x] Run `./ralphie.sh --doctor`.
- [x] Confirm spec `004` acceptance criteria are satisfied.
- [x] Mark `specs/004-lock-contention-observability/spec.md` status `COMPLETE`.

Completed:
- [x] `bash tests/ralphie_shell_tests.sh` passed with lock contention fixtures.
- [x] `./ralphie.sh --doctor` succeeded and reported expected environment readiness.

## Traceability

- Risk 1 -> Phase 1 + 3
- Risk 2 -> Phase 1
- Risk 3 -> Phase 2
- Risk 4 -> Phase 3
- Risk 5 -> Phase 1 + 2

## Exit Criteria

- [x] All phase validations pass.
- [x] Spec `004` is marked COMPLETE.
- [x] No unresolved high-severity lock observability risk remains.
