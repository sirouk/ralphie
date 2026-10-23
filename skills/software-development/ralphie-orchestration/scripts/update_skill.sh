#!/usr/bin/env bash
# Maintain an explicitly installed skill; never alter a project checkout.
set -euo pipefail

ACTION=check
DESTINATION=''
SOURCE=sirouk/ralphie
REF=main
SUBDIR=skills/software-development/ralphie-orchestration
FILES=(ralphie.sh "$SUBDIR/SKILL.md" "$SUBDIR/agents/openai.yaml" \
    "$SUBDIR/scripts/update_skill.sh" "$SUBDIR/references/supervising.md" \
    "$SUBDIR/references/development.md")
STORE=''
WORK=''
SWITCH_DIR=''
LOCK_HELD=false
OLD_TARGET=''
SOURCE_ARGUMENT=false

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
root_ok() {
    case "$1" in *$'\r'*|*$'\n'*) fail 'Install and source roots cannot contain CR or LF.';; esac
}
physical_dir() {
    root_ok "$1"
    local physical
    physical="$(cd -P "$1" && printf '%s/.' "$PWD")" || return 1
    physical="${physical%/.}"
    root_ok "$physical"
    printf '%s\n' "$physical"
}
full_commit() {
    [ "${#1}" -eq 40 ] || return 1
    case "$1" in *[!0-9a-f]*) return 1;; esac
}
source_ok() {
    local owner="${SOURCE%%/*}" repository="${SOURCE#*/}"
    case "$SOURCE" in *[!a-zA-Z0-9_./-]*) return 1;; esac
    [ "$owner" != "$SOURCE" ] && [ -n "$owner" ] && [ -n "$repository" ] || return 1
    case "$owner:$repository" in *..*|*/*) return 1;; esac
    case "$REF" in ''|*[!a-zA-Z0-9_./-]*|*..*|/*|*/|*//* ) return 1;; esac
}
paths() {
    printf 'REVISION=%s\nRUNTIME_PATH=%s/ralphie.sh\nSKILL_PATH=%s/%s/SKILL.md\n' "$1" "$2" "$2" "$SUBDIR"
}
cleanup() {
    local result=$?
    [ -z "$SWITCH_DIR" ] || rm -rf "$SWITCH_DIR" || result=1
    [ -z "$WORK" ] || rm -rf "$WORK" || result=1
    if [ "$LOCK_HELD" = true ]; then rmdir "$STORE/.update.lock" || result=1; fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

while [ "$#" -gt 0 ]; do
    case "$1" in
        --check) ACTION=check; shift;;
        --apply) ACTION=apply; shift;;
        --install) [ "$#" -ge 2 ] || fail '--install requires a destination.'; ACTION=install; DESTINATION="$2"; shift 2;;
        --source) [ "$#" -ge 2 ] || fail '--source requires owner/repository.'; SOURCE="$2"; SOURCE_ARGUMENT=true; shift 2;;
        --ref) [ "$#" -ge 2 ] || fail '--ref requires a branch, tag or full commit.'; REF="$2"; SOURCE_ARGUMENT=true; shift 2;;
        --help) printf '%s\n' 'Usage: update_skill.sh [--check|--apply]' '       update_skill.sh --install ABSOLUTE_SKILL_LINK [--source owner/repository] [--ref REF]' 'Installs never replace an existing path. Updates preserve local edits and retain prior revisions.'; exit 0;;
        *) fail "Unknown option: $1";;
    esac
done
[ "$ACTION" = install ] || [ "$SOURCE_ARGUMENT" = false ] || fail '--source and --ref are install-only; an installed source cannot be silently replaced.'
source_ok || fail 'Invalid GitHub source or ref.'
command -v git >/dev/null 2>&1 || fail 'Git is required for skill integrity checks; Ralphie runtime is unchanged.'
root_ok "${BASH_SOURCE[0]}"
root_ok "$PWD"
SCRIPT_DIR="$(physical_dir "$(dirname "${BASH_SOURCE[0]}")")" || exit 1
SKILL_DIR="$(physical_dir "$SCRIPT_DIR/..")" || exit 1
ROOT="$(physical_dir "$SKILL_DIR/../../..")" || exit 1
root_ok "$ROOT"

