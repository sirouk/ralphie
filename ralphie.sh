#!/usr/bin/env bash
#
#   ██████╗  █████╗ ██╗     ██████╗ ██╗  ██╗██╗███████╗
#   ██╔══██╗██╔══██╗██║     ██╔══██╗██║  ██║██║██╔════╝
#   ██████╔╝███████║██║     ██████╔╝███████║██║█████╗
#   ██╔══██╗██╔══██║██║     ██╔═══╝ ██╔══██║██║██╔══╝
#   ██║  ██║██║  ██║███████╗██║     ██║  ██║██║███████╗
#   ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝  ╚═╝╚═╝╚══════╝
#
#   An autonomy kernel for any project, on any machine, with any AI engine.
#
#   ralphie-kernel: this marker identifies this file to Ralphie itself. Gate
#   discovery uses it to avoid manufacturing a check of its own source, which
#   would be a gate that can never fail. Keep it, and keep it near the top.
#
#   THESIS
#     Ralphie supplies exactly the complement of what the engine cannot do.
#
#         ralphie = required_autonomy - engine_native_capability
#
#     Engines are measured, not assumed. A capable engine makes Ralphie shrink
#     to a durability shell. A weak engine makes Ralphie supply the scaffolding.
#     A better engine invented tomorrow needs no edit here.
#
#   LOOP
#     observe -> decide -> act -> verify -> record -> learn   (until done)
#
#   INVARIANTS
#     1. One file. bash + coreutils + git. No runtime dependencies.
#     2. Gates are truth. Only a passing gate promotes work. Self-reports never do.
#     3. Every run is resumable. Kill it anywhere; it continues correctly.
#     4. The ledger is append-only. State is derived, evidence is permanent.
#     5. The human is never blocked. Questions are files, not prompts.
#     6. Never waste a token on something a shell command already knows.
#     7. Every abnormal exit records a reason code.
#
#   Plant it in a project and run it:   ./ralphie.sh "make the tests pass"
#
#   License: MIT
#

# --- stream bootstrap -------------------------------------------------------
# `curl ... | bash` has no BASH_SOURCE. Persist to disk, then re-exec from disk
# so that every relative path anchors to the project the operator is standing in.
# Bash reads a piped script one character at a time, so `cat` here receives
# exactly the bytes after this block -- and nothing before it. The prefix bash
# already consumed has to be reconstructed, starting with the shebang, or the
# persisted file has no interpreter line and breaks the moment it is run again.
if [ "${RALPHIE_LIB:-0}" != "1" ] && [ -z "${BASH_SOURCE[0]:-}" ]; then
    _rb_target="$(pwd)/ralphie.sh"
    _rb_tmp="${_rb_target}.tmp.$$"
    if {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' '#'
        printf '%s\n' '#   RALPHIE - an autonomy kernel for any project.'
        printf '%s\n' '#   ralphie-kernel'
        printf '%s\n' '#'
        printf '%s\n' '#   Thesis: ralphie supplies exactly the complement of what the engine'
        printf '%s\n' '#   cannot do.  ralphie = required_autonomy - engine_native_capability'
        printf '%s\n' '#'
        printf '%s\n' '#   Loop: observe -> decide -> act -> verify -> record -> learn'
        printf '%s\n' '#'
        printf '%s\n' '#   Installed from a stream. Run `./ralphie.sh --help` to begin.'
        printf '%s\n' '#   License: MIT'
        printf '%s\n' '#'
        cat
    } > "$_rb_tmp"; then
        chmod +x "$_rb_tmp" 2>/dev/null || true
        mv -f "$_rb_tmp" "$_rb_target"
        printf 'ralphie: installed %s\n' "$_rb_target" >&2
        exec env RALPHIE_NO_UPDATE=1 "$_rb_target" "$@"
    fi
    rm -f "$_rb_tmp"
    printf 'ralphie: could not write %s\n' "$_rb_target" >&2
    exit 1
fi

set -euo pipefail

VERSION="3.0.0"

# A literal newline, for patterns. `$(printf '\n')` cannot be used: command
# substitution strips trailing newlines, leaving an empty pattern that matches
# every string -- which silently rejected every --gate.
RALPHIE_NL='
'

# ============================================================================
# LAYER 1 - CORE
#   Terminal-safe output, portable shims for tools that are missing on minimal
#   systems, and the small primitives every other layer stands on.
# ============================================================================

# Parameter expansion instead of dirname/basename: two fewer external commands
# to depend on, and it still works when PATH is broken or nearly empty.
_self_src="${BASH_SOURCE[0]}"
_self_dir="${_self_src%/*}"; [ "$_self_dir" = "$_self_src" ] && _self_dir="."
_self_name="${_self_src##*/}"
SELF="$(cd "$_self_dir" 2>/dev/null && pwd)/$_self_name"
PROJECT="${RALPHIE_PROJECT:-$(cd "$_self_dir" 2>/dev/null && pwd)}"
ME="$_self_name"
unset _self_src _self_dir _self_name

HOME_DIR="$PROJECT/.ralphie"
STATE_FILE="$HOME_DIR/state"
EVENTS_FILE="$HOME_DIR/events.jsonl"
GATES_FILE="$HOME_DIR/gates"
OBJECTIVE_FILE="$HOME_DIR/OBJECTIVE.md"
ASK_FILE="$HOME_DIR/ASK.md"
MEMORY_FILE="$HOME_DIR/MEMORY.md"
LOG_DIR="$HOME_DIR/log"
RUN_DIR="$HOME_DIR/run"
LOCK_FILE="$HOME_DIR/lock"
STOP_FILE="$HOME_DIR/stop"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    C_RED=$'\033[1;31m'; C_YEL=$'\033[1;33m'; C_BLU=$'\033[1;34m'
    C_GRN=$'\033[1;32m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
    C_RED=""; C_YEL=""; C_BLU=""; C_GRN=""; C_DIM=""; C_OFF=""
fi

VERBOSE="${RALPHIE_VERBOSE:-0}"
# --quiet silences the running commentary -- info and dim -- and nothing else.
# A warning, an error and the verdict of a cycle always survive it: an
# unattended run that hides the one line explaining why it stopped is worse
# than a noisy one.
QUIET="${RALPHIE_QUIET:-0}"

# A launcher can pass SIGPIPE as ignored (including CI runners). Bash cannot
# install a trap for a signal ignored at exec, so check terminal writes too.
# Do this after printf returns: bash 3.2 must retire its failed buffer before
# EXIT forks command substitutions that write ledger data.
terminal_printf() {
    local code=0
    printf "$@" || code=$?
    if [ "$code" -ne 0 ] && [ -p /dev/stdout ]; then
        on_pipe
        return 141
    fi
    return "$code"
}
say()  { terminal_printf '%s\n' "$*"; }
# The quiet guard is `||`, never `&& return`, so a suppressed line still
# reports success. Several functions end on `[ ... ] && dim "..."`, and turning
# a silenced line into a failed one would abort the run under `set -e`.
info() { is_true "$QUIET" || terminal_printf '%s%s%s\n' "$C_BLU" "$*" "$C_OFF"; }
good() { terminal_printf '%s%s%s\n' "$C_GRN" "$*" "$C_OFF"; }
warn() { printf '%s%s%s\n' "$C_YEL" "$*" "$C_OFF" >&2; }
err()  { printf '%s%s%s\n' "$C_RED" "$*" "$C_OFF" >&2; }
dim()  { is_true "$QUIET" || terminal_printf '%s%s%s\n' "$C_DIM" "$*" "$C_OFF"; }
dbg()  { is_true "$VERBOSE" && printf '%s  . %s%s\n' "$C_DIM" "$*" "$C_OFF" >&2 || true; }
die()  { err "ralphie: $*"; exit 1; }

now_iso()  { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_epoch(){ date +%s; }
stamp()    { date -u +%Y%m%dT%H%M%SZ; }

# Portable shims. Minimal containers, BSD/macOS, busybox and Termux all differ.
have() { command -v "$1" >/dev/null 2>&1; }

sha_of() {
    # sha256 of stdin. Falls back through every common implementation, then to
    # cksum, which is weak but always present and only ever used for change
    # detection -- never for security.
    if   have sha256sum; then sha256sum       | awk '{print $1}'
    elif have shasum;    then shasum -a 256   | awk '{print $1}'
    elif have openssl;   then openssl dgst -sha256 | awk '{print $NF}'
    else cksum | awk '{print $1"-"$2}'
    fi
}

timeout_cmd() {
    # GNU coreutils `timeout`, macOS homebrew `gtimeout`, or nothing.
    if   have timeout;  then printf 'timeout\n'
    elif have gtimeout; then printf 'gtimeout\n'
    else printf '\n'
    fi
}

rand_token() {
    # Never depends on $RANDOM alone: seeded shells repeat it.
    if [ -r /dev/urandom ] && have od; then
        od -An -N6 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n'
    else
        printf '%s%s' "$(date +%s)" "$$"
    fi
}

json_escape() {
    # Escape stdin for embedding as a JSON string value. Control characters are
    # dropped rather than encoded: the ledger stores evidence, not binaries.
    LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' \
                 -e 's/\r//g' -e 's/[[:cntrl:]]//g' | awk 'BEGIN{ORS=""} {print sep $0; sep="\\n"}'
}

json_str() { printf '%s' "$1" | json_escape; }

is_int()  { case "${1:-}" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }
is_true() { case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in 1|true|yes|y|on) return 0;; *) return 1;; esac; }

trim() { printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

# Bounded reads. Agent logs can reach gigabytes; never load one into a variable.
tail_of() { [ -f "${1:-}" ] && tail -c "${2:-4000}" -- "$1" 2>/dev/null || true; }

secs_since() { local t="${1:-0}"; is_int "$t" || t=0; printf '%s' "$(( $(now_epoch) - t ))"; }

file_bytes() {
    # Size of a file, 0 if it is missing. `wc -c < missing` makes the SHELL
    # print "No such file or directory" before wc ever runs, so a 2>/dev/null
    # on the command cannot suppress it. In an unattended log, stray errors are
    # indistinguishable from real ones.
    local n
    [ -f "${1:-}" ] || { printf '0'; return 0; }
    n="$(wc -c < "$1" 2>/dev/null | tr -d ' \n')" || n=0
    is_int "$n" || n=0
    printf '%s' "$n"
}

count_of() {
    # `grep -c` prints 0 AND exits 1 on no match, so the common
    # `grep -c ... || echo 0` idiom emits "0\n0" and every later arithmetic
    # test explodes. One safe counter, used everywhere.
    local n; n="$( "$@" 2>/dev/null | wc -l | tr -d ' \n' )" || n=0
    is_int "$n" || n=0
    printf '%s' "$n"
}

human_secs() {
    local s="${1:-0}"; is_int "$s" || s=0
    if   [ "$s" -lt 60 ];   then printf '%ss' "$s"
    elif [ "$s" -lt 3600 ]; then printf '%sm%ss' "$((s/60))" "$((s%60))"
    else printf '%sh%sm' "$((s/3600))" "$(((s%3600)/60))"
    fi
}

# The operator's wall-clock budget as one absolute epoch second; 0 means
# unlimited. `loop` sets it once from --minutes and everything else only reads
# it. It exists because checking the budget between cycles was not enough: a
# single engine call may run for ENGINE_TIMEOUT seconds, so `--minutes 1` could
# return forty minutes late having never once been asked to stop.
RUN_DEADLINE=0

budget_left() {
    # Seconds of budget remaining, or -1 when the run is unlimited. Never
    # negative, so `0` means exactly one thing everywhere: the budget is spent.
    local left
    [ "${RUN_DEADLINE:-0}" -gt 0 ] || { printf '%s' '-1'; return 0; }
    left=$(( RUN_DEADLINE - $(now_epoch) ))
    [ "$left" -lt 0 ] && left=0
    printf '%s' "$left"
}

budget_expired() {
    # True only when a budget exists and has run out.
    [ "$(budget_left)" = "0" ]
}

budget_cap() {
    # Clamp a timeout to the time actually left in the budget. The one second
    # floor is deliberate: `timeout 0` means "no timeout at all" to GNU
    # coreutils, so an expired budget would otherwise buy an unlimited call.
    local want="${1:-0}" left
    is_int "$want" || want=0
    left="$(budget_left)"
    [ "$left" -lt 0 ] && { printf '%s' "$want"; return 0; }
    # A caller asking for 0 means "no limit of my own", which under a budget
    # means the budget, not zero seconds.
    if [ "$want" -le 0 ] || [ "$left" -lt "$want" ]; then want="$left"; fi
    [ "$want" -lt 1 ] && want=1
    printf '%s' "$want"
}

# ============================================================================
# LAYER 2 - LEDGER
#   State and evidence have different lifetimes.
#     state        counters and durable identities, a strict key=value allowlist
#     events.jsonl append-only audit trail, rotated at the retention limit
#   Acceptance identity must survive rotation; losing it fails closed.
#   Objectives, acceptance commands and operator requests retain their own files.
# ============================================================================

STATE_KEYS="cycle engine model request_set objective_hash acceptance_binding acceptance_work blocked_count untrusted_count \
    started_at \
    updated_at status reason pass_count fail_count learned_count \
    last_cycle_at run_id unverified_count nochange_streak objective_started \
    tokens_spent run_tokens run_cost start_commit base_branch total_seconds"

state_get() {
    local key="$1" def="${2:-}" line
    [ -f "$STATE_FILE" ] || { printf '%s' "$def"; return 0; }
    line="$(grep -E "^${key}=" "$STATE_FILE" 2>/dev/null | tail -1)" || true
    [ -n "$line" ] && printf '%s' "${line#*=}" || printf '%s' "$def"
}

state_set() {
    # Rewrites one key. Temp file plus atomic rename so an interrupt can never
    # leave a half-written state file, and a short mkdir mutex so two processes
    # -- a running loop and an `answer` typed in another terminal -- cannot lose
    # each other's update in the read-modify-write.
    local key="$1" val="$2" tmp lk tries=0
    case " $STATE_KEYS " in *" $key "*) ;; *) dbg "ignoring unknown state key: $key"; return 0;; esac
    val="$(printf '%s' "$val" | tr -d '\n\r')"
    mkdir -p "$HOME_DIR" 2>/dev/null || true
    # If the directory cannot be written at all, there is no contention to
    # arbitrate and nothing to wait for. Without this check the mutex spun for
    # thirty seconds on EVERY state write against a read-only .ralphie, and the
    # run hung instead of failing -- the worst outcome for an unattended loop.
    [ -w "$HOME_DIR" ] || { dbg "state directory is not writable; skipping"; return 0; }
    # Repaired HERE, on every write, not only at start-up. An agent that
    # replaced the state file with a DIRECTORY mid-run broke every write from
    # then on: `mv` moved each temp file INTO the directory instead (87 of them
    # accumulated), the cycle number vanished so the banner read "cycle  ",
    # every cycle overwrote the same log, and `status` was blank afterwards --
    # all of it silent, because each individual write "succeeded".
    [ -e "$STATE_FILE" ] && [ ! -f "$STATE_FILE" ] && ensure_state_file
    lk="$STATE_FILE.lock"
    while ! mkdir "$lk" 2>/dev/null; do
        tries=$((tries+1))
        # Bounded: a crashed writer must never wedge the loop forever.
        [ "$tries" -ge 30 ] && { rm -rf "$lk" 2>/dev/null; mkdir "$lk" 2>/dev/null || break; break; }
        sleep 1
    done
    tmp="$STATE_FILE.tmp.$$.$(rand_token | cut -c1-6)"
    { [ -f "$STATE_FILE" ] && grep -vE "^${key}=" "$STATE_FILE" 2>/dev/null || true
      printf '%s=%s\n' "$key" "$val"
    } > "$tmp" 2>/dev/null
    # `mv` onto a DIRECTORY moves the file inside it and reports success, so the
    # failure has to be detected by checking the result, not the exit status.
    if mv -f "$tmp" "$STATE_FILE" 2>/dev/null && [ -f "$STATE_FILE" ]; then :; else
        rm -rf "$tmp" "$STATE_FILE" 2>/dev/null || true
        { [ -f "$STATE_FILE" ] && grep -vE "^${key}=" "$STATE_FILE" 2>/dev/null || true
          printf '%s=%s\n' "$key" "$val"; } > "$STATE_FILE" 2>/dev/null || true
    fi
    rmdir "$lk" 2>/dev/null || true
}

state_bump() {
    local key="$1" by="${2:-1}" cur
    cur="$(state_get "$key" 0)"; is_int "$cur" || cur=0
    state_set "$key" "$(( cur + by ))"
}

