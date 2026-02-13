# 007 - Redact Paths In Markdown Artifacts (Self-Improvement Log)

## Context

`ralphie.sh` enforces a markdown privacy gate (`markdown_artifacts_are_clean`) that fails build readiness when markdown artifacts contain:

- home-directory absolute paths (for example, expanded `$HOME` paths)
- local usernames
- tool transcript leakage patterns

The self-heal path `self_heal_codex_reasoning_effort_xhigh` currently appends `- Backup: $backup_file` to `research/SELF_IMPROVEMENT_LOG.md`. `$backup_file` is under `$HOME` and can violate the markdown privacy gate.

## Requirements

- Self-heal/self-improvement logging must never write absolute workstation paths or local usernames into markdown artifacts under `research/` or `specs/`.
- Path strings written to markdown must be redacted using existing display helpers (e.g. `path_for_display`) or equivalent logic.
- The fix must be engine-neutral and must not weaken the markdown privacy gate.

## Acceptance Criteria (Testable)

1. Triggering the self-heal path does not introduce local identity/path leakage in `research/SELF_IMPROVEMENT_LOG.md`.
2. `markdown_artifacts_are_clean` returns success after a self-heal log append.
3. The logged backup path is redacted (e.g. uses `~` instead of the full `$HOME` path).
4. `bash tests/ralphie_shell_tests.sh` passes end-to-end.

## Verification Steps

1. Add a focused shell test that runs `self_heal_codex_reasoning_effort_xhigh` in a temp `$HOME`.
2. Assert `research/SELF_IMPROVEMENT_LOG.md` does not match the privacy leakage patterns.
3. Assert `markdown_artifacts_are_clean` returns success.
4. Run `bash tests/ralphie_shell_tests.sh`.

## Status: INCOMPLETE
