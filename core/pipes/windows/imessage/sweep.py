#!/usr/bin/env python3
"""window-imessage: the passive thread-day sweeper.

The capture unit for chat-like windows is the CLOSED thread-day (specs/01 §Atoms): one
capture per chat per finished local day, raw = the verbatim transcript. The filer writes
1..n atoms per window (default 1 — a 75-message meme day is one honest line).

The edge's direct-line chats are excluded (already captured per-message). Locator dedup
makes the sweep replayable; days_back bounds the scan window.
"""
import datetime
import json
import os
import pathlib
import sqlite3
import subprocess

PG_BIN = os.environ.get("PG_BIN", "/opt/homebrew/opt/postgresql@17/bin")
ROLE = os.environ.get("CLAUDIO_DB_ROLE", "w_edge")
CHATDB = os.environ.get("CLAUDIO_CHATDB", os.path.expanduser("~/Library/Messages/chat.db"))
STATE = pathlib.Path(os.environ.get("CLAUDIO_STATE_DIR", os.path.expanduser("~/.claudio/state")))
ADAPTER = "window-imessage"
APPLE_EPOCH = 978307200  # 2001-01-01 in unix seconds


def psql(sql, vars=None):
    cmd = [f"{PG_BIN}/psql", "-U", ROLE, "-d", "claudio", "-tAq", "-v", "ON_ERROR_STOP=1"]
    for k, v in (vars or {}).items():
        cmd += ["-v", f"{k}={v}"]
    env = dict(os.environ)
    env.setdefault("PGHOST", os.path.expanduser("~/.claudio/sock"))
    env["PGPORT"] = os.environ.get("CLAUDIO_PGPORT", env.get("PGPORT", "5433"))
    return subprocess.run(cmd, input=sql + ";\n", capture_output=True, text=True, env=env)


def apple_ts_to_local(raw):
    """message.date is ns since 2001 on modern macOS; seconds on old rows. Handle both."""
    secs = raw / 1_000_000_000 if raw > 10_000_000_000 else raw
    return datetime.datetime.fromtimestamp(secs + APPLE_EPOCH)


def load_config():
    cache = STATE / "window-imessage-config.json"
    r = psql("select coalesce(config::text, '{}') from l1.components where id = :'cid'", {"cid": ADAPTER})
    if r.returncode == 0 and r.stdout.strip():
        cfg = json.loads(r.stdout.strip())
        STATE.mkdir(parents=True, exist_ok=True)
        cache.write_text(json.dumps(cfg))
        return cfg
    return json.loads(cache.read_text()) if cache.exists() else {}


def main():
    cfg = load_config()
    watch = cfg.get("watch", [])
    exclude = set(cfg.get("exclude", []))
    days_back = int(cfg.get("days_back", 3))
    if not watch:
        print("window-imessage: no watch config; skipping")
        return
    if not pathlib.Path(CHATDB).exists():
        print(f"window-imessage: {CHATDB} not found; skipping")
        return

    today = datetime.date.today()
    floor = today - datetime.timedelta(days=days_back)

    con = sqlite3.connect(f"file:{CHATDB}?mode=ro", uri=True)
    rows = con.execute(
        """select c.chat_identifier, m.date, coalesce(h.id, 'me'), coalesce(m.text, '[non-text message]'), m.ROWID
           from message m
           left join handle h on h.ROWID = m.handle_id
           join chat_message_join j on j.message_id = m.ROWID
           join chat c on c.ROWID = j.chat_id
           order by m.ROWID"""
    ).fetchall()

    # group into chat-days (local time), keep only CLOSED days inside the scan window
    days = {}
    for chat, raw_ts, sender, text, rowid in rows:
        if chat in exclude or (watch != ["*"] and chat not in watch):
            continue
        ts = apple_ts_to_local(raw_ts)
        day = ts.date()
        if day >= today or day < floor:
            continue  # open day, or out of window
        days.setdefault((chat, day), []).append((ts, sender, text))

    n = 0
    for (chat, day), msgs in sorted(days.items(), key=lambda kv: (kv[0][1], kv[0][0])):
        transcript = "\n".join(f"[{ts.strftime('%H:%M')}] {sender}: {text}" for ts, sender, text in msgs)
        header = f"[thread-day window: {len(msgs)} messages in {chat} on {day.isoformat()}]"
        r = psql(
            "select l1.capture(:'adapter', :'raw', "
            "jsonb_build_object('source','imessage','handle',:'chat','service','iMessage','chat',:'chat',"
            "'thread_day',:'day','message_count',(:'n')::int), "
            ":'locator', null, 0::smallint, 'verbatim')",
            {"adapter": ADAPTER, "raw": f"{header}\n{transcript}", "chat": chat,
             "day": day.isoformat(), "n": str(len(msgs)),
             "locator": f"imsg-day-{chat}-{day.isoformat()}"})
        if r.returncode == 0:
            n += 1
        else:
            print(f"window-imessage: {chat}/{day}: capture failed: {r.stderr.strip()[:150]}")

    print(f"window-imessage: {n} chat-days swept ({len(days)} candidates)")


if __name__ == "__main__":
    main()
