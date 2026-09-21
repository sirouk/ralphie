# Graph Report - ralphy-baby  (2026-09-20)

## Corpus Check
- Corpus is ~38,351 words - fits in a single context window. You may not need a graph.

## Summary
- 864 nodes · 2904 edges · 44 communities
- Extraction: 90% EXTRACTED · 9% INFERRED · 0% AMBIGUOUS · INFERRED: 272 edges (avg confidence: 0.5)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Engine / Interface
- Human / Ledger
- Interface
- Project
- Loop / Human
- Core
- Ledger / Loop
- Project / Loop
- Loop
- Project
- Project
- Shared interfaces
- Engine / Ledger
- Loop
- Loop / Ledger
- Core
- Loop / Project
- Project
- Ledger / Interface
- Ledger / Project
- Core / Interface
- Interface / Ledger
- Interface
- Project / Core
- Project / Interface
- Ledger / Core
- Project
- Project
- Ledger
- Interface / Loop
- Project / Core
- Human
- Project
- Engine / Ledger
- Project
- Project
- Project
- Human / Core
- Interface
- Project
- Ledger / Engine
- Interface
- Project
- Ledger

## God Nodes (most connected - your core abstractions)
1. `Bootstrap and script entry` - 119 edges
2. `parse_args()` - 84 edges
3. `event()` - 67 edges
4. `PROJECT` - 63 edges
5. `PROJECT` - 58 edges
6. `cycle_begin()` - 50 edges
7. `run_prepare()` - 50 edges
8. `state_set()` - 48 edges
9. `cycle_observe()` - 43 edges
10. `cycle_act()` - 43 edges

## Surprising Connections (you probably didn't know these)
- `project_bind()` --interface_evidence_overlaps--> `Project-local persistence and evidence paths`  [INFERRED]
  ralphie.sh → ralphie.sh  _Bridges community 15 → community 13_
- `warn()` --interface_evidence_overlaps--> `console`  [INFERRED]
  ralphie.sh → ralphie.sh  _Bridges community 30 → community 20_
- `err()` --interface_evidence_overlaps--> `console`  [INFERRED]
  ralphie.sh → ralphie.sh  _Bridges community 24 → community 20_
- `die()` --interface_evidence_overlaps--> `console`  [INFERRED]
  ralphie.sh → ralphie.sh  _Bridges community 1 → community 20_
- `event()` --interface_evidence_overlaps--> `ledger human`  [INFERRED]
  ralphie.sh → ralphie.sh  _Bridges community 14 → community 18_

## Import Cycles
- None detected.

## Communities (44 total, 0 thin omitted)

### Community 0 - "Engine / Interface"
Cohesion: 0.06
Nodes (66): tr, "$t", "$e", RALPHIE_ENGINE_ANSWER, RALPHIE_ENGINE_CAPS, RALPHIE_ENGINE_CMD, RALPHIE_ENGINE_SESSION, custom command (+58 more)

### Community 1 - "Human / Ledger"
Cohesion: 0.07
Nodes (60): mkdir, mv, ps, wc, RALPHIE_ANSWER, run lock, Commands, callbacks and mutable executable inputs, Immutable publication and cycle-boundary request consumption (+52 more)

### Community 2 - "Interface"
Cohesion: 0.04
Nodes (48): --, --accept, --branch, --cycles, --done-when-green, --engine, --gate, --help (+40 more)

### Community 3 - "Project"
Cohesion: 0.08
Nodes (36): chmod, dirname, readlink, eval "_gsnap_$snap_n=\$g", eval "g=\$_gsnap_$n", eval "g=\$_gsnap_$i", eval "g=\$_gsnap_$i", gate baseline and snapshot (+28 more)

### Community 4 - "Loop / Human"
Cohesion: 0.14
Nodes (32): awk, head, Engine final report, LOOP, asks_open(), backlog_items(), build_prompt(), commit_message() (+24 more)

### Community 5 - "Core"
Cohesion: 0.13
Nodes (26): cksum, date, od, openssl, sha256sum, shasum, budget, clock random digest (+18 more)

