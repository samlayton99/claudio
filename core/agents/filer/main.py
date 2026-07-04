#!/usr/bin/env python3
"""The filer worker: pending intake -> one LLM judgment per row -> file_intake/discard/hold.

Plumbing is deterministic code; the model only judges (P12 spirit):
- tier-0 refs are INJECTED into every record_atom (the model cannot forget provenance)
- parse failure files the honest default (kind=unknown atom) after one retry — a row is
  never left to retry forever, and nothing is silently dropped
- file_intake's own poison-pill quarantine catches bad batches row-by-row

Two rows never reach the model at all (specs/01 §Atoms):
- `semantics.discard_patterns` on the row's window (term/stdlib regex list) discards
  OTP/spam shapes deterministically — raw stays in intake, no LLM pass
- a zero-signal thread-day (no questions, commitments, times, links, or unknown
  senders in the transcript) files its one honest atom from a template

LLM command comes from CLAUDIO_LLM_CMD (default `claude -p`); tests inject a stub.
"""
import json
import os
import pathlib
import re
import shlex
import subprocess

DIR = pathlib.Path(__file__).resolve().parent
PG_BIN = os.environ.get("PG_BIN", "/opt/homebrew/opt/postgresql@17/bin")
ROLE = os.environ.get("CLAUDIO_DB_ROLE", "w_filer")
LLM_CMD = os.environ.get("CLAUDIO_LLM_CMD", "claude -p")
BATCH = int(os.environ.get("CLAUDIO_FILER_BATCH", "10"))


def psql(sql, vars=None):
    cmd = [f"{PG_BIN}/psql", "-U", ROLE, "-d", "claudio", "-tAq", "-v", "ON_ERROR_STOP=1"]
    for k, v in (vars or {}).items():
        cmd += ["-v", f"{k}={v}"]
    env = dict(os.environ)
    env.setdefault("PGHOST", os.path.expanduser("~/.claudio/sock"))
    env["PGPORT"] = os.environ.get("CLAUDIO_PGPORT", env.get("PGPORT", "5433"))
    return subprocess.run(cmd, input=sql + ";\n", capture_output=True, text=True, env=env)


def must(r, what):
    if r.returncode != 0:
        raise RuntimeError(f"{what}: {r.stderr.strip()}")
    return r.stdout.strip()


def llm(prompt):
    r = subprocess.run(shlex.split(LLM_CMD), input=prompt, capture_output=True, text=True,
                       timeout=int(os.environ.get("CLAUDIO_LLM_TIMEOUT", "300")))
    if r.returncode != 0:
        raise RuntimeError(f"llm failed: {r.stderr.strip()[:300]}")
    return r.stdout


UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.I)
UUID_ENDPOINT_TYPES = {"person", "task", "expectation", "atom", "document"}  # role/purpose ids are slugs


def _idlike(v):
    return (isinstance(v, dict) and "$ref" in v) or (isinstance(v, str) and UUID_RE.match(v))


def parse_decision(out):
    """Find the decision object in model output; raises (with a pointed message the retry
    prompt carries back) on anything the dispatcher would quarantine."""
    out = out.strip()
    try:
        d = json.loads(out)
    except json.JSONDecodeError:
        start, end = out.find("{"), out.rfind("}")
        if start < 0 or end <= start:
            raise
        d = json.loads(out[start:end + 1])
    if d.get("action") not in ("file", "discard", "hold"):
        raise ValueError(f"bad action: {d.get('action')}")
    if d["action"] == "file":
        acts = d.get("actions")
        if not isinstance(acts, list) or not acts:
            raise ValueError('"file" requires a non-empty "actions" array')
        for a in acts:
            if not a.get("fn") or not isinstance(a.get("args"), dict):
                raise ValueError('every action needs "fn" and an "args" OBJECT (args must wrap the keys)')
            if a["fn"] == "record_atom":
                missing = [k for k in ("ts", "kind", "summary") if not a["args"].get(k)]
                if missing:
                    raise ValueError(f"record_atom args missing required {missing}")
            if (a["fn"] == "add_link" and a["args"].get("origin", "inferred") == "inferred"
                    and a["args"].get("confidence") is None):
                raise ValueError("an inferred add_link requires a confidence (0..1)")
            s = a["args"].get("sensitivity")
            if s is not None and s not in (0, 1, 2):
                raise ValueError("sensitivity must be the integer 0 or 1, never a word")
            if s == 2:
                raise ValueError("the filer never assigns sensitivity 2 (a user/core designation) — use 1; the write floor still clamps up")
            for k in ("person_id", "obligation_id", "atom_id"):
                v = a["args"].get(k)
                if v is not None and not _idlike(v):
                    raise ValueError(f"{k} must be a uuid or {{'$ref': i}} — never a name or invented id")
            endpoints = ([(lk.get("to_type"), lk.get("to_id")) for lk in a["args"].get("links", [])]
                         if a["fn"] == "record_atom" else
                         [(a["args"].get("from_type"), a["args"].get("from_id")),
                          (a["args"].get("to_type"), a["args"].get("to_id"))] if a["fn"] == "add_link" else [])
            for etype, eid in endpoints:
                if etype in UUID_ENDPOINT_TYPES and not _idlike(eid):
                    raise ValueError(f"a link to a {etype} needs its uuid or a $ref — drop the link if you have no id (got {str(eid)[:40]})")
    return d


