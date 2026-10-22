#!/usr/bin/env bash
# Test-only guards: a missed fixture must fail instead of spending or networking.
OFFLINE_TEST_GUARD_OWNER=false
OFFLINE_TEST_ORIGINAL_PATH="$PATH"

prepare_offline_test_guards() {
    if [ -n "${RALPHIE_TEST_GUARD_DIR:-}" ] && [ -x "$RALPHIE_TEST_GUARD_DIR/prime-agent" ]; then
        PATH="$RALPHIE_TEST_GUARD_DIR:$PATH"
        export PATH
        return 0
    fi
    RALPHIE_TEST_GUARD_DIR="$(mktemp -d /tmp/ralphie-offline-guards.XXXXXX)" || return 1
    OFFLINE_TEST_GUARD_OWNER=true
    local name
    for name in prime-agent codex claude curl wget; do
        cat > "$RALPHIE_TEST_GUARD_DIR/$name" <<'EOF_GUARD'
#!/usr/bin/env bash
case "${0##*/}:${1:-}" in
    prime-agent:--version|codex:--version|claude:--version)
        printf 'offline-test-mock 999.0.0\n'
        exit 0
        ;;
    prime-agent:--help|codex:--help|claude:--help)
        printf '%s\n' 'Offline test guard; configure a fixture to run inference.'
        exit 0
        ;;
esac
printf 'OFFLINE GUARD: unmocked %s invocation refused\n' "${0##*/}" >&2
exit 97
EOF_GUARD
        chmod +x "$RALPHIE_TEST_GUARD_DIR/$name"
    done
    PATH="$RALPHIE_TEST_GUARD_DIR:$PATH"
    export PATH RALPHIE_TEST_GUARD_DIR
    return 0
}

cleanup_offline_test_guards() {
    if [ "$OFFLINE_TEST_GUARD_OWNER" = true ] && [ -n "${RALPHIE_TEST_GUARD_DIR:-}" ]; then
        rm -rf "$RALPHIE_TEST_GUARD_DIR"
    fi
    return 0
}

leave_offline_test_guards() {
    PATH="$OFFLINE_TEST_ORIGINAL_PATH"
    export PATH
    cleanup_offline_test_guards
    unset RALPHIE_TEST_GUARD_DIR
}
