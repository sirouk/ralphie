"""Add source-bound inspection to Graphify's viewer, with a pinned offline asset."""
import base64
import hashlib
import html
import json
from pathlib import Path
import re
import urllib.request

ASSET_URL = "https://unpkg.com/vis-network@9.1.6/standalone/umd/vis-network.min.js"
ASSET_SRI = "Ux6phic9PEHJ38YtrijhkzyJ8yQlH8i/+buBR8s3mAZOJrP1gwyvAcIYl3GWtpX1"


def enrich(out, source, sha):
    asset_path = out / ".vis-network-9.1.6.js"
    if asset_path.exists():
        asset = asset_path.read_bytes()
    else:
        with urllib.request.urlopen(ASSET_URL, timeout=30) as response:
            asset = response.read()
    if base64.b64encode(hashlib.sha384(asset).digest()).decode() != ASSET_SRI:
        raise ValueError("Pinned viewer asset integrity mismatch")
    asset_path.write_bytes(asset)
    graph = json.loads((out / "graph.json").read_text())
    metadata = {n["id"]: {"label": n.get("label", n["id"]),
                           "line": n.get("source_location", "L1"),
                           **n.get("metadata", {})} for n in graph["nodes"]}
    details = json.dumps(metadata, ensure_ascii=False).replace("<", "\\u003c")
    edges = json.dumps(graph["links"], ensure_ascii=False).replace("<", "\\u003c")
    raw = (out / "graph.html").read_text()
    raw, changed = re.subn(r'<script\b[^>]*src="https://unpkg.com/vis-network@9\.1\.6/standalone/umd/vis-network\.min\.js"[^>]*></script>',
                          lambda _: "<script>" + asset.decode().replace("</script", "<\\/script") + "</script>", raw)
    if changed != 1:
        raise ValueError("Expected exactly one pinned Graphify asset reference")
    styles = """<style>
    #sidebar{display:block;width:390px;max-width:48vw;overflow-y:auto} #info-panel{min-height:0}
    #info-content{overflow-wrap:anywhere} #legend-wrap{flex:0 0 auto}
    #map-header{padding:16px;border-bottom:1px solid #343454;font-size:12px;line-height:1.6}
    #map-header h1{font-size:20px;color:#fafafa} #map-header p{color:#bfc6da;margin:6px 0}
    #map-header a,#info-content a{color:#87c9ff} #map-view{width:100%;padding:6px;background:#101027;color:#eee;border:1px solid #565677}
    #info-content h4{margin-top:12px;color:#fff} #info-content ul{padding-left:18px}
    #info-content li{margin:4px 0} #info-content details{margin:7px 0} #neighbors-list{max-height:200px}
    @media(max-width:700px){#sidebar{width:45vw;max-width:45vw}#map-header{padding:8px}#map-header h1{font-size:16px}}
    </style>"""
    script = r"""<script>
    const MAP_DETAILS = __DETAILS__;
    const MAP_EDGES = __EDGES__;
    const mapHeader = document.createElement('section'); mapHeader.id='map-header';
    mapHeader.innerHTML='<h1>Ralphie · source map</h1><p>5,478 lines · 234 definitions<br>Source __SHORT_SHA__</p><p>Static relationships, not a runtime trace.</p><p><a href="COMPREHENSION.md">Read the comprehension map</a> · <a href="source.html">Browse source</a></p><label for="map-view">Graph view</label><select id="map-view"><option value="focus">Selected node and neighbors</option><option value="functions">Functions and calls</option><option value="cycle">Cycle and its direct dependencies</option><option value="all">All inputs, outputs and state</option></select><p id="visible-count"></p>';
    document.getElementById('sidebar').prepend(mapHeader);
    const mapView = document.getElementById('map-view');
    const revealed = new Set();
    let activeNode='ralphie_cycle_once';
    const cycleRoots = new Set(['ralphie_main','ralphie_run_prepare','ralphie_loop','ralphie_cycle_once','ralphie_cycle_begin','ralphie_cycle_observe','ralphie_cycle_act','ralphie_cycle_verify','ralphie_cycle_record','ralphie_record_outcome','ralphie_cycle_learn']);
    const cycleIds = new Set(cycleRoots);
    for(const edge of MAP_EDGES) if(cycleRoots.has(edge.source) && edge.relation.split(' / ').includes('calls')) cycleIds.add(edge.target);
    function applyMapView(){
      let count=0;
      const focused=new Set([activeNode]);
      for(const e of MAP_EDGES){if(e.source===activeNode)focused.add(e.target);if(e.target===activeNode)focused.add(e.source);}
      nodesDS.update(RAW_NODES.map(n=>{
        const m=MAP_DETAILS[n.id]||{};
        const allowed=mapView.value==='all'||(mapView.value==='focus'&&focused.has(n.id))||(mapView.value==='functions'&&['bash_function','bash_entrypoint','file','layer'].includes(m.kind))||(mapView.value==='cycle'&&cycleIds.has(n.id))||revealed.has(n.id);
        const hidden=!allowed||hiddenCommunities.has(n.community);
        if(!hidden)count++;
        return {id:n.id,hidden,physics:!hidden};
      }));
      document.getElementById('visible-count').textContent=count+' visible / '+RAW_NODES.length+' total nodes';
    }
    mapView.addEventListener('change',()=>{revealed.clear();applyMapView();network.fit({animation:true});});
    document.getElementById('legend-wrap').addEventListener('change',()=>queueMicrotask(applyMapView));
    function textValue(v){return typeof v==='string'?v:(v.description||v.summary||JSON.stringify(v));}
    function section(panel,title,values){
      if(!values||!values.length)return;
      const h=document.createElement('h4');h.textContent=title;panel.append(h);
      const ul=document.createElement('ul');
      for(const value of values){const li=document.createElement('li');li.textContent=textValue(value);ul.append(li);}panel.append(ul);
    }
    showInfo=function(nodeId){
      const m=MAP_DETAILS[nodeId];if(!m)return;
      activeNode=nodeId;
      if(mapView.value==='focus'){revealed.clear();applyMapView();network.fit({animation:true});}
      if(nodesDS.get(nodeId).hidden){revealed.add(nodeId);hiddenCommunities.delete(nodesDS.get(nodeId)._community);applyMapView();}
      const panel=document.getElementById('info-content');panel.replaceChildren();
      const title=document.createElement('strong');title.textContent=m.label;panel.append(title);
      const kind=document.createElement('p');kind.textContent=m.kind+(m.layer?' · '+m.layer:'');panel.append(kind);
      const link=document.createElement('a');link.href='source.html#'+m.line;link.target='_blank';link.rel='noopener';link.textContent='ralphie.sh:'+m.line.replace(/^L/,'')+(m.end_line?'–'+m.end_line:'');panel.append(link);
      if(m.summary){const p=document.createElement('p');p.textContent=m.summary;panel.append(p);}
      section(panel,'Inputs',m.inputs);section(panel,'Outputs',m.outputs);section(panel,'Side effects',m.side_effects);
      if(m.note){const p=document.createElement('p');p.textContent=m.note;panel.append(p);}
      if(m.contract){const d=document.createElement('details');const s=document.createElement('summary');s.textContent='Full reviewed contract';const p=document.createElement('pre');p.style.whiteSpace='pre-wrap';p.textContent=JSON.stringify(m.contract,null,2);d.append(s,p);panel.append(d);}
      const h=document.createElement('h4');h.textContent='Relationships';panel.append(h);
      const neighbors=document.createElement('div');neighbors.id='neighbors-list';
      for(const e of MAP_EDGES.filter(e=>e.source===nodeId||e.target===nodeId)){
        const dst=e.source===nodeId?e.target:e.source;
        const a=document.createElement('button');a.className='neighbor-link';a.style.cssText='color:#ddd;background:transparent;border:0;text-align:left;width:100%';
        a.textContent=(e.source===nodeId?'→ ':'← ')+(MAP_DETAILS[dst]?.label||dst)+' · '+e.relation;
        a.title=e.confidence+'; lines '+(e.evidence||[]).map(x=>x.line).join(', ');
        a.addEventListener('click',()=>focusNode(dst));neighbors.append(a);
      }panel.append(neighbors);
    };
    applyMapView();showInfo('ralphie_cycle_once');
    </script>""".replace("__DETAILS__", details).replace("__EDGES__", edges).replace("__SHORT_SHA__", sha[:16])
    raw = raw.replace("</head>", styles + "</head>").replace("</body>", script + "</body>")
    raw = re.sub(r"<title>.*?</title>", "<title>Ralphie — source and I/O map</title>", raw, count=1)
    (out / "graph.html").write_text(raw)
    lines = "".join(f'<span class="line" id="L{i}"><a href="#L{i}">{i:4}</a> {html.escape(value)}</span>' for i,value in enumerate(source.decode().splitlines(),1))
    (out / "source.html").write_text("""<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>ralphie.sh — reviewed source</title>
<style>body{margin:0;background:#101221;color:#dde2f1;font:14px/1.6 ui-monospace,monospace}header{padding:15px 24px;background:#1b2036;position:sticky;top:0;z-index:1}a{color:#8acbff}pre{padding:20px;width:max-content;min-width:95%}.line{display:block;scroll-margin-top:110px}.line:target{background:#36466c}.line>a{display:inline-block;width:4ch;color:#94a1be;margin-right:16px;text-decoration:none}</style>
<header><a href="graph.html">← Interactive graph</a> · ralphie.sh · read-only snapshot<br>SHA-256 """ + sha + "</header><pre>" + lines + "</pre></html>")
    (out / "viewer-asset.json").write_text(json.dumps({"url":ASSET_URL,"sha384_base64":ASSET_SRI,"embedded":True,"runtime_network_required":False,"license":"Vis Network MIT / Apache-2.0; original notices retained in embedded bundle."},indent=2)+"\n")
