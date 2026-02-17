# Ralphie

Version: `2.0.0`

Ralphie is a high-fidelity autonomous development framework for Codex and Claude Code. It orchestrates a multi-phase engineering lifecycle—merging recursive planning, evidence-based implementation, and deep consensus swarms into a single, self-healing recursive loop.

## Design Philosophy: Correct-by-Construction

Ralphie operates on a "Thinking before Doing" doctrine. The system is designed around **Critique-Driven Development**, where autonomous agents do not just execute tasks but recursively critique their own research, specifications, and implementation plans. This ensures that every code change is backed by executable logic and peer-validated consensus before a single line of production code is modified.

## Core Features

-   **Recursive Planning:** Merges research, specification, and implementation planning into a single high-fidelity `Plan` mode.
-   **Deep Consensus Swarm:** Multi-persona reviewer panels (Adversarial, Optimist, Forensic) that alternate engines (Codex/Claude) and utilize stochastic jitter to eliminate confirmation bias.
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

When operating in autonomous YOLO mode, Ralphie enforces high-security standards for Claude Code:
-   **Environment Isolation:** All commands are prefixed with `env IS_SANDBOX=1`.
-   **Permission Enforcement:** Automatically injects `--dangerously-skip-permissions` using an idempotent check to prevent argument duplication.

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

`ralphie.sh` supports explicit session/retry budgets plus optional cost accounting.

### CLI Flags

- `--resume`  
- `--no-resume`  
- `--rebootstrap`  
- `--max-session-cycles N`  
- `--session-token-budget N`  
- `--session-token-rate-cents-per-million N`  
- `--session-cost-budget-cents N`  
- `--max-phase-completion-attempts N`  
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

Equivalent environment variables in `.ralphie/config.env`:
`MAX_SESSION_CYCLES`, `SESSION_TOKEN_BUDGET`, `SESSION_TOKEN_RATE_CENTS_PER_MILLION`,
`SESSION_COST_BUDGET_CENTS`, `PHASE_COMPLETION_MAX_ATTEMPTS`, `PHASE_COMPLETION_RETRY_DELAY_SECONDS`,
`PHASE_COMPLETION_RETRY_VERBOSE`, `MAX_CONSENSUS_ROUTING_ATTEMPTS`, `RUN_AGENT_MAX_ATTEMPTS`,
`RUN_AGENT_RETRY_DELAY_SECONDS`, `RUN_AGENT_RETRY_VERBOSE`, `SWARM_CONSENSUS_TIMEOUT`,
`AUTO_REPAIR_MARKDOWN_ARTIFACTS`, `STRICT_VALIDATION_NOOP`, `RALPHIE_ENGINE_OUTPUT_TO_STDOUT`,
`RALPHIE_STARTUP_OPERATIONAL_PROBE`,
`RALPHIE_CONSENSUS_SCORE_THRESHOLD`,
`RALPHIE_ENGINE_OVERRIDES_BOOTSTRAPPED`,
`RALPHIE_NOTIFICATIONS_ENABLED`, `RALPHIE_NOTIFY_TELEGRAM_ENABLED`,
`TG_BOT_TOKEN`, `TG_CHAT_ID`,
`RALPHIE_NOTIFY_DISCORD_ENABLED`, `RALPHIE_NOTIFY_DISCORD_WEBHOOK_URL`,
`RALPHIE_NOTIFY_TTS_ENABLED`, `CHUTES_API_KEY`,
`RALPHIE_NOTIFY_CHUTES_TTS_URL`, `RALPHIE_NOTIFY_CHUTES_VOICE`, `RALPHIE_NOTIFY_CHUTES_SPEED`,
`RALPHIE_NOTIFICATION_WIZARD_BOOTSTRAPPED`,
`RALPHIE_AUTO_INIT_GIT_IF_MISSING`,
`RALPHIE_AUTO_COMMIT_ON_PHASE_PASS`,
`RALPHIE_AUTO_ENGINE_PREFERENCE`,
`RALPHIE_CODEX_ENDPOINT`, `RALPHIE_CODEX_USE_RESPONSES_SCHEMA`, `RALPHIE_CODEX_RESPONSES_SCHEMA_FILE`,
`RALPHIE_CODEX_THINKING_OVERRIDE`, `RALPHIE_CLAUDE_ENDPOINT`, `RALPHIE_CLAUDE_THINKING_OVERRIDE`,
`CODEX_MODEL`, `CLAUDE_MODEL`,
`PHASE_NOOP_POLICY_PLAN`, `PHASE_NOOP_POLICY_BUILD`, `PHASE_NOOP_POLICY_TEST`,
`PHASE_NOOP_POLICY_REFACTOR`, `PHASE_NOOP_POLICY_LINT`, `PHASE_NOOP_POLICY_DOCUMENT`,
`PHASE_NOOP_PROFILE`,
`MAX_ITERATIONS`.

