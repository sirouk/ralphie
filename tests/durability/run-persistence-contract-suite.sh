#!/usr/bin/env bash
set -euo pipefail

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Reuse only the frozen free-engine fixtures and honest result accounting.
# shellcheck source=tests/durability/run-continuation-suite.sh
source "$SUITE_DIR/run-continuation-suite.sh"

persistence_load_fixture() {
    local ws="$1"
    source "$RALPHIE_FILE"
    prepare_unit_terminal_contract "$ws"
    REASON_LOG_FILE="$CONFIG_DIR/reasons.log"
    NOTIFICATION_LOG_FILE="$CONFIG_DIR/notifications.log"
    STATE_FILE="$CONFIG_DIR/state.env"
    SESSION_CHANGED_PATHS_FILE="$CONFIG_DIR/session-changed-paths.txt"
    LOCK_FILE="$CONFIG_DIR/run.lock"
    git -C "$PROJECT_DIR" config user.name 'Offline Persistence'
    git -C "$PROJECT_DIR" config user.email persistence@example.test
    git -C "$PROJECT_DIR" config commit.gpgsign false
    git -C "$PROJECT_DIR" config core.filemode true
}

persistence_set_gate() {
    ACCEPT_COMMANDS=("$1")
    SHELL_GATES_FINGERPRINT=""
    rm -f "$SHELL_GATES_FILE"
    prepare_shell_gates
    snapshot_operator_inputs
}

test_invalid_state_never_restarts_paid_budget() {
    local ws state original kind status before_calls
    ws="$(new_continuation_workspace)"
    state="$ws/project with spaces/.ralphie/state.env"
    if run_continuation_fixture "$ws" --objective 'Keep mission counters intact' --accept 'bash check.sh' --plan-only --max-session-cycles 1 > "$ws/first.log" 2>&1; then return 1; fi
    original="$ws/original-state"
    cp "$state" "$original"
    before_calls="$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')"
    [ "$before_calls" -eq 1 ]
    for kind in mismatch missing empty malformed_number overflow; do
        case "$kind" in
            mismatch) sed 's/^SESSION_ATTEMPT_COUNT="1"/SESSION_ATTEMPT_COUNT="0"/' "$original" > "$state" ;;
            missing) sed '/^STATE_CHECKSUM=/d' "$original" > "$state" ;;
            empty) : > "$state" ;;
            malformed_number|overflow)
                if [ "$kind" = malformed_number ]; then value=not-a-number; else value=9223372036854775808; fi
                sed '/^STATE_CHECKSUM=/d' "$original" | sed "s/^SESSION_ATTEMPT_COUNT=.*/SESSION_ATTEMPT_COUNT=\"$value\"/" > "$state"
                checksum="$(file_sha256 "$state")"
                printf 'STATE_CHECKSUM="%s"\n' "$checksum" >> "$state"
                ;;
        esac
        cp "$state" "$ws/rejected-state"
        if run_continuation_fixture "$ws" --objective 'Keep mission counters intact' --accept 'bash check.sh' --plan-only --max-session-cycles 1 > "$ws/$kind.log" 2>&1; then return 1; fi
        cmp -s "$state" "$ws/rejected-state"
        [ "$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')" -eq "$before_calls" ]
        grep -q -- '--no-resume' "$ws/$kind.log"
    done
}

test_runtime_aliases_are_refused_before_any_write() {
    local ws target outside path kind alias
    for alias in .ralphie logs research .ralphie/run.lock .ralphie/reasons.log .ralphie/notifications.log .ralphie/state.env .ralphie/owned-paths.nul; do
        for kind in symlink directory; do
            ws="$(new_continuation_workspace)"
            target="$ws/project with spaces"
            outside="$ws/outside"
            mkdir "$outside"
            printf 'external sentinel\n' > "$outside/sentinel"
            path="$target/$alias"
            if [ "$alias" = .ralphie ]; then rmdir "$path"; fi
            if [ "$kind" = symlink ]; then
                case "$alias" in .ralphie|logs|research) ln -s "$outside" "$path" ;; *) ln -s "$outside/sentinel" "$path" ;; esac
            else
                # Ordinary owned directories are allowed; only leaf files get a directory adversary.
                case "$alias" in .ralphie|logs|research) continue ;; esac
                mkdir "$path"
            fi
            if run_continuation_fixture "$ws" --objective 'Do not follow runtime aliases' --accept 'bash check.sh' --plan-only --max-session-cycles 1 > "$ws/run.out" 2>&1; then return 1; fi
            [ "$(cat "$outside/sentinel")" = 'external sentinel' ]
            [ "$(ls -A "$outside" | wc -l | tr -d ' ')" -eq 1 ]
            [ ! -e "$target/.mock-prime/calls" ]
            if [ "$kind" = symlink ]; then [ -L "$path" ]; else [ -d "$path" ]; fi
        done
    done
}

