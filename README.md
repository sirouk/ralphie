# Ralphie

Ralphie is a high-fidelity autonomous development framework for Codex and Claude Code. It orchestrates a multi-phase engineering lifecycle—merging recursive planning, evidence-based implementation, and deep consensus swarms into a single, self-healing recursive loop.

## Design Philosophy: Correct-by-Construction

Ralphie operates on a "Thinking before Doing" doctrine. The system is designed around **Critique-Driven Development**, where autonomous agents do not just execute tasks but recursively critique their own research, specifications, and implementation plans. This ensures that every code change is backed by executable logic and peer-validated consensus before a single line of production code is modified.

## Core Features

-   **Recursive Planning:** Merges research, specification, and implementation planning into a single high-fidelity `Plan` mode.
-   **Deep Consensus Swarm:** Multi-persona reviewer panels (Adversarial, Optimist, Forensic) that alternate engines (Codex/Claude) and utilize stochastic jitter to eliminate confirmation bias.
-   **Autonomous YOLO Mode:** Enabled by default, granting agents the authority to execute shell commands and modify files.
-   **Self-Healing State:** SHA-256 checksum-validated state snapshots that detect artifact drift and allow for robust recovery via `--resume`.
-   **Atomic Lifecycle Management:** Global process tracking ensures that orphaned agent processes are terminated on failure or interrupt.
-   **Self-Contained Runtime:** Runtime behavior is version-stable and local to the checked-out orchestrator script; no runtime auto-update is performed.

## Operational Phases & Governance

Ralphie transitions through structured phases governed by strict validation gates and state management.

### 1. Plan (Research + Spec + Implementation Plan)
-   **Logic:** Recursive mapping of codebase surfaces, external dependency research, and creation of testable specs.
-   **Gate:** Requires a `<promise>DONE</promise>` signal followed by a **Plan-Gate Consensus Swarm** with a score $\ge$ `MIN_CONSENSUS_SCORE`.
-   **State:** Persists plan checksums to prevent out-of-band drift during implementation.

### 2. Build
-   **Logic:** Targeted implementation of items from the validated `IMPLEMENTATION_PLAN.md`.
-   **Gate:** Verification of spec-status updates and line-by-line acceptance criteria validation.
-   **Transition:** Auto-switches to `Plan` mode for backfill if the work queue becomes empty.

### 3. Test
-   **Logic:** Test-Driven Development (TDD) cycle. High-risk behavior surfaces are identified and verified with adversarial unit/integration tests.
-   **Gate:** Requires green test suites; failed verification triggers a rewind to the `Build` phase.

### 4. Refactor
-   **Logic:** Behavior-preserving simplification. Focuses on reducing incidental complexity and technical debt.
-   **Gate:** Mandatory post-refactor test pass to ensure zero behavioral regression.

### 5. Lint
-   **Logic:** Static analysis and formatting.
-   **Gate:** Clean report from repository-configured linting workflows.

### 6. Document
-   **Logic:** Synchronization of READMEs and module docs with the new executable reality.
-   **Gate:** Final documentation-quality check before loop closure.

## Runtime Management

`ralphie.sh` does not auto-update itself at runtime. Release drift is handled intentionally through normal checkout/version control workflows.
To upgrade behavior, update the checked-out `ralphie.sh` script (or repository) and rerun with the same command.

## Security & Sandboxing (Claude Code)

When operating in autonomous YOLO mode, Ralphie enforces high-security standards for Claude Code:
-   **Environment Isolation:** All commands are prefixed with `env IS_SANDBOX=1`.
-   **Permission Enforcement:** Automatically injects `--dangerously-skip-permissions` using an idempotent check to prevent argument duplication.

## Usage

### Quick Start
```bash
curl -fsSL https://raw.githubusercontent.com/sirouk/ralphie/refs/heads/master/ralphie.sh | bash
```

`ralphie.sh` will self-bootstrap missing control artifacts before the first run:

- `.specify/memory/constitution.md`
- placeholder research artifacts under `research/`
- placeholder implementation scaffolding under `IMPLEMENTATION_PLAN.md`
- `.ralphie/project-bootstrap.md` containing:
  - project type (`existing` or `new`)
  - primary objective for this session
  - explicit plan→build transition consent

Startup bootstrap is interactive when a terminal is attached (`/dev/tty` is present):
- `project_type`: is this a new project?
- `objective`: what should Ralphie optimize for?
- `build_consent`: proceed from PLAN to BUILD automatically when gates pass?

If `project_bootstrap.md` already exists and was created interactively, `ralphie.sh` will reuse it.
If it was created non-interactively, the first interactive run will refresh it by default.
To force a refresh at any time, run:
```bash
./ralphie.sh --rebootstrap
```

### Autonomous Resumption
If a run is interrupted by a timeout or crash, Ralphie automatically resumes from the previous state by default. You can force a fresh start with:
```bash
./ralphie.sh --no-resume
```

### Reference Sources

- `engines/setup-agent-subrepos.sh` is retained for comparative engine behavior research only.
- It is **not** required for a standard `ralphie.sh` run on a user project.

## Runtime Configuration (CLI + `config.env`)

`ralphie.sh` supports explicit session/retry budgets plus optional cost accounting.

### CLI Flags

