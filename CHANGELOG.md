# Changelog

## Unreleased — May autonomy continuation

This branch continues commit `e1c7d15` from May 26, 2026. It retains PLAN,
BUILD, TEST, REFACTOR, LINT and DOCUMENT, scored consensus review, adaptive
phase routing, plan freshness checks and interruption recovery.

- Add Prime Agent alongside Codex and Claude for phase execution, handoff and
  consensus. Automatic selection prefers Prime; explicit engine choices remain
  authoritative. Prime provider, model and thinking overrides are explicit.
- Add a project target and unattended objective/document intake. A changed seed
  cannot silently resume another mission. Planning-only work has an explicit
  completion boundary without claiming that the project is done.
  Git targets must be repository roots so path ownership and commits share the
  same boundary.
- Run project checks independently of reviewer prose and preserve selected gate
  definitions across workers and reviewers. Red checks cannot be outvoted.
  Checks that change HEAD or nonignored project files cannot certify that tree.
- Report failed or incomplete lifecycle runs with a nonzero exit status.
- Preserve operator work when committing phase changes, including filenames
  that contain spaces, non-ASCII bytes or newlines. Verify required saves before
  advancing a phase.
- Avoid silence timeouts for buffered print-mode engines. Retain elapsed-time
  bounds, portable descendant cleanup and bounded engine output.
- Count reviewer, retry and paid engine-health inference in session budgets.
  Refuse new attempts before exceeding the attempt cap, and serialize budgeted
  consensus admission.
- Make self-update opt-in and use an operator-controlled source rather than the
  managed project's Git remote.
- Make the test runner offline by default, protect it from real engine calls,
  and detect assertions hidden by later successful commands.
- Refuse corrupt existing resume state and unsafe owned runtime paths instead
  of resetting budgets or following aliases. Serialize stale-lock admission.
- Isolate automatic Git saves from the operator's index and disable hooks for
  those saves. Refuse pending Git operations rather than consume their history.
  Include modes, index entries and submodule worktrees in checks.
- Preserve environment precedence across configuration aliases, validate
  effective numeric and boolean settings, round estimated request cost upward, and bound free
  engine probes and paid readiness output. Permanent credential failures stop
  retries without retaining the credential text.
- Honor same-phase routes and consent on every development dispatch. Reject
  malformed reviews, retain usable HOLD feedback, and require actual ordered
  phase passes and a persistent raw-tree witness for no-work handoff.
- Stage updates beside the installed file, use unique backups, preserve the
  invocation directory/interpreter, and bound downloads. Stream installation
  validates its input and refuses aliased or non-file destinations.
- Escape all JSON control bytes, keep Telegram discovery output parseable, and
  reject TTS HTTP errors so text fallback remains available.

The September supervisor chat, companion, named-mission features and simplified
execution loop are not part of this continuation.
