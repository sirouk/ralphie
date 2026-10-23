#!/usr/bin/env bash
set -euo pipefail

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/durability/run-continuation-suite.sh
source "$SUITE_DIR/run-continuation-suite.sh"

run_terminal_contract_group() {
    command -v python3 >/dev/null 2>&1 || return 200
    local ws="$1" group="$2"
    python3 - "$RALPHIE_FILE" "$ws" "$group" "$RALPHIE_TEST_GUARD_DIR" <<'PY_TERMINAL'
import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import sys
import termios
import time

script, workspace, group, guards = sys.argv[1:]
root = Path(workspace)
base_env = dict(PATH=guards + ':/usr/bin:/bin:/usr/sbin:/sbin', HOME=str(root / 'home'),
                TMPDIR=str(root / 'engine-scratch'), TERM='xterm-256color', LANG='en_US.UTF-8',
                RALPHIE_LIB='1')
for relative in ('home', 'engine-scratch'):
    (root / relative).mkdir(exist_ok=True)

def run(name, code='', steps=(), expected=0, updates=None, arguments=None):
    case = root / name
    case.mkdir()
    env = dict(base_env, MENU_CASE=str(case), MENU_RESULT=str(case / 'value'), MENU_STATUS=str(case / 'status'))
    if updates:
        env.update(updates)
    master, slave = pty.openpty()
    def attach():
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)
    if arguments is None:
        command = ['/bin/bash', '-c', 'source "$1"; set +e; ' + code, 'menu-contract', script]
    else:
        env.pop('RALPHIE_LIB')
        command = ['/bin/bash', script] + arguments
    child = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave,
                             env=env, preexec_fn=attach)
    os.close(slave)
    output = bytearray()
    cursor = 0
    pending = list(steps)
    deadline = time.monotonic() + (45 if arguments is not None else 12)
    closed = False
    try:
        while time.monotonic() < deadline:
            if not closed and select.select([master], [], [], 0.05)[0]:
                try:
                    chunk = os.read(master, 65536)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    chunk = b''
                if chunk:
                    output.extend(chunk)
                else:
                    closed = True
            while pending and pending[0][0] in output[cursor:]:
                token, answer = pending.pop(0)
                cursor = output.index(token, cursor) + len(token)
                os.write(master, answer)
            if child.poll() is not None:
                break
            if closed:
                time.sleep(0.01)
        if child.poll() is None:
            raise AssertionError(name + ' did not finish within its terminal deadline')
        while not closed and select.select([master], [], [], 0)[0]:
            try:
                chunk = os.read(master, 65536)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                break
            if not chunk:
                break
            output.extend(chunk)
        assert not pending, (name, 'expected prompt was not reached', pending)
        assert child.returncode == expected, (name, child.returncode, expected)
    except BaseException:
        sys.stderr.write(name + ':\n' + output.decode(errors='replace') + '\n')
        raise
    finally:
        if child.poll() is None:
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                if child.poll() is None:
                    child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    if child.poll() is None:
                        child.kill()
                child.wait(timeout=2)
        os.close(master)
        (case / 'terminal.log').write_bytes(output)
    return case, bytes(output)

def capture(expression, prefix=''):
    return prefix + 'v="$(' + expression + ')"; r=$?; printf %s "$v" > "$MENU_RESULT"; printf %s "$r" > "$MENU_STATUS"'

def value(case, expected, status=0):
    assert (case / 'value').read_bytes() == expected, (case.name, (case / 'value').read_bytes(), expected)
    assert (case / 'status').read_text() == str(status), (case.name, (case / 'status').read_text(), status)

if group == 'line':
    cases = [('default', b'\n', b'yes'), ('option', b'-n\n', b'-n'),
             ('spaces', b'  exact  \n', b'  exact  '), ('unicode', 'café \\literal\n'.encode(), 'café \\literal'.encode()),
             ('arrows', b'ac\x1b[Db\n', b'abc'), ('eof', b'\x04', b'')]
    for name, answer, expected in cases:
        case, _ = run(name, capture('prompt_read_line "PROMPT> " yes'), [(b'PROMPT> ', answer)])
        value(case, expected, 130 if name == 'eof' else 0)
    case, _ = run('pipe-arrows', capture('prompt_read_line "PROMPT> " yes', 'exec 0< <(printf pipe); '),
                  [(b'PROMPT> ', b'ac\x1b[Db\n')])
    value(case, b'abc')
    case, output = run('dumb-spaces', capture('prompt_read_line "PROMPT> " yes'),
                       [(b'PROMPT> ', b'  exact  \n')], updates={'TERM': 'dumb'})
    value(case, b'  exact  ')
    assert b'\x1b' not in output, output
