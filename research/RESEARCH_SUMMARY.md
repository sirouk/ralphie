# Research Summary

Date: 2026-02-13
Mode: Prepare (Research + Plan + Spec)
Primary target: high-confidence build-readiness for `ralphie.sh`

## Iteration 5

### 1) Proposed architecture and execution plan
- Keep `ralphie.sh` as the orchestrator (no structural refactor this cycle).
- Focus next build scope on lock-contention reliability and diagnostics.
- Add explicit, machine-readable lock reason codes on all lock-fail exits.
- Add lock-aware test coverage and preserve cross-engine neutrality.

### 2) Self-critique
- Existing readiness artifacts marked prior scope complete, but lock-contention diagnosis is still partially opaque.
- Immediate lock-fail path currently exits without deterministic reason code.
- Active external lock holder can block smoke checks and reduce confidence if not handled by a lock-aware verification protocol.

### 3) Plan improvements
- Added new spec `004` with measurable acceptance criteria for lock failure classification and diagnostics.
- Replaced completed-plan content with a pending implementation plan scoped to spec `004`.
- Tightened risk register around lock contention and triage-quality.

### 4) Component research (reputable sources)

Local primary sources:
- `.specify/memory/constitution.md`
- `maps/agent-source-map.yaml`
- `maps/binary-steering-map.yaml`
- `ralphie.sh` (lock + gate logic)
- `tests/ralphie_shell_tests.sh`
- `subrepos/codex/docs/exec.md`
- `subrepos/codex/docs/config.md`
- `subrepos/claude-code/README.md`
- `subrepos/claude-code/examples/settings/README.md`
- `subrepos/claude-code/CHANGELOG.md`

Runtime probes (2026-02-13):
- `codex --version`: `codex-cli 0.101.0`
- `codex exec --help`: confirms `--output-last-message` and `--dangerously-bypass-approvals-and-sandbox`
- `claude --version`: `2.1.7 (Claude Code)`
- `claude --help`: confirms `-p/--print`, `--dangerously-skip-permissions`, and `--settings`

External references:
- GNU Bash job control: https://www.gnu.org/software/bash/manual/html_node/Job-Control-Builtins.html
- `flock(1)` reference: https://man7.org/linux/man-pages/man1/flock.1.html
- GNU coreutils `timeout`: https://www.gnu.org/software/coreutils/manual/html_node/timeout-invocation.html
- OpenAI Codex non-interactive docs: https://developers.openai.com/codex/noninteractive
- OpenAI Codex config reference: https://developers.openai.com/codex/config-reference
- Claude Code settings docs: https://code.claude.com/docs/en/settings

### 5) Fallback handling when verification is blocked
- Web and local research were available this iteration.
- End-to-end lock-isolated prepare smoke remains de-prioritized until lock diagnostics are hardened.
- Active lock evidence captured directly from repository runtime state:
  - lock file: `.ralphie/run.lock`
  - pid: `87111`
  - holder command: `bash ./ralphie.sh prepare --max 1 --engine codex --timeout 180 --wait-for-lock 30 --build-approval on_ready --prompt .ralphie/PROMPT_prepare_once.md`

### 6) Map-guided critique (required)

Source map active: `maps/agent-source-map.yaml`

Focused critique target: `ralphie.sh` parity and reliability.

Evidence sampled from both families:
- Codex: `subrepos/codex/docs/exec.md`, `subrepos/codex/docs/config.md`, runtime `codex exec --help`
- Claude: `subrepos/claude-code/README.md`, `subrepos/claude-code/examples/settings/README.md`, runtime `claude --help`

Anti-overfit rules applied before tool-specific recommendations:
- No provider-specific output assumptions.
- Engine-specific flags remain isolated to invocation boundaries.
- Behavior remains stable when either CLI is unavailable.
- Capability probes stay runtime-based (no hard version pinning).

Result:
- Accepted Option A (in-place lock hardening) and created spec `004` + implementation plan tasks.

### 7) Confidence by component
- Constitution and mode compliance: 99
- Cross-engine invocation parity: 95
- Output contract and build gate integrity: 93
- Lock-contention observability: 80
- End-to-end build-readiness for next implementation cycle: 91

## Readiness judgment
Preparation is complete for the next build cycle. Scope is bounded, testable, and aligned with map anti-overfit constraints.

<confidence>91</confidence>
<needs_human>false</needs_human>
<human_question></human_question>
<phase>PLAN_READY</phase>
<promise>DONE</promise>
