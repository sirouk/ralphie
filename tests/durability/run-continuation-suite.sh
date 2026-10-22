#!/usr/bin/env bash
set -euo pipefail

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/durability/run-durability-suite.sh
source "$SUITE_DIR/run-durability-suite.sh"

new_continuation_workspace() {
    local ws
    ws="$(make_workspace)"
    mkdir -p "$ws/project with spaces/.ralphie" "$ws/home" "$ws/bin" "$ws/engine-scratch"
    cp "$ROOT_DIR/tests/durability/mock-prime-control.sh" "$ws/bin/prime-agent"
    chmod +x "$ws/bin/prime-agent"
    cat > "$ws/project with spaces/check.sh" <<'EOF_CHECK'
#!/usr/bin/env bash
printf 'checked\n' >> check-receipts.log
exit 0
EOF_CHECK
    printf '.mock-prime/\ncheck-receipts.log\nfailing-check.receipt\n' > "$ws/project with spaces/.gitignore"
    git -C "$ws/project with spaces" init -q
    git -C "$ws/project with spaces" add -- .gitignore check.sh
    git -C "$ws/project with spaces" -c user.name='Offline Fixture' -c user.email=fixture@example.test -c commit.gpgsign=false commit -qm 'initial fixture'
    printf '%s' "$ws"
}

run_continuation_fixture() {
    local ws="$1"
    shift
    env -i \
        PATH="$RALPHIE_TEST_GUARD_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
        HOME="$ws/home" TMPDIR="$ws/engine-scratch" LANG=en_US.UTF-8 TERM=dumb \
        PRIME_ENGINE_CMD="$ws/bin/prime-agent" \
        CODEX_ENGINE_CMD="$RALPHIE_TEST_GUARD_DIR/codex" \
        CLAUDE_ENGINE_CMD="$RALPHIE_TEST_GUARD_DIR/claude" \
        RALPHIE_NOTIFICATIONS_ENABLED=false RALPHIE_STARTUP_OPERATIONAL_PROBE=false \
        RALPHIE_ENGINE_OVERRIDES_BOOTSTRAPPED=true RALPHIE_NOTIFICATION_WIZARD_BOOTSTRAPPED=true \
        RALPHIE_AUTO_COMMIT_ON_PHASE_PASS="${CONTINUATION_AUTO_COMMIT:-false}" RALPHIE_AUTO_UPDATE=false \
        RALPHIE_QUALITY_LEVEL="${CONTINUATION_QUALITY_LEVEL:-minimal}" RALPHIE_SWARM_MAX_PARALLEL=1 \
        RALPHIE_SWARM_CONSENSUS_TIMEOUT=10 RALPHIE_ENGINE_HEALTH_MAX_ATTEMPTS=1 \
        RALPHIE_ENGINE_HEALTH_RETRY_DELAY_SECONDS=0 \
        MOCK_PRIME_FAIL_INFERENCE="${MOCK_PRIME_FAIL_INFERENCE:-false}" \
        MOCK_PRIME_BLOCK_INFERENCE="${MOCK_PRIME_BLOCK_INFERENCE:-false}" \
        MOCK_PRIME_REVIEW_BREAK_CHECK="${MOCK_PRIME_REVIEW_BREAK_CHECK:-false}" \
        MOCK_PRIME_TAMPER_GATES="${MOCK_PRIME_TAMPER_GATES:-false}" \
        MOCK_PRIME_REVIEW_TAMPER_GATES="${MOCK_PRIME_REVIEW_TAMPER_GATES:-false}" \
        MOCK_PRIME_VALIDATION_ONLY="${MOCK_PRIME_VALIDATION_ONLY:-false}" \
        MOCK_PRIME_PERMANENT_FAILURE="${MOCK_PRIME_PERMANENT_FAILURE:-false}" \
        MOCK_PRIME_REVIEW_PERMANENT_FAILURE="${MOCK_PRIME_REVIEW_PERMANENT_FAILURE:-false}" \
        MOCK_PRIME_REVIEW_TRANSIENT_ONCE="${MOCK_PRIME_REVIEW_TRANSIENT_ONCE:-false}" \
        MOCK_PRIME_REVIEW_PAUSE="${MOCK_PRIME_REVIEW_PAUSE:-false}" \
        MOCK_PRIME_WORKER_FAIL_ONCE="${MOCK_PRIME_WORKER_FAIL_ONCE:-false}" \
        MOCK_PRIME_WORKER_PAUSE_ONCE="${MOCK_PRIME_WORKER_PAUSE_ONCE:-false}" \
        /bin/bash "$ws/ralphie.sh" \
        --project "$ws/project with spaces" --engine "${CONTINUATION_ENGINE:-prime-agent}" \
        --prime-provider fixture-provider --prime-model fixture-model --prime-thinking max \
        --max-phase-completion-attempts 1 --phase-completion-retry-delay-seconds 0 \
        --run-agent-max-attempts 1 --run-agent-retry-delay-seconds 0 \
        --max-consensus-routing-attempts 1 "$@"
}

assert_incomplete_fixture() {
    local ws="$1"
    local status="$2"
    [ "$status" -ne 0 ]
    if [ -f "$ws/project with spaces/.ralphie/state.env" ]; then
        if grep -q '^CURRENT_PHASE="done"' "$ws/project with spaces/.ralphie/state.env"; then
            cat "$ws/run.out" >&2
            return 1
        fi
    fi
    if grep -q 'All phases completed. Session done.' "$ws/run.out"; then
        cat "$ws/run.out" >&2
        return 1
    fi
}

install_budget_receipt_wrapper() {
    local ws="$1"
    mv "$ws/bin/prime-agent" "$ws/bin/prime-agent-fixture"
    cat > "$ws/bin/prime-agent" <<'EOF_BUDGET_RECEIPT'
#!/usr/bin/env bash
set -euo pipefail
fixture="$(cd "$(dirname "$0")" && pwd)/prime-agent-fixture"
case "${1:-}" in --help|--version) exec "$fixture" "$@" ;; esac
target=""
previous=""
for argument in "$@"; do
    [ "$previous" != --cwd ] || target="$argument"
    previous="$argument"
done
[ -d "$target" ]
mkdir -p "$target/.mock-prime/usage"
receipt="$target/.mock-prime/usage/$$"
cat > "$receipt.prompt"
if "$fixture" "$@" < "$receipt.prompt" > "$receipt.stdout" 2> "$receipt.stderr"; then result=0; else result=$?; fi
cat "$receipt.stdout"
cat "$receipt.stderr" >&2
exit "$result"
EOF_BUDGET_RECEIPT
    chmod +x "$ws/bin/prime-agent"
}