elif group == 'yes-no':
    for name, default, answer, expected, status in [
            ('yes-default', 'y', b'\n', b'true', 0), ('no', 'y', b'n\n', b'false', 0),
            ('eof', 'y', b'\x04', b'', 130)]:
        case, _ = run(name, capture('prompt_yes_no "PROMPT>" ' + default), [(b'PROMPT>', answer)])
        value(case, expected, status)
    case, output = run('invalid-prefix', capture('prompt_yes_no "PROMPT>" n'),
                       [(b'PROMPT>', b'yolo\n'), (b'PROMPT>', b'no\n')])
    value(case, b'false')
    assert b'Please enter yes or no' in output, output
elif group == 'multiline':
    for name, answer, expected, status in [
            ('empty-eof', b'\x04', b'', 130), ('default', b'\n', b'kept', 0),
            ('sentinel', b'first line\nsecond line\nEOF\n', b'first line\nsecond line', 0),
            ('partial-eof', b'first line\nsecond line\n\x04', b'first line\nsecond line', 0)]:
        case, _ = run(name, capture('prompt_multiline_block "PASTE" kept EOF'), [(b'> ', answer)])
        value(case, expected, status)
elif group == 'credentials':
    current = b'fixture-existing-token-12345'
    replacement = b'fixture-replacement-token-67890'
    for name, answer, expected, status, updates in [
            ('default', b'\n', current, 0, {}), ('typed', replacement + b'\n', replacement, 0, {}),
            ('clear', b'-\n', b'', 0, {}), ('eof', b'\x04', b'', 130, {}),
            ('dumb-typed', replacement + b'\n', replacement, 0, {'TERM': 'dumb'})]:
        expression = 'prompt_override_value "Secret credential" fixture-existing-token-12345 true'
        case, output = run(name, capture(expression), [(b'Secret credential', answer)], updates=updates)
        value(case, expected, status)
        assert b'configured' in output and current not in output and replacement not in output, output
elif group == 'interrupt':
    setup = ('ENGINE_OUTPUT_TO_STDOUT=false; '
             'save_state() { printf saved >> "$MENU_CASE/saved"; return "${MENU_SAVE_RESULT:-0}"; }; '
             'cleanup_resources() { printf cleanup >> "$MENU_CASE/cleanup"; }; '
             'cleanup_managed_processes() { :; }; ')
    for name, answer, expected in [('resume', b'r\n', 0), ('pause', b'p\n', 0),
                                    ('eof', b'\x04', 0), ('quit', b'q\n', 130)]:
        case, output = run(name, setup + 'show_interrupt_menu; printf AFTER_MENU', [(b'Action [', answer)], expected)
        if name == 'resume':
            assert b'AFTER_MENU' in output and not (case / 'saved').exists()
        else:
            assert b'AFTER_MENU' not in output and (case / 'cleanup').exists(), output
            if name != 'quit':
                assert (case / 'saved').read_bytes() == b'saved'
                assert b'Resuming...' not in output, output
    case, output = run('failed-save', setup + 'show_interrupt_menu; printf AFTER_MENU',
                       [(b'Action [', b'\x04')], 1, {'MENU_SAVE_RESULT': '1'})
    assert b'AFTER_MENU' not in output and b'State saved.' not in output, output
    case, output = run('second-interrupt', setup + 'trap handle_interrupt INT; handle_interrupt; printf AFTER_MENU',
                       [(b'Action [', b'\x03')], 130)
    assert b'AFTER_MENU' not in output and (case / 'cleanup').exists(), output
    case, output = run('help-toggle-resume', setup + 'show_interrupt_menu; printf %s "$ENGINE_OUTPUT_TO_STDOUT" > "$MENU_RESULT"',
                       [(b'Action [', b'h\n'), (b'Action [', b'l\n'), (b'Action [', b'r\n')])
    assert (case / 'value').read_bytes() == b'true' and (case / 'saved').read_bytes() == b'saved', output
