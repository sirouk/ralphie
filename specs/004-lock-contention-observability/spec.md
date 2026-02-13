# 004 - Lock Contention Observability And Recovery

## Context

Build-readiness is mostly complete. The highest remaining gap is lock contention diagnosis and deterministic automation behavior when an active run already holds `.ralphie/run.lock`.

## Requirements

- Emit machine-readable reason codes for all lock-contention exits.
- Improve lock diagnostics without provider-specific assumptions.
- Keep lock behavior portable and neutral across Codex and Claude paths.
- Add tests proving contention behavior and diagnosis output.

## Acceptance Criteria (Testable)

1. `acquire_lock` emits a deterministic reason code when lock acquisition fails immediately (`--wait-for-lock 0`).
2. `acquire_lock` emits timeout reason code with wait duration and lock path on timed wait expiry.
3. Lock-failure logs include holder pid and best-effort holder command when available.
4. Lock-failure logs include lock age when timestamp is available in lock file.
5. Behavior remains unchanged when holder metadata cannot be resolved (`ps` unavailable or pid gone).
6. Shell tests cover immediate-fail, timed-wait-timeout, stale-lock cleanup, and diagnostics fallback.
7. `./ralphie.sh --doctor` continues to pass after lock hardening.

## Verification Steps

1. Run `bash tests/ralphie_shell_tests.sh`.
2. Run `./ralphie.sh --doctor`.
3. Execute lock-contention fixture tests that simulate:
- live holder with wait disabled
- live holder with timeout
- stale lock file
- missing process metadata

## Status: COMPLETE
