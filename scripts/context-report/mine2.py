#!/usr/bin/env python3
"""Second pass: residency-weighted cost, tail analysis, bash breakdown, main-session composition."""
import json, os, re, glob, statistics, collections, datetime
ROOT = os.path.expanduser("~/.claude/projects/-Users-junhanliu-SBM-Projects-portal-quota-com-au")

def rel(p):
    p = re.sub(r"^/Users/junhanliu/SBM_Projects/(portal\.quota\.com\.au|\.espalier-worktrees/[^/]+/[^/]+|worktrees/[^/]+/[^/]+)/", "", p)
    return p

def cat_path(p):
    p = rel(p)
    if p.startswith("/"): return "outside-repo"
    if p.startswith("espalier/rules/"): return "esp.rules"
    if p.startswith("espalier/agents/"): return "esp.agents"
    if p.startswith("espalier/skills/") and "/specs/" in p: return "esp.specs"
    if p.startswith("espalier/skills/"): return "esp.skill"
    if p.startswith("espalier/wiki/"): return "esp.wiki"
    if p.startswith("espalier/maps/"): return "esp.maps"
    if p in ("espalier/pipeline.md", "espalier/agent.md"): return "esp.pipeline+agent"
    if p.startswith("espalier/changes/"):
        b = os.path.basename(p)
        if b.startswith("coding-report"): return "chg.coding-report"
        if b == "requirements.md": return "chg.requirements"
        if b == "context-pack.md": return "chg.context-pack"
        if b == "review-record.md": return "chg.review-record"
        if b == "security-record.md": return "chg.security-record"
        if b == "pipeline-state.md": return "chg.pipeline-state"
        return "chg.other"
    if p.startswith("espalier/"): return "esp.other"
    if p.endswith("CLAUDE.md"): return "CLAUDE.md"
    if "__generated__" in p: return "code.generated"
    if "node_modules" in p: return "node_modules"
    if re.search(r"\.(test|spec)\.(ts|tsx|js)$", p): return "code.tests"
    if p.endswith((".prisma", ".graphql")): return "code.schema"
    if p.startswith(("backend/", "frontend/", "mobile/")): return "code.src"
    if p.startswith("scratchpad/") or "/scratchpad/" in p: return "scratchpad"
    return "other:" + p[:30]

PATH_RE = re.compile(r"((?:/Users/junhanliu/SBM_Projects/[^\s'\"]+?/)?(?:espalier|backend|frontend|mobile|scratchpad)/[\w./@\-\[\]]+)")

def text_len(c):
    if isinstance(c, str): return len(c)
    if isinstance(c, list): return sum(len(b.get("text", "")) if isinstance(b, dict) else len(str(b)) for b in c)
    return 0

def parse(path):
    out = []
    with open(path) as fh:
        for line in fh:
            try: out.append(json.loads(line))
            except Exception: pass
    return out

def bash_kind(cmd):
    c = cmd.strip()
    if re.search(r"\b(vitest|npm (run )?test|npx vitest|test:coverage|jest)\b", c): return "bash.test"
    if re.search(r"\b(npm run build|tsc|next build|keystone build|npm run lint|eslint|npx tsc)\b", c): return "bash.build/lint"
    if re.search(r"\bgit (diff|show)\b", c): return "git-diff"
    if re.search(r"\bgit (log|status|branch|rev-parse|ls-files|blame)\b", c): return "git.meta"
    if re.search(r"^\s*(cat|sed -n|head|tail|less)\b", c) or re.search(r"\b(cat|sed -n|head|tail) [^|;&]*\.(md|ts|tsx|json|prisma|sh)", c): return "bash.read"
    if re.search(r"\b(grep|rg|find|ls|wc|awk)\b", c): return "bash.search"
    if re.search(r"\b(docker|curl)\b", c): return "bash.docker/curl"
    return "bash.other"

