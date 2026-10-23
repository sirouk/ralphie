#!/usr/bin/env bash
set -euo pipefail

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/durability/run-continuation-suite.sh
source "$SUITE_DIR/run-continuation-suite.sh"

STEERING_OBJECTIVE='Complete the fixture while honoring durable operator requests'
STEERING_RUN_PID=''

steering_control() {
    local ws="$1"
    shift
    env -i PATH="$RALPHIE_TEST_GUARD_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
        HOME="$ws/home" TMPDIR="$ws/engine-scratch" LANG=en_US.UTF-8 TERM=dumb \
        PRIME_ENGINE_CMD="$ws/bin/control-engine-refused" \
        CODEX_ENGINE_CMD="$ws/bin/control-engine-refused" \
        CLAUDE_ENGINE_CMD="$ws/bin/control-engine-refused" \
        RALPHIE_AUTO_UPDATE=false RALPHIE_NOTIFICATIONS_ENABLED=false \
        /bin/bash "$ws/ralphie.sh" --project "$ws/project with spaces" "$@"
}

steering_initialize() {
    local ws="$1"
    shift
    run_continuation_fixture "$ws" --objective "$STEERING_OBJECTIVE" \
        --accept 'bash check.sh' --plan-only "$@" > "$ws/initialize.out" 2>&1
    grep -q '^CURRENT_PHASE="build"' "$ws/project with spaces/.ralphie/state.env"
    [ "$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')" -eq 3 ]
    cat > "$ws/bin/control-engine-refused" <<'EOF_CONTROL_GUARD'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$(dirname "$0")/control-engine.calls"
printf 'Control commands must not invoke an engine.\n' >&2
exit 97
EOF_CONTROL_GUARD
    chmod +x "$ws/bin/control-engine-refused"
}

steering_assert_body_is_durable() {
    local ws="$1" expected="$2" candidate found=false
    while IFS= read -r -d '' candidate; do
        if cmp -s "$expected" "$candidate"; then found=true; break; fi
    done < <(find "$ws/project with spaces/.ralphie" -type f -print0)
    [ "$found" = true ] || { fail 'No exact durable copy of the request body exists.'; return 1; }
}

steering_make_legacy_checkpoint() {
    local ws="$1" state checksum
    state="$ws/project with spaces/.ralphie/state.env"
    sed '/^REQUEST_REVIEWED_FINGERPRINT=/d; /^STATE_CHECKSUM=/d' "$state" > "$ws/legacy-state"
    checksum="$(/bin/bash -c 'export RALPHIE_LIB=1; source "$1"; sha256_file_sum "$2"' \
        legacy-checksum "$ws/ralphie.sh" "$ws/legacy-state")"
    printf 'STATE_CHECKSUM="%s"\n' "$checksum" >> "$ws/legacy-state"
    mv "$ws/legacy-state" "$state"
    mv "$ws/project with spaces/.ralphie/requests" "$ws/new-queue.saved"
}

test_request_controls_are_sideband_and_exact() {
    local ws calls
    ws="$(new_continuation_workspace)"
    steering_initialize "$ws"
    cp "$ws/project with spaces/.ralphie/state.env" "$ws/state.before"
    cp "$ws/project with spaces/.ralphie/gates" "$ws/gates.before"
    cp "$ws/project with spaces/.ralphie/project-bootstrap.md" "$ws/bootstrap.before"
    calls="$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')"
    cat > "$ws/request with spaces.md" <<'EOF_REQUEST'
Keep the café workflow and the user's exact Unicode: 雪.

Literal shell-looking text: $(touch request-must-not-run) `touch request-must-not-run`
Literal flags: --engine claude --prime-model another-model --accept true

EOF_REQUEST
    steering_control "$ws" --request-file "$ws/request with spaces.md" > "$ws/request.out" 2>&1
    grep -qi 'queued' "$ws/request.out"
    steering_assert_body_is_durable "$ws" "$ws/request with spaces.md"
    steering_control "$ws" --requests > "$ws/list.out" 2>&1
    grep -qi 'queued' "$ws/list.out"
    if grep -qi 'completed' "$ws/request.out" "$ws/list.out"; then return 1; fi
    cmp "$ws/state.before" "$ws/project with spaces/.ralphie/state.env"
    cmp "$ws/gates.before" "$ws/project with spaces/.ralphie/gates"
    cmp "$ws/bootstrap.before" "$ws/project with spaces/.ralphie/project-bootstrap.md"
    [ "$calls" -eq "$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')" ]
    [ ! -e "$ws/bin/control-engine.calls" ]
    [ ! -e "$ws/project with spaces/request-must-not-run" ]
}

test_request_control_rejects_missing_mission_and_mixed_modes() {
    local ws status option
    ws="$(new_continuation_workspace)"
    git -C "$ws/project with spaces" status --porcelain=v1 -z > "$ws/status.before"
    git -C "$ws/project with spaces" rev-parse HEAD > "$ws/head.before"
    for option in --requests --requests-json; do
        status=0
        steering_control "$ws" "$option" > "$ws/missing-list.out" 2>&1 || status=$?
        [ "$status" -ne 0 ]
    done
    status=0
    steering_control "$ws" --request 'No mission exists yet' > "$ws/missing.out" 2>&1 || status=$?
    [ "$status" -ne 0 ]
    [ ! -e "$ws/project with spaces/.ralphie/state.env" ]
    [ ! -e "$ws/project with spaces/.mock-prime/calls" ]
    [ -z "$(find "$ws/project with spaces/.ralphie" -mindepth 1 -print)" ]
    [ ! -e "$ws/project with spaces/logs" ] && [ ! -e "$ws/project with spaces/consensus" ]
    [ ! -e "$ws/project with spaces/IMPLEMENTATION_PLAN.md" ]
    git -C "$ws/project with spaces" status --porcelain=v1 -z > "$ws/status.after"
    git -C "$ws/project with spaces" rev-parse HEAD > "$ws/head.after"
    cmp "$ws/status.before" "$ws/status.after"
    cmp "$ws/head.before" "$ws/head.after"
    steering_initialize "$ws"
    steering_control "$ws" --requests-json > "$ws/empty.json"
    status=0
    steering_control "$ws" --request 'Must not publish' --requests > "$ws/mixed.out" 2>&1 || status=$?
    [ "$status" -ne 0 ]
    status=0
    steering_control "$ws" --requests --requests-json > "$ws/mixed-list.out" 2>&1 || status=$?
    [ "$status" -ne 0 ]
    status=0
    steering_control "$ws" --request 'One' --request 'Two' > "$ws/duplicate.out" 2>&1 || status=$?
    [ "$status" -ne 0 ]
    steering_control "$ws" --requests-json > "$ws/after.json"
    cmp "$ws/empty.json" "$ws/after.json"
    [ ! -e "$ws/bin/control-engine.calls" ]
}

