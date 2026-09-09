#!/usr/bin/env python3
"""Third pass: close the accounting (baseline / tool results / hook+system injections / own output),
Claude Code version + model per week, orchestrator Write sizes, sample Agent stub."""
import json, os, re, glob, statistics, collections
ROOT = os.path.expanduser("~/.claude/projects/-Users-junhanliu-SBM-Projects-portal-quota-com-au")

def parse(path):
    out = []
    with open(path) as fh:
        for line in fh:
            try: out.append(json.loads(line))
            except Exception: pass
    return out

def tl(c):
    if isinstance(c, str): return len(c)
    if isinstance(c, list): return sum(len(b.get("text", "")) if isinstance(b, dict) else len(str(b)) for b in c)
    return 0

def med(xs): return int(statistics.median(xs)) if xs else 0

def account(recs):
    msgs = {}; order = []
    tool_res = []; user_txt = []; hook_txt = []; sysrem = []
    out_tok = []; tool_in_chars = []
    version = None; model = None
    for o in recs:
        t = o.get("type")
        if t == "assistant":
            m = o["message"]; mid = m.get("id") or o.get("uuid")
            if mid not in msgs: order.append(mid)
            msgs[mid] = m.get("usage") or msgs.get(mid) or {}
            version = version or o.get("version"); model = model or m.get("model")
            for c in m.get("content", []) or []:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    tool_in_chars.append((len(order), len(json.dumps(c.get("input") or {}))))
        elif t == "user":
            c = o["message"].get("content"); T = len(order)
            if isinstance(c, str):
                user_txt.append((T, len(c)))
                if "hook" in c[:200].lower() or "<system-reminder>" in c: hook_txt.append((T, len(c)))
                continue
            for b in c or []:
                if not isinstance(b, dict): continue
                if b.get("type") == "tool_result":
                    s = b.get("content"); n = tl(s)
                    ss = s if isinstance(s, str) else json.dumps(s)
                    rem = sum(len(mm.group(0)) for mm in re.finditer(r"<system-reminder>.*?</system-reminder>", ss or "", re.S))
                    tool_res.append((T, n - rem)); sysrem.append((T, rem))
                elif b.get("type") == "text":
                    s = b.get("text", ""); rem = sum(len(mm.group(0)) for mm in re.finditer(r"<system-reminder>.*?</system-reminder>", s, re.S))
                    user_txt.append((T, len(s) - rem)); sysrem.append((T, rem))
                    if "hook" in s[:300].lower(): hook_txt.append((T, len(s)))
    us = [msgs[i] for i in order if msgs[i]]
    if not us: return None
    ctx = [u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0) + u.get("cache_read_input_tokens", 0) for u in us]
    outs = [u.get("output_tokens", 0) for u in us]
    T = len(ctx); tot = sum(ctx); base = ctx[0] * T
    def resid(pairs, div): return sum(n / div * max(T - t, 0) for t, n in pairs)
    return dict(T=T, total_in=tot, base=base, first=ctx[0], peak=max(ctx),
                r_tool=resid(tool_res, 3.5), r_sys=resid(sysrem, 3.8), r_user=resid(user_txt, 3.8),
                r_out=sum(o * max(T - i - 1, 0) for i, o in enumerate(outs)), sum_out=sum(outs),
                raw_tool=sum(n for _, n in tool_res), raw_sys=sum(n for _, n in sysrem), raw_user=sum(n for _, n in user_txt),
                raw_hook=sum(n for _, n in hook_txt), n_hook=len(hook_txt),
                version=version, model=model, first_ts=recs[0].get("timestamp", ""))

rows = collections.defaultdict(list)
for meta in glob.glob(os.path.join(ROOT, "*", "subagents", "agent-*.meta.json")):
    jl = meta.replace(".meta.json", ".jsonl")
    if not os.path.exists(jl): continue
    a = account(parse(jl))
    if a: a["type"] = json.load(open(meta)).get("agentType", "?"); rows[a["type"]].append(a)

print("## Accounting of total_in per agent type (sum over spawns), in M token-turns")
print(f"{'type':18}{'total_in':>10}{'baseline':>10}{'tool-results':>13}{'sys-reminders':>14}{'other user txt':>15}{'own output':>11}{'unexplained':>12}")
for t, xs in sorted(rows.items(), key=lambda kv: -len(kv[1])):
    tot = sum(a["total_in"] for a in xs); b = sum(a["base"] for a in xs); rt = sum(a["r_tool"] for a in xs); rs = sum(a["r_sys"] for a in xs); ru = sum(a["r_user"] for a in xs); ro = sum(a["r_out"] for a in xs)
    print(f"{t:18}{tot/1e6:>9.0f}M{100*b/tot:>9.0f}%{100*rt/tot:>12.0f}%{100*rs/tot:>13.0f}%{100*ru/tot:>14.0f}%{100*ro/tot:>10.0f}%{100*(tot-b-rt-rs-ru-ro)/tot:>11.0f}%")
