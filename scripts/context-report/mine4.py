#!/usr/bin/env python3
"""Fourth pass: (1) task-notification sizes landing in orchestrator context per agent type;
(2) orchestrator own-output split prose vs tool payload; (3) coder peak-context vs next panel round P0/P1 (quality proxy);
(4) top coder spawns by stage label."""
import json, os, re, glob, statistics, collections, datetime
ROOT = os.path.expanduser("~/.claude/projects/-Users-junhanliu-SBM-Projects-portal-quota-com-au")
CH = "/Users/junhanliu/SBM_Projects/portal.quota.com.au/espalier/changes"
def parse(p):
    out = []
    for line in open(p):
        try: out.append(json.loads(line))
        except Exception: pass
    return out
def med(xs): return int(statistics.median(xs)) if xs else 0

# (1)+(2)
notif = collections.defaultdict(list); prose = []; payload = []; nsess = 0
for jl in glob.glob(os.path.join(ROOT, "*.jsonl")):
    recs = parse(jl); has = False; pr = 0; pl = 0; agent_type = {}
    for o in recs:
        if o.get("type") == "assistant":
            for c in o["message"].get("content", []) or []:
                if not isinstance(c, dict): continue
                if c.get("type") == "text": pr += len(c.get("text", ""))
                elif c.get("type") == "tool_use":
                    pl += len(json.dumps(c.get("input") or {}))
                    if c["name"] == "Agent": has = True
        elif o.get("type") == "user":
            c = o["message"].get("content")
            s = c if isinstance(c, str) else "".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
            if "<task-notification>" in s:
                m = re.search(r"<subagent_type>([^<]+)</subagent_type>|subagent_type[\"']?:\s*[\"']?([\w-]+)", s)
                t = (m.group(1) or m.group(2)) if m else "?"
                if t == "?":
                    m = re.search(r"You are the (harness-\w+)", s); t = m.group(1) if m else ("scout" if "scout" in s[:600].lower() else "?")
                notif[t].append(len(s))
    if has: nsess += 1; prose.append(pr); payload.append(pl)
print("## Orchestrator own output per session (median chars): prose text =", med(prose), " tool_use payloads =", med(payload), f"(n={nsess})")
print("## task-notification (subagent final message) sizes landing in orchestrator context")
for t, xs in sorted(notif.items(), key=lambda kv: -len(kv[1])):
    print(f"   {t:16} n={len(xs):4} median={med(xs)/1024:5.1f} KB p90={sorted(xs)[int(len(xs)*.9)]/1024:5.1f} KB max={max(xs)/1024:5.1f} KB sum={sum(xs)/1024:7.0f} KB")
sample = None
for jl in glob.glob(os.path.join(ROOT, "*.jsonl")):
    for o in parse(jl):
        if o.get("type") == "user":
            c = o["message"].get("content"); s = c if isinstance(c, str) else ""
            if "<task-notification>" in s and "harness-reviewer" in s: sample = s[:900]; break
    if sample: break
print("   sample:", (sample or "")[:900].replace("\n", " | "))

# (3) quality proxy
subs = json.load(open(os.path.dirname(os.path.abspath(__file__)) + "/subagents.json"))["subagents"]
coders = [a for a in subs if a["agentType"] == "harness-coder"]
def dt(s):
    try: return datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception: return None
rounds = []
for f in glob.glob(CH + "/*/*/pipeline-state.md"):
    for line in open(f):
        m = re.match(r"\|\s*4\s*\|\s*ROUND\s*(\d+)\s*(\w+)\s*\|\s*([0-9T:\-Z]+)\s*\|(.*)", line)
        if not m: continue
        rn, verdict, ts, notes = m.groups()
        p = re.findall(r"p0=(\d+)\s*p1=(\d+)", notes)
        p01 = sum(int(a) + int(b) for a, b in p)
        rounds.append((dt(ts), int(rn), verdict, p01, f.split("/changes/")[1].split("/pipeline-state")[0]))
rounds = [r for r in rounds if r[0]]
print(f"\n## Quality proxy: Stage 4 panel rounds parsed = {len(rounds)}; coder spawns = {len(coders)}")
joined = []
for T, rn, verdict, p01, slug in rounds:
    cands = [a for a in coders if dt(a["last_ts"]) and T - datetime.timedelta(hours=4) <= dt(a["last_ts"]) <= T + datetime.timedelta(minutes=30)]
    if not cands: continue
    last = max(cands, key=lambda a: dt(a["last_ts"]))
    joined.append((last["peak_ctx"], last["calls"], p01, verdict, rn, slug))
print(f"   rounds joined to a preceding coder spawn: {len(joined)}")
for lo, hi in ((0, 150000), (150000, 250000), (250000, 10**9)):
    g = [j for j in joined if lo <= j[0] < hi]
    if not g: continue
    bad = sum(1 for j in g if j[2] > 0); fail = sum(1 for j in g if j[3] == "FAIL")
    print(f"   coder peak {lo//1000:3}k-{hi//1000 if hi<10**9 else '∞':>3}k: rounds={len(g):3}  next panel had P0/P1: {100*bad/len(g):3.0f}%  FAIL verdict: {100*fail/len(g):3.0f}%  median calls={med([j[1] for j in g])}")
for lo, hi in ((0, 30), (30, 60), (60, 10**9)):
    g = [j for j in joined if lo <= j[1] < hi]
    if not g: continue
    bad = sum(1 for j in g if j[2] > 0)
    print(f"   coder calls {lo:3}-{hi if hi<10**9 else '∞':>3}: rounds={len(g):3}  next panel had P0/P1: {100*bad/len(g):3.0f}%")

# (4) top coder spawns by label
print("\n## Coder spawn cost by label (median total_in, peak) — Stage 5/test spawns vs Stage 3 vs fix rounds")
lab = collections.defaultdict(list)
for a in coders:
    d = a["desc"].lower()
    k = "stage5/tests" if re.search(r"stage 5|test", d) else ("fix-round" if re.search(r"round|fix", d) else ("contract" if "contract" in d else "stage3/impl"))
    lab[k].append(a)
for k, xs in sorted(lab.items(), key=lambda kv: -sum(a["total_in"] for a in kv[1])):
    print(f"   {k:14} n={len(xs):3} median total_in={med([a['total_in'] for a in xs])/1e6:4.1f}M  median peak={med([a['peak_ctx'] for a in xs])//1000}k  median calls={med([a['calls'] for a in xs])}  share of coder spend={100*sum(a['total_in'] for a in xs)/sum(a['total_in'] for a in coders):3.0f}%")
