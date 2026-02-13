## 2026-02-12 22:15:15 - Self-heal: Codex config compatibility
- Trigger: Codex failed to parse model_reasoning_effort='xhigh'.
- Action: Rewrote model_reasoning_effort to 'high'.
- Backup: config.toml backup created alongside the original file (path redacted).
- Outcome: Ready to retry agent loop.
## 2026-02-12 22:22:14 - Ready position established
- Source map: maps/agent-source-map.yaml
- Binary steering map: maps/binary-steering-map.yaml
- Runtime artifacts: archived + reset
- Prompts: refreshed
- Specs: self-improvement seed ensured

## 2026-02-12 22:23:50 - Ready position established
- Source map: maps/agent-source-map.yaml
- Binary steering map: maps/binary-steering-map.yaml
- Runtime artifacts: archived + reset
- Prompts: refreshed
- Specs: self-improvement seed ensured

## 2026-02-12 22:26:05 - Ready position established
- Source map: maps/agent-source-map.yaml
- Binary steering map: maps/binary-steering-map.yaml
- Runtime artifacts: archived + reset
- Prompts: refreshed
- Specs: self-improvement seed ensured

## 2026-02-12 22:26:47 - Ready position established
- Source map: maps/agent-source-map.yaml
- Binary steering map: maps/binary-steering-map.yaml
- Runtime artifacts: archived + reset
- Prompts: refreshed
- Specs: self-improvement seed ensured

## 2026-02-12 22:27:43 - Ready position established
- Source map: maps/agent-source-map.yaml
- Binary steering map: maps/binary-steering-map.yaml
- Runtime artifacts: archived + reset
- Prompts: refreshed
- Specs: self-improvement seed ensured

## 2026-02-12 22:28:54 - Ready position established
- Source map: maps/agent-source-map.yaml
- Binary steering map: maps/binary-steering-map.yaml
- Runtime artifacts: archived + reset
- Prompts: refreshed
- Specs: self-improvement seed ensured

## 2026-02-12 22:30:32 - Ready position established
- Source map: maps/agent-source-map.yaml
- Binary steering map: maps/binary-steering-map.yaml
- Runtime artifacts: archived + reset
- Prompts: refreshed
- Specs: self-improvement seed ensured

## 2026-02-12 22:36:22 - Ready position established
- Source map: maps/agent-source-map.yaml
- Binary steering map: maps/binary-steering-map.yaml
- Runtime artifacts: archived + reset
- Prompts: refreshed
- Specs: self-improvement seed ensured

## 2026-02-12 22:41:59 - Ready position established
- Source map: maps/agent-source-map.yaml
- Binary steering map: maps/binary-steering-map.yaml
- Runtime artifacts: archived + reset
- Prompts: refreshed
- Specs: self-improvement seed ensured

## 2026-02-12 22:42:50 - Ready position established
- Source map: maps/agent-source-map.yaml
- Binary steering map: maps/binary-steering-map.yaml
- Runtime artifacts: archived + reset
- Prompts: refreshed
- Specs: self-improvement seed ensured

## 2026-02-13 00:00:00 - Map-guided critique: parity and reliability planning
- Hypothesis: Build readiness improves if engine capability probes and semantic artifact gates are added before execution.
- Evidence sampled:
  - Codex: `subrepos/codex/docs/exec.md`, runtime `codex exec --help`.
  - Claude: `subrepos/claude-code/README.md`, `subrepos/claude-code/examples/settings/README.md`, runtime `claude --help`.
- Anti-overfit checks applied:
  - avoided single-provider output assumptions
  - required paired parity/fallback tasks
  - preserved behavior when either CLI is missing
- Result: Accepted for implementation planning; queued tasks in `IMPLEMENTATION_PLAN.md` and `specs/002-gate-and-parity-hardening/spec.md`.
- Validation pending: execute shell tests for both `--engine codex` and `--engine claude` paths after implementation.


## 2026-02-13 00:00:00 - Map-guided hardening: capability probes + consensus threshold
- Hypothesis: Enforcing runtime CLI capability probes, reviewer-failure consensus invalidation, and machine-readable reason codes will reduce false GO decisions and improve deterministic recovery.
- Evidence sampled:
  - Codex sources: `subrepos/codex/docs/exec.md`, runtime `codex exec --help`.
  - Claude sources: `subrepos/claude-code/README.md`, runtime `claude --help`.
