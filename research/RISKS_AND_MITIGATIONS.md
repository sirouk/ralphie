# Risks And Mitigations

Date: 2026-02-13

## Risk Register

1. Non-atomic lock acquisition race can allow concurrent runs.
- Severity: High
- Evidence (prior): `acquire_lock` used check-then-write lock behavior, which can race under simultaneous starts.
- Mitigation: implement atomic lock acquisition (preferred backend: hard-link publish via `ln`, with `noclobber` fallback) and preserve deterministic reason codes/diagnostics.
- Validation: concurrent-start race fixture proves single-owner behavior; backend-fallback fixture proves atomic fallback still acquires.
- Status: Mitigated (spec `005` COMPLETE; shell test suite includes atomic race + backend fallback).

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
- Evidence (prior): limited fixtures for `capture_human_priorities` and external notify channel behavior.
- Mitigation: add bounded fixtures for queue parsing and notification dispatch failures (specs `008` and `009`).
- Validation: shell tests cover `Status: NEW` parsing, prompt injection, non-interactive capture reason code, and notify channel failure modes without leaking secrets.
- Status: Mitigated (specs `008` and `009` COMPLETE; shell tests cover the contract).

5. Subrepo setup and map refresh script is integration-heavy and lightly tested.
- Severity: Medium
- Evidence (prior): `scripts/setup-agent-subrepos.sh` performed git/network operations and map generation without automated regression coverage in this repo.
- Mitigation: add a deterministic harness using mocked `git` in `PATH` and implement partial-init repair behavior (spec `010`).
- Validation: shell tests run the setup script in an isolated temp repo, repair partial-init `.git` file states, and assert map output stays repo-relative.
- Status: Mitigated (spec `010` COMPLETE; deterministic harness added).

6. Bash process substitution is blocked in some sandboxed shells, breaking core execution paths.
- Severity: High
- Evidence (prior): `ralphie.sh` relied on Bash process substitution for session logging and stream capture; this can fail in environments where process substitution is blocked.
- Mitigation: replace `>(...)` with FIFO/pipeline-based logging and add focused regression tests (spec `006`).
- Validation: `bash tests/ralphie_shell_tests.sh` passes end-to-end; `ralphie.sh` contains no `> >(...)` or `< <(...)` process substitution.
- Status: Mitigated (spec `006` COMPLETE; session logging fixture added).

7. Self-heal/self-improvement logging can leak absolute paths into markdown artifacts.
- Severity: High
- Evidence (prior): `ralphie.sh:self_heal_codex_reasoning_effort_xhigh` appended an unredacted `- Backup: $backup_file` entry to `research/SELF_IMPROVEMENT_LOG.md`; `$backup_file` is under `$HOME`, which violates the markdown privacy guard.
- Mitigation: redact paths before writing to markdown artifacts and add a focused regression test that simulates self-heal and asserts `markdown_artifacts_are_clean` remains true (spec `007`).
- Validation: new test passes; `research/SELF_IMPROVEMENT_LOG.md` contains no expanded home-directory absolute paths or local usernames.
- Status: Mitigated (spec `007` COMPLETE; focused self-heal redaction fixture added).

## Residual Risk

After closing specs `005`-`010`, the largest remaining risks are medium-severity: YAML fallback-order parsing brittleness, ongoing CLI capability drift, and limited focused coverage for prompt artifact generation policy (`S10`).
