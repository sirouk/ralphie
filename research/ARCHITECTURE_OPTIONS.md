# Architecture Options

Date: 2026-02-13
Decision target: final prepare-cycle scope before next build execution.

## Option A: In-place lock hardening in `ralphie.sh` (Recommended)

Description:
- Keep single-script orchestration.
- Add deterministic reason codes to all lock-failure exits.
- Add richer lock diagnostics (pid, age, command best-effort).
- Add lock-aware smoke guidance and targeted shell tests.

Pros:
- Fastest path to close the remaining high-impact readiness gap.
- No new runtime dependencies.
- Preserves current operational model.

Cons:
- Lock logic complexity remains concentrated in one script.

## Option B: Extract lock module (`lib/lock.sh`)

Description:
- Move lock acquisition/release and diagnostics into a sourced library.

Pros:
- Cleaner boundaries and easier direct unit-like testing.
- Better maintainability for future lock features.

Cons:
- Medium migration risk in this cycle.
- More file-level coordination overhead now.

## Option C: Replace file lock with external state helper

Description:
- Use a sidecar utility (typed language) for lock lifecycle and stale-state management.

Pros:
- Stronger process/state modeling.
- Easier future extension (metrics, richer introspection).

Cons:
- Adds dependency and packaging overhead.
- Too heavy for current objective.

## Weighted comparison (0-5)

Weights from `maps/agent-source-map.yaml`:
- cross_engine_parity: 0.35
- reliability_and_recovery: 0.25
- observability: 0.20
- prompt_quality: 0.20

Scores:
- Option A: 4.7
- Option B: 3.9
- Option C: 2.8

## Decision
Choose Option A for the next build cycle. Defer Option B unless lock incidents persist after spec `004` is completed and validated.
