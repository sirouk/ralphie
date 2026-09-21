"""Verify source custody, graph identity/coverage and the standalone viewer."""
from collections import Counter
from datetime import datetime, timezone
import hashlib
import html
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

OUT = Path(__file__).resolve().parent
ROOT = OUT.parent
checks = []


def check(condition, name):
    if not condition:
        raise SystemExit("FAIL: " + name)
    checks.append(name)


def read(name):
    return json.loads((OUT / name).read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


source = (ROOT / "ralphie.sh").read_bytes()
sha = hashlib.sha256(source).hexdigest()
index = read("source-index.json")
inventory = read("function-inventory.json")
coverage = read("coverage.json")
manifest = read("map-manifest.json")
graph = read("graph.json")
raw = read(".graphify_extract.json")
check(all(x.get("source_sha256", x.get("sha256")) == sha for x in (index, inventory, coverage, manifest)), "all source-bound artifacts match current bytes")
expected = set((m.group(1).decode(), source[:m.start(1)].count(b"\n") + 1)
               for m in re.finditer(rb"(?m)^[ \t]*([A-Za-z_][A-Za-z_0-9]*)\(\)[ \t]*[({]", source))
actual = {(f["name"], f["start_line"]) for f in index["functions"]}
check(expected == actual and len(actual) == 234, "234 definitions agree with independent declaration scan")
reviewed = {(f["review"]["name"], f["review"]["start_line"]) for f in inventory["functions"]}
check(reviewed == actual, "every definition has a reviewed contract")
check(coverage["reviewed_line_ranges"] == [[1,1696],[1697,3161],[3162,5478]], "reviews cover all 5478 lines without overlap or gaps")
check(not index["parse_errors"] and len(index["parser_normalizations"]) == 9, "Bash parse and explicit normalization receipt")
nodes = {n["id"] for n in graph["nodes"]}
check(len(nodes) == len(graph["nodes"]) == len(raw["nodes"]), "all node identities survive export")
check(nodes == {n["id"] for n in raw["nodes"]}, "no graph node merged or lost")
pairs = {(e["source"], e["target"]) for e in graph["links"]}
check(len(pairs) == len(graph["links"]) == len(raw["edges"]), "edge endpoint pairs retain all aggregated evidence")
check(pairs == {(e["source"], e["target"]) for e in raw["edges"]}, "all directed relationships survive export")
check(all(a in nodes and b in nodes for a,b in pairs), "no dangling graph endpoints")
check({f["id"] for f in index["functions"]} <= nodes, "all 234 functions exist in graph")
check({(a,b) for a,b in pairs if a==b} == {("ralphie_kill_tree","ralphie_kill_tree")}, "only self-loop is source-backed kill_tree recursion")
check(all(1 <= int(n["source_location"][1:]) <= len(source.splitlines()) for n in graph["nodes"]), "all node source anchors are in range")
check(all(e.get("evidence") and all(1<=x["line"]<=5478 for x in e["evidence"]) for e in graph["links"]), "every edge retains valid source-line evidence")
check(manifest["graph_sha256"] == digest(OUT/"graph.json") and manifest["html_sha256"] == digest(OUT/"graph.html"), "graph and viewer hashes match manifest")
for name, expected_sha in manifest.get("artifact_sha256", {}).items():
    check(digest(OUT/name)==expected_sha, "manifest artifact unchanged: "+name)
snapshot = (OUT / "source.html").read_text()
lines = re.findall(r'<span class="line" id="L(\d+)"><a href="#L\d+">\s*\d+</a> (.*?)</span>', snapshot, flags=re.S)
check([int(n) for n,_ in lines] == list(range(1,5479)), "source browser has every line anchor exactly once")
check([html.unescape(s) for _,s in lines] == source.decode().splitlines(), "source browser preserves every reviewed line")
for name in ("COMPREHENSION.md", "FUNCTIONS.md", "INPUTS_OUTPUTS.md"):
    body=(OUT/name).read_text()
    check(sha in body, name+" is bound to the reviewed source")
    check(all(1<=int(n)<=5478 for n in re.findall(r"source\.html#L(\d+)",body)), name+" source anchors are in range")

class Scripts(HTMLParser):
    def __init__(self):
        super().__init__(); self.active=False; self.scripts=[]; self.sources=[]
    def handle_starttag(self,tag,attrs):
        if tag=="script":
            attrs=dict(attrs);self.active=True;self.scripts.append("")
            if "src" in attrs:self.sources.append(attrs["src"])
    def handle_endtag(self,tag):
        if tag=="script":self.active=False
    def handle_data(self,data):
        if self.active:self.scripts[-1]+=data
parser=Scripts();parser.feed((OUT/"graph.html").read_text())
check(not parser.sources, "viewer has no external script dependency")
node=shutil.which("node")
if not node:
    raise SystemExit("Node unavailable for analysis-only JavaScript syntax check")
for n,script in enumerate(parser.scripts):
    with tempfile.NamedTemporaryFile(mode="w",suffix=".js",dir=OUT,delete=False) as temp:
        temp.write(script); temporary=Path(temp.name)
    try:
        result=subprocess.run([node,"--check",str(temporary)],capture_output=True,text=True)
        check(result.returncode==0, f"viewer script {n+1} parses: "+result.stderr[:100])
    finally:
        temporary.unlink()
for row in (OUT/".pre-analysis-sha256").read_text().splitlines():
    before,name=row.split(maxsplit=1)
    check(digest(ROOT/name)==before, "pre-existing file unchanged: "+name)
check(subprocess.check_output(["git","diff","--binary"],cwd=ROOT)==(OUT/".pre-analysis.patch").read_bytes(), "tracked diff unchanged from task start")
check(subprocess.check_output(["git","rev-parse","HEAD"],cwd=ROOT).decode().strip()==(OUT/".pre-analysis-head").read_text().strip(), "Git HEAD unchanged")
result=dict(source_sha256=sha,verified_at=datetime.now(timezone.utc).isoformat(),checks=checks,
            counts=dict(definitions=len(actual),nodes=len(nodes),edges=len(pairs),commands=len(index['commands']),redirects=len(index['redirects']),heredocs=len(index['heredocs'])),
            scope="Source/analysis artifacts only. No product execution, provider calls, product tests, commits or pushes.")
(OUT/"verification.json").write_text(json.dumps(result,indent=2)+"\n")
print(f"PASS: {len(checks)} artifact checks; 234 definitions; {len(nodes)} nodes; {len(pairs)} edges; product bytes and Git HEAD unchanged.")