def analyse(recs, is_main=False):
    msgs = {}; order = []; tool_uses = {}; events = []  # events: (turn_index, category, bytes, label)
    model = None; first_ts = None; last_ts = None
    turn = 0; first_edit_turn = None
    for o in recs:
        t = o.get("type"); ts = o.get("timestamp")
        if ts:
            first_ts = first_ts or ts; last_ts = ts
        if t == "assistant":
            m = o["message"]; mid = m.get("id") or o.get("uuid")
            if mid not in msgs: order.append(mid); turn = len(order)
            msgs[mid] = m.get("usage") or msgs.get(mid) or {}
            model = model or m.get("model")
            for c in m.get("content", []) or []:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    tool_uses[c["id"]] = (c["name"], c.get("input") or {}, turn)
                    if c["name"] in ("Edit", "Write", "MultiEdit") and first_edit_turn is None:
                        p = (c.get("input") or {}).get("file_path", "")
                        if not p.endswith((".md",)) or "espalier/changes" not in p: first_edit_turn = turn
        elif t == "user":
            c = o["message"].get("content")
            blocks = c if isinstance(c, list) else []
            for b in blocks:
                if not isinstance(b, dict) or b.get("type") != "tool_result": continue
                n = text_len(b.get("content"))
                name, inp, tu = tool_uses.get(b.get("tool_use_id"), ("?", {}, turn))
                if name == "Read": events.append((tu, cat_path(inp.get("file_path", "?")), n, rel(inp.get("file_path", "?"))))
                elif name == "Bash":
                    cmd = inp.get("command", ""); k = bash_kind(cmd)
                    if k == "bash.read":
                        m2 = PATH_RE.search(cmd); p = m2.group(1) if m2 else "?"
                        events.append((tu, cat_path(p), n, rel(p)))
                    else: events.append((tu, k, n, cmd[:70].replace("\n", " ")))
                elif name in ("Grep", "Glob"): events.append((tu, "grep/glob", n, name))
                elif name == "Agent": events.append((tu, "agent-result", n, inp.get("subagent_type", "?") + ": " + inp.get("description", "")[:40]))
                elif name in ("Edit", "Write", "MultiEdit"): events.append((tu, "edit-result", n, name))
                else: events.append((tu, "tool." + name, n, name))
    usages = [msgs[i] for i in order if msgs[i]]
    if not usages: return None
    ctx = [u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0) + u.get("cache_read_input_tokens", 0) for u in usages]
    T = len(ctx)
    # residency-weighted: bytes * (turns remaining after the read)
    res = collections.Counter(); raw = collections.Counter()
    for tu, cat, n, lab in events:
        res[cat] += n * max(T - tu, 0); raw[cat] += n
    return dict(model=model, first_ts=first_ts, last_ts=last_ts, calls=T, ctx=ctx, first_ctx=ctx[0], peak=max(ctx), total_in=sum(ctx),
                total_out=sum(u.get("output_tokens", 0) for u in usages), events=events, res=res, raw=raw, first_edit_turn=first_edit_turn)

def med(xs): return int(statistics.median(xs)) if xs else 0

subs = []
for meta in glob.glob(os.path.join(ROOT, "*", "subagents", "agent-*.meta.json")):
    jl = meta.replace(".meta.json", ".jsonl")
    if not os.path.exists(jl): continue
    m = json.load(open(meta)); a = analyse(parse(jl))
    if not a: continue
    a["type"] = m.get("agentType", "?"); a["desc"] = m.get("description", ""); subs.append(a)
by = collections.defaultdict(list)
for a in subs: by[a["type"]].append(a)