test_request_json_preserves_literal_and_file_payloads() {
    command -v python3 >/dev/null 2>&1 || return 200
    local ws text
    ws="$(new_continuation_workspace)"
    steering_initialize "$ws"
    for text in -n --help --project; do
        steering_control "$ws" --request "$text" > "$ws/literal.out" 2>&1
    done
    printf 'Exact caf\303\251 and \351\233\252\twith CR\r\nand final lines\n\n' > "$ws/request exact bytes.md"
    ( cd "$ws"; steering_control "$ws" --request-file 'request exact bytes.md' ) > "$ws/file.out" 2>&1
    steering_control "$ws" --requests-json > "$ws/list.json"
    python3 - "$ws/list.json" "$ws/request exact bytes.md" <<'PY_REQUEST_JSON'
import json, pathlib, sys
document = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert document['schema'] == 1 and document['mission_id']
requests = document['requests']
assert len(requests) == 4 and len({request['id'] for request in requests}) == 4
expected = {'-n', '--help', '--project', pathlib.Path(sys.argv[2]).read_bytes().decode()}
assert {request['text'] for request in requests} == expected, requests
for request in requests:
    assert request['mission_id'] == document['mission_id']
    assert request['status'] == 'queued'
    assert request['worker_presented'] is False and request['review_presented'] is False
    assert request['bytes'] == len(request['text'].encode())
PY_REQUEST_JSON
    steering_assert_body_is_durable "$ws" "$ws/request exact bytes.md"
    printf '\377' > "$ws/malformed UTF-8"
    local status=0
    steering_control "$ws" --request-file "$ws/malformed UTF-8" > "$ws/invalid-utf8.out" 2>&1 || status=$?
    [ "$status" -ne 0 ]
    steering_control "$ws" --requests-json > "$ws/after-invalid.json"
    cmp "$ws/list.json" "$ws/after-invalid.json"
    [ ! -e "$ws/bin/control-engine.calls" ]
}

test_request_capacity_concurrent_publish_and_stopped_archive() {
    local ws pid_a pid_b status_a=0 status_b=0 slot status before_bodies after_bodies
    ws="$(new_continuation_workspace)"
    install_budget_receipt_wrapper "$ws"
    steering_initialize "$ws" --session-token-rate-cents-per-million 1000000
    steering_install_barrier_mock "$ws"
    steering_control "$ws" --request 'Concurrent request A' > "$ws/concurrent-a.out" 2>&1 &
    pid_a=$!
    steering_control "$ws" --request 'Concurrent request B' > "$ws/concurrent-b.out" 2>&1 &
    pid_b=$!
    wait "$pid_a" || status_a=$?
    wait "$pid_b" || status_b=$?
    # Busy is a bounded refusal, never a lost acknowledged request. Retry a
    # refused producer after the admitted transaction has finished.
    if [ "$status_a" -ne 0 ]; then steering_control "$ws" --request 'Concurrent request A' > "$ws/concurrent-a.out"; fi
    if [ "$status_b" -ne 0 ]; then steering_control "$ws" --request 'Concurrent request B' > "$ws/concurrent-b.out"; fi
    for slot in $(seq 3 32); do
        printf 'Capacity request %02d\n%04076d' "$slot" 0 > "$ws/capacity-body-$slot"
        [ "$(wc -c < "$ws/capacity-body-$slot" | tr -d ' ')" -eq 4096 ]
        steering_control "$ws" --request-file "$ws/capacity-body-$slot" > "$ws/capacity-$slot.out" 2>&1
    done
    before_bodies="$(find "$ws/project with spaces/.ralphie/requests/active" -name body -type f | wc -l | tr -d ' ')"
    [ "$before_bodies" -eq 32 ]
    status=0
    steering_control "$ws" --request 'This is request 33' > "$ws/over-capacity.out" 2>&1 || status=$?
    [ "$status" -ne 0 ]
    : > "$ws/empty request"
    status=0
    steering_control "$ws" --request-file "$ws/empty request" > "$ws/empty.out" 2>&1 || status=$?
    [ "$status" -ne 0 ]
    printf '%04097d' 0 > "$ws/oversized request"
    status=0
    steering_control "$ws" --request-file "$ws/oversized request" > "$ws/oversized.out" 2>&1 || status=$?
    [ "$status" -ne 0 ]
    printf 'before\000after' > "$ws/nul request"
    status=0
    steering_control "$ws" --request-file "$ws/nul request" > "$ws/nul.out" 2>&1 || status=$?
    [ "$status" -ne 0 ]
    after_bodies="$(find "$ws/project with spaces/.ralphie/requests/active" -name body -type f | wc -l | tr -d ' ')"
    [ "$after_bodies" -eq 32 ]
    steering_control "$ws" --requests-json > "$ws/full.json"
    [ "$(grep -o 'Concurrent request A' "$ws/full.json" | wc -l | tr -d ' ')" -eq 1 ]
    [ "$(grep -o 'Concurrent request B' "$ws/full.json" | wc -l | tr -d ' ')" -eq 1 ]
    local CONTINUATION_QUALITY_LEVEL=high CONTINUATION_SWARM_TIMEOUT=120
    # Hold the first four actual reviewer invocations until all four have read
    # their prompts. This proves concurrent inference at the supported ceiling.
    mkdir "$ws/bin/steering-control/parallel-reviewers"
    run_continuation_fixture "$ws" --objective "$STEERING_OBJECTIVE" --accept 'bash check.sh' \
        --plan-only --session-token-rate-cents-per-million 1000000 > "$ws/large-context.out" 2>&1
    [ -f "$ws/bin/steering-control/parallel-ready" ]
    assert_budget_matches_actual_inference_receipts "$ws" 10
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$ws" <<'PY_FULL_REQUEST_PROMPTS'
from pathlib import Path
import sys
root = Path(sys.argv[1])
bodies = [p.read_bytes() for p in (root / 'project with spaces/.ralphie/requests/active').glob('*/body')]
assert len(bodies) == 32
roles = (root / 'bin/steering-control/roles').read_text().splitlines()
assert len(roles) == 7 and sum(r.startswith('reviewer:') for r in roles) == 5, roles
for role in roles:
    prompt = Path(role.split(':', 2)[2]).read_bytes()
    assert all(body in prompt for body in bodies), role
PY_FULL_REQUEST_PROMPTS
    fi
    # A local presentation-receipt failure is a stop before dispatch, even with
    # retry allowances. The strict mock's actual calls cannot increase.
    mkdir "$ws/io-failure-bin"
    cp "$RALPHIE_TEST_GUARD_DIR/"* "$ws/io-failure-bin/"
    cat > "$ws/io-failure-bin/mktemp" <<'EOF_RECEIPT_IO_FAILURE'
#!/usr/bin/env bash
case "${1:-}" in */.presented.XXXXXX)
    printf 'receipt write refused\n' >> "$(dirname "$0")/fault-observed"
    exit 1
    ;;