test_late_log_aliases_cannot_modify_external_files() {
    local ws
    ws="$(make_workspace)"
    persistence_load_fixture "$ws"
    printf sentinel > "$ws/outside"
    ln -s "$ws/outside" "$REASON_LOG_FILE"
    ln -s "$ws/outside" "$NOTIFICATION_LOG_FILE"
    if log_reason_code RB_FIXTURE 'must refuse'; then return 1; fi
    if notification_log_append fixture blocked suppressed 'must refuse'; then return 1; fi
    [ "$(cat "$ws/outside")" = sentinel ]
    [ -L "$REASON_LOG_FILE" ] && [ -L "$NOTIFICATION_LOG_FILE" ]
}

test_claim_ownership_and_abandoned_claim_are_fail_closed() {
    local ws claim token
    ws="$(make_workspace)"
    persistence_load_fixture "$ws"
    claim="$CONFIG_DIR/transaction.claim"
    acquire_lock_claim "$claim" 0
    token="$LOCK_CLAIM_TOKEN"
    if (acquire_lock_claim "$claim" 0); then return 1; fi
    if release_lock_claim "$claim" wrong-token; then return 1; fi
    [ -d "$claim" ]
    (release_lock_claim "$claim" "$token")
    [ ! -e "$claim" ]
    mkdir "$claim"
    printf 'pid=99999999\ntoken=abandoned\n' > "$claim/owner"
    if acquire_lock_claim "$claim" 0 > "$ws/claim.log" 2>&1; then return 1; fi
    grep -q 'all launchers are stopped' "$ws/claim.log"
    grep -q '^token=abandoned$' "$claim/owner"
}

persistence_wait_file() {
    local file="$1" n=0
    while [ ! -f "$file" ] && [ "$n" -lt 300 ]; do sleep 0.02; n=$((n + 1)); done
    [ -f "$file" ]
}

test_stale_reclaim_never_admits_two_live_workers() {
    local ws holder contender
    ws="$(make_workspace)"
    mkdir -p "$ws/project/.ralphie/run.lock.d"
    printf 'pid=99999999\ntoken=stale\n' > "$ws/project/.ralphie/run.lock.d/owner"
    printf '99999999\ntoken=stale\n' > "$ws/project/.ralphie/run.lock"
    cat > "$ws/contender.sh" <<'EOF_CONTENDER'
#!/bin/bash
set -euo pipefail
source "$AUDIT_SOURCE"
PROJECT_DIR="$AUDIT_WORK/project"
CONFIG_DIR="$PROJECT_DIR/.ralphie"
LOCK_FILE="$CONFIG_DIR/run.lock"
REASON_LOG_FILE="$CONFIG_DIR/reasons.log"
if [ "$AUDIT_NAME" = B ]; then
    rm() {
        if [ "${1:-}" = -f ] && [ "${2:-}" = "$LOCK_FILE" ] && [ ! -f "$AUDIT_WORK/stale-observed" ]; then
            : > "$AUDIT_WORK/stale-observed"
            n=0
            while [ ! -f "$AUDIT_WORK/release-B" ] && [ "$n" -lt 400 ]; do sleep 0.02; n=$((n + 1)); done
        fi
        command rm "$@"
    }
fi
if acquire_lock; then
    printf '%s\n' "$$" > "$AUDIT_WORK/$AUDIT_NAME-acquired"
    n=0
    while [ ! -f "$AUDIT_WORK/finish" ] && [ "$n" -lt 400 ]; do sleep 0.02; n=$((n + 1)); done
    release_lock
else
    : > "$AUDIT_WORK/$AUDIT_NAME-refused"
    exit 1
fi
EOF_CONTENDER
    AUDIT_SOURCE="$RALPHIE_FILE" AUDIT_WORK="$ws" AUDIT_NAME=B /bin/bash "$ws/contender.sh" > "$ws/B.log" 2>&1 &
    holder=$!
    persistence_wait_file "$ws/stale-observed"
    AUDIT_SOURCE="$RALPHIE_FILE" AUDIT_WORK="$ws" AUDIT_NAME=A /bin/bash "$ws/contender.sh" > "$ws/A.log" 2>&1 &
    contender=$!
    if wait "$contender"; then : > "$ws/unexpected-A-success"; fi
    : > "$ws/release-B"
    persistence_wait_file "$ws/B-acquired"
    : > "$ws/finish"
    wait "$holder"
    [ -f "$ws/A-refused" ]
    [ ! -e "$ws/A-acquired" ] && [ ! -e "$ws/unexpected-A-success" ]
    [ ! -e "$ws/project/.ralphie/run.lock.d" ] && [ ! -e "$ws/project/.ralphie/run.lock.claim" ]
}

