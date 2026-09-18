# Ralphie

**An autonomy kernel for any project, on any machine, with any AI engine.**

One file. No dependencies beyond `bash`, coreutils and `git`. Plant it in a
project, tell it what you want, and walk away.

```bash
curl -fsSL https://raw.githubusercontent.com/sirouk/ralphie/master/ralphie.sh | bash -s -- "make the tests pass"
```

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
- Against an **engine that does not exist yet**, Ralphie needs one new table row.

Capability is earned by measurement, never granted by name. A better engine
released years from now takes the lead automatically.

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

## Gates: the definition of "working"

A gate is any shell command that exits 0 when the project is healthy.

```
$ cat .ralphie/gates
npm run typecheck
npm run lint
npm test
```

Ralphie discovers them on first run from `package.json`, `pyproject.toml`,
`Cargo.toml`, `go.mod`, `Makefile`, `deno.json`, `pom.xml`, `mix.exs`, and more.
Every candidate is **trial-run before it is accepted**, so a command that cannot
execute on this machine never becomes a gate. Then the file is yours. Edit it.

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

Gates the engine *adds* are kept. A project teaching Ralphie how to check itself
is exactly what should happen, and it does.

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
-m, --minutes N         Stop after N minutes, mid-cycle included: an engine
                        call never gets more time than the budget has left
    --once              A single cycle
    --gate "CMD"        Add a verification command (repeatable)
    --no-commit         Never commit
    --done-when-green   Stop as soon as everything passes and nothing remains
    --no-yolo           Do not grant the engine autonomous tool permission
    --update            Self-update before running
-v, --verbose           Show the machinery
-q, --quiet             Print less: no progress commentary
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

## Safety

**Nothing is committed unless the gates pass** — and when a project has no gate
at all, Ralphie says so, does not call the result green, does not count it as a
passing cycle, and writes `NOT VERIFIED` into the commit message. The safety
model is enforced by re-running the gates, never by trusting a report.

Around it:

- **Work on a branch.** `--branch ralphie/fix-login` creates it, works there, and
  leaves your protected branch alone. Review it as a normal pull request.
- **One command undoes an entire run.** Ralphie records the commit it started
  from and prints it at the top of every run and in `status`:
  `git reset --hard <sha>`.
- **Work you had already started is never swept into an autonomous commit.**
  Paths that were modified before Ralphie started are excluded for the whole
  run, and the list of them is checksummed so that nothing can quietly empty it.
  Work Ralphie itself left behind on a red cycle is remembered as its own — by
  content, not by name — so it still gets committed once it goes green, and the
  moment you change those bytes yourself the claim is dropped.
  Ralphie cannot see an edit you make *while* a cycle is running; the snapshot
  is taken once, when the run starts. Avoid editing the project during a cycle,
  or run Ralphie on its own branch with `--branch`.
- **Likely secrets and bulk are held back.** `.env` in any directory, private
  keys, `.netrc`, `.npmrc`, credentials and service-account files, `kubeconfig`,
  `*.tfstate`, `.aws/`, `.ssh/`, symlinks that resolve outside the repository,
  `node_modules/`, build output, and anything over 1 MB. They are left untouched
  on disk and reported to you. This is a strong net, not a secret scanner: a
  credential in an ordinary source file will still be committed, exactly as it
  would be by a human.
- **Ralphie never pushes.** Publishing stays a human decision.
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
  written is never rewritten. `.ralphie/log/` keeps the full engine output for
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
| `gates` | The checks that define "working". Edit freely. |
| `OBJECTIVE.md` | What you want done. |
| `MEMORY.md` | Durable lessons. Injected into every prompt. |
| `ASK.md` | Questions awaiting you. |
| `events.jsonl` | Append-only evidence of everything that happened. |
| `log/` | Full engine output, one file per cycle. |
| `state` | Derived state. Safe to delete; the cycle and outcome counts rebuild from the ledger, and the run totals restart from zero. |

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
| `130` | Interrupted |
| `141` | Output was closed early (for example `ralphie.sh \| head`) |

---

## Design invariants

1. **One file.** `bash` + coreutils + `git`. Nothing else.
2. **Gates are truth.** Only a passing gate promotes work. Self-reports never do.
3. **Every run is resumable.** Kill it anywhere; it continues correctly.
4. **The ledger is append-only.** State is derived; evidence is permanent.
5. **The human is never blocked.** Questions are files, not prompts.
6. **Never waste a token** on something a shell command already knows.
7. **Every abnormal exit records a reason code.**

Ralphie stops itself when it stops being useful: three cycles with no change to
the tree ends the run and asks you a question, instead of spending the budget
proving it is stuck.

---

## Requirements

`bash` 3.2 or newer (macOS ships 3.2; Ralphie is tested against it), `git`, and
one AI engine on `PATH`. `timeout` or `gtimeout` is strongly recommended so
engine calls and gates can be time-limited.

## License

MIT.