esac
exec /usr/bin/mktemp "$@"
EOF_RECEIPT_IO_FAILURE
    chmod +x "$ws/io-failure-bin/mktemp"
    local original_guards="$RALPHIE_TEST_GUARD_DIR"
    RALPHIE_TEST_GUARD_DIR="$ws/io-failure-bin"
    status=0
    run_continuation_fixture "$ws" --objective "$STEERING_OBJECTIVE" --accept 'bash check.sh' \
        --run-agent-max-attempts 3 --max-phase-completion-attempts 5 --max-iterations 3 \
        --session-token-rate-cents-per-million 1000000 > "$ws/receipt-failure.out" 2>&1 || status=$?
    RALPHIE_TEST_GUARD_DIR="$original_guards"
    [ "$status" -ne 0 ] && [ -s "$ws/io-failure-bin/fault-observed" ]
    [ "$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')" -eq 10 ]
    steering_assert_handoff_waits_for_publication "$ws"
    steering_assert_publication_survives_worker_termination "$ws"
    steering_control "$ws" --archive-request all > "$ws/archive.out" 2>&1
    [ "$(find "$ws/project with spaces/.ralphie/requests/archive" -name body -type f | wc -l | tr -d ' ')" -eq 34 ]
    [ "$(find "$ws/project with spaces/.ralphie/requests/active" -name body -type f | wc -l | tr -d ' ')" -eq 0 ]
    steering_control "$ws" --request 'Capacity is available after explicit archive' > "$ws/after-archive.out" 2>&1
    [ "$(find "$ws/project with spaces/.ralphie/requests/active" -name body -type f | wc -l | tr -d ' ')" -eq 1 ]
    [ ! -e "$ws/bin/control-engine.calls" ]
}

steering_start_verified_producer() {
    local ws="$1" body="$2" output="$3" count=0
    # exec makes this PID the public producer recorded in both real claims.
    /bin/bash -c '
        source "$1"
        env() { exec /usr/bin/env "$@"; }
        steering_control "$2" --request-file "$3"
    ' capacity-producer "$SUITE_DIR/run-steering-contract-suite.sh" "$ws" "$body" > "$output" 2>&1 &
    STEERING_PRODUCER_PID=$!
    while ! { grep -Fxq "pid=$STEERING_PRODUCER_PID" "$ws/project with spaces/.ralphie/run.lock.claim/owner" 2>/dev/null \
        && grep -Fxq "pid=$STEERING_PRODUCER_PID" "$ws/project with spaces/.ralphie/requests.lock/owner" 2>/dev/null; }; do
        if [ "$count" -ge 100 ] || ! kill -0 "$STEERING_PRODUCER_PID" 2>/dev/null; then
            kill -TERM "$STEERING_PRODUCER_PID" 2>/dev/null || true
            wait "$STEERING_PRODUCER_PID" 2>/dev/null || true
            return 1
        fi
        sleep 0.1
        count=$((count + 1))
    done
}

steering_assert_handoff_waits_for_publication() {
    local ws="$1" first_record status=0 calls_before
    trap steering_stop_run EXIT
    first_record="$(find "$ws/project with spaces/.ralphie/requests/active" -mindepth 1 -maxdepth 1 -type d | sort | head -n 1)"
    steering_control "$ws" --archive-request "${first_record##*/}" > "$ws/handoff-archive-one.out"
    calls_before="$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')"
    printf 'Handoff completion must wait for this accepted request.\n\n' > "$ws/handoff request.md"
    printf 'handoff:plan' > "$ws/bin/steering-control/hold"
    cat > "$ws/handoff-owner.sh" <<'EOF_HANDOFF_OWNER'
#!/usr/bin/env bash
set -euo pipefail
export RALPHIE_LIB=1
source "$1"
PROJECT_DIR="$2"
CONFIG_DIR="$PROJECT_DIR/.ralphie"
STATE_FILE="$CONFIG_DIR/state.env"
LOCK_FILE="$CONFIG_DIR/run.lock"
REASON_LOG_FILE="$CONFIG_DIR/reasons.log"
REQUESTS_DIR="$CONFIG_DIR/requests"
REQUEST_CLAIM_DIR="$CONFIG_DIR/requests.lock"
RUNTIME_GUARD_DIR="$3/handoff-private"
mkdir "$RUNTIME_GUARD_DIR"
load_state
acquire_lock
install_cleanup_traps
RALPHIE_CLEANUP_STATE_ENABLED=true
REQUESTS_ENABLED=true
REQUEST_ROLE=handoff
request_take_snapshot
ACTIVE_ENGINE=prime-agent
ACTIVE_CMD="$3/bin/prime-agent"
PRIME_CMD="$ACTIVE_CMD"
PRIME_HEALTHY=true
PRIME_CAP_PRINT=1
ENGINE_CAPABILITIES_PROBED=true
PRIME_PROVIDER=fixture-provider
PRIME_MODEL=fixture-model
PRIME_THINKING_OVERRIDE=max
RUN_AGENT_MAX_ATTEMPTS=1
RUN_AGENT_RETRY_DELAY_SECONDS=0
ENGINE_OUTPUT_TO_STDOUT=false
COMMAND_TIMEOUT_SECONDS=120
printf '# Handoff Validation Prompt\nPhase: plan\n' > "$3/capacity-handoff-prompt.md"
result=0
run_agent_with_prompt "$3/capacity-handoff-prompt.md" "$3/capacity-handoff.log" "$3/capacity-handoff.answer" false handoff || result=$?
printf 'status=%s\npermanent=%s\nrefresh=%s\n' "$result" "$ENGINE_PERMANENT_FAILURE" "$REQUEST_REFRESH_REQUIRED" > "$3/handoff-result"
EOF_HANDOFF_OWNER
    /bin/bash "$ws/handoff-owner.sh" "$ws/ralphie.sh" "$ws/project with spaces" "$ws" > "$ws/handoff-owner.out" 2>&1 &
    STEERING_RUN_PID=$!
    steering_wait_file "$ws/bin/steering-control/ready" 120
    steering_start_verified_producer "$ws" "$ws/handoff request.md" "$ws/handoff-publish.out"
    : > "$ws/bin/steering-control/release"
    steering_wait_run
    wait "$STEERING_PRODUCER_PID" || status=$?
    [ "$STEERING_RUN_STATUS" -eq 0 ] && [ "$status" -eq 0 ]
    grep -qx 'status=76' "$ws/handoff-result"
    grep -qx 'refresh=true' "$ws/handoff-result"
    grep -qx 'permanent=false' "$ws/handoff-result"
    grep -q 'Queued request' "$ws/handoff-publish.out"
    [ "$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')" -eq $((calls_before + 1)) ]
    steering_assert_body_is_durable "$ws" "$ws/handoff request.md"
    [ ! -e "$ws/project with spaces/.ralphie/run.lock.d" ]
    [ ! -e "$ws/project with spaces/.ralphie/run.lock.claim" ]
    [ ! -e "$ws/project with spaces/.ralphie/requests.lock" ]
    trap - EXIT
}