assert_budget_matches_actual_inference_receipts() {
    local ws="$1" expected_calls="$2"
    local state_file="$ws/project with spaces/.ralphie/state.env"
    local receipt_dir="$ws/project with spaces/.mock-prime/usage"
    local calls prompt prompt_bytes stdout_bytes stderr_bytes expected_tokens=0 receipts=0 value
    calls="$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')"
    [ "$calls" -eq "$expected_calls" ] || { fail "Budget admitted $calls actual calls; expected $expected_calls."; return 1; }
    for prompt in "$receipt_dir"/*.prompt; do
        [ -f "$prompt" ]
        prompt_bytes="$(wc -c < "$prompt" | tr -d ' ')"
        stdout_bytes="$(wc -c < "${prompt%.prompt}.stdout" | tr -d ' ')"
        stderr_bytes="$(wc -c < "${prompt%.prompt}.stderr" | tr -d ' ')"
        # The documented estimator charges prompt, diagnostic log and answer
        # separately. These raw fixture streams contain no redaction targets.
        expected_tokens=$((expected_tokens + (prompt_bytes + 3) / 4 + (stdout_bytes + stderr_bytes + 3) / 4 + (stdout_bytes + 3) / 4))
        receipts=$((receipts + 1))
    done
    [ "$receipts" -eq "$calls" ]
    value="$(sed -n 's/^SESSION_ATTEMPT_COUNT="\([0-9]*\)"$/\1/p' "$state_file")"
    [ "$value" = "$calls" ] || { fail "Saved budget count $value differs from $calls actual calls."; return 1; }
    value="$(sed -n 's/^SESSION_TOKEN_COUNT="\([0-9]*\)"$/\1/p' "$state_file")"
    [ "$value" -eq "$expected_tokens" ] || { fail "Saved token count $value differs from $expected_tokens receipt tokens."; return 1; }
    value="$(sed -n 's/^SESSION_COST_CENTS="\([0-9]*\)"$/\1/p' "$state_file")"
    [ "$value" -eq "$expected_tokens" ] || { fail "Saved cost $value differs from $expected_tokens receipt cents."; return 1; }
}

test_session_budget_counts_parallel_reviewers_and_retries() {
    local ws
    ws="$(new_continuation_workspace)"
    install_budget_receipt_wrapper "$ws"
    CONTINUATION_QUALITY_LEVEL=standard
    MOCK_PRIME_REVIEW_TRANSIENT_ONCE=true
    run_continuation_fixture "$ws" --objective 'Account for every parallel reviewer and retry' --accept 'bash check.sh' \
        --plan-only --run-agent-max-attempts 2 --session-token-rate-cents-per-million 1000000 > "$ws/run.out" 2>&1
    [ "$(grep -c '^consensus:plan$' "$ws/project with spaces/.mock-prime/roles")" -eq 6 ]
    assert_budget_matches_actual_inference_receipts "$ws" 8
    grep -q '^CURRENT_PHASE="build"' "$ws/project with spaces/.ralphie/state.env"
}

test_session_budget_allows_last_admitted_success() {
    local ws
    ws="$(new_continuation_workspace)"
    install_budget_receipt_wrapper "$ws"
    run_continuation_fixture "$ws" --objective 'Accept the last admitted planning review' --accept 'bash check.sh' \
        --plan-only --max-session-cycles 3 --session-token-rate-cents-per-million 1000000 > "$ws/run.out" 2>&1
    assert_budget_matches_actual_inference_receipts "$ws" 3
    grep -q '^CURRENT_PHASE="build"' "$ws/project with spaces/.ralphie/state.env"
    grep -q '^PHASE_ATTEMPT_IN_PROGRESS="false"' "$ws/project with spaces/.ralphie/state.env"
    grep -q 'Planning complete; build was not authorized' "$ws/run.out"
}

test_session_budget_stops_parallel_admission_at_exact_cap() {
    local ws budget status
    CONTINUATION_QUALITY_LEVEL=standard
    for budget in 4 5; do
        ws="$(new_continuation_workspace)"
        install_budget_receipt_wrapper "$ws"
        MOCK_PRIME_REVIEW_TRANSIENT_ONCE=false
        [ "$budget" -ne 5 ] || MOCK_PRIME_REVIEW_TRANSIENT_ONCE=true
        set +e
        run_continuation_fixture "$ws" --objective 'Bound reviewer admission before spending' --accept 'bash check.sh' \
            --plan-only --max-session-cycles "$budget" --run-agent-max-attempts 2 \
            --session-token-rate-cents-per-million 1000000 > "$ws/run.out" 2>&1
        status=$?
        set -e
        assert_incomplete_fixture "$ws" "$status"
        assert_budget_matches_actual_inference_receipts "$ws" "$budget"
    done
}

install_budget_canary_mocks() {
    local ws="$1"
    cat > "$ws/bin/health-canary" <<'EOF_HEALTH_CANARY'
#!/usr/bin/env bash
set -euo pipefail
engine="${0##*/}"
case "${1:-}" in
    --version) printf 'offline canary fixture 999.0.0\n'; exit 0 ;;
    --help) printf '%s\n' '-p, --print --output-last-message --dangerously-skip-permissions tool read write'; exit 0 ;;
esac
if [ "${1:-}" = exec ] && [ "${2:-}" = --help ]; then
    printf '%s\n' '--output-last-message --dangerously-bypass-approvals-and-sandbox'
    exit 0
fi
answer_path=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        exec|-p|-) shift ;;
        --output-last-message) answer_path="$2"; shift 2 ;;
        --model|-c|--settings) shift 2 ;;
        *) printf 'Unexpected health-canary argument: %s\n' "$1" >&2; exit 28 ;;
    esac
done
receipt="$CANARY_RECEIPT_DIR/$$"
cat > "$receipt.prompt"
grep -q '^Reply with ONLY this exact token on a single line, nothing else: ralphie_smoke_' "$receipt.prompt"
printf '%s\n' "$engine" >> "$CANARY_RECEIPT_DIR/calls"
if [ "$CANARY_FAIL" = true ]; then
    printf 'fixture wrong canary\n' > "$receipt.answer"
else
    sed -n 's/^Reply with ONLY this exact token on a single line, nothing else: //p' "$receipt.prompt" > "$receipt.answer"
fi
if [ -n "$answer_path" ]; then cp "$receipt.answer" "$answer_path"; else cat "$receipt.answer"; fi
EOF_HEALTH_CANARY
    cp "$ws/bin/health-canary" "$ws/bin/claude"
    cp "$ws/bin/health-canary" "$ws/bin/codex"
    chmod +x "$ws/bin/claude" "$ws/bin/codex"
}