### Community 6 - "Ledger / Loop"
Cohesion: 0.11
Nodes (27): find, sort, freshness paths, git fingerprint io, "$HOME_DIR/run", acceptance_work_fingerprint(), find_changed_since(), fingerprint() (+19 more)

### Community 7 - "Project / Loop"
Cohesion: 0.12
Nodes (26): git, RALPHIE_GIT_INIT, git discovery, git init config, git refs, commit_head(), dirty_paths_nul(), ensure_git() (+18 more)

### Community 8 - "Loop"
Cohesion: 0.20
Nodes (26): Shared proof, triggers and outcome ordering, acceptance_done(), cache_verdict(), completion_ready(), cycle_observe(), cycle_record(), record_nochange(), record_outcome() (+18 more)

### Community 9 - "Project"
Cohesion: 0.12
Nodes (25): ownership files, nul_list_has(), pre_dirty_count(), pre_dirty_has(), pre_dirty_intact(), pre_dirty_seal(), release_owned_paths(), warn_protected_unsaved() (+17 more)

### Community 10 - "Project"
Cohesion: 0.12
Nodes (24): exec git commit -q -m "$msg", git commit, git execution policy, git private index, build_commit_index(), git_commit_cycle(), git_top(), index_holds_our_work_only() (+16 more)

### Community 11 - "Shared interfaces"
Cohesion: 0.09
Nodes (23): exec env RALPHIE_NO_UPDATE=1 "$_rb_target" "$@", NO_COLOR, RALPHIE_AUTO_UPDATE, RALPHIE_BRANCH, RALPHIE_MODEL, RALPHIE_QUIET, RALPHIE_THINKING, RALPHIE_VERBOSE (+15 more)

### Community 12 - "Engine / Ledger"
Cohesion: 0.12
Nodes (22): basename, mktemp, exec "$@", TMPDIR, engine execution, engine_invoke(), ensure_own_file(), retain_engine_output() (+14 more)

### Community 13 - "Loop"
Cohesion: 0.16
Nodes (22): Project-local persistence and evidence paths, Objective, acceptance and request identities are distinct, Keys read or written by the reviewed lifecycle, acceptance_bind(), acceptance_error(), acceptance_intact(), acceptance_latest(), acceptance_note_work() (+14 more)

### Community 14 - "Loop / Ledger"
Cohesion: 0.13
Nodes (21): event format, Status fields and process exit meanings, budget_stop(), cycle_once(), event(), guard_objective(), json_str(), loop() (+13 more)

### Community 15 - "Core"
Cohesion: 0.13
Nodes (20): RALPHIE_PROJECT, project selection, runtime primary paths, "$HOME_DIR/events.jsonl", "$HOME_DIR/gates", "$PROJECT/.ralphie", "$HOME_DIR/lock", "$HOME_DIR/log" (+12 more)

### Community 16 - "Loop / Project"
Cohesion: 0.18
Nodes (20): acceptance_verify(), check_gates(), cycle_act(), cycle_begin(), cycle_guard_inputs(), cycle_verify(), 2>/dev/null, 2>/dev/null (+12 more)

### Community 17 - "Project"
Cohesion: 0.20
Nodes (19): grep, node, python3, project tool selection, root manifests, gate_candidates(), has_make_target(), has_make_target() [L999] (+11 more)

### Community 18 - "Ledger / Interface"
Cohesion: 0.16
Nodes (19): rmdir, tail, state format, state write temporaries, ledger human, "$HOME_DIR/state", ensure_state_file(), json_dec() (+11 more)

### Community 19 - "Ledger / Project"
Cohesion: 0.17
Nodes (18): pgrep, exec "$GATE_SH" -c "$GATE_PRELUDE$cmd", process hygiene, child_pids_of(), gate_exec(), kill_tree(), track_pid(), untrack_pid() (+10 more)

### Community 20 - "Core / Interface"
Cohesion: 0.24
Nodes (18): console, cmd_doctor(), dbg(), dim(), good(), info(), is_true(), return_to_base_branch() (+10 more)

### Community 21 - "Interface / Ledger"
Cohesion: 0.21
Nodes (18): recovery scratch, cmd_status(), rebuild_state_from_ledger(), status_json(), > "$all", 2>/dev/null, 2>/dev/null, blocked_count (+10 more)

