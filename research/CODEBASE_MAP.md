# Codebase Map

Date: 2026-02-13
Scope: Repository execution surfaces, configuration surfaces, and integration boundaries.

## Repository Inventory

Tracked project files (excluding subrepo internals) are centered in:

- `ralphie.sh`
- `tests/ralphie_shell_tests.sh`
- `scripts/setup-agent-subrepos.sh`
- Prompt specs/docs: `PROMPT_*.md`, `specs/*/spec.md`, `research/*.md`, `README.md`, `IMPLEMENTATION_PLAN.md`
- Steering artifacts: `maps/agent-source-map.yaml`, `maps/binary-steering-map.yaml`

## Entrypoints

1. `ralphie.sh`
- Primary orchestrator.
- Supports modes: `prepare`, `plan`, `build`, `test`, `refactor`, `lint`, `document`, plus admin operations (`--doctor`, `--status`, `--clean`, `--ready`, `--human`).

2. `scripts/setup-agent-subrepos.sh`
- Installs/updates `subrepos/codex` and `subrepos/claude-code` via submodule or clone mode.
- Emits/upgrades `maps/agent-source-map.yaml` and binary steering references.
- Repairs partially-initialized subrepos (a `.git` file that points at a missing `.git/modules/...` target) by re-initializing the registered submodule (submodule mode) or re-cloning (clone mode).
- Enforces repo-relative map output by requiring `--subrepo-dir` and `--map-file` to live under the repository root.

3. `tests/ralphie_shell_tests.sh`
- Sources `ralphie.sh` as a library (`RALPHIE_LIB=1`) and validates parsing, lock behavior, gates, concurrency ceilings, cleanup behavior, and invocation contracts.

## Runtime Artifact Paths

- `.ralphie/config.env`: persisted run configuration
- `.ralphie/run.lock`: active run lock state
- `logs/`: per-iteration logs/output/prompt expansions
- `consensus/`: reviewer prompts, outputs, consensus reports
- `completion_log/`: completion audit entries
- `.ralphie/ready-archives/`: archive backups during ready/deep-clean flows

## Module Map (Behavior-Based)

1. Bootstrap and process setup (`ralphie.sh`)
- Stream-install bootstrap for `curl ... | bash` usage.
- Strict shell mode: `set -euo pipefail`.

2. Locking and cleanup (`ralphie.sh`)
- Lock lifecycle: acquisition, release, diagnostics, stale-lock handling.
- Runtime and deep-clean artifact lifecycle.

3. Setup, constitution, and prompt generation (`ralphie.sh`)
- Wizard-driven configuration and constitution creation.
- Prompt generation for all modes with policy guardrails.

4. Work discovery and human queue (`ralphie.sh`)
- Incomplete spec detection, plan task detection, optional GitHub issue checks, optional human instruction queue processing.

5. Engine resolution and capability probing (`ralphie.sh`)
- Engine selection/fallback (`codex`/`claude`/`auto`).
- Runtime probing for CLI flag support.

6. Agent invocation and output contract parsing (`ralphie.sh`)
- Unified invocation wrapper with per-engine flag boundaries.
- XML-tag extraction for prepare/build orchestration contracts.
- Claude stdout/stderr capture is pipeline-based (stdout to output artifact; stderr to log artifact).
- Session logging uses FIFO + `tee` (no process substitution; spec `006` COMPLETE).

7. Build gate and consensus orchestration (`ralphie.sh`)
- Semantic prereq checks.
- Multi-reviewer consensus with configurable parallel ceilings.

8. Main loop and phase transitions (`ralphie.sh`)
- Iterative execution, failover, phase gating, retries/backoff, completion logging.
- Session logging uses FIFO + `tee` to duplicate orchestrator output to both terminal and log file (no process substitution; spec `006` COMPLETE).

9. Subrepo/map management (`scripts/setup-agent-subrepos.sh`)
- Git orchestration for source-map evidence inputs.

10. Validation harness (`tests/ralphie_shell_tests.sh`)
- Regression checks for core orchestration logic.

## Configuration Surfaces

Primary configurable inputs:

- CLI args (`--engine`, `--mode`, `--timeout`, `--wait-for-lock`, `--swarm-*`, `--min-consensus`, `--max-reviewer-failures`, etc.)
- Environment vars (`CODEX_CMD`, `CLAUDE_CMD`, `CODEX_MODEL`, `CLAUDE_MODEL`, timeout/lock/consensus settings, notify channel)
- Persisted config in `.ralphie/config.env`
- Map-guided behavior from `maps/*.yaml`

## Integration Boundaries

External binaries and services invoked by runtime:

- `codex` CLI
- `claude` CLI
- `git` CLI
- optional `gh` CLI
- optional `timeout`/`gtimeout`
- `ps`, `date`, `tar`

Network-dependent paths:

- `scripts/setup-agent-subrepos.sh` git fetch/clone/submodule operations

## Coverage Status Snapshot

- Known-surface mapping completeness: high.
- Previously high-severity gaps (atomic lock, markdown privacy leakage, and process substitution portability) are now closed (specs `005`-`007` COMPLETE).
- Remaining medium gaps: setup-script integration coverage, notification/human-queue fixtures, and prompt-generation policy fixtures.
