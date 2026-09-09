#!/usr/bin/env python3
"""Context report for one Claude Code install (espalier plan Track F.2 / F.4).

Reads a Claude Code project directory (~/.claude/projects/<slug>/) and prints
where the tokens go, per espalier agent type:

  1. spend map           first-turn / peak / calls / total per spawn, sum
  2. tail                share of tokens processed above 150k / 200k context,
                         share of spawns peaking above 200k / 300k / 400k
  3. baseline share      first-turn ctx x calls, tool results, own output, user
                         text (linear residency accounting)
  4. pack cohort         coders that read context-pack.md vs not
  5. orchestrator        main sessions that spawned agents; compactions
  6. on-demand reads     share of spawns that opened the phase skills / specs /
                         a scoped CLAUDE.md
  7. platform injection  nested_memory and the other `attachment` records
                         (KB per spawn, which files)                     [F.4]
  8. self re-read waste  spawns that Read their own agent file; duplicate reads
  9. handoff / resume    `| 3 | HANDOFF` / `| N | RESUMED` rows and coding-log/
                         files per change (--repo PATH, or the cwd the
                         transcripts ran in)

--bare prints only the bare-session first-turn context of the main sessions
(subagents excluded), per entrypoint -- cli = interactive terminal, sdk-cli =
headless `claude -p`, sdk-py = Agent SDK: run it before and after trimming the
user-global harness and compare the cli row (plan Appendix A).

Usage:
  python3 scripts/context-report.py [PROJECT_DIR] [--since YYYY-MM-DD]
          [--until YYYY-MM-DD] [--repo PATH] [--json] [--bare]

PROJECT_DIR defaults to the Claude Code project dir of the current working
directory. "total" = the context sent on every API call (input + cache
creation + cache read tokens), summed -- the quantity that scales cost and
latency. Usage is taken once per assistant message (streamed records repeat
the same message.id). Malformed JSONL lines are skipped.

Stdlib only; Python 3.9+. Consolidates the seed scripts in
scripts/context-report/ (mine_transcripts.py, mine2.py, mine3.py, mine4.py).
"""
import argparse
import collections
import datetime
import glob
import json
import os
import re
import statistics
import sys

ORCH = "orchestrator session"
MAIN = "main session"
ATTACHMENT_KINDS = ("nested_memory", "instructions", "skill_listing",
                    "agent_listing_delta", "mcp_instructions_delta",
                    "deferred_tools_delta")
# chars-per-token divisors of the residency accounting (mine3.account()).
CHARS_PER_TOKEN_TOOL = 3.5
CHARS_PER_TOKEN_TEXT = 3.8

SYSREM_RE = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)
BASH_READ_RE = re.compile(r"^\s*(cat|sed -n|head|tail|less)\b")
BASH_READ_INLINE_RE = re.compile(r"\b(cat|sed -n|head|tail) [^|;&]*\.(md|ts|tsx|json|prisma|sh)")
PATH_TOKEN_RE = re.compile(
    r"/?(?:[\w.@~\-\[\]]+/)*[\w.@~\-\[\]]+"
    r"\.(?:md|ts|tsx|js|jsx|mjs|cjs|json|prisma|graphql|sh|py|yaml|yml|toml|sql|txt)(?![\w.])")
SPEC_RE = re.compile(r"espalier/skills/[^/]+/specs/[^/]+\.md$")
HANDOFF_RE = re.compile(r"^\|\s*\d+(?:-\d+)?\s*\|\s*HANDOFF\b")
RESUMED_RE = re.compile(r"^\|\s*\d+(?:-\d+)?\s*\|\s*RESUMED\b")
NOTIF_TOOL_USE_RE = re.compile(r"<tool-use-id>\s*([\w-]+)\s*</tool-use-id>")
NOTIF_AGENT_RE = re.compile(r'Agent "([\w:.-]+):')
NOTIF_TYPE_RE = re.compile(r"<subagent_type>([^<]+)</subagent_type>|subagent_type[\"']?:\s*[\"']?([\w-]+)")
NOTIF_YOU_ARE_RE = re.compile(r"You are the (harness-\w+)")

# Section 6: files an agent is expected to open on demand (path predicates).
ON_DEMAND = (
    ("coding SKILL", lambda p: p.endswith("espalier-coding/SKILL.md")),
    ("specs/*.md", lambda p: SPEC_RE.search(p) is not None),
    ("review SKILL", lambda p: p.endswith("espalier-review/SKILL.md")),
    ("security SKILL", lambda p: p.endswith("espalier-security/SKILL.md")),
    ("testing SKILL", lambda p: p.endswith("espalier-testing/SKILL.md")),
    ("CLAUDE.md", lambda p: os.path.basename(p) == "CLAUDE.md"),
)


# ---------------------------------------------------------------- helpers ---

def med(xs):
    xs = list(xs)
    return int(statistics.median(xs)) if xs else 0


def p90(xs):
    xs = sorted(xs)
    return int(xs[max(int(len(xs) * 0.9) - 1, 0)]) if xs else 0


def share(num, den):
    return 100.0 * num / den if den else 0.0


def pct(value, known=True):
    return "%3.0f%%" % value if known else "  -"


def fk(tokens):
    return "%dk" % round(tokens / 1000.0)


def fm(tokens, digits=1):
    return ("{:,.%df}M" % digits).format(tokens / 1e6)


def fsum(tokens):
    return fm(tokens, 0) if tokens >= 10e6 else fm(tokens, 1)