def ambient_context():
    ctx = os.environ.get("CLAUDIO_CONTEXT", "")
    if ctx.strip():
        return ctx
    roles = must(psql("select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name)), '[]') from l1.roles where status = 'active'"), "roles")
    atom_kinds = must(psql("select string_agg(key, ', ' order by key) from l1.kinds where domain = 'atom' and status = 'active'"), "atom kinds")
    link_kinds = must(psql("select string_agg(key, ', ' order by key) from l1.kinds where domain = 'link' and status = 'active'"), "link kinds")
    people = must(psql("select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'role', primary_role_id) order by name), '[]') "
                       "from (select id, name, primary_role_id from l1.people where status = 'active' order by updated_at desc limit 50) p"), "people")
    tasks = must(psql("select l1.due_tasks('{}')"), "due_tasks")
    exps = must(psql("select l1.pending_expectations('{}')"), "pending_expectations")
    return (f"Active roles: {roles}\n"
            f"Atom kinds (closed vocabulary — use ONLY these): {atom_kinds}\n"
            f"Link kinds (closed vocabulary): {link_kinds}\n"
            f"Known people (most recently active, up to 50): {people}\n"
            f"Open tasks: {tasks}\n"
            f"Pending expectations (when this capture IS the awaited thing arriving, close it: "
            f"resolve_obligation with the listed id and outcome 'met'): {exps}")


def known_person(sender):
    if not sender or not sender.get("handle") or sender.get("handle") == "me":
        return "the user himself" if sender and sender.get("handle") == "me" else None
    r = psql("select p.name || ' (person_id: ' || p.id || ')' from l1.person_handles ph "
             "join l1.people p on p.id = ph.person_id "
             "where ph.source = :'s' and ph.handle = :'h'",
             {"s": sender.get("source", ""), "h": sender["handle"]})
    return r.stdout.strip() or None if r.returncode == 0 else None


# ---------- deterministic pre-passes (no LLM) ----------

MSG_LINE_RE = re.compile(r"^\[\d{2}:\d{2}\] ([^:]+): (.*)$")
# any hit routes the row to the model — the template's failure mode (silently thinning a
# real conversation to one line) is worse than a wasted LLM pass
SIGNAL_RES = [re.compile(p, re.I) for p in (
    r"\?",                                            # questions
    r"https?://|www\.",                               # links
    r"[\w.+-]+@[\w-]+\.\w+",                          # emails
    r"\+?\d[\d\-\s().]{6,}\d",                        # phone-ish
    r"[$€£]\s?\d|\b\d+ ?(dollars|bucks)\b",           # money
    r"\b\d{1,2}(:\d{2})?\s?(am|pm)\b|\b\d{1,2}:\d{2}\b",  # clock times
    r"\b(mon|tues|wednes|thurs|fri|satur|sun)day\b|\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]* \d",
    r"\b(today|tonight|tomorrow|next week|this week(end)?)\b",
    r"\b(i'?ll|i will|we'?ll|can you|could you|will you|let'?s|need to|don'?t forget|remind|due|meet|call|send|book|schedule|confirm|rsvp|invite|deadline|pick up)\b",
)]

_cfg_cache = {}


def component_config(adapter):
    if adapter not in _cfg_cache:
        r = psql("select coalesce(config::text, '{}') from l1.components where id = :'a'", {"a": adapter})
        _cfg_cache[adapter] = json.loads(r.stdout.strip() or "{}") if r.returncode == 0 else {}
    return _cfg_cache[adapter]


