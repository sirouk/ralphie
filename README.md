# Ralphie

Version: `2.0.0`

Ralphie is an autonomous engineering orchestrator for Codex and Claude Code. It runs a multi-phase software lifecycle with planning, implementation, validation, and consensus review in a resumable loop.

## Design Philosophy: Correct-by-Construction

Ralphie operates on a "Thinking before Doing" doctrine. The system is designed around **Critique-Driven Development**, where autonomous agents do not just execute tasks but recursively critique their own research, specifications, and implementation plans. This ensures that every code change is backed by executable logic and peer-validated consensus before a single line of production code is modified.

## Core Features

-   **Recursive Planning:** Merges research, specification, and implementation planning into a single high-fidelity `Plan` mode.
-   **Deep Consensus Swarm:** Multi-persona reviewer panels (Architect, Skeptic, Execution Reviewer, Safety Reviewer, Operations Reviewer, Quality Reviewer) with score/verdict routing (`GO|HOLD`) and next-phase recommendations.
-   **Autonomous YOLO Mode:** Enabled by default, granting agents the authority to execute shell commands and modify files.
-   **Self-Healing State:** SHA-256 checksum-validated state snapshots that detect artifact drift and allow for robust recovery via `--resume`.
-   **Atomic Lifecycle Management:** Global process tracking ensures that orphaned agent processes are terminated on failure or interrupt.
-   **Self-Contained Runtime:** Runtime behavior is version-stable and local to the checked-out orchestrator script; no runtime auto-update is performed.
-   **Resilient Consensus Orchestration:** Adaptive phase routing includes bounded retries and hard timeouts for reviewer swarms.

## Operational Phases & Governance

Ralphie transitions through structured phases governed by strict validation gates and state management.

### 1. Plan (Research + Spec + Implementation Plan)
-   **Logic:** Recursive mapping of codebase surfaces, external dependency research, and creation of testable specs.
-   **Gate:** Requires consensus review approval from the phase swarm with a strong signal from agent outputs, then transitions by consensus score/verdict.
-   **State:** Persists plan checksums to prevent out-of-band drift during implementation.

### 2. Build
-   **Logic:** Targeted implementation of items from the validated `IMPLEMENTATION_PLAN.md`.
-   **Gate:** Requires successful phase completion validation by execution + consensus reviewers.
-   **Transition:** Auto-switches to `Plan` mode for backfill if the work queue becomes empty.

### 3. Test
-   **Logic:** Test-Driven Development (TDD) cycle. High-risk behavior surfaces are identified and verified with adversarial unit/integration tests.
-   **Gate:** Requires successful verification and review consensus that tests/coverage intent is satisfied.

### 4. Refactor
-   **Logic:** Behavior-preserving simplification. Focuses on reducing incidental complexity and technical debt.
-   **Gate:** Mandatory post-refactor test pass to ensure zero behavioral regression.

### 5. Lint
-   **Logic:** Static analysis and formatting.
-   **Gate:** Clean report from repository-configured linting workflows.

### 6. Document
-   **Logic:** Synchronization of READMEs and module docs with the new executable reality.
-   **Gate:** Final documentation-quality check before loop closure.

## Runtime Management

`ralphie.sh` does not auto-update itself at runtime. Release drift is handled intentionally through normal checkout/version control workflows.
To upgrade behavior, update the checked-out `ralphie.sh` script (or repository) and rerun with the same command.

## Security & Sandboxing (Claude Code)

When operating in autonomous YOLO mode, Ralphie applies Claude runtime safeguards:
-   **Environment Flagging:** Agent command execution includes `IS_SANDBOX=1`.
-   **Permission Flag Handling:** If supported by the installed Claude binary, Ralphie injects `--dangerously-skip-permissions` with idempotent argument checks.

## Usage

### Quick Start
```bash
curl -fsSL https://raw.githubusercontent.com/sirouk/ralphie/refs/heads/master/ralphie.sh | bash
```

`ralphie.sh` will self-bootstrap missing control artifacts before the first run:

- `.specify/memory/constitution.md`
- placeholder research artifacts under `research/`
- placeholder implementation scaffolding under `IMPLEMENTATION_PLAN.md`
- `.ralphie/project-bootstrap.md` containing:
  - project type (`existing` or `new`)
  - primary objective for this session
  - optional constraints/non-goals and success criteria
  - explicit plan→build transition consent