def slen(x):
    return len(x) if isinstance(x, str) else 0


def text_len(content):
    if isinstance(content, str):
        return len(content)
    if isinstance(content, list):
        total = 0
        for block in content:
            if isinstance(block, dict):
                total += slen(block.get("text"))
            else:
                total += len(str(block))
        return total
    return 0


def ctx_of(usage):
    return (int(usage.get("input_tokens") or 0)
            + int(usage.get("cache_creation_input_tokens") or 0)
            + int(usage.get("cache_read_input_tokens") or 0))


def version_key(v):
    try:
        return tuple(int(x) for x in str(v).split("."))
    except ValueError:
        return (0,)


def project_slug(path):
    """Claude Code's project-dir name: every non-alphanumeric of the absolute path becomes '-'."""
    return re.sub(r"[^A-Za-z0-9]", "-", os.path.abspath(path))


def default_project_dir():
    return os.path.join(os.path.expanduser("~"), ".claude", "projects", project_slug(os.getcwd()))


def make_short(root):
    """Path shortener for the file lists: strip the repo root, else keep the tail."""
    prefix = (root.rstrip("/") + "/") if root else None

    def short(p):
        p = str(p)
        if prefix and p.startswith(prefix):
            return p[len(prefix):]
        if "/espalier/" in p:
            return "espalier/" + p.split("/espalier/", 1)[1]
        parts = p.strip("/").split("/")
        return p if len(parts) <= 4 else ".../" + "/".join(parts[-4:])
    return short


# ---------------------------------------------------------------- parsing ---

def parse_jsonl(path):
    records = []
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                if isinstance(obj, dict):
                    records.append(obj)
    except OSError:
        return []
    return records


def is_bash_read(cmd):
    return bool(BASH_READ_RE.search(cmd) or BASH_READ_INLINE_RE.search(cmd))


def notification_type(text, tool_uses):
    """Agent type behind a <task-notification>, or None when the task was not an
    agent (background Bash, Monitor, SendMessage). The <tool-use-id> names the
    tool_use that started the task; text heuristics cover notifications whose
    id is missing or unmatched."""
    m = NOTIF_TOOL_USE_RE.search(text)
    if m and m.group(1) in tool_uses:
        name, inp, _ = tool_uses[m.group(1)]
        if name in ("Agent", "Task"):
            return str(inp.get("subagent_type") or name)
        return None
    m = NOTIF_AGENT_RE.search(text)
    if m:
        return m.group(1)
    m = NOTIF_TYPE_RE.search(text)
    if m:
        return m.group(1) or m.group(2)
    m = NOTIF_YOU_ARE_RE.search(text)
    if m:
        return m.group(1)
    return "scout" if "scout" in text[:600].lower() else "?"


def attachment_size(att):
    """(chars injected, [file paths]) for one `attachment` record's payload."""
    kind = att.get("type")
    if kind == "nested_memory":
        content = att.get("content")
        if isinstance(content, dict):
            return slen(content.get("content")), [content.get("path") or att.get("path") or "?"]
        return slen(content), [att.get("path") or "?"]
    if kind == "instructions":
        files = [f for f in (att.get("files") or []) if isinstance(f, dict)]
        return sum(slen(f.get("content")) for f in files), [f.get("path") or "?" for f in files]
    if kind == "skill_listing":
        return slen(att.get("content")), []
    if kind in ("agent_listing_delta", "deferred_tools_delta"):
        return sum(len(str(x)) for x in (att.get("addedLines") or [])), []
    if kind == "mcp_instructions_delta":
        return sum(len(str(x)) for x in (att.get("addedBlocks") or [])), []
    if kind == "session_context":
        ctx = att.get("context")
        return (sum(len(str(v)) for v in ctx.values()) if isinstance(ctx, dict) else 0), []
    if kind in ("hook_additional_context", "hook_success"):
        return slen(att.get("content")), []
    return 0, []


def split_reminders(text):
    """(chars without <system-reminder> blocks, chars of the blocks)."""
    rem = sum(len(m.group(0)) for m in SYSREM_RE.finditer(text))
    return max(len(text) - rem, 0), rem


