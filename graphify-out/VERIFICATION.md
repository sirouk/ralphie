# Map verification

Source SHA-256: `c21744b635e3b640aa6d65b6c36daa7dc0d8e1e90b7bf45fb09f8937055aa905`.

**49 artifact checks passed.** [Machine receipt](verification.json), [source/artifact hashes](map-manifest.json).

- All 5,478 source lines were covered by three nonoverlapping reviews; all 234 function definitions match both the independent declaration scan and reviewed boundaries.
- The final graph preserves all 864 node identities and 2,904 directed relationships, with source evidence and no dangling endpoints. Its only self-loop is `kill_tree` recursion.
- The index retains 2,724 raw AST command sites, 442 redirections, 16 heredocs, 988 assignments, 2,649 expansions and 128 case branches. Nine parser normalizations are explicit; these counts are syntax coverage, not execution counts.
- Browser inspection in Chrome confirmed the focused cycle diagram, readable function inspector, search for `completion_ready`, and navigation to the exact `cycle_once` source line. The graph also opened directly from disk without a server; visualization code is embedded and its upstream asset integrity was checked.
- Every source-browser line matches the reviewed source. Inline JavaScript passes Node syntax checks. Documentation anchors and 14 supporting artifact hashes are validated.
- The five pre-existing modified files, their tracked diff and Git HEAD are byte-for-byte unchanged from the start of this task. Only analysis artifacts under `graphify-out/` were added.

Product tests, gates, engines and update candidates were not run for this analysis-only task. No commit or push was performed. Static comprehension does not certify arbitrary project correctness or production readiness.

Recheck with `python3 graphify-out/verify_map.py` (Node is used only to syntax-check this viewer). Rebuild the graph with the interpreter recorded in `.graphify_python` and `build_map.py`; changed source requires fresh reviewed annotations. These tools are optional development support, not dependencies of `ralphie.sh`.
