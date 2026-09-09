#!/usr/bin/env python3
"""Mine portal.quota.com.au Claude Code transcripts for per-spawn context composition."""
import json, os, re, sys, glob, statistics, collections, datetime

ROOT = os.path.expanduser("~/.claude/projects/-Users-junhanliu-SBM-Projects-portal-quota-com-au")
REPO = "/Users/junhanliu/SBM_Projects/portal.quota.com.au/"
CUT = datetime.datetime(2026, 9, 7, 1, 20, tzinfo=datetime.timezone.utc)  # eea0a620 compress commit

def cat_path(p):
    p = p.replace(REPO, "")
    if p.startswith("/"):
        return "outside-repo"
    if p.startswith("espalier/rules/"): return "esp.rules"
    if p.startswith("espalier/agents/"): return "esp.agents"
    if p.startswith("espalier/skills/") and "/specs/" in p: return "esp.specs"
    if p.startswith("espalier/skills/"): return "esp.skill"
    if p.startswith("espalier/wiki/"): return "esp.wiki"
    if p.startswith("espalier/conventions/"): return "esp.conventions"
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
    if p.endswith("schema.prisma") or p.endswith("schema.graphql"): return "code.schema"
    if p.startswith(("backend/", "frontend/", "mobile/")): return "code.src"
    return "other"

PATH_RE = re.compile(r"(?:/Users/junhanliu/SBM_Projects/portal\.quota\.com\.au/)?((?:espalier|backend|frontend|mobile|docs)/[\w./@\-\[\]]+)")

def ctx_of(u):
    return (u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0) + u.get("cache_read_input_tokens", 0))

def text_len(c):
    if isinstance(c, str): return len(c)
    if isinstance(c, list):
        return sum(len(b.get("text", "")) if isinstance(b, dict) else len(str(b)) for b in c)
    return 0

def parse(path):
    recs = []
    with open(path) as fh:
        for line in fh:
            try: recs.append(json.loads(line))
            except Exception: pass
    return recs

def analyse(recs):
    msgs = {}  # message id -> usage (dedupe streamed blocks)
    order = []
    tool_uses = {}  # id -> (name, input)
    reads = []  # (category, path, bytes, via)
    sysrem = collections.Counter(); sysrem_bytes = collections.Counter()
    model = None; first_ts = None; last_ts = None
    dup = collections.Counter()
    for o in recs:
        t = o.get("type")
        ts = o.get("timestamp")
        if ts:
            if first_ts is None: first_ts = ts
            last_ts = ts
        if t == "assistant":
            m = o["message"]; mid = m.get("id") or o.get("uuid")
            if mid not in msgs: order.append(mid)
            msgs[mid] = m.get("usage") or msgs.get(mid) or {}
            model = model or m.get("model")
            for c in m.get("content", []) or []:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    tool_uses[c["id"]] = (c["name"], c.get("input") or {})
        elif t == "user":
            c = o["message"].get("content")
            blocks = c if isinstance(c, list) else [{"type": "text", "text": c or ""}]
            for b in blocks:
                if not isinstance(b, dict): continue
                if b.get("type") == "tool_result":
                    n = text_len(b.get("content"))
                    name, inp = tool_uses.get(b.get("tool_use_id"), ("?", {}))
                    if name == "Read":
                        p = inp.get("file_path", "?"); reads.append((cat_path(p), p, n, "Read")); dup[p] += 1
                    elif name == "Bash":
                        cmd = inp.get("command", "")
                        if re.search(r"\bgit (diff|show)\b", cmd): reads.append(("git-diff", cmd[:80], n, "Bash"))
                        elif re.search(r"^\s*(cat|sed -n|head|tail|less)\b", cmd) or re.search(r"\b(cat|sed -n|head|tail) [^|;&]*\.(md|ts|tsx|json|prisma)", cmd):
                            m2 = PATH_RE.search(cmd)
                            p = m2.group(1) if m2 else "?"; reads.append((cat_path(p), p, n, "Bash")); dup[p] += 1
                        else:
                            reads.append(("bash.other", cmd[:60], n, "Bash"))
                    elif name in ("Grep", "Glob"):
                        reads.append(("grep/glob", name, n, name))
                    elif name == "Agent":
                        reads.append(("agent-result", inp.get("subagent_type", "?"), n, "Agent"))
                    else:
                        reads.append(("tool." + name, name, n, name))
                    # system reminders embedded in tool results (scoped CLAUDE.md etc.)
                    s = b.get("content") if isinstance(b.get("content"), str) else json.dumps(b.get("content"))
                    for mm in re.finditer(r"<system-reminder>(.*?)</system-reminder>", s or "", re.S):
                        body = mm.group(1)
                        key = "sysrem.CLAUDE.md" if "CLAUDE.md" in body[:400] else "sysrem.other"
                        sysrem[key] += 1; sysrem_bytes[key] += len(body)
                elif b.get("type") == "text":
                    s = b.get("text", "")
                    for mm in re.finditer(r"<system-reminder>(.*?)</system-reminder>", s, re.S):
                        body = mm.group(1)
                        key = "sysrem.CLAUDE.md" if "CLAUDE.md" in body[:400] else "sysrem.other"
                        sysrem[key] += 1; sysrem_bytes[key] += len(body)
    usages = [msgs[i] for i in order if msgs[i]]
    if not usages: return None
    first = usages[0]; last = usages[-1]
    total_in = sum(ctx_of(u) for u in usages)
    total_create = sum(u.get("cache_creation_input_tokens", 0) for u in usages)
    total_read = sum(u.get("cache_read_input_tokens", 0) for u in usages)
    total_out = sum(u.get("output_tokens", 0) for u in usages)
    peak = max(ctx_of(u) for u in usages)
    return dict(model=model, first_ts=first_ts, last_ts=last_ts, calls=len(usages),
                first_ctx=ctx_of(first), first_create=first.get("cache_creation_input_tokens", 0), first_read=first.get("cache_read_input_tokens", 0),
                last_ctx=ctx_of(last), peak_ctx=peak, total_in=total_in, total_create=total_create, total_read=total_read, total_out=total_out,
                reads=reads, dup=dup, sysrem=dict(sysrem), sysrem_bytes=dict(sysrem_bytes))