event() {
    # event <kind> <status> [detail] [key=value ...]
    # One JSON object per line. Never rewritten. This is the evidence trail and
    # the only thing a post-mortem needs.
    local kind="$1" status="$2" detail="${3:-}"
    if [ "$#" -gt 3 ]; then shift 3; else set --; fi
    local extra="" kv
    for kv in "$@"; do
        [ -z "$kv" ] && continue
        extra="$extra,\"${kv%%=*}\":\"$(json_str "${kv#*=}")\""
    done
    mkdir -p "$HOME_DIR"
    # Repaired here, on every write. The append-only ledger is the evidence the
    # whole program rests on, and an agent that replaced it with a DIRECTORY got
    # three commits, zero events and exit 0: no history, no reason code, and
    # nothing in `status`. `state` was given this repair; the ledger, which
    # matters more, was not.
    [ -e "$EVENTS_FILE" ] && [ ! -f "$EVENTS_FILE" ] && ensure_own_file "$EVENTS_FILE" "ledger"
    # The run and cycle come from MEMORY when a cycle is in progress, not from
    # the state file. Re-reading state here meant an engine that destroyed it
    # mid-cycle made every remaining event of that cycle claim `"cycle":0` and
    # `"run":"-"` -- so the append-only record, the one thing meant to survive
    # exactly this, stopped naming the cycle it belonged to.
    local ev_cycle ev_run
    ev_cycle="${CY_N:-}"; is_int "${ev_cycle:-}" || ev_cycle="$(json_num cycle)"
    ev_run="${RUN_ID_MEM:-}"; [ -n "$ev_run" ] || ev_run="$(state_get run_id -)"
    printf '{"ts":"%s","run":"%s","cycle":%s,"kind":"%s","status":"%s","detail":"%s"%s}\n' \
        "$(now_iso)" "$ev_run" "$ev_cycle" \
        "$kind" "$status" "$(json_str "$detail")" "$extra" >> "$EVENTS_FILE"
    state_set updated_at "$(now_iso)"
}

ensure_dirs() {
    # Re-created on demand rather than once at startup. An agent given free rein
    # over the repository may delete .ralphie/ at any moment, and a loop that
    # cannot survive its own workspace being tidied away is not durable.
    mkdir -p "$HOME_DIR" "$LOG_DIR" "$RUN_DIR" 2>/dev/null || true
}

ensure_own_file() {
    # Every file Ralphie owns must be a readable, writable REGULAR file. The
    # same defect appeared independently on state, gates and ASK.md: each could
    # be replaced by a directory, and in every case Ralphie kept reporting
    # success while silently losing what it wrote.
    #
    # Three rules, learned one painful case at a time:
    #   1. DATA IS NEVER DESTROYED. Content is discarded only when the path was
    #      never a readable file, so there was nothing to lose. An earlier
    #      version replaced anything it could not write, and `chmod 444` plus a
    #      bare `ralphie status` emptied the operator's gates.
    #   2. THE OPERATOR'S PROTECTION IS NEVER STRIPPED. `chmod 444` on the gate
    #      file is the obvious response to "an agent is editing my verification
    #      surface". Quietly restoring write permission defeats the one defence
    #      they reached for. It is reported instead.
    #   3. IT ALWAYS RETURNS 0. Returning non-zero made a repair failure
    #      propagate under `set -e` and take down every command, including the
    #      read-only ones.
    local f="$1" what="$2"
    # Cleared on every check, not only set. As a one-way latch, a gate file
    # repaired mid-run still reported "the gate file could not be read" on every
    # later cycle -- the same "for ever" failure this function's own comment
    # claims to have fixed.
    [ "$f" = "$GATES_FILE" ] && GATES_FILE_BROKEN=0
    [ -e "$f" ] || return 0
    [ -f "$f" ] && [ -r "$f" ] && [ -w "$f" ] && return 0

    if [ -f "$f" ] && [ ! -r "$f" ]; then
        # Unreadable but a real file: recoverable, and the content is intact.
        chmod u+r "$f" 2>/dev/null || true
    fi
    if [ -f "$f" ] && [ -r "$f" ]; then
        if [ ! -w "$f" ]; then
            # Reported, never recorded. Writing an event here meant five
            # `ralphie status` calls appended five identical lines to the
            # append-only ledger -- a monitoring cron added ~1,440 a day and
            # eventually rotated real evidence out of existence.
            warn "the $what is read-only, so Ralphie cannot update it: $(basename "$f")"
            dim  "  its contents are untouched; chmod u+w it if that was not deliberate"
        fi
        return 0
    fi

    # A directory, a device, or a dangling symlink: there was never any content
    # to preserve, so replacing it loses nothing. It can still fail -- an
    # immutable flag, a foreign owner, a read-only mount -- and announcing a
    # repair that did not happen is how a project with a real, failing gate came
    # to report "gates: none" and commit the work as NOT VERIFIED.
    if rm -rf "$f" 2>/dev/null && : > "$f" 2>/dev/null; then
        warn "the $what was not a usable file and has been replaced"
        return 0
    fi
    err "the $what cannot be read or repaired: $f"
    dim "  ralphie will not guess what it should contain"
    # Recorded once per run, never per invocation. As an unconditional event,
    # one run plus five `status` calls wrote six identical lines -- the exact
    # flood the read-only rule twenty lines above exists to prevent.
    # Keyed on the COMMAND, not on owning the run: every owned file except the
    # gates is repaired in ledger_init, which runs before the lock is taken, so
    # an unusable state or questions file was never recorded at all.
    if [ "${CMD:-run}" = "run" ] && [ "${UNUSABLE_REPORTED:-}" != "$f" ]; then
        UNUSABLE_REPORTED="$f"
        event file unusable "the $what could not be read or repaired" "path=$f"
    fi
    # Scoped to the GATE file. As a global "some owned file is broken" it made a
    # damaged MEMORY.md report "the gate file could not be read" on every cycle
    # for ever: the real gate passed, the work was thrown away, and the engine
    # was paid again to fix a file that was not broken.
    [ "$f" = "$GATES_FILE" ] && GATES_FILE_BROKEN=1
    return 0
}

ensure_state_file() {
    # The state file must be a readable, writable REGULAR file. If it is a
    # directory, a dangling symlink, or unreadable, then every read silently
    # returns empty and every write is silently dropped: the loop keeps working
    # but loses its cycle numbers, its recovery point and its counters while
    # still reporting success. Measured: a run committed real work under
    # "cycle  " with "no commits yet" as its undo point. Repair, never run blind.
    ensure_own_file "$STATE_FILE" "state file"
}

rebuild_state_from_ledger() {
    # Only the counters that matter for not repeating work. Everything else is
    # genuinely derived and will be recomputed on the next cycle.
    # Every generation, not just the current one: after a rotation the rebuild
    # saw a fraction of the history and reported 4 green out of 28. And the
    # counters are distinguished, because an unverified cycle turning into a
    # green one is worse than losing the count entirely.
    local all="$RUN_DIR/ledger-all.$$" last_cycle pass fail unver blocked untrusted learned secs
    cat "$EVENTS_FILE" "$EVENTS_FILE".[0-9]* > "$all" 2>/dev/null || cp -f "$EVENTS_FILE" "$all" 2>/dev/null || return 0
    last_cycle="$(grep -o '"cycle":[0-9]*' "$all" 2>/dev/null | sed 's/.*://' | sort -n | tail -1)"
    is_int "$last_cycle" || last_cycle=0
    [ "$last_cycle" -gt 0 ] || { rm -f "$all"; return 0; }
    pass="$(count_of grep '"kind":"cycle","status":"pass"' "$all")"
    fail="$(count_of grep '"kind":"cycle","status":"fail"' "$all")"
    unver="$(count_of grep '"kind":"cycle","status":"unverified"' "$all")"
    blocked="$(count_of grep '"kind":"cycle","status":"blocked"' "$all")"
    untrusted="$(count_of grep '"kind":"cycle","status":"untrusted"' "$all")"
    learned="$(count_of grep '"kind":"learn","status":"ok"' "$all")"
    # Time really is in the ledger, one timing line per cycle, so it is restored
    # rather than reset: a rebuild that silently zeroed it made `status` report
    # a long-running project as though it had just started.
    # ONLY the per-cycle timing line. `engine ok` carries a `seconds` field of
    # its own, and summing every line that has one counted the engine's time a
    # second time inside the cycle that contained it.
    # `|| true` on the GREP, not on the pipeline. With `set -o pipefail` a grep
    # that matches nothing fails the whole pipeline, which under `set -e` took
    # down the calling command: a ledger with no timing line yet made `rm
    # .ralphie/state` brick every single command, for ever, with empty output.
    secs="$( { grep '"kind":"cycle","status":"timing"' "$all" 2>/dev/null || true; } \
            | sed -n 's/.*"seconds":"\([0-9][0-9]*\)".*/\1/p' \
            | awk '{t+=$1} END{print t+0}' 2>/dev/null)"
    is_int "$secs" || secs=0
    rm -f "$all" 2>/dev/null || true
    state_set cycle "$last_cycle"
    state_set pass_count "$pass"
    state_set fail_count "$fail"
    [ "$unver" -gt 0 ] && state_set unverified_count "$unver"
    [ "$blocked" -gt 0 ] && state_set blocked_count "$blocked"
    [ "$untrusted" -gt 0 ] && state_set untrusted_count "$untrusted"
    [ "$learned" -gt 0 ] && state_set learned_count "$learned"
    [ "$secs" -gt 0 ] && state_set total_seconds "$secs"
    # start_commit and the token counters describe THIS run and cannot be
    # recovered from history; they are left unset rather than guessed.
    warn "state was missing; rebuilt cycle=$last_cycle from the ledger"
    event state rebuilt "recovered cycle=$last_cycle pass=$pass fail=$fail blocked=$blocked from events.jsonl"
}

ledger_init() {
    # Safe for EVERY command, including read-only ones. It must not write run
    # state: `ralphie status` or `ralphie stop` typed in a second terminal used
    # to re-snapshot the running loop's own edits as "pre-existing" work, so the
    # loop then excluded its own verified changes from its commit. A read-only
    # command must be exactly that.
    ensure_dirs
    ensure_state_file
    ensure_gates_file
    ensure_ask_file
    ensure_own_file "$EVENTS_FILE" "ledger"
    ensure_own_file "$MEMORY_FILE" "memory file"
    ensure_own_file "$OBJECTIVE_FILE" "objective file"
    # The ledger is append-only and survives; state is derived and does not.
    # Deleting state used to restart the cycle counter at 1 and overwrite
    # cycle-1.log, losing the history the ledger still held.
    if [ ! -s "$STATE_FILE" ] && [ -s "$EVENTS_FILE" ]; then rebuild_state_from_ledger; fi
    # Fills in what is MISSING, and never overwrites what is there. Two traps
    # meet at this line. Keyed on `[ ! -f "$STATE_FILE" ]` it stopped running at
    # all, because any `event` on the way here ends with `state_set updated_at`
    # and creates the file. Keyed on `started_at` alone it ran too often, and
    # reset the counters the rebuild above had just recovered from the ledger.
    local k
    for k in "cycle 0" "pass_count 0" "fail_count 0" "status new"; do
        [ -n "$(state_get "${k%% *}" '')" ] || state_set "${k%% *}" "${k##* }"
    done
    [ -n "$(state_get started_at '')" ] || state_set started_at "$(now_iso)"
}

run_init() {
    # Only the run command owns run state, and only once it holds the lock.
    # Stale per-pid snapshots from earlier runs are cleared HERE, before this
    # run takes its own. Clearing them afterwards deleted the live snapshot and
    # silently disabled the exclusion that protects the operator's work.
    # Every per-pid scratch file, not only the two that were remembered: the
    # private index, the committed-path list and the commit-error capture all
    # accumulated in .ralphie/run/ for ever, one set per run.
    rm -f "$RUN_DIR"/pre-dirty.[0-9]*.nul "$RUN_DIR"/staged.[0-9]*.nul \
          "$RUN_DIR"/index.[0-9]* "$RUN_DIR"/committed.[0-9]*.nul \
          "$RUN_DIR"/commit-error.[0-9]* 2>/dev/null || true
    RUN_ID_MEM="$(stamp)-$(rand_token | cut -c1-6)"
    state_set run_id "$RUN_ID_MEM"
    state_set run_tokens 0
    state_set run_cost 0
    OWNS_RUN=1
}
OWNS_RUN=0

ensure_ignored() {
    # .git/info/exclude, never the operator's tracked .gitignore. Editing a
    # tracked file means Ralphie's own housekeeping shows up in the operator's
    # diff and lands inside the first autonomous commit -- a change to their
    # repository that they never asked for, in a file other people review.
    # info/exclude is local, untracked, and achieves exactly the same thing.
    local entry=".ralphie/" ex
    git_ready || return 0
    # Test a path INSIDE the directory: a `dir/` pattern does not match the
    # bare directory name, so checking $HOME_DIR itself always reports "not
    # ignored" and an existing operator rule would be duplicated.
    git -C "$PROJECT" check-ignore -q "$HOME_DIR/state" 2>/dev/null && return 0
    ex="$(git -C "$PROJECT" rev-parse --git-dir 2>/dev/null)/info/exclude" || return 0
    case "$ex" in /*) ;; *) ex="$PROJECT/$ex";; esac
    mkdir -p "${ex%/*}" 2>/dev/null || return 0
    grep -qxF "$entry" "$ex" 2>/dev/null && return 0
    printf '\n# Ralphie runtime state (local only; not part of the repository)\n%s\n' "$entry" >> "$ex" 2>/dev/null || true
    dbg "excluded $entry via $ex"
}

prune_artifacts() {
    # A loop meant to run for weeks must not fill the disk. Only Ralphie's own
    # runtime directory is ever touched, and only entries older than the keep
    # window. Cycle artifacts are pruned BY NUMBER rather than by mtime, so the
    # arithmetic is exact and no filename ever has to be parsed.
    local keep="${RALPHIE_KEEP_CYCLES:-50}" n cut i
    n="$(json_num cycle)"; is_int "$n" || return 0
    is_int "$keep" || keep=50
    cut=$(( n - keep ))
    # Walk DOWN from the cycle that just fell out of the window and stop at the
    # first one with nothing left: everything older was pruned on an earlier
    # pass. In steady state that is one cycle per cycle, instead of re-sweeping
    # a fixed twenty for ever to delete files that were already gone -- and it
    # still catches up completely if the window is lowered or state is rebuilt.
    i="$cut"
    while [ "$i" -ge 1 ]; do
        if [ -e "$LOG_DIR/cycle-$i.log" ] || [ -e "$RUN_DIR/cycle-$i.answer" ] || [ -e "$RUN_DIR/cycle-$i.prompt.md" ]; then
            rm -f "$LOG_DIR/cycle-$i.log" "$RUN_DIR/cycle-$i.answer" "$RUN_DIR/cycle-$i.prompt.md" 2>/dev/null || true
            rm -f "$RUN_DIR/gates-$i".* "$RUN_DIR/gates-$i-after".* 2>/dev/null || true
            i=$(( i - 1 ))
        else
            break
        fi
    done
    rotate_ledger
}

rotate_ledger() {
    # Checked on EVERY cycle, not only once the cycle count exceeds the keep
    # window: it used to sit behind an early return, so a project that never
    # reached fifty cycles could grow its ledger without bound.
    local sz; sz="$(file_bytes "$EVENTS_FILE")"
    [ "$sz" -gt "${RALPHIE_LEDGER_MAX:-16777216}" ] || return 0
    # Generations are shifted, never overwritten. The second rotation used to
    # destroy the first one -- in the one file that exists to never lose data.
    # Declared separately. `local keep=X i="$keep"` reads `keep` while the
    # declaration is still being evaluated: under `set -u` that is an unbound
    # variable, and worse, when this function was called from prune_artifacts
    # it silently picked up THAT function's `keep` -- the cycle-retention
    # window -- and kept three generations instead of five. Two cycles of the
    # append-only ledger were destroyed before anyone looked.
    local keep i
    keep="${RALPHIE_LEDGER_GENERATIONS:-5}"
    i="$keep"
    while [ "$i" -gt 1 ]; do
        [ -f "$EVENTS_FILE.$(( i - 1 ))" ] && mv -f "$EVENTS_FILE.$(( i - 1 ))" "$EVENTS_FILE.$i" 2>/dev/null
        i=$(( i - 1 ))
    done
    mv -f "$EVENTS_FILE" "$EVENTS_FILE.1" 2>/dev/null || return 0
    event ledger rotated "previous ledger kept as events.jsonl.1 (up to $keep generations)"
    return 0
}

prune_sessions() {
    # Engine session directories accumulate one per run, and each can be large.
    local keep="${RALPHIE_KEEP_RUNS:-5}" dir="$RUN_DIR/sessions" total drop d
    [ -d "$dir" ] || return 0
    is_int "$keep" || keep=5
    total="$(count_of ls -1 "$dir")"
    drop=$(( total - keep ))
    [ "$drop" -gt 0 ] || return 0
    # `head -n -N` is GNU-only, so the count is computed instead.
    ls -1 "$dir" 2>/dev/null | sort | head -n "$drop" | while IFS= read -r d; do
        [ -n "$d" ] && rm -rf "$dir/$d" 2>/dev/null || true
    done
}

mark_tree() { mkdir -p "$RUN_DIR" 2>/dev/null || true; : > "$RUN_DIR/tree.mark" 2>/dev/null || true; }

tree_listing_digest() {
    # A digest of WHICH files exist. `find -newer` reports modifications but is
    # blind to a deletion: removing a file the gates depend on left both the
    # marker and the fingerprint unchanged, so a red tree was reported green,
    # a fabricated gate-pass was written into the append-only ledger, and the
    # run exited 0 having run no gates at all.
    local d
    ( cd "$PROJECT" 2>/dev/null || exit 0
      set --
      for d in $NOISE_DIRS; do set -- "$@" -o -name "$d"; done
      shift
      find . \( "$@" \) -prune -o -type f -print 2>/dev/null ) | LC_ALL=C sort | sha_of
}

mark_verify() {
    mkdir -p "$RUN_DIR" 2>/dev/null || true
    : > "$RUN_DIR/verify.mark" 2>/dev/null || true
    LAST_VERIFY_LISTING="$(tree_listing_digest)"
}

verify_mark_stale() {
    # Stale if anything was WRITTEN since the verdict (the marker) or if the set
    # of files has CHANGED at all (the digest). Either alone is not enough.
    local m="$RUN_DIR/verify.mark"
    [ -f "$m" ] || return 0
    [ -n "$(find_changed_since "$m" | head -1)" ] && return 0
    [ "$(tree_listing_digest)" != "${LAST_VERIFY_LISTING:-}" ]
}

# Kept as a function rather than a string: the string form was passed through
# `eval`, where the unquoted parentheses were a syntax error, so tree_touched
# silently never worked and a project with no git repository could never make
# progress -- every cycle reported "changed nothing" while real work piled up.
# The single definition of "not real work": directories whose contents are
# generated, cached or vendored. It is used BOTH to decide whether the tree
# changed and to decide what may be committed. Keeping two lists meant they
# drifted: `.pytest_cache` was missing from one, so on every Python project the
# test cache being rewritten looked like progress, the no-change streak never
# advanced, and a lazy engine could run for ever. Change this in one place.
NOISE_DIRS='.git .ralphie node_modules .venv venv target dist build __pycache__ .next vendor .pytest_cache .mypy_cache .ruff_cache .tox coverage .nyc_output .terraform .gradle .idea .vscode'

find_changed_since() {
    # The marker is captured BEFORE `set --`, which would otherwise destroy it.
    local m="$1" d
    set --
    for d in $NOISE_DIRS; do set -- "$@" -o -name "$d"; done
    shift   # drop the leading -o
    ( cd "$PROJECT" 2>/dev/null || exit 0
      find . \( "$@" \) -prune -o -type f -newer "$m" -print 2>/dev/null )
}

tree_touched() {
    # The answer to "did anything actually change?" when there is no repository.
    # `find -newer` is one process, exact to the filesystem's own timestamp
    # resolution, and portable. Hashing the tree would cost a full walk every
    # cycle, and `ls -l` timestamps are only accurate to the minute, so a change
    # made within the same minute would be invisible.
    local m="$RUN_DIR/tree.mark"
    [ -f "$m" ] || return 0
    [ -n "$(find_changed_since "$m" | head -1)" ]
}

work_changed() {
    # $1 is the fingerprint captured before the engine ran. Both signals are
    # consulted: the fingerprint catches content and history, the mtime marker
    # catches an untracked file being rewritten in place. A false "changed" only
    # costs one cycle; a false "unchanged" throws away verified work.
    [ "$(fingerprint)" != "$1" ] && return 0
    tree_touched
}

# The fingerprint answers one question: has anything actually changed?
# It is the anti-waste primitive. Identical fingerprint plus green gates means
# there is nothing to do, and Ralphie must not spend a single token proving it.
fingerprint() {
    { git -C "$PROJECT" rev-parse HEAD 2>/dev/null || printf 'nogit'
      git -C "$PROJECT" status --porcelain 2>/dev/null || true
      # Content, not just the status letter. `git status` prints " M calc.py"
      # whatever the file now contains, so the moment a red gate keeps the tree
      # dirty -- the exact situation this loop exists for -- every later edit
      # becomes invisible, real work is discarded as "changed nothing", and a
      # productive run is declared stalled. Measured.
      git -C "$PROJECT" diff HEAD 2>/dev/null || true
      cat "$GATES_FILE" 2>/dev/null || true
      cat "$OBJECTIVE_FILE" 2>/dev/null || true
    } | sha_of
}

# --- locking ----------------------------------------------------------------
# One loop per project. A stale lock from a killed run must never wedge a
# colony forever, so ownership is proven by a live pid, not by file existence.

lock_acquire() {
    mkdir -p "$HOME_DIR" 2>/dev/null || true
    if [ ! -w "$HOME_DIR" ]; then
        # Blaming a stale lock here sent operators hunting for a process that
        # never existed. The real problem is that Ralphie cannot write.
        err "cannot write to $HOME_DIR - ralphie needs it to record what it does"
        return 1
    fi
    local owner stale_pid
    if mkdir "$LOCK_FILE" 2>/dev/null; then
        printf '%s\n' "$$" > "$LOCK_FILE/pid"
        printf '%s\n' "$(rand_token)" > "$LOCK_FILE/token"
        printf '%s\n' "$(now_iso)" > "$LOCK_FILE/since"
        LOCK_HELD=1
        return 0
    fi
    stale_pid="$(cat "$LOCK_FILE/pid" 2>/dev/null || printf '')"
    # A lock directory with no pid yet belongs to a process that is mid-acquire.
    if [ -z "$stale_pid" ] && [ -d "$LOCK_FILE" ]; then
        sleep 1
        stale_pid="$(cat "$LOCK_FILE/pid" 2>/dev/null || printf '')"
        [ -n "$stale_pid" ] && { err "another ralphie is starting here (pid $stale_pid)"; return 1; }
    fi
    # `kill -0` fails with EPERM for a process owned by someone else, which
    # looks identical to "it is gone". Stealing a lock from a live run started
    # by another user would put two loops in one worktree.
    if [ -n "$stale_pid" ] && { kill -0 "$stale_pid" 2>/dev/null || ps -p "$stale_pid" >/dev/null 2>&1; }; then
        owner="$(cat "$LOCK_FILE/since" 2>/dev/null || printf 'unknown')"
        err "another ralphie loop is running here (pid $stale_pid, since $owner)"
        err "stop it with:  $ME stop"
        return 1
    fi
    # An empty or unreadable pid file means the previous owner died between
    # mkdir and the write. Treat it as stale, but prove ownership afterwards:
    # two processes can clear one stale lock and both succeed at mkdir, and
    # four of them once "acquired" the same lock at the same time.
    warn "clearing stale lock from pid ${stale_pid:-unknown}"
    local token; token="$(rand_token)"
    rm -rf "$LOCK_FILE" 2>/dev/null || true
    mkdir "$LOCK_FILE" 2>/dev/null || { err "cannot acquire lock"; return 1; }
    printf '%s\n' "$$" > "$LOCK_FILE/pid"
    printf '%s\n' "$token" > "$LOCK_FILE/token"
    printf '%s\n' "$(now_iso)" > "$LOCK_FILE/since"
    # Settle, then confirm the token that survived is ours. Whoever loses backs
    # off rather than running a second loop in the same worktree.
    sleep 1
    if [ "$(cat "$LOCK_FILE/token" 2>/dev/null || printf '')" != "$token" ]; then
        err "lost a race for the lock with another ralphie; not starting"
        return 1
    fi
    LOCK_HELD=1
}

LOCK_HELD=0
lock_release() { [ "$LOCK_HELD" = "1" ] && rm -rf "$LOCK_FILE" 2>/dev/null; LOCK_HELD=0; return 0; }

# --- process hygiene --------------------------------------------------------
# An agent spawns compilers, test runners and servers. If Ralphie dies without
# reaping the tree, the host keeps paying for orphans forever.

CHILD_PIDS=""
track_pid()   { CHILD_PIDS="$CHILD_PIDS $1"; }
untrack_pid() { CHILD_PIDS="$(printf '%s' "$CHILD_PIDS" | tr ' ' '\n' | grep -vx "$1" | tr '\n' ' ')"; }

child_pids_of() {
    # `pgrep` is absent on Termux, on Alpine without procps, and in many minimal
    # container images. Without a fallback, kill_tree reaps only the direct child
    # and silently orphans everything the agent started -- compilers, test
    # runners, dev servers -- which then bill the host forever with no trace.
    if have pgrep; then
        pgrep -P "$1" 2>/dev/null || true
    else
        ps -A -o pid= -o ppid= 2>/dev/null | awk -v p="$1" '$2==p {print $1}' || true
    fi
}

kill_tree() {
    local pid="$1" sig="${2:-TERM}" kid
    [ -n "$pid" ] || return 0
    for kid in $(child_pids_of "$pid"); do kill_tree "$kid" "$sig"; done
    kill "-$sig" "$pid" 2>/dev/null || true
}

terminate_tree() {
    # Snapshot descendants BEFORE TERM: a cooperative parent can exit and
    # orphan a TERM-ignoring child before the forced-kill pass finds it.
    # Launchers use a private process group too, where job control is allowed.
    local pid="$1" pending="$1" all="" p
    while [ -n "$pending" ]; do
        p="${pending%% *}"
        if [ "$pending" = "$p" ]; then pending=""; else pending="${pending#* }"; fi
        all="$all $p"
        for p in $(child_pids_of "$p"); do pending="${pending:+$pending }$p"; done
    done
    kill -TERM "-$pid" 2>/dev/null || true
    for p in $all; do kill -TERM "$p" 2>/dev/null || true; done
    sleep 2
    kill -KILL "-$pid" 2>/dev/null || true
    for p in $all; do kill -KILL "$p" 2>/dev/null || true; done
}

reap_children() {
    local pid live=0
    for pid in $CHILD_PIDS; do
        kill -0 "$pid" 2>/dev/null || continue
        kill_tree "$pid" TERM
        live=1
    done
    # Only pay the settling second when something was actually killed; every
    # `ralphie status` used to sleep for no reason.
    [ "$live" = "1" ] || { CHILD_PIDS=""; return 0; }
    sleep 1
    for pid in $CHILD_PIDS; do
        kill -0 "$pid" 2>/dev/null || continue
        kill_tree "$pid" KILL
    done
    CHILD_PIDS=""
}

INTERRUPTED=0
SIGPIPE_SEEN=0
on_exit() {
    local code=$?
    [ "$SIGPIPE_SEEN" = "1" ] && code=141
    # Best effort, and only that. An EXIT trap cannot run after SIGKILL, an OOM
    # or a power loss, so a cycle lost that way leaves work the next run cannot
    # distinguish from the operator's own edits -- it is treated as theirs and
    # excluded from commits, which is the safe direction to be wrong in. There
    # is no sound way to infer it afterwards: an earlier attempt guessed, and
    # started committing the operator's files.
    [ "$OWNS_RUN" = "1" ] && record_owned_paths 2>/dev/null || true
    reap_children
    lock_release
    # Only the process that owns the run may write run status. Without this, a
    # failed `ralphie update` in a second terminal rewrote a healthy running
    # loop's status to "error".
    if [ "$OWNS_RUN" = "1" ] && [ "$code" -ne 0 ] && [ "$INTERRUPTED" = "0" ]; then
        case "$(state_get status running)" in
            running|new) state_set status "error"; event exit error "exit code $code" "code=$code";;
            *)           event exit "$(state_get status)" "exit code $code" "code=$code";;
        esac
    fi
    [ "$SIGPIPE_SEEN" = "1" ] && exit 141
    return 0
}

on_int() {
    INTERRUPTED=1
    say ""
    warn "interrupted - finishing safely"
    if [ "$OWNS_RUN" = "1" ]; then
        # Whatever the engine wrote before the signal is Ralphie's work. Without
        # this the next run snapshots it as the operator's pre-existing change
        # and excludes it from every future commit, permanently.
        record_owned_paths 2>/dev/null || true
        state_set status "stopped"
        event exit interrupted "operator interrupt"
    fi
    reap_children
    lock_release
    exit 130
}
on_pipe() {
    # Retire broken stdout BEFORE EXIT forks any command substitutions. Bash
    # 3.2 otherwise flushes pending terminal bytes into state and ledger JSON.
    # Do not exit inside this trap: bash 3.2 retains the poisoned buffer through
    # EXIT if we do. Let the interrupted write return, then report 141 on exit.
    exec 1>/dev/null
    SIGPIPE_SEEN=1
}
install_traps() {
    trap on_exit EXIT
    trap on_int INT TERM HUP
    trap on_pipe PIPE
}

# ============================================================================
# LAYER 3 - PROJECT
#   Deterministic ground truth about the host project: what it is built from,
#   and how it proves itself correct.
#
#   Gates are the centre of gravity of this whole program. A gate is any shell
#   command that returns 0 when the project is healthy. Tests, types, linters,
#   builds, migrations, smoke checks, deploy dry-runs, a physics simulation --
#   Ralphie does not care what it is, only whether it passes. That is why the
#   loop generalises past software into anything a machine can verify.
# ============================================================================

pkg_manager() {
    if   [ -f "$PROJECT/bun.lockb" ]      || [ -f "$PROJECT/bun.lock" ]; then printf 'bun'
    elif [ -f "$PROJECT/pnpm-lock.yaml" ]; then printf 'pnpm'
    elif [ -f "$PROJECT/yarn.lock" ];      then printf 'yarn'
    else printf 'npm'
    fi
}

has_npm_script() {
    # No jq dependency. Try the tools a JS project almost certainly has, then
    # fall back to a loose grep that is good enough to propose a candidate gate
    # (a wrong candidate fails its own trial run below and is discarded).
    local name="$1" pj="$PROJECT/package.json"
    [ -f "$pj" ] || return 1
    if have node; then
        node -e 'const s=(require(process.argv[1]).scripts)||{};process.exit(s[process.argv[2]]?0:1)' "$pj" "$name" 2>/dev/null && return 0 || return 1
    elif have python3; then
        python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));sys.exit(0 if (d.get("scripts") or {}).get(sys.argv[2]) else 1)' "$pj" "$name" 2>/dev/null && return 0 || return 1
    else
        grep -qE "\"$name\"[[:space:]]*:" "$pj" 2>/dev/null
    fi
}

has_make_target() {
    [ -f "$PROJECT/Makefile" ] || [ -f "$PROJECT/makefile" ] || return 1
    grep -qE "^$1[[:space:]]*:" "$PROJECT/Makefile" "$PROJECT/makefile" 2>/dev/null
}

py_runner() {
    # Prefer the project's own interpreter. Running a project's tools from the
    # wrong environment is the single most common false failure in automation.
    if   [ -x "$PROJECT/.venv/bin/$1" ]; then printf '.venv/bin/%s' "$1"
    elif [ -x "$PROJECT/venv/bin/$1" ];  then printf 'venv/bin/%s' "$1"
    elif [ -f "$PROJECT/uv.lock" ] && have uv; then printf 'uv run %s' "$1"
    elif have "$1"; then printf '%s' "$1"
    else printf ''
    fi
}

detect_stack() {
    # Space separated tags. Order is not significant; presence is.
    local tags=""
    [ -f "$PROJECT/package.json" ]     && tags="$tags node"
    [ -f "$PROJECT/tsconfig.json" ]    && tags="$tags typescript"
    { [ -f "$PROJECT/pyproject.toml" ] || [ -f "$PROJECT/setup.py" ] || [ -f "$PROJECT/requirements.txt" ]; } && tags="$tags python"
    [ -f "$PROJECT/Cargo.toml" ]       && tags="$tags rust"
    [ -f "$PROJECT/go.mod" ]           && tags="$tags go"
    [ -f "$PROJECT/pom.xml" ]          && tags="$tags maven"
    { [ -f "$PROJECT/build.gradle" ] || [ -f "$PROJECT/build.gradle.kts" ]; } && tags="$tags gradle"
    [ -f "$PROJECT/Gemfile" ]          && tags="$tags ruby"
    [ -f "$PROJECT/composer.json" ]    && tags="$tags php"
    [ -f "$PROJECT/mix.exs" ]          && tags="$tags elixir"
    [ -f "$PROJECT/deno.json" ]        && tags="$tags deno"
    [ -f "$PROJECT/CMakeLists.txt" ]   && tags="$tags cmake"
    [ -f "$PROJECT/Dockerfile" ]       && tags="$tags docker"
    { [ -d "$PROJECT/.terraform" ] || ls "$PROJECT"/*.tf >/dev/null 2>&1; } && tags="$tags terraform"
    { [ -f "$PROJECT/Makefile" ] || [ -f "$PROJECT/makefile" ]; } && tags="$tags make"
    ls "$PROJECT"/*.sh >/dev/null 2>&1  && tags="$tags shell"
    [ -d "$PROJECT/.git" ]             && tags="$tags git"
    trim "$tags"
}

# Preview only: the normal candidate parser may invoke node/python. Keep its
# shell-text substitute scoped to this subshell, never the verification path.
discover_candidates() (
    has_npm_script() {
        [ -f "$PROJECT/package.json" ] && [ -r "$PROJECT/package.json" ] || return 1
        grep -qE "\"$1\"[[:space:]]*:" "$PROJECT/package.json" 2>/dev/null
    }
    has_make_target() {
        local f
        for f in "$PROJECT/Makefile" "$PROJECT/makefile"; do
            [ -f "$f" ] && [ -r "$f" ] || continue
            grep -qE "^$1[[:space:]]*:" "$f" 2>/dev/null && return 0
        done
        return 1
    }
    gate_candidates || true
)

# Git's apparently read-only status can refresh the index, launch fsmonitor,
# run clean/process filters, or inspect submodules. Disable all of those here.
# These overrides are command-local; never change the operator's git config.
discover_git() {
    local key
    local opts=( -c core.fsmonitor=false -c core.untrackedCache=false )
    while IFS= read -r key; do
        [ -n "$key" ] && opts+=( -c "$key=" )
    done < <(git -C "$PROJECT" config --name-only --get-regexp '^filter\..*\.(clean|process)$' 2>/dev/null || true)
    GIT_OPTIONAL_LOCKS=0 GIT_NO_LAZY_FETCH=1 git -C "$PROJECT" "${opts[@]+"${opts[@]}"}" "$@"
}

cmd_discover() (
    # No ledger, repair, trap installation, engine probes or gate trials. A
    # subshell also keeps relative custom command lookup anchored to PROJECT.
    [ "${#REST[@]}" -eq 0 ] || die "discover takes no arguments"
    cd "$PROJECT" 2>/dev/null || die "cannot read project: $PROJECT"
    local PROJECT GATES_FILE
    PROJECT="$(pwd -P)"; GATES_FILE="$PROJECT/.ralphie/gates"
    local branch dirty stack f n candidates found=0
    say "Project: $PROJECT"
    if [ "$(discover_git rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; then
        say "Git: repository"
        branch="$(discover_git symbolic-ref --quiet --short HEAD 2>/dev/null)" || branch="detached"
        say "Branch: $branch"
        if discover_git rev-parse --verify --quiet HEAD >/dev/null 2>&1; then say "Unborn: no"
        else say "Unborn: yes (no commits yet)"; fi
        if dirty="$(discover_git status --porcelain --untracked-files=normal --ignore-submodules=all 2>/dev/null)"; then
            if [ -n "$dirty" ]; then say "Dirty: yes"; else say "Dirty: no"; fi
        else say "Dirty: unknown (git status failed)"; fi
        say "  Submodule changes are not inspected; content filters are disabled."
    else
        say "Git: no work tree (not initialized)"
        say "Branch: unavailable; Unborn: unavailable; Dirty: unavailable"
    fi
    stack="$(detect_stack)"; say "Stack: ${stack:-unknown (no recognized root manifests)}"
    say "Standing instructions:"
    for f in AGENTS.md CLAUDE.md GEMINI.md; do
        [ -f "$PROJECT/$f" ] || continue
        say "  $f"; found=1
    done
    [ "$found" = 1 ] || say "  none found"
    found=0; say "Known plans (unchecked boxes are not proof of completion):"
    for f in IMPLEMENTATION_PLAN.md PLAN.md TODO.md TASKS.md ROADMAP.md docs/TODO.md; do
        [ -f "$PROJECT/$f" ] || continue
        if [ -r "$PROJECT/$f" ]; then
            n="$(count_of grep -E '^[[:space:]]*[-*][[:space:]]*\[[[:space:]]\]' "$PROJECT/$f")"
            say "  $f: $n pending task(s)"
        else say "  $f: unreadable"; fi
        found=1
    done
    [ "$found" = 1 ] || say "  none found"
    if [ -f "$PROJECT/.ralphie/OBJECTIVE.md" ]; then
        say "Stored objective: .ralphie/OBJECTIVE.md (not evaluated)"
    else say "Stored objective: none"; fi
    say "Configured gates — NOT RUN:"
    if [ -f "$GATES_FILE" ] && [ -r "$GATES_FILE" ]; then
        if [ -s "$GATES_FILE" ]; then sed 's/^/  /' "$GATES_FILE"; else say "  empty gate file"; fi
    elif [ -e "$GATES_FILE" ]; then say "  unavailable (not a readable regular file)"
    else say "  none configured"; fi
    say "Candidate checks — NOT RUN (heuristic root-file scan, not validated):"
    candidates="$(discover_candidates)"
    if [ -n "$candidates" ]; then printf '%s\n' "$candidates" | sed 's/^/  /'; else say "  none found"; fi
    say "Engine command presence only — NOT RUN (authentication and health unknown):"
    while IFS= read -r n; do
        if engine_present "$n"; then say "  $n: present"; else say "  $n: absent"; fi
    done < <(engine_names)
    say "No checks or engines ran. Requirements and project health cannot be inferred."
    say "Next: review your plans and gates; start a separate run with an explicit objective."
)

gate_candidates() {
    # Emit candidate gate commands, cheapest and most decisive first. A failing
    # type check costs seconds and rules out a whole class of error, so it is
    # ordered ahead of a slow end-to-end suite.
    local pm; pm="$(pkg_manager)"
    local run="$pm run"; [ "$pm" = "npm" ] && run="npm run"

    if [ -f "$PROJECT/package.json" ]; then
        has_npm_script typecheck  && printf '%s typecheck\n' "$run"
        has_npm_script "type-check" && printf '%s type-check\n' "$run"
        has_npm_script lint       && printf '%s lint\n' "$run"
        has_npm_script check      && printf '%s check\n' "$run"
        has_npm_script build      && printf '%s build\n' "$run"
        has_npm_script test       && printf '%s test\n' "$run"
    fi

    if [ -f "$PROJECT/pyproject.toml" ] || [ -f "$PROJECT/setup.py" ] || [ -f "$PROJECT/requirements.txt" ] || [ -f "$PROJECT/tox.ini" ] || [ -f "$PROJECT/pytest.ini" ]; then
        local r
        r="$(py_runner ruff)";   [ -n "$r" ] && printf '%s check .\n' "$r"
        r="$(py_runner mypy)";   [ -n "$r" ] && [ -d "$PROJECT/src" ] && printf '%s src\n' "$r"
        r="$(py_runner pytest)"; [ -n "$r" ] && printf '%s -q\n' "$r"
    fi

    [ -f "$PROJECT/Cargo.toml" ] && { printf 'cargo check\n'; printf 'cargo clippy -- -D warnings\n'; printf 'cargo test\n'; }
    [ -f "$PROJECT/go.mod" ]     && { printf 'go vet ./...\n'; printf 'go build ./...\n'; printf 'go test ./...\n'; }
    [ -f "$PROJECT/deno.json" ]  && { printf 'deno check .\n'; printf 'deno test -A\n'; }
    [ -f "$PROJECT/mix.exs" ]    && printf 'mix test\n'
    [ -f "$PROJECT/Gemfile" ]    && printf 'bundle exec rspec\n'
    [ -f "$PROJECT/pom.xml" ]    && printf 'mvn -q -B test\n'
    { [ -f "$PROJECT/build.gradle" ] || [ -f "$PROJECT/build.gradle.kts" ]; } && printf './gradlew test\n'
    [ -f "$PROJECT/composer.json" ] && printf 'composer test\n'
    ls "$PROJECT"/*.tf >/dev/null 2>&1 && printf 'terraform validate\n'

    has_make_target check && printf 'make check\n'
    has_make_target lint  && printf 'make lint\n'
    has_make_target test  && printf 'make test\n'

    # A repository of shell scripts still deserves a gate.
    # Only when there is a shell script that is not Ralphie itself. The
    # documented install drops ralphie.sh into the project root, so a naive
    # `*.sh` rule produced a loop whose body never ran: "gates: 1 active",
    # always green, and a commit claiming "Verified by 1 gate(s)" on a project
    # nothing had checked. Ralphie is identified by content, not by filename,
    # because a renamed copy is the same file.
    local other_sh=0 f
    for f in "$PROJECT"/*.sh; do
        [ -f "$f" ] || continue
        head -40 "$f" 2>/dev/null | grep -q 'ralphie-kernel' && continue
        other_sh=1; break
    done
    if [ "$other_sh" = "1" ] && ! [ -f "$PROJECT/package.json" ] && ! [ -f "$PROJECT/pyproject.toml" ]; then
        # The gate GLOBS at run time; it never interpolates a filename into a
        # command string. Interpolating was a command-injection hole: a file
        # named  $(touch PWNED)lib.sh  executed on discovery, passed its trial
        # because the substitution expanded to nothing, was written into the
        # gates file, and then ran again on every cycle forever. Filenames come
        # from cloned repositories and from the engine, so they are untrusted.
        printf '%s\n' 'n=0; for f in ./*.sh; do [ -f "$f" ] || continue; head -40 "$f" | grep -q ralphie-kernel && continue; n=$((n+1)); bash -n "$f" || exit 1; done; [ "$n" -gt 0 ]'
        [ -x "$PROJECT/test.sh" ] && printf './test.sh\n'
    fi
}

# A gate containing a pipe must not report the status of the last command in
# that pipe. `pytest -q | tail` exits 0 while the tests fail, which would let a
# red project be committed as green -- precisely the failure this whole program
# exists to prevent. pipefail makes a pipeline report the real result. POSIX sh
# does not guarantee it, so bash is used whenever it is present.
# The prelude also makes the gate's own shell reap its own background jobs on
# exit. A gate that starts a server or a watcher would otherwise leave it
# running for ever, holding the port the next cycle needs. Killing by process
# group is not enough on its own: `setpgid` is "Operation not permitted" in a
# nested shell with no controlling terminal, so no group is ever created there.
# The gate shell always knows its own children, in every environment.
GATE_REAP='trap '"'"'for __j in $(jobs -p 2>/dev/null); do kill "$__j" 2>/dev/null; done'"'"' EXIT
'
# RALPHIE IS BASH, so the interpreter running this line is always available --
# by absolute path, whatever PATH happens to contain. Looking bash up on PATH
# instead meant a machine without it silently ran gates under `sh` with NO
# pipefail, and a gate like `./run-tests.sh 2>&1 | tail -5` reported the exit
# status of `tail`. Measured: the identical project committed as
# "Verified by 1 gate(s)" while its own test run exited 1. Verification that
# quietly stops verifying is the worst failure this program has.
if [ -n "${BASH:-}" ] && [ -x "${BASH:-}" ]; then
    GATE_SH="$BASH"
    GATE_PRELUDE="set -o pipefail
$GATE_REAP"
elif have bash; then
    GATE_SH="bash"
    GATE_PRELUDE="set -o pipefail
$GATE_REAP"
else
    # Unreachable while this file is run by bash, and kept honest anyway: if it
    # ever happens, the operator is told that a pipeline's real result may be
    # hidden, rather than finding out from a green gate on a broken project.
    GATE_SH="sh"; GATE_PRELUDE="$GATE_REAP"
    GATE_NO_PIPEFAIL=1
fi

gate_tool_names() {
    # The names whose absence means the TOOL is missing rather than the project
    # being broken: the executable itself, and the module of `python -m NAME`.
    local first second third
    # shellcheck disable=SC2086
    set -- $1
    first="${1:-}"; second="${2:-}"; third="${3:-}"
    [ -n "$first" ] && printf '%s\n' "${first##*/}"
    case "$second" in -m) [ -n "$third" ] && printf '%s\n' "$third";; esac
    return 0
}

GATE_EXEC_RC=0
gate_exec() {
    # gate_exec <command> <output-file> <timeout-seconds>
    # All hosts use the same watchdog, including stock macOS without timeout.
    local cmd="$1" out="$2" secs="${3:-0}" gp
    set -m 2>/dev/null || true
    { ( cd "$PROJECT" && exec "$GATE_SH" -c "$GATE_PRELUDE$cmd" ) >"$out" 2>&1 </dev/null & } 2>/dev/null
    gp=$!
    set +m 2>/dev/null || true
    track_pid "$gp"
    watchdog_wait "$gp" "$out" 0 "$secs" gate; GATE_EXEC_RC=$?
    untrack_pid "$gp"
    # Only pay the settling second when something actually survived.
    if kill -0 "-$gp" 2>/dev/null || [ -n "$(child_pids_of "$gp")" ]; then
        kill -TERM "-$gp" 2>/dev/null || true
        kill_tree "$gp" TERM 2>/dev/null || true
        sleep 1
        kill -KILL "-$gp" 2>/dev/null || true
    fi
    return "$GATE_EXEC_RC"
}

gate_trial() {
    # A candidate only becomes a gate if it can actually run here. This is what
    # stops Ralphie from inventing a gate that fails for environmental reasons
    # and then burning the entire budget "fixing" a problem that never existed.
    local cmd="$1" t; t="$(timeout_cmd)"
    local out="$RUN_DIR/trial.$$"
    mkdir -p "$RUN_DIR"
    # Same single path as a real gate run, so a candidate is trialled exactly
    # the way it will later be executed -- detached from the terminal, bounded,
    # and reaped. A candidate that reads stdin (`jest --watch`, a prompting
    # Makefile, maven asking for credentials) would otherwise wait for a human
    # for ever, breaking the one invariant that says this never blocks.
    gate_exec "$cmd" "$out" "${GATE_TRIAL_TIMEOUT:-120}"
    local rc=$?
    # 127 = command not found, 126 = not executable. Those are environment
    # facts, not project facts, and must never be presented as a broken build.
    case "$rc" in 126|127) rm -f "$out"; return 2;; esac
    # An exit of 1 can mean "this command cannot run here" OR "this project is
    # broken", and the two look almost identical. `python3 -m pytest` says
    # "No module named pytest" when the TOOL is absent; a project whose test
    # imports a module that does not exist yet says "No module named app" when
    # the PROJECT is broken. Rejecting both left zero gates on the single most
    # common starting state there is -- a failing test to make pass.
    #
    # So an absence message only disqualifies a candidate when it names the
    # tool being invoked. Anything else is the project's problem, which is
    # precisely what a gate is for.
    local absent name
    absent="$(grep -iE 'command not found|no module named|is not recognized|executable file not found|cannot find module|unknown command' "$out" 2>/dev/null || true)"
    if [ -n "$absent" ]; then
        for name in $(gate_tool_names "$cmd"); do
            if printf '%s\n' "$absent" | grep -qiF -- "$name"; then rm -f "$out"; return 2; fi
        done
    fi
    rm -f "$out"
    return 0
}

discover_gates() {
    # Runs once. The written file is then the operator's editable truth and is
    # never silently overwritten; `ralphie gates --redetect` is explicit.
    local force="${1:-0}"
    ensure_gates_file
    if [ -f "$GATES_FILE" ] && [ "$force" != "1" ]; then return 0; fi
    # A DANGLING symlink is not "no gate file": `-e` is false for it, so nothing
    # above repaired it, and the write below would have followed it and created
    # the target -- anywhere on the filesystem the operator can reach.
    if [ -L "$GATES_FILE" ] && [ ! -e "$GATES_FILE" ]; then
        warn "the gate file is a broken symlink - removing it rather than writing through it"
        rm -f "$GATES_FILE" 2>/dev/null || true
    fi

    info "discovering how this project proves itself correct..."
    local tmp="$GATES_FILE.tmp.$$" cmd kept=0 skipped=0
    mkdir -p "$HOME_DIR"
    {
        cat <<'GATES_HEADER'
# Ralphie gates - the definition of "working" for this project.
# One shell command per line, run from the project root.
# Exit 0 means healthy. Edit freely: this file is yours, not Ralphie's.
# Cheapest and most decisive checks first.
#
# WHAT YOU ARE SIGNING UP FOR: every command here runs at least once per
# cycle, for as long as the loop runs, with your full permissions. That is
# right for a test, a linter or a build. Think hard before putting anything
# here that touches live state - a migration, a deploy, `terraform apply` -
# because it will be run again, and again, unattended.
#
GATES_HEADER
    } > "$tmp"

    while IFS= read -r cmd; do
        [ -z "$cmd" ] && continue
        if gate_trial "$cmd"; then
            printf '%s\n' "$cmd" >> "$tmp"; kept=$((kept+1)); dim "  + $cmd"
        else
            printf '# unavailable here: %s\n' "$cmd" >> "$tmp"; skipped=$((skipped+1)); dbg "  - $cmd (not runnable)"
        fi
    done <<EOF
$(gate_candidates)
EOF

    if [ "$kept" -eq 0 ]; then
        # Honest degradation. Ralphie states plainly that it cannot verify this
        # project yet, and asks for a gate instead of pretending to be sure.
        printf '# NO GATE FOUND. Ralphie cannot verify this project yet.\n' >> "$tmp"
        printf '# Add one command below and everything downstream becomes trustworthy.\n' >> "$tmp"
        warn "no verifiable gate found - add one to $(basename "$GATES_FILE") for trustworthy results"
        warn "discovery checks the project root only; for unsupported stacks or workspaces, use --gate or edit .ralphie/gates"
        ask_human "What single shell command proves this project is healthy? Write it into .ralphie/gates"
    fi
    # Written through, not moved over: `mv` replaces the inode and would turn a
    # symlinked gate file into a private copy, exactly as it did in the restore.
    cat "$tmp" > "$GATES_FILE" 2>/dev/null || mv -f "$tmp" "$GATES_FILE"
    rm -f "$tmp" 2>/dev/null || true
    event gates discovered "kept $kept, skipped $skipped" "kept=$kept" "skipped=$skipped"
    [ "$kept" -gt 0 ] && good "gates: $kept active" || true
}

gates_list() {
    gate_path_inside_project || return 0
    [ -f "$GATES_FILE" ] || return 0
    grep -vE '^[[:space:]]*(#|$)' "$GATES_FILE" 2>/dev/null || true
}

# `grep -c` on an empty list exits 1 AND prints 0, so gates are counted
# through count_of rather than directly (see AGENTS.md).
gates_count() { count_of gates_list; }

