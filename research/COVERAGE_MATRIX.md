# Coverage Matrix

Date: 2026-02-13
Goal: map discovered code/config/runtime surfaces to spec and plan coverage, and mark explicit gaps.

## Surface Coverage

| Surface ID | Runtime Surface | Primary Paths | Spec Coverage | Plan Coverage | Test Coverage | Status |
|---|---|---|---|---|---|---|
| S1 | Lock lifecycle and contention handling | `ralphie.sh` (`acquire_lock`, `release_lock`, diagnostics) | `004` COMPLETE, `005` COMPLETE | Covered | Good (contention + stale lock + atomic race + backend fallback) | Covered |
| S2 | Engine invocation and capability probes | `ralphie.sh` (`resolve_engine`, `probe_engine_capabilities`, `run_agent_with_prompt`) | `002`, `003` COMPLETE | Covered (regression retention) | Good (model flag forwarding + probe behavior) | Covered |
| S3 | Prepare output contract parsing | `ralphie.sh` (`extract_tag_value`, `detect_completion_signal`) | `003` COMPLETE | Covered | Good (fallback parsing tests) | Covered |
| S4 | Build prerequisite semantic gate | `ralphie.sh` (`check_build_prerequisites`) | `002`, `003` COMPLETE | Covered | Good (`test_prerequisite_quality_gate`) | Covered |
| S5 | Swarm consensus and concurrency ceiling | `ralphie.sh` (`run_swarm_consensus`) | `003` COMPLETE | Covered | Good (parallel ceiling + reviewer failure threshold) | Covered |
| S6 | Human queue ingestion and prompt injection | `ralphie.sh` (`count_pending_human_requests`, `check_human_requests`, `prepare_prompt_for_iteration`, `capture_human_priorities`) | `008` COMPLETE | Covered | Good (pending count + prompt injection + non-interactive capture reason code) | Covered |
| S7 | Notification channels and delivery failure behavior | `ralphie.sh` (`notify_human`) | `009` COMPLETE | Covered | Good (none/terminal, missing env, curl missing/fail, no secret leakage) | Covered |
| S8 | Setup/subrepo refresh integration | `scripts/setup-agent-subrepos.sh`, `ready_position` | `010` COMPLETE | Covered | Good (mocked git harness repairs partial-init; map path relativity) | Covered |
| S9 | Cleanup/ready/deep-clean durability boundaries | `ralphie.sh` cleanup functions | `001`, `004` partial | Covered | Good (clean and clean-deep tests) | Covered |
| S10 | Prompt artifact generation policy | `ralphie.sh` (`write_prompt_files`) and `PROMPT_*.md` | `001`, `002` partial | Covered | Indirect only | PARTIAL |
| S11 | Session log + output capture portability (no process substitution) | `ralphie.sh` (session log redirection, Claude output capture) | `006` COMPLETE | Covered | Good (Claude output separation + session log FIFO fixture) | Covered |
| S12 | Markdown artifact privacy compliance (self-improvement log) | `ralphie.sh` (`append_self_improvement_log`, self-heal paths, markdown gate) | `007` COMPLETE | Covered | Good (self-heal redaction fixture + privacy gate) | Covered |

## Coverage Totals

- Discovered major runtime surfaces: 12
- Fully covered: 11
- Partial: 1
- Explicit gaps: 0
- High-severity gaps: 0

## Gap-Driven Next Scope

1. Improve `S10` prompt artifact generation policy coverage with focused fixtures.
