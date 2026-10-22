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

The September supervisor chat, companion, named-mission features and simplified
execution loop are not part of this continuation.
