# Ralphie

**An autonomy kernel for any project, on any machine, with any AI engine.**

One file. No dependencies beyond `bash`, coreutils and `git`. Plant it in a
project, tell it what you want, and walk away.

```bash
curl -fsSL https://raw.githubusercontent.com/sirouk/ralphie/master/ralphie.sh | bash -s -- "make the tests pass"
```

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
positional text or a command, as with the other CLI options.

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

Every engine is described by one table row listing what it can actually do:
`autonomy`, `gates`, `memory`, `subagents`, `resume`, `skills`, `json`.
Ralphie measures that, then supplies only the missing parts.

- Against a **fully capable engine** (Prime Agent), Ralphie collapses into a thin
  durability shell: evidence, git, budget, memory, the human channel. The engine
  self-drives against the gates.
- Against a **weak engine**, Ralphie expands and supplies the scaffolding:
  explicit decide/act/verify cycles, retries, fallback, its own memory.
- Against an **engine that does not exist yet**, Ralphie needs a new table row and an `engine_build` case branch.

Selection uses declared, source-checked capabilities, not a live benchmark.
Prime Agent currently has the highest capability score. Explicit engine choices
always win. New engines can take the lead when their supported capabilities are
added to the table.

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
# An installed copy defaults to its own directory, not the caller's cwd:
RALPHIE_PROJECT="/path/to/my project" /path/to/ralphie.sh discover
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

And it enforces that, rather than asking. A verification surface the agent can
edit is not a verification surface.

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
Review the new file and add any custom commands before the next run.

---

## The human is never blocked

Ralphie has no interactive mode, no wizard, and no interview. It cannot stall
waiting for someone to type.

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
./ralphie.sh "what you want done"   Run the loop
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
./ralphie.sh update                 Replace this script with the latest
```

Useful options:

```
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

Ralphie picks the most capable engine installed, and falls back down the list
when one fails. A permanent failure (bad key, no quota, unknown model) is never
retried; a transient one (rate limit, 503, reset connection) always is.

---

Gate and engine call limits use a built-in watchdog; no `timeout` utility is
required. At a deadline, Ralphie sends TERM, allows two seconds for cleanup,
then forces termination. Polling can add about one second. `COMMIT_TIMEOUT`
bounds git commit, hooks, and signing (default 120 seconds). Explicit zero gate
or engine limits disable those call limits.

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
| `1` | Could not start: no engine, another loop is running, or a bad argument |
| `2` | Blocked: no engine could complete a cycle |
| `3` | Stalled: several cycles in a row changed nothing |
| `10`, `11` | Never returned: "objective met" and "out of time" are clean stops, so they exit `0` |
| `130` | Interrupted |
| `141` | Output was closed early (for example `ralphie.sh \| head`) |

---

## Design invariants

1. **One file.** `bash` + coreutils + `git`. Nothing else.
2. **Gates are truth.** Only a passing gate promotes work. Self-reports never do.
3. **Every run is resumable.** Kill it anywhere; it continues correctly.
4. **The ledger is append-only.** Counters can be rebuilt; acceptance identity must be retained. Evidence follows the documented ledger retention limits.
5. **The human is never blocked.** Questions are files, not prompts.
6. **Never waste a token** on something a shell command already knows.
7. **Every abnormal exit records a reason code.**

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
not complete. Acceptance runs once in each eligible health-green verification,
even for engines with native gates. It uses the health watchdog (`GATE_TIMEOUT`)
and writes `.ralphie/log/acceptance-N.log` plus ledger pass/fail evidence.

A bare resume restores the command from `.ralphie/acceptance`. Missing, changed,
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
gates, should be checks rather than project-mutating actions. No TODO semantics
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