run_gates() {
    # The single source of truth for "is it working". Returns 0 only if every
    # gate passes. Writes per-gate output for the next prompt to learn from.
    # $2 = "verify" marks the run that decides whether work is saved. That one
    # is never squeezed by the time budget: killing it discards finished,
    # correct work and then tells the operator the gate "was killed after 900s".
    # The budget exists to bound the expensive part, which is the engine.
    local logbase="${1:-$RUN_DIR/gates}" phase="${2:-observe}" cmd rc t n=0 failed=0
    GATES_NONE=0
    t="$(timeout_cmd)"
    mkdir -p "$RUN_DIR"
    : > "$logbase.summary"
    GATE_FAIL_CMD=""; GATE_FAIL_LOG=""; GATE_FLAKY=""; GATE_TIMED_OUT=""; GATE_TIMED_OUT_SECS=""
    # Checked HERE, every run of the gates. The flag was only ever refreshed in
    # run_prepare, so a gate file damaged mid-run was never noticed and one
    # repaired mid-run was never forgiven: the value read here was whatever it
    # had been at start-up.
    ensure_gates_file
    if [ "${GATES_FILE_BROKEN:-0}" = "1" ]; then
        # "The gate file is unreadable" is not "this project has no gates". The
        # difference decides whether work is committed as NOT VERIFIED, so an
        # unreadable gate file stops the run instead of quietly downgrading it.
        printf 'UNREADABLE  the gate file could not be read\n' > "$logbase.summary"
        GATE_FAIL_CMD="the gate file could not be read"
        return 1
    fi
    if [ "$(gates_count)" -eq 0 ]; then
        # "Nothing to run" is not "everything passes". Saying green here would
        # make Ralphie most confident exactly where it knows least, and it would
        # commit unverified work under the message "Gates green."
        printf 'UNVERIFIED  no gates configured\n' > "$logbase.summary"
        GATES_NONE=1
        return 0
    fi
    GATES_NONE=0
    while IFS= read -r cmd; do
        [ -z "$cmd" ] && continue
        n=$((n+1))
        local glog="$logbase.$n.log"
        dbg "gate: $cmd"
        local gsecs="${GATE_TIMEOUT:-900}"
        [ "$phase" = "verify" ] || gsecs="$(budget_cap "$gsecs")"
        gate_exec "$cmd" "$glog" "$gsecs"; rc=$?

        # A flaky gate is worse than a failing one: it sends the agent off to
        # fix a bug that does not exist, which costs money and can do damage.
        # One retry separates "this project is broken" from "this check is
        # unreliable", and the difference is reported rather than hidden.
        if [ "$rc" -ne 0 ] && [ "${GATE_RETRIES:-1}" -gt 0 ]; then
            dbg "gate failed, confirming: $cmd"
            gate_exec "$cmd" "$glog.retry" "$gsecs"; local rc2=$?
            if [ "$rc2" -eq 0 ]; then
                GATE_FLAKY="$cmd"
                event gate flaky "$cmd" "gate=$cmd" "phase=$phase"
                if [ "$phase" = "verify" ]; then
                    # THE VERIFY RUN DECIDES WHETHER WORK IS SAVED, so a gate
                    # that failed once is not forgiven here. Treating "failed
                    # then passed" as a pass in this phase promoted a genuinely
                    # broken project: the screen said "flaky gate ... not a real
                    # failure", then "gates: green", then "committed ... Verified
                    # by 1 gate(s)", then "objective complete" and exit 0 --
                    # while the same gate run by hand immediately afterwards
                    # still exited 1. No gate text was touched, so nothing else
                    # could have noticed.
                    warn "flaky gate: '$cmd' failed then passed - NOT treated as green"
                    dim  "  a check that cannot decide cannot promote work; fix or replace it"
                else
                    # Before the work is done, a flake is information, not a
                    # verdict: it must not send the engine to debug a phantom.
                    warn "flaky gate: '$cmd' failed then passed - not a real failure"
                    rc=0
                fi
            fi
            rm -f "$glog.retry" 2>/dev/null || true
        fi

        # Only the tail of a gate log is ever read, but a chatty suite can write
        # tens of megabytes per run, and the retention window keeps fifty
        # cycles. Trim to the part that is actually used.
        local lmax="${GATE_LOG_MAX:-262144}"
        if [ "$(file_bytes "$glog")" -gt "$lmax" ]; then
            tail -c "$lmax" "$glog" > "$glog.trim" 2>/dev/null &&
                mv -f "$glog.trim" "$glog" 2>/dev/null || rm -f "$glog.trim" 2>/dev/null
        fi

        if [ "$rc" -eq 0 ]; then
            printf 'PASS  %s\n' "$cmd" >> "$logbase.summary"
        else
            printf 'FAIL(%s)  %s\n' "$rc" "$cmd" >> "$logbase.summary"
            failed=$((failed+1))
            # 124 is `timeout` giving up, not the project being wrong. Telling an
            # agent to find the root cause of a 40-minute suite that was killed
            # at 15 minutes sends it to debug a limit it cannot see.
            [ "$rc" -eq 124 ] && { GATE_TIMED_OUT="$cmd"; GATE_TIMED_OUT_SECS="$gsecs"; }
            [ -z "$GATE_FAIL_CMD" ] && { GATE_FAIL_CMD="$cmd"; GATE_FAIL_LOG="$glog"; }
        fi
    done <<EOF
$(gates_list)
EOF
    [ "$failed" -eq 0 ]
}

GATES_BASELINE_FILE=""
ensure_gates_file() {
    # Same repair as state and ASK.md. A gates file replaced by a DIRECTORY
    # produced "cat: Is a directory", "gates: 1 active" printed next to
    # "gates 0", and a `--redetect` that failed while still exiting 0.
    # Reject before repair too: chmod and writes through an unresolved path
    # must not reach outside the project. Verification must not read it either.
    if ! gate_path_inside_project; then
        GATES_FILE_BROKEN=1
        warn "the gate file points outside the project or cannot be resolved"
        return 0
    fi
    ensure_own_file "$GATES_FILE" "gates file"
}

baseline_gates_load() {
    ensure_gates_file
    # The authoritative set persisted ACROSS runs. Holding it only in memory
    # defended one process: an engine that left a child behind
    # (`nohup sh -c "sleep 12; rm -f .ralphie/gates" &`) deleted the gates after
    # the run ended, and the next run simply re-derived the weaker set and
    # committed a broken project as "Verified by 1 gate(s)".
    GATES_BASELINE_FILE="$HOME_DIR/gates.baseline"
    [ -f "$GATES_BASELINE_FILE" ] || return 0
    local g missing=0
    while IFS= read -r g; do
        [ -n "$g" ] || continue
        grep -qxF -- "$g" "$GATES_FILE" 2>/dev/null && continue
        missing=$((missing+1))
    done < "$GATES_BASELINE_FILE"
    [ "$missing" -eq 0 ] && return 0
    # The same ordered merge the in-cycle restore uses. Appending here put the
    # cheapest check last for ever -- exactly the defect fixed one function
    # away, in the path the README actually leads with.
    GATES_SNAPSHOT="$(cat "$GATES_BASELINE_FILE" 2>/dev/null)"
    if ! restore_gate_order; then
        # Never claim a repair that did not happen. Saying "restored" here put
        # it on screen, into the append-only ledger, and into the question sent
        # to the human -- while the gates were still missing.
        err "$missing gate(s) from an earlier run are missing and could NOT be restored"
        event gates restored "$missing gate(s) could NOT be restored" "n=$missing"
        ask_human "Gates that existed in an earlier run are missing, and Ralphie could not put them back -- check whether $GATES_FILE is writable."
        return 1
    fi
    # Between runs a shrink could be the operator's own edit, so this is never
    # silent: restore, and let a human confirm. `gates --redetect` starts fresh.
    warn "$missing gate(s) present in an earlier run are missing now - restored"
    dim "  if you removed them on purpose: $ME gates --redetect"
    event gates restored "$missing gate(s) restored from the baseline" "n=$missing"
    ask_human "Gates that existed in an earlier run were missing at the start of this one, and Ralphie restored them. If you removed them deliberately, run '$ME gates --redetect'; if you did not, something in this project removed them."
}

baseline_gates_save() {
    [ -n "${GATES_BASELINE_FILE:-}" ] || GATES_BASELINE_FILE="$HOME_DIR/gates.baseline"
    gates_list > "$GATES_BASELINE_FILE" 2>/dev/null || true
}

GATES_SNAPSHOT=""
snapshot_gates() {
    # Held in memory, not only on disk. An agent asked to "tidy up" will happily
    # delete .ralphie/, taking the gates and any on-disk snapshot with it. The
    # one place it cannot reach is Ralphie's own process.
    #
    # It GROWS for the whole run and never shrinks. Re-deriving it from the file
    # each cycle was the hole: a gate deleted in cycle 1 was simply absent from
    # cycle 2's snapshot, the shrunken set was adopted as if normal, and three
    # commits landed saying "Verified by 1 gate(s)" on a project still broken.
    # An operator who wants a gate gone removes it between runs; an agent does
    # not get to remove one during a run.
    local cur g; cur="$(gates_list 2>/dev/null || true)"
    if [ -z "$GATES_SNAPSHOT" ]; then
        GATES_SNAPSHOT="$cur"
    else
        while IFS= read -r g; do
            [ -n "$g" ] || continue
            printf '%s\n' "$GATES_SNAPSHOT" | grep -qxF -- "$g" && continue
            GATES_SNAPSHOT="$GATES_SNAPSHOT
$g"
        done <<EOF
$cur
EOF
    fi
    mkdir -p "$RUN_DIR" 2>/dev/null || true
    printf '%s\n' "$GATES_SNAPSHOT" > "$RUN_DIR/gates.before" 2>/dev/null || true
}

check_gates() {
    # Always both halves. Written out at four call sites, one of them eventually
    # forgot the second line and the tamper was recorded with no name attached.
    guard_gates || CY_GATE_TAMPER=1
    [ -n "${GATE_TAMPER:-}" ] && CY_TAMPER_NAME="$GATE_TAMPER"
    return 0
}

resolve_link() {
    # FOLLOWED TO THE END, not one hop. A single hop was defeated by a two-link
    # chain: the first pointed inside the project, the second out of it, and the
    # containment check passed while the write landed anywhere the operator
    # could reach. Bounded so a cycle of links cannot hang the run.
    local p="$1" t n=0
    while [ "$n" -lt 16 ]; do
        t="$(readlink "$p" 2>/dev/null || printf '')"
        [ -n "$t" ] || break
        case "$t" in /*) p="$t";; *) p="$(dirname "$p")/$t";; esac
        n=$((n+1))
    done
    # A limit is not successful resolution. Never return an intermediate link
    # that passes containment while the kernel follows it to an external file.
    [ ! -L "$p" ] || return 1
    printf '%s' "$p"
}

gate_path_inside_project() {
    local target parent root
    target="$(resolve_link "$GATES_FILE")" || return 1
    [ -n "$target" ] || return 1
    parent="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)" || return 1
    root="$(cd "$PROJECT" 2>/dev/null && pwd -P)" || return 1
    [ -n "$parent" ] && [ -n "$root" ] || return 1
    case "$parent/" in "$root"/*) return 0;; esac
    return 1
}

restore_gate_order() {
    # A restored gate goes back WHERE IT WAS, not onto the end. The file's own
    # header says "cheapest and most decisive checks first", and appending made
    # the cheapest check run last for ever, after every tamper event.
    #
    # An ordered merge of two sequences: walk the file the operator has now, and
    # each time it reaches a gate Ralphie remembers, first emit any remembered
    # gates that belonged before it. Comments, blank lines and gates the engine
    # ADDED keep their places; only the missing ones are put back.
    local out="$GATES_FILE.restore.$$" line g i k n=0
    local snap_n=0
    # Writable, or nothing below can be honest. An unwritable gate file used to
    # produce "restored" on screen and in the append-only ledger while the file
    # was untouched -- and a raw shell error from the redirect on top.
    [ -w "$GATES_FILE" ] || { warn "the gate file is not writable - gates were NOT restored"; return 1; }
    # A symlink is honoured, but only while its TARGET stays inside the project.
    # Writing through one that points outside would let a hostile engine turn a
    # gate restore into a write to any file the operator can reach.
    # Both sides are resolved: on macOS /tmp is itself a symlink to /private/tmp,
    # so comparing a resolved path against an unresolved one rejects everything.
    gate_path_inside_project || {
        warn "the gate file points outside the project or cannot be resolved - gates were NOT restored"
        return 1
    }
    while IFS= read -r g; do
        [ -n "$g" ] || continue
        eval "_gsnap_$snap_n=\$g"
        snap_n=$((snap_n+1))
    done <<EOF
$GATES_SNAPSHOT
EOF
    : > "$out" || return 1
    i=0
    while IFS= read -r line || [ -n "$line" ]; do
        k=-1
        n="$i"
        while [ "$n" -lt "$snap_n" ]; do
            eval "g=\$_gsnap_$n"
            [ "$g" = "$line" ] && { k="$n"; break; }
            n=$((n+1))
        done
        if [ "$k" -ge 0 ]; then
            while [ "$i" -lt "$k" ]; do
                eval "g=\$_gsnap_$i"
                grep -qxF -- "$g" "$GATES_FILE" 2>/dev/null || printf '%s\n' "$g" >> "$out"
                i=$((i+1))
            done
            i=$((k+1))
        fi
        printf '%s\n' "$line" >> "$out"
    done < "$GATES_FILE"
    while [ "$i" -lt "$snap_n" ]; do
        eval "g=\$_gsnap_$i"
        grep -qxF -- "$g" "$GATES_FILE" 2>/dev/null || printf '%s\n' "$g" >> "$out"
        i=$((i+1))
    done
    # Written THROUGH the path, never moved over it. `mv` replaces the inode,
    # which turns a symlinked gate file into a private regular copy (the
    # operator's real file keeps the damage) and resets a deliberate `chmod 444`
    # to 644. self_update documents the same trap 2,000 lines below.
    #
    # But `>` truncates FIRST and can then fail part-way: on a full disk this
    # left an 81-gate file at 0 bytes and printed 12,909 raw shell errors. So
    # the old contents are kept until the new ones are proven to have landed
    # whole, and put back byte for byte if they did not.
    local want keep="$GATES_FILE.keep.$$"
    want="$(wc -c < "$out" 2>/dev/null | tr -d ' ')"
    cat "$GATES_FILE" > "$keep" 2>/dev/null || : > "$keep"
    if cat "$out" > "$GATES_FILE" 2>/dev/null &&
       [ "$(wc -c < "$GATES_FILE" 2>/dev/null | tr -d ' ')" = "$want" ]; then
        rm -f "$out" "$keep" 2>/dev/null || true
        return 0
    fi
    cat "$keep" > "$GATES_FILE" 2>/dev/null || true
    rm -f "$out" "$keep" 2>/dev/null || true
    warn "the gate file could not be rewritten - gates were NOT restored"
    return 1
}

guard_gates() {
    # The contract asks the engine not to make a gate pass by deleting it.
    # Asking is not enforcing. A verification surface that the thing being
    # verified is free to edit is not a verification surface at all.
    #
    # Measured: a mock engine replaced the only gate with `true`. Ralphie
    # reported green, committed, and declared the objective complete while the
    # project was still broken. That is the single failure this program exists
    # to prevent, so removal is now undone rather than trusted.
    #
    # Gates the engine ADDS are kept. A project teaching Ralphie how to check it
    # is exactly what should happen, and it has been observed doing so usefully.
    GATE_TAMPER=""
    local g missing=0
    [ -n "$GATES_SNAPSHOT" ] || return 0
    ensure_dirs
    if ! gate_path_inside_project; then
        GATE_TAMPER="the gate file points outside the project or cannot be resolved"
        err "$GATE_TAMPER"
        event gate tampered "$GATE_TAMPER"
        return 1
    fi
    # The path must be a readable regular file before anything can be restored
    # into it. Measured: replacing .ralphie/gates with a DIRECTORY made every
    # later read fail, left the project with zero usable gates, and let a broken
    # tree through as "unverified" -- an escape hatch out of verification
    # altogether. Deleting it or making it unreadable are the same trick.
    if [ ! -f "$GATES_FILE" ] || [ ! -r "$GATES_FILE" ]; then
        rm -rf "$GATES_FILE" 2>/dev/null || true
        : > "$GATES_FILE" 2>/dev/null || true
        chmod u+rw "$GATES_FILE" 2>/dev/null || true
    fi
    while IFS= read -r g; do
        [ -n "$g" ] || continue
        grep -qxF -- "$g" "$GATES_FILE" 2>/dev/null && continue
        missing=$((missing+1))
        GATE_TAMPER="$g"
    done <<EOF
$GATES_SNAPSHOT
EOF
    [ "$missing" -eq 0 ] && return 0
    # Report only what was really done. Announcing "restored" when the rewrite
    # failed put a restore that never happened into the append-only ledger.
    if restore_gate_order; then
        err "$missing gate(s) disappeared during this cycle - restored"
        event gate tampered "$missing gate(s) removed and restored; last: $GATE_TAMPER" "n=$missing"
    else
        err "$missing gate(s) disappeared during this cycle and could NOT be restored"
        event gate tampered "$missing gate(s) removed; restore FAILED; last: $GATE_TAMPER" "n=$missing"
    fi
    return 1
}

gate_failure_brief() {
    # Bounded, high-signal failure evidence. The tail of a failing run contains
    # the error; the head contains setup noise nobody needs to pay tokens for.
    [ -n "${GATE_FAIL_CMD:-}" ] || return 0
    if [ -n "${GATE_TIMED_OUT:-}" ]; then
        printf 'GATE TIMED OUT after %ss: %s\n\n' "${GATE_TIMED_OUT_SECS:-${GATE_TIMEOUT:-900}}" "$GATE_TIMED_OUT"
        printf 'This is an environment limit, not necessarily a defect. The command was\n'
        printf 'killed before it could finish, so its result is unknown. Do not guess at a\n'
        printf 'root cause from the truncated output below. If this check legitimately needs\n'
        printf 'longer, say so in ask: and the operator can raise GATE_TIMEOUT.\n\n'
    else
        printf 'FAILING GATE: %s\n\n' "$GATE_FAIL_CMD"
    fi
    [ -f "${GATE_FAIL_LOG:-}" ] && tail_of "$GATE_FAIL_LOG" "${GATE_BRIEF_BYTES:-3000}"
}

# --- git --------------------------------------------------------------------

git_ready() {
    # `.git` is a FILE in a worktree and in a submodule. Requiring a directory
    # meant Ralphie reported green cycles in a worktree while committing
    # absolutely nothing.
    git -C "$PROJECT" rev-parse --git-dir >/dev/null 2>&1
}

ensure_git() {
    git_ready && return 0
    is_true "${RALPHIE_GIT_INIT:-1}" || return 1
    git -C "$PROJECT" init -q 2>/dev/null || return 1
    info "initialised a git repository (every cycle needs somewhere to land)"
    event git init "repository created"
}

git_identity() {
    # A commit with no identity aborts the whole cycle. Supply a local one
    # rather than failing, and never touch global config.
    git_ready || return 0
    git -C "$PROJECT" config user.email >/dev/null 2>&1 || git -C "$PROJECT" config user.email "ralphie@localhost"
    git -C "$PROJECT" config user.name  >/dev/null 2>&1 || git -C "$PROJECT" config user.name  "Ralphie"
}

git_dirty() { git_ready && [ -n "$(git -C "$PROJECT" status --porcelain 2>/dev/null)" ]; }

git_branch() {
    # `rev-parse --abbrev-ref HEAD` prints the literal string "HEAD" AND exits
    # non-zero in a repository with no commits, so a naive `||` fallback emits
    # both values. symbolic-ref works before the first commit; rev-parse covers
    # a detached head.
    git -C "$PROJECT" symbolic-ref --quiet --short HEAD 2>/dev/null && return 0
    git -C "$PROJECT" rev-parse --short HEAD 2>/dev/null && return 0
    printf 'none'
}

OWNED_FILE=""
nul_list_has() {
    # nul_list_has <file> <path>: is this exact path in a NUL-separated list?
    # Read NUL to NUL. Converting to newlines first -- which is what this very
    # helper existed to avoid -- meant one file whose name contains a newline
    # made Ralphie disown its own work permanently.
    local entry
    [ -n "${1:-}" ] && [ -f "$1" ] || return 1
    while IFS= read -r -d '' entry; do
        [ "$entry" = "$2" ] && return 0
    done < "$1"
    return 1
}
path_fingerprint() {
    # The content Ralphie left behind, or "-" when the file is absent.
    # `-r` as well as `-f`: an input redirect fails BEFORE `2>/dev/null` can
    # apply to it, so an unreadable file printed a raw shell error to the
    # operator's terminal. file_bytes documents the same trap; it came back.
    # One sentinel: "these are not bytes Ralphie can vouch for". No caller ever
    # distinguished absent from unreadable, and two spellings of the same answer
    # is an invitation to compare against the wrong one.
    [ -f "$PROJECT/$1" ] && [ -r "$PROJECT/$1" ] || { printf -- '-'; return 0; }
    sha_of < "$PROJECT/$1" 2>/dev/null || printf -- '-'
}

owned_has() {
    # A claim is tied to CONTENT, not to dirtiness. Keeping it while the file
    # was merely "still dirty" meant the operator could revert Ralphie's work,
    # write their own in the same file, and have it committed on Ralphie's
    # behalf -- with no warning, breaking the promise the README leads with.
    # The instant the bytes differ from what Ralphie left, the claim is void.
    local want p rest
    [ -n "${OWNED_FILE:-}" ] && [ -f "$OWNED_FILE" ] || return 1
    want="$(path_fingerprint "$1")"
    # EVERY matching record is considered, not just the first. Returning on the
    # first match let a duplicate -- which the budget-expired path creates, by
    # recording without releasing first -- shadow the true one and make Ralphie
    # disown its own work.
    while IFS= read -r -d '' rest; do
        [ -n "$rest" ] || continue
        p="${rest#*	}"
        [ "$p" = "$1" ] || continue
        [ "${rest%%	*}" = "$want" ] && return 0
    done < "$OWNED_FILE"
    return 1
}
pre_dirty_has() { nul_list_has "${PRE_DIRTY_FILE:-}" "$1"; }

dirty_paths_nul() {
    # --no-renames is required: with rename detection a `git mv` collapses to
    # the destination path only, so the operator's in-flight move was half
    # excluded and half committed.
    ( cd "$(git_top)" && git diff --name-only -z --no-renames HEAD 2>/dev/null ) || true
    ( cd "$(git_top)" && git ls-files --others --exclude-standard -z 2>/dev/null ) || true
}

release_owned_paths() {
    # A path stops being Ralphie's the moment it is no longer dirty: the work
    # was committed, or reverted, and any LATER change to that file belongs to
    # whoever made it. Keeping the claim for ever meant the operator's own
    # uncommitted edit was silently committed days afterwards -- the exact
    # promise the README leads with.
    git_ready || return 0
    OWNED_FILE="$HOME_DIR/owned.nul"
    [ -s "$OWNED_FILE" ] || return 0
    local dirty="$RUN_DIR/dirty-now.nul" kept="$OWNED_FILE.tmp.$$" rec p
    dirty_paths_nul > "$dirty" 2>/dev/null || return 0
    : > "$kept"
    while IFS= read -r -d '' rec; do
        [ -n "$rec" ] || continue
        p="${rec#*	}"
        # Kept only while the path is still dirty AND still holds exactly the
        # bytes Ralphie left there.
        nul_list_has "$dirty" "$p" || continue
        if [ "${rec%%	*}" != "$(path_fingerprint "$p")" ]; then
            # Still dirty, but the bytes are no longer the ones Ralphie left.
            # Dropping the claim is not enough: record_owned_paths re-claims any
            # dirty path that is not pre-dirty, so three lines later the
            # operator's own edit became Ralphie's. Hand the path back instead.
            # Re-sealed ONLY over a list that is still provably intact. Stamping
            # a new seal onto an already-damaged list launders the damage: the
            # guard then compares the tampered list against its own fresh
            # checksum, finds them equal, and commits the operator's work. That
            # is the same promise broken a fourth time, by the repair itself.
            if [ "${1:-}" != "after-cycle" ] \
               && [ -n "${PRE_DIRTY_FILE:-}" ] && [ -f "$PRE_DIRTY_FILE" ] \
               && pre_dirty_intact && ! pre_dirty_has "$p"; then
                printf '%s\0' "$p" >> "$PRE_DIRTY_FILE"
                pre_dirty_seal
            fi
            continue
        fi
        printf '%s\0' "$rec" >> "$kept"
    done < "$OWNED_FILE"
    mv -f "$kept" "$OWNED_FILE" 2>/dev/null || rm -f "$kept" 2>/dev/null
    rm -f "$dirty" 2>/dev/null || true
    return 0
}

record_owned_paths() {
    # A cycle whose gates stayed red leaves real work uncommitted. Without this,
    # the NEXT run snapshots that work as "the operator's pre-existing changes"
    # and excludes it from every future commit -- permanently. Ralphie therefore
    # remembers which paths are its own.
    git_ready || return 0
    # The seal is checked HERE too, not only before a commit. `pre_dirty_has`
    # answers "no" for every path once the exclusion list is gone, so a cycle
    # that destroyed it went on to claim the operator's files as RALPHIE'S OWN --
    # and that claim outlived the run. The next run saw a perfectly valid
    # content-keyed claim, excluded the file from its fresh snapshot, and
    # committed the operator's work with no warning.
    #
    # Found by the fuzzer, not by inspection: it needed one cycle to delete the
    # list and a later cycle in the NEXT run to go green on the same file.
    if ! pre_dirty_intact; then
        dbg "the exclusion list is not intact - claiming nothing this cycle"
        return 0
    fi
    OWNED_FILE="$HOME_DIR/owned.nul"
    local tmp="$RUN_DIR/dirty.nul" p
    dirty_paths_nul > "$tmp" 2>/dev/null || return 0
    while IFS= read -r -d '' p; do
        [ -n "$p" ] || continue
        pre_dirty_has "$p" && continue
        owned_has "$p" && continue
        printf '%s\t%s\0' "$(path_fingerprint "$p")" "$p" >> "$OWNED_FILE"
    done < "$tmp"
    rm -f "$tmp" 2>/dev/null || true
}

pre_dirty_count() {
    [ -n "${PRE_DIRTY_FILE:-}" ] && [ -f "$PRE_DIRTY_FILE" ] || { printf '0'; return 0; }
    local n; n="$(tr '\0' '\n' < "$PRE_DIRTY_FILE" 2>/dev/null | grep -c . 2>/dev/null)" || n=0
    is_int "$n" || n=0
    printf '%s' "$n"
}

use_branch() {
    # Most teams protect their main branch, and an autonomous committer is
    # exactly the thing that protection exists for. Doing the work on a named
    # branch makes Ralphie reviewable through the normal pull-request path
    # instead of something you have to trust.
    local want="$1"
    [ -n "$want" ] || return 0
    git_ready || { warn "cannot use a branch without a git repository"; return 0; }
    # Recorded ONCE. Overwriting it on a resumed run made the work branch its
    # own base, so the operator was never returned to their protected branch.
    if [ -z "$(state_get base_branch '')" ] || [ "$(git_branch)" != "$want" ]; then
        state_set base_branch "$(git_branch)"
    fi
    if [ "$(git_branch)" = "$want" ]; then
        dbg "already on branch $want"
    elif git -C "$PROJECT" show-ref --verify --quiet "refs/heads/$want" 2>/dev/null; then
        git -C "$PROJECT" checkout -q "$want" 2>/dev/null || { err "cannot switch to branch '$want'"; return 1; }
        info "switched to existing branch $want"
    else
        git -C "$PROJECT" checkout -q -b "$want" 2>/dev/null || { err "cannot create branch '$want'"; return 1; }
        info "created branch $want"
    fi
    event git branch "working on $want" "branch=$want"
    RESTORE_BRANCH="$(state_get base_branch '')"
}

warn_detached_head() {
    # A commit made on a detached HEAD is unreachable the moment anyone checks
    # out a branch: the work looks saved, and then is simply gone. An
    # unattended loop must not quietly produce that.
    git_ready || return 0
    git -C "$PROJECT" symbolic-ref --quiet HEAD >/dev/null 2>&1 && return 0
    err "HEAD is detached: a commit made here is unreachable after any checkout"
    err "rerun with --branch NAME, or check out a branch first"
    event git detached "refused to run on a detached HEAD"
    ask_human "Ralphie refused to run on a detached HEAD, because anything it committed would be unreachable once you check out a branch. Rerun with --branch NAME, or check out a branch first."
    return 1
}

SELF_HASH=""
self_hash_record() { SELF_HASH="$(sha_of < "$SELF" 2>/dev/null || printf '')"; }

self_is_reviewed() {
    # Said at START-UP, before any work happens. A previous cycle can leave a
    # modified kernel on disk that was never committed -- because it failed its
    # gates -- and THIS run is the one that executes it. The operator deserves
    # to know that the code about to supervise their repository is not the code
    # their repository has under review.
    git_ready || return 0
    case "$SELF" in "$PROJECT"/*) ;; *) return 0;; esac   # not inside this repo
    local rel="${SELF#"$PROJECT"/}"
    git -C "$PROJECT" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 || return 0
    git -C "$PROJECT" diff --quiet -- "$rel" 2>/dev/null && return 0
    warn "the script you are running differs from the committed copy ($rel)"
    dim  "  review it before trusting this run:  git diff -- $rel"
    event self uncommitted "the running script differs from the committed copy"
    return 1
}

self_hash_check() {
    # An engine with write access to the repository can edit the verifier. A
    # probe committed `guard_gates() { return 0; }` as "verified work", and the
    # NEXT run happily emptied the gates file with no tamper report at all.
    # Ralphie improving its own source is a legitimate and intended use, so this
    # is never silently blocked -- but it is never silent either.
    local now
    [ -n "$SELF_HASH" ] || return 0
    now="$(sha_of < "$SELF" 2>/dev/null || printf '')"
    [ -n "$now" ] && [ "$now" = "$SELF_HASH" ] && return 0
    err "the running script was modified during this cycle"
    dim "  this run keeps using the copy it started with; the NEXT run will not"
    event self modified "ralphie.sh changed during a cycle"
    ask_human "Ralphie's own script was modified while it was running. If that was the point of this work, review the diff before the next run, because the next run executes the new copy and it may have weakened its own checks. If it was not, revert it."
    SELF_HASH="$now"
    return 1
}

record_recovery_point() {
    # One command undoes an entire unattended run. An operator who knows that is
    # willing to let it run; one who does not, is not.
    git_ready || return 0
    # --verify --quiet is the only spelling that stays silent and fails cleanly
    # on a repository with no commits, instead of echoing "HEAD" back.
    local sha; sha="$(git -C "$PROJECT" rev-parse --verify --quiet HEAD 2>/dev/null || printf '')"
    case "$sha" in ''|*[!0-9a-fA-F]*) 
        dbg "no commits yet; this run creates the first"
        return 0;;
    esac
    state_set start_commit "$sha"
    event git recovery "run starts at $sha" "sha=$sha"
}

pre_dirty_seal() {
    # POSITIVE PROOF, not another negative test. Three rounds of review each
    # produced a guard that asked "is the exclusion list damaged?" -- first
    # "is it empty", then "is it missing" -- and each time an engine found a
    # spelling of damage the question did not cover (truncate it; point it at
    # an empty file). The list is now SEALED: its length and checksum are
    # recorded here and re-checked immediately before every commit, so any
    # change at all, by any means, is caught.
    PRE_DIRTY_SEAL="$(pre_dirty_count):$(sha_of < "$PRE_DIRTY_FILE" 2>/dev/null || printf 'none')"
}

pre_dirty_intact() {
    # No seal means no proof, and no proof must never read as "fine". Failing
    # open here meant a project with no git repository -- where the snapshot
    # returns early and never seals -- committed the operator's whole directory.
    [ -n "${PRE_DIRTY_SEAL:-}" ] || return 1
    [ -n "$PRE_DIRTY_FILE" ] && [ -f "$PRE_DIRTY_FILE" ] || return 1
    [ "$(pre_dirty_count):$(sha_of < "$PRE_DIRTY_FILE" 2>/dev/null || printf 'none')" = "$PRE_DIRTY_SEAL" ]
}

RESTORE_BRANCH=""
PRE_DIRTY_FILE=""
PRE_DIRTY_SEAL=""
GATES_FILE_BROKEN=0
UNUSABLE_REPORTED=""
GIT_MODE=repo
GATE_NO_PIPEFAIL=0
OPERATOR_STAGED=""
PRE_DIRTY_N=0
snapshot_pre_dirty() {
    # Whatever the operator already had in flight before Ralphie started is
    # theirs. Sweeping it into an autonomous commit is a betrayal of trust that
    # is very hard to undo, so those paths are recorded and later excluded.
    #
    # The paths MUST be NUL-separated and unquoted. `git status --porcelain`
    # wraps any path containing a space or a non-ASCII byte in quotes and
    # escapes it ("rÃ©servÃ©.txt"). That quoted form never matches
    # the real file, the exclusion silently does nothing, and the operator's
    # work is committed anyway. Measured: it really happened.
    git_ready || return 0
    # Private to this process: a second `ralphie status` used to overwrite the
    # running loop's snapshot with the loop's own edits, so the loop then
    # excluded its own verified work from its commit.
    PRE_DIRTY_FILE="$RUN_DIR/pre-dirty.$$.nul"
    OWNED_FILE="$HOME_DIR/owned.nul"
    # What the operator has STAGED, which is different from what they have
    # modified. These paths are the ones the private-index commit must leave
    # alone afterwards, because a staged revision can exist nowhere else.
    OPERATOR_STAGED="$RUN_DIR/operator-staged.nul"
    ( cd "$(git_top)" && git diff --cached --name-only -z --no-renames HEAD 2>/dev/null ) > "$OPERATOR_STAGED" 2>/dev/null || : > "$OPERATOR_STAGED"
    mkdir -p "$RUN_DIR"
    local raw="$RUN_DIR/pre-dirty.raw.$$" p
    dirty_paths_nul > "$raw" 2>/dev/null || : > "$raw"
    : > "$PRE_DIRTY_FILE"
    while IFS= read -r -d '' p; do
        [ -n "$p" ] || continue
        # Ralphie's own runtime noise and its own unfinished work from an
        # earlier run are not the operator's in-flight changes.
        # .ralphie/ is Ralphie's own noise. .gitignore is NOT exempt any more:
        # Ralphie stopped writing it, so an uncommitted edit there is the
        # operator's, and sweeping it up was exactly the promise being broken.
        case "$p" in .ralphie/*) continue;; esac
        owned_has "$p" && continue
        printf '%s\0' "$p" >> "$PRE_DIRTY_FILE"
    done < "$raw"
    rm -f "$raw" 2>/dev/null || true
    local n; n="$(pre_dirty_count)"
    PRE_DIRTY_N="$n"
    pre_dirty_seal
    # Only worth saying when Ralphie is about to commit something.
    if [ "$n" -gt 0 ] && [ "${CMD:-run}" = "run" ]; then
        warn "$n path(s) were already modified before this run - they will not be committed"
        event git predirty "$n pre-existing modified paths excluded from commits" "n=$n"
        if ! git -C "$PROJECT" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
            warn "no baseline commit: existing protected files will remain unsaved, even if the engine edits them"
            warn "  before engine work, consider stopping to review and commit only a safe baseline; do not add private files blindly"
        fi
    fi
}

# Things an autonomous commit must never sweep up. Measured: a cycle committed
# a .env holding a live AWS key, a 200 KB binary and node_modules/, all under a
# message claiming the gates were green. An agent does not know which of your
# files are secrets; this list does.
RISKY_PATHS='(^|/)[^/]*\.env($|\.)|(^|/)\.envrc$|[._-]env$|(^|/)id_(rsa|dsa|ecdsa|ed25519)$|\.(pem|p12|pfx|key|keystore|jks|ppk)$|(^|/)\.netrc$|(^|/)\.npmrc$|(^|/)\.pypirc$|(^|/)\.git-credentials$|(^|/)credentials(\.[a-z]+)?$|(^|/)\.aws/|(^|/)\.ssh/|(^|/)\.gnupg/|(^|/)secrets?([._-][^/]*)?\.(ya?ml|json|toml|ini|env)$|(^|/)service[-_]account[^/]*\.json$|\.tfstate(\.backup)?$|(^|/)\.terraform/|(^|/)kubeconfig$|(^|/)\.kube/config$|(^|/)\.dockercfg$|(^|/)\.docker/config\.json$|\.(jks|p8|pkcs12)$'
BULK_PATHS='(^|/)(node_modules|vendor|\.venv|venv|__pycache__|\.mypy_cache|\.pytest_cache|dist|build|target|\.next|coverage|\.terraform)/'

unstage_risky() {
    # The index to operate on, passed rather than read from a global: it was set
    # in one function and read in another, with nothing to stop it going stale.
    local COMMIT_INDEX="$1"
    # Runs after `git add -A`, before the commit.
    local p n=0 big=0 bulk=0 sz max="${RALPHIE_MAX_COMMIT_BYTES:-1048576}"
    UNSTAGED_RISKY=""; UNSTAGED_BULK=""
    # A NUL-separated list MUST travel through a file. Command substitution
    # silently discards NUL bytes, so `done <<EOF $(git ... -z) EOF` collapses
    # every path into one unusable string and the whole filter quietly does
    # nothing. It looked like it worked.
    local staged="$RUN_DIR/staged.$$.nul"
    mkdir -p "$RUN_DIR" 2>/dev/null || true
    ( cd "$(git_top)" && GIT_INDEX_FILE="$COMMIT_INDEX" git diff --cached --name-only -z --no-renames 2>/dev/null ) > "$staged" 2>/dev/null || : > "$staged"
    local home_rel="${HOME_DIR#"$PROJECT"/}"
    while IFS= read -r -d '' p; do
        [ -n "$p" ] || continue
        # RALPHIE NEVER COMMITS ITS OWN STATE, even when the operator has chosen
        # to track it. `.ralphie/` is normally excluded, but git ignores an
        # ignore rule for a path that is already tracked -- and a team that
        # deliberately shares its gate file has exactly that. Committing it
        # would write Ralphie's ledger, prompts and, worst of all, a WEAKENED
        # gate file into the project's history as though it were work.
        # Changes the operator makes to their own tracked gate file stay theirs
        # to commit. Found by the fuzzer.
        case "$p/" in
            "$home_rel"/*) ( cd "$(git_top)" && GIT_INDEX_FILE="$COMMIT_INDEX" git reset -q -- "$p" ) >/dev/null 2>&1 || true
                           continue;;
        esac
        if printf '%s' "$p" | grep -qE "$RISKY_PATHS"; then
            ( cd "$(git_top)" && GIT_INDEX_FILE="$COMMIT_INDEX" git reset -q -- "$p" ) >/dev/null 2>&1 || true
            UNSTAGED_RISKY="$UNSTAGED_RISKY $p"; n=$((n+1)); continue
        fi
        if printf '%s' "$p" | grep -qE "$BULK_PATHS"; then
            ( cd "$(git_top)" && GIT_INDEX_FILE="$COMMIT_INDEX" git reset -q -- "$p" ) >/dev/null 2>&1 || true
            UNSTAGED_BULK="$UNSTAGED_BULK $p"; bulk=$((bulk+1)); continue
        fi
        # A staged DELETION still appears in the path list but no longer exists
        # on disk, and `wc -c < missing` makes the shell itself print a redirect
        # error that 2>/dev/null inside the substitution cannot suppress.
        # A symlink is committed as its TARGET path, so a link to /etc/passwd
        # carries nothing secret -- but a link that RESOLVES outside the project
        # is still a deliberate escape from the repository and never something
        # an autonomous commit should decide to add.
        if [ -L "$PROJECT/$p" ]; then
            local tgt; tgt="$(cd "$PROJECT" 2>/dev/null && readlink "$p" 2>/dev/null || printf '')"
            case "$tgt" in
                /*|*../*) ( cd "$(git_top)" && GIT_INDEX_FILE="$COMMIT_INDEX" git reset -q -- "$p" ) >/dev/null 2>&1 || true
                          UNSTAGED_RISKY="$UNSTAGED_RISKY $p"; n=$((n+1)); continue;;
            esac
        fi
        sz="$(file_bytes "$PROJECT/$p")"
        if [ "$sz" -gt "$max" ]; then
            ( cd "$(git_top)" && GIT_INDEX_FILE="$COMMIT_INDEX" git reset -q -- "$p" ) >/dev/null 2>&1 || true
            UNSTAGED_RISKY="$UNSTAGED_RISKY $p"; big=$((big+1)); continue
        fi
    done < "$staged"
    rm -f "$staged" 2>/dev/null || true
    # Build output is obvious junk and needs a note, not a decision. Only a
    # possible secret or something surprisingly large is worth a human's
    # attention: a channel that cries wolf about __pycache__ stops being read.
    if [ "$bulk" -gt 0 ]; then
        dim "  skipped $bulk build artefact(s):$(printf '%s' "$UNSTAGED_BULK" | cut -c1-120)"
        event commit skipped "$bulk build artefact(s) not committed" "n=$bulk"
    fi
    [ "$((n+big))" -eq 0 ] && return 0
    warn "held back $((n+big)) path(s) from the commit (possible secrets or very large files)"
    dim "  $(trim "$UNSTAGED_RISKY")"
    event commit held "$((n+big)) risky path(s) excluded:$UNSTAGED_RISKY" "n=$((n+big))"
    ask_human "Ralphie refused to commit these paths automatically:$UNSTAGED_RISKY. If they belong in the repository, add them yourself; if they are secrets, add them to .gitignore."
    # Explicit: without it this function returns `ask_human`'s status, and a
    # caller reading it as "could not hold anything back" would be wrong.
    return 0
}

# Resolved ONCE per run and then read from memory. As a fresh `git rev-parse`
# at every index operation it cost a subprocess per staged path, and six
# instant gates went from 7 to 9 seconds. The repository root cannot move while
# a run is in progress; if the repository is destroyed, GIT_MODE says so.
GIT_TOP=""
PROJECT_PREFIX=""

git_top() {
    # THE REPOSITORY ROOT, not the project directory. They are the same thing
    # only when Ralphie is planted at the top of its own repository.
    #
    # Planted one level down -- a monorepo sub-project, a checkout inside a
    # checkout, any directory that merely SITS INSIDE a parent repository such
    # as a dotfiles `~/.git` -- `git add -A` stages the WHOLE repository, while
    # every exclusion was `cd "$PROJECT" && git reset -- <path>` with a path
    # git reports relative to the ROOT. From a subdirectory those paths resolve
    # to `$PROJECT/$path`, match nothing, and exit 0. So the pre-dirty
    # exclusion, the secret filter, the bulk filter and the `.ralphie/` rule
    # were all silent no-ops, and Ralphie printed "held back 2 path(s)" and
    # then committed a live AWS key and the operator's private draft.
    #
    # Every index operation is anchored here so that the paths git gives us are
    # the paths git accepts back.
    if [ -z "${GIT_TOP:-}" ]; then
        GIT_TOP="$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PROJECT")"
    fi
    printf '%s' "$GIT_TOP"
}

project_prefix() {
    # Where the project sits inside the repository, as a pathspec git
    # understands from the root. `.` when they are the same directory.
    #
    # BOTH sides are reduced to their PHYSICAL path first. `git --show-toplevel`
    # already returns one, so on macOS it answers /private/tmp/... while
    # $PROJECT is still /tmp/...: the containment test then failed, the prefix
    # came out as `.`, and this whole defence quietly did nothing.
    if [ -z "${PROJECT_PREFIX:-}" ]; then
        local top p
        top="$( cd "$(git_top)" 2>/dev/null && pwd -P )" || top=""
        p="$( cd "$PROJECT" 2>/dev/null && pwd -P )" || p=""
        if { [ -n "$top" ] && [ -n "$p" ]; } && [ "$p" != "$top" ]; then
            case "$p" in "$top"/*) PROJECT_PREFIX="${p#"$top"/}";; *) PROJECT_PREFIX=".";; esac
        else
            PROJECT_PREFIX="."
        fi
    fi
    printf '%s' "$PROJECT_PREFIX"
}

commit_head() {
    # `git rev-parse HEAD` prints the literal string "HEAD" in an empty
    # repository, so the safe spelling is the only spelling used.
    git -C "$PROJECT" rev-parse --verify --quiet HEAD 2>/dev/null || printf 'none'
}

# Evidence captured in memory before any cycle command can change history.
CY_HEAD=""
CY_REF=""
CY_OLD_COMMITS=""
CY_HISTORY_CAPTURED=0
CY_ENGINE_SAVED=0

engine_history_is_safe() {
    # HEAD movement alone is not work: reject rewrites, branch switches, old
    # commits, and empty changes. Inspect EVERY new commit, not only the final
    # diff (a secret added then deleted is still in history). Never reset the
    # operator's history to hide an invalid engine commit; leave it for review.
    local head="$1" commits c parents previous p paths size mode target prefix home_rel
    [ "$CY_HISTORY_CAPTURED" = 1 ] || return 1
    [ "$head" != none ] && [ -n "$CY_REF" ] || return 1
    [ "$(git -C "$PROJECT" symbolic-ref --quiet HEAD 2>/dev/null)" = "$CY_REF" ] || return 1
    pre_dirty_intact || return 1
    if [ "$CY_HEAD" = none ]; then
        commits="$(git -C "$PROJECT" rev-list --reverse "$head" 2>/dev/null)" || return 1
    else
        git -C "$PROJECT" merge-base --is-ancestor "$CY_HEAD" "$head" 2>/dev/null || return 1
        commits="$(git -C "$PROJECT" rev-list --reverse "$CY_HEAD..$head" 2>/dev/null)" || return 1
        git -C "$PROJECT" diff --quiet "$CY_HEAD" "$head" && return 1
    fi
    [ -n "$commits" ] || return 1
    previous="$CY_HEAD"; prefix="$(project_prefix)"
    home_rel="${HOME_DIR#"$(git_top)"/}"
    paths="$RUN_DIR/engine-commit-paths.$$.nul"
    ensure_own_file "$paths" "engine commit paths"
    [ ! -e "$paths" ] || { [ -f "$paths" ] && [ -w "$paths" ]; } || return 1
    for c in $commits; do
        case " $CY_OLD_COMMITS " in *" $c "*) return 1;; esac
        parents="$(git -C "$PROJECT" show -s --format=%P "$c")" || return 1
        if [ "$previous" = none ]; then
            [ -z "$parents" ] || return 1
        else
            [ "$parents" = "$previous" ] || return 1
        fi
        git -C "$(git_top)" diff-tree --root --no-commit-id --no-renames --name-only -r -z "$c" > "$paths" || return 1
        [ -s "$paths" ] || return 1
        while IFS= read -r -d '' p; do
            [ "$prefix" = . ] || case "$p" in "$prefix"/*) ;; *) return 1;; esac
            case "$p/" in "$home_rel"/*) return 1;; esac
            pre_dirty_has "$p" && return 1
            printf '%s' "$p" | grep -qE "$RISKY_PATHS|$BULK_PATHS" && return 1
            # Read committed objects, not mutable working-tree bytes. Deletions
            # have no object; every added/modified object must be a small blob.
            if git -C "$(git_top)" cat-file -e "$c:$p" 2>/dev/null; then
                [ "$(git -C "$(git_top)" cat-file -t "$c:$p")" = blob ] || return 1
                size="$(git -C "$(git_top)" cat-file -s "$c:$p")" || return 1
                [ "$size" -le "${RALPHIE_MAX_COMMIT_BYTES:-1048576}" ] || return 1
                mode="$(git -C "$(git_top)" ls-tree "$c" -- "$p")" || return 1
                case "$mode" in 120000*)
                    target="$(git -C "$(git_top)" cat-file blob "$c:$p")" || return 1
                    case "$target" in /*|..|../*|*/../*|*/..) return 1;; esac;;
                esac
            fi
        done < "$paths"
        previous="$c"
    done
    return 0
}

