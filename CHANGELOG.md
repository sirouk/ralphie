# Changelog

All notable changes to `ralphie.sh`. Versions follow semantic versioning applied to
the two interfaces a script can depend on: **exit codes** and `status --json`.

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