- Changes accepted:
  - Added capability probes for required/optional Codex and Claude flags.
  - Added reviewer-failure threshold (`CONSENSUS_MAX_REVIEWER_FAILURES`) that invalidates consensus when exceeded.
  - Added deterministic `reason_code=...` log lines for gate and loop failures.
  - Added shell tests in `tests/ralphie_shell_tests.sh` for parsing, failover, and gate behavior.
- Result:
  - `bash tests/ralphie_shell_tests.sh` passes.
  - Specs `000`, `001`, and `002` marked COMPLETE after implementation + test verification.
- Anti-overfit checks:
  - Capability checks are runtime-based, not version-hardcoded.
  - Dangerous flags are optional and safely omitted when unsupported.
  - Cross-engine fallback remains in place (`codex <-> claude`).
## 2026-02-12 23:06:06 - Ready position established
- Source map: maps/agent-source-map.yaml
- Binary steering map: maps/binary-steering-map.yaml
- Runtime artifacts: archived + reset
- Prompts: refreshed
- Specs: self-improvement seed ensured


## 2026-02-12 23:08:22 - Map-guided critique: concurrency + gate semantics + output contract
- Hypothesis: Build readiness confidence will improve if consensus parallelism is truly bounded, plan gating is semantic (not checkbox-count based), and Claude output capture is less brittle.
- Evidence sampled:
  - Codex: `subrepos/codex/codex-rs/exec/src/cli.rs` and runtime `codex exec --help` (`codex-cli 0.101.0`).
  - Claude: `subrepos/claude-code/examples/settings/README.md`, `subrepos/claude-code/examples/settings/settings-strict.json`, and runtime `claude --help` (`2.1.7`).
- Anti-overfit checks applied:
  - kept engine-specific behavior at invocation boundary only
  - required parity validation for codex and claude smoke paths
  - avoided version-pinned assumptions; relied on runtime probes
- Result: Accepted as next implementation scope and captured in `IMPLEMENTATION_PLAN.md` and `specs/003-consensus-concurrency-and-output-contract/spec.md`.
- Validation status: Pending implementation + test execution in next build cycle.

## 2026-02-13 00:00:00 - Map-guided critique: plan gate semantics and output-contract parity
- Hypothesis: Prepare/build reliability will increase if plan gating becomes semantic and output parsing no longer depends on mixed log/output streams.
- Evidence sampled:
  - Codex: `subrepos/codex/codex-rs/exec/src/cli.rs`, `subrepos/codex/codex-rs/README.md`, runtime `codex exec --help` (`codex-cli 0.101.0`).
  - Claude: `subrepos/claude-code/examples/settings/README.md`, `subrepos/claude-code/examples/settings/settings-strict.json`, runtime `claude --help` (`2.1.7`), and `subrepos/claude-code/CHANGELOG.md` (`-p` mode fixes).
- Anti-overfit checks applied:
  - retained neutral orchestration and engine-agnostic gate semantics
  - confined engine-specific behavior to invocation boundaries
  - required parity test additions for any parser/output-contract change
- Result: Accepted for next build cycle; tasks updated in `IMPLEMENTATION_PLAN.md` and specs refreshed for testable scope.
- Additional note: `maps/agent-source-map.yaml` references `subrepos/claude-code/docs/`, but that path is absent in pinned revision `2322133`; fallback evidence sources were used and uncertainty was documented in research artifacts.
## 2026-02-13 23:20:00 - Map-guided critique: semantic gate + output-contract parity
- Hypothesis: Build-readiness confidence will improve if prerequisite gating is semantic and output parsing is decoupled from provider-specific stream behavior.
- Evidence sampled:
  - Codex: `subrepos/codex/codex-rs/exec/src/cli.rs`, `subrepos/codex/codex-rs/README.md`, runtime `codex exec --help` (`codex-cli 0.101.0`).
  - Claude: `subrepos/claude-code/examples/settings/README.md`, `subrepos/claude-code/examples/settings/settings-strict.json`, `subrepos/claude-code/CHANGELOG.md`, runtime `claude --help` (`2.1.7`).
