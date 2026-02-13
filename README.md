# Ralphie

Single-file autonomous loop runner for Codex/Claude projects.

## Quick Start (Very Simple)

1. Open a new repo directory:

```bash
mkdir my-project && cd my-project
```

2. Install and run from GitHub in one line (this writes `./ralphie.sh` in your current folder, then starts onboarding):

```bash
curl -fsSL https://raw.githubusercontent.com/sirouk/ralphie/refs/heads/master/ralphie.sh | bash
```

3. If you want a health check instead of onboarding first:

```bash
./ralphie.sh --doctor
```

4. Run the full autonomous chain in one go:

```bash
./ralphie.sh
```

This default command runs:
`prepare -> build -> test -> refactor -> test -> lint -> document`

What it will ask on first run:
- project name/vision/principles
- engine preference (auto/codex/claude)
- YOLO + git autonomy
- build approval style (`upfront` or `on_ready`)
- notifications + GitHub issues options

Default run now executes a phase pipeline:
`prepare -> build -> test -> refactor -> test -> lint -> document`
(unless you explicitly choose a mode).

## Binary Bootstrap And Models

Setup now offers optional binary bootstrap prompts (and remembers skips in `.ralphie/config.env`):
- Node.js toolchain via `nvm` (latest release tag)
- Chutes Codex installer script
- Chutes Claude Code installer script

Re-open that installer flow any time:

```bash
./ralphie.sh --setup
```

If you skip an installer once, it is remembered and won’t prompt again until you edit `.ralphie/config.env`.

Version checks and updates:

```bash
codex --version
claude --version
```

Codex update options:
- npm: `npm install -g @openai/codex@latest`
- homebrew: `brew upgrade --cask codex`

Claude update options:
- in-place updater: `claude update`
- native installer refresh: `claude install stable`

Model selection:
- setup asks for default Codex/Claude model overrides
- or pass per run:

```bash
./ralphie.sh --codex-model gpt-5.3-codex
./ralphie.sh --engine claude --claude-model sonnet
```

## Human In The Loop (Important)

Human checkpoints happen in these places:
- setup wizard questions
- prepare start approval when policy is `upfront`
- prepare -> build approval when policy is `on_ready`
- prepare confidence escalation (`<needs_human>true</needs_human>` or confidence stagnation)
- low build-gate consensus override prompt

Privacy guard:
- Build prerequisites now fail if markdown artifacts contain local usernames or home-directory absolute paths.
- Build prerequisites also fail if `.gitignore` is missing required local/sensitive/runtime patterns.

You can inject priorities while the loop is already running.

### Interrupt + Resume (simple)

- Press `Ctrl+C` in the loop terminal to open an interrupt menu.
- Default action is `resume` (safe for accidental keypresses).
- Menu options:
  - resume loop
  - capture human instructions immediately
  - show status
  - quit
- Disable this menu if needed:

```bash
./ralphie.sh --no-interrupt-menu
```

### Option A: Edit file directly

Create or edit this file in repo root:

```bash
HUMAN_INSTRUCTIONS.md
```

Use one request at a time:

```md
## 2026-02-13 10:00:00
- Request: Add per-PR changelog generation.
- Why: release visibility
- Priority: high
- Status: NEW
```

The loop reads this file on the next iteration and prioritizes `Status: NEW`.

### Option B: Use guided capture

From another terminal in the same repo:

```bash
./ralphie.sh --human
```

This runs an interactive one-by-one capture flow and writes to `HUMAN_INSTRUCTIONS.md`.
The active loop picks this up on its next iteration.

## Planning

Run planning/research/spec generation:

```bash
./ralphie.sh prepare
```

Prepare mode now uses a skeptical research doctrine:
- local docs/comments/naming are treated as hints, not truth
- external primary sources are preferred for dependencies/framework behavior
- deep repo mapping + coverage matrix artifacts are expected before build handoff

Auto-handoff into build after prepare passes:

```bash
./ralphie.sh prepare --auto-continue-build --build-approval upfront
```

Consensus threshold controls readiness strictness:
- CLI flag: `--min-consensus N`
- config/env: `MIN_CONSENSUS_SCORE`

You can inspect current values in:

```bash
.ralphie/config.env
```

## Building

Run build loop directly:

```bash
./ralphie.sh build --engine codex --timeout 180 --wait-for-lock 30
```

If build finds no tasks/spec work, it auto-switches once to prepare backfill by default; if disabled, it runs one internal planning refresh and then backs off.

## Build Something Not Planned Yet

Use prepare first, then auto-enter build when ready:

```bash
./ralphie.sh prepare --auto-continue-build --build-approval upfront
```

This is the intended path when there is no existing plan/spec queue.
When build mode starts with an empty queue, Ralphie auto-switches to prepare for deep backfill once (unless disabled), then returns to build after readiness gates pass.

Deep backfill target:
- map code + configuration surfaces
- generate dependency research from external primary sources
- build coverage matrix artifacts and convert gaps into specs/plan tasks
- reach consensus before build execution

Disable auto backfill if you want legacy idle behavior:

```bash
./ralphie.sh build --no-auto-prepare-backfill
```

## QA + Consensus Status

Current behavior:
- prepare gate uses swarm consensus before entering build
- build gate uses swarm consensus before build starts
- default pipeline includes phase transitions with consensus gating:
  - build -> test
  - test -> refactor
  - refactor -> test
  - test -> lint
  - lint -> document
- failed transition consensus rewinds to the previous phase
- prepare/build/test/refactor/lint/document prompts all enforce verification-focused behavior

## Run A Single Phase

You can run phases directly:

```bash
./ralphie.sh plan
./ralphie.sh build
./ralphie.sh test
./ralphie.sh refactor
./ralphie.sh lint
./ralphie.sh document
```

## Cleanup

Runtime cleanup only:

```bash
./ralphie.sh --clean
```

Deep generated-artifact cleanup (backup tarball preserved):

```bash
./ralphie.sh --clean-deep
```

## Artifact Policy

Keep (durable):
- `.specify/memory/constitution.md`
- `IMPLEMENTATION_PLAN.md`
- `specs/`
- `research/`
- `maps/`
- `subrepos/`
- `PROMPT_prepare.md`, `PROMPT_plan.md`, `PROMPT_build.md`, `PROMPT_test.md`, `PROMPT_refactor.md`, `PROMPT_lint.md`, `PROMPT_document.md`

Runtime/history (safe to wipe):
- `logs/`
- `consensus/`
- `completion_log/`
- `.ralphie/run.lock`

Backups (preserved by cleanup):
- `.ralphie/ready-archives/`

## Useful Checks

```bash
./ralphie.sh --doctor
./ralphie.sh --status
bash tests/ralphie_shell_tests.sh
```

## Inference Provider

Chutes.ai is supported as an optional inference/bootstrap provider in setup.
Chutes is a provider of open-source AI inference services with a single API and powered by Bittensor's decentralized compute network.

## Inspiration and Credit

This project was inspired by Florian Standhartinger’s work:
`ralph-wiggum` — https://github.com/fstandhartinger/ralph-wiggum

Credit to Florian for the original idea and foundation that helped inspire Ralphie.