### Community 22 - "Interface"
Cohesion: 0.13
Nodes (17): bash, curl, wget, RALPHIE_LIB, RALPHIE_MIN_UPDATE_BYTES, RALPHIE_NO_UPDATE, All 15 recognized command spellings, Public environment and standard-shell context (+9 more)

### Community 23 - "Project / Core"
Cohesion: 0.17
Nodes (17): gate outcome globals, gate retry and capture, gate_failure_brief(), run_gates(), tail_of(), 2>/dev/null, >> "$logbase.summary", > "$logbase.summary" (+9 more)

### Community 24 - "Project / Interface"
Cohesion: 0.15
Nodes (17): err(), prepare_gates(), run_prepare(), self_is_reviewed(), use_branch(), warn_detached_head(), >/dev/null, >> "$GATES_FILE" (+9 more)

### Community 25 - "Ledger / Core"
Cohesion: 0.15
Nodes (16): RALPHIE_KEEP_CYCLES, RALPHIE_KEEP_RUNS, RALPHIE_LEDGER_GENERATIONS, RALPHIE_LEDGER_MAX, ledger retention, run scratch and retention, human_secs(), is_int() (+8 more)

### Community 26 - "Project"
Cohesion: 0.14
Nodes (16): git index, resync_operator_index(), snapshot_pre_dirty(), < "$raw", > "$OPERATOR_STAGED", < "$committed", > "$raw", >> "$PRE_DIRTY_FILE" (+8 more)

### Community 27 - "Project"
Cohesion: 0.16
Nodes (15): ls, discovery git overrides, discovery report, PROJECT, cmd_discover(), detect_stack(), discover_candidates(), discover_git() (+7 more)

### Community 28 - "Ledger"
Cohesion: 0.26
Nodes (14): signal contract, LEDGER, install_traps(), on_exit(), on_int(), on_pipe(), reap_children(), 2>/dev/null (+6 more)

### Community 29 - "Interface / Loop"
Cohesion: 0.27
Nodes (13): cat, cp, sed, touch, INTERFACE, cmd_forget(), cmd_gates(), cmd_log() (+5 more)

### Community 30 - "Project / Core"
Cohesion: 0.22
Nodes (13): human questions, baseline_gates_load(), discover_gates(), ensure_gates_file(), warn(), >&2, > "$tmp", < "$GATES_BASELINE_FILE" (+5 more)

### Community 31 - "Human"
Cohesion: 0.18
Nodes (12): sh, RALPHIE_MESSAGE, RALPHIE_NOTIFY_CMD, RALPHIE_NOTIFY_WAIT, Noninteractive human channel, ask_human(), notify(), 2>&1 (+4 more)

### Community 32 - "Project"
Cohesion: 0.20
Nodes (12): git history validation, git path filter, engine_history_is_safe(), project_prefix(), > "$paths", 2>/dev/null, < "$paths", 2>/dev/null (+4 more)

### Community 33 - "Engine / Ledger"
Cohesion: 0.25
Nodes (11): cut, usage python, read_engine_usage(), run_init(), 2>/dev/null, 2>/dev/null, run_cost, run_id (+3 more)

### Community 34 - "Project"
Cohesion: 0.24
Nodes (11): owned_has(), path_fingerprint(), record_owned_paths(), < "$tmp", < "$OWNED_FILE", > "$tmp", 2>/dev/null, < "$path" (+3 more)

### Community 35 - "Project"
Cohesion: 0.27
Nodes (10): self file, "$(cd "$_self_dir" 2>/dev/null && pwd -P)/$_self_name", self_hash_check(), self_hash_record(), 2>/dev/null, < "$SELF", < "$SELF", 2>/dev/null (+2 more)

### Community 36 - "Project"
Cohesion: 0.22
Nodes (9): RALPHIE_MAX_COMMIT_BYTES, unstage_risky(), 2>&1, < "$staged", > "$staged", 2>/dev/null, BULK_PATHS, RALPHIE_MAX_COMMIT_BYTES (+1 more)

### Community 37 - "Human / Core"
Cohesion: 0.25
Nodes (8): "$@", "$HOME_DIR/ASK.md", asks_open_count(), count_of(), ensure_ask_file(), gates_count(), 2>/dev/null, ASK_FILE

