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
| 7 INTERFACE | CLI, doctor, status, self-update, main |

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
5. **Never block on a human.** No `read` from a terminal. Ever.
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
./test.sh              # everything, about two minutes, no network, no tokens
./test.sh -v           # trace every command
./test.sh loop         # only tests whose name contains "loop"
```

The suite drives the entire loop against a **mock engine**, so the full
observe → act → verify → commit → learn cycle is proven without a single API
call. Add a test for every behaviour you change. A behaviour with no test is a
behaviour that will regress.

Three traps in the harness itself, each of which has already silently hidden
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

Sabotage a function and confirm the suite goes red before trusting a green run.

If you touch engine invocation, also run one real cycle by hand:

```bash
cd /tmp && mkdir demo && cd demo && git init -q
# create something broken with a test that proves it
/path/to/ralphie.sh --once -v "fix the failing test"
```

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