git_commit_cycle() {
    # Committed through a PRIVATE index, never the operator's.
    #
    # `git add -A` writes the repository's real index, so a revision the
    # operator had staged with `git add -p` -- and then edited further -- existed
    # only in that index and was destroyed by Ralphie's first commit. Using
    # GIT_INDEX_FILE means the operator's staging area is not read, not written
    # and not restored: it is simply not involved. That also removes the need to
    # detect a half-finished commit and undo it, because there is nothing to
    # undo. `git commit` still honours GIT_INDEX_FILE, so hooks, signing and
    # every other policy the repository sets still apply.
    #
    # Read the six lines below and you have the whole commit path. Each step
    # refuses for exactly one reason, and says which -- but none of them is
    # TRUSTED to say it. Whether a commit actually happened is decided by
    # `record_outcome`, which compares HEAD before and after. That is why a step
    # here may return without explaining itself and still not produce a false
    # green: the claim is checked against the repository, not against the step.
    local msg="$1" idx="$RUN_DIR/index.$$"
    commit_is_permitted     || return 0
    git_identity
    build_commit_index "$idx"        || return 0
    index_holds_our_work_only "$idx" || return 0
    write_commit "$idx" "$msg"       || return 1
    resync_operator_index
    local sha; sha="$(git -C "$PROJECT" rev-parse --short HEAD 2>/dev/null || printf '?')"
    good "committed $sha  $(printf '%s' "$msg" | head -1)"
    event commit ok "$msg" "sha=$sha"
    warn_protected_unsaved
}

warn_protected_unsaved() {
    # A partial save is not a save of the whole working tree. Check for remaining
    # changes, not who made them; the snapshot proves exclusion, not authorship.
    # Only test whether status is empty. Never parse porcelain output for paths.
    local p
    [ -s "$PRE_DIRTY_FILE" ] || return 0
    while IFS= read -r -d '' p; do
        [ -n "$p" ] || continue
        if [ -n "$(git -C "$(git_top)" status --porcelain -- "$p" 2>/dev/null)" ]; then
            warn "protected changes remain unsaved in this commit"
            warn "  review git status and diffs, then manually save the intended changes; pre-existing paths remain excluded for this run"
            return 0
        fi
    done < "$PRE_DIRTY_FILE"
    return 0
}

