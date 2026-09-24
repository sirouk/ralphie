# Changelog

## Unreleased — explicit review checkpoint MVP

- Added separate, hash-bound `checkpoint prepare/show/record/run` evidence lane. Only `run ID --engine prime-agent|claude --spend` starts up to three one-shot tool-free model attempts; no model selection or fallback. All provider identities remain unconfirmed absent trusted receipts; no approval or gate promotion.
- Refuse unknown bare single-word argv as paid objectives unless explicitly selected; `-- WORD` and `-o WORD` remain valid.


All notable changes to `ralphie.sh`. Versions follow semantic versioning applied to
the two interfaces a script can depend on: **exit codes** and `status --json`.

## 4.2.4 — 2026-09-24

**Resident companion boot and event routing fail closed.** Prime daemon snapshots
now distinguish a verified empty list from list failure, malformed JSON and
ambiguous IDs. A new candidate must have an ID absent before boot, exact project
cwd, and an owned transcript within the new private `--session-dir`; Ralphie
never renames an arbitrary same-project session found after a failed list.
An existing name is not proof of ownership: startup refuses a second paid boot
if the saved companion cannot be verified. Prime events, manual tells, attaches
and stops recheck the saved ID/project/fence and route by immutable ID, not by a
reusable display name. Legacy or uncertain companions fall back to stateless chat.

The v2 SHA-256 record covers the broker bytes, intended flags, model, system
and append prompts, kickoff, project, boot directory and ID. It is a **local
self-attestation of Ralphie's intended boot**, *not* authenticated proof of the
daemon's actual launch flags. Any same-user process can edit the witness and
broker or spoof local daemon data; the daemon, OS account, installed Prime and
this script are in the trust base. This CLI fence is not an OS sandbox. No
network or paid agent is used in the mock regression tests.

## 4.2.3 — 2026-09-24

**Named mission MVP.** `mission preview` validates a named, bounded set of
project-local documents without writing or calling an engine. `mission start`
explicitly runs in the foreground and snapshots the spec, reference, backlog,
open decisions, and acceptance context into the ordinary stored objective.
Engine/model, cycle/minute budgets, and optional `--accept CMD` are explicit
per-invocation inputs. The existing ledger, lock, gates, and blocked-provider
refusal remain authoritative; acceptance documents are not executable gates,
and open decisions are not silently answered. Hermetic mission tests added.


**Blocked model/provider requirements fail before spending.** Direct `run` and detached
`start` now check a saved blocked objective before resetting run state, admitting
a worker, or calling an engine. ASK.md answers, `--model`, and `--no-resume`
do not revise it. An explicit, byte-different replacement objective must remove
the model/provider prerequisite; Ralphie does not infer provider availability
from the replacement text. Legacy objective identity is checked when a byte
hash is unavailable. Missing or unsafe saved objectives fail closed.

The blocked-chat requirement check now consumes the whole objective: an early
model clause followed by a long tail can no longer turn a SIGPIPE into a false
negative. Mock regressions cover Kimi versus Max, unfamiliar model names,
`run`/`start`, revisions, legacy state, and the long-tail case.

## 4.2.2 — 2026-09-24

**Blocked work stays stopped until its saved requirements can be verified.**
`/continue` only drafts a new worker for the same saved objective, engine and
model, with a bound run ID and full objective-byte digest. A second `yes` never
starts it; `/apply ID` is required. An objective with a model or provider clause
is refused rather than using an ASK.md answer as an implicit override. Revise
that objective explicitly before any new run.

**Approval and review evidence are narrower.**

- Quiet rails after two declines still show open human questions and the exact
  answer form. Declining suggestions must not hide a human decision.
- Saved `.ralphie/chat/rails` commands are no longer replayed across chat
  processes. Workers can edit the file, including its stored binding; no
  worker-writable self-check can prove that a command is the one printed.
  Same-process shortcuts still work, and a fresh chat shows current options.
- A printed proposal key becomes stale if its proposal ID changes before it
  is taken, even when the proposal body and all other settings are unchanged.
