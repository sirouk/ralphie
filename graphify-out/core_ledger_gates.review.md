# Core, ledger and gates source review

Pinned source: `ralphie.sh` SHA256 `c21744b635e3b640aa6d65b6c36daa7dc0d8e1e90b7bf45fb09f8937055aa905`; 5478 total lines. Reviewed every line **1–1696**. Covered **92 definitions / 90 distinct names**, including the two subshell-local discovery helpers. No product/test/documentation edits or runtime executions were made for this review.

`EXTRACTED` marks a source operation or declaration. `INFERRED` marks an implication or limit. Source comments about historical incidents are context, not freshly reproduced evidence. Anchors below refer to the pinned file.

## Top-level execution and declarations

- **script_header** [EXTRACTED] Bash entrypoint; ralphie-kernel marker identifies this product to shell-gate discovery. Header describes design intent rather than executable enforcement. [`ralphie.sh:1–40`](../ralphie.sh#L1)

- **stream_bootstrap** [EXTRACTED] When not library mode and BASH_SOURCE is empty, reconstruct a header and consume remaining stdin into pwd/ralphie.sh.tmp.PID, chmod, rename to pwd/ralphie.sh and exec with RALPHIE_NO_UPDATE1. Failure removes scratch and exits1. [`ralphie.sh:42–76`](../ralphie.sh#L42)

- **strict_shell** [EXTRACTED] Enable errexit, nounset and pipefail before function definitions and normal execution. [`ralphie.sh:78`](../ralphie.sh#L78)

- **version_and_newline** [EXTRACTED] Set VERSION3.1.0 and retain a literal newline in RALPHIE_NL rather than a stripped command substitution. [`ralphie.sh:80–86`](../ralphie.sh#L80)

- **core_header** [EXTRACTED] Layer1 defines output, portability shims and primitives shared by subsequent layers. [`ralphie.sh:88–94`](../ralphie.sh#L88)

- **self_and_initial_project** [EXTRACTED] Derive physical script-parent SELF plus original basename ME. Initial PROJECT is nonempty RALPHIE_PROJECT or SELF parent; final CLI/environment binding occurs through project_bind later. [`ralphie.sh:96–104`](../ralphie.sh#L96)

- **presentation_defaults** [EXTRACTED] Use ANSI colors only on tty stdout with empty NO_COLOR and non-dumb TERM. VERBOSE and QUIET derive from RALPHIE_VERBOSE/RALPHIE_QUIET, each default0. [`ralphie.sh:122–138`](../ralphie.sh#L122)

- **budget_default** [EXTRACTED] RUN_DEADLINE starts0, meaning unlimited. Header commentary says loop sets it, while current run_prepare actually starts it before preparation trials. [`ralphie.sh:244–249`](../ralphie.sh#L244)

- **ledger_header_and_keys** [EXTRACTED] Layer2 introduces persistent state, append-only event writes, locking and process hygiene; STATE_KEYS declares the only writable state keys. [`ralphie.sh:281–294`](../ralphie.sh#L281)

- **run_ownership_default** [EXTRACTED] OWNS_RUN starts0; run_init changes it only after run setup begins. [`ralphie.sh:565`](../ralphie.sh#L565)

- **noise_directory_policy** [EXTRACTED] One named directory list excludes generated/vendor/runtime paths from filesystem freshness evidence and is reused later by commit filtering. [`ralphie.sh:685–695`](../ralphie.sh#L685)

- **lock_and_child_defaults** [EXTRACTED] LOCK_HELD starts0 and CHILD_PIDS starts empty. These are process-local cleanup bookkeeping, not durable process handles. [`ralphie.sh:801–808`](../ralphie.sh#L801)

- **signal_defaults** [EXTRACTED] INTERRUPTED and SIGPIPE_SEEN start0. Traps are installed only later by install_traps. [`ralphie.sh:861–862`](../ralphie.sh#L861)

- **project_layer_header** [EXTRACTED] Layer3 supplies deterministic stack inference, gate discovery/execution and Git operations; Git function bodies begin after the assigned boundary. [`ralphie.sh:918–928`](../ralphie.sh#L918)

- **gate_exit_prelude** [EXTRACTED] GATE_REAP installs an EXIT trap in the child gate shell that sends a default kill signal to jobs -p children. [`ralphie.sh:1143–1155`](../ralphie.sh#L1143)

- **gate_shell_selection** [EXTRACTED] Prefer executable BASH, then PATH bash. Both gate preludes enable pipefail. Last fallback is sh with no pipefail and GATE_NO_PIPEFAIL1. [`ralphie.sh:1157–1177`](../ralphie.sh#L1157)

- **gate_executor_default** [EXTRACTED] GATE_EXEC_RC starts0 and is replaced by each gate executor result. [`ralphie.sh:1191`](../ralphie.sh#L1191)

- **baseline_default** [EXTRACTED] GATES_BASELINE_FILE starts empty and is bound to HOME_DIR/gates.baseline on first baseline operation. [`ralphie.sh:1424`](../ralphie.sh#L1424)

- **snapshot_default** [EXTRACTED] GATES_SNAPSHOT starts empty; snapshot_gates grows it in the main process. [`ralphie.sh:1481`](../ralphie.sh#L1481)

- **assigned_boundary** [EXTRACTED] Lines1695–1696 are the Git subsection marker/blank line; git_ready starts1697 outside this inventory. [`ralphie.sh:1695–1696`](../ralphie.sh#L1695)


## Function inventory

### `project_bind` — 106–120

**CORE; scope: global; EXTRACTED.** Resolve the selected project physically and bind every primary runtime path once. [`ralphie.sh:106–120`](../ralphie.sh#L106)

- **Inputs [EXTRACTED]:** Argument1 is an existing project directory; the caller may pass a relative path. Current working directory supplies relative-path interpretation.

- **Outputs [EXTRACTED]:** Sets PROJECT, exported RALPHIE_PROJECT, HOME_DIR, STATE_FILE, EVENTS_FILE, GATES_FILE, OBJECTIVE_FILE, ASK_FILE, MEMORY_FILE, LOG_DIR, RUN_DIR, LOCK_FILE and STOP_FILE. No normal stdout.

- **Side effects [EXTRACTED]:** Exports the physical project path to child processes. The cd runs in command substitution; the caller working directory is unchanged. No directories are created here.

- **Invariants and scope [EXTRACTED]:** Every primary runtime path derives from the single physical PROJECT value.

- **Failure and recovery [EXTRACTED]:** A failed directory resolution invokes die and exits1; it does not fall back to another project.

- **Calls/callbacks:** `die` [`ralphie.sh:107`](../ralphie.sh#L107).

- **Shell/host commands:** `cd`, `pwd`.



### `terminal_printf` — 140–148

**CORE; scope: global; EXTRACTED.** Print to stdout and translate a failed pipe write into the SIGPIPE cleanup protocol. [`ralphie.sh:140–148`](../ralphie.sh#L140)

- **Inputs [EXTRACTED]:** Printf format and arguments, plus /dev/stdout file type.

- **Outputs [EXTRACTED]:** Formatted stdout; returns printf status, or141 when a failed write targets a pipe.

- **Side effects [EXTRACTED]:** On a pipe failure invokes on_pipe, which retires stdout and latches SIGPIPE_SEEN.

- **Invariants and scope [EXTRACTED]:** Only a failed write together with a pipe-shaped stdout takes the special SIGPIPE path.

- **Failure and recovery [EXTRACTED]:** Ordinary non-pipe print failures retain their original status.

- **Calls/callbacks:** `on_pipe` [`ralphie.sh:144`](../ralphie.sh#L144).

- **Shell/host commands:** `printf`.



### `say` — 149–149

**CORE; scope: global; EXTRACTED.** Print one uncolored line through the pipe-aware output helper. [`ralphie.sh:149`](../ralphie.sh#L149)

- **Inputs [EXTRACTED]:** All arguments joined using $*.

- **Outputs [EXTRACTED]:** Stdout line and terminal_printf status.

- **Side effects [EXTRACTED]:** May trigger the shared broken-pipe protocol.

- **Invariants and scope [EXTRACTED]:** Formatting is fixed to %s followed by a newline.

- **Failure and recovery [EXTRACTED]:** Print errors propagate through terminal_printf.

- **Calls/callbacks:** `terminal_printf` [`ralphie.sh:149`](../ralphie.sh#L149).

- **Shell/host commands:** `printf`.



### `info` — 153–153

**CORE; scope: global; EXTRACTED.** Print an informational colored line unless quiet mode is true. [`ralphie.sh:153`](../ralphie.sh#L153)

- **Inputs [EXTRACTED]:** QUIET, color globals, message arguments.

- **Outputs [EXTRACTED]:** No output with successful status when quiet; otherwise formatted stdout.

- **Side effects [EXTRACTED]:** May trigger the shared broken-pipe protocol.

- **Invariants and scope [EXTRACTED]:** Suppressing a line succeeds because the guard uses OR.

- **Failure and recovery [EXTRACTED]:** Print errors otherwise propagate through terminal_printf.

- **Calls/callbacks:** `is_true` [`ralphie.sh:153`](../ralphie.sh#L153); `terminal_printf` [`ralphie.sh:153`](../ralphie.sh#L153).



### `good` — 154–154

**CORE; scope: global; EXTRACTED.** Print a success-colored line. [`ralphie.sh:154`](../ralphie.sh#L154)

- **Inputs [EXTRACTED]:** Color globals and message arguments; QUIET is not consulted.

- **Outputs [EXTRACTED]:** Formatted stdout and terminal_printf status.

- **Side effects [EXTRACTED]:** May trigger the shared broken-pipe protocol.

- **Invariants and scope [EXTRACTED]:** Success output remains visible in quiet mode.

- **Failure and recovery [EXTRACTED]:** Print errors propagate through terminal_printf.

- **Calls/callbacks:** `terminal_printf` [`ralphie.sh:154`](../ralphie.sh#L154).



### `warn` — 155–155

**CORE; scope: global; EXTRACTED.** Print a warning-colored line to stderr. [`ralphie.sh:155`](../ralphie.sh#L155)

- **Inputs [EXTRACTED]:** Color globals and message arguments.

- **Outputs [EXTRACTED]:** Stderr line and printf status.

- **Side effects [EXTRACTED]:** Writes to stderr directly.

- **Invariants and scope [EXTRACTED]:** No stdout dependency.

- **Failure and recovery [EXTRACTED]:** No local write-error recovery.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `printf`.



### `err` — 156–156

**CORE; scope: global; EXTRACTED.** Print an error-colored line to stderr. [`ralphie.sh:156`](../ralphie.sh#L156)

- **Inputs [EXTRACTED]:** Color globals and message arguments.

- **Outputs [EXTRACTED]:** Stderr line and printf status.

- **Side effects [EXTRACTED]:** Writes to stderr directly.

- **Invariants and scope [EXTRACTED]:** No stdout dependency.

- **Failure and recovery [EXTRACTED]:** No local write-error recovery.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `printf`.



### `dim` — 157–157

**CORE; scope: global; EXTRACTED.** Print a dim line unless quiet mode is true. [`ralphie.sh:157`](../ralphie.sh#L157)

- **Inputs [EXTRACTED]:** QUIET, color globals and message arguments.

- **Outputs [EXTRACTED]:** Successful silence when quiet; otherwise formatted stdout.

- **Side effects [EXTRACTED]:** May trigger the shared broken-pipe protocol.

- **Invariants and scope [EXTRACTED]:** Suppressing the message does not cause a false command failure.

- **Failure and recovery [EXTRACTED]:** Print errors otherwise propagate through terminal_printf.

- **Calls/callbacks:** `is_true` [`ralphie.sh:157`](../ralphie.sh#L157); `terminal_printf` [`ralphie.sh:157`](../ralphie.sh#L157).



### `dbg` — 158–158

**CORE; scope: global; EXTRACTED.** Print a debug line to stderr only when verbosity is true. [`ralphie.sh:158`](../ralphie.sh#L158)

- **Inputs [EXTRACTED]:** VERBOSE, color globals and message arguments.

- **Outputs [EXTRACTED]:** Optional stderr line; returns0.

- **Side effects [EXTRACTED]:** Direct stderr write when enabled.

- **Invariants and scope [EXTRACTED]:** The final OR true makes debug output non-fatal.

- **Failure and recovery [EXTRACTED]:** Suppression and print failure are both successful to the caller.

- **Calls/callbacks:** `is_true` [`ralphie.sh:158`](../ralphie.sh#L158).

- **Shell/host commands:** `printf`.



### `die` — 159–159

**CORE; scope: global; EXTRACTED.** Report a prefixed fatal message and exit. [`ralphie.sh:159`](../ralphie.sh#L159)

- **Inputs [EXTRACTED]:** Message arguments.

- **Outputs [EXTRACTED]:** Stderr via err, then process exit1.

- **Side effects [EXTRACTED]:** Triggers any installed EXIT trap.

- **Invariants and scope [EXTRACTED]:** The fatal prefix is ralphie:.

- **Failure and recovery [EXTRACTED]:** No local continuation after exit1.

- **Calls/callbacks:** `err` [`ralphie.sh:159`](../ralphie.sh#L159).

- **Shell/host commands:** `exit`.



### `now_iso` — 161–161

**CORE; scope: global; EXTRACTED.** Emit the current UTC timestamp for ledger records. [`ralphie.sh:161`](../ralphie.sh#L161)

- **Inputs [EXTRACTED]:** System clock.

- **Outputs [EXTRACTED]:** YYYY-MM-DDTHH:MM:SSZ plus newline on stdout.

- **Side effects [EXTRACTED]:** Reads the system clock.

- **Invariants and scope [EXTRACTED]:** UTC formatting is explicit through date -u.

- **Failure and recovery [EXTRACTED]:** Date failure has no local fallback.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `date`.



### `now_epoch` — 162–162

**CORE; scope: global; EXTRACTED.** Emit the current epoch second. [`ralphie.sh:162`](../ralphie.sh#L162)

- **Inputs [EXTRACTED]:** System clock.

- **Outputs [EXTRACTED]:** Decimal epoch seconds plus newline on stdout.

- **Side effects [EXTRACTED]:** Reads the system clock.

- **Invariants and scope [EXTRACTED]:** Uses date +%s.

- **Failure and recovery [EXTRACTED]:** Date failure has no local fallback.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `date`.



### `stamp` — 163–163

**CORE; scope: global; EXTRACTED.** Emit a UTC timestamp suitable for a run identifier. [`ralphie.sh:163`](../ralphie.sh#L163)

- **Inputs [EXTRACTED]:** System clock.

- **Outputs [EXTRACTED]:** YYYYMMDDTHHMMSSZ plus newline on stdout.

- **Side effects [EXTRACTED]:** Reads the system clock.

- **Invariants and scope [EXTRACTED]:** UTC formatting omits punctuation unsafe for common filenames.

- **Failure and recovery [EXTRACTED]:** Date failure has no local fallback.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `date`.



### `have` — 166–166

**CORE; scope: global; EXTRACTED.** Check whether command resolution can find a name. [`ralphie.sh:166`](../ralphie.sh#L166)

- **Inputs [EXTRACTED]:** Argument1 command name and current shell/PATH command resolution.

- **Outputs [EXTRACTED]:** Only command -v status; stdout and stderr are discarded.

- **Side effects [EXTRACTED]:** No invocation of the named command.

- **Invariants and scope [EXTRACTED]:** Presence is a resolution check, not a health or authentication probe.

- **Failure and recovery [EXTRACTED]:** Missing names return nonzero.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `command -v`.



### `sha_of` — 168–177

**CORE; scope: global; EXTRACTED.** Hash stdin using the first available supported digest tool. [`ralphie.sh:168–177`](../ralphie.sh#L168)

- **Inputs [EXTRACTED]:** Stdin bytes and availability of sha256sum, shasum and openssl.

- **Outputs [EXTRACTED]:** Digest text; fallback is cksum checksum-bytecount.

- **Side effects [EXTRACTED]:** Runs one selected external digest implementation.

- **Invariants and scope [EXTRACTED]:** Selection order is sha256sum, shasum -a256, openssl SHA256, then cksum.

- **Failure and recovery [EXTRACTED]:** No retry follows a present digest tool failing; fallback choice is based on presence. cksum is explicitly weaker than SHA256.

- **Calls/callbacks:** `have` [`ralphie.sh:172`](../ralphie.sh#L172), [`ralphie.sh:173`](../ralphie.sh#L173), [`ralphie.sh:174`](../ralphie.sh#L174).

- **Shell/host commands:** `sha256sum`, `shasum`, `openssl`, `cksum`, `awk`.



### `timeout_cmd` — 179–185

**CORE; scope: global; EXTRACTED.** Return the available GNU timeout command name or an empty line. [`ralphie.sh:179–185`](../ralphie.sh#L179)

- **Inputs [EXTRACTED]:** PATH command availability.

- **Outputs [EXTRACTED]:** timeout, gtimeout, or an empty line.

- **Side effects [EXTRACTED]:** No timeout command is executed.

- **Invariants and scope [EXTRACTED]:** timeout is preferred over gtimeout.

- **Failure and recovery [EXTRACTED]:** No available timeout produces a successful empty result.

- **Calls/callbacks:** `have` [`ralphie.sh:181`](../ralphie.sh#L181), [`ralphie.sh:182`](../ralphie.sh#L182).

- **Shell/host commands:** `printf`.



### `rand_token` — 187–194

**CORE; scope: global; EXTRACTED.** Generate a small run/lock token. [`ralphie.sh:187–194`](../ralphie.sh#L187)

- **Inputs [EXTRACTED]:** Readable /dev/urandom, od presence, current time and shell PID.

- **Outputs [EXTRACTED]:** Twelve hexadecimal characters when urandom is used; otherwise epoch seconds concatenated with PID.

- **Side effects [EXTRACTED]:** Reads6 random bytes or the system clock.

- **Invariants and scope [EXTRACTED]:** The fallback avoids relying on Bash RANDOM alone.

- **Failure and recovery [INFERRED]:** No uniqueness or cryptographic guarantee follows from the fallback; od failure is not retried locally.

- **Calls/callbacks:** `have` [`ralphie.sh:189`](../ralphie.sh#L189).

- **Shell/host commands:** `od`, `tr`, `date`.



### `json_escape` — 196–201

**CORE; scope: global; EXTRACTED.** Escape textual stdin for a JSON string body. [`ralphie.sh:196–201`](../ralphie.sh#L196)

- **Inputs [EXTRACTED]:** Textual stdin bytes.

- **Outputs [EXTRACTED]:** Backslashes, quotes and tabs escaped; CR and other control bytes dropped; input line boundaries represented as literal backslash-n.

- **Side effects [EXTRACTED]:** Runs a sed/awk pipeline with C locale for sed.

- **Invariants and scope [EXTRACTED]:** It emits the string body without surrounding quotes or a trailing newline of its own.

- **Failure and recovery [EXTRACTED]:** This deliberately is not binary-preserving JSON serialization. Pipeline failures have no local recovery.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `sed`, `awk`.



### `json_str` — 203–203

**CORE; scope: global; EXTRACTED.** Escape a single argument as a JSON string body. [`ralphie.sh:203`](../ralphie.sh#L203)

- **Inputs [EXTRACTED]:** Argument1.

- **Outputs [EXTRACTED]:** Escaped text on stdout.

- **Side effects [EXTRACTED]:** Pipes the argument to json_escape.

- **Invariants and scope [EXTRACTED]:** Printf prevents the argument from acting as a format string.

- **Failure and recovery [EXTRACTED]:** Propagates pipeline failures.

- **Calls/callbacks:** `json_escape` [`ralphie.sh:203`](../ralphie.sh#L203).

- **Shell/host commands:** `printf`.



### `is_int` — 205–205

**CORE; scope: global; EXTRACTED.** Recognize a nonempty unsigned decimal digit string. [`ralphie.sh:205`](../ralphie.sh#L205)

- **Inputs [EXTRACTED]:** Optional argument1, empty by default.

- **Outputs [EXTRACTED]:** Status0 for digits only;1 for empty or any other byte.

- **Side effects [EXTRACTED]:** None.

- **Invariants and scope [EXTRACTED]:** Signs, spaces and decimal points are rejected.

- **Failure and recovery [EXTRACTED]:** Invalid data returns1 without output.

- **Calls/callbacks:** No repository-function callback in this body.



### `is_true` — 206–206

**CORE; scope: global; EXTRACTED.** Recognize common case-insensitive true values. [`ralphie.sh:206`](../ralphie.sh#L206)

- **Inputs [EXTRACTED]:** Optional argument1.

- **Outputs [EXTRACTED]:** Status0 for1/true/yes/y/on;1 otherwise.

- **Side effects [EXTRACTED]:** Lowercases through tr.

- **Invariants and scope [EXTRACTED]:** False, empty and unrecognized spellings return1.

- **Failure and recovery [EXTRACTED]:** No diagnostics for invalid values.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `printf`, `tr`.



### `trim` — 208–208

**CORE; scope: global; EXTRACTED.** Trim leading and trailing whitespace from an argument. [`ralphie.sh:208`](../ralphie.sh#L208)

- **Inputs [EXTRACTED]:** Argument1 text.

- **Outputs [EXTRACTED]:** Trimmed text on stdout.

- **Side effects [EXTRACTED]:** Runs sed.

- **Invariants and scope [EXTRACTED]:** Whitespace processing follows sed line semantics.

- **Failure and recovery [EXTRACTED]:** No local recovery for a failed text pipeline.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `printf`, `sed`.



### `tail_of` — 211–211

**CORE; scope: global; EXTRACTED.** Read a bounded tail of an existing regular file. [`ralphie.sh:211`](../ralphie.sh#L211)

- **Inputs [EXTRACTED]:** Argument1 path; optional byte count default4000.

- **Outputs [EXTRACTED]:** Up to the requested trailing bytes on stdout; returns0.

- **Side effects [EXTRACTED]:** Reads the file, suppressing tail stderr.

- **Invariants and scope [EXTRACTED]:** Missing/nonregular files are a successful empty read.

- **Failure and recovery [EXTRACTED]:** Tail failure is suppressed by OR true.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `tail`.



### `secs_since` — 213–213

**CORE; scope: global; EXTRACTED.** Compute elapsed seconds from an epoch value. [`ralphie.sh:213`](../ralphie.sh#L213)

- **Inputs [EXTRACTED]:** Optional epoch argument default0 and current system time.

- **Outputs [EXTRACTED]:** Current epoch minus supplied integer, without newline.

- **Side effects [EXTRACTED]:** Reads the system clock.

- **Invariants and scope [EXTRACTED]:** A non-integer input is normalized to0.

- **Failure and recovery [EXTRACTED]:** Future epochs can produce negative elapsed time; no clock-skew correction is applied.

- **Calls/callbacks:** `is_int` [`ralphie.sh:213`](../ralphie.sh#L213); `now_epoch` [`ralphie.sh:213`](../ralphie.sh#L213).

- **Shell/host commands:** `printf`.



### `file_bytes` — 215–225

**CORE; scope: global; EXTRACTED.** Return a regular file byte count or zero. [`ralphie.sh:215–225`](../ralphie.sh#L215)

- **Inputs [EXTRACTED]:** Optional path argument.

- **Outputs [EXTRACTED]:** Unsigned decimal count, normalized to0 when absent, nonregular, failed or invalid.

- **Side effects [EXTRACTED]:** Reads file contents through wc -c.

- **Invariants and scope [EXTRACTED]:** Checks regular-file existence before opening the path.

- **Failure and recovery [EXTRACTED]:** A failed count is replaced by0; concurrent path changes are not locked.

- **Calls/callbacks:** `is_int` [`ralphie.sh:223`](../ralphie.sh#L223).

- **Shell/host commands:** `wc`, `tr`, `printf`.



### `count_of` — 227–234

**CORE; scope: global; EXTRACTED.** Count stdout lines from an arbitrary supplied command. [`ralphie.sh:227–234`](../ralphie.sh#L227)

- **Inputs [EXTRACTED]:** All arguments form the callback command argv.

- **Outputs [EXTRACTED]:** Nonnegative integer line count, or0 on pipeline failure/invalid count.

- **Side effects [EXTRACTED]:** Executes caller-supplied command; its stderr is suppressed and its stdout is consumed.

- **Invariants and scope [EXTRACTED]:** A nonzero callback status becomes count0 under inherited pipefail.

- **Failure and recovery [EXTRACTED]:** No-match grep is normalized without creating a duplicated zero. Callback side effects are not constrained.

- **Calls/callbacks:** `is_int` [`ralphie.sh:232`](../ralphie.sh#L232); `$argv-command` [`ralphie.sh:231`](../ralphie.sh#L231).

- **Shell/host commands:** `wc`, `tr`, `printf`.



### `human_secs` — 236–242

**CORE; scope: global; EXTRACTED.** Format a duration in seconds, minutes or hours. [`ralphie.sh:236–242`](../ralphie.sh#L236)

- **Inputs [EXTRACTED]:** Optional unsigned seconds default0.

- **Outputs [EXTRACTED]:** Ns, NmNs or NhNm without newline.

- **Side effects [EXTRACTED]:** None besides stdout.

- **Invariants and scope [EXTRACTED]:** Invalid integers normalize to0; hours output omits residual seconds.

- **Failure and recovery [EXTRACTED]:** No handling beyond unsigned-digit validation.

- **Calls/callbacks:** `is_int` [`ralphie.sh:237`](../ralphie.sh#L237).

- **Shell/host commands:** `printf`.



### `budget_left` — 251–259

**CORE; scope: global; EXTRACTED.** Compute remaining time under the absolute run deadline. [`ralphie.sh:251–259`](../ralphie.sh#L251)

- **Inputs [EXTRACTED]:** RUN_DEADLINE default0 and system clock.

- **Outputs [EXTRACTED]:** -1 for unlimited; otherwise seconds remaining clamped at0.

- **Side effects [EXTRACTED]:** Reads the system clock.

- **Invariants and scope [EXTRACTED]:** Only a positive deadline creates a bounded budget.

- **Failure and recovery [EXTRACTED]:** The global deadline is trusted numeric input here.

- **Calls/callbacks:** `now_epoch` [`ralphie.sh:256`](../ralphie.sh#L256).

- **Shell/host commands:** `printf`.



### `budget_expired` — 261–264

**CORE; scope: global; EXTRACTED.** Test whether an active run budget is exhausted. [`ralphie.sh:261–264`](../ralphie.sh#L261)

- **Inputs [EXTRACTED]:** RUN_DEADLINE via budget_left.

- **Outputs [EXTRACTED]:** Status0 exactly when budget_left is the string0.

- **Side effects [EXTRACTED]:** None beyond the clock read delegated to budget_left.

- **Invariants and scope [EXTRACTED]:** Unlimited (-1) does not count as expired.

- **Failure and recovery [EXTRACTED]:** No local recovery beyond budget_left.

- **Calls/callbacks:** `budget_left` [`ralphie.sh:263`](../ralphie.sh#L263).



### `budget_cap` — 266–279

**CORE; scope: global; EXTRACTED.** Clamp a requested timeout to the remaining run budget. [`ralphie.sh:266–279`](../ralphie.sh#L266)

- **Inputs [EXTRACTED]:** Optional requested seconds default0, RUN_DEADLINE.

- **Outputs [EXTRACTED]:** Requested limit when unlimited; bounded minimum with a1-second floor otherwise.

- **Side effects [EXTRACTED]:** No persistent mutation.

- **Invariants and scope [EXTRACTED]:** Requested0 means no local limit; an exhausted finite budget still produces1 rather than unlimited0.

- **Failure and recovery [EXTRACTED]:** Invalid requested integers normalize to0. The return is a timeout value, not a guarantee of exact wall-clock termination.

- **Calls/callbacks:** `is_int` [`ralphie.sh:271`](../ralphie.sh#L271); `budget_left` [`ralphie.sh:272`](../ralphie.sh#L272).

- **Shell/host commands:** `printf`.



### `state_get` — 296–301

**LEDGER; scope: global; EXTRACTED.** Read the last stored value for a key, or a supplied default. [`ralphie.sh:296–301`](../ralphie.sh#L296)

- **Inputs [EXTRACTED]:** Key argument, optional default, STATE_FILE.

- **Outputs [EXTRACTED]:** Last matching key=value suffix or default on stdout.

- **Side effects [EXTRACTED]:** Reads the state file using grep/tail.

- **Invariants and scope [EXTRACTED]:** Missing/nonregular state returns the default. Duplicate keys use the last line.

- **Failure and recovery [EXTRACTED]:** The key is interpolated into a regex and is expected to be an internal key; read failures are suppressed.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `grep`, `tail`, `printf`.



### `state_set` — 303–343

**LEDGER; scope: global; EXTRACTED.** Replace one allowlisted state key using a directory mutex and temporary file. [`ralphie.sh:303–343`](../ralphie.sh#L303)

- **Inputs [EXTRACTED]:** Key/value arguments, STATE_KEYS, HOME_DIR, STATE_FILE; time/PID/randomness for scratch identity.

- **Outputs [EXTRACTED]:** Best-effort state update; no success receipt other than file state. Unknown keys and unwritable HOME_DIR return0 after debug text.

- **Side effects [EXTRACTED]:** Creates HOME_DIR; may repair STATE_FILE; creates/removes state.lock; rewrites a same-directory temporary file and renames it; failure fallback removes state and writes the single requested key.

- **Invariants and scope [EXTRACTED]:** Only allowlisted keys are accepted; CR and LF are removed from values. The normal path verifies the rename destination is a regular file.

- **Failure and recovery [INFERRED]:** After30 failed mutex acquisitions the lock is forcibly replaced. Rename/postcondition failure takes a best-effort destructive state fallback; preservation of other keys is not guaranteed by that fallback.

- **Calls/callbacks:** `dbg` [`ralphie.sh:309`](../ralphie.sh#L309), [`ralphie.sh:316`](../ralphie.sh#L316); `ensure_state_file` [`ralphie.sh:323`](../ralphie.sh#L323); `rand_token` [`ralphie.sh:331`](../ralphie.sh#L331).

- **Shell/host commands:** `tr`, `mkdir`, `rm`, `sleep`, `cut`, `grep`, `printf`, `mv`, `rmdir`.



### `state_bump` — 345–349

**LEDGER; scope: global; EXTRACTED.** Increment a state counter through the common writer. [`ralphie.sh:345–349`](../ralphie.sh#L345)

- **Inputs [EXTRACTED]:** Key and optional increment default1; state value default0.

- **Outputs [EXTRACTED]:** Updated state via state_set.

- **Side effects [EXTRACTED]:** Mutates one state key.

- **Invariants and scope [EXTRACTED]:** An invalid existing counter becomes0.

- **Failure and recovery [EXTRACTED]:** Increment expression is trusted; state_set retains its best-effort semantics.

- **Calls/callbacks:** `state_get` [`ralphie.sh:347`](../ralphie.sh#L347); `is_int` [`ralphie.sh:347`](../ralphie.sh#L347); `state_set` [`ralphie.sh:348`](../ralphie.sh#L348).



### `event` — 351–381

**LEDGER; scope: global; EXTRACTED.** Append one textual JSON event and update the last-write timestamp. [`ralphie.sh:351–381`](../ralphie.sh#L351)

- **Inputs [EXTRACTED]:** Kind/status/detail arguments and optional key=value extras; CY_N/RUN_ID_MEM globals, state fallback, paths.

- **Outputs [EXTRACTED]:** One appended events.jsonl record with ts/run/cycle/kind/status/detail and string extras; state updated_at.

- **Side effects [EXTRACTED]:** Creates HOME_DIR, repairs a nonregular existing ledger path, appends bytes, then updates state.

- **Invariants and scope [EXTRACTED]:** In-memory run/cycle identities take precedence over editable state; detail and extra values pass through JSON escaping. Records are appended, not rewritten by this function.

- **Failure and recovery [EXTRACTED]:** Kind/status/run/extra-key strings are trusted structural inputs rather than escaped values. File write failures have no independent durable queue or fsync.

- **Calls/callbacks:** `json_str` [`ralphie.sh:360`](../ralphie.sh#L360), [`ralphie.sh:379`](../ralphie.sh#L379); `ensure_own_file` [`ralphie.sh:368`](../ralphie.sh#L368); `is_int` [`ralphie.sh:375`](../ralphie.sh#L375); `json_num` [`ralphie.sh:375`](../ralphie.sh#L375); `state_get` [`ralphie.sh:376`](../ralphie.sh#L376); `now_iso` [`ralphie.sh:378`](../ralphie.sh#L378), [`ralphie.sh:380`](../ralphie.sh#L380); `state_set` [`ralphie.sh:380`](../ralphie.sh#L380).

- **Shell/host commands:** `mkdir`, `printf`.



### `ensure_dirs` — 383–388

**LEDGER; scope: global; EXTRACTED.** Create the three runtime directories on demand. [`ralphie.sh:383–388`](../ralphie.sh#L383)

- **Inputs [EXTRACTED]:** HOME_DIR, LOG_DIR, RUN_DIR.

- **Outputs [EXTRACTED]:** Returns0.

- **Side effects [EXTRACTED]:** mkdir -p may create project runtime directories.

- **Invariants and scope [EXTRACTED]:** Repeated calls are allowed.

- **Failure and recovery [EXTRACTED]:** Creation failures and stderr are suppressed.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `mkdir`.



### `ensure_own_file` — 390–460

**LEDGER; scope: global; EXTRACTED.** Repair or report an unusable Ralphie-owned file without rejecting the caller. [`ralphie.sh:390–460`](../ralphie.sh#L390)

- **Inputs [EXTRACTED]:** Path, human-readable file type, GATES_FILE identity, CMD and UNUSABLE_REPORTED globals.

- **Outputs [EXTRACTED]:** Returns0; refreshes GATES_FILE_BROKEN for the gate path; may update UNUSABLE_REPORTED.

- **Side effects [EXTRACTED]:** May chmod u+r; preserves readable read-only regular-file content; may recursively delete a nonusable existing path and create an empty file; emits console text and potentially one file-unusable event.

- **Invariants and scope [EXTRACTED]:** Readable protected regular files are not made writable or truncated. Repair success is reported only after replacement succeeds. The broken-file flag is gate-specific.

- **Failure and recovery [EXTRACTED]:** A path failing -e, including a dangling symlink, returns early. Unrepairable gate paths set GATES_FILE_BROKEN1. Recursive deletion is actual behavior for nonusable existing paths; source comments do not prove their contained data is valueless.

- **Calls/callbacks:** `warn` [`ralphie.sh:427`](../ralphie.sh#L427), [`ralphie.sh:439`](../ralphie.sh#L439); `dim` [`ralphie.sh:428`](../ralphie.sh#L428), [`ralphie.sh:443`](../ralphie.sh#L443); `err` [`ralphie.sh:442`](../ralphie.sh#L442); `event` [`ralphie.sh:452`](../ralphie.sh#L452).

- **Shell/host commands:** `chmod`, `basename`, `rm`, `printf`.



### `ensure_state_file` — 462–470

**LEDGER; scope: global; EXTRACTED.** Apply common owned-file repair to the state path. [`ralphie.sh:462–470`](../ralphie.sh#L462)

- **Inputs [EXTRACTED]:** STATE_FILE.

- **Outputs [EXTRACTED]:** Returns ensure_own_file status, which is designed as0.

- **Side effects [EXTRACTED]:** May repair/report the state file.

- **Invariants and scope [EXTRACTED]:** Uses the shared repair policy.

- **Failure and recovery [EXTRACTED]:** The wrapper does not reconstruct state counters; rebuild_state_from_ledger is a separate step.

- **Calls/callbacks:** `ensure_own_file` [`ralphie.sh:469`](../ralphie.sh#L469).



### `rebuild_state_from_ledger` — 472–517

**LEDGER; scope: global; EXTRACTED.** Reconstruct cycle counters and cycle elapsed time from retained event generations. [`ralphie.sh:472–517`](../ralphie.sh#L472)

- **Inputs [EXTRACTED]:** EVENTS_FILE and numeric generations; RUN_DIR scratch path; state writer.

- **Outputs [EXTRACTED]:** Restores max cycle, pass_count, fail_count and positive unverified/blocked/untrusted/learned/time totals; emits a rebuilt event and warning.

- **Side effects [EXTRACTED]:** Creates/deletes ledger-all.$$ scratch, rewrites selected state keys, appends one event.

- **Invariants and scope [EXTRACTED]:** Only cycle timing records contribute seconds; engine timing is excluded. Run-specific token and recovery identity values are not guessed.

- **Failure and recovery [INFERRED]:** Concat failure falls back to the current ledger. No positive cycle causes cleanup/return. Reconstruction is limited to retained textual matching records, not a full JSON replay.

- **Calls/callbacks:** `is_int` [`ralphie.sh:482`](../ralphie.sh#L482), [`ralphie.sh:503`](../ralphie.sh#L503); `count_of` [`ralphie.sh:484`](../ralphie.sh#L484), [`ralphie.sh:485`](../ralphie.sh#L485), [`ralphie.sh:486`](../ralphie.sh#L486), [`ralphie.sh:487`](../ralphie.sh#L487), [`ralphie.sh:488`](../ralphie.sh#L488), [`ralphie.sh:489`](../ralphie.sh#L489); `state_set` [`ralphie.sh:505`](../ralphie.sh#L505), [`ralphie.sh:506`](../ralphie.sh#L506), [`ralphie.sh:507`](../ralphie.sh#L507), [`ralphie.sh:508`](../ralphie.sh#L508), [`ralphie.sh:509`](../ralphie.sh#L509), [`ralphie.sh:510`](../ralphie.sh#L510), [`ralphie.sh:511`](../ralphie.sh#L511), [`ralphie.sh:512`](../ralphie.sh#L512); `warn` [`ralphie.sh:515`](../ralphie.sh#L515); `event` [`ralphie.sh:516`](../ralphie.sh#L516).

- **Shell/host commands:** `cat`, `cp`, `grep`, `sed`, `sort`, `tail`, `awk`, `rm`.



### `ledger_init` — 519–546

**LEDGER; scope: global; EXTRACTED.** Initialize/repair shared runtime storage without claiming ownership of a run. [`ralphie.sh:519–546`](../ralphie.sh#L519)

- **Inputs [EXTRACTED]:** Runtime paths and existing state/events.

- **Outputs [EXTRACTED]:** Fills missing cycle/pass_count/fail_count/status/started_at defaults; may recover retained counters.

- **Side effects [EXTRACTED]:** Creates directories, repairs owned files, writes missing state, may append recovery events. Does not set OWNS_RUN or make pre-dirty snapshots.

- **Invariants and scope [EXTRACTED]:** Existing nonempty default keys are left unchanged. Rebuild occurs only for empty state with a nonempty current ledger.

- **Failure and recovery [EXTRACTED]:** This initializer can mutate storage even for commands described as read-only in comments. Discover/help/version bypass it in main; general status does not. Repair/write helpers keep their own failure behavior.

- **Calls/callbacks:** `ensure_dirs` [`ralphie.sh:525`](../ralphie.sh#L525); `ensure_state_file` [`ralphie.sh:526`](../ralphie.sh#L526); `ensure_gates_file` [`ralphie.sh:527`](../ralphie.sh#L527); `ensure_ask_file` [`ralphie.sh:528`](../ralphie.sh#L528); `ensure_own_file` [`ralphie.sh:529`](../ralphie.sh#L529), [`ralphie.sh:530`](../ralphie.sh#L530), [`ralphie.sh:531`](../ralphie.sh#L531); `rebuild_state_from_ledger` [`ralphie.sh:535`](../ralphie.sh#L535); `state_get` [`ralphie.sh:543`](../ralphie.sh#L543), [`ralphie.sh:545`](../ralphie.sh#L545); `state_set` [`ralphie.sh:543`](../ralphie.sh#L543), [`ralphie.sh:545`](../ralphie.sh#L545); `now_iso` [`ralphie.sh:545`](../ralphie.sh#L545).



### `run_init` — 548–564

**LEDGER; scope: global; EXTRACTED.** Start run-owned bookkeeping and remove stale per-PID scratch files. [`ralphie.sh:548–564`](../ralphie.sh#L548)

- **Inputs [EXTRACTED]:** RUN_DIR; timestamp/random token; caller-held run lock is an ordering precondition.

- **Outputs [EXTRACTED]:** Sets RUN_ID_MEM and OWNS_RUN1; writes run_id, run_tokens0 and run_cost0.

- **Side effects [EXTRACTED]:** Deletes matching stale pre-dirty/staged/index/committed/commit-error artifacts; writes state.

- **Invariants and scope [EXTRACTED]:** Ownership is enabled only after run identity and usage reset are attempted. No snapshot is made here.

- **Failure and recovery [EXTRACTED]:** Scratch deletion is best effort. Lock ownership is not checked inside this function; run_prepare supplies that ordering.

- **Calls/callbacks:** `stamp` [`ralphie.sh:559`](../ralphie.sh#L559); `rand_token` [`ralphie.sh:559`](../ralphie.sh#L559); `state_set` [`ralphie.sh:560`](../ralphie.sh#L560), [`ralphie.sh:561`](../ralphie.sh#L561), [`ralphie.sh:562`](../ralphie.sh#L562).

- **Shell/host commands:** `rm`, `cut`.



### `ensure_ignored` — 567–585

**LEDGER; scope: global; EXTRACTED.** Exclude Ralphie runtime storage using local Git exclusion metadata. [`ralphie.sh:567–585`](../ralphie.sh#L567)

- **Inputs [EXTRACTED]:** PROJECT, HOME_DIR/state, Git repository discovery and .git/info/exclude.

- **Outputs [EXTRACTED]:** No machine stdout; optional debug message.

- **Side effects [EXTRACTED]:** May create Git info directory and append a comment plus .ralphie/ exclusion.

- **Invariants and scope [EXTRACTED]:** Does not edit the tracked .gitignore. An existing effective ignore rule avoids a duplicate append.

- **Failure and recovery [EXTRACTED]:** No repository, failed metadata resolution/directory creation, or append failure is tolerated without aborting the caller.

- **Calls/callbacks:** `git_ready` [`ralphie.sh:574`](../ralphie.sh#L574); `dbg` [`ralphie.sh:584`](../ralphie.sh#L584).

- **Shell/host commands:** `git`, `mkdir`, `grep`, `printf`.



### `prune_artifacts` — 587–612

**LEDGER; scope: global; EXTRACTED.** Prune old numbered cycle artifacts and then consider ledger rotation. [`ralphie.sh:587–612`](../ralphie.sh#L587)

- **Inputs [EXTRACTED]:** State cycle, RALPHIE_KEEP_CYCLES default50, LOG_DIR and RUN_DIR.

- **Outputs [EXTRACTED]:** No normal stdout; delegates rotation result.

- **Side effects [EXTRACTED]:** Deletes old cycle log/answer/prompt and associated before/after gate captures.

- **Invariants and scope [EXTRACTED]:** Walks backward from cycle-minus-keep and stops at the first cycle missing all three primary artifacts.

- **Failure and recovery [EXTRACTED]:** Invalid keep becomes50. Deletion errors are suppressed; gaps can stop pruning older leftovers.

- **Calls/callbacks:** `json_num` [`ralphie.sh:593`](../ralphie.sh#L593); `is_int` [`ralphie.sh:593`](../ralphie.sh#L593), [`ralphie.sh:594`](../ralphie.sh#L594); `rotate_ledger` [`ralphie.sh:611`](../ralphie.sh#L611).

- **Shell/host commands:** `rm`.



### `rotate_ledger` — 614–638

**LEDGER; scope: global; EXTRACTED.** Rotate an oversized current ledger into bounded numbered generations. [`ralphie.sh:614–638`](../ralphie.sh#L614)

- **Inputs [EXTRACTED]:** EVENTS_FILE size, RALPHIE_LEDGER_MAX default16777216, RALPHIE_LEDGER_GENERATIONS default5.

- **Outputs [EXTRACTED]:** Optional appended ledger-rotated event in a new current file; returns0 on normal/early paths.

- **Side effects [EXTRACTED]:** Renames .n-1 to .n from high to low, then current to.1. The highest retained generation may be overwritten.

- **Invariants and scope [EXTRACTED]:** Current records are moved as a file rather than rewritten record by record. keep and loop index are initialized separately to avoid Bash dynamic-scope declaration leakage.

- **Failure and recovery [EXTRACTED]:** Failure moving the current ledger returns0. Rotation is finite retention rather than perpetual history. Retention environment values are not validated locally.

- **Calls/callbacks:** `file_bytes` [`ralphie.sh:618`](../ralphie.sh#L618); `event` [`ralphie.sh:636`](../ralphie.sh#L636).

- **Shell/host commands:** `mv`.



### `prune_sessions` — 640–652

**LEDGER; scope: global; EXTRACTED.** Delete oldest lexical session-directory entries beyond retention. [`ralphie.sh:640–652`](../ralphie.sh#L640)

- **Inputs [EXTRACTED]:** RUN_DIR/sessions, RALPHIE_KEEP_RUNS default5.

- **Outputs [EXTRACTED]:** No normal stdout.

- **Side effects [EXTRACTED]:** Lists/sorts entries and recursively removes the first count-minus-keep names.

- **Invariants and scope [EXTRACTED]:** No session directory or no excess entries is an early return. Invalid keep becomes5.

- **Failure and recovery [EXTRACTED]:** Deletion failures are suppressed. The line-based listing assumes generated session names, not arbitrary newline-containing paths.

- **Calls/callbacks:** `is_int` [`ralphie.sh:644`](../ralphie.sh#L644); `count_of` [`ralphie.sh:645`](../ralphie.sh#L645).

- **Shell/host commands:** `ls`, `sort`, `head`, `rm`.



### `mark_tree` — 654–654

**LEDGER; scope: global; EXTRACTED.** Touch the work-change timestamp marker. [`ralphie.sh:654`](../ralphie.sh#L654)

- **Inputs [EXTRACTED]:** RUN_DIR.

- **Outputs [EXTRACTED]:** Returns0.

- **Side effects [EXTRACTED]:** Creates RUN_DIR and truncates/creates tree.mark.

- **Invariants and scope [EXTRACTED]:** Marker path is owned runtime storage.

- **Failure and recovery [EXTRACTED]:** Both mkdir and marker-write failure are suppressed.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `mkdir`.



### `tree_listing_digest` — 656–668

**LEDGER; scope: global; EXTRACTED.** Digest the sorted set of non-noise regular-file pathnames. [`ralphie.sh:656–668`](../ralphie.sh#L656)

- **Inputs [EXTRACTED]:** PROJECT and NOISE_DIRS.

- **Outputs [EXTRACTED]:** Hash text from the pathname listing.

- **Side effects [EXTRACTED]:** Walks the project filesystem; no file contents are hashed.

- **Invariants and scope [EXTRACTED]:** Every name in NOISE_DIRS is pruned by find; remaining regular-file pathnames are listed. The name predicate applies to any matching entry, not just directories.

- **Failure and recovery [INFERRED]:** Failed cd produces an empty listing; find errors are suppressed. Newline-delimited names and the weak digest fallback limit this to a change heuristic.

- **Calls/callbacks:** `sha_of` [`ralphie.sh:667`](../ralphie.sh#L667).

- **Shell/host commands:** `cd`, `find`, `sort`.



### `mark_verify` — 670–674

**LEDGER; scope: global; EXTRACTED.** Record the current verification marker and file-set digest. [`ralphie.sh:670–674`](../ralphie.sh#L670)

- **Inputs [EXTRACTED]:** RUN_DIR and project filesystem through tree_listing_digest.

- **Outputs [EXTRACTED]:** Sets LAST_VERIFY_LISTING.

- **Side effects [EXTRACTED]:** Creates/truncates verify.mark; creates RUN_DIR.

- **Invariants and scope [EXTRACTED]:** Both timestamp and pathname-set evidence are captured.

- **Failure and recovery [EXTRACTED]:** Marker creation failure is suppressed; later missing-marker checks make the cache stale.

- **Calls/callbacks:** `tree_listing_digest` [`ralphie.sh:673`](../ralphie.sh#L673).

- **Shell/host commands:** `mkdir`.



### `verify_mark_stale` — 676–683

**LEDGER; scope: global; EXTRACTED.** Tell callers whether filesystem evidence invalidates a cached verdict. [`ralphie.sh:676–683`](../ralphie.sh#L676)

- **Inputs [EXTRACTED]:** RUN_DIR/verify.mark, LAST_VERIFY_LISTING, current non-noise regular files.

- **Outputs [EXTRACTED]:** Status0 for missing marker, a newer file, or changed pathname digest; nonzero otherwise.

- **Side effects [EXTRACTED]:** Filesystem reads only.

- **Invariants and scope [EXTRACTED]:** Deletion is observable through the listing digest even when find -newer cannot report it.

- **Failure and recovery [INFERRED]:** This is timestamp/name-set evidence, not exhaustive content freshness or a concurrency barrier.

- **Calls/callbacks:** `find_changed_since` [`ralphie.sh:681`](../ralphie.sh#L681); `tree_listing_digest` [`ralphie.sh:682`](../ralphie.sh#L682).

- **Shell/host commands:** `head`.



### `find_changed_since` — 697–705

**LEDGER; scope: global; EXTRACTED.** List regular project files newer than a supplied marker. [`ralphie.sh:697–705`](../ralphie.sh#L697)

- **Inputs [EXTRACTED]:** Marker argument, PROJECT, NOISE_DIRS.

- **Outputs [EXTRACTED]:** Newline-delimited find paths relative to project root.

- **Side effects [EXTRACTED]:** Filesystem metadata reads only.

- **Invariants and scope [EXTRACTED]:** Captures marker before replacing positional arguments with the find predicate. Every matching NOISE_DIRS name is pruned before regular-file testing.

- **Failure and recovery [EXTRACTED]:** Failed cd exits the subshell successfully with no output; find errors are hidden.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `cd`, `find`.



### `tree_touched` — 707–716

**LEDGER; scope: global; EXTRACTED.** Check the work-change marker for any newer non-noise regular file. [`ralphie.sh:707–716`](../ralphie.sh#L707)

- **Inputs [EXTRACTED]:** RUN_DIR/tree.mark and project filesystem.

- **Outputs [EXTRACTED]:** Status0 if marker missing or a newer path exists;1 otherwise.

- **Side effects [EXTRACTED]:** Filesystem reads only.

- **Invariants and scope [EXTRACTED]:** Absence of the marker is treated as changed.

- **Failure and recovery [EXTRACTED]:** Deletions alone are not detected by this function. Timestamp granularity remains a filesystem property.

- **Calls/callbacks:** `find_changed_since` [`ralphie.sh:715`](../ralphie.sh#L715).

- **Shell/host commands:** `head`.



### `work_changed` — 718–725

**LEDGER; scope: global; EXTRACTED.** Combine the Git/runtime fingerprint with filesystem modification evidence. [`ralphie.sh:718–725`](../ralphie.sh#L718)

- **Inputs [EXTRACTED]:** Before-fingerprint argument, current PROJECT/runtime state and tree.mark.

- **Outputs [EXTRACTED]:** Status0 when fingerprint differs or tree_touched succeeds.

- **Side effects [EXTRACTED]:** Filesystem/Git reads through helpers.

- **Invariants and scope [EXTRACTED]:** Either signal is sufficient to report change.

- **Failure and recovery [INFERRED]:** The check inherits the coverage limits of fingerprint and tree_touched; it is not a content snapshot.

- **Calls/callbacks:** `fingerprint` [`ralphie.sh:723`](../ralphie.sh#L723); `tree_touched` [`ralphie.sh:724`](../ralphie.sh#L724).



### `fingerprint` — 730–742

**LEDGER; scope: global; EXTRACTED.** Digest Git-visible state together with gate and objective bytes. [`ralphie.sh:730–742`](../ralphie.sh#L730)

- **Inputs [EXTRACTED]:** PROJECT repository, GATES_FILE, OBJECTIVE_FILE.

- **Outputs [EXTRACTED]:** Digest of HEAD/status/diff/gates/objective concatenated output.

- **Side effects [EXTRACTED]:** Runs Git reads and reads two runtime files.

- **Invariants and scope [EXTRACTED]:** Tracked content differences are included through git diff HEAD, not only status letters.

- **Failure and recovery [EXTRACTED]:** Git/read errors are tolerated. It does not hash all untracked/ignored content; it must be combined with timestamp/listing signals for cache decisions.

- **Calls/callbacks:** `sha_of` [`ralphie.sh:741`](../ralphie.sh#L741).

- **Shell/host commands:** `git`, `printf`, `cat`.



### `lock_acquire` — 748–799

**LEDGER; scope: global; EXTRACTED.** Acquire the per-project run lock and reject an apparently live owner. [`ralphie.sh:748–799`](../ralphie.sh#L748)

- **Inputs [EXTRACTED]:** HOME_DIR, LOCK_FILE, process PID/time, existing pid/token/since files, process table.

- **Outputs [EXTRACTED]:** LOCK_HELD1 on success; explicit1 on unwritable storage, live owner, acquisition failure or token race loss.

- **Side effects [EXTRACTED]:** Creates lock directory/metadata, waits for a possibly starting owner, may recursively remove stale lock, writes a fresh token.

- **Invariants and scope [EXTRACTED]:** Fresh acquisition uses atomic mkdir; stale takeover waits and compares a surviving random token. kill0 and ps both count as liveness evidence.

- **Failure and recovery [INFERRED]:** No lock capability is provided by the OS beyond mkdir. PID reuse, filesystem concurrency and stale-takeover races are not ruled out by static reading.

- **Calls/callbacks:** `err` [`ralphie.sh:753`](../ralphie.sh#L753), [`ralphie.sh:769`](../ralphie.sh#L769), [`ralphie.sh:776`](../ralphie.sh#L776), [`ralphie.sh:777`](../ralphie.sh#L777), [`ralphie.sh:787`](../ralphie.sh#L787), [`ralphie.sh:795`](../ralphie.sh#L795); `rand_token` [`ralphie.sh:759`](../ralphie.sh#L759), [`ralphie.sh:785`](../ralphie.sh#L785); `now_iso` [`ralphie.sh:760`](../ralphie.sh#L760), [`ralphie.sh:790`](../ralphie.sh#L790); `warn` [`ralphie.sh:784`](../ralphie.sh#L784).

- **Shell/host commands:** `mkdir`, `printf`, `cat`, `sleep`, `kill`, `ps`, `rm`.



### `lock_release` — 802–802

**LEDGER; scope: global; EXTRACTED.** Release the lock when this process records ownership. [`ralphie.sh:802`](../ralphie.sh#L802)

- **Inputs [EXTRACTED]:** LOCK_HELD, LOCK_FILE.

- **Outputs [EXTRACTED]:** Sets LOCK_HELD0 and returns0.

- **Side effects [EXTRACTED]:** Recursively removes LOCK_FILE when the flag is1.

- **Invariants and scope [EXTRACTED]:** The in-memory flag gates removal.

- **Failure and recovery [EXTRACTED]:** Removal errors are suppressed; release does not recheck the stored token.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `rm`.



### `track_pid` — 809–809

**LEDGER; scope: global; EXTRACTED.** Add a child PID to the in-memory cleanup list. [`ralphie.sh:809`](../ralphie.sh#L809)

- **Inputs [EXTRACTED]:** PID argument and CHILD_PIDS.

- **Outputs [EXTRACTED]:** Updated space-delimited CHILD_PIDS.

- **Side effects [EXTRACTED]:** In-memory mutation only.

- **Invariants and scope [EXTRACTED]:** PIDs are retained for later cleanup.

- **Failure and recovery [EXTRACTED]:** No validation or deduplication of supplied PID.

- **Calls/callbacks:** No repository-function callback in this body.



### `untrack_pid` — 810–810

**LEDGER; scope: global; EXTRACTED.** Remove a child PID from the cleanup list. [`ralphie.sh:810`](../ralphie.sh#L810)

- **Inputs [EXTRACTED]:** PID argument and CHILD_PIDS.

- **Outputs [EXTRACTED]:** Updated space-delimited CHILD_PIDS.

- **Side effects [EXTRACTED]:** Runs text filters and updates memory.

- **Invariants and scope [EXTRACTED]:** Exact whole-line matching removes the PID after space splitting.

- **Failure and recovery [EXTRACTED]:** An empty resulting list remains representable. The function returns its text pipeline status; PID input is expected to be internal numeric text.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `printf`, `tr`, `grep`.



### `child_pids_of` — 812–822

**LEDGER; scope: global; EXTRACTED.** Find direct children of a PID using available process tools. [`ralphie.sh:812–822`](../ralphie.sh#L812)

- **Inputs [EXTRACTED]:** Parent PID and pgrep availability/process table.

- **Outputs [EXTRACTED]:** Child PIDs, one per line.

- **Side effects [EXTRACTED]:** Process-table reads.

- **Invariants and scope [EXTRACTED]:** pgrep -P is preferred; ps/awk is the fallback.

- **Failure and recovery [EXTRACTED]:** Process-read errors yield no children through OR true. A changing process tree is not frozen.

- **Calls/callbacks:** `have` [`ralphie.sh:817`](../ralphie.sh#L817).

- **Shell/host commands:** `pgrep`, `ps`, `awk`.



### `kill_tree` — 824–829

**LEDGER; scope: global; EXTRACTED.** Recursively signal a process and its currently visible descendants. [`ralphie.sh:824–829`](../ralphie.sh#L824)

- **Inputs [EXTRACTED]:** PID and optional signal defaultTERM.

- **Outputs [EXTRACTED]:** Returns successful best-effort cleanup.

- **Side effects [EXTRACTED]:** Signals descendants before the supplied PID.

- **Invariants and scope [EXTRACTED]:** Child discovery precedes signalling the parent at each recursive level.

- **Failure and recovery [INFERRED]:** Signal failures are suppressed; detached/reparented children may escape this traversal.

- **Calls/callbacks:** `child_pids_of` [`ralphie.sh:827`](../ralphie.sh#L827); `kill_tree` [`ralphie.sh:827`](../ralphie.sh#L827).

- **Shell/host commands:** `kill`.



### `terminate_tree` — 831–847

**LEDGER; scope: global; EXTRACTED.** Snapshot descendants, send TERM, then send KILL after a grace period. [`ralphie.sh:831–847`](../ralphie.sh#L831)

- **Inputs [EXTRACTED]:** Root PID and process table.

- **Outputs [EXTRACTED]:** No normal stdout.

- **Side effects [EXTRACTED]:** Builds a PID list; signals process group and each captured PID with TERM, sleeps2, then KILLs group/list.

- **Invariants and scope [EXTRACTED]:** Descendants are enumerated before the root is terminated so immediate reparenting does not erase already found children.

- **Failure and recovery [EXTRACTED]:** Kill errors are ignored. It does not wait/reap the process, freeze PID identity, or discover descendants created after the snapshot.

- **Calls/callbacks:** `child_pids_of` [`ralphie.sh:840`](../ralphie.sh#L840).

- **Shell/host commands:** `kill`, `sleep`.



### `reap_children` — 849–859

**LEDGER; scope: global; EXTRACTED.** Terminate tracked children that still appear live. [`ralphie.sh:849–859`](../ralphie.sh#L849)

- **Inputs [EXTRACTED]:** CHILD_PIDS and process liveness.

- **Outputs [EXTRACTED]:** Clears CHILD_PIDS.

- **Side effects [EXTRACTED]:** Runs terminate_tree for each PID passing kill0.

- **Invariants and scope [EXTRACTED]:** Cleanup walks the recorded list, then resets it.

- **Failure and recovery [EXTRACTED]:** No wait is performed here. Processes failing kill0 are skipped.

- **Calls/callbacks:** `terminate_tree` [`ralphie.sh:856`](../ralphie.sh#L856).

- **Shell/host commands:** `kill`.



### `on_exit` — 863–886

**LEDGER; scope: global; EXTRACTED.** Perform EXIT cleanup while preserving run/error bookkeeping and SIGPIPE status. [`ralphie.sh:863–886`](../ralphie.sh#L863)

- **Inputs [EXTRACTED]:** Original shell status, SIGPIPE_SEEN, OWNS_RUN, INTERRUPTED and state status.

- **Outputs [EXTRACTED]:** May set state status error and append an exit event; explicit exit141 when SIGPIPE was seen.

- **Side effects [EXTRACTED]:** Records owned dirty paths if this is a run, reaps children, releases lock, may write state/events.

- **Invariants and scope [EXTRACTED]:** Non-run commands do not claim run ownership or rewrite run status. SIGPIPE overrides the observed code to141.

- **Failure and recovery [INFERRED]:** Bookkeeping is best effort. EXIT traps do not run on SIGKILL or machine failure; this code is not a power-loss durability proof.

- **Calls/callbacks:** `record_owned_paths` [`ralphie.sh:872`](../ralphie.sh#L872); `reap_children` [`ralphie.sh:873`](../ralphie.sh#L873); `lock_release` [`ralphie.sh:874`](../ralphie.sh#L874); `state_get` [`ralphie.sh:879`](../ralphie.sh#L879), [`ralphie.sh:881`](../ralphie.sh#L881); `state_set` [`ralphie.sh:880`](../ralphie.sh#L880); `event` [`ralphie.sh:880`](../ralphie.sh#L880), [`ralphie.sh:881`](../ralphie.sh#L881).

- **Shell/host commands:** `exit`.



### `on_int` — 888–903

**LEDGER; scope: global; EXTRACTED.** Stop an interrupted run and exit with conventional interrupt status. [`ralphie.sh:888–903`](../ralphie.sh#L888)

- **Inputs [EXTRACTED]:** INT/TERM/HUP trap delivery, OWNS_RUN and tracked process state.

- **Outputs [EXTRACTED]:** Sets INTERRUPTED1; owned run status stopped and interrupted event; exits130.

- **Side effects [EXTRACTED]:** Writes console/ledger/state, records owned work, reaps children and releases lock.

- **Invariants and scope [EXTRACTED]:** The human channel is not read; interruption uses automated cleanup.

- **Failure and recovery [EXTRACTED]:** Best-effort cleanup precedes exit130 for all three registered signals, not signal-specific143/129.

- **Calls/callbacks:** `say` [`ralphie.sh:890`](../ralphie.sh#L890); `warn` [`ralphie.sh:891`](../ralphie.sh#L891); `record_owned_paths` [`ralphie.sh:896`](../ralphie.sh#L896); `state_set` [`ralphie.sh:897`](../ralphie.sh#L897); `event` [`ralphie.sh:898`](../ralphie.sh#L898); `reap_children` [`ralphie.sh:900`](../ralphie.sh#L900); `lock_release` [`ralphie.sh:901`](../ralphie.sh#L901).

- **Shell/host commands:** `exit`.



### `on_pipe` — 904–911

**LEDGER; scope: global; EXTRACTED.** Retire a broken stdout pipe without exiting inside the signal trap. [`ralphie.sh:904–911`](../ralphie.sh#L904)

- **Inputs [EXTRACTED]:** PIPE delivery or terminal_printf detection.

- **Outputs [EXTRACTED]:** Sets SIGPIPE_SEEN1; redirects future stdout to /dev/null.

- **Side effects [EXTRACTED]:** Changes file descriptor1 for the current shell.

- **Invariants and scope [EXTRACTED]:** Defers final exit141 to on_exit to avoid Bash3.2 buffered-write corruption described in the source.

- **Failure and recovery [EXTRACTED]:** The redirect has no local fallback if it fails. After a successful redirect the function latches the flag without an immediate exit.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `exec`.



### `install_traps` — 912–916

**LEDGER; scope: global; EXTRACTED.** Register the shared exit, interrupt and pipe callbacks. [`ralphie.sh:912–916`](../ralphie.sh#L912)

- **Inputs [EXTRACTED]:** Current shell trap table.

- **Outputs [EXTRACTED]:** Installed EXIT, INT, TERM, HUP and PIPE handlers.

- **Side effects [EXTRACTED]:** Overwrites handlers for those signals/events.

- **Invariants and scope [EXTRACTED]:** EXIT and signal cleanup are centralized.

- **Failure and recovery [EXTRACTED]:** Signal-delivery behavior remains controlled by Bash and the operating system.

- **Calls/callbacks:** `trap:on_exit` [`ralphie.sh:913`](../ralphie.sh#L913); `trap:on_int` [`ralphie.sh:914`](../ralphie.sh#L914); `trap:on_pipe` [`ralphie.sh:915`](../ralphie.sh#L915).

- **Shell/host commands:** `trap`.



### `pkg_manager` — 930–936

**PROJECT; scope: global; EXTRACTED.** Choose a JavaScript package manager from root lockfile presence. [`ralphie.sh:930–936`](../ralphie.sh#L930)

- **Inputs [EXTRACTED]:** PROJECT/bun.lockb or bun.lock, pnpm-lock.yaml, yarn.lock.

- **Outputs [EXTRACTED]:** bun, pnpm, yarn, or default npm.

- **Side effects [EXTRACTED]:** Filesystem existence checks only.

- **Invariants and scope [EXTRACTED]:** Priority is bun, pnpm, yarn, npm.

- **Failure and recovery [EXTRACTED]:** No executable, lockfile validity or multi-workspace check is performed.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `printf`.



### `has_npm_script` — 938–951

**PROJECT; scope: global; EXTRACTED.** Check a root package script using an available JSON parser or a loose text fallback. [`ralphie.sh:938–951`](../ralphie.sh#L938)

- **Inputs [EXTRACTED]:** Script name, PROJECT/package.json, availability of node/python3.

- **Outputs [EXTRACTED]:** Status0 for a truthy named script according to the selected parser, otherwise1 or grep status.

- **Side effects [EXTRACTED]:** Runs a short Node or Python parser; otherwise reads text through grep.

- **Invariants and scope [EXTRACTED]:** Parsers inspect scripts, while grep only proposes a likely key.

- **Failure and recovery [EXTRACTED]:** A selected parser failure returns1 without trying the later parser; malformed JSON produces no diagnostic. Candidate execution occurs later in gate_trial.

- **Calls/callbacks:** `have` [`ralphie.sh:944`](../ralphie.sh#L944), [`ralphie.sh:946`](../ralphie.sh#L946).

- **Shell/host commands:** `node`, `python3`, `grep`.



### `has_make_target` — 953–956

**PROJECT; scope: global; EXTRACTED.** Look for an explicitly written Make target in root Makefiles. [`ralphie.sh:953–956`](../ralphie.sh#L953)

- **Inputs [EXTRACTED]:** Target name, PROJECT/Makefile and makefile.

- **Outputs [EXTRACTED]:** grep status for an anchored target-name pattern.

- **Side effects [EXTRACTED]:** Reads Makefiles as text; does not run make.

- **Invariants and scope [EXTRACTED]:** Requires at least one regular Makefile path.

- **Failure and recovery [EXTRACTED]:** Missing alternate file errors are hidden; this is text detection rather than Make syntax evaluation.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `grep`.



### `py_runner` — 958–967

**PROJECT; scope: global; EXTRACTED.** Choose a command prefix for a Python project tool. [`ralphie.sh:958–967`](../ralphie.sh#L958)

- **Inputs [EXTRACTED]:** Tool name, project .venv/venv executable paths, uv.lock and PATH.

- **Outputs [EXTRACTED]:** Relative virtualenv tool path, uv run TOOL, global TOOL, or empty string.

- **Side effects [EXTRACTED]:** Existence/executability checks only.

- **Invariants and scope [EXTRACTED]:** Project virtualenv executables precede uv and global tools.

- **Failure and recovery [EXTRACTED]:** No selected tool is run or health-checked here.

- **Calls/callbacks:** `have` [`ralphie.sh:963`](../ralphie.sh#L963), [`ralphie.sh:964`](../ralphie.sh#L964).

- **Shell/host commands:** `printf`.



### `detect_stack` — 969–990

**PROJECT; scope: global; EXTRACTED.** Infer a space-separated stack tag list from root metadata. [`ralphie.sh:969–990`](../ralphie.sh#L969)

- **Inputs [EXTRACTED]:** Known manifest paths, *.tf/*.sh and .git directory presence under PROJECT.

- **Outputs [EXTRACTED]:** Tags node/typescript/python/rust/go/maven/gradle/ruby/php/elixir/deno/cmake/docker/terraform/make/shell/git as applicable.

- **Side effects [EXTRACTED]:** Filesystem and glob checks.

- **Invariants and scope [EXTRACTED]:** Multiple stack tags can coexist; tag order is not declared significant.

- **Failure and recovery [INFERRED]:** Root-only heuristics do not prove tool availability or project correctness. The git tag requires a directory even though Git worktrees can use a file.

- **Calls/callbacks:** `trim` [`ralphie.sh:989`](../ralphie.sh#L989).

- **Shell/host commands:** `ls`.



### `discover_candidates` — 994–1008

**PROJECT; scope: global/subshell; EXTRACTED.** Preview candidate gate text using subshell-local text-only manifest helpers. [`ralphie.sh:994–1008`](../ralphie.sh#L994)

- **Inputs [EXTRACTED]:** PROJECT metadata and parent helper functions.

- **Outputs [EXTRACTED]:** Candidate shell command lines; returns0 through OR true.

- **Side effects [EXTRACTED]:** Defines two helper overrides only inside this subshell; no gate commands are executed.

- **Invariants and scope [EXTRACTED]:** The local overrides prevent Node/Python package parsing during discovery preview and do not replace runtime helpers in the parent.

- **Failure and recovery [EXTRACTED]:** Candidate-generation failure is suppressed for the preview.

- **Calls/callbacks:** `has_npm_script` (scoped definition) [`ralphie.sh:995–998`](../ralphie.sh#L995); `has_make_target` (scoped definition) [`ralphie.sh:999–1006`](../ralphie.sh#L999); `gate_candidates` [`ralphie.sh:1007`](../ralphie.sh#L1007).



### `has_npm_script` — 995–998

**PROJECT; scope: discover_candidates subshell; EXTRACTED.** Preview a possible package script through a readable-file text match. [`ralphie.sh:995–998`](../ralphie.sh#L995)

- **Inputs [EXTRACTED]:** Script name and PROJECT/package.json.

- **Outputs [EXTRACTED]:** Status0 on key-pattern match; nonzero otherwise.

- **Side effects [EXTRACTED]:** Reads package.json through grep only.

- **Invariants and scope [EXTRACTED]:** This definition exists inside discover_candidates and bypasses JSON parser execution.

- **Failure and recovery [INFERRED]:** False-positive key matches are possible because this is a preview heuristic, not JSON validation.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `grep`.



### `has_make_target` — 999–1006

**PROJECT; scope: discover_candidates subshell; EXTRACTED.** Preview a Make target while skipping absent or unreadable Makefiles. [`ralphie.sh:999–1006`](../ralphie.sh#L999)

- **Inputs [EXTRACTED]:** Target name, PROJECT/Makefile and makefile.

- **Outputs [EXTRACTED]:** Status0 on the first anchored match;1 if neither readable file matches.

- **Side effects [EXTRACTED]:** Reads text through grep only.

- **Invariants and scope [EXTRACTED]:** This definition is scoped to discover_candidates.

- **Failure and recovery [EXTRACTED]:** Unreadable files are skipped without invocation or diagnostics.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `grep`.



### `discover_git` — 1013–1020

**PROJECT; scope: global; EXTRACTED.** Run the limited discovery Git query with selected execution/network side effects disabled. [`ralphie.sh:1013–1020`](../ralphie.sh#L1013)

- **Inputs [EXTRACTED]:** Git argv, PROJECT and configured filter.*.(clean|process) keys.

- **Outputs [EXTRACTED]:** Passes Git stdout/stderr/status to its caller.

- **Side effects [EXTRACTED]:** Reads Git config; runs Git with core.fsmonitor=false, core.untrackedCache=false, configured clean/process filters cleared, GIT_OPTIONAL_LOCKS0 and GIT_NO_LAZY_FETCH1.

- **Invariants and scope [EXTRACTED]:** Overrides apply to this command, not global Git configuration or subsequent gates.

- **Failure and recovery [INFERRED]:** This is source-level suppression of identified Git mechanisms, not a general sandbox or proof against every external filesystem/provider behavior.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `git`.



### `cmd_discover` — 1022–1079

**PROJECT; scope: global/subshell; EXTRACTED.** Print a project discovery report without starting a run. [`ralphie.sh:1022–1079`](../ralphie.sh#L1022)

- **Inputs [EXTRACTED]:** REST must be empty; PROJECT metadata, existing objective/gate files, engine table/presence.

- **Outputs [EXTRACTED]:** Human-readable Git/stack/instruction/plan/objective/gate/candidate/engine report; failure if arguments or project directory invalid.

- **Side effects [EXTRACTED]:** Uses a subshell cd and reads local files/Git metadata; no ledger initializer, gate trial or engine liveness call occurs here.

- **Invariants and scope [EXTRACTED]:** Reports configured gates and candidate gates distinctly. Explicit text states engines are not checked for auth or health.

- **Failure and recovery [EXTRACTED]:** An unreadable gate file is reported; arbitrary gate text is not executed. File/Git read errors are mostly suppressed and can limit the report.

- **Calls/callbacks:** `die` [`ralphie.sh:1025`](../ralphie.sh#L1025), [`ralphie.sh:1026`](../ralphie.sh#L1026); `discover_git` [`ralphie.sh:1031`](../ralphie.sh#L1031), [`ralphie.sh:1033`](../ralphie.sh#L1033), [`ralphie.sh:1035`](../ralphie.sh#L1035), [`ralphie.sh:1037`](../ralphie.sh#L1037); `detect_stack` [`ralphie.sh:1045`](../ralphie.sh#L1045); `count_of` [`ralphie.sh:1056`](../ralphie.sh#L1056); `discover_candidates` [`ralphie.sh:1071`](../ralphie.sh#L1071); `engine_names` [`ralphie.sh:1076`](../ralphie.sh#L1076); `engine_present` [`ralphie.sh:1075`](../ralphie.sh#L1075); `say` [`ralphie.sh:1030`](../ralphie.sh#L1030), [`ralphie.sh:1032`](../ralphie.sh#L1032), [`ralphie.sh:1034`](../ralphie.sh#L1034), [`ralphie.sh:1035`](../ralphie.sh#L1035), [`ralphie.sh:1036`](../ralphie.sh#L1036), [`ralphie.sh:1038`](../ralphie.sh#L1038), [`ralphie.sh:1039`](../ralphie.sh#L1039), [`ralphie.sh:1040`](../ralphie.sh#L1040), [`ralphie.sh:1042`](../ralphie.sh#L1042), [`ralphie.sh:1043`](../ralphie.sh#L1043), [`ralphie.sh:1045`](../ralphie.sh#L1045), [`ralphie.sh:1046`](../ralphie.sh#L1046), [`ralphie.sh:1049`](../ralphie.sh#L1049), [`ralphie.sh:1051`](../ralphie.sh#L1051), [`ralphie.sh:1052`](../ralphie.sh#L1052), [`ralphie.sh:1057`](../ralphie.sh#L1057), [`ralphie.sh:1058`](../ralphie.sh#L1058), [`ralphie.sh:1061`](../ralphie.sh#L1061), [`ralphie.sh:1063`](../ralphie.sh#L1063), [`ralphie.sh:1064`](../ralphie.sh#L1064), [`ralphie.sh:1065`](../ralphie.sh#L1065), [`ralphie.sh:1067`](../ralphie.sh#L1067), [`ralphie.sh:1068`](../ralphie.sh#L1068), [`ralphie.sh:1069`](../ralphie.sh#L1069), [`ralphie.sh:1070`](../ralphie.sh#L1070), [`ralphie.sh:1072`](../ralphie.sh#L1072), [`ralphie.sh:1073`](../ralphie.sh#L1073), [`ralphie.sh:1075`](../ralphie.sh#L1075), [`ralphie.sh:1077`](../ralphie.sh#L1077), [`ralphie.sh:1078`](../ralphie.sh#L1078).

- **Shell/host commands:** `cd`, `pwd`, `printf`, `grep`, `sed`.



### `gate_candidates` — 1081–1141

**PROJECT; scope: global; EXTRACTED.** Emit root-level candidate health commands for recognized project stacks. [`ralphie.sh:1081–1141`](../ralphie.sh#L1081)

- **Inputs [EXTRACTED]:** Root manifests/lockfiles, Make targets, available Python runners and shell file markers.

- **Outputs [EXTRACTED]:** Ordered newline-delimited command strings for package scripts, Python, Cargo, Go, Deno, Elixir, Ruby, Maven, Gradle, Composer, Terraform, Make and shell checks.

- **Side effects [EXTRACTED]:** Reads project metadata; global has_npm_script may invoke JSON parsers. It does not execute the emitted checks.

- **Invariants and scope [EXTRACTED]:** Shell filenames are expanded when the gate runs rather than interpolated into source text. Ralphie copies identified by the first40-line marker are omitted.

- **Failure and recovery [INFERRED]:** Unsupported layouts and nested workspace members need explicit gates. Command presence/correctness is not guaranteed until trial/execution.

- **Calls/callbacks:** `pkg_manager` [`ralphie.sh:1085`](../ralphie.sh#L1085); `has_npm_script` [`ralphie.sh:1089`](../ralphie.sh#L1089), [`ralphie.sh:1090`](../ralphie.sh#L1090), [`ralphie.sh:1091`](../ralphie.sh#L1091), [`ralphie.sh:1092`](../ralphie.sh#L1092), [`ralphie.sh:1093`](../ralphie.sh#L1093), [`ralphie.sh:1094`](../ralphie.sh#L1094); `py_runner` [`ralphie.sh:1099`](../ralphie.sh#L1099), [`ralphie.sh:1100`](../ralphie.sh#L1100), [`ralphie.sh:1101`](../ralphie.sh#L1101); `has_make_target` [`ralphie.sh:1114`](../ralphie.sh#L1114), [`ralphie.sh:1115`](../ralphie.sh#L1115), [`ralphie.sh:1116`](../ralphie.sh#L1116).

- **Shell/host commands:** `printf`, `ls`, `head`, `grep`.



### `gate_tool_names` — 1179–1189

**PROJECT; scope: global; EXTRACTED.** Extract simple tool names used to recognize unavailable-candidate errors. [`ralphie.sh:1179–1189`](../ralphie.sh#L1179)

- **Inputs [EXTRACTED]:** Shell command string argument.

- **Outputs [EXTRACTED]:** Basename of its first split word and third word for a second-word -m invocation; returns0.

- **Side effects [EXTRACTED]:** Uses unquoted shell splitting and pathname expansion of the input string.

- **Invariants and scope [EXTRACTED]:** Only invoked tool/module names are intended to classify absence messages.

- **Failure and recovery [INFERRED]:** It is not a shell parser and cannot resolve general wrappers, quoting, compounds or dynamically selected commands.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `printf`.



### `gate_exec` — 1192–1211

**PROJECT; scope: global; EXTRACTED.** Execute one gate in the selected shell with capture, deadline and process cleanup. [`ralphie.sh:1192–1211`](../ralphie.sh#L1192)

- **Inputs [EXTRACTED]:** Command, output-file path, optional hard seconds default0; PROJECT, GATE_SH and GATE_PRELUDE.

- **Outputs [EXTRACTED]:** Merged stdout/stderr in the capture; return status stored in GATE_EXEC_RC.

- **Side effects [EXTRACTED]:** Enables job control to launch a background group, cd to project, exec shell -c, stdin /dev/null; tracks PID, waits via watchdog, then signals surviving process group/children.

- **Invariants and scope [EXTRACTED]:** The same executor is used by trial and measured gates. Idle timeout is0; the caller supplies hard timeout.

- **Failure and recovery [EXTRACTED]:** Gate commands run with inherited operator permissions and can mutate arbitrary reachable state. Watchdog returns real rc or124 for timeout; cleanup is best effort and not an isolation boundary.

- **Calls/callbacks:** `track_pid` [`ralphie.sh:1200`](../ralphie.sh#L1200); `watchdog_wait` [`ralphie.sh:1201`](../ralphie.sh#L1201); `untrack_pid` [`ralphie.sh:1202`](../ralphie.sh#L1202); `child_pids_of` [`ralphie.sh:1204`](../ralphie.sh#L1204); `kill_tree` [`ralphie.sh:1206`](../ralphie.sh#L1206); `$GATE_SH -c $GATE_PRELUDE$cmd` [`ralphie.sh:1197`](../ralphie.sh#L1197).

- **Shell/host commands:** `set`, `cd`, `exec`, `kill`, `sleep`.



### `gate_trial` — 1213–1249

**PROJECT; scope: global; EXTRACTED.** Run a candidate and reject unavailable tools while retaining ordinary failing checks. [`ralphie.sh:1213–1249`](../ralphie.sh#L1213)

- **Inputs [EXTRACTED]:** Command string, RUN_DIR, GATE_TRIAL_TIMEOUT default120.

- **Outputs [EXTRACTED]:** Returns2 for rc126/127 or a recognized absence line naming the invoked tool;0 otherwise.

- **Side effects [EXTRACTED]:** Creates/removes trial.$$ output and runs the candidate through gate_exec.

- **Invariants and scope [EXTRACTED]:** A runnable failing project check remains a candidate. Trial success means suitability, not a green project.

- **Failure and recovery [INFERRED]:** The message/tool-name heuristic can misclassify complex commands. Timeout124 is not rejected by the explicit unavailable cases. The timeout_cmd result is assigned but unused.

- **Calls/callbacks:** `timeout_cmd` [`ralphie.sh:1217`](../ralphie.sh#L1217); `gate_exec` [`ralphie.sh:1225`](../ralphie.sh#L1225); `gate_tool_names` [`ralphie.sh:1243`](../ralphie.sh#L1243).

- **Shell/host commands:** `mkdir`, `grep`, `printf`, `rm`.



### `discover_gates` — 1251–1310

**PROJECT; scope: global; EXTRACTED.** Discover and persist gate commands when no gate file exists or redetection is explicit. [`ralphie.sh:1251–1310`](../ralphie.sh#L1251)

- **Inputs [EXTRACTED]:** Force argument default0; GATES_FILE/HOME_DIR, candidate metadata and trial environment.

- **Outputs [EXTRACTED]:** Gate file with explanatory header, active commands and unavailable comments; gates-discovered event.

- **Side effects [EXTRACTED]:** May remove a dangling gate symlink, create runtime storage/temp file, execute every candidate trial, write through GATES_FILE and remove temp. No gate found records a nonblocking human question.

- **Invariants and scope [EXTRACTED]:** An existing regular gate file, including an empty one, is retained unless force1. Normal publication writes through the path to preserve supported symlinks.

- **Failure and recovery [EXTRACTED]:** The cat-to-gates publication falls back to mv. Candidate execution is real project code, not a dry scan. Missing gates remain explicitly unverified.

- **Calls/callbacks:** `ensure_gates_file` [`ralphie.sh:1255`](../ralphie.sh#L1255); `warn` [`ralphie.sh:1261`](../ralphie.sh#L1261), [`ralphie.sh:1300`](../ralphie.sh#L1300), [`ralphie.sh:1301`](../ralphie.sh#L1301); `info` [`ralphie.sh:1265`](../ralphie.sh#L1265); `gate_trial` [`ralphie.sh:1286`](../ralphie.sh#L1286); `dim` [`ralphie.sh:1287`](../ralphie.sh#L1287); `dbg` [`ralphie.sh:1289`](../ralphie.sh#L1289); `gate_candidates` [`ralphie.sh:1292`](../ralphie.sh#L1292); `ask_human` [`ralphie.sh:1302`](../ralphie.sh#L1302); `event` [`ralphie.sh:1308`](../ralphie.sh#L1308); `good` [`ralphie.sh:1309`](../ralphie.sh#L1309).

- **Shell/host commands:** `rm`, `mkdir`, `cat`, `printf`, `basename`, `mv`.



### `gates_list` — 1312–1316

**PROJECT; scope: global; EXTRACTED.** List active configured gate command lines. [`ralphie.sh:1312–1316`](../ralphie.sh#L1312)

- **Inputs [EXTRACTED]:** GATES_FILE and project path containment.

- **Outputs [EXTRACTED]:** All lines excluding whitespace-only and leading-whitespace comments; returns0 for missing/outside/nonregular/unmatched input.

- **Side effects [EXTRACTED]:** Reads gate file only after containment.

- **Invariants and scope [EXTRACTED]:** A gate is one noncomment shell-command line; text is returned verbatim otherwise.

- **Failure and recovery [EXTRACTED]:** Read errors are suppressed; broken readability is surfaced by ensure_gates_file/run_gates separately.

- **Calls/callbacks:** `gate_path_inside_project` [`ralphie.sh:1313`](../ralphie.sh#L1313).

- **Shell/host commands:** `grep`.



### `gates_count` — 1320–1320

**PROJECT; scope: global; EXTRACTED.** Count active configured gates safely. [`ralphie.sh:1320`](../ralphie.sh#L1320)

- **Inputs [EXTRACTED]:** gates_list result.

- **Outputs [EXTRACTED]:** Integer line count.

- **Side effects [EXTRACTED]:** Reads gate file through gates_list.

- **Invariants and scope [EXTRACTED]:** Empty lists become0 through the common counter.

- **Failure and recovery [EXTRACTED]:** Shares gates_list containment and empty-result behavior.

- **Calls/callbacks:** `count_of` [`ralphie.sh:1320`](../ralphie.sh#L1320); `gates_list` [`ralphie.sh:1320`](../ralphie.sh#L1320).



### `run_gates` — 1322–1422

**PROJECT; scope: global; EXTRACTED.** Measure the configured gates and record bounded per-gate evidence. [`ralphie.sh:1322–1422`](../ralphie.sh#L1322)

- **Inputs [EXTRACTED]:** Optional logbase default RUN_DIR/gates, phase default observe, GATE_TIMEOUT900, GATE_RETRIES1, GATE_LOG_MAX262144, current budget and gate file.

- **Outputs [EXTRACTED]:** Return0 if no failed commands, including no-gate mode; GATES_NONE disambiguates no evidence. Writes logbase.summary and numbered logs; sets failure/flaky/timeout globals.

- **Side effects [EXTRACTED]:** Repairs gate file, runs every active command, retries failed checks once when GATE_RETRIES>0, appends flaky event, deletes retry captures and truncates oversized primary logs to tails.

- **Invariants and scope [EXTRACTED]:** An unreadable gate file returns1, not UNVERIFIED. Verify phase ignores run-budget clamping and does not forgive fail-then-pass; observe can forgive that flake. Every configured gate is measured rather than stopping at first failure.

- **Failure and recovery [INFERRED]:** rc124 sets timeout metadata. GATE_RETRIES is only a boolean threshold for one retry, not a retry count. Timeout and log limits are assumed numeric here; log trimming is after execution and does not bound peak disk use. timeout_cmd is unused.

- **Calls/callbacks:** `timeout_cmd` [`ralphie.sh:1331`](../ralphie.sh#L1331); `ensure_gates_file` [`ralphie.sh:1339`](../ralphie.sh#L1339); `gates_count` [`ralphie.sh:1348`](../ralphie.sh#L1348); `dbg` [`ralphie.sh:1361`](../ralphie.sh#L1361), [`ralphie.sh:1371`](../ralphie.sh#L1371); `budget_cap` [`ralphie.sh:1363`](../ralphie.sh#L1363); `gate_exec` [`ralphie.sh:1364`](../ralphie.sh#L1364), [`ralphie.sh:1372`](../ralphie.sh#L1372); `event` [`ralphie.sh:1375`](../ralphie.sh#L1375); `warn` [`ralphie.sh:1386`](../ralphie.sh#L1386), [`ralphie.sh:1391`](../ralphie.sh#L1391); `dim` [`ralphie.sh:1387`](../ralphie.sh#L1387); `file_bytes` [`ralphie.sh:1402`](../ralphie.sh#L1402); `gates_list` [`ralphie.sh:1419`](../ralphie.sh#L1419).

- **Shell/host commands:** `mkdir`, `printf`, `rm`, `tail`, `mv`.



### `ensure_gates_file` — 1425–1437

**PROJECT; scope: global; EXTRACTED.** Check gate-path containment before applying owned-file repair. [`ralphie.sh:1425–1437`](../ralphie.sh#L1425)

- **Inputs [EXTRACTED]:** GATES_FILE and PROJECT.

- **Outputs [EXTRACTED]:** Sets GATES_FILE_BROKEN1 and returns0 on unresolved/outside target; otherwise shared repair result.

- **Side effects [EXTRACTED]:** May warn or repair an in-project gate path.

- **Invariants and scope [EXTRACTED]:** No repair is attempted through a path rejected by containment.

- **Failure and recovery [EXTRACTED]:** Unresolvable parent directories also count as broken. Caller must inspect the flag; rc0 alone is not readability proof.

- **Calls/callbacks:** `gate_path_inside_project` [`ralphie.sh:1431`](../ralphie.sh#L1431); `warn` [`ralphie.sh:1433`](../ralphie.sh#L1433); `ensure_own_file` [`ralphie.sh:1436`](../ralphie.sh#L1436).



### `baseline_gates_load` — 1439–1474

**PROJECT; scope: global; EXTRACTED.** Restore gate commands missing from the previous-run baseline. [`ralphie.sh:1439–1474`](../ralphie.sh#L1439)

- **Inputs [EXTRACTED]:** HOME_DIR/gates.baseline, GATES_FILE and path repair.

- **Outputs [EXTRACTED]:** Sets GATES_BASELINE_FILE; when missing entries exist sets GATES_SNAPSHOT; returns1 if ordered restore fails.

- **Side effects [EXTRACTED]:** May rewrite gate file, emits restore event/warning and queues a human review question.

- **Invariants and scope [EXTRACTED]:** Exact-line baseline membership persists between runs; intentional shrink needs explicit redetection to reset the baseline.

- **Failure and recovery [EXTRACTED]:** Unreadable/missing baseline or no missing entries avoids restore. Failure is reported as could-NOT-be-restored and returns1; event kind/status remains gates/restored even for the failure-detail branch.

- **Calls/callbacks:** `ensure_gates_file` [`ralphie.sh:1440`](../ralphie.sh#L1440); `restore_gate_order` [`ralphie.sh:1459`](../ralphie.sh#L1459); `err` [`ralphie.sh:1463`](../ralphie.sh#L1463); `event` [`ralphie.sh:1464`](../ralphie.sh#L1464), [`ralphie.sh:1472`](../ralphie.sh#L1472); `ask_human` [`ralphie.sh:1465`](../ralphie.sh#L1465), [`ralphie.sh:1473`](../ralphie.sh#L1473); `warn` [`ralphie.sh:1470`](../ralphie.sh#L1470); `dim` [`ralphie.sh:1471`](../ralphie.sh#L1471).

- **Shell/host commands:** `grep`, `cat`.



### `baseline_gates_save` — 1476–1479

**PROJECT; scope: global; EXTRACTED.** Persist the current active gate set as the cross-run baseline. [`ralphie.sh:1476–1479`](../ralphie.sh#L1476)

- **Inputs [EXTRACTED]:** GATES_BASELINE_FILE or HOME_DIR/gates.baseline; gates_list.

- **Outputs [EXTRACTED]:** Baseline file content; returns0.

- **Side effects [EXTRACTED]:** Directly overwrites baseline file with current active lines.

- **Invariants and scope [EXTRACTED]:** Defaults the baseline path once when unset.

- **Failure and recovery [EXTRACTED]:** Write/list errors are ignored; this is not an atomic or independently protected persistence transaction.

- **Calls/callbacks:** `gates_list` [`ralphie.sh:1478`](../ralphie.sh#L1478).



### `snapshot_gates` — 1482–1508

**PROJECT; scope: global; EXTRACTED.** Grow the in-memory run gate set and write a diagnostic snapshot. [`ralphie.sh:1482–1508`](../ralphie.sh#L1482)

- **Inputs [EXTRACTED]:** Existing GATES_SNAPSHOT, current gates_list, RUN_DIR.

- **Outputs [EXTRACTED]:** GATES_SNAPSHOT monotonically accumulates exact command lines; run/gates.before mirrors it.

- **Side effects [EXTRACTED]:** Updates memory, creates runtime directory and writes snapshot file.

- **Invariants and scope [EXTRACTED]:** Current file additions are retained; missing previous lines are not removed from memory during the run.

- **Failure and recovery [EXTRACTED]:** Disk snapshot write failures are tolerated because guard uses the in-memory copy. It does not validate command semantics or underlying test files.

- **Calls/callbacks:** `gates_list` [`ralphie.sh:1493`](../ralphie.sh#L1493).

- **Shell/host commands:** `printf`, `grep`, `mkdir`.



### `check_gates` — 1510–1516

**PROJECT; scope: global; EXTRACTED.** Run the gate guard and preserve tamper evidence for the whole cycle. [`ralphie.sh:1510–1516`](../ralphie.sh#L1510)

- **Inputs [EXTRACTED]:** GATES_SNAPSHOT/GATES_FILE through guard_gates; GATE_TAMPER.

- **Outputs [EXTRACTED]:** Sets CY_GATE_TAMPER1 on guard failure and copies nonempty GATE_TAMPER to CY_TAMPER_NAME; returns0.

- **Side effects [EXTRACTED]:** May invoke gate restoration and event writes.

- **Invariants and scope [EXTRACTED]:** Later successful checks do not clear CY_GATE_TAMPER in this function.

- **Failure and recovery [EXTRACTED]:** Always returns0 so callers must use the cycle flag to enforce outcomes.

- **Calls/callbacks:** `guard_gates` [`ralphie.sh:1513`](../ralphie.sh#L1513).



### `resolve_link` — 1518–1534

**PROJECT; scope: global; EXTRACTED.** Follow a leaf symlink chain with a bounded hop count. [`ralphie.sh:1518–1534`](../ralphie.sh#L1518)

- **Inputs [EXTRACTED]:** Path argument; readlink resolution.

- **Outputs [EXTRACTED]:** Resolved non-link path text without newline, or status1 if a symlink remains after16 hops.

- **Side effects [EXTRACTED]:** Filesystem reads only.

- **Invariants and scope [EXTRACTED]:** Relative link targets are interpreted relative to the current link dirname. Cycles cannot spin forever.

- **Failure and recovery [EXTRACTED]:** It does not canonicalize parent components or require target existence. A surviving leaf link is rejected, including after readlink failure.

- **Calls/callbacks:** No repository-function callback in this body.

- **Shell/host commands:** `readlink`, `printf`, `dirname`.



### `gate_path_inside_project` — 1536–1545

**PROJECT; scope: global; EXTRACTED.** Determine whether the physically resolved gate parent is inside the physical project root. [`ralphie.sh:1536–1545`](../ralphie.sh#L1536)

- **Inputs [EXTRACTED]:** GATES_FILE, PROJECT and existing parent directories.

- **Outputs [EXTRACTED]:** Status0 for contained target parent;1 for failed resolution/cd/empty result/outside root.

- **Side effects [EXTRACTED]:** Reads symlinks and directory metadata.

- **Invariants and scope [EXTRACTED]:** Both target parent and project root use pwd -P before the slash-delimited containment comparison.

- **Failure and recovery [EXTRACTED]:** This is a point-in-time path check, not an atomic open or filesystem sandbox. Missing parent fails closed.

- **Calls/callbacks:** `resolve_link` [`ralphie.sh:1538`](../ralphie.sh#L1538).

- **Shell/host commands:** `dirname`, `cd`, `pwd`.



### `restore_gate_order` — 1547–1624

**PROJECT; scope: global; EXTRACTED.** Merge missing snapshot commands back into their original order while retaining current comments and additions. [`ralphie.sh:1547–1624`](../ralphie.sh#L1547)

- **Inputs [EXTRACTED]:** GATES_SNAPSHOT, current writable GATES_FILE and project containment.

- **Outputs [EXTRACTED]:** Return0 after successful rewrite with matching byte count;1 on rejected path/write failure.

- **Side effects [EXTRACTED]:** Creates restore.$$ and keep.$$ siblings, stores snapshot lines in dynamically named shell variables, writes through the gate path, deletes scratch files; failed publication attempts to restore the old bytes.

- **Invariants and scope [EXTRACTED]:** Requires a writable contained destination. Existing comments/blank lines/added gates are copied; missing remembered commands are inserted before the next remembered successor. Publication preserves the gate path inode/symlink.

- **Failure and recovery [EXTRACTED]:** Backup restoration is best effort and validated publication compares length, not content hash. No concurrent writer lock or fsync is used. Dynamic _gsnap_N variables remain shell state.

- **Calls/callbacks:** `warn` [`ralphie.sh:1561`](../ralphie.sh#L1561), [`ralphie.sh:1568`](../ralphie.sh#L1568), [`ralphie.sh:1622`](../ralphie.sh#L1622); `gate_path_inside_project` [`ralphie.sh:1567`](../ralphie.sh#L1567).

- **Shell/host commands:** `eval`, `grep`, `printf`, `wc`, `tr`, `cat`, `rm`.



### `guard_gates` — 1626–1677

**PROJECT; scope: global; EXTRACTED.** Detect missing remembered gate commands, restore them if possible, and flag the cycle as tampered. [`ralphie.sh:1626–1677`](../ralphie.sh#L1626)

- **Inputs [EXTRACTED]:** GATES_SNAPSHOT, GATES_FILE, PROJECT and runtime paths.

- **Outputs [EXTRACTED]:** GATE_TAMPER description or last missing command;0 with empty snapshot/no missing lines;1 whenever containment or remembered-command loss is detected.

- **Side effects [EXTRACTED]:** May recreate nonregular/unreadable gate file with rm-rf/truncate/chmod, invoke ordered restore and append tamper event.

- **Invariants and scope [EXTRACTED]:** Restoration does not turn the detected tamper into success. Added commands remain permitted. Exact remembered lines are the protected unit.

- **Failure and recovery [INFERRED]:** An empty snapshot provides no prior-set protection. It does not prove that a surviving command or its transitive dependencies retained the same meaning. Repair failures still return1.

- **Calls/callbacks:** `ensure_dirs` [`ralphie.sh:1641`](../ralphie.sh#L1641); `gate_path_inside_project` [`ralphie.sh:1642`](../ralphie.sh#L1642); `err` [`ralphie.sh:1644`](../ralphie.sh#L1644), [`ralphie.sh:1670`](../ralphie.sh#L1670), [`ralphie.sh:1673`](../ralphie.sh#L1673); `event` [`ralphie.sh:1645`](../ralphie.sh#L1645), [`ralphie.sh:1671`](../ralphie.sh#L1671), [`ralphie.sh:1674`](../ralphie.sh#L1674); `restore_gate_order` [`ralphie.sh:1669`](../ralphie.sh#L1669).

- **Shell/host commands:** `rm`, `chmod`, `grep`.



### `gate_failure_brief` — 1679–1693

**PROJECT; scope: global; EXTRACTED.** Format a bounded prompt-ready explanation of the first recorded gate failure. [`ralphie.sh:1679–1693`](../ralphie.sh#L1679)

- **Inputs [EXTRACTED]:** GATE_FAIL_CMD, GATE_TIMED_OUT and seconds, GATE_FAIL_LOG, GATE_BRIEF_BYTES default3000.

- **Outputs [EXTRACTED]:** Failure or timeout explanation plus optional failing log tail.

- **Side effects [EXTRACTED]:** Reads log only.

- **Invariants and scope [EXTRACTED]:** Timeout is described as an unknown result rather than assumed project defect.

- **Failure and recovery [EXTRACTED]:** No failure command returns0 silently. The final file condition can return1 when no log exists; callers must not treat this formatter as a success predicate.

- **Calls/callbacks:** `tail_of` [`ralphie.sh:1692`](../ralphie.sh#L1692).

- **Shell/host commands:** `printf`.



## External interfaces and persisted surfaces

- **project_selection** [EXTRACTED] Input environment RALPHIE_PROJECT defaults to script directory; project_bind turns the selected existing directory into an exported physical path. CWD matters for relative selection and streamed install. [`ralphie.sh:96–120`](../ralphie.sh#L96)

- **runtime_primary_paths** [EXTRACTED] Primary templates: PROJECT/.ralphie/{state,events.jsonl,gates,OBJECTIVE.md,ASK.md,MEMORY.md,log,run,lock,stop}. No HOME environment override is used for these paths. [`ralphie.sh:109–119`](../ralphie.sh#L109)

- **bootstrap_paths** [EXTRACTED] Streaming reads the remaining script bytes from stdin and publishes pwd/ralphie.sh via pwd/ralphie.sh.tmp.PID; exec receives original argv and RALPHIE_NO_UPDATE1. [`ralphie.sh:49–75`](../ralphie.sh#L49)

- **state_format** [EXTRACTED] State is line-oriented key=value; last matching key wins. Values written by state_set have CR/LF removed. Only STATE_KEYS is writable through that function. [`ralphie.sh:290–343`](../ralphie.sh#L290)

- **state_write_temporaries** [EXTRACTED] State writer uses STATE_FILE.lock as a mkdir mutex and STATE_FILE.tmp.PID.TOKEN as a rename scratch. After30 failed lock attempts it removes/recreates the mutex. [`ralphie.sh:324–342`](../ralphie.sh#L324)

- **event_format** [EXTRACTED] Append one compact JSON object per line with ts/run/cycle/kind/status/detail; extra argv key=value fields become string-valued properties. Only detail/extra values are escaped at this boundary. [`ralphie.sh:351–381`](../ralphie.sh#L351)

- **ledger_retention** [EXTRACTED] EVENTS_FILE.1..N are rotated generations; RALPHIE_LEDGER_MAX default16777216 and RALPHIE_LEDGER_GENERATIONS default5 bound retained history. Max size/generation values are not locally validated. [`ralphie.sh:614–638`](../ralphie.sh#L614)

- **recovery_scratch** [EXTRACTED] Rebuild reads current plus EVENTS_FILE.[0-9]* into RUN_DIR/ledger-all.PID and extracts cycle/counter/timing values textually. [`ralphie.sh:472–517`](../ralphie.sh#L472)

- **run_scratch_and_retention** [EXTRACTED] run_init clears pre-dirty.PID.nul, staged.PID.nul, index.PID, committed.PID.nul and commit-error.PID. Cycle retention RALPHIE_KEEP_CYCLES defaults50; session retention RALPHIE_KEEP_RUNS defaults5. [`ralphie.sh:548–652`](../ralphie.sh#L548)

- **freshness_paths** [EXTRACTED] RUN_DIR/tree.mark and verify.mark plus LAST_VERIFY_LISTING combine modification times with a sorted regular-file name digest. NOISE_DIRS excludes runtime and build/cache/vendor trees. [`ralphie.sh:654–725`](../ralphie.sh#L654)

- **noise_list** [EXTRACTED] Noise names are .git .ralphie node_modules .venv venv target dist build __pycache__ .next vendor .pytest_cache .mypy_cache .ruff_cache .tox coverage .nyc_output .terraform .gradle .idea .vscode. [`ralphie.sh:695`](../ralphie.sh#L695)

- **git_fingerprint_io** [EXTRACTED] Ordinary fingerprint invokes Git rev-parse HEAD, status --porcelain and diff HEAD, then includes gates and objective content. Unlike discover_git, these calls do not carry discovery-only config overrides. [`ralphie.sh:730–742`](../ralphie.sh#L730)

- **git_local_exclude** [EXTRACTED] ensure_ignored may append .ralphie/ into the repository metadata info/exclude resolved by Git, while leaving tracked .gitignore unchanged. [`ralphie.sh:567–585`](../ralphie.sh#L567)

- **run_lock** [EXTRACTED] LOCK_FILE is a directory containing pid, token and since; live-owner checks use kill0 or ps. The token is checked after stale takeover, and LOCK_HELD controls later removal. [`ralphie.sh:748–802`](../ralphie.sh#L748)

- **process_hygiene** [EXTRACTED] CHILD_PIDS is a space-delimited process-local list. pgrep-P or ps supplies children; cleanup sends TERM/KILL to PIDs and process groups. These are observations and signals, not process isolation. [`ralphie.sh:808–859`](../ralphie.sh#L808)

- **signal_contract** [EXTRACTED] EXIT calls on_exit; INT/TERM/HUP call on_int and exit130; PIPE calls on_pipe, retires stdout and causes final exit141. Owned-run exit cleanup records work and releases lock. [`ralphie.sh:861–916`](../ralphie.sh#L861)

- **console** [EXTRACTED] Stdout helpers use terminal_printf; warnings/errors/debug use stderr. RALPHIE_QUIET suppresses info/dim, RALPHIE_VERBOSE enables dbg, NO_COLOR/TERM/tty state control color. /dev/stdout determines pipe handling. [`ralphie.sh:122–159`](../ralphie.sh#L122)

- **clock_random_digest** [EXTRACTED] System date supplies UTC/epoch values, /dev/urandom plus od supplies tokens with epoch+PID fallback, and sha_of selects an available SHA256 tool or weaker cksum. [`ralphie.sh:161–194`](../ralphie.sh#L161)

- **budget** [EXTRACTED] RUN_DEADLINE is absolute epoch seconds,0 unlimited. budget_cap floors finite expired limits to1. run_prepare sets the deadline from MAX_MINUTES before discovery and --gate trials. [`ralphie.sh:249–279`](../ralphie.sh#L249), [`ralphie.sh:5239–5247`](../ralphie.sh#L5239)

- **root_manifests** [EXTRACTED] Detection uses root package.json, tsconfig.json, pyproject.toml/setup.py/requirements.txt, Cargo.toml, go.mod, pom.xml, build.gradle(.kts), Gemfile, composer.json, mix.exs, deno.json, CMakeLists.txt, Dockerfile, Makefile/makefile and .tf/.sh glob presence. [`ralphie.sh:930–990`](../ralphie.sh#L930)

- **project_tool_selection** [EXTRACTED] Package-manager lockfiles select bun/pnpm/yarn/npm. Python tools prefer executable .venv/bin or venv/bin, then uv run with uv.lock, then global PATH. Normal package-script lookup optionally invokes node or python3. [`ralphie.sh:930–967`](../ralphie.sh#L930)

- **discovery_report** [EXTRACTED] Read-only discovery consumes standing-instruction filenames AGENTS.md/CLAUDE.md/GEMINI.md, known root plans and docs/TODO.md, current objective/gates, Git status and engine executable presence. It prints these facts and candidate text without running gates or engines. [`ralphie.sh:1022–1079`](../ralphie.sh#L1022)

- **discovery_git_overrides** [EXTRACTED] discover_git applies GIT_OPTIONAL_LOCKS0/GIT_NO_LAZY_FETCH1, disables fsmonitor/untracked-cache and configured clean/process filters for its Git invocation. It does not export these settings into later gate commands. [`ralphie.sh:1013–1020`](../ralphie.sh#L1013)

- **gate_text_contract** [EXTRACTED] GATES_FILE is one shell command per nonblank/noncomment line, executed from PROJECT. Original active lines are protected by exact text membership; added lines remain allowed. [`ralphie.sh:1269–1280`](../ralphie.sh#L1269), [`ralphie.sh:1312–1316`](../ralphie.sh#L1312), [`ralphie.sh:1482–1508`](../ralphie.sh#L1482), [`ralphie.sh:1626–1677`](../ralphie.sh#L1626)

- **gate_runtime** [EXTRACTED] GATE_SH -c receives pipefail/EXIT-reap prelude plus command text. Stdin is /dev/null, stdout and stderr merge into the requested capture, command execution inherits operator authority and environment. [`ralphie.sh:1154–1211`](../ralphie.sh#L1154)

- **gate_timeouts** [EXTRACTED] GATE_TRIAL_TIMEOUT defaults120 and GATE_TIMEOUT900. All gate execution delegates hard timing to watchdog_wait; verify is not clamped to the remaining run budget. Gate hard timeout returns124. [`ralphie.sh:1213–1249`](../ralphie.sh#L1213), [`ralphie.sh:1362–1364`](../ralphie.sh#L1362), [`ralphie.sh:2955–3015`](../ralphie.sh#L2955)

- **gate_retry_and_capture** [EXTRACTED] GATE_RETRIES defaults1 and enables one retry when positive. Observe may forgive failed-then-passed; verify does not. GATE_LOG_MAX defaults262144 retained bytes; GATE_BRIEF_BYTES defaults3000 prompt-tail bytes. [`ralphie.sh:1370–1416`](../ralphie.sh#L1370), [`ralphie.sh:1679–1693`](../ralphie.sh#L1679)

- **gate_evidence_outputs** [EXTRACTED] Execution writes RUN_DIR/trial.PID during trial, or logbase.summary plus logbase.N.log and temporary .retry/.trim files. Summary records PASS, FAIL(rc), UNVERIFIED or UNREADABLE. GATES_NONE must accompany rc0 to disambiguate absent checks. [`ralphie.sh:1218–1248`](../ralphie.sh#L1218), [`ralphie.sh:1329–1355`](../ralphie.sh#L1329), [`ralphie.sh:1360–1421`](../ralphie.sh#L1360)

- **gate_outcome_globals** [EXTRACTED] run_gates resets/sets GATES_NONE, GATE_FAIL_CMD, GATE_FAIL_LOG, GATE_FLAKY, GATE_TIMED_OUT and GATE_TIMED_OUT_SECS; gate_exec records GATE_EXEC_RC. These values are consumed by later lifecycle/prompt decisions. [`ralphie.sh:1191–1210`](../ralphie.sh#L1191), [`ralphie.sh:1329–1356`](../ralphie.sh#L1329), [`ralphie.sh:1374–1416`](../ralphie.sh#L1374), [`ralphie.sh:1679–1693`](../ralphie.sh#L1679)

- **gate_baseline_and_snapshot** [EXTRACTED] Persistent HOME_DIR/gates.baseline protects between-run command membership; in-memory GATES_SNAPSHOT and run/gates.before protect current-run membership. Restore uses GATES_FILE.restore.PID and .keep.PID. [`ralphie.sh:1439–1624`](../ralphie.sh#L1439)

- **gate_containment** [EXTRACTED] Gate reads/repairs/resets in these helpers resolve up to16 leaf symlinks and physicalize the target parent/root before containment. This path check does not confine what a gate command can access. [`ralphie.sh:1518–1545`](../ralphie.sh#L1518)

- **human_questions** [EXTRACTED] Discovery with no gates or cross-run gate restoration calls ask_human; that later function writes deduplicated questions to ASK.md, confirms persistence, emits events and calls notify. It does not read a terminal. [`ralphie.sh:1300–1302`](../ralphie.sh#L1300), [`ralphie.sh:1463–1473`](../ralphie.sh#L1463), [`ralphie.sh:4520–4542`](../ralphie.sh#L4520)


Writable state keys at lines290–294: `cycle`, `engine`, `model`, `request_set`, `objective_hash`, `acceptance_binding`, `acceptance_work`, `blocked_count`, `untrusted_count`, `started_at`, `updated_at`, `status`, `reason`, `pass_count`, `fail_count`, `learned_count`, `last_cycle_at`, `run_id`, `unverified_count`, `nochange_streak`, `objective_started`, `tokens_spent`, `run_tokens`, `run_cost`, `start_commit`, `base_branch`, `total_seconds`.


## Critical control and data relationships

- **bind_to_runtime** [EXTRACTED] main parses args/load_spec, handles help/version, then calls project_bind before discover or ledger work. Library mode calls project_bind directly at the file end. [`ralphie.sh:5447–5478`](../ralphie.sh#L5447)

- **discover_early_exit** [EXTRACTED] main dispatches discover immediately after binding and exits, before request scanning, ledger_init, traps, update, run_prepare and loop. [`ralphie.sh:5454–5470`](../ralphie.sh#L5454)

- **discovery_local_overrides** [EXTRACTED] discover_candidates locally replaces has_npm_script and has_make_target inside its subshell so gate_candidates uses text-only preview parsing without changing runtime definitions. [`ralphie.sh:994–1008`](../ralphie.sh#L994)

- **prepare_order** [EXTRACTED] run_prepare acquires the run lock, establishes time budget and run state, then later prepares gates and restores the persistent baseline before first-cycle work. [`ralphie.sh:5239–5310`](../ralphie.sh#L5239)

- **state_event_dependency** [EXTRACTED] event appends evidence and calls state_set(updated_at). Repair may call event, so the UNUSABLE_REPORTED latch prevents repeating the same unusable-path reporting path. [`ralphie.sh:351–460`](../ralphie.sh#L351)

- **ledger_rebuild_input** [EXTRACTED] ledger_init and cycle_begin can recover selected counters from retained event generations; run identity/tokens are not reconstructed by rebuild_state_from_ledger. [`ralphie.sh:472–546`](../ralphie.sh#L472), [`ralphie.sh:3763–3783`](../ralphie.sh#L3763)

- **run_exit_custody** [EXTRACTED] EXIT and interrupt handlers record_owned_paths only for OWNS_RUN1, then terminate tracked children and release the lock. The called custody implementation excludes operator/sibling/runtime paths separately. [`ralphie.sh:863–903`](../ralphie.sh#L863), [`ralphie.sh:1847–1882`](../ralphie.sh#L1847)

- **gate_candidates_to_truth** [EXTRACTED] gate_candidates emits possibilities; gate_trial executes them to distinguish unavailable tools from runnable failure; discover_gates persists accepted lines; run_gates measures their pass/fail result. [`ralphie.sh:1081–1141`](../ralphie.sh#L1081), [`ralphie.sh:1213–1310`](../ralphie.sh#L1213), [`ralphie.sh:1322–1422`](../ralphie.sh#L1322)

- **gate_executor_watchdog** [EXTRACTED] Both gate_trial and run_gates use gate_exec. The executor tracks the process, calls watchdog_wait with idle0 and caller hard limit, then cleans remaining descendants. [`ralphie.sh:1192–1249`](../ralphie.sh#L1192), [`ralphie.sh:1362–1372`](../ralphie.sh#L1362), [`ralphie.sh:2955–3015`](../ralphie.sh#L2955)

- **zero_gates_contract** [INFERRED] run_gates returns0 with GATES_NONE1 when no gates exist; later lifecycle code must read that flag as well as return status to avoid promoting absent evidence. [`ralphie.sh:1348–1355`](../ralphie.sh#L1348), [`ralphie.sh:3830–3850`](../ralphie.sh#L3830)

- **snapshot_before_executable_inputs** [EXTRACTED] cycle_begin snapshots gates before gates/engine can execute. check_gates latches tamper evidence; cycle_verify checks around measured gates and acceptance, so restore success cannot erase the cycle flag. [`ralphie.sh:1482–1516`](../ralphie.sh#L1482), [`ralphie.sh:3802–3808`](../ralphie.sh#L3802), [`ralphie.sh:3949–4007`](../ralphie.sh#L3949)

- **gate_crossrun_protection** [EXTRACTED] baseline_gates_load restores missing prior-run lines; snapshot_gates protects the in-memory set; baseline_gates_save persists the current set after a cycle only if CY_GATE_TAMPER is not1. [`ralphie.sh:1439–1508`](../ralphie.sh#L1439), [`ralphie.sh:4006`](../ralphie.sh#L4006)

- **freshness_cache** [EXTRACTED] cache_verdict stores fingerprint plus mark_verify after recording. cycle_observe reuses a verdict only when fingerprint matches and verify_mark_stale is false; otherwise it runs gates. [`ralphie.sh:654–742`](../ralphie.sh#L654), [`ralphie.sh:3821–3842`](../ralphie.sh#L3821), [`ralphie.sh:4185–4198`](../ralphie.sh#L4185)

- **acceptance_side_effect_health** [EXTRACTED] cycle_verify fingerprints and marks before acceptance, then re-runs health gates if acceptance changed tracked/runtime fingerprint or timestamp/file-set evidence. A second mutation by health clears acceptance instead of looping indefinitely. [`ralphie.sh:3965–3993`](../ralphie.sh#L3965)

- **gate_feedback** [EXTRACTED] run_gates records first failing command/log and any timeout metadata; gate_failure_brief emits a bounded tail and distinguishes a killed check from a demonstrated code defect. [`ralphie.sh:1407–1416`](../ralphie.sh#L1407), [`ralphie.sh:1679–1693`](../ralphie.sh#L1679)

- **retention_limits_recovery** [INFERRED] Because rotate_ledger retains finitely many generations, recovery can reconstruct only that retained history; append-only writing does not imply unbounded historical availability. [`ralphie.sh:472–517`](../ralphie.sh#L472), [`ralphie.sh:614–638`](../ralphie.sh#L614)

- **guard_scope_limit** [INFERRED] The guard protects the exact command lines remembered in GATES_SNAPSHOT. A retained command can still execute changed tests, dependencies or external services; source membership alone cannot establish semantic equivalence. [`ralphie.sh:1493–1504`](../ralphie.sh#L1493), [`ralphie.sh:1658–1666`](../ralphie.sh#L1658)


## Limits of this evidence

- **static_scope** [EXTRACTED] This is a static, every-line review of1–1696 at the pinned SHA256. It executes neither tests, project gates nor provider engines and establishes no live readiness or performance result. [`ralphie.sh:1–1696`](../ralphie.sh#L1)

- **external_code_unknown** [INFERRED] Project gate shell text and commands, package tooling, Git hooks/filters outside discover_git, provider implementations and external services can have behavior unavailable from this source. The runner is orchestration, not a sandbox. [`ralphie.sh:1192–1211`](../ralphie.sh#L1192)

- **source_intent_not_guarantee** [EXTRACTED] Historical incident comments and design slogans document intent. The inventory describes executable operations separately; it does not independently reproduce those incidents or adopt absolute comments as proofs. [`ralphie.sh:16–35`](../ralphie.sh#L16)

- **persistence_strength** [INFERRED] mkdir/rename/append and best-effort repairs provide source-level recovery mechanisms, but no fsync protocol, filesystem fault model or concurrent-writer proof is present in these functions. [`ralphie.sh:303–460`](../ralphie.sh#L303)

- **finite_recovery** [EXTRACTED] Event rotation has finite retention. State rebuild derives counters/time from matching retained text and cannot reconstruct every prior state key or deleted history. [`ralphie.sh:472–517`](../ralphie.sh#L472), [`ralphie.sh:614–638`](../ralphie.sh#L614)

- **freshness_scope** [INFERRED] Fingerprint, mtimes and a newline-delimited regular-file list are complementary heuristics; they do not atomically snapshot all content or cover excluded directories, symlink targets and arbitrary external state. [`ralphie.sh:654–742`](../ralphie.sh#L654)

- **repair_side_effects** [EXTRACTED] ensure_own_file and guard_gates can recursively remove existing unusable paths. Readable protected regular files are preserved, but comment claims that directories contain no valuable data are not established by the code. [`ralphie.sh:390–460`](../ralphie.sh#L390), [`ralphie.sh:1653–1656`](../ralphie.sh#L1653)

- **shell_error_context** [INFERRED] The script enables set-eu/pipefail. Bash errexit propagation depends on calling context, particularly conditionals; function descriptions record explicit returns/guards rather than claiming every failed subprocess always aborts or always recovers. [`ralphie.sh:78`](../ralphie.sh#L78)

- **timeout_and_log_bounds** [INFERRED] Watchdog hard limits include polling/grace overhead. run_gates trims captured output after a gate finishes, so retained-size limits alone do not bound peak disk consumption during execution. [`ralphie.sh:1192–1211`](../ralphie.sh#L1192), [`ralphie.sh:1398–1405`](../ralphie.sh#L1398), [`ralphie.sh:2955–3015`](../ralphie.sh#L2955)

- **point_in_time_containment** [INFERRED] Gate-path checks physicalize parents and reject unresolved leaf links, but no descriptor-based atomic containment or concurrent-renaming protection is shown here. [`ralphie.sh:1518–1545`](../ralphie.sh#L1518)

- **process_cleanup_limits** [INFERRED] PID/process-group signals and descendant snapshots are best-effort cleanup. They cannot prove cleanup after SIGKILL/power loss or capture every child that reparents or changes session between observations. [`ralphie.sh:812–916`](../ralphie.sh#L812)

- **gate_membership_limit** [INFERRED] A nonshrinking list of command strings constrains one edit surface; correctness still depends on the chosen commands and their implementations. Zero-gate rc0 requires the separate GATES_NONE flag. [`ralphie.sh:1322–1422`](../ralphie.sh#L1322), [`ralphie.sh:1482–1508`](../ralphie.sh#L1482), [`ralphie.sh:1626–1677`](../ralphie.sh#L1626)

- **outside_range** [EXTRACTED] Git custody, engine behavior, objective/acceptance logic, human notifications and most CLI behavior are inventoried by other reviewers. Only specifically cited cross-layer functions were read here to establish outgoing contracts. [`ralphie.sh:1695–1696`](../ralphie.sh#L1695)


## Coverage receipt

- Every assigned line read: **1–1696 /1696**.
- Function range set matches the independent AST inventory exactly: **92 definitions**, **90 names**, **2 nested overrides**.
- Top-level sections: **20**; interface records: **32**; relationship records: **17**.
- The frozen source digest was checked before artifact generation and again immediately before writing.
- Function-call anchors were verified against their source lines; local definition edges are explicitly distinguished from calls.
- Cross-layer reads are explicitly listed in the JSON and cited only to explain contracts leaving this assigned range.