- optional `.ralphie/project-goals.md` for pasted goals/context documents

Startup bootstrap is interactive when a terminal is attached (`/dev/tty` is present):
- `project_type`: is this a new project?
- `objective`: what should Ralphie optimize for?
- `constraints` and `success_criteria`: quick single-line defaults (press Enter to keep)
- optional `goals document URL`: single-line link input (press Enter to skip)
- optional multi-line `project goals/context` paste mode:
  - paste full document content or URL notes
  - finish with a line containing only `EOF` (or press `Ctrl+D`)
- `build_consent`: proceed from PLAN to BUILD automatically when gates pass?

If `.ralphie/project-bootstrap.md` already exists and was created interactively, `ralphie.sh` will reuse it.
If it was created non-interactively, the first interactive run will refresh it by default.
To force a refresh at any time, run:
```bash
./ralphie.sh --rebootstrap
```

### Autonomous Resumption
If a run is interrupted by a timeout or crash, Ralphie automatically resumes from the previous state by default. You can force a fresh start with:
```bash
./ralphie.sh --no-resume
```

### Reference Sources

- `engines/setup-agent-subrepos.sh` is retained for comparative engine behavior research only.
- It is **not** required for a standard `ralphie.sh` run on a user project.

## Runtime Configuration (CLI + `config.env`)

`ralphie.sh` supports explicit session/retry budgets plus optional cost accounting. Defaults favor resumability and developer autonomy; CI presets are provided for stricter caps.

### CLI Flags

- `--resume`  
- `--no-resume`  
- `--rebootstrap`  
- `--max-session-cycles N`  
- `--session-token-budget N`  
- `--session-token-rate-cents-per-million N`  
- `--session-cost-budget-cents N`  
- `--max-phase-completion-attempts N`  
- `--phase-wallclock-limit-seconds N`  
- `--phase-completion-retry-delay-seconds N`  
- `--phase-completion-retry-verbose true|false`  
- `--max-consensus-routing-attempts N`  
- `--consensus-score-threshold N`  
- `--run-agent-max-attempts N`  
- `--run-agent-retry-delay-seconds N`  
- `--run-agent-retry-verbose true|false`  
- `--auto-init-git-if-missing true|false`
- `--auto-commit-on-phase-pass true|false`
- `--auto-engine-preference codex|claude`
- `--auto-repair-markdown-artifacts true|false`  
- `--strict-validation-noop true|false`  
- `--engine-output-to-stdout true|false`  
- `--phase-noop-profile strict|balanced|read-only-first|custom`
- `--phase-noop-policy-plan hard|soft|none`
- `--phase-noop-policy-build hard|soft|none`
- `--phase-noop-policy-test hard|soft|none`
- `--phase-noop-policy-refactor hard|soft|none`
- `--phase-noop-policy-lint hard|soft|none`
- `--phase-noop-policy-document hard|soft|none`
- `--max-iterations N`

For persistent behavior across runs, place overrides in `.ralphie/config.env`.
Ralphie supports both CLI flags and environment/config keys, but this README intentionally avoids mirroring the full key surface to prevent drift.

Operator guidance:

- Use CLI flags for run-scoped overrides.
- Use `.ralphie/config.env` for stable project/operator defaults.
- Treat `./ralphie.sh --help` as the source of truth for supported options and compatibility aliases.
- Use the startup config banner as the source of truth for effective values after config/env/CLI precedence.

Phase no-op profile precedence: explicit per-phase policy flags win over profile-derived policy values.

Supported no-op profiles:
- `balanced` (default): plan=`none`, build=`hard`, test=`soft`, refactor=`hard`, lint=`hard`, document=`soft`.
- `strict`: all phases (`plan`, `build`, `test`, `refactor`, `lint`, `document`) `hard`.
- `read-only-first`: plan=`none`, build=`hard`, test=`soft`, refactor=`none`, lint=`soft`, document=`none`.
- `custom`: only explicit per-phase flags apply.

Behavior summary:
- `0` values for retry/routing budgets are treated as unlimited loops with stagnation guards.
- Resume remains enabled by default (`--resume`).
- Terminal routing to `done` is guarded: lint and document must each pass at least once before completion.

## Interrupt Controls

In interactive mode, pressing `Ctrl+C` opens a control menu:

- `r` resume immediately (default)
- `l` toggle live engine output on/off
- `p` persist state and pause
- `q` immediate stop
- `h` help

The current `engine-output-to-stdout` mode is preserved in session state and reused on resume.

## Deterministic Stack Discovery

Before each planning run, `ralphie.sh` writes `research/STACK_SNAPSHOT.md` with:

- ranked stack candidates,
- deterministic evidence signals,
- and a ranked alternatives list.

Build transitions require the snapshot and clean artifact checks to pass.

## Restart behavior

- Resume is enabled by default. On restart, `ralphie.sh` restores the latest persisted phase and iteration state.
- State snapshots are written atomically (`tmp` file + rename) with checksum validation to avoid partial-write corruption.
- Resume now restores attempt-level execution (`CURRENT_PHASE_ATTEMPT`) and whether an attempt was in-flight.
- If a process stops mid-attempt, the next run re-enters that exact phase/attempt instead of skipping ahead.
- Phase transition context is persisted and restored, so consensus routing history survives restarts.
- If resume lands on a phase with broken prerequisites (for example missing artifacts, bad markdown hygiene, or non-actionable plan), it automatically falls back to `plan` and records the reason in `last_gate_feedback`.
- This prevents silent stalls while avoiding unnecessary recomputation.

## Phase-Gated Auto Commit (No Push)

- When enabled, Ralphie creates a local commit after a phase passes handoff + consensus gates.
- Commit subjects are concise, lowercase, one-line summaries grouped by changed file areas.
- Ralphie never runs `git push`.
- At startup, Ralphie checks whether a valid git commit identity is available (`git var GIT_COMMITTER_IDENT`) and records that status in resumable state.
- If identity is missing, auto-commit is disabled for the run and a clear warning is shown up front.
- After configuring identity (`git config user.name/user.email` or equivalent git identity environment), restart with `--resume`; Ralphie re-checks identity and auto-commit can resume.
- Commits are scoped to files touched in the current phase manifest delta; pre-staged index content is skipped to avoid accidental mixed commits.

## Git Repository Bootstrap

- By default, Ralphie initializes a git repository at startup when one is missing.
- This behavior is configurable through the startup options surface.
- If git is unavailable and auto-init is enabled, startup fails early.

## Startup Operational Probe

- When startup operational probing is enabled, Ralphie validates core runtime dependencies before the loop starts.
- This includes command availability checks for core shell tooling and git workflow commands (`git`, `seq`, `cut`, `head`, `tail`, `wc`, `tr`, `tee`, `comm`, `cmp`, plus base shell utilities).
- It also validates writable state storage and timeout wrapper behavior.

## First-Deploy Engine Override Wizard

- On first interactive run, Ralphie can prompt once for engine override setup after engine readiness checks pass.
- The wizard can update:
  - engine mode (`auto|codex|claude`) and AUTO preference
  - Codex endpoint/model/thinking/schema settings
  - Claude endpoint/model/thinking settings
- It only offers Codex/Claude override prompts for engines that passed health checks in that run.
- Selections are persisted to `.ralphie/config.env`.
- Completion state is stored via a bootstrap sentinel to avoid repeated prompting.
- To re-run the wizard later, reset that sentinel in `.ralphie/config.env` (see `--help` for the exact key).

## First-Deploy Notification Wizard

- On first interactive run, Ralphie can prompt once for notification setup.
- Supported channels:
  - Telegram bot messages
  - Discord webhook
  - Optional Chutes TTS voice attachments for Telegram/Discord
- The wizard includes quick setup guidance, auto-chat-id discovery for Telegram via `getUpdates`, and sends test messages during setup.
- The wizard can also configure anti-spam cadence for duplicate suppression and incident reminders.
- Notification events are standardized:
  - `session_start`
  - `phase_decision`
  - `phase_complete`
  - `phase_blocked`
  - `session_done`
  - `session_error`
- Notification policy is high-signal only. Repeated incidents are suppressed and re-notified on reminder cadence.
- Selections are persisted to `.ralphie/config.env`.
- Completion state is stored via a bootstrap sentinel.
- To re-run later, reset that sentinel in `.ralphie/config.env` (see `--help` for the exact key).

## Notification Reliability Guarantees