- Panel seats use tool-free Prime/Claude CLI flags and fixed system prompts;
  custom and Codex seats fail closed. Their model-written checks are UNVERIFIED
  proposals by default, not executed red evidence. `PANEL_RUN_CHECKS=1` explicitly
  runs potentially writing project scripts; timeouts and missing tools are
  UNKNOWN, not vetoes. Completed nonzero checks alone may veto, never approve.
- The resident companion loads only Ralphie's generated read broker, not global
  provider extensions. Explicit system and append prompts replace project
  `.prime/agent/SYSTEM.md` and `APPEND_SYSTEM.md`. Authentication that depends on
  a global extension fails closed with a clear message; this CLI fence is not
  an operating-system sandbox.

## 4.2.1 — 2026-09-23

**An installed copy can update itself from any project.** `update` used the
selected project's Git origin, branch and script filename as its source. In the
demo `budget-sheet-app` that produced an HTTP 404; a committed vendor copy
could instead return itself forever as "already current". With no explicit
`RALPHIE_UPDATE_URL`, Ralphie now uses the same published GitHub file as the
install instructions. A project's Git remote cannot choose executable update
code. Forks and private mirrors select their source explicitly in the operator
environment; project config files still cannot set this variable. Existing
copies need the override **once** to install this fix. The staged candidate's
version/help execution checks and atomic publication are unchanged.

## 4.2.0 — 2026-09-23

**Chat is now a real engine on rails, and you can watch the work.** Designed
with a four-seat adversarial panel and a three-agent federation (Claude, Codex,
Hermes; confidence 82→88, 76→88, 94→97 after cross-review), then built and
live-verified against the demo project.

**The resident companion**

- **`chat` talks to ONE resident agent per project** — the steerer, which already
  receives every run event. It remembers the conversation and READS the run with
  its own tools: status, the ledger, the gates, open questions, the engine's live
  dialog, queued requests, and any text file in the project (bounded, redacted,
  never `.ralphie/` or `.git/`, never through a symlink). Measured on the demo
  project: asked what the gate runs and whether the last cycle passed it, it
  made 13 reads and answered correctly — and flagged, unprompted, that the
  "gate pass" logged at cycle 7's start was too fast to be a real run.
- **It is on rails through its exposed tools, not an OS sandbox.** It boots
  with `--no-builtin-tools --no-extensions --no-context-files --no-skills
  --no-prompt-templates --no-themes`. Prime 0.9.5 *still* loads explicit `-e`
  extensions, so Ralphie passes only its hash-verified read broker, **not**
  global provider extensions (which can run host code and register write tools).
  `--no-context-files` omits `AGENTS.md`, but *not* project
  `.prime/agent/SYSTEM.md`/`APPEND_SYSTEM.md`: explicit controlled
  `--system-prompt` and `--append-system-prompt` replace those sources. An
  extension-dependent provider may therefore be unavailable; Ralphie reports
  that failure without a false success or automatic extension replay. Prime,
  Ralphie, or other processes with host permissions can still modify files.
- **Everything it wants to change is a proposal you approve with `/apply`**,
  validated by exactly the same code as before.
- **The first boot asks, with one key.** A resident agent spends tokens, so a
  warning line is not consent. No prime-agent, tmux or python3, a declined boot,
  or `RALPHIE_CHAT_ENGINE=ralphie` keep the stateless console, which says so.
- **It waits as long as the companion is working**, shows each look it takes,
  and Ctrl-C stops waiting — never chat, never the companion. A reply that
  arrives after you stopped waiting is shown at your next message.
- 4.1.x's second, unfenced chat agent is gone; `chat --stop` ends the companion
  and cleans up any 4.1.x chat session left behind.

**Watch the work**

- **`watch` on a terminal shows the live work**: the engine's own dialog for the
  current cycle, humanely rendered and sanitized. It starts and spends nothing.
  `watch --attach` is the companion's own screen.
- **`request` says when it lands**: at the worker's next cycle boundary (the
  engine call running now is unchanged), and a live companion is told at once.