### Community 38 - "Interface"
Cohesion: 0.25
Nodes (8): All 22 option families and positional parsing, load_spec(), need_value(), < "$SPEC_FILE", >/dev/null, CMD, OBJECTIVE_EXPLICIT, SPEC_FILE

### Community 39 - "Project"
Cohesion: 0.29
Nodes (7): rm, gate evidence outputs, gate runtime, gate timeouts, gate_tool_names(), gate_trial(), 2>/dev/null

### Community 40 - "Ledger / Engine"
Cohesion: 0.33
Nodes (7): sleep, engine environment, engine output, terminate_tree(), watchdog_wait(), 2>/dev/null, 2>/dev/null

### Community 41 - "Interface"
Cohesion: 0.40
Nodes (5): RALPHIE_UPDATE_URL, looks_like_typo(), update_url(), 2>/dev/null, ME

### Community 42 - "Project"
Cohesion: 0.40
Nodes (5): git operation markers, commit_is_permitted(), 2>/dev/null, COMMIT_SKIPPED, GIT_MODE

### Community 43 - "Ledger"
Cohesion: 0.50
Nodes (4): git local exclude, ensure_ignored(), 2>/dev/null, >> "$ex"

## Ambiguous Edges - Review These
- `gate_candidates()` → `has_make_target()`  [AMBIGUOUS]
  ralphie.sh · relation: calls
- `gate_candidates()` → `has_make_target() [L999]`  [AMBIGUOUS]
  ralphie.sh · relation: calls
- `gate_candidates()` → `has_npm_script()`  [AMBIGUOUS]
  ralphie.sh · relation: calls
- `gate_candidates()` → `has_npm_script() [L995]`  [AMBIGUOUS]
  ralphie.sh · relation: calls

## Knowledge Gaps
- **351 isolated node(s):** `BOOTSTRAP`, `exec env RALPHIE_NO_UPDATE=1 "$_rb_target" "$@"`, `sha256sum`, `shasum`, `openssl` (+346 more)
  These have ≤1 connection - possible missing edges or undocumented components.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `gate_candidates()` and `has_make_target()`?**
  _Edge tagged AMBIGUOUS (relation: calls) - confidence is low._
- **What is the exact relationship between `gate_candidates()` and `has_make_target() [L999]`?**
  _Edge tagged AMBIGUOUS (relation: calls) - confidence is low._
- **What is the exact relationship between `gate_candidates()` and `has_npm_script()`?**
  _Edge tagged AMBIGUOUS (relation: calls) - confidence is low._
- **What is the exact relationship between `gate_candidates()` and `has_npm_script() [L995]`?**
  _Edge tagged AMBIGUOUS (relation: calls) - confidence is low._
- **Why does `run_gates()` connect `Project / Core` to `Engine / Interface`, `Human / Ledger`, `Project`, `Core`, `Human / Core`, `Project`, `Loop`, `Loop / Ledger`, `Ledger / Interface`, `Ledger / Project`, `Core / Interface`, `Project / Core`?**
  _High betweenness centrality (0.076) - this node is a cross-community bridge._
- **Why does `GATES_FILE_BROKEN` connect `Engine / Ledger` to `Project / Core`?**
  _High betweenness centrality (0.070) - this node is a cross-community bridge._
- **Why does `ensure_own_file()` connect `Engine / Ledger` to `Project`, `Project`, `Loop / Ledger`, `Core / Interface`, `Project / Interface`, `Project / Core`?**
  _High betweenness centrality (0.068) - this node is a cross-community bridge._
## Scope and measurement limits

This graph is bound to source SHA-256 `c21744b635e3b640aa6d65b6c36daa7dc0d8e1e90b7bf45fb09f8937055aa905`. All 234 Bash definitions are indexed and reviewed, including subshell overrides and the nested archive function. Calls are possible static routes, not observed execution. Shared variable edges are lexical, not a claim of unique runtime storage. Arbitrary gate/engine/hook programs remain open interfaces.

The zero token figure above covers deterministic extraction only. Host-agent and delegated source-review tokens are unavailable through these tools; total analysis tokens and monetary cost are unknown, not zero.
