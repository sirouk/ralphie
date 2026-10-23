# Ralphie

Ralphie is one portable Bash script that develops a new or existing project from
an objective or specification. It works through PLAN, BUILD, TEST, REFACTOR,
LINT and DOCUMENT with Prime Agent, Codex or Claude Code. Reviewers guide the
route; executed project checks determine whether the result passes.

The default `main` branch continues the May 26, 2026 `2.0.0` harness. The later
simplified design is preserved at `tangent/simplified-harness`; legacy `master`
install links remain frozen on that design. Use `main` for this continuation.

- [Before you start](#before-you-start) and [Quick Start](#quick-start)
- [Human, agent and unattended runs](#human-agent-and-unattended-runs)
- [Observe progress](#observe-progress)
- [Interrupt, steer and resume](#interrupt-steer-and-resume)
- [Executed project checks](#executed-project-checks)
- [Interactive bootstrap](#interactive-bootstrap)
- [Runtime configuration](#runtime-configuration-cli--configenv)
- [Lifecycle and governance](#operational-phases--governance)
- [Installation and self-update](#runtime-management)
- [CI and tests](#github-actions-ci)
- [Agent guide](AGENTS.md)

## Before you start

- Have Bash 3.2 or newer, standard Unix command-line tools, Git and `ps`.
  Python, Node, jq, pgrep and a `timeout` binary are not required by Ralphie.
- Install and configure at least one supported engine: `prime-agent`, `codex`
  or `claude`. Provider authentication and model access belong to that engine.
- Select an existing directory. It can be empty for a new project; inside Git,
  select the repository root, not a nested directory.
- Configure a Git commit identity if using the default automatic phase commits.
  Ralphie never pushes. Use `--auto-commit-on-phase-pass false` only when you
  intend to manage local saves yourself.
- Know the project check to run, such as `./test.sh`. New projects can plan and
  build before a check exists, but verified completion needs executable checks.

Engines and checks run with your permissions. Use the project's normal isolation
and access controls; the CLI flags do not provide an operating-system sandbox.

The script, invocation directory, project and owned runtime roots (including
`TMPDIR` and initialized submodule roots) cannot contain CR or LF characters.
Project filenames within those roots may contain tabs or newlines.

## Quick Start

From this checkout, launch one prepared mission against your project:

```bash
./ralphie.sh --project /path/to/project --engine prime-agent \
  --objective "Fix the failing checkout tests and document the result" \
  --accept './test.sh'
```

Replace the objective and check with your own. This authorizes the local
lifecycle and runs in the foreground without questionnaires. Automatic saves
create local phase commits. The check runs from the target project root.

Only `ralphie.sh` is needed at runtime. To install it in the current directory
and show help without starting an engine:

```bash
curl -fsSL https://raw.githubusercontent.com/sirouk/ralphie/main/ralphie.sh | bash -s -- --help
```

Use `./ralphie.sh --help` to inspect the available options without probing or
calling an engine. If the script is not executable, use `bash /path/to/ralphie.sh`.

## Human, agent and unattended runs

The interface is the same CLI for a person or a supervising agent:

| Workflow | How to start | Terminal behavior |
|---|---|---|
| Guided human setup | `./ralphie.sh --project /path/to/project` | Asks bootstrap and first-deploy questions when needed and a terminal is available. |
| Prepared human or agent mission | Add `--objective TEXT` or `--spec FILE` | No questionnaires or interrupt menu, even in a terminal. |
| Planning only | Add `--plan-only` to the prepared launch | Researches, specifies and reviews the plan; saves BUILD as the next phase. |
| Resume the same mission | Repeat the original launch options, or use `--resume` with the same project | Restores saved phase/attempt and counters. A saved seeded mission still does not prompt. |

Current `main` uses options rather than `run`, `start`, `chat`, `watch` or
`status` subcommands. A supervising agent supplies the objective/specification,
checks and explicit engine choices, then inspects the same output and files a
human can read. For agents working on Ralphie itself, start with [AGENTS.md](AGENTS.md)
and its required [orchestration skill](skills/software-development/ralphie-orchestration/SKILL.md).

### Start from a document; approve planning before BUILD

`--spec` retains the complete document as mission context. Relative target and
specification paths resolve from the invocation directory.

```bash
./ralphie.sh --project /path/to/project --engine prime-agent \
  --spec /path/to/project-seed.md --accept './test.sh' --plan-only
```

After planning succeeds, deliberately authorize development by repeating the
**same seed and checks without `--plan-only`**:

```bash
./ralphie.sh --project /path/to/project --engine prime-agent \
  --spec /path/to/project-seed.md --accept './test.sh'
```

Plain `--resume` after planning-only retains the saved `build_consent: false`;
it does not grant BUILD consent. A changed seed or selected check definition
requires a new mission with `--no-resume`.

For Prime overrides, use `--prime-provider`, `--prime-model` and
`--prime-thinking`. Without overrides, Prime uses its configured defaults.
Automatic selection prefers Prime when available. An explicit `--engine`
binds execution, handoff and consensus without switching engines on failure.

### Unattended launch with explicit limits

An explicit seed makes the run unattended. On a fresh unseeded launch without
prepared bootstrap context, removing the terminal defaults build consent to
false. For example:

```bash
RALPHIE_COMMAND_TIMEOUT_SECONDS=120 RALPHIE_SWARM_CONSENSUS_TIMEOUT=120 \
  ./ralphie.sh --project /path/to/project --engine prime-agent \
  --objective "Fix the failing checkout tests and document the result" \
  --accept './test.sh' --max-session-cycles 60 \
  --max-phase-completion-attempts 3 --phase-wallclock-limit-seconds 900 \
  --gate-timeout-seconds 180 </dev/null
```

These example limits cap inference admissions, worker/reviewer calls, phase
attempts and checks; adjust them for your project. Limits can stop an incomplete
mission and are not provider billing limits. Resuming retains session totals.
See [budgets and configuration](#runtime-configuration-cli--configenv).

Ralphie remains a foreground process. Unattended means it does not ask for
terminal input; it does not imply background supervision or survival across
terminal closure, logout or reboot. Arrange process supervision separately if
needed, and relaunch to resume after interruption.

## Observe progress

Keep the launch terminal open for phase/attempt messages, checks, decisions and
engine output. Engine output is enabled by default; use
`--engine-output-to-stdout true|false` to choose it for a launch. Prime and
Claude print mode buffer their answers, so a silent interval is not proof that
the worker has stopped. Enabling output does not make those engines stream.

For a persistent console record, append `> /tmp/ralphie-run.log 2>&1` to your
launch command. Keep this log outside the managed project so it cannot change
the tree during verification. In another terminal:

```bash
tail -f /tmp/ralphie-run.log
```

You can inspect the following files read-only from the target project root;
they appear as setup and the relevant actions run:

| File or directory | What it tells you |
|---|---|
| `.ralphie/state.env` | Current phase, attempt, in-progress flag, iteration and session counters. Read it as data; do not source or edit it to steer work. |
| `.ralphie/verification.jsonl` | Recorded shell-check commands and outcomes. |
| `.ralphie/reasons.log` | Reason-coded refusals, limits and failures. |
| `.ralphie/last_gate_feedback.md` | Latest blockers written by Ralphie; this is output, not a human-request inbox. |
| `logs/`, `completion_log/`, `consensus/` | Phase execution logs, outputs, handoff and reviewer artifacts. |

```bash
cd /path/to/project
sed -n '1,120p' .ralphie/state.env
tail -n 30 .ralphie/reasons.log
tail -n 20 .ralphie/verification.jsonl
```

Successful lifecycle completion exits `0`. Successful planning-only also exits
`0`, reports planning completion and saves BUILD next. An intentional interactive
pause exits `0` with resumable unfinished state. Failures and incomplete limit
stops exit nonzero; a cycle or budget limit is not completion.

## Interrupt, steer and resume

Use durable requests for feedback while work is running. Stop or pause first
when you need to edit the plan or replace the mission itself.

### Stop or pause before changing direction

For an **unseeded interactive** run, `Ctrl+C` normally stops managed children
and opens the control menu:

- `r`: resume immediately (default)
- `l`: toggle engine output; the choice is saved for resume
- `p`: persist state, clean up and pause
- `q`: stop immediately
- `h`: show help

A second `Ctrl+C` while the menu is open exits after cleanup. `Ctrl+D` at the
menu saves and pauses, just like `p`; it never selects resume. For a seeded run,
a run without terminal input, or a short request-publication checkpoint,
`Ctrl+C` instead cleans up, persists state, releases the lock and exits; it
never opens this menu. Let cleanup finish before launching another worker.

### Human requests and steering

After Ralphie initializes a saved mission, a person or supervising agent can
submit feedback from another terminal without stopping the worker:

```bash
./ralphie.sh --project /path/to/project \
  --request "Keep the existing checkout API; add coverage for empty carts."
./ralphie.sh --project /path/to/project --requests
```

For multiline input, use `--request-file /path/to/feedback.md`. The copied
request retains its exact bytes, including trailing newlines. Each request
accepts 1–4096 bytes of valid UTF-8 text; at most 32 can remain active. These
control commands never call an engine. `--requests-json` provides the same
retained requests and presentation fields as JSON for another agent. A live
worker must support this request channel; stop an older worker and resume with
this version before submitting feedback.

A request does not interrupt an engine call or shell check already running.
At the next safe boundary, Ralphie detects the changed request set, rejects
approval based on the old set and returns to PLAN. Active requests appear in
subsequent worker, handoff and consensus prompts until explicitly archived.
They can refine work within the mission; they cannot grant BUILD consent,
change the selected engine/model/provider or replace protected checks.
Ordinary budgets, plan freshness and executed checks still apply.

Read the receipt before assuming delivery:

| Receipt | Meaning |
|---|---|
| `queued` | The request is stored, awaiting worker presentation. |
| `presented` / `worker_presented: true` | Its snapshot was included in an admitted worker prompt. This is not implementation or verified completion. |
| `review_presented: true` | The snapshot was included in an admitted review prompt. |
| `archived` | The request is retained for history and excluded from future active prompts. Earlier work is not undone. |

To remove an active request, stop or pause the worker and let cleanup finish,
then use the ID printed by `--requests`:

```bash
./ralphie.sh --project /path/to/project --archive-request req-ID
# Or explicitly archive every active request:
./ralphie.sh --project /path/to/project --archive-request all
```

Archiving is refused while a worker is running. An uninitialized project
cannot accept requests, and a completed mission refuses new requests. Start a
new mission for new intent, explicitly archiving the previous mission's active
requests first. Do not combine request controls with objective/specification
or fresh-start options, or edit the queue files by hand.

The [archived simplified harness](https://github.com/sirouk/ralphie/tree/tangent/simplified-harness)
used a `request` subcommand at the next cycle. This continuation uses the flags
above and checks safe boundaries throughout its multi-phase lifecycle.
Creating `HUMAN_INSTRUCTIONS.md`, `research/HUMAN_FEEDBACK.md` or editing
`.ralphie/last_gate_feedback.md` does not enqueue a durable request.

For direct plan edits or a different objective:

1. Stop or pause the worker and let cleanup finish.
2. For the same objective, update the active `IMPLEMENTATION_PLAN.md` backlog
   or its referenced context while stopped, then resume. Ralphie re-reads
   backlog content; configured freshness checks can require another PLAN pass.
3. For a new or changed objective, archive active requests while stopped and
   supply a new seed with `--no-resume`:

   ```bash
   ./ralphie.sh --project /path/to/project --engine prime-agent --no-resume \
     --objective "Implement the next checkout slice" --accept './test.sh'
   ```

Mission objective/specification, bootstrap consent and selected checks are
snapshotted and protected. Editing their saved copies is not a steering API;
Ralphie can restore/reject those changes. Replace a seeded mission explicitly
instead. Changed `.ralphie/gates` or `--accept` definitions also require reviewed
checks and `--no-resume`.

### Resume the same mission

Repeat the original launch options with the same project, seed, checks and
engine selections. `--resume` is the default. Plain `./ralphie.sh` also resumes
when the script is planted in that project; from another installation, keep
`--project /path/to/project`.

Resume restores the phase, attempt, route history and whether work was in
flight. Broken prerequisites can route back through PLAN with the reason in
`.ralphie/last_gate_feedback.md`. It does not start an unrelated objective:
if saved state says `CURRENT_PHASE=done`, it rechecks that completed mission.
Do not delete `.ralphie/state.env` to change focus or reset spending.

For a new unseeded mission where you want the questionnaire again:

```bash
./ralphie.sh --project /path/to/project --no-resume --rebootstrap
```

`--rebootstrap` alone refreshes unseeded bootstrap context without disabling
resume. Seeded missions retain their exact intent; use a new `--objective` or
`--spec` with `--no-resume` to replace it.

### Recovery and locks

State snapshots publish only after the full body and checksum have been written
successfully. A failed checkpoint preserves the prior snapshot; finite-budget
inference admission refuses dispatch if it cannot save that admission.

An existing state file that fails validation is preserved and stops resume
before inference. It is never treated as a new mission with zero spending.
Inspect the saved state before using `--no-resume`, which explicitly starts a
fresh mission and resets its counters. Owned runtime paths must be ordinary
files and directories; Ralphie refuses aliases rather than writing through them.

Lock admission uses `.ralphie/run.lock.claim`, separate from the running worker
lock. The updater uses `ABSOLUTE_SCRIPT_PATH.update.lock`, shared by all projects
using that installation. If a launcher dies while holding a claim, Ralphie
reports the path and refuses to guess that it is stale. Verify every launcher,
worker and updater using that lock has stopped, inspect its owner/PID, then
remove only the claim owner file and empty claim directory before retrying.
Leave the primary worker lock and mission state intact.

### Reference sources vs. backlog sources

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

After a PLAN phase passes, Ralphie records a fingerprint of configured non-plan
backlog sources in `.ralphie/state.env`. BUILD freshness checks compare against
that checkpoint. Changes to those sources route back through PLAN; the active
implementation plan is excluded from this fingerprint and its task content is
read separately. Incorrectly listed reference files can cause plan loops or
terminal-done deadlocks.

### Mission context template

A small current-slice steering or goals block should stay short, explicit, and
bounded. This shape works well as the content of a new `--spec` document or as reference
linked from `IMPLEMENTATION_PLAN.md`. Do not overwrite the protected goals copy
of a saved seeded mission to change its objective:

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

## Executed project checks

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

The narrow no-check exception is a reviewed handoff with no project changes
outside Ralphie's defined planning/runtime artifacts. Its original raw-tree
witness is independent of Git ignore rules and remains bound to the mission
across resume. Missing or changed proof cannot authorize that exception.

Checks run with your permissions. A check that changes HEAD, staged blobs,
file modes or nonignored project files (including initialized submodule
worktrees) fails verification, even if it exits successfully; generated
build and test artifacts should be ignored by Git. Each check has a 900-second
default deadline, configurable with `--gate-timeout-seconds` or
`RALPHIE_GATE_TIMEOUT_SECONDS`. CLI controls do not provide an operating-system
sandbox.

## Interactive Bootstrap

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

Without an explicit or saved seed, startup bootstrap is interactive when a terminal is available (`/dev/tty`). In a script stream, stdin carries the script and prompts use the controlling terminal. `--objective`, `--spec` and saved seeded missions suppress these prompts.

Enter accepts the displayed default. Yes/no prompts accept whole answers
(`y`, `yes`, `true`, `on`, `1` or `n`, `no`, `false`, `off`, `0`), ignoring case;
other answers are retried. Single-line text keeps its spaces and backslashes.
Normal terminals support native line editing, including Left/Right and
Backspace. `TERM=dumb` uses plain line input. Escape has no menu action;
use `Ctrl+D` on an empty single-line prompt to cancel setup without starting
work. In paste mode, `Ctrl+D` finishes nonempty text; Enter immediately keeps
the current value. Redirected output is plain text. Set `NO_COLOR` to disable
decorative colors in a terminal.

- `project_type`: is this a new project?
- `objective`: what should Ralphie optimize for?
- `constraints` and `success_criteria`: quick single-line defaults (press Enter to keep)
- optional `goals document URL`: single-line link input (press Enter to skip)
- optional multi-line `project goals/context` paste mode:
  - paste full document content or URL notes
  - finish with a line containing only `EOF` (or press `Ctrl+D`)
- `build_consent`: proceed from PLAN to BUILD automatically when gates pass?

Without a terminal or an explicit seed, bootstrap uses deterministic fallback values and records `interactive_prompted: false`. In that non-interactive fallback, `build_consent` defaults to `false`; Ralphie can complete planning but will not dispatch any development phase until you set consent intentionally, for example by rerunning `./ralphie.sh --rebootstrap` in a terminal or editing the unseeded bootstrap file while Ralphie is stopped. Adaptive routing cannot bypass that choice.

Valid saved bootstrap context is reused, including context created without a
terminal. The alignment dialogue stops after 12 rounds or two unchanged rounds;
an unresolved stop saves the context with BUILD consent disabled and exits
nonzero. To finish that dialogue or intentionally refresh saved context, run:
```bash
./ralphie.sh --rebootstrap
```

## Agent guide and reference sources

The [orchestration skill](skills/software-development/ralphie-orchestration/SKILL.md)
now covers agent/subagent launch, observation, feedback, recovery and sequencing,
as well as maintenance of this script. Its
[supervising guide](skills/software-development/ralphie-orchestration/references/supervising.md)
includes paste-ready instructions for another harness.

Use this local result immediately, including unpublished changes:

```bash
/bin/bash /absolute/ralphie/skills/software-development/ralphie-orchestration/scripts/update_skill.sh --apply
```

A repository checkout reports `DEVELOPMENT`, prints its runtime/guide paths and
never fetches, resets or replaces local work. For a separate installation, use
that trusted helper with `--install /absolute/agent-skills/ralphie-orchestration`
(an absent destination outside a project checkout). The default source is
`sirouk/ralphie` at `main`; a remote install requires these files to have been
published there. The local path above works before publication.

On each new use, the installed skill checks/applies a clean update, stages the
guide and executable from one fixed commit, and retains prior physical
revisions. Dirty installs refuse replacement; offline use reports that
freshness was not verified. Updates never execute a downloaded installer.
Git and HTTPS `curl` serve skill maintenance; they add no dependency to the
Ralphie loop. See the supervising guide for trusted source/ref overrides and
explicit install/update examples.

Record the printed physical runtime **and** skill paths for each mission.
Reconnect and steer with that original pair; do not update beneath its worker.
Launch retained runtimes with `RALPHIE_SKIP_AUTO_UPDATE=1` so Ralphie's separate
startup updater cannot replace the pinned file, even when operator settings
opt into runtime updates. New skill updates apply to new launches.

Paste this into the supervising agent, replacing the concrete inputs:

```text
Use the Ralphie orchestration skill at PHYSICAL_SKILL_PATH. Launch or reconnect
PROJECT_ROOT using EXACT_SEED_OR_SPEC, REAL_CHECKS, ENGINE_OPTIONS and approved
budgets. For an existing mission retain its original physical runtime/guide;
for a new one apply the skill update and reread the printed guide first.
Set RALPHIE_SKIP_AUTO_UPDATE=1. Own the process, output and final exit receipt;
observe actual checks and saved state. Steer through --request/--request-file,
reconcile --requests-json, and never equate presentation with completion.
Resume the same mission; stop/clean up before archiving or replacing its seed.
Report verified done, planning-only/pause, or the specific resumable blocker.
```

- `engines/setup-agent-subrepos.sh` is retained for comparative engine behavior research only.
- It is **not** required for a standard `ralphie.sh` run on a user project.

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
published [`main` source](https://raw.githubusercontent.com/sirouk/ralphie/main/ralphie.sh). It never
derives an update from the managed project's Git remote, and project
`config.env` cannot select the downloaded script. Forks and private mirrors need
their own explicit raw source URL. The nondefault `master` branch is frozen at
the old simplified harness (`4.3.1`) so existing raw install/update links keep
working. It does not follow `main` or migrate old installations to this
continuation; their update contracts are incompatible.

Only `ralphie.sh` is downloaded. Ralphie validates the candidate without
executing it, syntax-checks it, writes a unique backup under
`.ralphie/self-update/`, atomically replaces the installed script, and re-execs
once with an update loop guard. Replacement staging and the transaction lock
live beside the installed script, so different projects share the same lock and
replacement stays on one filesystem. Re-execution preserves the original
argument base directory and Bash interpreter, including `bash ralphie.sh` on
a non-executable file.

Safety defaults:

- local uncommitted edits to `ralphie.sh` block self-update unless `AUTO_UPDATE_ALLOW_DIRTY=true`;
- `https://`, `file://`, and local paths are accepted; plaintext `http://` requires `AUTO_UPDATE_ALLOW_INSECURE=true`;
- concurrent starts share a short self-update lock so only one process can replace `ralphie.sh` at a time;
- a symlink launcher is left intact; launch the actual regular script to update it;
- fetches have a finite wall-clock deadline and a 2 MB ceiling. HTTPS redirects
  cannot silently downgrade to HTTP; the wget-only fallback refuses redirects;
- failed fetch, failed validation, or failed replacement leaves the current script in place;
- `curl | bash` validates the complete stream before installation, refuses
  symlink/directory destinations, and re-execs with auto-update skipped for that
  first persisted run.

## Engine Authority

Engines execute with the invoking user's permissions. Claude's `IS_SANDBOX=1`
environment and approval flags do not create an operating-system sandbox.
Prime's direct CLI execution is also not a sandbox. Use the host project's
normal isolation and access controls when work requires them.

Ralphie retains phase orchestration, retries, scoring, state, and verification.
Reviewer personas provide judgment; their prose does not substitute for an
executed project check. Consensus and handoff use private validated answer and
status receipts, so a later role rewriting an earlier public artifact cannot
change its vote. Unsupported raw control bytes make a review invalid. Prime calls use independent prompts rather than a
shared continuation session or a second nested lifecycle loop.

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
lack a settled token or cost estimate. A finite cost cap requires a positive
`--session-token-rate-cents-per-million` value. Each request estimate is rounded
up to whole cents; small requests can each consume one estimated cent.
Accounting overflow refuses further inference.

### CLI Flags

- `--project DIR`
- `--objective TEXT`
- `--spec FILE`
- `--plan-only`
- `--request TEXT` (durable feedback for an initialized active mission)
- `--request-file FILE` (exact multiline feedback)
- `--requests` (human-readable retained requests)
- `--requests-json` (machine-readable retained requests)
- `--archive-request ID|all` (only while the worker is stopped)
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
- Exported environment values override project config, including across compatibility aliases; CLI values win over both.
- Use the startup config banner as the source of truth for effective values.
- Only supported public settings and their compatibility aliases are loaded from
  `config.env`; unknown and internal process keys are ignored with a diagnostic.
- Scalar values preserve literal backslashes and quotes, including through CLI
  overrides; multiline engine names and scalar settings are refused. Unsupported
  reasoning values are rejected before inference instead of selecting a default.
- Operator booleans accept true/false, yes/no, on/off, y/n and 1/0. Malformed values stop startup before updates or inference; they no longer select a default.

Phase no-op profile precedence: explicit per-phase policy flags win over profile-derived policy values.
`--strict-validation-noop true` is a compatibility hardening switch for test and lint no-op handling after profile and explicit policy resolution; it does not make the plan phase require worktree mutation.

Supported no-op profiles:
- `balanced` (default): plan=`none`, build=`hard`, test=`soft`, refactor=`hard`, lint=`soft`, document=`soft`.
- `strict`: all phases (`plan`, `build`, `test`, `refactor`, `lint`, `document`) `hard`.
- `read-only-first`: plan=`none`, build=`hard`, test=`soft`, refactor=`none`, lint=`soft`, document=`none`.
- `custom`: starts from balanced defaults; explicit per-phase policies override them.

Behavior summary:
- Zero disables session/iteration limits or leaves phase completion/routing retries unlimited with stagnation guards. Worker and engine-health attempt counts require at least one attempt.
- Integer settings accept decimal digits, normalize leading zeroes and reject malformed or overflowing values before updates or inference. Confidence and consensus scores stay within 0–100.
- Resume remains enabled by default (`--resume`). Replace a seeded mission with `--no-resume --objective ...` or `--no-resume --spec ...`; use `--rebootstrap` for the unseeded interactive questionnaire.
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
their own consensus timeout. Free CLI capability probes run only when needed,
with a separate three-second and 64-KiB limit per command; `--help` does not
probe installed engines. An enabled Codex output schema must name a readable
regular file or the call is refused. Permanent provider, model or authentication
failures stop paid retries without replacing an explicitly selected engine.
A local output-recording failure also stops inference without provider retries
or fallback; an admitted call continues to count toward the session budget even
if its answer cannot be recorded. Notification cadence settings use bounded
decimal integers; malformed or overflowing values stop startup before runtime
setup.

Successful lifecycle completion exits `0`. Successful `--plan-only` also exits
`0`, reports planning completion and saves BUILD as the next phase. An intentional
interactive pause exits `0` with resumable unfinished state. Failures and
incomplete limit stops exit nonzero; a cycle or budget limit is not completion.

## Deterministic Stack Discovery

Before each planning run, `ralphie.sh` writes `research/STACK_SNAPSHOT.md` with:

- ranked stack candidates,
- deterministic evidence signals,
- and a ranked alternatives list.

Build transitions require the snapshot and clean artifact checks to pass.

## Phase-Gated Auto Commit (No Push)

- When enabled, Ralphie creates a local commit after a phase passes handoff + consensus gates.
- Commit subjects are concise, lowercase, one-line summaries grouped by changed file areas.
- Ralphie never runs `git push`.
- At startup, Ralphie checks whether a valid git commit identity is available (`git var GIT_COMMITTER_IDENT`) and records that status in resumable state.
- If identity is missing while auto-commit is enabled, startup fails before
  engine work. Configure `git user.name`/`user.email` or equivalent identity
  environment and resume; use `--auto-commit-on-phase-pass false` only when you
  intentionally want to manage saves yourself.
- Commits are scoped to approved phase paths. If the operator index already
  contains staged changes, Ralphie refuses the automatic save until those
  changes are saved separately.
- Automatic saves use a private index and disable Git hooks. Put required
  validation in `--accept` or `.ralphie/gates`; it runs independently before
  phase promotion. Unrelated operator index entries remain intact, including
  when a save fails. Repository-selection variables such as `GIT_DIR` and
  `GIT_INDEX_FILE` are cleared for executable launches so `--project` remains
  authoritative; ordinary identity, signing and transport settings still apply.
- Older content-only ownership records cannot certify dirty paths under the
  stronger mode/type checks. Such paths stay protected as operator work; review
  and save them explicitly before resuming automatic saves.
- Automatic saves refuse pending merge, cherry-pick, revert, rebase or sequencer
  operations, including in linked worktrees. Finish or abort the operation
  outside Ralphie before resuming; Ralphie leaves its metadata intact.
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
- Existing bot tokens, webhook URLs and Chutes API keys display only
  `[configured]`. New secret input is hidden; Enter keeps the value and `-`
  clears it.
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
- `tests/durability/run-*-contract-suite.sh` for configuration/resource limits,
  persistence and Git ownership, phase/completion evidence, updates and outputs
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
