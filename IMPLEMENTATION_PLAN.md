# Implementation Plan

Date: 2026-02-13
Scope: Implement spec `005` (`specs/005-atomic-lock-acquisition/spec.md`).

## Objectives

- Make lock acquisition atomic so simultaneous starts cannot yield multiple active runners.
- Preserve existing deterministic reason codes and lock diagnostics output.
- Keep behavior portable (no required external lock binary) and engine-neutral.

## Assumptions

- `flock` may not exist in the runtime environment; a portable atomic fallback is required.
- Publishing a fully-written lock file via an atomic primitive (prefer `link(2)`/`ln` hard-link; fallback: Bash `noclobber`) avoids check-then-write races and avoids exposing partially-written lock metadata.
- Changes must be validated with `bash tests/ralphie_shell_tests.sh`, plus new concurrency fixtures.

## Design Notes (Lock Backends)

- `flock` backend (when available): open the lock file without truncation (use `>>`), acquire `flock` on the file descriptor, then truncate/write metadata only after the lock is held (to preserve diagnostics under contention).
- Fallback backend (portable): write pid/timestamp metadata to a temp file, then atomically publish ownership via `ln` (hard-link) to the canonical lock path; only one contender can win the publish step.
- Stale-lock removal must be conservative: never remove an existing lock unless the holder pid is readable and proven dead.

## Phase 1: Implement Atomic Lock Backend Selection

Targets:

- `ralphie.sh`: `acquire_lock`, `release_lock`, and stale-lock recovery paths
- `research/DEPENDENCY_RESEARCH.md`: expand lock primitive references (portable fallback)

Tasks:

- [ ] Introduce a small lock-backend abstraction.
- Preferred backend: `flock` when available (optional).
- Fallback backend: portable atomic acquisition (no external binary).
- [ ] Ensure backend selection is deterministic and observable in logs (once per run).
- [ ] Keep the lock metadata contract (pid first line, timestamp second line) stable.

Validation:

- [ ] With `flock` absent, fallback backend acquires and releases correctly.
- [ ] If `flock` is present, it is selected and behaves correctly (or the script cleanly falls back).

## Phase 2: Harden Contention, Stale-Lock, And Diagnostics Under Atomic Acquisition

Targets:

- `ralphie.sh`: contention wait loop, stale-lock removal, and diagnostics

Tasks:

- [ ] Replace check-then-write acquisition with a single atomic acquisition attempt loop.
- [ ] Make stale-lock removal conservative and race-safe.
- Only remove when holder pid is readable and proven dead, or when explicitly documented criteria are met.
- Never remove a lock solely because metadata is temporarily unavailable.
- [ ] Preserve existing reason codes and messages.
- Ensure `RB_LOCK_ALREADY_HELD` for immediate contention (`--wait-for-lock 0`).
- Ensure `RB_LOCK_WAIT_TIMEOUT` for timed contention.

Validation:

- [ ] Existing lock tests continue to pass unchanged.
- [ ] Reason-code outputs remain line-stable for the contention paths.

## Phase 3: Add Concurrency Fixtures (Prove Single-Owner)

Targets:

- `tests/ralphie_shell_tests.sh`: new race fixture and backend-fallback fixture

Tasks:

- [ ] Add a race test that starts at least two concurrent processes attempting `acquire_lock` and asserts exactly one succeeds.
- [ ] Add a backend-fallback test that forces preferred backend unavailability and asserts fallback acquisition still works.

Validation:

- [ ] New tests fail on the current non-atomic implementation and pass after the change.

## Phase 4: Regression And Readiness Validation

Tasks:

- [ ] Run `bash tests/ralphie_shell_tests.sh`.
- [ ] Run a build-prerequisite check (markdown cleanliness + semantic plan gate) without needing `--force-build`.
- [ ] Mark spec `005` COMPLETE only after all acceptance criteria are met with executable evidence.

## Follow-Ups (Queued)

- Spec `007` (`specs/007-self-improvement-log-redaction/spec.md`): ensure self-heal cannot introduce markdown privacy leakage.
- Spec `006` (`specs/006-process-substitution-portability/spec.md`): remove Bash process substitution usage for restricted-shell portability.

## Traceability

- Risk 1 -> Phase 1 + 2 + 3 + 4
- Risk 7 -> follow-up (spec `007`)
- Risk 6 -> follow-up (spec `006`)

## Exit Criteria

- [ ] Concurrent starts cannot produce multiple active lock owners.
- [ ] All shell tests pass end-to-end in this environment.
- [ ] Spec `005` is marked COMPLETE with validation evidence.
