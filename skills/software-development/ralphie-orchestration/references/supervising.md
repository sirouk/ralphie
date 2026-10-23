# Supervising a Ralphie mission

## Install or use a local checkout

For this checkout, including unpublished changes, no installation is needed:

```bash
/bin/bash /absolute/ralphie/skills/software-development/ralphie-orchestration/scripts/update_skill.sh --apply
```

`DEVELOPMENT` prints this checkout's runtime and guide paths, current commit
and whether relevant files differ. It performs no fetch or reset. Retain those
paths; keep the checkout unchanged while its mission runs. A dirty checkout is
useful for development, but its commit alone does not identify all local bytes.

For a separate managed skill installation, create the agent's intended skill
parent if necessary, then explicitly install to an **absent** destination:

```bash
/bin/bash /trusted/ralphie/skills/software-development/ralphie-orchestration/scripts/update_skill.sh \
  --install /absolute/agent-skills/ralphie-orchestration
```

The default is `sirouk/ralphie` at `main`. A trusted fork or a pinned full
40-character commit is selected **only at install time** with
`--source owner/repository --ref REF`. A fixed commit intentionally stays fixed.
Before these helper files are published on that ref, use the local checkout
path above; a remote install correctly refuses an incomplete payload.

The install creates a skill symlink and a sibling
`.ralphie-orchestration.revisions/COMMIT` store with the runtime, skill, UI
metadata, references and updater. Nothing existing is adopted or overwritten.
Install outside a project Git checkout. Future uses run the installed helper
with `--apply`; `--check` reports availability without changing the selected
revision. Both verify local bytes, including source/ref metadata, before a
network check. Modified installs refuse updates; retain the edits and reconcile
them outside this helper. There is no force mode or automatic pruning.

Updates fetch a finite list of files over HTTPS from one resolved commit,
validate shell syntax and skill identity, then atomically replace the managed
link after staging succeeds. A private symlink probe selects native `mv -h` or
`mv -T`; maintenance refuses if neither preserves that replacement contract. Prior physical revisions remain available. Downloaded code is
not executed during installation. This does not authenticate arbitrary forks
or make upstream code safe: select only a trusted repository/ref. Git is needed
for byte checks; `curl` is needed for online maintenance. A missing/network-
unavailable `curl` retains a verified installed revision with an `OFFLINE`
diagnostic. Initial installation requires a successful download.

A busy/abandoned update claim refuses maintenance. Do not delete it while
another helper runs; inspect its owner/process and reconcile a genuinely
abandoned claim while all updaters are stopped. Ralphie's worker is independent.
The helper never updates global installations unless explicitly invoked with
their destination. Managed root paths containing CR/LF are refused.

## Record a launch before starting it

Use the existing task owner/harness to retain:

- Physical runtime and skill paths and the revision/check-out status.
- Exact project root, objective or spec bytes, check commands and all selected
  engine/model/provider, consent and budget options.
- The foreground tool session or supervised process identity, console location
  and eventual exit result.

Keep those records outside the managed project's worker-editable files. Do not
create a new project owner or a competing continuity system. Do not copy keys,
tokens or entire environment/configuration files into receipts.

An agent or authorized subagent may own the run. Give it a concrete mission and
checks, allow it to remain responsible until exit, and require the final
observed result. The supervising agent keeps authority over scope and recovery.

## First launch and planning approval

The target must already exist and be a Git root if inside Git. A new ordinary
empty directory is supported. Invoke the **physical** runtime, not the managed
symlink, with the startup updater disabled:

```bash
RALPHIE_SKIP_AUTO_UPDATE=1 /bin/bash /physical/revision/ralphie.sh \
  --project '/absolute/project with spaces' --engine prime-agent \
  --spec /absolute/mission.md --accept './test.sh' \
  --max-session-cycles 24 --plan-only
```

`--objective TEXT` is the single-string alternative; `--spec FILE` copies exact
seed bytes. Relative spec/request-file paths resolve from the invocation
directory. Explicit seeds authorize the local lifecycle without questionnaires,
except that `--plan-only` stops after approved planning with BUILD saved next.
Planning-only exit 0 is not project completion. To approve BUILD later, resume
with the same seed/checks/options and omit `--plan-only`. Do not add
`--no-resume` for this continuation.

Choose the actual available engine. Prime overrides are `--prime-provider`,
`--prime-model` and `--prime-thinking`; do not assume this skill can change the
supervising agent's model. Budgets apply to worker, review, retries and paid
health checks. Admission counts are retained on resume. Token/cost totals are
estimates, not provider billing receipts. Use the operator-authorized limits;
do not silently raise them after exhaustion.

Use explicit project checks (`--accept` is repeatable) or reviewed
`.ralphie/gates`. Selected commands are bound to the mission and protected.
Review votes cannot overrule failing or absent checks. The narrow no-check
reviewed planning/handoff exception proves only no project changes outside
Ralphie's defined planning/runtime artifacts; it is not a substitute for
verification of implementation work.

Prefer a foreground tool session whose final status you can collect. If the
harness deliberately backgrounds the job, it must own the exact process and
capture stdout/stderr and final exit status. Do not assume a PID, `nohup`,
terminal detachment or this skill guarantees survival across host logout.
Never launch a duplicate worker to find out whether the first one is alive.

## Observe without spending or changing work

Inspect bounded output from the owned process/session and project artifacts:

```bash
sed -n '1,100p' /absolute/project/.ralphie/state.env
sed -n '1,100p' /absolute/project/.ralphie/reasons.log
sed -n '1,160p' /absolute/project/.ralphie/last_gate_feedback.md
```

State is checksummed data, not shell code: never `source` or `eval` it. Read
phase/attempt, in-progress status, counts and reasons together. Shell-check
receipts are append-only at `.ralphie/verification.jsonl`; phase output is in
`completion_log/`, logs in `logs/` and diagnostic reviews in `consensus/`.
A quiet buffered engine can still be healthy. Respect the configured deadline;
do not start a second inference because a console is quiet.

These are observations, not authorization to alter files. There is no current
`status`, `watch`, `chat` or worker-launch subcommand. Use the options-only CLI.
An older live worker without request support refuses publication; stop it,
wait for cleanup, then resume with an updated runtime deliberately.

## Steer and reconcile feedback

Use the pinned runtime and project, with no engine call:

```bash
RALPHIE_SKIP_AUTO_UPDATE=1 /bin/bash /physical/revision/ralphie.sh \
  --project /absolute/project --request-file /absolute/feedback.md
RALPHIE_SKIP_AUTO_UPDATE=1 /bin/bash /physical/revision/ralphie.sh \
  --project /absolute/project --requests-json
```

Requests need an initialized, unfinished mission. Bodies are exact valid UTF-8,
1–4096 bytes, at most 32 active requests. A successful acknowledgement names
the durable request. At the next safe boundary, Ralphie finishes/accounted
in-flight inference or checks, invalidates stale approval and returns to PLAN.
All active bodies remain in worker, handoff and consensus prompts. No request
changes the saved seed, selected checks, engine requirements, consent or limits.

`queued` means stored. `presented` means included in an admitted worker prompt;
`review_presented` records review delivery separately. Neither means completed.
A known busy refusal publishes nothing: retry after a bounded delay. For an
interrupted command or unknown/lost acknowledgement, list JSON and match the
stored request before retrying; blind resubmission can create duplicate intent.
Other refusal reasons need correction, not an endless retry loop.

Never write `.ralphie/requests` files or gate feedback directly. Archive only
after the worker has stopped and cleanup finished:

```bash
RALPHIE_SKIP_AUTO_UPDATE=1 /bin/bash /physical/revision/ralphie.sh \
  --project /absolute/project --archive-request REQUEST_ID
```

`--archive-request all` retains history and removes all bodies from active
prompts; it does not undo implementation. Do not archive merely because a
request was presented. Verify its requested behavior and review the result.

## Recover or sequence another mission

For an interrupted/failed mission, first collect its nonzero exit, reason and
remaining process identity. Use the same physical runtime and exact seed/checks
to resume; resume is the default. Stop via the harness's owned process/session,
then wait for its cleanup. Seeded/nonterminal interrupts save and stop; an
unseeded terminal may offer a menu, except during short publication checkpoints.
Do not kill by a guessed/stale PID, remove a live lock or edit saved counters.
Invalid state, permanent provider/configuration errors and output-recording
failures need diagnosis before another paid attempt.

A different seed or check set requires a new mission: stop the worker, archive
active requests, preserve the previous work and then use `--no-resume` with the
new explicit objective/spec and reviewed checks. Never repurpose a saved done
mission by changing only its implementation plan. Dependent missions run
sequentially after verified completion; independent projects may run in parallel
only under the task's authorization, each with its own root/process/budget.

Full lifecycle success requires observed exit 0, saved `CURRENT_PHASE=done`,
applicable shell checks passing on the accepted tree and required local saves.
Planning-only success and an intentional interactive pause can also exit 0;
inspect the saved phase and console before claiming completion. Do not call
queued/presented feedback done without behavior/check evidence. Final reports
name the actual result, changed project files, verification, saved work and
any remaining limitation. Never substitute engine self-report for shell truth.

## Paste-ready handoff to another supervising agent

Replace the capitalized fields with authorized concrete values:

```text
Use the Ralphie orchestration skill at PHYSICAL_SKILL_PATH. For a NEW mission,
run its update_skill.sh --apply, reread the printed physical guide, and retain
that guide/runtime pair. For an EXISTING mission, use its recorded original
physical pair instead; do not update beneath its worker.
Own PROJECT_ROOT using EXACT_SEED_OR_SPEC, REAL_CHECK_COMMANDS, ENGINE_OPTIONS
and AUTHORIZED_BUDGETS. Launch the pinned runtime with
RALPHIE_SKIP_AUTO_UPDATE=1 and an explicit --objective or --spec; use
--plan-only only if planning approval is required. Keep the process/session,
console and final exit receipt. Do not start a duplicate worker or read a
terminal for a seeded mission.
Observe state/reasons/check receipts without sourcing project files. Submit
new feedback with --request/--request-file and inspect --requests-json.
Queued/presented is delivery, not completion. Retry a known busy refusal after
a bounded delay; reconcile unknown outcomes before resubmission. Leave consent,
engine, checks and spending limits intact. Stop and collect cleanup before
archiving or starting a different seed. Resume the same exact mission on its
original physical runtime; do not erase state or raise budgets silently.
Finish only after the observed lifecycle/check/save result, or report the
specific blocker and preserved resumable state. Report planning-only/pause
separately from project done. Do not push, deploy or use real inference beyond
the authority supplied with this task.
```