def analyse(records, skip_sidechain=False):
    """One transcript -> per-spawn numbers, or None when it made no API call.

    Usage is deduplicated by message.id; context per call = input +
    cache_creation + cache_read tokens. Residency-weighted shares follow
    mine3.account(): chars / divisor x turns the text stayed in context.
    """
    usage_by_id = {}
    order = []
    tool_uses = {}
    reads = []            # (turn, path, chars, via)
    tool_results = []     # (turn, chars)
    user_text = []
    reminders = []
    attachments = collections.defaultdict(list)   # kind -> [(chars, [paths])]
    spawns = collections.Counter()
    notifications = []    # (agent type, chars)
    other_tasks = 0       # task-notifications from background Bash / Monitor, not agents
    boundaries = summaries = 0

    def note(text):
        nonlocal other_tasks
        kind = notification_type(text, tool_uses)
        if kind is None:
            other_tasks += 1
        else:
            notifications.append((kind, len(text)))
    first_edit_turn = None
    model = version = cwd = entrypoint = first_ts = last_ts = None
    sidechain_skipped = 0

    for rec in records:
        if skip_sidechain and rec.get("isSidechain"):
            sidechain_skipped += 1
            continue
        kind = rec.get("type")
        ts = rec.get("timestamp")
        if isinstance(ts, str):
            first_ts = first_ts or ts
            last_ts = ts
        cwd = cwd or rec.get("cwd")
        version = version or rec.get("version")
        entrypoint = entrypoint or rec.get("entrypoint")
        if rec.get("isCompactSummary"):
            summaries += 1
        turn = len(order)

        if kind == "assistant":
            msg = rec.get("message")
            if not isinstance(msg, dict):
                continue
            mid = msg.get("id") or rec.get("uuid")
            if mid not in usage_by_id:
                order.append(mid)
                usage_by_id[mid] = {}
            usage = msg.get("usage")
            if isinstance(usage, dict) and usage:
                usage_by_id[mid] = usage
            model = model or msg.get("model")
            turn = len(order)
            for block in msg.get("content") or []:
                if not isinstance(block, dict) or block.get("type") != "tool_use":
                    continue
                name = block.get("name") or "?"
                inp = block.get("input") if isinstance(block.get("input"), dict) else {}
                tool_uses[block.get("id")] = (name, inp, turn)
                if name in ("Agent", "Task"):
                    spawns[str(inp.get("subagent_type") or "?")] += 1
                elif name in ("Edit", "Write", "MultiEdit") and first_edit_turn is None:
                    path = str(inp.get("file_path") or "")
                    if not path.endswith(".md") or "espalier/changes" not in path:
                        first_edit_turn = turn

        elif kind == "user":
            msg = rec.get("message")
            content = msg.get("content") if isinstance(msg, dict) else None
            if isinstance(content, str):
                plain, rem = split_reminders(content)
                user_text.append((turn, plain))
                reminders.append((turn, rem))
                if "<task-notification>" in content:
                    note(content)
                continue
            for block in content or []:
                if not isinstance(block, dict):
                    continue
                btype = block.get("type")
                if btype == "tool_result":
                    body = block.get("content")
                    chars = text_len(body)
                    if isinstance(body, str):
                        text = body
                    elif body:
                        text = json.dumps(body, default=str)
                    else:
                        text = ""
                    rem = sum(len(m.group(0)) for m in SYSREM_RE.finditer(text))
                    tool_results.append((turn, max(chars - rem, 0)))
                    reminders.append((turn, rem))
                    name, inp, use_turn = tool_uses.get(block.get("tool_use_id"), ("?", {}, turn))
                    if name == "Read":
                        reads.append((use_turn, str(inp.get("file_path") or "?"), chars, "Read"))
                    elif name == "Bash":
                        cmd = str(inp.get("command") or "")
                        if is_bash_read(cmd):
                            for i, path in enumerate(PATH_TOKEN_RE.findall(cmd)):
                                reads.append((use_turn, path, chars if i == 0 else 0, "Bash"))
                elif btype == "text":
                    text = block.get("text") if isinstance(block.get("text"), str) else ""
                    plain, rem = split_reminders(text)
                    user_text.append((turn, plain))
                    reminders.append((turn, rem))
                    if "<task-notification>" in text:
                        note(text)

        elif kind == "attachment":
            att = rec.get("attachment")
            if not isinstance(att, dict):
                continue
            chars, paths = attachment_size(att)
            if chars == 0:
                chars = sum(slen(r.get("content")) for r in (rec.get("rendered") or []) if isinstance(r, dict))
            attachments[str(att.get("type") or "?")].append((chars, paths))

        elif kind == "system" and rec.get("subtype") == "compact_boundary":
            boundaries += 1

    # A call with zero context is a synthetic record (API error, abort), not a turn.
    usages = [u for u in (usage_by_id[i] for i in order) if u and ctx_of(u) > 0]
    if not usages:
        return None
    ctx = [ctx_of(u) for u in usages]
    outs = [int(u.get("output_tokens") or 0) for u in usages]
    calls = len(ctx)

    def resident(pairs, divisor):
        return sum(chars / divisor * max(calls - turn, 0) for turn, chars in pairs)

    return {
        "first_ts": first_ts, "last_ts": last_ts, "model": model, "version": version, "cwd": cwd,
        "entrypoint": str(entrypoint) if entrypoint else "?",
        "calls": calls, "ctx": ctx, "first_ctx": ctx[0], "peak": max(ctx),
        "total": sum(ctx), "total_out": sum(outs), "base": ctx[0] * calls,
        "r_tool": resident(tool_results, CHARS_PER_TOKEN_TOOL),
        "r_sys": resident(reminders, CHARS_PER_TOKEN_TEXT),
        "r_user": resident(user_text, CHARS_PER_TOKEN_TEXT),
        "r_out": sum(o * max(calls - i - 1, 0) for i, o in enumerate(outs)),
        "reads": reads, "first_edit_turn": first_edit_turn, "spawns": spawns,
        "notifications": notifications, "other_task_notifications": other_tasks,
        "compactions": max(boundaries, summaries),
        "attachments": dict(attachments), "sidechain_skipped": sidechain_skipped,
    }


def in_window(spawn, since, until):
    day = (spawn.get("first_ts") or "")[:10]
    if not (since or until):
        return True
    if not day:
        return False
    return (not since or day >= since) and (not until or day <= until)


