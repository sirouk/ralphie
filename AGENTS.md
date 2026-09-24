# Working on Ralphie

This repository contains one product: **`ralphie.sh`**.

Everything else exists only to keep that one file correct, portable and
documented. If a change does not make `ralphie.sh` better, it does not belong.

## Read this first

`ralphie.sh` is organised in seven layers, in order, each with a header comment
explaining what it is for and why it exists:

| Layer | Purpose |
|---|---|
| 1 CORE | output, portable shims, primitives |
| 2 LEDGER | state, append-only events, locking, process hygiene |
| 3 PROJECT | stack detection, gate discovery, gate execution, git |
| 4 ENGINE | the driver table, capability model, invocation, retries |
| 5 LOOP | observe → decide → act → verify → record → learn |
| 6 HUMAN | the non-blocking question channel |
| 7 INTERFACE | CLI, supervisor chat, worker launch, doctor, status, self-update, main |

Two places are deliberately shaped to be read before anything else, because
they are the program:

```bash
cycle_once()          # 1 screen: begin, observe, act, verify, record, learn
main()                # 1 screen: parse, dispatch, prepare, loop, finish
```

Each phase is a named function. If you find yourself adding a seventh step to
`cycle_once`, stop: the loop has six phases because the README says it has six.
Put the work inside the phase it belongs to.

Read the layer header before changing anything inside it. The comments explain
the failures each piece of defensive code exists to prevent; several of them
were paid for the hard way.

## The rule that governs every design decision

> **Ralphie supplies exactly the complement of what the engine cannot do.**

Before adding a feature, ask whether a capable engine already provides it. If it
does, add the capability name to that engine's row in `ENGINE_TABLE` and let
Ralphie skip the work.

Line count is not the measure; duplication is. The previous generation reached
~10,000 lines by reimplementing what engines already did. This one is larger
than that and still correct, because every line pays for something no engine
supplies: durability, evidence, the gate contract, the human channel, and the
stops. When you add code, name which of those it serves. If the answer is "the
engine already does this", delete it and add a capability instead.

## Invariants you may not break

1. **One file.** `bash` 3.2, coreutils and `git`. **The loop** may never gain a
   runtime dependency. An *optional* feature may use an optional tool — live
   `/follow` uses `python3`, `steerer` uses `prime-agent`/`claude` and `tmux` —
   on one condition: without that tool the feature says exactly why, once, and
   everything else keeps working. A feature that breaks the loop when a tool is
   missing is not optional, it is a dependency.
2. **Gates are truth.** Never let an engine's self-report promote work, and
   never let the engine shrink the gate set. `guard_gates` restores anything
   removed during a cycle. Without it, a mock engine replaced the only gate with
   `true` and Ralphie committed a broken project while reporting success.
3. **Resumable.** Any interruption must leave recoverable state.
4. **Append-only ledger.** `events.jsonl` is never rewritten.
5. **Never block the worker on a human.** No autonomous worker may `read` from
   a terminal. The user explicitly authorized one narrow exception: the
   foreground interactive supervisor chat client may read terminal input when
   both stdin and stdout are terminals. One-turn chat never reads a terminal.
   Chat must have separate locks, history and cleanup; closing it must not stop
   the worker. This exception does not permit prompts in any worker phase.
6. **Never waste a token** on something a shell command can determine.
7. **Explicit operator choices are honoured**, including `--engine`.

## Portability rules

macOS still ships **bash 3.2**, and it is the version this is tested against.

- No `mapfile`, `readarray`, `declare -A`, `wait -n`, `${x^^}`, `${x,,}`.
- Never expand a possibly-empty array without the guard: `"${a[@]+"${a[@]}"}"`.
  Under `set -u`, bash 3.2 aborts on the naked form.
- Always pass `--` to `grep` when the pattern may begin with `-`. BSD grep
  parses it as an option and fails.
- `grep -c` prints `0` *and* exits 1 on no match. Use `count_of`.
- `$(printf '\n')` is the empty string: command substitution strips trailing
  newlines, so `case $x in *"$(printf '\n')"*)` matches *everything*. Use the
  `RALPHIE_NL` variable.
