#!/usr/bin/env python3
"""ai-usage — remaining quota across AI agent subscriptions.

Sources (all read-only; none cost money, but every lane is METERED QUOTA):
  codex        ~/.codex/sessions/**/rollout-*.jsonl  -> last token_count.rate_limits
  claude       `claude -p "/usage"`                  (subscription windows, 0 tokens)
  agy          `agy   -p "/usage"`                   (Antigravity quota TSV)
  opencode-go  GET https://opencode.ai/zen/go/v1/usage  (Hermes backend; needs UA header)

No money is billed here, but "free of charge" is NOT "unlimited". In particular `agy` is not free
capacity: the Google AI Pro plan behind it meters the Gemini pool and the Claude/GPT pool
separately, both are shared with other clients, and exhausting a pool locks it out for the rest of
the week. Antigravity shows the authoritative remaining figures in the GUI's `/usage` (the same
command this script reads headlessly). Never treat an agent lane's headroom as free capacity.

Usage:
  ai-usage                 human table (colored)
  ai-usage --json          machine output
  ai-usage --brief         one-line summary (statusline / cron)
  ai-usage --only codex,claude
  ai-usage --ttl 300       cache seconds for claude/agy subprocess probes (default 120, 0=off)

A row carries "stale": true when its number is last-known rather than current — the window's
reset time has already passed (the source has not refreshed since), or the codex rollout is
older than 15 min. Stale rows are marked, never silently presented as current.

Security: the opencode-go key is read from auth.json and used only in a request header. It must
never reach errs/output, so that request never interpolates raw exception text (a header
ValueError echoes the offending value, i.e. the key) and a key with control characters is refused.
"""
import argparse
import glob
import json
import math
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

SESSIONS = os.path.expanduser("~/.codex/sessions")
CACHE_DIR = os.path.expanduser("~/.cache/ai-usage")
OC_AUTH = os.path.expanduser("~/.local/share/opencode/auth.json")
OC_USAGE_URL = "https://opencode.ai/zen/go/v1/usage"
UA = "curl/8.5.0"          # Cloudflare 1010-blocks bare/unknown agents on this endpoint
CMD_TIMEOUT = 60           # claude/agy spawn a whole CLI; measured ~7 s cold, 60 s is headroom
STALE_S = 900              # codex rollout older than this = last-known, not current

HOUR = 3600
DAY = 86400

# --------------------------------------------------------------------------- util
def human_delta(sec):
    sec = int(max(0, sec))
    d, rem = divmod(sec, DAY)
    h, rem = divmod(rem, HOUR)
    m = rem // 60
    if d:
        return f"{d}d{h}h"
    if h:
        return f"{h}h{m:02d}m"
    return f"{m}m"


def clamp_pct(v):
    """Finite percentage in [0,100], else None. Keeps NaN/inf out of the math and out of JSON
    (json.dumps emits a bare NaN, which is not valid JSON)."""
    try:
        f = float(v)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(f) or f < 0:
        return None
    if f > 100:
        return 100.0 if f <= 101 else None   # tolerate rounding noise, reject a unit change
    return f


def bar(remaining, width=20):
    fill = max(0, min(width, int(round(remaining / 100.0 * width))))
    return "█" * fill + "░" * (width - fill)


def parse_iso(s):
    """Parse an ISO8601 UTC timestamp -> epoch. Accepts "...Z", lowercase "z", "+00:00" and any
    fraction length (strptime accepted only Z with <=6 digits, silently returning None otherwise —
    which disabled the expired/stale logic for that row)."""
    if not s:
        return None
    s = s.strip()
    if s[-1] in ("Z", "z"):
        s = s[:-1] + "+00:00"        # normalise the UTC designator for fromisoformat
    try:
        dt = datetime.fromisoformat(s)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.timestamp()