**Older defects fixed by the same pass**

- **The panel no longer runs commands a model wrote.** Its safety filter was a
  denylist that accepted 10 of 12 plainly dangerous commands — including one
  that installed a gate, after which commits said "Verified by 1 gate(s)" — while
  refusing harmless ones. Seat checks are now recorded, never run, unless
  `PANEL_RUN_CHECKS=1`, and even then only a plain test/lint runner command may
  run. `panel --promote` lists first and promotes one named line, never all.
- **`PANEL_MAX_PER_RUN` is per run again**; it was a lifetime total, so the panel
  died for good on any project that had used it three times.
- **`update` runs the downloaded file before publishing it.** A download
  truncated at 97% passed every byte check and was published, leaving a kernel
  that answered every command with exit 0 and no output; a `#!/bin/sh` file
  bricked the install. The staged file must now run as itself, report exactly
  the version it declares, print a complete help screen, and end on its last
  line. **The one-line stream install** refuses a cut-off stream the same way
  instead of silently replacing a working copy.
- **Telegram `revoke` from the phone deletes before it speaks.** It used to reply
  "the token has been deleted", signal itself, and exit before deleting anything.
  The bearer-token file is also created private instead of chmodded afterwards.
- **A gate that proves nothing is no longer installed.** A trial the watchdog
  killed was promoted; a missing test PLUGIN was read as a missing test runner
  (substring match) and the project's tests left the gates; and
  `npm run test --workspaces --if-present` was offered when no declared member
  had a test, running zero tests and passing for ever.
- **Background launches report what is true.** A worker whose pid could not be
  recorded kept running while `start` said it failed; it is now stopped first.
  An old, provably interrupted launch no longer blocks every future `start`.
  `stop` on a launch that already exited says there is nothing to stop.
- `steerer stop` no longer deletes its only handle to an agent the engine did not
  confirm stopping (the defect `chat --stop` was fixed for, one function away).

**What may surprise you**

- `watch` on a terminal is now the live work, not the resident agent's screen
  (that is `watch --attach`). Piped or in CI it is still the bounded snapshot.
- Panel checks no longer run by default. Set `PANEL_RUN_CHECKS=1` to run the
  plain test/lint ones.
- `panel --promote` with no number now lists; `panel --promote N` promotes one.


---

## 4.1.3 — 2026-09-23

A second adversarial retrace, this time aimed at 4.1.1's own fix pass. Seven
reviews, one surface each; every claim reproduced before it was believed. Four
of the defects below were introduced by that pass, and two of those were worse
than what they replaced.

- **A report block is now identified by a per-cycle token, not by position.**
  4.1.1 refused any reply carrying more than one `<<<RALPHIE ... RALPHIE>>>`
  block. That also refuses an HONEST engine that restates the format once:
  measured, the same work cost three times as much and `done` became
  unreachable, because the warning went to the operator's console and the
  engine was never told. Each cycle now carries a random token, printed in the
  prompt; a block carrying it is provably the engine's answer to that prompt,
  because nothing inside the project can know it. One block is trusted exactly
  as before. Many blocks with no token take no VERDICT, tell the engine so in
  the next prompt, and after three such cycles the run stops and hands the
  operator something to act on, rather than spending the budget in silence.
- **An unattributable reply no longer swallows the engine's question.** 4.1.1
  blanked `ask:` along with the verdict, and `consensus_stop` needs blocked AND
  a question — so it re-broke the hand-over to a human that the same patch had
  just restored. A question can only help; it can never end a run.
- **The placeholder refusal covers every template and matches whole lines.** It
  knew only about `RALPHIE_CONTRACT`, so the continuation prompt's template
  still wrote its placeholder lesson into MEMORY.md; and matching the wording
  as a substring made the contract's own prose ("status: done means the
  objective is fully met") reset a legitimate `done` to progress.
