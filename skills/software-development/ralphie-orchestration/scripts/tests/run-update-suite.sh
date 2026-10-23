#!/usr/bin/env bash
# Offline component tests. curl is always shadowed; no installed skill is touched.
set -u
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
SKILL_DIR="$(cd -P "$SCRIPT_DIR/../.." && pwd)" || exit 1
REPO="$(cd -P "$SKILL_DIR/../../.." && pwd)" || exit 1
HELPER="$SKILL_DIR/scripts/update_skill.sh"
SUBDIR=skills/software-development/ralphie-orchestration
T="$(mktemp -d "${TMPDIR:-/tmp}/ralphie-skill-test.XXXXXX")" || exit 1
T="$(cd -P "$T" && pwd)" || exit 1
trap 'rm -rf "$T"' EXIT
mkdir "$T/bin" "$T/upstream" || exit 1
export FIXTURE_ROOT="$T/upstream" CURL_RECEIPT="$T/curl.receipt"
: > "$CURL_RECEIPT"
export PATH="$T/bin:$PATH"
cat > "$T/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$CURL_RECEIPT"
[ ! -f "$FIXTURE_ROOT/offline" ] || exit 7
output=''; url=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) output="$2"; shift 2;;
        --proto|--proto-redir|--connect-timeout|--max-time|--max-filesize) shift 2;;
        --fail|--silent|--show-error|--location) shift;;
        https://*) url="$1"; shift;;
        *) exit 90;;
    esac
done
case "$url" in
    https://api.github.com/repos/sirouk/ralphie/commits/main)
        sha="$(cat "$FIXTURE_ROOT/current")"
        printf '{\n  "sha": "%s",\n  "parents": []\n}\n' "$sha" > "$output";;
    https://raw.githubusercontent.com/sirouk/ralphie/*)
        tail="${url#https://raw.githubusercontent.com/sirouk/ralphie/}"
        [ -f "$FIXTURE_ROOT/$tail" ] || exit 22
        cp "$FIXTURE_ROOT/$tail" "$output";;
    *) exit 91;;
esac
MOCK
chmod +x "$T/bin/curl" || exit 1
A=0000000000000000000000000000000000000001
B=0000000000000000000000000000000000000002
C=0000000000000000000000000000000000000003
D=0000000000000000000000000000000000000004
FILES=(ralphie.sh "$SUBDIR/SKILL.md" "$SUBDIR/agents/openai.yaml" "$SUBDIR/scripts/update_skill.sh" "$SUBDIR/references/supervising.md" "$SUBDIR/references/development.md")
for sha in "$A" "$B" "$C" "$D"; do
    for file in "${FILES[@]}"; do
        mkdir -p "$T/upstream/$sha/$(dirname "$file")" || exit 1
        cp "$REPO/$file" "$T/upstream/$sha/$file" || exit 1
    done
