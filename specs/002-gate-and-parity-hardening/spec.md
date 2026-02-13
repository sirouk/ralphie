# 002 - Gate And Parity Hardening

## Context

Prepare/build transitions currently rely on basic artifact existence checks and consensus scoring. Engine invocations also depend on CLI flags that may drift across versions.

## Requirements

- Harden prepare/build gates with quality checks.
- Improve cross-engine invocation reliability with capability probing.
- Keep failure behavior deterministic and diagnosable.

## Acceptance Criteria (Testable)

1. Script probes support for critical engine flags before use.
2. If a critical flag is unsupported, script logs a warning and falls back safely.
3. Build/prepare gate checks include artifact quality checks (not just file presence).
4. Consensus is marked invalid when reviewer command failures exceed threshold.
5. Logs include machine-readable reason codes for gate failures.
6. Tests cover codex and claude paths for new logic.

## Verification Steps

1. Run script in environments with and without each CLI and verify fallback behavior.
2. Run tests for parsing, gating, and consensus-failure scenarios.
3. Inspect logs for explicit reason codes and actionable diagnostics.

## Status: COMPLETE
