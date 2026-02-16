# Ralphie Constitution

## Purpose
- Establish deterministic, portable, and reproducible control planes for autonomous execution.
- Define behavior for all phases from planning through documentation.

## Governance
- Keep artifacts machine-readable: avoid local absolute paths, avoid command transcript leakage, and keep logs deterministic.
- Never skip consensus checks or phase schema checks.
- Treat gate failures as actionable signals, not terminal failure when bounded retries remain.
- Preserve context through deterministic evidence (prompt file lineage, stack discovery inputs, and consensus snapshots).

## Phase Contracts
- **Plan** produces research artifacts, an explicit implementation plan, and a deterministic stack snapshot.
- **Build** executes plan tasks against evidence in `IMPLEMENTATION_PLAN.md` and validates build schema.
- **Test** verifies behavior changes and records validation evidence.
- **Refactor** preserves behavior, reduces complexity, and documents rationale.
- **Lint** enforces deterministic quality and cleanup policies.
- **Document** closes the lifecycle with updated user-facing documentation.

## Transition Contracts
- Resume behavior is default; missing/invalid prerequisites for resumed phase MUST trigger fallback to `plan`.
- All phase transitions require phase schema checks, consensus checks, and completion-signal hygiene.
- Plan outputs from a prior run may only transition to Build when stack snapshot, plan consistency, and build preconditions are clean.
- Bounded retry mechanisms may retry a blocked phase with updated feedback; hard stop only occurs when budgets are exhausted and blockers are persisted.

## Recovery and Retry Policy
- Every phase attempt that fails schema, consensus, or transition checks is retried within
  `PHASE_COMPLETION_MAX_ATTEMPTS` using feedback from prior blockers.
- Hard stop occurs only after bounded retries are exhausted and gate feedback is persisted.
- Retry and session safety are additionally bounded by `MAX_SESSION_CYCLES`, optional token budget, and optional cost budget.

## Mutation and Drift Policy
- Worktree mutation intent is controlled via per-phase no-op policy and profile (`hard`, `soft`, `none`).
- Artifact hygiene (transcript leakage, local absolute path leakage, and explicit local fingerprints) must be clean before build transition.
- Artifact repair may be applied automatically only when `AUTO_REPAIR_MARKDOWN_ARTIFACTS` is enabled, and must be included in gate feedback before retry.
- `--resume` is default; fallback persistence must record `last_gate_feedback` for non-actionable states.

## Evidence Requirements
- Each phase writes machine-readable completion signal `<promise>DONE</promise>`.
- Plan/build/test/refactor/lint/document outputs must be reviewed by consensus and schema checks before transition.
- `IMPLEMENTATION_PLAN.md`, research artifacts, and review artifacts must include concrete, machine-parseable rationale and failure handling.

## Environment Scope
- Repository-relative paths and relative markdown links are preferred.
- External references are allowed only when version/risk tradeoffs are explicitly documented.