def thread_day_template(row):
    """A CLOSED thread-day with zero detected signal files one templated atom — no LLM pass.
    Signal = any question/commitment/time/link/money pattern, or any sender we cannot resolve
    to a known person (a new handle is a signal)."""
    raw = row["raw"] or ""
    first = raw.splitlines()[0] if raw else ""
    if not first.startswith("[thread-day window"):
        return None
    cm = re.search(r"(\d+) messages in (.+)", first)
    if not cm:
        return None
    count = cm.group(1)
    chat = re.split(r" on \d{4}-\d{2}-\d{2}\]| — |\]", cm.group(2))[0].strip()
    dm = re.search(r" on (\d{4}-\d{2}-\d{2})\]", first)
    day = ((row.get("sender") or {}).get("thread_day") or (dm.group(1) if dm else None)
           or str(row.get("received_at", ""))[:10])
    if not day:
        return None
    senders, bodies = set(), []
    for line in raw.splitlines()[1:]:
        lm = MSG_LINE_RE.match(line)
        if lm:
            senders.add(lm.group(1))
            bodies.append(lm.group(2))
        else:
            bodies.append(line)  # continuation lines are message text
    if any(rx.search("\n".join(bodies)) for rx in SIGNAL_RES):
        return None
    source = (row.get("sender") or {}).get("source", "imessage")
    links, participants = [], []
    for s in sorted(senders):
        if s == "me":
            continue
        r = psql("select ph.person_id from l1.person_handles ph where ph.source = :'s' and ph.handle = :'h'",
                 {"s": source, "h": s})
        pid = r.stdout.strip() if r.returncode == 0 else ""
        if not pid:
            return None  # unknown sender — the model should look at this day
        participants.append(s)
        links.append({"to_type": "person", "to_id": pid, "kind": "participant"})
    role = (component_config(row["adapter"]).get("role_map") or ["general"])[0]
    return {"action": "file", "actions": [{
        "fn": "record_atom",
        "args": {"ts": f"{day}T22:00:00", "kind": "communication",
                 "summary": f"Active day in {chat} ({count} messages) — no questions, commitments, or plans detected.",
                 "primary_role_id": role, "links": links,
                 "meta": {"template": True, "participants": participants}},
    }]}


def _default_role(cfg):
    return cfg.get("default_role") or (cfg.get("role_map") or ["general"])[0]


def gcal_event_template(row, cfg):
    """An ENDED calendar event is a structured fact — pointer + one atom, no judgment needed."""
    ev = json.loads(row["raw"])
    if not (ev.get("event") and ev.get("started") and ev.get("ended")):
        return None
    attendees = f" ({ev['attendees']} attendees)" if ev.get("attendees") else ""
    meta = {"template": True}
    if (cfg.get("semantics") or {}).get("commitment_strength") == "tentative":
        meta["tentative"] = True
    return {"action": "file", "actions": [{"fn": "record_atom", "args": {
        "ts": ev["started"], "ts_end": ev["ended"], "kind": "meeting",
        "summary": f"{ev['event']}{attendees}.",
        "primary_role_id": _default_role(cfg),
        "refs": [{"source": "gcal", "locator": ev.get("id") or row.get("locator"), "tool": row["adapter"]}],
        "meta": meta}}]}


def day_log_template(row, cfg):
    """A structured self-report (date + typed entries) maps to session atoms by config, not judgment."""
    d = json.loads(row["raw"])
    date, entries = d.get("date"), d.get("entries")
    if not (date and isinstance(entries, list) and entries):
        return None
    roles = cfg.get("entry_roles") or {}
    actions = []
    for e in entries:
        etype, start, mins = e.get("type"), e.get("start"), e.get("mins")
        if not (etype and start):
            return None  # shape drifted — let the model look
        h, m = (int(x) for x in start.split(":"))
        end = f"{(h + (m + int(mins or 0)) // 60) % 24:02d}:{(m + int(mins or 0)) % 60:02d}"
        actions.append({"fn": "record_atom", "args": {
            "ts": f"{date}T{start}:00", "ts_end": f"{date}T{end}:00", "kind": "session",
            "summary": f"{etype.replace('_', ' ').capitalize()}: {e.get('note', '')} ({mins} min).",
            "primary_role_id": roles.get(etype, _default_role(cfg)),
            "refs": [{"source": "dashboard", "locator": f"{date}#{etype}-{start.replace(':', '')}", "tool": row["adapter"]}],
            "meta": {"template": True}}})
    return {"action": "file", "actions": actions}


STRUCTURED_TEMPLATES = {"gcal-event": gcal_event_template, "day-log": day_log_template}


def deterministic_decision(row):
    """Returns (decision, path) when no model is needed; (None, None) otherwise."""
    cfg = component_config(row["adapter"])
    sem = cfg.get("semantics") or {}
    for pat in sem.get("discard_patterns", []):
        name, rx = (pat.get("name", "pattern"), pat.get("regex")) if isinstance(pat, dict) else ("pattern", pat)
        if rx and re.search(rx, row["raw"] or "", re.I | re.S):
            return {"action": "discard", "reason": f"pattern:{name}"}, f"deterministic:{name}"
    conv = STRUCTURED_TEMPLATES.get(cfg.get("template"))
    if conv:
        try:
            t = conv(row, cfg)
        except (ValueError, KeyError, TypeError, json.JSONDecodeError):
            t = None  # malformed payload: the model should look at it
        if t:
            return t, f"template:{cfg['template']}"
    t = thread_day_template(row)
    if t:
        return t, "template"
    return None, None