`RESUME_REQUESTED` can be supplied via `.ralphie/config.env` as `RALPHIE_RESUME_REQUESTED=true|false` (default: true).
`REBOOTSTRAP_REQUESTED` can be supplied via `.ralphie/config.env` as `RALPHIE_REBOOTSTRAP_REQUESTED=true|false`.

`PHASE_NOOP_PROFILE` can be supplied via `.ralphie/config.env` as `RALPHIE_PHASE_NOOP_PROFILE=balanced|strict|read-only-first|custom`.

Phase no-op profile precedence: `--phase-noop-profile` / `RALPHIE_PHASE_NOOP_PROFILE` set the profile, and any explicitly passed `--phase-noop-policy-*` flags override profile defaults for that phase.

### Engine, Inference, Model, and Thinking Controls (Optional)

All inference-shaping knobs are optional. If you do not set them, `ralphie.sh` uses built-in defaults.

- `RALPHIE_ENGINE=auto` selects engine automatically.
- `RALPHIE_AUTO_ENGINE_PREFERENCE=codex|claude` controls which engine AUTO prefers first.
- `CODEX_MODEL` and `CLAUDE_MODEL` are optional. Leave empty to use each binary's configured/default model.
- `RALPHIE_CODEX_ENDPOINT` is optional. Leave empty to avoid overriding `OPENAI_BASE_URL`.
- `RALPHIE_CLAUDE_ENDPOINT` is optional. Leave empty to avoid overriding `ANTHROPIC_BASE_URL`.
- `RALPHIE_CODEX_USE_RESPONSES_SCHEMA=true|false` controls codex `--output-schema` usage.
- `RALPHIE_CODEX_RESPONSES_SCHEMA_FILE` is only used when schema mode is enabled.
- `RALPHIE_CODEX_THINKING_OVERRIDE=none|minimal|low|medium|high|xhigh` controls codex reasoning effort.
- `RALPHIE_CLAUDE_THINKING_OVERRIDE=none|off|low|medium|high|xhigh` controls claude thinking behavior.
- `RALPHIE_AUTO_INIT_GIT_IF_MISSING=true|false` initializes a local git repository at startup when missing.
- `RALPHIE_AUTO_COMMIT_ON_PHASE_PASS=true|false` controls phase-gated local commits (no push).
- `RALPHIE_STARTUP_OPERATIONAL_PROBE=true|false` controls startup operational self-checks.
- `RALPHIE_CONSENSUS_SCORE_THRESHOLD=0..100` sets minimum average score for consensus and handoff pass.
- `RALPHIE_ENGINE_OVERRIDES_BOOTSTRAPPED=true|false` controls whether the first-deploy engine override wizard should run.
- `RALPHIE_NOTIFICATIONS_ENABLED=true|false` is the master notification toggle.
- `RALPHIE_NOTIFY_TELEGRAM_ENABLED=true|false` enables Telegram bot notifications (requires `TG_BOT_TOKEN` and `TG_CHAT_ID`).
- `RALPHIE_NOTIFY_DISCORD_ENABLED=true|false` enables Discord webhook notifications (requires `RALPHIE_NOTIFY_DISCORD_WEBHOOK_URL`).
- `RALPHIE_NOTIFY_TTS_ENABLED=true|false` enables Chutes TTS voice notifications over Telegram/Discord (requires `CHUTES_API_KEY`).
- `RALPHIE_NOTIFY_EVENT_DEDUP_WINDOW_SECONDS=N` suppresses duplicate notification events for `N` seconds.
- `RALPHIE_NOTIFY_INCIDENT_REMINDER_MINUTES=N` sends reminders every `N` minutes for sustained incident series.
- `RALPHIE_NOTIFICATION_WIZARD_BOOTSTRAPPED=true|false` controls whether the first-deploy notification wizard should run.

