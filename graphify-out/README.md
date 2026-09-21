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