- **`watch` no longer says it attached to something it never attached to.**
  4.1.1's `|| true` swallowed a refusal, so a missing session printed "attached
  to the steerer ... unfettered" and "detached. The steerer keeps running" and
  exited 0. The attempt and the outcome are now separate lines, and only the
  code that observed the outcome reports it. An ordinary Ctrl-C detach is no
  longer announced as a status.
- **Usage errors are exit 1, not exit 2.** The documented table gives 2 to a run
  that "stopped early and needs you" — what a cron wrapper pages a human on —
  and 4.1.1 gave the same code to a mistyped flag. Every documented exit code
  now has an assertion. Unknown `watch` options are refused wherever they
  appear, not only in first position.
- **Settings are validated against the vocabulary their reader actually uses.**
  4.1.1 guessed ranges: it refused `0` for five timeouts although `budget_cap`
  documents 0 as "no limit of my own" (ralphie sets `ENGINE_IDLE_TIMEOUT=0`
  itself), refused `RALPHIE_NOTIFY_WAIT=0`, and range-checked
  `RALPHIE_DIALOG_THINKING` — a BOOLEAN whose reader accepts `true|yes|on` — as
  a number. Numbers and booleans are now separate tables, each derived from its
  reader, with a test per class and an assertion that every entry is a real
  documented knob (the first draft of the boolean table contained a name this
  program has never had).


---

## 4.1.2 — 2026-09-23

- **`commits` in `status --json` is per RUN**, like `run_tokens` and `run_cost`
  beside it. 4.1.1 added the field and documented it as per-run while it in fact
  accumulated for the life of the project, so it could never answer the question
  it exists for: did THIS run save anything?


---

## 4.1.1 — 2026-09-23

The retrace release. Six adversarial reviews of 4.1.0, one surface each, plus
independent reproduction of every claim. 4.1.0's headline feature did not work
at all; this fixes that, and eleven older defects the same pass turned up.

**4.1.0 regressions**

- **The engine chat session could never boot.** `engine_chat_boot` asked
  `steerer_scratch` for its scratch file twice; that helper returns ONE path per
  process and truncates it on every call, and `steerer_pa_sessions` deletes the
  same path itself — so the reader always saw an empty file, the new agent's id
  was never found, and every `chat` waited 60 seconds in silence before failing.
  Both boots now share one scan (`steerer_pa_new_id`) that also filters on
  `lifecycle == live` and `cwd == this project`: the chat copy had neither, and
  could have renamed an unrelated session the operator had open elsewhere.
- **A failed attach ended `chat` instead of falling back.** The call was a bare
  statement under `set -e`, so a refused engine or a dead daemon exited 1 with no
  console at all — the opposite of the contract the redesign was built on.
- **Ctrl-C did not reliably return you to ralphie.** `"$bin" attach; rc=$?` lets
  `set -e` exit before the assignment, so a TUI ending on 130 skipped both the
  INT-trap restore and the terminal restore. Detaching is not failing.
- **Failed boots leaked a paid agent**: `steerer_tmux_kill` only matched
  `ralphie-steerer-*`, so every cleanup call in the `ralphie-chat-*` family was a
  no-op. Both families are now recognised.
- **`chat --stop` used the wrong engine and claimed success regardless.** It
  dispatched through the STEERER engine, so `RALPHIE_STEERER_ENGINE=claude` sent
  the stop to claude, swallowed the failure, and still deleted the only name that
  could find the real session. It now stops prime-agent directly, reports what
  actually happened, and keeps the handle when a stop fails.
- **`watch --attach` had no terminal check** — in cron or CI it would start a
  billing agent and attach a TUI to a pipe. Refused without a terminal.
- **`watch --nonsense` was silently accepted** and `watch ID` was ignored on the
  attach path. Unknown flags are refused; a launch id still means that launch.
- Booting the chat session now names its cost before it spends, like
  `watch --attach` does.

**Older defects, found by the same pass**

- **A false "objective complete".** `parse_report` took the LAST report block, so
  an engine that quoted a file containing one after its own report handed the run
  a forged verdict: measured, a run that said "still working, not finished" ended
  at cycle 1 as done, exit 0. More than one block now means no terminal claim, no
  durable lesson and no question in Ralphie's voice — progress only.