done
printf '\n# second-revision-runtime\n' >> "$T/upstream/$B/ralphie.sh"
printf '\nSecond revision guide.\n' >> "$T/upstream/$B/$SUBDIR/SKILL.md"
printf '\nif then\n' >> "$T/upstream/$C/$SUBDIR/scripts/update_skill.sh"
rm "$T/upstream/$D/$SUBDIR/references/supervising.md" || exit 1
# A downloaded program must never execute during install or update.
printf '\nprintf "unsafe candidate executed" > "%s"\n' "$T/payload-executed" >> "$T/upstream/$B/ralphie.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
has() { grep -Fq -- "$2" "$1" || fail "Missing [$2] in $1"; }
absent() {
    if [ -e "$1" ] || [ -L "$1" ]; then
        fail "Unexpected path $1"
    fi
}
install_a() {
    local parent="$1"
    mkdir "$parent" || fail 'fixture parent'
    printf '%s\n' "$A" > "$T/upstream/current"
    /bin/bash "$HELPER" --install "$parent/ralphie-orchestration" > "$parent/install.log" 2>&1 || fail "install: $(cat "$parent/install.log")"
    [ -L "$parent/ralphie-orchestration" ] || fail 'not a managed link'
}
case_switch_and_pin() {
    local parent="$T/switch with spaces" old new
    install_a "$parent"
    old="$(readlink "$parent/ralphie-orchestration")" || fail readlink
    has "$parent/install.log" "REVISION=$A"
    printf '%s\n' "$B" > "$T/upstream/current"
    /bin/bash "$parent/ralphie-orchestration/scripts/update_skill.sh" --check > "$parent/check.log" 2>&1 || fail check
    has "$parent/check.log" UPDATE_AVAILABLE
    [ "$(readlink "$parent/ralphie-orchestration")" = "$old" ] || fail 'check mutated link'
    /bin/bash "$parent/ralphie-orchestration/scripts/update_skill.sh" --apply > "$parent/update.log" 2>&1 || fail "update: $(cat "$parent/update.log")"
    new="$(readlink "$parent/ralphie-orchestration")" || fail readlink
    [ "$old" != "$new" ] || fail 'link did not switch'
    has "$parent/update.log" "REVISION=$B"
    has "$new/SKILL.md" 'Second revision guide.'
    has "$new/../../../ralphie.sh" second-revision-runtime
    if grep -Fq -- second-revision-runtime "$old/../../../ralphie.sh"; then fail 'old runtime mutated'; fi
    if grep -Fq -- 'Second revision guide.' "$old/SKILL.md"; then fail 'old guide mutated'; fi
    RALPHIE_SKIP_AUTO_UPDATE=1 /bin/bash "$old/../../../ralphie.sh" --help > "$parent/old-help.log" 2>&1 || fail 'retained runtime unusable'
    has "$parent/old-help.log" --objective
    /bin/bash "$old/scripts/update_skill.sh" --apply > "$parent/old-guide.log" 2>&1 || fail 'old helper reconnect'
    has "$parent/old-guide.log" SUPERSEDED
    has "$parent/old-guide.log" "REVISION=$B"
    absent "$T/payload-executed"
    absent "$parent/.ralphie-orchestration.revisions/.update.lock"
}
case_dirty_refusal() {
    local parent="$T/dirty" old
    install_a "$parent"
    old="$(readlink "$parent/ralphie-orchestration")"
    printf '\nlocal unpublished edits\n' >> "$old/SKILL.md"
    printf '%s\n' "$B" > "$T/upstream/current"
    if /bin/bash "$parent/ralphie-orchestration/scripts/update_skill.sh" --apply > "$parent/update.log" 2>&1; then fail 'dirty install accepted'; fi
    has "$parent/update.log" LOCAL_CHANGED
    has "$old/SKILL.md" 'local unpublished edits'
    [ "$(readlink "$parent/ralphie-orchestration")" = "$old" ] || fail 'dirty link changed'
}
case_bad_payloads() {
    local parent="$T/bad" old sha
    install_a "$parent"
    old="$(readlink "$parent/ralphie-orchestration")"
    for sha in "$C" "$D"; do
        printf '%s\n' "$sha" > "$T/upstream/current"
        if /bin/bash "$parent/ralphie-orchestration/scripts/update_skill.sh" --apply > "$parent/$sha.log" 2>&1; then fail "bad payload accepted $sha"; fi
        [ "$(readlink "$parent/ralphie-orchestration")" = "$old" ] || fail 'bad update changed link'
        absent "$parent/.ralphie-orchestration.revisions/$sha"
        absent "$parent/.ralphie-orchestration.revisions/.update.lock"
    done
    has "$parent/$C.log" 'shell syntax is invalid'
    has "$parent/$D.log" 'Incomplete update payload'
    # Metadata edits are dirty too, including source trust changes.
    sed 's/source=sirouk\/ralphie/source=other\/repository/' "$old/../../../.ralphie-skill-install" > "$T/meta"
    cp "$T/meta" "$old/../../../.ralphie-skill-install" || fail metadata
    if /bin/bash "$parent/ralphie-orchestration/scripts/update_skill.sh" --apply > "$parent/meta.log" 2>&1; then fail 'changed source accepted'; fi
    has "$parent/meta.log" LOCAL_CHANGED
}
case_offline_and_refusals() {
    local parent="$T/offline" old tool resolved
    install_a "$parent"
    old="$(readlink "$parent/ralphie-orchestration")"
    : > "$T/upstream/offline"
    /bin/bash "$parent/ralphie-orchestration/scripts/update_skill.sh" --apply > "$parent/offline.log" 2>&1 || fail offline
    rm "$T/upstream/offline"
    has "$parent/offline.log" OFFLINE
    has "$parent/offline.log" "REVISION=$A"
    [ "$(readlink "$parent/ralphie-orchestration")" = "$old" ] || fail 'offline changed link'
    # No curl on a private PATH must retain the verified runtime explicitly.
    mkdir "$T/no-curl" || fail fixture
    for tool in git dirname basename find tr wc cat mkdir rmdir rm readlink mktemp grep sed awk; do
        resolved="$(command -v "$tool")" || fail "required test utility $tool"
        ln -s "$resolved" "$T/no-curl/$tool" || fail 'minimal PATH'
    done
    PATH="$T/no-curl" /bin/bash "$parent/ralphie-orchestration/scripts/update_skill.sh" --apply > "$parent/no-curl.log" 2>&1 || fail 'missing curl broke retained runtime'
    has "$parent/no-curl.log" 'curl is unavailable'
    has "$parent/no-curl.log" OFFLINE
    if /bin/bash "$HELPER" --install "$parent/ralphie-orchestration" > "$parent/exists.log" 2>&1; then fail 'adopted existing path'; fi
    has "$parent/exists.log" 'Destination already exists'
    mkdir "$T/outside" "$T/alias" || fail fixture
    printf 'operator sentinel\n' > "$T/outside/sentinel"
    ln -s "$T/outside" "$T/alias/.ralphie-orchestration.revisions" || fail alias
    if /bin/bash "$HELPER" --install "$T/alias/ralphie-orchestration" > "$parent/alias.log" 2>&1; then fail 'aliased store accepted'; fi
    has "$T/outside/sentinel" 'operator sentinel'
    [ "$(find "$T/outside" -type f | wc -l)" -eq 1 ] || fail 'wrote outside store'
    absent "$T/alias/ralphie-orchestration"
}
case_failed_switch_restores_link() {
    local parent="$T/rollback" old real_mv
    install_a "$parent"
    old="$(readlink "$parent/ralphie-orchestration")"
    real_mv="$(command -v mv)"
    cat > "$T/bin/mv" <<MOCK
#!/usr/bin/env bash
for arg in "\$@"; do
    case "\$arg" in */.ralphie-orchestration.link.*/skill) exit 42;; esac
