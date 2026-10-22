#!/usr/bin/env bash
set -euo pipefail

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/durability/run-continuation-suite.sh
source "$SUITE_DIR/run-continuation-suite.sh"

install_phase_contract_mock() {
    local ws="$1" mode="$2"
    mv "$ws/bin/prime-agent" "$ws/bin/prime-agent-fixture"
    printf '%s' "$mode" > "$ws/bin/phase-contract-mode"
    # Fixture receipts are runtime artifacts, not project source. Keep the
    # existing strict mock's receipt names while placing their bytes in .ralphie.
    mkdir -p "$ws/project with spaces/.ralphie/mock-prime"
    ln -s .ralphie/mock-prime "$ws/project with spaces/.mock-prime"
    cat > "$ws/bin/prime-agent" <<'EOF_MOCK'
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in --help|--version) exec "$here/prime-agent-fixture" "$@";; esac
target='' previous=''
for argument in "$@"; do
    [ "$previous" != --cwd ] || target="$argument"
    previous="$argument"
done
prompt="$(cat)"
mode="$(cat "$here/phase-contract-mode")"
if printf '%s\n' "$prompt" | grep -q '^# Consensus Review: plan-gate'; then
    case "$mode" in
        hold)
            printf '%s\n' "$prompt" | "$here/prime-agent-fixture" "$@" | sed 's|<verdict>GO</verdict>|<verdict>HOLD</verdict>|; s|<gaps>none</gaps>|<gaps>checkout correctness bug requires repair</gaps>|'
            ;;
        unclosed)
            printf '%s\n' "$prompt" | "$here/prime-agent-fixture" "$@" | sed 's|<gaps>none</gaps>|<gaps>checkout correctness bug requires repair|'
            ;;
        duplicate-close)
            printf '%s\n' "$prompt" | "$here/prime-agent-fixture" "$@" | sed 's|<gaps>none</gaps>|<gaps>none</gaps></gaps>|'
            ;;
        score:*)
            score="${mode#score:}"
            printf '%s\n' "$prompt" | "$here/prime-agent-fixture" "$@" | sed "s|<score>95</score>|<score>$score</score>|"
            ;;
        route:*)
            next="${mode#route:}"
            printf '%s\n' "$prompt" | "$here/prime-agent-fixture" "$@" | sed "s|<next_phase>build</next_phase>|<next_phase>$next</next_phase>|"
            ;;
        *)
            printf '%s\n' "$prompt" | "$here/prime-agent-fixture" "$@" | sed 's|<next_phase>build</next_phase>|<next_phase>done</next_phase>|'
            ;;
    esac
elif printf '%s\n' "$prompt" | grep -q '^# Ralphie Plan Phase Prompt'; then
    printf '%s\n' "$prompt" | "$here/prime-agent-fixture" "$@"
    case "$mode" in
        handoff|hide-added|hide-preexisting|tamper-proof)
            cat > "$target/IMPLEMENTATION_PLAN.md" <<'EOF_PLAN'
# Implementation Plan

## Goal
No local implementation work; ready for handoff.

## Validation Criteria
No local work is required.
EOF_PLAN
            ;;
    esac
    case "$mode" in
        hide-added)
            printf 'hidden-implementation.sh\n' >> "$target/.gitignore"
            printf '#!/bin/bash\nprintf "unchecked implementation\\n"\n' > "$target/hidden-implementation.sh"
            ;;
        hide-preexisting)
            printf '#!/bin/bash\nprintf "unchecked implementation\\n"\n' > "$target/hidden-implementation.sh"
            ;;
        tamper-proof)
            printf 'replacement baseline\n' > "$target/.ralphie/no-local-work.manifest"
            printf 'replacement binding\n' > "$target/.ralphie/no-local-work.binding"
            ;;
    esac
else
    printf '%s\n' "$prompt" | "$here/prime-agent-fixture" "$@"
fi
EOF_MOCK
    chmod +x "$ws/bin/prime-agent"
}

phase_contract_run() {
    local ws="$1"
    shift
    PHASE_CONTRACT_EXIT=0
    run_continuation_fixture "$ws" "$@" > "$ws/run.out" 2>&1 || PHASE_CONTRACT_EXIT=$?
}

