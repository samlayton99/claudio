#!/usr/bin/env python3
"""The filer worker: pending intake -> one LLM judgment per row -> file_intake/discard/hold.

Plumbing is deterministic code; the model only judges (P12 spirit):
- tier-0 refs are INJECTED into every record_atom (the model cannot forget provenance)
- parse failure files the honest default (kind=unknown atom) after one retry — a row is
  never left to retry forever, and nothing is silently dropped
- file_intake's own poison-pill quarantine catches bad batches row-by-row

LLM command comes from CLAUDIO_LLM_CMD (default `claude -p`); tests inject a stub.
"""
import json
import os
import pathlib
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
    r = subprocess.run(shlex.split(LLM_CMD), input=prompt, capture_output=True, text=True, timeout=180)
    if r.returncode != 0:
        raise RuntimeError(f"llm failed: {r.stderr.strip()[:300]}")
    return r.stdout


def parse_decision(out):
    """Find the decision object in model output; raises on anything unusable."""
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
    return d


def ambient_context():
    ctx = os.environ.get("CLAUDIO_CONTEXT", "")
    if ctx.strip():
        return ctx
    roles = must(psql("select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name)), '[]') from l1.roles where status = 'active'"), "roles")
    tasks = must(psql("select l1.due_tasks('{}')"), "due_tasks")
    exps = must(psql("select l1.pending_expectations('{}')"), "pending_expectations")
    return f"Active roles: {roles}\nOpen tasks: {tasks}\nPending expectations: {exps}"


def known_person(sender):
    if not sender or not sender.get("handle") or sender.get("handle") == "me":
        return "the user himself" if sender and sender.get("handle") == "me" else None
    r = psql("select p.name from l1.person_handles ph join l1.people p on p.id = ph.person_id "
             "where ph.source = :'s' and ph.handle = :'h'",
             {"s": sender.get("source", ""), "h": sender["handle"]})
    return r.stdout.strip() or None if r.returncode == 0 else None


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
    for a in actions:
        if a.get("fn") == "record_atom" and row.get("locator"):
            a.setdefault("args", {}).setdefault("refs", [{"source": row["adapter"], "locator": row["locator"]}])
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
    return "quarantined" if '"quarantined": true' in out or '"quarantined":true' in out else "filed"


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
        prompt = f"{system}\n\n## Context\n{ambient}\n\n## The capture to file\n{row_block(row)}\n"
        outcome = None
        try:
            decision = None
            for attempt in (1, 2):
                try:
                    decision = parse_decision(llm(prompt if attempt == 1 else prompt + "\nRespond with ONLY the JSON decision object."))
                    break
                except (ValueError, json.JSONDecodeError):
                    continue
            outcome = dispatch(row, decision) if decision else unknown_fallback(row)
        except Exception as e:  # a row never kills the filer (poison-pill spirit)
            print(f"filer: {row['locator'] or row['id']}: ERROR {str(e)[:200]}")
            continue
        print(f"filer: {row['locator'] or row['id']}: {outcome}")


if __name__ == "__main__":
    main()
