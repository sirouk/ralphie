# Human Needs: Ralphie Autonomous Development Framework

This document outlines the core human-centric requirements and engineering solutions that govern the Ralphie ecosystem. It defines the "Human Needs" addressed by the orchestrator to ensure that autonomous development remains safe, predictable, and mission-ready.

## 1. The Need for Predictability & Governance
Humans require that autonomous agents do not "go rogue" or skip critical quality checks. Ralphie addresses this through **Phase Governance**.
-   **Structured Pipeline:** Enforces a linear `Plan -> Build -> Test -> Refactor -> Lint -> Document` lifecycle.
-   **Validation Gates:** No phase can advance without meeting explicit exit criteria, verified by a diverse consensus panel.
-   **Isolation:** Supports single-phase execution to allow targeted human intervention without breaking pipeline integrity.

## 2. The Need for Reliability & Continuity
In distant future or remote (off-planet) deployments, humans cannot manually debug state corruption. Ralphie addresses this through **State Integrity**.
-   **Atomic Snapshots:** Every iteration is check-summed and snapshotted to `.ralphie/state.env`.
-   **Autonomous Recovery:** Supports `--resume` to recover from inference stalls or power failures, validating artifact consistency before resumption.
-   **Locking Protocol:** Prevents race conditions and concurrent state modification through atomic filesystem locks.

## 3. The Need for Intellectual Honesty & Truth
A single model's output can be biased or hallucinatory. Humans need a "second opinion" (and a third). Ralphie addresses this through the **Deep Consensus Swarm**.
-   **Psychological Diversity:** Reviewers are assigned **Adversarial**, **Optimist**, and **Forensic** personas to break confirmation bias.
-   **Stochastic Jitter:** Random seeds and varying focus areas force the panel to explore non-obvious failure modes.
-   **Physical Diversity:** Alternates between Codex and Claude Code to leverage different model architectures in every decision.

## 4. The Need for Toolchain Versatility
Humans should not be tied to a single provider whose API might fail or be deprecated. Ralphie addresses this through **Engine Failover**.
-   **Dynamic Resolution:** Automatically detects and probes the capabilities of available agent binaries.
-   **Seamless Failover:** Pivot to a diversified engine if a model becomes stuck or reaches a reasoning plateau.
-   **Self-Healing:** Automatically remediates known engine-specific configuration errors (e.g., Codex reasoning effort mismatches).

## 5. The Need for Safety & Risk Mitigation
Autonomous code execution (YOLO mode) is inherently risky. Humans need a "fail-safe" environment. Ralphie addresses this through **Sandbox Enforcement**.
-   **Sandboxing:** Strictly enforces `env IS_SANDBOX=1` and dangerous permission bypass flags for Claude Code.
-   **Identity Protection:** Redacts local paths and usernames from all public/durable artifacts to prevent information leakage.
-   **Atomic Cleanup:** A global process registry ensures zero orphaned processes remain active after an interrupt.

## 6. The Need for Efficiency & Stewardship
Computation and time are finite resources. Humans require "Zero-Waste" engineering. Ralphie addresses this through **Loop Efficiency**.
-   **Idle Detection:** Automatically switches to `Plan` backfill if the work queue is empty, preventing aimless looping.
-   **Exponential Backoff:** Gracefully slows down during idle periods to preserve compute and energy.
-   **Immediate Feedback:** Inject specific gate blockers (e.g., "missing acceptance criteria") directly into the next prompt to accelerate convergence.

## 7. The Need for Long-Term Sustainability
Systems intended for the distant future must be self-contained and portable. Ralphie addresses this through **Hardened Self-Modality**.
-   **Self-Containment:** A single-file orchestrator with minimal external dependencies.
-   **Auto-Update Logic:** Best-effort synchronization with verified upstream safety patches.
-   **Durable Registry:** Maintains a history of decisions in `reasons.log` and `completion_log/` for multi-generational auditing.