- **The contract template was believed when echoed back.** It contains a complete
  report block, so an engine repeating its instructions wrote the placeholder
  lesson into MEMORY.md for ever and filed the placeholder question as a real one.
- **`watch --follow` printed untrusted engine text raw**, re-opening the terminal
  escape and forged-prompt hole the chat follow had already closed. Every chunk is
  sanitized now, and its idle bound measures idleness rather than elapsed ticks.
- **A planted FIFO in `.ralphie/lock/pid` parked `run` for ever.** Worker
  admission had refused ambiguous lock metadata since 4.0 and said why; the other
  readers still opened it blind. Measured: 4.1.0 never returned; this exits 1 with
  "ambiguous lock".
- **Counters lost increments.** `state_bump` read outside the mutex: measured,
  two writers x 60 bumps left 60. Read and write now share one reentrant lock.
- **A crashed writer wedged state for 30 seconds**, and a live one could be
  robbed. The mutex now decides by the holder's liveness.
- **Numeric settings were not validated**, though a comment claimed they were.
  `GATE_TIMEOUT=abc` silently removed the gate watchdog, `MIN_ANSWER_BYTES=$HOME`
  rejected every answer, `RALPHIE_MAX_COMMIT_BYTES=1MB` committed a 3 MiB blob.
  Every numeric setting now has a declared range, checked from `config.env` and
  from the environment. `0` still disables the streak limits that document it.
- **A bare Enter could buy a paid turn.** `/draft` was armed as `safe` while the
  class table called it spending; the `n` key ran an unvalidated line from a file
  inside the project; and `yes` fell through to ordinary conversation when the
  option it took failed, sending the word "yes" to the model as a turn.
- **One reply field could own the ledger.** An unbounded summary went verbatim
  into an event line and made the history decoder take minutes per cycle.
- **Gate changes between runs were invisible.** The gate set is fingerprinted per
  run; a change is warned and recorded. It is still your right to change them.
- **`status --json` could not tell "done" from "done and saved nothing".** Added
  `"commits"`. Every existing field keeps its meaning.
- **The ownership record was unsealed** while the list built from it was sealed,
  so one forged line dropped the operator's in-flight file out of protection.
  It is sealed with the cycle's snapshot and re-checked before any commit.
- **A live chat's lock could be stolen** in the instant before its pid appeared.
- **The retreat note ordered "Report status: progress"** even to an engine that
  had just reported blocked with a real question, which made the documented
  hand-over to a human unreachable. It now states the exception.
- Replacing `.ralphie/state` with a directory hid the schema stamp, and the
  repair ran first: that is now reported instead of passing as a new project.
- A state-file repair wrote `key\nvalue` instead of `key=value`.

**What may surprise you**

- A junk numeric setting is now refused with a message, where it used to be
  applied and misbehave quietly.
- `watch --attach` without a terminal exits 2 instead of starting an agent.
- An engine reply containing more than one report block can no longer end a run.


---

## 4.1.0 — 2026-09-22

`watch` and `chat` became execution sockets to the engine, not parsed views.

