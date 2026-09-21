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
Ralphie skip the work. Reimplementing something the engine already does well is
how the previous version reached 9,547 lines.

## Invariants you may not break

1. **One file.** `bash` 3.2, coreutils and `git`. No new runtime dependency.
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
./test.sh loop         # only tests whose name contains "loop"
```

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

Preserve original launch options and all gate/acceptance/ownership checks.
`--spec FILE chat` keeps the full exact spec authoritative, not the proposal title.
Keep worker console retention honest: first 1 MiB, then drain excess; watch is a
bounded snapshot, not a rolling/live tail. Refuse at 32 retained launch entries
before another launch spec copy. Never prune receipts automatically; manual
archiving requires all launchers/workers stopped and preserves whole launch dirs.

Prime supervisor support requires exactly 0.9.5 and its reviewed internal
owned-worker frontend, not a generic no-tools sandbox claim. Unsupported
providers fail without fallback. Selected custom inference requires the explicit
trusted `RALPHIE_CHAT_ADAPTER` executable, not merely a custom worker command.
Keep chat accounting and cleanup separate from worker totals and children. Usage
retains nine recent receipts, not a lifetime total. Enforce 4096-byte human input,
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

`README.md` is the operator contract. Keep the install URL working: the script
self-updates from the GitHub raw URL derived from `origin`, the current branch
and its own filename, so `ralphie.sh` must stay at the repository root under
that exact name.