Current defaults are:

- `RALPHIE_ENGINE=auto`
- `RALPHIE_AUTO_ENGINE_PREFERENCE=codex`
- `RALPHIE_AUTO_INIT_GIT_IF_MISSING=true`
- `RALPHIE_AUTO_COMMIT_ON_PHASE_PASS=true`
- `RALPHIE_CODEX_ENDPOINT=""`
- `RALPHIE_CODEX_USE_RESPONSES_SCHEMA=false`
- `RALPHIE_CODEX_RESPONSES_SCHEMA_FILE=""`
- `CODEX_MODEL=""`
- `RALPHIE_CODEX_THINKING_OVERRIDE=high`
- `RALPHIE_CLAUDE_ENDPOINT=""`
- `CLAUDE_MODEL=""`
- `RALPHIE_CLAUDE_THINKING_OVERRIDE=high`
- `RALPHIE_STARTUP_OPERATIONAL_PROBE=true`
- `RALPHIE_CONSENSUS_SCORE_THRESHOLD=70`
- `RALPHIE_ENGINE_OVERRIDES_BOOTSTRAPPED=false`
- `RALPHIE_NOTIFICATIONS_ENABLED=false`
- `RALPHIE_NOTIFY_TELEGRAM_ENABLED=false`
- `RALPHIE_NOTIFY_DISCORD_ENABLED=false`
- `RALPHIE_NOTIFY_TTS_ENABLED=false`
- `RALPHIE_NOTIFY_CHUTES_TTS_URL=https://chutes-kokoro.chutes.ai/speak`
- `RALPHIE_NOTIFY_CHUTES_VOICE=am_michael`
- `RALPHIE_NOTIFY_CHUTES_SPEED=1.0`
- `RALPHIE_NOTIFICATION_WIZARD_BOOTSTRAPPED=false`

Example `.ralphie/config.env`:

```bash
RALPHIE_ENGINE=auto
RALPHIE_AUTO_ENGINE_PREFERENCE=codex
RALPHIE_AUTO_INIT_GIT_IF_MISSING=true
RALPHIE_AUTO_COMMIT_ON_PHASE_PASS=true

RALPHIE_CODEX_ENDPOINT=
RALPHIE_CODEX_USE_RESPONSES_SCHEMA=false
RALPHIE_CODEX_RESPONSES_SCHEMA_FILE=
CODEX_MODEL=
RALPHIE_CODEX_THINKING_OVERRIDE=high

RALPHIE_CLAUDE_ENDPOINT=
CLAUDE_MODEL=
RALPHIE_CLAUDE_THINKING_OVERRIDE=high
RALPHIE_STARTUP_OPERATIONAL_PROBE=true
RALPHIE_CONSENSUS_SCORE_THRESHOLD=70
RALPHIE_ENGINE_OVERRIDES_BOOTSTRAPPED=false

RALPHIE_NOTIFICATIONS_ENABLED=false
RALPHIE_NOTIFY_TELEGRAM_ENABLED=false
TG_BOT_TOKEN=
TG_CHAT_ID=
RALPHIE_NOTIFY_DISCORD_ENABLED=false
RALPHIE_NOTIFY_DISCORD_WEBHOOK_URL=
RALPHIE_NOTIFY_TTS_ENABLED=false
CHUTES_API_KEY=
RALPHIE_NOTIFY_CHUTES_TTS_URL=https://chutes-kokoro.chutes.ai/speak
RALPHIE_NOTIFY_CHUTES_VOICE=am_michael
RALPHIE_NOTIFY_CHUTES_SPEED=1.0
RALPHIE_NOTIFY_EVENT_DEDUP_WINDOW_SECONDS=90
RALPHIE_NOTIFY_INCIDENT_REMINDER_MINUTES=10
RALPHIE_NOTIFICATION_WIZARD_BOOTSTRAPPED=false
```

