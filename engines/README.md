# Engines Research Workspace

This directory stores scripts and supporting context used by the Ralphie
maintenance process when evaluating how external agents work.

## Purpose

- `setup-agent-subrepos.sh` installs and snapshots upstream Codex and Claude Code
  repositories.
- The snapshots are used as **reference material only** for command and behavior
  comparisons.
- They are not a runtime dependency of `ralphie.sh`.

## Working Dogfood

When iterating on Ralphie itself, the loop should continue to use
`ralphie.sh` as the active orchestrator and evaluate itself with the same gates,
consensus, and completion logic.

## Guidance

- Keep generated research artifacts in `research/` and `specs/` portable.
- Keep prompt outputs and generated markdown free of local paths and raw transcript
  noise.
- Use `engines/setup-agent-subrepos.sh` only for comparative work, not for normal
  production deployment.
