# 006 - Remove Process Substitution For Sandbox Portability

## Context

`ralphie.sh` previously relied on Bash process substitution (`>(...)` and `< <(...)`) in core paths such as:

- Session log capture (teeing orchestrator output while still printing to terminal)
- Loop helpers that fed `while read ...` via `< <(...)`

Some sandboxed shells block process substitution, causing `ralphie.sh` execution and the shell test suite to fail in those environments.

## Requirements

- Eliminate reliance on process substitution (`>(...)`, `<(...)`, and `< <(...)`) in `ralphie.sh`.
- Preserve current logging and output-separation behavior.
- Session log captures all orchestrator output while still printing to the terminal.
- Claude stdout is written to the output artifact without stderr noise.
- Runtime stderr remains available in the log artifact.
- Keep behavior engine-neutral and compatible with strict bash mode (`set -euo pipefail`).

## Acceptance Criteria (Testable)

1. `rg -n '>\\s*>\\(' ralphie.sh` returns no matches (no process substitution remains).
2. `rg -n '<\\s*<\\(' ralphie.sh` returns no matches (no process substitution remains).
3. `bash tests/ralphie_shell_tests.sh` completes successfully in this environment.
4. `test_claude_output_log_separation` passes without relying on process substitution.
5. A focused shell test exercises the session-log mechanism and proves it writes to a log file without using process substitution.
6. No new local identity/path leakage is introduced into markdown artifacts or loop outputs.

## Verification Steps

1. Run `bash tests/ralphie_shell_tests.sh`.
2. Run `rg -n '>\\s*>\\(' ralphie.sh` and confirm zero results.
3. Run `rg -n '<\\s*<\\(' ralphie.sh` and confirm zero results.
4. Run the focused session-log test added in this spec.
5. (Optional) Smoke `./ralphie.sh --doctor` to ensure diagnostics still work.

## Status: COMPLETE