elif group == 'colors':
    for name, updates in [('dumb', {'TERM': 'dumb'}), ('no-color-empty', {'NO_COLOR': ''}), ('no-color', {'NO_COLOR': '1'})]:
        _, output = run(name, 'info information; warn warning; err error; success success', updates=updates)
        assert b'\x1b' not in output, (name, output)
    case, output = run('destination', 'info plain > "$MENU_RESULT"; warn warning')
    assert b'\x1b' not in (case / 'value').read_bytes() and b'\x1b[1;33m' in output, output
elif group == 'critical-interrupt':
    code = '''PROJECT_DIR="$MENU_PROJECT"; CONFIG_DIR="$PROJECT_DIR/.ralphie"
STATE_FILE="$CONFIG_DIR/state.env"; LOCK_FILE="$CONFIG_DIR/run.lock"
REASON_LOG_FILE="$CONFIG_DIR/reasons.log"; REQUEST_CLAIM_DIR="$CONFIG_DIR/requests.lock"
RUNTIME_GUARD_DIR=''; CURRENT_PHASE=build; CURRENT_PHASE_INDEX=1
RALPHIE_CLEANUP_STATE_ENABLED=true; save_state || exit 1
acquire_lock || exit 1; request_lock || exit 1
NO_TERMINAL_INPUT=false; install_cleanup_traps
CURRENT_PHASE=done; CURRENT_PHASE_INDEX=6; PHASE_ATTEMPT_IN_PROGRESS=false
kill -INT $$
printf RETURNED_AFTER_CRITICAL_INTERRUPT
'''
    target = root / 'project with spaces'
    _, output = run('critical-interrupt', code, expected=130, updates={'MENU_PROJECT': str(target)})
    assert b'Action [' not in output and b'RETURNED_AFTER_CRITICAL_INTERRUPT' not in output, output
    assert 'CURRENT_PHASE="done"' in (target / '.ralphie/state.env').read_text()
    assert not (target / '.ralphie/requests.lock').exists(), output
    assert not (target / '.ralphie/run.lock.d').exists(), output
elif group == 'main-eof':
    target = root / 'project with spaces'
    mode = (root / 'main-mode').read_text()
    engine_guard = root / 'bin' / 'menu-engine-guard'
    engine_guard.write_text('''#!/usr/bin/env bash
case "${1:-}" in
 --help) printf '%s\\n' '-p --print --mode --cwd --offline --no-session --provider --model --thinking'; exit 0 ;;
 --version) printf 'offline menu fixture\\n'; exit 0 ;;
esac
printf inference >> "$(dirname "$0")/unexpected-menu-inference"
exit 97
''')
    engine_guard.chmod(0o755)
    for name in ('curl', 'wget'):
        path = root / 'bin' / name
        path.write_text('#!/usr/bin/env bash\nprintf network >> "$(dirname "$0")/unexpected-menu-network"\nexit 97\n')
        path.chmod(0o755)
    settings = dict(PRIME_ENGINE_CMD=str(engine_guard), CODEX_ENGINE_CMD=str(engine_guard), CLAUDE_ENGINE_CMD=str(engine_guard),
                    PATH=str(root / 'bin') + ':' + base_env['PATH'], RALPHIE_AUTO_UPDATE='false',
                    RALPHIE_AUTO_COMMIT_ON_PHASE_PASS='false', RALPHIE_STARTUP_OPERATIONAL_PROBE='false',
                    RALPHIE_NOTIFICATIONS_ENABLED='false', RALPHIE_ENGINE_HEALTH_MAX_ATTEMPTS='1',
                    RALPHIE_RUN_AGENT_MAX_ATTEMPTS='1', RALPHIE_RUN_AGENT_RETRY_DELAY_SECONDS='0',
                    RALPHIE_PHASE_COMPLETION_MAX_ATTEMPTS='1', RALPHIE_PHASE_COMPLETION_RETRY_DELAY_SECONDS='0',
                    RALPHIE_ENGINE_OVERRIDES_BOOTSTRAPPED='false' if mode == 'engine' else 'true',
                    RALPHIE_NOTIFICATION_WIZARD_BOOTSTRAPPED='false' if mode == 'notifications' else 'true')
    token = {'bootstrap': b'Is this a new project', 'engine': b'Configure engine selection',
             'notifications': b'Configure notifications now'}[mode]
    _, output = run(mode, steps=[(token, b'\x04')], expected=130, updates=settings,
                    arguments=['--project', str(target), '--accept', 'bash check.sh', '--max-iterations', '1'])
    assert not (root / 'bin' / 'unexpected-menu-inference').exists(), output
    assert not (root / 'bin' / 'unexpected-menu-network').exists(), output
    if mode == 'bootstrap':
        assert not (target / '.ralphie' / 'project-bootstrap.md').exists(), output
    else:
        config = target / '.ralphie' / 'config.env'
        if config.exists():
            key = 'ENGINE_OVERRIDES_BOOTSTRAPPED' if mode == 'engine' else 'NOTIFICATION_WIZARD_BOOTSTRAPPED'
            assert (key + '="true"').encode() not in config.read_bytes(), config.read_text()
    assert not (target / '.ralphie' / 'run.lock.d').exists(), output
