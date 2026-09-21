# Local production readiness

**The candidate passes the local production verification described below.**
`ralphie.sh` remains the only runtime product. No runtime dependency was added;
the test suite, source maps and this evidence folder are development aids.
This records local verification completed on 2026-09-21 before publication.
It is not a guarantee for every project, engine or future engine version.
Publication fields in the evidence manifest describe that verification time;
see [hosted CI](https://github.com/sirouk/ralphie/actions/workflows/test.yml)
for subsequent runs and their commit identities.

- Verification base HEAD: `04dc8eff299b8535ad0ef676295bba1ebcb9fca3`
- Script SHA-256: `432b3bf7b0dd81371646fda0d5e5e0cbc94067fd11dfc76bc41c2627c81f6514`
- Test SHA-256: `aebc48548482ad4ffefa2962f56f0e8a8f6b528798f56d957027a7da99cd7b90`
- [All file hashes](production-verification/final-hashes.json)
- [Verified patch against the base HEAD](production-verification/final.patch)
- [Structured evidence manifest](production-verification/manifest.json)

## Changes in this hardening pass

- Explicit `run` preserves options and objective text. Command failures retain
  their exit codes; stop requests and gate backups must exist before success.
- JSON status canonicalizes decimal text without shell arithmetic overflow.
- Custom file-answer engines receive their current `RALPHIE_OUTPUT` destination.
  Engine version probes have closed stdin and a portable 15-second watchdog.
- Updates validate without executing the candidate, bound both downloaders,
  preserve mode and symlinks, verify previous bytes and publish by same-filesystem
  rename. Recovery-path aliases and changed source bytes cause refusal.
- Operator help and README now describe these contracts and their limits.
  The assertion floor was raised from 655 to 1350.

## Complete offline matrix

| Environment | Passed | Explicit skips | Duration | Receipt |
|---|---:|---:|---:|---|
| macOS, system Bash 3.2.57 | 1548 | 0 | 1155.9s | [log](production-verification/macos-bash32.log) |
| Linux, Bash 5.2.21, Python and curl available | 1545 | 1 | 514.9s | [log](production-verification/linux-tools.log) |
| Linux, Bash 5.2.21, no Python/Node/jq/curl/wget | 1528 | 14 | 513.9s | [log](production-verification/linux-minimal.log) |

All three suites used the exact script and test hashes above. Linux ran without
network access, as UID 65534 with all capabilities dropped, in disposable copies
of a read-only mounted candidate. Python, Node and jq are not product requirements.
The Linux tools image has Python and curl; it does not have Node, jq or wget.
The minimal image lacks all five. Skips identify optional-parser/downloader and
filesystem-specific checks; the logs retain the individual reasons.

Shell syntax, ShellCheck at error severity and Git whitespace checks passed:
[static receipt](production-verification/static.json). The configured hosted CI
matrix covers Ubuntu and macOS using system Bash, including child scripts.
Hosted CI had not run when these local receipts were captured.

The first matrix was deliberately interrupted after its documentation check
found the missing `RALPHIE_LIB` help entry. That entry was added and the complete
matrix above restarted from a new frozen candidate. The earlier logs are kept at
`/private/tmp/ralphie-production-hcl5xesd/rejected-first-matrix` and are not counted as passing verification.

## Standalone proof

Only `ralphie.sh` was copied to an installation directory. From another working
directory, it targeted an empty project whose path contained spaces. A custom
file-answer engine created code and tests; Ralphie independently passed health
and acceptance checks, saved a local commit, left a clean worktree and released
its lock. An inherited output destination remained untouched. No project-side
copy of the script or other repository files were required. This ran without
Python, Node, jq, curl, wget or network access.

[Receipt](production-verification/standalone-final.json),
[execution log](production-verification/standalone-final.log).

## Real Prime Agent proof

Installed Prime Agent 0.9.5 was selected by default and repaired a
deliberately broken arithmetic project in 47.8 seconds.
Independent checks verified both health gates, objective acceptance, unchanged
test bytes, a commit changing only `calc.sh`, a clean tree and a released lock.
The fixture commit is `d603051f18e517fb11e25ab89c871b1c79e9c4df`. This is an integration smoke test;
other adapters are covered by offline contracts, not equivalent live runs.

The call was limited to 120 seconds, 12 turns, two continuations and 65536 tokens.
The engine reported 58286 tokens. Its reported zero cost is
not proof that the provider billed nothing.

[Checks](production-verification/prime-result.json),
[run log](production-verification/prime-live.log),
[final status](production-verification/prime-status.json).

## Custody and limits

At verification time, the repository had seven tracked files and these changes
were uncommitted. Existing unrelated work and runtime evidence were preserved.
The source maps and verification receipts accompany the subsequent publication
as optional development support.
Gates remain the completion authority, but they do not sandbox an engine sharing
the operator's OS user or make test files immutable. Update sources are trusted
operator inputs; atomic publication does not prove power-loss durability or
coordinate simultaneous updates from different projects.

The earlier [comprehension map](COMPREHENSION.md) and [graph](graph.html) remain
frozen evidence for source `c21744b635e3b640aa6d65b6c36daa7dc0d8e1e90b7bf45fb09f8937055aa905`.
Their old line anchors and recorded defects describe that snapshot, not the
current script. They were not rewritten to suggest a fresh full-source review.