print("## Residency-weighted share of context-turns by category (what actually drives total_in), per type")
print("   (bytes x turns-remaining; the first-turn baseline is shown as 'BASELINE(system+rules+prompt)' from usage)")
for t in ("harness-coder", "harness-reviewer", "harness-security", "scout"):
    xs = by[t]; tot = collections.Counter()
    for a in xs: tot.update(a["res"])
    # baseline in token-turns: first_ctx * calls ; convert reads bytes->tokens ~ /3.6
    base_tt = sum(a["first_ctx"] * a["calls"] for a in xs)
    out_tt = sum(a["total_out"] for a in xs)  # rough: outputs also accumulate; approximate as out * calls/2
    read_tt = {k: v / 3.6 for k, v in tot.items()}
    total_in = sum(a["total_in"] for a in xs)
    explained = base_tt + sum(read_tt.values())
    print(f"\n### {t} n={len(xs)}  sum total_in={total_in/1e6:.0f}M   baseline(first_ctx x calls)={base_tt/1e6:.0f}M ({100*base_tt/total_in:.0f}%)   tool-reads(est)={sum(read_tt.values())/1e6:.0f}M ({100*sum(read_tt.values())/total_in:.0f}%)   rest=assistant output accumulation")
    for k, v in sorted(read_tt.items(), key=lambda kv: -kv[1])[:16]:
        print(f"   {k:22} {v/1e6:7.1f}M token-turns  ({100*v/total_in:4.1f}% of total_in)   raw={tot[k]/1024/len(xs):6.1f} KB/spawn")

print("\n## Tail analysis (coder): share of total_in from top spawns; spawns by peak context")
xs = sorted(by["harness-coder"], key=lambda a: -a["total_in"]); tot = sum(a["total_in"] for a in xs)
for frac in (0.1, 0.2, 0.3):
    k = int(len(xs) * frac); print(f"   top {int(frac*100)}% ({k} spawns) = {100*sum(a['total_in'] for a in xs[:k])/tot:.0f}% of coder total_in")
for lim in (100000, 150000, 200000, 300000, 400000):
    n = sum(1 for a in xs if a["peak"] > lim); print(f"   spawns with peak ctx > {lim//1000}k: {n} ({100*n/len(xs):.0f}%)")
above = sum(c for a in xs for c in a["ctx"] if c > 200000); print(f"   tokens processed on turns where ctx > 200k: {above/1e6:.0f}M = {100*above/tot:.0f}% of coder total_in")
above = sum(c for a in xs for c in a["ctx"] if c > 150000); print(f"   tokens processed on turns where ctx > 150k: {above/1e6:.0f}M = {100*above/tot:.0f}%")
print("   calls distribution: median=%d p75=%d p90=%d max=%d" % (med([a['calls'] for a in xs]), sorted(a['calls'] for a in xs)[int(len(xs)*.75)], sorted(a['calls'] for a in xs)[int(len(xs)*.9)], max(a['calls'] for a in xs)))
for t in ("harness-reviewer", "harness-security"):
    ys = by[t]; tt = sum(a["total_in"] for a in ys)
    above = sum(c for a in ys for c in a["ctx"] if c > 150000)
    print(f"   {t}: calls median={med([a['calls'] for a in ys])} p90={sorted(a['calls'] for a in ys)[int(len(ys)*.9)]}  peak>200k: {sum(1 for a in ys if a['peak']>200000)}  share of total_in at ctx>150k: {100*above/tt:.0f}%")

print("\n## Coder: turns before first source edit (discovery phase), pack-read vs no-pack")
pk = [a for a in by["harness-coder"] if any(c == "chg.context-pack" for _, c, _, _ in a["events"])]
npk = [a for a in by["harness-coder"] if a not in pk]
for lab, grp in (("read pack", pk), ("no pack", npk)):
    fe = [a["first_edit_turn"] for a in grp if a["first_edit_turn"]]
    print(f"   {lab:10} n={len(grp):3}  first-edit turn median={med(fe)}  calls median={med([a['calls'] for a in grp])}  total_in median={med([a['total_in'] for a in grp])/1e6:.1f}M  ctx at first edit median={med([a['ctx'][min(a['first_edit_turn'],a['calls'])-1] for a in grp if a['first_edit_turn']])}")

print("\n## Biggest single tool results (coder+reviewer+security), by kind: what floods context")
big = collections.defaultdict(list)
for t in ("harness-coder", "harness-reviewer", "harness-security"):
    for a in by[t]:
        for tu, cat, n, lab in a["events"]:
            big[cat].append((n, lab, t))
