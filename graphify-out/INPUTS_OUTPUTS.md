# Ralphie inputs and outputs


**Pinned source:** `ralphie.sh`, **5,478 lines**, SHA256 `c21744b635e3b640aa6d65b6c36daa7dc0d8e1e90b7bf45fb09f8937055aa905`. This catalogue combines the three frozen source reviews and [source-index.json](source-index.json). Links open the exact source in [source.html](source.html). No product commands, tests, engines, or remote calls were run to produce it.


**Evidence:** unless marked **INFERRED**, entries describe extracted source behavior. Defaults are implementation defaults, not promises that every environment variable is a supported public control. Internal variables and child-only exports are identified separately. External command behavior remains external. Per-function contracts are in [FUNCTIONS.md](FUNCTIONS.md); the index retains all raw commands, redirects, variable expansions and assignments.


## Entry, argument parsing and working directories


A saved script runs under Bash with `set -euo pipefail`. `SELF` uses the physical script-parent directory and original basename. `PROJECT` starts from nonempty `RALPHIE_PROJECT`, otherwise that script directory. `--project DIR` can override it; `project_bind` resolves the selected directory physically and exports `RALPHIE_PROJECT`. Runtime storage is always under the selected project. A streamed invocation instead first writes `pwd/ralphie.sh`, marks it executable and reexecutes it with `RALPHIE_NO_UPDATE=1`. [L42–120](source.html#L42)


| Order | Input/dispatch rule | Evidence |
| --- | --- | --- |
| 1 | Top-level defaults and shell setup execute before main. `RALPHIE_LIB=1` ultimately binds the project and skips main; it still changes shell options/globals. | [L78](source.html#L78), [L96](source.html#L96), [L5084](source.html#L5084), [L5477](source.html#L5477) |
| 2 | `parse_args` scans left-to-right. A recognized command stops global parsing and preserves remaining argv in REST. A normal positional token or `--` stops parsing and joins the remainder with spaces as objective text. | [L5145–5203](source.html#L5145) |
| 3 | Only separated values are implemented. No `--name=value` or combined short flags. A value must exist and be nonempty, but another flag token can be consumed as a value. Repeated ordinary assignments use the last value. | [L5090–5094](source.html#L5090); [L5155–5198](source.html#L5155) |
| 4 | `-h/--help` and `--version` exit immediately from parsing. Otherwise `load_spec` validates/reads `--spec` before project binding. `help`/`version` commands then exit before binding and ledger repair. | [L5194](source.html#L5194), [L5195](source.html#L5195), [L5450](source.html#L5450), [L5451](source.html#L5451), [L5455](source.html#L5455), [L5456](source.html#L5456) |
| 5 | Physical project binding precedes early `discover` and `request` dispatch. Other commands validate any request evidence, initialize/repair the ledger, install traps, then dispatch simple commands. | [L5458–5468](source.html#L5458) |
| 6 | A run may self-update, then acquire the worker lock, initialize run state, establish Git/custody/objective/acceptance/engine/gates, execute cycles, and finish. Automatic update failure is tolerated. | [L5239–5310](source.html#L5239); [L5470–5475](source.html#L5470) |
| Path bases | `--project` and `--spec` relative paths use invocation cwd. `request --file` relative paths use PROJECT. Gates, acceptance, engines and project tooling execute from PROJECT. Git private-index operations use the Git repository root. | [L107](source.html#L107), [L1197](source.html#L1197), [L2394](source.html#L2394), [L2892](source.html#L2892), [L4480](source.html#L4480), [L5134](source.html#L5134) |
| Typo guard | A single lowercase/hyphen token resembling a listed command prefix/suffix is rejected; multiword objectives bypass that guard. The typo list omits discover. | [L5096–5120](source.html#L5096) |



**Practical parse consequence:** `ralphie.sh --once --objective "repair parser"` sets run controls and objective. `ralphie.sh run --once` stores `--once` in REST; it does not set MAX_CYCLES. Trailing run arguments are not consumed as an objective. [L5154](source.html#L5154), [L5166](source.html#L5166), [L5239](source.html#L5239)


## Commands


| Command | Arguments | Behavior | Source |
| --- | --- | --- | --- |
| `run` | No defined arguments | Default execution path; options must precede the command. parse_args captures trailing argv into REST, but run_prepare does not consume REST as objective/options. | [L5151](source.html#L5151), [L5239](source.html#L5239) |
| `discover` | no arguments | Early read-only orientation via cmd_discover before ledger/traps/update; rejects trailing args in layer 3. | [L1022](source.html#L1022), [L5459](source.html#L5459) |
| `status` | optional first --json | Human report by default; exact first --json selects machine output; other trailing args are not generally rejected. | [L4879](source.html#L4879), [L5217](source.html#L5217) |
| `doctor` | No defined arguments | Capabilities/presence/liveness diagnostic; engine version probes may execute. | [L4982](source.html#L4982), [L5231](source.html#L5231) |
| `gates` | optional first --redetect | Discover/display; redetect backs up then removes old list+baseline and rediscovers while refusing live worker. | [L5036](source.html#L5036), [L5230](source.html#L5230) |
| `ask` | No defined arguments | Show bounded open-question excerpts or no-open-questions. | [L4544](source.html#L4544), [L5221](source.html#L5221) |
| `answer` | N; answer argv joined with one space between arguments | Rewrite numbered ASK section and remember a redacted one-line operator decision. | [L4586](source.html#L4586), [L5223](source.html#L5223) |
| `request` | TEXT; --file FILE; list; archive | Early dedicated path before ledger/traps. No args/list enumerate, archive retains batch, other accepted forms publish. | [L4458](source.html#L4458), [L5461](source.html#L5461) |
| `memory` | No defined arguments | Show MEMORY.md if nonempty, otherwise nothing-learned commentary. | [L5213](source.html#L5213), [L5220](source.html#L5220) |
| `forget` | No defined arguments | Explicitly disable acceptance and remove stored objective/hash when nonempty. | [L4970](source.html#L4970), [L5218](source.html#L5218) |
| `log` | optional first n, default 20 | Tail current ledger; nondigit n falls back to 20; render only matching event lines. | [L5074](source.html#L5074), [L5219](source.html#L5219) |
| `stop` | No defined arguments | Touch stop file; loop consumes it between cycles and ignores a stale first-iteration request. | [L4288](source.html#L4288), [L5228](source.html#L5228) |
| `update` | No defined arguments | Run self_update; explicit result is propagated by run_simple_command. | [L4826](source.html#L4826), [L5229](source.html#L5229) |
| `version` | No defined arguments | Print ralphie followed by version; handled before project bind/ledger. | [L5215](source.html#L5215), [L5456](source.html#L5456) |
| `help` | No defined arguments | Print help; handled before project bind/ledger. | [L5216](source.html#L5216), [L5456](source.html#L5456) |



There are **15 recognized command spellings**, with no separate command aliases. Command-specific handling is intentionally uneven: `discover` rejects trailing arguments; `request` validates its accepted forms; several simple commands inspect only the first argument or ignore extras. `--version` prints bare VERSION, while `version` prints `ralphie VERSION`. The `gates` command can execute discovery trials; `doctor` can run engine `--version` probes. They are not equivalent to the early discovery preview. [L5151–5154](source.html#L5151); [L5213–5235](source.html#L5213); [L5036–5072](source.html#L5036)


## Global option families


| Spellings | Value | Default | Effect and validation | Source |
| --- | --- | --- | --- | --- |
| `--project` | DIR | RALPHIE_PROJECT or script directory | PROJECT override; physical absolute binding after parse; existing directory; need nonempty value | [L5155](source.html#L5155) |
| `-o`, `--objective` | TEXT | empty/resume stored file | replace objective; last explicit objective assignment wins; nonempty argument | [L5156](source.html#L5156) |
| `--spec` | FILE | none | read once from invocation cwd before binding; once; readable regular file; run only; no objective or REST; plain text 1..1048576 bytes | [L5157](source.html#L5157) |
| `--engine` | NAME | Prime preferred then layer-4 selection | ENGINE_EXPLICIT=1; no provider substitution; nonempty argument; adapter validates selection | [L5160](source.html#L5160) |
| `-b`, `--branch` | NAME | RALPHIE_BRANCH or empty | requested work branch; nonempty argument | [L5161](source.html#L5161) |
| `--model` | ID | RALPHIE_MODEL or empty | engine model identifier; nonempty argument | [L5162](source.html#L5162) |
| `--thinking` | LEVEL | RALPHIE_THINKING or empty | pass level through adapter; help lists off\|minimal\|low\|medium\|high\|xhigh\|max; nonempty argument; parser does not enforce help enum | [L5163](source.html#L5163) |
| `-n`, `--cycles` | N | 0 unlimited | maximum cycles per invocation; 0 disables; digits only via is_int; no sign | [L5164](source.html#L5164) |
| `-m`, `--minutes` | N | 0 unlimited | engine/observe allowance, not hard completion deadline; digits only via is_int; no sign | [L5165](source.html#L5165) |
| `--once` | none | off | MAX_CYCLES=1; none | [L5166](source.html#L5166) |
| `--gate` | CMD | no extra commands | append trialled unique command to persistent gates; repeatable; nonempty argument; literal LF forbidden; CR not expressly forbidden | [L5167](source.html#L5167) |
| `--accept` | CMD | persisted binding or absent | separate completion condition with exact objective identity; once; nonempty/nonblank; LF and CR forbidden | [L5179](source.html#L5179) |
| `--no-commit` | none | AUTO_COMMIT=1 | waive automatic saving and allow verified completion on disk; none | [L5184](source.html#L5184) |
| `--no-update` | none | DO_UPDATE from RALPHIE_AUTO_UPDATE | set DO_UPDATE=0 for automatic update; global RALPHIE_NO_UPDATE remains stronger; none | [L5185](source.html#L5185) |
| `--update` | none | DO_UPDATE from RALPHIE_AUTO_UPDATE | set DO_UPDATE=1; auto-update failure does not abort run; none | [L5186](source.html#L5186) |
| `--done-when-green` | none | off | enable health/no-outstanding-work completion triggers, still subject to completion_ready; none | [L5187](source.html#L5187) |
| `--no-yolo` | none | YOLO=1 | withhold adapter bypass flags where supported; not a general sandbox; none | [L5188](source.html#L5188) |
| `-v`, `--verbose` | none | RALPHIE_VERBOSE or 0 | VERBOSE=1; QUIET=0; last opposite flag wins; none | [L5192](source.html#L5192) |
| `-q`, `--quiet` | none | RALPHIE_QUIET or 0 | QUIET=1; VERBOSE=0; warnings/errors/verdicts survive; none | [L5193](source.html#L5193) |
| `-h`, `--help` | none | none | immediate usage and exit 0 even before load_spec; none | [L5194](source.html#L5194) |
| `--version` | none | none | immediate bare VERSION and exit 0; none | [L5195](source.html#L5195) |
| `--` | remaining argv | none | join remaining argv with spaces as explicit objective; no subsequent option parsing | [L5196](source.html#L5196) |



`--spec` accepts **1..1,048,576 bytes** of nonblank plain text, preserving trailing newlines. It rejects NUL and controls except tab/CR/LF, may appear once, is run-only, and conflicts with objective text or arguments after `run`. The file is read once into the objective; its contents are not shell-evaluated. `--gate` rejects LF; `--accept` rejects both LF and CR and requires nonblank text. These are intentionally executable shell-command options, unlike a spec/request body. [L5122–5143](source.html#L5122); [L5167–5183](source.html#L5167)


## Environment: every RALPHIE implementation read/write site


For `${NAME:-default}`, both unset and empty values select the stated default. Boolean controls generally use case-insensitive `1/true/yes/y/on`; `RALPHIE_LIB` specifically compares with `1`. The **read/write columns enumerate every implementation site for these names**, including command-argv assignment and embedded Awk reads that are not shell-expansion nodes. Repeated expansions on one line are marked ×N. Help-only mentions do not count as reads. [L49](source.html#L49), [L205](source.html#L205), [L206](source.html#L206), [L5477](source.html#L5477)


| Name | Role | Default/value | Meaning | Reads | Writes/exports |
| --- | --- | --- | --- | --- | --- |
| `RALPHIE_ANSWER` | Internal child environment | Assigned answer text | Flattened answer passed to Awk; Awk reads ENVIRON, preventing it from becoming Awk source. | [L4600](source.html#L4600) | [L4597](source.html#L4597) |
| `RALPHIE_AUTO_UPDATE` | Operator input | 0 | Initial DO_UPDATE; --update/--no-update override it. | [L5085](source.html#L5085) | — |
| `RALPHIE_BRANCH` | Operator input | empty | Default branch request. | [L5086](source.html#L5086) | — |
| `RALPHIE_CONTRACT` | Internal shell constant | Literal report/work contract | Overwritten at source load; inserted into engine prompt, not a supported override. | [L3657](source.html#L3657) | [L3546](source.html#L3546) |
| `RALPHIE_ENGINE_ANSWER` | Operator/custom adapter | stdout | Answer route; file means use the answer file, but the generic custom adapter does not expose its filename (see help-only row). | [L2547](source.html#L2547) | — |
| `RALPHIE_ENGINE_CAPS` | Operator/custom adapter | empty | Whitespace-separated declared capability names; trusted for routing/ranking. | [L2548](source.html#L2548) | — |
| `RALPHIE_ENGINE_CMD` | Operator input | empty | Nonempty selects custom explicitly. Executable whole path wins; otherwise field splitting/globbing constructs argv, without shell grammar evaluation. | [L2539](source.html#L2539), [L2546](source.html#L2546), [L2624](source.html#L2624), [L2625](source.html#L2625), [L2737](source.html#L2737), [L2738](source.html#L2738), [L2741](source.html#L2741), [L5088](source.html#L5088) | — |
| `RALPHIE_ENGINE_SESSION` | Operator input | 1 | Prime per-run session directory; false adds --no-session. | [L2688](source.html#L2688) | — |
| `RALPHIE_GIT_INIT` | Operator input | 1 | False permits starting without a newly initialized Git repository. | [L1706](source.html#L1706) | — |
| `RALPHIE_KEEP_CYCLES` | Operator input | 50 | Old cycle artifact window; nondigit value resets to50. | [L592](source.html#L592) | — |
| `RALPHIE_KEEP_RUNS` | Operator input | 5 | Session-directory retention; nondigit value resets to5. | [L642](source.html#L642) | — |
| `RALPHIE_LEDGER_GENERATIONS` | Operator input | 5 | Numbered event generations; no local integer validation. | [L629](source.html#L629) | — |
| `RALPHIE_LEDGER_MAX` | Operator input | 16777216 bytes | Rotate when current ledger exceeds threshold; no local integer validation. | [L619](source.html#L619) | — |
| `RALPHIE_LIB` | Internal/library entry input | 0 | 1 suppresses stream install/main and exposes functions; updater explicitly runs its candidate with0. | [L49](source.html#L49), [L5477](source.html#L5477) | [L4854](source.html#L4854) |
| `RALPHIE_MAX_COMMIT_BYTES` | Operator input | 1048576 bytes | Automatic staging/history path-size ceiling; comparison trusts numeric input. | [L2077](source.html#L2077), [L2254](source.html#L2254) | — |
| `RALPHIE_MESSAGE` | Internal child export | Assigned notification text | Passed only to configured notification shell; any read belongs to the external hook. | — | [L4622](source.html#L4622) |
| `RALPHIE_MIN_UPDATE_BYTES` | Operator input | 40000 bytes | Minimum accepted update candidate size. | [L4851](source.html#L4851) | — |
| `RALPHIE_MODEL` | Operator input | empty | Default --model; provider resolves the identifier. | [L5084](source.html#L5084) | — |
| `RALPHIE_NL` | Internal shell constant | One literal LF | Used for line validation and string assembly; overwritten at load. | [L4357](source.html#L4357), [L5175](source.html#L5175), [L5181](source.html#L5181), [L5316](source.html#L5316) | [L85](source.html#L85) |
| `RALPHIE_NOTIFY_CMD` | Operator executable configuration | empty/disabled | Shell source passed to sh -c; receives RALPHIE_MESSAGE. | [L4618](source.html#L4618), [L4622](source.html#L4622) | — |
| `RALPHIE_NOTIFY_WAIT` | Operator input | 10 polls, one second each | Bounds waiting, not hook lifetime; a surviving hook is left running. | [L4624](source.html#L4624) | — |
| `RALPHIE_NO_UPDATE` | Operator input and bootstrap child export | 0; bootstrap writes1 | Refuses explicit and automatic self-update when true. | [L4831](source.html#L4831), [L5470](source.html#L5470) | [L71](source.html#L71) |
| `RALPHIE_OUTPUT` | Help-only advertised name | Not assigned by this source | Mentioned for custom file answers at4723, but no runtime read/export/assignment or generic filename argv exists. Do not depend on it as an implemented environment contract. | — | — |
| `RALPHIE_PROJECT` | Operator input, then child export | Physical script-parent directory | --project overrides; project_bind exports canonical PROJECT. | [L100](source.html#L100) | [L108](source.html#L108) |
| `RALPHIE_QUIET` | Operator input | 0 | Initial QUIET; CLI -q/-v are opposing last-wins flags. | [L134](source.html#L134) | — |
| `RALPHIE_THINKING` | Operator input | empty | Default --thinking; adapter passes through where supported. | [L5084](source.html#L5084) | — |
| `RALPHIE_UPDATE_URL` | Operator input | Derive GitHub raw URL | Nonempty override bypasses origin-derived construction, then initial scheme check applies. | [L4805](source.html#L4805) ×2 | — |
| `RALPHIE_VERBOSE` | Operator input | 0 | Initial VERBOSE; CLI -v/-q are opposing last-wins flags. | [L129](source.html#L129) | — |



`RALPHIE_HELP_EOF` is a quoted heredoc delimiter and update-marker string, **not an environment variable**. The custom file-output discrepancy is a directly observed source/help mismatch; this review did not invoke a custom wrapper. [L4636](source.html#L4636), [L4723](source.html#L4723), [L4797](source.html#L4797), [L4847](source.html#L4847); [L2735–2742](source.html#L2735); [L2891–2927](source.html#L2891)


## Other consumed configuration and host environment


| Name | Default | Use | All reads | Writes |
| --- | --- | --- | --- | --- |
| `ENGINE_TIMEOUT` | 2400 seconds | Per-call hard allowance, clamped to run budget;0 can mean unbounded without a run deadline. Prime omits native autonomy when the resulting call allowance is nonpositive. | [L2693](source.html#L2693), [L2887](source.html#L2887) | — |
| `ENGINE_IDLE_TIMEOUT` | 600 seconds | Only streaming-capable engines; counts growth in raw capture, not file-answer growth. | [L2905](source.html#L2905) | — |
| `ENGINE_OUTPUT_MAX_BYTES` | 16777216 bytes | Combined raw+answer ceiling; invalid/nonpositive restores default. Polling can overshoot before termination. | [L2858](source.html#L2858) | — |
| `ENGINE_RETRIES` | 3 attempts | Total attempts before permitted provider fallback; not validated locally. | [L2801](source.html#L2801) | — |
| `ENGINE_BACKOFF` | 5 seconds | Retry sleep is (attempt-1) × this value. | [L2846](source.html#L2846) | — |
| `ENGINE_MAX_TURNS` | 24 | Prime native autonomous max turns. | [L2705](source.html#L2705) | — |
| `ENGINE_MAX_CONT` | 6 | Prime native autonomous max continuations. | [L2706](source.html#L2706) | — |
| `ENGINE_MAX_TOKENS` | unset | Optional Prime native token cap; not a dollar budget. | [L2715](source.html#L2715) ×2 | — |
| `GATE_TIMEOUT` | 900 seconds | Health/acceptance limit; native Prime gate limit clamps to call allowance. Verify is not clamped to remaining run time. | [L1362](source.html#L1362), [L1684](source.html#L1684), [L2710](source.html#L2710), [L3279](source.html#L3279) | — |
| `GATE_RETRIES` | 1 | Any positive value enables exactly one confirmation retry.0 disables it; despite help wording, larger values do not add retries. | [L1370](source.html#L1370) | — |
| `GATE_TRIAL_TIMEOUT` | 120 seconds | Candidate trial hard limit; trials share gate_exec. | [L1225](source.html#L1225) | — |
| `GATE_BRIEF_BYTES` | 3000 bytes | Failing-log tail inserted into prompt evidence. | [L1692](source.html#L1692) | — |
| `GATE_LOG_MAX` | 262144 bytes | Retained health/acceptance log tail; trimming occurs after execution. | [L1401](source.html#L1401), [L3281](source.html#L3281) | — |
| `COMMIT_TIMEOUT` | 120 seconds | Commit/hooks/signing watchdog; invalid/nonpositive restores120. | [L2458](source.html#L2458) | — |
| `NOCHANGE_LIMIT` | 3 cycles | Persisted consecutive nonprogress threshold; reaches stalled exit3. | [L4222](source.html#L4222) | — |
| `MEMORY_MAX` | 60 lessons | Retain most recent - lesson lines after appending. | [L3725](source.html#L3725), [L3727](source.html#L3727) | — |
| `MIN_ANSWER_BYTES` | 2 bytes | Minimum answer size before whitespace/login-page checks. | [L2781](source.html#L2781) | — |



These settings are documented in help, but their validation differs. The table describes actual consumption. Internal globals such as MODEL, YOLO, AUTO_COMMIT, GATES_NONE and RUN_DEADLINE are not additional supported environment options: normal entry initializes or derives them. All such shell reads/writes remain available in the raw source index.


| Name/context | Contract | Read sites | Write/export/apply sites |
| --- | --- | --- | --- |
| `NO_COLOR` | Nonempty disables ANSI color. | [L122](source.html#L122) | — |
| `TERM` | Default dumb; non-dumb plus tty stdout is required for color. | [L122](source.html#L122) | — |
| `TMPDIR` | Default /tmp for external raw captures and trim temporaries. | [L2881](source.html#L2881) ×2, [L3023](source.html#L3023) | — |
| `BASH` | Shell-provided current Bash path; preferred gate interpreter if executable. | [L1163](source.html#L1163) ×2, [L1164](source.html#L1164) | — |
| `BASH_SOURCE[0]` | Bash source context: empty indicates stream bootstrap; named source locates SELF. | [L49](source.html#L49), [L96](source.html#L96) | — |
| `BASH_VERSION` | Shell-provided version; doctor default unknown. | [L4989](source.html#L4989) | — |
| `LC_ALL` | Command-local C locale for byte/text processing; local C binding in load_spec. | — | [L199](source.html#L199), [L667](source.html#L667), [L3446](source.html#L3446), [L3455](source.html#L3455), [L3475](source.html#L3475), [L3513](source.html#L3513), [L4469](source.html#L4469) ×2, [L4506](source.html#L4506), [L4546](source.html#L4546), [L5131](source.html#L5131) |
| `GIT_OPTIONAL_LOCKS` | Command-local0 in discovery queries; not globally exported. | — | [L1019](source.html#L1019) |
| `GIT_NO_LAZY_FETCH` | Command-local1 in discovery queries; not globally exported. | — | [L1019](source.html#L1019) |
| `GIT_INDEX_FILE` | Internal alternate-index path for selected staging/diff/reset/commit commands. Commit exports it inside its child subshell. | — | [L2087](source.html#L2087), [L2099](source.html#L2099), [L2103](source.html#L2103), [L2107](source.html#L2107), [L2120](source.html#L2120), [L2126](source.html#L2126), [L2378](source.html#L2378), [L2394](source.html#L2394), [L2423](source.html#L2423), [L2434](source.html#L2434), [L2461](source.html#L2461) |
| `IS_SANDBOX` | Engine environment array adds1 for Claude when YOLO is enabled; applied via env during invocation. | — | [L2725](source.html#L2725), [L2894](source.html#L2894) |
| `PATH / inherited provider environment` | Command lookup and children inherit host environment; Ralphie does not enumerate credentials or directly expand HOME/PATH in this source. External tools may interpret any inherited values. | — | — |



Bash special parameters (`$?`, `$$`, `$!`, argv), file descriptors and the process table are also inputs. IFS is set empty around line/NUL readers; locale/PATH and external-program defaults remain host behavior where no override is shown. The `env IS_SANDBOX=1` construction and stream `env RALPHIE_NO_UPDATE=1` are execution argv, not standalone global exports. [L71](source.html#L71), [L809](source.html#L809), [L2894](source.html#L2894), [L2897](source.html#L2897)


## Files, schemas and persistence


Unless qualified below, paths are relative to **PROJECT/.ralphie**. `PID`, `N`, `ID`, `TOKEN` and `EPOCH` denote generated values, not literal filenames. Reads may create/repair runtime state through `ledger_init`; only early help/version/discover/request dispatch bypasses that generic initializer. [L106–120](source.html#L106); [L519–564](source.html#L519); [L5454–5468](source.html#L5454)


| Path/family | Direction/schema | Contract | Source |
| --- | --- | --- | --- |
| state | Read/write key=value | Allowlisted keys; CR/LF removed from values; last duplicate key wins. Normal write is mutex + same-directory tempfile/rename; fallback is best effort. | [L290–349](source.html#L290) |
| state.lock; state.tmp.PID.TOKEN | Internal write scratch | mkdir mutex, up to30 failed acquisition attempts before forced recreation; scratch suffix includes6 token characters. | [L324–342](source.html#L324) |
| events.jsonl; events.jsonl.1..N | Append/rotate/read | One JSON object per line; old files shift through finite retention. Recovery scans current plus numeric generations; log/history presentations generally read current only. | [L351–381](source.html#L351); [L472–517](source.html#L472); [L614–638](source.html#L614) |
| OBJECTIVE.md | Authoritative objective bytes | Explicit spec retains exact bytes/trailing LF; ordinary objective adds presentation LF. In-memory copy restores changes during the run; state objective_hash tracks input identity. | [L3382–3394](source.html#L3382); [L5309–5336](source.html#L5309) |
| acceptance | Four-line bound configuration | ralphie-acceptance-v1, random nonce, objective hash, single-line command; full-file digest binds state and memory. Missing/damaged required evidence fails closed; none tombstones old acceptance. | [L3183–3269](source.html#L3183) |
| gates; gates.baseline; gates.previous | Executable text and witnesses | One active shell command per nonblank/noncomment line. Baseline protects between-run membership; previous is best-effort redetection backup. A protected empty existing gate file stays empty. | [L1251–1316](source.html#L1251); [L1439–1479](source.html#L1439); [L5036–5072](source.html#L5036) |
| gates.tmp.PID; gates.restore.PID; gates.keep.PID; run/gates.before | Gate publication/restoration scratch | Discovery temporary, ordered-merge candidate, pre-rewrite backup, and disk copy of in-memory snapshot. The in-memory snapshot is the current-run guard authority. | [L1266](source.html#L1266), [L1482](source.html#L1482), [L1507](source.html#L1507), [L1556](source.html#L1556), [L1612](source.html#L1612) |
| MEMORY.md; MEMORY.md.tmp.PID | Durable lesson text | Header plus deduplicated - lesson lines, flattened/capped to1000 bytes each; MEMORY_MAX retention. Recent whole-line prompt excerpt has3900-byte budget. | [L3451–3466](source.html#L3451); [L3710–3734](source.html#L3710) |
| ASK.md; ASK.md.tmp.PID | Question/answer text | Numbered open/answered Markdown sections and > answer slots. Open excerpts omit answer lines; only CLI answer transitions headers and copies a redacted decision into memory. | [L4512–4612](source.html#L4512) |
| requests/slot-1..slot-32/ID.txt | Published operator text | ID = epoch-pid-token;1..4096 bytes; published regular owned non-symlink files. Producer writes hidden .body then chmod400 and renames. Every active request is injected at subsequent cycle boundaries. | [L4328–4510](source.html#L4328) |
| requests/slot-N/.body; ID.applied | Reservation and presentation receipt | Private staging body remains if interrupted. Exclusive .applied receipt contains durable cycle prompt path; means presented, not implemented/verified. Applied bodies stay active. | [L4408](source.html#L4408), [L4411](source.html#L4411), [L4498](source.html#L4498), [L4500](source.html#L4500), [L4507](source.html#L4507), [L4508](source.html#L4508) |
| request-write.lock/{pid,token,since}; request-archives/EPOCH-PID-TOKEN/ | Writer coordination and retained batches | Separate publication lock. Archive takes worker then writer lock, renames full active batch including unfinished reservations, and recreates active directory. Nothing archived is implicitly completed. | [L4421–4455](source.html#L4421) |
| lock/{pid,token,since}; stop | Worker coordination/stop | mkdir/PID/token worker lock. Stop marker is consumed between cycles; a first-iteration stale marker is removed without stopping that newly started run. | [L748–802](source.html#L748); [L4288–4297](source.html#L4288); [L5228](source.html#L5228) |
| owned.nul; owned.nul.tmp.PID | Content-keyed ownership | Records checksum TAB repository-relative path NUL. Matching current dirty bytes allow ownership across cycles/runs; operator-preexisting, runtime and sibling paths are excluded. | [L1732–1882](source.html#L1732) |
| run/pre-dirty.PID.nul; run/operator-staged.nul; run/pre-dirty.raw.PID | Operator custody snapshots | NUL-delimited repository-relative paths; memory checksum seals pre-dirty evidence. Originally staged paths are preserved when real index is reconciled. | [L1983–2063](source.html#L1983); [L2484–2502](source.html#L2484) |
| run/dirty-now.nul; run/dirty.nul; run/staged.PID.nul | NUL path scratch | Scratch for ownership reconciliation and private-index filtering; NULs travel through files, never command substitution. | [L1807](source.html#L1807), [L1867](source.html#L1867), [L2083](source.html#L2083) |
| run/index.PID | Git alternate index | Private index staged from HEAD or unborn state, scoped to PROJECT, filtered before commit. No promise of an OS sandbox or immutable Git hooks. | [L2267–2296](source.html#L2267); [L2365–2454](source.html#L2365) |
| run/engine-commit-paths.PID.nul; run/committed.PID.nul | Committed path evidence | NUL paths used to validate engine-created history and synchronize only unprotected committed paths back into real index. | [L2231](source.html#L2231), [L2490](source.html#L2490) |
| run/commit-error.PID | Commit capture | Merged hook/signing/git stdout/stderr; bounded excerpts feed events/questions; removed on successful save. | [L2456–2482](source.html#L2456) |
| run/tree.mark; run/verify.mark | Timestamp witnesses | Freshness combines mtime, non-noise regular-file pathname digest and Git/runtime fingerprint. These are change heuristics, not an atomic content snapshot. | [L654–742](source.html#L654) |
| run/ledger-all.PID; run/acceptance-paths.PID | Recovery/work scratch | Concatenated retained ledgers for state rebuild; NUL paths for eligible acceptance-work fingerprint. | [L479](source.html#L479), [L3315](source.html#L3315) |
| run/cycle-N.prompt.md | Engine stdin and durable request receipt target | Persisted assembled prompt; source documents/spec/request bodies are data. Prompt is required before engine launch and acknowledgement. | [L3784](source.html#L3784), [L3880](source.html#L3880), [L4408](source.html#L4408); [L3583–3671](source.html#L3583) |
| run/cycle-N.answer; log/cycle-N.log | Engine answer/capture | Usability/report parsing precede tail retention. Attempts/borrowed engines reuse these paths and can replace prior full capture for that cycle. | [L2853–2953](source.html#L2853); [L3785](source.html#L3785), [L3786](source.html#L3786), [L3926](source.html#L3926), [L3927](source.html#L3927), [L3928](source.html#L3928) |
| run/gates[-N][-after].summary; .K.log; .K.log.retry; .K.log.trim; run/trial.PID | Health and trial captures | PASS/FAIL(rc)/UNVERIFIED/UNREADABLE summary text; numbered merged output; retry/temp output removed; primary log trimmed after use. | [L1213–1249](source.html#L1213); [L1322–1422](source.html#L1322) |
| log/acceptance-N.log; .trim | Acceptance capture | Merged command output and current acceptance exit evidence; retained tail uses GATE_LOG_MAX. | [L3271–3293](source.html#L3271) |
| run/sessions/RUN_ID/**/*.jsonl | External Prime session records | Prime writes records; optional Python reads current-run usage only. Session schema/lifecycle belongs to selected engine version; retention uses RALPHIE_KEEP_RUNS. | [L2689](source.html#L2689), [L3047](source.html#L3047); [L3050–3119](source.html#L3050) |
| ralphie.previous | Update backup | Best-effort prior SELF bytes under selected project runtime directory, even if SELF is installed elsewhere. | [L4865](source.html#L4865) |
| TMPDIR/ralphie.raw.XXXXXX or .PID; TMPDIR/ralphie.tail.XXXXXX | Outside-project engine scratch | Raw capture survives deletion of project runtime paths; trim scratch bounds retained captures. Default TMPDIR=/tmp. | [L2881](source.html#L2881), [L3023](source.html#L3023) |
| mktemp result or /tmp/ralphie.PID | Update download scratch | Downloaded candidate verified then copied/moved onto SELF; temporary removed on handled rejection/success. | [L4838–4871](source.html#L4838) |
| SELF; streamed pwd/ralphie.sh and .tmp.PID | Running/installable script | Self-hash detects changes; self-update replaces SELF. Bootstrap reconstruction saves streamed source before execution. | [L49–76](source.html#L49); [L1930–1966](source.html#L1930); [L4826–4875](source.html#L4826) |
| Git metadata info/exclude/config/index/objects/refs/reflogs | External Git persistence | Local runtime ignore rule, optional default identity, alternate-index commits and branch operations modify repository metadata. | [L567–585](source.html#L567); [L1704–1730](source.html#L1704); [L2456–2502](source.html#L2456) |



**State key allowlist:** `cycle`, `engine`, `model`, `request_set`, `objective_hash`, `acceptance_binding`, `acceptance_work`, `blocked_count`, `untrusted_count`, `started_at`, `updated_at`, `status`, `reason`, `pass_count`, `fail_count`, `learned_count`, `last_cycle_at`, `run_id`, `unverified_count`, `nochange_streak`, `objective_started`, `tokens_spent`, `run_tokens`, `run_cost`, `start_commit`, `base_branch`, `total_seconds`. [L290–294](source.html#L290)


**Event shape:** `{"ts":"UTC ISO timestamp","run":"ID","cycle":N,"kind":"...","status":"...","detail":"...", "extra":"..."}`. Extras come from internal key=value arguments and are strings; cycle is numeric. Detail and extra values are escaped, while structural kind/status/run/extra-key strings are trusted internal inputs. Appends have no separate fsync queue. Retention bounds historical reconstruction. [L351–381](source.html#L351); [L614–638](source.html#L614)


**Question schema:** `## QN  [open]  ISO_TIMESTAMP`, followed by question text and a blank `> ` answer slot. `answer N TEXT` changes the section to `[answered]`, fills blank slots and records the flattened answer; only its remembered decision copy is redacted. A manually edited answer slot is not automatically consumed into memory by this implementation. Open-question display is bounded to20 lines/1000 bytes per line. The channel never waits for terminal input. [L4520–4612](source.html#L4520)

## Project content consumed as inputs


| Input | Interpretation/bounds | Source |
| --- | --- | --- |
| Root manifests/lockfiles | Package scripts, Python manifests/venvs, Cargo/go/Deno/mix/Gemfile/Maven/Gradle/Composer/Make/Terraform/shell presence propose checks. Candidate commands are subsequently executed during discovery trials; this is not a general workspace graph. | [L930–1141](source.html#L930) |
| Shell files and executable test.sh | First40 lines containing ralphie-kernel exclude Ralphie copies; a runtime-glob bash-n gate and optional ./test.sh are proposed only under the documented root conditions. | [L1126–1140](source.html#L1126) |
| Standing instructions | Prompt embeds first3000 bytes each of AGENTS.md, CLAUDE.md, CONVENTIONS.md, .cursorrules. Discovery only reports AGENTS.md/CLAUDE.md/GEMINI.md presence. These lists differ intentionally in the current source. | [L1047](source.html#L1047); [L3535–3543](source.html#L3535) |
| Known plans | IMPLEMENTATION_PLAN.md, PLAN.md, TODO.md, TASKS.md, ROADMAP.md, docs/TODO.md; unchecked Markdown boxes. Backlog caps20 matches per file and1000 bytes per line; focus uses first5, prompt first10 when not already backlog. | [L3470–3487](source.html#L3470); [L3425](source.html#L3425), [L3639](source.html#L3639) |
| Objective/spec | Full OBJECTIVE.md stays authoritative; prompt excerpt is first4000 bytes and points to the full file when longer. Engine obedience to that instruction is external behavior. | [L3407](source.html#L3407); [L3586–3605](source.html#L3586) |
| Recent evidence | Git last commit,25 dirty-status lines and5 recent commits; last10 matching current-ledger cycle outcomes; recent lessons and open questions; failing gate tail. These are bounded context, not complete history. | [L3490–3532](source.html#L3490); [L3628–3656](source.html#L3628) |
| Published requests | All active bodies at cycle boundary enter prompt in full under a data heading. Membership changes reset stale completion/work credit and block completion until consumed by a later boundary. | [L4362–4416](source.html#L4362) |



## Process, stdio and executable boundaries


| Boundary | Input | Output/status | Authority/lifetime | Source |
| --- | --- | --- | --- | --- |
| Health / acceptance | PROJECT cwd; selected Bash -c prelude+command; stdin /dev/null. Native gate prelude enables pipefail and EXIT job reap. | stdout+stderr merged into per-gate log; child rc or watchdog124. Acceptance records a flag/event rather than returning command rc. | Inherited operator permissions. No shell read from the terminal; command can still access other files/network/terminal devices itself. | [L1154–1211](source.html#L1154); [L3271–3293](source.html#L3271) |
| Engine invocation | PROJECT cwd; direct adapter argv; persisted prompt on stdin; inherited environment plus ENGINE_ENV. | Merged raw stdout/stderr; stdout answer or engine-written file; usage/report consumed separately. | Job-control process group when available; tracked PID; idle/hard/output watchdog. Arbitrary engine tools are external. | [L2853–2928](source.html#L2853) |
| Git commit | Repository-root cwd; alternate index; generated commit message; stdin /dev/null. | Merged commit-error capture; rc plus COMMIT_FAILED/COMMIT_SKIPPED and actual HEAD movement postcondition. | Configured hooks/signers may execute. COMMIT_TIMEOUT applies, but their earlier effects are not rolled back. | [L2456–2482](source.html#L2456); [L4110–4173](source.html#L4110) |
| Engine liveness | Executable --version. | Discarded stdout/stderr; memoized status. | 15-second timeout utility if available; no built-in watchdog fallback for this probe. | [L2578–2599](source.html#L2578) |
| Notification | Configured sh -c RALPHIE_NOTIFY_CMD with RALPHIE_MESSAGE. | stdout/stderr discarded; notify returns0 after bounded polling. | Untracked hook may remain alive beyond RALPHIE_NOTIFY_WAIT and run exit. | [L4614–4627](source.html#L4614) |
| Package metadata parsing | Node/Python short parser with package.json path/name. | Exit status indicating named script presence. | Optional parsers used by normal candidate discovery; preview overrides them with text matching. | [L938–951](source.html#L938); [L994–1008](source.html#L994) |
| Awk answer insertion | Flattened CLI answer in child environment RALPHIE_ANSWER. | Rewritten question section, event, and separately redacted memory note. | Answer is data rather than evaluated Awk code; the unredacted answer remains in ASK/event evidence. | [L4586–4612](source.html#L4586) |
| Usage parser | Python heredoc code; current session directory argv. | Integer tokens and six-decimal cost text; no Python means no update/estimate. | Reads external engine JSONL; not billing reconciliation. | [L3031–3119](source.html#L3031) |
| Global cleanup | EXIT, INT/TERM/HUP, PIPE and tracked child IDs. | INT/TERM/HUP exits130; PIPE redirects stdout then final141; owned-run exit writes custody/status evidence. | PID/group TERM then KILL; best-effort cleanup, not isolation or a guarantee after SIGKILL/power loss. | [L808–916](source.html#L808) |



Regular informational stdout uses the pipe-aware helper; warnings/errors/debug use stderr. Quiet hides info/dim progress, not warnings and verdicts. A gate’s rc, an engine answer’s usability, and final objective completion are distinct signals. [L140–159](source.html#L140)


## Engine adapter and answer contracts


| Adapter | Constructed protocol | Declared capabilities | Evidence |
| --- | --- | --- | --- |
| prime-agent | `-p --mode text --cwd PROJECT --offline`; model/thinking optional; per-run session or --no-session. In bounded autonomous mode pass every gate separately, turns24/continuations6, optional token ceiling, positive call/gate milliseconds. | autonomy gates memory subagents resume skills json usage; no stream | [L2533–2537](source.html#L2533); [L2675–2717](source.html#L2675) |
| claude | `-p`, optional model; YOLO adds --dangerously-skip-permissions and IS_SANDBOX=1. | subagents resume skills json; no stream | [L2535](source.html#L2535); [L2718–2727](source.html#L2718) |
| codex | `exec`, optional model/reasoning config; YOLO bypass flag; prompt stdin through `-`; --output-last-message points to answer file. | resume json stream | [L2536](source.html#L2536); [L2728–2734](source.html#L2728) |
| custom | Executable whole path if executable, otherwise unquoted field-split/glob argv. Prompt stdin. No shell grammar parsing; complex workflows need an executable wrapper. | RALPHIE_ENGINE_CAPS, empty by default; answer route defaults stdout | [L2544–2549](source.html#L2544); [L2735–2742](source.html#L2735) |



Selection prefers responsive Prime when no engine was named. Explicit --engine or nonempty RALPHIE_ENGINE_CMD prohibits provider substitution. Otherwise fallback is cycle-local, capability-ranked, and strips a model ID borrowed from another provider namespace; a weaker adapter falls back to oneshot mode. Capability labels are declarations, not version negotiation or proof of a provider’s implementation. [L2612–2673](source.html#L2612); [L3121–3160](source.html#L3121)


Prime --offline suppresses its startup release check according to the adapter contract; it does **not** make model inference offline. --no-yolo changes supported adapter flags and does not implement a sandbox for Prime or custom tools. [L2677–2684](source.html#L2677); [L2736](source.html#L2736)


An answer needs MIN_ANSWER_BYTES, some nonwhitespace content, and no obvious HTML/login marker in its first2000 bytes. Normal success is rc0 plus usable answer. One narrow exception accepts Prime autonomous rc1 only when the final nonblank log line matches `Autonomous quality gate still failing after attempt N/N: ...` or `Autonomous run stopped before terminal evidence; (maxContinuations|maxTurns|maxTokens|timeoutMs) reached (...`. Ralphie still verifies project gates independently. [L2774–2788](source.html#L2774); [L2930–2953](source.html#L2930)


Output resource limits count raw capture plus answer bytes during and after execution. Exceeding returns125, empties the answer, and forbids retry/fallback. Consumed captures above262144 bytes become a marker plus262080-byte tail; provider session files and arbitrary engine-created files are outside that capture ceiling. [L2858–2927](source.html#L2858); [L2955–3029](source.html#L2955)


**Session usage schema:** read current-run `.jsonl` files, ignoring blank/non-JSON/nondict rows. Message records carry `message.usage`; assistant message `id` values are targets for `child_usage_attributed.targetId`, whose last `aggregateUsage` replaces that assistant usage within the same file. Attribution rows are not added independently. `compaction` and `branch_summary` carry entry-level `usage`. Sum numeric `totalTokens` and `cost.total` (booleans excluded); shell adds the nonnegative run-token delta to lifetime tokens and stores current run tokens/cost. No Python means no usage update or estimate. External session schema changes and duplicate records across files remain outside this reader’s guarantees. [L3031–3119](source.html#L3031)

## Report, acceptance, status and return protocols


The model is asked to finish with this text block. It is an attributed report, not authority to mark code verified. [L3546–3581](source.html#L3546)


```text
<<<RALPHIE
status: progress | done | blocked
summary: one line describing what actually changed
lesson: one durable fact, or -
ask: one human-only question, or -
RALPHIE>>>
```


Parser rules: last complete marker block wins; markers are substring regex matches. A later incomplete block does not erase an earlier complete block. First case-sensitive field label wins and CR is stripped; status values lowercase to done for done/complete/finished, blocked for blocked/stuck, otherwise progress. Exact `-`, `none`, `n/a`, `NA`, or empty suppresses lesson/ask. Present file without a complete block defaults to progress; missing file leaves fields empty. [L3678–3708](source.html#L3678)


**Shared completion postcondition:** current nonempty health gates green; trusted cycle/save policy; no gate tamper, commit failure, running-source edit, outstanding owned work, newly pending request, or unmet acceptance requirement. If acceptance is configured, completion additionally needs current acceptance pass and eligible actual-work identity bound to that objective. Health-green progress can be saved while acceptance is unmet. Acceptance-induced changes trigger health remeasurement; further mutation invalidates acceptance instead of looping checks indefinitely. [L3295–3377](source.html#L3295); [L3949–4007](source.html#L3949)


| API/signal | Return/value contract | Evidence |
| --- | --- | --- |
| gate_trial | 0 means usable candidate, even for ordinary failing/timeout results;2 excludes unavailable executable/tool. This is not a project pass. | [L1213–1249](source.html#L1213) |
| run_gates | 0 with GATES_NONE0 means no failed health commands;0 with GATES_NONE1 means UNVERIFIED/no checks. Unreadable gate file or measured failures return1. Verify never forgives fail-then-pass; observe can. | [L1322–1422](source.html#L1322) |
| acceptance_verify | Returns0 after ordinary pass/fail handling; ACCEPT_PASS/event carry outcome. It runs only for intact configured acceptance and nonempty green health under save policy. | [L3271–3293](source.html#L3271) |
| watchdog_wait / engine_invoke | Actual child rc, or124 hard/idle timeout,125 combined output ceiling. Polling/grace can exceed nominal allowance. | [L2955–3015](source.html#L2955) |
| engine_run | 0 usable answer;1 attempts exhausted;2 cannot start;3 permanent failure;4 run budget expired;5 output resource limit. ENGINE_REASON holds explanation. | [L2792–2851](source.html#L2792) |
| engine_run_with_fallback | 0 when primary/allowed borrowed engine supplies answer;1 otherwise. Explicit selection, spent budget and output resource ceiling prevent provider fallback. | [L3121–3160](source.html#L3121) |
| Commit recording | Return codes/flags are supplemented by a single postcondition: a green auto-save must move HEAD unless intentionally skipped/already failed. Gate-green alone does not prove persistence. | [L4132–4173](source.html#L4132) |
| Cycle internal10 /11 | 10 means done;11 means budget pause. Loop maps both to process0. | [L4237](source.html#L4237), [L4306](source.html#L4306), [L4307](source.html#L4307) |
| Process0 | Successful command, completed objective, requested stop, cycle limit or time-budget pause; **not exclusively task completion**. | [L4276–4310](source.html#L4276); [L5471–5475](source.html#L5471) |
| Process1 /2 /3 | 1 typical invalid/startup/refusal;2 blocked cycle/no completed engine or missing acceptance-work baseline;3 persisted no-progress stall. Other unhandled shell/command failures can propagate. | [L159](source.html#L159), [L3889](source.html#L3889), [L3917](source.html#L3917), [L4228](source.html#L4228), [L4304](source.html#L4304), [L5471](source.html#L5471) |
| Process130 /141 | Installed INT/TERM/HUP cleanup / closed-output SIGPIPE cleanup. Early commands before trap installation have their ordinary shell behavior. | [L863–916](source.html#L863); [L5454–5465](source.html#L5454) |



`status --json` normally writes **one JSON line** with string fields `version, project, status, engine, model, branch, start_commit, reason, run`; integer fields `cycle, pass, fail, gates, lessons, questions_open, blocked, untrusted, unverified, tokens, run_tokens, seconds`; and decimal `run_cost`. Integer readers normalize nondigits to0. `json_dec` rejects nondigit/non-dot characters or more than one dot but does not perform a full JSON-number parse; arbitrary poisoned values therefore are outside a guaranteed well-formed-number contract. A persisted running state with no live lock owner is rendered interrupted without claiming the worker still exists. [L4928–4968](source.html#L4928)


Lifecycle status writes include new/running/paused/stopped/done/blocked/stalled/error; status also presents interrupted when liveness disagrees. Human output remains presentation, and `log` uses a narrow retained-event renderer rather than a generic JSON reader. [L542](source.html#L542), [L880](source.html#L880), [L897](source.html#L897), [L3868](source.html#L3868), [L3889](source.html#L3889), [L4224](source.html#L4224), [L4235](source.html#L4235), [L4272](source.html#L4272), [L4284](source.html#L4284), [L4296](source.html#L4296), [L4300](source.html#L4300), [L4381](source.html#L4381), [L4886](source.html#L4886), [L4956](source.html#L4956); [L5074–5080](source.html#L5074)


## Git and network protocols


Git path custody uses repository-relative **NUL-delimited** names, not parsed porcelain quoting. PROJECT may be a subdirectory of the repository; a physical project prefix confines staging and ownership. Filesystem-derived pathspecs use command-local --literal-pathspecs. An alternate GIT_INDEX_FILE preserves operator staging while risky/bulk/runtime/preexisting paths are excluded; after commit only unprotected committed paths are resynchronized. These are Git ownership rules, not an OS filesystem boundary. [L1732–1882](source.html#L1732); [L1983–2146](source.html#L1983); [L2155–2296](source.html#L2155); [L2365–2502](source.html#L2365)


Startup may `git init` and fill missing local identity; local info/exclude suppresses runtime files. Branch choice uses checkout/existing-or-new refs; finish may restore the original branch only when permitted by the current tree. In-progress merge/cherry-pick/revert/rebase markers block automatic commit. Engine-created commits are inspected from committed objects for linear history, scope, protected paths, size and symlink rules; rejection preserves history for review rather than resetting it. This source does not automatically push or fetch. Inherited Git filters, hooks, signing and helpers can execute external code. [L1704–1730](source.html#L1704); [L1891–1928](source.html#L1891); [L2205–2265](source.html#L2205); [L2344–2361](source.html#L2344); [L5422–5441](source.html#L5422)


| Network/external protocol | Implementation contract | Evidence |
| --- | --- | --- |
| Self-update source | Nonempty RALPHIE_UPDATE_URL, else GitHub origin+current branch+ME raw URL. Origin supports git@github.com: or https://github.com/ with path checks; invalid branch becomes master. Initial URL must match https://, file:// or absolute path. | [L4804–4837](source.html#L4804) |
| Downloader | Optional curl -fsSL --max-time60 preferred; wget -qO fallback without equivalent explicit max-time. Both capture to temporary file with stderr suppressed; absent downloaders reject update. | [L4837–4841](source.html#L4837) |
| Candidate trust/execution | Require six marker strings, minimum byte size, bash-n, executed candidate version, no older version, and changed bytes. Candidate version runs with RALPHIE_LIB0 before replacement. These checks are structural/version checks, not signature/authenticity or sandbox proof. | [L4845–4875](source.html#L4845) |
| Engine providers | Network/authentication/model APIs are owned by selected engine and inherited configuration. Ralphie passes argv/stdin and reads files/status; no provider API wire protocol or credentials are implemented here. | [L2665–2751](source.html#L2665); [L2853–2928](source.html#L2853) |
| Gate/project commands, Git helpers, notification hook | May reach external services with operator authority. No destination allowlist or packet-level control is supplied by this runner; source cannot determine their runtime actions. | [L1197](source.html#L1197), [L2461](source.html#L2461), [L4622](source.html#L4622) |



## Coverage and boundaries


- **15 commands;22 global option families.** Command/option tables were checked against parsing and dispatch source, not inferred only from help.
- **28 RALPHIE-prefixed names:** all source identifiers in this namespace are classified, plus the separately excluded heredoc marker. The site table contains **41 read occurrences and7 assignment/export occurrences**, including Awk ENVIRON and stream env-argv supplements. Help-only RALPHIE_OUTPUT has no runtime site.
- **17 additional configurable limits** and explicit host/child environment interfaces are catalogued. Their full read/write sites are linked; opaque inherited environment remains an external-process boundary.
- All durable paths and internal scratch families are grouped by schema/ownership rather than duplicating234 function contracts. The raw index preserves each redirect and variable site.
- Runtime correctness, provider behavior, filesystem failure/concurrency behavior and actual command effects were not established by this static catalogue. It is a comprehension artifact pinned to the stated source bytes.