commit_is_permitted() {
    # The three reasons never to reach for the index at all.
    #
    # Each used to `return 0` silently, which left COMMIT_FAILED at 0 and put
    # the cycle in `pass`: status reported "5 green" against an empty git log,
    # and because the tree really had changed the stall detector never fired.
    if ! git_ready; then
        # Running without version control is a supported MODE -- but only when
        # it was the mode the run STARTED in. Deciding it from the filesystem
        # instead meant an engine that ran `rm -rf .git` mid-run got four green
        # cycles, `status` reported "4 green", and it offered
        # `git reset --hard <sha>` for a repository that no longer existed.
        # The mode is recorded once, at the start, and never re-derived.
        if [ "${GIT_MODE:-repo}" = "none" ]; then
            COMMIT_SKIPPED=1
        else
            COMMIT_FAILED=1
            COMMIT_BLOCKED_WHY="the git repository disappeared during the run"
            err "the git repository is gone - the work is verified but NOT saved"
            event commit blocked "the repository disappeared during the run"
            ask_human "Ralphie started in a git repository and it is no longer there, so verified work could not be committed. The change is on disk. Check whether something in this project removed .git."
        fi
        return 1
    fi
    if ! git_dirty; then
        COMMIT_FAILED=1
        COMMIT_BLOCKED_WHY="the gates passed but nothing in the repository changed"
        return 1
    fi
    # A merge, rebase, cherry-pick or revert in progress is the operator's
    # half-finished operation, and `git commit` concludes it THROUGH ANY INDEX:
    # it writes a two-parent merge commit, removes MERGE_HEAD, and
    # `git merge --abort` then fails with "there is no merge to abort".
    # Measured: the other branch's change was recorded as merged and silently
    # discarded, while the conflict markers were still in the worktree.
    local gd; gd="$(git -C "$PROJECT" rev-parse --git-dir 2>/dev/null || printf '')"
    case "$gd" in ''|/*) ;; *) gd="$PROJECT/$gd";; esac
    if [ -n "$gd" ] && { [ -e "$gd/MERGE_HEAD" ] || [ -e "$gd/CHERRY_PICK_HEAD" ] || \
         [ -e "$gd/REVERT_HEAD" ] || [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]; }; then
        COMMIT_FAILED=1
        COMMIT_BLOCKED_WHY="a merge or rebase was in progress"
        warn "a merge or rebase is in progress - this cycle's work was not committed"
        warn "  finish or abort it, then rerun; the change is safe on disk"
        event commit blocked "a git operation was in progress"
        ask_human "A cycle passed the gates while a merge or rebase was in progress. Committing would have concluded it for you, so Ralphie did not. Finish or abort the operation, then rerun."
        return 1
    fi
    return 0
}

build_commit_index() {
    # A private index holding everything Ralphie may save, and nothing else.
    local idx="$1" p
    rm -f "$idx" 2>/dev/null || true
    # Seed from HEAD so the private index starts as the last commit, not as
    # whatever the operator happens to have staged.
    # Every failure here sets COMMIT_FAILED. Returning without it meant the
    # cycle landed in `pass`: status said "3 green" against a git log holding
    # only `init`, with no commit event, no warning and no question -- and the
    # no-progress streak reset, so it never stalled either. A Git-LFS repo on a
    # machine without git-lfs is enough to trigger it: a required clean filter
    # makes `git add -A` exit 128.
    if git -C "$PROJECT" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
        ( cd "$(git_top)" && GIT_INDEX_FILE="$idx" git read-tree HEAD ) >/dev/null 2>&1 || {
            rm -f "$idx" 2>/dev/null
            COMMIT_FAILED=1
            COMMIT_BLOCKED_WHY="git could not read the current commit into a private index"
            err "git could not prepare a commit - the work is verified but NOT saved"
            event commit refused "git read-tree failed"
            return 1; }
    fi
    # SCOPED TO THE PROJECT. Anchoring the paths was only half the repair: a
    # bare `git add -A` from a subdirectory stages the ENTIRE repository, so
    # Ralphie would still be deciding the fate of files in a parent project it
    # was never pointed at. It commits the directory it was planted in, and
    # nothing above it. Where the two are the same, this is exactly `git add -A`.
    ( cd "$(git_top)" && GIT_INDEX_FILE="$idx" git add -A -- "$(project_prefix)" ) >/dev/null 2>&1 || {
        rm -f "$idx" 2>/dev/null
        COMMIT_FAILED=1
        COMMIT_BLOCKED_WHY="git refused to stage the work"
        err "git could not stage the work - it is verified but NOT saved"
        dim "  a required clean/smudge filter (git-lfs) or a broken hook is the usual cause"
        event commit refused "git add -A failed"
        ask_human "Git could not stage verified work, so nothing was committed. A required clean filter (for example git-lfs not installed) or a broken hook is the usual cause. The change is still on disk."
        return 1; }

    unstage_risky "$idx"
    # The exclusion list lives in the one directory an agent is most likely to
    # tidy away, so it is sealed and the seal is checked HERE -- the last
    # moment before anything can be committed. Missing or altered has to mean
    # "refuse", never "there was nothing to exclude": measured, deleting one
    # file committed the operator's work, right after Ralphie promised on
    # screen that it would not.
    if ! pre_dirty_intact; then
        rm -f "$idx" 2>/dev/null || true
        COMMIT_FAILED=1
        COMMIT_BLOCKED_WHY="the record of your pre-existing changes was gone"
        err "the record of your pre-existing changes is gone - refusing to commit"
        event commit blocked "the pre-dirty snapshot disappeared during the run"
        ask_human "Ralphie could not find its record of the files you had already modified, so it refused to commit anything this cycle. The work is on disk. Rerun to rebuild the record."
        return 1
    fi
    if [ -n "$PRE_DIRTY_FILE" ] && [ -s "$PRE_DIRTY_FILE" ]; then
        while IFS= read -r -d '' p; do
            [ -n "$p" ] || continue
            ( cd "$(git_top)" && GIT_INDEX_FILE="$idx" git reset -q -- "$p" ) >/dev/null 2>&1 || true
        done < "$PRE_DIRTY_FILE"
    fi
    return 0
}

index_holds_our_work_only() {
    # Reads backwards, so plainly: `git diff --cached --quiet` succeeds when the
    # index is EMPTY. So "not quiet" -- the `||` branch -- means there IS
    # something staged, which is the good case, and the function returns 0.
    local idx="$1"
    ( cd "$(git_top)" && GIT_INDEX_FILE="$idx" git diff --cached --quiet ) || return 0
    # The gates passed on a tree that includes the operator's uncommitted
    # edits, but those edits are not Ralphie's to commit -- and when the agent
    # touched the same files, there is nothing left to separate. Say so
    # plainly: the work is real, it is on disk, and it is not saved.
    rm -f "$idx" 2>/dev/null || true
    # An inspected engine commit already saved this cycle's work. An empty
    # private index then means only protected or excluded paths remain.
    [ "${CY_ENGINE_SAVED:-0}" = 1 ] && return 1
    # Counted as a failure, not a pass. Returning 0 here let cycle_record bump
    # pass_count and write `cycle pass` into the append-only ledger for a commit
    # that never happened: `status` reported "11 green" against 4 commits, with
    # 7 `commit blocked` lines in the same ledger.
    COMMIT_FAILED=1
    COMMIT_BLOCKED_WHY="the work is mixed into files you had already modified"
    warn "verified work cannot be committed: it is mixed into files you had already modified"
    warn "  the change is on disk and the gates pass; commit it yourself, or stash your edits and rerun"
    event commit blocked "verified work overlaps the operator's uncommitted changes"
    ask_human "A cycle passed the gates, but its work is in files you had already modified, so Ralphie could not commit it without taking your changes too. Commit it yourself, or stash your edits and rerun."
    return 1
}

write_commit() {
    local idx="$1" msg="$2" cerr="$RUN_DIR/commit-error.$$" cp rc secs
    secs="${COMMIT_TIMEOUT:-120}"
    is_int "$secs" && [ "$secs" -gt 0 ] || secs=120
    set -m 2>/dev/null || true
    { ( cd "$(git_top)" || exit 2; export GIT_INDEX_FILE="$idx"; exec git commit -q -m "$msg" ) >"$cerr" 2>&1 </dev/null & } 2>/dev/null
    cp=$!
    set +m 2>/dev/null || true
    track_pid "$cp"
    watchdog_wait "$cp" "$cerr" 0 "$secs" commit; rc=$?
    untrack_pid "$cp"
    [ "$rc" -ne 124 ] || printf 'Commit timed out after %ss (hook or signing process).\n' "$secs" >> "$cerr"
    if [ "$rc" -eq 0 ]; then
        rm -f "$cerr" "$idx" 2>/dev/null || true
        return 0
    fi
    # git refuses for reasons that have nothing to do with the work: a
    # pre-commit hook, a missing GPG key, a stale index.lock. Reporting
    # "green" three times with an empty git log is the worst of both.
    err "git refused the commit - the work is verified but NOT saved"
    dim "  $(tail_of "$cerr" 400 | tr '\n' ' ' | cut -c1-200)"
    event commit refused "$(tail_of "$cerr" 300)"
    ask_human "Git refused to commit verified work: $(tail_of "$cerr" 200 | tr '\n' ' '). The change is still on disk. A pre-commit hook, a signing key, or a stale .git/index.lock is the usual cause."
    rm -f "$cerr" "$idx" 2>/dev/null || true
    COMMIT_FAILED=1
    return 1
}

resync_operator_index() {
    # HEAD has moved, but the operator's real index still describes the OLD
    # commit, so git would report every committed file as a staged deletion.
    # Re-point those paths at the new HEAD -- and only those: a path the
    # operator had staged is left exactly as they left it, because that
    # revision may exist nowhere else.
    local committed="$RUN_DIR/committed.$$.nul" p
    # --root, or the FIRST commit in a repository lists nothing and the real
    # index is left describing every committed file as a staged deletion for
    # ever -- after which Ralphie claims ownership of every file in the repo.
    # -m, or a merge commit lists nothing for the same reason.
    ( cd "$(git_top)" && git diff-tree -m --root --no-commit-id --name-only -r -z HEAD 2>/dev/null ) > "$committed" 2>/dev/null || : > "$committed"
    while IFS= read -r -d '' p; do
        [ -n "$p" ] || continue
        nul_list_has "$OPERATOR_STAGED" "$p" && continue
        ( cd "$(git_top)" && git reset -q -- "$p" ) >/dev/null 2>&1 || true
    done < "$committed"
    rm -f "$committed" 2>/dev/null || true
}


# ============================================================================
# LAYER 4 - ENGINE
#   The extension point of the whole program.
#
#   An engine is described by one table row and driven through one contract.
#   Ralphie then supplies only the capabilities the engine lacks:
#
#       ralphie_work = required_autonomy - engine_caps
#
#   Capabilities are earned, never granted by name. Prime Agent leads because it
#   measures highest, not because it is hardcoded to. An engine released years
#   from now that scores higher takes the lead automatically, by adding a row.
#
#   CAPABILITIES
#     autonomy   keeps working by itself until the gates pass
#     gates      accepts verification commands and honours them
#     memory     carries durable memory between runs
#     subagents  parallelises internally
#     resume     continues a previous session
#     skills     loads project skill files
#     json       emits machine-readable results
#     stream     writes progress to stdout while it works, rather than buffering
#                the whole answer until the end
#     usage      records real token and cost figures in a machine-readable form
#                that Ralphie can read back afterwards
# ============================================================================

#            name        | command     | answer   | capabilities
ENGINE_TABLE='
prime-agent  | prime-agent | stdout | autonomy gates memory subagents resume skills json usage
claude       | claude      | stdout | subagents resume skills json
codex        | codex       | file   | resume json stream
'

engine_names() { printf '%s\n' "$ENGINE_TABLE" | grep -E '\|' | cut -d'|' -f1 | tr -d ' ' | grep . ; [ -n "${RALPHIE_ENGINE_CMD:-}" ] && printf 'custom\n' || true; }

engine_field() {
    # engine_field <name> <1=cmd|2=answer|3=caps>
    local name="$1" idx="$2" row
    if [ "$name" = "custom" ]; then
        case "$idx" in
            1) printf '%s' "${RALPHIE_ENGINE_CMD:-}";;
            2) printf '%s' "${RALPHIE_ENGINE_ANSWER:-stdout}";;
            3) printf '%s' "${RALPHIE_ENGINE_CAPS:-}";;
        esac
        return 0
    fi
    row="$(printf '%s\n' "$ENGINE_TABLE" | grep -E "^[[:space:]]*${name}[[:space:]]*\|" | head -1)"
    [ -n "$row" ] || return 1
    printf '%s' "$(trim "$(printf '%s' "$row" | cut -d'|' -f$((idx+1)))")"
}

engine_cmd()    { engine_field "$1" 1; }
engine_answer() { engine_field "$1" 2; }
engine_caps()   { engine_field "$1" 3; }
engine_has()    { case " $(engine_caps "$1") " in *" $2 "*) return 0;; *) return 1;; esac; }
engine_score()  { printf '%s' "$(engine_caps "$1" | wc -w | tr -d ' ')"; }

engine_exe() {
    # A custom engine is either one executable whose path may contain spaces, or
    # a command line with arguments. Guessing wrong truncates "/opt/my tools/ai"
    # to "/opt/my". Test the whole string first, then fall back to its first word.
    local c="$1"
    if [ -x "$c" ]; then printf '%s' "$c"; else printf '%s' "${c%% *}"; fi
}

engine_present() {
    local c; c="$(engine_cmd "$1" 2>/dev/null)" || return 1
    [ -n "$c" ] || return 1
    [ -x "$c" ] && return 0
    have "$(engine_exe "$c")"
}

ENGINE_LIVE_CACHE=""
engine_live() {
    # Memoised for the life of the process: doctor asked twice per engine, once
    # to print a status and once to choose, paying two probe timeouts each.
    case "$ENGINE_LIVE_CACHE" in
        *" ok:$1 "*)   return 0;;
        *" dead:$1 "*) return 1;;
    esac
    if engine_live_probe "$1"; then ENGINE_LIVE_CACHE="$ENGINE_LIVE_CACHE ok:$1 "; return 0; fi
    ENGINE_LIVE_CACHE="$ENGINE_LIVE_CACHE dead:$1 "
    return 1
}

engine_live_probe() {
    # Cheapest possible liveness check: does the binary answer at all? Anything
    # heavier (an auth round trip, a token spend) is refused here on principle.
    local name="$1" c t e; c="$(engine_cmd "$name")"; t="$(timeout_cmd)"
    engine_present "$name" || return 1
    e="$(engine_exe "$c")"
    if [ -n "$t" ]; then "$t" 15 "$e" --version >/dev/null 2>&1
    else "$e" --version >/dev/null 2>&1; fi
}

engine_check_model() {
    # Prime Agent owns selector semantics: provider/id, patterns and thinking
    # suffixes cannot be validated by substring search in its display table.
    # Pass the explicit selector unchanged and let the engine resolve or reject
    # it. Do not claim that a missing table substring means default fallback.
    [ "$1" = "prime-agent" ] && [ -n "${2:-}" ] &&
        dbg "Prime Agent will resolve model selector '$2'"
    return 0
}

engine_pick() {
    # Highest capability score among engines actually installed here. An explicit
    # request always wins, and fails loudly rather than silently substituting:
    # silent substitution is how an operator loses a night to the wrong model.
    local want="${1:-}" best="" best_score=-1 n s
    if [ -n "$want" ]; then
        engine_present "$want" || { err "engine '$want' is not installed"; return 1; }
        printf '%s' "$want"; return 0
    fi
    # Configuring a custom engine IS an explicit choice. Ranking it against the
    # installed engines let a capability score overrule the operator, silently
    # sending the work -- and the bill -- to a provider they had just told
    # Ralphie not to use.
    if [ -n "${RALPHIE_ENGINE_CMD:-}" ]; then
        engine_present custom || { err "custom engine is not installed: $RALPHIE_ENGINE_CMD"; return 1; }
        printf 'custom'; return 0
    fi
    # Two passes. A responsive engine always beats an unresponsive one, whatever
    # its capability score: doctor used to report "installed but not responding"
    # and then select that very engine on the next line.
    local live_best="" live_score=-1
    while IFS= read -r n; do
        [ -z "$n" ] && continue
        engine_present "$n" || continue
        s="$(engine_score "$n")"
        if [ "$s" -gt "$best_score" ]; then best="$n"; best_score="$s"; fi
        if engine_live "$n" && [ "$s" -gt "$live_score" ]; then live_best="$n"; live_score="$s"; fi
    done <<EOF
$(engine_names)
EOF
    [ -n "$live_best" ] && { printf '%s' "$live_best"; return 0; }
    [ -n "$best" ] || return 1
    printf '%s' "$best"
}

engine_fallbacks() {
    # Every installed engine except the active one, best first.
    local active="$1" n
    engine_names | while IFS= read -r n; do
        [ -z "$n" ] || [ "$n" = "$active" ] && continue
        engine_present "$n" && printf '%s %s\n' "$(engine_score "$n")" "$n"
    done | sort -rn | awk '{print $2}'
}

# --- argv construction -------------------------------------------------------
# ENGINE_ARGV is rebuilt for every call. Nothing is cached, because a colony
# upgrades its tools underneath a running loop and must not be surprised.

ENGINE_ARGV=()
ENGINE_ENV=()

engine_build() {
    # engine_build <name> <mode:autonomous|oneshot> <out_file>
    local name="$1" mode="$2" out="$3" g
    ENGINE_ARGV=(); ENGINE_ENV=()
    # A model id belongs to one provider's namespace. Passing the operator's
    # --model to a BORROWED fallback engine asks it for a model it has never
    # heard of, which either fails or silently runs something else.
    local MODEL="${MODEL:-}"
    [ -n "${ENGINE:-}" ] && [ "$name" != "$ENGINE" ] && MODEL=""

    case "$name" in
      prime-agent)
        ENGINE_ARGV=( "$(engine_cmd "$name")" -p --mode text --cwd "$PROJECT" )
        # --offline suppresses the release-manifest fetch at startup. It does not
        # make inference offline; it just stops every cycle paying for a version
        # check nobody asked for.
        ENGINE_ARGV+=( --offline )
        is_true "${YOLO:-1}" || dbg "--no-yolo has no effect on prime-agent: it has no permission-bypass flag"
        [ -n "${MODEL:-}" ]    && ENGINE_ARGV+=( --model "$MODEL" )
        [ -n "${THINKING:-}" ] && ENGINE_ARGV+=( --thinking "$THINKING" )
        # Sessions are leased by path. Two processes sharing one session file
        # both fail with "Session is already active", so each run gets its own
        # session directory and concurrent Ralphies never collide.
        if is_true "${RALPHIE_ENGINE_SESSION:-1}"; then
            ENGINE_ARGV+=( --session-dir "$RUN_DIR/sessions/$(state_get run_id run)" )
        else
            ENGINE_ARGV+=( --no-session )
        fi
        if [ "$mode" = "autonomous" ]; then
            ENGINE_ARGV+=( --autonomous )
            while IFS= read -r g; do
                [ -n "$g" ] && ENGINE_ARGV+=( --autonomous-gate "$g" )
            done <<EOF
$(gates_list)
EOF
            ENGINE_ARGV+=( --autonomous-max-turns "${ENGINE_MAX_TURNS:-24}" )
            ENGINE_ARGV+=( --autonomous-max-continuations "${ENGINE_MAX_CONT:-6}" )
            # The engine's own deadline must never outlive the operator's.
            ENGINE_ARGV+=( --autonomous-timeout-ms "$(( $(budget_cap "${ENGINE_TIMEOUT:-2400}") * 1000 ))" )
            [ -n "${ENGINE_MAX_TOKENS:-}" ] && ENGINE_ARGV+=( --autonomous-max-tokens "$ENGINE_MAX_TOKENS" )
        fi
        ;;
      claude)
        ENGINE_ARGV=( "$(engine_cmd "$name")" -p )
        [ -n "${MODEL:-}" ] && ENGINE_ARGV+=( --model "$MODEL" )
        # Autonomy is the point of an unattended loop; without it every cycle
        # stalls on a permission prompt no human is present to answer.
        if is_true "${YOLO:-1}"; then
            ENGINE_ARGV+=( --dangerously-skip-permissions )
            ENGINE_ENV=( IS_SANDBOX=1 )
        fi
        ;;
      codex)
        ENGINE_ARGV=( "$(engine_cmd "$name")" exec )
        [ -n "${MODEL:-}" ]    && ENGINE_ARGV+=( --model "$MODEL" )
        [ -n "${THINKING:-}" ] && ENGINE_ARGV+=( -c "model_reasoning_effort=\"$THINKING\"" )
        is_true "${YOLO:-1}" && ENGINE_ARGV+=( --dangerously-bypass-approvals-and-sandbox )
        ENGINE_ARGV+=( - --output-last-message "$out" )
        ;;
      custom)
        is_true "${YOLO:-1}" || dbg "--no-yolo has no effect on a custom engine"
        if [ -x "${RALPHIE_ENGINE_CMD:-}" ]; then
            ENGINE_ARGV=( "$RALPHIE_ENGINE_CMD" )
        else
            # shellcheck disable=SC2206
            ENGINE_ARGV=( ${RALPHIE_ENGINE_CMD} )
        fi
        ;;
      *) err "unknown engine: $name"; return 1;;
    esac
    # A bash function returns the status of its last command. Several branches
    # above end in a conditional `&&` that is legitimately false, which would
    # silently report "cannot build argv" and send the loop to a weaker engine.
    # This is not redundant.
    return 0
}

# --- failure classification --------------------------------------------------
# Retrying a permanent failure burns budget and never succeeds. Not retrying a
# transient one throws away a run that would have worked on the next attempt.
# Getting this wrong in either direction is expensive, so it is explicit.

FAIL_TRANSIENT='rate.?limit|overloaded|too many requests|429|502|503|504|backend error|connection (refused|reset)|ECONNRESET|ETIMEDOUT|EAI_AGAIN|socket hang up|timed? ?out|temporarily unavailable|internal server error'
FAIL_PERMANENT='invalid.{0,10}api.?key|authentication.{0,10}failed|unauthorized|401|403|permission denied|insufficient.{0,10}(quota|credit|balance)|model.{0,10}not.{0,10}found|no such model|account.{0,10}(suspended|disabled)'

classify_failure() {
    # classify_failure <exit_code> <log_file> -> transient|permanent|resource-limit|unknown
    local rc="$1" log="$2"
    case "$rc" in 125) printf 'resource-limit'; return 0;; 124|137|143) printf 'transient'; return 0;; esac
    if [ -f "$log" ]; then
        if tail -c 20000 "$log" 2>/dev/null | grep -qiE "$FAIL_PERMANENT"; then printf 'permanent'; return 0; fi
        if tail -c 20000 "$log" 2>/dev/null | grep -qiE "$FAIL_TRANSIENT"; then printf 'transient'; return 0; fi
    fi
    # An unexplained non-zero exit is usually a crash, and a crash is usually
    # worth exactly one more try.
    printf 'unknown'
}

answer_is_usable() {
    # An engine that logged in through a browser, hit a captcha, or returned an
    # error page will happily hand back HTML. Treat that as no answer at all.
    local f="$1"
    [ -f "$f" ] || return 1
    [ -s "$f" ] || return 1
    local n; n="$(file_bytes "$f")"
    [ "$n" -ge "${MIN_ANSWER_BYTES:-2}" ] || return 1
    # An engine that returned only blank lines has said nothing. Counting bytes
    # alone accepted "   \n\n  \n" as a real answer and let the cycle proceed
    # as though the engine had done work.
    [ -n "$(tr -d '[:space:]' < "$f" 2>/dev/null | head -c 1)" ] || return 1
    head -c 2000 "$f" | grep -qiE '<!doctype html|<html[ >]|sign in to continue|please (log|sign) in|authentication required' && return 1
    return 0
}

# --- invocation --------------------------------------------------------------

engine_run() {
    # engine_run <name> <mode> <prompt_file> <log_file> <out_file>
    # Returns 0 with a usable answer in <out_file>, or non-zero with a reason in
    # ENGINE_REASON. Handles retries, watchdogs and process trees so no caller
    # ever has to think about them again.
    #
    #   0 answer  1 out of attempts  2 cannot start  3 permanent  4 out of time
    #   5 output resource-limit
    local name="$1" mode="$2" prompt="$3" log="$4" out="$5"
    local attempt=1 max="${ENGINE_RETRIES:-3}" rc cls
    ENGINE_REASON=""
    ENGINE_RESOURCE_LIMIT=0
    [ -f "$prompt" ] || { ENGINE_REASON="prompt missing"; return 2; }
    engine_present "$name" || { ENGINE_REASON="engine not installed"; return 2; }
    ensure_dirs

    while [ "$attempt" -le "$max" ]; do
        # The operator's wall clock outranks the retry policy. Starting a call
        # that cannot finish before the deadline spends real money on an answer
        # that is guaranteed to be killed before it arrives.
        if budget_expired; then
            ENGINE_REASON="$name: the run's time limit expired"
            event engine limit "$ENGINE_REASON" "engine=$name" "attempt=$attempt"
            return 4
        fi
        engine_build "$name" "$mode" "$out" || { ENGINE_REASON="cannot build argv"; return 2; }
        event engine start "$name attempt $attempt/$max ($mode)" "engine=$name" "attempt=$attempt"

        local started; started="$(now_epoch)"
        engine_invoke "$name" "$prompt" "$log" "$out"; rc=$?
        local took; took="$(secs_since "$started")"

        if engine_answered "$name" "$mode" "$rc" "$log" "$out" "$took"; then return 0; fi

        cls="$(classify_failure "$rc" "$log")"
        ENGINE_REASON="$name exit $rc ($cls)"
        [ "$rc" -eq 0 ] && ENGINE_REASON="$name returned no usable answer"
        warn "$ENGINE_REASON"
        event engine fail "$ENGINE_REASON" "engine=$name" "class=$cls" "code=$rc"

        retain_engine_output "$log"
        retain_engine_output "$out"
        if [ "$cls" = "resource-limit" ]; then
            ENGINE_RESOURCE_LIMIT=1
            ENGINE_REASON="$name: output resource-limit exceeded. Not retrying."
            return 5
        fi
        if [ "$cls" = "permanent" ]; then
            ENGINE_REASON="$name: permanent failure (auth, quota or model). Not retrying."
            return 3
        fi
        attempt=$(( attempt + 1 ))
        # Backing off into an expired budget is time spent buying nothing.
        if [ "$attempt" -le "$max" ] && ! budget_expired; then
            sleep "$(( (attempt - 1) * ${ENGINE_BACKOFF:-5} ))"
        fi
    done
    ENGINE_REASON="$name failed $max attempts"
    return 1
}

engine_invoke() {
    # One attempt: launch, guard, collect. Everything about processes and files
    # lives here so the retry policy above can be read on its own.
    local name="$1" prompt="$2" log="$3" out="$4"
    local rc idle slice raw pid ceiling
    ceiling="${ENGINE_OUTPUT_MAX_BYTES:-16777216}"
    # A finite positive ceiling is required; invalid values restore the default.
    is_int "$ceiling" && [ "$ceiling" -gt 0 ] || ceiling=16777216
    ensure_dirs
    # A bare `: > "$log"` printed bash's own error to the operator's screen --
    # "./ralphie.sh: line 2567: /path/.ralphie/log/cycle-2.log: Permission
    # denied" -- an internal line number and an absolute path, four times a run,
    # from a program whose whole promise is that it explains itself. The cycle
    # log is a convenience; losing it must never look like a crash.
    if ! { : > "$log"; } 2>/dev/null; then
        warn "cannot write the cycle log ($(basename "$log")) - continuing without it"
        log="/dev/null"
    fi
    if ! { : > "$out"; } 2>/dev/null; then
        # The answer file is NOT optional: without it there is nothing to read
        # back, so this fails the attempt honestly instead of half-running.
        err "cannot write the engine's answer file: $out"
        return 1
    fi

    # The engine writes its raw output OUTSIDE the project. An agent with full
    # tool authority may delete .ralphie/ while it runs; the file descriptor
    # survives but the path does not, and the answer is lost with it.
    raw="$(mktemp "${TMPDIR:-/tmp}/ralphie.raw.XXXXXX" 2>/dev/null)" || raw="${TMPDIR:-/tmp}/ralphie.raw.$$"
    dbg "engine: ${ENGINE_ARGV[*]+"${ENGINE_ARGV[*]}"}"

    # One call may not outlast what is left of the run. Without this the budget
    # was only honoured between cycles, so `--minutes 1` waited out a full
    # ENGINE_TIMEOUT before it was allowed to notice.
    slice="$(budget_cap "${ENGINE_TIMEOUT:-2400}")"
    # bash 3.2 with `set -u` treats a naked empty-array expansion as an unbound
    # variable and aborts. The `[@]+` guard is not decoration.
    set -m 2>/dev/null || true
    (
        cd "$PROJECT" || exit 2
        set -- ${ENGINE_ARGV[@]+"${ENGINE_ARGV[@]}"}
        if [ "${#ENGINE_ENV[@]}" -gt 0 ]; then set -- env "${ENGINE_ENV[@]}" "$@"; fi
        exec "$@" < "$prompt"
    ) > "$raw" 2>&1 &
    pid=$!; track_pid "$pid"
    set +m 2>/dev/null || true

    # Only an engine that streams can be judged by its silence. `prime-agent -p`
    # and `claude -p` buffer the whole answer and print it at the end, so a
    # healthy run emits nothing for many minutes. Measured the hard way: a
    # working self-improvement run was killed at exactly ten minutes of silence.
    idle=0
    engine_has "$name" stream && idle="${ENGINE_IDLE_TIMEOUT:-600}"
    # Always enforce the call limit, even without a run deadline or timeout(1).
    watchdog_wait "$pid" "$raw" "$idle" "$slice" engine "$ceiling" "$out"; rc=$?
    untrack_pid "$pid"

    # The engine may have deleted Ralphie's working directory while it ran. Heal
    # before writing the answer, or a tidy-minded agent costs a whole cycle and
    # three retries for no reason.
    ensure_dirs
    # Do not duplicate an oversized capture or let a partial report claim done.
    if [ "$rc" -eq 125 ]; then
        retain_engine_output "$raw"
        ensure_own_file "$out" "engine answer"
        { : > "$out"; } 2>/dev/null || true
    fi
    # stdout carries the answer for most engines; codex writes it to a file.
    cp -f "$raw" "$log" 2>/dev/null || true
    if [ "$rc" -ne 125 ] && [ "$(engine_answer "$name")" = "stdout" ]; then
        # Verified: prime-agent's text mode always opens with two blank lines.
        sed -e '/./,$!d' "$raw" > "$out" 2>/dev/null || cp -f "$raw" "$out" 2>/dev/null || true
    fi
    rm -f "$raw"
    return "$rc"
}

engine_answered() {
    # Did this attempt produce something Ralphie can use? Two different things
    # count as yes, and separating them from the retry policy is the point.
    local name="$1" mode="$2" rc="$3" log="$4" out="$5" took="$6"

    if [ "$rc" -eq 0 ] && answer_is_usable "$out"; then
        event engine ok "$name finished in $(human_secs "$took")" "engine=$name" "seconds=$took"
        return 0
    fi

    # A self-driving engine exits non-zero when it gave up on its own gates.
    # That is a report about the PROJECT, not a malfunction, and Ralphie re-runs
    # the gates itself anyway; retrying would pay twice for the same news.
    # Only an UNEXPLAINED non-zero exit qualifies: a 503 or a rate limit in the
    # same position was being recorded as success and never retried.
    if [ "$mode" = "autonomous" ] && answer_is_usable "$out" \
       && [ "$(classify_failure "$rc" "$log")" = "unknown" ]; then
        event engine ok "$name self-reported unmet gates in $(human_secs "$took")" "engine=$name" "seconds=$took" "code=$rc"
        dbg "engine exit $rc in autonomous mode; gates decide, not the exit code"
        return 0
    fi
    return 1
}

watchdog_wait() {
    # watchdog_wait <pid> <log> [idle_secs] [hard_secs] [label] [bytes] [answer]
    # An engine that stops producing output has almost certainly hung on a
    # network read. Waiting out a 40 minute wall clock for it wastes the one
    # resource that cannot be refunded. Kill it and let the retry path work.
    # <hard_secs> bounds engines, gates and commits on every host. Allow one
    # polling second plus two seconds for TERM before KILL. Both limits return
    # 124, the code the
    # failure classifier already reads as "transient, and not the engine's
    # fault".
    local pid="$1" log="$2" idle="${3:-0}" hard="${4:-0}"
    local last_size=0 quiet=0 waited=0 size label="${5:-engine}"
    local ceiling="${6:-0}" answer="${7:-/dev/null}" rc
    is_int "$ceiling" || ceiling=0
    is_int "$idle" || idle=0
    is_int "$hard" || hard=0
    if [ "$idle" -le 0 ] && [ "$hard" -le 0 ] && [ "$ceiling" -le 0 ]; then wait "$pid"; return $?; fi
    while kill -0 "$pid" 2>/dev/null; do
        # Let instant gates finish without charging them a whole polling second.
        # BSD/macOS and GNU sleep both accept fractions. Split only the first
        # tick: long jobs keep the same one-second accounting and timeout bound.
        if [ "$waited" -eq 0 ]; then
            sleep 0.05
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.95
        else
            sleep 1
        fi
        kill -0 "$pid" 2>/dev/null || break
        waited=$((waited+1))
        size="$(file_bytes "$log")"
        if [ "$ceiling" -gt 0 ] && [ "$((size + $(file_bytes "$answer")))" -gt "$ceiling" ]; then
            warn "$label output resource-limit exceeded ($ceiling bytes) - terminating"
            terminate_tree "$pid"
            wait "$pid" 2>/dev/null || true
            return 125
        fi
        if [ "$size" -gt "$last_size" ]; then last_size="$size"; quiet=0
        else quiet=$((quiet+1)); fi
        if [ "$idle" -gt 0 ] && [ "$quiet" -ge "$idle" ]; then
            warn "$label produced no output for $(human_secs "$idle") - terminating"
            terminate_tree "$pid"
            wait "$pid" 2>/dev/null || true
            return 124
        fi
        if [ "$hard" -gt 0 ] && [ "$waited" -ge "$hard" ]; then
            warn "$label reached its $(human_secs "$hard") limit - terminating"
            terminate_tree "$pid"
            wait "$pid" 2>/dev/null || true
            return 124
        fi
    done
    wait "$pid"; rc=$?
    # A buffered or fast producer can finish between polls. Its oversized
    # answer must still fail, even if it contains a complete-looking report.
    if [ "$ceiling" -gt 0 ] && [ "$(( $(file_bytes "$log") + $(file_bytes "$answer") ))" -gt "$ceiling" ]; then
        warn "$label output resource-limit exceeded ($ceiling bytes)"
        return 125
    fi
    return "$rc"
}

retain_engine_output() {
    # Only consumed captures, never prompts or provider session records.
    # Keep at most 256 KiB, including the marker, after parsing/classification.
    local f="$1" tmp
    [ -f "$f" ] && [ "$(file_bytes "$f")" -gt 262144 ] || return 0
    ensure_own_file "$f" "engine capture"
    tmp="$(mktemp "${TMPDIR:-/tmp}/ralphie.tail.XXXXXX" 2>/dev/null)" || return 0
    if { printf '[Ralphie: output truncated; retained tail follows]\n'; tail -c 262080 "$f"; } > "$tmp"; then
        cat "$tmp" > "$f" 2>/dev/null || warn "cannot trim engine capture: $(basename "$f")"
    fi
    rm -f "$tmp"
    return 0
}

read_engine_usage() {
    # Real figures, taken from the engine's own session record. Never estimated.
    # The previous version of this program guessed tokens as bytes/4 and printed
    # the result as if it were fact; a confident wrong number is worse than no
    # number, because people budget against it.
    #
    # It needs a real JSON parser. Hand-rolling one out of grep and sed would be
    # exactly the kind of fragile cleverness this program exists to avoid, so if
    # no parser is present Ralphie simply reports nothing and says why.
    engine_has "$ENGINE" usage || return 0
    # THIS RUN'S session directory, not every retained one. `$RUN_DIR/sessions`
    # keeps up to RALPHIE_KEEP_RUNS previous runs, so summing all of it charged
    # this run for work five runs old: 15 calls that really cost 1,500 tokens
    # and $0.03 were reported as "tokens 4500 ... (1500 this run)" and
    # "cost 0.150000 ... for this run". The whole point of these numbers is that
    # they are MEASURED; a confidently wrong one is worse than none at all.
    local dir="$RUN_DIR/sessions/$(state_get run_id run)" out
    [ -d "$dir" ] || return 0
    have python3 || { dbg "no python3: engine usage cannot be read"; return 0; }
    out="$(python3 - "$dir" <<'PY' 2>/dev/null
import json, os, sys
tok = 0.0; cost = 0.0
for root, _dirs, files in os.walk(sys.argv[1]):
    for name in files:
        if not name.endswith(".jsonl"):
            continue
        try:
            records = []
            with open(os.path.join(root, name), "r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        rec = json.loads(line)
                    except ValueError:
                        continue
                    if isinstance(rec, dict):
                        records.append(rec)
            # Prime Agent v0.9.5 replays the latest aggregate onto the target
            # assistant, by entry ID. Each aggregate already includes earlier
            # children (and their descendants); adding attribution rows would
            # double-charge them. IDs are local to this session file.
            assistants = {}
            for rec in records:
                msg = rec.get("message")
                if (rec.get("type") == "message" and isinstance(msg, dict)
                        and msg.get("role") == "assistant" and isinstance(rec.get("id"), str)):
                    assistants[rec["id"]] = msg
            for rec in records:
                if rec.get("type") != "child_usage_attributed":
                    continue
                target = rec.get("targetId")
                msg = assistants.get(target) if isinstance(target, str) else None
                if msg is not None:
                    msg["usage"] = rec.get("aggregateUsage")
            for rec in records:
                msg = rec.get("message")
                usage = msg.get("usage") if isinstance(msg, dict) else None
                if not isinstance(usage, dict):
                    continue
                total = usage.get("totalTokens")
                if type(total) in (int, float):
                    tok += total
                c = usage.get("cost")
                if isinstance(c, dict) and type(c.get("total")) in (int, float):
                    cost += c["total"]
        except OSError:
            continue
print("%d %.6f" % (int(tok), cost))
PY
)" || return 0
    [ -n "$out" ] || return 0
    local now_tok now_cost prev_tok
    now_tok="${out%% *}"; now_cost="${out##* }"
    is_int "$now_tok" || return 0
    prev_tok="$(json_num run_tokens)"; is_int "$prev_tok" || prev_tok=0
    # Only the delta is added to the lifetime total: the session directory holds
    # the whole run, and it is re-read every cycle.
    [ "$now_tok" -ge "$prev_tok" ] && state_bump tokens_spent "$(( now_tok - prev_tok ))"
    state_set run_tokens "$now_tok"
    state_set run_cost "$now_cost"
    USAGE_NOTE="$now_tok tokens"
    case "$now_cost" in 0.000000|0|"") ;; *) USAGE_NOTE="$USAGE_NOTE, \$$now_cost";; esac
    dim "  used    $USAGE_NOTE this run"
}

engine_run_with_fallback() {
    # A colony cannot wait for a human to notice that one provider is down.
    local mode="$1" prompt="$2" log="$3" out="$4" alt
    CYCLE_ENGINE="$ENGINE"
    if engine_run "$ENGINE" "$mode" "$prompt" "$log" "$out"; then return 0; fi
    local first_reason="$ENGINE_REASON"
    [ "${ENGINE_RESOURCE_LIMIT:-0}" = 1 ] && return 1
    # A budget that has expired will not be any less expired for the next
    # engine. Falling back here would spend time the operator does not have.
    if budget_expired; then return 1; fi
    # An operator who named an engine chose it for a reason - cost, privacy, a
    # provider agreement, an offline box. Quietly spending money on a different
    # engine instead is never the helpful thing to do.
    if is_true "${ENGINE_EXPLICIT:-0}"; then
        dbg "engine was named explicitly; not falling back"
        return 1
    fi
    while IFS= read -r alt; do
        [ -z "$alt" ] && continue
        warn "falling back to engine '$alt'"
        event engine fallback "from $ENGINE to $alt: $first_reason" "from=$ENGINE" "to=$alt"
        # A weaker engine cannot self-drive; degrade the mode with the engine.
        local m="$mode"
        if [ "$m" = "autonomous" ] && ! { engine_has "$alt" autonomy && engine_has "$alt" gates; }; then m="oneshot"; fi
        if engine_run "$alt" "$m" "$prompt" "$log" "$out"; then
            # Used for THIS cycle only. Making the demotion permanent meant a
            # single rate limit sent every later cycle to a weaker engine, in a
            # weaker mode, for the rest of the run.
            CYCLE_ENGINE="$alt"
            event engine borrowed "used $alt for this cycle; $ENGINE is still preferred" "used=$alt"
            return 0
        fi
        [ "${ENGINE_RESOURCE_LIMIT:-0}" = 1 ] && return 1
    done <<EOF
$(engine_fallbacks "$ENGINE")
EOF
    ENGINE_REASON="${first_reason:-no engine could run}"
    return 1
}

# ============================================================================
# LAYER 5 - LOOP
#   observe -> decide -> act -> verify -> record -> learn
#
#   Two rules give this loop its character.
#
#   ANTI-WASTE: never pay a model for something a shell command already knows.
#   Everything in the brief below is gathered by git, grep and the gates. The
#   engine is asked only for judgement, which is the one thing it alone has.
#
#   EVIDENCE OVER ASSERTION: the engine's own claim of success changes nothing.
#   Ralphie re-runs the gates itself, every cycle, and believes only those.
# ============================================================================

# Objective acceptance is a completion condition, never a health gate. The
# durable state names the required config digest, independent of log retention.
# The config is a second presence witness: losing either file fails closed.
# This detects damage, not a hostile same-user actor rewriting both files.
# Referenced scripts remain mutable.
ACCEPT_ARG=""; ACCEPT_EXPLICIT=0; ACCEPT_CMD=""; ACCEPT_BIND=""
ACCEPT_WORK=0; ACCEPT_PASS=0; ACCEPT_BROKEN=0

acceptance_latest() {
    state_get acceptance_binding ''
}

acceptance_bind() {
    # Publish the requirement before the config. Verify persistence because
    # state_set is best-effort on an unwritable state directory.
    state_set acceptance_binding "$1"
    [ "$(acceptance_latest)" = "$1" ] || { acceptance_error; return 1; }
    event acceptance binding "$1"
}

objective_identity() {
    # Explicit text/spec identity is the exact input, not OBJECTIVE.md's
    # presentation newline. Resume reuses the identity set_objective saved.
    if [ -n "${OBJECTIVE:-}" ]; then printf '%s' "$OBJECTIVE" | sha_of
    else state_get objective_hash ''; fi
}

acceptance_error() {
    ACCEPT_BROKEN=1; ACCEPT_PASS=0
    err "acceptance configuration is missing or damaged; supply --accept again or set a new objective"
    event acceptance invalid "acceptance configuration is missing or damaged"
    return 1
}

acceptance_intact() {
    [ -n "$ACCEPT_BIND" ] || return 0
    [ "$ACCEPT_BROKEN" = 0 ] && [ -f "$HOME_DIR/acceptance" ] &&
        [ ! -L "$HOME_DIR/acceptance" ] && [ -r "$HOME_DIR/acceptance" ] &&
        [ "$(sha_of < "$HOME_DIR/acceptance")" = "$ACCEPT_BIND" ] &&
        [ "$(acceptance_latest)" = "$ACCEPT_BIND" ] || acceptance_error
}

acceptance_prepare() {
    local latest obj reset=0 stored="" cmd="" conf digest
    latest="$(acceptance_latest)"
    obj="$(objective_identity)"
    ACCEPT_CMD=""; ACCEPT_BIND=""; ACCEPT_WORK=0; ACCEPT_PASS=0; ACCEPT_BROKEN=0
    local previous="${ACCEPT_OLD_OBJECTIVE:-}"
    if [ -z "$previous" ] && [ -f "$HOME_DIR/acceptance" ] && [ ! -L "$HOME_DIR/acceptance" ]; then
        previous="$(sed -n '3p' "$HOME_DIR/acceptance")"
    fi
    if [ -n "${OBJECTIVE:-}" ] && [ "$obj" != "$previous" ]; then reset=1; fi
    # A missing binding must not turn an existing config into an optional one.
    if [ -z "$latest" ] && { [ -e "$HOME_DIR/acceptance" ] || [ -L "$HOME_DIR/acceptance" ]; }; then
        if [ "$reset" = 0 ] && [ "$ACCEPT_EXPLICIT" = 0 ]; then acceptance_error; return 1; fi
        latest=missing
    fi
    if [ -n "$latest" ] && [ "$latest" != none ]; then
        if [ -f "$HOME_DIR/acceptance" ] && [ ! -L "$HOME_DIR/acceptance" ] &&
           [ -r "$HOME_DIR/acceptance" ] && [ "$(sha_of < "$HOME_DIR/acceptance")" = "$latest" ]; then
            stored="$(sed -n '3p' "$HOME_DIR/acceptance")"
            cmd="$(sed -n '4p' "$HOME_DIR/acceptance")"
            [ "$(sed -n '1p' "$HOME_DIR/acceptance")" = 'ralphie-acceptance-v1' ] &&
                [ "$(wc -l < "$HOME_DIR/acceptance" | tr -d ' ')" = 4 ] &&
                [ -n "${cmd//[[:space:]]/}" ] || stored="invalid"
        fi
        if [ "$reset" = 0 ] && [ "$ACCEPT_EXPLICIT" = 0 ]; then
            [ "$stored" = "$obj" ] || { acceptance_error; return 1; }
            ACCEPT_CMD="$cmd"; ACCEPT_BIND="$latest"
        fi
    fi
    if [ "$ACCEPT_EXPLICIT" = 1 ]; then
        if [ "$reset" = 0 ] && [ "$stored" = "$obj" ] && [ "$cmd" = "$ACCEPT_ARG" ]; then
            ACCEPT_CMD="$cmd"; ACCEPT_BIND="$latest"
        else
            # Publish the requirement BEFORE the file. An interruption fails
            # closed on resume rather than silently dropping a new condition.
            conf="$(printf 'ralphie-acceptance-v1\n%s\n%s\n%s' "$(rand_token)" "$obj" "$ACCEPT_ARG")"
            digest="$(printf '%s\n' "$conf" | sha_of)"
            acceptance_bind "$digest" || return 1
            ensure_own_file "$HOME_DIR/acceptance" "acceptance configuration"
            [ ! -L "$HOME_DIR/acceptance" ] || { acceptance_error; return 1; }
            printf '%s\n' "$conf" > "$HOME_DIR/acceptance" || { acceptance_error; return 1; }
            ACCEPT_CMD="$ACCEPT_ARG"; ACCEPT_BIND="$digest"
        fi
    elif [ "$reset" = 1 ] && [ -n "$latest" ] && [ "$latest" != none ]; then
        acceptance_bind none || return 1
    fi
    if [ -n "$ACCEPT_BIND" ]; then
        acceptance_intact || return 1
        if [ "$(state_get acceptance_work '')" = "$ACCEPT_BIND" ]; then ACCEPT_WORK=1; fi
    fi
    return 0
}

acceptance_verify() {
    [ -n "$ACCEPT_BIND" ] || return 0
    ACCEPT_PASS=0
    acceptance_intact || return 0
    [ "$GATES_GREEN" = yes ] && [ "${GATES_NONE:-0}" != 1 ] &&
        [ "$CY_MAY_COMMIT" = 1 ] || return 0
    local out rc=0
    out="$LOG_DIR/acceptance-$CY_N.log"
    ensure_own_file "$out" "acceptance evidence"
    gate_exec "$ACCEPT_CMD" "$out" "${GATE_TIMEOUT:-900}" || rc=$?
    acceptance_intact || return 0
    local lmax="${GATE_LOG_MAX:-262144}"
    if [ "$(file_bytes "$out")" -gt "$lmax" ]; then
        tail -c "$lmax" "$out" > "$out.trim" 2>/dev/null &&
            mv -f "$out.trim" "$out" 2>/dev/null || rm -f "$out.trim" 2>/dev/null
    fi
    if [ "$rc" = 0 ]; then
        ACCEPT_PASS=1; event acceptance pass "$ACCEPT_BIND" "log=$out"
    else
        event acceptance fail "$ACCEPT_BIND" "rc=$rc" "log=$out"
        warn "objective acceptance not met (exit $rc); health-green progress can still be saved"
    fi
    return 0
}

acceptance_note_work() {
    [ -n "$ACCEPT_BIND" ] || return 0
    if [ "${ACCEPT_CHANGED:-0}" = 1 ] && [ "$CY_MAY_COMMIT" = 1 ] &&
       [ "${COMMIT_FAILED:-0}" != 1 ] && [ "${CY_SELF_EDIT:-0}" != 1 ] && acceptance_intact; then
        state_set acceptance_work "$ACCEPT_BIND"
        [ "$(state_get acceptance_work '')" = "$ACCEPT_BIND" ] || { acceptance_error; return 1; }
        ACCEPT_WORK=1
        event acceptance work "$ACCEPT_BIND"
    fi
    return 0
}

acceptance_done() {
    [ -n "$ACCEPT_BIND" ] || return 0
    [ "$ACCEPT_PASS" = 1 ] && [ "$ACCEPT_WORK" = 1 ] &&
        [ "$GATES_GREEN" = yes ] && [ "${GATES_NONE:-0}" != 1 ] &&
        [ "$CY_MAY_COMMIT" = 1 ] && [ "${COMMIT_FAILED:-0}" != 1 ] &&
        acceptance_intact
}


FOCUS=""; FOCUS_KIND=""; OBJECTIVE_TEXT=""

# Keep the authoritative objective intact even when an engine edits its ledger.
# In-memory custody already exists for deletion recovery; no second spec file
# or binding is needed. The source is never reread after startup.
guard_objective() {
    [ -n "${OBJECTIVE_MEM:-}" ] || return 0
    local expected actual
    expected="$(printf '%s' "$OBJECTIVE_MEM" | sha_of)"
    actual="$(cat "$OBJECTIVE_FILE" 2>/dev/null | sha_of)"
    [ "$expected" = "$actual" ] && return 0
    ensure_own_file "$OBJECTIVE_FILE" "objective file"
    printf '%s' "$OBJECTIVE_MEM" > "$OBJECTIVE_FILE" || die "cannot restore objective"
    warn "the objective file vanished or changed; restored from this run"
    event objective restored "stored objective changed and was restored"
    return 1
}

select_focus() {
    # What would a good engineer do next, decided without spending a token.
    # Order is value per unit of risk: a red gate is the most valuable and the
    # least ambiguous work in any repository, so it always comes first.
    local n
    # The operator's objective is remembered separately from whatever is most
    # urgent right now. Carrying both in one variable meant a red gate deleted
    # the objective from the prompt and wrote a false Objective: line into the
    # commit -- the engine spent repair cycles never knowing what it was for.
    OBJECTIVE_TEXT=""
    [ -s "$OBJECTIVE_FILE" ] && OBJECTIVE_TEXT="$(head -c 4000 "$OBJECTIVE_FILE")"

    if [ "${GATES_GREEN:-unknown}" = "no" ]; then
        FOCUS_KIND="repair"
        if [ -n "${GATE_TIMED_OUT:-}" ]; then
            # Nothing is known to be wrong: the check was killed before it could
            # answer. Telling an agent to find a root cause invites it to invent
            # one and "fix" a project that may be perfectly healthy.
            FOCUS="A gate was killed by its time limit before it could finish, so its result is unknown. Do not guess at a root cause. Either make the check finish materially faster without weakening what it checks, or say in ask: that it needs a longer limit and spend this cycle on something that is actually known to be wrong."
        else
            FOCUS="A gate is failing. Diagnose the true root cause and fix it. Do not weaken, skip, delete or special-case the check to make it pass."
        fi
        return 0
    fi
    if [ -n "$OBJECTIVE_TEXT" ]; then
        FOCUS_KIND="objective"
        FOCUS="$OBJECTIVE_TEXT"
        return 0
    fi
    n="$(backlog_items | head -5)"
    if [ -n "$n" ]; then
        FOCUS_KIND="backlog"
        FOCUS="Unfinished work is recorded in this repository. Complete the next item, smallest first:

$n"
        return 0
    fi
    FOCUS_KIND="propose"
    if [ "${GATES_NONE:-0}" = "1" ]; then
        FOCUS="This project has no way to prove itself correct, so nothing here can be verified. The most valuable thing you can do is give it one: add a real check (a test, a type check, a build, a smoke script), make it pass, and write the command into .ralphie/gates. Then everything after this becomes trustworthy."
    else
        FOCUS="There is no stated objective and every gate is green. Find the single highest-value improvement this repository actually needs, state why it matters, and implement it. Prefer correctness and clarity over new surface area."
    fi
}

# Byte budgets use the C locale even on multibyte hosts. Every shortened
# excerpt says so; source files remain authoritative, never edited here.
context_excerpt() {
    local text="$1" limit="$2" marker="${3:- [truncated]}"
    printf '%s\n' "$text" | LC_ALL=C awk -v limit="$limit" -v marker="$marker" '
        { if (length($0) > limit) print substr($0, 1, limit-length(marker)) marker
          else print }'
}

lessons_brief() {
    # Select whole recent lesson lines, not a tail starting mid-lesson. Legacy
    # oversized lines are omitted, not allowed to evict every useful old fact.
    [ -f "$MEMORY_FILE" ] || return 0
    LC_ALL=C awk '
        /^- / { if (length($0)+1 <= 3900) lines[++n]=$0; else omitted=1 }
        END {
            used=0; first=n+1
            for (i=n; i>0; i--) {
                if (used+length(lines[i])+1 > 3900) { omitted=1; break }
                used+=length(lines[i])+1; first=i
            }
            if (omitted) print "[Older/oversized lessons omitted; see .ralphie/MEMORY.md]"
            for (i=first; i<=n; i++) print lines[i]
        }' "$MEMORY_FILE"
}

backlog_items() {
    # Unchecked markdown task boxes are a near-universal convention across every
    # planning tool, so they are the one backlog format worth reading natively.
    local f
    for f in "$PROJECT"/IMPLEMENTATION_PLAN.md "$PROJECT"/PLAN.md "$PROJECT"/TODO.md \
             "$PROJECT"/TASKS.md "$PROJECT"/ROADMAP.md "$PROJECT"/docs/TODO.md; do
        [ -f "$f" ] || continue
        LC_ALL=C awk -v source="${f#"$PROJECT"/}" '
            /^[[:space:]]*[-*][[:space:]]*\[[[:space:]]\]/ {
                prefix=source ":" NR ":"
                marker=" [truncated; read full item at " source ":" NR "]"
                text=$0
                if (length(prefix text)>1000)
                    text=substr(text,1,1000-length(prefix)-length(marker)) marker
                print prefix text
                if (++n==20) exit
            }' "$f" 2>/dev/null
    done
}

git_brief() {
    git_ready || { printf 'not a git repository\n'; return 0; }
    printf 'branch: %s\n' "$(git_branch)"
    printf 'head:   %s\n' "$(git -C "$PROJECT" log -1 --pretty='%h %s' 2>/dev/null || printf 'no commits yet')"
    local dirty; dirty="$(git -C "$PROJECT" status --porcelain 2>/dev/null | head -25)"
    if [ -n "$dirty" ]; then printf 'uncommitted:\n%s\n' "$dirty"; else printf 'uncommitted: none\n'; fi
    printf 'recent:\n%s\n' "$(git -C "$PROJECT" log -5 --pretty='  %h %s' 2>/dev/null || printf '  none')"
}

ledger_render() {
    # The one place that turns a ledger line into something a person reads.
    # There were two hand-rolled sed chains doing this, each matching the
    # field ORDER that `event()` happens to emit, so both would have started
    # printing raw JSON the first time a field moved -- silently, and only in
    # the two places anyone actually looks.
    sed -n \
        -e 's/.*"ts":"\([^"]*\)".*"cycle":\([0-9]*\).*"kind":"\([a-z]*\)".*"status":"\([a-z]*\)".*"detail":"\([^"]*\)".*/\1  c\2 \3 \4: \5/p'
}