steering_assert_publication_survives_worker_termination() {
    local ws="$1" first_record status=0 calls_before
    local session_before seed_before attempts_before
    trap steering_stop_run EXIT
    first_record="$(find "$ws/project with spaces/.ralphie/requests/active" -mindepth 1 -maxdepth 1 -type d | sort | head -n 1)"
    steering_control "$ws" --archive-request "${first_record##*/}" > "$ws/archive-one.out"
    session_before="$(sed -n '/^SESSION_ID=/p' "$ws/project with spaces/.ralphie/state.env")"
    seed_before="$(sed -n '/^MISSION_SEED_SHA=/p' "$ws/project with spaces/.ralphie/state.env")"
    attempts_before="$(sed -n '/^SESSION_ATTEMPT_COUNT=/p' "$ws/project with spaces/.ralphie/state.env")"
    calls_before="$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')"
    printf 'Accepted during TERM: exact caf\303\251 \351\233\252 and trailing lines\n\n' > "$ws/term request.md"
    cat > "$ws/term-owner.sh" <<'EOF_TERM_OWNER'
#!/usr/bin/env bash
set -euo pipefail
export RALPHIE_LIB=1
source "$1"
PROJECT_DIR="$2"
CONFIG_DIR="$PROJECT_DIR/.ralphie"
STATE_FILE="$CONFIG_DIR/state.env"
LOCK_FILE="$CONFIG_DIR/run.lock"
REASON_LOG_FILE="$CONFIG_DIR/reasons.log"
REQUESTS_DIR="$CONFIG_DIR/requests"
REQUEST_CLAIM_DIR="$CONFIG_DIR/requests.lock"
RUNTIME_GUARD_DIR=''
load_state
acquire_lock
install_cleanup_traps
RALPHIE_CLEANUP_STATE_ENABLED=true
sleep 90 &
register_managed_pid "$!"
printf 'ready\n' > "$3"
wait
EOF_TERM_OWNER
    /bin/bash "$ws/term-owner.sh" "$ws/ralphie.sh" "$ws/project with spaces" "$ws/term.ready" > "$ws/term-owner.out" 2>&1 &
    STEERING_RUN_PID=$!
    steering_wait_file "$ws/term.ready"
    steering_start_verified_producer "$ws" "$ws/term request.md" "$ws/term-publish.out"
    kill -TERM "$STEERING_RUN_PID"
    steering_wait_run
    wait "$STEERING_PRODUCER_PID" || status=$?
    [ "$STEERING_RUN_STATUS" -eq 143 ] && [ "$status" -eq 0 ]
    grep -q 'Queued request' "$ws/term-publish.out"
    steering_assert_body_is_durable "$ws" "$ws/term request.md"
    [ ! -e "$ws/project with spaces/.ralphie/run.lock.d" ]
    [ ! -e "$ws/project with spaces/.ralphie/run.lock.claim" ]
    [ ! -e "$ws/project with spaces/.ralphie/requests.lock" ]
    # Ordinary resume must recognize the unreviewed generation before another
    # inference. Its existing iteration ceiling leaves the request recoverable.
    status=0
    run_continuation_fixture "$ws" --objective "$STEERING_OBJECTIVE" --accept 'bash check.sh' \
        --max-iterations 3 --session-token-rate-cents-per-million 1000000 > "$ws/term-resume.out" 2>&1 || status=$?
    [ "$status" -ne 0 ]
    grep -q '^CURRENT_PHASE="plan"' "$ws/project with spaces/.ralphie/state.env"
    grep -Fqx "$session_before" "$ws/project with spaces/.ralphie/state.env"
    grep -Fqx "$seed_before" "$ws/project with spaces/.ralphie/state.env"
    grep -Fqx "$attempts_before" "$ws/project with spaces/.ralphie/state.env"
    grep -q RB_HUMAN_REQUEST_REFRESH "$ws/project with spaces/.ralphie/reasons.log"
    [ "$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')" -eq "$calls_before" ]
    steering_assert_body_is_durable "$ws" "$ws/term request.md"
    trap - EXIT
}

test_request_aliases_fail_closed() {
    local ws requests body status
    ws="$(new_continuation_workspace)"
    steering_initialize "$ws"
    steering_control "$ws" --request 'Protect this durable body' > "$ws/request.out"
    requests="$ws/project with spaces/.ralphie/requests"
    mkdir "$ws/outside"
    printf 'outside sentinel\n' > "$ws/outside/sentinel"
    cp "$ws/outside/sentinel" "$ws/outside.before"
    mv "$requests" "$ws/requests.saved"
    ln -s "$ws/outside" "$requests"
    status=0
    steering_control "$ws" --requests-json > "$ws/alias.out" 2>&1 || status=$?
    [ "$status" -ne 0 ]
    cmp "$ws/outside.before" "$ws/outside/sentinel"
    [ "$(find "$ws/outside" -mindepth 1 -print | wc -l | tr -d ' ')" -eq 1 ]
    rm "$requests"
    mv "$ws/requests.saved" "$requests"
    body="$(find "$requests/active" -type f -name body | head -n 1)"
    mv "$body" "$ws/body.saved"
    ln -s "$ws/outside/sentinel" "$body"
    status=0
    steering_control "$ws" --requests-json > "$ws/body-alias.out" 2>&1 || status=$?
    [ "$status" -ne 0 ]
    cmp "$ws/outside.before" "$ws/outside/sentinel"
    rm "$body"
    mkdir "$body"
    status=0
    steering_control "$ws" --requests-json > "$ws/body-directory.out" 2>&1 || status=$?
    [ "$status" -ne 0 ]
    rmdir "$body"
    mv "$ws/body.saved" "$body"
    ln -s "$ws/outside" "$ws/project with spaces/.ralphie/requests.lock"
    status=0
    steering_control "$ws" --requests > "$ws/claim-alias.out" 2>&1 || status=$?
    [ "$status" -ne 0 ]
    rm "$ws/project with spaces/.ralphie/requests.lock"
    cmp "$ws/outside.before" "$ws/outside/sentinel"
    [ ! -e "$ws/bin/control-engine.calls" ]
}