done
exec "$real_mv" "\$@"
MOCK
    chmod +x "$T/bin/mv" || fail mock
    printf '%s\n' "$B" > "$T/upstream/current"
    if /bin/bash "$parent/ralphie-orchestration/scripts/update_skill.sh" --apply > "$parent/update.log" 2>&1; then fail 'failed switch accepted'; fi
    rm "$T/bin/mv"
    has "$parent/update.log" 'current link retained'
    [ "$(readlink "$parent/ralphie-orchestration")" = "$old" ] || fail 'failed switch lost old link'
    has "$old/SKILL.md" 'Ralphie Orchestration'
    absent "$parent/.ralphie-orchestration.revisions/.update.lock"
    # Kill immediately before/after publication; there is no unlinked interval; old mission paths remain usable in either outcome.
    local timing killed_parent expected result
    for timing in before after; do
        killed_parent="$T/killed-$timing"
        install_a "$killed_parent"
        old="$(readlink "$killed_parent/ralphie-orchestration")"
        cat > "$T/bin/mv" <<MOCK
#!/usr/bin/env bash
for arg in "\$@"; do
    case "\$arg" in */.ralphie-orchestration.link.*/skill)
        if [ "$timing" = after ]; then "$real_mv" "\$@" || exit 41; fi
        kill -KILL "\$PPID"
        exit 0;;
    esac
