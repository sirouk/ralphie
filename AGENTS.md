# Ralphie Agent Guide

## Load The Skill

Before doing substantive work in this repository, read:

- `skills/software-development/ralphie-orchestration/SKILL.md`

That skill is the operating guide. Use it to understand how to run, inspect, debug, modify, test, and document `ralphie.sh`.

## What This Repo Supports

This repository is scaffolding around one portable script: `ralphie.sh`.

- `ralphie.sh` is the seed and the runtime.
- `README.md` explains the operator contract.
- `test.sh` and `tests/` validate the script.
- `engines/` and `subrepos/` provide comparative engine research and setup support.
- Generated runtime artifacts belong to the project where Ralphie is planted, not usually to this source repo.

When you need details, do not expand this guide. Open the skill.

## Seedling Model

`ralphie.sh` is like a seedling that unfolds into any project, new or existing. A user plants the single script in a project directory. From there it can create bootstrap context, prompts, research artifacts, specs, logs, state, and phase gates around the host project. The rest of this repo exists to keep that seed compact, portable, testable, and documented.

Preserve that framing when editing docs or code.