test_request_abandoned_claim_and_list_read_failure_are_loud() {
    local ws started elapsed status=0
    ws="$(new_continuation_workspace)"
    steering_initialize "$ws"
    steering_control "$ws" --request 'A real durable body whose failed read cannot become empty JSON' > "$ws/request.out"
    mkdir "$ws/project with spaces/.ralphie/requests.lock"
    printf 'pid=99999999\ntoken=abandoned-fixture\n' > "$ws/project with spaces/.ralphie/requests.lock/owner"
    cp "$ws/project with spaces/.ralphie/requests.lock/owner" "$ws/owner.before"
    started="$(date +%s)"
    steering_control "$ws" --requests-json > "$ws/abandoned.out" 2>&1 || status=$?
    elapsed=$(( $(date +%s) - started ))
    [ "$status" -ne 0 ] && [ "$elapsed" -le 8 ]
    grep -qi 'busy or abandoned' "$ws/abandoned.out"
    cmp "$ws/owner.before" "$ws/project with spaces/.ralphie/requests.lock/owner"
    rm "$ws/project with spaces/.ralphie/requests.lock/owner"
    rmdir "$ws/project with spaces/.ralphie/requests.lock"
    (
        export RALPHIE_LIB=1
        # shellcheck source=/dev/null
        source "$ws/ralphie.sh"
        PROJECT_DIR="$ws/project with spaces"
        CONFIG_DIR="$PROJECT_DIR/.ralphie"
        STATE_FILE="$CONFIG_DIR/state.env"
        REQUESTS_DIR="$CONFIG_DIR/requests"
        REQUEST_CLAIM_DIR="$CONFIG_DIR/requests.lock"
        load_state
        request_lock
        request_validate_mission
        cat() {
            case "${1:-}" in */body) return 1;; esac
            command cat "$@"
        }
        local read_status=0
        request_render_list json > "$ws/read-failure.json" || read_status=$?
        request_unlock
        [ "$read_status" -ne 0 ]
    )
    [ ! -e "$ws/bin/control-engine.calls" ]
}

test_request_publication_serializes_with_interrupted_done_checkpoint() {
    local ws status=0
    trap steering_stop_run EXIT
    ws="$(new_continuation_workspace)"
    steering_initialize "$ws"
    cat > "$ws/cleanup-owner.sh" <<'EOF_CLEANUP_OWNER'
#!/usr/bin/env bash
set -euo pipefail
export RALPHIE_LIB=1
source "$1"
PROJECT_DIR="$2"
CONFIG_DIR="$PROJECT_DIR/.ralphie"
STATE_FILE="$CONFIG_DIR/state.env"
LOCK_FILE="$CONFIG_DIR/run.lock"
REASON_LOG_FILE="$CONFIG_DIR/reasons.log"
REQUESTS_DIR="$CONFIG_DIR/requests"
REQUEST_CLAIM_DIR="$CONFIG_DIR/requests.lock"
RUNTIME_GUARD_DIR=''
load_state
acquire_lock
request_lock
# Interruption between assigning terminal state and its checked publication.
CURRENT_PHASE=done
CURRENT_PHASE_INDEX=6
PHASE_ATTEMPT_IN_PROGRESS=false
RALPHIE_CLEANUP_STATE_ENABLED=true
# Preserve the marker outside the project and its guarded manifests.
marker="$3"
cleanup_managed_processes() { printf 'checkpoint window\n' > "$marker"; sleep 2; }
cleanup_resources
EOF_CLEANUP_OWNER
    /bin/bash "$ws/cleanup-owner.sh" "$ws/ralphie.sh" "$ws/project with spaces" "$ws/cleanup.ready" > "$ws/cleanup-owner.out" 2>&1 &
    STEERING_RUN_PID=$!
    steering_wait_file "$ws/cleanup.ready"
    steering_control "$ws" --request 'An unseen request must not be acknowledged while cleanup publishes done' > "$ws/publish-race.out" 2>&1 || status=$?
    steering_wait_run
    [ "$STEERING_RUN_STATUS" -eq 0 ]
    [ "$status" -ne 0 ]
    grep -q '^CURRENT_PHASE="done"' "$ws/project with spaces/.ralphie/state.env"
    [ "$(find "$ws/project with spaces/.ralphie/requests/active" -name body -type f | wc -l | tr -d ' ')" -eq 0 ]
    [ ! -e "$ws/project with spaces/.ralphie/requests.lock" ]
    [ ! -e "$ws/project with spaces/.ralphie/run.lock.d" ]
    [ ! -e "$ws/bin/control-engine.calls" ]
    trap - EXIT
}

test_request_fresh_start_refuses_before_rewriting_intent() {
    local ws path status calls
    ws="$(new_continuation_workspace)"
    steering_initialize "$ws"
    steering_control "$ws" --request 'Do not silently discard or inherit this old mission request' > "$ws/request.out"
    mkdir "$ws/protected-before"
    for path in state.env OBJECTIVE.md project-goals.md project-bootstrap.md gates; do
        cp "$ws/project with spaces/.ralphie/$path" "$ws/protected-before/$path"
    done
    calls="$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')"
    status=0
    run_continuation_fixture "$ws" --objective 'A different mission must not overwrite active prior steering' \
        --accept 'bash check.sh' --no-resume --plan-only > "$ws/fresh.out" 2>&1 || status=$?
    [ "$status" -ne 0 ]
    for path in state.env OBJECTIVE.md project-goals.md project-bootstrap.md gates; do
        cmp "$ws/protected-before/$path" "$ws/project with spaces/.ralphie/$path"
    done
    [ "$calls" -eq "$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')" ]
    steering_control "$ws" --archive-request all > "$ws/archive.out"
    run_continuation_fixture "$ws" --objective 'A different mission after deliberate archive' \
        --accept 'bash check.sh' --no-resume --plan-only > "$ws/fresh-after-archive.out" 2>&1
    grep -q '^CURRENT_PHASE="build"' "$ws/project with spaces/.ralphie/state.env"
    [ "$(find "$ws/project with spaces/.ralphie/requests/archive" -name body -type f | wc -l | tr -d ' ')" -eq 1 ]
}

steering_install_barrier_mock() {
    local ws="$1"
    mv "$ws/bin/prime-agent" "$ws/bin/prime-agent-steering-fixture"
    mkdir -p "$ws/bin/steering-control/prompts"
    cat > "$ws/bin/prime-agent" <<'EOF_STEERING_MOCK'
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in --help|--version) exec "$here/prime-agent-steering-fixture" "$@" ;; esac
control="$here/steering-control"
prompt="$control/prompts/$$.md"
cat > "$prompt"
role=worker
phase=''
if grep -q '^# Handoff Validation Prompt' "$prompt"; then
    role=handoff
    phase="$(sed -n 's/^Phase: //p' "$prompt" | head -n 1)"
elif grep -q '^# Consensus Review:' "$prompt"; then
    role=reviewer
    phase="$(sed -n 's/^# Consensus Review: //p' "$prompt" | head -n 1)"
    phase="${phase%-gate}"
else
    for candidate in Plan Build Test Refactor Lint Document; do
        if grep -q "^# Ralphie $candidate Phase Prompt" "$prompt"; then
            phase="$(printf '%s' "$candidate" | tr '[:upper:]' '[:lower:]')"
            break
        fi
    done
fi
[ -n "$phase" ] || exit 81
printf '%s:%s:%s\n' "$role" "$phase" "$prompt" >> "$control/roles"
if [ "$role" = reviewer ] && [ -d "$control/parallel-reviewers" ]; then
    mkdir "$control/parallel-reviewers/$$"
    count=0
    while [ ! -f "$control/parallel-ready" ]; do
        if [ "$(find "$control/parallel-reviewers" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" -ge 4 ]; then
            printf 'four reviewer calls are concurrently admitted\n' > "$control/parallel-ready"
            break
        fi
        [ "$count" -lt 90 ] || exit 83
        sleep 1
        count=$((count + 1))
    done