def med(xs): return int(statistics.median(xs)) if xs else 0
def p90(xs): xs = sorted(xs); return int(xs[int(len(xs) * 0.9) - 1]) if xs else 0
def fmt_ts(ts): return ts[:10] if ts else "?"

subagents = []
for meta in glob.glob(os.path.join(ROOT, "*", "subagents", "agent-*.meta.json")):
    jl = meta.replace(".meta.json", ".jsonl")
    if not os.path.exists(jl): continue
    try: m = json.load(open(meta))
    except Exception: m = {}
    a = analyse(parse(jl))
    if not a: continue
    a["agentType"] = m.get("agentType", "?"); a["desc"] = m.get("description", ""); a["file"] = jl
    a["session"] = jl.split("/")[-3]
    subagents.append(a)

print(f"subagent transcripts analysed: {len(subagents)}")
by = collections.defaultdict(list)
for a in subagents: by[a["agentType"]].append(a)

def dt(a):
    try: return datetime.datetime.fromisoformat(a["first_ts"].replace("Z", "+00:00"))
    except Exception: return None

print("\n## Per agent type (medians; tokens)")
print(f"{'type':18}{'n':>5}{'calls':>7}{'first_ctx':>11}{'last_ctx':>10}{'peak':>9}{'total_in(sum ctx/turn)':>24}{'cache_create':>13}{'out':>8}  models")
for t, xs in sorted(by.items(), key=lambda kv: -len(kv[1])):
    models = collections.Counter(a["model"] for a in xs).most_common(3)
    print(f"{t:18}{len(xs):>5}{med([a['calls'] for a in xs]):>7}{med([a['first_ctx'] for a in xs]):>11}{med([a['last_ctx'] for a in xs]):>10}{med([a['peak_ctx'] for a in xs]):>9}{med([a['total_in'] for a in xs]):>24}{med([a['total_create'] for a in xs]):>13}{med([a['total_out'] for a in xs]):>8}  {models}")

print("\n## Totals per agent type (sum over all spawns; M tokens)")
for t, xs in sorted(by.items(), key=lambda kv: -len(kv[1])):
    print(f"{t:18} total_in={sum(a['total_in'] for a in xs)/1e6:7.1f}M  cache_create={sum(a['total_create'] for a in xs)/1e6:6.1f}M  cache_read={sum(a['total_read'] for a in xs)/1e6:7.1f}M  out={sum(a['total_out'] for a in xs)/1e6:5.2f}M")