- Notification delivery is non-blocking for the main phase loop: delivery failures are logged and do not terminate Ralphie execution.
- If TTS is enabled but Chutes TTS generation/upload fails, Ralphie still sends text updates on enabled channels and records `tts=fallback_text_only` in `.ralphie/notifications.log`.
- If notifications are disabled or `curl` is unavailable, Ralphie continues normally without channel delivery attempts.

## GitHub Actions CI

Ralphie now includes a GitHub Actions workflow at `.github/workflows/durability-ci.yml`.

- Auto run (push + PR): runs `tests/durability/run-durability-suite.sh` as the default offline durability gate.
- Manual run (`workflow_dispatch`): optional live engine smoke check using `tests/durability/run-live-smoke.sh`.

### Live smoke inputs

- `run_live_smoke` (`true|false`): whether to execute live smoke.
- `live_engine` (`codex|claude`): which live engine to test.

### Live smoke interactive behavior

- Running `tests/durability/run-live-smoke.sh` in an interactive terminal now prompts for:
  - engine selection (`codex|claude`) when not explicitly provided
  - optional temporary API key/model/endpoint overrides for the selected engine
- These overrides are in-memory for that invocation only and are not persisted.
- You can force prompt mode with `--prompt` or disable prompts with `--no-prompt`.

### Live smoke secrets/vars

- Configure provider API credentials for the engine you want to smoke-test.
- Optional endpoint/model overrides are supported for both engines.
- Use `.github/workflows/durability-ci.yml` and `tests/durability/run-live-smoke.sh --help` for the exact key names and current defaults.

Live smoke is manual by default because it uses real provider credentials and can incur usage cost.

## Controlled Claude Phase Stress Harness

For fast, fail-fast, end-to-end orchestration validation (all Ralphie phases with handoff + consensus), use:

```bash
tests/durability/run-claude-phase-stress.sh
```

This harness runs in isolated temporary workspaces using a deterministic mock Claude binary (`tests/durability/mock-claude-control.sh`) and verifies:

- full lifecycle path: `plan -> build -> test -> refactor -> lint -> document -> done`
- retry behavior (simulated first-attempt handoff HOLD, then recovery)
- crash/resume behavior (mid-phase interrupt, then `--resume` completion)
- phase artifacts, handoff artifacts, consensus outputs, and terminal state integrity

Common options:

- `--scenarios full,retry,resume`
- `--timeout-seconds 90`
- `--keep-workspaces` (retain scenario workspaces for debugging)
- `--discord-webhook-url <url>` (optional high-signal run notifications)
- `--exercise-tts-fallback` (requires `--discord-webhook-url`; enables Ralphie TTS path with forced fail-fast TTS generation to verify text fallback delivery)

Artifacts are written to:

- `tests/durability/artifacts/claude-phase-stress-<timestamp>/`
- summary report: `report.md`
- per-scenario stdout/stderr logs

## Test Isolation Guarantees

- `tests/durability/run-durability-suite.sh` runs against isolated temporary copies and fails if tracked repository files change.
- `tests/durability/run-claude-phase-stress.sh` executes scenarios in isolated temporary workspaces and enforces tracked-file integrity checks against the main repo.
- `tests/durability/run-live-smoke.sh` performs network smoke checks only and enforces tracked-file integrity on exit.
- `tests/notify-smoke.sh` targets project-root `.ralphie/config.env` for optional onboarding persistence and enforces tracked-file integrity checks to protect repository code.

## One-Command Pre-Ship

Use the root test runner to execute the full pre-ship chain:

```bash
./test.sh
```

Default sequence:
- `bash -n ralphie.sh`
- `tests/durability/run-durability-suite.sh`
- `tests/durability/run-claude-phase-stress.sh --scenarios full,retry,resume`
- `tests/durability/run-live-smoke.sh` in auto mode (runs only if matching creds are present)

Common flags:
- `--live` (require live smoke and fail if creds missing)
- `--skip-live` (offline-only pre-ship run)
- `--live-engine codex|claude`
- `--stress-scenarios full,retry,resume`
- `--discord-webhook-url <url>`
- `--exercise-tts-fallback` (requires webhook)

## Credits

Ralphie was inspired by the original [`ralph-wiggum`](https://github.com/fstandhartinger/ralph-wiggum) project by Florian Standhartinger.
Florian's original work is the foundation for this project's name, spirit, and autonomous orchestration direction.
