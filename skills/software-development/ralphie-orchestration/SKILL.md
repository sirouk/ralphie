---
name: ralphie-orchestration
description: "Use Ralphie to autonomously plan, build, test, refactor, lint and document a project. Launch or reconnect to a mission, observe evidence, queue feedback, supervise recovery, sequence dependent work, or maintain the single-file orchestrator."
---

# Ralphie Orchestration

Ralphie supplies durable lifecycle coordination around Prime Agent, Codex or
Claude. The product is `ralphie.sh`; this skill explains how a supervising agent
uses it without becoming a competing execution loop.

## On every use: choose the correct revision

**Reconnect to an existing mission first.** Recover its original physical
runtime path, physical skill path, exact seed/checks/options and process owner
from the supervising harness's existing records. Read that retained skill and
use that runtime for observation, requests and resume. Do not apply an update
underneath a running mission. If these records are missing, inspect the existing
launcher and project evidence; do not guess a runtime or start another worker.

**Before a new launch**, run the helper beside this loaded skill:

```bash
/bin/bash /absolute/path/to/ralphie-orchestration/scripts/update_skill.sh --apply
```

Read its output as data; never `eval` or `source` it.

- `DEVELOPMENT`: this is a repository checkout. It remains unchanged, including
  dirty or unpublished work; use the printed runtime and guide paths. No
  network request is made. This is the supported path before publication.
- `UPDATED`, `UP_TO_DATE` or `SUPERSEDED`: read the printed physical `SKILL_PATH`
  before continuing and retain it together with `RUNTIME_PATH` and `REVISION`.
  An old physical helper reports the current revision instead of updating it.
- `OFFLINE`: the installed revision passed its byte checks, but remote freshness
  was not verified. Report that limit once; use the retained revision if the
  task does not require the newest release.
- Any error: preserve the existing installation and diagnose it. Do not bypass
  dirty checks, change sources or reset a developer checkout.

Managed installation instructions are in
[supervising.md](references/supervising.md#install-or-use-a-local-checkout).
Updates use the recorded GitHub repository/ref, resolving a branch or tag to a
full commit and staging the guide, helper and runtime from that same commit.
No downloaded installer is executed. This is trust in the selected upstream,
not a code review or an operating-system sandbox. Git and optional HTTPS `curl`
are used by maintenance; no new tool is required by Ralphie's loop.

## Launch and supervise

Read [the operating guide](references/supervising.md) for the launch receipt,
request/recovery procedure and paste-ready instructions for another agent.

For a fresh authorized mission, choose an existing project root, exact objective
or spec, real shell checks, engine/model and finite spending limits. Seeded
runs never read a terminal. Example using the physical runtime printed above:

```bash
RALPHIE_SKIP_AUTO_UPDATE=1 /bin/bash /physical/revision/ralphie.sh \
  --project /absolute/project --engine prime-agent \
  --objective 'Fix the failing tests and document the result' \
  --accept './test.sh' --max-session-cycles 24
```

Always set `RALPHIE_SKIP_AUTO_UPDATE=1` for a retained runtime. Ralphie's own
opt-in startup updater is separate from this skill updater; the skip prevents
operator update settings from replacing the pinned executable. Do not source
project configuration or state into your supervising shell.

Keep one worker per project. Own the process, console and final exit receipt in
the harness already supervising the task; launching a background shell alone
is not proof it will survive host logout. Never report success from a banner,
process, reviewer GO or request presentation alone.

Use the same physical runtime to steer an initialized, unfinished mission:

```bash
RALPHIE_SKIP_AUTO_UPDATE=1 /bin/bash /physical/revision/ralphie.sh \
  --project /absolute/project --request 'Preserve the public API; cover empty input'
RALPHIE_SKIP_AUTO_UPDATE=1 /bin/bash /physical/revision/ralphie.sh \
  --project /absolute/project --requests-json
```

Feedback is stored immediately when acknowledged and consumed at a safe
boundary after an in-flight call/check finishes. Changed feedback returns work
to PLAN. Active requests remain in worker and review prompts until archived
while stopped. `presented` means an admitted worker prompt contained it; it
never means implemented or verified. A known busy refusal stored nothing and
may be retried after a bounded delay. Reconcile an unknown/lost command outcome
with `--requests-json` before resubmitting, to avoid duplicates.

Consent, selected engines, protected checks and spending limits remain
binding. Do not rewrite live seed/gate/state/request files or use historical
`chat`, `/apply`, `start`, `watch` or `status` commands: those belong to the
archived simplified harness, not this May continuation.

## When changing Ralphie itself

Read [development.md](references/development.md). Preserve Bash 3.2 portability,
one-file execution, independent shell checks, exact ownership, resumable state,
explicit engine choices and the existing test/receipt boundaries. Use free
mocks for regression tests; live inference requires the task's authorization.
