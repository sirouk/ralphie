# Coverage Matrix

Date: 2026-02-13
Goal: map discovered code/config/runtime surfaces to spec and plan coverage, and mark explicit gaps.

## Surface Coverage

| Surface ID | Runtime Surface | Primary Paths | Spec Coverage | Plan Coverage | Test Coverage | Status |
|---|---|---|---|---|---|---|
| S1 | Lock lifecycle and contention handling | `ralphie.sh` (`acquire_lock`, `release_lock`, diagnostics) | `004` COMPLETE, `005` INCOMPLETE | `IMPLEMENTATION_PLAN.md` phase 1-4 | Partial (contention + stale lock; no race fixture) | GAP (high): atomic acquisition not yet proven |
| S2 | Engine invocation and capability probes | `ralphie.sh` (`resolve_engine`, `probe_engine_capabilities`, `run_agent_with_prompt`) | `002`, `003` COMPLETE | Covered (regression retention) | Good (model flag forwarding + probe behavior) | Covered |
| S3 | Prepare output contract parsing | `ralphie.sh` (`extract_tag_value`, `detect_completion_signal`) | `003` COMPLETE | Covered | Good (fallback parsing tests) | Covered |
| S4 | Build prerequisite semantic gate | `ralphie.sh` (`check_build_prerequisites`) | `002`, `003` COMPLETE | Covered | Good (`test_prerequisite_quality_gate`) | Covered |
| S5 | Swarm consensus and concurrency ceiling | `ralphie.sh` (`run_swarm_consensus`) | `003` COMPLETE | Covered | Good (parallel ceiling + reviewer failure threshold) | Covered |
| S6 | Human queue ingestion and escalation | `ralphie.sh` (`capture_human_priorities`, `maybe_collect_human_feedback`) | No dedicated spec | Deferred (post-005) | Limited | GAP (medium) |
| S7 | Notification channels and delivery failure behavior | `ralphie.sh` (`notify_human`) | No dedicated spec | Deferred (post-005) | Limited | GAP (medium) |
| S8 | Setup/subrepo refresh integration | `scripts/setup-agent-subrepos.sh`, `ready_position` | `000` partial | Deferred (post-005) | None in repo tests | GAP (medium) |
| S9 | Cleanup/ready/deep-clean durability boundaries | `ralphie.sh` cleanup functions | `001`, `004` partial | Covered | Good (clean and clean-deep tests) | Covered |
| S10 | Prompt artifact generation policy | `ralphie.sh` (`write_prompt_files`) and `PROMPT_*.md` | `001`, `002` partial | Covered | Indirect only | PARTIAL |
| S11 | Session log + output capture portability (no process substitution) | `ralphie.sh` (session log redirection, Claude output capture) | `006` INCOMPLETE | Queued (post-`005`) | Passes in this environment; no restricted-shell coverage | GAP (medium): remove `>(...)` for portability |
| S12 | Markdown artifact privacy compliance (self-improvement log) | `ralphie.sh` (`append_self_improvement_log`, self-heal paths, markdown gate) | `007` INCOMPLETE | Queued (post-`005`) | Indirect only (generic privacy gate; no self-heal fixture) | GAP (high): self-heal can write absolute paths into markdown |

## Coverage Totals

- Discovered major runtime surfaces: 12
- Fully covered: 5
- Partial: 1
- Explicit gaps: 6
- High-severity gaps: 2 (`S1` lock atomicity, `S12` markdown privacy compliance)

## Gap-Driven Next Scope

1. Implement spec `005` to close `S1` (highest general correctness priority).
2. Implement spec `007` to close `S12` (markdown privacy compliance should not be bypassable by self-heal).
3. Implement spec `006` to close `S11` (portability hardening; remove process substitution).
4. Add dedicated spec/tests for `S6` and `S7` once `S1` is complete.
5. Add integration harness for `S8` or isolate script internals for testability.
