#!/usr/bin/env python3
"""edge-gv: the Google Voice channel edge (Sam's channel decision, 2026-07-19).

The channel is a GV number; GV forwards each SMS/MMS to the owning Gmail. One cycle =
inbound sweep (IMAP UNSEEN -> capture(); mark \\Seen only after capture succeeds, so the
mailbox itself is the durability spool) + outbound drain (claim 'user' queue -> reply-by-
email over SMTP -> resolve only on send success; a failed send stays claimed and the
lease re-arms it). Deterministic stdlib only — no LLM in this context, ever (P6).

Reply path reality: GV sends each forwarded SMS from a per-conversation address at
txt.voice.google.com; replying to that address delivers an SMS back. The freshest such
address per sender is remembered in state; until the user has texted the number once,
there is no reply path and outbound stays queued (never dropped).

Test seams: CLAUDIO_GV_MAILDIR (a dir of .eml files replaces IMAP; processed names are
recorded in state) and CLAUDIO_GV_OUTBOX (outbound writes .eml files instead of SMTP).
"""
import email
import email.policy
import imaplib
import json
import os
import pathlib
import re
import smtplib
import subprocess
from email.message import EmailMessage

PG_BIN = os.environ.get("PG_BIN", "/opt/homebrew/opt/postgresql@17/bin")
ROLE = os.environ.get("CLAUDIO_DB_ROLE", "w_edge")
STATE = pathlib.Path(os.environ.get("CLAUDIO_STATE_DIR", os.path.expanduser("~/.claudio/state")))
ATTACH = pathlib.Path(os.environ.get("CLAUDIO_GV_ATTACH_DIR", os.path.expanduser("~/.claudio/archive/edge-gv")))
PASS_FILE = pathlib.Path(os.environ.get("CLAUDIO_GV_PASS_FILE", os.path.expanduser("~/.claudio/gv-app-pass")))
MAILDIR = os.environ.get("CLAUDIO_GV_MAILDIR")
OUTBOX = os.environ.get("CLAUDIO_GV_OUTBOX")
ADAPTER = "edge-gv"
GV_DOMAINS = ("txt.voice.google.com", "voice-noreply@google.com")

CAPTURE_SQL = (
    "select l1.capture(:'adapter', :'raw', "
    "jsonb_build_object('source','gv-sms','handle',:'handle','service','SMS',"
    "'verified_user',(:'vu')::boolean,'attachments',(:'atts')::jsonb), "
    ":'locator', null, 0::smallint, 'verbatim')"
)


def psql(sql, vars=None):
    cmd = [f"{PG_BIN}/psql", "-U", ROLE, "-d", "claudio", "-tAq", "-v", "ON_ERROR_STOP=1"]
    for k, v in (vars or {}).items():
        cmd += ["-v", f"{k}={v}"]
    env = dict(os.environ)
    env.setdefault("PGHOST", os.path.expanduser("~/.claudio/sock"))
    env["PGPORT"] = os.environ.get("CLAUDIO_PGPORT", env.get("PGPORT", "5433"))
    return subprocess.run(cmd, input=sql + ";\n", capture_output=True, text=True, env=env)


def load_config():
    cache = STATE / "edge-gv-config.json"
    r = psql("select coalesce(config::text, '{}') from l1.components where id = :'cid'", {"cid": ADAPTER})
    if r.returncode == 0 and r.stdout.strip():
        cfg = json.loads(r.stdout.strip())
        cache.write_text(json.dumps(cfg))
        return cfg
    if cache.exists():
        return json.loads(cache.read_text())
    return {}


def digits10(handle):
    d = re.sub(r"\D", "", handle or "")
    return d[-10:] if len(d) >= 10 else d


def is_gv(msg):
    src = (msg.get("From", "") + " " + msg.get("Reply-To", "")).lower()
    return any(dom in src for dom in GV_DOMAINS)


def parse_gv(msg):
    """Sender number, SMS text (footer stripped), reply address, attachments."""
    from_addr = email.utils.parseaddr(msg.get("From", ""))[1]
    reply_addr = email.utils.parseaddr(msg.get("Reply-To", msg.get("From", "")))[1]
    display = email.utils.parseaddr(msg.get("From", ""))[0]
    sender = digits10(display) or digits10(from_addr.split("@")[0])

    body, atts = "", []
    for part in msg.walk():
        ctype = part.get_content_type()
        if ctype == "text/plain" and not body:
            body = part.get_content()
        elif part.get_filename() and ctype.startswith(("image/", "video/", "audio/")):
            ATTACH.mkdir(parents=True, exist_ok=True)
            safe = re.sub(r"[^A-Za-z0-9._-]", "_", part.get_filename())
            mid = re.sub(r"[^A-Za-z0-9]", "", msg.get("Message-ID", "noid"))[-12:]
            dest = ATTACH / f"{mid}-{safe}"
            dest.write_bytes(part.get_payload(decode=True) or b"")
            atts.append(str(dest))
    # GV appends a boilerplate footer (account/help/unsubscribe links); keep lines above it
    lines = []
    for line in body.splitlines():
        if re.search(r"voice\.google\.com|YOUR ACCOUNT|HELP CENTER|To respond to this text", line, re.I):
            break
        lines.append(line)
    text = "\n".join(lines).strip()
    return sender, text, reply_addr, atts