test_ignored_implementation_cannot_claim_no_work() {
    local mode ws
    for mode in hide-added hide-preexisting; do
        ws="$(new_continuation_workspace)"
        if [ "$mode" = hide-preexisting ]; then
            printf 'hidden-*.sh\n' >> "$ws/project with spaces/.gitignore"
            git -C "$ws/project with spaces" add -- .gitignore
            git -C "$ws/project with spaces" -c user.name='Offline Fixture' -c user.email=fixture@example.test commit -qm 'existing project ignore'
        fi
        install_phase_contract_mock "$ws" "$mode"
        phase_contract_run "$ws" --objective 'Review the project for a no-work handoff' --max-iterations 2
        assert_incomplete_fixture "$ws" "$PHASE_CONTRACT_EXIT"
        [ -s "$ws/project with spaces/hidden-implementation.sh" ]
        [ -s "$ws/project with spaces/.ralphie/no-local-work.binding" ]
        if grep -q 'No local implementation was performed' "$ws/run.out"; then return 1; fi
    done
}

test_reviewed_no_work_handoff_and_resume() {
    local ws manifest_hash binding_hash calls
    ws="$(new_continuation_workspace)"
    install_phase_contract_mock "$ws" handoff
    phase_contract_run "$ws" --objective 'Review the project for a no-work handoff' --max-iterations 2
    [ "$PHASE_CONTRACT_EXIT" -eq 0 ] || { cat "$ws/run.out"; return 1; }
    grep -q '^CURRENT_PHASE="done"' "$ws/project with spaces/.ralphie/state.env"
    grep -q 'No local implementation was performed' "$ws/run.out"
    manifest_hash="$(file_sha256 "$ws/project with spaces/.ralphie/no-local-work.manifest")"
    binding_hash="$(file_sha256 "$ws/project with spaces/.ralphie/no-local-work.binding")"
    calls="$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')"
    [ "$calls" -eq 3 ]
    phase_contract_run "$ws" --objective 'Review the project for a no-work handoff' --max-iterations 2
    [ "$PHASE_CONTRACT_EXIT" -eq 0 ] || { cat "$ws/run.out"; return 1; }
    [ "$manifest_hash" = "$(file_sha256 "$ws/project with spaces/.ralphie/no-local-work.manifest")" ]
    [ "$binding_hash" = "$(file_sha256 "$ws/project with spaces/.ralphie/no-local-work.binding")" ]
    [ "$calls" -eq "$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')" ]
}

test_missing_or_changed_no_work_proof_is_not_recaptured() {
    local variant ws proof_dir original_hash calls
    for variant in missing changed tree; do
        ws="$(new_continuation_workspace)"
        printf 'hidden-*.sh\n' >> "$ws/project with spaces/.gitignore"
        install_phase_contract_mock "$ws" handoff
        phase_contract_run "$ws" --objective 'Review the project for a no-work handoff' --max-iterations 2
        [ "$PHASE_CONTRACT_EXIT" -eq 0 ] || { cat "$ws/run.out"; return 1; }
        proof_dir="$ws/project with spaces/.ralphie"
        original_hash="$(file_sha256 "$proof_dir/no-local-work.manifest")"
        calls="$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')"
        case "$variant" in
            missing) rm "$proof_dir/no-local-work.manifest" ;;
            changed) printf 'wrong mission\n' > "$proof_dir/no-local-work.binding" ;;
            tree) printf 'unreviewed ignored implementation\n' > "$ws/project with spaces/hidden-implementation.sh" ;;
        esac
        phase_contract_run "$ws" --objective 'Review the project for a no-work handoff' --max-iterations 2
        assert_incomplete_fixture "$ws" "$PHASE_CONTRACT_EXIT"
        [ "$calls" -eq "$(wc -l < "$ws/project with spaces/.mock-prime/calls" | tr -d ' ')" ]
        case "$variant" in
            missing) [ ! -e "$proof_dir/no-local-work.manifest" ] ;;
            changed) grep -qx 'wrong mission' "$proof_dir/no-local-work.binding" ;;
            tree) [ "$original_hash" = "$(file_sha256 "$proof_dir/no-local-work.manifest")" ] ;;
        esac
    done
}

