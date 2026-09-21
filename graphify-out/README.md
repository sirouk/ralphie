# Development evidence

This directory is optional. Running `ralphie.sh` requires none of its files.

- [Current local production verification](PRODUCTION_READINESS.md) binds tests,
  standalone execution and the live Prime Agent check to exact candidate hashes.
- [Source comprehension map](COMPREHENSION.md), [inputs and outputs](INPUTS_OUTPUTS.md)
  and [interactive graph](graph.html) describe the earlier frozen `c21744b` source.
  Their line anchors remain valid in the included frozen source browser; they do
  not describe every change in the published script.

`verify_map.py` verifies that earlier analysis and its original no-modification
custody. It is not the verifier for the subsequent production changes.

Machine-local interpreter paths, caches and query history are excluded from Git.
References to `.graphify_python` in the frozen analysis describe its original
local interpreter. Reproduction requires an analysis environment with the
Graphify and Bash parser versions recorded in `map-manifest.json`; those tools
are not needed to open the graph or run Ralphie.

## Repository structure and sync policy

Keep this bundle at its existing paths: the HTML viewers, Markdown links and
hash manifests refer to those names. Moving generated files into new folders
would break the frozen evidence without improving the runtime.

| Area | Kept in Git | Purpose |
|---|---|---|
| Entry points | `README.md`, `PRODUCTION_READINESS.md` | Navigation and the verified production candidate |
| Frozen source map | `graph.json`, `graph.html`, `source.html`, reports, indexes and reviewed contracts | Browse and audit the earlier source snapshot |
| Map provenance | `map-manifest.json`, `verification.json`, `.graphify_extract.json`, `.pre-analysis*`, viewer receipt | Preserve inputs and custody evidence referenced by the map verifier |
| Optional tools | `build_map.py`, `render_map.py`, `verify_map.py` | Development-only analysis support |
| Production evidence | `production-verification/` allowlisted receipts, final patch, logs and proof scripts | Audit the published hardening pass |
| Local only | extraction intermediates, detection/stat caches, interpreter/root paths, query history, downloaded JS, scratch patches | Regenerable or machine/session-specific data |

The root `.gitignore` is an explicit allowlist for this directory. New generated
files stay local unless deliberately reviewed and added to that list. Existing
local files are not deleted by this policy. The HTML viewer embeds its JS, so
opening the published map does not require the local downloaded asset.

The map is **historical**, not a current-source certification. `verify_map.py`
checks its original source and Git custody; it is expected to reject a newer
checkout. Do not overwrite its receipts to make the current tree look verified.
Rebuilding needs fresh source-bound reviews and a new manifest. Detection and
extraction caches must be regenerated in the optional Graphify environment.
Ralphie itself needs none of this directory and gains no runtime dependency.