print("\n## First-turn context (system+CLAUDE.md+rules+prompt) before/after 2026-09-07 compress, per type")
for t, xs in sorted(by.items(), key=lambda kv: -len(kv[1])):
    pre = [a["first_ctx"] for a in xs if dt(a) and dt(a) < CUT]
    post = [a["first_ctx"] for a in xs if dt(a) and dt(a) >= CUT]
    print(f"{t:18} pre: n={len(pre):3} med={med(pre):7}  | post: n={len(post):3} med={med(post):7}")

print("\n## First-turn context by week (all harness-* types)")
wk = collections.defaultdict(list)
for a in subagents:
    d = dt(a)
    if d and a["agentType"].startswith("harness"): wk[d.strftime("%Y-%W")].append(a["first_ctx"])
for k in sorted(wk): print(f"  week {k}: n={len(wk[k]):3} median first_ctx={med(wk[k])} p90={p90(wk[k])}")

print("\n## Bytes pulled into context via tool results, per spawn (median KB) and share of total, by agent type")
cats = ["esp.rules", "esp.agents", "esp.skill", "esp.specs", "esp.wiki", "esp.pipeline+agent", "esp.conventions", "esp.other", "chg.context-pack", "chg.requirements", "chg.coding-report", "chg.review-record", "chg.security-record", "chg.pipeline-state", "chg.other", "CLAUDE.md", "code.src", "code.tests", "code.schema", "code.generated", "git-diff", "grep/glob", "bash.other", "agent-result", "sysrem.CLAUDE.md", "sysrem.other"]
for t, xs in sorted(by.items(), key=lambda kv: -len(kv[1])):
    print(f"\n### {t} (n={len(xs)})")
    tot_all = 0; per_cat_tot = collections.Counter(); per_cat_spawn = collections.defaultdict(list); per_cat_n = collections.Counter()
    for a in xs:
        c = collections.Counter(); cn = collections.Counter()
        for cat, p, n, via in a["reads"]:
            c[cat] += n; cn[cat] += 1
        for k, v in a["sysrem_bytes"].items(): c[k] += v; cn[k] += a["sysrem"][k]
        for k in cats: per_cat_spawn[k].append(c.get(k, 0))
        per_cat_tot.update(c); per_cat_n.update(cn); tot_all += sum(c.values())
    print(f"{'category':20}{'med KB/spawn':>13}{'p90 KB':>9}{'share':>8}{'reads/spawn':>12}")
    for k in cats:
        if per_cat_tot[k] == 0: continue
        print(f"{k:20}{med(per_cat_spawn[k])/1024:>13.1f}{p90(per_cat_spawn[k])/1024:>9.1f}{100*per_cat_tot[k]/max(tot_all,1):>7.1f}%{per_cat_n[k]/len(xs):>12.1f}")
    print(f"{'TOTAL tool bytes':20}{med([sum(n for _,_,n,_ in a['reads'])+sum(a['sysrem_bytes'].values()) for a in xs])/1024:>13.1f} KB median/spawn; sum={tot_all/1e6:.1f} MB")

print("\n## Most-read files across all subagents (count, total KB)")
fc = collections.Counter(); fb = collections.Counter()
for a in subagents:
    for cat, p, n, via in a["reads"]:
        if via in ("Read", "Bash") and cat not in ("git-diff", "bash.other", "grep/glob"):
            k = re.sub(r"espalier/changes/[^/]+/[^/]+/", "espalier/changes/*/*/", p.replace(REPO, ""))
            k = re.sub(r"frontend/src/domains/[^/]+/CLAUDE.md", "frontend/src/domains/<d>/CLAUDE.md", k)
            fc[k] += 1; fb[k] += n
for k, n in fc.most_common(45): print(f"  {n:4}  {fb[k]/1024:8.1f} KB  {k}")

print("\n## Explicit Read of espalier/rules/* (already auto-loaded) pre/post compress, by type")
for t, xs in sorted(by.items(), key=lambda kv: -len(kv[1])):
    pre = sum(1 for a in xs if dt(a) and dt(a) < CUT for cat, p, n, via in a["reads"] if cat == "esp.rules")
    post = sum(1 for a in xs if dt(a) and dt(a) >= CUT for cat, p, n, via in a["reads"] if cat == "esp.rules")
    npre = sum(1 for a in xs if dt(a) and dt(a) < CUT); npost = len(xs) - npre
    print(f"{t:18} pre: {pre} reads over {npre} spawns   post: {post} reads over {npost} spawns")

