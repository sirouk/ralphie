# Ralphie

**An autonomy kernel for any project, on any machine, with any AI engine.**

One file. No dependencies beyond `bash`, coreutils and `git`. Plant it in a
project, tell it what you want, and walk away.

```bash
curl -fsSL https://raw.githubusercontent.com/sirouk/ralphie/master/ralphie.sh | bash -s -- "make the tests pass"
```

Or keep one installed copy and select an existing directory:

```bash
/path/to/ralphie.sh --project "/path/to/my project" discover
/path/to/ralphie.sh --project "/path/to/my project" --once "make the tests pass"
```

`--project` overrides `RALPHIE_PROJECT`; otherwise the script's directory is
the project. Relative project paths resolve from your invocation directory and
are made absolute before any work. A missing directory is refused. An empty
directory is a valid starting point. No other repository file is needed to run
Ralphie; the engine and the project's own build/test tools must be installed.

---

## Supervisor chat

```bash
./ralphie.sh                        # open default conversation; do not start work
./ralphie.sh chat                   # the same interactive client
./ralphie.sh chat "What should we prepare before starting?"  # one turn, then exit
./ralphie.sh run                    # explicitly resume the autonomous loop
/path/to/ralphie.sh --project "/path/to/my project" --engine prime-agent chat
./ralphie.sh --spec "docs/product spec.md" --once chat
```

Inside interactive chat:

```text
/help                         # grouped command guide; no model call
/start Fix the failing tests  # review the proposal and its settings
/apply p-ID                   # replace p-ID with the displayed proposal ID
/new tests                    # create a named conversation; no worker starts
/jobs                         # find the retained launch ID
/select LAUNCH-ID              # remember this job in the conversation
/follow                       # follow selected job; q detaches, x proposes stop
/stop LAUNCH-ID                # propose a safe-boundary stop, then /apply its ID
```

**Only zero arguments default to chat.** Bare invocation and `chat` require
terminal stdin and stdout. Otherwise they fail promptly without consuming piped
input or starting a worker. Cron and unattended jobs that used no arguments must
add `run`. Options-only invocations still run: `--once`, `--project DIR` alone,
and objective-bearing invocations retain their run behavior. Use
`--project DIR chat` to chat. `chat "MESSAGE"` accepts one nonempty turn and exits;
it works with redirected input/output and never reads a terminal. Use `run chat`
for the objective text `chat`. Put global options **before** `chat`.

Chat is a concise `You:` / `Ralphie:` conversation about the project's goal,
preparation, progress and steering. It retains bounded conversation history, with
chat cleanup and accounting separate from the worker. One project-wide chat lock
and one independent worker lock apply across all conversations. It reads
project and worker facts without initializing or repairing the worker ledger.
Opening chat does not start project work.

### Resume discussion, select work

A conversation is discussion context, not a worker or saved execution setup:

```text
/new tests          # create and select tests
/sessions           # list conversations
/switch default     # return to the original history
/resume tests       # restore tests history and its advisory job selection
/jobs
/select LAUNCH-ID   # choose any retained job explicitly
/follow             # inspect it; q returns to chat
```

Startup selects `default`. To reopen another existing conversation directly:

```bash
./ralphie.sh --engine prime-agent chat --session tests
./ralphie.sh chat --session tests "What remains?"  # one turn, never reads input
./ralphie.sh chat -- "--session"                  # literal one-turn message
```

Only `--session` immediately after `chat` is a conversation option; use `--`
after `chat` to send option-looking prose literally. Global options still go
before `chat`. The reconnect command does not restore saved run settings.

Names use 1–32 ASCII letters, digits, `_` or `-`, starting with a letter or digit. `default` keeps the existing `.ralphie/chat/`
history; named conversations live under `.ralphie/conversations/NAME/`. At
**32 retained conversations including default**, creation is refused. History
is not automatically pruned to make room. `/resume` and `/switch` require an
existing name; neither creates work, resumes an engine, restores a workspace,
or changes the project ledger.

Selection is a navigation preference, **not conversation ownership of a job**.
Any conversation can select any retained job. The selected job and current
project worker may differ. A missing or historical selection never silently
becomes the current worker for control. With no selection, observation and
`/stop` can use the current worker; stop still displays its exact target and
requires `/apply ID`. Steering requests are project-wide next-cycle requests,
not private conversation queues; a conflicting historical selection is refused.

To do new work, use `/start GOAL` and approve its fresh proposal. New starts use
**this invocation's settings**, not historical engine options, budgets or a
saved configuration. To use a spec, reopen with `--spec FILE chat`. The stopped
historical job stays retained; restoring its conversation does not restart it.

### Terminal view and input

On recognized xterm, screen, tmux and rxvt terminals, interactive chat uses a
compact alternate-screen view with a sanitized latest-turn preview of at most
120 characters. This is only a display preview; it does not shorten submitted
input. Other terminals use ordinary output. No new runtime dependency or tmux
installation is required.

Full authority belongs in normal terminal scrollback, not a clipped preview.
The first proposal leaves the compact view for the rest of that chat session and
prints its full action, payload and settings. `/proposal` displays the same pending
proposal again; it does not create a fresh ID or refresh its authorization.
`/history` also leaves the compact view. `/help` shows a grouped command guide
outside the compact view, then returns. Scrollback retention still depends on
your terminal's settings.

