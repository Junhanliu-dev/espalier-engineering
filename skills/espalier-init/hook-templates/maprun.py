#!/usr/bin/env python3
"""
maprun — state machine for the Espalier run lane (/espalier-maprun).

The master agent (see espalier/skills/espalier-maprun/SKILL.md) owns no state in
its context. Everything lives in two files beside the map:

    <map>/plan/plan.json    static  — tickets, dependency edges, worker + sync config
    <map>/plan/state.json   mutable — where every ticket currently stands

Every subcommand reads from disk, mutates, and writes back atomically, so a
master killed at any instant loses nothing but the pass it was mid-way through.

Usage:
    maprun.py <map-dir> init            seed state.json from plan.json
    maprun.py <map-dir> status          human summary of the run
    maprun.py <map-dir> frontier        keys that may be dispatched right now
    maprun.py <map-dir> reap            classify every DISPATCHED worker
    maprun.py <map-dir> pause [reason]  durable dispatch pause (in-flight finish; nothing new)
    maprun.py <map-dir> resume          lift the pause
    maprun.py <map-dir> tail [<k>]     summarize worker stream logs
    maprun.py <map-dir> watch [sec] [--once|--plain]  live dashboard. On a TTY:
                                        full-screen tabbed TUI — Overview plus one
                                        tab per active worker (←/→ or h/l/Tab
                                        switch; ↑/↓ scroll a worker's feed; q
                                        quits). --plain / non-TTY: refreshing
                                        text frame; --once: print one frame.
                                        Read-only — safe in a second terminal
                                        while master passes run.
    maprun.py <map-dir> feed <k> [--follow]   worker's log rendered human-readable:
                                        THINK / SAY / TOOL / RES lines. --follow
                                        streams as the worker writes.
    maprun.py <map-dir> mark <k> <s>    force a ticket's status
    maprun.py <map-dir> set-pr <k> <n> <url>   record a ticket's slice PR
                                        (written by maprun-pr.sh open)
    maprun.py <map-dir> clickup <k>     push status + comment to ClickUp (optional config)
    maprun.py <map-dir> clickup-stages [<k>…]  mirror live pipeline stage to ClickUp:
                                        a "Pipeline: stage N — <label>" subtask under
                                        the ticket's task (created once, renamed as
                                        stages advance) + a stage comment. Defaults to
                                        all DISPATCHED; deduped, state-untouched —
                                        safe from cron/any terminal.
    maprun.py <map-dir> harvest-plan <k>    time-entry payload for the master's MCP post
    maprun.py <map-dir> harvest-record <k> <id>  record a posted entry id
    maprun.py <map-dir> harvest <k>     direct post fallback (token in .local.env)
    maprun.py <map-dir> graph           print the dependency graph

No third-party dependencies: stdlib only, so it runs anywhere the repo does.
External sync (ClickUp/Harvest) is OPTIONAL: absent config keys are silent
no-ops and must never block the build.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

# ── ticket states ────────────────────────────────────────────────────────────
TODO = "TODO"                    # never started, or died and will retry
DISPATCHED = "DISPATCHED"        # a worker is running
PARKED = "PARKED"                # waiting on a human answer; slot released
PASSED = "PASSED"                # worker finished clean, not yet merged
MERGED = "MERGED"                # merged into the integration branch
ESCALATED = "ESCALATED"          # worker gave up; halts the run
BLOCKED = "BLOCKED"              # an upstream dependency escalated
QUOTA = "QUOTA"                  # worker died on a usage limit; resumable
DONE = "DONE"                    # integration-verified at run end

VALID_STATES = {TODO, DISPATCHED, PARKED, PASSED, MERGED, ESCALATED,
                BLOCKED, QUOTA, DONE}
TERMINAL_OK = {MERGED, DONE}
RESUMABLE = {TODO, QUOTA}

# ── run states ───────────────────────────────────────────────────────────────
RUN_IDLE = "IDLE"
RUN_RUNNING = "RUNNING"
RUN_HALTED = "HALTED"
RUN_COMPLETE = "COMPLETE"

# Worker process names _alive() accepts. Session mode records the pid of the
# generated spawn helper (…spawn.sh, whose foreground child is claude/codex);
# staged mode records the wrapper script's pid (…worker.sh).
WORKER_PROC_MARKERS = ("claude", "codex", "worker.sh", "spawn.sh")


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def die(msg):
    print(f"maprun: {msg}", file=sys.stderr)
    sys.exit(1)


def _clip(s, n):
    s = str(s).replace("\n", " ").strip()
    return s if len(s) <= n else s[:n - 1] + "…"


def _tool_arg(inp):
    """Pick the one input field that tells a human what the call does."""
    if not isinstance(inp, dict):
        return ""
    for f in ("command", "file_path", "description", "pattern",
              "prompt", "query", "url"):
        v = inp.get(f)
        if isinstance(v, str) and v.strip():
            return v
    for v in inp.values():
        if isinstance(v, str) and v.strip():
            return v
    return ""


def render_stream_event(ev):
    """One worker stream-json event → zero or more human-readable lines.

    Tags are plain and greppable: THINK (reasoning), SAY (worker text),
    TOOL (a tool call), RES (tool result). Used by `feed` and by the
    `watch` dashboard's last-activity column.
    """
    out = []
    kind = ev.get("type")
    if kind == "system" and ev.get("subtype") == "init":
        out.append(f"== session start (model {ev.get('model', '?')}) ==")
        return out
    if kind == "result":
        out.append(f"== result: {ev.get('subtype')} "
                   f"is_error={ev.get('is_error')} "
                   f"turns={ev.get('num_turns')} "
                   f"cost_usd={ev.get('total_cost_usd')} ==")
        return out
    msg = ev.get("message") or {}
    for block in (msg.get("content") or []):
        if not isinstance(block, dict):
            continue
        bt = block.get("type")
        if bt == "thinking":
            t = (block.get("thinking") or "").strip()
            if t:
                out.append("  THINK " + _clip(t, 300))
        elif bt == "text":
            t = (block.get("text") or "").strip()
            if t:
                out.append("  SAY   " + _clip(t, 300))
        elif bt == "tool_use":
            out.append(f"  TOOL  {block.get('name', '?')}: "
                       + _clip(_tool_arg(block.get("input")), 200))
        elif bt == "tool_result":
            c = block.get("content")
            if isinstance(c, list):
                c = " ".join(b.get("text", "") for b in c
                             if isinstance(b, dict))
            flag = " (ERROR)" if block.get("is_error") else ""
            s = _clip(c or "", 160)
            if s or flag:
                out.append(f"   RES  {s}{flag}")
    return out


# ── file plumbing ────────────────────────────────────────────────────────────
class Run:
    def __init__(self, map_dir):
        self.map_dir = os.path.abspath(map_dir)
        self.plan_dir = os.path.join(self.map_dir, "plan")
        self.plan_path = os.path.join(self.plan_dir, "plan.json")
        self.state_path = os.path.join(self.plan_dir, "state.json")
        if not os.path.isfile(self.plan_path):
            die(f"no plan.json at {self.plan_path}")
        self.plan = json.load(open(self.plan_path))
        self.state = (json.load(open(self.state_path))
                      if os.path.isfile(self.state_path) else None)

    # -- accessors ------------------------------------------------------------
    @property
    def tickets(self):
        return self.plan["tickets"]

    def ticket(self, key):
        for t in self.tickets:
            if t["key"] == key:
                return t
        die(f"unknown ticket '{key}'")

    def ts(self, key):
        """Mutable state for one ticket."""
        if key not in self.state["tickets"]:
            die(f"ticket '{key}' missing from state.json — run `init`?")
        return self.state["tickets"][key]

    def repo_root(self):
        return subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, cwd=self.map_dir
        ).stdout.strip()

    def change_type(self):
        # Map-lane slices are filed under changes/feat/ (charted_from
        # skeletons). Overridable for future non-feat maps.
        return self.plan.get("change_type", "feat")

    # -- persistence ----------------------------------------------------------
    def save(self):
        """Atomic write — a crash mid-save must never truncate state.json."""
        self.state["last_pass"] = now_iso()
        tmp = self.state_path + ".tmp"
        with open(tmp, "w") as fh:
            json.dump(self.state, fh, indent=2, sort_keys=False)
            fh.write("\n")
        os.replace(tmp, self.state_path)

    # -- lifecycle ------------------------------------------------------------
    def init(self, force=False):
        if self.state and not force:
            print(f"state.json already exists — {len(self.state['tickets'])} "
                  f"tickets, status {self.state['status']}. Use --force to reseed.")
            return
        # Fail fast on a malformed graph: an unknown dep key would otherwise
        # crash the first frontier call with a bare KeyError.
        keys = {t["key"] for t in self.tickets}
        for t in self.tickets:
            for d in t.get("deps", []):
                if d not in keys:
                    die(f"ticket '{t['key']}' depends on unknown key '{d}'")
        self.state = {
            "map": self.plan["map"],
            "run_id": f"run-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}",
            "started": now_iso(),
            "last_pass": now_iso(),
            "status": RUN_IDLE,
            "halt_reason": None,
            "passes": 0,
            "tickets": {
                t["key"]: {
                    "status": TODO,
                    "stage": None,
                    "branch": None,
                    "worktree": None,
                    "pid": None,
                    "log": None,
                    "dispatched_at": None,
                    "started_epoch": None,
                    "ended_epoch": None,
                    "hours": None,
                    "attempts": 0,
                    "last_error": None,
                    "harvest_entry_id": None,
                    "clickup_status": None,
                    "pr_number": None,
                    "pr_url": None,
                }
                for t in self.tickets
            },
        }
        os.makedirs(os.path.join(self.plan_dir, "questions"), exist_ok=True)
        os.makedirs(os.path.join(self.plan_dir, "logs"), exist_ok=True)
        self.save()
        print(f"seeded {self.state_path} with {len(self.tickets)} tickets")

    # -- graph ----------------------------------------------------------------
    def deps_of(self, key):
        return self.ticket(key).get("deps", [])

    def dependents_of(self, key):
        return [t["key"] for t in self.tickets if key in t.get("deps", [])]

    def downstream(self, key, seen=None):
        """Transitive dependents — the blast radius of a failure."""
        seen = seen if seen is not None else set()
        for d in self.dependents_of(key):
            if d not in seen:
                seen.add(d)
                self.downstream(d, seen)
        return seen

    def levels(self):
        """Topological levels; index = earliest wave the ticket can run in."""
        depth, changed = {t["key"]: 0 for t in self.tickets}, True
        guard = 0
        while changed and guard < 100:
            changed, guard = False, guard + 1
            for t in self.tickets:
                for d in t.get("deps", []):
                    want = depth[d] + 1
                    if want > depth[t["key"]]:
                        depth[t["key"]], changed = want, True
        if guard >= 100:
            die("dependency graph does not settle — cycle in ticket deps?")
        return depth

    def frontier(self):
        """Tickets that may be dispatched right now.

        Deliberately conservative: an ESCALATED ticket anywhere halts the run
        (the operator's rule), so the frontier is empty while one exists. A
        human pause does the same — in-flight workers finish and are merged,
        but nothing new starts.
        """
        if self.state.get("dispatch_paused"):
            return []
        if any(s["status"] == ESCALATED for s in self.state["tickets"].values()):
            return []
        running = sum(1 for s in self.state["tickets"].values()
                      if s["status"] == DISPATCHED)
        slots = self.plan.get("concurrency", 3) - running
        if slots <= 0:
            return []
        ready = []
        for t in self.tickets:
            st = self.state["tickets"][t["key"]]
            if st["status"] not in RESUMABLE:
                continue
            if all(self.state["tickets"][d]["status"] in TERMINAL_OK
                   for d in t.get("deps", [])):
                ready.append(t["key"])
        # stable order: shallowest first, then plan order
        depth = self.levels()
        order = {t["key"]: i for i, t in enumerate(self.tickets)}
        ready.sort(key=lambda k: (depth[k], order[k]))
        return ready[:slots]

    # -- reaping --------------------------------------------------------------
    def _alive(self, pid):
        if not pid:
            return False
        try:
            os.kill(int(pid), 0)
        except (OSError, ValueError):
            return False
        # PID liveness alone lies after a reboot recycles pids. Confirm the
        # process is actually one of ours; if ps is unavailable, stay
        # conservative and treat it as alive.
        try:
            out = subprocess.run(["ps", "-p", str(pid), "-o", "command="],
                                 capture_output=True, text=True).stdout
            return any(m in out for m in WORKER_PROC_MARKERS)
        except Exception:
            return True

    def _heartbeat_age(self, key):
        """Seconds since the dispatch supervisor last touched the heartbeat."""
        p = os.path.join(self.plan_dir, "logs", f"{key}.heartbeat")
        if not os.path.isfile(p):
            return None
        try:
            lines = [l.strip() for l in open(p) if l.strip()]
            return int(time.time()) - int(lines[-1])
        except (OSError, ValueError, IndexError):
            return None

    def _change_dir(self, key):
        t, st = self.ticket(key), self.ts(key)
        wt = st.get("worktree")
        if not wt:
            return None
        return os.path.join(wt, "espalier", "changes", self.change_type(),
                            t["slug"])

    def _outcome_file(self, key):
        """Sentinel the worker writes on exit; see SKILL.md worker contract."""
        d = self._change_dir(key)
        return os.path.join(d, ".maprun-outcome") if d else None

    def _question_file(self, key):
        """In-worktree question channel (.maprun-question.md).

        The worker has no access to the master's plan/ dir — it parks a
        question INSIDE its own change folder and reap collects it.
        """
        d = self._change_dir(key)
        return os.path.join(d, ".maprun-question.md") if d else None

    def _collect_question(self, key):
        """Move an in-worktree question file to plan/questions/<key>.md.

        Returns True if a question is waiting master-side (either just
        collected or already there from a previous pass).
        """
        dst = os.path.join(self.plan_dir, "questions", f"{key}.md")
        src = self._question_file(key)
        if src and os.path.isfile(src):
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)
            os.unlink(src)
        return os.path.isfile(dst)

    def _pipeline_stage(self, key):
        d = self._change_dir(key)
        if not d:
            return None
        p = os.path.join(d, "pipeline-state.md")
        if not os.path.isfile(p):
            return None
        m = re.search(r"^- Current Stage:\s*(\d+)", open(p).read(), re.M)
        return int(m.group(1)) if m else None

    def _log_says_quota(self, key):
        st = self.ts(key)
        log = st.get("log")
        if not log or not os.path.isfile(log):
            return False
        try:
            tail = open(log, errors="replace").read()[-40000:]
        except OSError:
            return False
        patterns = [
            r"usage limit",
            r"rate.?limit",
            r"\bquota\b",
            r'"status"\s*:\s*429',
            r"\b429\b",
            r"overloaded",
            r"insufficient.*credit",
            r"exceeded.*budget",
        ]
        return any(re.search(p, tail, re.I) for p in patterns)

    def tail(self, key):
        """Summarise a worker's stream-json log: what it is actually doing.

        `claude -p` with --output-format text buffers everything until exit, so
        a running worker looks identical to a hung one. Streaming JSON gives the
        master something to report mid-flight. (codex workers: the log is plain
        text — this degrades to an event count of 0; read the file directly.)
        """
        st = self.ts(key)
        log = st.get("log")
        if not log or not os.path.isfile(log):
            return f"{key}: no log yet"
        events, tools, texts, result = 0, [], [], None
        try:
            with open(log, errors="replace") as fh:
                for raw in fh:
                    raw = raw.strip()
                    if not raw.startswith("{"):
                        continue
                    try:
                        ev = json.loads(raw)
                    except ValueError:
                        continue
                    events += 1
                    kind = ev.get("type")
                    if kind == "result":
                        result = ev
                    msg = ev.get("message") or {}
                    for block in (msg.get("content") or []):
                        if not isinstance(block, dict):
                            continue
                        if block.get("type") == "tool_use":
                            tools.append(block.get("name", "?"))
                        elif block.get("type") == "text":
                            t = (block.get("text") or "").strip()
                            if t:
                                texts.append(t.replace("\n", " ")[:160])
        except OSError as e:
            return f"{key}: cannot read log ({e})"

        out = [f"{key}: {events} stream events"]
        if tools:
            counts = {}
            for t in tools:
                counts[t] = counts.get(t, 0) + 1
            busiest = ", ".join(f"{k}×{v}" for k, v in
                                sorted(counts.items(), key=lambda x: -x[1])[:6])
            out.append(f"  tools : {busiest}")
            out.append(f"  recent: {' → '.join(tools[-6:])}")
        for t in texts[-3:]:
            out.append(f"  said  : {t}")
        if result:
            out.append(f"  RESULT: subtype={result.get('subtype')} "
                       f"is_error={result.get('is_error')} "
                       f"turns={result.get('num_turns')} "
                       f"cost_usd={result.get('total_cost_usd')}")
        return "\n".join(out)

    # -- observability (read-only; safe to run while a master pass is live) ----
    def _log_glance(self, key, max_bytes=400000):
        """From the log tail: the last visible action and the last thing the
        worker SAID (its own narration — usually the best one-line summary of
        where it is)."""
        st = self.ts(key)
        log = st.get("log")
        out = {"last": "", "say": ""}
        if not log or not os.path.isfile(log):
            return out
        try:
            with open(log, "rb") as fh:
                fh.seek(0, 2)
                size = fh.tell()
                fh.seek(max(0, size - max_bytes))
                data = fh.read().decode(errors="replace")
        except OSError:
            return out
        for raw in data.splitlines():
            raw = raw.strip()
            if not raw.startswith("{"):
                continue
            try:
                ev = json.loads(raw)
            except ValueError:
                continue
            for line in render_stream_event(ev):
                line = line.strip()
                if line:
                    out["last"] = line
                if line.startswith("SAY"):
                    out["say"] = line[3:].strip()
        return out

    def _stage_names(self):
        """Stage labels parsed from espalier/pipeline.md (### N. Name).
        Missing file or headings → empty dict; the dashboard shows numbers."""
        if not hasattr(self, "_stage_name_cache"):
            names = {}
            p = os.path.join(self.repo_root(), "espalier", "pipeline.md")
            if os.path.isfile(p):
                try:
                    for m in re.finditer(r"^###\s*(\d+)\.\s*(.+?)\s*$",
                                         open(p, errors="replace").read(),
                                         re.M):
                        names[int(m.group(1))] = m.group(2)
                except OSError:
                    pass
            self._stage_name_cache = names
        return self._stage_name_cache

    @staticmethod
    def _fmt_elapsed(sec):
        if sec is None:
            return ""
        sec = int(sec)
        if sec < 3600:
            return f"{sec // 60}m"
        return f"{sec // 3600}h{(sec % 3600) // 60:02d}m"

    def _wt_progress(self, key):
        """Commits ahead of the integration branch + uncommitted file count —
        the tangible 'has it actually produced anything' signal."""
        st = self.ts(key)
        wt = st.get("worktree")
        if not wt or not os.path.isdir(wt):
            return ""
        try:
            ahead = subprocess.run(
                ["git", "log", "--oneline",
                 f"{self.plan['integration_branch']}..HEAD"],
                capture_output=True, text=True, cwd=wt, timeout=10)
            dirty = subprocess.run(["git", "status", "--porcelain"],
                                   capture_output=True, text=True, cwd=wt,
                                   timeout=10)
        except Exception:
            return ""
        n_ahead = len([l for l in ahead.stdout.splitlines() if l.strip()])
        n_dirty = len([l for l in dirty.stdout.splitlines() if l.strip()])
        bits = [f"{n_ahead} commit{'s' if n_ahead != 1 else ''}"]
        if n_dirty:
            bits.append(f"{n_dirty} dirty")
        return " +".join(bits) if n_dirty else bits[0]

    def _wt_files(self, key, limit=200):
        """Uncommitted changes in the worker's worktree, porcelain-style."""
        st = self.ts(key)
        wt = st.get("worktree")
        if not wt or not os.path.isdir(wt):
            return []
        try:
            out = subprocess.run(["git", "status", "--porcelain"],
                                 capture_output=True, text=True, cwd=wt,
                                 timeout=10).stdout
        except Exception:
            return []
        return [l for l in out.splitlines() if l.strip()][:limit]

    def _wt_commits(self, key, limit=8):
        """Worker's commits ahead of the integration branch, newest first."""
        st = self.ts(key)
        wt = st.get("worktree")
        if not wt or not os.path.isdir(wt):
            return []
        try:
            out = subprocess.run(
                ["git", "log", "--oneline", f"-{limit}",
                 f"{self.plan['integration_branch']}..HEAD"],
                capture_output=True, text=True, cwd=wt, timeout=10).stdout
        except Exception:
            return []
        return [l for l in out.splitlines() if l.strip()]

    def _question_preview(self, key):
        """First substantive line of a waiting question, wherever it sits."""
        for p in [os.path.join(self.plan_dir, "questions", f"{key}.md"),
                  self._question_file(key)]:
            if p and os.path.isfile(p):
                try:
                    for line in open(p, errors="replace"):
                        line = line.strip().lstrip("#").strip()
                        if line and not line.startswith("---"):
                            return _clip(line, 110)
                except OSError:
                    pass
        return ""

    def watch_frame(self):
        """One dashboard frame. Reads state + filesystem signals; writes nothing
        (never calls save() or moves question files), so an operator can leave
        `watch` running in a second terminal while master passes execute."""
        s = self.state
        stale_after = self.plan.get("heartbeat_stale_seconds", 1800)
        counts = {}
        for st in s["tickets"].values():
            counts[st["status"]] = counts.get(st["status"], 0) + 1
        done = sum(counts.get(k, 0) for k in (MERGED, DONE))
        out = [f"map    : {s['map']}",
               f"run    : {s['run_id']}  status {s['status']}  "
               f"pass {s.get('passes', 0)}   "
               + datetime.now().strftime("%H:%M:%S"),
               f"tickets: {done}/{len(s['tickets'])} merged   "
               + ", ".join(f"{k} {v}" for k, v in sorted(counts.items()))]
        if s.get("dispatch_paused"):
            out.append(f"PAUSED : {s.get('pause_reason') or 'by operator'}")
        if s.get("halt_reason"):
            out.append(f"halted : {s['halt_reason']}")
        out.append("")
        depth = self.levels()
        stage_names = self._stage_names()
        for t in self.tickets:
            key = t["key"]
            st = s["tickets"][key]
            name = t.get("name") or t.get("slug") or ""
            row = f"  L{depth[key]} {st['status']:<10} {key:<14}"
            if name:
                row += f" {_clip(name, 52)}"
            status = st["status"]
            if status == DISPATCHED:
                stage = self._pipeline_stage(key) or st.get("stage")
                label = stage_names.get(stage, "")
                hb = self._heartbeat_age(key)
                bits = [f"stage {stage if stage is not None else '?'}"
                        + (f" ({label})" if label else "")]
                el = self._fmt_elapsed(
                    time.time() - st["started_epoch"]
                    if st.get("started_epoch") else None)
                if el:
                    bits.append(f"running {el}")
                if (st.get("attempts") or 0) > 1:
                    bits.append(f"attempt {st['attempts']}")
                prog = self._wt_progress(key)
                if prog:
                    bits.append(prog)
                bits.append("alive" if self._alive(st.get("pid"))
                            else "NO PROCESS")
                if hb is not None:
                    bits.append(f"hb {hb}s"
                                + (" STALE" if hb > stale_after else ""))
                ofile = self._outcome_file(key)
                if ofile and os.path.isfile(ofile):
                    try:
                        verdict = (open(ofile).read().strip().split() or ["?"])[0]
                    except OSError:
                        verdict = "?"
                    bits.append(f"outcome={verdict} (awaiting reap)")
                q = self._question_preview(key)
                if q:
                    bits.append("QUESTION waiting")
                row += "\n        " + " · ".join(bits)
                glance = self._log_glance(key)
                if glance["say"]:
                    row += f"\n        say: {_clip(glance['say'], 150)}"
                if glance["last"] and not glance["last"].startswith("SAY"):
                    row += f"\n        now: {_clip(glance['last'], 150)}"
                if q:
                    row += f"\n        ask: {q}"
            elif status == PARKED:
                q = self._question_preview(key)
                row += "\n        waiting on human answer"
                row += " (next master pass relays it)" if q else \
                       " — question file not found yet"
                if q:
                    row += f"\n        ask: {q}"
            elif status == PASSED:
                prog = self._wt_progress(key)
                row += "\n        finished clean — awaiting merge on next " \
                       "master pass" + (f" ({prog})" if prog else "")
            elif status in (TODO, BLOCKED):
                unmet = [d for d in t.get("deps", [])
                         if s["tickets"][d]["status"] not in TERMINAL_OK]
                if unmet:
                    row += "  waits: " + ",".join(unmet)
                if st.get("last_error"):
                    row += f"  ({_clip(st['last_error'], 70)})"
            elif st.get("last_error"):
                row += f"  ({_clip(st['last_error'], 70)})"
            out.append(row)
        fr = self.frontier()
        out.append("")
        out.append("frontier: " + (", ".join(fr) if fr else "(none)"))
        out.append("(read-only view — safe beside a live master; Ctrl-C exits. "
                   "Full worker trail: maprun.py <map> feed <key> --follow)")
        return "\n".join(out)

    def feed(self, key, follow=False):
        """Chronological human render of a worker's log: thinking, text, tool
        calls, tool results. Non-JSON lines (codex logs, staged-wrapper leg
        markers) pass through raw. --follow keeps streaming as the file grows."""
        st = self.ts(key)
        log = st.get("log")
        if not log:
            print(f"{key}: no log recorded in state.json")
            return
        pos, buf = 0, ""
        printed_missing = False
        while True:
            if os.path.isfile(log):
                printed_missing = False
                try:
                    with open(log, errors="replace") as fh:
                        fh.seek(pos)
                        chunk = fh.read()
                        pos = fh.tell()
                except OSError as e:
                    print(f"{key}: cannot read log ({e})")
                    return
                buf += chunk
                lines = buf.split("\n")
                buf = lines.pop()          # keep any partial trailing line
                for raw in lines:
                    raw = raw.strip()
                    if not raw:
                        continue
                    if not raw.startswith("{"):
                        print(f"  | {raw}", flush=True)
                        continue
                    try:
                        ev = json.loads(raw)
                    except ValueError:
                        print(f"  | {_clip(raw, 200)}", flush=True)
                        continue
                    for line in render_stream_event(ev):
                        print(line, flush=True)
            elif not printed_missing:
                print(f"{key}: log not written yet"
                      + (" — waiting" if follow else ""), flush=True)
                printed_missing = True
            if not follow:
                return
            time.sleep(2)

    def _git_state_ok(self, key, stage):
        """Does the worktree actually match the stage its state file claims?

        Catches a worker that died between writing pipeline-state.md and doing
        the work that state describes — the nastiest resume case.
        """
        st = self.ts(key)
        wt = st.get("worktree")
        if not wt or not os.path.isdir(wt):
            return False, "worktree missing"
        if stage and stage >= 3:
            r = subprocess.run(["git", "log", "--oneline",
                                f"{self.plan['integration_branch']}..HEAD"],
                               capture_output=True, text=True, cwd=wt)
            dirty = subprocess.run(["git", "status", "--porcelain"],
                                   capture_output=True, text=True, cwd=wt)
            if not r.stdout.strip() and not dirty.stdout.strip():
                return False, f"stage {stage} claimed but worktree has no work"
        return True, "ok"

    def reap(self):
        """Classify every DISPATCHED ticket. Returns a list of transitions."""
        moves = []
        self.state["passes"] = (self.state.get("passes") or 0) + 1
        stale_after = self.plan.get("heartbeat_stale_seconds", 1800)
        for key, st in self.state["tickets"].items():
            if st["status"] != DISPATCHED:
                continue
            alive = self._alive(st.get("pid"))
            outcome_path = self._outcome_file(key)
            outcome = None
            if outcome_path and os.path.isfile(outcome_path):
                outcome = open(outcome_path).read().strip().split()[0].upper()
            stage = self._pipeline_stage(key)
            if stage:
                st["stage"] = stage

            # question parked by the worker (collected from its worktree)
            if self._collect_question(key) and outcome in (None, "PARKED"):
                st["status"] = PARKED
                st["ended_epoch"] = int(time.time())
                moves.append((key, PARKED, "worker parked a question"))
                continue

            if outcome == "PASSED":
                st["status"] = PASSED
                st["ended_epoch"] = int(time.time())
                moves.append((key, PASSED, f"clean at stage {stage}"))
            elif outcome in ("ESCALATED", "ABORTED", "MISBASED"):
                st["status"] = ESCALATED
                st["ended_epoch"] = int(time.time())
                st["last_error"] = f"worker reported {outcome}"
                moves.append((key, ESCALATED, f"worker reported {outcome}"))
            elif alive:
                # Still working — but a heartbeat older than the stale window
                # with a "live" pid usually means a recycled pid or a dead
                # supervisor loop. Flag it; the master inspects with `tail`.
                age = self._heartbeat_age(key)
                if age is not None and age > stale_after:
                    st["last_error"] = (f"heartbeat stale {age}s with live pid "
                                        f"— inspect with `tail {key}`; if the "
                                        f"worker is gone, mark TODO by hand")
                    moves.append((key, DISPATCHED,
                                  f"SUSPECT: heartbeat stale {age}s"))
                continue
            else:
                # process gone with no outcome — died. Why?
                if self._log_says_quota(key):
                    st["status"] = QUOTA
                    st["last_error"] = "usage limit hit; resumable"
                    st["ended_epoch"] = int(time.time())
                    moves.append((key, QUOTA, "usage limit — resumable"))
                else:
                    ok, why = self._git_state_ok(key, stage)
                    st["status"] = TODO
                    if not ok:
                        # The state file claims work the worktree cannot show.
                        # Clear the recorded stage so nothing resumes the lie —
                        # the next worker rebuilds from git evidence (worker
                        # contract: resume discipline).
                        st["stage"] = None
                    st["last_error"] = f"worker died ({why})"
                    st["ended_epoch"] = int(time.time())
                    moves.append((key, TODO, f"worker died ({why}) — will retry"))

        # any escalation halts the run and marks the blast radius
        esc = [k for k, s in self.state["tickets"].items()
               if s["status"] == ESCALATED]
        if esc:
            self.state["status"] = RUN_HALTED
            self.state["halt_reason"] = f"escalated: {', '.join(sorted(esc))}"
            for e in esc:
                for d in self.downstream(e):
                    ds = self.state["tickets"][d]
                    if ds["status"] in RESUMABLE:
                        ds["status"] = BLOCKED
                        ds["last_error"] = f"upstream {e} escalated"
        self.save()
        return moves

    # -- reporting ------------------------------------------------------------
    def status_report(self):
        s = self.state
        counts = {}
        for st in s["tickets"].values():
            counts[st["status"]] = counts.get(st["status"], 0) + 1
        out = [f"map    : {s['map']}",
               f"run    : {s['run_id']}  status {s['status']}  pass {s.get('passes', 0)}"]
        if s.get("dispatch_paused"):
            out.append(f"PAUSED : {s.get('pause_reason') or 'by operator'} "
                       "— in-flight finish and merge; nothing new dispatches")
        if s.get("halt_reason"):
            out.append(f"halted : {s['halt_reason']}")
        out.append("counts : " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
        out.append("")
        depth = self.levels()
        for t in self.tickets:
            st = s["tickets"][t["key"]]
            deps = ",".join(t.get("deps", [])) or "-"
            extra = ""
            if st.get("stage"):
                extra += f" stage={st['stage']}"
            if st.get("pr_number"):
                extra += f" PR#{st['pr_number']}"
            if st.get("last_error"):
                extra += f"  ({st['last_error']})"
            out.append(f"  L{depth[t['key']]} {st['status']:<10} {t['key']:<14} "
                       f"deps[{deps}]{extra}")
        fr = self.frontier()
        out.append("")
        out.append("frontier: " + (", ".join(fr) if fr else "(none)"))
        return "\n".join(out)

    def graph(self):
        depth = self.levels()
        by_level = {}
        for t in self.tickets:
            by_level.setdefault(depth[t["key"]], []).append(t["key"])
        out = []
        for lvl in sorted(by_level):
            out.append(f"L{lvl}: " + "  ".join(by_level[lvl]))
        return "\n".join(out)


# ── watch TUI (read-only; stdlib curses) ─────────────────────────────────────
class _FeedReader:
    """Incremental reader of one worker's log → rendered feed lines.

    Keeps a byte offset so each poll parses only what the worker wrote since
    the last one. On first open of a large log it starts from the last
    ~300KB so the TUI comes up instantly.
    """
    def __init__(self, log):
        self.log = log
        self.pos = None      # None = not opened yet
        self.buf = ""
        self.lines = []

    def poll(self):
        if not self.log or not os.path.isfile(self.log):
            return
        try:
            with open(self.log, errors="replace") as fh:
                if self.pos is None:
                    fh.seek(0, 2)
                    size = fh.tell()
                    self.pos = max(0, size - 300000)
                    if self.pos:
                        self.lines.append("| … older output omitted — "
                                          "full trail: feed <key> …")
                fh.seek(self.pos)
                chunk = fh.read()
                self.pos = fh.tell()
        except OSError:
            return
        if not chunk:
            return
        self.buf += chunk
        raw_lines = self.buf.split("\n")
        self.buf = raw_lines.pop()
        for raw in raw_lines:
            raw = raw.strip()
            if not raw:
                continue
            if raw.startswith("{"):
                try:
                    ev = json.loads(raw)
                except ValueError:
                    self.lines.append("| " + _clip(raw, 300))
                    continue
                self.lines.extend(render_stream_event(ev))
            else:
                self.lines.append("| " + _clip(raw, 300))
        del self.lines[:-800]


def _tui_wrap(line, width, max_rows=4):
    """Soft-wrap one feed line into at most max_rows display rows."""
    line = line.rstrip()
    if not line:
        return [""]
    rows = []
    indent = ""
    while line and len(rows) < max_rows:
        rows.append(indent + line[:width - len(indent)])
        line = line[width - len(indent):]
        indent = "        "
    if line:
        rows[-1] = rows[-1][:max(0, width - 2)] + "…"
    return rows


def watch_tui(map_dir, refresh=2):
    """Full-screen dashboard. ←/→ (or h/l, Tab) switch tabs: Overview first,
    then one tab per active worker (DISPATCHED/PARKED/QUOTA) with job detail,
    live file changes, and the worker's feed streaming like a terminal.
    ↑/↓/PgUp/PgDn scroll a worker feed, End/G resumes follow, q quits.
    Read-only throughout — identical safety to `watch --plain`."""
    import curses
    import locale
    locale.setlocale(locale.LC_ALL, "")

    readers = {}
    scrolls = {}                       # tab key → rows scrolled up from tail

    def color_for(token, pairs):
        for needle, pair in (("MERGED", 1), ("DONE", 1), ("PASSED", 1),
                             ("DISPATCHED", 2), ("QUOTA", 3), ("PARKED", 3),
                             ("ESCALATED", 4), ("BLOCKED", 4),
                             ("NO PROCESS", 4), ("STALE", 4)):
            if needle in token:
                return pairs.get(pair, 0)
        return 0

    def feed_attr(line, pairs, A):
        s = line.lstrip()
        if s.startswith("TOOL"):
            return pairs.get(3, 0)
        if s.startswith("SAY"):
            return A["bold"]
        if s.startswith("THINK") or s.startswith("RES") or s.startswith("|"):
            return A["dim"]
        if s.startswith("=="):
            return pairs.get(2, 0)
        return 0

    def paint(scr, y, x, text, attr=0):
        h, w = scr.getmaxyx()
        if 0 <= y < h and x < w:
            try:
                scr.addnstr(y, x, text, w - x - 1, attr)
            except curses.error:
                pass

    def draw(scr, run, tabs, active, pairs, A):
        scr.erase()
        h, w = scr.getmaxyx()
        # tab bar
        x = 0
        for i, tab in enumerate(tabs):
            label = f" {tab if tab != '__overview__' else 'Overview'} "
            attr = curses.A_REVERSE if i == active else A["dim"]
            paint(scr, 0, x, label, attr)
            x += len(label) + 1
        paint(scr, 0, max(x + 1, w - 20),
              datetime.now().strftime("%H:%M:%S"), A["dim"])
        tab = tabs[active]
        if tab == "__overview__":
            for i, line in enumerate(run.watch_frame().split("\n")):
                paint(scr, 2 + i, 0, line, color_for(line, pairs))
            paint(scr, h - 1, 0,
                  "←/→ switch tab · q quit · read-only", A["dim"])
        else:
            draw_worker(scr, run, tab, pairs, A, h, w)
        scr.refresh()

    def draw_worker(scr, run, key, pairs, A, h, w):
        t, st = run.ticket(key), run.ts(key)
        stage = run._pipeline_stage(key) or st.get("stage")
        label = run._stage_names().get(stage, "")
        hb = run._heartbeat_age(key)
        alive = run._alive(st.get("pid"))
        y = 2
        paint(scr, y, 0, f"{key} — {t.get('name') or t.get('slug') or ''}",
              A["bold"]); y += 1
        bits = [st["status"],
                f"stage {stage if stage is not None else '?'}"
                + (f" ({label})" if label else "")]
        el = Run._fmt_elapsed(time.time() - st["started_epoch"]
                              if st.get("started_epoch") else None)
        if el:
            bits.append(f"running {el}")
        if (st.get("attempts") or 0) > 1:
            bits.append(f"attempt {st['attempts']}")
        bits.append("alive" if alive else "NO PROCESS")
        if hb is not None:
            bits.append(f"hb {hb}s")
        line = " · ".join(bits)
        paint(scr, y, 0, line, color_for(line, pairs)); y += 1
        paint(scr, y, 0, f"branch {st.get('branch') or '?'} · "
              f"worktree {st.get('worktree') or '?'}", A["dim"]); y += 1
        deps = ",".join(t.get("deps", [])) or "-"
        paint(scr, y, 0, f"deps [{deps}] · requirement: "
              + _clip(t.get("requirement") or "", w - 30), A["dim"]); y += 1
        q = run._question_preview(key)
        if q:
            paint(scr, y, 0, f"QUESTION waiting: {q}", pairs.get(3, 0)); y += 1
        commits = run._wt_commits(key)
        files = run._wt_files(key)
        paint(scr, y, 0, f"commits ahead {len(commits)} · "
              f"uncommitted files {len(files)}", 0); y += 1
        for c in commits[:3]:
            paint(scr, y, 2, _clip(c, w - 4), pairs.get(1, 0)); y += 1
        file_rows = min(len(files), max(0, (h // 3) - (y - 6)), 8)
        for f in files[:file_rows]:
            paint(scr, y, 2, _clip(f, w - 4), 0); y += 1
        if len(files) > file_rows:
            paint(scr, y, 2, f"… +{len(files) - file_rows} more files",
                  A["dim"]); y += 1
        paint(scr, y, 0, "─" * (w - 1), A["dim"]); y += 1
        # feed pane — bottom of screen, follows tail unless scrolled
        rd = readers.get(key)
        pane_h = h - y - 1
        if rd and pane_h > 0:
            rows = []
            for line in rd.lines[-400:]:
                for r in _tui_wrap(line, w - 1):
                    rows.append((r, feed_attr(line, pairs, A)))
            off = min(scrolls.get(key, 0), max(0, len(rows) - pane_h))
            scrolls[key] = off
            view = rows[-(pane_h + off): len(rows) - off or None]
            for i, (r, attr) in enumerate(view[-pane_h:]):
                paint(scr, y + i, 0, r, attr)
        hint = "←/→ tab · ↑/↓ PgUp/PgDn scroll · End follow · q quit"
        if scrolls.get(key, 0):
            hint = f"[scrolled ↑{scrolls[key]}] " + hint
        paint(scr, h - 1, 0, hint, A["dim"])

    def loop(scr):
        curses.curs_set(0)
        scr.timeout(int(refresh * 1000))
        pairs = {}
        if curses.has_colors():
            curses.start_color()
            curses.use_default_colors()
            for n, fg in ((1, curses.COLOR_GREEN), (2, curses.COLOR_CYAN),
                          (3, curses.COLOR_YELLOW), (4, curses.COLOR_RED)):
                curses.init_pair(n, fg, -1)
                pairs[n] = curses.color_pair(n)
        A = {"dim": curses.A_DIM, "bold": curses.A_BOLD}
        active = 0
        while True:
            run = Run(map_dir)          # fresh read — master mutates between frames
            if run.state is None:
                return
            act = [t["key"] for t in run.tickets
                   if run.ts(t["key"])["status"] in (DISPATCHED, PARKED, QUOTA)]
            tabs = ["__overview__"] + act
            active = min(active, len(tabs) - 1)
            for k in act:
                st = run.ts(k)
                if k not in readers or readers[k].log != st.get("log"):
                    readers[k] = _FeedReader(st.get("log"))
                readers[k].poll()
            draw(scr, run, tabs, active, pairs, A)
            ch = scr.getch()
            if ch in (ord("q"), ord("Q")):
                return
            if ch in (curses.KEY_RIGHT, ord("l"), ord("\t")):
                active = (active + 1) % len(tabs)
            elif ch in (curses.KEY_LEFT, ord("h")):
                active = (active - 1) % len(tabs)
            elif ord("1") <= ch <= ord("9") and ch - ord("1") < len(tabs):
                active = ch - ord("1")
            elif tabs[active] != "__overview__":
                k = tabs[active]
                if ch == curses.KEY_UP:
                    scrolls[k] = scrolls.get(k, 0) + 1
                elif ch == curses.KEY_DOWN:
                    scrolls[k] = max(0, scrolls.get(k, 0) - 1)
                elif ch == curses.KEY_PPAGE:
                    scrolls[k] = scrolls.get(k, 0) + 20
                elif ch == curses.KEY_NPAGE:
                    scrolls[k] = max(0, scrolls.get(k, 0) - 20)
                elif ch in (curses.KEY_END, ord("G")):
                    scrolls[k] = 0

    curses.wrapper(loop)


# ── external sync (OPTIONAL — absent config = silent no-op) ──────────────────
def _read_env(path, name):
    if not os.path.isfile(path):
        return None
    for line in open(path):
        m = re.match(rf"^{re.escape(name)}=(.*)$", line.strip())
        if m:
            return m.group(1).strip().strip('"').strip("'")
    return None


def _http(method, url, headers, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code}: {e.read().decode()[:300]}")
    except urllib.error.URLError as e:
        raise RuntimeError(f"network: {e}")


def clickup_sync(run, key, note=None):
    """Move the ClickUp status and leave a comment describing the transition."""
    cfg = run.plan.get("clickup") or {}
    if not cfg:
        return "no clickup config — skipped"
    t, st = run.ticket(key), run.ts(key)
    task_id = t.get("clickup")
    if not task_id:
        return "no clickup id on ticket"
    api_key = _read_env(os.path.join(run.repo_root(), ".local.env"),
                        "CLICKUP_API_KEY")
    if not api_key:
        return "CLICKUP_API_KEY not found — skipped"
    want = (cfg.get("status_map") or {}).get(st["status"])
    hdr = {"Authorization": api_key, "Content-Type": "application/json"}
    done = []
    if want and want != st.get("clickup_status"):
        _http("PUT", f"https://api.clickup.com/api/v2/task/{task_id}",
              hdr, {"status": want})
        st["clickup_status"] = want
        done.append(f"status→{want}")
    live_stage = run._pipeline_stage(key) or st.get("stage")
    body = note or f"**{st['status']}**" + (
        f" — stage {live_stage}" if live_stage else "")
    if st.get("last_error"):
        body += f"\n\n> {st['last_error']}"
    _http("POST", f"https://api.clickup.com/api/v2/task/{task_id}/comment",
          hdr, {"comment_text": body, "notify_all": False})
    done.append("commented")
    # keep the 'Pipeline: …' subtask honest at rest states
    side = _read_stage_sidecar(_stage_sidecar_path(run, key))
    if side.get("subtask") and st["status"] in (MERGED, DONE, ESCALATED,
                                                PARKED, QUOTA):
        final = {MERGED: "Pipeline: merged ✓",
                 DONE: "Pipeline: done ✓",
                 PARKED: "Pipeline: parked — waiting on a human answer",
                 QUOTA: "Pipeline: paused on usage limit (resumable)"}.get(
            st["status"], "Pipeline: escalated"
            + (f" at stage {live_stage}" if live_stage else ""))
        try:
            _http("PUT",
                  f"https://api.clickup.com/api/v2/task/{side['subtask']}",
                  hdr, {"name": final})
            done.append("subtask finalized")
        except RuntimeError:
            pass
    run.save()
    return ", ".join(done)


def _stage_sidecar_path(run, key):
    return os.path.join(run.plan_dir, "logs", f".clickup-stage-{key}")


def _read_stage_sidecar(path):
    """{"stage": N, "subtask": id} — tolerates the legacy bare-int format."""
    try:
        raw = open(path).read().strip()
    except OSError:
        return {}
    try:
        d = json.loads(raw)
        return d if isinstance(d, dict) else {}
    except ValueError:
        try:
            return {"stage": int(raw)}
        except ValueError:
            return {}


def clickup_stage_ping(run, key):
    """Mirror the worker's LIVE stage onto ClickUp: one 'Pipeline: …' subtask
    under the ticket's task (created on first stage, renamed as stages
    advance) plus an optional stage comment.

    Reads the stage straight from the worktree's pipeline-state.md and dedupes
    via a sidecar in plan/logs — it never writes state.json, so it is safe to
    run from any terminal or a cron while a master pass is mid-flight
    (clickup_sync, which does save state, stays master-only)."""
    cfg = run.plan.get("clickup") or {}
    if not cfg:
        return "no clickup config — skipped"
    t, st = run.ticket(key), run.ts(key)
    task_id = t.get("clickup")
    if not task_id:
        return "no clickup id on ticket"
    stage = run._pipeline_stage(key) or st.get("stage")
    if not stage:
        return "no stage yet"
    marker = _stage_sidecar_path(run, key)
    side = _read_stage_sidecar(marker)
    if side.get("stage") == stage and (side.get("subtask")
                                       or cfg.get("stage_subtask") is False):
        return f"stage {stage} already posted"
    api_key = _read_env(os.path.join(run.repo_root(), ".local.env"),
                        "CLICKUP_API_KEY")
    if not api_key:
        return "CLICKUP_API_KEY not found — skipped"
    label = run._stage_names().get(stage, "")
    name = f"Pipeline: stage {stage}" + (f" — {label}" if label else "")
    hdr = {"Authorization": api_key, "Content-Type": "application/json"}
    made = []
    sub = side.get("subtask")
    if cfg.get("stage_subtask", True):
        if not sub:
            parent = _http("GET",
                           f"https://api.clickup.com/api/v2/task/{task_id}",
                           hdr)
            list_id = (parent.get("list") or {}).get("id")
            if list_id:
                created = _http(
                    "POST",
                    f"https://api.clickup.com/api/v2/list/{list_id}/task",
                    hdr, {"name": name, "parent": task_id})
                sub = created.get("id")
                made.append("subtask created")
        else:
            _http("PUT", f"https://api.clickup.com/api/v2/task/{sub}",
                  hdr, {"name": name})
            made.append("subtask renamed")
    if cfg.get("stage_comments", True) and side.get("stage") != stage:
        el = Run._fmt_elapsed(time.time() - st["started_epoch"]
                              if st.get("started_epoch") else None)
        body = (f"maprun: stage {stage}" + (f" — {label}" if label else "")
                + (f" ({el} in)" if el else ""))
        _http("POST",
              f"https://api.clickup.com/api/v2/task/{task_id}/comment",
              hdr, {"comment_text": body, "notify_all": False})
        made.append("commented")
    os.makedirs(os.path.dirname(marker), exist_ok=True)
    with open(marker, "w") as fh:
        fh.write(json.dumps({"stage": stage, "subtask": sub}))
    return f"stage {stage}: " + (", ".join(made) or "nothing to do")


def _harvest_notes(run, key):
    t = run.ticket(key)
    link = (f"https://app.clickup.com/t/{t['clickup']}"
            if t.get("clickup") else "(no tracker ticket)")
    # House convention where a tracker id exists: "#<id> - <name>".
    ref = f"#{t['clickup']} - " if t.get("clickup") else ""
    return (f"{ref}{t['name']}\n"
            f"Espalier slice {t['slug']} — pipeline stages 1-6, "
            f"review panel clean.\n{link}")


def harvest_plan(run, key):
    """Compute the time entry WITHOUT posting it.

    The master is an interactive session with the Harvest MCP connected, so it
    posts via `mcp__harvest__log_time` and records the id with `harvest-record`.
    This keeps the credential out of the repo entirely — `.local.env` needs no
    Harvest token.
    """
    cfg = run.plan.get("harvest") or {}
    if not cfg:
        return {"skip": "no harvest config"}
    st = run.ts(key)
    if st.get("harvest_entry_id"):
        return {"skip": f"already logged as entry {st['harvest_entry_id']}"}
    if not (st.get("started_epoch") and st.get("ended_epoch")):
        return {"skip": "no start/end recorded"}
    hours = max(round((st["ended_epoch"] - st["started_epoch"]) / 3600.0, 2), 0.01)
    # mode record_only: the operator runs their own timer against this project,
    # so posting per-ticket entries would double-count. Record, post nothing.
    if (cfg.get("mode") or "post") == "record_only":
        st["hours"] = hours
        run.save()
        return {"skip": f"record_only — {hours}h recorded in state.json, not posted",
                "hours": hours}
    return {
        "project_id": cfg.get("project_id"),
        "task_id": cfg.get("task_id"),
        "spent_at": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "hours": hours,
        "notes": _harvest_notes(run, key),
    }


def harvest_record(run, key, entry_id):
    st = run.ts(key)
    st["harvest_entry_id"] = entry_id
    plan = harvest_plan(run, key)
    if "hours" in plan:
        st["hours"] = plan["hours"]
    run.save()
    return f"recorded Harvest entry {entry_id} for {key}"


def harvest_log(run, key):
    """Fallback: post directly, for headless use when a token IS configured."""
    cfg = run.plan.get("harvest") or {}
    if not cfg:
        return "no harvest config — skipped"
    st = run.ts(key)
    if st.get("harvest_entry_id"):
        return f"already logged ({st['harvest_entry_id']})"
    if not (st.get("started_epoch") and st.get("ended_epoch")):
        return "no start/end recorded — skipped"
    if (cfg.get("mode") or "post") == "record_only":
        st["hours"] = max(round((st["ended_epoch"] - st["started_epoch"]) / 3600.0, 2), 0.01)
        run.save()
        return f"record_only — {st['hours']}h recorded, not posted"
    token = _read_env(os.path.join(run.repo_root(), ".local.env"),
                      "HARVEST_ACCESS_TOKEN")
    account = _read_env(os.path.join(run.repo_root(), ".local.env"),
                        "HARVEST_ACCOUNT_ID")
    if not (token and account):
        return "HARVEST_ACCESS_TOKEN/HARVEST_ACCOUNT_ID not in .local.env — skipped"
    hours = max(round((st["ended_epoch"] - st["started_epoch"]) / 3600.0, 2), 0.01)
    st["hours"] = hours
    hdr = {"Authorization": f"Bearer {token}",
           "Harvest-Account-Id": str(account),
           "Content-Type": "application/json",
           "User-Agent": "espalier-maprun"}
    res = _http("POST", "https://api.harvestapp.com/v2/time_entries", hdr, {
        "project_id": cfg.get("project_id"),
        "task_id": cfg.get("task_id"),
        "spent_date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "hours": hours,
        "notes": _harvest_notes(run, key),
    })
    st["harvest_entry_id"] = res.get("id")
    run.save()
    return f"logged {hours}h as entry {res.get('id')}"


# ── cli ──────────────────────────────────────────────────────────────────────
def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    map_dir, cmd, rest = argv[1], argv[2], argv[3:]
    run = Run(map_dir)

    if cmd == "init":
        run.init(force="--force" in rest)
        return 0
    if run.state is None:
        die("no state.json — run `init` first")

    if cmd == "status":
        print(run.status_report())
    elif cmd == "graph":
        print(run.graph())
    elif cmd == "pause":
        run.state["dispatch_paused"] = True
        run.state["pause_reason"] = " ".join(rest) or "paused by operator"
        run.save()
        print(f"dispatch PAUSED — {run.state['pause_reason']}\n"
              "In-flight workers finish and are merged; nothing new is dispatched.\n"
              "Resume with: maprun.py <map-dir> resume")
    elif cmd == "resume":
        run.state["dispatch_paused"] = False
        run.state["pause_reason"] = None
        run.save()
        print("dispatch RESUMED")
    elif cmd == "frontier":
        print("\n".join(run.frontier()))
    elif cmd == "tail":
        keys = rest or [k for k, s in run.state["tickets"].items()
                        if s["status"] == DISPATCHED]
        if not keys:
            print("nothing dispatched")
        for k in keys:
            print(run.tail(k))
            print()
    elif cmd == "watch":
        interval, once, plain = 10, "--once" in rest, "--plain" in rest
        for a in rest:
            if a.isdigit():
                interval = max(2, int(a))
        if not (once or plain) and sys.stdout.isatty():
            # full-screen tabbed TUI; falls back to the plain loop anywhere
            # curses is unavailable (some minimal containers)
            try:
                watch_tui(map_dir, refresh=min(interval, 5))
                return 0
            except ImportError:
                pass
            except KeyboardInterrupt:
                return 0
        try:
            while True:
                # rebuild per frame: the master mutates state.json between frames
                frame = Run(map_dir).watch_frame()
                if once:
                    print(frame)
                    break
                print("\033[2J\033[H" + frame, flush=True)
                time.sleep(interval)
        except KeyboardInterrupt:
            print()
    elif cmd == "feed":
        if not rest:
            die("feed <ticket> [--follow]")
        try:
            run.feed(rest[0], follow=("--follow" in rest or "-f" in rest))
        except KeyboardInterrupt:
            print()
    elif cmd == "reap":
        moves = run.reap()
        if not moves:
            print("no transitions")
        for k, s, why in moves:
            print(f"{k}: → {s}  ({why})")
    elif cmd == "mark":
        if len(rest) < 2:
            die("mark <ticket> <status> [--stage N] [--error MSG] [--pid N] "
                "[--worktree P] [--branch B] [--log P]")
        key, status = rest[0], rest[1].upper()
        if status not in VALID_STATES:
            die(f"invalid status '{status}' — one of: "
                + ", ".join(sorted(VALID_STATES)))
        st = run.ts(key)
        st["status"] = status
        for i, a in enumerate(rest):
            nxt = rest[i + 1] if i + 1 < len(rest) else None
            if a == "--stage" and nxt:
                st["stage"] = int(nxt)
            elif a == "--error" and nxt:
                st["last_error"] = nxt
            elif a == "--pid" and nxt:
                st["pid"] = int(nxt)
            elif a == "--worktree" and nxt:
                st["worktree"] = nxt
            elif a == "--branch" and nxt:
                st["branch"] = nxt
            elif a == "--log" and nxt:
                st["log"] = nxt
        if status == DISPATCHED:
            st["dispatched_at"] = now_iso()
            st["started_epoch"] = int(time.time())
            st["attempts"] = (st.get("attempts") or 0) + 1
            st["last_error"] = None
            run.state["status"] = RUN_RUNNING
        if status in (PASSED, MERGED, ESCALATED, PARKED, QUOTA) and not st.get("ended_epoch"):
            st["ended_epoch"] = int(time.time())
        # The run reaches COMPLETE exactly when every ticket is DONE — derived
        # here so no one ever hand-edits state.json to finish a run.
        if all(s["status"] == DONE for s in run.state["tickets"].values()):
            run.state["status"] = RUN_COMPLETE
            run.state["halt_reason"] = None
        run.save()
        print(f"{key} → {status}")
    elif cmd == "set-pr":
        if len(rest) < 3:
            die("set-pr <ticket> <number> <url>")
        st = run.ts(rest[0])
        st["pr_number"] = int(rest[1])
        st["pr_url"] = rest[2]
        run.save()
        print(f"{rest[0]}: PR #{rest[1]} recorded")
    elif cmd == "clickup":
        if not rest:
            die("clickup <ticket> [note]")
        try:
            print(clickup_sync(run, rest[0], " ".join(rest[1:]) or None))
        except RuntimeError as e:
            print(f"clickup sync failed (non-blocking): {e}")
    elif cmd == "clickup-stages":
        keys = rest or [k for k, s in run.state["tickets"].items()
                        if s["status"] == DISPATCHED]
        if not keys:
            print("nothing dispatched")
        for k in keys:
            try:
                print(f"{k}: {clickup_stage_ping(run, k)}")
            except RuntimeError as e:
                print(f"{k}: stage ping failed (non-blocking): {e}")
    elif cmd == "harvest-plan":
        if not rest:
            die("harvest-plan <ticket>")
        print(json.dumps(harvest_plan(run, rest[0]), indent=2))
    elif cmd == "harvest-record":
        if len(rest) < 2:
            die("harvest-record <ticket> <entry-id>")
        print(harvest_record(run, rest[0], rest[1]))
    elif cmd == "harvest":
        if not rest:
            die("harvest <ticket>")
        try:
            print(harvest_log(run, rest[0]))
        except RuntimeError as e:
            print(f"harvest log failed (non-blocking): {e}")
    else:
        die(f"unknown command '{cmd}'")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
