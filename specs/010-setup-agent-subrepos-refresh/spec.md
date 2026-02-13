# 010 - Setup-Agent-Subrepos Refresh And Partial-Init Repair

## Context

`scripts/setup-agent-subrepos.sh` is responsible for ensuring local evidence sources exist under `subrepos/` and that the source maps in `maps/` are present and up-to-date.

This surface is integration-heavy:

- It invokes `git` for submodule or clone workflows.
- It may require network access to fetch/update the upstream repos.
- It must be robust to partially-initialized directories (for example, a `subrepos/<name>/.git` file that points at a missing gitdir).

## Requirements

- The script must handle "partial init" states deterministically:
  - detect invalid git work trees under `subrepos/`
  - repair them (either by re-initializing submodules or re-cloning, depending on mode)
  - avoid leaving the repo in a broken half-state
- Map output (`maps/agent-source-map.yaml`) must remain repo-relative (no absolute workstation paths).
- A test harness must exist that exercises core decision logic without requiring network access.

## Acceptance Criteria (Testable)

1. In a temporary repo, a "partial init" `subrepos/codex` directory is repaired without manual intervention.
2. In a temporary repo, a "partial init" `subrepos/claude-code` directory is repaired without manual intervention.
3. A deterministic test mode exists (e.g. `--dry-run` or mocked `git` in `PATH`) that does not perform network operations.
4. When the script emits a map file, it contains repo-relative paths for `local_path` and `key_paths`.
5. Failures emit clear `[error] ...` output and a non-zero exit code.
6. `bash tests/ralphie_shell_tests.sh` passes end-to-end.

## Verification Steps

1. Implement a test harness that runs `scripts/setup-agent-subrepos.sh` in a temp repo with mocked `git`.
2. Add fixtures for partial-init `.git` file states.
3. Run `bash tests/ralphie_shell_tests.sh`.

## Status: COMPLETE
