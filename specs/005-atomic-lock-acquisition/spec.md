# 005 - Atomic Lock Acquisition And Contention Correctness

## Context

`ralphie.sh` currently uses file-based lock ownership in `acquire_lock`. Under simultaneous starts, check-then-write lock behavior can allow race conditions and concurrent execution.

## Requirements

- Use atomic lock acquisition semantics.
- Preserve deterministic lock-failure reason codes.
- Keep lock behavior portable and engine-neutral.
- Retain or improve current lock diagnostics.

## Acceptance Criteria (Testable)

1. Simultaneous process starts cannot produce multiple active lock owners.
2. Lock backend selection is deterministic: preferred backend plus atomic fallback backend when preferred backend is unavailable.
3. Immediate contention path (`--wait-for-lock 0`) emits `RB_LOCK_ALREADY_HELD`.
4. Timed contention path emits `RB_LOCK_WAIT_TIMEOUT` with waited duration and lock path metadata.
5. Lock diagnostics still include holder pid and best-effort command where available.
6. Lock diagnostics still include lock age when timestamp parsing succeeds.
7. Existing stale-lock recovery behavior is preserved or explicitly documented when backend differs.
8. Shell tests include a race fixture and backend-fallback fixture.

## Verification Steps

1. Run `bash tests/ralphie_shell_tests.sh`.
2. Run race fixture test that launches concurrent lock attempts.
3. Run fallback fixture test where preferred lock backend is unavailable.
4. Verify contention failure logs for required reason-code and metadata fields.

## Status: COMPLETE
