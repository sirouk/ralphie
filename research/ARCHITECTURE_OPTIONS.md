# Architecture Options

Date: 2026-02-13
Decision target: lock correctness, portability, and cross-engine parity reliability.

## Option A: Keep Legacy Check-Then-Write Lock File

Description:

- Keep legacy `acquire_lock` flow unchanged.
- Continue relying on contention wait + diagnostics only.

Pros:

- Zero implementation effort.
- No new primitives.

Cons:

- Non-atomic acquisition can permit dual runners under race.
- Reliability risk remains unresolved.

## Option B: Hybrid Atomic Locking (Recommended)

Description:

- Preferred backend: write metadata to a temp file, then atomically publish ownership via `link(2)`/`ln` (hard-link) to the canonical lock path (avoids partially-written metadata becoming visible).
- Atomic fallback backend: Bash `noclobber` (`set -C`) to atomically create the canonical lock file when hard links are unavailable or fail unexpectedly.
- Preserve current reason codes and diagnostics contracts.

Pros:

- Closes highest-risk race window.
- Preserves cross-engine neutrality.
- Keeps deterministic automation behavior.

Cons:

- Moderate implementation/test complexity.
- Requires careful fallback parity between backends.

## Option C: Keep File Lock but Add Post-Acquire Verification

Description:

- Continue file lock writes, then add immediate read-back consistency checks.

Pros:

- Smaller code change than backend abstraction.

Cons:

- Still weaker than true atomic lock primitives.
- Harder to reason about correctness under heavy contention.

## Weighted Comparison (0-5)

Weights from `maps/agent-source-map.yaml`:

- `cross_engine_parity`: 0.35
- `reliability_and_recovery`: 0.25
- `observability`: 0.20
- `prompt_quality`: 0.20

Scores:

- Option A: 2.7
- Option B: 4.7
- Option C: 3.4

## Decision

Implemented Option B (spec `005` COMPLETE).

Notes:

- Engine-specific behavior stays at invocation boundaries only.
- Lock backend choice must remain independent of Codex/Claude mode.

## Logging And Session Capture Portability

Problem:

- `ralphie.sh` previously relied on Bash process substitution (`>(...)` / `< <(...)`) for session logging and some capture/loop helpers.
- Some restricted shells/sandboxes block process substitution, which can break execution in those environments.
- This remains a portability risk unless process substitution is eliminated from core paths.

### Option D: Keep Process Substitution

Description:

- Retain `exec > >(tee -a "$SESSION_LOG") 2>&1` and the existing Claude capture approach.

Pros:

- Simple and idiomatic Bash in unconstrained environments.

Cons:

- Fails outright in environments where process substitution is disallowed.
- Blocks test-driven progress and portability.

### Option E: FIFO-Based Tee (Recommended)

Description:

- Replace process substitution with an explicit `mkfifo` + background `tee` reader for session logging.
- Replace Claude output capture with pipeline-based `tee` (no process substitution).

Pros:

- Works in restricted shells where process substitution is blocked.
- Keeps behavior engine-neutral.

Cons:

- Slightly more code; requires careful cleanup/traps for FIFO lifecycle.

### Option F: Pipeline Wrapper For The Whole Loop

Description:

- Run the main loop in a subshell and pipe `2>&1 | tee -a "$SESSION_LOG"`.

Pros:

- Minimal helper code.

Cons:

- Subshell semantics can surprise (variable updates, traps, exit status propagation).
- Riskier refactor for an orchestrator script.

### Decision (Portability)

- Implemented Option E (spec `006` COMPLETE).