- Anti-overfit rules applied:
  - preserved neutral orchestration and fallback behavior when either CLI is absent
  - confined engine-specific behavior to invocation boundary
  - avoided assumptions tied to one provider's output style
- Result: Accepted for build-phase implementation. Updated artifacts: `research/RESEARCH_SUMMARY.md`, `research/ARCHITECTURE_OPTIONS.md`, `research/RISKS_AND_MITIGATIONS.md`, `IMPLEMENTATION_PLAN.md`, `specs/003-consensus-concurrency-and-output-contract/spec.md`.
- Validation pending: implement code changes and pass shell tests plus dual-engine prepare smoke checks.

## 2026-02-13 23:35:00 - Map-guided critique: build-gate semantics + output parsing reliability
- Hypothesis: Build readiness confidence will increase if plan prerequisites become semantic and tag parsing supports deterministic fallback files.
- Evidence sampled:
  - Codex: `subrepos/codex/codex-rs/exec/src/cli.rs`, `subrepos/codex/codex-rs/README.md`, `subrepos/codex/sdk/typescript/src/exec.ts`, runtime `codex exec --help` (`codex-cli 0.101.0`).
  - Claude: `subrepos/claude-code/examples/settings/README.md`, `subrepos/claude-code/examples/settings/settings-strict.json`, `subrepos/claude-code/CHANGELOG.md`, runtime `claude --help` (`2.1.7`).
- Anti-overfit checks applied:
  - preserved neutral orchestration and engine fallback behavior
  - kept provider-specific behavior isolated to invocation flags
  - avoided version-pinned assumptions; relied on runtime capability probes
- Result: Accepted for next build cycle. Updated artifacts: `research/RESEARCH_SUMMARY.md`, `research/ARCHITECTURE_OPTIONS.md`, `research/RISKS_AND_MITIGATIONS.md`, `IMPLEMENTATION_PLAN.md`, `specs/003-consensus-concurrency-and-output-contract/spec.md`.
- Validation pending: complete spec 003 tasks and pass dual-engine smoke checks.

## 2026-02-13 23:55:00 - Map-guided critique: gate semantics + output-contract reliability
- Hypothesis: Build-readiness confidence improves when plan gating is semantic and tag extraction supports ordered fallback files.
- Evidence sampled:
  - Codex: `subrepos/codex/docs/exec.md`, `subrepos/codex/docs/config.md`, runtime `codex exec --help` (`codex-cli 0.101.0`).
  - Claude: `subrepos/claude-code/examples/settings/README.md`, `subrepos/claude-code/CHANGELOG.md`, runtime `claude --help` (`2.1.7`).
- Anti-overfit checks applied:
  - preserved neutral orchestration and fallback behavior when either CLI is unavailable
  - isolated provider-specific behavior to invocation flags and capability probes
  - required parity validation tasks for both codex and claude paths
- Result: Accepted and incorporated into `IMPLEMENTATION_PLAN.md`, `research/RISKS_AND_MITIGATIONS.md`, and `specs/003-consensus-concurrency-and-output-contract/spec.md`.
- Validation status: Pending build-phase implementation and dual-engine prepare smoke checks.

## 2026-02-13 23:59:00 - Map-guided critique: parity and reliability before build
- Hypothesis: Build success probability increases if gate semantics, output parsing fallback, and Claude output artifact handling are hardened before implementation.
- Evidence sampled:
  - Codex: `subrepos/codex/docs/exec.md`, `subrepos/codex/docs/config.md`, runtime `codex exec --help` (`codex-cli 0.101.0`).
  - Claude: `subrepos/claude-code/README.md`, `subrepos/claude-code/examples/settings/README.md`, runtime `claude --help` (`2.1.7`).
- Anti-overfit rules applied:
  - preserved neutral orchestration and fallback behavior with either CLI missing
  - kept engine-specific details at invocation boundaries only
  - avoided version-pinned assumptions; relied on runtime capability probes
