#!/usr/bin/env python3
"""
openai-usage — show your ChatGPT usage (the chatgpt.com/settings/usage page) in a terminal.

It reads the ChatGPT access token that the Codex CLI already keeps in ~/.codex/auth.json,
refreshes it when it expires, and asks the same backend endpoint the web page uses:

    GET https://chatgpt.com/backend-api/wham/usage

No third-party packages, no API key, no browser.

Usage:
    usage.py                 # human-readable summary
    usage.py --json          # raw JSON (for jq / scripting)
    usage.py --detail        # also list rate-limit reset credits
    usage.py --watch 300     # refresh every 5 minutes until Ctrl-C
    usage.py --refresh       # force a token refresh (also happens automatically when needed)
    usage.py --waybar        # one json line for waybar's custom module (see openai.README.md)
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from contextlib import suppress
from datetime import datetime

import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

AUTH_FILE = os.path.expanduser("~/.codex/auth.json")
BASE_URL = "https://chatgpt.com/backend-api"
USAGE_PATH = "/wham/usage"
RESET_CREDITS_PATH = "/wham/rate-limit-reset-credits"
TOKEN_URL = "https://auth.openai.com/oauth/token"
CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"  # the client the Codex CLI / ChatGPT web app use
SCOPE = "openid profile email offline_access"
UA = "openai-usage-script/1.0"
CACHE_PATH = os.path.expanduser("~/.cache/openai-usage/state.json")
ICON = "\ue000"  # OpenAI knot artwork in Waybar's bundled fonts/openai-logo.ttf
# Pango rise is in 1/1024 px; lower the knot 2 px to match the text's optical center.
ICON_MARKUP = f"<span font_family='OpenAI Usage Logo' font_size='14pt' font_weight='normal' rise='-2048'>{ICON}</span>"

# palette from ~/.config/waybar/colors.css, for the tooltip markup
OK_COLOR, WARN_COLOR, CRIT_COLOR, MUTED_COLOR = "#8faa89", "#d8ad70", "#cb8580", "#a5b5ad"

REFRESH_MARGIN_SECONDS = 300  # refresh when the token has less than 5 minutes left
WAYBAR_TIMEOUT = 8            # seconds; the bar must not wait on a slow network at startup
BG_TIMEOUT = 20               # seconds; the background refresh can afford to wait longer
STALE_AFTER = 900             # seconds; past this the bar goes muted and the tooltip says so
LOCK_PATH = os.path.expanduser("~/.cache/openai-usage/refresh.lock")


class AuthError(Exception):
    """Something is wrong with the ChatGPT credentials."""


def _b64url(s: str) -> bytes:
    return base64.b64decode(s + "=" * (-len(s) % 4))


def jwt_claims(token: str) -> dict:
    """Decode the payload of a JWT (no signature verification, we only read `exp`)."""
    try:
        return json.loads(_b64url(token.split(".")[1]))
    except Exception:
        return {}


def read_auth(path: str) -> dict:
    try:
        with open(path) as fh:
            data = json.load(fh)
    except FileNotFoundError:
        raise AuthError(
            f"no auth file at {path}. Log in with the Codex CLI first "
            "(`codex login`), or point --auth-file at the right json."
        )
    except json.JSONDecodeError as exc:
        raise AuthError(f"{path} is not valid json: {exc}")

    if data.get("auth_mode") != "chatgpt":
        raise AuthError(
            f"{path} is in api-key mode, not chatgpt mode. "
            "This script reports ChatGPT plan usage, so it needs chatgpt auth."
        )
    tokens = data.get("tokens") or {}
    if not tokens.get("access_token"):
        raise AuthError(f"{path} has no access_token. Run `codex login` again.")
    return data


def token_expires_at(data: dict) -> int | None:
    claims = jwt_claims(data["tokens"]["access_token"])
    exp = claims.get("exp")
    return int(exp) if exp else None


def refresh_tokens(path: str) -> dict:
    """Exchange the refresh token for a fresh access token and save it back to auth.json."""
    data = read_auth(path)
    refresh_token = (data.get("tokens") or {}).get("refresh_token")
    if not refresh_token:
        raise AuthError("no refresh_token in auth.json; run `codex login` to sign in again.")

    body = urllib.parse.urlencode(
        {
            "grant_type": "refresh_token",
            "client_id": CLIENT_ID,
            "refresh_token": refresh_token,
            "scope": SCOPE,
        }
    ).encode()
    req = urllib.request.Request(
        TOKEN_URL,
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded", "User-Agent": UA},
    )
    try:
        resp = json.loads(urllib.request.urlopen(req, timeout=30).read())
    except urllib.error.HTTPError as exc:
        raise AuthError(f"token refresh rejected ({exc.code}): {exc.read().decode(errors='replace')[:300]}")
    except Exception as exc:
        raise AuthError(f"token refresh failed: {exc}")

    if not resp.get("access_token"):
        raise AuthError("token refresh returned no access_token")

    tokens = data["tokens"]
    tokens["access_token"] = resp["access_token"]
    if resp.get("refresh_token"):
        tokens["refresh_token"] = resp["refresh_token"]
    if resp.get("id_token"):
        tokens["id_token"] = resp["id_token"]
    data["last_refresh"] = datetime.now().astimezone().isoformat()

    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        if os.name == "posix":
            os.chmod(tmp, 0o600)
        json.dump(data, fh, indent=2)
    os.replace(tmp, path)
    return data


def api_get(path: str, token: str, timeout: int = 30) -> dict:
    req = urllib.request.Request(
        BASE_URL + path,
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/json",
            "User-Agent": UA,
            "OAI-Product-Source": "chatgpt",
            "OAI-Product-Use": "agentic",
            "api_type": "web",
        },
    )
    try:
        resp = urllib.request.urlopen(req, timeout=timeout)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")[:200]
        raise AuthError(f"{path} -> HTTP {exc.code}: {detail} (if the token is stale, try --refresh)")
    except Exception as exc:
        raise AuthError(f"network error calling {path}: {exc}")
    return json.loads(resp.read())


def read_cached() -> tuple[dict, float] | tuple[None, None]:
    """Return the last fetched payload and how old it is in seconds, whatever its age."""
    try:
        with open(CACHE_PATH) as fh:
            data = json.load(fh)
    except Exception:
        return None, None
    return data, max(0.0, time.time() - data.get("_fetched_at", 0))


def write_cache(payload: dict) -> None:
    """Save through a temp file, so a background refresh never leaves a half-written cache."""
    payload = dict(payload, _fetched_at=time.time())
    os.makedirs(os.path.dirname(CACHE_PATH), exist_ok=True)
    tmp = f"{CACHE_PATH}.{os.getpid()}.tmp"
    with open(tmp, "w") as fh:
        json.dump(payload, fh)
    os.replace(tmp, CACHE_PATH)


def claim_lock(max_age: int = 120) -> bool:
    """Take the refresh lock, unless a live refresher is already holding it."""
    try:
        if time.time() - os.stat(LOCK_PATH).st_mtime < max_age:
            return False
    except FileNotFoundError:
        pass
    try:
        with os.fdopen(os.open(LOCK_PATH, os.O_CREAT | os.O_EXCL | os.O_WRONLY), "w") as fh:
            fh.write(str(os.getpid()))
    except OSError:
        return False
    return True


def release_lock() -> None:
    with suppress(OSError):
        os.unlink(LOCK_PATH)


def short_span(seconds: float | None) -> str:
    if not seconds:
        return "window"
    seconds = int(seconds)
    if seconds % 86400 == 0:
        return f"{seconds // 86400}d"
    if seconds % 3600 == 0:
        return f"{seconds // 3600}h"
    return f"{seconds // 60}m"


def pango_escape(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def window_left(win: dict) -> float | None:
    """Seconds until the window resets, from the absolute timestamp when present."""
    at = win.get("reset_at")
    if at:
        return max(0.0, at - time.time())
    return win.get("reset_after_seconds")


def collect_windows(payload: dict) -> list[tuple[str, dict]]:
    rl = payload.get("rate_limit") or {}
    out = []
    for key in ("primary_window", "secondary_window"):
        if rl.get(key):
            out.append((short_span(rl[key].get("limit_window_seconds")) + " window", rl[key]))
    for extra in payload.get("additional_rate_limits") or []:
        win = (extra.get("rate_limit") or {}).get("primary_window")
        if win:
            label = extra.get("limit_name") or "extra limit"
            if extra.get("normal_model_slug"):
                label += f" ({extra['normal_model_slug']})"
            out.append((label, win))
    return out


def meter(pct: float, width: int = 12) -> str:
    filled = round(width * min(100, max(0, pct)) / 100)
    return "█" * filled + "░" * (width - filled)


def waybar_payload(payload: dict, age: float = 0.0) -> dict:
    """Shape the usage data into waybar's custom-module json: text, tooltip, class, percentage."""
    windows = collect_windows(payload)
    worst = max((w.get("used_percent") or 0) for _, w in windows) if windows else 0
    reached = payload.get("rate_limit_reached_type") or (payload.get("rate_limit") or {}).get("limit_reached")

    if reached:
        state = "critical"
    elif worst >= 95:
        state = "critical"
    elif worst >= 80:
        state = "warning"
    else:
        state = "ok"
    stale = age > STALE_AFTER
    if stale and state != "critical":
        state = "stale"

    five_hour = next((w for _, w in windows if w.get("limit_window_seconds") == 5 * 3600), None)
    five_hour_used = (five_hour.get("used_percent") or 0) if five_hour is not None else None
    summary = f"{five_hour_used:.0f}%" if five_hour_used is not None else "–"
    if five_hour is not None:
        left = window_left(five_hour)
        if left is not None:
            summary += f" ↻ {humanize(left).replace(' ', '')}"
    text = f"{ICON_MARKUP} {summary}"

    fetched = time.strftime("%H:%M", time.localtime(time.time() - age))
    lines = [
        f"<big><b>OpenAI · {(payload.get('plan_type') or '?').title()}</b></big>",
        f"<span color='{MUTED_COLOR}'>{pango_escape(payload.get('email') or payload.get('user_id') or '')} · fetched {fetched}"
        + (f" · {humanize(age)} old</span>" if stale else "</span>"),
        "",
    ]
    width = max((len(label) for label, _ in windows), default=12)
    for label, win in windows:
        used = win.get("used_percent") or 0
        tint = CRIT_COLOR if used >= 95 else WARN_COLOR if used >= 80 else OK_COLOR
        left = window_left(win)
        tail = f"resets in {humanize(left)}" if left is not None else ""
        lines.append(
            f"<b>{pango_escape(label)}</b>{' ' * (width - len(label))}"
            f" <span color='{tint}'>{meter(used)} {used:.0f}% used</span>"
            + (f" · {tail}" if tail else "")
        )

    credits = payload.get("credits") or {}
    if credits:
        lines.append(f"<span color='{MUTED_COLOR}'>credits {credits.get('balance', '0')} · "
                     f"{'unlimited' if credits.get('unlimited') else 'metered'}</span>")
    resets = (payload.get("_reset_credits") or {}).get("credits") or []
    available = [c for c in resets if c.get("status") == "available"]
    if available:
        lines.append(
            f"<span color='{OK_COLOR}'>reset credits: {len(available)} available</span>"
            + "".join(
                f"\n  <span color='{MUTED_COLOR}'>{pango_escape(c.get('title', ''))} · expires {fmt_iso(c.get('expires_at'))}</span>"
                for c in available
            )
        )
    tooltip = "\n".join(lines)

    return {
        "text": text,
        "tooltip": tooltip,
        "class": state,
        "percentage": round(five_hour_used) if five_hour_used is not None else 0,
    }


