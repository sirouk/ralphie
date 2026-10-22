# Ralphie

May continuation, based on the `2.0.0` checkpoint from May 26, 2026.

Ralphie is a single-file autonomous engineering orchestrator for Prime Agent, Codex, and Claude Code. Give it an objective or a seed document for a new or existing project. It develops the research and plan, then works through implementation, testing, refactoring, linting, and documentation with scored consensus review and resumable state.

This branch, `feature/may-autonomy-prime`, continues the May harness. It preserves its development phases and adaptive review routing while adapting useful correctness and engine-integration lessons from the later `master` implementation.

## Design Philosophy

Ralphie asks agents to research and critique their specifications and implementation plans before building. Reviewer scores guide phase transitions; independent project checks establish whether the resulting work passes. Review approval and a successful executable check provide different evidence, and both matter.

## Core Features

-   **Recursive Planning:** Merges research, specification, and implementation planning into a single high-fidelity `Plan` mode.
-   **Deep Consensus Swarm:** Multi-persona reviewer panels (Architect, Skeptic, Execution Reviewer, Safety Reviewer, Operations Reviewer, Quality Reviewer) with score/verdict routing (`GO|HOLD`) and next-phase recommendations.
-   **Autonomous execution:** Engines can run commands and modify project files using their supported execution controls. They run with the invoking user's permissions.
-   **Self-Healing State:** SHA-256 checksum-validated state snapshots that detect artifact drift and allow for robust recovery via `--resume`.
-   **Process cleanup:** Managed-process tracking and descendant snapshots stop local engine processes on timeout or interrupt.
-   **Self-Contained Runtime:** Runtime behavior is version-stable and local to the checked-out orchestrator script. Optional pre-run self-update can replace only `ralphie.sh` before startup, then re-exec the verified copy.
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

`ralphie.sh` never mutates itself mid-session. By default, release drift is handled through normal checkout/version control workflows.

Optional pre-run single-file self-update is available with:

```bash
AUTO_UPDATE=true ./ralphie.sh
```

Updating is disabled by default. When enabled, Ralphie uses an explicit
operator source (`RALPHIE_UPDATE_URL`, or `--auto-update-url`) or the canonical
published Ralphie source. It never
derives an update from the managed project's Git remote, and project
`config.env` cannot select the downloaded script. A published continuation or
private mirror needs its own explicit raw source URL; the public `master`
currently follows the separate newer design.

Only `ralphie.sh` is downloaded. Ralphie validates the candidate without
executing it, syntax-checks it, writes a timestamped backup under
`.ralphie/self-update/`, atomically replaces the installed script, and re-execs
once with an update loop guard.

Safety defaults:

- local uncommitted edits to `ralphie.sh` block self-update unless `AUTO_UPDATE_ALLOW_DIRTY=true`;
- `https://`, `file://`, and local paths are accepted; plaintext `http://` requires `AUTO_UPDATE_ALLOW_INSECURE=true`;
- concurrent starts share a short self-update lock so only one process can replace `ralphie.sh` at a time;
- failed fetch, failed validation, or failed replacement leaves the current script in place;
- `curl | bash` remains install-and-run bootstrap only and re-execs with auto-update skipped for that first persisted run.

## Engine Authority

Engines execute with the invoking user's permissions. Claude's `IS_SANDBOX=1`
environment and approval flags do not create an operating-system sandbox.
Prime's direct CLI execution is also not a sandbox. Use the host project's
normal isolation and access controls when work requires them.

Ralphie retains phase orchestration, retries, scoring, state, and verification.
Reviewer personas provide judgment; their prose does not substitute for an
executed project check. Prime calls use independent prompts rather than a
shared continuation session or a second nested lifecycle loop.

## Usage

### Quick Start

From this checkout, target the project you want to work on:

```bash
./ralphie.sh --project /path/to/project --engine prime-agent \
  --objective "Fix the failing checkout tests and document the result"
```