- Result: Accepted. Updated `research/RESEARCH_SUMMARY.md`, `research/ARCHITECTURE_OPTIONS.md`, `research/RISKS_AND_MITIGATIONS.md`, `IMPLEMENTATION_PLAN.md`, and `specs/003-consensus-concurrency-and-output-contract/spec.md`.
- Validation next: implement spec `003`, run shell tests, then dual-engine one-iteration prepare smokes.
## 2026-02-12 23:35:48 - Ready position established
- Source map: maps/agent-source-map.yaml
- Binary steering map: maps/binary-steering-map.yaml
- Runtime artifacts: archived + reset
- Prompts: refreshed
- Specs: self-improvement seed ensured


## 2026-02-13 00:25:00 - Map-guided critique: lock contention parity and reliability
- Hypothesis: Build-readiness confidence increases if lock-contention failures are machine-classified and diagnostically rich while preserving neutral cross-engine behavior.
- Evidence sampled:
  - Codex: `subrepos/codex/docs/exec.md`, `subrepos/codex/docs/config.md`, runtime `codex exec --help` (`codex-cli 0.101.0`).
  - Claude: `subrepos/claude-code/README.md`, `subrepos/claude-code/examples/settings/README.md`, runtime `claude --help` (`2.1.7`).
- Anti-overfit checks applied:
  - no provider-specific parsing assumptions
  - engine-specific behavior restricted to invocation flags only
  - retained fallback behavior when either CLI is unavailable

## 2026-02-13 12:25:42 - Map-guided critique: medium-gap closure planning
- Hypothesis: Build readiness improves if remaining medium-gap runtime surfaces have explicit specs and deterministic offline tests, without introducing provider-specific behavior outside invocation boundaries.
- Evidence sampled (Codex): `subrepos/codex/docs/exec.md`, `subrepos/codex/docs/config.md`.
- Evidence sampled (Claude): `subrepos/claude-code/README.md`, `subrepos/claude-code/examples/settings/README.md`.
- Anti-overfit check: avoid relying on any single CLI output format.
- Anti-overfit check: keep engine-specific behavior constrained to invocation boundaries and runtime capability probes.
- Anti-overfit check: preserve stable fallback behavior when either CLI is missing.
- Result: drafted specs `008`-`010` (human queue ingestion, notifications, setup-agent-subrepos refresh/repair) and updated `research/COVERAGE_MATRIX.md`.
- Validation next: implement tests for specs `008` and `009` (mock `curl`, no-network) and add a deterministic harness for spec `010` (mocked `git` or `--dry-run`).
- Result: Accepted for next cycle as spec `004` (`specs/004-lock-contention-observability/spec.md`) with phased tasks in `IMPLEMENTATION_PLAN.md`.
- Validation status: Pending build implementation and shell-test/doctor verification.

## 2026-02-13 04:06:46 - Map-guided critique: lock correctness parity before next build
- Hypothesis: Prepare/build reliability is still materially exposed by non-atomic lock acquisition; fixing lock correctness should be prioritized before additional feature scope.
- Evidence sampled:
  - Codex sources: `subrepos/codex/codex-rs/exec/src/cli.rs`, `subrepos/codex/sdk/typescript/src/exec.ts`, `subrepos/codex/docs/exec.md`.
  - Claude sources: `subrepos/claude-code/README.md`, `subrepos/claude-code/examples/settings/README.md`, `subrepos/claude-code/CHANGELOG.md`.
  - External references: `flock(1)` manual, GNU Bash docs, GNU timeout docs.
- Anti-overfit checks applied:
  - kept lock design engine-agnostic (no Codex/Claude-specific lock behavior)
  - preserved engine-specific flags only at invocation boundaries
  - retained fallback behavior when either CLI is unavailable
- Result: Accepted. Added `specs/005-atomic-lock-acquisition/spec.md`, updated `IMPLEMENTATION_PLAN.md`, and refreshed research coverage/dependency artifacts.
- Validation pending: implement spec `005`, pass shell tests including new concurrent lock race fixture.

