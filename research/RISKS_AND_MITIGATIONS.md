# Risks And Mitigations

Date: 2026-02-13

## Risk Register

1. Lock contention can prevent parity smokes and delay build entry.
- Severity: High
- Evidence: active lock holder observed (`.ralphie/run.lock`, pid `87111`) during prepare planning.
- Mitigation: implement lock-aware verification strategy and deterministic lock-failure reason codes.
- Validation: add lock contention tests and documented fallback verification path.

2. Immediate lock-fail path (`--wait-for-lock 0`) lacks machine-readable reason code.
- Severity: High
- Impact: automation cannot classify failure class consistently.
- Mitigation: emit explicit reason code for non-wait lock rejection path.
- Validation: shell test asserting reason code output for immediate lock fail.

3. Lock diagnostics are insufficient for stale/long-running holder triage.
- Severity: Medium
- Impact: operators may remove locks without enough evidence.
- Mitigation: log lock holder pid, lock age, and holder command best-effort before exit.
- Validation: fixture tests for diagnostic output and safe fallback when `ps` metadata is unavailable.

4. Provider CLI contract drift can break invocation flags.
- Severity: Medium
- Mitigation: preserve runtime capability probes and neutral fallback order.
- Validation: keep `--doctor` checks and periodic dual-engine smoke tasks in plan.

5. Cross-engine overfit during reliability fixes.
- Severity: Medium
- Mitigation: enforce map anti-overfit rules and paired Codex/Claude evidence for behavior changes.
- Validation: update `research/SELF_IMPROVEMENT_LOG.md` with paired-source evidence before implementation recommendations.

## Residual Risk
Environmental concurrency remains a residual risk because external long-lived runs can still hold the lock. Planned hardening reduces ambiguity and improves recovery without changing core locking model.
