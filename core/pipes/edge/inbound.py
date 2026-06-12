#!/usr/bin/env python3
"""Edge inbound: chat.db -> capture(). Capture-first: durable before anything judges it.

Stdlib only. psql calls use -v variables (injection-safe quoting via :'var').
DB-unreachable contract (specs/06): failed captures append to the on-disk spool and replay
next cycle; the watch config is cached so capture survives a Postgres outage end-to-end.
The cursor advances even when spooling — the spool IS durability; locator dedup makes
replays free if anything overlaps.
"""
import json
import os
import pathlib
import sqlite3
import subprocess

PG_BIN = os.environ.get("PG_BIN", "/opt/homebrew/opt/postgresql@17/bin")
ROLE = os.environ.get("CLAUDIO_DB_ROLE", "w_edge")
CHATDB = os.environ.get("CLAUDIO_CHATDB", os.path.expanduser("~/Library/Messages/chat.db"))
STATE = pathlib.Path(os.environ.get("CLAUDIO_STATE_DIR", os.path.expanduser("~/.claudio/state")))
SPOOL = pathlib.Path(os.environ.get("CLAUDIO_SPOOL_DIR", os.path.expanduser("~/.claudio/spool")))
ADAPTER = "edge-imessage"

CAPTURE_SQL = (
    "select l1.capture(:'adapter', :'raw', "
    "jsonb_build_object('source','imessage','handle',:'handle','service','iMessage',"
    "'verified_user',(:'vu')::boolean,'chat',:'chat'), "
    ":'locator', null, 0::smallint, 'verbatim')"
)


def psql(sql, vars):
    # SQL goes via STDIN, never -c: psql only interpolates -v variables (the injection-safe
    # :'var' quoting) for scripts, not for -c strings.
    cmd = [f"{PG_BIN}/psql", "-U", ROLE, "-d", "claudio", "-tAq", "-v", "ON_ERROR_STOP=1"]
    for k, v in vars.items():
        cmd += ["-v", f"{k}={v}"]
    env = dict(os.environ)
    env.setdefault("PGHOST", os.path.expanduser("~/.claudio/sock"))
    env["PGPORT"] = os.environ.get("CLAUDIO_PGPORT", env.get("PGPORT", "5433"))
    return subprocess.run(cmd, input=sql + ";\n", capture_output=True, text=True, env=env)


def try_capture(item):
    r = psql(CAPTURE_SQL, {
        "adapter": ADAPTER, "raw": item["raw"], "handle": item["handle"],
        "vu": "true" if item["vu"] else "false", "chat": item.get("chat", ""),
        "locator": item["locator"],
    })
    return r.returncode == 0


def load_config():
    """Live config when the DB is up; cached config (so capture survives outages) when not."""
    cache = STATE / "edge-config.json"
    r = psql("select coalesce(config::text, '{}') from l1.components where id = :'cid'", {"cid": ADAPTER})
    if r.returncode == 0 and r.stdout.strip():
        cfg = json.loads(r.stdout.strip())
        cache.write_text(json.dumps(cfg))
        return cfg
    if cache.exists():
        return json.loads(cache.read_text())
    return {}


def main():
    STATE.mkdir(parents=True, exist_ok=True)
    SPOOL.mkdir(parents=True, exist_ok=True)
    spool_file = SPOOL / "edge.jsonl"

    # 1. replay spool (reconnect path)
    if spool_file.exists() and spool_file.stat().st_size:
        remaining = []
        for line in spool_file.read_text().splitlines():
            if line.strip() and not try_capture(json.loads(line)):
                remaining.append(line)
        spool_file.write_text("\n".join(remaining) + ("\n" if remaining else ""))
        if remaining:
            print(f"edge inbound: {len(remaining)} still spooled (db unreachable)")

    # 2. sweep chat.db
    cfg = load_config()
    watch = cfg.get("watch", [])
    user_handles = set(cfg.get("user_handles", []))
    if not watch:
        print("edge inbound: no watched chats configured; skipping")
        return
    if not pathlib.Path(CHATDB).exists():
        print(f"edge inbound: {CHATDB} not found (TCC/Full Disk Access at deploy?); skipping")
        return

    cursor_file = STATE / "edge-imessage.rowid"
    cursor = int(cursor_file.read_text().strip() or 0) if cursor_file.exists() else 0

    con = sqlite3.connect(f"file:{CHATDB}?mode=ro", uri=True)
    placeholders = ",".join("?" * len(watch))
    rows = con.execute(
        f"""select m.ROWID, m.guid, coalesce(m.text, '[non-text message]'),
                   coalesce(h.id, 'me'), c.chat_identifier, m.is_from_me
            from message m
            left join handle h on h.ROWID = m.handle_id
            join chat_message_join j on j.message_id = m.ROWID
            join chat c on c.ROWID = j.chat_id
            where m.ROWID > ? and c.chat_identifier in ({placeholders})
            order by m.ROWID""",
        [cursor, *watch],
    ).fetchall()

    n_ok = n_spooled = 0
    for rowid, guid, text, handle, chat, from_me in rows:
        item = {
            "raw": text,
            "handle": "me" if from_me else handle,
            "vu": bool(from_me) or handle in user_handles,
            "chat": chat,
            "locator": f"imsg-{guid}",
        }
        if try_capture(item):
            n_ok += 1
        else:
            with spool_file.open("a") as f:
                f.write(json.dumps(item) + "\n")
            n_spooled += 1
        cursor = rowid
        cursor_file.write_text(str(cursor))

    print(f"edge inbound: {n_ok} captured, {n_spooled} spooled")


if __name__ == "__main__":
    main()