- NUL-separated data must travel through a file. Command substitution discards
  NUL bytes, so `done <<EOF $(git ... -z) EOF` silently collapses every path
  into one string and the filter quietly does nothing.
- Every file Ralphie owns can be replaced by a directory or made unreadable by
  the agent it is supervising. Route them all through `ensure_own_file`.
- Never write `local a="$X" b="$a"`. The second name reads `a` while the
  declaration is still being evaluated: standalone that is an unbound-variable
  error, and inside a function called by another one it silently picks up the
  CALLER's variable of the same name. That destroyed two generations of the
  append-only ledger, and only a counter comparison revealed it. Declare first,
  assign after.
- Do not assume `timeout`, `sha256sum`, `pgrep`, `python3`, `node` or `jq` exist.
  Layer 1 has a fallback for each thing that is genuinely needed.
- `ps` IS assumed, and it is the one exception. `descendants_of` (L833) is
  `ps -A -o pid= -o ppid=` piped into awk, and it is the only way Ralphie finds
  what a timed-out gate or engine left behind. There is **no fallback**, in a
  program whose Layer 1 has a fallback for everything else. `ps` is in `procps`,
  not coreutils, so "bash + coreutils + git" was never the whole truth. If you
  ever add a second process-discovery path, that is the site. Until then say so
  in `README.md` rather than pretending coreutils is enough.
- Never parse `git status --porcelain` for paths. It quotes and escapes anything
  containing a space or a non-ASCII byte, the quoted form never matches the real
  file, and the operator's uncommitted work gets committed. Use `-z` forms.
- `git rev-parse HEAD` prints the literal "HEAD" and exits non-zero in a repo
  with no commits. Use `rev-parse --verify --quiet` and `symbolic-ref`.
- A command path may contain spaces. Do not use `${cmd%% *}` to find the
  executable without testing the whole string first.
- A function whose last statement is a conditional returns that condition's
  status. Add an explicit `return 0` when that is not what you meant. This
  silently demoted the best engine to a fallback once already.

## Testing

```bash
./test.sh              # full offline suite, no network, no tokens
./test.sh -v           # trace every command
./test.sh loop         # only tests whose group name contains "loop"
```

Run it from a **frozen copy**, never from a tree you are still editing: the
suite copies `ralphie.sh` into every fixture, so an edit landing mid-run gives
a result for a file that never existed.

The suite shadows `prime-agent`, `claude` and `codex` with free mocks on its own
`PATH` before anything runs, so no real engine is ever invoked and no machine
needs one installed. Never bypass that shadow.

The suite drives the entire loop against a **mock engine**, so the full
observe → act → verify → commit → learn cycle is proven without a single API
call. Add a test for every behaviour you change. A behaviour with no test is a
behaviour that will regress.

Five traps in the harness itself, each of which has already silently hidden
failures:

- A test that calls a `ralphie.sh` function must be inside a `( load_lib ... )`
  group. Outside one, the function does not exist, the call fails, and the
  assertion "passes" for the wrong reason.
- `load_lib` does `set +e` after sourcing, because `ralphie.sh` sets `set -e`
  for itself and would otherwise abort the whole group at the first
  deliberately-failing assertion.
- Counters live in files under `$TALLY`, not in variables, because a subshell
  cannot increment a parent variable. Counting in variables let a FAIL print and
  still report an all-green suite.
- **Every result is counted twice**, once in its bucket and once in `$TALLY/all`,
  and the two totals must agree. Guarding only "was anything counted at all"
  protected the pass counter and left the fail counter unprotected: making
  `$TALLY/fail` a directory silenced every failure, and the suite printed
  `FAIL ...` on screen and then `PASS 642 passed`, exit 0.
- **Every `( load_lib ... )` group ends in `true )` and its status is checked.**
  `load_lib` clears `-e` but not `-u`, so one unbound variable aborted a group
  and took the rest of its assertions with it -- 18 vanished, and the summary
  said `PASS`.

Sabotage a function and confirm the suite goes red before trusting a green run.
The suite tests this about itself: `./test.sh harness-honesty` destroys the
counters and swallows a failure on purpose, and requires `BROKEN` and exit 1.