# Hash bytes independently of caller/project Git configuration or filters.
digest() { GIT_DEFAULT_HASH=sha1 git --git-dir=/dev/null/ralphie-skill-no-repository hash-object --no-filters --stdin < "$1"; }
read_meta() {
    local key value lines=0 schema='' source='' ref='' commit='' destination=''
    [ -f "$1/.ralphie-skill-install" ] && [ ! -L "$1/.ralphie-skill-install" ] || return 1
    while IFS='=' read -r key value; do
        lines=$((lines + 1))
        case "$key" in
            schema) [ -z "$schema" ] || return 1; schema="$value";;
            source) [ -z "$source" ] || return 1; source="$value";;
            ref) [ -z "$ref" ] || return 1; ref="$value";;
            commit) [ -z "$commit" ] || return 1; commit="$value";;
            destination) [ -z "$destination" ] || return 1; destination="$value";;
            *) return 1;;
        esac
    done < "$1/.ralphie-skill-install"
    [ "$lines" -eq 5 ] && [ "$schema" = 1 ] && full_commit "$commit" || return 1
    SOURCE="$source"; REF="$ref"; INSTALLED="$commit"; DESTINATION="$destination"
    source_ok || return 1
    case "$DESTINATION" in /*) ;; *) return 1;; esac
    root_ok "$DESTINATION"
}
write_manifest() {
    local file hash
    for file in "${FILES[@]}" .ralphie-skill-install; do
        [ -f "$1/$file" ] && [ ! -L "$1/$file" ] || return 1
        hash="$(digest "$1/$file")" || return 1
        printf '%s %s\n' "$hash" "$file" || return 1
    done
}
verify_release() {
    local count manifest expected file
    [ -d "$1" ] && [ ! -L "$1" ] && [ -f "$1/.ralphie-skill-files" ] \
        && [ ! -L "$1/.ralphie-skill-files" ] || return 1
    # Six payload files, two metadata files and six fixed directories. NUL
    # counting also catches added aliases, special files and newline names.
    count="$(find "$1" -mindepth 1 -print0 | LC_ALL=C tr -cd '\000' | wc -c)" || return 1
    [ "$count" -eq 14 ] || return 1
    for file in skills skills/software-development "$SUBDIR" "$SUBDIR/agents" "$SUBDIR/scripts" "$SUBDIR/references"; do
        [ -d "$1/$file" ] && [ ! -L "$1/$file" ] || return 1
    done
    manifest="$(write_manifest "$1")" || return 1
    expected="$(cat "$1/.ralphie-skill-files")" || return 1
    [ "$manifest" = "$expected" ] || return 1
}

if [ "$ACTION" != install ]; then
    checkout="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
    if [ "$checkout" = "$ROOT" ]; then
        revision="$(git -C "$ROOT" rev-parse --verify HEAD)" || exit 1
        changes="$(git -C "$ROOT" status --porcelain=v1 --untracked-files=normal -- ralphie.sh "$SUBDIR")" || exit 1
        dirty=false; [ -z "$changes" ] || dirty=true
        printf 'DEVELOPMENT dirty=%s; checkout retained, no network or update attempted.\n' "$dirty"
        paths "$revision" "$ROOT"
        exit 0
    fi
    read_meta "$ROOT" || fail 'Unmanaged skill copy; use an explicitly trusted checkout or install with --install.'
    verify_release "$ROOT" || fail 'LOCAL_CHANGED: installed payload differs; no files were overwritten.'
fi

root_ok "$DESTINATION"
case "$DESTINATION" in /*) ;; *) fail 'Install destination must be absolute.';; esac
PARENT="$(physical_dir "$(dirname "$DESTINATION")")" || fail 'Create the intended skill parent directory first.'
BASE="$(basename "$DESTINATION")"
case "$BASE" in ''|.|..) fail 'Choose a named skill destination.';; esac
root_ok "$PARENT"
DESTINATION="$PARENT/$BASE"
STORE="$PARENT/.${BASE}.revisions"
if [ -L "$STORE" ] || { [ -e "$STORE" ] && [ ! -d "$STORE" ]; }; then
    fail 'Unsafe revision store; no update performed.'
fi
if [ "$ACTION" = install ]; then
    if [ -e "$DESTINATION" ] || [ -L "$DESTINATION" ]; then
        fail 'Destination already exists; refusing to replace or adopt it.'
    fi
    checkout="$(git -C "$PARENT" rev-parse --show-toplevel 2>/dev/null || true)"
    [ -z "$checkout" ] || fail 'Install outside a writable project checkout; use the checkout directly for development.'
else
    [ -L "$DESTINATION" ] || fail 'Managed skill link is missing or replaced; no update performed.'
    current="$(physical_dir "$DESTINATION/../../..")" || fail 'Managed skill link is broken.'
    case "$current" in "$STORE/"*) ;; *) fail 'Managed link points outside its revision store.';; esac
    if [ "$current" != "$ROOT" ]; then
        if ! read_meta "$current" || ! verify_release "$current"; then
            fail 'Current managed revision cannot be verified.'
        fi
        printf 'SUPERSEDED: reload the current physical skill before a new launch.\n'
        paths "$INSTALLED" "$current"
        exit 0
    fi
fi
mkdir -p "$STORE" || exit 1
mkdir "$STORE/.update.lock" 2>/dev/null || fail 'Skill update is busy or abandoned; installed revisions remain available.'
LOCK_HELD=true
if [ "$ACTION" != install ]; then
    verify_release "$ROOT" || fail 'LOCAL_CHANGED: installed payload changed during update admission.'
    OLD_TARGET="$(readlink "$DESTINATION")" || exit 1
    [ "$OLD_TARGET" = "$ROOT/$SUBDIR" ] || fail 'Managed link changed during update admission.'
fi
WORK="$(mktemp -d "$STORE/.stage.XXXXXX")" || exit 1

fetch() {
    command -v curl >/dev/null 2>&1 || { printf '%s\n' 'curl is unavailable; online skill maintenance needs curl. Ralphie runtime is unchanged.' >&2; return 1; }
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --connect-timeout 5 --max-time 20 --max-filesize 2097152 --output "$2" "$1"
}
LATEST="$REF"
if ! full_commit "$LATEST"; then
    if ! fetch "https://api.github.com/repos/$SOURCE/commits/$REF" "$WORK/commit.json"; then
        [ "$ACTION" != install ] || fail 'Cannot resolve the install revision; nothing was installed.'
        printf 'OFFLINE: freshness not verified; retained the verified installed revision.\n'
        paths "$INSTALLED" "$ROOT"
        exit 0
    fi
    LATEST="$(sed -n 's/^[[:space:]]*"sha":[[:space:]]*"\([0-9a-f]*\)".*/\1/p' "$WORK/commit.json" | awk 'NR==1 {print}')" || exit 1