def fetch_payload(auth_file: str, timeout: int = 30) -> dict:
    """Auth, refresh the token if it is about to expire, and ask both endpoints at once."""
    data = read_auth(auth_file)
    exp = token_expires_at(data)
    if exp is not None and exp - time.time() < REFRESH_MARGIN_SECONDS:
        data = refresh_tokens(auth_file)
    token = data["tokens"]["access_token"]
    with ThreadPoolExecutor(max_workers=2) as pool:
        usage_job = pool.submit(api_get, USAGE_PATH, token, timeout)
        credits_job = pool.submit(api_get, RESET_CREDITS_PATH, token, timeout)
        payload = usage_job.result()
        try:
            payload["_reset_credits"] = credits_job.result()
        except Exception:
            payload["_reset_credits"] = {}
    return payload


def spawn_refresh(auth_file: str) -> None:
    """Hand the fetch to a detached copy of this script, so the bar gets its json right away."""
    if not claim_lock():
        return
    try:
        subprocess.Popen(
            [sys.executable, os.path.realpath(__file__), "--waybar", "--bg-refresh",
             "--auth-file", auth_file],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True, close_fds=True,
        )
    except OSError:
        release_lock()


def refresh_cache(auth_file: str) -> None:
    """The detached half of spawn_refresh: fetch and save quietly, then hand the lock back."""
    try:
        write_cache(fetch_payload(auth_file, timeout=BG_TIMEOUT))
    except Exception:
        pass  # the bar keeps showing the last good payload; the lock expires and we retry
    finally:
        release_lock()


