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
-   **Auto-Update Mechanism:** Best-effort synchronization with upstream versions to ensure the orchestrator always utilizes the latest safety and capability improvements.

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

## Auto-Update Mechanism

Ralphie includes a best-effort auto-update routine at launch ([`ralphie.sh:3760`](ralphie.sh:3760)). 
1.  **Detection:** Checks `AUTO_UPDATE_ENABLED` and fetches the latest script from `AUTO_UPDATE_URL`.
2.  **Validation:** Verifies the download has a valid shebang and Ralphie header to prevent accidental execution of malformed content.
3.  **Atomic Swap:** Backs up the current version to `.ralphie/ready-archives/` before performing an atomic `mv`.
4.  **Re-exec:** The script immediately re-executes itself with the new version, preserving all CLI arguments and current environment state.

## Security & Sandboxing (Claude Code)

When operating in autonomous YOLO mode, Ralphie enforces high-security standards for Claude Code:
-   **Environment Isolation:** All commands are prefixed with `env IS_SANDBOX=1`.
-   **Permission Enforcement:** Automatically injects `--dangerously-skip-permissions` using an idempotent check to prevent argument duplication.

## Usage

### Quick Start
```bash
curl -fsSL https://raw.githubusercontent.com/sirouk/ralphie/refs/heads/master/ralphie.sh | bash
```

### Autonomous Resumption
If a run is interrupted by a timeout or crash, Ralphie will automatically detect the previous state at launch and prompt you to resume. You can also bypass the prompt and force a resumption via:
```bash
./ralphie.sh --resume
```

## Credits

Ralphie was inspired by the original [`ralph-wiggum`](https://github.com/fstandhartinger/ralph-wiggum) project by Florian Standhartinger.