else:
    raise AssertionError('Unknown terminal contract group: ' + group)
print('Terminal contract group passed: ' + group)
PY_TERMINAL
}

test_terminal_line_values_and_editing() {
    local ws
    ws="$(new_continuation_workspace)"
    run_terminal_contract_group "$ws" line
}

test_terminal_yes_no_and_cancellation() {
    local ws
    ws="$(new_continuation_workspace)"
    run_terminal_contract_group "$ws" yes-no
}

test_terminal_multiline_eof_contract() {
    local ws
    ws="$(new_continuation_workspace)"
    run_terminal_contract_group "$ws" multiline
}

test_terminal_credentials_are_hidden_and_masked() {
    local ws
    ws="$(new_continuation_workspace)"
    run_terminal_contract_group "$ws" credentials
}

test_terminal_interrupt_pause_and_cancel() {
    local ws
    ws="$(new_continuation_workspace)"
    run_terminal_contract_group "$ws" interrupt
}

test_terminal_colors_respect_destination_and_opt_out() {
    local ws
    ws="$(new_continuation_workspace)"
    run_terminal_contract_group "$ws" colors
}

test_terminal_critical_interrupt_never_opens_menu_or_strands_claim() {
    local ws
    ws="$(new_continuation_workspace)"
    run_terminal_contract_group "$ws" critical-interrupt
}

test_terminal_main_eof_never_admits_inference() {
    local ws mode
    for mode in bootstrap engine notifications; do
        ws="$(new_continuation_workspace)"
        printf '%s' "$mode" > "$ws/main-mode"
        if [ "$mode" != bootstrap ]; then
            (
                export RALPHIE_LIB=1
                # shellcheck source=/dev/null
                source "$ws/ralphie.sh"
                PROJECT_DIR="$ws/project with spaces"
                CONFIG_DIR="$PROJECT_DIR/.ralphie"
                PROJECT_BOOTSTRAP_FILE="$CONFIG_DIR/project-bootstrap.md"
                write_bootstrap_context_file existing \
                    'Improve the existing project with independently checked local changes.' \
                    true true 'Preserve the operator files and remain fully portable.' \
                    'All required acceptance checks pass for the completed objective.' false '' \
                    'Use the existing project architecture.' 'Use the existing portable shell tools.'
            )
        fi
        run_terminal_contract_group "$ws" main-eof
    done
}

test_menu_headless_never_reads_or_accepts_eof_default() {
    local ws
    ws="$(new_continuation_workspace)"
    (
        export RALPHIE_LIB=1
        # shellcheck source=/dev/null
        source "$ws/ralphie.sh"
        set +e
        local status value
        NO_TERMINAL_INPUT=true
        printf 'unconsumed input\n' > "$ws/input"
        exec 3< "$ws/input"
        value="$(prompt_read_line 'Must not prompt' 'chosen default' <&3)"
        [ "$value" = 'chosen default' ] || exit 1
        IFS= read -r value <&3
        [ "$value" = 'unconsumed input' ] || exit 1
        value="$(prompt_yes_no 'Must not prompt' n)"
        status=$?
        [ "$status" -eq 0 ] && [ "$value" = false ] || exit 1
        NO_TERMINAL_INPUT=false
        value="$(prompt_read_line 'Cannot accept a closed input' yes </dev/null)"
        status=$?
        [ "$status" -eq 130 ] && [ -z "$value" ] || exit 1
        INTERRUPT_MENU_ACTIVE=false
        NO_TERMINAL_INPUT=true
        cleanup_resources() { :; }
        handle_interrupt
        exit 99
    ) > "$ws/headless.out" 2>&1 &
    local child=$! status=0
    wait "$child" || status=$?
    [ "$status" -eq 130 ]
    if grep -q 'Action \[' "$ws/headless.out"; then return 1; fi
}