Only `ralphie.sh` is needed at runtime. You can also plant that file directly in
a project. The public `master` install URL follows the separate newer design;
it does not install this local continuation branch.

### Start from an objective or document

The target directory must already exist. If it is inside Git, select the
repository root; a nested directory is refused before runtime setup. An empty
directory is a new project; an existing codebase is researched before its
implementation plan is built.

```bash
# Use an existing project check as the acceptance condition.
./ralphie.sh --project /path/to/project --engine prime-agent \
  --objective "Fix the checkout bug described in issue 42" \
  --accept './test.sh'

# Pass the complete document, not just its filename or a generated summary.
./ralphie.sh --project /path/to/project --engine prime-agent \
  --spec /path/to/project-seed.md

# Research, specify and review the plan without authorizing BUILD.
./ralphie.sh --project /path/to/project --engine prime-agent \
  --spec /path/to/project-seed.md --plan-only
```

An explicit objective or seed document authorizes the local lifecycle unless
`--plan-only` is selected. These launches suppress bootstrap questionnaires,
setup wizards and terminal interrupt menus, so another agent can supervise them.
The complete document is retained as project goals context. Relative target
and document paths are resolved from the calling directory.

Repeating the same seed resumes the saved mission. A different seed requires
`--no-resume`; it cannot quietly inherit a completed or interrupted mission's
phase state. The selected check definitions are bound to that mission too;
changing `.ralphie/gates` or adding a different `--accept` requires reviewing
the checks and starting with `--no-resume`. After a successful planning-only
run, the same seed and check definitions without `--plan-only` can continue
into BUILD.

For Prime-specific overrides, use `--prime-provider`, `--prime-model` and
`--prime-thinking`. Without overrides, Prime uses its own configured defaults.
Automatic selection prefers Prime when available; an explicit `--engine` is
honored for execution, handoff and consensus without switching engines on failure.

### Executed project checks

Scored consensus reviews retain the May harness's planning and phase-routing
role. Successful local completion also requires actual shell-run project
checks. Use repeatable `--accept 'command'` arguments or list commands in
`.ralphie/gates`, one per line. Ralphie can discover conventional project test
commands when explicit checks have not been supplied.

The selected check definitions are protected across engine and reviewer calls.
Checks run against the reviewed work, including again before terminal completion.
A reviewer mentioning `pytest`, inventing command output, or voting GO cannot
overrule a failing check. A new project may PLAN and BUILD before a test command
exists, but it cannot claim verified completion without executable checks.

Checks run with your permissions. A check that changes HEAD or the nonignored
project files fails verification, even if it exits successfully; generated
build and test artifacts should be ignored by Git. Each check has a 900-second
default deadline, configurable with `--gate-timeout-seconds` or
`RALPHIE_GATE_TIMEOUT_SECONDS`. CLI controls do not provide an operating-system
sandbox.

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

Startup bootstrap is interactive when a terminal is attached (`/dev/tty` is present). This includes `curl | bash` runs: stdin carries the script stream, and prompts are read from the controlling terminal when available.
- `project_type`: is this a new project?
- `objective`: what should Ralphie optimize for?
- `constraints` and `success_criteria`: quick single-line defaults (press Enter to keep)
- optional `goals document URL`: single-line link input (press Enter to skip)
- optional multi-line `project goals/context` paste mode:
  - paste full document content or URL notes
  - finish with a line containing only `EOF` (or press `Ctrl+D`)
- `build_consent`: proceed from PLAN to BUILD automatically when gates pass?

When no terminal is available, bootstrap uses deterministic fallback values and records `interactive_prompted: false`. In that non-interactive fallback, `build_consent` defaults to `false`; Ralphie can complete planning but will not proceed into BUILD until you set consent intentionally, for example by rerunning `./ralphie.sh --rebootstrap` in a terminal or editing `.ralphie/project-bootstrap.md`.

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

### Continuing With A New Focus

Ralphie keeps two separate pieces of operator state:

- `.ralphie/state.env` stores the current phase, phase attempt, iteration
  counters, route history, and completion state. `--resume` is the default, so
  plain `./ralphie.sh` tries to load this file.
- `.ralphie/project-bootstrap.md` stores the project type, objective,
  constraints, success criteria, architecture/technology preferences, and
  plan-to-build consent. `--rebootstrap` refreshes this file; it does **not**
  disable resume by itself.

Plain `./ralphie.sh` means **continue the current mission**. That is the right
default after a crash, timeout, pause, or terminal disconnect because Ralphie
can restore the exact phase and attempt from `.ralphie/state.env`. It is also
why plain `./ralphie.sh` is not the right launch mode for unrelated work after a
completed loop: if state says `CURRENT_PHASE=done`, Ralphie will resume that
completed mission and exit done again.

After a mission has met its goals, treat the next objective as a new mission
instead of resuming the old one. The hardened operator pattern is:

1. Checkpoint the completed work with a commit, tag, or other intentional
   project-local snapshot.
2. Update `.ralphie/project-goals.md` and/or `IMPLEMENTATION_PLAN.md` so the
   next active objective is explicit.
3. Keep large steering docs as **reference** material unless their checkboxes
   are truly live backlog. A steering/spec file can be named from
   `.ralphie/project-goals.md`; it does not have to be listed in
   `--backlog-sources`.
4. Keep `IMPLEMENTATION_PLAN.md` as the active backlog source unless you have a
   second file that is intentionally acting as a current checklist.
5. Launch the new mission with `--no-resume`.

Prepared fresh mission, when you have already updated project goals / active
backlog:

```bash
# update project-goals/backlog somehow
./ralphie.sh --no-resume --backlog-sources 'IMPLEMENTATION_PLAN.md,AGENTS.md'
```

Interactive fresh mission, when you want Ralphie to ask the bootstrap
questions again:

```bash
./ralphie.sh \
  --no-resume \
  --rebootstrap \
  --backlog-sources 'IMPLEMENTATION_PLAN.md,AGENTS.md'
```

Use `--resume` or plain `./ralphie.sh` again only after that new mission has
started and you want Ralphie to continue the same in-flight work.

For a legacy mission created without `--objective` or `--spec`,
`--rebootstrap` can enrich bootstrap intent while preserving phase state.
Seeded missions keep their exact supplied intent; replace it with
`--no-resume --objective ...` or `--no-resume --spec ...`. Do not manually
delete `.ralphie/state.env` for normal operator steering.

#### Reference sources vs. backlog sources

Ralphie has powerful freshness and terminal-done guards, but those guards only
know about files listed as backlog sources. Do not put broad constitutions,
historical audits, long steering docs, or future-roadmap checklists in
`--backlog-sources` unless every unchecked task in those files should block
terminal `done`.

Use this split:

- **Guardrails:** `AGENTS.md`, `.specify/memory/constitution.md`, project
  operating rules.
- **Reference:** design docs, large steering docs, architecture notes,
  historical audit files. Mention these from `.ralphie/project-goals.md` or
  `IMPLEMENTATION_PLAN.md` so PLAN can read them.
- **Active backlog:** `IMPLEMENTATION_PLAN.md`, plus any small current-slice
  checklist that should block `done`.
- **Evidence:** completion logs, build notes, test reports. These should inform
  PLAN/TEST but should not usually be backlog sources.

If remaining work must block `done`, make it machine-readable in the active
backlog. Ralphie's terminal backlog guard scans unchecked markdown tasks in
configured backlog sources; prose-only future slices may be documented but may
not block completion. Prefer explicit checkboxes:

```markdown
- [x] Slice 1: Completed previous focus
- [ ] Slice 2: Next focus
- [ ] Slice 3: Later focus
```

After a PLAN phase passes, Ralphie records a fingerprint of configured backlog
sources in `.ralphie/state.env`. BUILD freshness checks compare against that
checkpoint. If a listed source changes later, Ralphie routes back through PLAN.
This protects against stale plans, but it also means incorrectly listed
reference files can cause plan loops or terminal-done deadlocks.

