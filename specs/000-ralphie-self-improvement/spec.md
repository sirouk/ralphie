# 000 - Map-Guided Ralphie Self-Improvement

## Context

This repository includes map-based guidance for improving `ralphie.sh`:
- `maps/agent-source-map.yaml`
- `maps/binary-steering-map.yaml`

## Requirements

- Improve `ralphie.sh` with evidence from both Codex and Claude sources.
- Preserve portability when either CLI is unavailable.
- Avoid provider-specific overfitting.
- Record hypotheses and outcomes in `research/SELF_IMPROVEMENT_LOG.md`.

## Acceptance Criteria (Testable)

1. At least one reliability or observability improvement is implemented in `ralphie.sh`.
2. Every engine-specific behavior change has an explicit fallback path for the other engine.
3. A map-guided evidence note cites both source families:
- one from `subrepos/codex/*`
- one from `subrepos/claude-code/*`
4. `research/SELF_IMPROVEMENT_LOG.md` contains:
- hypothesis
- change decision (accepted/rejected)
- observed result or expected validation step
5. A reviewer can run `./ralphie.sh --doctor` and confirm both map files are detected.

## Verification Steps

1. Run `./ralphie.sh --doctor` and verify map presence lines are `yes`.
2. Run targeted tests/smoke checks for changed reliability/parity behavior.
3. Inspect `research/SELF_IMPROVEMENT_LOG.md` for required entry fields.

## Status: COMPLETE