fi
if [ -f "$control/hold" ] && [ "$(cat "$control/hold")" = "$role:$phase" ] && \
    mkdir "$control/held" 2>/dev/null; then
    printf '%s\n' "$prompt" > "$control/ready"
    count=0
    while [ ! -f "$control/release" ]; do
        [ "$count" -lt 60 ] || exit 82
        sleep 1
        count=$((count + 1))
    done
fi
if [ -f "$control/force-exit-76" ] && [ "$(cat "$control/force-exit-76")" = "$role:$phase" ]; then
    "$here/prime-agent-steering-fixture" "$@" < "$prompt"
    exit 76
fi
exec "$here/prime-agent-steering-fixture" "$@" < "$prompt"
EOF_STEERING_MOCK
    chmod +x "$ws/bin/prime-agent"
}

steering_start_run() {
    local ws="$1"
    shift
    # Replace the fixture driver's shell at its final env invocation. The PID
    # below is the actual Ralphie process, so failure cleanup stays scoped.
    /bin/bash -c '
        source "$1"
        env() { exec /usr/bin/env "$@"; }
        run_continuation_fixture "$2" "${@:3}"
    ' steering-driver "$SUITE_DIR/run-continuation-suite.sh" "$ws" \
        --objective "$STEERING_OBJECTIVE" --accept 'bash check.sh' "$@" \
        > "$ws/run.out" 2>&1 &
    STEERING_RUN_PID=$!
}

steering_stop_run() {
    local count=0
    [ -n "$STEERING_RUN_PID" ] || return 0
    if kill -0 "$STEERING_RUN_PID" 2>/dev/null; then
        kill -TERM "$STEERING_RUN_PID" 2>/dev/null || true
        while kill -0 "$STEERING_RUN_PID" 2>/dev/null && [ "$count" -lt 10 ]; do
            sleep 1
            count=$((count + 1))
        done
        kill -KILL "$STEERING_RUN_PID" 2>/dev/null || true
    fi
    wait "$STEERING_RUN_PID" 2>/dev/null || true
    STEERING_RUN_PID=''
}

steering_wait_file() {
    local file="$1" limit="${2:-45}" count=0
    while [ ! -s "$file" ]; do
        if [ -n "$STEERING_RUN_PID" ] && ! kill -0 "$STEERING_RUN_PID" 2>/dev/null; then
            return 1
        fi
        [ "$count" -lt "$limit" ] || return 1
        sleep 1
        count=$((count + 1))
    done
}

steering_wait_run() {
    local count=0
    while kill -0 "$STEERING_RUN_PID" 2>/dev/null; do
        [ "$count" -lt 90 ] || return 1
        sleep 1
        count=$((count + 1))
    done
    STEERING_RUN_STATUS=0
    wait "$STEERING_RUN_PID" || STEERING_RUN_STATUS=$?
    STEERING_RUN_PID=''
}

steering_assert_plan_received_request() {
    local ws="$1" request_line="$2" role prompt
    for role in worker handoff reviewer; do
        prompt="$(sed -n "s/^$role:plan://p" "$ws/bin/steering-control/roles" | tail -n 1)"
        [ -f "$prompt" ]
        grep -Fq -- "$request_line" "$prompt"
    done
    [ "$(grep -c '^plan$' "$ws/project with spaces/.mock-prime/phases")" -eq 2 ]
    steering_control "$ws" --requests > "$ws/presented.out"
    grep -qi 'presented' "$ws/presented.out"
    if grep -qi 'completed' "$ws/presented.out"; then return 1; fi
    [ ! -e "$ws/bin/control-engine.calls" ]
}

test_requests_invalidate_inflight_worker_handoff_and_reviewer() {
    local ws role request_line status prompt
    trap steering_stop_run EXIT
    for role in worker handoff reviewer; do
        ws="$(new_continuation_workspace)"
        steering_initialize "$ws"
        steering_install_barrier_mock "$ws"
        printf '%s:build' "$role" > "$ws/bin/steering-control/hold"
        steering_start_run "$ws" --max-iterations 3
        steering_wait_file "$ws/bin/steering-control/ready"
        # The explicit same-seed resume grants BUILD consent before this
        # boundary. Steering itself must preserve that admitted context.
        cp "$ws/project with spaces/.ralphie/project-bootstrap.md" "$ws/bootstrap.before"
        cp "$ws/project with spaces/.ralphie/gates" "$ws/gates.before"
        prompt="$(cat "$ws/bin/steering-control/ready")"
        request_line="Boundary request for $role: keep café exact and never run shell prose."
        if grep -Fq -- "$request_line" "$prompt"; then return 1; fi
        steering_control "$ws" --request "$request_line" > "$ws/request.out" 2>&1
        grep -qi 'queued' "$ws/request.out"
        steering_control "$ws" --requests > "$ws/queued.out"
        grep -qi 'queued' "$ws/queued.out"
        status=0
        steering_control "$ws" --archive-request all > "$ws/archive-running.out" 2>&1 || status=$?
        [ "$status" -ne 0 ]
        : > "$ws/bin/steering-control/release"
        steering_wait_run
        assert_incomplete_fixture "$ws" "$STEERING_RUN_STATUS"
        steering_assert_plan_received_request "$ws" "$request_line"
        cmp "$ws/bootstrap.before" "$ws/project with spaces/.ralphie/project-bootstrap.md"
        cmp "$ws/gates.before" "$ws/project with spaces/.ralphie/gates"
    done
    trap - EXIT
}