for cat in ("bash.test", "bash.build/lint", "bash.search", "bash.other", "git-diff", "code.src", "code.tests", "chg.coding-report", "chg.requirements", "grep/glob"):
    xs2 = sorted(big[cat], reverse=True)
    if not xs2: continue
    print(f"   {cat:16} n={len(xs2):5}  total={sum(n for n,_,_ in xs2)/1024/1024:5.1f} MB  median={med([n for n,_,_ in xs2])/1024:5.1f} KB  p90={sorted(n for n,_,_ in xs2)[int(len(xs2)*.9)]/1024:5.1f} KB  max={xs2[0][0]/1024:.0f} KB  e.g. {xs2[0][1][:60]!r}")

print("\n## Test-output results > 20 KB (count, and share of bash.test bytes)")
xs2 = big["bash.test"]; b20 = [n for n, _, _ in xs2 if n > 20000]
print(f"   {len(b20)} of {len(xs2)} test runs returned > 20 KB; they hold {100*sum(b20)/max(sum(n for n,_,_ in xs2),1):.0f}% of test-output bytes")

print("\n## Main sessions: composition")
mains = []
for jl in glob.glob(os.path.join(ROOT, "*.jsonl")):
    recs = parse(jl); a = analyse(recs, True)
    if not a: continue
    n_agent = sum(1 for _, c, _, _ in a["events"] if c == "agent-result")
    if n_agent == 0: continue
    mains.append(a)
tot = collections.Counter(); totres = collections.Counter(); tin = sum(a["total_in"] for a in mains)
base = sum(a["first_ctx"] * a["calls"] for a in mains)
for a in mains: tot.update(a["raw"]); totres.update(a["res"])
print(f"   n={len(mains)} sum total_in={tin/1e6:.0f}M  baseline(first_ctx x calls)={base/1e6:.0f}M ({100*base/tin:.0f}%)")
print(f"   first_ctx: median={med([a['first_ctx'] for a in mains])}  Aug median={med([a['first_ctx'] for a in mains if a['first_ts'][:7]=='2026-08'])}  Sep median={med([a['first_ctx'] for a in mains if a['first_ts'][:7]=='2026-09'])}")
for k, v in sorted(totres.items(), key=lambda kv: -kv[1])[:14]:
    print(f"   {k:22} raw={tot[k]/1024/len(mains):7.1f} KB/session  residency={v/3.6/1e6:7.1f}M token-turns ({100*v/3.6/tin:4.1f}% of main total_in)")
ag = [n for a in mains for _, c, n, _ in a["events"] if c == "agent-result"]
print(f"   agent-result sizes: n={len(ag)} median={med(ag)/1024:.1f} KB p90={sorted(ag)[int(len(ag)*.9)]/1024:.1f} KB max={max(ag)/1024:.0f} KB")
agt = collections.defaultdict(list)
for a in mains:
    for _, c, n, lab in a["events"]:
        if c == "agent-result": agt[lab.split(":")[0]].append(n)
for k, v in agt.items(): print(f"      {k:18} n={len(v):4} median={med(v)/1024:5.1f} KB p90={sorted(v)[int(len(v)*.9)]/1024:5.1f} KB")
bt = [n for a in mains for _, c, n, _ in a["events"] if c == "bash.test"]
print(f"   main-session test-run outputs: n={len(bt)} median={med(bt)/1024:.1f} KB p90={sorted(bt)[int(len(bt)*.9)]/1024 if bt else 0:.1f} KB sum={sum(bt)/1024/1024:.1f} MB")
rr = collections.Counter(); rb = collections.Counter()
for a in mains:
    for _, c, n, lab in a["events"]:
        if c.startswith("chg."): rr[c] += 1; rb[c] += n
for k in rr: print(f"   orchestrator reads {k:20} {rr[k]:4} times, {rb[k]/1024:7.0f} KB")