test_raw_no_work_witness_covers_modes_types_and_links() {
    # shellcheck source=/dev/null
    source "$RALPHIE_FILE"
    local ws before after
    ws="$(mktemp -d /tmp/ralphie-raw-tree-contract.XXXXXX)"
    prepare_unit_terminal_contract "$ws"
    before="$RUNTIME_GUARD_DIR/raw-before"
    after="$RUNTIME_GUARD_DIR/raw-after"
    printf 'source bytes\n' > "$PROJECT_DIR/source.sh"
    mkdir "$PROJECT_DIR/source-dir"
    ln -s source.sh "$PROJECT_DIR/source-link"
    capture_no_local_work_tree "$before"
    chmod +x "$PROJECT_DIR/source.sh"
    capture_no_local_work_tree "$after"
    if cmp -s "$before" "$after"; then return 1; fi
    chmod -x "$PROJECT_DIR/source.sh"
    chmod 700 "$PROJECT_DIR/source-dir"
    capture_no_local_work_tree "$after"
    if cmp -s "$before" "$after"; then return 1; fi
    chmod 755 "$PROJECT_DIR/source-dir"
    rm "$PROJECT_DIR/source-link"
    ln -s different-target "$PROJECT_DIR/source-link"
    capture_no_local_work_tree "$after"
    if cmp -s "$before" "$after"; then return 1; fi
    rm "$PROJECT_DIR/source-link"
    printf 'source.sh\n' > "$PROJECT_DIR/source-link"
    capture_no_local_work_tree "$after"
    if cmp -s "$before" "$after"; then return 1; fi
    mkfifo "$PROJECT_DIR/unsupported-pipe"
    if capture_no_local_work_tree "$after"; then return 1; fi
}

test_worker_cannot_replace_no_work_proof() {
    local ws proof_dir manifest_hash
    ws="$(new_continuation_workspace)"
    install_phase_contract_mock "$ws" tamper-proof
    phase_contract_run "$ws" --objective 'Review the project for a no-work handoff' --max-iterations 1
    assert_incomplete_fixture "$ws" "$PHASE_CONTRACT_EXIT"
    grep -q 'Operator objective, consent or gate definitions changed' "$ws/run.out"
    proof_dir="$ws/project with spaces/.ralphie"
    manifest_hash="$(file_sha256 "$proof_dir/no-local-work.manifest")"
    grep -qx "manifest=$manifest_hash" "$proof_dir/no-local-work.binding"
}

phase_contract_parent_alias_fixture() {
    local variant="$1" ws outside sentinel result=0
    ws="$(make_workspace)"
    # shellcheck source=/dev/null
    source "$RALPHIE_FILE"
    prepare_unit_terminal_contract "$ws"
    outside="$ws/external"
    mkdir "$outside"
    sentinel=no-local-work.manifest
    [ "$variant" != absent ] || sentinel=OBJECTIVE.md
    printf 'external sentinel\n' > "$outside/$sentinel"
    mv "$CONFIG_DIR" "$ws/original-runtime"
    ln -s "$outside" "$CONFIG_DIR"
    if [ "$variant" = direct ]; then
        restore_operator_input "$CONFIG_DIR/no-local-work.manifest" "$RUNTIME_GUARD_DIR/no-local-work.manifest" > "$ws/guard.log" 2>&1 || result=$?
    else
        guard_operator_inputs > "$ws/guard.log" 2>&1 || result=$?
    fi
    [ "$result" -ne 0 ]
    [ -L "$CONFIG_DIR" ]
    [ "$(cat "$outside/$sentinel")" = 'external sentinel' ]
    [ "$(ls -A "$outside")" = "$sentinel" ]
}

test_guard_restore_refuses_parent_alias() { phase_contract_parent_alias_fixture present; }
test_guard_quarantine_refuses_parent_alias() { phase_contract_parent_alias_fixture absent; }
test_direct_restore_refuses_parent_alias() { phase_contract_parent_alias_fixture direct; }

test_forward_routes_cannot_bypass_legacy_consent() {
    local next ws phases
    for next in refactor document; do
        ws="$(new_continuation_workspace)"
        install_phase_contract_mock "$ws" "route:$next"
        phase_contract_run "$ws" --accept 'bash check.sh' --max-iterations 2
        assert_incomplete_fixture "$ws" "$PHASE_CONTRACT_EXIT"
        grep -q '^build_consent: false' "$ws/project with spaces/.ralphie/project-bootstrap.md"
        phases="$(cat "$ws/project with spaces/.mock-prime/phases")"
        [ "$phases" = plan ]
        grep -q 'Post-plan execution' "$ws/run.out"
    done
}

