# Risks And Mitigations

Date: 2026-02-13

## Risk Register

1. Non-atomic lock acquisition race can allow concurrent runs.
- Severity: High
- Evidence: `acquire_lock` uses lock-file existence checks followed by file write, without atomic acquisition primitive.
- Mitigation: implement atomic lock backend strategy (preferred: `flock`, with atomic fallback backend).
- Validation: add concurrent-start race tests proving single-owner behavior.

2. CLI capability drift can break invocation flags.
- Severity: Medium
- Evidence: external CLI contracts evolve (`codex exec`, `claude` print/safety flags).
- Mitigation: preserve runtime capability probing and deterministic fallback reason codes.
- Validation: shell tests for supported/unsupported flag probe paths.

3. Fallback-order YAML parsing is brittle to structural changes.
- Severity: Medium
- Evidence: `mode_fallback_order` parses YAML with line-pattern matching rather than a YAML parser.
- Mitigation: constrain map format assumptions and add parser regression tests around malformed input.
- Validation: tests for default fallback when map parsing fails.

4. Human queue + notification paths have limited test coverage.
- Severity: Medium
- Evidence: no dedicated fixtures for `capture_human_priorities` and external notify channel behavior.
- Mitigation: add bounded fixtures for queue parsing and notification dispatch failures.
- Validation: shell tests for `Status: NEW` parsing and notify channel fallback behavior.

5. Subrepo setup and map refresh script is integration-heavy and lightly tested.
- Severity: Medium
- Evidence: `scripts/setup-agent-subrepos.sh` performs git/network operations and map generation without current automated tests in this repo. In this workspace, `subrepos/*` appear present but `git -C subrepos/<name>` fails due to missing submodule gitdir targets, which is a realistic "partially-initialized submodule" failure mode the script should handle.
- Mitigation: add dry-run/smoke checks with mocked git commands or scoped integration harness.
- Validation: deterministic script tests in isolated temp repos.

6. Bash process substitution is blocked in some sandboxed shells, breaking core execution paths.
- Severity: High
- Evidence: `ralphie.sh` uses `>(...)` for session logging and Claude output capture; this can fail in environments without `/dev/fd` support or where process substitution is blocked.
- Mitigation: replace `>(...)` with FIFO/pipeline-based logging and add focused regression tests (spec `006`).
- Validation: `bash tests/ralphie_shell_tests.sh` passes end-to-end and `ralphie.sh` contains no process substitution.

7. Self-heal/self-improvement logging can leak absolute paths into markdown artifacts.
- Severity: High
- Evidence: `ralphie.sh:self_heal_codex_reasoning_effort_xhigh` appends `- Backup: $backup_file` to `research/SELF_IMPROVEMENT_LOG.md`; `$backup_file` is under `$HOME`, which violates the markdown privacy guard.
- Mitigation: redact paths before writing to markdown artifacts and add a focused regression test that simulates self-heal and asserts `markdown_artifacts_are_clean` remains true (spec `007`).
- Validation: new test passes; `research/SELF_IMPROVEMENT_LOG.md` contains no expanded home-directory absolute paths or local usernames.

## Residual Risk

After implementing spec `005` and tightening markdown privacy compliance (spec `007`), the largest remaining risks shift to portability hardening (spec `006`), setup-script integration, and optional human-interaction paths.