#### What plain `./ralphie.sh` does

With no flags, Ralphie:

1. Loads `.ralphie/config.env` if present.
2. Uses `--resume` behavior by default.
3. Loads `.ralphie/state.env` if it exists and passes checksum validation.
4. Runs startup probes and engine health checks.
5. Reuses `.ralphie/project-bootstrap.md` if it is valid.
6. Prompts only when interactive input is available **and** bootstrap or
   first-deploy setup needs attention.
7. Enters the persisted phase/attempt, or starts at PLAN if there is no valid
   state.

So yes, Ralphie can ask questions, but it does not ask every time. A no-flag
run is intentionally optimized for durable resumption. To force questions for a
new mission, use `--no-resume --rebootstrap`.

Current interactive prompt surfaces include:

- project bootstrap (`new` vs `existing`, objective, constraints, success
  criteria, architecture, technology, goals/context, build consent);
- first-deploy engine override wizard;
- first-deploy notification wizard.

If no terminal is attached, Ralphie uses deterministic fallback bootstrap
values and defaults build consent to false.

#### Seed a new mission

Use `--objective` or `--spec` for a prepared, unattended mission, with
`--no-resume` when replacing an existing objective. Keep broad reference documents
separate from the active backlog so future ideas do not prevent completion of
the current slice.

A small current-slice steering or goals block should stay short, explicit, and
bounded. This shape works well when pasted into `.ralphie/project-goals.md` or
linked from `IMPLEMENTATION_PLAN.md` as reference context:

````markdown
# Ralphie Steering: Next Focus

## Current State
- What is already complete.
- What validation already passed.

## Next Objective
One precise build slice Ralphie should complete next.

## Do Not Rebuild
- Stable surfaces that should be preserved unless a focused test fails.

## Expected Outputs
- Files, modules, docs, or tests that should change.

## Validation Floor
```bash
git diff --check
./project-specific-test-command
```

## Done Means
- The exact observable outcome required before Ralphie may route to done.
````

### Reference Sources

- `engines/setup-agent-subrepos.sh` is retained for comparative engine behavior research only.
- It is **not** required for a standard `ralphie.sh` run on a user project.

## Runtime Configuration (CLI + `config.env`)

`ralphie.sh` supports explicit session/retry budgets plus optional cost accounting. Defaults favor resumability and developer autonomy; CI presets are provided for stricter caps.

Session totals include worker, handoff, consensus, retry and paid engine-health
canary attempts, and are retained on resume. Free CLI capability probes and
shell checks are excluded. `--max-session-cycles N` admits at most N inference
attempts; the last allowed successful attempt can still pass its gate. A finite
attempt, token or cost budget makes consensus reviewers run sequentially so
each admission uses the current totals. Unbounded runs retain parallel review.
Token and cost totals are byte-based estimates, not provider billing receipts;
an admitted request can cross those estimated limits before its result is
available, after which further inference is refused. Interrupted requests can
lack a settled token or cost estimate.

### CLI Flags

- `--project DIR`
- `--objective TEXT`
- `--spec FILE`
- `--plan-only`
- `--accept COMMAND` (repeatable)
- `--gate-timeout-seconds N`
- `--engine auto|prime-agent|codex|claude`
- `--prime-provider NAME`
- `--prime-model MODEL`
- `--prime-thinking LEVEL`
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
- `--auto-engine-preference prime-agent|codex|claude`
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
Self-update settings are operator-only and cannot be supplied by this file.
Ralphie supports both CLI flags and environment/config keys, but this README intentionally avoids mirroring the full key surface to prevent drift.

Operator guidance:

- Use CLI flags for run-scoped overrides.
- Use `.ralphie/config.env` for stable project/operator defaults.
- Treat `./ralphie.sh --help` as the source of truth for supported options and compatibility aliases.
- Use the startup config banner as the source of truth for effective values after config/env/CLI precedence.