history_brief() {
    # Only outcomes, not duplicate commit/gate events. Decode the JSON string
    # without optional tools: a quoted engine summary must not hide gate truth.
    [ -f "$EVENTS_FILE" ] || return 0
    grep -E '"kind":"cycle","status":"(pass|fail|nochange|stalled|blocked|untrusted|unverified|limit)"' "$EVENTS_FILE" 2>/dev/null \
      | tail -10 \
      | LC_ALL=C awk '
        {
            cycle=$0; sub(/^.*"cycle":/, "", cycle); sub(/,.*/, "", cycle)
            status=$0; sub(/^.*"status":"/, "", status); sub(/".*/, "", status)
            text=$0; sub(/^.*"detail":"/, "", text)
            detail=""; escaped=0
            for (i=1; i<=length(text); i++) {
                c=substr(text,i,1)
                if (escaped) {
                    if (c=="n" || c=="r" || c=="t") c=" "
                    detail=detail c; escaped=0
                } else if (c=="\\") escaped=1
                else if (c=="\"") break
                else detail=detail c
            }
            line="  cycle " cycle " " status ": " detail
            if (length(line)>1400)
                line=substr(line,1,1320) " [truncated; full outcome: .ralphie/events.jsonl]"
            print line
        }'
    return 0
}

context_files() {
    # Standing instructions the operator already wrote for agents. Ralphie reads
    # them and never rewrites them: they belong to the project, not to Ralphie.
    local f
    for f in AGENTS.md CLAUDE.md CONVENTIONS.md .cursorrules; do
        [ -f "$PROJECT/$f" ] || continue
        printf '### %s\n%s\n\n' "$f" "$(head -c 3000 "$PROJECT/$f")"
    done
}

RALPHIE_CONTRACT='You are operating inside Ralphie, an autonomous engineering loop.

HOW YOU ARE JUDGED
  The gates below are the only definition of success. Your own description of
  what you did changes nothing; Ralphie re-runs every gate after you stop and
  believes only the result. Making a gate pass by weakening it, deleting it,
  skipping the test, catching and swallowing the error, or special-casing the
  input is counted as a failure and will be reverted.

HOW TO WORK
  Do one coherent, complete piece of work, not six half-finished ones.
  Read before you write. Reproduce a failure before you fix it.
  Find the root cause. A patch over a symptom will come back next cycle.
  Match the conventions already in this repository over your own preferences.
  Leave the tree in a state where every gate can run.
  If a change is risky, make the smallest version of it that is still correct.
  Do not add dependencies, scaffolding, or abstraction the task did not require.
  Leave unrelated code alone. Every extra edit is risk the task did not ask for.
  Run the gates yourself before you stop. Finishing red costs a whole new cycle.
  Do not commit; Ralphie commits for you once the gates are green.
  If you truly cannot proceed without a human decision, say so in ask: and then
  do the most useful work that does not depend on that decision.

REPORT WHEN YOU FINISH
  End your reply with this block, exactly once:

<<<RALPHIE
status: progress | done | blocked
summary: one line describing what actually changed
lesson: one durable fact a future cycle would be glad to already know, or -
ask: a specific question only a human can answer, or -
RALPHIE>>>

  status: done means the objective is fully met and nothing remains. Claim it
  only when it is true; Ralphie verifies with the gates and will continue if it
  is not. Everything outside this block is free-form and is kept in the log.'

build_prompt() {
    local out="$1"
    {
        printf '# RALPHIE CYCLE %s\n\n' "$(json_num cycle)"
        if [ -s "$OBJECTIVE_FILE" ] && [ "$(file_bytes "$OBJECTIVE_FILE")" -gt 4000 ]; then
            printf '## AUTHORITATIVE FULL OBJECTIVE\n'
            printf 'Full objective file: %s\n' "$OBJECTIVE_FILE"
            printf 'Read this ENTIRE file before planning or work. The excerpt below is NOT the full specification.\n'
            printf 'Maintain a verifiable implementation plan mapping requirements to work and acceptance checks.\n'
            printf 'Preserve supplied plans; use a separate implementation plan if necessary.\n'
            printf 'Do not edit the authoritative objective. Add meaningful acceptance gates, including for a blank project.\n\n'
            printf '## OBJECTIVE EXCERPT (first 4000 bytes only)\n%s\n\n' "$OBJECTIVE_TEXT"
            if [ "$FOCUS_KIND" != "objective" ]; then
                printf '## WHAT IS WRONG RIGHT NOW\n%s\n\n' "$FOCUS"
            fi
        elif [ -n "$OBJECTIVE_TEXT" ] && [ "$FOCUS_KIND" != "objective" ]; then
            # Both, always: what you were asked to achieve, and what is most
            # urgent right now. Showing only the urgent thing loses the point.
            printf '## OBJECTIVE\n%s\n\n' "$OBJECTIVE_TEXT"
            printf '## WHAT IS WRONG RIGHT NOW\n%s\n\n' "$FOCUS"
        else
            printf '## OBJECTIVE\n%s\n\n' "$FOCUS"
        fi

        request_prompt
        printf '## GATES - THE DEFINITION OF DONE\n'
        if [ "$(gates_count)" -gt 0 ]; then
            printf 'Every one of these must exit 0, run from the project root:\n\n'
            gates_list | sed 's/^/  $ /'
            printf '\nLast run: %s\n' "$([ "${GATES_GREEN:-unknown}" = "yes" ] && printf 'all passing' || printf 'FAILING')"
            if [ "${GATES_GREEN:-unknown}" = "no" ]; then
                printf '\n```\n%s\n```\n' "$(gate_failure_brief)"
            fi
        else
            printf 'No gate is configured yet, so nothing can be verified.\n'
            printf 'If you can identify the command this project uses to prove itself\n'
            printf 'healthy, write it into .ralphie/gates as part of your work.\n'
        fi
        printf '\n'

        if [ -n "$ACCEPT_BIND" ]; then
            printf '## OBJECTIVE ACCEPTANCE (separate from HEALTH)\n'
            printf 'Health-green changes are progress, not necessarily completion.\n'
            printf 'Completion requires HEALTH, ACTUAL WORK, and current ACCEPTANCE pass.\n'
            printf 'Acceptance command (project root): %s\n' "$ACCEPT_CMD"
            printf 'Ralphie runs it independently; do not edit .ralphie/acceptance.\n\n'
        fi
        printf '## PROJECT\n'
        printf 'path:  %s\n' "$PROJECT"
        printf 'stack: %s\n' "$(detect_stack)"
        git_brief
        printf '\n'

        # The backlog belongs in the brief even when an objective is set: it is
        # how a large objective was decomposed, and it was previously unreachable
        # in exactly the multi-cycle work that needs it most.
        if [ "$FOCUS_KIND" != "backlog" ]; then
            local bl; bl="$(backlog_items | head -10)"
            [ -n "$bl" ] && printf '## UNFINISHED WORK RECORDED IN THIS REPOSITORY\n%s\n\n' "$bl"
        fi

        local h; h="$(history_brief)"
        [ -n "$h" ] && printf '## ALREADY ATTEMPTED\n%s\n\n' "$h"

        if [ -s "$MEMORY_FILE" ]; then
            printf '## DURABLE LESSONS FROM EARLIER CYCLES\n%s\n\n' "$(lessons_brief)"
        fi

        local a; a="$(asks_open)"
        [ -n "$a" ] && printf '## AWAITING A HUMAN - DO NOT BLOCK ON THESE\n%s\n\n' "$a"

        local c; c="$(context_files)"
        [ -n "$c" ] && printf '## STANDING PROJECT INSTRUCTIONS\n%s\n' "$c"

        printf '## CONTRACT\n%s\n' "$RALPHIE_CONTRACT"
        # Tell an engine about a strength only if it actually has it. Advising a
        # single-threaded engine to "delegate in parallel" wastes its attention,
        # which is the same complement rule the engine table follows.
        if engine_has "$ENGINE" subagents; then
            printf '\n  You can delegate. Split genuinely independent work across parallel\n'
            printf '  workers, and keep anything that must stay consistent in one place.\n'
        fi
        if engine_has "$ENGINE" memory; then
            printf '\n  You keep your own durable memory. Record what would save a future run\n'
            printf '  real time, and still report the single most important line in lesson:.\n'
        fi
    } > "$out" || die "cannot persist cycle prompt"
    # A prompt that outgrows the brief is a prompt nobody reads carefully.
    dbg "prompt: $(file_bytes "$out") bytes"
}

# --- the engine's report ------------------------------------------------------
# Parsed leniently on purpose. A missing or malformed block must never stop the
# loop, because the gates already carry the decision that matters.

REPORT_STATUS=""; REPORT_SUMMARY=""; REPORT_LESSON=""; REPORT_ASK=""
parse_report() {
    local f="$1" body
    REPORT_STATUS=""; REPORT_SUMMARY=""; REPORT_LESSON=""; REPORT_ASK=""
    [ -f "$f" ] || return 0
    # No block at all is normal for a terse engine. Default to "progress" so a
    # caller never has to distinguish "absent" from "said progress".
    REPORT_STATUS="progress"
    # Only the LAST complete block, because the contract says the reply ENDS
    # with it. Concatenating every match and reading the first status in the
    # last 20 lines let PROJECT TEXT echoed by the engine forge a report: a repo
    # ended a five-cycle run at cycle 1 as "done" and raised a question in
    # Ralphie's own voice asking the operator for the production database
    # password.
    body="$(awk '/<<<RALPHIE/{buf=""; inb=1}
                 inb{buf = buf $0 "\n"}
                 /RALPHIE>>>/{if (inb) {last=buf; inb=0}}
                 END{printf "%s", last}' "$f" 2>/dev/null)"
    [ -n "$body" ] || return 0
    REPORT_STATUS="$(printf '%s\n' "$body"  | sed -n 's/^[[:space:]]*status:[[:space:]]*//p'  | head -1 | tr -d '\r')"
    REPORT_SUMMARY="$(printf '%s\n' "$body" | sed -n 's/^[[:space:]]*summary:[[:space:]]*//p' | head -1 | tr -d '\r')"
    REPORT_LESSON="$(printf '%s\n' "$body"  | sed -n 's/^[[:space:]]*lesson:[[:space:]]*//p'  | head -1 | tr -d '\r')"
    REPORT_ASK="$(printf '%s\n' "$body"     | sed -n 's/^[[:space:]]*ask:[[:space:]]*//p'     | head -1 | tr -d '\r')"
    case "$REPORT_LESSON" in -|none|n/a|NA|"") REPORT_LESSON="";; esac
    case "$REPORT_ASK"    in -|none|n/a|NA|"") REPORT_ASK="";; esac
    case "$(printf '%s' "$REPORT_STATUS" | tr '[:upper:]' '[:lower:]')" in
        done|complete|finished) REPORT_STATUS="done";;
        blocked|stuck)          REPORT_STATUS="blocked";;
        *)                      REPORT_STATUS="progress";;
    esac
}

remember() {
    # One line, deduplicated. A memory file that repeats itself teaches nothing
    # and costs tokens in every future prompt.
    local lesson; lesson="$(context_excerpt "$(flatten_text "$1")" 1000)"
    [ -n "$lesson" ] || return 0
    # `--` is mandatory: the pattern begins with a dash and BSD grep would
    # otherwise parse it as an option and fail with "invalid option".
    [ -f "$MEMORY_FILE" ] && grep -qxF -- "- $lesson" "$MEMORY_FILE" 2>/dev/null && return 0
    mkdir -p "$HOME_DIR"
    [ -f "$MEMORY_FILE" ] || printf '# Durable lessons\n\n' > "$MEMORY_FILE"
    printf -- '- %s\n' "$lesson" >> "$MEMORY_FILE"
    event learn ok "$lesson"
    dim "  learned: $lesson"
    # Keep the file bounded; the oldest lessons have usually been superseded.
    local n; n="$(count_of grep '^- ' "$MEMORY_FILE")"
    if [ "$n" -gt "${MEMORY_MAX:-60}" ]; then
        local tmp="$MEMORY_FILE.tmp.$$"
        { printf '# Durable lessons\n\n'; grep '^- ' "$MEMORY_FILE" | tail -n "${MEMORY_MAX:-60}"; } > "$tmp"
        mv -f "$tmp" "$MEMORY_FILE"
    fi
    # Counted after the trim, or status reports one lesson more than the file
    # holds, for ever.
    state_set learned_count "$(count_of grep '^- ' "$MEMORY_FILE")"
    return 0
}

# --- one cycle ----------------------------------------------------------------

cycle_once() {
    # The whole program, in the order the README promises. Each phase is named
    # for what it is, so the shape of the loop is visible without reading its
    # parts. They share CY_* state rather than returning values, because bash
    # returns a status and nothing else, and hiding that in a pipeline would
    # cost more clarity than it bought.
    #
    #   0 keep going   2 blocked   3 stalled   10 done   11 out of time
    # `set -e` is suspended here because every caller of cycle_once tests its
    # status, so a non-zero return ends the cycle rather than the program. The
    # phases that cannot fail say `return 0` explicitly instead of being wrapped
    # in `|| true`, which would silently swallow a status they might one day
    # want to report.
    local rc=0
    cycle_begin
    cycle_observe || return $?
    cycle_act     || return $?
    cycle_verify
    cycle_record
    cycle_learn || rc=$?
    return "$rc"
}

# --- 0. begin ---------------------------------------------------------------

cycle_begin() {
    # If the state file was destroyed mid-run the counter restarts at 1, so the
    # ledger gains a second cycle 1 and `log/cycle-1.log` is overwritten -- the
    # append-only record stops being a narrative. The ledger already knows how
    # far we got, so it is consulted, but ONLY when the counter looks lost:
    # a grep over a 16 MB ledger is not worth paying for on a healthy cycle.
    if [ "$(state_get cycle 0)" = "0" ] && [ -s "$EVENTS_FILE" ]; then
        local seen
        seen="$(grep -o '"cycle":[0-9]*' "$EVENTS_FILE" 2>/dev/null | sed 's/.*://' | sort -n | tail -1)"
        if is_int "${seen:-}" && [ "${seen:-0}" -gt 0 ]; then
            # The whole tally is rebuilt, not just the cycle number. Restoring
            # the counter alone left `status` reporting "0 green" for a project
            # holding four real Ralphie commits -- a worse lie than admitting
            # the count was lost, because it reads as "nothing was achieved".
            rebuild_state_from_ledger
            [ "$(state_get cycle 0)" = "0" ] && state_set cycle "$seen"
            dbg "the counters were lost; rebuilt from the ledger (cycle $seen)"
        fi
    fi
    state_bump cycle
    CY_N="$(state_get cycle)"
    CY_PROMPT="$RUN_DIR/cycle-$CY_N.prompt.md"
    CY_LOG="$LOG_DIR/cycle-$CY_N.log"
    CY_OUT="$RUN_DIR/cycle-$CY_N.answer"
    CY_STARTED="$(now_epoch)"
    ACCEPT_PASS=0
    if [ -n "$ACCEPT_BIND" ]; then COMMIT_FAILED=0; fi
    CY_GATE_TAMPER=0      # a gate was removed during this cycle
    CY_SELF_EDIT=0        # ralphie.sh itself was modified during this cycle
    CY_TAMPER_NAME=""
    CY_MAY_COMMIT=1       # policy: is this cycle allowed to save its work?
    # The blank line is the banner's other half: under --quiet it would be the
    # only thing left of the separator, one empty line per cycle for ever.
    is_true "$QUIET" || say ""
    info "── cycle $CY_N ─────────────────────────────────────────────"
    ensure_dirs
    # An agent that deletes .ralphie/ used to take the objective with it, and
    # the loop quietly retargeted itself to "propose" -- paying to do work
    # nobody asked for. The objective is held in memory for exactly this.
    guard_objective || true
    request_boundary
    # Before any gate is allowed to run. Taken later, a gate whose side effect
    # deletes another gate had already shrunk the file by the time the snapshot
    # was made, so the loss was invisible and the smaller set became the norm.
    snapshot_gates
    # Compare ownership before gates or the engine can change the claimed bytes.
    release_owned_paths
    CY_HEAD="$(commit_head)"
    CY_REF="$(git -C "$PROJECT" symbolic-ref --quiet HEAD 2>/dev/null || true)"
    CY_HISTORY_CAPTURED=0
    CY_OLD_COMMITS="$(git -C "$PROJECT" rev-list --all 2>/dev/null | tr '\n' ' ')" && CY_HISTORY_CAPTURED=1
    return 0
}

# --- 1. observe -------------------------------------------------------------
# Deterministic and free. Nothing here costs a token, because nothing here
# needs judgement.

cycle_observe() {
    CY_FP="$(fingerprint)"

    # The tree cannot change between the previous cycle's verify and this
    # cycle's observe, so re-running the gates there is pure waste. On a project
    # with a forty-minute suite it doubled every cycle.
    local gate_summary=""
    # Both must agree before a verdict may be reused: the fingerprint proves
    # git-visible content is unchanged, and the marker proves nothing at all has
    # been written since the verdict was measured -- including the untracked and
    # ignored files the fingerprint cannot see.
    if [ -n "${LAST_VERIFY_FP:-}" ] && [ "$LAST_VERIFY_FP" = "$CY_FP" ] && ! verify_mark_stale; then
        GATES_GREEN="$LAST_VERIFY_RESULT"; GATES_NONE="${LAST_VERIFY_NONE:-0}"
        # Carry the evidence forward with the verdict. Reusing only the verdict
        # left the ledger with an empty gate detail from cycle two onward, and
        # put blank lines into the prompt where the gate summary should be.
        gate_summary="${LAST_VERIFY_SUMMARY:-}"
        dbg "gates unchanged since last verify; reusing the result"
    else
        if run_gates "$RUN_DIR/gates-$CY_N"; then GATES_GREEN=yes; else GATES_GREEN=no; fi
        gate_summary="$(head -c 400 "$RUN_DIR/gates-$CY_N.summary" 2>/dev/null || printf '')"
    fi

    # A gate can damage the gate set while merely being observed.
    check_gates

    if   [ "${GATES_NONE:-0}" = "1" ]; then warn "gates: none - nothing here can be verified"
    elif [ "$GATES_GREEN" = "yes" ];   then good "gates: green"
    else warn "gates: red  ($GATE_FAIL_CMD)"; fi
    event gate "$([ "$GATES_GREEN" = yes ] && printf pass || printf fail)" "$gate_summary"

    select_focus
    dim "  focus: $FOCUS_KIND"

    # Green, nothing outstanding, and the operator asked to stop there.
    # `objective_started` is what makes this safe: it holds the hash of the
    # objective a cycle has actually been spent on, so the test reads "this
    # objective has been worked". A green repo plus a brand-new instruction is
    # the one moment where "nothing left to do" is certainly wrong, and
    # comparing the other way round -- which is how this was first written --
    # made the loop do literally nothing and report success, for ever.
    if [ -z "$ACCEPT_BIND" ] && [ "$GATES_GREEN" = "yes" ] && [ "${GATES_NONE:-0}" != "1" ] && is_true "${DONE_WHEN_GREEN:-0}" \
       && ! request_pending \
       && { [ -z "${REQUEST_CYCLE_IDS:-}" ] || [ "$(state_get objective_started '')" = "$(state_get objective_hash '')" ]; } \
       && [ -z "$(backlog_items | head -1)" ] \
       && { [ ! -s "$OBJECTIVE_FILE" ] || [ "$(state_get objective_started '')" = "$(state_get objective_hash '')" ]; }; then
        state_set status done; event cycle done "green with nothing outstanding"
        good "nothing left to do - gates green, no outstanding work"
        return 10
    fi
    return 0
}

# --- 2. act -----------------------------------------------------------------
# The only phase that spends money.

cycle_act() {
    build_prompt "$CY_PROMPT"
    request_ack
    local mode="oneshot"
    if engine_has "$ENGINE" autonomy && engine_has "$ENGINE" gates && [ "$(gates_count)" -gt 0 ]; then
        mode="autonomous"
    fi
    dim "  engine: $ENGINE ($mode)"
    mark_tree

    if ! engine_run_with_fallback "$mode" "$CY_PROMPT" "$CY_LOG" "$CY_OUT"; then
        if budget_expired; then
            # Being out of time is not the engine failing, and must never be
            # reported as one. The tree keeps whatever was written.
            warn "cycle $CY_N was cut short by the time limit"
            # Still checked: a gate deleted during the final cycle of a timed
            # run was otherwise neither restored nor reported by this process.
            check_gates
            self_hash_check || CY_SELF_EDIT=1
            if [ "$CY_GATE_TAMPER" = "1" ]; then
                # Restoring it silently taught the next run nothing, and left
                # the operator with no idea it had happened.
                remember "Gates must not be removed. '${CY_TAMPER_NAME:-a gate}' was deleted during a cycle and was restored automatically."
                ask_human "The engine removed the gate '${CY_TAMPER_NAME:-a gate}' during the final cycle of a timed run. Ralphie restored it. Review that cycle before trusting it."
            fi
            # That work is Ralphie's. Without this the next run snapshots it as
            # the operator's pre-existing change and excludes it for ever.
            record_owned_paths
            event cycle limit "time limit expired during the cycle"
            return 11
        fi
        err "no engine could complete this cycle: $ENGINE_REASON"
        state_set status blocked; state_set reason "$ENGINE_REASON"
        event cycle fail "$ENGINE_REASON"
        return 2
    fi

    read_engine_usage
    # The preferred engine is retried next cycle; a borrowed one is not adopted.
    [ -n "${CYCLE_ENGINE:-}" ] && [ "$CYCLE_ENGINE" != "$ENGINE" ] && \
        dim "  (used $CYCLE_ENGINE this cycle; $ENGINE is still preferred)"
    parse_report "$CY_OUT"
    retain_engine_output "$CY_LOG"
    retain_engine_output "$CY_OUT"
    [ -n "$REPORT_SUMMARY" ] && say "  ${C_DIM}said:${C_OFF} $REPORT_SUMMARY"
    return 0
}

# --- 3. verify --------------------------------------------------------------
# The engine has just said it succeeded. That is not evidence.

cycle_verify() {
    if ! guard_objective; then
        CY_MAY_COMMIT=0
        REPORT_STATUS="progress"
    fi
    # Restore any gate that vanished first, so the verdict is measured against
    # the checks that were agreed, not the ones that survived the cycle.
    check_gates

    # GATES_GREEN is a MEASUREMENT and nothing else writes to it. Overwriting it
    # with a policy decision looked harmless, but the next cycle cached that
    # value as evidence and reported `gates: red ()` with an empty failure
    # block -- then paid an engine to repair a failure that never happened.
    if run_gates "$RUN_DIR/gates-$CY_N-after" verify; then GATES_GREEN=yes; else GATES_GREEN=no; fi

    # Again, because a gate can damage the gate set WHILE IT RUNS. Checking only
    # beforehand missed an added gate whose side effect deleted the real one,
    # and three commits landed saying "Verified by 1 gate(s)" on a broken
    # project. Verification has to be checked after it happens, not only before.
    check_gates
    if ! guard_objective; then
        CY_MAY_COMMIT=0
        REPORT_STATUS="progress"
    fi

    self_hash_check || CY_SELF_EDIT=1

    # The two are reported separately, because they mean entirely different
    # things. Conflating them made a SUPPORTED self-improvement cycle write a
    # fabricated "Gates must not be removed" lesson into MEMORY.md for ever,
    # and ask the operator a question about a gate that was never touched.
    if [ "$CY_GATE_TAMPER" = "1" ]; then
        CY_MAY_COMMIT=0
        REPORT_STATUS="progress"   # a cycle that weakened its own checks cannot claim done
        remember "Gates must not be removed. '${CY_TAMPER_NAME:-a gate}' was deleted during a cycle and was restored automatically."
        ask_human "The engine removed the gate '${CY_TAMPER_NAME:-a gate}' during a cycle. Ralphie restored it. Review that cycle before trusting it."
    fi
    if [ "$CY_SELF_EDIT" = "1" ]; then
        # Improving Ralphie with Ralphie is supported, so this does NOT refuse
        # the commit: the gates still decide, exactly as the README says. It is
        # reported, and the operator is asked to look before the next run.
        REPORT_STATUS="progress"
    fi
    if [ -n "$ACCEPT_BIND" ]; then
        ACCEPT_CHANGED=0
        work_changed "$CY_FP" && ACCEPT_CHANGED=1
        acceptance_verify
        # Acceptance is an operator command and may itself damage health checks.
        check_gates
        if [ "$CY_GATE_TAMPER" = 1 ]; then CY_MAY_COMMIT=0; ACCEPT_PASS=0; REPORT_STATUS=progress; fi
    fi
    [ "$CY_GATE_TAMPER" = "1" ] || baseline_gates_save
    return 0
}

# --- 4. record --------------------------------------------------------------
# Commit on green. Append evidence always.

cycle_record() {
    # What happened, whether it may be saved, and whose work is in the tree.
    if work_changed "$CY_FP"; then
        record_outcome
        acceptance_note_work
    else record_nochange; fi
    # Changes made during this cycle are not evidence of an operator edit.
    # Drop old content claims, then record the new bytes without changing the
    # sealed exclusions captured before the cycle.
    release_owned_paths after-cycle
    record_owned_paths
    cache_verdict
    state_set last_cycle_at "$(now_epoch)"
    # Records that THIS objective has had a cycle spent on it. Counting per-run
    # instead made `--once --done-when-green` unable to ever stop, because a
    # single-cycle run never has a previous cycle; counting per-lifetime made it
    # stop immediately on any repo that had ever been green.
    state_set objective_started "$(state_get objective_hash '')"
    prune_artifacts
    local took; took="$(secs_since "$CY_STARTED")"
    state_bump total_seconds "$took"
    dim "  cycle $CY_N took $(human_secs "$took")"
    event cycle timing "$(human_secs "$took")" "seconds=$took"
    return 0
}

record_nochange() {
    warn "cycle $CY_N changed nothing"
    event cycle nochange "${REPORT_SUMMARY:-engine made no change}"
    # Persisted, because `--once` from cron is a fresh process every time.
    # Holding this only in memory made exit code 3 unreachable for every
    # unattended deployment: five no-change cycles in a row each exited 0.
    NOCHANGE_STREAK=$(( ${NOCHANGE_STREAK:-0} + 1 ))
    state_set nochange_streak "$NOCHANGE_STREAK"
}

record_outcome() {
    # The whole point of Ralphie, in one ladder. Work was produced; this decides
    # what it was worth. Nothing here consults the engine's opinion of itself.
    # The no-progress streak is NOT cleared here. Clearing it up front and then
    # incrementing it below always produced 1, so a loop that was untrusted or
    # blocked on every single cycle could never stall. Only the outcomes that
    # really moved the project forward clear it, each saying so itself.

    # Untrusted outranks the measurement, whatever it said: the checks were
    # damaged, so the result means nothing either way. Saying "gates passed"
    # here would have been a lie when they had not.
    if [ "$CY_MAY_COMMIT" != "1" ]; then
        # Not progress. Clearing the streak here meant a loop that damaged its
        # own verification every single cycle could never stall, and ran until
        # it hit a limit -- paying for every cycle of it.
        NOCHANGE_STREAK=$(( ${NOCHANGE_STREAK:-0} + 1 ))
        state_set nochange_streak "$NOCHANGE_STREAK"
        state_bump untrusted_count
        warn "this cycle is not trusted - its own verification was damaged; nothing was committed"
        event cycle untrusted "verification was damaged during the cycle"
        return 0
    fi

    if [ "$GATES_GREEN" != "yes" ]; then
        # A red cycle that really changed the tree IS progress: the next cycle
        # has new evidence to work from. Only cycles that saved nothing count
        # towards the stall.
        NOCHANGE_STREAK=0; state_set nochange_streak 0
        state_bump fail_count
        warn "gates: still red after cycle $CY_N"
        # Never "gates red: unknown": if no gate is named, say what is actually
        # known instead of inventing a cause.
        # Written as `${X:+red: $X}${X:-none}` this DOUBLED the gate name into
        # the append-only ledger on every red cycle: `${X:-none}` is X when X is
        # set. Two expansions of the same variable are not either/or.
        local attempt="" evidence
        if [ -n "${REPORT_SUMMARY:-}" ]; then
            attempt="engine-reported attempt: $(context_excerpt "$(flatten_text "$REPORT_SUMMARY")" 700); "
        fi
        if [ -n "${GATE_FAIL_CMD:-}" ]
        then evidence="gates red: $GATE_FAIL_CMD"
        else evidence="no gate passed and none reported a name"; fi
        event cycle fail "$attempt$evidence"
        return 0
    fi

    # THE MEASUREMENT, announced before anything is done with it. What the gates
    # said and whether the work could be saved are different facts, and a cycle
    # whose commit was refused used to be reported as though the gates had
    # failed -- which was simply untrue.
    [ "${GATES_NONE:-0}" = "1" ] || good "gates: green"

    # The commit is attempted BEFORE anything is counted. Counting the cycle
    # green first meant a commit git refused still produced "1 green" in status
    # with an empty git log.
    COMMIT_FAILED=0
    COMMIT_BLOCKED_WHY=""
    COMMIT_SKIPPED=0
    CY_ENGINE_SAVED=0
    local head_before head_after
    head_before="${CY_HEAD:-$(commit_head)}"
    head_after="$(commit_head)"
    if [ "$head_after" != "$head_before" ]; then
        if ! engine_history_is_safe "$head_after"; then
            COMMIT_FAILED=1
            COMMIT_BLOCKED_WHY="engine changed history without safe, new project work"
            event commit blocked "$COMMIT_BLOCKED_WHY"
            ask_human "The engine changed git history, but Ralphie could not validate those commits. Nothing was reset. Review the history and protected paths before continuing."
        else
            CY_ENGINE_SAVED=1
            if git_dirty; then
                is_true "${AUTO_COMMIT:-1}" && { git_commit_cycle "$(commit_message "$CY_N")" || true; }
            fi
            event commit ok "verified engine-created commits" "sha=$head_after"
        fi
    else
        is_true "${AUTO_COMMIT:-1}" && { git_commit_cycle "$(commit_message "$CY_N")" || true; }
    fi
    head_after="$(commit_head)"

    # ONE POSTCONDITION, CHECKED ONCE, FOR THE WHOLE COMMIT PATH.
    #
    # A green cycle claims the work is SAVED. The only proof of that is that
    # HEAD moved. Everything else -- five functions, three globals, and every
    # guard added in four consecutive reviews -- is a way of describing why it
    # did not.
    #
    # This replaces asking "did step N remember to set a flag?" at each site.
    # Four separate defects across four reviews were all the same missing
    # answer at a different site: a step returned without setting a flag, and
    # the cycle landed in `pass` with an empty git log behind it. Two more were
    # found in this file after the other four were fixed. A new step added
    # tomorrow cannot reintroduce it, because the claim is no longer built from
    # the steps' own reports -- it is checked against the repository.
    if is_true "${AUTO_COMMIT:-1}" && [ "${COMMIT_SKIPPED:-0}" != "1" ] \
       && [ "${COMMIT_FAILED:-0}" != "1" ] && [ "$head_after" = "$head_before" ]; then
        COMMIT_FAILED=1
        COMMIT_BLOCKED_WHY="the commit step reported success but no commit was made"
        err "the work is verified but NOT saved - git reported success and HEAD did not move"
        event commit blocked "no commit was made although no step reported a failure"
        ask_human "A cycle passed its gates and the commit reported no error, but no commit exists. The work is on disk. This is a defect in Ralphie, not in your project - please report it with .ralphie/events.jsonl."
    fi

    if [ "${COMMIT_FAILED:-0}" = "1" ]; then
        # Nothing was saved, so nothing moved forward: a loop that is blocked
        # every cycle must be allowed to notice and stop.
        NOCHANGE_STREAK=$(( ${NOCHANGE_STREAK:-0} + 1 ))
        state_set nochange_streak "$NOCHANGE_STREAK"
        # Green, but not saved. Never counted as a pass: doing so wrote
        # `cycle pass` into the append-only ledger for a commit that never
        # happened, and status reported "11 green" against 4 commits.
        state_bump blocked_count
        event cycle blocked "${COMMIT_BLOCKED_WHY:-git refused the commit}"
    elif [ "${GATES_NONE:-0}" = "1" ]; then
        # An unverified cycle is not a green cycle. Counting it made status
        # report "N green" for work nothing had checked.
        NOCHANGE_STREAK=0; state_set nochange_streak 0     # work was saved
        state_bump unverified_count
        warn "unverified work - no gate exists to check it"
        # A distinct status, so a rebuild from the ledger can tell an unverified
        # cycle from a green one. The old rebuild grepped for a phrase the
        # ledger never wrote and silently promoted every unverified cycle.
        event cycle unverified "${REPORT_SUMMARY:-work completed, nothing checked it}"
    else
        NOCHANGE_STREAK=0; state_set nochange_streak 0     # work was saved
        state_bump pass_count
        event cycle pass "${REPORT_SUMMARY:-work completed}"
    fi
}