Readline keeps normal arrow-key editing and Unicode input. **Empty-left job
navigation is not supported on Bash 3.2**; use `/jobs`, then `/attach LAUNCH-ID`.
For multiline input, enter `/paste`, type the lines, then `/send` on its own line.
Use `/cancel` on its own line to discard that input. The 4096-byte message limit
still applies. A waiting indicator shows while supervisor inference runs; it is
not a model token stream or proof of remote progress.

### Discuss, propose, apply

**Discussion is not authorization.** Ordinary messages may produce a proposal,
but only your explicit `/apply ID` authorizes the displayed action. Saying “yes”
or receiving a model-generated command does not authorize anything. Model output
is parsed as data, never evaluated as shell code.

Control commands below are local and make no model call. The `/paste` composer
is also local, but `/send` submits its message for normal processing and may call
the supervisor model:

| Command | Effect |
|---|---|
| `/start GOAL` or `/run GOAL` | Propose a background run. |
| `/start` | Propose running the selected `--spec`; otherwise ask for a goal. |
| `/request TEXT` | Propose a next-cycle steering request. |
| `/stop [LAUNCH-ID]` | Propose a safe-boundary stop of the explicit or selected job; with no selection, use the current worker. |
| `/kill LAUNCH-ID` or `/nuke LAUNCH-ID` | Propose force termination; requires `/apply ID`. |
| `/proposal` | Redisplay the current proposal without changing its authorization. |
| `/apply ID` | Approve the current displayed proposal. |
| `/cancel` | Discard the proposal, not a running inference call or worker. |
| `/status` | Read project, worker and request facts. |
| `/sessions` or `/resume` | List retained conversations. |
| `/new NAME` | Create and select a conversation; no worker starts. |
| `/resume NAME` or `/switch NAME` | Select an existing conversation; no engine resumes. |
| `/jobs` | List retained launches and their observed states; not all are running. |
| `/select LAUNCH-ID` | Remember a job selection in this conversation; no execution change. |
| `/follow [LAUNCH-ID]`, `/attach [LAUNCH-ID]` or `/watch --follow [LAUNCH-ID]` | Follow bounded snapshots in interactive chat; an explicit ID also selects it. |
| `/watch [LAUNCH-ID]` | Print a bounded worker/receipt/log snapshot, then return; defaults to selection, otherwise the current worker. |
| `/history` | Show retained conversation in normal scrollback. |
| `/paste` | Begin multiline input; `/send` submits and `/cancel` discards. |
| `/help` | Show the grouped command guide. |
| `/quit` or `/exit` | Leave chat without stopping the worker. |

For example, discuss the goal, enter `/start Fix the failing tests`, review the
launch settings, then enter `/apply` followed by the displayed proposal ID.
Use `/jobs` to find the launch ID, then `/attach LAUNCH-ID` to follow it or
`/watch LAUNCH-ID` for one snapshot. Detaching returns to chat and does not stop
the worker. To steer, enter
`/request Add a regression test for empty input`, then approve its new ID.

Proposals bind to the displayed action, conversation, selected job, settings and
worker generation. Changes invalidate approval; switching conversations or
interactive reconnect discards pending authority. Start preserves the current
invocation's original project and run options, including
engine/model, gates, acceptance, budgets and permissions.

With `--spec FILE chat`, the **full selected spec is the execution objective**,
not the proposal title or a shorter `/start GOAL`. The proposal shows its path,
digest and a bounded excerpt: read the full file before approval. A changed spec
invalidates the proposal. On approved launch, validated spec bytes are copied
exactly, including trailing newlines, into that launch's retained spec. Merely
opening chat does not install it as the worker objective.

A request is queued for a cycle boundary, not injected into an active engine
call. Chat does not rewrite live objectives, gates or state. Queued means stored;
presented means included in a durable engine prompt, **not implemented or
completed**. Gate outcomes remain separate evidence. Stop targets the displayed
worker and requests a safe preparation/cycle boundary; “stop requested” does not
mean “stopped”. The worker keeps its six phases and never waits for chat.

### Stop safely, or explicitly force termination

Prefer `/stop LAUNCH-ID`, review the proposal, then `/apply ID`. This asks for a
safe boundary; it does not interrupt an active engine call immediately. In follow
mode, press `x` or type `/stop` then Enter to return to chat with a stop proposal
for that fixed displayed job. Neither action stops or signals the worker. Review
the full proposal in normal scrollback and approve its ID. A finished, missing or
changed target is refused, never replaced with another worker. Outside follow,
ordinary `x` is just message text.

For an unresponsive worker, `/kill LAUNCH-ID` (alias `/nuke LAUNCH-ID`) displays
a force proposal. **Review its launch identity and warning before `/apply ID`.**
Ralphie checks the current lock/token and the recorded process identity. It
refuses workers without the new identity witness, including older launches, or
whose recorded script path no longer matches. It snapshots at most 256 processes,
sends TERM to verified identities, then after two seconds sends KILL to matching
survivors. It does not signal a whole process group.

