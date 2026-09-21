#!/usr/bin/env python3
"""Reproduce a source-bound Ralphie map; never execute the subject script.

Requires the analysis-only Graphify interpreter recorded in .graphify_python.
Reviewed annotations must match the source hash; new source needs new review.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
from pathlib import Path
import re

from tree_sitter import Language, Parser
import tree_sitter_bash

OUT = Path(__file__).resolve().parent
ROOT = OUT.parent
SOURCE = ROOT / "ralphie.sh"
DATA = SOURCE.read_bytes()
SHA = hashlib.sha256(DATA).hexdigest()
LAYERS = [(1, "BOOTSTRAP"), (89, "CORE"), (282, "LEDGER"),
          (919, "PROJECT"), (2506, "ENGINE"), (3162, "LOOP"),
          (4314, "HUMAN"), (4630, "INTERFACE")]


def write(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def text(node):
    return DATA[node.start_byte:node.end_byte].decode("utf-8") if node else ""


def line(node):
    return node.start_point[0] + 1


def layer(at):
    return next(name for start, name in reversed(LAYERS) if at >= start)


def walk(node):
    yield node
    for child in node.children:
        yield from walk(child)


def ancestors(node):
    while node.parent is not None:
        node = node.parent
        yield node


def literal(value):
    if len(value) > 1 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]
    return value if value in (":", "{", "}") or re.fullmatch(r"[A-Za-z_][A-Za-z_0-9.-]*", value) else None


def index_source():
    tree = Parser(Language(tree_sitter_bash.language())).parse(DATA)
    all_nodes = list(walk(tree.root_node))
    errors = [n for n in all_nodes if n.type == "ERROR" or n.is_missing]
    if errors:
        raise SystemExit("Bash parse errors at " + ", ".join(str(line(n)) for n in errors))
    definitions = [n for n in all_nodes if n.type == "function_definition"]
    functions, by_start, by_name = [], {}, defaultdict(list)
    for n in definitions:
        name = text(n.child_by_field_name("name"))
        enclosing = next((p for p in ancestors(n) if p.type == "function_definition"), None)
        ident = "ralphie_" + name + ("__L" + str(line(n)) if enclosing else "")
        record = dict(id=ident, name=name, start_line=line(n), end_line=n.end_point[0] + 1,
                      start_byte=n.start_byte, end_byte=n.end_byte, layer=layer(line(n)),
                      enclosing_start_line=line(enclosing) if enclosing else None)
        functions.append(record)
        by_start[n.start_byte] = record
        by_name[name].append(record)

    def owner(n):
        parent = next((p for p in ancestors(n) if p.type == "function_definition"), None)
        return by_start[parent.start_byte]["id"] if parent else "ralphie_sh__entry"

    commands, redirects, variables, assignments, heredocs, cases = [], [], [], [], [], []
    normalizations=[]
    for n in all_nodes:
        base = dict(function_id=owner(n), line=line(n), end_line=n.end_point[0] + 1)
        if n.type == "command":
            name_node = n.child_by_field_name("name")
            name = literal(text(name_node))
            arguments = [text(c) for i, c in enumerate(n.children)
                         if n.field_name_for_child(i) == "argument"]
            resolution_override=None
            # tree-sitter-bash 0.25.1 reports no ERROR but misgroups several valid
            # negated brace groups and a redirected test. Preserve the raw node
            # and record these source-checked corrections explicitly.
            if name in ("{", "then") and arguments:
                normalizations.append(dict(line=line(n),raw=text(n),correction="group/keyword prefix, not command name"))
                name=literal(arguments.pop(0))
            elif name in ("}", "fi", "then"):
                resolution_override="syntax_only"
                normalizations.append(dict(line=line(n),raw=text(n),correction="closing syntax, not execution"))
            elif text(n).endswith(" ]") and any(p.type=="test_command" for p in ancestors(n)):
                resolution_override="test_operand_not_execution"
                normalizations.append(dict(line=line(n),raw=text(n),correction="test operand, not dynamic dispatch"))
            possible = by_name.get(name, [])
            enclosing_ids = [by_start[p.start_byte]["id"] for p in ancestors(n)
                             if p.type == "function_definition"]
            local_targets = [f for f in possible if f["enclosing_start_line"] and any(
                parent["id"] in enclosing_ids and parent["start_line"] == f["enclosing_start_line"]
                for parent in functions)]
            targets = local_targets or possible
            commands.append(dict(base, command=text(name_node), literal_command=name,
                                 arguments=arguments, source=text(n),
                                 internal_targets=[f["id"] for f in targets],
                                 resolution=resolution_override or ("context_dependent" if len(targets) > 1 else
                                            "internal" if targets else "literal_external_or_builtin" if name else "dynamic"
                                 ),
                                 substitutions=[p.type for p in ancestors(n) if p.type in
                                                ("command_substitution", "process_substitution", "subshell")]))
        elif n.type in ("file_redirect", "herestring_redirect"):
            dest = n.child_by_field_name("destination")
            redirects.append(dict(base, type=n.type, source=text(n), destination=text(dest),
                                  operators=[text(c) for c in n.children if not c.is_named]))
        elif n.type == "heredoc_redirect":
            body = next((c for c in n.children if c.type == "heredoc_body"), None)
            marker = next((c for c in n.children if c.type == "heredoc_start"), None)
            heredocs.append(dict(base, marker=text(marker), body_start_line=line(body) if body else None,
                                 body_end_line=body.end_point[0]+1 if body else None,
                                 interpolated=not any(c in text(marker) for c in "\"'\\"), body=text(body)))
        elif n.type in ("simple_expansion", "expansion"):
            name = next((c for c in n.children if c.type in ("variable_name", "special_variable_name")), None)
            op = n.child_by_field_name("operator")
            variables.append(dict(base, name=text(name), expression=text(n), operator=text(op)))
        elif n.type == "variable_assignment":
            declaration = next((p for p in ancestors(n) if p.type == "declaration_command"), None)
            assignments.append(dict(base, name=text(n.child_by_field_name("name")),
                                    value=text(n.child_by_field_name("value")), source=text(n),
                                    declaration=text(declaration).split()[0] if declaration else None))
        elif n.type == "case_item":
            # Adjacent value nodes can be fragments of ONE quoted/glob pattern.
            # Only a top-level | token separates case alternatives.
            values, start, end = [], None, None
            fragments = []
            for i, c in enumerate(n.children):
                if c.type in ("|", ")") and not c.is_named:
                    if start is not None:
                        values.append(DATA[start:end].decode("utf-8"))
                    start, end = None, None
                    if c.type == ")":
                        break
                elif n.field_name_for_child(i) == "value":
                    fragments.append(text(c))
                    if start is None:
                        start = c.start_byte
                    end = c.end_byte
            cases.append(dict(base, patterns=values, pattern_fragments=fragments, source=text(n)))
    result = dict(schema_version=1, source_file="ralphie.sh", source_sha256=SHA,
                  source_lines=len(DATA.splitlines()), parse_errors=[], functions=functions,
                  commands=commands, redirects=redirects, variable_expansions=variables,
                  assignments=assignments, heredocs=heredocs, case_branches=cases, parser_normalizations=normalizations,
                  limitations=["Static command sites are possible execution, not a runtime trace.",
                               "Bash dynamically scoped variables and runtime functions can change bindings.",
                               "Quoted/constructed programs executed by bash, awk, sed, Python, Node, engines, or hooks remain separate contracts.",
                               "Redirect inventory is syntactic; commands also access files without shell redirection."])
    write("source-index.json", result)
    write("call-sites.json", [c for c in commands if c["internal_targets"]])
    print(f"Indexed {len(functions)} definitions, {len(commands)} command sites, {len(redirects)} redirects, {len(heredocs)} heredocs; no Bash parse errors.")
    return result


def make_graph(index, reviews):
    from graphify.build import build_from_json
    from graphify.cluster import cluster, score_all
    from graphify.analyze import god_nodes, surprising_connections, suggest_questions
    from graphify.report import generate
    from graphify.export import to_json
    from graphify.exporters.html import to_html
    from graphify.diagnostics import diagnose_extraction
    from graphify.detect import save_manifest

    annotations = {}
    for review in reviews:
        if review.get("source_sha256") != SHA:
            raise SystemExit("Review source hash mismatch")
        for f in review["functions"]:
            key = (f["name"], f["start_line"])
            if key in annotations:
                raise SystemExit(f"Duplicate review: {key}")
            annotations[key] = f
    actual = {(f["name"], f["start_line"]) for f in index["functions"]}
    if actual != set(annotations):
        raise SystemExit(f"Review coverage mismatch; missing={sorted(actual-set(annotations))}, extra={sorted(set(annotations)-actual)}")
    for f in index["functions"]:
        reviewed = annotations[(f["name"], f["start_line"])]
        if f["end_line"] != reviewed["end_line"]:
            raise SystemExit(f"Review endpoint mismatch: {f['name']} at {f['start_line']}")
    next_line = 1
    for review in sorted(reviews, key=lambda r: r["reviewed_line_range"][0]):
        first, last = review["reviewed_line_range"]
        if first != next_line or last < first:
            raise SystemExit("Source review has a gap or overlap")
        next_line = last + 1
    if next_line != len(DATA.splitlines()) + 1:
        raise SystemExit("Source review did not reach the end of the script")

    nodes = {}; edges = {}
    def node(ident, label, kind, at=1, **metadata):
        nodes.setdefault(ident, dict(id=ident, label=label, file_type="code", source_file="ralphie.sh",
                                    source_location=f"L{at}", _origin="semantic" if kind=="reviewed_interface" else "ast",
                                    metadata=dict(kind=kind, **metadata)))
    def edge(src, dst, relation, at, confidence="EXTRACTED", **context):
        if src not in nodes or dst not in nodes:
            raise ValueError((src,dst))
        key=(src,dst)
        if key not in edges:
            edges[key]=dict(source=src, target=dst, relation=relation, confidence=confidence,
                            source_file="ralphie.sh", source_location=f"L{at}", weight=1.0,
                            evidence=[dict(line=at, relation=relation, confidence=confidence, **context)])
        else:
            edges[key]["evidence"].append(dict(line=at, relation=relation, confidence=confidence, **context))
            if edges[key]["confidence"] != confidence:
                edges[key]["confidence"]="AMBIGUOUS"
            if relation not in edges[key]["relation"].split(" / "):
                edges[key]["relation"] += " / " + relation

    node("ralphie", "ralphie.sh", "file")
    node("ralphie_sh__entry", "Bootstrap and script entry", "bash_entrypoint")
    edge("ralphie","ralphie_sh__entry","contains",1)
    for at, name in LAYERS:
        node("layer_"+name, name, "layer", at)
        edge("ralphie", "layer_"+name, "contains_layer", at)
    for f in index["functions"]:
        annotation=annotations[(f["name"],f["start_line"])]
        f["review"]=annotation
        node(f["id"], f["name"]+"()"+(f" [L{f['start_line']}]" if f["enclosing_start_line"] else ""),
             "bash_function", f["start_line"], end_line=f["end_line"], layer=f["layer"],
             summary=annotation.get("summary", ""), inputs=annotation.get("inputs", []),
             outputs=annotation.get("outputs", []), side_effects=annotation.get("side_effects", []))
        edge("layer_"+f["layer"],f["id"],"defines",f["start_line"])
    builtins=set(": { } then fi alias bg bind break builtin caller cd command compgen complete continue declare dirs disown echo enable eval exec exit export false fc fg getopts hash help history jobs kill let local logout mapfile popd printf pushd pwd read readonly return set shift shopt source test time times trap true type typeset ulimit umask unalias unset wait".split())
    for c in index["commands"]:
        src=c["function_id"]
        if c["resolution"] in ("syntax_only", "test_operand_not_execution"):
            continue
        for dst in c["internal_targets"]:
            edge(src,dst,"calls",c["line"], "AMBIGUOUS" if c["resolution"]=="context_dependent" else "EXTRACTED",
                 source=c["source"][:300], substitutions=c["substitutions"], resolution=c["resolution"])
        name=c["literal_command"]
        if not c["internal_targets"] and name and name not in builtins:
            ident="command_"+re.sub(r"[^A-Za-z0-9_]","_",name)
            node(ident,name,"external_command",c["line"])
            edge(src,ident,"invokes_command",c["line"], source=c["source"][:300])
        if c["resolution"]=="dynamic":
            ident="dynamic_L"+str(c["line"])
            node(ident,c["command"],"dynamic_execution",c["line"], source=c["source"][:500])
            edge(src,ident,"dynamic_dispatch",c["line"], resolution="runtime value not resolved")
        if name in ("exec", "eval") and c["arguments"]:
            ident="dispatch_L"+str(c["line"])
            node(ident,c["source"][:120],"shell_execution_boundary",c["line"], source=c["source"],
                 note="Exec argv or evaluated shell text; downstream program behavior is outside this graph.")
            edge(src,ident,"executes_argv" if name=="exec" else "evaluates_shell",c["line"])
        if name=="trap":
            for f in index["functions"]:
                if re.search(r"\b"+re.escape(f["name"])+r"\b", " ".join(c["arguments"])):
                    edge(src,f["id"],"registers_trap",c["line"], source=c["source"])
        if name=="count_of" and c["arguments"]:
            callback=literal(c["arguments"][0])
            for f in index["functions"]:
                if f["name"]==callback:
                    edge(src,f["id"],"passes_callable_to_count_of",c["line"], source=c["source"])

    # Whitelisted state keys are a finite, directly inspectable persistent interface.
    state_assignment=next(a for a in index["assignments"] if a["name"]=="STATE_KEYS")
    state_keys=re.findall(r"[a-z][a-z_]+",state_assignment["value"])
    for key in state_keys:
        node("state_"+key,key,"persistent_state_key",state_assignment["line"])
    for c in index["commands"]:
        if c["literal_command"] in ("state_get","state_set","state_bump","json_num","json_dec") and c["arguments"]:
            key=literal(c["arguments"][0])
            if key in state_keys:
                if c["literal_command"] in ("state_get","json_num","json_dec"):
                    edge("state_"+key,c["function_id"],"read_by",c["line"])
                else:
                    edge(c["function_id"],"state_"+key,"writes_or_bumps",c["line"])

    cli_cases=[c for c in index["case_branches"] if c["function_id"]=="ralphie_parse_args"]
    for c in cli_cases:
        for pattern in c["patterns"]:
            if re.fullmatch(r"(?:--?[a-z][a-z-]*|[a-z]+|--)",pattern):
                ident="cli_"+pattern.replace("-","_")
                node(ident,pattern,"cli_input",c["line"])
                edge(ident,"ralphie_parse_args","parsed_by",c["line"])

    # Keep every lexical variable site in the index; show shared uppercase state only.
    read_by=defaultdict(set); write_by=defaultdict(set)
    for v in index["variable_expansions"]:
        if re.fullmatch(r"[A-Z][A-Z_0-9]*",v["name"]): read_by[v["name"]].add(v["function_id"])
    for a in index["assignments"]:
        if re.fullmatch(r"[A-Z][A-Z_0-9]*",a["name"]): write_by[a["name"]].add(a["function_id"])
    shared={n for n in set(read_by)|set(write_by) if len(read_by[n]|write_by[n])>1}
    for name in sorted(shared):
        first_line=min(v["line"] for v in index["variable_expansions"]+index["assignments"] if v["name"]==name)
        node("var_"+name,name,"shell_variable",first_line, binding="lexical; Bash dynamic scope may shadow")
    for v in index["variable_expansions"]:
        if v["name"] in shared: edge("var_"+v["name"],v["function_id"],"expanded_by",v["line"])
    for a in index["assignments"]:
        if a["name"] in shared: edge(a["function_id"],"var_"+a["name"],"assigns",a["line"])

    # Path bindings and literal redirects complement calls: commands have data I/O.
    path_variables={"PROJECT", "SELF", "HOME_DIR", "STATE_FILE", "EVENTS_FILE", "GATES_FILE",
                    "OBJECTIVE_FILE", "ASK_FILE", "MEMORY_FILE", "LOG_DIR", "RUN_DIR", "LOCK_FILE", "STOP_FILE"}
    for a in index["assignments"]:
        if a["name"] in path_variables and a["function_id"] in ("ralphie_sh__entry", "ralphie_project_bind"):
            ident="path_"+a["name"]+"_L"+str(a["line"])
            node(ident,a["value"],"path_binding",a["line"],variable=a["name"])
            edge(a["function_id"],ident,"binds_path",a["line"])
            if a["name"] in shared: edge(ident,"var_"+a["name"],"named_by",a["line"])
    for v in index["variable_expansions"]:
        if (v["name"].startswith("RALPHIE_") or v["name"] in {"NO_COLOR","TERM","TMPDIR","HOME","PATH"}) and v["name"] not in {"RALPHIE_NL","RALPHIE_CONTRACT"}:
            ident="input_"+v["name"]
            node(ident,v["name"],"environment_or_exported_input",v["line"],
                 note="May also be internally exported or overridden; inspect assignment sites.")
            edge(ident,v["function_id"],"expanded_input",v["line"],expression=v["expression"])
    for a in index["assignments"]:
        if a["name"].startswith("RALPHIE_") and a["name"] not in {"RALPHIE_NL","RALPHIE_CONTRACT"}:
            ident="input_"+a["name"]
            node(ident,a["name"],"environment_or_exported_input",a["line"])
            edge(a["function_id"],ident,"assigns_environment_value",a["line"],value=a["value"])
    for r in index["redirects"]:
        # Same-looking local $out in two functions is not a single filesystem object.
        ident="redirect_"+hashlib.sha256((r["function_id"]+"\0"+r["destination"]+"\0"+str(r["operators"])).encode()).hexdigest()[:16]
        node(ident,r["source"],"shell_redirection_endpoint",r["line"],
             owner=r["function_id"],destination=r["destination"],operators=r["operators"],
             note="Symbolic target; path/descriptor and actual bytes depend on runtime values.")
        incoming=any("<" in operator for operator in r["operators"])
        if incoming: edge(ident,r["function_id"],"redirects_input",r["line"])
        else: edge(r["function_id"],ident,"redirects_output",r["line"])

    # Reviewed interfaces include file access inside commands and embedded programs,
    # which shell redirect syntax alone cannot describe. Range overlap is a navigation
    # relationship, deliberately not an inferred call or exact dataflow direction.
    for review_no, review in enumerate(reviews):
        for interface_no, interface in enumerate(review.get("interfaces", [])):
            interface_id = interface.get("id", interface.get("kind", "contract") + "_" + str(interface_no))
            ident = f"interface_{review_no}_" + interface_id
            evidence = interface.get("evidence", []) + interface.get("additional_evidence", [])
            if not evidence:
                evidence = [dict(start_line=n, end_line=n) for n in interface.get("source_lines", [])]
            starts = [e["start_line"] for e in evidence if "start_line" in e]
            at = min(starts) if starts else review["reviewed_line_range"][0]
            node(ident, interface.get("name", interface_id.replace("_", " ").replace("-", " ")), "reviewed_interface", at,
                 summary=interface.get("summary", interface.get("description", interface.get("name", ""))),
                 contract=interface, note="Source-reviewed interface; association edges are source-range overlaps, not execution.")
            associated = set()
            for e in evidence:
                if "start_line" not in e:
                    continue
                for f in index["functions"]:
                    if f["start_line"] <= e.get("end_line", e["start_line"]) and f["end_line"] >= e["start_line"]:
                        associated.add(f["id"])
                        edge(f["id"], ident, "interface_evidence_overlaps", max(f["start_line"], e["start_line"]),
                             "INFERRED", evidence_range=[e["start_line"], e.get("end_line", e["start_line"])])
            if not associated:
                edge("ralphie_sh__entry", ident, "documents_top_level_interface", at, "INFERRED")

    extraction=dict(nodes=list(nodes.values()),edges=list(edges.values()),hyperedges=[],input_tokens=0,output_tokens=0)
    write(".graphify_extract.json",extraction)
    write("function-inventory.json",dict(source_sha256=SHA,functions=index["functions"]))
    catalogue=["# Function catalogue", "", "Pinned source SHA-256: `"+SHA+"`. All 234 definitions, including the nested archive function and both preview-only overrides.", "",
               "Each function links to the frozen source. Full inputs, outputs, side effects, failures and callbacks are in [function-inventory.json](function-inventory.json) and the detailed reviews: [core/ledger/gates](core_ledger_gates.review.md), [Git/engines](git_engine.review.md), [loop/human/interface](loop_human_interface.review.md).", ""]
    last_layer=None
    for f in index["functions"]:
        if f["layer"] != last_layer:
            last_layer=f["layer"]
            catalogue += ["", "## "+last_layer, "", "| Function | Lines | Responsibility |", "|---|---:|---|"]
        summary=f["review"]["summary"].replace("|", "\\|").replace("\n", " ")
        catalogue.append(f"| [`{f['name']}`](source.html#L{f['start_line']}) | {f['start_line']}–{f['end_line']} | {summary} |")
    (OUT/"FUNCTIONS.md").write_text("\n".join(catalogue)+"\n")
    write("interfaces.json",dict(source_sha256=SHA,reviews=[dict(reviewed_line_range=r["reviewed_line_range"],
                                                              interfaces=r.get("interfaces",[]),
                                                              relationships=r.get("relationships",[]),
                                                              limitations=r.get("limitations",[])) for r in reviews]))
    G=build_from_json(extraction,root=ROOT,directed=True)
    if set(G.nodes) != set(nodes) or set(G.edges) != set(edges):
        raise SystemExit(f"Graph normalization lost identities: nodes={sorted(set(nodes)-set(G.nodes))}, edges={len(set(edges)-set(G.edges))}")
    communities=cluster(G)
    cohesion=score_all(G,communities)
    labels={}
    for cid,members in communities.items():
        distribution=Counter(G.nodes[n].get("metadata",{}).get("layer") for n in members if G.nodes[n].get("metadata",{}).get("layer"))
        labels[cid]=" / ".join(k.title() for k,_ in distribution.most_common(2)) or "Shared interfaces"
    gods=god_nodes(G); surprises=surprising_connections(G,communities)
    questions=suggest_questions(G,communities,labels)
    detection=json.loads((OUT/".graphify_detect.json").read_text())
    if not to_json(G,communities,str(OUT/"graph.json"),community_labels=labels):
        raise SystemExit("Graph export refused; inspect shrink guard")
    report=generate(G,communities,cohesion,labels,gods,surprises,detection,
                    {"input":0,"output":0},str(ROOT),suggested_questions=questions)
    report += "\n## Scope and measurement limits\n\nThis graph is bound to source SHA-256 `"+SHA+"`. All 234 Bash definitions are indexed and reviewed, including subshell overrides and the nested archive function. Calls are possible static routes, not observed execution. Shared variable edges are lexical, not a claim of unique runtime storage. Arbitrary gate/engine/hook programs remain open interfaces.\n\nThe zero token figure above covers deterministic extraction only. Host-agent and delegated source-review tokens are unavailable through these tools; total analysis tokens and monetary cost are unknown, not zero.\n"
    (OUT/"GRAPH_REPORT.md").write_text(report)
    write(".graphify_analysis.json",dict(communities={str(k):v for k,v in communities.items()},cohesion=cohesion,gods=gods,surprises=surprises,questions=questions))
    write(".graphify_labels.json",{str(k):v for k,v in labels.items()})
    diagnostics=diagnose_extraction(extraction,directed=True,root=ROOT)
    write("graph-health.json",diagnostics)
    if not to_html(G,communities,str(OUT/"graph.html"),community_labels=labels):
        raise SystemExit("HTML export failed")
    from render_map import enrich
    enrich(OUT, DATA, SHA)
    write("coverage.json",dict(source_sha256=SHA,source_lines=len(DATA.splitlines()),
                                function_definitions=len(index["functions"]),unique_function_names=len({f["name"] for f in index["functions"]}),
                                reviewed_definitions=len(annotations),missing_reviews=[],parse_errors=[],
                                parser_normalizations=index['parser_normalizations'],
                                reviewed_line_ranges=[r["reviewed_line_range"] for r in reviews],
                                static_command_sites=len(index["commands"]),shell_redirects=len(index["redirects"]),heredocs=len(index["heredocs"]),
                                graph_nodes=G.number_of_nodes(),graph_edges=G.number_of_edges(),communities=len(communities)))
    write("cost.json",dict(structural_input_tokens=0,structural_output_tokens=0,host_review_tokens=None,
                            total_analysis_tokens=None,total_cost=None,note="No external semantic-extraction API or engine invocation. Session review usage not exposed."))
    save_manifest(detection['files'], str(OUT/"manifest.json"), kind="ast", root=ROOT,
                  scan_corpus={str(SOURCE)})
    write("map-manifest.json",dict(source_file="ralphie.sh",sha256=SHA,graph_sha256=hashlib.sha256((OUT/"graph.json").read_bytes()).hexdigest(),
                                html_sha256=hashlib.sha256((OUT/"graph.html").read_bytes()).hexdigest(),
                                graphify_version=importlib.metadata.version("graphifyy"),
                                tree_sitter_bash_version=importlib.metadata.version("tree-sitter-bash"),
                                generated_at=datetime.now(timezone.utc).isoformat(),
                                rebuild="Run build_map.py with .graphify_python; source changes require fresh reviewed annotations.",
                                artifact_sha256={name:hashlib.sha256((OUT/name).read_bytes()).hexdigest() for name in
                                    ("COMPREHENSION.md","INPUTS_OUTPUTS.md","FUNCTIONS.md","source-index.json","function-inventory.json",
                                     "interfaces.json","trace-proof.json","source.html","build_map.py","render_map.py","verify_map.py",
                                     "core_ledger_gates.review.json","git_engine.review.json","loop_human_interface.review.json") if (OUT/name).is_file()},
                                structural_validation="verify_map.py", static_analysis_only=True,
                                semantic_reviews_bound_to_source=True))
    if hashlib.sha256(SOURCE.read_bytes()).hexdigest()!=SHA:
        raise SystemExit("Source changed while the map was being built; do not use these artifacts")
    print(f"Graph complete: {G.number_of_nodes()} nodes, {G.number_of_edges()} edges, {len(communities)} communities; {len(annotations)} reviewed definitions.")


if __name__ == "__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--index-only",action="store_true")
    args=parser.parse_args()
    index=index_source()
    if not args.index_only:
        review_names=("core_ledger_gates.review.json","git_engine.review.json","loop_human_interface.review.json")
        reviews=[json.loads((OUT/n).read_text()) for n in review_names]
        make_graph(index,reviews)