print("\n   raw bytes per spawn (median): tool-results / system-reminders / other user text / hook-looking user text (count)")
for t, xs in sorted(rows.items(), key=lambda kv: -len(kv[1])):
    print(f"   {t:18} {med([a['raw_tool'] for a in xs])/1024:7.1f} KB / {med([a['raw_sys'] for a in xs])/1024:6.1f} KB / {med([a['raw_user'] for a in xs])/1024:6.1f} KB / {med([a['raw_hook'] for a in xs])/1024:6.1f} KB ({med([a['n_hook'] for a in xs])})   own output median={med([a['sum_out'] for a in xs])} tok")

print("\n## Claude Code version and model by ISO week (harness-* spawns): median first-turn ctx")
import datetime
wk = collections.defaultdict(list)
for t, xs in rows.items():
    if not t.startswith("harness"): continue
    for a in xs:
        try: d = datetime.datetime.fromisoformat(a["first_ts"].replace("Z", "+00:00"))
        except Exception: continue
        wk[(d.strftime("%Y-%W"))].append(a)
for k in sorted(wk):
    xs = wk[k]; vs = collections.Counter(a["version"] for a in xs).most_common(2); ms = collections.Counter(a["model"] for a in xs).most_common(3)
    print(f"   {k}: n={len(xs):3} first_ctx med={med([a['first'] for a in xs]):6}  versions={vs}  models={ms}")
print("\n   first_ctx by model (harness-coder only):")
for m, xs in collections.defaultdict(list, {m: [a for a in rows['harness-coder'] if a['model'] == m] for m in set(a['model'] for a in rows['harness-coder'])}).items():
    print(f"     {m:20} n={len(xs):3} median first_ctx={med([a['first'] for a in xs])}  by week: " + ", ".join(f"{k}:{med([a['first'] for a in wk[k] if a['model']==m and a['type']=='harness-coder'])}" for k in sorted(wk) if any(a['model']==m and a['type']=='harness-coder' for a in wk[k])))

print("\n## Orchestrator (main sessions): Write/Edit payload sizes by target, and sample Agent tool_result stub")
wr = collections.Counter(); wrn = collections.Counter(); stub = None
outs = []
for jl in glob.glob(os.path.join(ROOT, "*.jsonl")):
    recs = parse(jl); has_agent = False; tu = {}
    for o in recs:
        if o.get("type") == "assistant":
            for c in o["message"].get("content", []) or []:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    tu[c["id"]] = c
                    if c["name"] == "Agent": has_agent = True
        elif o.get("type") == "user" and stub is None and isinstance(o["message"].get("content"), list):
            for b in o["message"]["content"]:
                if isinstance(b, dict) and b.get("type") == "tool_result" and tu.get(b.get("tool_use_id"), {}).get("name") == "Agent":
                    s = b.get("content"); stub = (s if isinstance(s, str) else json.dumps(s))[:600]
    if not has_agent: continue
    a = account(recs); outs.append(a)
    for c in tu.values():
        if c["name"] in ("Write", "Edit", "MultiEdit"):
            p = (c.get("input") or {}).get("file_path", ""); n = len((c.get("input") or {}).get("content", "") or (c.get("input") or {}).get("new_string", ""))
            k = "chg." + os.path.basename(p) if "espalier/changes" in p else ("espalier/" + p.split("espalier/")[1].split("/")[0] if "espalier/" in p else "other")
            wr[k] += n; wrn[k] += 1
for k, v in wr.most_common(12): print(f"   {k:28} {wrn[k]:4} writes  {v/1024:8.0f} KB")
print("   sample Agent tool_result:", stub)
tot = sum(a["total_in"] for a in outs); b = sum(a["base"] for a in outs); rt = sum(a["r_tool"] for a in outs); rs = sum(a["r_sys"] for a in outs); ru = sum(a["r_user"] for a in outs); ro = sum(a["r_out"] for a in outs)
print(f"\n   main-session accounting: total_in={tot/1e6:.0f}M baseline={100*b/tot:.0f}% tool-results={100*rt/tot:.0f}% sys-reminders={100*rs/tot:.0f}% user-text={100*ru/tot:.0f}% own-output={100*ro/tot:.0f}% unexplained={100*(tot-b-rt-rs-ru-ro)/tot:.0f}%")
print(f"   main-session raw per session (median): tool-results {med([a['raw_tool'] for a in outs])/1024:.0f} KB, sys-reminders {med([a['raw_sys'] for a in outs])/1024:.0f} KB, user text {med([a['raw_user'] for a in outs])/1024:.0f} KB, own output {med([a['sum_out'] for a in outs])} tok")