def load(project_dir, since, until):
    """All subagent transcripts and main sessions of one project dir."""
    subs, mains = [], []
    info = {"subagent_files": 0, "subagent_skipped_no_usage": 0,
            "main_files": 0, "main_skipped_no_usage": 0, "sidechain_records_skipped": 0}
    for jl in sorted(glob.glob(os.path.join(project_dir, "*", "subagents", "agent-*.jsonl"))):
        info["subagent_files"] += 1
        meta = {}
        meta_path = jl[:-len(".jsonl")] + ".meta.json"
        if os.path.exists(meta_path):
            try:
                with open(meta_path, encoding="utf-8") as fh:
                    loaded = json.load(fh)
                meta = loaded if isinstance(loaded, dict) else {}
            except Exception:
                meta = {}
        spawn = analyse(parse_jsonl(jl))
        if not spawn:
            info["subagent_skipped_no_usage"] += 1
            continue
        spawn["type"] = str(meta.get("agentType") or "?")
        spawn["desc"] = str(meta.get("description") or "")
        spawn["file"] = jl
        subs.append(spawn)
    for jl in sorted(glob.glob(os.path.join(project_dir, "*.jsonl"))):
        info["main_files"] += 1
        session = analyse(parse_jsonl(jl), skip_sidechain=True)
        if not session:
            info["main_skipped_no_usage"] += 1
            continue
        info["sidechain_records_skipped"] += session["sidechain_skipped"]
        session["type"] = ORCH if sum(session["spawns"].values()) else MAIN
        session["desc"] = ""
        session["file"] = jl
        mains.append(session)
    subs = [s for s in subs if in_window(s, since, until)]
    mains = [s for s in mains if in_window(s, since, until)]
    return subs, mains, info


def by_type(subs):
    groups = collections.defaultdict(list)
    for spawn in subs:
        groups[spawn["type"]].append(spawn)
    return groups


def type_order(groups):
    return sorted(groups, key=lambda t: (-len(groups[t]), t))


def iter_groups(groups, orch):
    for t in type_order(groups):
        yield t, groups[t]
    if orch:
        yield ORCH, orch


# --------------------------------------------------------------- sections ---

def build_meta(project_dir, subs, mains, info, since, until, root):
    everything = subs + mains
    days = sorted(d for d in ((s.get("first_ts") or "")[:10] for s in everything) if d)
    versions = sorted({s["version"] for s in everything if s.get("version")}, key=version_key)
    models = collections.Counter(s["model"] for s in everything if s.get("model")).most_common(3)
    return {
        "project_dir": project_dir, "since": since, "until": until,
        "subagent_transcripts": len(subs),
        "subagent_files": info["subagent_files"],
        "subagent_skipped_no_usage": info["subagent_skipped_no_usage"],
        "main_sessions": len(mains), "main_files": info["main_files"],
        "main_skipped_no_usage": info["main_skipped_no_usage"],
        "orchestrator_sessions": sum(1 for s in mains if s["type"] == ORCH),
        "sidechain_records_skipped": info["sidechain_records_skipped"],
        "window": [days[0], days[-1]] if days else None,
        "claude_code_versions": [versions[0], versions[-1]] if versions else None,
        "models": [{"model": m, "n": n} for m, n in models],
        "main_entrypoints": [{"entrypoint": e, "n": n} for e, n in
                             collections.Counter(s["entrypoint"] for s in mains).most_common()],
        "repo_root": root,
    }


def spend_row(t, xs):
    return {"type": t, "spawns": len(xs),
            "calls_med": med(a["calls"] for a in xs),
            "first_ctx_med": med(a["first_ctx"] for a in xs),
            "peak_med": med(a["peak"] for a in xs),
            "total_med": med(a["total"] for a in xs),
            "sum": sum(a["total"] for a in xs)}


def build_spend_map(groups, orch):
    rows = [spend_row(t, xs) for t, xs in iter_groups(groups, orch)]
    return {"rows": rows, "sum_all": sum(r["sum"] for r in rows)}


def build_tail(groups, orch):
    rows = []
    for t, xs in iter_groups(groups, orch):
        n = len(xs)
        total = sum(a["total"] for a in xs)
        ranked = sorted((a["total"] for a in xs), reverse=True)
        top = max(int(round(n * 0.2)), 1) if n else 0
        rows.append({
            "type": t, "n": n,
            "tokens_above_150k": share(sum(c for a in xs for c in a["ctx"] if c > 150000), total),
            "tokens_above_200k": share(sum(c for a in xs for c in a["ctx"] if c > 200000), total),
            "spawns_peak_above_200k": share(sum(1 for a in xs if a["peak"] > 200000), n),
            "spawns_peak_above_300k": share(sum(1 for a in xs if a["peak"] > 300000), n),
            "spawns_peak_above_400k": share(sum(1 for a in xs if a["peak"] > 400000), n),
            "peak_max": max((a["peak"] for a in xs), default=0),
            "calls_p90": p90(a["calls"] for a in xs),
            "top20_spawns_share": share(sum(ranked[:top]), total),
        })
    return {"rows": rows}


def build_baseline(groups, orch):
    rows = []
    for t, xs in iter_groups(groups, orch):
        total = sum(a["total"] for a in xs)
        base = sum(a["base"] for a in xs)
        tool = sum(a["r_tool"] for a in xs)
        sysr = sum(a["r_sys"] for a in xs)
        user = sum(a["r_user"] for a in xs)
        own = sum(a["r_out"] for a in xs)
        rows.append({
            "type": t, "n": len(xs), "total": total,
            "baseline": share(base, total), "tool_results": share(tool, total),
            "own_output": share(own, total), "user_text": share(user, total),
            "sys_reminders": share(sysr, total),
            "unexplained": share(total - base - tool - sysr - user - own, total),
        })
    return {"rows": rows}


def read_pack(spawn):
    return any(os.path.basename(p) == "context-pack.md" for _, p, _, _ in spawn["reads"])