persistence_prepare_commit() {
    local ws="$1"
    persistence_load_fixture "$ws"
    printf base > "$PROJECT_DIR/phase.txt"
    printf base > "$PROJECT_DIR/operator.txt"
    git -C "$PROJECT_DIR" add -- phase.txt operator.txt
    git -C "$PROJECT_DIR" commit -qm baseline
    printf 'operator unsaved sentinel\n' >> "$PROJECT_DIR/operator.txt"
    capture_operator_baseline
    phase_capture_worktree_manifest "$ws/before"
    printf 'worker implementation\n' >> "$PROJECT_DIR/phase.txt"
    phase_capture_worktree_manifest "$ws/after"
    record_phase_owned_paths "$ws/before" "$ws/after"
    AUTO_COMMIT_SESSION_ENABLED=true
    AUTO_COMMIT_ON_PHASE_PASS=true
}

test_auto_save_cannot_run_scope_expanding_hooks() {
    local ws
    ws="$(make_workspace)"
    persistence_prepare_commit "$ws"
    cat > "$PROJECT_DIR/.git/hooks/pre-commit" <<'EOF_HOOK'
#!/bin/sh
printf ran > hook-ran
git add -- operator.txt
EOF_HOOK
    chmod +x "$PROJECT_DIR/.git/hooks/pre-commit"
    commit_phase_approved_changes build test "$ws/before" "$ws/after"
    [ "$PHASE_SAVE_REQUIRED" = true ] && [ "$PHASE_SAVE_OK" = true ]
    git -C "$PROJECT_DIR" diff-tree --no-commit-id --name-only -r HEAD > "$ws/committed"
    [ "$(cat "$ws/committed")" = phase.txt ]
    [ ! -e "$PROJECT_DIR/hook-ran" ]
    [ "$(git -C "$PROJECT_DIR" show HEAD:operator.txt)" = base ]
    grep -q 'operator unsaved sentinel' "$PROJECT_DIR/operator.txt"
    git -C "$PROJECT_DIR" diff --cached --quiet
}

test_failed_private_save_leaves_real_index_unchanged_and_retry_works() {
    local ws head
    ws="$(make_workspace)"
    persistence_prepare_commit "$ws"
    head="$(git -C "$PROJECT_DIR" rev-parse HEAD)"
    cp "$PROJECT_DIR/.git/index" "$ws/index-before"
    git -C "$PROJECT_DIR" config commit.gpgsign true
    git -C "$PROJECT_DIR" config gpg.program /usr/bin/false
    if commit_phase_approved_changes build test "$ws/before" "$ws/after"; then return 1; fi
    [ "$PHASE_SAVE_OK" = false ]
    [ "$(git -C "$PROJECT_DIR" rev-parse HEAD)" = "$head" ]
    cmp -s "$PROJECT_DIR/.git/index" "$ws/index-before"
    git -C "$PROJECT_DIR" config commit.gpgsign false
    commit_phase_approved_changes build test "$ws/before" "$ws/after"
    [ "$PHASE_SAVE_OK" = true ]
    [ "$(git -C "$PROJECT_DIR" rev-parse HEAD)" != "$head" ]
    git -C "$PROJECT_DIR" diff --cached --quiet
}