**Prefer one enforced postcondition to many guards.** Four defects in four
consecutive reviews were the same missing answer at a different site: a commit
step returned without setting a flag, and the cycle landed in `pass` with an
empty git log. The fix was not a fifth guard but a single check in
`record_outcome` -- a green cycle claims the work is saved, so HEAD must have
moved. `./test.sh commit-postcondition` injects a brand-new silent-failure site
that no guard knows about and proves it is still caught.

If you touch engine invocation, also run one real cycle by hand:

```bash
cd /tmp && mkdir demo && cd demo && git init -q
# create something broken with a test that proves it
/path/to/ralphie.sh --once -v "fix the failing test"
```

## Supervisor chat

Chat is a control surface, not a second execution loop. Keep `cycle_once` at six
phases. Dispatch chat before ordinary ledger repair or worker preparation;
snapshots are read-only and conversation is chat-local. Only explicit `/apply ID`
authorizes a displayed, finite, settings- and generation-bound proposal. Never
evaluate model output or rewrite live objectives, gates or state. Requests belong
to the next-cycle channel; presented is not completed. Start and stop receipts
must reflect observed worker identity and actual lifecycle state.

The compact terminal viewport is a preview, never an authorization surface.
Leave it before full authoritative proposal output and keep subsequent output in
normal scrollback. `/proposal` redisplays the same pending proposal without
renewing its ID, settings or generation. Keep grouped help, waiting indication,
multiline input and native Unicode editing independent of worker execution.
Bash 3.2 lacks the readline state needed for safe empty-left navigation; preserve
native editing and document `/jobs` as the fallback, not an implemented shortcut.
No mandatory terminal UI dependency is allowed.

Named conversations restore bounded discussion and advisory job selection, never
engine execution, a workspace or historical configuration. Preserve default
history at `.ralphie/chat`; named data lives at `.ralphie/conversations/NAME`.
Keep one project-wide chat lock and one independent worker lock. Refuse unsafe
names/paths and capacity beyond 32 conversations including default; never prune
history automatically. `/new NAME` creates/selects; `/resume NAME` and
`/switch NAME` select existing conversations. `chat --session NAME [MESSAGE]`
reconnects explicitly; `chat -- "--session"` sends literal option-looking prose.
Selection is cross-conversation navigation, not job ownership. New starts use
current invocation settings.
Switching/reconnecting invalidates pending authority; bind proposals to the
conversation and selected target as well as existing settings/generation inputs.
Keep next-cycle requests project-wide and refuse conflicting historical targets.

`/jobs` lists retained launches, not just live processes. `/select ID` stores an
advisory target. `/follow`, `/attach` and `/watch --follow` share one fixed-target
follow. What it follows is the **engine's own dialog**, read from the session
transcript Ralphie already asks `prime-agent` to keep and advanced by byte
offset, so it never replays and never freezes at the console cap. With no
transcript (another engine, `RALPHIE_ENGINE_SESSION=0`, or no `python3`) it says
so once and falls back to bounded `output.log` snapshots. Never move the follow
onto the money path: `engine_build`, `engine_invoke`, `engine_answered`,
`watchdog_wait`, `worker_capture` and the `ENGINE_OUTPUT_MAX_BYTES` ceiling must
stay byte-for-byte unaffected by anything a viewer does. Explicit IDs also select
the job. Missing saved selections
never fall back to the current worker. With no selection, observation and `/stop`
may use the current worker, but the stop proposal displays the exact target.
q, Esc and Ctrl-C detach without stopping work; final/interrupted/unknown jobs
show a snapshot and return. x or typed `/stop` plus Enter leaves follow and shows
a full safe-stop proposal for its fixed ID, never a signal or stop marker;
`/apply ID` remains necessary. Ordinary composer x stays text. Preserve terminal
cleanup and consume escape sequences without leaking suffixes into chat.
`/watch` without `--follow` remains one-shot. A safe `/stop` remains
a boundary request. `/kill ID` and `/nuke ID` are explicit local force proposals
requiring `/apply ID`; never infer force authorization from model output. Bind
force to the current token/lock and recorded process identity, refuse missing or
changed witnesses, and signal only the finite verified process snapshot. Never
promise force saves work, stops remote billing, or eliminates same-user tampering
and check-to-signal PID races. Retain interruption evidence for recovery.