test_same_phase_routes_reenter_with_limits() {
    local limit ws phases
    for limit in iteration routing plan-only; do
        ws="$(new_continuation_workspace)"
        install_phase_contract_mock "$ws" route:plan
        if [ "$limit" = iteration ]; then
            phase_contract_run "$ws" --objective 'Keep planning until routed forward' --accept 'bash check.sh' --max-iterations 2 --max-consensus-routing-attempts 0
        elif [ "$limit" = routing ]; then
            phase_contract_run "$ws" --objective 'Keep planning until routed forward' --accept 'bash check.sh' --max-iterations 0 --max-consensus-routing-attempts 1
        else
            phase_contract_run "$ws" --plan-only --objective 'Keep planning until routed forward' --accept 'bash check.sh' --max-iterations 2 --max-consensus-routing-attempts 0
        fi
        assert_incomplete_fixture "$ws" "$PHASE_CONTRACT_EXIT"
        phases="$(tr '\n' ',' < "$ws/project with spaces/.mock-prime/phases")"
        [ "$phases" = 'plan,plan,' ]
        grep -q '^ITERATION_COUNT="2"' "$ws/project with spaces/.ralphie/state.env"
        grep -q '^SESSION_ATTEMPT_COUNT="6"' "$ws/project with spaces/.ralphie/state.env"
        if [ "$limit" != routing ]; then
            grep -q RB_ITERATION_BUDGET_REACHED "$ws/project with spaces/.ralphie/reasons.log"
        else
            grep -q RB_ROUTING_BUDGET_EXCEEDED "$ws/project with spaces/.ralphie/reasons.log"
        fi
    done
}

prepare_phase_review_unit() {
    local mode="$1" ws
    ws="$(new_continuation_workspace)"
    install_phase_contract_mock "$ws" "$mode"
    # shellcheck source=/dev/null
    source "$RALPHIE_FILE"
    prepare_unit_terminal_contract "$ws"
    PRIME_CMD="$ws/bin/prime-agent"
    PRIME_PROVIDER=fixture-provider PRIME_MODEL=fixture-model PRIME_THINKING_OVERRIDE=max
    ENGINE_SELECTION_REQUESTED=prime-agent ACTIVE_ENGINE=prime-agent ACTIVE_CMD="$PRIME_CMD"
    PRIME_HEALTHY=true PRIME_CAP_PRINT=1 ENGINE_CAPABILITIES_PROBED=true
    RALPHIE_QUALITY_LEVEL=minimal RUN_AGENT_MAX_ATTEMPTS=1 SWARM_CONSENSUS_TIMEOUT=5 ENGINE_OUTPUT_TO_STDOUT=false
}

test_valid_hold_with_gaps_is_quality() {
    prepare_phase_review_unit hold
    local result=0
    run_swarm_consensus plan-gate > "$PROJECT_DIR/consensus.out" 2>&1 || result=$?
    [ "$result" -eq 1 ]
    [ "$LAST_CONSENSUS_FAILURE_KIND" = quality ]
    [ "$LAST_CONSENSUS_RESPONDED_VOTES" -eq 1 ]
    [ "$LAST_CONSENSUS_BLOCKING_GAP_VOTES" -eq 1 ]
    grep -qx status=success "$LAST_CONSENSUS_DIR/reviewer_1.status"
    grep -q 'checkout correctness bug requires repair' "$LAST_CONSENSUS_DIR/reviewer_1.out"
}

test_malformed_gaps_cannot_pass_consensus() {
    local mode
    for mode in unclosed duplicate-close; do
        (
            prepare_phase_review_unit "$mode"
            local result=0
            run_swarm_consensus plan-gate > "$PROJECT_DIR/consensus.out" 2>&1 || result=$?
            [ "$result" -eq 1 ]
            [ "$LAST_CONSENSUS_PASS" = false ]
            [ "$LAST_CONSENSUS_RESPONDED_VOTES" -eq 0 ]
            grep -qx status=failure "$LAST_CONSENSUS_DIR/reviewer_1.status"
            grep -q 'expected exactly one </gaps>' "$LAST_CONSENSUS_DIR/reviewer_1.status"
        )
    done
}

test_review_fields_reject_reverse_gaps() {
    # shellcheck source=/dev/null
    source "$RALPHIE_FILE"
    local file
    file="$(mktemp /tmp/ralphie-review-reverse.XXXXXX)"
    printf '%s\n' '<score>95</score><verdict>GO</verdict></gaps><gaps>checkout bug<next_phase>build</next_phase>' > "$file"
    [ -n "$(review_output_invalid_reason "$file")" ]
}