persistence_prepare_pending_ours_merge() {
    local base_branch
    base_branch="$(git -C "$PROJECT_DIR" symbolic-ref --short HEAD)"
    git -C "$PROJECT_DIR" checkout -qb operator-side
    printf 'operator branch history\n' > "$PROJECT_DIR/branch-only.txt"
    git -C "$PROJECT_DIR" add -- branch-only.txt
    git -C "$PROJECT_DIR" commit -qm 'operator branch'
    git -C "$PROJECT_DIR" checkout -q "$base_branch"
    git -C "$PROJECT_DIR" merge --no-commit -s ours operator-side > "$1/merge.log" 2>&1
    git -C "$PROJECT_DIR" diff --cached --quiet
}

test_pending_git_operation_cannot_be_consumed_by_phase_save() {
    local ws stage head merge_path
    for stage in preparation publication; do
        ws="$(make_workspace)"
        persistence_prepare_commit "$ws"
        if [ "$stage" = preparation ]; then
            persistence_prepare_pending_ours_merge "$ws"
        else
            # Admit ordinary auto-save, then begin an operator merge before
            # publication so only the final metadata check can protect it.
            prepare_phase_auto_commit_mode
            persistence_prepare_pending_ours_merge "$ws"
        fi
        head="$(git -C "$PROJECT_DIR" rev-parse HEAD)"
        merge_path="$(git -C "$PROJECT_DIR" rev-parse --git-path MERGE_HEAD)"
        case "$merge_path" in /*) ;; *) merge_path="$PROJECT_DIR/$merge_path";; esac
        cp "$merge_path" "$ws/merge-before"
        cp "$PROJECT_DIR/.git/index" "$ws/index-before"
        cp "$PROJECT_DIR/phase.txt" "$ws/phase-before"
        cp "$PROJECT_DIR/operator.txt" "$ws/operator-before"
        if [ "$stage" = preparation ]; then
            if prepare_phase_auto_commit_mode; then return 1; fi
            [ "$AUTO_COMMIT_SESSION_ENABLED" = false ]
        else
            if commit_phase_approved_changes build test "$ws/before" "$ws/after"; then return 1; fi
            [ "$PHASE_SAVE_OK" = false ]
        fi
        printf '%s' "$PHASE_SAVE_REASON" | grep -q 'Git operation is pending (MERGE_HEAD)'
        [ "$(git -C "$PROJECT_DIR" rev-parse HEAD)" = "$head" ]
        cmp -s "$merge_path" "$ws/merge-before"
        cmp -s "$PROJECT_DIR/.git/index" "$ws/index-before"
        cmp -s "$PROJECT_DIR/phase.txt" "$ws/phase-before"
        cmp -s "$PROJECT_DIR/operator.txt" "$ws/operator-before"
    done
    # Linked worktrees store operation metadata outside their .git file.
    ws="$(make_workspace)"
    persistence_load_fixture "$ws"
    git -C "$PROJECT_DIR" worktree add -q -b linked-operator "$ws/linked" HEAD
    PROJECT_DIR="$ws/linked"
    persistence_prepare_pending_ours_merge "$ws"
    if phase_git_operation_idle; then return 1; fi
    printf '%s' "$PHASE_SAVE_REASON" | grep -q 'Git operation is pending (MERGE_HEAD)'
}

test_operator_chmod_breaks_saved_ownership() {
    local ws
    ws="$(make_workspace)"
    persistence_prepare_commit "$ws"
    chmod +x "$PROJECT_DIR/phase.txt"
    if owned_path_matches phase.txt; then return 1; fi
    capture_operator_baseline
    nul_file_contains "$AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE" phase.txt
}

test_verification_rejects_mode_symlink_and_index_mutations() {
    local kind ws command
    for kind in mode symlink index; do
        ws="$(make_workspace)"
        persistence_load_fixture "$ws"
        printf 'identical target bytes\n' > "$PROJECT_DIR/target-a"
        cp "$PROJECT_DIR/target-a" "$PROJECT_DIR/target-b"
        printf base > "$PROJECT_DIR/worker.sh"
        ln -s target-a "$PROJECT_DIR/link"
        git -C "$PROJECT_DIR" add -- target-a target-b worker.sh link
        git -C "$PROJECT_DIR" commit -qm baseline
        printf 'staged operator bytes' > "$PROJECT_DIR/worker.sh"
        git -C "$PROJECT_DIR" add -- worker.sh
        printf 'working operator bytes' > "$PROJECT_DIR/worker.sh"
        # Keep the symlink dirty both before and after a target-only change.
        rm "$PROJECT_DIR/link"
        ln -s ./target-a "$PROJECT_DIR/link"
        capture_operator_baseline
        case "$kind" in
            mode) command='test ! -x worker.sh && chmod +x worker.sh' ;;
            symlink) command='test "$(cat link)" = "identical target bytes" && rm link && ln -s ./target-b link' ;;
            index) command='blob=$(printf "replacement staged bytes" | git hash-object -w --stdin); git update-index --cacheinfo 100644,"$blob",worker.sh' ;;
        esac
        persistence_set_gate "$command"
        if run_shell_gates "$kind" > "$ws/gate.log" 2>&1; then return 1; fi
        [ "$SHELL_GATES_STATUS" = failed ]
        grep -q 'changed the nonignored project tree' "$ws/gate.log"
    done
}

test_verification_recurses_only_into_real_gitlink_roots() {
    local ws
    ws="$(make_workspace)"
    persistence_load_fixture "$ws"
    mkdir "$PROJECT_DIR/module"
    git -C "$PROJECT_DIR/module" init -q
    printf 'good source\n' > "$PROJECT_DIR/module/source.txt"
    git -C "$PROJECT_DIR/module" add -- source.txt
    git -C "$PROJECT_DIR/module" -c user.name=Fixture -c user.email=fixture@example.test commit -qm module
    git -C "$PROJECT_DIR" add -- module 2> "$ws/gitlink.log"
    git -C "$PROJECT_DIR" commit -qm gitlink
    printf 'already dirty source\n' > "$PROJECT_DIR/module/source.txt"
    capture_operator_baseline
    persistence_set_gate 'test "$(cat module/source.txt)" = "already dirty source" && printf "broken after checking\n" > module/source.txt'
    if run_shell_gates gitlink > "$ws/gate.log" 2>&1; then return 1; fi
    [ "$SHELL_GATES_STATUS" = failed ]
    mv "$PROJECT_DIR/module/.git" "$ws/module-git"
    if phase_capture_worktree_manifest "$ws/unsupported"; then return 1; fi
}

test_executable_ignores_inherited_git_path_redirection() {
    local kind ws target outside index_before external_before
    for kind in index gitdir; do
        ws="$(new_continuation_workspace)"
        target="$ws/project with spaces"
        git -C "$target" config user.name Fixture
        git -C "$target" config user.email fixture@example.test
        git -C "$target" config commit.gpgsign false
        cp "$ws/ralphie.sh" "$ws/ralphie-real.sh"
        if [ "$kind" = index ]; then
            cp "$target/.git/index" "$ws/external-index"
            cp "$ws/external-index" "$ws/external-index-before"
            : > "$ws/inject-index"
        else
            mkdir "$ws/external-repo"
            git -C "$ws/external-repo" init -q
            printf 'external sentinel\n' > "$ws/external-repo/external.txt"
            git -C "$ws/external-repo" add -- external.txt
            git -C "$ws/external-repo" -c user.name=Fixture -c user.email=fixture@example.test commit -qm external
            external_before="$(git -C "$ws/external-repo" rev-parse HEAD)"
        fi
        cat > "$ws/ralphie.sh" <<'EOF_LAUNCH'
#!/bin/bash
root="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$root/inject-index" ]; then export GIT_INDEX_FILE="$root/external-index"; else export GIT_DIR="$root/external-repo/.git"; fi
export GIT_AUTHOR_NAME='Preserved author'
exec /bin/bash "$root/ralphie-real.sh" "$@"
EOF_LAUNCH
        CONTINUATION_AUTO_COMMIT=true
        run_continuation_fixture "$ws" --objective 'Bind Git to the selected project' --accept 'bash check.sh' --plan-only --max-session-cycles 3 > "$ws/run.out" 2>&1
        [ "$(git -C "$target" log -1 --pretty=%an)" = 'Preserved author' ]
        if [ "$kind" = index ]; then
            cmp -s "$ws/external-index" "$ws/external-index-before"
        else
            [ "$(git -C "$ws/external-repo" rev-parse HEAD)" = "$external_before" ]
        fi
    done
    (
        export GIT_DIR=library-context GIT_INDEX_FILE=library-index
        source "$RALPHIE_FILE"
        [ "$GIT_DIR" = library-context ] && [ "$GIT_INDEX_FILE" = library-index ]
    )
}

test_state_io_failure_preserves_snapshot_and_refuses_inference() {
    local ws output status
    ws="$(make_workspace)"
    persistence_load_fixture "$ws"
    SESSION_ID=last-durable-session
    SESSION_ATTEMPT_COUNT=0
    save_state
    cp "$STATE_FILE" "$ws/state-before"
    MAX_SESSION_CYCLES=1
    SESSION_TOKEN_BUDGET=0
    SESSION_COST_BUDGET_CENTS=0
    RALPHIE_CLEANUP_STATE_ENABLED=true
    # Real filesystem write refusal, with stdout/stderr carried by a pipe so
    # the fixture can still report its result. Conditional dispatch exercises
    # the same disabled-errexit context used by the actual phase runner.
    output="$(
        trap '' XFSZ
        ulimit -S -f 0
        status=0
        if admit_session_attempt 'fixture engine dispatch'; then
            # A zero-byte mock receipt is possible even under this file limit.
            : > "$ws/dispatch-admitted"
        else
            status=$?
        fi
        printf '\nfixture_status=%s\nfixture_budget_exhausted=%s\n' "$status" "$ENGINE_BUDGET_EXHAUSTED"
    2>&1)"
    printf '%s\n' "$output" > "$ws/io-failure.log"
    grep -q '^fixture_status=75$' "$ws/io-failure.log"
    grep -q '^fixture_budget_exhausted=true$' "$ws/io-failure.log"
    cmp -s "$STATE_FILE" "$ws/state-before"
    [ ! -e "$ws/dispatch-admitted" ] && [ ! -e "$PROJECT_DIR/.mock-prime/calls" ]
    load_state
    [ "$SESSION_ATTEMPT_COUNT" -eq 0 ] && [ "$SESSION_ID" = last-durable-session ]
}

test_state_checksum_append_failure_preserves_previous_bytes() {
    local ws
    ws="$(make_workspace)"
    persistence_load_fixture "$ws"
    SESSION_ID=last-durable-session
    save_state
    cp "$STATE_FILE" "$ws/state-before"
    SESSION_ID=changed-session-must-not-publish
    # Isolate the later append boundary, after the body was written normally.
    printf() {
        case "${1:-}" in STATE_CHECKSUM*) return 1 ;; esac
        builtin printf "$@"
    }
    if save_state; then return 1; fi
    unset -f printf
    cmp -s "$STATE_FILE" "$ws/state-before"
    load_state
    [ "$SESSION_ID" = last-durable-session ]
}

test_checksum_and_owned_paths_preserve_delimiter_filenames() {
    local ws path expected operator
    local -a paths
    ws="$(make_workspace)"
    persistence_load_fixture "$ws"
    paths=($'source\ninside.txt' $'source\tinside.txt' $'source-final\n')
    operator=$'operator\nunsaved.txt'
    printf 'operator sentinel\n' > "$PROJECT_DIR/$operator"
    capture_operator_baseline
    phase_capture_worktree_manifest "$ws/before"
    for path in "${paths[@]}"; do printf 'worker source\n' > "$PROJECT_DIR/$path"; done
    expected="$(printf 'worker source\n' | sha256_stream_sum)"
    for path in "${paths[@]}"; do
        [ "$(sha256_file_sum "$PROJECT_DIR/$path")" = "$expected" ]
    done
    phase_capture_worktree_manifest "$ws/after"
    record_phase_owned_paths "$ws/before" "$ws/after"
    save_state
    OWNED_PATHS_SHA=""
    load_state
    for path in "${paths[@]}"; do owned_path_matches "$path"; done
    capture_operator_baseline
    nul_file_contains "$AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE" "$operator"
    for path in "${paths[@]}"; do
        if nul_file_contains "$AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE" "$path"; then return 1; fi
    done
    AUTO_COMMIT_SESSION_ENABLED=true
    AUTO_COMMIT_ON_PHASE_PASS=true
    commit_phase_approved_changes build test "$ws/before" "$ws/after"
    [ "$PHASE_SAVE_REQUIRED" = true ] && [ "$PHASE_SAVE_OK" = true ]
    for path in "${paths[@]}"; do
        git -C "$PROJECT_DIR" show "HEAD:$path" > "$ws/saved-source"
        cmp -s "$ws/saved-source" "$PROJECT_DIR/$path"
    done
    if git -C "$PROJECT_DIR" cat-file -e "HEAD:$operator" 2>/dev/null; then return 1; fi
    [ "$(cat "$PROJECT_DIR/$operator")" = 'operator sentinel' ]
    git -C "$PROJECT_DIR" diff --cached --quiet
}

test_delimiter_roots_are_refused_before_aliasing_or_writes() {
    local ws target normal expected route delimiter status
    for delimiter in $'\n' $'\r'; do
        for route in explicit default invocation stream script; do
            ws="$(new_continuation_workspace)"
            normal="$ws/project with spaces"
            target="${normal}${delimiter}"
            cp "$ws/ralphie.sh" "$normal/ralphie.sh"
            cp -R "$normal" "$target"
            expected="$ws/expected-normal"
            cp -R "$normal" "$expected"
            cp -R "$target" "$ws/expected-delimiter"
            status=0
            case "$route" in
                explicit)
                    if run_continuation_fixture "$ws" --project "$target" --objective 'Must not bind sibling' --plan-only --max-session-cycles 1 > "$ws/root.log" 2>&1; then status=0; else status=$?; fi
                    ;;
                default)
                    if (cd "$target" && env -i PATH="$RALPHIE_TEST_GUARD_DIR:/usr/bin:/bin" HOME="$ws/home" /bin/bash ./ralphie.sh --objective 'Must not bind sibling' --plan-only) > "$ws/root.log" 2>&1; then status=0; else status=$?; fi
                    ;;
                invocation)
                    if (cd "$target" && env -i PATH="$RALPHIE_TEST_GUARD_DIR:/usr/bin:/bin" HOME="$ws/home" /bin/bash "$ws/ralphie.sh" --project "$normal" --objective 'Must not bind sibling' --plan-only) > "$ws/root.log" 2>&1; then status=0; else status=$?; fi
                    ;;
                stream)
                    if (cd "$target" && env -i PATH="$RALPHIE_TEST_GUARD_DIR:/usr/bin:/bin" HOME="$ws/home" /bin/bash -s -- --objective 'Must not bind sibling' --plan-only < "$ws/ralphie.sh") > "$ws/root.log" 2>&1; then status=0; else status=$?; fi
                    ;;
                script)
                    if env -i PATH="$RALPHIE_TEST_GUARD_DIR:/usr/bin:/bin" HOME="$ws/home" /bin/bash "$target/ralphie.sh" --project "$normal" --objective 'Must not bind sibling' --plan-only > "$ws/root.log" 2>&1; then status=0; else status=$?; fi
                    ;;
            esac
            [ "$status" -ne 0 ]
            grep -q 'cannot contain CR or LF path bytes' "$ws/root.log"
            diff -r "$normal" "$expected"
            diff -r "$target" "$ws/expected-delimiter"
        done
    done
}

test_owned_runtime_root_rejects_delimiters_without_writing_sibling() {
    local ws directory
    ws="$(make_workspace)"
    persistence_load_fixture "$ws"
    mkdir "$ws/runtime"
    printf sentinel > "$ws/runtime/state.env"
    for directory in "$ws/runtime"$'\n' "$ws/runtime"$'\r'; do
        mkdir "$directory"
        if ensure_runtime_directory "$directory/subdir"; then return 1; fi
        if ensure_runtime_file "$directory/state.env"; then return 1; fi
        if env TMPDIR="$directory" /bin/bash "$RALPHIE_FILE" --help > "$ws/temp-root.log" 2>&1; then return 1; fi
        grep -q 'Temporary runtime root cannot contain CR or LF path bytes' "$ws/temp-root.log"
        [ ! -e "$directory/subdir" ] && [ ! -e "$directory/state.env" ]
        [ "$(cat "$ws/runtime/state.env")" = sentinel ]
    done
}

test_owner_metadata_write_failure_cannot_admit_lock() {
    local ws lock_dir
    ws="$(make_workspace)"
    persistence_load_fixture "$ws"
    lock_dir="${LOCK_FILE}.d"
    mkdir "$lock_dir"
    printf() {
        # The first owner write fails; later writes would succeed. Testing this
        # separately catches compound writers that only inspect their last call.
        case "${1:-}" in pid=*) return 1 ;; esac
        builtin printf "$@"
    }
    if write_lock_owner_files "$lock_dir" fixture-token; then return 1; fi
    unset -f printf
    [ ! -e "$lock_dir/owner" ] && [ ! -e "$LOCK_FILE" ]
}

test_owned_record_write_failure_preserves_previous_ownership() {
    local ws signature
    ws="$(make_workspace)"
    persistence_load_fixture "$ws"
    printf 'retained source\n' > "$PROJECT_DIR/retained.txt"
    git -C "$PROJECT_DIR" add -- retained.txt
    git -C "$PROJECT_DIR" commit -qm 'retained source baseline'
    capture_operator_baseline
    signature="$(owned_path_signature retained.txt)"
    builtin printf '%s\0%s\0' retained.txt "$signature" > "$OWNED_PATHS_FILE"
    cp "$OWNED_PATHS_FILE" "$ws/owned-before"
    phase_capture_worktree_manifest "$ws/before"
    builtin printf 'new worker source\n' > "$PROJECT_DIR/worker.txt"
    phase_capture_worktree_manifest "$ws/after"
    printf() {
        if [ "${1:-}" = '%s\0%s\0' ] && [ "${2:-}" = retained.txt ]; then return 1; fi
        builtin printf "$@"
    }
    if record_phase_owned_paths "$ws/before" "$ws/after"; then return 1; fi
    unset -f printf
    cmp -s "$OWNED_PATHS_FILE" "$ws/owned-before"
}

main() {
    CONTINUATION_FILTER="${1:-}"
    prepare_isolated_target
    trap 'cleanup_isolated_target; cleanup_offline_test_guards' EXIT
    capture_repo_tracked_status_baseline
    continuation_case persistence_boundary_lock_owner_io_failure test_owner_metadata_write_failure_cannot_admit_lock
    continuation_case persistence_boundary_owned_record_io_failure test_owned_record_write_failure_preserves_previous_ownership
    continuation_case persistence_boundary_state_io_failure test_state_io_failure_preserves_snapshot_and_refuses_inference
    continuation_case persistence_boundary_state_checksum_append_failure test_state_checksum_append_failure_preserves_previous_bytes
    continuation_case persistence_boundary_delimiter_filenames test_checksum_and_owned_paths_preserve_delimiter_filenames
    continuation_case persistence_boundary_delimiter_roots test_delimiter_roots_are_refused_before_aliasing_or_writes
    continuation_case persistence_boundary_owned_runtime_roots test_owned_runtime_root_rejects_delimiters_without_writing_sibling
    continuation_case invalid_state_never_restarts_paid_budget test_invalid_state_never_restarts_paid_budget
    continuation_case runtime_aliases_are_refused_before_any_write test_runtime_aliases_are_refused_before_any_write
    continuation_case late_log_aliases_cannot_modify_external_files test_late_log_aliases_cannot_modify_external_files
    continuation_case claim_ownership_and_abandoned_claim_are_fail_closed test_claim_ownership_and_abandoned_claim_are_fail_closed
    continuation_case stale_reclaim_never_admits_two_live_workers test_stale_reclaim_never_admits_two_live_workers
    continuation_case auto_save_cannot_run_scope_expanding_hooks test_auto_save_cannot_run_scope_expanding_hooks
    continuation_case failed_private_save_leaves_real_index_unchanged_and_retry_works test_failed_private_save_leaves_real_index_unchanged_and_retry_works
    continuation_case pending_git_operation_cannot_be_consumed_by_phase_save test_pending_git_operation_cannot_be_consumed_by_phase_save
    continuation_case operator_chmod_breaks_saved_ownership test_operator_chmod_breaks_saved_ownership
    continuation_case verification_rejects_mode_symlink_and_index_mutations test_verification_rejects_mode_symlink_and_index_mutations
    continuation_case verification_recurses_only_into_real_gitlink_roots test_verification_recurses_only_into_real_gitlink_roots
    continuation_case executable_ignores_inherited_git_path_redirection test_executable_ignores_inherited_git_path_redirection
    info "Persistence total: $TOTAL_COUNT | Passed: $PASS_COUNT | Failed: $FAIL_COUNT | Skipped: $SKIP_COUNT"
    [ "$TOTAL_COUNT" -gt 0 ] && [ "$TOTAL_COUNT" -eq "$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))" ] && [ "$FAIL_COUNT" -eq 0 ]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