Preserve original launch options and all gate/acceptance/ownership checks.
`--spec FILE chat` keeps the full exact spec authoritative, not the proposal title.
Keep worker console retention honest: first 1 MiB, then drain excess. `/watch`
without `--follow` is a bounded snapshot of that console, not a rolling tail, and
that cap is why `/follow` reads the transcript instead. Refuse at 32 retained launch entries
before another launch spec copy. Never prune receipts automatically; manual
archiving requires all launchers/workers stopped and preserves whole launch dirs.

Prime supervisor support requires exactly 0.9.5 and its reviewed internal
owned-worker frontend, not a generic no-tools sandbox claim. Unsupported
providers fail without fallback. Selected custom inference requires the explicit
trusted `RALPHIE_CHAT_ADAPTER` executable, not merely a custom worker command.
Keep chat accounting and cleanup separate from worker totals and children. Usage
retains nine recent project-chat receipts shared across conversations, not
per-conversation or lifetime totals. Prompt, answer, history and inference scratch
follow the selected conversation. Enforce 4096-byte human input,
32 KiB inference input, 8 KiB answers and a 90-second default (maximum 300-second)
inference allowance. Local cancellation cannot guarantee remote cancellation or
stop billing. No tmux dependency, OS-service, controlling-terminal or host logout
survival guarantee is implied.

Only zero arguments default to chat. Bare non-terminal invocation must fail;
unattended bare jobs migrate to `run`. Options-only and objective invocations
remain runs. Put global options before `chat`. The only terminal-read exception
is the interactive client described in invariant 5. Worker phases never prompt.
Verify dispatch, authority, resource limits and independent worker lifecycle with
offline mocks and terminal tests. Record current verification separately from
historical `graphify-out/` receipts; do not rebuild or relabel those receipts as
evidence for new chat behavior.

## The stops, and why they are ordered

v3 could work. It could not finish or give up. Four stops now exist and their
ORDER is load-bearing; `cycle_learn` decides them in this sequence and a new
decision goes LAST, never in front:

1. `NOCHANGE_LIMIT` — the tree stopped moving. `stalled`, return 3.
2. `done` — `completion_ready()`. Real gates green. return 10. **Byte-identical
   to v3.1.0 and it must stay that way.** Relaxing it by one clause is how a
   project with nothing to check starts reporting green.
3. `consensus_stop` — the engine's own word, believed only when it survives being
   asked again. Two claims only: `blocked` **with** a question in `ask:`, and
   `done` on a project with no gate (`unverifiable_done`). Neither is ever
   verified and neither exits 0. return 2.
4. `retreat_check` — change of approach, and the oscillation stop. return 3.

`unverifiable_done()` is deliberately NOT `completion_ready()` and must never be
folded into it. It says something strictly weaker and says so in its name.
Nothing that consults it may write `done`, count a green cycle, or exit 0.

An unchanging failure is not proof of futility. A stop keyed on "the signature
did not change" was written once and the suite rejected it: an engine can be
making real progress against a failure that reports identically. Count the
CROSSINGS, not the sameness.

## The steerer

One optional line inside `event`. With no steerer it is two shell tests and a
return, and that is the contract: the loop may never wait on it, and a wedged
agent may never hold a cycle open (`RALPHIE_STEERER_WAIT`, 5s, unconditional).

The engine interface is six verbs — `start id attach logs tell stop` — with a
`prime-agent` and a `claude` implementation. Adding a third host means
implementing six functions, not touching the loop. `claude` has no send verb, so
its events are PULLED from `.ralphie/steerer/mailbox.jsonl`; the mailbox is
written for both hosts so "what was Ralphie telling it" is answerable either way.

Everything that crosses into another agent is flattened, redacted and bounded
(`steerer_message`): a credential in gate output must not travel, and a
multi-line detail must not be able to forge a second event line.

Never trust a banner. A session id printed at boot is re-proved against the live
list every time, so a dead steerer is never reported as running.

## engine-doctor, and why it exists