Force can interrupt edits, gates and commits. Retained files and receipts support
recovery, but **interrupted work is not promised saved or committed**. Inspect the
working tree, ledger and gates before resuming. A stale PID alone cannot authorize
force. These identity checks are best effort: same-user metadata tampering and
the race between checking a PID and signaling it remain limitations. Escaped or
new descendants and accepted remote requests may continue; remote cancellation
and stopped billing are not guaranteed.

### Background work and retained evidence

An approved start launches the normal worker in the background. Pending is not
proof of startup: identity-bound acknowledgment establishes that it started.
Closing chat leaves it running. Reopen chat to inspect it; no tmux is required.
This is **not an OS service or full daemonization guarantee**. Standard input,
output and error are detached from the terminal, but Ralphie cannot guarantee
absence of a controlling terminal, survival of host/session-wide logout cleanup,
or survival across a reboot.

Each launch retains the **first 1 MiB** of console output in
`.ralphie/workers/LAUNCH-ID/output.log`, then drains and discards excess output.
This is not a rolling log or live tail. `/watch` is a snapshot in both interactive
and one-turn chat. `/follow` (also `/attach` or `/watch --follow`) refreshes
bounded snapshots; it cannot recover console output discarded after the cap.
Press `q`, Esc or Ctrl-C to detach without stopping work; `?` shows follow help.
Final, interrupted or unknown jobs show a snapshot and return automatically.
A final process state or exit code is not proof that the goal passed its gates.
Follow requires interactive chat with a terminal. It does not provide an engine
shell or engine input. Worker engine logs and ledger evidence are separate.

There is room for **32 retained launch entries**, including old or refused
launches. Admission refuses at capacity before making another launch spec copy;
nothing is automatically deleted. To free space, stop all launchers and workers,
verify they have exited, then manually move complete launch directories outside
`.ralphie/workers/` to an archive. Keep each spec and its receipts together.

### Supervisor inference and limits

Supervisor inference is separate from the coding engine. The built-in adapter
requires **Prime Agent exactly 0.9.5**. It passes `--no-tools` and **keeps
extensions enabled**, including provider extensions such as `ccs-max`. It uses
that version's source-reviewed internal owned-worker frontend
(`PRIME_AGENT_INTERNAL_LEGACY_OWNED_WORKER_FRONTEND=1`), not the shared daemon.
This is a version-specific integration constraint, **not a generic `--no-tools`
sandbox guarantee**. Unsupported versions and explicitly selected unsupported
providers fail without Ralphie substituting another provider. The exact explicit
model selector is forwarded unchanged. The worker engine permissions below are unchanged.

Prime filters built-in and extension-registered tools out of its tool registry
under `--no-tools`, including attempts to activate them through the extension API.
This does **not** disable extension code or hooks. Installed extensions are trusted
host code: they can write files, access the network, change the system prompt, or
select a model through their APIs. Trust them to honor your model choice and the
text-only supervisor contract. Private cwd, sessions, and usage receipts separate
supervisor calls from worker conversations; they do not sandbox extensions or
account for arbitrary work an extension starts itself. Ralphie only dispatches
proposed actions through `/apply`; it cannot impose that rule on extension host
code. `--offline` disables startup network operations, not all network access.

For a custom supervisor, select `--engine custom` and set
`RALPHIE_CHAT_ADAPTER` to a **trusted executable path**. A worker's
`RALPHIE_ENGINE_CMD` alone is not a supervisor adapter. The custom adapter reads
the supervisor envelope on stdin and receives `--model` and `--thinking` as
arguments. Ralphie executes it directly, without shell evaluation; the operator
must trust it to honor the text-only contract. Neither adapter is an OS sandbox
or a promise of no host filesystem writes or network access.

Each human message is limited to 4096 bytes. The assembled inference input is
limited to **32 KiB** and the answer to **8 KiB**. Inference defaults to **90
seconds**; `RALPHIE_CHAT_TIMEOUT` accepts 1–300 seconds. Version probing and
cleanup add time, so this is not a hard whole-command deadline. Interrupt or
timeout cleanup targets local adapter processes and their observed descendants;
it cannot guarantee cancellation of an already accepted remote request, escaped
processes, or provider billing. `/cancel` only clears a proposal.

Inference can incur charges. Across all conversations in this project, chat
retains the latest usage receipt and eight prior receipts: **nine recent
project-chat calls, not a per-conversation or lifetime total**. Measured usage stays
separate from worker accounting; missing measurements are unavailable, not zero.
Bounded context, output and time are not a strict spending cap.

Historical `graphify-out/` verification records describe only the versions they
measured. They are unchanged and do not certify this chat implementation.

---

## Start from a specification

Plant `ralphie.sh` in a blank directory or an existing project, then run:

```bash
./ralphie.sh --spec "docs/product spec.md" --once
./ralphie.sh --spec /path/to/spec.md
./ralphie.sh --once                    # resume the stored objective
```

`--spec FILE` reads a local, readable regular plain-text file, not stdin.
Relative paths resolve from the directory where you invoke Ralphie, even if
Ralphie is planted elsewhere. The project still defaults to the script's
location. Quote paths containing spaces. A positional path is ordinary
objective text; Ralphie does not guess whether it names a document.