test_session_budget_accounts_for_health_canaries_and_blocks_retry() {
    local fail_canary
    for fail_canary in true false; do
        (
            local ws status prompt prompt_bytes answer_bytes expected_tokens=0
            ws="$(new_continuation_workspace)"
            install_budget_canary_mocks "$ws"
            source "$RALPHIE_FILE"
            prepare_unit_terminal_contract "$ws"
            CODEX_CMD="$ws/bin/codex"
            CLAUDE_CMD="$ws/bin/claude"
            PRIME_CMD="$ws/bin/unavailable-prime"
            ENGINE_SELECTION_REQUESTED=auto
            AUTO_ENGINE_PREFERENCE=codex
            ENGINE_HEALTH_MAX_ATTEMPTS=6
            ENGINE_HEALTH_RETRY_DELAY_SECONDS=0
            ENGINE_HEALTH_RETRY_VERBOSE=false
            ENGINE_SMOKE_TEST_TIMEOUT=3
            ENGINE_CAPABILITIES_PROBED=false
            NO_TERMINAL_INPUT=true
            MAX_SESSION_CYCLES=1
            SESSION_TOKEN_RATE_CENTS_PER_MILLION=1000000
            CANARY_RECEIPT_DIR="$ws/canary-receipts"
            CANARY_FAIL="$fail_canary"
            mkdir "$CANARY_RECEIPT_DIR"
            export CANARY_RECEIPT_DIR CANARY_FAIL
            # Free capability/version checks are excluded from the finite cap.
            "$CODEX_CMD" --help >/dev/null
            "$CLAUDE_CMD" --version >/dev/null
            [ "$SESSION_ATTEMPT_COUNT" -eq 0 ]
            set +e
            if [ "$fail_canary" = true ]; then
                ensure_engines_ready auto > "$ws/health.out" 2>&1
            else
                probe_engine_capabilities true claude > "$ws/health.out" 2>&1
            fi
            status=$?
            set -e
            if [ "$fail_canary" = true ]; then
                [ "$status" -eq 75 ]
            else
                [ "$status" -eq 0 ]
                [ "$CLAUDE_SMOKE_PASS" = true ]
            fi
            [ "$(wc -l < "$CANARY_RECEIPT_DIR/calls" | tr -d ' ')" -eq 1 ]
            grep -qx claude "$CANARY_RECEIPT_DIR/calls"
            [ "$SESSION_ATTEMPT_COUNT" -eq 1 ]
            for prompt in "$CANARY_RECEIPT_DIR"/*.prompt; do
                prompt_bytes="$(wc -c < "$prompt" | tr -d ' ')"
                answer_bytes="$(wc -c < "${prompt%.prompt}.answer" | tr -d ' ')"
                expected_tokens=$((expected_tokens + (prompt_bytes + 3) / 4 + (answer_bytes + 3) / 4))
            done
            [ "$SESSION_TOKEN_COUNT" -eq "$expected_tokens" ]
            [ "$SESSION_COST_CENTS" -eq "$SESSION_TOKEN_COUNT" ]
            set +e
            smoke_test_engine "$CODEX_CMD" codex >> "$ws/health.out" 2>&1
            status=$?
            set -e
            [ "$status" -eq 75 ]
            [ "$ENGINE_BUDGET_EXHAUSTED" = true ]
            [ "$(wc -l < "$CANARY_RECEIPT_DIR/calls" | tr -d ' ')" -eq 1 ]
            [ "$SESSION_ATTEMPT_COUNT" -eq 1 ]
        )
    done
}

test_session_budget_imports_parallel_admissions_on_interrupt() {
    command -v python3 >/dev/null 2>&1 || return 200
    local ws
    ws="$(new_continuation_workspace)"
    python3 - "$ROOT_DIR/tests/durability/run-continuation-suite.sh" "$ws" <<'PY_PANEL_INTERRUPT'
import os
import pathlib
import signal
import subprocess
import sys
import time

suite, workspace = sys.argv[1:]
project = pathlib.Path(workspace) / 'project with spaces'
receipt = pathlib.Path(workspace) / 'run.out'
environment = os.environ.copy()
environment.update(CONTINUATION_QUALITY_LEVEL='standard', MOCK_PRIME_REVIEW_PAUSE='true')
code = 'source "$1"; run_continuation_fixture "$2" --objective "Preserve admitted parallel reviews on interrupt" --accept "bash check.sh" --plan-only'
with receipt.open('wb') as output:
    process = subprocess.Popen(['/bin/bash', '-c', code, 'panel-interrupt-fixture', suite, workspace],
                               stdout=output, stderr=subprocess.STDOUT, env=environment,
                               start_new_session=True)
    try:
        deadline = time.monotonic() + 45
        while True:
            calls_path = project / '.mock-prime/calls'
            pids_path = project / '.mock-prime/paused-reviewer-pids'
            calls = calls_path.read_text().splitlines() if calls_path.exists() else []
            pids = pids_path.read_text().splitlines() if pids_path.exists() else []
            if len(calls) == 4 and len(pids) == 4:
                break
            if process.poll() is not None or time.monotonic() >= deadline:
                raise RuntimeError('Two parallel reviewers did not reach admitted calls: ' + receipt.read_text(errors='replace'))
            time.sleep(0.05)
        worker = int((project / '.ralphie/run.lock').read_text().splitlines()[0])
        assert os.getpgid(worker) == process.pid
        os.kill(worker, signal.SIGTERM)
        assert process.wait(timeout=20) != 0
    except BaseException:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        raise
assert not (project / '.ralphie/run.lock').exists(), receipt.read_text(errors='replace')
actual_calls = len((project / '.mock-prime/calls').read_text().splitlines())
state = (project / '.ralphie/state.env').read_text().splitlines()
saved_count = [line for line in state if line.startswith('SESSION_ATTEMPT_COUNT=')]
assert saved_count == ['SESSION_ATTEMPT_COUNT="%d"' % actual_calls], (saved_count, actual_calls)
assert actual_calls == 4
for pid in pids:
    result = subprocess.run(['ps', '-p', pid, '-o', 'stat='], capture_output=True, text=True)
    assert not result.stdout.strip() or 'Z' in result.stdout, (pid, result.stdout)
PY_PANEL_INTERRUPT
    assert_incomplete_fixture "$ws" 143
    [ -z "$(find "$ws/engine-scratch" -mindepth 1 -print -quit)" ]
}

test_session_budget_admission_survives_sigkill_and_resume() {
    command -v python3 >/dev/null 2>&1 || return 200
    local ws
    ws="$(new_continuation_workspace)"
    python3 - "$ROOT_DIR/tests/durability/run-continuation-suite.sh" "$ws" <<'PY_BUDGET_KILL'
import os
import pathlib
import signal
import subprocess
import sys
import time

suite, workspace = sys.argv[1:]
project = pathlib.Path(workspace) / 'project with spaces'
environment = os.environ.copy()
environment['MOCK_PRIME_BLOCK_INFERENCE'] = 'true'
code = 'source "$1"; run_continuation_fixture "$2" --objective "Persist finite admission before a killed call" --accept "bash check.sh" --max-session-cycles 1'

def descendants(root):
    output = subprocess.check_output(['ps', '-A', '-o', 'pid=', '-o', 'ppid='], text=True)
    pairs = [tuple(map(int, line.split())) for line in output.splitlines() if line.strip()]
    selected = {root}
    while True:
        children = {pid for pid, parent in pairs if parent in selected}
        if children <= selected:
            return sorted(selected - {root})
        selected.update(children)

def stop_recorded(pids):
    # Only this fixture's finite, recorded child snapshot may be signalled.
    for sent_signal in (signal.SIGTERM, signal.SIGKILL):
        for pid in reversed(pids):
            try:
                os.kill(pid, sent_signal)
            except ProcessLookupError:
                pass
        time.sleep(0.2)

receipt = pathlib.Path(workspace) / 'run.out'
with receipt.open('wb') as output:
    process = subprocess.Popen(['/bin/bash', '-c', code, 'killed-budget-fixture', suite, workspace],
                               stdout=output, stderr=subprocess.STDOUT, env=environment,
                               start_new_session=True)
    recorded = []
    try:
        deadline = time.monotonic() + 45
        witness = project / '.mock-prime/blocked-inference-pids'
        while not witness.exists() or len(witness.read_text().splitlines()) != 2:
            if process.poll() is not None or time.monotonic() >= deadline:
                raise RuntimeError('Finite inference did not reach its blocking fixture: ' + receipt.read_text(errors='replace'))
            time.sleep(0.05)
        worker = int((project / '.ralphie/run.lock').read_text().splitlines()[0])
        assert os.getpgid(worker) == process.pid
        recorded = descendants(worker)
        assert set(map(int, witness.read_text().splitlines())) <= set(recorded)
        (pathlib.Path(workspace) / 'recorded-children').write_text('\n'.join(map(str, recorded)) + '\n')
        os.kill(worker, signal.SIGKILL)
        stop_recorded(recorded)
        assert process.wait(timeout=20) != 0
    except BaseException:
        recorded = recorded or descendants(process.pid)
        stop_recorded(recorded + [process.pid])
        process.wait()
        raise
state = (project / '.ralphie/state.env').read_text().splitlines()
assert 'SESSION_ATTEMPT_COUNT="1"' in state, state
assert len((project / '.mock-prime/calls').read_text().splitlines()) == 1
for pid in recorded:
    result = subprocess.run(['ps', '-p', str(pid), '-o', 'stat='], capture_output=True, text=True)
    assert not result.stdout.strip() or 'Z' in result.stdout, (pid, result.stdout)

environment['MOCK_PRIME_BLOCK_INFERENCE'] = 'false'
with (pathlib.Path(workspace) / 'resume.out').open('wb') as output:
    resumed = subprocess.Popen(['/bin/bash', '-c', code, 'resumed-budget-fixture', suite, workspace],
                               stdout=output, stderr=subprocess.STDOUT, env=environment,
                               start_new_session=True)
    try:
        assert resumed.wait(timeout=20) != 0
    except BaseException:
        stop_recorded(descendants(resumed.pid) + [resumed.pid])
        resumed.wait()
        raise
assert len((project / '.mock-prime/calls').read_text().splitlines()) == 1
assert 'SESSION_ATTEMPT_COUNT="1"' in (project / '.ralphie/state.env').read_text().splitlines()
assert not (project / '.ralphie/run.lock').exists()
PY_BUDGET_KILL
    assert_incomplete_fixture "$ws" 137
}

test_session_budget_refuses_unsafe_admission_checkpoint_without_inference() {
    local kind
    for kind in directory symlink; do
        (
            local ws status
            ws="$(new_continuation_workspace)"
            source "$RALPHIE_FILE"
            prepare_unit_terminal_contract "$ws"
            STATE_FILE="$CONFIG_DIR/state.env"
            printf 'operator state remains unchanged\n' > "$ws/operator-state"
            cp "$ws/operator-state" "$ws/expected-operator-state"
            if [ "$kind" = directory ]; then mkdir "$STATE_FILE"; else ln -s "$ws/operator-state" "$STATE_FILE"; fi
            RALPHIE_CLEANUP_STATE_ENABLED=true
            MAX_SESSION_CYCLES=1
            ENGINE_CAPABILITIES_PROBED=true
            PRIME_CAP_PRINT=1
            PRIME_HEALTHY=true
            ACTIVE_ENGINE=prime-agent
            PRIME_CMD="$ws/bin/prime-agent"
            ACTIVE_CMD="$PRIME_CMD"
            PRIME_PROVIDER=fixture-provider
            PRIME_MODEL=fixture-model
            PRIME_THINKING_OVERRIDE=max
            printf '# Ralphie Plan Phase Prompt\n' > "$ws/prompt.md"
            set +e
            run_agent_with_prompt "$ws/prompt.md" "$ws/engine.log" "$ws/answer.out" false > "$ws/admission.out" 2>&1
            status=$?
            set -e
            [ "$status" -eq 75 ]
            [ "$ENGINE_BUDGET_EXHAUSTED" = true ]
            [ ! -e "$PROJECT_DIR/.mock-prime/calls" ]
            cmp "$ws/expected-operator-state" "$ws/operator-state"
        )
    done
}

test_prime_full_lifecycle_and_real_checks() {
    local ws phase
    ws="$(new_continuation_workspace)"
    CONTINUATION_ENGINE=auto
    run_continuation_fixture "$ws" --objective 'Finish the fixture' --accept 'bash check.sh' >"$ws/run.out" 2>&1
    printf 'plan\nbuild\ntest\nrefactor\ntest\nlint\ndocument\n' > "$ws/expected-phases"
    cmp "$ws/expected-phases" "$ws/project with spaces/.mock-prime/phases"
    grep -q '^CURRENT_PHASE="done"' "$ws/project with spaces/.ralphie/state.env"
    [ -s "$ws/project with spaces/check-receipts.log" ]
    for phase in plan build test refactor lint document; do
        grep -q "^handoff:$phase$" "$ws/project with spaces/.mock-prime/roles"
        grep -q "^consensus:$phase$" "$ws/project with spaces/.mock-prime/roles"
    done
    grep -q 'provider=fixture-provider model=fixture-model thinking=max' "$ws/project with spaces/.mock-prime/calls"
    [ ! -e "$ws/.ralphie" ]
    [ ! -e "$ws/IMPLEMENTATION_PLAN.md" ]
}

test_project_subdirectory_is_rejected_before_runtime_writes() {
    local ws status before_head after_head
    ws="$(new_continuation_workspace)"
    printf 'operator staged bytes\n' > "$ws/project with spaces/operator.txt"
    cp "$ws/project with spaces/operator.txt" "$ws/expected-operator"
    git -C "$ws/project with spaces" add -- operator.txt
    cp "$ws/project with spaces/.git/index" "$ws/expected-index"
    before_head="$(git -C "$ws/project with spaces" rev-parse HEAD)"
    mkdir "$ws/project with spaces/subdir target"
    set +e
    run_continuation_fixture "$ws" --project "$ws/project with spaces/subdir target" \
        --objective 'Reject an unsafe Git subtree target' --accept true >"$ws/run.out" 2>&1
    status=$?
    set -e
    [ "$status" -ne 0 ]
    grep -qiE 'git.*(root|top.level)' "$ws/run.out"
    [ ! -e "$ws/project with spaces/subdir target/.ralphie" ]
    [ ! -e "$ws/project with spaces/.mock-prime" ]
    after_head="$(git -C "$ws/project with spaces" rev-parse HEAD)"
    [ "$before_head" = "$after_head" ]
    cmp "$ws/expected-index" "$ws/project with spaces/.git/index"
    cmp "$ws/expected-operator" "$ws/project with spaces/operator.txt"
}

test_prime_failure_is_not_success() {
    local ws status
    ws="$(new_continuation_workspace)"
    MOCK_PRIME_FAIL_INFERENCE=true
    set +e
    run_continuation_fixture "$ws" --objective 'Fail the provider fixture' --accept 'bash check.sh' >"$ws/run.out" 2>&1
    status=$?
    set -e
    assert_incomplete_fixture "$ws" "$status"
    grep -q 'fixture provider failed' "$ws/run.out" "$ws/project with spaces"/logs/*.log
}

test_prime_permanent_auth_failure_does_not_retry_or_fallback() {
    local ws status
    ws="$(new_continuation_workspace)"
    CONTINUATION_ENGINE=auto
    MOCK_PRIME_PERMANENT_FAILURE=true
    set +e
    run_continuation_fixture "$ws" --objective 'Stop on permanent provider configuration failure' --accept 'bash check.sh' \
        --run-agent-max-attempts 6 --max-phase-completion-attempts 5 >"$ws/run.out" 2>&1
    status=$?
    set -e
    assert_incomplete_fixture "$ws" "$status"
    [ "$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')" -eq 1 ]
    grep -q 'No API key for provider:.*token error' "$ws/run.out" "$ws/project with spaces"/logs/*.log
}

test_prime_permanent_reviewer_failure_stops_phase_retry() {
    local ws status
    ws="$(new_continuation_workspace)"
    MOCK_PRIME_REVIEW_PERMANENT_FAILURE=true
    set +e
    run_continuation_fixture "$ws" --objective 'Stop a panel on permanent reviewer configuration failure' --accept 'bash check.sh' \
        --run-agent-max-attempts 6 --max-phase-completion-attempts 5 >"$ws/run.out" 2>&1
    status=$?
    set -e
    assert_incomplete_fixture "$ws" "$status"
    printf 'plan\n' > "$ws/expected-phases"
    cmp "$ws/expected-phases" "$ws/project with spaces/.mock-prime/phases"
    [ "$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')" -eq 3 ]
    grep -rq '^exit_code=126$' "$ws/project with spaces/consensus"
    grep -rq '^failure_kind=permanent$' "$ws/project with spaces/consensus"
}

test_validation_only_phases_do_not_require_empty_commits() {
    local ws before_head after_head
    ws="$(new_continuation_workspace)"
    git -C "$ws/project with spaces" config user.name 'Offline Fixture'
    git -C "$ws/project with spaces" config user.email fixture@example.test
    git -C "$ws/project with spaces" config commit.gpgsign false
    before_head="$(git -C "$ws/project with spaces" rev-parse HEAD)"
    CONTINUATION_AUTO_COMMIT=true
    MOCK_PRIME_VALIDATION_ONLY=true
    run_continuation_fixture "$ws" --objective 'Complete saved work with validation-only test phases' --accept 'bash check.sh' >"$ws/run.out" 2>&1
    grep -q '^CURRENT_PHASE="done"' "$ws/project with spaces/.ralphie/state.env"
    [ "$(grep -c '^test$' "$ws/project with spaces/.mock-prime/phases")" -eq 2 ]
    after_head="$(git -C "$ws/project with spaces" rev-parse HEAD)"
    [ "$before_head" != "$after_head" ]
    if git -C "$ws/project with spaces" log --format=%s "$before_head..$after_head" | grep -q '^test->'; then return 1; fi
}

prepare_owned_resume_fixture() {
    local ws="$1"
    git -C "$ws/project with spaces" config user.name 'Offline Fixture'
    git -C "$ws/project with spaces" config user.email fixture@example.test
    git -C "$ws/project with spaces" config commit.gpgsign false
    printf 'operator baseline\n' > "$ws/project with spaces/operator.txt"
    git -C "$ws/project with spaces" add -- operator.txt
    git -C "$ws/project with spaces" commit -qm 'operator baseline'
    printf 'operator unsaved work\n' >> "$ws/project with spaces/operator.txt"
    CONTINUATION_AUTO_COMMIT=true
}

assert_owned_resume_saved_without_operator_work() {
    local ws="$1"
    grep -q '^CURRENT_PHASE="done"' "$ws/project with spaces/.ralphie/state.env"
    git -C "$ws/project with spaces" show HEAD:implementation.txt > "$ws/saved-implementation"
    cmp "$ws/saved-implementation" "$ws/project with spaces/implementation.txt"
    grep -qx implemented "$ws/saved-implementation"
    [ "$(git -C "$ws/project with spaces" show HEAD:operator.txt)" = 'operator baseline' ]
    grep -qx 'operator unsaved work' "$ws/project with spaces/operator.txt"
    git -C "$ws/project with spaces" diff --cached --quiet
}

test_failed_worker_bytes_remain_owned_on_resume() {
    local ws status
    ws="$(new_continuation_workspace)"
    prepare_owned_resume_fixture "$ws"
    MOCK_PRIME_WORKER_FAIL_ONCE=true
    set +e
    run_continuation_fixture "$ws" --objective 'Resume worker-owned changes after a failed build' --accept 'bash check.sh' \
        --max-session-cycles 0 --max-iterations 2 >"$ws/run.out" 2>&1
    status=$?
    set -e
    assert_incomplete_fixture "$ws" "$status"
    [ "$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')" -eq 4 ]
    grep -q '^SESSION_ATTEMPT_COUNT="4"' "$ws/project with spaces/.ralphie/state.env"
    grep -qx 'incomplete implementation' "$ws/project with spaces/implementation.txt"
    run_continuation_fixture "$ws" --objective 'Resume worker-owned changes after a failed build' --accept 'bash check.sh' \
        --max-phase-completion-attempts 3 --max-consensus-routing-attempts 3 >"$ws/resume.out" 2>&1
    assert_owned_resume_saved_without_operator_work "$ws"
}

test_interrupted_worker_restores_inputs_and_keeps_owned_resume() {
    command -v python3 >/dev/null 2>&1 || return 200
    local ws
    ws="$(new_continuation_workspace)"
    prepare_owned_resume_fixture "$ws"
    python3 - "$ROOT_DIR/tests/durability/run-continuation-suite.sh" "$ws" <<'PY_INTERRUPT'
import os
import pathlib
import signal
import subprocess
import sys
import time

suite, workspace = sys.argv[1:]
project = pathlib.Path(workspace) / 'project with spaces'
receipt = pathlib.Path(workspace) / 'interrupt.out'
environment = os.environ.copy()
environment.update(CONTINUATION_AUTO_COMMIT='true', MOCK_PRIME_WORKER_PAUSE_ONCE='true')
code = 'source "$1"; run_continuation_fixture "$2" --objective "Resume an interrupted owned build" --accept "bash check.sh"'
with receipt.open('wb') as output:
    process = subprocess.Popen(['/bin/bash', '-c', code, 'interrupt-fixture', suite, workspace],
                               stdout=output, stderr=subprocess.STDOUT, env=environment,
                               start_new_session=True)
    try:
        deadline = time.monotonic() + 45
        while not (project / '.mock-prime/paused').exists():
            if process.poll() is not None or time.monotonic() >= deadline:
                raise RuntimeError('Worker did not reach its interruption checkpoint')
            time.sleep(0.05)
        worker = int((project / '.ralphie/run.lock').read_text().splitlines()[0])
        assert os.getpgid(worker) == process.pid
        os.kill(worker, signal.SIGTERM)
        assert process.wait(timeout=20) != 0
    except BaseException:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        raise
assert not (project / '.ralphie/run.lock').exists(), receipt.read_text(errors='replace')
PY_INTERRUPT
    cmp "$ws/project with spaces/.mock-prime/original-gates" "$ws/project with spaces/.ralphie/gates"
    cmp "$ws/project with spaces/.mock-prime/original-bootstrap" "$ws/project with spaces/.ralphie/project-bootstrap.md"
    grep -qx 'interrupted implementation' "$ws/project with spaces/implementation.txt"
    [ -z "$(find "$ws/engine-scratch" -mindepth 1 -print -quit)" ]
    MOCK_PRIME_WORKER_PAUSE_ONCE=true
    run_continuation_fixture "$ws" --objective 'Resume an interrupted owned build' --accept 'bash check.sh' \
        --max-phase-completion-attempts 3 >"$ws/resume.out" 2>&1
    assert_owned_resume_saved_without_operator_work "$ws"
}

configure_prime_adapter_fixture() {
    local ws="$1"
    # Source only the frozen candidate; invoke the strict free CLI fixture.
    source "$RALPHIE_FILE"
    PROJECT_DIR="$ws/project with spaces"
    CONFIG_DIR="$PROJECT_DIR/.ralphie"
    ACTIVE_ENGINE=prime-agent
    ACTIVE_CMD="$ws/bin/prime-agent"
    PRIME_CMD="$ACTIVE_CMD"
    PRIME_HEALTHY=true
    PRIME_PROVIDER=fixture-provider
    PRIME_MODEL=fixture-model
    PRIME_THINKING_OVERRIDE=max
    mkdir -p "$ws/engine-scratch"
    TMPDIR="$ws/engine-scratch"
    export TMPDIR
    RUN_AGENT_MAX_ATTEMPTS=1
    RUN_AGENT_RETRY_DELAY_SECONDS=0
    ENGINE_OUTPUT_TO_STDOUT=false
    ENGINE_IDLE_OUTPUT_TIMEOUT_SECONDS=1
    COMMAND_TIMEOUT_SECONDS=8
    printf '# Handoff Validation Prompt\nPhase: plan\n' > "$ws/prompt.md"
}

test_prime_buffered_output_and_hard_timeout() {
    local ws status
    ws="$(new_continuation_workspace)"
    configure_prime_adapter_fixture "$ws"
    export MOCK_PRIME_SILENT_SECONDS=2
    run_agent_with_prompt "$ws/prompt.md" "$ws/silent.log" "$ws/silent.out" true 1
    grep -q '<verdict>GO</verdict>' "$ws/silent.out"
    # The independent hard bound must still work without GNU timeout.
    get_timeout_command() { printf '\n'; }
    COMMAND_TIMEOUT_SECONDS=1
    export MOCK_PRIME_SILENT_SECONDS=3
    set +e
    run_agent_with_prompt "$ws/prompt.md" "$ws/timed.log" "$ws/timed.out" true 1
    status=$?
    set -e
    [ "$status" -ne 0 ]
    if grep -q '<verdict>GO</verdict>' "$ws/timed.out"; then return 1; fi
    [ -z "$(find "$TMPDIR" -mindepth 1 -print -quit)" ]
}

test_prime_stderr_cannot_forge_answers_and_output_is_bounded() {
    local ws status
    ws="$(new_continuation_workspace)"
    configure_prime_adapter_fixture "$ws"
    export MOCK_PRIME_STDERR_XML=true
    run_agent_with_prompt "$ws/prompt.md" "$ws/diagnostic.log" "$ws/answer.out" true 1
    [ "$(grep -c '<verdict>' "$ws/answer.out")" -eq 1 ]
    grep -q '<verdict>GO</verdict>' "$ws/answer.out"
    if grep -q 'fixture stderr only' "$ws/answer.out"; then return 1; fi
    grep -q 'fixture stderr only' "$ws/diagnostic.log"
    unset MOCK_PRIME_STDERR_XML
    export MOCK_PRIME_LARGE_OUTPUT=true
    ENGINE_OUTPUT_MAX_BYTES=128
    set +e
    run_agent_with_prompt "$ws/prompt.md" "$ws/capped.log" "$ws/capped.out" true 1
    status=$?
    set -e
    [ "$status" -ne 0 ]
    [ ! -s "$ws/capped.out" ]
    [ "$(wc -c < "$ws/capped.log" | tr -d ' ')" -le 128 ]
    [ -z "$(find "$TMPDIR" -mindepth 1 -print -quit)" ]
}

test_prime_infinite_unterminated_output_stops_at_cap() {
    command -v python3 >/dev/null 2>&1 || return 200
    local ws
    ws="$(new_continuation_workspace)"
    python3 - "$ROOT_DIR/tests/durability/run-continuation-suite.sh" "$ws" <<'PY_CAP'
import os
import signal
import subprocess
import sys

suite, workspace = sys.argv[1:]
code = '''
source "$1"
prepare_isolated_target
trap 'cleanup_isolated_target; cleanup_offline_test_guards' EXIT
configure_prime_adapter_fixture "$2"
COMMAND_TIMEOUT_SECONDS=0
ENGINE_OUTPUT_MAX_BYTES=128
export MOCK_PRIME_INFINITE_OUTPUT=true
set +e
run_agent_with_prompt "$2/prompt.md" "$2/infinite.log" "$2/infinite.out" true 1
status=$?
set -e
[ "$status" -ne 0 ]
[ ! -s "$2/infinite.out" ]
'''
process = subprocess.Popen(['/bin/bash', '-c', code, 'cap-fixture', suite, workspace],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           start_new_session=True)
try:
    output, _ = process.communicate(timeout=8)
except subprocess.TimeoutExpired:
    os.killpg(process.pid, signal.SIGKILL)
    output, _ = process.communicate()
    raise SystemExit('Output cap did not stop an infinite no-newline producer:\n' + output.decode(errors='replace'))
if process.returncode:
    raise SystemExit('Output-cap fixture failed:\n' + output.decode(errors='replace'))
PY_CAP
}

test_process_cleanup_without_pgrep_kills_term_ignoring_grandchild() {
    local ws tree_pid child_pid grandchild_pid poll state
    ws="$(new_continuation_workspace)"
    source "$RALPHIE_FILE"
    # This deliberately unavailable optional command must not be needed.
    pgrep() { return 127; }
    (
        (
            trap '' TERM
            ( trap '' TERM; exec sleep 30 ) &
            printf '%s\n' "$!" > "$ws/grandchild.pid"
            wait
        ) &
        printf '%s\n' "$!" > "$ws/child.pid"
        wait
    ) &
    tree_pid=$!
    trap 'kill -KILL "$tree_pid" "${child_pid:-}" "${grandchild_pid:-}" 2>/dev/null || true' EXIT
    poll=0
    while [ ! -s "$ws/grandchild.pid" ] && [ "$poll" -lt 30 ]; do sleep 0.1; poll=$((poll + 1)); done
    [ -s "$ws/grandchild.pid" ]
    child_pid="$(cat "$ws/child.pid")"
    grandchild_pid="$(cat "$ws/grandchild.pid")"
    kill -0 "$grandchild_pid"
    stop_process_tree "$tree_pid"
    poll=0
    while [ "$poll" -lt 30 ]; do
        state="$(ps -p "$grandchild_pid" -o stat= 2>/dev/null || true)"
        case "$state" in ''|*Z*) break ;; esac
        sleep 0.1
        poll=$((poll + 1))
    done
    case "$state" in ''|*Z*) ;; *) return 1 ;; esac
    wait "$tree_pid" 2>/dev/null || true
    trap - EXIT
}

test_autocommit_protects_unusual_operator_paths() {
    local ws name before_head after_head
    local -a names=('operator notes.txt' $'operator\ttab.txt' 'café.txt' $'operator\nnewline.txt' '--operator.txt' 'literal[ab]*?.txt' ':(glob)operator.txt')
    ws="$(new_continuation_workspace)"
    source "$RALPHIE_FILE"
    PROJECT_DIR="$ws/project with spaces"
    CONFIG_DIR="$PROJECT_DIR/.ralphie"
    LOG_DIR="$PROJECT_DIR/logs"
    mkdir -p "$LOG_DIR"
    git -C "$PROJECT_DIR" init -q
    git -C "$PROJECT_DIR" config user.name 'Offline Fixture'
    git -C "$PROJECT_DIR" config user.email 'fixture@example.test'
    git -C "$PROJECT_DIR" config commit.gpgsign false
    for name in "${names[@]}"; do
        printf 'base\n' > "$PROJECT_DIR/$name"
        git --literal-pathspecs -C "$PROJECT_DIR" add -- "$name"
    done
    git -C "$PROJECT_DIR" commit -qm 'initial fixture'
    AUTO_COMMIT_SESSION_ENABLED=true
    AUTO_COMMIT_ON_PHASE_PASS=true
    AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE="$ws/baseline-dirty"
    PHASE_MANIFEST_MODE=deep
    export GIT_AUTHOR_NAME='Offline Fixture' GIT_COMMITTER_NAME='Offline Fixture'
    export GIT_AUTHOR_EMAIL='fixture@example.test' GIT_COMMITTER_EMAIL='fixture@example.test'
    before_head="$(git -C "$PROJECT_DIR" rev-parse HEAD)"
    for name in "${names[@]}"; do
        printf 'operator work\n' >> "$PROJECT_DIR/$name"
        collect_git_dirty_paths > "$AUTO_COMMIT_BASELINE_DIRTY_PATHS_FILE"
        phase_capture_worktree_manifest "$ws/manifest.before"
        printf 'engine work\n' >> "$PROJECT_DIR/$name"
        phase_capture_worktree_manifest "$ws/manifest.after"
        set +e
        commit_phase_approved_changes build test "$ws/manifest.before" "$ws/manifest.after"
        set -e
        after_head="$(git -C "$PROJECT_DIR" rev-parse HEAD)"
        [ "$before_head" = "$after_head" ]
        git -C "$PROJECT_DIR" diff --cached --quiet
        grep -q '^operator work$' "$PROJECT_DIR/$name"
        printf 'base\n' > "$PROJECT_DIR/$name"
    done
}

test_failing_check_cannot_be_outvoted() {
    local ws status
    ws="$(new_continuation_workspace)"
    printf '#!/usr/bin/env bash\nprintf "actually failed\\n" >> failing-check.receipt\nexit 19\n' > "$ws/project with spaces/check.sh"
    set +e
    run_continuation_fixture "$ws" --objective 'Exercise a failing check' --accept 'bash check.sh' --accept true >"$ws/run.out" 2>&1
    status=$?
    set -e
    assert_incomplete_fixture "$ws" "$status"
    [ -s "$ws/project with spaces/failing-check.receipt" ]
}

test_check_prose_does_not_replace_missing_checks() {
    local ws status
    ws="$(new_continuation_workspace)"
    rm "$ws/project with spaces/check.sh"
    set +e
    run_continuation_fixture "$ws" --objective 'Require an actual project check' >"$ws/run.out" 2>&1
    status=$?
    set -e
    assert_incomplete_fixture "$ws" "$status"
}

test_worker_cannot_shrink_gate_commands() {
    local ws status
    ws="$(new_continuation_workspace)"
    printf 'bash check.sh\n' > "$ws/project with spaces/.ralphie/gates"
    printf 'bash check.sh\n' > "$ws/expected-gates"
    MOCK_PRIME_TAMPER_GATES=true
    set +e
    run_continuation_fixture "$ws" --objective 'Protect operator checks' >"$ws/run.out" 2>&1
    status=$?
    set -e
    assert_incomplete_fixture "$ws" "$status"
    cmp "$ws/expected-gates" "$ws/project with spaces/.ralphie/gates"
}

test_reviewer_changes_are_checked_again() {
    local ws status
    ws="$(new_continuation_workspace)"
    MOCK_PRIME_REVIEW_BREAK_CHECK=true
    set +e
    run_continuation_fixture "$ws" --objective 'Check the final reviewed tree' --accept 'bash check.sh' >"$ws/run.out" 2>&1
    status=$?
    set -e
    assert_incomplete_fixture "$ws" "$status"
    grep -q '^consensus:document$' "$ws/project with spaces/.mock-prime/roles"
    grep -q '^exit 17$' "$ws/project with spaces/check.sh"
}

test_reviewer_cannot_shrink_gate_commands() {
    local ws status
    ws="$(new_continuation_workspace)"
    printf 'bash check.sh\n' > "$ws/project with spaces/.ralphie/gates"
    printf 'bash check.sh\n' > "$ws/expected-gates"
    MOCK_PRIME_REVIEW_TAMPER_GATES=true
    set +e
    run_continuation_fixture "$ws" --objective 'Keep reviewer gate authority bounded' >"$ws/run.out" 2>&1
    status=$?
    set -e
    assert_incomplete_fixture "$ws" "$status"
    grep -q '^consensus:document$' "$ws/project with spaces/.mock-prime/roles"
    cmp "$ws/expected-gates" "$ws/project with spaces/.ralphie/gates"
}

test_check_cannot_pass_then_write_broken_source() {
    local ws status
    ws="$(new_continuation_workspace)"
    printf 'base\n' > "$ws/project with spaces/code.txt"
    git -C "$ws/project with spaces" add -- code.txt
    git -C "$ws/project with spaces" -c user.name='Offline Fixture' -c user.email=fixture@example.test -c commit.gpgsign=false commit -qm 'source fixture'
    printf 'good\n' > "$ws/project with spaces/code.txt"
    mkdir -p "$ws/project with spaces/.mock-prime"
    cp -p "$ws/project with spaces/code.txt" "$ws/project with spaces/.mock-prime/code-reference"
    cat > "$ws/project with spaces/check.sh" <<'EOF_MUTATING_CHECK'
#!/usr/bin/env bash
set -e
grep -qx good code.txt
printf 'checked good code\n' >> check-receipts.log
printf 'evil\n' > code.txt
touch -r .mock-prime/code-reference code.txt
exit 0
EOF_MUTATING_CHECK
    set +e
    run_continuation_fixture "$ws" --objective 'Reject checks that invalidate their own proof' --accept 'bash check.sh' >"$ws/run.out" 2>&1
    status=$?
    set -e
    assert_incomplete_fixture "$ws" "$status"
    grep -qx evil "$ws/project with spaces/code.txt"
    grep -qx 'checked good code' "$ws/project with spaces/check-receipts.log"
}

test_exact_spec_plan_only_and_seed_resume() {
    local ws status before_count after_count
    ws="$(new_continuation_workspace)"
    printf 'Complete fixture intake.\n\nLiteral bytes: $() `not a command` and Unicode caf\303\251.\n\n' > "$ws/seed file.md"
    ( cd "$ws"; run_continuation_fixture "$ws" --spec 'seed file.md' --accept 'bash check.sh' --plan-only ) >"$ws/run.out" 2>&1
    grep -q '^CURRENT_PHASE="build"' "$ws/project with spaces/.ralphie/state.env"
    grep -q '^PHASE_ATTEMPT_IN_PROGRESS="false"' "$ws/project with spaces/.ralphie/state.env"
    printf 'plan\n' > "$ws/expected-phases"
    cmp "$ws/expected-phases" "$ws/project with spaces/.mock-prime/phases"
    grep -q 'Planning complete' "$ws/run.out"
    # The exact seed must be retained, including its final blank line.
    local found_exact=false candidate
    while IFS= read -r candidate; do
        if cmp -s "$ws/seed file.md" "$candidate"; then found_exact=true; break; fi
    done < <(find "$ws/project with spaces/.ralphie" -type f)
    [ "$found_exact" = true ]
    before_count="$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')"
    printf 'A changed objective.\n' >> "$ws/seed file.md"
    set +e
    run_continuation_fixture "$ws" --spec "$ws/seed file.md" --accept 'bash check.sh' >"$ws/conflict.out" 2>&1
    status=$?
    set -e
    [ "$status" -ne 0 ]
    grep -q -- '--no-resume' "$ws/conflict.out"
    after_count="$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')"
    [ "$before_count" -eq "$after_count" ]
    run_continuation_fixture "$ws" --spec "$ws/seed file.md" --no-resume --plan-only >"$ws/reseed.out" 2>&1
    [ "$(grep -c '^plan$' "$ws/project with spaces/.mock-prime/phases")" -eq 2 ]
    run_continuation_fixture "$ws" --spec "$ws/seed file.md" --accept 'bash check.sh' >"$ws/resume.out" 2>&1
    grep -q '^CURRENT_PHASE="done"' "$ws/project with spaces/.ralphie/state.env"
    [ "$(grep -c '^plan$' "$ws/project with spaces/.mock-prime/phases")" -eq 2 ]
}

test_seeded_plan_never_reads_attached_terminal() {
    command -v python3 >/dev/null 2>&1 || return 200
    local ws
    ws="$(new_continuation_workspace)"
    python3 - "$ROOT_DIR/tests/durability/run-continuation-suite.sh" "$ws" <<'PY_PTY'
import errno
import fcntl
import os
import pty
import select
import signal
import subprocess
import sys
import termios
import time

suite, workspace = sys.argv[1:]
master, slave = pty.openpty()
def attach_terminal():
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)
code = 'source "$1"; run_continuation_fixture "$2" --objective "Seeded terminal fixture" --plan-only'
process = subprocess.Popen(['/bin/bash', '-c', code, 'pty-fixture', suite, workspace],
                           stdin=slave, stdout=slave, stderr=slave,
                           preexec_fn=attach_terminal)
os.close(slave)
output = bytearray()
deadline = time.monotonic() + 45
try:
    while process.poll() is None and time.monotonic() < deadline:
        if select.select([master], [], [], 0.1)[0]:
            try:
                chunk = os.read(master, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            output.extend(chunk)
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
        raise SystemExit('Seeded run blocked with a terminal attached:\n' + output.decode(errors='replace'))
    if process.wait() != 0:
        raise SystemExit('Seeded PTY run failed:\n' + output.decode(errors='replace'))
    while select.select([master], [], [], 0)[0]:
        try:
            chunk = os.read(master, 65536)
        except OSError as error:
            if error.errno == errno.EIO:
                break
            raise
        if not chunk:
            break
        output.extend(chunk)
finally:
    os.close(master)
assert b'Planning complete' in output, output.decode(errors='replace')
for prompt in (b'Is this a new project', b'Proceed from PLAN', b'Action [r/l/p/q/h]'):
    assert prompt not in output, output.decode(errors='replace')
PY_PTY
}

continuation_case() {
    local name="$1"
    if [ -n "${CONTINUATION_FILTER:-}" ] && [[ "$name" != *"$CONTINUATION_FILTER"* ]]; then return 0; fi
    run_case "$name" "$2"
}

main() {
    CONTINUATION_FILTER="${1:-}"
    prepare_isolated_target
    trap 'cleanup_isolated_target; cleanup_offline_test_guards' EXIT
    capture_repo_tracked_status_baseline
    continuation_case session_budget_counts_parallel_reviewers_and_retries test_session_budget_counts_parallel_reviewers_and_retries
    continuation_case session_budget_allows_last_admitted_success test_session_budget_allows_last_admitted_success
    continuation_case session_budget_stops_parallel_admission_at_exact_cap test_session_budget_stops_parallel_admission_at_exact_cap
    continuation_case session_budget_accounts_for_health_canaries_and_blocks_retry test_session_budget_accounts_for_health_canaries_and_blocks_retry
    continuation_case session_budget_imports_parallel_admissions_on_interrupt test_session_budget_imports_parallel_admissions_on_interrupt
    continuation_case session_budget_admission_survives_sigkill_and_resume test_session_budget_admission_survives_sigkill_and_resume
    continuation_case session_budget_refuses_unsafe_admission_checkpoint_without_inference test_session_budget_refuses_unsafe_admission_checkpoint_without_inference
    continuation_case prime_full_lifecycle_and_real_checks test_prime_full_lifecycle_and_real_checks
    continuation_case project_subdirectory_is_rejected_before_runtime_writes test_project_subdirectory_is_rejected_before_runtime_writes
    continuation_case prime_failure_is_not_success test_prime_failure_is_not_success
    continuation_case prime_permanent_auth_failure_does_not_retry_or_fallback test_prime_permanent_auth_failure_does_not_retry_or_fallback
    continuation_case prime_permanent_reviewer_failure_stops_phase_retry test_prime_permanent_reviewer_failure_stops_phase_retry
    continuation_case validation_only_phases_do_not_require_empty_commits test_validation_only_phases_do_not_require_empty_commits
    continuation_case failed_worker_bytes_remain_owned_on_resume test_failed_worker_bytes_remain_owned_on_resume
    continuation_case interrupted_worker_restores_inputs_and_keeps_owned_resume test_interrupted_worker_restores_inputs_and_keeps_owned_resume
    continuation_case prime_buffered_output_and_hard_timeout test_prime_buffered_output_and_hard_timeout
    continuation_case prime_stderr_cannot_forge_answers_and_output_is_bounded test_prime_stderr_cannot_forge_answers_and_output_is_bounded
    continuation_case prime_infinite_unterminated_output_stops_at_cap test_prime_infinite_unterminated_output_stops_at_cap
    continuation_case process_cleanup_without_pgrep_kills_term_ignoring_grandchild test_process_cleanup_without_pgrep_kills_term_ignoring_grandchild
    continuation_case autocommit_protects_unusual_operator_paths test_autocommit_protects_unusual_operator_paths
    continuation_case failing_check_cannot_be_outvoted test_failing_check_cannot_be_outvoted
    continuation_case check_prose_does_not_replace_missing_checks test_check_prose_does_not_replace_missing_checks
    continuation_case worker_cannot_shrink_gate_commands test_worker_cannot_shrink_gate_commands
    continuation_case reviewer_changes_are_checked_again test_reviewer_changes_are_checked_again
    continuation_case reviewer_cannot_shrink_gate_commands test_reviewer_cannot_shrink_gate_commands
    continuation_case check_cannot_pass_then_write_broken_source test_check_cannot_pass_then_write_broken_source
    continuation_case exact_spec_plan_only_and_seed_resume test_exact_spec_plan_only_and_seed_resume
    continuation_case seeded_plan_never_reads_attached_terminal test_seeded_plan_never_reads_attached_terminal
    info "Continuation total: $TOTAL_COUNT | Passed: $PASS_COUNT | Failed: $FAIL_COUNT | Skipped: $SKIP_COUNT"
    [ "$TOTAL_COUNT" -gt 0 ]
    [ "$TOTAL_COUNT" -eq "$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))" ]
    [ "$FAIL_COUNT" -eq 0 ]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