test_request_during_final_gate_cannot_finish_unseen() {
    local ws request_line before_lines after_lines calls status
    trap steering_stop_run EXIT
    ws="$(new_continuation_workspace)"
    cat > "$ws/project with spaces/check.sh" <<'EOF_FINAL_GATE'
#!/usr/bin/env bash
set -euo pipefail
printf 'checked\n' >> check-receipts.log
control='../bin/steering-control'
if [ -f .ralphie/state.env ] && grep -q '^CURRENT_PHASE="document"' .ralphie/state.env && \
    [ -f "$control/hold-check" ] && mkdir "$control/check-held" 2>/dev/null; then
    printf 'document check in flight\n' > "$control/check-ready"
    count=0
    while [ ! -f "$control/check-release" ]; do
        [ "$count" -lt 60 ] || exit 82
        sleep 1
        count=$((count + 1))
    done
fi
EOF_FINAL_GATE
    git -C "$ws/project with spaces" add -- check.sh
    git -C "$ws/project with spaces" -c user.name='Offline Fixture' -c user.email=fixture@example.test commit -qm 'hold the final shell check'
    steering_initialize "$ws"
    steering_install_barrier_mock "$ws"
    : > "$ws/bin/steering-control/hold-check"
    steering_start_run "$ws" --max-iterations 8 --max-consensus-routing-attempts 0
    steering_wait_file "$ws/bin/steering-control/check-ready" 180
    cp "$ws/project with spaces/.ralphie/verification.jsonl" "$ws/verification.before"
    before_lines="$(wc -l < "$ws/verification.before" | tr -d ' ')"
    [ "$before_lines" -gt 0 ]
    request_line='Final gate request: the snow workflow 雪 must be considered before done.'
    steering_control "$ws" --request "$request_line" > "$ws/request.out" 2>&1
    : > "$ws/bin/steering-control/check-release"
    steering_wait_run
    assert_incomplete_fixture "$ws" "$STEERING_RUN_STATUS"
    steering_assert_plan_received_request "$ws" "$request_line"
    after_lines="$(wc -l < "$ws/project with spaces/.ralphie/verification.jsonl" | tr -d ' ')"
    [ "$after_lines" -gt "$before_lines" ]
    head -n "$before_lines" "$ws/project with spaces/.ralphie/verification.jsonl" > "$ws/verification.prefix"
    cmp "$ws/verification.before" "$ws/verification.prefix"
    # Once the durable request has reached a worker and all ordinary guards
    # pass, the same mission may complete. A completed mission refuses another
    # request instead of acknowledging work no future worker will see.
    run_continuation_fixture "$ws" --objective "$STEERING_OBJECTIVE" --accept 'bash check.sh' \
        --max-iterations 0 --max-consensus-routing-attempts 0 > "$ws/resume.out" 2>&1
    grep -q '^CURRENT_PHASE="done"' "$ws/project with spaces/.ralphie/state.env"
    calls="$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')"
    steering_control "$ws" --requests-json > "$ws/done-before.json"
    status=0
    steering_control "$ws" --request 'Too late for this completed mission' > "$ws/after-done.out" 2>&1 || status=$?
    [ "$status" -ne 0 ]
    steering_control "$ws" --requests-json > "$ws/done-after.json"
    cmp "$ws/done-before.json" "$ws/done-after.json"
    [ "$calls" -eq "$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')" ]
    [ ! -e "$ws/bin/control-engine.calls" ]
    # A genuinely completed pre-feature checkpoint with no request metadata
    # must still verify locally at its exact spent budget, without inference.
    steering_control "$ws" --archive-request all > "$ws/archive-done.out"
    steering_make_legacy_checkpoint "$ws"
    run_continuation_fixture "$ws" --objective "$STEERING_OBJECTIVE" --accept 'bash check.sh' \
        --max-session-cycles "$calls" > "$ws/legacy-done-resume.out" 2>&1
    grep -q '^CURRENT_PHASE="done"' "$ws/project with spaces/.ralphie/state.env"
    grep -q "^SESSION_ATTEMPT_COUNT=\"$calls\"" "$ws/project with spaces/.ralphie/state.env"
    [ "$calls" -eq "$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')" ]
    trap - EXIT
}

test_genuine_exit_76_is_not_a_steering_event() {
    local ws role status
    for role in worker handoff reviewer; do
        ws="$(new_continuation_workspace)"
        steering_initialize "$ws"
        steering_install_barrier_mock "$ws"
        printf '%s:build' "$role" > "$ws/bin/steering-control/force-exit-76"
        status=0
        run_continuation_fixture "$ws" --objective "$STEERING_OBJECTIVE" --accept 'bash check.sh' \
            --max-iterations 3 > "$ws/run.out" 2>&1 || status=$?
        assert_incomplete_fixture "$ws" "$status"
        # Ordinary exhausted phases may backtrack to PLAN. They must retain
        # their failure reason instead of claiming an operator request arrived.
        if grep -q 'RB_HUMAN_REQUEST_REFRESH' "$ws/project with spaces/.ralphie/reasons.log"; then return 1; fi
        grep -q 'last_exit=76' "$ws/project with spaces/.ralphie/reasons.log"
        grep -q '^CURRENT_PHASE="build"' "$ws/project with spaces/.ralphie/state.env"
    done
    ws="$(new_continuation_workspace)"
    steering_initialize "$ws"
    printf '#!/usr/bin/env bash\nexit 76\n' > "$ws/project with spaces/check.sh"
    status=0
    run_continuation_fixture "$ws" --objective "$STEERING_OBJECTIVE" --accept 'bash check.sh' \
        --max-iterations 3 > "$ws/run.out" 2>&1 || status=$?
    assert_incomplete_fixture "$ws" "$status"
    if grep -q 'RB_HUMAN_REQUEST_REFRESH' "$ws/project with spaces/.ralphie/reasons.log"; then return 1; fi
    grep -q '^CURRENT_PHASE="build"' "$ws/project with spaces/.ralphie/state.env"
    grep -Eq '"exit"[[:space:]]*:[[:space:]]*76' "$ws/project with spaces/.ralphie/verification.jsonl"
}

test_pending_request_survives_interruption_and_resume() {
    local ws calls request_line='Persist this request through interruption: café and 雪.'
    trap steering_stop_run EXIT
    ws="$(new_continuation_workspace)"
    steering_initialize "$ws"
    steering_install_barrier_mock "$ws"
    printf 'worker:build' > "$ws/bin/steering-control/hold"
    steering_start_run "$ws" --max-iterations 3
    steering_wait_file "$ws/bin/steering-control/ready"
    steering_control "$ws" --request "$request_line" > "$ws/request.out"
    steering_stop_run
    [ ! -e "$ws/project with spaces/.ralphie/run.lock.d" ]
    steering_control "$ws" --requests-json > "$ws/interrupted.json"
    grep -q '"status":"queued"' "$ws/interrupted.json"
    grep -q '"worker_presented":false' "$ws/interrupted.json"
    calls="$(sed -n 's/^SESSION_ATTEMPT_COUNT="\([0-9]*\)"$/\1/p' "$ws/project with spaces/.ralphie/state.env")"
    [ "$calls" -ge 4 ]
    # Same mission, no changed seed and no fresh-start flag: the pending
    # instructions must reach a worker rather than disappear during recovery.
    run_continuation_fixture "$ws" --objective "$STEERING_OBJECTIVE" --accept 'bash check.sh' \
        --plan-only > "$ws/resume.out" 2>&1
    steering_assert_plan_received_request "$ws" "$request_line"
    grep -q '^CURRENT_PHASE="build"' "$ws/project with spaces/.ralphie/state.env"
    [ "$(sed -n 's/^SESSION_ATTEMPT_COUNT="\([0-9]*\)"$/\1/p' "$ws/project with spaces/.ralphie/state.env")" -gt "$calls" ]
    trap - EXIT
}