def try_capture(sender, text, atts, locator, user_handles):
    vu = digits10(sender) in {digits10(h) for h in user_handles}
    r = psql(CAPTURE_SQL, {
        "adapter": ADAPTER, "raw": text or "[non-text message]", "handle": sender,
        "vu": "true" if vu else "false", "atts": json.dumps(atts), "locator": locator,
    })
    return r.returncode == 0


def remember_reply(sender, reply_addr):
    f = STATE / "gv-replyto.json"
    m = json.loads(f.read_text()) if f.exists() else {}
    m[digits10(sender)] = reply_addr
    f.write_text(json.dumps(m))


def inbound(cfg):
    user_handles = cfg.get("user_handles", [])
    n = 0
    if MAILDIR:  # test seam
        seen_file = STATE / "gv-maildir-seen.json"
        seen = set(json.loads(seen_file.read_text())) if seen_file.exists() else set()
        for p in sorted(pathlib.Path(MAILDIR).glob("*.eml")):
            if p.name in seen:
                continue
            msg = email.message_from_bytes(p.read_bytes(), policy=email.policy.default)
            if not is_gv(msg):
                continue
            sender, text, reply_addr, atts = parse_gv(msg)
            if try_capture(sender, text, atts, f"gv-{msg.get('Message-ID', p.name)}", user_handles):
                remember_reply(sender, reply_addr)
                seen.add(p.name)
                n += 1
        seen_file.write_text(json.dumps(sorted(seen)))
        return n

    account = cfg.get("account", "")
    if not account or not PASS_FILE.exists():
        print("edge-gv: account/app-password not configured; skipping inbound")
        return 0
    pw = PASS_FILE.read_text().strip()
    imap = imaplib.IMAP4_SSL(os.environ.get("CLAUDIO_GV_IMAP", "imap.gmail.com"))
    try:
        imap.login(account, pw)
        imap.select("INBOX")
        _, data = imap.search(None, "UNSEEN")
        for uid in data[0].split():
            _, fetched = imap.fetch(uid, "(BODY.PEEK[])")
            msg = email.message_from_bytes(fetched[0][1], policy=email.policy.default)
            if not is_gv(msg):
                continue
            sender, text, reply_addr, atts = parse_gv(msg)
            if try_capture(sender, text, atts, f"gv-{msg.get('Message-ID', uid.decode())}", user_handles):
                remember_reply(sender, reply_addr)
                imap.store(uid, "+FLAGS", "\\Seen")  # durable: unseen == unprocessed
                n += 1
    finally:
        try:
            imap.logout()
        except Exception:
            pass
    return n


def send_one(cfg, reply_addr, text):
    account = cfg.get("account", "")
    msg = EmailMessage()
    msg["From"], msg["To"], msg["Subject"] = account, reply_addr, ""
    msg.set_content(text)
    if OUTBOX:  # test seam
        out = pathlib.Path(OUTBOX)
        out.mkdir(parents=True, exist_ok=True)
        n = len(list(out.glob("*.eml")))
        (out / f"{n:04d}.eml").write_bytes(bytes(msg))
        return True
    if not account or not PASS_FILE.exists():
        return False
    try:
        with smtplib.SMTP_SSL(os.environ.get("CLAUDIO_GV_SMTP", "smtp.gmail.com"), 465) as s:
            s.login(account, PASS_FILE.read_text().strip())
            s.send_message(msg)
        return True
    except Exception as e:
        print(f"edge-gv: send failed ({e}); message stays claimed")
        return False


def outbound(cfg):
    user_handles = cfg.get("user_handles", [])
    f = STATE / "gv-replyto.json"
    replymap = json.loads(f.read_text()) if f.exists() else {}
    reply_addr = replymap.get(digits10(user_handles[0])) if user_handles else None
    if not reply_addr:
        print("edge-gv: no reply path yet (user must text the GV number once); outbound queued")
        return 0
    n = 0
    while True:
        r = psql("select (s.m->>'id') || e'\\x1f' || coalesce(s.m->'payload'->>'summary', '(no summary)') "
                 "from (select l1.claim_message('user') as m) s where s.m is not null")
        line = r.stdout.strip()
        if r.returncode != 0 or not line:
            break
        mid, _, text = line.partition("\x1f")
        if send_one(cfg, reply_addr, text):
            psql("select l1.resolve_message((:'id')::uuid, jsonb_build_object('delivered', true, 'via', 'gv-email'))",
                 {"id": mid})
            n += 1
        else:
            break  # stays claimed; lease re-arms it
    return n


def main():
    STATE.mkdir(parents=True, exist_ok=True)
    cfg = load_config()
    n_in = inbound(cfg)
    n_out = outbound(cfg)
    print(f"edge-gv: {n_in} captured, {n_out} sent")
    url = os.environ.get("CLAUDIO_DEADMAN_URL")
    if url:
        subprocess.run(["curl", "-fsS", "-m", "10", url], capture_output=True)


if __name__ == "__main__":
    main()