## 2026-02-13 04:20:00 - Map-guided critique: process substitution portability
- Hypothesis: Ralphie reliability improves if we eliminate Bash process substitution (`>(...)`) and instead use FIFO/pipeline logging so it runs in sandboxed shells where process substitution is blocked.
- Evidence sampled:
  - Codex: `subrepos/codex/docs/exec.md`
  - Claude: `subrepos/claude-code/README.md`
- Anti-overfit checks applied:
  - kept engine-specific behavior at invocation boundaries
  - avoided provider-specific parsing assumptions
  - preserved behavior when either CLI is unavailable
- Result: Accepted for next build scope as spec `006` and captured in `IMPLEMENTATION_PLAN.md`.
- Validation pending: implement spec `006`, then run `bash tests/ralphie_shell_tests.sh`.

## 2026-02-13 04:51:16 - Prepare verification: executable evidence and plan correction
- Hypothesis: Preparation artifacts should reflect executable evidence; prioritize correctness work that is environment-independent.
- Evidence sampled:
  - Local: `bash tests/ralphie_shell_tests.sh` passes end-to-end in this environment (including Claude output/log separation).
  - Codex sources: `subrepos/codex/codex-rs/exec/src/cli.rs`, `subrepos/codex/sdk/typescript/src/exec.ts`.
  - Claude sources: `subrepos/claude-code/examples/settings/README.md`, `subrepos/claude-code/CHANGELOG.md`.
  - External references: OpenAI Codex docs, Claude Code docs, GNU Bash manual, GNU coreutils manual, man7 pages for `flock(1)` and `mkdir(2)`.
- Anti-overfit checks applied:
  - kept engine-specific flags and parsing isolated to invocation boundaries
  - kept lock correctness changes engine-agnostic
- Result:
  - Corrected inaccurate local claim that the shell test suite fails due to process substitution.

## 2026-02-13 11:45:00 - Map-guided closure: build-gate blockers (specs 005-007)
- Hypothesis: Build-gate readiness will improve by closing remaining high-severity items with executable evidence: atomic lock correctness, process-substitution portability, and markdown path redaction.
- Evidence sampled:
  - Source map: `maps/agent-source-map.yaml`
  - Binary steering map: `maps/binary-steering-map.yaml`
  - Codex: `subrepos/codex/docs/exec.md`, `subrepos/codex/codex-rs/exec/src/cli.rs`
  - Claude: `subrepos/claude-code/README.md`, `subrepos/claude-code/examples/settings/README.md`
- Anti-overfit checks applied:
  - kept lock/logging changes engine-neutral (no provider-specific assumptions)
  - preserved invocation boundaries and runtime capability probes
- Result:
  - Fixed `try_acquire_lock_atomic` return-code handling (Bash `if` status pitfall) and added atomic race + backend fallback fixtures.
  - Removed remaining `< <(...)` process substitution usage; added FIFO session logging fixture.
  - Added self-heal redaction fixture; markdown privacy gate remains strict.
  - `bash tests/ralphie_shell_tests.sh` passes; specs `005`-`007` marked COMPLETE; research artifacts refreshed.
  - Re-scoped `IMPLEMENTATION_PLAN.md` to spec `005` (atomic lock acquisition).
  - Added spec `007` to prevent self-heal from introducing markdown privacy leakage.

## 2026-02-13 08:54:04 - Prepare hygiene: artifact policy alignment + readiness verification
- Hypothesis: Build-readiness confidence improves if prepare artifacts are validated against the same privacy/transcript gates enforced by `check_build_prerequisites`.
- Evidence sampled:
  - Local runtime: `bash tests/ralphie_shell_tests.sh` (all tests pass).
  - Gate behavior: `check_build_prerequisites` passes on current durable artifacts.
  - Codex sources: `subrepos/codex/codex-rs/exec/src/cli.rs`.
  - Claude sources: `subrepos/claude-code/README.md`.
  - External docs: OpenAI Codex non-interactive + config-reference docs; Claude Code CLI reference.
- Anti-overfit checks applied:
  - kept provider-specific details confined to invocation boundaries and capability probes
  - kept prepare changes focused on neutral artifact hygiene and verification
- Result:
  - Removed example home-directory absolute-path strings from committed markdown artifacts.
  - Verified build gate prerequisites succeed with the current prepare outputs.