test_legacy_checkpoint_without_requests_resumes_same_phase_and_budget() {
    local ws state status=0
    ws="$(new_continuation_workspace)"
    steering_initialize "$ws"
    state="$ws/project with spaces/.ralphie/state.env"
    # f561 checkpoints predate the queue directory and this optional state key.
    # Retain every other serialized byte and recompute its ordinary checksum.
    steering_make_legacy_checkpoint "$ws"
    MOCK_PRIME_WORKER_FAIL_ONCE=true
    run_continuation_fixture "$ws" --objective "$STEERING_OBJECTIVE" --accept 'bash check.sh' \
        --max-session-cycles 4 --max-iterations 2 > "$ws/run.out" 2>&1 || status=$?
    assert_incomplete_fixture "$ws" "$status"
    grep -q '^CURRENT_PHASE="build"' "$state"
    grep -q '^SESSION_ATTEMPT_COUNT="4"' "$state"
    [ "$(grep -c '^plan$' "$ws/project with spaces/.mock-prime/phases")" -eq 1 ]
    [ "$(grep -c '^build$' "$ws/project with spaces/.mock-prime/phases")" -eq 1 ]
    [ "$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')" -eq 4 ]
}

test_saved_done_with_unseen_request_must_reopen_plan() {
    local ws status=0 request_line='Recover this acknowledged but unseen instruction before treating saved done as complete.'
    ws="$(new_continuation_workspace)"
    steering_initialize "$ws"
    steering_install_barrier_mock "$ws"
    steering_control "$ws" --request "$request_line" > "$ws/request.out"
    # This is the valid historical shape produced by the reproduced old-worker
    # and cleanup races: disk says done while a queued request has no receipts.
    (
        export RALPHIE_LIB=1
        # shellcheck source=/dev/null
        source "$ws/ralphie.sh"
        PROJECT_DIR="$ws/project with spaces"
        CONFIG_DIR="$PROJECT_DIR/.ralphie"
        STATE_FILE="$CONFIG_DIR/state.env"
        load_state
        CURRENT_PHASE=done
        CURRENT_PHASE_INDEX=6
        CURRENT_PHASE_ATTEMPT=1
        PHASE_ATTEMPT_IN_PROGRESS=false
        save_state
    )
    run_continuation_fixture "$ws" --objective "$STEERING_OBJECTIVE" --accept 'bash check.sh' \
        --max-iterations 2 --max-session-cycles 6 > "$ws/recover-done.out" 2>&1 || status=$?
    [ "$status" -ne 0 ]
    steering_assert_plan_received_request "$ws" "$request_line"
    grep -q '^CURRENT_PHASE="build"' "$ws/project with spaces/.ralphie/state.env"
    grep -q '^SESSION_ATTEMPT_COUNT="6"' "$ws/project with spaces/.ralphie/state.env"
}

test_live_worker_without_request_consumer_refuses_publication() {
    local ws owner status=0
    trap steering_stop_run EXIT
    ws="$(new_continuation_workspace)"
    steering_initialize "$ws"
    steering_install_barrier_mock "$ws"
    printf 'worker:build' > "$ws/bin/steering-control/hold"
    steering_start_run "$ws" --max-iterations 2
    steering_wait_file "$ws/bin/steering-control/ready"
    owner="$ws/project with spaces/.ralphie/run.lock.d/owner"
    cp "$owner" "$ws/owner.current"
    # Legacy owner receipts have the same real live PID/token, without the
    # capability witness. A new CLI cannot promise this worker will consume.
    sed '/^request_consumer=/d' "$owner" > "$ws/owner.legacy"
    cp "$ws/owner.legacy" "$owner"
    cp "$ws/project with spaces/.ralphie/state.env" "$ws/state.before"
    steering_control "$ws" --request 'A legacy worker must not acknowledge unseen steering' > "$ws/legacy-publish.out" 2>&1 || status=$?
    [ "$status" -ne 0 ]
    grep -qi 'live worker does not support durable requests' "$ws/legacy-publish.out"
    cmp "$ws/state.before" "$ws/project with spaces/.ralphie/state.env"
    steering_control "$ws" --requests-json > "$ws/legacy-list.json"
    grep -q '"requests":\[\]' "$ws/legacy-list.json"
    [ ! -e "$ws/bin/control-engine.calls" ]
    cp "$ws/owner.current" "$owner"
    steering_control "$ws" --request 'The same verified new worker can consume this request' > "$ws/current-publish.out"
    grep -qi queued "$ws/current-publish.out"
    steering_stop_run
    trap - EXIT
}

steering_case() {
    local name="$1"
    if [ -n "${STEERING_FILTER:-}" ] && [[ "$name" != *"$STEERING_FILTER"* ]]; then return 0; fi
    run_case "$name" "$2"
}

main() {
    STEERING_FILTER="${1:-}"
    prepare_isolated_target
    trap 'steering_stop_run; cleanup_isolated_target; cleanup_offline_test_guards' EXIT
    capture_repo_tracked_status_baseline
    steering_case request_controls_are_sideband_and_exact test_request_controls_are_sideband_and_exact
    steering_case request_control_rejects_missing_mission_and_mixed_modes test_request_control_rejects_missing_mission_and_mixed_modes
    steering_case request_json_preserves_literal_and_file_payloads test_request_json_preserves_literal_and_file_payloads
    steering_case request_capacity_concurrent_publish_and_stopped_archive test_request_capacity_concurrent_publish_and_stopped_archive
    steering_case request_aliases_fail_closed test_request_aliases_fail_closed
    steering_case request_abandoned_claim_and_list_read_failure_are_loud test_request_abandoned_claim_and_list_read_failure_are_loud
    steering_case request_publication_serializes_with_interrupted_done_checkpoint test_request_publication_serializes_with_interrupted_done_checkpoint
    steering_case request_fresh_start_refuses_before_rewriting_intent test_request_fresh_start_refuses_before_rewriting_intent
    steering_case requests_invalidate_inflight_worker_handoff_and_reviewer test_requests_invalidate_inflight_worker_handoff_and_reviewer
    steering_case request_during_final_gate_cannot_finish_unseen test_request_during_final_gate_cannot_finish_unseen
    steering_case genuine_exit_76_is_not_a_steering_event test_genuine_exit_76_is_not_a_steering_event
    steering_case pending_request_survives_interruption_and_resume test_pending_request_survives_interruption_and_resume
    steering_case legacy_checkpoint_without_requests_resumes_same_phase_and_budget test_legacy_checkpoint_without_requests_resumes_same_phase_and_budget
    steering_case live_worker_without_request_consumer_refuses_publication test_live_worker_without_request_consumer_refuses_publication
    steering_case saved_done_with_unseen_request_must_reopen_plan test_saved_done_with_unseen_request_must_reopen_plan
    info "Steering total: $TOTAL_COUNT | Passed: $PASS_COUNT | Failed: $FAIL_COUNT | Skipped: $SKIP_COUNT"
    [ "$TOTAL_COUNT" -gt 0 ]
    [ "$TOTAL_COUNT" -eq "$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))" ]
    [ "$FAIL_COUNT" -eq 0 ]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