Supported no-op profiles:
- `balanced` (default): plan=`none`, build=`hard`, test=`soft`, refactor=`hard`, lint=`soft`, document=`hard`.
- `strict`: all phases (`plan`, `build`, `test`, `refactor`, `lint`, `document`) `hard`.
- `read-only-first`: plan=`none`, build=`hard`, test=`soft`, refactor=`none`, lint=`soft`, document=`none`.
- `custom`: only explicit per-phase flags apply.

Defaults:
- `max-session-cycles`: `0` (unlimited)
- `session token budget`: `0` (unlimited)
- `session cost budget`: `0` (unlimited)
- `max-phase-completion-attempts`: `3`
- `max-consensus-routing-attempts`: `2`
- `run-agent-max-attempts`: `3`
- `auto-init-git-if-missing`: `true`
- `auto-commit-on-phase-pass`: `true` (local commit only; no push)
- `engine-output-to-stdout`: `true`
- `SWARM_CONSENSUS_TIMEOUT`: `600`
- `phase-noop default policy`: plan=`none`, build=`hard`, test=`soft`, refactor=`hard`, lint=`soft`, document=`hard`
- `resume`: enabled by default (`--resume`)

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
- After configuring identity (`git config user.name/user.email` or `GIT_COMMITTER_*` env vars), restart with `--resume`; Ralphie re-checks identity and auto-commit can resume.
- If the run starts from a dirty worktree, the first phase commit may include those pre-existing local changes.

## Git Repository Bootstrap

- By default, Ralphie initializes a git repository at startup when one is missing.
- This behavior is controlled by `RALPHIE_AUTO_INIT_GIT_IF_MISSING` (or `--auto-init-git-if-missing`).
- If git is unavailable and auto-init is enabled, startup fails early.

## Startup Operational Probe

- When `RALPHIE_STARTUP_OPERATIONAL_PROBE=true`, Ralphie validates core runtime dependencies before the loop starts.
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
- Completion state is stored in `RALPHIE_ENGINE_OVERRIDES_BOOTSTRAPPED=true` to avoid repeated prompting.
- To re-run the wizard later, set `RALPHIE_ENGINE_OVERRIDES_BOOTSTRAPPED=false` in config.

## First-Deploy Notification Wizard

- On first interactive run, Ralphie can prompt once for notification setup.
- Supported channels:
  - Telegram bot messages (`TG_BOT_TOKEN`, `TG_CHAT_ID`)
  - Discord webhook (`RALPHIE_NOTIFY_DISCORD_WEBHOOK_URL`)
  - Optional Chutes TTS voice attachments for Telegram/Discord (`CHUTES_API_KEY`)
- The wizard includes quick setup guidance, auto-chat-id discovery for Telegram via `getUpdates`, and sends test messages during setup.
- The wizard can also configure anti-spam cadence (`RALPHIE_NOTIFY_EVENT_DEDUP_WINDOW_SECONDS`, `RALPHIE_NOTIFY_INCIDENT_REMINDER_MINUTES`).
- Notification events are standardized:
  - `session_start`
  - `phase_decision`
  - `phase_complete`
  - `phase_blocked`
  - `session_done`
  - `session_error`
- Notification policy is high-signal only. Repeated incidents are suppressed and re-notified on reminder cadence.
- Selections are persisted to `.ralphie/config.env`.
- Completion state is stored in `RALPHIE_NOTIFICATION_WIZARD_BOOTSTRAPPED=true`.
- To re-run later, set `RALPHIE_NOTIFICATION_WIZARD_BOOTSTRAPPED=false`.

## Credits

Ralphie was inspired by the original [`ralph-wiggum`](https://github.com/fstandhartinger/ralph-wiggum) project by Florian Standhartinger.