def emit_waybar(cache_seconds: int, auth_file: str) -> None:
    """Print one line of json for waybar's custom module; never let a hiccup crash the bar."""
    try:
        payload, age = read_cached()
        if payload is not None and age > cache_seconds:
            # the cached numbers are usable but overdue: show them now, fetch in the background
            spawn_refresh(auth_file)
        elif payload is None:
            # no cache at all (first ever run): fetch, but keep the wait short
            payload = fetch_payload(auth_file, timeout=WAYBAR_TIMEOUT)
            write_cache(payload)
            age = 0.0
        print(json.dumps(waybar_payload(payload, age)))
    except Exception as exc:
        note = str(exc).replace("\n", " ")[:120]
        text = f"{ICON_MARKUP} –"
        print(json.dumps({
            "text": text,
            "tooltip": f"<b>OpenAI usage is stale</b>\n<span color='{CRIT_COLOR}'>{pango_escape(note)}</span>",
            "class": "stale",
            "percentage": 0,
        }))


def humanize(seconds: float | None) -> str:
    if seconds is None:
        return "?"
    seconds = max(0, int(seconds))
    d, rem = divmod(seconds, 86400)
    h, rem = divmod(rem, 3600)
    m = rem // 60
    if d:
        return f"{d}d {h}h"
    if h:
        return f"{h}h {m:02d}m"
    return f"{m}m"


