---
name: ralphie-orchestration
description: "Use when an agent needs to understand, run, debug, modify, or document `ralphie.sh`: the single-file Ralphie bootstrapper and autonomous lifecycle orchestrator for new or existing projects."
---

# Ralphie Orchestration

## Core Idea

`ralphie.sh` is the product. Everything else in this repository exists to explain, test, harden, or compare that one script.

Treat `ralphie.sh` as a portable seed:

- The user plants it in a project directory.
- If it arrives through `curl | bash`, it writes itself to `./ralphie.sh` and re-execs from disk.
- It discovers the surrounding project.
- It unfolds local scaffolding: bootstrap context, prompts, research notes, specs, logs, state, and gates.
- It drives the project through plan, build, test, refactor, lint, and document phases with Codex or Claude Code.

Your job when using this skill is to preserve that seed behavior while making Ralphie easier to run, safer to resume, and clearer to debug.

## How To Use `ralphie.sh`

Run Ralphie from the root of the project it should manage.

Quick start:

```bash
curl -fsSL https://raw.githubusercontent.com/sirouk/ralphie/refs/heads/master/ralphie.sh | bash
```

Local run:

```bash
./ralphie.sh
```

Useful control runs:

```bash
./ralphie.sh --help
./ralphie.sh --rebootstrap
./ralphie.sh --resume
./ralphie.sh --no-resume
./ralphie.sh --engine-output-to-stdout true
```

Important behavior:

- `curl | bash` uses stdin for the script stream. Any interactive prompt must read from `/dev/tty`.
- In a terminal, Ralphie prompts for project type, objective, constraints, success criteria, optional goals context, and plan-to-build consent.
- Without a terminal, Ralphie uses deterministic fallback bootstrap values and keeps `build_consent: false`.
- `--rebootstrap` refreshes `.ralphie/project-bootstrap.md`.
- Resume is enabled by default; `--no-resume` starts fresh.
- Ralphie may initialize git if the managed directory is not already a repository, depending on configuration.

## What Ralphie Unfolds

When planted in a project, `ralphie.sh` may create or update:

- `./ralphie.sh`: persisted local copy when installed from stdin.
- `.ralphie/project-bootstrap.md`: user/session intent and build consent.
- `.ralphie/project-goals.md`: optional pasted goals or context.
- `.ralphie/state.env`: resumable phase, attempt, token/cost, and git identity state.
- `.ralphie/reasons.log`: reason-coded failures and blockers.
- `.ralphie/last_gate_feedback.md`: latest gate blockers.
- `.specify/memory/constitution.md`: baseline governance context.
- `IMPLEMENTATION_PLAN.md`: plan artifact, initially a placeholder when missing.
- `PROMPT_plan.md`, `PROMPT_build.md`, `PROMPT_test.md`, `PROMPT_refactor.md`, `PROMPT_lint.md`, `PROMPT_document.md`: phase prompts.
- `research/`: discovery artifacts such as stack snapshot, codebase map, coverage matrix, dependency research, and summary.
- `specs/`: project contracts and specifications.
- `logs/`, `completion_log/`, `consensus/`: execution, output, and reviewer artifacts.

Generated placeholders are not final work. They are soil preparation. The plan phase should replace generic placeholder content with project-specific artifacts before build gates pass.

## How To Read `ralphie.sh`

Use `rg` to find the relevant surface before editing:

```bash
rg -n "stream bootstrap|ensure_project_bootstrap|prompt_read_line|run_agent_with_prompt|ensure_engines_ready|save_state|phase" ralphie.sh
rg -n "RB_REASON_CODE_OR_LOG_TEXT" ralphie.sh tests
```

Main conceptual regions:

1. **Stream bootstrap**: detects stdin execution, writes `./ralphie.sh`, re-execs from disk.
2. **Constants and paths**: defines project-local runtime paths such as `.ralphie/`, prompts, research, specs, logs, and state.
3. **Config parsing**: merges defaults, `.ralphie/config.env`, environment, and CLI flags.
4. **Prompt and bootstrap helpers**: collects or writes project objective, constraints, goals, and build consent.
5. **Engine discovery and readiness**: chooses Codex or Claude, probes capabilities, and builds invocation flags.
6. **Agent dispatch**: runs the active engine with phase prompts, retry policy, and idle-output watchdogs.
7. **Phase loop**: coordinates plan, build, test, refactor, lint, and document phases.
8. **Gates and consensus**: validates outputs, manifests, no-op policy, markdown hygiene, and reviewer verdicts.
9. **State and resume**: saves checksummed state and resumes cleanly after crashes or interrupts.
10. **Cleanup and signals**: handles locks, child processes, interrupts, pause/quit behavior, and notifications.

## Debugging A Ralphie Run

Start with state and reasons:

```bash
sed -n '1,120p' .ralphie/state.env
sed -n '1,160p' .ralphie/reasons.log
sed -n '1,200p' .ralphie/last_gate_feedback.md
```

Then inspect phase artifacts:

```bash
find logs completion_log consensus -maxdepth 2 -type f | sort
sed -n '1,200p' completion_log/<phase>*.out
sed -n '1,200p' logs/<phase>*.log
```

Common interpretations:

- `SESSION_ATTEMPT_COUNT=0`: Ralphie did not reach agent dispatch.
- `PHASE_ATTEMPT_IN_PROGRESS=true`: next resume should re-enter that phase/attempt.
- `build_consent: false`: build is intentionally blocked after planning.
- Placeholder `IMPLEMENTATION_PLAN.md`: plan phase has not yet produced a real project-specific plan.
- Empty `logs/` and `completion_log/`: startup, bootstrap, engine selection, or prompt collection likely stopped before the phase loop.

## Changing `ralphie.sh` Safely

Use this loop for changes to Ralphie itself:

1. Check the worktree:
   ```bash
   git status -sb
   ```
2. Find the narrow function or reason code:
   ```bash
   rg -n "exact option, prompt, log text, function, or reason code" ralphie.sh tests
   ```
3. Patch the smallest script surface.
4. Add or update a focused durability test when behavior changes.
5. Run syntax and targeted validation:
   ```bash
   bash -n ralphie.sh tests/notify-smoke.sh tests/durability/run-durability-suite.sh
   ./tests/durability/run-durability-suite.sh
   ```
6. For broad orchestration, engine, notification, or setup changes, run:
   ```bash
   ./test.sh --skip-live
   ```

When editing:

- Keep Bash dependency-light and guarded. Prefer existing helpers over new primitives.
- Preserve `curl | bash` behavior.
- Preserve direct `./ralphie.sh` behavior.
- Preserve non-interactive behavior.
- Preserve resume behavior.
- Preserve source-repo cleanliness during tests.
- Do not commit generated runtime artifacts from ad hoc runs.

## Failure Mode Recipes

### Prompt Looks Frozen

Likely area: `prompt_read_line`, `prompt_yes_no`, `prompt_multiline_block`, or `/dev/tty` handling.

Check:

- Does stdin carry the script stream?
- Is the prompt printed to the controlling terminal?
- Is command substitution capturing only the answer, not the prompt?
- Is there a regression test using a pseudo-terminal and piped stdin?

### Placeholders Were Created But Nothing Ran

Likely area: startup bootstrap before phase dispatch.

Check:

- `.ralphie/state.env` for `SESSION_ATTEMPT_COUNT`.
- `.ralphie/project-bootstrap.md` validity and `interactive_prompted`.
- `/dev/tty` prompt path.
- engine readiness logs and startup probe.

### Build Will Not Start

Likely intentional.

Check:

- `.ralphie/project-bootstrap.md` for `build_consent: false`.
- `IMPLEMENTATION_PLAN.md` for `ralphie_fallback_placeholder: true`.
- `.ralphie/last_gate_feedback.md` for build prerequisites.
- markdown hygiene checks for local path or transcript leakage.

### Resume Skips Or Repeats Work

Likely area: `save_state`, `load_state`, phase attempt state, checkpoint placement, or resume blockers.

Check:

- `CURRENT_PHASE`, `CURRENT_PHASE_INDEX`, `CURRENT_PHASE_ATTEMPT`, `PHASE_ATTEMPT_IN_PROGRESS`.
- checksum mismatch warnings.
- phase transition history.
- tests that kill mid-run and resume.

### Engine Dispatch Fails

Likely area: command discovery, capability probes, model/endpoint overrides, or engine-specific CLI flags.

Check:

- active engine in startup banner.
- `ensure_engines_ready`.
- `run_agent_with_prompt`.
- Codex and Claude capability variables.
- mocked CLI contract tests before live runs.

## Test Surfaces

Use the support files as scaffolding for `ralphie.sh`, not as separate products:

- `tests/durability/run-durability-suite.sh`: best place for isolated regressions against shell functions and mocked phase behavior.
- `tests/durability/run-claude-phase-stress.sh`: use for broader phase-loop stress.
- `tests/durability/mock-claude-control.sh`: update only when mocked engine behavior must change.
- `tests/notify-smoke.sh`: use for notification behavior and prompt helpers copied there.
- `test.sh`: use as the pre-ship umbrella.
- `README.md`: update when operator behavior changes.
- `AGENTS.md`: keep as the pointer to this skill and the repo-level scaffolding summary.

## Verification Checklist

- [ ] The agent can explain what `ralphie.sh` does without relying on unrelated repo files.
- [ ] The agent can run or recommend the correct `ralphie.sh` invocation for a fresh or existing project.
- [ ] The agent can identify generated artifacts and avoid committing them accidentally.
- [ ] The agent can debug a stalled run from `.ralphie/state.env`, reasons, logs, and completion outputs.
- [ ] The agent can modify `ralphie.sh` with focused durability coverage.
- [ ] `curl | bash`, direct execution, interactive bootstrap, non-interactive fallback, and resume remain coherent.