def build_pack_cohort(groups):
    coders = groups.get("harness-coder", [])
    rows = []
    for label, grp in (("read the pack", [a for a in coders if read_pack(a)]),
                       ("no pack", [a for a in coders if not read_pack(a)])):
        edited = [a for a in grp if a["first_edit_turn"]]
        rows.append({
            "cohort": label, "n": len(grp),
            "first_edit_turn_med": med(a["first_edit_turn"] for a in edited),
            "calls_med": med(a["calls"] for a in grp),
            "total_med": med(a["total"] for a in grp),
            "ctx_at_first_edit_med": med(a["ctx"][min(a["first_edit_turn"], a["calls"]) - 1] for a in edited),
            "no_source_edit": len(grp) - len(edited),
        })
    return {"rows": rows}


def build_orchestrator(orch):
    if not orch:
        return {"n": 0}
    notes = [(t, n) for a in orch for t, n in a["notifications"]]
    per_type = collections.defaultdict(list)
    for t, n in notes:
        per_type[t].append(n)
    sizes = [n for _, n in notes]
    return {
        "n": len(orch),
        "first_ctx_med": med(a["first_ctx"] for a in orch),
        "peak_med": med(a["peak"] for a in orch),
        "peak_max": max(a["peak"] for a in orch),
        "calls_med": med(a["calls"] for a in orch),
        "calls_max": max(a["calls"] for a in orch),
        "total_med": med(a["total"] for a in orch),
        "sum": sum(a["total"] for a in orch),
        "spawns_per_session_med": med(sum(a["spawns"].values()) for a in orch),
        "compactions_total": sum(a["compactions"] for a in orch),
        "sessions_with_compaction": sum(1 for a in orch if a["compactions"]),
        "notifications": {
            "n": len(sizes), "other_tasks_excluded": sum(a["other_task_notifications"] for a in orch),
            "kb_med": round(med(sizes) / 1024.0, 1),
            "kb_p90": round(p90(sizes) / 1024.0, 1),
            "kb_max": round(max(sizes) / 1024.0, 1) if sizes else 0,
            "by_type": [{"type": t, "n": len(v), "kb_med": round(med(v) / 1024.0, 1)}
                        for t, v in sorted(per_type.items(), key=lambda kv: -len(kv[1]))],
        },
    }


def build_on_demand(groups, orch):
    rows = []
    for t, xs in iter_groups(groups, orch):
        row = {"type": t, "n": len(xs), "share": {}}
        for name, pred in ON_DEMAND:
            hits = sum(1 for a in xs if any(pred(p) for _, p, _, _ in a["reads"]))
            row["share"][name] = share(hits, len(xs))
        rows.append(row)
    return {"columns": [name for name, _ in ON_DEMAND], "rows": rows}


def build_platform_injection(groups, orch, transcripts, short):
    rows = []
    for t, xs in iter_groups(groups, orch):
        # "logged": spawns whose transcript carries any attachment record at all
        # (Claude Code writes them from 2.1.227); shares are taken over those.
        row = {"type": t, "n": len(xs), "logged": sum(1 for a in xs if a["attachments"]), "kinds": {}}
        for kind in ATTACHMENT_KINDS:
            per_spawn = [sum(n for n, _ in a["attachments"].get(kind, []))
                         for a in xs if a["attachments"].get(kind)]
            row["kinds"][kind] = {
                "spawns_with": len(per_spawn),
                "kb_med": round(med(per_spawn) / 1024.0, 1),
                "kb_max": round(max(per_spawn) / 1024.0, 1) if per_spawn else 0,
            }
        nested = [a for a in xs if a["attachments"].get("nested_memory")]
        row["nested_memory_files_per_spawn_med"] = med(len(a["attachments"]["nested_memory"]) for a in nested)
        rows.append(row)
    files = collections.Counter()
    file_chars = collections.defaultdict(list)
    for a in transcripts:
        for chars, paths in a["attachments"].get("nested_memory", []):
            for p in paths:
                files[short(p)] += 1
                file_chars[short(p)].append(chars)
    top = [{"path": p, "n": c, "kb_med": round(med(file_chars[p]) / 1024.0, 1)}
           for p, c in files.most_common(10)]
    return {"rows": rows, "top_files": top,
            "transcripts": len(transcripts),
            "transcripts_with_attachment_records": sum(1 for a in transcripts if a["attachments"])}


def build_self_reread(groups):
    rows = []
    for t in type_order(groups):
        xs = groups[t]
        own = "espalier/agents/%s.md" % t
        self_chars = []
        waste = []
        for a in xs:
            mine = sum(n for _, p, n, _ in a["reads"] if p.endswith(own))
            if any(p.endswith(own) for _, p, _, _ in a["reads"]):
                self_chars.append(mine)
            seen = set()
            wasted = 0
            for _, p, n, via in a["reads"]:
                if via != "Read":
                    continue
                if p in seen:
                    wasted += n
                seen.add(p)
            waste.append(wasted)
        dup = [w for w in waste if w]
        rows.append({
            "type": t, "n": len(xs),
            "self_reread_share": share(len(self_chars), len(xs)),
            "self_reread_kb_med": round(med(self_chars) / 1024.0, 1),
            "dup_share": share(len(dup), len(xs)),
            "dup_kb_mean_all": round(sum(waste) / len(xs) / 1024.0, 1) if xs else 0,
            "dup_kb_med_with_dup": round(med(dup) / 1024.0, 1),
        })
    return {"rows": rows}


