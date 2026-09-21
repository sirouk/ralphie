# Function catalogue

Pinned source SHA-256: `c21744b635e3b640aa6d65b6c36daa7dc0d8e1e90b7bf45fb09f8937055aa905`. All 234 definitions, including the nested archive function and both preview-only overrides.

Each function links to the frozen source. Full inputs, outputs, side effects, failures and callbacks are in [function-inventory.json](function-inventory.json) and the detailed reviews: [core/ledger/gates](core_ledger_gates.review.md), [Git/engines](git_engine.review.md), [loop/human/interface](loop_human_interface.review.md).


## CORE

| Function | Lines | Responsibility |
|---|---:|---|
| [`project_bind`](source.html#L106) | 106–120 | Resolve the selected project physically and bind every primary runtime path once. |
| [`terminal_printf`](source.html#L140) | 140–148 | Print to stdout and translate a failed pipe write into the SIGPIPE cleanup protocol. |
| [`say`](source.html#L149) | 149–149 | Print one uncolored line through the pipe-aware output helper. |
| [`info`](source.html#L153) | 153–153 | Print an informational colored line unless quiet mode is true. |
| [`good`](source.html#L154) | 154–154 | Print a success-colored line. |
| [`warn`](source.html#L155) | 155–155 | Print a warning-colored line to stderr. |
| [`err`](source.html#L156) | 156–156 | Print an error-colored line to stderr. |
| [`dim`](source.html#L157) | 157–157 | Print a dim line unless quiet mode is true. |
| [`dbg`](source.html#L158) | 158–158 | Print a debug line to stderr only when verbosity is true. |
| [`die`](source.html#L159) | 159–159 | Report a prefixed fatal message and exit. |
| [`now_iso`](source.html#L161) | 161–161 | Emit the current UTC timestamp for ledger records. |
| [`now_epoch`](source.html#L162) | 162–162 | Emit the current epoch second. |
| [`stamp`](source.html#L163) | 163–163 | Emit a UTC timestamp suitable for a run identifier. |
| [`have`](source.html#L166) | 166–166 | Check whether command resolution can find a name. |
| [`sha_of`](source.html#L168) | 168–177 | Hash stdin using the first available supported digest tool. |
| [`timeout_cmd`](source.html#L179) | 179–185 | Return the available GNU timeout command name or an empty line. |
| [`rand_token`](source.html#L187) | 187–194 | Generate a small run/lock token. |
| [`json_escape`](source.html#L196) | 196–201 | Escape textual stdin for a JSON string body. |
| [`json_str`](source.html#L203) | 203–203 | Escape a single argument as a JSON string body. |
| [`is_int`](source.html#L205) | 205–205 | Recognize a nonempty unsigned decimal digit string. |
| [`is_true`](source.html#L206) | 206–206 | Recognize common case-insensitive true values. |
| [`trim`](source.html#L208) | 208–208 | Trim leading and trailing whitespace from an argument. |
| [`tail_of`](source.html#L211) | 211–211 | Read a bounded tail of an existing regular file. |
| [`secs_since`](source.html#L213) | 213–213 | Compute elapsed seconds from an epoch value. |
| [`file_bytes`](source.html#L215) | 215–225 | Return a regular file byte count or zero. |
| [`count_of`](source.html#L227) | 227–234 | Count stdout lines from an arbitrary supplied command. |
| [`human_secs`](source.html#L236) | 236–242 | Format a duration in seconds, minutes or hours. |
| [`budget_left`](source.html#L251) | 251–259 | Compute remaining time under the absolute run deadline. |
| [`budget_expired`](source.html#L261) | 261–264 | Test whether an active run budget is exhausted. |
| [`budget_cap`](source.html#L266) | 266–279 | Clamp a requested timeout to the remaining run budget. |

## LEDGER

| Function | Lines | Responsibility |
|---|---:|---|
| [`state_get`](source.html#L296) | 296–301 | Read the last stored value for a key, or a supplied default. |
| [`state_set`](source.html#L303) | 303–343 | Replace one allowlisted state key using a directory mutex and temporary file. |
| [`state_bump`](source.html#L345) | 345–349 | Increment a state counter through the common writer. |
| [`event`](source.html#L351) | 351–381 | Append one textual JSON event and update the last-write timestamp. |
| [`ensure_dirs`](source.html#L383) | 383–388 | Create the three runtime directories on demand. |
| [`ensure_own_file`](source.html#L390) | 390–460 | Repair or report an unusable Ralphie-owned file without rejecting the caller. |
| [`ensure_state_file`](source.html#L462) | 462–470 | Apply common owned-file repair to the state path. |
| [`rebuild_state_from_ledger`](source.html#L472) | 472–517 | Reconstruct cycle counters and cycle elapsed time from retained event generations. |
| [`ledger_init`](source.html#L519) | 519–546 | Initialize/repair shared runtime storage without claiming ownership of a run. |
| [`run_init`](source.html#L548) | 548–564 | Start run-owned bookkeeping and remove stale per-PID scratch files. |
| [`ensure_ignored`](source.html#L567) | 567–585 | Exclude Ralphie runtime storage using local Git exclusion metadata. |
| [`prune_artifacts`](source.html#L587) | 587–612 | Prune old numbered cycle artifacts and then consider ledger rotation. |
| [`rotate_ledger`](source.html#L614) | 614–638 | Rotate an oversized current ledger into bounded numbered generations. |
| [`prune_sessions`](source.html#L640) | 640–652 | Delete oldest lexical session-directory entries beyond retention. |
| [`mark_tree`](source.html#L654) | 654–654 | Touch the work-change timestamp marker. |
| [`tree_listing_digest`](source.html#L656) | 656–668 | Digest the sorted set of non-noise regular-file pathnames. |
| [`mark_verify`](source.html#L670) | 670–674 | Record the current verification marker and file-set digest. |
| [`verify_mark_stale`](source.html#L676) | 676–683 | Tell callers whether filesystem evidence invalidates a cached verdict. |
| [`find_changed_since`](source.html#L697) | 697–705 | List regular project files newer than a supplied marker. |
| [`tree_touched`](source.html#L707) | 707–716 | Check the work-change marker for any newer non-noise regular file. |
| [`work_changed`](source.html#L718) | 718–725 | Combine the Git/runtime fingerprint with filesystem modification evidence. |
| [`fingerprint`](source.html#L730) | 730–742 | Digest Git-visible state together with gate and objective bytes. |
| [`lock_acquire`](source.html#L748) | 748–799 | Acquire the per-project run lock and reject an apparently live owner. |
| [`lock_release`](source.html#L802) | 802–802 | Release the lock when this process records ownership. |
| [`track_pid`](source.html#L809) | 809–809 | Add a child PID to the in-memory cleanup list. |
| [`untrack_pid`](source.html#L810) | 810–810 | Remove a child PID from the cleanup list. |
| [`child_pids_of`](source.html#L812) | 812–822 | Find direct children of a PID using available process tools. |
| [`kill_tree`](source.html#L824) | 824–829 | Recursively signal a process and its currently visible descendants. |
| [`terminate_tree`](source.html#L831) | 831–847 | Snapshot descendants, send TERM, then send KILL after a grace period. |
| [`reap_children`](source.html#L849) | 849–859 | Terminate tracked children that still appear live. |
| [`on_exit`](source.html#L863) | 863–886 | Perform EXIT cleanup while preserving run/error bookkeeping and SIGPIPE status. |
| [`on_int`](source.html#L888) | 888–903 | Stop an interrupted run and exit with conventional interrupt status. |
| [`on_pipe`](source.html#L904) | 904–911 | Retire a broken stdout pipe without exiting inside the signal trap. |
| [`install_traps`](source.html#L912) | 912–916 | Register the shared exit, interrupt and pipe callbacks. |

## PROJECT

| Function | Lines | Responsibility |
|---|---:|---|
| [`pkg_manager`](source.html#L930) | 930–936 | Choose a JavaScript package manager from root lockfile presence. |
| [`has_npm_script`](source.html#L938) | 938–951 | Check a root package script using an available JSON parser or a loose text fallback. |
| [`has_make_target`](source.html#L953) | 953–956 | Look for an explicitly written Make target in root Makefiles. |
| [`py_runner`](source.html#L958) | 958–967 | Choose a command prefix for a Python project tool. |
| [`detect_stack`](source.html#L969) | 969–990 | Infer a space-separated stack tag list from root metadata. |
| [`discover_candidates`](source.html#L994) | 994–1008 | Preview candidate gate text using subshell-local text-only manifest helpers. |
| [`has_npm_script`](source.html#L995) | 995–998 | Preview a possible package script through a readable-file text match. |
| [`has_make_target`](source.html#L999) | 999–1006 | Preview a Make target while skipping absent or unreadable Makefiles. |
| [`discover_git`](source.html#L1013) | 1013–1020 | Run the limited discovery Git query with selected execution/network side effects disabled. |
| [`cmd_discover`](source.html#L1022) | 1022–1079 | Print a project discovery report without starting a run. |
| [`gate_candidates`](source.html#L1081) | 1081–1141 | Emit root-level candidate health commands for recognized project stacks. |
| [`gate_tool_names`](source.html#L1179) | 1179–1189 | Extract simple tool names used to recognize unavailable-candidate errors. |
| [`gate_exec`](source.html#L1192) | 1192–1211 | Execute one gate in the selected shell with capture, deadline and process cleanup. |
| [`gate_trial`](source.html#L1213) | 1213–1249 | Run a candidate and reject unavailable tools while retaining ordinary failing checks. |
| [`discover_gates`](source.html#L1251) | 1251–1310 | Discover and persist gate commands when no gate file exists or redetection is explicit. |
| [`gates_list`](source.html#L1312) | 1312–1316 | List active configured gate command lines. |
| [`gates_count`](source.html#L1320) | 1320–1320 | Count active configured gates safely. |
| [`run_gates`](source.html#L1322) | 1322–1422 | Measure the configured gates and record bounded per-gate evidence. |
| [`ensure_gates_file`](source.html#L1425) | 1425–1437 | Check gate-path containment before applying owned-file repair. |
| [`baseline_gates_load`](source.html#L1439) | 1439–1474 | Restore gate commands missing from the previous-run baseline. |
| [`baseline_gates_save`](source.html#L1476) | 1476–1479 | Persist the current active gate set as the cross-run baseline. |
| [`snapshot_gates`](source.html#L1482) | 1482–1508 | Grow the in-memory run gate set and write a diagnostic snapshot. |
| [`check_gates`](source.html#L1510) | 1510–1516 | Run the gate guard and preserve tamper evidence for the whole cycle. |
| [`resolve_link`](source.html#L1518) | 1518–1534 | Follow a leaf symlink chain with a bounded hop count. |
| [`gate_path_inside_project`](source.html#L1536) | 1536–1545 | Determine whether the physically resolved gate parent is inside the physical project root. |
| [`restore_gate_order`](source.html#L1547) | 1547–1624 | Merge missing snapshot commands back into their original order while retaining current comments and additions. |
| [`guard_gates`](source.html#L1626) | 1626–1677 | Detect missing remembered gate commands, restore them if possible, and flag the cycle as tampered. |
| [`gate_failure_brief`](source.html#L1679) | 1679–1693 | Format a bounded prompt-ready explanation of the first recorded gate failure. |
| [`git_ready`](source.html#L1697) | 1697–1702 | Ask Git whether PROJECT belongs to a repository, including worktrees and submodules. |
| [`ensure_git`](source.html#L1704) | 1704–1710 | Keep an existing repository or initialize one when allowed. |
| [`git_identity`](source.html#L1712) | 1712–1718 | Supply repository-local author defaults only when Git cannot resolve existing identity. |
| [`git_dirty`](source.html#L1720) | 1720–1720 | Return whether Git porcelain status is nonempty without parsing its paths. |
| [`git_branch`](source.html#L1722) | 1722–1730 | Describe a symbolic branch, detached commit, or missing Git head. |
| [`nul_list_has`](source.html#L1733) | 1733–1744 | Test exact membership in a NUL-delimited pathname file. |
| [`path_fingerprint`](source.html#L1745) | 1745–1758 | Fingerprint current readable regular-file bytes at a repository-relative path. |
| [`owned_has`](source.html#L1760) | 1760–1780 | Accept an ownership claim only when a matching path record has the current content fingerprint. |
| [`pre_dirty_has`](source.html#L1781) | 1781–1781 | Test whether a path belongs to the protected initial-change set. |
| [`dirty_paths_nul`](source.html#L1783) | 1783–1796 | Emit changed tracked and untracked repository-relative paths, preserving rename endpoints. |
| [`release_owned_paths`](source.html#L1798) | 1798–1845 | Retire claims outside the project, in runtime state, no longer dirty, or holding changed bytes. |
| [`record_owned_paths`](source.html#L1847) | 1847–1882 | Remember uncommitted work for future runs without claiming protected or out-of-project paths. |
| [`pre_dirty_count`](source.html#L1884) | 1884–1889 | Produce a display/checksum-component count for the protected list. |
| [`use_branch`](source.html#L1891) | 1891–1915 | Optionally select or create the requested work branch and remember its base. |
| [`warn_detached_head`](source.html#L1917) | 1917–1928 | Refuse a run on detached HEAD through status and nonblocking notification. |
| [`self_hash_record`](source.html#L1931) | 1931–1931 | Save the current script byte fingerprint in process memory. |
| [`self_is_reviewed`](source.html#L1933) | 1933–1948 | Warn when the tracked in-project script differs from its index copy at startup. |
| [`self_hash_check`](source.html#L1950) | 1950–1966 | Detect changed or unreadable script bytes after a cycle and notify the operator. |
| [`record_recovery_point`](source.html#L1968) | 1968–1981 | Persist a valid starting commit for later recovery instructions. |
| [`pre_dirty_seal`](source.html#L1983) | 1983–1992 | Seal the exact protection-file bytes plus the display count in memory. |
| [`pre_dirty_intact`](source.html#L1994) | 1994–2001 | Require the protection file and its current count/checksum to match the stored seal. |
| [`snapshot_pre_dirty`](source.html#L2012) | 2012–2063 | Capture original staged paths and all initial non-owned dirty paths before engine work. |
| [`unstage_risky`](source.html#L2072) | 2072–2146 | Remove runtime, named secret, bulk, escaping-link and oversized paths from a private commit index. |
| [`git_top`](source.html#L2155) | 2155–2175 | Cache and return the repository root used for repository-relative path operations. |
| [`project_prefix`](source.html#L2177) | 2177–2196 | Resolve physical project/root paths and cache the project-relative staging prefix. |
| [`commit_head`](source.html#L2198) | 2198–2202 | Read a full valid HEAD object name or the explicit unborn/missing sentinel. |
| [`engine_history_is_safe`](source.html#L2211) | 2211–2265 | Inspect every new engine-created commit against captured branch/history and project ownership constraints. |
| [`git_commit_cycle`](source.html#L2267) | 2267–2296 | Sequence commit authorization, private staging, commit execution, index resync and evidence. |
| [`warn_protected_unsaved`](source.html#L2298) | 2298–2313 | Tell the operator when protected paths remain dirty after a partial commit. |
| [`commit_is_permitted`](source.html#L2315) | 2315–2363 | Refuse automatic commit when a repository disappeared, work is absent, or an operator Git operation is active. |
| [`build_commit_index`](source.html#L2365) | 2365–2427 | Create a HEAD-seeded alternate index, stage only the project, and remove forbidden/protected paths. |
| [`index_holds_our_work_only`](source.html#L2429) | 2429–2454 | Require a nonempty private-index change or explain why no independently committable work remains. |
| [`write_commit`](source.html#L2456) | 2456–2482 | Run Git commit with the alternate index and a bounded child-process watchdog. |
| [`resync_operator_index`](source.html#L2484) | 2484–2502 | Refresh committed real-index paths against new HEAD while preserving initially staged paths. |

## ENGINE

| Function | Lines | Responsibility |
|---|---:|---|
| [`engine_names`](source.html#L2539) | 2539–2539 | Enumerate table engine names and configured custom engine. |
| [`engine_field`](source.html#L2541) | 2541–2555 | Resolve command, answer destination or capability field for an engine. |
| [`engine_cmd`](source.html#L2557) | 2557–2557 | Return engine command field. |
| [`engine_answer`](source.html#L2558) | 2558–2558 | Return engine answer destination field. |
| [`engine_caps`](source.html#L2559) | 2559–2559 | Return space-delimited declared engine capabilities. |
| [`engine_has`](source.html#L2560) | 2560–2560 | Test a capability as an exact space-bounded word. |
| [`engine_score`](source.html#L2561) | 2561–2561 | Count declared capability words for engine ranking. |
| [`engine_exe`](source.html#L2563) | 2563–2569 | Resolve a literal executable path, including spaces, or the first space-delimited command token. |
| [`engine_present`](source.html#L2571) | 2571–2576 | Check configured executable path or command availability without provider authentication. |
| [`engine_live`](source.html#L2579) | 2579–2589 | Memoize successful and failed engine version probes within its shell process. |
| [`engine_live_probe`](source.html#L2591) | 2591–2599 | Execute the selected engine binary with --version and suppress output. |
| [`engine_check_model`](source.html#L2601) | 2601–2609 | Leave model selector resolution to the engine and optionally log the Prime selector. |
| [`engine_pick`](source.html#L2611) | 2611–2647 | Honor explicit engine/custom choice; otherwise prefer responsive Prime and rank alternatives. |
| [`engine_fallbacks`](source.html#L2649) | 2649–2656 | List other installed engines in descending declared-capability score. |
| [`engine_build`](source.html#L2665) | 2665–2751 | Rebuild invocation argv/env for Prime, Claude, Codex or custom command. |
| [`classify_failure`](source.html#L2761) | 2761–2772 | Map resource/deadline exits and bounded diagnostic text to retry classes. |
| [`answer_is_usable`](source.html#L2774) | 2774–2788 | Require substantive answer bytes and reject obvious HTML/login output. |
| [`engine_run`](source.html#L2792) | 2792–2851 | Execute bounded retry policy for one engine, retaining actionable final reason and capture path. |
| [`engine_invoke`](source.html#L2853) | 2853–2928 | Launch one engine attempt in PROJECT with prompt stdin and durable raw capture, then collect its answer. |
| [`engine_answered`](source.html#L2930) | 2930–2953 | Recognize a usable successful result or only Prime native bounded-stop diagnostics after exit 1. |
| [`watchdog_wait`](source.html#L2955) | 2955–3015 | Wait for a tracked child with optional silence, elapsed-poll and combined-output ceilings. |
| [`retain_engine_output`](source.html#L3017) | 3017–3029 | Keep a marked bounded tail of consumed captures larger than 256 KiB. |
| [`read_engine_usage`](source.html#L3031) | 3031–3119 | Replay current-run Prime session usage, replacing cumulative child attribution and adding separate summary/compaction calls. |
| [`engine_run_with_fallback`](source.html#L3121) | 3121–3159 | Borrow an installed alternate only for an implicitly selected engine and only for the current cycle. |

## LOOP

| Function | Lines | Responsibility |
|---|---:|---|
| [`acceptance_latest`](source.html#L3183) | 3183–3185 | Read the durable acceptance requirement identifier. |
| [`acceptance_bind`](source.html#L3187) | 3187–3193 | Publish and read back an acceptance binding before recording its event. |
| [`objective_identity`](source.html#L3195) | 3195–3200 | Compute exact explicit input identity or reuse the persisted identity on resume. |
| [`acceptance_error`](source.html#L3202) | 3202–3207 | Mark the current acceptance proof invalid and emit recovery guidance. |
| [`acceptance_intact`](source.html#L3209) | 3209–3215 | Compare the required config against both in-memory and durable binding witnesses. |
| [`acceptance_prepare`](source.html#L3217) | 3217–3268 | Resolve resumed acceptance, explicit replacement, and new-objective reset. |
| [`acceptance_verify`](source.html#L3270) | 3270–3293 | Run the bound completion command only after trusted nonempty health gates pass. |
| [`acceptance_note_work`](source.html#L3295) | 3295–3309 | Persist actual eligible work for the current binding independently of save success. |
| [`acceptance_work_fingerprint`](source.html#L3311) | 3311–3349 | Hash eligible project work separately from the full verification tree. |
| [`acceptance_done`](source.html#L3351) | 3351–3357 | Test the additional completion obligations of an active acceptance binding. |
| [`unsaved_work`](source.html#L3359) | 3359–3365 | Test reconciled ownership evidence for unfinished work that policy requires saving. |
| [`completion_ready`](source.html#L3367) | 3367–3376 | Apply one shared trusted, current, saved completion postcondition. |
| [`guard_objective`](source.html#L3384) | 3384–3395 | Restore authoritative objective bytes from this run when the file changes. |
| [`select_focus`](source.html#L3397) | 3397–3440 | Choose a deterministic focus without an engine call. |
| [`context_excerpt`](source.html#L3444) | 3444–3449 | Bound each line to a byte budget with an explicit marker. |
| [`lessons_brief`](source.html#L3451) | 3451–3466 | Select recent complete lesson lines within a 3900-byte prompt allowance. |
| [`backlog_items`](source.html#L3468) | 3468–3486 | Read unchecked task boxes from six fixed project plan paths. |
| [`git_brief`](source.html#L3488) | 3488–3495 | Render branch, last commit, a short dirty display and recent history for prompts. |
| [`ledger_render`](source.html#L3497) | 3497–3505 | Convert canonical ledger field ordering into short human-readable lines. |
| [`history_brief`](source.html#L3507) | 3507–3534 | Render the last ten selected cycle outcomes with bounded decoded details. |
| [`context_files`](source.html#L3536) | 3536–3544 | Read small excerpts of standing project instructions. |
| [`build_prompt`](source.html#L3583) | 3583–3672 | Persist the engine brief assembled from deterministic project evidence and the report contract. |
| [`parse_report`](source.html#L3679) | 3679–3708 | Parse only the last complete report block and normalize its four fields. |
| [`remember`](source.html#L3710) | 3710–3734 | Append a flattened, deduplicated lesson and retain a bounded recent set. |
| [`cycle_once`](source.html#L3738) | 3738–3759 | Orchestrate begin, observe/decide, act, verify, record and learn in order. |
| [`cycle_begin`](source.html#L3763) | 3763–3815 | Repair lost counters, create the cycle context and snapshot trust/history boundaries. |
| [`cycle_observe`](source.html#L3821) | 3821–3873 | Measure or reuse health, inspect trust, select focus and possibly finish before an engine call. |
| [`cycle_act`](source.html#L3878) | 3878–3931 | Persist the prompt/receipt, choose engine mode and run the selected/fallback engine. |
| [`cycle_guard_inputs`](source.html#L3936) | 3936–3947 | Restore gate/objective inputs and revoke this cycle trust after damage. |
| [`cycle_verify`](source.html#L3949) | 3949–4008 | Independently verify health, acceptance freshness and input custody after engine work. |
| [`cycle_record`](source.html#L4013) | 4013–4042 | Record new work or retry owned green work, then reconcile ownership and persist cycle evidence. |
| [`record_nochange`](source.html#L4044) | 4044–4052 | Persist one no-progress cycle. |
| [`record_outcome`](source.html#L4054) | 4054–4182 | Classify produced work by trust, health and save evidence rather than engine assertions. |
| [`cache_verdict`](source.html#L4185) | 4185–4198 | Cache the post-record fingerprint, measured verdict and filesystem freshness witness. |
| [`cycle_learn`](source.html#L4204) | 4204–4245 | Record lessons/questions, enforce no-progress limit and decide final completion. |
| [`commit_message`](source.html#L4247) | 4247–4266 | Describe actual checked evidence and origin in the auto-commit message. |
| [`budget_stop`](source.html#L4268) | 4268–4274 | Persist a clean paused state for exhausted time budget. |
| [`loop`](source.html#L4276) | 4276–4311 | Repeat bounded cycles, honoring stop requests, persisted stalls and time/cycle limits. |

## HUMAN

| Function | Lines | Responsibility |
|---|---:|---|
| [`request_dir`](source.html#L4328) | 4328–4333 | Create or validate a private owned directory for request evidence. |
| [`request_init`](source.html#L4334) | 4334–4337 | Validate/create request root and active batch. |
| [`request_file`](source.html#L4338) | 4338–4340 | Validate a request body/receipt as owned readable regular non-symlink evidence. |
| [`request_scan`](source.html#L4341) | 4341–4361 | Validate all published active request bodies and snapshot membership. |
| [`request_pending`](source.html#L4362) | 4362–4367 | Detect membership published after this cycle snapshot. |
| [`request_boundary`](source.html#L4368) | 4368–4387 | Bind a cycle to the current request membership and reset stale work-completion credit. |
| [`request_prompt`](source.html#L4388) | 4388–4403 | Inject complete immutable request bodies into the durable cycle prompt. |
| [`request_ack`](source.html#L4404) | 4404–4416 | Write a durable prompt reference after requests have been presented. |
| [`request_write_lock`](source.html#L4421) | 4421–4432 | Wait a bounded number of times for the short-lived publication lock. |
| [`request_archive`](source.html#L4433) | 4433–4456 | Archive the complete active batch while excluding worker and producer races. |
| [`request_archive_locked`](source.html#L4438) | 4438–4454 | Move the active request directory atomically into retained archives under both locks. |
| [`request_command`](source.html#L4458) | 4458–4510 | List, publish or explicitly archive durable unsolicited requests. |
| [`ensure_ask_file`](source.html#L4512) | 4512–4518 | Repair the owned question-file path before recording questions. |
| [`ask_human`](source.html#L4520) | 4520–4542 | Persist a deduplicated numbered question and optionally notify without terminal input. |
| [`asks_open`](source.html#L4544) | 4544–4556 | Render a bounded excerpt of open question sections. |
| [`asks_open_count`](source.html#L4558) | 4558–4561 | Count exact open-question headers. |
| [`redact_secrets`](source.html#L4563) | 4563–4575 | Redact selected credential-looking values while preserving surrounding text. |
| [`flatten_text`](source.html#L4577) | 4577–4584 | Turn a text value into one structural line safe for question/memory formatting. |
| [`answer_ask`](source.html#L4586) | 4586–4611 | Replace blank answer slots and mark a numbered question answered, then remember a redacted decision. |
| [`notify`](source.html#L4613) | 4613–4627 | Run a user-configured shell notification hook with the message in an environment variable. |

## INTERFACE

| Function | Lines | Responsibility |
|---|---:|---|
| [`usage`](source.html#L4635) | 4635–4798 | Print the version-substituted operator contract. |
| [`update_url`](source.html#L4804) | 4804–4824 | Select an explicit update source or derive one from GitHub origin, current branch and script filename. |
| [`self_update`](source.html#L4826) | 4826–4875 | Fetch and structurally validate a candidate before overwriting the running script path. |
| [`cmd_status`](source.html#L4879) | 4879–4926 | Render persistent run health, real counters and recovery instructions. |
| [`json_num`](source.html#L4928) | 4928–4934 | Render a state value as an unsigned integer or zero. |
| [`json_dec`](source.html#L4935) | 4935–4940 | Render a decimal-like state value after a limited character/point check. |
| [`run_is_alive`](source.html#L4942) | 4942–4948 | Check process existence using the persisted worker-lock pid. |
| [`status_json`](source.html#L4950) | 4950–4968 | Emit one compact machine-readable status record from project/state evidence. |
| [`cmd_forget`](source.html#L4970) | 4970–4980 | Tombstone acceptance and remove a stored objective. |
| [`cmd_doctor`](source.html#L4982) | 4982–5023 | Inspect available engine presence/responsiveness, capabilities, stack, Git and gates. |
| [`missing_caps`](source.html#L5027) | 5027–5034 | List capability names absent from an engine row. |
| [`cmd_gates`](source.html#L5036) | 5036–5072 | Discover/display gates or explicitly replace the agreed set after stopping a worker. |
| [`cmd_log`](source.html#L5074) | 5074–5080 | Render the requested tail of the current ledger. |
| [`need_value`](source.html#L5090) | 5090–5094 | Reject missing or empty option values before shift. |
| [`looks_like_typo`](source.html#L5096) | 5096–5120 | Reject a lone lower-case prefix/extension of known command names. |
| [`load_spec`](source.html#L5122) | 5122–5143 | Read a bounded plain-text specification from invocation cwd exactly once. |
| [`parse_args`](source.html#L5145) | 5145–5202 | Parse global options until a command or positional objective terminates option scanning. |
| [`run_simple_command`](source.html#L5213) | 5213–5235 | Dispatch non-run commands using preserved positional arguments. |
| [`run_prepare`](source.html#L5239) | 5239–5307 | Acquire the worker and establish persistence, custody, objective, engine and verification prerequisites. |
| [`set_objective`](source.html#L5309) | 5309–5348 | Persist explicit objective bytes or resume the stored objective into memory custody. |
| [`choose_engine`](source.html#L5350) | 5350–5360 | Resolve the selected engine and persist selection/model metadata. |
| [`prepare_gates`](source.html#L5362) | 5362–5382 | Discover baseline gates and trial each unique explicit --gate addition. |
| [`print_run_banner`](source.html#L5384) | 5384–5404 | Describe chosen engine/mode, limits, branch and recovery point. |
| [`run_finish`](source.html#L5406) | 5406–5420 | Print the final run disposition and try to return to the operator base branch. |
| [`return_to_base_branch`](source.html#L5422) | 5422–5441 | Restore the original branch only if tracked working changes do not need review. |
| [`main`](source.html#L5447) | 5447–5475 | Order parsing, early commands, project binding, ledger/traps, preparation, loop and finish. |