Specifications must be nonempty and at most **1 MiB (1048576 bytes)**, including
line endings. Larger files are refused, not truncated. The objective excerpt in
the cycle prompt is limited to 4000 bytes. For larger objectives the prompt
explicitly labels the excerpt and identifies the authoritative full stored file.
The engine is instructed to read that entire file before work, maintain a
verifiable implementation plan, preserve supplied plans, and add meaningful
acceptance gates even in a blank project. NUL and control bytes other
than tab, CR and LF are refused. Plain-text Markdown and UTF-8 text are fine;
PDF, word-processor documents and other binary formats are not supported.
Use only one `--spec`, without `--objective` or positional objective text;
put additional requirements in the document instead. Place options before
positional text. Options may follow an explicit `run`; for other commands,
place global options before the command.

The content becomes `.ralphie/OBJECTIVE.md` through the normal objective
machinery and survives a later run without `--spec`; the source is not reread
on resume, even if the source changes or is deleted. Spec bytes, including
trailing newlines, are preserved exactly. The full input determines objective
identity, while ledger summaries and prompt excerpts remain bounded. Ralphie
restores edits to the stored objective during the run and does not commit that
cycle; gates remain the evidence of acceptance, not the implementation plan.
Ralphie does not shell-evaluate, modify or automatically stage the source
specification. Its content is sent to the selected engine as instructions,
so use trusted documents. Normal gate verification still decides success.

---

## The idea

Most agent harnesses are built for one AI tool, and they rot the moment that
tool changes. Ralphie is built the other way around:

> **Ralphie supplies exactly the complement of what the engine cannot do.**
>
> ```
> ralphie = required_autonomy − engine_native_capability
> ```

Every engine is described by one table row declaring its supported capabilities:
`autonomy`, `gates`, `memory`, `subagents`, `resume`, `skills`, `json`, `stream`,
and `usage`. Ralphie uses those declarations to supply the missing parts.

- Against a **fully capable engine** (Prime Agent), Ralphie collapses into a thin
  durability shell: evidence, git, budget, memory, the human channel. The engine
  self-drives against the gates.
- Against a **weak engine**, Ralphie expands and supplies the scaffolding:
  explicit decide/act/verify cycles, retries, fallback, its own memory.
- Against an **engine that does not exist yet**, Ralphie needs a new table row and an `engine_build` case branch.

Selection uses declared, source-checked capabilities, not a live benchmark.
A responsive Prime Agent is the first default choice. Other installed engines
are ranked by capability when Prime is unavailable. Explicit `--engine` and
custom-command choices always win, including when that engine fails.

---

## The loop

```
observe → decide → act → verify → record → learn     (repeat until done)
```

- **observe** — git state, gate status, open work, past attempts, lessons.
  All of it gathered by shell commands. No tokens spent.
- **decide** — pick the highest-value next move. A red gate always wins.
- **act** — the engine does the work with full tool authority.
- **verify** — Ralphie re-runs every gate itself.
- **record** — commit on green. Append evidence to the ledger, always.
- **learn** — keep one durable lesson, injected into every future prompt.

---

## Orient before running

```bash
./ralphie.sh discover
# An installed copy can target another project:
/path/to/ralphie.sh --project "/path/to/my project" discover
```

`discover` takes no arguments. It reads root manifests, known plan filenames,
Git state, configured gates and engine command presence. It works before Git or
`.ralphie` exists. It creates or repairs nothing and does not run checks, engines
(not even `--version`), hooks, updates or network requests. Use an already saved
script; the `curl | bash` installer itself writes the script.

Candidate checks are **NOT RUN** and are only shell-text hints, not validated
commands. Git inspection disables content filters and ignores submodule changes.
Engine presence does not prove authentication or health. Plans and unchecked task
counts do not prove requirement coverage. Review these facts, then start a
separate run with an explicit objective. Discovery never starts paid work.

## Gates: the definition of "working"

A gate is any shell command that exits 0 when the project is healthy.

```
$ cat .ralphie/gates
npm run typecheck
npm run lint
npm test
```

Ralphie discovers them on first run from root manifests such as `package.json`,
`pyproject.toml`, `requirements.txt`, `Cargo.toml`, `go.mod`, `Makefile`,
`deno.json`, `pom.xml`, and `mix.exs`.
Every candidate is **trial-run before it is accepted**, so a command that cannot
execute on this machine never becomes a gate. Discovery does not search child
workspace packages. Use `--gate "your check command"` or add a command to
`.ralphie/gates` for unsupported layouts. Commands run from the project root.
An existing gate file, even an empty one, is kept; use `gates --redetect` after
adding tools or manifests.

Gates are why Ralphie generalises past software. Tests, type checks, linters,
builds, migrations, smoke checks, deploy dry-runs, a simulation converging —
Ralphie does not care what the command is, only whether it exits 0.

**Gates are the only definition of success.** An engine saying "I fixed it"
changes nothing. Ralphie re-runs the gates after every cycle and believes only
those.

Ralphie protects the agreed command list and runs it independently. This detects
command removal and weakening; it does not make the underlying test files
immutable or sandbox an engine running as your OS user. The checks themselves
must meaningfully test the required behavior. Use externally controlled checks
and an isolated environment when the work requires that stronger boundary.

The gate set is remembered **across runs**, not only within one. An engine that
leaves a background process behind to delete the gates after the run ends gets
nowhere: the next run restores them and asks you about it.