Phase no-op profile precedence: explicit per-phase policy flags win over profile-derived policy values.
`--strict-validation-noop true` is a compatibility hardening switch for test and lint no-op handling after profile and explicit policy resolution; it does not make the plan phase require worktree mutation.

Supported no-op profiles:
- `balanced` (default): plan=`none`, build=`hard`, test=`soft`, refactor=`hard`, lint=`soft`, document=`soft`.
- `strict`: all phases (`plan`, `build`, `test`, `refactor`, `lint`, `document`) `hard`.
- `read-only-first`: plan=`none`, build=`hard`, test=`soft`, refactor=`none`, lint=`soft`, document=`none`.
- `custom`: starts from balanced defaults; explicit per-phase policies override them.

Behavior summary:
- `0` values for retry/routing budgets are treated as unlimited loops with stagnation guards.
- Resume remains enabled by default (`--resume`); use `--no-resume --rebootstrap` when changing to a new mission or focus.
- Terminal routing to `done` is guarded: lint and document must each pass at least once before completion.

Prime supports `--prime-thinking off|minimal|low|medium|high|xhigh|max`. Its
executable can be selected with `RALPHIE_PRIME_ENGINE_CMD`; provider, model and
thinking environment overrides use `RALPHIE_PRIME_PROVIDER`,
`RALPHIE_PRIME_MODEL` and `RALPHIE_PRIME_THINKING_OVERRIDE`. Explicit CLI values
take precedence over exported environment, project configuration and defaults.

Captured engine output is limited to 16 MiB per stream per attempt by default
(`RALPHIE_ENGINE_OUTPUT_MAX_BYTES`). Exceeding the cap stops the attempt rather
than accepting a truncated answer. Prime and Claude print mode buffer output,
so silence alone does not time them out. A positive
`RALPHIE_COMMAND_TIMEOUT_SECONDS` enforces a whole-call deadline even without a
`timeout` executable; `0` leaves that deadline disabled. Reviewers also have
their own consensus timeout.

Successful lifecycle completion exits `0`. Successful `--plan-only` also exits
`0`, reports planning completion and saves BUILD as the next phase. Failed or
incomplete runs exit nonzero; reaching a cycle or budget limit is not completion.

## Interrupt Controls

In interactive mode, pressing `Ctrl+C` stops managed child processes, persists
state, and opens a control menu:

- `r` resume immediately (default)
- `l` toggle live engine output on/off
- `p` persist state and pause
- `q` immediate stop
- `h` help

The current `engine-output-to-stdout` mode is preserved in session state and reused on resume.

If you press `Ctrl+C` again while the interrupt menu is already open, Ralphie
exits immediately after cleanup. In non-interactive contexts there is no menu:
an interrupt triggers cleanup, state persistence, managed process termination,
lock release, and exit.

Use `p` when you want the most durable pause/resume boundary. The next plain
`./ralphie.sh` run resumes that same mission from saved state. Use
`--no-resume` only when you intentionally want a new mission/fresh phase loop
instead of continuing the paused one.

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
- If identity is missing while auto-commit is enabled, startup fails before
  engine work. Configure `git user.name`/`user.email` or equivalent identity
  environment and resume; use `--auto-commit-on-phase-pass false` only when you
  intentionally want to manage saves yourself.
- Commits are scoped to files touched in the current phase manifest delta; pre-staged index content is skipped to avoid accidental mixed commits.
- A required but unsuccessful save blocks the phase. Validation-only phases
  without savable changes do not need an empty commit.

## Git Repository Bootstrap

- By default, Ralphie initializes a git repository at startup when one is missing.
- This behavior is configurable through the startup options surface.
- If git is unavailable and auto-init is enabled, startup fails early.

## Startup Operational Probe

- When startup operational probing is enabled, Ralphie validates core runtime dependencies before the loop starts.
- This includes command availability checks for core shell tooling and git workflow commands (`git`, `seq`, `cut`, `head`, `tail`, `wc`, `tr`, `tee`, `comm`, `cmp`, plus base shell utilities).
- It also validates writable state storage and timeout wrapper behavior.