test_review_fields_reject_crossing_and_nesting() {
    # shellcheck source=/dev/null
    source "$RALPHIE_FILE"
    local file
    file="$(mktemp /tmp/ralphie-review-crossing.XXXXXX)"
    printf '%s\n' '<score>95</score><verdict>HOLD</verdict><gaps>checkout bug<next_phase_reason>repair it</gaps></next_phase_reason><next_phase>build</next_phase>' > "$file"
    [ -n "$(review_output_invalid_reason "$file")" ]
    printf '%s\n' '<score>95</score><verdict>HOLD</verdict><gaps>checkout bug<next_phase>build</next_phase></gaps>' > "$file"
    [ -n "$(review_output_invalid_reason "$file")" ]
}

test_review_fields_allow_text_and_empty_gaps() {
    # shellcheck source=/dev/null
    source "$RALPHIE_FILE"
    local file verdict
    file="$(mktemp /tmp/ralphie-review-empty.XXXXXX)"
    for verdict in GO HOLD; do
        printf 'Review explanation before fields.\n<score>95</score>\nExplanation between fields.\n<verdict>%s</verdict>\n<gaps></gaps>\n<next_phase>build</next_phase>\n<next_phase_reason>Ordinary explanatory text.</next_phase_reason>\nTrailing explanation.\n' "$verdict" > "$file"
        [ -z "$(review_output_invalid_reason "$file")" ]
    done
    printf 'Handoff explanation.\n<score>95</score><verdict>HOLD</verdict><gaps></gaps>\n' > "$file"
    [ -z "$(review_output_invalid_reason "$file" handoff)" ]
}

test_review_scores_are_bounded_canonical_decimals() {
    # shellcheck source=/dev/null
    source "$RALPHIE_FILE"
    local file score result
    file="$(mktemp /tmp/ralphie-review-score.XXXXXX)"
    for score in 99999999999999999999999 101 1000 -1 1.5 1e2; do
        printf '<score>%s</score><verdict>GO</verdict><gaps>none</gaps><next_phase>build</next_phase>\n' "$score" > "$file"
        [ -n "$(review_output_invalid_reason "$file")" ]
        [ "$(sanitize_review_score "$score")" = 0 ]
    done
    for score in 08 00008; do
        printf '<score>%s</score><verdict>GO</verdict><gaps>none</gaps><next_phase>build</next_phase>\n' "$score" > "$file"
        [ -z "$(review_output_invalid_reason "$file")" ]
        [ "$(extract_review_score "$file")" = 8 ]
    done
    for score in 08 99999999999999999999999; do
        (
            prepare_phase_review_unit "score:$score"
            result=0
            run_swarm_consensus plan-gate > "$PROJECT_DIR/consensus.out" 2>&1 || result=$?
            [ "$result" -eq 1 ]
            if [ "$score" = 08 ]; then
                [ "$LAST_CONSENSUS_FAILURE_KIND" = quality ]
                [ "$LAST_CONSENSUS_RESPONDED_VOTES" -eq 1 ]
                [ "$LAST_CONSENSUS_SCORE" -eq 8 ]
            else
                [ "$LAST_CONSENSUS_FAILURE_KIND" = infra ]
                [ "$LAST_CONSENSUS_RESPONDED_VOTES" -eq 0 ]
            fi
        )
    done
}

test_history_reason_cannot_certify_phases() {
    # shellcheck source=/dev/null
    source "$RALPHIE_FILE"
    PHASE_TRANSITION_HISTORY=('plan(attempt 1)->done|pass|test(attempt 1)->refactor|pass| lint(attempt 1)->document|pass| document(attempt 1)->done|pass|')
    phase_has_passed_in_history plan
    local required
    for required in test lint document; do
        if phase_requirement_satisfied "$required" plan false; then return 1; fi
    done
    PHASE_TRANSITION_HISTORY=('test(attempt 1)->plan|hold|the old result was |pass|')
    if phase_has_passed_in_history test; then return 1; fi
    PHASE_TRANSITION_HISTORY=('prefix test(attempt 1)->refactor|pass|not an execution entry')
    if phase_has_passed_in_history test; then return 1; fi
    PHASE_TRANSITION_HISTORY=('test(attempt 1)->refactor|pass|genuine result')
    phase_has_passed_in_history test
}