If the gates are damaged during a cycle — deleted, emptied, commented out,
weakened in place, made unreadable, or replaced by a directory — Ralphie
**restores them to their original place in the file, refuses to commit that
cycle at all, and tells you**. Work measured against a broken check means
nothing, so it is not saved; it is left on disk for a human to look at. The
restored gates run on the next cycle, against the tree as the engine left it.

Gates the engine *adds* are kept and become part of the persistent baseline.
Deleting a line by hand does not revoke that baseline: Ralphie cannot tell an
operator deletion from an engine deletion. To replace the agreed checks, stop
the loop and run `./ralphie.sh gates --redetect`. This clears the old baseline,
rediscovers checks, and saves the previous file as `.ralphie/gates.previous`.
If that backup cannot be written and verified, redetection fails and leaves
the current gates and baseline intact.
Review the new file and add any custom commands before the next run.

---

## The human is never blocked

The autonomous worker has no wizard or interview. It never reads from a
terminal and cannot stall waiting for someone to type. Only the explicitly
user-authorized interactive supervisor chat may wait for terminal input; that
client is independent of the worker.

When it needs a decision, it writes a numbered question to `.ralphie/ASK.md`,
optionally fires `$RALPHIE_NOTIFY_CMD`, and **goes and does other work**.

```bash
./ralphie.sh ask                            # what is waiting on you
./ralphie.sh answer 1 "use postgres"        # the next cycle uses it immediately
```

An answer also becomes a durable lesson, so it is never asked twice.

---

## Commands

```
./ralphie.sh                        Open default interactive conversation
./ralphie.sh chat "MESSAGE"         One supervisor turn, then exit
./ralphie.sh "what you want done"   Run the loop
./ralphie.sh start --once "..."     Launch a background worker
./ralphie.sh watch [LAUNCH-ID]      Worker receipt and retained log snapshot
./ralphie.sh run --once "..."      Explicit run; options precede objective text
./ralphie.sh status                 Cycles, gates, budget, open questions
./ralphie.sh doctor                 Engines, capabilities, gates, git
./ralphie.sh gates [--redetect]     The checks that define "working"
./ralphie.sh ask                    Open questions
./ralphie.sh answer N "..."         Answer one
./ralphie.sh memory                 Durable lessons
./ralphie.sh forget                 Clear the stored objective
./ralphie.sh status --json          One line of JSON, for CI and monitoring
./ralphie.sh log [n]                Recent ledger events
./ralphie.sh stop                   Stop after the current cycle
./ralphie.sh update                 Install from the configured trusted source
```

After `run`, command-looking words such as `status` are objective text. Use
`run -- "..."` when the objective starts with a dash.

`status --json` normalizes leading zeroes and incomplete decimal notation
without rounding large counters. Malformed numeric state is reported as zero.

Useful options:

```
    --project DIR       Work in this existing directory
-o, --objective TEXT    What you want done
-b, --branch NAME       Work on this branch, creating it if needed
    --engine NAME       Force an engine
    --model ID          Model id
    --thinking LEVEL    off|minimal|low|medium|high|xhigh|max
-n, --cycles N          Stop after N cycles
-m, --minutes N         Engine/observe budget; verification and saving may
                        finish afterward (not a hard whole-run deadline)
    --once              A single cycle
    --gate "CMD"        Add a verification command (repeatable)
    --no-commit         Never commit
    --done-when-green   Stop as soon as everything passes and nothing remains
    --no-yolo           Do not grant the engine autonomous tool permission
    --update            Self-update before running
    --no-update         Skip the self-update check for this run
-v, --verbose           Show the machinery
-q, --quiet             Print less: no progress commentary
-h, --help              The full option list
    --                  Everything after this is the objective
```

---

## Engines

This section describes autonomous worker engines, not supervisor inference.

| Engine | Capabilities | What Ralphie adds |
|---|---|---|
| `prime-agent` | autonomy, gates, memory, subagents, resume, skills, json, usage | durability, evidence, git, human channel |
| `claude` | subagents, resume, skills, json | + the decide/verify cycle, gate execution, retries |
| `codex` | resume, json, stream | + the decide/verify cycle, gate execution, retries |
| custom | whatever you declare | whatever is left |

`usage` means the engine keeps real token and cost figures that Ralphie can read
back. When it does, `status` reports them. When it does not, Ralphie reports
**nothing** — it never estimates. The previous version guessed tokens as
bytes ÷ 4 and printed the result as fact; a confident wrong number is worse than
no number, because people budget against it.

One capability is about behaviour rather than features: `stream` means the
engine writes progress while it works. Only a streaming engine can be judged by
its silence, so only a streaming engine gets the idle watchdog. An engine that
buffers its answer is perfectly healthy while quiet, and is bounded by the wall
clock instead.

Any command that reads a prompt on stdin can be an engine:

```bash
RALPHIE_ENGINE_CMD="my-agent --headless" \
RALPHIE_ENGINE_CAPS="resume json" \
./ralphie.sh "do the thing"
```

For a wrapper that writes its answer to a file, set
`RALPHIE_ENGINE_ANSWER=file`. Ralphie passes the current attempt's destination as
`RALPHIE_OUTPUT` in the engine's environment. The wrapper reads the prompt on
stdin and writes the final answer to that path; stdout and stderr remain logs.
An inherited `RALPHIE_OUTPUT` cannot redirect the answer elsewhere.