cache_verdict() {
    # Taken AFTER the commit, so it matches the tree the next cycle observes.
    # Recording it before meant it never matched, and the "reuse the verify
    # result" optimisation never fired once.
    # Cached only when it is a real measurement of a tree that is about to be
    # observed again. A distrusted cycle leaves the cache alone rather than
    # teaching the next cycle something that was never measured.
    if [ "$CY_MAY_COMMIT" != "1" ]; then LAST_VERIFY_FP=""; return 0; fi
    LAST_VERIFY_FP="$(fingerprint)"
    LAST_VERIFY_RESULT="$GATES_GREEN"
    LAST_VERIFY_NONE="${GATES_NONE:-0}"
    mark_verify
    LAST_VERIFY_SUMMARY="$(head -c 400 "$RUN_DIR/gates-$CY_N-after.summary" 2>/dev/null || printf '')"
}


# --- 5. learn ---------------------------------------------------------------
# What a future cycle should already know, and what only a human can settle.

cycle_learn() {
    if [ -n "${GATE_TIMED_OUT:-}" ]; then
        warn "gate '$GATE_TIMED_OUT' timed out after ${GATE_TIMED_OUT_SECS:-?}s - raise GATE_TIMEOUT if it needs longer"
        ask_human "The gate '$GATE_TIMED_OUT' was killed after ${GATE_TIMED_OUT_SECS:-?}s. If it legitimately takes longer, run with a larger GATE_TIMEOUT; otherwise it is genuinely hanging."
    fi
    if [ -n "${GATE_FLAKY:-}" ]; then
        # An unreliable check quietly taxes every future cycle and undermines
        # the one signal this whole loop trusts.
        remember "The gate '$GATE_FLAKY' is flaky: it has failed and then passed on an unchanged tree."
        ask_human "The gate '$GATE_FLAKY' is unreliable (failed, then passed with no change). Fix or replace it; until then every result that depends on it is less trustworthy."
    fi
    [ -n "$REPORT_LESSON" ] && remember "$REPORT_LESSON"
    # Attributed, always. A question relayed from the engine must never look
    # like Ralphie speaking: the same channel was used to phish an operator.
    [ -n "$REPORT_ASK" ]    && ask_human "The engine asks: $REPORT_ASK"

    # A loop that cannot move the tree will not start moving it by trying
    # harder. Stop and say so, rather than spending the whole budget.
    if [ "${NOCHANGE_STREAK:-0}" -ge "${NOCHANGE_LIMIT:-3}" ]; then
        err "no progress in ${NOCHANGE_STREAK} consecutive cycles - stopping"
        state_set status stalled
        state_set reason "no change in ${NOCHANGE_STREAK} cycles"
        event cycle stalled "no change in ${NOCHANGE_STREAK} cycles"
        ask_human "Ralphie made no progress for ${NOCHANGE_STREAK} cycles on: ${FOCUS_KIND}. The objective may be unclear, unreachable, or already done."
        return 3
    fi

    if { [ "$REPORT_STATUS" = "done" ] ||
         { [ -n "$ACCEPT_BIND" ] && is_true "${DONE_WHEN_GREEN:-0}" && [ -z "$(backlog_items | head -1)" ]; }; } &&
       [ "$GATES_GREEN" = "yes" ] && [ "${GATES_NONE:-0}" != "1" ] && ! request_pending && acceptance_done; then
        # Believed only because real health gates agree, never an empty set.
        state_set status done
        event cycle done "${REPORT_SUMMARY:-objective met, gates green}"
        return 10
    fi
    # A DIFFERENT fact from "the gates passed but the work could not be saved",
    # and it must not share that name: the rebuild counts `cycle blocked` lines,
    # so the engine's own opinion of itself inflated a real outcome counter and
    # status claimed work "could not be saved" against successful commits.
    [ "$REPORT_STATUS" = "blocked" ] && event engine stuck "${REPORT_ASK:-engine reported blocked}"
    return 0
}

commit_message() {
    # The message must not claim more than was actually checked. A commit that
    # says "Gates green" on a project with no gates is a lie that outlives the
    # run, in the one artifact a reviewer will trust years later.
    local n="$1" s="${REPORT_SUMMARY:-autonomous cycle}" verdict
    s="$(printf '%s' "$s" | cut -c1-72)"
    if [ "${GATES_NONE:-0}" = "1" ]; then
        verdict="NOT VERIFIED - this project has no gate"
    else
        verdict="Verified by $(gates_count) gate(s)."
    fi
    # Trailers so `git log` can answer "which engine and model wrote this, and
    # in which run", months later, without the ledger.
    local obj; obj="${OBJECTIVE_TEXT:-$FOCUS}"
    printf 'ralphie: %s\n\nCycle %s. %s\nObjective: %s\n\nRalphie-Engine: %s\nRalphie-Model: %s\nRalphie-Run: %s\nRalphie-Version: %s\n' \
        "$s" "$n" "$verdict" "$(printf '%s' "$obj" | head -1 | cut -c1-120)" \
        "${CYCLE_ENGINE:-${ENGINE:-unknown}}" \
        "$([ "${CYCLE_ENGINE:-$ENGINE}" = "${ENGINE:-}" ] && printf '%s' "${MODEL:-default}" || printf 'default')" \
        "$(state_get run_id -)" "$VERSION"
}

budget_stop() {
    # One place decides what "out of time" looks like, so a limit reached
    # inside a cycle and one reached between cycles read identically.
    info "reached the time limit (${MAX_MINUTES}m)"
    state_set status paused
    event exit limit "time limit"
}

loop() {
    local rc started; started="$(now_epoch)"
    # Carried across processes so an unattended `--once` loop can still stall.
    NOCHANGE_STREAK="$(json_num nochange_streak)"
    # Already set in main() before discovery; only seeded here if it was not.
    if [ "${RUN_DEADLINE:-0}" -le 0 ] && [ "${MAX_MINUTES:-0}" -gt 0 ]; then
        RUN_DEADLINE=$(( started + MAX_MINUTES * 60 ))
    fi
    state_set status running
    local i=0
    while :; do
        i=$((i+1))
        if [ -f "$STOP_FILE" ]; then
            rm -f "$STOP_FILE"
            if [ "$i" -eq 1 ]; then
                # A leftover stop file used to make a cron job exit 0 having done
                # nothing at all, looking perfectly healthy.
                warn "cleared a leftover stop request from a previous run - continuing"
                event run resumed "stale stop file cleared"
            else
                warn "stop requested"; state_set status stopped; event exit stopped "stop file"; return 0
            fi
        fi
        if [ "${MAX_CYCLES:-0}" -gt 0 ] && [ "$i" -gt "${MAX_CYCLES}" ]; then
            info "reached the cycle limit (${MAX_CYCLES})"; state_set status paused; event exit limit "cycle limit"; return 0
        fi
        if budget_expired; then budget_stop; return 0; fi
        rc=0; cycle_once || rc=$?
        case "$rc" in
            0)  ;;
            10) good "objective complete"; return 0;;
            11) budget_stop; return 0;;
            *)  return "$rc";;
        esac
    done
}

# ============================================================================
# LAYER 6 - HUMAN
#   The human is a collaborator, never a blocking dependency.
#
#   Ralphie does not have an interactive mode, a wizard, or an interview. It
#   cannot stall waiting for someone to type. A question becomes a numbered
#   line in a file and, optionally, a notification. The loop then goes and does
#   work that does not depend on the answer. This is the difference between an
#   assistant you have to sit with and a system you can leave running.
# ============================================================================