print("\n## Duplicate reads of the same file inside one spawn (wasted bytes), by type")
for t, xs in sorted(by.items(), key=lambda kv: -len(kv[1])):
    waste = 0; nd = 0
    for a in xs:
        seen = {}
        for cat, p, n, via in a["reads"]:
            if via == "Read":
                if p in seen: waste += n; nd += 1
                seen[p] = n
    print(f"{t:18} dup reads={nd:4}  wasted={waste/1024:8.1f} KB  ({waste/1024/max(len(xs),1):5.1f} KB/spawn)")

print("\n## coding-report reads per spawn (count, KB) for reviewer/security, split by description containing 'round'")
for t in ("harness-reviewer", "harness-security", "harness-coder"):
    xs = by.get(t, [])
    r1 = [a for a in xs if not re.search(r"round\s*[2-9]|re-review|re-audit|round [2-9]", a["desc"], re.I)]
    rn = [a for a in xs if re.search(r"round\s*[2-9]|re-review|re-audit|round [2-9]", a["desc"], re.I)]
    for lab, grp in (("round1/unlabelled", r1), ("round2+", rn)):
        kb = [sum(n for cat, p, n, via in a["reads"] if cat == "chg.coding-report") / 1024 for a in grp]
        cnt = [sum(1 for cat, p, n, via in a["reads"] if cat == "chg.coding-report") for a in grp]
        print(f"{t:18} {lab:18} n={len(grp):3}  coding-report reads/spawn med={med(cnt)}  KB/spawn med={med(kb):.1f} p90={p90(kb):.1f}")

print("\n## Longest spawns by total_in (top 12)")
for a in sorted(subagents, key=lambda a: -a["total_in"])[:12]:
    print(f"  {a['agentType']:17} {fmt_ts(a['first_ts'])} calls={a['calls']:3} peak={a['peak_ctx']:6} total_in={a['total_in']/1e6:5.1f}M  {a['desc'][:70]}")

print("\n## Main sessions with Agent spawns")
mains = []
for jl in glob.glob(os.path.join(ROOT, "*.jsonl")):
    recs = parse(jl)
    spawns = collections.Counter(); entry = ""
    compactions = 0
    for o in recs:
        if o.get("type") == "assistant":
            for c in o["message"].get("content", []) or []:
                if isinstance(c, dict) and c.get("type") == "tool_use" and c["name"] == "Agent":
                    spawns[c["input"].get("subagent_type", "?")] += 1
        elif o.get("type") == "user" and not entry:
            c = o["message"].get("content")
            s = c if isinstance(c, str) else ""
            if s.strip().startswith("/espalier") or "<command-name>/espalier" in s: entry = re.search(r"/espalier[\w-]*", s).group(0)
            elif s and not s.startswith("<"): entry = "(prompt) " + s[:40].replace("\n", " ")
        if o.get("isCompactSummary") or (o.get("type") == "user" and isinstance(o["message"].get("content"), str) and "This session is being continued from a previous conversation" in o["message"]["content"]):
            compactions += 1
    if sum(spawns.values()) == 0: continue
    a = analyse(recs)
    if not a: continue
    a["spawns"] = spawns; a["entry"] = entry; a["compactions"] = compactions; a["file"] = os.path.basename(jl)
    mains.append(a)
mains.sort(key=lambda a: a["first_ts"] or "")
print(f"{'date':11}{'calls':>6}{'first':>8}{'peak':>8}{'total_in':>10}{'out':>7}{'compact':>8}  spawns  entry")
for a in mains:
    sp = ",".join(f"{k.replace('harness-','')}:{v}" for k, v in a["spawns"].most_common())
    print(f"{fmt_ts(a['first_ts']):11}{a['calls']:>6}{a['first_ctx']:>8}{a['peak_ctx']:>8}{a['total_in']/1e6:>9.1f}M{a['total_out']/1000:>6.0f}k{a['compactions']:>8}  {sp:40} {a['entry'][:40]}")
print(f"\nmain sessions: n={len(mains)} median peak={med([a['peak_ctx'] for a in mains])} median total_in={med([a['total_in'] for a in mains])/1e6:.1f}M sum total_in={sum(a['total_in'] for a in mains)/1e6:.1f}M")
print(f"orchestrator share of total_in: main={sum(a['total_in'] for a in mains)/1e6:.1f}M vs subagents={sum(a['total_in'] for a in subagents)/1e6:.1f}M")

json.dump({"subagents": [{k: v for k, v in a.items() if k not in ("reads", "dup")} for a in subagents]}, open(os.path.join(os.path.dirname(__file__), "subagents.json"), "w"))
