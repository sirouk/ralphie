#!/bin/bash
set -eu
proof_root=$(mktemp -d)
mkdir -p "$proof_root/installed" "$proof_root/empty project" "$proof_root/caller" "$proof_root/tools"
cp /source/ralphie.sh "$proof_root/installed/ralphie.sh"
chmod +x "$proof_root/installed/ralphie.sh"
script="$proof_root/installed/ralphie.sh"
project="$proof_root/empty project"
cd "$proof_root/caller"
for optional_tool in python3 node jq curl wget; do
    if command -v "$optional_tool" >/dev/null 2>&1; then
        printf 'unexpected optional tool: %s\n' "$optional_tool" >&2
        exit 1
    fi
done
"$script" --project "$project" discover > "$proof_root/discover.log"
test ! -e "$project/.ralphie"
test ! -e "$project/.git"
cat > "$proof_root/tools/file engine" <<'ENGINE'
#!/bin/bash
set -eu
if [ "${1:-}" = --version ]; then printf 'fixture 1\n'; exit 0; fi
cat > "$FIXTURE_PROMPT"
cat > calc.sh <<'CALC'
#!/bin/bash
printf '%s\n' "$(($1 + $2))"
CALC
cat > verify.sh <<'VERIFY'
#!/bin/bash
set -eu
test "$(bash calc.sh 2 3)" = 5
test "$(bash calc.sh -8 3)" = -5
test "$(bash calc.sh 0 0)" = 0
VERIFY
printf '<<<RALPHIE\nstatus: done\nsummary: implemented integer sum\nlesson: arithmetic checks cover zero and negative values\nask: -\nRALPHIE>>>\n' > "$RALPHIE_OUTPUT"
ENGINE
chmod +x "$proof_root/tools/file engine"
export RALPHIE_ENGINE_CMD="$proof_root/tools/file engine"
export RALPHIE_ENGINE_ANSWER=file
export RALPHIE_ENGINE_CAPS=""
export FIXTURE_PROMPT="$proof_root/prompt"
export RALPHIE_OUTPUT="$proof_root/unrelated"
printf 'preserve me\n' > "$RALPHIE_OUTPUT"
"$script" --project "$project" run --once --no-update --gate 'test -f verify.sh && bash verify.sh' \
    --accept 'test "$(bash calc.sh -8 3)" = -5' 'Implement tested integer addition' \
    > "$proof_root/run.log" 2>&1
test -s "$project/.ralphie/OBJECTIVE.md"
test "$(cat "$project/.ralphie/OBJECTIVE.md")" = 'Implement tested integer addition'
test "$(cat "$RALPHIE_OUTPUT")" = 'preserve me'
(cd "$project" && bash verify.sh)
git -C "$project" rev-parse --verify HEAD
test -z "$(git -C "$project" status --porcelain)"
test ! -d "$project/.ralphie/lock"
test ! -e "$project/ralphie.sh"
test "$(find "$proof_root/installed" -type f | wc -l | tr -d ' ')" = 1
test ! -e "$proof_root/installed/.ralphie"
test ! -e "$proof_root/caller/.ralphie"
"$script" --project "$project" status --json
printf 'STANDALONE PASS: one installed script, blank target, file-output engine, gates, acceptance, git commit, no optional tools\n'