def reset_from(raw):
    """(epoch, unparseable) for a raw reset string. A non-empty string that will not parse must be
    reported, not silently treated as 'no reset' (an already-reset window would look current)."""
    if not raw:
        return None, False
    ep = parse_iso(raw)
    return ep, ep is None


def iso(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def pace(used, resets_at, window_s, now):
    """Linear-pace delta: positive = burning faster than the clock.

    None (no judgement) when there is no fixed window origin (a rolling window decays
    continuously and has none), when the window is exhausted, or in the first 15% of the
    window where a couple of points of legitimate use would false-trigger the flag."""
    if used is None or not resets_at or not window_s or now >= resets_at:
        return None
    start = resets_at - window_s
    elapsed = now - start
    if elapsed <= 0 or elapsed / window_s < 0.15:
        return None
    expected = min(100.0, elapsed / window_s * 100.0)
    d = round(used - expected, 1)
    return 0.0 if d == 0 else d          # avoid -0.0 in JSON


def row(provider, window, remaining, resets_at=None, window_s=None,
        note=None, reset_raw=None, used=None, stale=False):
    rem = clamp_pct(remaining) if remaining is not None else None
    u = used if used is not None else (None if rem is None else 100.0 - rem)
    u = clamp_pct(u) if u is not None else None
    if not (isinstance(resets_at, (int, float)) and math.isfinite(resets_at)):
        resets_at = None     # json.loads accepts NaN/Infinity; iso()/fromtimestamp() would raise
    expired = bool(resets_at and resets_at < time.time())
    if expired:
        # the window already reset: the on-disk number is last-known, not current
        note = note or "window already reset — last known value"
    return {
        "provider": provider,
        "window": window,
        "remaining_pct": None if rem is None else round(rem, 1),
        "used_pct": None if u is None else round(u, 1),
        "resets_at": iso(resets_at) if resets_at else reset_raw,
        "resets_in_s": int(max(0, resets_at - time.time())) if resets_at else None,
        "expired": expired,
        "stale": bool(stale or expired),
        "note": note,
        "pace": pace(u, resets_at, window_s, time.time()) if u is not None else None,
    }


def cached(name, ttl, fn):
    """Cache a probe's RAW output. A future timestamp is refused (clock skew would otherwise
    pin a value forever) and an empty/failed probe is never cached."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    f = os.path.join(CACHE_DIR, name + ".json")
    now = time.time()
    if ttl:
        try:
            d = json.load(open(f))
            age = now - d["t"]
            if 0 <= age < ttl and (d.get("v") or "").strip():
                return d["v"], d["t"], True
        except Exception:
            pass
    v = fn()
    if not (v or "").strip():
        raise RuntimeError("empty probe output")
    try:
        # pid-qualified: two concurrent runs probing the same name must not share a tmp path
        tmp = f"{f}.{os.getpid()}.tmp"
        with open(tmp, "w") as fh:
            json.dump({"t": time.time(), "v": v}, fh)
        os.replace(tmp, f)          # atomic: a concurrent reader never sees a truncated file
    except Exception:
        pass
    return v, time.time(), False


def run(cmd, timeout=CMD_TIMEOUT):
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    out, err = (p.stdout or ""), (p.stderr or "")
    if p.returncode != 0 and not out.strip():
        raise RuntimeError(f"{cmd[0]} exited {p.returncode}")
    # prefer stdout: a CLI echoing its usage block on both streams would otherwise double-parse
    return out if out.strip() else err


# --------------------------------------------------------------------------- codex
def get_codex(rows, errs):
    files = glob.glob(os.path.join(SESSIONS, "*", "*", "*", "rollout-*.jsonl"))
    if not files:
        errs.append("codex: no rollout files")
        return
    files.sort(key=os.path.getmtime, reverse=True)
    rl = None
    src = None
    # newest first, but fall back: a just-started session has no token_count event yet
    for cand in files[:3]:
        size = os.path.getsize(cand)
        with open(cand, "rb") as fh:
            fh.seek(max(0, size - 400_000))
            data = fh.read().decode("utf-8", "replace")
        lines = data.splitlines()
        if size > 400_000 and lines:
            lines = lines[1:]        # drop the line cut by the seek boundary
        found = None
        for line in lines:
            if '"rate_limits"' in line and '"token_count"' in line:
                try:
                    cand_rl = json.loads(line)["payload"]["rate_limits"]
                except Exception:
                    continue
                if cand_rl.get("primary") or cand_rl.get("secondary"):
                    found = cand_rl
        if found:
            rl, src = found, cand
            break
    if not rl:
        errs.append("codex: no rate_limits in the 3 newest rollouts")
        return
    file_stale = (time.time() - os.path.getmtime(src)) > STALE_S
    plan = rl.get("plan_type")
    prov = "codex" + (f" ({plan})" if plan else "")
    note = "last known — run codex to refresh" if file_stale else None
    parsed = 0
    for key in ("primary", "secondary"):
        w = rl.get(key) or {}
        pct = clamp_pct(w.get("used_percent"))
        if pct is None:
            continue
        mins = w.get("window_minutes")
        if mins:
            win = f"{mins // 60}h window" if mins < 1440 else f"{mins // 1440}d window"
        else:
            win = key
        rows.append(row(prov, win, 100.0 - pct, w.get("resets_at"),
                        (mins * 60) if mins else None, note, used=pct, stale=file_stale))
        parsed += 1
    if not parsed:      # rate_limits present but the window fields were renamed: say so
        errs.append("codex: rate_limits found but no window parsed")
    cr = rl.get("credits") or {}
    if cr.get("has_credits"):
        rows.append(row(prov, "credits", None, note=f"balance {cr.get('balance')}"))


# --------------------------------------------------------------------------- claude
RE_SESS = re.compile(r"Current session:\s*(\d+(?:\.\d+)?)%\s*used\b(?:\s*·\s*resets?\s*(.+))?",
                     re.IGNORECASE)
RE_WEEK = re.compile(r"Current week(?:\s*\(([^)]+)\))?:\s*(\d+(?:\.\d+)?)%\s*used\b"
                     r"(?:\s*·\s*resets?\s*(.+))?", re.IGNORECASE)


def get_claude(rows, errs, ttl):
    try:
        text, ts, hit = cached("claude", ttl, lambda: run(["claude", "-p", "/usage"]))
    except Exception as e:
        errs.append(f"claude: probe failed ({type(e).__name__})")
        return
    start = len(rows)
    m = RE_SESS.search(text)
    if m:
        pct = clamp_pct(m.group(1))
        if pct is not None:
            rows.append(row("claude (pro)", "session", 100 - pct,
                            reset_raw=(m.group(2) or "").strip() or None, used=pct))
    for mm in RE_WEEK.finditer(text):
        pct = clamp_pct(mm.group(2))
        if pct is None:
            continue
        label = mm.group(1) or "all models"
        rows.append(row("claude (pro)", f"week ({label})", 100 - pct,
                        reset_raw=(mm.group(3) or "").strip() or None, used=pct))
    # a header the regexes did not consume is format drift: report it, do not drop the lane quietly
    headers = len(re.findall(r"Current (?:session|week)", text, re.I))
    if len(rows) - start < headers:
        errs.append(f"claude: {headers - (len(rows) - start)} usage line(s) did not parse")
    if len(rows) == start:
        errs.append("claude: could not parse /usage output")
    if hit:
        age = time.time() - ts
        if age >= 60:
            for r in rows[start:]:
                if not r["note"]:
                    r["note"] = f"cached {human_delta(age)}"
                if ttl and age >= ttl:
                    r["stale"] = True    # claude reset is free text: cache age is the only signal


# --------------------------------------------------------------------------- agy
AGY_MIN_JSON = (1, 1, 11)   # 1.1.11+ exposes native print-mode quota JSON. On older builds the
                            # same command may be taken as a PROMPT and burn quota, so refuse it.


def agy_version():
    """(major, minor, patch) of the installed agy, or None if it cannot be read."""
    try:
        out = run(["agy", "--version"], timeout=30)
    except Exception:
        return None
    for tok in out.split():
        m = re.match(r"^(\d+)\.(\d+)\.(\d+)", tok)
        if m:
            return tuple(int(x) for x in m.groups())
    return None


def _agy_tsv(rows, errs, text):
    """Fallback: the TSV string carried inside the same /usage JSON (pre-1.1.11 shape)."""
    start = len(rows)
    for line in text.splitlines():
        parts = line.split("\t")
        if len(parts) < 4 or "limit remaining" not in parts[1].lower():
            continue
        pct = clamp_pct(parts[2].strip().rstrip("%"))
        if pct is None:
            continue
        wl = parts[1].lower()
        short = ("5h" if re.match(r"^(five|5)[- ]?hour", wl)
                 else "weekly" if ("week" in wl or re.match(r"^7[- ]?day", wl))
                 else parts[1].replace(" Limit Remaining", "")[:18])
        ep, bad = reset_from(parts[3].strip())
        rows.append(row(f"agy ({parts[0]})", short, pct, ep, None,
                        "unparseable reset time — staleness unknown" if bad else None, stale=bad))
    if len(rows) == start:
        errs.append("agy: no JSON groups and no parseable TSV")


def get_agy(rows, errs, ttl):
    ver = agy_version()
    if ver and ver < AGY_MIN_JSON:
        errs.append("agy: %d.%d.%d predates native quota JSON (needs 1.1.11+); not probing "
                    "/usage — older builds can treat it as a prompt and spend quota" % ver)
        return
    start = len(rows)
    try:
        raw, ts, hit = cached("agy-usage-json", ttl,
                              lambda: run(["agy", "-p", "/usage", "--output-format", "json"]))
    except Exception as e:
        errs.append(f"agy: probe failed ({type(e).__name__})")
        return
    try:
        doc = json.loads(raw)
    except ValueError:
        errs.append("agy: /usage did not return JSON — is agy >= 1.1.11?")
        return
    if doc.get("status") not in (None, "SUCCESS"):
        errs.append(f"agy: /usage status={doc.get('status')}")
    spent = ((doc.get("usage") or {}).get("total_tokens")) or 0
    if spent:
        # this path is supposed to be free (num_turns: 0); spending tokens means a CLI regression
        errs.append(f"agy: /usage cost {spent} tokens — expected 0")
    groups = ((doc.get("command") or {}).get("data") or {}).get("groups") or []
    if not groups:
        _agy_tsv(rows, errs, doc.get("response") or "")
    else:
        for g in groups:
            gname = (g.get("name") or "?").strip()
            for b in (g.get("buckets") or []):
                win = (b.get("window") or "").strip()
                short = {"5h": "5h", "weekly": "weekly"}.get(
                    win, win or (b.get("name") or "?").strip()[:18])
                frac = b.get("remaining_fraction")
                if isinstance(frac, (int, float)) and math.isfinite(frac):
                    rem, note = clamp_pct(frac * 100.0), None
                else:
                    rem, note = None, "remaining unknown (backend reported no fraction)"
                ep, bad = reset_from(b.get("reset_time") or "")
                if bad:
                    note = "unparseable reset time — staleness unknown"
                # agy publishes no window origin (an idle bucket reports reset ~= now + window),
                # so any linear pace off reset_time is noise: window_s stays None.
                rows.append(row(f"agy ({gname})", short, rem, ep, None, note, stale=bad))
    if len(rows) == start:
        errs.append("agy: no quota buckets in /usage JSON")
    if hit:
        age = time.time() - ts
        if age >= 60:
            for r in rows[start:]:
                if not r["note"]:
                    r["note"] = f"cached {human_delta(age)}"
                if ttl and age >= ttl:
                    r["stale"] = True


# --------------------------------------------------------------------------- opencode-go
class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Refuse redirects: urllib re-sends the Authorization header to the target host."""

    def redirect_request(self, *args, **kwargs):
        return None


def get_opencode(rows, errs):
    try:
        key = json.load(open(OC_AUTH))["opencode-go"]["key"]
    except Exception as e:
        errs.append(f"opencode-go: no readable key in auth.json ({type(e).__name__})")
        return
    if not isinstance(key, str) or not key.strip() or any(ord(c) < 32 for c in key.strip()):
        errs.append("opencode-go: key is empty or contains control characters")
        return
    key = key.strip()
    try:
        req = urllib.request.Request(OC_USAGE_URL,
                                     headers={"Authorization": "Bearer " + key,
                                              "User-Agent": UA})
        # follow no redirects: urllib re-sends the Authorization header to the redirect target
        with urllib.request.build_opener(_NoRedirect).open(req, timeout=20) as r:
            data = json.load(r)
    except urllib.error.HTTPError as e:
        # status code only: the reason phrase is server-controlled, i.e. untrusted text
        errs.append(f"opencode-go: HTTP {e.code}")
        return
    except urllib.error.URLError:
        errs.append("opencode-go: network error")
        return
    except Exception as e:
        # deliberate: NEVER interpolate the exception text here — a header ValueError
        # echoes the offending value, i.e. the API key, into errs and on to stdout/JSON.
        errs.append(f"opencode-go: request failed ({type(e).__name__})")
        return
    # rolling is a sliding window and the monthly reset is not a month boundary: neither has a
    # fixed origin, so no linear pace for them (only the weekly boundary is anchored).
    wins = [("rolling", "5h rolling", None),
            ("weekly", "weekly", 7 * DAY),
            ("monthly", "monthly", None)]
    u = data.get("usage", {})
    n = 0
    for k, label, wsec in wins:
        w = u.get(k) or {}
        pct = clamp_pct(w.get("percent"))
        if pct is None:
            continue
        note = None
        if 0 < pct < 1:
            # 0.5 could mean 0.5% or 50%: never guess the scale, and never show it silently
            note = "value <1 — possible percent/fraction unit change"
            errs.append(f"opencode-go: {k} percent={pct} is below 1 ({note})")
        ep, bad = reset_from(w.get("resetsAt") or "")
        if bad:
            note = "unparseable reset time — staleness unknown"
        rows.append(row("opencode-go (hermes)", label, 100.0 - pct, ep, wsec,
                        note=note, used=pct, stale=bad))
        n += 1
    if not n:
        errs.append("opencode-go: no usage windows in response")


# --------------------------------------------------------------------------- output
C = {"g": "\033[32m", "y": "\033[33m", "r": "\033[31m", "d": "\033[2m",
     "b": "\033[1m", "x": "\033[0m"}


def paint(rem, use_color):
    if rem is None or not use_color:
        return ""
    return C["g"] if rem >= 50 else (C["y"] if rem >= 20 else C["r"])


def render(rows, errs, use_color=True):
    now = datetime.now().strftime("%a %d %b %H:%M %Z")
    print(f"{C['b'] if use_color else ''}AI subscription quota — {now}"
          f"{C['x'] if use_color else ''}")
    print("─" * 78)
    cur = None
    for r in rows:
        if r["provider"] != cur:
            cur = r["provider"]
            print(f"{C['b'] if use_color else ''}{cur.upper()}{C['x'] if use_color else ''}")
        rem = r["remaining_pct"]
        if rem is None:
            print(f"  {r['window']:<18} {r['note'] or 'n/a'}")
            continue
        col = paint(rem, use_color)
        if r["expired"]:
            # The window has rolled over: the stored figure is PRE-reset, so it is not a current
            # reading. Say the window reset instead of printing a value the eye takes as live.
            last = f"  (last known {rem:.1f}% left before reset)"
            print(f"  {r['window']:<18} reset — current value unknown{last}"
                  f"{'  ·stale' if r['stale'] else ''}")
            continue
        when = ""
        if r["resets_in_s"] is not None:
            if r["resets_in_s"] <= 0:
                when = "  window elapsed — refresh source"
            else:
                when = f"  in {human_delta(r['resets_in_s'])}"
                if r["note"]:
                    when += f"  ({r['note']})"
        elif r["resets_at"]:
            when = f"  resets {r['resets_at']}"
            if r["note"]:            # e.g. a claude row served from cache: show its age
                when += f"  ({r['note']})"
        mark = "  ·stale" if r["stale"] else ""
        if r["pace"] is not None:
            mark += "  ▲fast" if r["pace"] > 12 else ("  ▼slow" if r["pace"] < -12 else "  ~")
            if use_color and r["pace"] > 12:
                mark = C["r"] + mark + C["x"]
        print(f"  {r['window']:<18} [{bar(rem)}] "
              f"{col}{rem:>5.1f}% left{C['x'] if use_color else ''}  {when}{mark}")
    print()
    for e in errs:
        print(f"  {C['d'] if use_color else ''}! {e}{C['x'] if use_color else ''}")


def _tag(p):
    p = p.lower()
    if p.startswith("codex"):
        return "codex"
    if p.startswith("claude"):
        return "claude"
    if p.startswith("agy"):
        return "agy-gem" if "gemini" in p else "agy-cg"
    if p.startswith("opencode"):
        return "go"
    return p[:6]


def brief(rows, nerrs=0):
    out = []
    for r in rows:
        tag = f"{_tag(r['provider'])}:{r['window'].split()[0]}"
        if r["expired"]:
            # an elapsed window has rolled over: a percentage here would read as current
            out.append(f"{tag} reset")
            continue
        if r["remaining_pct"] is None:
            continue
        mark = "?" if r["stale"] else ""       # ? = last known, not current
        out.append(f"{tag} {r['remaining_pct']:.0f}%{mark}")
    line = " · ".join(out)
    if nerrs:
        line += f" · !{nerrs}"                 # a source failed: visible even in --brief
    return line


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--brief", action="store_true")
    ap.add_argument("--plain", action="store_true")
    ap.add_argument("--only", default="codex,claude,agy,opencode")
    ap.add_argument("--ttl", type=int, default=120)
    a = ap.parse_args()
    only = {s.strip() for s in a.only.split(",") if s.strip()}

    rows, errs = [], []
    if "codex" in only:
        try:
            get_codex(rows, errs)
        except Exception as e:
            errs.append(f"codex: {type(e).__name__}: {str(e)[:80]}")
    if "claude" in only:
        try:
            get_claude(rows, errs, a.ttl)
        except Exception as e:
            errs.append(f"claude: {type(e).__name__}: {str(e)[:80]}")
    if "agy" in only:
        try:
            get_agy(rows, errs, a.ttl)
        except Exception as e:
            errs.append(f"agy: {type(e).__name__}: {str(e)[:80]}")
    if "opencode" in only or "go" in only:
        try:
            get_opencode(rows, errs)
        except Exception as e:
            # never interpolate text: it could carry the key
            errs.append(f"opencode-go: {type(e).__name__}")

    if a.json:
        print(json.dumps({"generated": iso(time.time()), "rows": rows, "errors": errs}, indent=2))
    elif a.brief:
        print(brief(rows, len(errs)))
    else:
        render(rows, errs, use_color=(not a.plain and sys.stdout.isatty()))
    # 0 = clean; 2 = a source failed (a cron job can alert on this); 1 = nothing collected at all
    if not rows:
        return 1
    return 2 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
