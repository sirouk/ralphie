# Dependency Research

Date: 2026-02-13
Method: primary-source references first, then local runtime/source alignment.

## 1) OpenAI Codex CLI

Why it matters:

- `ralphie.sh` depends on `codex exec` for non-interactive runs.
- Output artifact behavior and safety flags directly affect loop correctness.

Primary references:

- OpenAI non-interactive docs: https://developers.openai.com/codex/noninteractive
- OpenAI config reference: https://developers.openai.com/codex/config-reference
- Local source refs:
  - `subrepos/codex/codex-rs/exec/src/cli.rs`
  - `subrepos/codex/sdk/typescript/src/exec.ts`

Best-practice implications:

- Keep `--output-last-message` capability checks before use.
- Treat dangerous bypass flags as optional capabilities, not assumptions.
- Keep model override flags isolated to invocation boundary.

## 2) Claude Code CLI

Why it matters:

- `ralphie.sh` uses print/headless mode and optional danger flags for automation.

Primary references:

- Claude CLI reference: https://code.claude.com/docs/en/cli-reference (alias: https://docs.claude.com/en/docs/claude-code/cli-reference)
- Claude settings docs: https://code.claude.com/docs/en/settings (alias: https://docs.claude.com/en/docs/claude-code/settings)
- Local source refs:
  - `subrepos/claude-code/README.md`
  - `subrepos/claude-code/examples/settings/README.md`
  - `subrepos/claude-code/CHANGELOG.md`

Best-practice implications:

- Probe for print mode support and dangerous flag variants at runtime.
- Keep permission/sandbox policy explicit and externally configurable.
- Avoid coupling orchestration logic to one output stream format.

## 3) Bash Runtime Semantics

Why it matters:

- Core orchestrator behavior relies on strict-shell mode, traps, and process checks.

Primary references:

- Bash `set` builtin: https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
- Bash builtins (`trap`): https://www.gnu.org/software/bash/manual/html_node/Bourne-Shell-Builtins.html

Best-practice implications:

- Keep strict mode enabled but isolate commands expected to fail (`|| true`) in controlled paths.
- Use traps for lock release on `EXIT`, `INT`, and `TERM` paths.

## 4) Timeout Semantics

Why it matters:

- Iteration timeouts drive retry/failure logic and reason-code accuracy.

Primary reference:

- GNU coreutils `timeout`: https://www.gnu.org/software/coreutils/manual/html_node/timeout-invocation.html

Best-practice implications:

- Treat exit status `124` as timeout.
- Preserve distinct handling for timeout vs generic command failures.

## 5) Process Liveness and Diagnostics

Why it matters:

- Lock ownership checks and diagnostic metadata rely on process/liveness APIs.

Primary references:

- Linux `kill(2)` semantics (`sig=0` existence check): https://man7.org/linux/man-pages/man2/kill.2.html
- Linux `ps(1)` output formats (`comm`, `args`): https://man7.org/linux/man-pages/man1/ps.1.html

Best-practice implications:

- Keep `kill -0` checks for holder liveness.
- Keep best-effort `ps` output and explicit fallback text when metadata is unavailable.

## 6) Git Submodule/Clone Management

Why it matters:

- Source-map evidence quality depends on up-to-date `subrepos/codex` and `subrepos/claude-code`.

Primary reference:

- Git submodule manual: https://git-scm.com/docs/git-submodule

Best-practice implications:

- Prefer explicit branch/update commands and deterministic initialization.
- Handle already-present repos idempotently.

## 7) GitHub CLI (Optional Queue Source)

Why it matters:

- Optional issue polling can contribute to work discovery.

Primary reference:

- `gh issue list` manual: https://cli.github.com/manual/gh_issue_list

Best-practice implications:

- Keep issue polling optional and guard with auth readiness checks.
- Use explicit state filters to avoid ambiguous backlog signals.

## 8) Lock Primitive Upgrade Candidate

Why it matters:

- Lock correctness depends on atomic lock acquisition; portable primitives are required.

Primary references:

- `flock(1)` (util-linux) manual: https://man7.org/linux/man-pages/man1/flock.1.html
- `flock(2)` system call (advisory file locks): https://man7.org/linux/man-pages/man2/flock.2.html
- `link(2)` system call (atomic hard-link creation): https://man7.org/linux/man-pages/man2/link.2.html
- `mkdir(2)` system call (atomic directory creation primitive): https://man7.org/linux/man-pages/man2/mkdir.2.html
- GNU Bash manual: redirections + `noclobber` behavior (atomic create via O_EXCL): https://www.gnu.org/software/bash/manual/html_node/Redirections.html

Best-practice implications:

- Prefer true atomic acquisition over check-then-write lock files.
- If using `flock`, do not truncate the lock file before the lock is acquired (open with `>>` before locking; truncate/write metadata only after the lock is held) to preserve diagnostics under contention.
- When `flock` is unavailable, prefer an atomic primitive that does not publish partial metadata: write metadata to a temp file, then atomically publish ownership via `link(2)`/`ln` (hard-link) to the canonical lock path; only the winner will succeed.
- Alternatively, use Bash `noclobber` (`set -C`) to atomically create the lock file, but ensure contenders treat missing/partial metadata as "held" (do not delete) to avoid breaking atomicity.
- Current implementation choice: hard-link publish (`ln`) as preferred backend, with `noclobber` fallback; no external `flock` dependency is required.

## 9) Bash Process Substitution And FIFO Logging

Why it matters:

- `ralphie.sh` previously used Bash process substitution (`>(...)` / `< <(...)`) for session logging and some loop helpers.
- Some sandboxed shells disallow process substitution, causing hard failures.

Primary references:

- GNU Bash manual: process substitution (portability notes and semantics): https://www.gnu.org/software/bash/manual/html_node/Process-Substitution.html
- GNU coreutils manual: `mkfifo` (named pipes/FIFO): https://www.gnu.org/software/coreutils/manual/html_node/mkfifo-invocation.html

Best-practice implications:

- Prefer explicit FIFO (`mkfifo`) + `tee` patterns when process substitution is not guaranteed.
- Keep stdin unchanged for interactive prompts; only redirect stdout/stderr.
- Add focused tests that exercise the chosen logging mechanism in restricted shells.
- Current implementation choice: FIFO-based session logging plus pipeline-based Claude stdout/stderr separation; no process substitution remains.

## Uncertainty Notes

- Claude Code CLI options evolve quickly; periodic runtime `--help` probes remain necessary.
- Hard-link support and `mkfifo` availability may vary by environment; fallbacks and explicit disablement paths remain necessary.
