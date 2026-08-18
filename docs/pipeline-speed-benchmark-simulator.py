#!/usr/bin/env python3
"""v0.21 vs v0.22 pipeline wall-clock model.

Machine-step numbers marked MEASURED come from the micro-benchmarks
(2026-08-18, this branch); agent durations are ASSUMED mid-range values for
a medium repo — the release's own Track A stats section is what will
replace them with field truth. Human waits are reported as round-trip
counts, priced separately.
"""

# --- Parameters -------------------------------------------------------------
# Agent spawn durations (seconds) — ASSUMED
CODER_FEAT = 480; CODER_FIX_LANE = 300; CODER_FIXROUND = 240
REV_FULL = 300; REV_DELTA = 150
SEC_FULL = 240; SEC_NOOP = 60; SEC_DELTA = 90
TESTCODER = 360; TESTCODER_FIX = 300
TESTREV = 180; TESTREV_FIX = 150
CONTRACT = 120          # abuse-test phase spawn (sensitive changes only)
RECONCILE = 180         # restore+reconcile(+contract) spawn after a FAIL round

# Machine steps (seconds) — grounded in MEASURED ratios, project scale:
# build 45, lint 20, tests 120, dependency audit 10 (typical; 45 cap)
BL_SERIAL = 65          # MEASURED shape: 9.05s at 6+3 scale -> sum
BL_CONC = 45            # MEASURED shape: 6.04s at 6+3 scale -> max
HOOK_V21 = 45+20+120+10           # serial gates + audit every push
HOOK_V22_DEF = 45+20+120+0.2      # serial gates + warm audit cache (MEASURED 0.2s)
HOOK_V22_PAR = 120+0.2            # opted-in: max(gates) + warm cache (MEASURED shape)
VERIFY_FIX = 40         # Base-Ref scoped regression verification (fix lane)
BASH_STEP = 4           # drift parse / step-1 handoff bash
QUARANTINE = 2

# Orchestrator round-trip latency (seconds/turn) — ASSUMED
TURN = 8
CI_SECONDS = 480; POLL = 45
CI_OVERHEAD_V21 = (CI_SECONDS // POLL + 1) * TURN   # ~11 poll turns
CI_OVERHEAD_V22 = 1 * TURN                          # one blocking watch
STAGE7_BATCH_SAVING = 4 * TURN                      # fix lane: 5 invocations -> 1

def v21(coder, rev, sec, test, testrev, rounds_extra=0, fix_lane=False):
    t = coder + BL_SERIAL + max(rev, sec) + BASH_STEP
    for _ in range(rounds_extra):
        t += CODER_FIXROUND + BL_SERIAL + max(REV_DELTA, SEC_DELTA) + BASH_STEP
    t += test + (VERIFY_FIX if fix_lane else 0) + testrev
    return t

def v22(coder, rev, sec, test, testrev, rounds_extra=0, fix_lane=False, sensitive=False):
    t = coder + BL_CONC + max(rev, sec, test) + BASH_STEP   # 3-agent round 1
    if rounds_extra:
        t += QUARANTINE
        for _ in range(rounds_extra):
            t += CODER_FIXROUND + BL_CONC + max(REV_DELTA, SEC_DELTA) + BASH_STEP
        t += RECONCILE                                       # restore+reconcile(+contract)
    elif sensitive:
        t += CONTRACT
    t += (VERIFY_FIX if fix_lane else 0) + testrev
    if fix_lane:
        t -= STAGE7_BATCH_SAVING * 0  # counted in the push column instead
    return t

rows = []
def add(name, a, b, hook_a, hook_b, ci_a=CI_OVERHEAD_V21, ci_b=CI_OVERHEAD_V22):
    ta, tb = a + hook_a + ci_a, b + hook_b + ci_b
    rows.append((name, ta, tb, ta - tb, 100 * (ta - tb) / ta))

# S1 feat, 1-round clean, non-sensitive (security self-noops)
add("S1 feat 1-round, non-sensitive",
    v21(CODER_FEAT, REV_FULL, SEC_NOOP, TESTCODER, TESTREV),
    v22(CODER_FEAT, REV_FULL, SEC_NOOP, TESTCODER, TESTREV),
    HOOK_V21, HOOK_V22_DEF)
# S2 feat, 1-round, sensitive (contract phase fires)
add("S2 feat 1-round, sensitive",
    v21(CODER_FEAT, REV_FULL, SEC_FULL, TESTCODER, TESTREV),
    v22(CODER_FEAT, REV_FULL, SEC_FULL, TESTCODER, TESTREV, sensitive=True),
    HOOK_V21, HOOK_V22_DEF)
# S3 feat, 2 rounds (reviewer P0 on round 1)
add("S3 feat 2-round, sensitive",
    v21(CODER_FEAT, REV_FULL, SEC_FULL, TESTCODER, TESTREV, rounds_extra=1),
    v22(CODER_FEAT, REV_FULL, SEC_FULL, TESTCODER, TESTREV, rounds_extra=1),
    HOOK_V21, HOOK_V22_DEF)
# S4 fix lane, 1-round, non-sensitive (no CI stage in fix lane; Stage 7 batching)
add("S4 fix 1-round, non-sensitive",
    v21(CODER_FIX_LANE, 240, SEC_NOOP, TESTCODER_FIX, TESTREV_FIX, fix_lane=True),
    v22(CODER_FIX_LANE, 240, SEC_NOOP, TESTCODER_FIX, TESTREV_FIX, fix_lane=True)
      - STAGE7_BATCH_SAVING,
    HOOK_V21, HOOK_V22_DEF, ci_a=0, ci_b=0)
# S5 = S1 with the opt-in parallel hook
add("S5 = S1 + hook-parallel-gates",
    v21(CODER_FEAT, REV_FULL, SEC_NOOP, TESTCODER, TESTREV),
    v22(CODER_FEAT, REV_FULL, SEC_NOOP, TESTCODER, TESTREV),
    HOOK_V21, HOOK_V22_PAR)

print("| Scenario | v0.21 (min) | v0.22 (min) | saved (min) | saved % |")
print("|---|---|---|---|---|")
for n, a, b, d, p in rows:
    print(f"| {n} | {a/60:.1f} | {b/60:.1f} | {d/60:.1f} | {p:.0f}% |")

print()
print("Human round-trips removed (priced separately; H = human response time):")
print("- pre-flight fold: -1 trip on every run carrying non-critical signals")
print("- deploy pre-auth: -1 trip at the post-CI stall (deploy-configured repos;")
print("  this is the trip where the human has typically walked away)")
print(f"- CI poll turns folded into machine numbers above: {CI_OVERHEAD_V21-CI_OVERHEAD_V22:.0f}s per CI'd run")
