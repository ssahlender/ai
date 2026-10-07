#!/usr/bin/env python3
"""Edge-case harness for ai-usage.py — proves each applied review finding.
Run: python3 tools/ai-usage-test.py
Re-runnable; needs no network (all probes are monkeypatched).
"""
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import time
import types

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ai-usage.py")
spec = importlib.util.spec_from_file_location("ai_usage", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

fails = []


def check(name, cond, detail=""):
    print(f"  {'PASS' if cond else 'FAIL'}  {name}" + (f"   [{detail}]" if detail and not cond else ""))
    if not cond:
        fails.append(name)


print("1) parse_iso — both Z forms are UTC (the bug that made countdowns 2h short)")
import calendar
e1 = mod.parse_iso("2026-10-07T19:33:58Z")
e2 = mod.parse_iso("2026-10-06T23:30:11.000Z")
check("3-digit fraction parses", e2 is not None)
check("no-fraction parses", e1 is not None)
check("fraction form is UTC", abs(e2 - calendar.timegm(time.strptime("2026-10-06T23:30:11", "%Y-%m-%dT%H:%M:%S"))) < 0.001, f"got {e2}")
check("no-fraction form is UTC", abs(e1 - calendar.timegm(time.strptime("2026-10-07T19:33:58", "%Y-%m-%dT%H:%M:%S"))) < 0.001, f"got {e1}")
check("garbage -> None", mod.parse_iso("not-a-date") is None and mod.parse_iso("") is None)

print("2) clamp_pct — NaN/inf/out-of-range never reach math or JSON")
for bad in (float("nan"), float("inf"), -1, 150, "abc", None):
    check(f"rejects {bad!r}", mod.clamp_pct(bad) is None)
for good in (0, 100, 50.5):
    check(f"accepts {good}", mod.clamp_pct(good) == float(good))
check("mild overflow clamped to 100", mod.clamp_pct(100.4) == 100.0)

print("3) pace — no judgement where it would be bogus")
now = time.time()
check("rolling window (no origin) -> None",
      mod.pace(6.0, now + 3600, None, now) is None)
check("exhausted window -> None",
      mod.pace(50.0, now - 10, 18000, now) is None)
check("first 15% of window -> None",
      mod.pace(15.0, now + 3590, 3600, now) is None)      # elapsed 10s of 3600s
p = mod.pace(50.0, now + 1800, 3600, now)               # 50% elapsed, 50% used
check("mid-window returns a number", isinstance(p, float), f"got {p!r}")
check("no negative zero", repr(p) != "-0.0", f"got {p!r}")

print("4) row() — expired windows are flagged stale, not presented as current")
r = mod.row("codex (plus)", "5h window", 15.0, resets_at=now - 600, window_s=18000, used=85.0)
check("expired row marked expired", r["expired"] is True)
check("expired row marked stale", r["stale"] is True)
check("expired row carries a note", bool(r["note"]))
check("resets_in_s clamped to 0", r["resets_in_s"] == 0)
r2 = mod.row("x", "w", 90.0, resets_at=now + 600, window_s=3600, used=10.0)
check("live row not stale", r2["stale"] is False and r2["expired"] is False)

print("5) get_opencode — the key can never reach errs/output (codex+agy HIGH, verified exploit)")
good = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
json.dump({"opencode-go": {"type": "api", "key": "sk-goodkey12345"}}, good)
good.close()
bad = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
json.dump({"opencode-go": {"type": "api", "key": "sk-CONTROLCANARY\nxyz"}}, bad)
bad.close()

old_auth, old_urllib = mod.OC_AUTH, mod.urllib
mod.OC_AUTH = bad.name
rows, errs = [], []
mod.get_opencode(rows, errs)
check("control-char key refused", any("control characters" in e for e in errs))
check("control-char key not echoed", not any("CONTROLCANARY" in e for e in errs), str(errs))

# force the exact failure the reviewers warned about: a ValueError echoing the header value
class _BoomReq:
    def __init__(self, *a, **k):
        raise ValueError("Invalid header value b'Bearer sk-LEAKCANARY999\\nabc'")


mod.OC_AUTH = good.name
mod.urllib = types.SimpleNamespace(
    request=types.SimpleNamespace(Request=_BoomReq, urlopen=None),
    error=old_urllib.error,
)
rows, errs = [], []
mod.get_opencode(rows, errs)
check("exception type reported", any("ValueError" in e for e in errs), str(errs))
check("key NOT leaked via exception text", not any("LEAKCANARY999" in e for e in errs), str(errs))
check("no rows fabricated on failure", rows == [])
mod.OC_AUTH, mod.urllib = old_auth, old_urllib

print("6) get_claude — a failed parse must not be masked by the word 'week' in an error line")
old_cached = mod.cached
mod.cached = lambda name, ttl, fn: (
    "Claude usage is temporarily unavailable this week, try later\n", time.time(), False)
rows, errs = [], []
mod.get_claude(rows, errs, 0)
check("no rows parsed", rows == [])
check("parse failure reported (old code stayed silent)", any("could not parse" in e for e in errs), str(errs))

mod.cached = lambda name, ttl, fn: (
    "You are currently using your subscription\nCurrent session: 86% used \u00b7 resets Oct 7, 2:40am (Europe/Zurich)\n"
    "Current week (all models): 26% used \u00b7 resets Oct 12, 4pm (Europe/Zurich)\n",
    time.time(), False)
rows, errs = [], []
mod.get_claude(rows, errs, 0)
check("session row parsed", len(rows) == 2, str(rows))
check("used->remaining inverted", rows and rows[0]["remaining_pct"] == 14.0, str(rows[:1]))
check("no spurious error", errs == [], str(errs))

print("7) _agy_tsv (JSON fallback) — label variants tolerated, NaN skipped")
rows, errs = [], []
mod._agy_tsv(rows, errs,
             "Gemini Models\t5-Hour Limit Remaining\t78%\t2026-10-06T23:10:24Z\n"
             "Gemini Models\tWeekly Limit Remaining\tNaN%\t2026-10-07T19:33:58Z\n"
             "Gemini Models\tDaily Limit Remaining\t40%\t2026-10-07T00:00:00Z\n")
check("'5-Hour' variant -> 5h window", any(r["window"] == "5h" for r in rows), str(rows))
check("NaN percentage skipped", not any(r["remaining_pct"] is not None and r["remaining_pct"] != r["remaining_pct"] for r in rows))
check("unknown label still reported", any(r["window"] not in ("5h", "weekly") for r in rows), str(rows))
mod.cached = old_cached        # sections 10+ exercise the REAL cache: do not leave the stub in place

print("8) run() — a failed probe raises instead of being cached as 'usage'")
class _P:
    returncode, stdout, stderr = 1, "", "boom"


old_sp = mod.subprocess.run
mod.subprocess.run = lambda *a, **k: _P()
try:
    mod.run(["claude", "-p", "/usage"])
    check("failed probe raises", False, "no exception")
except RuntimeError:
    check("failed probe raises", True)
mod.subprocess.run = old_sp

print("9) JSON output is standard JSON even with a stale/expired row")
payload = json.dumps({"rows": [r], "errors": []})
check("json round-trips", json.loads(payload)["rows"][0]["stale"] is True)
check("no bare NaN token in json", "NaN" not in json.dumps({"rows": mod.row("x", "w", float("nan"))}))

print("10) delta-pass: untrusted reason text, atomic cache, unit ambiguity, boundaries")
import io
import urllib.error as _ue

# 10a — a server-controlled HTTP reason must not reach errs (it is untrusted text)
class _BoomOpen:
    def __enter__(self):
        raise _ue.HTTPError("https://x", 403, "CANARY-REASON-9", {}, None)

    def __exit__(self, *a):
        return False


mod.OC_AUTH = good.name
mod.urllib = types.SimpleNamespace(
    request=types.SimpleNamespace(
        Request=lambda *a, **k: object(),
        build_opener=lambda *a, **k: types.SimpleNamespace(open=lambda *a, **k: _BoomOpen()),
        HTTPRedirectHandler=object),
    error=_ue)
rows, errs = [], []
mod.get_opencode(rows, errs)
check("HTTP status code reported", any("HTTP 403" in e for e in errs), str(errs))
check("server reason text NOT echoed", not any("CANARY-REASON-9" in e for e in errs), str(errs))
mod.OC_AUTH, mod.urllib = old_auth, old_urllib

# 10b — a future-dated cache is not trusted; corrupt cache falls through; write is atomic
cdir = tempfile.mkdtemp(prefix="ai-usage-cachetest-")
os.makedirs(cdir, exist_ok=True)
for stale_name in ("futuretest.json", "corrupt.json"):
    try:
        os.remove(os.path.join(cdir, stale_name))
    except OSError:
        pass
orig_cache_dir = mod.CACHE_DIR
mod.CACHE_DIR = cdir
json.dump({"t": time.time() + 3600, "v": "CACHED-FUTURE"},
          open(os.path.join(cdir, "futuretest.json"), "w"))
calls = []
v, _, hit = mod.cached("futuretest", 120, lambda: (calls.append(1), "FRESH")[1])
check("future-dated cache refused", hit is False and v == "FRESH", f"{v} hit={hit}")
check("probe re-run instead", calls == [1])
check("no .tmp left behind", not os.path.exists(os.path.join(cdir, "futuretest.json.tmp")))
open(os.path.join(cdir, "corrupt.json"), "w").write("{not json")
calls2 = []
v2, _, hit2 = mod.cached("corrupt", 120, lambda: (calls2.append(1), "FRESH2")[1])
check("corrupt cache -> fresh probe", hit2 is False and v2 == "FRESH2")
mod.CACHE_DIR = orig_cache_dir
shutil.rmtree(cdir, ignore_errors=True)

# 10c — the 15% pace boundary in both directions, and the timeout actually wired in
t0 = time.time()
check("timeout constant is 60s", mod.CMD_TIMEOUT == 60, str(mod.CMD_TIMEOUT))
check("exactly 15% elapsed -> pace allowed", mod.pace(50.0, t0 + 3060, 3600, t0) is not None)
check("14% elapsed -> pace suppressed", mod.pace(50.0, t0 + 3096, 3600, t0) is None)


# 10d — a sub-1 percent is ambiguous (0.5% vs 50%); flagged, not shown silently
class _Ok:
    def __init__(self, payload):
        self.b = io.BytesIO(json.dumps(payload).encode())

    def __enter__(self):
        return self.b

    def __exit__(self, *a):
        return False


mod.OC_AUTH = good.name
mod.urllib = types.SimpleNamespace(
    request=types.SimpleNamespace(
        Request=lambda *a, **k: object(),
        build_opener=lambda *a, **k: types.SimpleNamespace(
            open=lambda *a, **k: _Ok({"usage": {"weekly": {"percent": 0.5,
                                                           "resetsAt": "2026-10-12T00:00:00.000Z"}}})),
        HTTPRedirectHandler=object),
    error=_ue)
rows, errs = [], []
mod.get_opencode(rows, errs)
check("sub-1 percent flagged", any("below 1" in e for e in errs), str(errs))
check("row kept with an explanatory note",
      bool(rows) and "percent/fraction" in (rows[0]["note"] or ""), str(rows))
mod.OC_AUTH, mod.urllib = old_auth, old_urllib

print("11) final-pass: claude cache note visible in the table, cache tmp is pid-qualified")
import contextlib
import io as _io

# 11a — a claude row's note (its cache age) must actually appear in the human table
claude_row = mod.row("claude (pro)", "session", 10.0, reset_raw="Oct 7, 2:39am", used=90.0,
                     note="cached 3m")
buf = _io.StringIO()
with contextlib.redirect_stdout(buf):
    mod.render([claude_row], [], use_color=False)
table = buf.getvalue()
check("claude row rendered", "claude (pro)" in table.lower(), table)
check("claude note visible in the table", "cached 3m" in table, table)

# 11b — concurrent runs probing the same name must not share a tmp path
seen = []
real_replace = os.replace
mod.os.replace = lambda s, d: (seen.append(s), real_replace(s, d))[1]
try:
    mod.CACHE_DIR = cdir
    os.makedirs(cdir, exist_ok=True)   # section 10b removed it after its own checks
    mod.cached("tmpname", 0, lambda: "V")
finally:
    mod.os.replace = real_replace
    mod.CACHE_DIR = orig_cache_dir
check("tmp path carries the pid", bool(seen) and f".{os.getpid()}." in seen[0], str(seen))
check("no .tmp left after write", not any(".tmp" in n for n in os.listdir(cdir)), str(os.listdir(cdir)))

print("12) review-3 (MiMo) fixes: parse_iso variants, non-finite reset, pace policy, exit codes, drift")

# 12a — parse_iso accepts the variants strptime rejected
check("'+00:00' offset parses", mod.parse_iso("2026-10-06T23:30:11+00:00") is not None)
check("lowercase 'z' parses", mod.parse_iso("2026-10-06T23:30:11z") is not None)
check("nanosecond fraction parses", mod.parse_iso("2026-10-06T23:30:11.123456789Z") is not None)
check("garbage still -> None", mod.parse_iso("not-a-date") is None)
check("reset_from: empty -> (None, False)", mod.reset_from("") == (None, False))
check("reset_from: unparseable -> flagged", mod.reset_from("soon") == (None, True))

# 12b — non-finite resets_at must not blow up iso()/fromtimestamp()
r = mod.row("x", "w", 50.0, resets_at=float("nan"), window_s=3600, used=50.0)
check("NaN resets_at neutralised", r["resets_at"] is None and r["resets_in_s"] is None)

# 12c — agy native print-mode quota JSON (1.1.11+), then opencode-go pace policy
import json
mod.agy_version = lambda: (1, 3, 1)
agy_doc = {"status": "SUCCESS", "usage": {"total_tokens": 0},
           "command": {"name": "usage", "data": {"groups": [
               {"name": "Gemini Models", "buckets": [
                   {"id": "gemini-weekly", "window": "weekly",
                    "remaining_fraction": 0.5255396962165833,
                    "reset_time": "2026-10-07T19:33:58Z"},
                   {"id": "gemini-5h", "window": "5h", "remaining_fraction": 1,
                    "reset_time": "2026-10-07T12:03:39Z"}]},
               {"name": "Claude and GPT models", "buckets": [
                   {"id": "3p-5h", "window": "5h", "remaining_fraction": None}]}]}}}
mod.cached = lambda name, ttl, fn: (json.dumps(agy_doc), time.time(), False)
rows, errs = [], []
mod.get_agy(rows, errs, 0)
byk = {(x["provider"], x["window"]): x for x in rows}
check("agy JSON: 3 buckets parsed", len(rows) == 3, str(errs))
check("agy JSON: fraction parsed at full precision",
      abs(mod.clamp_pct(0.5255396962165833 * 100.0) - 52.55396962165833) < 1e-6)
check("agy JSON: row carries the value at its 1dp contract",
      byk[("agy (Gemini Models)", "weekly")]["remaining_pct"] == 52.6,
      str(byk.get(("agy (Gemini Models)", "weekly"))))
check("agy JSON: idle 5h reads 100%", byk[("agy (Gemini Models)", "5h")]["remaining_pct"] == 100.0)
check("agy JSON: no pace (no published origin)", all(x["pace"] is None for x in rows), str(rows))
check("agy JSON: null fraction -> unknown note, row kept",
      byk[("agy (Claude and GPT models)", "5h")]["remaining_pct"] is None
      and "unknown" in (byk[("agy (Claude and GPT models)", "5h")]["note"] or ""),
      str(byk.get(("agy (Claude and GPT models)", "5h"))))
check("agy JSON: clean doc yields no errors", errs == [], str(errs))

mod.agy_version = lambda: (1, 1, 10)
mod.cached = lambda name, ttl, fn: ("should not be reached", time.time(), False)
rows, errs = [], []
mod.get_agy(rows, errs, 0)
check("agy <1.1.11: refuses to probe, explains why",
      not rows and any("predates" in e for e in errs), str(errs))

mod.agy_version = lambda: (1, 3, 1)
cost_doc = json.loads(json.dumps(agy_doc))
cost_doc["usage"]["total_tokens"] = 120
mod.cached = lambda name, ttl, fn: (json.dumps(cost_doc), time.time(), False)
rows, errs = [], []
mod.get_agy(rows, errs, 0)
check("agy: unexpected token spend flagged", any("cost 120 tokens" in e for e in errs), str(errs))

mod.cached = lambda name, ttl, fn: (json.dumps(
    {"status": "SUCCESS", "response":
     "Gemini Models\tWeekly Limit Remaining\t53%\t2026-10-07T19:33:58Z\n"}), time.time(), False)
rows, errs = [], []
mod.get_agy(rows, errs, 0)
check("agy: TSV fallback from the same JSON still works", len(rows) == 1, str(errs))

monthly = {"usage": {"weekly": {"percent": 30, "resetsAt": "2026-10-12T00:00:00.000Z"},
                     "monthly": {"percent": 10, "resetsAt": "2026-10-26T16:04:22.000Z"}}}
_ue2 = _ue
mod.urllib = types.SimpleNamespace(
    request=types.SimpleNamespace(
        Request=lambda *a, **k: object(),
        build_opener=lambda *a, **k: types.SimpleNamespace(open=lambda *a, **k: _Ok(monthly)),
        HTTPRedirectHandler=object),
    error=_ue2)
rows, errs = [], []
mod.get_opencode(rows, errs)
by = {x["window"]: x for x in rows}
check("monthly pace suppressed", by["monthly"]["pace"] is None, str(by.get("monthly")))
check("weekly pace still computed", by["weekly"]["pace"] is not None, str(by.get("weekly")))
mod.urllib = old_urllib
mod.cached = old_cached

# 12d — exit codes: a failed source must be distinguishable from a clean run
old_argv, old_sessions = sys.argv, mod.SESSIONS
with contextlib.redirect_stdout(_io.StringIO()):
    try:
        mod.SESSIONS = "/nonexistent-codex-dir"
        sys.argv = ["ai-usage", "--only", "codex"]
        rc_fail = mod.main()
        sys.argv = ["ai-usage", "--only", "zzz"]
        rc_none = mod.main()
    finally:
        sys.argv, mod.SESSIONS = old_argv, old_sessions
check("no rows -> exit 1 (nothing collected)", rc_fail == 1, str(rc_fail))
check("nothing collected -> exit 1", rc_none == 1, str(rc_none))
check("brief surfaces an error count", mod.brief([claude_row], 2).endswith("· !2"),
      mod.brief([claude_row], 2))

# a degraded run (some rows, some errors) must be distinguishable from a clean one
old_cg, old_go = mod.get_codex, mod.get_opencode
mod.get_codex = lambda r, e: e.append("codex: simulated failure")
mod.get_opencode = lambda r, e: r.append(mod.row("opencode-go (hermes)", "weekly", 50.0))
with contextlib.redirect_stdout(_io.StringIO()):
    sys.argv = ["ai-usage", "--only", "codex,opencode"]
    rc_partial = mod.main()
sys.argv = old_argv
mod.get_codex, mod.get_opencode = old_cg, old_go
check("partial (rows + errors) -> exit 2", rc_partial == 2, str(rc_partial))

# 12e — format drift is reported rather than silently dropping a lane
mod.cached = lambda name, ttl, fn: (
    "Current session: 86% used \u00b7 resets Oct 7, 2:40am (Europe/Zurich)\n"
    "Current week (all models): something unexpected\n",
    time.time(), False)
rows, errs = [], []
mod.get_claude(rows, errs, 0)
check("session parses without the resets tail", len(rows) >= 1, str(rows))
check("unconsumed header reported", any("did not parse" in e for e in errs), str(errs))
mod.cached = old_cached

print()
print(f"RESULT: {len(fails)} failure(s)" + ("" if not fails else f" -> {fails}"))
sys.exit(1 if fails else 0)