Ralphie prefers Prime Agent, then falls back through available engines when an
automatically selected engine fails. An explicit selection never changes provider.
A permanent failure (bad key, no quota, unknown model) is never
retried; a transient one (rate limit, 503, reset connection) always is.

Prime supplies its native tool loop, recursive subagents, skills, context
compaction, and autonomous gate loop. Ralphie supplies the durable outer loop
and independently verifies each result. Native gates receive Ralphie's gate
timeout, capped by the remaining engine-call allowance. With no engine timeout
or run deadline, Ralphie uses Prime's ordinary tool loop and supplies continuation
itself: Prime's autonomous CLI requires a positive timeout. Only Prime's explicit
gate/limit termination messages count as a completed attempt after a nonzero exit;
configuration errors and unexplained crashes remain failures.

The adapter was checked against Prime's 0.9.5 source at
[`e311d64`](https://github.com/PrimeIntellect-ai/prime-agent/tree/e311d6495124cf0bdc629c813fc97a39a9a3054d):
[CLI](https://github.com/PrimeIntellect-ai/prime-agent/blob/e311d6495124cf0bdc629c813fc97a39a9a3054d/packages/coding-agent/src/cli/args.ts),
[autonomous controller](https://github.com/PrimeIntellect-ai/prime-agent/blob/e311d6495124cf0bdc629c813fc97a39a9a3054d/packages/coding-agent/src/core/autonomous.ts),
[headless output](https://github.com/PrimeIntellect-ai/prime-agent/blob/e311d6495124cf0bdc629c813fc97a39a9a3054d/packages/coding-agent/src/modes/print-mode.ts),
[REPL and subagents](https://github.com/PrimeIntellect-ai/prime-agent/blob/e311d6495124cf0bdc629c813fc97a39a9a3054d/packages/coding-agent/docs/rlm.md),
and [usage accounting](https://github.com/PrimeIntellect-ai/prime-agent/blob/e311d6495124cf0bdc629c813fc97a39a9a3054d/packages/coding-agent/src/core/context-tree.ts).
Usage includes message calls, compaction, branch summaries, and attributed child
work, without adding child attribution twice. Python is optional and used only
to parse these records; without it Ralphie omits usage totals.

Codex's adapter follows its public
[non-interactive contract](https://learn.chatgpt.com/docs/non-interactive-mode)
and [exec source at `9fdff73`](https://github.com/openai/codex/tree/9fdff739ea0eca7881f180858dfd71b7bd1fa483/codex-rs/exec/src).
Source review establishes integration contracts, not a benchmark ranking or a
guarantee about future releases. Keep the adapter tests and a real bounded cycle
in the upgrade process.

---

Gate and engine call limits use a built-in watchdog; no `timeout` utility is
required. At a deadline, Ralphie sends TERM, allows two seconds for cleanup,
then forces termination. Polling can add about one second. `COMMIT_TIMEOUT`
bounds git commit, hooks, and signing (default 120 seconds). Explicit zero gate
or engine limits disable those call limits.

Engine version probes use the same watchdog with a fixed 15-second allowance
and closed stdin. `discover` only checks command presence and never probes.

## Updating an installed copy

`update` uses `RALPHIE_UPDATE_URL` when set; otherwise it derives a GitHub raw
URL from the selected project's origin, branch and script filename. For an
installed copy serving unrelated projects, explicitly set the trusted source:

```bash
RALPHIE_UPDATE_URL=https://raw.githubusercontent.com/sirouk/ralphie/master/ralphie.sh \
/path/to/ralphie.sh --project "/path/to/my project" update
```

Ralphie checks structure, Bash syntax and literal `VERSION="major.minor.patch"`
metadata without executing the candidate. Older versions are refused;
identical bytes are a no-op, and changed bytes at the same version are allowed.
These checks do not authenticate the publisher. Downloads through curl or wget
have a 60-second deadline plus watchdog cleanup grace.

The replacement is staged beside the installed script, preserving its mode and
entry-point symlinks. An exact previous copy is verified at the selected
project's `.ralphie/ralphie.previous` before the installed target is replaced
by rename. Both the installed target and its parent must be writable. Backup or
publication failure leaves the installed script unchanged. An update from the
previous copy itself is refused when it would overwrite that recovery path.
New invocations use the replacement; `--update` does not reload the current
process's already loaded version.

Interrupted updates may leave private `.ralphie-update.*` or
`.ralphie.previous.*` staging directories. Atomic replacement prevents partial
executable bytes becoming visible; it does not guarantee persistence through
power loss or coordinate simultaneous updates from different projects.

## Safety

**When gates exist, nothing is committed unless they pass.** When a project has
no gate at all, Ralphie may commit unverified work. It says so, does not call the
result green, does not count it as a passing cycle, and writes `NOT VERIFIED`
into the commit message. The safety
model is enforced by re-running the gates, never by trusting a report.

Around it:

- **Work on a branch.** `--branch ralphie/fix-login` creates it, works there, and
  leaves your protected branch alone. Review it as a normal pull request.
- **Undo a run without discarding uncommitted work.** When a starting commit
  exists, Ralphie prints it at the top of the run and in `status`:
  `git reset --keep <sha>`. If it refuses, commit or stash your work first.
  A new repository has no starting commit to reset to.
- **Work you had already started is never swept into an autonomous commit.**
  Paths that were modified before Ralphie started are excluded for the whole
  run, and the list of them is checksummed so that nothing can quietly empty it.
  Work Ralphie itself left behind on a red cycle is remembered as its own — by
  content, not by name — so it still gets committed once it goes green, and the
  moment you change those bytes yourself the claim is dropped.
  Initial exclusions are captured when the run starts; ownership of unfinished
  work is checked again at cycle boundaries. Ralphie cannot distinguish your
  edits from engine edits *during* a cycle. Avoid concurrent edits, or use a
  separate git worktree. `--branch` alone does not isolate working files.
- **Likely secrets and bulk are held back.** `.env` in any directory, private
  keys, `.netrc`, `.npmrc`, credentials and service-account files, `kubeconfig`,
  `*.tfstate`, `.aws/`, `.ssh/`, symlinks that resolve outside the repository,
  `node_modules/`, build output, and anything over 1 MB. They are left untouched
  on disk and reported to you. This is a strong net, not a secret scanner: a
  credential in an ordinary source file will still be committed, exactly as it
  would be by a human.
- **Ralphie never pushes.** Publishing stays a human decision.
- **Existing files in a new repository stay yours.** If Ralphie initializes git
  in an existing directory, it protects the files already there instead of
  silently making an initial commit of potentially private work. New files can
  be saved automatically. To let Ralphie commit edits to existing files, review
  and commit a safe baseline first; otherwise those edits remain on disk.
- **Your repository is not modified for Ralphie's convenience.** Its own state is
  excluded through `.git/info/exclude`, which is local and untracked, so nothing
  appears in your diffs or in a review.
- **If verified work cannot be committed, you are told.** When a green cycle
  touched files you had already modified, Ralphie refuses to take your changes
  with it, says so, and explains how to save the work.
  Failed or refused saves cannot complete the objective. Ralphie's unsaved work
  is retried on resume even when the engine makes no further edit. `--no-commit`
  explicitly permits completion with verified work left on disk.
- **Ralphie notices if its own script is edited.** Improving Ralphie with
  Ralphie is a supported use, so this is never blocked — but it is never silent
  either, because the *next* run executes the new copy.
- **Every commit says who made it.** `Ralphie-Engine`, `Ralphie-Model`,
  `Ralphie-Run` and `Ralphie-Version` trailers mean `git log` alone can separate
  agent commits from yours, months later.
- **Everything is on the record.** `events.jsonl` is append-only: a line once
  written is never rewritten. `.ralphie/log/` keeps engine output (marked tails after consumption, at most 256 KiB each) for
  the last `RALPHIE_KEEP_CYCLES` (50) cycles.
  When the ledger passes `RALPHIE_LEDGER_MAX` (16 MB) it is *rotated*, not
  truncated: the file becomes `events.jsonl.1`, older generations shift down,
  and `RALPHIE_LEDGER_GENERATIONS` (5) of them are kept — about 80 MB of
  history. Beyond that the oldest generation is dropped, which is the only way
  Ralphie ever forgets anything. Raise either number if you need more.
- **A flaky gate is called out, not silently obeyed.** If a gate fails and then
  passes on an unchanged tree, Ralphie says so, remembers it, and asks you to fix
  it, instead of sending an agent to chase a bug that does not exist.

---

## Files

Everything lives in `.ralphie/`, is plain text, and is yours to read or edit.

| File | What it is |
|---|---|
| `gates` | The checks that define "working". Add commands freely; to remove or replace baseline checks, stop the loop and use `gates --redetect`, then review the file. |
| `OBJECTIVE.md` | What you want done. |
| `MEMORY.md` | Durable lessons. Injected into every prompt. |
| `ASK.md` | Questions awaiting you. |
| `events.jsonl` | Append-only evidence of everything that happened. |
| `log/` | Engine output or a marked retained tail, one file per cycle. |
| `state` | Counters plus durable objective/acceptance identity. Do not delete it during a run or to reset acceptance. Cycle and outcome counts can rebuild from the ledger, but acceptance binding and work identity cannot; losing them fails closed and requires explicit recovery with `--accept`. |

Ralphie excludes its own directory through `.git/info/exclude`, which is local
and untracked, so your `.gitignore` is never modified and nothing about Ralphie
appears in a review.


### Exit codes

So cron and CI can react without parsing text:

| Code | Meaning |
|---|---|
| `0` | Ran to a clean stop: objective met, limit reached, or stopped on request |
| `1` | Could not start, or a command was refused or could not persist its result |
| `2` | Blocked: no engine could complete a cycle |
| `3` | Stalled: several cycles in a row changed nothing |
| `10`, `11` | Never returned: "objective met" and "out of time" are clean stops, so they exit `0` |
| `130` | Interrupted |
| `141` | Output was closed early (for example `ralphie.sh \| head`) |

---

## Design invariants

1. **One file.** `bash` + coreutils + `git`. Nothing else.
2. **Gates are truth.** Only a passing gate promotes work. Self-reports never do.
3. **Interrupted runs can resume.** Preserve objective files and state; detected
   acceptance damage is refused until explicitly repaired.
4. **The ledger is append-only.** Counters can be rebuilt; acceptance identity must be retained. Evidence follows the documented ledger retention limits.
5. **The worker never waits for a human.** Worker questions are files, not
   prompts. Only the user-authorized interactive chat client may read terminal
   input; one-turn chat and autonomous runs never do.
6. **Never waste a token** on something a shell command already knows.
7. **Handled failures and signals record a reason.** An untrappable kill can
   leave a stale lock; `status` detects the missing worker and reports interruption.

Ralphie stops itself when it stops being useful: three cycles with no change to
the tree ends the run and asks you a question, instead of spending the budget
proving it is stuck.

---

## Requirements

`bash` 3.2 or newer (macOS ships 3.2; Ralphie is tested against it), `git`, and
one AI engine on `PATH`. The built-in watchdog bounds engine calls, gates, and
commits; neither `timeout` nor `gtimeout` is required.

## License

MIT.

### Objective acceptance

Use `--accept 'COMMAND'` to add an objective-specific completion condition.
The command must be one nonempty single line. It runs from the project root,
separately from health gates. It need not work when the run starts.

```bash
./ralphie.sh --accept './check-feature.sh' "implement the requested feature"
```

Health-green work can still be committed when acceptance fails. Acceptance alone
never stops the loop: completion still needs the engine's `done` report or the
operator's `--done-when-green` choice. Both routes require health gates, a current
acceptance pass, and actual changed work on this objective and command binding.
A no-change green baseline is not work. Without health gates, work is unverified,
not complete. In Git projects, protected pre-existing files, runtime state, and
changes outside the selected project do not supply acceptance work evidence.
Genuine work for the current binding survives a refused save, but must still be
saved before completion unless `--no-commit` was selected. A new request clears
that work identity. Acceptance runs once in each eligible health-green verification,
even for engines with native gates. It uses the health watchdog (`GATE_TIMEOUT`)
and writes `.ralphie/log/acceptance-N.log` plus ledger pass/fail evidence.

A resumed run (`run` or `--once`) restores the command from `.ralphie/acceptance`. Missing, changed,
or malformed configuration fails closed. Supplying a different explicit objective
without `--accept` clears the old requirement; supplying a new command starts a
fresh work identity. Repeating the same objective and command resumes the existing
identity. `forget` clears the requirement. To recover damaged configuration,
supply `--accept` again (this starts fresh when the old binding cannot be verified).

Command text is frozen in memory for a run. A state-bound digest detects config
damage before and after execution. Binding and work identity survive ledger
rotation, even after the original events leave the retention window. Losing
either the binding or configuration fails closed. This is not a security boundary
against an actor that can rewrite or remove both state and configuration as the
same OS user.
Files invoked by the command are not frozen. Acceptance commands, like health
gates, should be checks rather than project-mutating actions. If acceptance
changes the verified tree, Ralphie reruns health gates before saving, and checks
gate/objective integrity again. If those health checks change the accepted tree,
acceptance becomes stale and completion waits for a later cycle. Checks are not
rerun indefinitely against each other's side effects. No TODO semantics
are inferred to construct acceptance conditions.

### Engine output limits

`ENGINE_OUTPUT_MAX_BYTES` sets a positive per-call ceiling for combined captured
stdout/stderr and file-based answers (default 16777216 bytes, 16 MiB). Zero or
invalid values restore the default. The watchdog checks while the engine runs,
even with zero timeouts, and checks again on exit. Exceeding the ceiling kills
the process tree and blocks the cycle with an output `resource-limit` reason.
It does not retry, switch providers, or accept a partial completion report.

This is a polling limit, not a strict disk quota: a fast producer can overshoot
between polls and during termination. Normal answers are parsed before retained
logs and answers are trimmed to a marked tail of at most 256 KiB each. Oversized
failed captures are trimmed before copying, and their answer is cleared. Prompts
and provider session records are not trimmed. This does not bound total disk
use, provider-owned files, or the size of the active provider session.


### Ongoing operator requests

Use `./ralphie.sh request "requirement"` or `request --file FILE` while a worker
runs or while stopped. Files resolve relative to the project. Each request is
1–4096 bytes; the active batch has 32 slots (including interrupted reservations).
The next cycle includes every active request. `request list` reports queued or
applied; applied means presented in a durable prompt, **not completed**.

When you deliberately retire the current batch, stop the worker and run
`./ralphie.sh request archive`. It refuses a live worker and shares the worker
start lock. This explicit action moves the entire batch to
`.ralphie/request-archives/UNIQUE-ID`, including original bytes, presentation
receipts and incomplete reservations, then starts an empty active batch. It
does not mark work complete. Archived requirements are not automatically
injected. Review them and explicitly resubmit anything still required. Nothing
is automatically pruned. Archive also recovers capacity used by killed producers.

Publication and archive serialize through a short writer lock. A racing accepted
submission belongs either to the retained archive or to the new active batch;
it cannot disappear between them. Busy writers may ask you to retry. The batch
rename is atomic; interruption before recreation leaves a missing active
directory, which means an empty batch and is recreated on the next submission.
There is no fsync/power-loss or exactly-once claim. Same-user malicious evidence
mutation/deletion is not protected. Presentation receipts retain prompt paths,
not copies of prompts.