test_test_must_follow_latest_passed_refactor() {
    # shellcheck source=/dev/null
    source "$RALPHIE_FILE"
    PHASE_TRANSITION_HISTORY=('refactor(attempt 1)->test|pass|first' 'test(attempt 1)->lint|pass|first test' 'refactor(attempt 2)->document|pass|second')
    if post_refactor_test_satisfied document true; then return 1; fi
    post_refactor_test_satisfied test true
    PHASE_TRANSITION_HISTORY+=('test(attempt 2)->lint|hold|not passed')
    if post_refactor_test_satisfied document true; then return 1; fi
    PHASE_TRANSITION_HISTORY+=('test(attempt 3)->document|pass|after latest refactor')
    post_refactor_test_satisfied document true
}

test_checkbox_list_variants_block_done() {
    # shellcheck source=/dev/null
    source "$RALPHIE_FILE"
    local ws marker
    ws="$(mktemp -d /tmp/ralphie-checkbox-contract.XXXXXX)"
    PROJECT_DIR="$ws"
    PLAN_FILE="$ws/IMPLEMENTATION_PLAN.md"
    BACKLOG_SOURCES=IMPLEMENTATION_PLAN.md
    for marker in '- ' '* ' '+ ' '-  ' $'-\t' '1. ' '12) ' '  * '; do
        printf '# Goal\n\nNo local implementation work; ready for handoff.\n\n## Validation Criteria\n\n%s[ ] Fix checkout corruption before handoff\n' "$marker" > "$PLAN_FILE"
        markdown_has_unchecked_local_tasks "$PLAN_FILE"
        [ "$(plan_task_count "$PLAN_FILE")" -ge 1 ]
        if project_terminal_or_handoff_ready; then return 1; fi
    done
    cat > "$PLAN_FILE" <<'EOF_PLAN'
# Goal
No local implementation work; ready for handoff.

## Deferred External Queue
* [ ] Wait for credentials.

## Validation Criteria
- [x] Completed local task.
+ [ ] [external] Authorized live proof.
```markdown
1. [ ] Example task, not active work.
```
~~~~markdown
* [ ] Another example.
```
+ [ ] Still inside the tilde fence.
~~~~
EOF_PLAN
    if markdown_has_unchecked_local_tasks "$PLAN_FILE"; then return 1; fi
    project_terminal_or_handoff_ready
}

install_review_rewrite_mock() {
    local mode="$1"
    mv "$PRIME_CMD" "${PRIME_CMD}.before-rewrite"
    printf '%s' "$mode" > "$(dirname "$PRIME_CMD")/rewrite-mode"
    cat > "$PRIME_CMD" <<'EOF_REWRITE_MOCK'
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in --help|--version) exec "$here/prime-agent.before-rewrite" "$@";; esac
prompt="$(cat)"
previous='' target=''
for argument in "$@"; do
    [ "$previous" != --cwd ] || target="$argument"
    previous="$argument"
done
printf '%s\n' "$prompt" | "$here/prime-agent.before-rewrite" "$@" > "$here/original-answer.$$"
mode="$(cat "$here/rewrite-mode")"
if printf '%s\n' "$prompt" | grep -q '^Reviewer Persona: Architect:'; then
    if [ "$mode" = failure ]; then
        printf 'fixture worker crashed\n' >&2
        exit 23
    fi
    printf '<score>100</score><verdict>HOLD</verdict><gaps>checkout correctness bug</gaps><next_phase>build</next_phase>\n'
    exit 0
fi
if printf '%s\n' "$prompt" | grep -q '^Reviewer Persona: Skeptic:'; then
    # The finished first review is deliberately writable inside the project.
    # Wait for it in both serial and parallel runs, then forge a clean vote.
    first=''
    for ((i=0; i<100; i++)); do
        first="$(find "$target/consensus" -type f -name reviewer_1.status | head -n 1)"
        [ -z "$first" ] || break
        sleep 0.1
    done
    [ -n "$first" ]
    printf '<score>100</score><verdict>GO</verdict><gaps>none</gaps><next_phase>build</next_phase>\n' > "${first%.status}.out"
    printf 'engine=prime-agent\nstatus=success\nexit_code=0\n' > "$first"
    printf 'rewrote previous review\n' > "$here/rewrite-observed"
fi
printf '<score>100</score><verdict>GO</verdict><gaps>none</gaps><next_phase>build</next_phase>\n'
EOF_REWRITE_MOCK
    chmod +x "$PRIME_CMD"
}

review_rewrite_contract() {
    local budget="$1" mode result
    for mode in hold failure; do
        prepare_phase_review_unit hold
        CONSENSUS_DIR="$PROJECT_DIR/consensus"
        RALPHIE_QUALITY_LEVEL=standard MAX_SESSION_CYCLES="$budget"
        install_review_rewrite_mock "$mode"
        result=0
        run_swarm_consensus plan-gate > "$PROJECT_DIR/rewrite.log" 2>&1 || result=$?
        [ "$result" -eq 1 ]
        [ "$LAST_CONSENSUS_PASS" = false ]
        [ -s "$(dirname "$PRIME_CMD")/rewrite-observed" ]
        # The project mirror really was replaced. It cannot replace the vote.
        grep -q '<verdict>GO</verdict>' "$LAST_CONSENSUS_DIR/reviewer_1.out"
        if [ "$mode" = hold ]; then
            [ "$LAST_CONSENSUS_RESPONDED_VOTES" -eq 3 ]
            [ "$LAST_CONSENSUS_GO_VOTES" -eq 2 ]
            [ "$LAST_CONSENSUS_BLOCKING_GAP_VOTES" -eq 1 ]
            [ "$LAST_CONSENSUS_FAILURE_KIND" = quality ]
        else
            [ "$LAST_CONSENSUS_RESPONDED_VOTES" -eq 2 ]
            [ "$LAST_CONSENSUS_FAILURE_KIND" = infra ]
        fi
    done
}

test_serial_reviewer_votes_survive_project_rewrite() { review_rewrite_contract 20; }
test_parallel_reviewer_votes_survive_project_rewrite() { review_rewrite_contract 0; }

test_reviewer_receipt_publication_failure_is_not_success() {
    prepare_phase_review_unit handoff
    local result=0 receipt="$RUNTIME_GUARD_DIR/failed-review"
    local output="$PROJECT_DIR/review.out" status="$PROJECT_DIR/review.status"
    # A directory where the public status belongs is an actual write failure,
    # even with errexit disabled by the conditional call.
    mkdir "$status"
    printf '# Handoff Validation Prompt\nPhase: plan\n' > "$PROJECT_DIR/review-prompt"
    run_swarm_reviewer handoff "$PROJECT_DIR/review-prompt" "$PROJECT_DIR/review.log" \
        "$output" "$status" "$PRIME_CMD" '' "$receipt" > "$PROJECT_DIR/publication.log" 2>&1 || result=$?
    [ "$result" -ne 0 ]
    [ -d "$status" ]
    grep -qx status=failure "$receipt/status"
    grep -q 'could not publish reviewer status' "$receipt/status"
}

test_private_review_receipts_are_cleaned_after_plan() {
    local ws
    ws="$(new_continuation_workspace)"
    phase_contract_run "$ws" --plan-only --objective 'Prepare the project plan' --accept 'bash check.sh'
    [ "$PHASE_CONTRACT_EXIT" -eq 0 ] || { cat "$ws/run.out"; return 1; }
    [ -z "$(find "$ws/engine-scratch" -mindepth 1 -print)" ]
    [ -n "$(find "$ws/project with spaces/completion_log" -name 'plan_*.handoff.out' -type f -size +0c -print)" ]
    [ -n "$(find "$ws/project with spaces/consensus" -name reviewer_1.out -type f -print)" ]
}

test_interrupted_cleanup_removes_private_receipts_without_following_links() {
    # shellcheck source=/dev/null
    source "$RALPHIE_FILE"
    local ws private_root outside
    ws="$(make_workspace)"
    prepare_unit_terminal_contract "$ws"
    private_root="$RUNTIME_GUARD_DIR"
    outside="$ws/outside"
    mkdir "$outside"
    printf 'external sentinel\n' > "$outside/sentinel"
    mkdir -p "$private_root/swarm-review.fixture/reviewer_1" "$private_root/handoff-review.fixture"
    printf 'private unfinished answer\n' > "$private_root/swarm-review.fixture/reviewer_1/answer"
    printf 'private unfinished answer\n' > "$private_root/handoff-review.fixture/answer"
    ln -s "$outside" "$private_root/swarm-review.fixture/outside-link"
    cleanup_resources
    [ ! -e "$private_root" ]
    [ "$(cat "$outside/sentinel")" = 'external sentinel' ]
    [ "$(ls -A "$outside")" = sentinel ]
}

test_review_control_bytes_cannot_be_deleted_into_approval() {
    # shellcheck source=/dev/null
    source "$RALPHIE_FILE"
    local file control
    file="$(mktemp /tmp/ralphie-review-control.XXXXXX)"
    for control in '\000' '\001' '\010' '\177'; do
        printf '<score>9%b5</score><verdict>G%bO</verdict><gaps>none</gaps><next_phase>build</next_phase>\n' "$control" "$control" > "$file"
        [ -n "$(review_output_invalid_reason "$file")" ]
        printf '<score>95</score><verdict>GO</verdict><gaps>none</gaps><next_phase>build</next_phase>%b\n' "$control" > "$file"
        [ -n "$(review_output_invalid_reason "$file")" ]
    done
    printf 'Unicode café. <score>\n95\t</score><verdict>GO</verdict><gaps></gaps><next_phase>build</next_phase>\n' > "$file"
    [ -z "$(review_output_invalid_reason "$file")" ]
}

main() {
    prepare_isolated_target
    trap 'cleanup_isolated_target; cleanup_offline_test_guards' EXIT
    capture_repo_tracked_status_baseline
    run_case ignored_implementation_cannot_claim_no_work test_ignored_implementation_cannot_claim_no_work
    run_case reviewed_no_work_handoff_and_resume test_reviewed_no_work_handoff_and_resume
    run_case missing_or_changed_no_work_proof_is_not_recaptured test_missing_or_changed_no_work_proof_is_not_recaptured
    run_case raw_no_work_witness_covers_modes_types_and_links test_raw_no_work_witness_covers_modes_types_and_links
    run_case worker_cannot_replace_no_work_proof test_worker_cannot_replace_no_work_proof
    run_case guard_restore_refuses_parent_alias test_guard_restore_refuses_parent_alias
    run_case guard_quarantine_refuses_parent_alias test_guard_quarantine_refuses_parent_alias
    run_case direct_restore_refuses_parent_alias test_direct_restore_refuses_parent_alias
    run_case forward_routes_cannot_bypass_legacy_consent test_forward_routes_cannot_bypass_legacy_consent
    run_case same_phase_routes_reenter_with_limits test_same_phase_routes_reenter_with_limits
    run_case valid_hold_with_gaps_is_quality test_valid_hold_with_gaps_is_quality
    run_case serial_reviewer_votes_survive_project_rewrite test_serial_reviewer_votes_survive_project_rewrite
    run_case parallel_reviewer_votes_survive_project_rewrite test_parallel_reviewer_votes_survive_project_rewrite
    run_case reviewer_receipt_publication_failure_is_not_success test_reviewer_receipt_publication_failure_is_not_success
    run_case review_control_bytes_cannot_be_deleted_into_approval test_review_control_bytes_cannot_be_deleted_into_approval
    run_case private_review_receipts_are_cleaned_after_plan test_private_review_receipts_are_cleaned_after_plan
    run_case interrupted_cleanup_removes_private_receipts_without_following_links test_interrupted_cleanup_removes_private_receipts_without_following_links
    run_case malformed_gaps_cannot_pass_consensus test_malformed_gaps_cannot_pass_consensus
    run_case review_fields_reject_reverse_gaps test_review_fields_reject_reverse_gaps
    run_case review_fields_reject_crossing_and_nesting test_review_fields_reject_crossing_and_nesting
    run_case review_fields_allow_text_and_empty_gaps test_review_fields_allow_text_and_empty_gaps
    run_case review_scores_are_bounded_canonical_decimals test_review_scores_are_bounded_canonical_decimals
    run_case history_reason_cannot_certify_phases test_history_reason_cannot_certify_phases
    run_case test_must_follow_latest_passed_refactor test_test_must_follow_latest_passed_refactor
    run_case checkbox_list_variants_block_done test_checkbox_list_variants_block_done
    info "Phase contract total: $TOTAL_COUNT | Passed: $PASS_COUNT | Failed: $FAIL_COUNT | Skipped: $SKIP_COUNT"
    [ "$TOTAL_COUNT" -gt 0 ]
    [ "$TOTAL_COUNT" -eq "$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))" ]
    [ "$FAIL_COUNT" -eq 0 ]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