# --- durable unsolicited requests ------------------------------------------
# Fixed exclusive slots bound the active batch. Never prune evidence.
# Broken paths fail closed. Explicit stopped-worker archive retains abandoned
# reservations too, so interrupted producers cannot exhaust capacity forever.
request_dir() {
    local d="$1"
    [ ! -L "$d" ] || die "request path is a symlink: $d"
    if [ ! -e "$d" ]; then mkdir -m 700 "$d" 2>/dev/null || [ -d "$d" ] || die "cannot create request directory: $d"; fi
    [ -d "$d" ] && [ -r "$d" ] && [ -w "$d" ] && [ -x "$d" ] && [ -O "$d" ] && [ ! -L "$d" ] || die "unsafe request directory: $d"
}
request_init() {
    request_dir "$HOME_DIR"
    request_dir "$HOME_DIR/requests"
}
request_file() {
    [ ! -L "$1" ] && [ -f "$1" ] && [ -r "$1" ] && [ -O "$1" ] || die "unsafe request evidence: $1"
}
request_scan() {
    # Call in the main shell: errors must stop, not disappear in substitution.
    local slot f id n=0
    REQUEST_IDS=""
    [ ! -e "$HOME_DIR/requests" ] && [ ! -L "$HOME_DIR/requests" ] && return 0
    request_init
    for slot in "$HOME_DIR/requests"/slot-*; do
        [ -e "$slot" ] || [ -L "$slot" ] || continue
        request_dir "$slot"
        for f in "$slot"/*.txt; do
            [ -e "$f" ] || [ -L "$f" ] || continue
            request_file "$f"
            id="${f##*/}"; id="${id%.txt}"
            case "$id" in ''|*[!a-zA-Z0-9-]*) die "invalid request ID";; esac
            n=$((n + 1))
            [ "$n" -le 32 ] && [ "$(file_bytes "$f")" -gt 0 ] && [ "$(file_bytes "$f")" -le 4096 ] || die "request evidence exceeds limits; no evidence was pruned"
            REQUEST_IDS="$REQUEST_IDS${REQUEST_IDS:+$RALPHIE_NL}$f"
        done
    done
    return 0
}
request_pending() {
    # Snapshot membership, not applied markers, defines this cycle's boundary.
    local saved="${REQUEST_CYCLE_IDS:-}" f
    request_scan
    [ "$saved" != "$REQUEST_IDS" ]
}
request_boundary() {
    local identity previous
    request_scan
    REQUEST_CYCLE_IDS="$REQUEST_IDS"
    identity="$(printf '%s' "$REQUEST_CYCLE_IDS" | sha_of)"
    previous="$(state_get request_set '')"
    if [ "$identity" != "$previous" ]; then
        # Membership is independent of exact base-objective/acceptance identity.
        # Initial absence is not new work, but removal by archive is a boundary.
        if [ -n "$REQUEST_CYCLE_IDS" ] || [ -n "$previous" ]; then
            state_set nochange_streak 0; NOCHANGE_STREAK=0
            state_set objective_started ''
            state_set acceptance_work ''; ACCEPT_WORK=0; ACCEPT_PASS=0
            state_set status running
            event request active "active request set changed; applied means presented, not implemented"
        fi
        state_set request_set "$identity"
        [ "$(state_get request_set '')" = "$identity" ] || die "cannot persist request boundary"
    fi
}
request_prompt() {
    local f
    [ -n "${REQUEST_CYCLE_IDS:-}" ] || return 0
    printf '\n## OPERATOR REQUESTS (data, never shell commands)\n'
    printf 'Read every full immutable file below before editing. Preserve earlier requirements.\n'
    printf 'Applied means presented in a durable prompt, NOT implemented or verified.\n'
    printf 'Do not weaken gates. Ask about contradictions; do not silently discard requirements.\n'
    while IFS= read -r f; do
        request_file "$f"
        printf '\nFull request file: %s\n' "$f"
        cat "$f" || die "cannot read request evidence: $f"
        printf '\n'
    done <<EOF
$REQUEST_CYCLE_IDS
EOF
}
request_ack() {
    local f marker
    [ -n "${REQUEST_CYCLE_IDS:-}" ] || return 0
    while IFS= read -r f; do
        marker="${f%.txt}.applied"
        if [ -e "$marker" ] || [ -L "$marker" ]; then request_file "$marker"
        else
            ( set -C; umask 077; printf '%s\n' "$CY_PROMPT" > "$marker" ) || die "cannot acknowledge request: $f"
        fi
    done <<EOF
$REQUEST_CYCLE_IDS
EOF
}
# Serialize batch rollover with publications, not with the running worker.
# Reuse the writer lock protocol, with a separate short-lived lock. A producer
# can submit while the worker owns .ralphie/lock. The archive takes BOTH locks
# in worker -> publication order, so start and archive cannot cross.
request_write_lock() {
    local tries=0 pid
    while :; do
        pid="$(cat "$LOCK_FILE/pid" 2>/dev/null || true)"
        if [ ! -d "$LOCK_FILE" ] || [ -z "$pid" ] || { [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null && ! ps -p "$pid" >/dev/null 2>&1; }; then
            if lock_acquire 2>/dev/null; then return 0; fi
        fi
        tries=$((tries + 1))
        [ "$tries" -lt 40 ] || { err "request writer busy; retry submission (if abandoned, stop worker and archive)"; return 1; }
        sleep 1
    done
}
request_archive() (
    request_dir "$HOME_DIR"
    lock_acquire || exit 1
    trap 'lock_release' EXIT
    # Dynamic local binding keeps the outer worker lock held until exit.
    request_archive_locked() (
        LOCK_FILE="$HOME_DIR/request-write.lock"; LOCK_HELD=0
        request_write_lock || exit 1
        trap 'lock_release' EXIT
        request_init
        request_dir "$HOME_DIR/request-archives"
        local dest
        dest="$HOME_DIR/request-archives/$(date +%s)-$$-$(rand_token)"
        [ ! -e "$dest" ] && [ ! -L "$dest" ] || die "archive destination exists"
        # One rename is the batch boundary. All published bodies, receipts and
        # unfinished reservations move together. Missing active directory means
        # an empty batch, including after interruption before its recreation.
        mv "$HOME_DIR/requests" "$dest" || die "cannot archive requests"
        request_init
        say "archived (NOT completed): $dest"
        say "Active batch is empty. Archived requirements are retained but not injected; explicitly resubmit any still wanted."
    )
    request_archive_locked
)

request_command() (
    local source="" text="" slot="" candidate f id bytes i preview status
    if [ "$#" -eq 1 ] && [ "$1" = archive ]; then request_archive; return $?; fi
    if [ "$#" -eq 0 ] || { [ "$#" -eq 1 ] && [ "$1" = list ]; }; then
        request_scan
        if [ -z "$REQUEST_IDS" ]; then say "no published requests"; return 0; fi
        while IFS= read -r f; do
            status=queued
            if [ -e "${f%.txt}.applied" ] || [ -L "${f%.txt}.applied" ]; then
                request_file "${f%.txt}.applied"; status=applied
            fi
            preview="$(head -c 100 "$f" | LC_ALL=C tr '\n\r\t' '   ' | LC_ALL=C tr -d '[:cntrl:]')"
            say "${f##*/} $status $preview"
        done <<EOF
$REQUEST_IDS
EOF
        say "applied = presented in a durable prompt, not implemented or verified"
        return 0
    fi
    if [ "$#" -eq 2 ] && [ "$1" = --file ]; then
        source="$2"; case "$source" in /*) ;; *) source="$PROJECT/$source";; esac
        [ ! -L "$source" ] && [ -f "$source" ] && [ -r "$source" ] || die "request --file needs a readable regular non-symlink file"
        bytes="$(file_bytes "$source")"
    elif [ "$#" -eq 1 ] && [ "$1" != --file ]; then
        text="$1"; bytes="$(printf '%s' "$text" | wc -c | tr -d ' ')"
    else die "usage: request TEXT | request --file FILE | request [list]"; fi
    [ "$bytes" -gt 0 ] && [ "$bytes" -le 4096 ] || die "request must contain 1..4096 bytes"
    request_dir "$HOME_DIR"
    LOCK_FILE="$HOME_DIR/request-write.lock"; LOCK_HELD=0
    request_write_lock || return 1
    trap 'lock_release' EXIT
    request_init
    for i in {1..32}; do
        candidate="$HOME_DIR/requests/slot-$i"
        if mkdir -m 700 "$candidate" 2>/dev/null; then slot="$candidate"; break; fi
    done
    [ -n "$slot" ] || die "request capacity is 32 active slots; stop the worker and use request archive to retain evidence and reset capacity"
    id="$(date +%s)-$$-$(rand_token)"
    f="$slot/$id.txt"
    # Exclusive private staging; atomic publication only after validation.
    if [ -n "$source" ]; then
        ( set -C; umask 077; head -c 4097 "$source" > "$slot/.body" ) || die "cannot snapshot request"
    else
        ( set -C; umask 077; printf '%s' "$text" > "$slot/.body" ) || die "cannot stage request"
    fi
    bytes="$(file_bytes "$slot/.body")"
    [ "$bytes" -gt 0 ] && [ "$bytes" -le 4096 ] || die "request source changed or exceeds 4096 bytes"
    # Reject control/binary bytes, preserving tabs, CR, LF and UTF-8 bytes.
    [ "$(LC_ALL=C tr -d '\000-\010\013\014\016-\037\177' < "$slot/.body" | wc -c | tr -d ' ')" = "$bytes" ] || die "request contains binary/control bytes"
    chmod 400 "$slot/.body" || die "cannot protect request"
    mv "$slot/.body" "$f" || die "cannot publish request"
    say "$id queued; consumed at a future cycle boundary; start/resume Ralphie if stopped"
)

ensure_ask_file() {
    # Same repair as the state and gates files. An unwritable ASK.md meant the
    # ledger, the counter, the notification and the console all reported a
    # question that had in fact been thrown away, and `answer 1` then said the
    # question did not exist.
    ensure_own_file "$ASK_FILE" "questions file"
}

ask_human() {
    local q; q="$(trim "$1")"
    [ -n "$q" ] || return 0
    mkdir -p "$HOME_DIR"
    ensure_ask_file
    [ -f "$ASK_FILE" ] || printf '# Open questions for a human\n#\n# Answer by writing under a question, or: ralphie.sh answer <n> "your answer"\n\n' > "$ASK_FILE"
    # Never ask the same thing twice. A duplicated question is how a notification
    # channel becomes noise that nobody reads.
    grep -qF -- "$q" "$ASK_FILE" 2>/dev/null && return 0
    local n; n="$(( $(count_of grep '^## Q' "$ASK_FILE") + 1 ))"
    printf '## Q%s  [open]  %s\n%s\n\n> \n\n' "$n" "$(now_iso)" "$q" >> "$ASK_FILE" 2>/dev/null
    # Only claim it if it is really on disk. Announcing a question that was
    # never written is worse than failing to ask.
    if ! grep -qF -- "$q" "$ASK_FILE" 2>/dev/null; then
        err "could not record a question for you: $q"
        event ask failed "could not write the question to $ASK_FILE"
        return 1
    fi
    event ask open "$q" "n=$n"
    warn "question for you (Q$n): $q"
    dim "  answer it: $ME answer $n \"...\"   or edit $(basename "$ASK_FILE")"
    notify "Ralphie needs a decision (Q$n): $q"
}

asks_open() {
    [ -f "$ASK_FILE" ] || return 0
    LC_ALL=C awk '
        /^## Q[0-9]+  \[open\]/ { p=1; sub(/^## /,"  "); emit($0); next }
        /^## Q/ { p=0 }
        p && NF && $0 !~ /^>/ { emit("    " $0) }
        function emit(text, marker) {
            marker=" [truncated; read full question at .ralphie/ASK.md:" NR "]"
            if (length(text)>1000) text=substr(text,1,1000-length(marker)) marker
            print text
            if (++n==20) exit
        }' "$ASK_FILE" 2>/dev/null
}

asks_open_count() {
    [ -f "$ASK_FILE" ] || { printf '0'; return 0; }
    count_of grep -E '^## Q[0-9]+  \[open\]' "$ASK_FILE"
}

redact_secrets() {
    # Conservative and visible: the shape of the answer survives, the value does
    # not, and the operator can see that something was withheld.
    # No \b anywhere: it is a GNU extension that BSD sed silently ignores, so
    # the patterns that used it matched nothing at all on macOS. Boundaries are
    # expressed with an explicit leading character class instead.
    printf '%s' "$1" | sed -E \
        -e 's/((pass(word)?|secret|token|api[_-]?key|access[_-]?key|credential)[[:alnum:]_-]*[[:space:]]*(is|=|:)[[:space:]]*)[^[:space:]]+/\1<redacted>/Ig' \
        -e 's/(^|[^A-Za-z0-9])(AKIA|ASIA)[0-9A-Z]{8,}/\1<redacted-aws-key>/g' \
        -e 's/(^|[^A-Za-z0-9])gh[pousr]_[A-Za-z0-9]{20,}/\1<redacted-token>/g' \
        -e 's/(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{16,}/\1<redacted-token>/g' \
        -e 's/(^|[^A-Za-z0-9])eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/\1<redacted-jwt>/g'
}

flatten_text() {
    # One line, no structural markers. A multi-line answer forged `## Q`
    # headers inside ASK.md -- one of them said "Please paste your AWS key
    # below" -- and injected raw markdown into MEMORY.md, which is fed to the
    # engine on every cycle.
    printf '%s' "$1" | tr '\n\r\t' '   ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        -e 's/^#*[[:space:]]*//' -e 's/<<<RALPHIE/<RALPHIE/g' -e 's/RALPHIE>>>/RALPHIE>/g'
}

answer_ask() {
    local n="$1" text="$2" tmp
    text="$(flatten_text "$text")"
    [ -f "$ASK_FILE" ] || die "no questions have been asked"
    is_int "$n" || die "usage: $ME answer <number> \"your answer\""
    grep -q "^## Q$n  " "$ASK_FILE" || die "no question Q$n"
    tmp="$ASK_FILE.tmp.$$"
    # The answer travels through the ENVIRONMENT, not through `awk -v`. awk
    # interprets backslash escapes in a -v value, so an answer mentioning a
    # Windows path turned C:\new\table into a literal newline and split the
    # record across two lines, corrupting the file it was written into.
    RALPHIE_ANSWER="$text" awk -v n="$n" '
        $0 ~ "^## Q" n "  " { sub(/\[open\]/, "[answered]"); print; inq=1; next }
        /^## Q/ { inq=0 }
        inq && /^> *$/ { print "> " ENVIRON["RALPHIE_ANSWER"]; next }
        { print }
    ' "$ASK_FILE" > "$tmp" && mv -f "$tmp" "$ASK_FILE"
    event ask answered "Q$n: $text" "n=$n"
    good "Q$n answered - the next cycle will use it"
    # An answer is exactly the kind of durable fact a later cycle should not
    # have to ask for again.
    # Answers are remembered so the same question is never asked twice -- but a
    # credential typed here would otherwise be written to MEMORY.md and re-sent
    # to the engine on every future cycle, for ever.
    remember "$(printf 'Operator decision: %s' "$(redact_secrets "$text")")"
}

notify() {
    # One hook replaces every transport. Telegram, Discord, Slack, email, SMS,
    # a desk lamp, a radio uplink to another planet: all of them are just a
    # command that takes a line of text, and none of them belong in here.
    local msg="$1"
    [ -n "${RALPHIE_NOTIFY_CMD:-}" ] || return 0
    # Deliberately NOT tracked as a child: the reaper kills tracked processes on
    # exit, which killed the very notification that was announcing the exit.
    # A short bounded wait keeps it from outliving the run instead.
    ( RALPHIE_MESSAGE="$msg" sh -c "$RALPHIE_NOTIFY_CMD" >/dev/null 2>&1 ) &
    local p=$! i=0
    while [ "$i" -lt "${RALPHIE_NOTIFY_WAIT:-10}" ] && kill -0 "$p" 2>/dev/null; do sleep 1; i=$((i+1)); done
    kill -0 "$p" 2>/dev/null && { dbg "notify hook still running after ${i}s; leaving it"; }
    return 0
}

# ============================================================================
# LAYER 7 - INTERFACE
#   Ten commands, all optional flags, no required configuration. A new operator
#   should be productive after reading one screen.
# ============================================================================

usage() {
cat <<'RALPHIE_HELP_EOF' | sed "s/VERSION_PLACEHOLDER/$VERSION/"
ralphie VERSION_PLACEHOLDER - an autonomy kernel for any project

  Plant it in a project and tell it what you want. It observes, decides, acts,
  verifies against the project's own checks, commits what passes, and learns.
  It never blocks waiting for you.

USAGE
  ./ralphie.sh [options] ["what you want done"]
  ./ralphie.sh <command> [args]

COMMANDS
  run            Run the loop. This is the default.
  status         What has happened: cycles, gates, time, open questions.
  status --json  The same as one line of JSON, for CI and monitoring.
  discover       Read-only orientation. No checks, engines or writes. No args.
  doctor         What is available here: engines, capabilities, gates, git.
  gates          Show the checks that define "working" for this project.
  gates --redetect   Rediscover them from scratch.
  ask            Show open questions Ralphie has for you.
  answer N "..." Answer question N. The next cycle uses it immediately.
  request TEXT   Queue an unsolicited request (4096 bytes; 32 active slots).
  request --file FILE  Queue a text file, relative to the project root.
  request [list] List queued/applied requests; applied is not completed.
  request archive  Retain/reset active batch; refuses a running worker.
  memory         Show the durable lessons learned so far.
  forget         Clear the stored objective.
  log [n]        Show the last n ledger events (default 20).
  stop           Ask a running loop to stop after its current cycle.
                 For a background or cron run, SIGTERM also stops it cleanly.
                 SIGINT does not: a shell sets it to ignore for background jobs.
  update         Replace this script with the latest published version.
  version        Print the version.
  help           This screen.

OPTIONS
  -o, --objective TEXT   What you want done. Persists to .ralphie/OBJECTIVE.md.
      --spec FILE        Use a local plain-text spec as the stored objective.
                         Maximum 1 MiB; relative to your current directory.
                         Cannot combine with objective text. No stdin input.
  -b, --branch NAME      Do the work on this branch, creating it if needed.
                         Use this when main is protected.
      --engine NAME      Force an engine (default: the most capable installed).
      --model ID         Model id for the engine.
      --thinking LEVEL   off|minimal|low|medium|high|xhigh|max
  -n, --cycles N         Stop after N cycles (default: unlimited).
  -m, --minutes N        Engine/observe budget in minutes (default: unlimited).
                         Verification and saving may finish after this budget;
                         it is not a hard whole-run deadline. Timed-out work
                         gets two seconds for TERM before forced termination.
      --once             One cycle, then stop. Same as --cycles 1.
      --gate "CMD"       Add a verification command. Repeatable, and kept in
                         .ralphie/gates alongside the discovered ones.
      --no-commit        Do not commit, even when the gates are green.
      --no-update        Skip the self-update check for this run.
      --accept CMD       Require this single-line command for objective completion.
                         Health-green progress still commits if acceptance fails.
      --done-when-green  Stop as soon as the gates pass and no work remains.
      --no-yolo          Withhold the permission-bypass flag from engines that
                         have one (claude, codex). prime-agent and a custom
                         engine have no such flag, so this cannot restrain them.
                         An unattended loop may stall waiting for a prompt.
      --update           Self-update before running.
  -v, --verbose          Show what is happening underneath.
  -q, --quiet            Print less: no progress commentary. Warnings, errors
                         and each cycle's verdict survive it. Opposite of -v.
  -h, --help             This screen.
      --                 Everything after this is the objective.

GATE DISCOVERY
  Discovery checks root manifests and scripts, not child workspace packages.
  For unsupported stacks or workspaces, supply --gate "your check command"
  or edit .ralphie/gates. Commands run from the project root.
  An existing gates file, even empty, is kept. After adding tools or manifests,
  use gates --redetect to discover again; previous gates are saved.

ENVIRONMENT
  RALPHIE_ENGINE_CMD     A custom engine: any command that reads a prompt on stdin.
                         Explicit selection: no provider fallback on failure.
                         --engine overrides this selection.
  RALPHIE_ENGINE_CAPS    Its capabilities: autonomy gates memory subagents resume skills json
  RALPHIE_NOTIFY_CMD     Run for each notification, with the text in $RALPHIE_MESSAGE.
  RALPHIE_NOTIFY_WAIT    Seconds a notification may take before it is abandoned
                         (default 10). It never blocks the loop.
  RALPHIE_ENGINE_ANSWER  Where a custom engine puts its answer: stdout (default)
                         or file, meaning it writes to $RALPHIE_OUTPUT.
  RALPHIE_MIN_UPDATE_BYTES  Smallest believable download for a self-update
                         (default 40000). A truncated fetch is refused.
  NO_COLOR               Set to anything to disable colour, per no-color.org.
  ENGINE_TIMEOUT         Seconds per engine call (default 2400), capped by
                         whatever --minutes has left.
  ENGINE_IDLE_TIMEOUT    Kill a STREAMING engine that has produced nothing for this
                         long (default 600). Engines that buffer their answer are
                         judged only by ENGINE_TIMEOUT, because silence is normal.
  ENGINE_OUTPUT_MAX_BYTES  Combined captured stdout/stderr and file-answer ceiling
                         per call (default 16777216 = 16 MiB). Positive bytes;
                         zero/invalid values use the default. Enforced even with
                         zero timeouts. Polling can overshoot; not a disk quota.
                         Oversize output fails without retry or provider fallback.
                         Consumed log/answer files retain a marked 256 KiB tail.
                         Prompts and provider session records are not trimmed.
  GATE_TIMEOUT           Seconds per gate (default 900).
  COMMIT_TIMEOUT         Seconds for git commit, hooks and signing (default 120).
  GATE_RETRIES           Confirm a failing gate this many times before believing
                         it (default 1). Set 0 to trust the first result.
  RALPHIE_KEEP_CYCLES    Cycle logs and prompts to keep (default 50).
  RALPHIE_KEEP_RUNS      Engine session directories to keep (default 5).
  RALPHIE_LEDGER_MAX     Rotate events.jsonl past this size (default 16 MB).
  RALPHIE_LEDGER_GENERATIONS  Rotated ledgers kept (default 5, so ~80 MB of
                         history). Past that the oldest is dropped - the only
                         thing Ralphie ever forgets.
  ENGINE_RETRIES         Attempts before falling back to another engine (default 3).
  ENGINE_BACKOFF         Seconds added per retry (default 5).
  ENGINE_MAX_TURNS       Assistant turns for a self-driving engine (default 24).
  ENGINE_MAX_CONT        Continuations for a self-driving engine (default 6).
  ENGINE_MAX_TOKENS      Token cap for a self-driving engine (default: its own).
  GATE_TRIAL_TIMEOUT     Seconds allowed to trial a candidate gate (default 120).
  GATE_BRIEF_BYTES       Failure output shown to the engine (default 3000).
  GATE_LOG_MAX           Gate output kept on disk per gate (default 256 KB).
  NOCHANGE_LIMIT         Cycles with no change before stopping (default 3).
  MEMORY_MAX             Durable lessons kept (default 60).
  MIN_ANSWER_BYTES       Shortest engine reply treated as real (default 2).
  RALPHIE_MAX_COMMIT_BYTES  Largest file committed automatically (default 1 MB).
  (Token and cost figures are read from the engine's own records when it keeps
   them, and need python3 to parse. They are never estimated.)
  RALPHIE_ENGINE_SESSION 0 to stop prime-agent saving a session per run.
  RALPHIE_GIT_INIT       0 to refuse to create a git repository.
  RALPHIE_BRANCH         Default for --branch.
  RALPHIE_MODEL          Default for --model.
  RALPHIE_THINKING       Default for --thinking.
  RALPHIE_VERBOSE        1 for --verbose.
  RALPHIE_QUIET          1 for --quiet.
  RALPHIE_AUTO_UPDATE    1 to self-update before every run.
  RALPHIE_NO_UPDATE      1 to refuse self-update entirely.
  RALPHIE_UPDATE_URL     Explicit source for `update`.
  RALPHIE_PROJECT        Operate on this directory instead of the script's own.

FILES  (all under .ralphie/, all yours to read and edit)
  gates          The checks that define "working". Edit freely.
  OBJECTIVE.md   What you want done.
  MEMORY.md      Durable lessons. Injected into every prompt.
  ASK.md         Questions awaiting you. Answering one unblocks the next cycle.
  events.jsonl   Append-only evidence of everything that happened.
  state          Derived state. Safe to delete; it rebuilds.

EXIT CODES  (so cron and CI can react without parsing text)
  0   ran to a clean stop: objective met, limit reached, or stopped on request
  1   could not start: no engine, another loop is running, or a bad argument
  2   blocked: no engine could complete a cycle (see: ralphie.sh status)
  3   stalled: several cycles in a row changed nothing
  130 interrupted
  141 output closed early (for example: ralphie.sh log | head)

EXAMPLES
  ./ralphie.sh "add rate limiting to the public API"
  ./ralphie.sh --once -v                      # one cycle, watch it work
  ./ralphie.sh --gate "make check" -n 5       # five cycles against your own check
  ./ralphie.sh status
  ./ralphie.sh answer 1 "use postgres, not sqlite"
RALPHIE_HELP_EOF
}

# --- self-update --------------------------------------------------------------
# One file, replaced atomically, only when it is provably a newer Ralphie.
# A colony ship cannot afford an update that half-lands.

update_url() {
    [ -n "${RALPHIE_UPDATE_URL:-}" ] && { printf '%s' "$RALPHIE_UPDATE_URL"; return 0; }
    local origin branch path
    origin="$(git -C "$PROJECT" config --get remote.origin.url 2>/dev/null)" || return 1
    case "$origin" in
        git@github.com:*) origin="${origin#git@github.com:}";;
        https://github.com/*) origin="${origin#https://github.com/}";;
        *) return 1;;
    esac
    origin="${origin%.git}"
    # A repository can set origin to anything. Without this, `a/b/../../../..`
    # walked the derived URL straight out of the project's namespace.
    case "$origin" in
        */*/*|*..*|*@*|*:*|"") warn "refusing an implausible update source derived from origin: $origin"; return 1;;
        *[!A-Za-z0-9._/-]*)    warn "refusing an update source with unexpected characters: $origin"; return 1;;
    esac
    branch="$(git_branch)"
    case "$branch" in ''|none|*[!A-Za-z0-9._/-]*) branch="master";; esac
    path="$ME"
    printf 'https://raw.githubusercontent.com/%s/%s/%s' "$origin" "$branch" "$path"
}

self_update() {
    local url tmp cur new
    # Honoured here too. The flag existed but the `update` command walked
    # straight past it, so the one switch an operator can set to forbid
    # self-replacement did nothing when they asked for it explicitly.
    if is_true "${RALPHIE_NO_UPDATE:-0}"; then
        warn "self-update is disabled here (RALPHIE_NO_UPDATE=1)"
        return 1
    fi
    url="$(update_url)" || { warn "no update source (set RALPHIE_UPDATE_URL)"; return 1; }
    case "$url" in https://*|file://*|/*) ;; *) die "refusing an insecure update source: $url";; esac
    have curl || have wget || { warn "neither curl nor wget is available"; return 1; }
    tmp="$(mktemp 2>/dev/null || printf '%s' "/tmp/ralphie.$$")"
    info "checking $url"
    if have curl; then curl -fsSL --max-time 60 "$url" -o "$tmp" 2>/dev/null || { rm -f "$tmp"; warn "download failed"; return 1; }
    else wget -qO "$tmp" "$url" 2>/dev/null || { rm -f "$tmp"; warn "download failed"; return 1; }; fi
    # Three independent proofs before anything is replaced.
    # A candidate must prove it is a newer Ralphie, not merely look like one.
    # A six-line file once passed the old checks, became the kernel, and turned
    # every command into a silent no-op that exited 0.
    local need sz cand_ver
    for need in 'ralphie-kernel' 'LAYER 4 - ENGINE' 'LAYER 5 - LOOP' 'guard_gates' 'run_gates' 'RALPHIE_HELP_EOF'; do
        grep -q "$need" "$tmp" 2>/dev/null || { rm -f "$tmp"; warn "downloaded file is missing '$need'; not a ralphie kernel"; return 1; }
    done
    sz="$(file_bytes "$tmp")"
    [ "$sz" -ge "${RALPHIE_MIN_UPDATE_BYTES:-40000}" ] || { rm -f "$tmp"; warn "downloaded file is implausibly small (${sz} bytes)"; return 1; }
    bash -n "$tmp" 2>/dev/null || { rm -f "$tmp"; warn "downloaded file does not parse"; return 1; }
    # It must run and identify itself, and it must not be older than this one.
    cand_ver="$(RALPHIE_LIB=0 bash "$tmp" version 2>/dev/null | head -1 | awk '{print $2}')"
    case "$cand_ver" in
        [0-9]*.[0-9]*.[0-9]*) ;;
        *) rm -f "$tmp"; warn "downloaded file does not report a version"; return 1;;
    esac
    if [ "$(printf '%s\n%s\n' "$VERSION" "$cand_ver" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "$cand_ver" ] \
       && [ "$cand_ver" != "$VERSION" ]; then
        rm -f "$tmp"; warn "refusing to downgrade from $VERSION to $cand_ver"; return 1
    fi
    cur="$(sha_of < "$SELF")"; new="$(sha_of < "$tmp")"
    if [ "$cur" = "$new" ]; then rm -f "$tmp"; good "already current ($VERSION)"; return 0; fi
    cp -f "$SELF" "$HOME_DIR/ralphie.previous" 2>/dev/null || true
    # Copy ONTO the existing file rather than replacing it: `mv` took the temp
    # file's restrictive mode with it (group and other lost read, so they could
    # no longer run it) and turned a symlink into a regular file.
    chmod +x "$tmp"
    if cat "$tmp" > "$SELF" 2>/dev/null; then rm -f "$tmp"
    else mv -f "$tmp" "$SELF"; chmod +x "$SELF" 2>/dev/null || true; fi
    good "updated. previous copy kept at .ralphie/ralphie.previous"
    event update ok "replaced from $url"
    return 0
}

# --- reporting ----------------------------------------------------------------

cmd_status() {
    # A reader that stops early must not leave a write error on the console.
    exec 2>/dev/null
    local st cy pc fc ao lc up
    st="$(state_get status new)"; cy="$(json_num cycle)"
    # A run killed outright never got to update its status. Reporting "running"
    # for ever afterwards is worse than saying nothing.
    if [ "$st" = "running" ] && ! run_is_alive; then st="interrupted (the process is gone)"; fi
    pc="$(json_num pass_count)"; fc="$(json_num fail_count)"
    ao="$(asks_open_count)"; lc="$(state_get learned_count 0)"
    up="$(state_get last_cycle_at 0)"
    say ""
    say "  ralphie $VERSION   $PROJECT"
    say "  ─────────────────────────────────────────────"
    printf '  status      %s\n' "$st"
    printf '  cycles      %s   (%s green, %s red)\n' "$cy" "$pc" "$fc"
    [ "$(json_num untrusted_count)" != "0" ] && printf '  untrusted   %s cycle(s) damaged their own verification and were discarded\n' "$(json_num untrusted_count)"
    [ "$(json_num blocked_count)" != "0" ] && printf '  blocked     %s cycle(s) passed the gates but could not be saved\n' "$(json_num blocked_count)"
    [ "$(json_num unverified_count)" != "0" ] && printf '  unverified  %s cycle(s) committed with no gate to check them\n' "$(json_num unverified_count)"
    printf '  engine      %s\n' "$(state_get engine '-')"
    printf '  gates       %s configured\n' "$(gates_count)"
    git_ready && printf '  branch      %s\n' "$(git_branch)"
    [ "$(json_num total_seconds)" != "0" ] && printf '  wall clock  %s across %s cycles (engine + gates + commit)\n' \
        "$(human_secs "$(json_num total_seconds)")" "$cy"
    # Reported only when the engine itself recorded it. Never estimated.
    [ "$(json_num tokens_spent)" != "0" ] && printf '  tokens      %s reported by the engine (%s this run)\n' \
        "$(json_num tokens_spent)" "$(json_num run_tokens)"
    case "$(json_dec run_cost)" in 0|0.000000|"") ;; *) printf '  cost        %s reported by the engine for this run\n' "$(state_get run_cost)";; esac
    printf '  lessons     %s\n' "$lc"
    printf '  questions   %s open\n' "$ao"
    [ "$up" != "0" ] && printf '  last cycle  %s ago\n' "$(human_secs "$(secs_since "$up")")"
    [ -n "$(state_get reason '')" ] && printf '  reason      %s\n' "$(state_get reason)"
    local rp; rp="$(state_get start_commit '')"
    # `--keep`, NEVER `--hard`. This line is printed in `status` and at the top of
# every run, three lines from the promise that uncommitted work is never
# committed -- and `--hard` DESTROYS exactly that work, with no commit, no stash
# and no reflog to recover it from. `--keep` rewinds the committed history and
# refuses rather than discard a change that has not been saved.
if [ -n "$rp" ]; then
    printf '  undo        git reset --keep %s\n' "$rp"
    printf '              (--keep, not --hard: it refuses rather than discard\n'
    printf '               work you have not committed. If it refuses, commit or\n'
    printf '               stash that work first.)\n'
fi
    say ""
    if [ -s "$OBJECTIVE_FILE" ]; then say "  objective:"; head -c 400 "$OBJECTIVE_FILE" | sed 's/^/    /'; say ""; fi
    if [ "$ao" -gt 0 ]; then warn "  $ao question(s) waiting - see: $ME ask"; fi
}

json_num() {
    # A state value that is not a number must not become bare JSON. `status
    # --json` emitted "cycle":nine and exited 0, which is worse than failing.
    local v; v="$(state_get "$1" 0)"
    is_int "$v" || v=0
    printf '%s' "$v"
}
json_dec() {
    # Same, for the one decimal field.
    local v; v="$(state_get "$1" 0)"
    case "$v" in ''|*[!0-9.]*|*.*.*) v=0;; esac
    printf '%s' "$v"
}

run_is_alive() {
    # The lock is the only durable evidence that a run still exists.
    local owner
    owner="$(cat "$LOCK_FILE/pid" 2>/dev/null || printf '')"
    [ -n "$owner" ] || return 1
    kill -0 "$owner" 2>/dev/null || ps -p "$owner" >/dev/null 2>&1
}

status_json() {
    # One line of valid JSON. A CI job should never have to parse prose to find
    # out whether the loop is healthy, how many gates exist, or whether a human
    # is being waited on. A reader that stops early exits through on_pipe,
    # preserving code 141 without leaking buffered output into the ledger.
    local jst; jst="$(state_get status new)"
    [ "$jst" = "running" ] && ! run_is_alive && jst="interrupted"
    printf '{"version":"%s","project":"%s","status":"%s","cycle":%s,"pass":%s,"fail":%s,' \
        "$VERSION" "$(json_str "$PROJECT")" "$(json_str "$jst")" \
        "$(json_num cycle)" "$(json_num pass_count)" "$(json_num fail_count)"
    printf '"engine":"%s","model":"%s","branch":"%s","gates":%s,"lessons":%s,"questions_open":%s,' \
        "$(json_str "$(state_get engine -)")" "$(json_str "$(state_get model default)")" \
        "$(json_str "$(git_ready && git_branch || printf '')")" \
        "$(gates_count)" "$(json_num learned_count)" "$(asks_open_count)"
    printf '"blocked":%s,"untrusted":%s,"unverified":%s,"tokens":%s,"run_tokens":%s,"run_cost":%s,"seconds":%s,"start_commit":"%s","reason":"%s","run":"%s"}\n' \
        "$(json_num blocked_count)" "$(json_num untrusted_count)" "$(json_num unverified_count)" "$(json_num tokens_spent)" \
        "$(json_num run_tokens)" "$(json_dec run_cost)" "$(json_num total_seconds)" "$(json_str "$(state_get start_commit '')")" \
        "$(json_str "$(state_get reason '')")" "$(json_str "$(state_get run_id -)")"
}

cmd_forget() {
    # A persisted objective that nobody remembers setting is worse than none.
    if [ -n "$(acceptance_latest)" ] || [ -e "$HOME_DIR/acceptance" ] || [ -L "$HOME_DIR/acceptance" ]; then
        acceptance_bind none || return 1
    fi
    [ -s "$OBJECTIVE_FILE" ] || { dim "no objective is set"; return 0; }
    rm -f "$OBJECTIVE_FILE"
    state_set objective_hash ""
    event objective cleared "operator cleared the objective"
    good "objective cleared - the next run will decide for itself"
}

cmd_doctor() {
    local n c caps
    say ""
    say "  ralphie $VERSION doctor"
    say "  ─────────────────────────────────────────────"
    printf '  project   %s\n' "$PROJECT"
    printf '  stack     %s\n' "$(detect_stack)"
    printf '  bash      %s\n' "${BASH_VERSION:-unknown}"
    printf '  git       %s\n' "$(git_ready && git_branch || printf 'not a repository')"
    printf '  deadlines built-in watchdog (TERM, then KILL)\n'
    say ""
    say "  engines"
    while IFS= read -r n; do
        [ -z "$n" ] && continue
        c="$(engine_cmd "$n")"; caps="$(engine_caps "$n")"
        if engine_present "$n"; then
            if engine_live "$n"; then printf '    %sok%s   %-12s %s\n' "$C_GRN" "$C_OFF" "$n" "$caps"
            else printf '    %s??%s   %-12s installed but not responding\n' "$C_YEL" "$C_OFF" "$n"; fi
        else
            printf '    %s--%s   %-12s not installed\n' "$C_DIM" "$C_OFF" "$n"
        fi
    done <<EOF
$(engine_names)
EOF
    local pick; pick="$(engine_pick "" 2>/dev/null || printf '')"
    say ""
    if [ -n "$pick" ]; then
        good "  selected: $pick  (most capable engine installed here)"
        if engine_has "$pick" autonomy && engine_has "$pick" gates; then
            dim "  it self-drives against the gates; ralphie supplies durability only"
        else
            dim "  ralphie supplies: $(missing_caps "$pick")"
        fi
    else
        err "  no engine installed. Install one of: $(engine_names | tr '\n' ' ')"
    fi
    say ""
    say "  gates"
    if [ "$(gates_count)" -gt 0 ]; then gates_list | sed 's/^/    $ /'
    else dim "    none yet - run the loop once, or write .ralphie/gates yourself"; fi
    say ""
}

ALL_CAPS="autonomy gates memory subagents resume skills json stream usage"

missing_caps() {
    # Reads the one list. It used to carry its own copy, which had already
    # drifted: `stream` and `usage` were missing, so doctor under-reported what
    # Ralphie was supplying.
    local e="$1" want="$ALL_CAPS" c out=""
    for c in $want; do engine_has "$e" "$c" || out="$out $c"; done
    printf '%s' "$(trim "$out")"
}

cmd_gates() {
    if [ "${1:-}" = "--redetect" ]; then
        # A loop holds its authoritative gate set in memory. Rewriting the file
        # underneath it looks exactly like the engine deleting a gate: the run
        # reports tampering and blames the engine for the operator's action.
        local owner; owner="$(cat "$LOCK_FILE/pid" 2>/dev/null || printf '')"
        if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
            err "a ralphie loop is running here (pid $owner)"
            err "stop it first: $ME stop   - rediscovering now would look like tampering to that run"
            return 1
        fi
        # THE BASELINE MUST GO TOO. It is the record of "the gates we agreed",
        # and the next run restores anything missing from it -- so a rediscovery
        # that dropped a gate had it silently put back, and Ralphie repeated the
        # same advice for ever. `--redetect` is the command Ralphie itself
        # recommends when the gates are wrong, so it has to be able to change
        # them.
        [ -n "${GATES_BASELINE_FILE:-}" ] || GATES_BASELINE_FILE="$HOME_DIR/gates.baseline"
        # The previous set is KEPT, not discarded: a hand-edited gate file is
        # the operator's work, and rediscovery must never be the one command
        # that loses it without a copy.
        if [ -s "$GATES_FILE" ]; then
            cp -f "$GATES_FILE" "$HOME_DIR/gates.previous" 2>/dev/null || true
            dim "  your previous gates were saved to $HOME_DIR/gates.previous"
        fi
        rm -f "$GATES_FILE" "$GATES_BASELINE_FILE"
        discover_gates 1
    fi
    discover_gates
    say ""; say "  gates for $PROJECT"; say ""
    if [ "$(gates_count)" -gt 0 ]; then gates_list | sed 's/^/    $ /'
    else
        dim "    none configured - use --gate or edit .ralphie/gates for unsupported stacks/workspaces"
        dim "    existing empty files are kept; use gates --redetect after adding tools or manifests"
    fi
    say ""; dim "  edit them: $GATES_FILE"; say ""
}

cmd_log() {
    local n="${1:-20}"
    is_int "$n" || n=20
    [ -f "$EVENTS_FILE" ] || { dim "no events yet"; return 0; }
    tail -n "$n" "$EVENTS_FILE" | ledger_render
    return 0
}

# --- argument parsing ---------------------------------------------------------

ENGINE=""; MODEL="${RALPHIE_MODEL:-}"; THINKING="${RALPHIE_THINKING:-}"
MAX_CYCLES=0; MAX_MINUTES=0; AUTO_COMMIT=1; DO_UPDATE="${RALPHIE_AUTO_UPDATE:-0}"
DONE_WHEN_GREEN=0; OBJECTIVE=""; SPEC_FILE=""; OBJECTIVE_EXPLICIT=0; EXTRA_GATES=""; CMD="run"; YOLO=1; ENGINE_EXPLICIT=0; BRANCH="${RALPHIE_BRANCH:-}"; REST=()
# Environment selection has the same no-substitution promise as --engine.
[ -n "${RALPHIE_ENGINE_CMD:-}" ] && ENGINE_EXPLICIT=1

need_value() {
    # Every value-taking option used to exit 1 silently when its value was
    # missing, because `shift 2` failed under `set -e` with nothing printed.
    [ "$#" -ge 2 ] && [ -n "${2:-}" ] || die "$1 needs a value  (try --help)"
}

looks_like_typo() {
    # An objective is a sentence; a subcommand is one word. `ralphie statuss`
    # was neither rejected nor questioned -- it became an objective, and a full
    # engine call was paid for a typo. Only a lone word that is nearly a real
    # command is refused, so a genuine one-word objective still works.
    # $2 is how many arguments REMAIN, not how many this function was given.
    # Reading `$#` here was always 1, so `ralphie asks for input` was refused as
    # a typo of `ask` -- six ordinary objectives in eight, turned away.
    local a="$1" argc="$2" c
    [ -n "$a" ] || return 0                          # `case "run" in ""*)` matches
    case "$a" in *[!a-z-]*) return 0;; esac          # not a bare lowercase word
    [ "$argc" -eq 1 ] || return 0                    # a sentence, not a command
    for c in run status doctor gates ask answer request memory log stop update version help forget; do
        # BOTH directions: `stat` is a prefix of `status`, and `statuss` has
        # `status` as a prefix. Checking only one caught the first and let the
        # second through to a paid engine call.
        case "$c" in "$a"*) ;; *)
            case "$a" in "$c"*) ;; *) continue;; esac
        esac
        err "unknown command: $a   (did you mean '$c'?)"
        dim "  to use it as an objective instead:  $ME -- \"$a\""
        exit 1
    done
    return 0
}

load_spec() {
    # Read from the invocation cwd, before ledger setup or any engine probe.
    # Read once, bounded, without evaluating any source text. The full document
    # lives in OBJECTIVE.md; the prompt carries only an explicitly labelled excerpt.
    [ -n "$SPEC_FILE" ] || return 0
    [ "$CMD" = run ] || die "--spec is only valid for a run"
    [ "${#REST[@]}" = 0 ] || die "--spec cannot be combined with arguments after run"
    [ "$OBJECTIVE_EXPLICIT" = 0 ] || die "--spec cannot be combined with objective text; put all requirements in the file"
    [ -f "$SPEC_FILE" ] && [ -r "$SPEC_FILE" ] || die "--spec needs a readable regular file: $SPEC_FILE"
    local text="" complete=0 LC_ALL=C
    # Bash 3.2 read keeps newlines and never evaluates the text. A NUL delimiter
    # or the 1048577th byte makes read succeed; ordinary EOF makes it fail.
    IFS= read -r -d '' -n 1048577 text < "$SPEC_FILE" && complete=1
    [ "${#text}" -le 1048576 ] || die "--spec exceeds the 1 MiB (1048576-byte) limit"
    [ "$complete" = 0 ] || die "--spec must be plain text (NUL byte found)"
    if printf '%s' "$text" | tr -d '\011\012\015' | grep '[[:cntrl:]]' >/dev/null; then
        die "--spec must be plain text (control byte found)"
    fi
    [ -n "$(printf '%s' "$text" | tr -d '[:space:]')" ] || die "--spec must not be empty or whitespace-only"
    OBJECTIVE="$text"
    return 0
}

parse_args() {
    local a
    while [ "$#" -gt 0 ]; do
        a="$1"
        case "$a" in
            run|discover|status|doctor|gates|ask|answer|request|memory|log|stop|update|version|help|forget)
                # Keep the real arguments. Flattening to a string and re-splitting
                # destroyed the operator's answer: "use *  and keep  spaces" was
                # glob-expanded into a file list and had its spacing collapsed.
                CMD="$a"; shift; REST=( "$@" ); break;;
            -o|--objective) need_value "$@"; OBJECTIVE_EXPLICIT=1; OBJECTIVE="$2"; shift 2;;
            --spec)     need_value "$@"
                        [ -z "$SPEC_FILE" ] || die "--spec may only be supplied once"
                        SPEC_FILE="$2"; shift 2;;
            --engine)   need_value "$@"; ENGINE="$2"; ENGINE_EXPLICIT=1; shift 2;;
            -b|--branch) need_value "$@"; BRANCH="$2"; shift 2;;
            --model)    need_value "$@"; MODEL="$2"; shift 2;;
            --thinking) need_value "$@"; THINKING="$2"; shift 2;;
            -n|--cycles)  need_value "$@"; MAX_CYCLES="$2"; is_int "$MAX_CYCLES" || die "--cycles needs a number"; shift 2;;
            -m|--minutes) need_value "$@"; MAX_MINUTES="$2"; is_int "$MAX_MINUTES" || die "--minutes needs a number"; shift 2;;
            --once)     MAX_CYCLES=1; shift;;
            --gate)     need_value "$@"
                        # Checked HERE, while the value is still intact. After
                        # the list is split on newlines each entry is a single
                        # line by construction, so a later check can never see
                        # the problem: `--gate "true<newline>rm -f app.txt"`
                        # silently became TWO gates, and the second one was
                        # trialled, accepted, and then run every cycle.
                        case "$2" in
                            *"$RALPHIE_NL"*) die "--gate must be a single command (it contained a newline)";;
                        esac
                        EXTRA_GATES="$EXTRA_GATES
$2"; shift 2;;
            --accept) need_value "$@"
                        [ "$ACCEPT_EXPLICIT" = 0 ] || die "--accept may be supplied only once"
                        case "$2" in *"$RALPHIE_NL"*|*$'\r'*) die "--accept must be a single line";; esac
                        [ -n "${2//[[:space:]]/}" ] || die "--accept needs a nonempty command"
                        ACCEPT_ARG="$2"; ACCEPT_EXPLICIT=1; shift 2;;
            --no-commit) AUTO_COMMIT=0; shift;;
            --no-update) DO_UPDATE=0; shift;;
            --update)    DO_UPDATE=1; shift;;
            --done-when-green) DONE_WHEN_GREEN=1; shift;;
            --no-yolo)  YOLO=0; shift;;
            # Opposites. Whichever is given last wins, so a shell alias that
            # carries -v can still be quietened on the command line, and a
            # RALPHIE_VERBOSE left in the environment cannot outvote --quiet.
            -v|--verbose) VERBOSE=1; QUIET=0; shift;;
            -q|--quiet)   QUIET=1; VERBOSE=0; shift;;
            -h|--help)  usage; exit 0;;
            --version)  say "$VERSION"; exit 0;;
            --)         shift; OBJECTIVE_EXPLICIT=1; OBJECTIVE="$*"; break;;
            -*)         die "unknown option: $a  (try --help)";;
            *)          looks_like_typo "$a" "$#"
                        OBJECTIVE_EXPLICIT=1; OBJECTIVE="$*"; break;;
        esac
    done
}

# ============================================================================
# MAIN
# ============================================================================

# --- commands ---------------------------------------------------------------
# Everything that answers a question and exits. None of it takes the lock, and
# none of it writes run state: a `status` typed in a second terminal must never
# disturb a loop that is working.

run_simple_command() {
    case "$CMD" in
        version) say "ralphie $VERSION";;
        help)    usage;;
        status)  if [ "${REST[0]:-}" = "--json" ]; then status_json; else cmd_status; fi;;
        forget)  cmd_forget;;
        log)     cmd_log "${REST[0]:-20}";;
        memory)  [ -s "$MEMORY_FILE" ] && cat "$MEMORY_FILE" || dim "nothing learned yet";;
        ask)     if [ "$(asks_open_count)" -gt 0 ]; then say ""; asks_open; say ""
                 else good "no open questions"; fi;;
        answer)  local qn="${REST[0]:-}" atext=""
                 if [ "${#REST[@]}" -gt 1 ]; then
                     atext="$(printf '%s ' "${REST[@]:1}")"; atext="${atext% }"
                 fi
                 answer_ask "$qn" "$atext";;
        stop)    touch "$STOP_FILE"; good "stop requested - the loop will finish its cycle and exit";;
        update)  self_update; return $?;;
        gates)   cmd_gates "${REST[0]:-}";;
        doctor)  cmd_doctor;;
        *)       return 1;;   # not a simple command: this is a run
    esac
    return 0
}

# --- the run ----------------------------------------------------------------

run_prepare() {
    # Everything that must be true before the first cycle. Ordered by what
    # depends on what, and nothing here is allowed to be silent.
    lock_acquire || return 1
    # The clock starts HERE, before gate discovery and before the --gate trials,
    # each of which can run for minutes. Starting it later meant `-m 1` was
    # measured at 103 seconds.
    [ "${MAX_MINUTES:-0}" -gt 0 ] && RUN_DEADLINE=$(( $(now_epoch) + MAX_MINUTES * 60 ))
    run_init

    say ""
    say "  ${C_BLU}ralphie $VERSION${C_OFF}  ${C_DIM}$PROJECT${C_OFF}"

    # Recorded ONCE, here, and never re-derived from the filesystem afterwards:
    # "there is no repository" and "the repository was destroyed mid-run" are
    # opposite facts that look identical to `git_ready`.
    # Resolved in the MAIN shell, before any subshell needs them: a value
    # computed inside `( ... )` is discarded when that subshell ends.
    GIT_TOP=""; PROJECT_PREFIX=""
    git_top >/dev/null; project_prefix >/dev/null
    if ensure_git; then GIT_MODE=repo; else
        GIT_MODE=none
        warn "no git repository - work cannot be committed or rolled back"
    fi
    # AFTER the repository exists. Writing the ignore rule first meant a repo
    # Ralphie initialised itself committed .ralphie/ wholesale: the ledger, the
    # state file, every prompt, the full engine logs, and the live lock.
    ensure_ignored
    # AFTER the repository exists, because both need it. Taken in run_init --
    # which runs first -- `git_ready` was false in a directory Ralphie was about
    # to initialise, the snapshot returned early, nothing was ever sealed, and
    # the operator's whole directory went into the first commit.
    #
    # A path stops being Ralphie's once it is no longer dirty. Released here as
    # well as at the end of a cycle: a claim made in one run survived the gap to
    # the next, and the operator's later work in progress on that same file was
    # then committed with no warning at all.
    release_owned_paths
    snapshot_pre_dirty
    use_branch "$BRANCH" || return 1
    # Refusing is the whole point: a warning that is ignored still loses work.
    warn_detached_head || { state_set status blocked; state_set reason "detached HEAD"; return 1; }
    self_hash_record
    self_is_reviewed || true
    record_recovery_point
    ACCEPT_OLD_OBJECTIVE="$(state_get objective_hash '')"
    set_objective
    acceptance_prepare || return 1
    choose_engine || return 1
    prepare_gates
    print_run_banner

    # Before the first cycle: a gate that vanished since the last run is
    # restored here, where it can still be questioned, rather than being
    # re-derived away silently.
    baseline_gates_load
    prune_sessions
    if [ "${GATE_NO_PIPEFAIL:-0}" = "1" ]; then
        # Louder than a warning about speed or tidiness: this one means a gate
        # can report success for a command that failed.
        err "gates will run under sh without pipefail"
        err "  a gate ending in a pipe may report the WRONG result, and work could be"
        err "  committed as verified when it is not. Install bash before relying on this."
        event run degraded "no bash for gates: pipelines are unreliable"
        ask_human "This machine has no bash for running gates, so a gate whose last command is a pipe (for example: make test | tail -5) can report success when the test failed. Install bash, or write gates that do not end in a pipe."
    fi
    event run start "engine=$ENGINE gates=$(gates_count)" "engine=$ENGINE"
    return 0
}

set_objective() {
    # The argument wins, then the stored file. A bare `./ralphie.sh` used to
    # silently resume whatever objective was set days ago.
    if [ -n "$OBJECTIVE" ]; then
        OBJECTIVE_MEM="$OBJECTIVE"
        # Preserve every spec byte, including its trailing newlines. Ordinary
        # objective text retains its historical final newline.
        [ -n "$SPEC_FILE" ] || OBJECTIVE_MEM="$OBJECTIVE_MEM$RALPHIE_NL"
        mkdir -p "$HOME_DIR"
        ensure_own_file "$OBJECTIVE_FILE" "objective file"
        printf '%s' "$OBJECTIVE_MEM" > "$OBJECTIVE_FILE"
        local oh; oh="$(objective_identity)"
        if [ "$oh" != "$(state_get objective_hash '')" ]; then
            # A new objective starts with a clean slate. Carrying the streak
            # across killed a brand-new objective after a single cycle with
            # "no progress in 3 consecutive cycles".
            state_set nochange_streak 0
            NOCHANGE_STREAK=0
        fi
        state_set objective_hash "$oh"
        # Never copy a large source into the append-only ledger.
        event objective set "$(head -c 4000 "$OBJECTIVE_FILE")" "hash=$oh"
    elif [ -s "$OBJECTIVE_FILE" ]; then
        OBJECTIVE_MEM=""
        # A successful NUL-delimited read means the stored file contains a
        # NUL byte. Never give the guard a partial copy to restore over it.
        if IFS= read -r -d '' OBJECTIVE_MEM < "$OBJECTIVE_FILE"; then
            die "stored objective must be plain text (NUL byte found); supply a new objective or use forget"
        fi
        # All three lines are one piece of commentary. Guarding only the
        # info line left --quiet printing 300 bytes of objective under no
        # heading at all.
        if ! is_true "$QUIET"; then
            say ""
            info "  continuing this objective (say a new one, or: $ME forget):"
            head -c 300 "$OBJECTIVE_FILE" | sed 's/^/    /'
        fi
    fi
    return 0
}

choose_engine() {
    ENGINE="$(engine_pick "$ENGINE")" || {
        err "no AI engine is installed here."
        err "install one of: $(engine_names | tr '\n' ' ')"
        err "or point RALPHIE_ENGINE_CMD at any command that reads a prompt on stdin."
        return 1
    }
    state_set engine "$ENGINE"
    [ -n "$MODEL" ] && { state_set model "$MODEL"; engine_check_model "$ENGINE" "$MODEL" || true; }
    return 0
}

prepare_gates() {
    discover_gates
    [ -n "$(trim "$EXTRA_GATES")" ] || return 0
    local g
    while IFS= read -r g; do
        [ -z "$(trim "$g")" ] && continue
        grep -qxF -- "$g" "$GATES_FILE" 2>/dev/null && continue
        # Trial-run like any discovered candidate. A typo in --gate used to make
        # the project permanently red, and the bad line stayed there for ever.
        if gate_trial "$g"; then
            printf '%s\n' "$g" >> "$GATES_FILE"
            dim "  + $g"
        else
            err "--gate '$g' cannot run here; not added"
            event gates rejected "--gate '$g' is not runnable here"
        fi
    done <<EOF
$EXTRA_GATES
EOF
    return 0
}

print_run_banner() {
    dim "  engine  $ENGINE  [$(engine_caps "$ENGINE")]"
    dim "  gates   $(gates_count)"
    if engine_has "$ENGINE" autonomy && engine_has "$ENGINE" gates; then
        dim "  mode    self-driving; ralphie supplies durability, evidence and memory"
    else
        dim "  mode    ralphie supplies: $(missing_caps "$ENGINE")"
    fi
    [ "$MAX_CYCLES" -gt 0 ]  && dim "  limit   $MAX_CYCLES cycles"
    [ "$MAX_MINUTES" -gt 0 ] && dim "  limit   $MAX_MINUTES minutes"
    git_ready && dim "  branch  $(git_branch)"
    local rp; rp="$(state_get start_commit '')"
    # `say`, not `dim`: the README promises the recovery point at the top of
    # every run, and --quiet hiding the one command that undoes an unattended
    # run is exactly the kind of silence that makes a quiet mode dangerous.
    # `--keep`, never `--hard`: see the note in `show_status`. The recovery line
# must not be the one thing in the program that loses the operator's work.
if [ -n "$rp" ]; then say "  undo    git reset --keep ${rp}   (everything this run does)"
    elif git_ready; then say "  undo    no commits yet - this run creates the first"; fi
    return 0
}

run_finish() {
    # The last thing an operator reads. It has to say what happened, where the
    # work is, and what is waiting on them.
    say ""
    case "$(state_get status)" in
        done)    good "  done. $(state_get pass_count) green cycles.";;
        stalled) err  "  stalled. see: $ME status";;
        blocked) err  "  blocked: $(state_get reason)";;
        *)       info "  paused. resume any time with: $ME";;
    esac
    return_to_base_branch
    [ "$(asks_open_count)" -gt 0 ] && warn "  $(asks_open_count) question(s) waiting: $ME ask"
    say ""
    return 0
}

return_to_base_branch() {
    # Leaving someone on a branch they never asked to be on is a surprise they
    # will discover at the worst possible moment.
    [ -n "${RESTORE_BRANCH:-}" ] && git_ready || return 0
    local work_branch; work_branch="$(git_branch)"
    [ "$work_branch" != "$RESTORE_BRANCH" ] || return 0
    if ! git -C "$PROJECT" diff --quiet HEAD 2>/dev/null; then
        # Only TRACKED modifications block the return: switching would drag
        # unverified changes onto the branch they were deliberately kept off.
        # Untracked files belong to no branch and travel harmlessly.
        warn "  still on '$work_branch': there are uncommitted changes to review first"
        dim  "  when they are dealt with: git checkout $RESTORE_BRANCH"
    elif git -C "$PROJECT" checkout -q "$RESTORE_BRANCH" 2>/dev/null; then
        good "  work is on '$work_branch'; you are back on '$RESTORE_BRANCH'"
        dim  "  review it: git log ${RESTORE_BRANCH}..${work_branch}"
    else
        warn "  still on '$work_branch' (could not return to '$RESTORE_BRANCH')"
    fi
    return 0
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    # Once ledger state exists, install_traps retires broken stdout before
    # cleanup and preserves the conventional SIGPIPE exit code (141).
    parse_args "$@"
    load_spec

    # These answer before ledger repair, traps or update, including in a
    # directory Ralphie cannot write to. Discovery never starts a run.
    case "$CMD" in
        version|help) run_simple_command; exit $?;;
        discover) cmd_discover; exit $?;;
    esac

    if [ "$CMD" = request ]; then request_command "${REST[@]+"${REST[@]}"}"; exit $?; fi
    # Validate request containment before generic ledger repair touches paths.
    if [ -e "$HOME_DIR/requests" ] || [ -L "$HOME_DIR/requests" ]; then request_scan; fi
    ledger_init
    install_traps
    if run_simple_command; then exit 0; else
        [ "$CMD" = "run" ] || exit $?
    fi

    if is_true "$DO_UPDATE" && ! is_true "${RALPHIE_NO_UPDATE:-0}"; then self_update || true; fi
    run_prepare || exit 1
    local rc=0; loop || rc=$?
    run_finish
    exit "$rc"
}

[ "${RALPHIE_LIB:-0}" = "1" ] || main "$@"