fi
full_commit "$LATEST" || fail 'Remote ref did not resolve to one full commit.'
if [ "$ACTION" != install ] && [ "$LATEST" = "$INSTALLED" ]; then
    printf 'UP_TO_DATE\n'; paths "$INSTALLED" "$ROOT"; exit 0
fi
if [ "$ACTION" = check ]; then
    printf 'UPDATE_AVAILABLE latest=%s\n' "$LATEST"; paths "$INSTALLED" "$ROOT"; exit 0
fi
RELEASE="$STORE/$LATEST"
if [ -e "$RELEASE" ] || [ -L "$RELEASE" ]; then
    if [ ! -d "$RELEASE" ] || [ -L "$RELEASE" ]; then
        fail 'Unsafe cached revision.'
    fi
    expected_source="$SOURCE"; expected_ref="$REF"; expected_destination="$DESTINATION"
    if ! read_meta "$RELEASE" || ! verify_release "$RELEASE"; then
        fail 'Cached revision differs; no files were overwritten.'
    fi
    [ "$SOURCE:$REF:$DESTINATION:$INSTALLED" = "$expected_source:$expected_ref:$expected_destination:$LATEST" ] || fail 'Cached revision binding differs.'
else
    mkdir "$WORK/payload" || exit 1
    for file in "${FILES[@]}"; do
        mkdir -p "$WORK/payload/$(dirname "$file")" || exit 1
        fetch "https://raw.githubusercontent.com/$SOURCE/$LATEST/$file" "$WORK/payload/$file" || fail "Incomplete update payload: $file; current install retained."
        if [ ! -s "$WORK/payload/$file" ] || [ -L "$WORK/payload/$file" ]; then
            fail "Empty update payload: $file"
        fi
    done
    if ! /bin/bash -n "$WORK/payload/ralphie.sh" || ! /bin/bash -n "$WORK/payload/$SUBDIR/scripts/update_skill.sh"; then
        fail 'Candidate shell syntax is invalid; current install retained.'
    fi
    grep -Fxq -- 'name: ralphie-orchestration' "$WORK/payload/$SUBDIR/SKILL.md" || fail 'Candidate skill identity differs.'
    printf 'schema=1\nsource=%s\nref=%s\ncommit=%s\ndestination=%s\n' "$SOURCE" "$REF" "$LATEST" "$DESTINATION" > "$WORK/payload/.ralphie-skill-install" || exit 1
    write_manifest "$WORK/payload" > "$WORK/payload/.ralphie-skill-files" || exit 1
    verify_release "$WORK/payload" || fail 'Staged payload could not be verified.'
    mv "$WORK/payload" "$RELEASE" || exit 1
