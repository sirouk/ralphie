# 009 - Notification Channels Contract (notify_human)

## Context

`ralphie.sh` can notify a human at key escalation points (approval required, plan completion, etc.) via `notify_human`.

Supported channels:

- `none`
- `terminal`
- `telegram`
- `discord`

## Requirements

- Channel selection must be case-insensitive.
- `none` must be a no-op that returns success.
- `terminal` must emit messages to stderr via the existing `warn` function and return success.
- `telegram` and `discord` must fail deterministically (non-zero exit) when required env vars are missing or `curl` is unavailable.
- Failures must not leak secrets (tokens/webhook URLs) into logs.

## Acceptance Criteria (Testable)

1. `HUMAN_NOTIFY_CHANNEL=none` causes `notify_human` to return `0`.
2. `HUMAN_NOTIFY_CHANNEL=terminal` causes `notify_human` to return `0` and emit the title (and body when provided).
3. `HUMAN_NOTIFY_CHANNEL=telegram` returns non-zero when `TELEGRAM_BOT_TOKEN` or `TELEGRAM_CHAT_ID` is missing.
4. `HUMAN_NOTIFY_CHANNEL=discord` returns non-zero when `DISCORD_WEBHOOK_URL` is missing.
5. When `curl` is missing from `PATH`, both `telegram` and `discord` return non-zero with a deterministic warning.
6. A mocked `curl` that fails causes `notify_human` to return non-zero and emit a failure warning.
7. Test output must not contain the raw values of `TELEGRAM_BOT_TOKEN` or `DISCORD_WEBHOOK_URL` (even on failures).
8. `bash tests/ralphie_shell_tests.sh` passes end-to-end.

## Verification Steps

1. Add shell tests with a mocked `curl` in `PATH` to simulate success/failure without network access.
2. Run `bash tests/ralphie_shell_tests.sh`.

## Status: COMPLETE