An engine's own documentation is not evidence. Measured on `prime-agent` 0.9.5:
`help send` advertises `--steer` and `--follow-up` and the binary rejects both;
the shipped docs say daemon protocol v4 while the live daemon reports v7. When
you add or change a flag in `engine_build`, add it to the matching
`ENGINE_FLAGS_*` list in the same commit. Scope matters as much as spelling:
`prime-agent`'s `--json` lives in `help send`, not `--help`, and every `codex`
flag lives in `codex exec --help`. Checking the wrong help text reports a present
flag as missing.

## Chat rails

The `[Next]` block is composed LOCALLY from project facts (`rail_probe`), never
from model text, and matched by local string comparison on the whole trimmed
lowercased line. That is the whole safety argument, and it is also why rails cost
no tokens.

Two rules you may not relax:

- An option that spends or stops is marked `spends` and names its consequence.
  A bare Enter never enacts one; it asks for a typed `yes`. Force termination is
  never offered as a key at all.
- `start`, `stop`, `run` and `request` never work as bare verbs. English prose
  begins with those words, and two of them cost money.

`RALPHIE_RAILS=0` must restore the older prefixed chat exactly. Keep that path
tested.

## Test-suite rules that are not obvious

- **Never hard-code the version in an assertion.** Five assertions spelled
  `"ralphie 3."` in full and a version bump failed nine of them for no reason but
  arithmetic. Use the derived `$RALPHIE_VERSION`.
- **Never assert an instant that the code does not guarantee.** One assertion
  read `[ ! -e .ralphie/lock ]` the moment the `final` receipt appeared, but
  `on_exit` writes `final` FIRST and releases the lock after it. It passed only
  because the gap is normally microseconds; inserting a one-second sleep between
  those two lines fails it every time, and so does a loaded CI runner. Poll with
  a bounded budget, and prove the fix still fails when the lock is never released.
- **`MIN_EXPECTED_ASSERTIONS` is a floor for the MINIMAL-tool run**, not for
  yours. Measure the minimal run before raising it; a floor set from a
  full-tool machine turns a legitimately smaller Linux run into a false BROKEN.
- `test.sh` is not, and cannot be, `shellcheck -S error` clean: it overrides the
  `[` builtin as a shell function to fake a terminal. Do not add it to the
  ShellCheck step.

## Changing the engine table

Adding an engine is one row and one `case` branch in `engine_build`:

```
name | command | answer(stdout|file) | capabilities
```

Declare only capabilities the engine genuinely has. Over-declaring `autonomy`
or `gates` makes Ralphie stop supplying them, and the loop quietly degrades.
Over-declaring `stream` is worse: Ralphie will judge the engine by its silence
and kill healthy long runs. `prime-agent -p` and `claude -p` buffer their whole
answer, so neither streams.

## Documentation

`README.md` is the operator contract. `--help` is the machine-readable one and
the suite enforces it: `documented-knobs` derives every environment variable the
script reads and never assigns, and requires each to appear in the `ENVIRONMENT`
section. Its prefix list is `RALPHIE|ENGINE|GATE|NOCHANGE|CONSENSUS|RETREAT|STAGNATION|OSCILLATION|MEMORY|MIN|NO` —
add yours to that list when you invent a new one, or the test that exists to
catch an undocumented knob will not see it. (`COMMIT_TIMEOUT` is documented but
outside the list today.)

`CHANGELOG.md` records BEHAVIOUR CHANGES a stranger could be surprised by, not
just features. Exit codes and `status --json` are a compatibility contract:
`--help` promises them "so cron and CI can react without parsing text". Widening
the meaning of an exit code, or adding a `status` value, is a MAJOR version.

Keep the install URL working: the default self-update source is the published
`https://raw.githubusercontent.com/sirouk/ralphie/master/ralphie.sh`, not the
selected project's Git remote. A project can contain a stale vendored copy or
have an unrelated origin. Forks and private mirrors must explicitly set
`RALPHIE_UPDATE_URL` in the operator environment; project `config.env` cannot
set it. Keep `ralphie.sh` at the repository root under that exact name.
`VERSION="major.minor.patch"` must remain exactly one literal line —
`self_update` parses it with
`sed -n 's/^VERSION="\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)"$/\1/p'` and
refuses any candidate that produces zero or two matches.