done
exec "$real_mv" "\$@"
MOCK
        chmod +x "$T/bin/mv" || fail mock
        printf '%s\n' "$B" > "$T/upstream/current"
        if /bin/bash "$killed_parent/ralphie-orchestration/scripts/update_skill.sh" --apply > "$killed_parent/kill.log" 2>&1; then
            fail 'SIGKILL fixture returned success'
        else
            result=$?
        fi
        rm "$T/bin/mv" || fail 'remove kill wrapper'
        [ "$result" -eq 137 ] || fail "helper was not SIGKILLed ($result)"
        expected="$A"; [ "$timing" != after ] || expected="$B"
        [ "$(readlink "$killed_parent/ralphie-orchestration")" = "$killed_parent/.ralphie-orchestration.revisions/$expected/$SUBDIR" ] || fail "lost old-or-new link on $timing kill"
        has "$old/SKILL.md" 'Ralphie Orchestration'
        RALPHIE_SKIP_AUTO_UPDATE=1 /bin/bash "$old/../../../ralphie.sh" --help > "$killed_parent/old-help.log" 2>&1 || fail 'killed update broke pinned runtime'
    done
}
case_development_and_pinned_startup() {
    local before after
    before="$(wc -l < "$CURL_RECEIPT")"
    # A local unpublished checkout is usable without installing or fetching.
    mkdir "$T/development" || fail fixture
    cp -R "$T/upstream/$A/." "$T/development/" || fail fixture
    git -c init.templateDir= -C "$T/development" init -q || fail 'development git init'
    git -C "$T/development" add . || fail 'development baseline'
    git -C "$T/development" -c core.hooksPath=/dev/null -c commit.gpgsign=false -c user.name=SkillTest -c user.email=skill@example.invalid commit -qm baseline || fail 'development baseline'
    printf '\nunpublished local guide\n' >> "$T/development/$SUBDIR/SKILL.md"
    /bin/bash "$T/development/$SUBDIR/scripts/update_skill.sh" --apply > "$T/development.log" 2>&1 || fail development
    has "$T/development.log" 'DEVELOPMENT dirty=true'
    has "$T/development.log" "RUNTIME_PATH=$T/development/ralphie.sh"
    has "$T/development/$SUBDIR/SKILL.md" 'unpublished local guide'
    after="$(wc -l < "$CURL_RECEIPT")"
    [ "$before" -eq "$after" ] || fail 'development fetched remote'
    # Exercise the actual runtime startup updater seam with operator opt-in.
    /bin/bash -c '
        source "$1"
        self_update_transaction() { printf "UNEXPECTED UPDATE\n"; return 87; }
        AUTO_UPDATE=true
        AUTO_UPDATE_URL=https://invalid.example/not-used
        RALPHIE_SKIP_AUTO_UPDATE=1
        self_update_check_and_reexec --auto-update true
    ' _ "$REPO/ralphie.sh" > "$T/pinned.log" 2>&1 || fail 'pinned startup updater did not skip'
    if grep -Fq -- 'UNEXPECTED UPDATE' "$T/pinned.log"; then fail 'pinned runtime updated'; fi
}
passed=0; failed=0
for group in case_switch_and_pin case_dirty_refusal case_bad_payloads case_offline_and_refusals case_failed_switch_restores_link case_development_and_pinned_startup; do
    ( set -e; "$group" )
    result=$?
    if [ "$result" -eq 0 ]; then printf 'PASS: %s\n' "$group"; passed=$((passed + 1)); else printf 'FAIL: %s (exit %s)\n' "$group" "$result"; failed=$((failed + 1)); fi
done
printf 'Skill updater: %s passed, %s failed\n' "$passed" "$failed"
[ "$passed" -eq 6 ] && [ "$failed" -eq 0 ]