def row_block(row):
    sender = row.get("sender") or {}
    known = known_person(sender)
    lines = [
        f"adapter: {row['adapter']}  received_at: {row['received_at']}  locator: {row.get('locator')}",
        f"sender: {json.dumps(sender)}  known_person: {known or 'NO MATCH'}",
        f"verified_user: {sender.get('verified_user', False)}",
        "<untrusted-raw>",
        row["raw"],
        "</untrusted-raw>",
    ]
    return "\n".join(lines)


def inject_refs(actions, row):
    """Every atom gets a tier-0 ref. A split (2+ atoms from one capture) numbers the
    later locators (#2, #3...) — deterministic by batch position, so replays still dedup
    against atoms_source_locator instead of colliding on it."""
    seen = 0
    for a in actions:
        if a.get("fn") != "record_atom" or not row.get("locator"):
            continue
        seen += 1
        args = a.setdefault("args", {})
        if "refs" not in args:
            args["refs"] = [{"source": row["adapter"],
                             "locator": row["locator"] if seen == 1 else f"{row['locator']}#{seen}"}]
    return actions


def dispatch(row, decision):
    rid = row["id"]
    if decision["action"] == "discard":
        must(psql("select l1.discard_intake((:'id')::uuid, :'reason')",
                  {"id": rid, "reason": str(decision.get("reason", "unspecified"))[:200]}), "discard")
        return "discarded"
    if decision["action"] == "hold":
        q = str(decision.get("question", "The filer needs clarification."))[:500]
        qid = must(psql("select (l1.post_message('user', 'question', jsonb_build_object('summary', :'q', 'intake_id', :'id')))->>'id'",
                        {"q": q, "id": rid}), "post question")
        must(psql("select l1.hold_intake((:'id')::uuid, (:'qid')::uuid)", {"id": rid, "qid": qid}), "hold")
        return "held"
    actions = inject_refs(decision.get("actions", []), row)
    out = must(psql("select l1.file_intake((:'id')::uuid, (:'actions')::jsonb)",
                    {"id": rid, "actions": json.dumps(actions)}), "file_intake")
    if '"quarantined": true' in out or '"quarantined":true' in out:
        print(f"filer: {row.get('locator') or rid}: quarantined batch was: {json.dumps(actions)[:500]}")
        return "quarantined"
    return "filed"


def unknown_fallback(row):
    actions = inject_refs([{
        "fn": "record_atom",
        "args": {"ts": row["received_at"], "kind": "unknown",
                 "summary": row["raw"][:200],
                 "meta": {"filer_parse_failure": True}},
    }], row)
    must(psql("select l1.file_intake((:'id')::uuid, (:'actions')::jsonb)",
              {"id": row["id"], "actions": json.dumps(actions)}), "unknown fallback")
    return "filed-as-unknown"


def main():
    rows_raw = must(psql(
        "select coalesce(jsonb_agg(r order by r->>'received_at'), '[]') from ("
        " select jsonb_build_object('id', id, 'adapter', adapter, 'received_at', received_at,"
        "        'sender', sender, 'raw', raw, 'locator', locator, 'rawness', rawness) as r"
        f" from l1.intake where status = 'pending' order by received_at limit {BATCH}) s"), "fetch pending")
    rows = json.loads(rows_raw or "[]")
    if not rows:
        print("filer: nothing pending")
        return

    system = (DIR / "prompt.md").read_text()
    ambient = ambient_context()

    for row in rows:
        outcome = None
        try:
            decision, path = deterministic_decision(row)
            if decision is None:
                prompt = f"{system}\n\n## Context\n{ambient}\n\n## The capture to file\n{row_block(row)}\n"
                err = ""
                for attempt in (1, 2):
                    try:
                        decision = parse_decision(llm(
                            prompt if attempt == 1
                            else prompt + f"\nYour previous response was invalid ({err}). Respond with ONLY a valid JSON decision object."))
                        break
                    except (ValueError, json.JSONDecodeError) as e:
                        err = str(e)[:200]
                        continue
            outcome = dispatch(row, decision) if decision else unknown_fallback(row)
            if path:
                outcome += f" ({path})"
        except Exception as e:  # a row never kills the filer (poison-pill spirit)
            print(f"filer: {row['locator'] or row['id']}: ERROR {str(e)[:200]}")
            continue
        print(f"filer: {row['locator'] or row['id']}: {outcome}")


if __name__ == "__main__":
    main()