- `--resume`  
- `--no-resume`  
- `--rebootstrap`  
- `--max-session-cycles N`  
- `--session-token-budget N`  
- `--session-token-rate-cents-per-million N`  
- `--session-cost-budget-cents N`  
- `--max-phase-completion-attempts N`  
- `--phase-completion-retry-delay-seconds N`  
- `--phase-completion-retry-verbose true|false`  
- `--run-agent-max-attempts N`  
- `--run-agent-retry-delay-seconds N`  
- `--run-agent-retry-verbose true|false`  
- `--auto-repair-markdown-artifacts true|false`  
- `--strict-validation-noop true|false`  
- `--engine-output-to-stdout true|false`  
- `--phase-noop-profile strict|balanced|read-only-first|custom`
- `--phase-noop-policy-plan hard|soft|none`
- `--phase-noop-policy-build hard|soft|none`
- `--phase-noop-policy-test hard|soft|none`
- `--phase-noop-policy-refactor hard|soft|none`
- `--phase-noop-policy-lint hard|soft|none`
- `--phase-noop-policy-document hard|soft|none`
- `--max-iterations N`

Equivalent environment variables in `.ralphie/config.env`:
`MAX_SESSION_CYCLES`, `SESSION_TOKEN_BUDGET`, `SESSION_TOKEN_RATE_CENTS_PER_MILLION`,
`SESSION_COST_BUDGET_CENTS`, `PHASE_COMPLETION_MAX_ATTEMPTS`, `PHASE_COMPLETION_RETRY_DELAY_SECONDS`,
`PHASE_COMPLETION_RETRY_VERBOSE`, `RUN_AGENT_MAX_ATTEMPTS`, `RUN_AGENT_RETRY_DELAY_SECONDS`,
`RUN_AGENT_RETRY_VERBOSE`, `AUTO_REPAIR_MARKDOWN_ARTIFACTS`, `STRICT_VALIDATION_NOOP`, `RALPHIE_ENGINE_OUTPUT_TO_STDOUT`,
`PHASE_NOOP_POLICY_PLAN`, `PHASE_NOOP_POLICY_BUILD`, `PHASE_NOOP_POLICY_TEST`,
`PHASE_NOOP_POLICY_REFACTOR`, `PHASE_NOOP_POLICY_LINT`, `PHASE_NOOP_POLICY_DOCUMENT`,
`PHASE_NOOP_PROFILE`,
`MAX_ITERATIONS`.

`RESUME_REQUESTED` can be supplied via `.ralphie/config.env` as `RALPHIE_RESUME_REQUESTED=true|false` (default: true).
`REBOOTSTRAP_REQUESTED` can be supplied via `.ralphie/config.env` as `RALPHIE_REBOOTSTRAP_REQUESTED=true|false`.

`PHASE_NOOP_PROFILE` can be supplied via `.ralphie/config.env` as `RALPHIE_PHASE_NOOP_PROFILE=balanced|strict|read-only-first|custom`.

Phase no-op profile precedence: `--phase-noop-profile` / `RALPHIE_PHASE_NOOP_PROFILE` set the profile, and any explicitly passed `--phase-noop-policy-*` flags override profile defaults for that phase.

Supported no-op profiles:
- `balanced` (default): plan=`none`, build=`hard`, test=`soft`, refactor=`hard`, lint=`soft`, document=`hard`.
- `strict`: all phases (`plan`, `build`, `test`, `refactor`, `lint`, `document`) `hard`.
- `read-only-first`: plan=`none`, build=`hard`, test=`soft`, refactor=`none`, lint=`soft`, document=`none`.
- `custom`: only explicit per-phase flags apply.

Defaults:
- `max-session-cycles`: `0` (unlimited)
- `session token budget`: `0` (unlimited)
- `session cost budget`: `0` (unlimited)
- `max-phase-completion-attempts`: `3`
- `run-agent-max-attempts`: `3`
- `engine-output-to-stdout`: `true`
- `phase-noop default policy`: plan=`none`, build=`hard`, test=`soft`, refactor=`hard`, lint=`soft`, document=`hard`
- `resume`: enabled by default (`--resume`)

## Interrupt Controls

In interactive mode, pressing `Ctrl+C` opens a control menu:

- `r` resume immediately (default)
- `l` toggle live engine output on/off
- `p` persist state and pause
- `q` immediate stop
- `h` help

The current `engine-output-to-stdout` mode is preserved in session state and reused on resume.

## Deterministic Stack Discovery

Before each planning run, `ralphie.sh` writes `research/STACK_SNAPSHOT.md` with:

- ranked stack candidates,
- deterministic evidence signals,
- and a ranked alternatives list.

Build transitions require the snapshot and clean artifact checks to pass.

## Restart behavior

- Resume is enabled by default. On restart, `ralphie.sh` restores the latest persisted phase and iteration state.
- If resume lands on a phase with broken prerequisites (for example missing artifacts, bad markdown hygiene, or non-actionable plan), it automatically falls back to `plan` and records the reason in `last_gate_feedback`.
- This prevents silent stalls while avoiding unnecessary recomputation.

## Credits

Ralphie was inspired by the original [`ralph-wiggum`](https://github.com/fstandhartinger/ralph-wiggum) project by Florian Standhartinger.