The runtime remains one Bash script, with Bash 3.2, standard command-line tools,
Git and `ps` for process discovery. Prime, Codex and Claude are selectable
external engines. Python, Node, jq, pgrep and a timeout binary are not added
runtime requirements; an individual project's checks may have their own tools.

## First-Deploy Engine Override Wizard

- On first interactive run, Ralphie can prompt once for engine override setup after engine readiness checks pass.
- The wizard can update:
  - engine mode (`auto|prime-agent|codex|claude`) and AUTO preference
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

- Auto run (push + PR): runs `./test.sh --skip-live` on Ubuntu and macOS using
  the system Bash. The macOS job exercises Bash 3.2.
- Manual run (`workflow_dispatch`): optional direct provider API smoke check using `tests/durability/run-live-smoke.sh`.

### Live smoke inputs

- `run_live_smoke` (`true|false`): whether to execute live smoke.
- `live_engine` (`codex|claude`): which provider API path to smoke-test.

### Live smoke interactive behavior

- Running `tests/durability/run-live-smoke.sh` in an interactive terminal now prompts for:
  - provider selection (`codex|claude`) when not explicitly provided
  - optional temporary API key/model/endpoint overrides for the selected provider path
- These overrides are in-memory for that invocation only and are not persisted.
- You can force prompt mode with `--prompt` or disable prompts with `--no-prompt`.

Live smoke calls the OpenAI Responses API or Anthropic Messages API directly with `curl`; it does not exercise the installed Codex or Claude CLI binaries.

### Live smoke secrets/vars

- Configure provider API credentials for the provider path you want to smoke-test.
- Optional endpoint/model overrides are supported for both provider paths.
- Use `.github/workflows/durability-ci.yml` and `tests/durability/run-live-smoke.sh --help` for the exact key names and current defaults.

Live smoke is manual by default because it uses real provider credentials and can incur usage cost.

## Controlled Claude Phase Stress Harness

For fast, fail-fast, end-to-end orchestration validation (all Ralphie phases with handoff + consensus), use:

```bash
tests/durability/run-claude-phase-stress.sh
```

This harness runs in isolated temporary workspaces using a deterministic mock Claude binary (`tests/durability/mock-claude-control.sh`) and verifies:

- full lifecycle path, including a test pass after refactoring:
  `plan -> build -> test -> refactor -> test -> lint -> document -> done`
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

Use a frozen copy of the candidate to execute the full pre-ship chain. Do not
edit `ralphie.sh` during a suite run: fixtures copy it at different times.

```bash
./test.sh --skip-live
```

Default sequence:
- bash syntax checks for `ralphie.sh` and support scripts
- `shellcheck` for support scripts when available
- offline `engines/setup-agent-subrepos.sh` fixture check
- `tests/durability/run-durability-suite.sh`
- `tests/durability/run-continuation-suite.sh` for Prime's CLI, seeded/headless
  use, executed gates, protected operator files and process cleanup
- `tests/durability/run-claude-phase-stress.sh --scenarios full,retry,resume`
- Live provider smoke is disabled by default. `--live` and `--auto-live`
  explicitly enable the separate direct-provider smoke path and can incur cost.

Common flags:
- `--live` (require live smoke and fail if creds missing)
- `--auto-live` (explicitly permit live smoke when matching credentials exist)
- `--skip-live` (offline-only pre-ship run)
- `--live-engine codex|claude`
- `--stress-scenarios full,retry,resume`
- `--discord-webhook-url <url>`
- `--exercise-tts-fallback` (requires webhook)

## Credits

Ralphie was inspired by the original [`ralph-wiggum`](https://github.com/fstandhartinger/ralph-wiggum) project by Florian Standhartinger.
Florian's original work is the foundation for this project's name, spirit, and autonomous orchestration direction.