- **`ralphie.sh watch` on a terminal attaches to the live steerer, unfettered**
  (`RALPHIE_WATCH_VIEW=engine`, the default). What you see is the engine's own
  TUI, nothing filtered or summarized. Ctrl-C (or the TUI's own exit) detaches
  and returns you to the ralphie console; the steerer keeps running. If no
  steerer is live, one is started first. `--attach`/`-a` forces it, `--follow`/
  `-f` keeps the humane parsed tail from 4.0.1, a non-terminal (pipe, CI) keeps
  the bounded snapshot, and `RALPHIE_WATCH_VIEW=ralphie` restores the old default.
- **Interactive `ralphie.sh chat` attaches the project's resident chat session**
  (`RALPHIE_CHAT_ENGINE=engine`, the default): a dedicated, per-project
  prime-agent conversation with its own tools and memory, booted once and kept
  alive between attaches. The full engine TUI runs; nothing is parsed. Exiting
  the TUI is caught by the harness and lands you back on the rails console.
  `chat --stop` ends that session. One-shot `chat "MESSAGE"`, a non-terminal
  chat, and `RALPHIE_CHAT_ENGINE=ralphie` all keep the 4.0.x rails chat.
- **The attach boundary is signal- and terminal-safe**: the standing `exit 130`
  INT trap is neutralized only while the TUI child runs, so Ctrl-C detaches
  instead of killing ralphie, and the terminal line discipline is saved before
  the attach and restored after it.
- **Fixed (4.0.1 regression): a chat lock was never released**, so every later
  chat in that project refused with "a chat is already open". 4.0.1 added a pid
  file inside the lock directory, and the release path still removed only
  `owner`, leaving `rmdir` to fail on a non-empty directory. The pid it left
  behind was the live shell's own, so the stale-lock recovery could not clear it
  either. Release now removes `owner` and `pid` together.
- **A stale proposal can no longer be approved by reflex**: slot 1 is always
  `/status`, reading the stale text is a separate numbered key (and is announced
  as gone when the record itself was invalidated), and redrafting `start`,
  `request` or `stop` is typed by hand under a warning — never an armed key.


---

## 4.0.1 — 2026-09-22

Chat works anytime. `watch --follow` is a live, humane tail of the engine dialog.

- **Chat opens even after a closed terminal** (.ralphie/chat/lock): a stale lock is
  detected by pid liveness and recovered with a warning; a genuinely live chat still
  refuses, naming the live pid.
- **`ralphie.sh watch --follow [ID]`** (and `-f`): a live, humane tail of the engine's
  dialog, tail -f style until Ctrl-C. Thinking is abbreviated (`[thinking ...]`,
  full text with RALPHIE_DIALOG_THINKING=1), tool calls shown as one line, tool
  results truncated. The full transcript always remains in .ralphie/run/sessions.


---

## 4.0.0 — unreleased

The loop learned to stop. v3.1.0 could work, verify, commit and remember, but on a
project with no gate it could not finish, and when the engine said "I cannot
proceed" it bought another full-price cycle to be told the same thing again. This
release makes both of those terminal, adds a resident agent that can drive and
watch a run, puts the operator conversation on rails, makes `/follow` show the
engine's real dialog, and lets a stuck loop change its approach instead of
repeating itself.

### Why this is a major version

`--help` promises exit codes "so cron and CI can react without parsing text". That
promise is a compatibility contract, and this release changes it. Exit code `2`
now covers two outcomes it never covered before, `status` gained a new terminal
value, and a run that previously spent its whole budget may now stop on cycle 1.
Any wrapper that reads those is affected. A minor bump would hide that.

### BEHAVIOUR CHANGES — read these before upgrading

1. **A gateless project can now finish, and it stops early.**
   When the engine reports `done` on a project with **no gate**, and Ralphie's own
   checks are in order, the run now stops after `CONSENSUS_LIMIT` (default 2)
   consecutive identical reports. It records `status=unverified`, writes an
   explanation to `ASK.md`, and **exits 2**.
   It is never called `done`, never counted as a green cycle, never exits 0.
   *Before:* `completion_ready()` required a passing gate, so `done` could not end
   the loop and the whole budget was spent committing work nothing checked.
   *If you relied on the old behaviour:* set `CONSENSUS_LIMIT=0`. Better: add one
   real command to `.ralphie/gates` and get a verified result instead.

2. **`blocked` is terminal.**
   When the engine reports `blocked` **and names a question in `ask:`** for
   `CONSENSUS_LIMIT` (default 2) consecutive cycles, the run stops with
   `status=blocked` and **exits 2**. A `blocked` report with no question still
   does not stop anything — an engine that cannot say what a human should decide
   has not met the contract.
   *Before:* `blocked` logged an event, returned 0, and bought another cycle.
   *If you relied on the old behaviour:* `CONSENSUS_LIMIT=0`.

3. **Exit code `2` means more than it did.**
   *Before:* "blocked: no engine could complete a cycle."
   *Now:* "stopped early and needs you" — no engine could complete a cycle, **or**
   the engine repeated that it cannot proceed, **or** it repeated that the work is
   finished on a project with no gate that could check it.
   None of these is verified and none is a pass. A cron wrapper that retried on
   `2` will now retry a finished objective; read `status --json` to tell them
   apart.

4. **`status` has a new terminal value: `unverified`.**
   It appears in `.ralphie/state`, in `status`, in `status --json` and in the
   final console line (`stopped, NOT VERIFIED: ...`). Anything that switches on
   the status string needs a branch for it. `done` still means, and only means,
   real gates passed.

5. **A capable engine now self-drives on a gateless project.**
   `cycle_act` no longer requires `gates_count > 0` before it asks an engine with
   `autonomy` + `gates` to drive itself. A greenfield project therefore gets
   autonomous mode, not one-shot mode — different engine argv, different prompt,
   a longer and more expensive call, and subagents that stay alive.
   *Before:* a project with no gate silently dropped to one-shot mode, which is
   also the mode that kills a harness engine's children when it pauses.

6. **A cycle may now make two engine calls.**
   If the engine ends its turn without finishing — "I'll pause here and resume
   when the workers report back", with no report block — Ralphie resumes the
   **same** session with a short continuation prompt. Bounded by the new
   `ENGINE_CONTINUE_MAX` (default `1`; `0` disables). Worst-case per-cycle engine
   cost therefore doubles. Both halves are recorded (`engine paused`,
   `engine continued`).

7. **Chat is on rails, and bare words now do things.**
   Every chat turn ends with one `[Next]` block. `yes` or Enter takes the default,
   `1`–`4` take an alternative, `n` declines. `answer`, `status`, `jobs`, `watch`,
   `follow`, `gates`, `proposal`, `cancel`, `help` and `quit` now work **without**
   the leading slash, so a message that was previously discussion text may now run
   a command. `start`, `stop` and `run` deliberately still require the slash.
   A default that spends money or stops work names its consequence and is never
   taken by a bare Enter.
   *Restore the old chat exactly:* `RALPHIE_RAILS=0`. Rails are local string
   matching and cost no tokens.

8. **`/follow` shows the engine, not the console.**
   `/follow`, `/attach` and `/watch --follow` now render the engine's own dialog
   as clean live text, read from the session transcript Ralphie already asks
   prime-agent to keep, advanced by byte offset.
   *Before:* they refreshed snapshots of `output.log`, which is capped at 1 MiB —
   so the window froze permanently once a worker passed the cap.
   *Fallback:* with no transcript (another engine, `RALPHIE_ENGINE_SESSION=0`, or
   no `python3`) it says so once and uses the old console snapshots.
   `/watch` without `--follow` is unchanged: still one bounded snapshot.

9. **A stuck loop changes its approach, and can now stop for circling.**
   New `retreat` ladder: `attack -> plan -> reframe`, applied as a
   `## CHANGE OF APPROACH` section in the prompt when the **same failure** repeats
   (`STAGNATION_LIMIT`, default 2). A new stop fires when Ralphie crosses the same
   pair of approaches `OSCILLATION_LIMIT` times (default 6, three full laps)
   against an unchanging failure — `status=stalled`, **exit 3**.
   Retreat never stops a run and never prevents one from stopping: `NOCHANGE_LIMIT`,
   `CONSENSUS_LIMIT` and `done` are all decided first. `RETREAT_LIMIT=0` turns it
   off; exit 3 previously only ever meant "no change".

10. **A refused commit no longer makes completion impossible.**
    A path Ralphie refuses to commit — a secret, a build artefact, an oversize
    file, a symlink escaping the repo — no longer counts as "unsaved work" that
    blocks completion. Measured: a project whose engine drops one `.pyc` every
    cycle used to burn 4 cycles and exit 3 `stalled`; it now finishes in 1 cycle.
    *This can complete a run that previously stalled.* The refusal is still
    reported, and the file is still not committed.

### Added

- `ralphie.sh steerer <start|status|attach|logs|tell|stop>` — a **resident agent**
  that kicks the run off, receives selected ledger events, and talks to you. Hosted
  by `prime-agent` or `claude`. Entirely optional: with none running the loop
  behaves exactly as before (two shell tests and a return inside `event`).
  Knobs: `RALPHIE_STEERER_ENGINE`, `RALPHIE_STEERER_MODEL`,
  `RALPHIE_STEERER_EVENTS`, `RALPHIE_STEERER_WAIT`, `RALPHIE_STEERER_PROMPT`,
  `RALPHIE_STEERER_MAILBOX_MAX`.
- `ralphie.sh engine-doctor` — asserts that an installed engine really accepts the
  flags Ralphie passes it, against the binary that is actually installed. Written
  because `prime-agent help send` advertises `--steer` and `--follow-up` and the
  binary rejects both. Run it after upgrading an engine.
- Chat: `/answer N TEXT`, `/answer`, `/gates`, `/draft`, and the bare-verb and
  `yes`/`n`/`1`-`4` shortcuts.
- Live dialog knobs: `RALPHIE_DIALOG_THINKING`, `RALPHIE_DIALOG_ARG_CHARS`,
  `RALPHIE_DIALOG_RESULT_CHARS`, `RALPHIE_DIALOG_TAIL_BYTES`.
- Loop knobs: `CONSENSUS_LIMIT`, `RETREAT_LIMIT`, `STAGNATION_LIMIT`,
  `OSCILLATION_LIMIT`, `ENGINE_CONTINUE_MAX`, `RALPHIE_RAILS`.
- Ledger events: `engine halted`, `engine paused`, `engine continued`,
  `steerer started|stopped|failed`.
- State keys: `consensus_claim`, `consensus_streak`, `retreat_level`,
  `stagnation_sig`, `stagnation_streak`, `retreat_pair`, `retreat_pair_count`.
  All seven are added to `STATE_KEYS`; `state_set` silently drops anything absent
  from that list, so a third-party patch that adds a key must add it there too.

### Changed

- `cycle_act` chooses autonomous mode from the engine's declared capabilities
  alone (see behaviour change 5).
- `--help` documents 59 environment knobs; every one is read by the script and
  every knob the script reads is documented, both directions verified.
- The final console line distinguishes `done`, `stalled`, `blocked`, `unverified`
  and `paused`.

### Unchanged, on purpose

- `completion_ready()` is byte-identical. Real gates are still the only thing that
  can promote work, write `done`, count a green cycle or exit 0.
- `answer_is_usable`, `parse_report`, `engine_build`, `engine_invoke`,
  `watchdog_wait`, `ENGINE_TABLE`, `worker_capture` and the `ENGINE_OUTPUT_MAX_BYTES`
  ceiling.
- The one-file, `bash 3.2` + coreutils + `git` + `ps` core. `python3` is used only
  by optional features and every one of them degrades honestly without it.
  (`ps` was always required and has no fallback — `descendants_of` is the only
  way Ralphie finds what a timed-out gate left behind. It was simply never
  written down. README and AGENTS now say so. Nothing about it changed here.)

### Upgrade checklist

```bash
./ralphie.sh engine-doctor      # your engine's flags, measured not assumed
./ralphie.sh --help             # the knob list is the contract
grep -n 'exit 2' your-cron-wrapper
```

If you script Ralphie, decide what you want from `CONSENSUS_LIMIT` before you
upgrade. The honest answer for most projects is to leave it at 2 and add a gate.

---

## 3.1.0 — 2026-09-21

Supervisor chat sessions, worker following, terminal controls, spec input,
ongoing operator requests, engine output limits, objective acceptance.

## 3.0.0 — 2026-09-18

Rewrite as a capability-complement autonomy kernel
(`ralphie = required_autonomy - engine_native_capability`). Seven layers, one
file, gates as the only definition of success.

## 2.0.0 — 2026-05-26

The previous generation: persona panels, consensus voting, ~10,000 lines.