fi
# Revalidate before switching. Old revisions remain at their physical paths.
verify_release "$RELEASE" || fail 'Candidate changed before publication.'
if [ "$ACTION" != install ]; then
    verify_release "$ROOT" || fail 'LOCAL_CHANGED: current install changed while staging.'
    [ "$(readlink "$DESTINATION")" = "$OLD_TARGET" ] || fail 'Managed link changed while staging.'
else
    if [ -e "$DESTINATION" ] || [ -L "$DESTINATION" ]; then
        fail 'Destination appeared while staging.'
    fi
fi
# The replacement link is staged beside its destination, on the same filesystem.
SWITCH_DIR="$(mktemp -d "$PARENT/.${BASE}.link.XXXXXX")" || exit 1
mkdir "$SWITCH_DIR/probe-directory" || exit 1
ln -s "$SWITCH_DIR/probe-directory" "$SWITCH_DIR/probe-old" || exit 1
ln -s new-target "$SWITCH_DIR/probe-new" || exit 1
MOVE_LINK_FLAG=''
for flag in -h -T; do
    if mv -f "$flag" "$SWITCH_DIR/probe-new" "$SWITCH_DIR/probe-old" 2>/dev/null; then
        if [ ! -L "$SWITCH_DIR/probe-old" ] || [ "$(readlink "$SWITCH_DIR/probe-old")" != new-target ] \
            || [ -e "$SWITCH_DIR/probe-directory/probe-new" ]; then
            fail 'mv cannot safely replace a directory symlink.'
        fi
        MOVE_LINK_FLAG="$flag"
        break
    fi
done
[ -n "$MOVE_LINK_FLAG" ] || fail 'mv needs native -h or -T support; current skill link retained.'
ln -s "$RELEASE/$SUBDIR" "$SWITCH_DIR/skill" || exit 1
# Native no-dereference rename preserves old-or-new visibility even on SIGKILL.
mv -f "$MOVE_LINK_FLAG" "$SWITCH_DIR/skill" "$DESTINATION" || fail 'Cannot publish skill link; current link retained.'
printf 'UPDATED\n'
paths "$LATEST" "$RELEASE"
