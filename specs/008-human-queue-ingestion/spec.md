# 008 - Human Queue Ingestion And Prompt Injection

## Context

`ralphie.sh` supports a human priority queue file (`HUMAN_INSTRUCTIONS.md`) that can be created via `./ralphie.sh --human`.

When the file exists:

- Work discovery should treat `Status: NEW` entries as highest-priority candidate work.
- Prompt augmentation should include the queue contents so the active agent can process one request at a time.

## Requirements

- Pending human requests must be detected case-insensitively and tolerate extra whitespace.
- Work discovery must mark "has human work" when at least one `Status: NEW` entry exists.
- Prompt augmentation must include the human-queue section and embed the queue contents when the file exists.
- Non-interactive `--human` must fail deterministically with a reason code (no blocking prompts).

## Acceptance Criteria (Testable)

1. `count_pending_human_requests` returns `0` when `HUMAN_INSTRUCTIONS.md` is missing.
2. `count_pending_human_requests` counts `Status: NEW` entries case-insensitively (e.g. `status: new`, `STATUS: NEW`).
3. `check_human_requests` sets `HAS_HUMAN_REQUESTS=true` when at least one pending request exists.
4. `plan_prompt_for_iteration` injects a "Human Priority Queue" section and includes the queue contents when the file exists.
5. `plan_prompt_for_iteration` does not inject the human section when the file is missing.
6. `capture_human_priorities` returns non-zero in non-interactive mode and logs `reason_code=RB_HUMAN_MODE_NON_INTERACTIVE`.
7. `bash tests/ralphie_shell_tests.sh` passes end-to-end.

## Verification Steps

1. Add shell tests that create a temporary `HUMAN_INSTRUCTIONS.md` with mixed-case status fields.
2. Run `bash tests/ralphie_shell_tests.sh`.

## Status: COMPLETE