def count_stat(values):
    nonzero = [v for v in values if v]
    return {"changes_with": len(nonzero), "total": sum(values),
            "median": med(nonzero), "max": max(values) if values else 0}


def build_handoff(repo):
    if not repo:
        return {"repo": None, "changes": 0}
    states = sorted(glob.glob(os.path.join(repo, "espalier", "changes", "*", "*", "pipeline-state.md")))
    handoffs, resumes, logs = [], [], []
    for state in states:
        h = r = 0
        try:
            with open(state, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if HANDOFF_RE.match(line):
                        h += 1
                    elif RESUMED_RE.match(line):
                        r += 1
        except OSError:
            continue
        log_dir = os.path.join(os.path.dirname(state), "coding-log")
        n_log = 0
        if os.path.isdir(log_dir):
            n_log = sum(1 for f in os.listdir(log_dir) if os.path.isfile(os.path.join(log_dir, f)))
        handoffs.append(h)
        resumes.append(r)
        logs.append(n_log)
    return {"repo": repo, "changes": len(states),
            "handoff_rows": count_stat(handoffs), "resumed_rows": count_stat(resumes),
            "coding_log_files": count_stat(logs)}


def first_turn_stats(sessions):
    firsts = sorted(a["first_ctx"] for a in sessions)
    latest = max(sessions, key=lambda a: a["first_ts"] or "")
    return {"n": len(sessions), "min": firsts[0],
            "p10": firsts[min(int(len(firsts) * 0.1), len(firsts) - 1)],
            "median": med(firsts), "max": firsts[-1],
            "latest": {"date": (latest["first_ts"] or "")[:10], "first_ctx": latest["first_ctx"]}}


def build_bare(mains):
    """First-turn context of the main sessions, per entrypoint: `cli` is the
    interactive terminal (the harness the owner trims), `sdk-cli` a headless
    `claude -p`, `sdk-py` the Agent SDK."""
    if not mains:
        return {"n": 0}
    groups = collections.defaultdict(list)
    for a in mains:
        groups[a["entrypoint"]].append(a)
    order = sorted(groups, key=lambda e: (e != "cli", -len(groups[e]), e))
    days = sorted(d for d in ((a.get("first_ts") or "")[:10] for a in mains) if d)
    plain = [a["first_ctx"] for a in mains if a["type"] == MAIN]
    return {
        "n": len(mains), "window": [days[0], days[-1]] if days else None,
        "by_entrypoint": [dict(first_turn_stats(groups[e]), entrypoint=e) for e in order],
        "all": first_turn_stats(mains),
        "sessions_without_spawns": {"n": len(plain), "median": med(plain)},
    }


# --------------------------------------------------------------- printing ---

def table(headers, rows):
    cells = [[str(h) for h in headers]] + [[str(c) for c in r] for r in rows]
    widths = [max(len(row[i]) for row in cells) for i in range(len(headers))]
    for row in cells:
        print("  " + "  ".join(c.ljust(widths[i]) if i == 0 else c.rjust(widths[i])
                               for i, c in enumerate(row)).rstrip())


def section(title, note=None):
    print()
    print("## " + title + (" -- " + note if note else ""))


def print_meta(m):
    print("# Context report -- %s" % m["project_dir"])
    window = "%s -> %s" % tuple(m["window"]) if m["window"] else "no dated transcripts"
    if m["since"] or m["until"]:
        window += " (filter %s .. %s)" % (m["since"] or "", m["until"] or "")
    print("subagent transcripts: %d analysed, %d without an API call; main sessions: %d (%d orchestrator, %d without an API call); %s"
          % (m["subagent_transcripts"], m["subagent_skipped_no_usage"], m["main_sessions"],
             m["orchestrator_sessions"], m["main_skipped_no_usage"], window))
    versions = "%s - %s" % tuple(m["claude_code_versions"]) if m["claude_code_versions"] else "?"
    models = ", ".join("%s (%d)" % (x["model"], x["n"]) for x in m["models"]) or "?"
    entrypoints = ", ".join("%s %d" % (x["entrypoint"], x["n"]) for x in m["main_entrypoints"]) or "?"
    print("Claude Code %s; models: %s; main-session entrypoints: %s" % (versions, models, entrypoints))
    if m["repo_root"]:
        print("repo root (most common cwd): %s" % m["repo_root"])
    if m["sidechain_records_skipped"]:
        print("sidechain records skipped in main sessions: %d (subagents inlined by an older Claude Code)"
              % m["sidechain_records_skipped"])


def print_spend_map(s):
    section("1. Spend map", "medians per spawn; total = context sent on every call, summed")
    if not s["rows"]:
        print("  none")
        return
    rows = [[r["type"], r["spawns"], r["calls_med"], fk(r["first_ctx_med"]), fk(r["peak_med"]),
             fm(r["total_med"]), fsum(r["sum"]), pct(share(r["sum"], s["sum_all"]))] for r in s["rows"]]
    rows.append(["all", sum(r["spawns"] for r in s["rows"]), "", "", "", "", fsum(s["sum_all"]), "100%"])
    table(["type", "spawns", "calls", "first-turn", "peak", "total/spawn", "sum", "share"], rows)


def print_tail(s):
    section("2. Tail", "share of tokens processed above a context size; share of spawns peaking above it")
    if not s["rows"]:
        print("  none")
        return
    rows = [[r["type"], r["n"], pct(r["tokens_above_150k"]), pct(r["tokens_above_200k"]),
             pct(r["spawns_peak_above_200k"]), pct(r["spawns_peak_above_300k"]),
             pct(r["spawns_peak_above_400k"]), fk(r["peak_max"]), r["calls_p90"],
             pct(r["top20_spawns_share"])] for r in s["rows"]]
    table(["type", "n", "tok>150k", "tok>200k", "peak>200k", "peak>300k", "peak>400k",
           "max peak", "calls p90", "top-20% spawns"], rows)


def print_baseline(s):
    section("3. Baseline share", "first-turn ctx x calls / total; rest by linear residency (chars / %.1f-%.1f x turns resident)"
            % (CHARS_PER_TOKEN_TOOL, CHARS_PER_TOKEN_TEXT))
    if not s["rows"]:
        print("  none")
        return
    print("  own output counts every output token as resident, thinking included, although the API drops"
          " earlier thinking blocks: an upper bound, so unexplained can go negative on thinking-heavy sessions")
    rows = [[r["type"], r["n"], pct(r["baseline"]), pct(r["tool_results"]), pct(r["own_output"]),
             pct(r["user_text"]), pct(r["sys_reminders"]), pct(r["unexplained"])] for r in s["rows"]]
    table(["type", "n", "baseline", "tool results", "own output", "user text", "sys-reminders", "unexplained"], rows)


def print_pack_cohort(s):
    section("4. Pack cohort (harness-coder)", "spawns that Read a context-pack.md vs not")
    if not any(r["n"] for r in s["rows"]):
        print("  none (no harness-coder spawns)")
        return
    rows = [[r["cohort"], r["n"], r["first_edit_turn_med"] or "-", r["calls_med"], fm(r["total_med"]),
             fk(r["ctx_at_first_edit_med"]) if r["ctx_at_first_edit_med"] else "-", r["no_source_edit"]]
            for r in s["rows"]]
    table(["cohort", "n", "first-edit turn", "calls", "total/spawn", "ctx at first edit", "no source edit"], rows)


def print_orchestrator(s):
    section("5. Orchestrator sessions", "main sessions with at least one Agent spawn")
    if not s["n"]:
        print("  none")
        return
    print("  n=%d  first-turn %s (median)  peak %s median / %s max  calls %d median / %d max  total %s median, %s sum"
          % (s["n"], fk(s["first_ctx_med"]), fk(s["peak_med"]), fk(s["peak_max"]), s["calls_med"],
             s["calls_max"], fm(s["total_med"]), fsum(s["sum"])))
    print("  spawns per session %d (median); compactions: %d in %d sessions"
          % (s["spawns_per_session_med"], s["compactions_total"], s["sessions_with_compaction"]))
    notes = s["notifications"]
    if notes["n"]:
        print("  task-notifications (subagent final messages): n=%d  %s KB median, %s KB p90, %s KB max  (%d from background Bash/Monitor tasks excluded)"
              % (notes["n"], notes["kb_med"], notes["kb_p90"], notes["kb_max"], notes["other_tasks_excluded"]))
        table(["from", "n", "KB med"], [[x["type"], x["n"], x["kb_med"]] for x in notes["by_type"][:8]])
    else:
        print("  task-notifications: none")


def print_on_demand(s):
    section("6. On-demand reads", "share of spawns that opened the file (Read, or cat/sed/head/tail)")
    if not s["rows"]:
        print("  none")
        return
    rows = [[r["type"], r["n"]] + [pct(r["share"][c]) for c in s["columns"]] for r in s["rows"]]
    table(["type", "n"] + s["columns"], rows)


def print_platform_injection(s):
    section("7. Platform doc injection (F.4)", "`attachment` records; KB per spawn over spawns that carry the record")
    if not s["rows"]:
        print("  none")
        return
    print("  transcripts with attachment records: %d of %d (Claude Code logs them from 2.1.227; earlier spawns show none)"
          % (s["transcripts_with_attachment_records"], s["transcripts"]))
    rows = []
    for r in s["rows"]:
        nm = r["kinds"]["nested_memory"]
        rows.append([r["type"], r["n"], r["logged"], nm["spawns_with"],
                     pct(share(nm["spawns_with"], r["logged"]), known=bool(r["logged"])),
                     nm["kb_med"], nm["kb_max"], r["nested_memory_files_per_spawn_med"]])
    print("  nested_memory (scoped CLAUDE.md chain injected on a Read under a workspace); share = of logged:")
    table(["type", "n", "logged", "spawns with", "share", "KB med", "KB max", "files med"], rows)
    print("  other injections, KB per spawn (median) [spawns with]:")
    others = [k for k in ATTACHMENT_KINDS if k != "nested_memory"]
    rows = []
    for r in s["rows"]:
        rows.append([r["type"]] + ["%s [%d]" % (r["kinds"][k]["kb_med"], r["kinds"][k]["spawns_with"]) for k in others])
    table(["type"] + others, rows)
    if s["top_files"]:
        print("  nested_memory files, top %d by injections:" % len(s["top_files"]))
        table(["injections", "KB med", "path"], [[f["n"], f["kb_med"], f["path"]] for f in s["top_files"]])
    else:
        print("  nested_memory files: none")


def print_self_reread(s):
    section("8. Self re-read waste", "spawns that Read espalier/agents/<own type>.md; duplicate Reads of one file inside a spawn")
    if not s["rows"]:
        print("  none")
        return
    rows = [[r["type"], r["n"], pct(r["self_reread_share"]), r["self_reread_kb_med"],
             pct(r["dup_share"]), r["dup_kb_mean_all"], r["dup_kb_med_with_dup"]] for r in s["rows"]]
    table(["type", "n", "self re-read", "KB med", "spawns w/ dup", "dup KB mean", "dup KB med (w/ dup)"], rows)


def print_handoff(s):
    section("9. Handoff / resume (v0.25)", "pipeline-state.md rows and coding-log/ files per change")
    if not s["repo"]:
        print("  none (pass --repo PATH to scan PATH/espalier/changes)")
        return
    print("  repo %s: %d change dirs with pipeline-state.md" % (s["repo"], s["changes"]))
    if not s["changes"]:
        return
    rows = []
    for label, key in (("HANDOFF rows", "handoff_rows"), ("RESUMED rows", "resumed_rows"),
                       ("coding-log/ files", "coding_log_files")):
        st = s[key]
        if st["total"]:
            rows.append([label, st["changes_with"], st["total"], st["median"], st["max"]])
        else:
            rows.append([label, 0, "none", "-", "-"])
    table(["row", "changes with", "n", "median/change", "max/change"], rows)


def print_bare(b):
    if not b["n"]:
        print("bare-session first-turn context: none (no main session made an API call)")
        return
    window = "%s -> %s" % tuple(b["window"]) if b["window"] else "undated"
    print("bare-session first-turn context, %d main sessions (subagents excluded), %s" % (b["n"], window))
    rows = []
    for r in b["by_entrypoint"] + [dict(b["all"], entrypoint="all")]:
        rows.append([r["entrypoint"], r["n"], "{:,}".format(r["min"]), "{:,}".format(r["p10"]),
                     "{:,}".format(r["median"]), "{:,}".format(r["max"]),
                     "{:,} ({})".format(r["latest"]["first_ctx"], r["latest"]["date"])])
    table(["entrypoint", "n", "min", "p10", "median", "max", "latest"], rows)
    plain = b["sessions_without_spawns"]
    print("  cli = interactive terminal (compare this row before and after a harness trim); sdk-cli = headless"
          " `claude -p`; sdk-py = Agent SDK. Sessions without Agent spawns: n={:,}, median {:,}".format(
              plain["n"], plain["median"]))


# ------------------------------------------------------------------- main ---

def parse_day(value, flag):
    if value is None:
        return None
    try:
        return datetime.date.fromisoformat(value).isoformat()
    except ValueError:
        sys.stderr.write("context-report: %s expects YYYY-MM-DD, got %r\n" % (flag, value))
        sys.exit(2)


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Context report for one Claude Code install (where each espalier agent's tokens go).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__.split("Usage:")[0])
    ap.add_argument("project_dir", nargs="?", help="~/.claude/projects/<slug>/ (default: the current directory's)")
    ap.add_argument("--since", metavar="YYYY-MM-DD", help="keep spawns and sessions whose first timestamp is on/after this day")
    ap.add_argument("--until", metavar="YYYY-MM-DD", help="keep spawns and sessions whose first timestamp is on/before this day")
    ap.add_argument("--repo", metavar="PATH", help="repo to scan for espalier/changes/*/*/pipeline-state.md (section 9)")
    ap.add_argument("--json", action="store_true", help="emit the same numbers as JSON")
    ap.add_argument("--bare", action="store_true", help="print only the bare-session first-turn context (main sessions)")
    args = ap.parse_args(argv)

    project_dir = os.path.abspath(args.project_dir) if args.project_dir else default_project_dir()
    if not os.path.isdir(project_dir):
        sys.stderr.write("context-report: project dir not found: %s\n" % project_dir)
        if not args.project_dir:
            sys.stderr.write("  (derived from cwd %s; pass the ~/.claude/projects/<slug>/ path explicitly)\n" % os.getcwd())
        return 2
    since = parse_day(args.since, "--since")
    until = parse_day(args.until, "--until")

    subs, mains, info = load(project_dir, since, until)
    cwds = collections.Counter(s["cwd"] for s in subs + mains if s.get("cwd"))
    root = cwds.most_common(1)[0][0] if cwds else None

    if args.bare:
        bare = build_bare(mains)
        if args.json:
            print(json.dumps(bare, indent=2))
        else:
            print_bare(bare)
        return 0

    groups = by_type(subs)
    orch = [s for s in mains if s["type"] == ORCH]
    repo = args.repo
    if repo is None and root and os.path.isdir(os.path.join(root, "espalier", "changes")):
        repo = root
    report = {
        "meta": build_meta(project_dir, subs, mains, info, since, until, root),
        "spend_map": build_spend_map(groups, orch),
        "tail": build_tail(groups, orch),
        "baseline": build_baseline(groups, orch),
        "pack_cohort": build_pack_cohort(groups),
        "orchestrator": build_orchestrator(orch),
        "on_demand_reads": build_on_demand(groups, orch),
        "platform_injection": build_platform_injection(groups, orch, subs + mains, make_short(root)),
        "self_reread": build_self_reread(groups),
        "handoff": build_handoff(repo),
    }
    if args.json:
        print(json.dumps(report, indent=2, default=str))
        return 0
    print_meta(report["meta"])
    print_spend_map(report["spend_map"])
    print_tail(report["tail"])
    print_baseline(report["baseline"])
    print_pack_cohort(report["pack_cohort"])
    print_orchestrator(report["orchestrator"])
    print_on_demand(report["on_demand_reads"])
    print_platform_injection(report["platform_injection"])
    print_self_reread(report["self_reread"])
    print_handoff(report["handoff"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