test_bootstrap_changing_alignment_is_bounded_and_preserved() {
    local ws
    ws="$(new_continuation_workspace)"
    (
        export RALPHIE_LIB=1
        # shellcheck source=/dev/null
        source "$ws/ralphie.sh"
        set +e
        PROJECT_DIR="$ws/project with spaces"
        CONFIG_DIR="$PROJECT_DIR/.ralphie"
        PROJECT_BOOTSTRAP_FILE="$CONFIG_DIR/project-bootstrap.md"
        PROJECT_GOALS_FILE="$CONFIG_DIR/project-goals.md"
        CONFIG_FILE="$CONFIG_DIR/config.env"
        REBOOTSTRAP_REQUESTED=true
        local rounds="$ws/alignment-rounds" status round
        printf '0' > "$rounds"
        is_tty_input_available() { return 0; }
        prompt_yes_no() { printf '%s\n' false; }
        prompt_read_line() {
            local count
            count="$(cat "$rounds")"
            printf '%s' "$((count + 1))" > "$rounds"
            printf '%s\n' r
        }
        prompt_optional_line() {
            if [ "$1" = 'Add or correct context before rerun (optional)' ]; then
                printf 'Preserved unique context for round %s.\n' "$(cat "$rounds")"
            else
                printf '%s\n' "${2:-}"
            fi
        }
        ensure_project_bootstrap > "$ws/alignment.out" 2>&1
        status=$?
        [ "$status" -ne 0 ] || exit 1
        [ "$(cat "$rounds")" -eq 12 ] || exit 1
        grep -q '^build_consent: false$' "$PROJECT_BOOTSTRAP_FILE" || exit 1
        for round in $(seq 1 12); do
            grep -Fq -- "Preserved unique context for round $round." "$PROJECT_GOALS_FILE" || exit 1
        done
    )
}

menu_case() {
    local name="$1"
    if [ -n "${MENU_FILTER:-}" ] && [[ "$name" != *"$MENU_FILTER"* ]]; then return 0; fi
    run_case "$name" "$2"
}

main() {
    MENU_FILTER="${1:-}"
    prepare_isolated_target
    trap 'cleanup_isolated_target; cleanup_offline_test_guards' EXIT
    capture_repo_tracked_status_baseline
    menu_case terminal_line_values_and_editing test_terminal_line_values_and_editing
    menu_case terminal_yes_no_and_cancellation test_terminal_yes_no_and_cancellation
    menu_case terminal_multiline_eof_contract test_terminal_multiline_eof_contract
    menu_case terminal_credentials_are_hidden_and_masked test_terminal_credentials_are_hidden_and_masked
    menu_case terminal_interrupt_pause_and_cancel test_terminal_interrupt_pause_and_cancel
    menu_case terminal_colors_respect_destination_and_opt_out test_terminal_colors_respect_destination_and_opt_out
    menu_case terminal_critical_interrupt_never_opens_menu_or_strands_claim test_terminal_critical_interrupt_never_opens_menu_or_strands_claim
    menu_case terminal_main_eof_never_admits_inference test_terminal_main_eof_never_admits_inference
    menu_case menu_headless_never_reads_or_accepts_eof_default test_menu_headless_never_reads_or_accepts_eof_default
    menu_case bootstrap_changing_alignment_is_bounded_and_preserved test_bootstrap_changing_alignment_is_bounded_and_preserved
    info "Menu total: $TOTAL_COUNT | Passed: $PASS_COUNT | Failed: $FAIL_COUNT | Skipped: $SKIP_COUNT"
    [ "$TOTAL_COUNT" -gt 0 ]
    [ "$TOTAL_COUNT" -eq "$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))" ]
    [ "$FAIL_COUNT" -eq 0 ]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