def window_line(name: str, window: dict, width: int = 20) -> str:
    used = window.get("used_percent") or 0
    filled = int(round(width * min(100, max(0, used)) / 100))
    bar = "█" * filled + "░" * (width - filled)
    parts = [f"{bar} {used:>3.0f}% used"]
    span = window.get("limit_window_seconds")
    if span:
        parts.append(f"over {humanize(span)}")
    left = window.get("reset_after_seconds")
    if left is not None:
        parts.append(f"resets in {humanize(left)}")
    elif window.get("reset_at"):
        parts.append(time.strftime("%Y-%m-%d %H:%M", time.localtime(window["reset_at"])))
    return f"{name:<28} " + " · ".join(parts)


def render(payload: dict, detail: bool, color: bool) -> str:
    out: list[str] = []

    def paint(text: str, code: str) -> str:
        return f"\x1b[{code}m{text}\x1b[0m" if color else text

    plan = (payload.get("plan_type") or "?").title()
    who = payload.get("email") or payload.get("user_id") or "?"
    out.append(paint(f"ChatGPT usage · {who} · plan {plan}", "1"))
    out.append(time.strftime("%Y-%m-%d %H:%M:%S %Z", time.localtime()))
    out.append("")

    rl = payload.get("rate_limit") or {}
    out.append(paint("Usage limits", "1;4"))
    if rl.get("primary_window"):
        out.append("  " + window_line("primary window", rl["primary_window"]))
    if rl.get("secondary_window"):
        out.append("  " + window_line("secondary window", rl["secondary_window"]))
    for extra in payload.get("additional_rate_limits") or []:
        label = extra.get("limit_name") or "extra limit"
        if extra.get("normal_model_slug"):
            label += f" ({extra['normal_model_slug']})"
        elif extra.get("metered_feature"):
            label += f" ({extra['metered_feature']})"
        win = (extra.get("rate_limit") or {}).get("primary_window")
        if win:
            out.append("  " + window_line(label, win))
    out.append("")

    worst = max(
        [w.get("used_percent", 0) for w in
         [rl.get("primary_window"), rl.get("secondary_window")] +
         [(e.get("rate_limit") or {}).get("primary_window") for e in payload.get("additional_rate_limits") or []]
         if w],
        default=0,
    )
    reached = payload.get("rate_limit_reached_type") or (rl.get("limit_reached"))
    if reached:
        note = f" ({reached})" if isinstance(reached, str) else ""
        out.append(paint(f"⚠ a limit has been reached{note}", "1;31"))
    elif worst >= 90:
        out.append(paint(f"⚠ {worst:.0f}% of a window is used — you are close to a limit", "1;33"))
    else:
        out.append(paint(f"OK — highest window at {worst:.0f}% used", "1;32"))
    out.append("")

    credits = payload.get("credits") or {}
    if credits:
        out.append(paint("Credits", "1;4"))
        out.append(
            f"  balance {credits.get('balance', '0')} · "
            f"{'unlimited' if credits.get('unlimited') else 'metered'} · "
            f"overage limit {'reached' if credits.get('overage_limit_reached') else 'not reached'}"
        )
        out.append("")

    spend = payload.get("spend_control") or {}
    if spend:
        limit = spend.get("individual_limit")
        out.append(paint("Spend control", "1;4"))
        line = f"  monthly budget {'reached' if spend.get('reached') else 'not reached'}"
        if isinstance(limit, dict):
            used, cap = limit.get("used"), limit.get("limit") or limit.get("max")
            line += f" · {used} / {cap} USD" if used is not None and cap else ""
        out.append(line)
        out.append("")

    models = payload.get("model_usage") or {}
    if models:
        out.append(paint("Model access", "1;4"))
        for slug, info in sorted(models.items()):
            flags = []
            if info.get("available"):
                flags.append("available")
            elif info.get("available_at"):
                flags.append("unlocks " + time.strftime("%Y-%m-%d", time.localtime(info["available_at"])))
            if info.get("credits_would_enable"):
                flags.append("credits would unlock")
            out.append(f"  {slug:<24} " + ", ".join(flags))
        out.append("")

    if detail:
        resets = payload.get("_reset_credits") or {}
        items = resets.get("credits") or []
        available = [c for c in items if c.get("status") == "available"]
        out.append(paint(f"Rate-limit reset credits ({len(available)} available)", "1;4"))
        for c in available:
            out.append(
                f"  {c.get('title', '?')} · {c.get('reset_type', '?')} · "
                f"granted {fmt_iso(c.get('granted_at'))} · expires {fmt_iso(c.get('expires_at'))}"
            )
        if not available:
            out.append("  none")
        out.append("")

    return "\n".join(out).rstrip()


def fmt_iso(s: str | None) -> str:
    if not s:
        return "?"
    try:
        dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
        return dt.astimezone().strftime("%Y-%m-%d")
    except Exception:
        return s


def main() -> int:
    ap = argparse.ArgumentParser(description="Show your ChatGPT usage without opening the browser.")
    ap.add_argument("--json", action="store_true", help="print the raw JSON instead of a summary")
    ap.add_argument("--detail", action="store_true", help="also show reset credits and per-model notes")
    ap.add_argument("--watch", type=int, metavar="SECONDS", help="redraw every N seconds until Ctrl-C")
    ap.add_argument("--refresh", action="store_true", help="force a token refresh before fetching")
    ap.add_argument("--auth-file", default=AUTH_FILE, help="ChatGPT auth json (default: ~/.codex/auth.json)")
    ap.add_argument("--plain", action="store_true", help="never emit ANSI colors")
    ap.add_argument("--waybar", action="store_true", help="print one json line for waybar's custom module")
    ap.add_argument("--cache", type=int, default=0, metavar="SECONDS",
                    help="reuse the previous result if it is younger than N seconds")
    ap.add_argument("--bg-refresh", action="store_true",
                    help="with --waybar: refetch in the background and print nothing (used internally)")
    args = ap.parse_args()

    color = sys.stdout.isatty() and not args.plain

    if args.waybar:
        if args.bg_refresh:
            refresh_cache(args.auth_file)
            return 0
        emit_waybar(args.cache, args.auth_file)
        return 0

    def show_once() -> None:
        data = read_auth(args.auth_file)
        exp = token_expires_at(data)
        if args.refresh or (exp is not None and exp - time.time() < REFRESH_MARGIN_SECONDS):
            data = refresh_tokens(args.auth_file)
        payload = api_get(USAGE_PATH, data["tokens"]["access_token"])
        if args.detail:
            try:
                payload["_reset_credits"] = api_get(RESET_CREDITS_PATH, data["tokens"]["access_token"])
            except AuthError:
                payload["_reset_credits"] = {}
        if args.json:
            print(json.dumps(payload, indent=2))
        else:
            print(render(payload, args.detail, color))

    try:
        if args.watch:
            while True:
                start = time.time()
                show_once()
                time.sleep(max(1, args.watch - (time.time() - start)))
                if sys.stdout.isatty():
                    sys.stdout.write("\x1b[H\x1b[2J")
        else:
            show_once()
    except KeyboardInterrupt:
        return 130
    except AuthError as exc:
        print(f"error: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
