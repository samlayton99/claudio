#!/usr/bin/env python3
"""Purpose-contract seeder: parses the SIGNED purpose-contract.md + roles.json and
emits the L1 calls (SQL on stdout) that seed the term. Never invents content:
APPROVE/APPROVED rows seed verbatim, DRAFT rows are skipped loudly, an unsigned
contract refuses to seed at all. Idempotent: purpose/roles upsert; the priorities
document only gets a new version when the body actually changed.

Usage: seed.py [contract.md] [roles.json]   (defaults: files next to this script)
Pipe the output through psql as claudio_core in one transaction (see seed.sh).
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ID_PREFIX = {"goal": "goal-", "value": "value-", "attribute": "attr-"}
ROW_RE = re.compile(r"^### (goal|value|attribute): ([a-z0-9-]+) \[([A-Z]+)\]\s*$")
FIELD_RE = re.compile(r"^- (horizon|statement|watchable markers|goalposts): (.+)$")


def die(msg):
    print(f"seed: {msg}", file=sys.stderr)
    sys.exit(1)


def q(text):
    """Dollar-quote text with a tag guaranteed absent from it."""
    n = 0
    while f"$s{n}$" in text:
        n += 1
    return f"$s{n}${text}$s{n}$"


def parse_contract(path):
    raw = path.read_text()
    if not re.search(r"^- \[x\] Signed by Sam", raw, re.M):
        die(f"{path.name} is NOT signed (signature box unchecked) — refusing to seed the apex contract")
    body = re.sub(r"<!--.*?-->", "", raw, flags=re.S)

    rows, skipped, current = [], [], None
    for line in body.splitlines():
        m = ROW_RE.match(line)
        if m:
            kind, slug, tag = m.groups()
            current = {"kind": kind, "slug": slug, "tag": tag, "fields": {}}
            if tag in ("APPROVE", "APPROVED"):  # Sam tags by hand; both spellings are approval
                rows.append(current)
            elif tag == "DRAFT":
                skipped.append(f"{kind}:{slug}")
                current = None
            else:
                die(f"unknown row tag [{tag}] on {kind}:{slug}")
            continue
        m = FIELD_RE.match(line)
        if m and current is not None:
            current["fields"][m.group(1)] = m.group(2).strip()

    for r in rows:
        if "statement" not in r["fields"]:
            die(f"{r['kind']}:{r['slug']} has no statement")
        if r["kind"] == "goal" and r["fields"].get("horizon") not in ("life", "year", "quarter"):
            die(f"goal:{r['slug']} horizon must be life|year|quarter")

    m = re.search(r"^## Priorities\s*$(.*?)^## ", body, re.M | re.S)
    if not m:
        die("no ## Priorities section found")
    priorities = m.group(1).strip()
    if not priorities:
        die("## Priorities section is empty")
    return rows, skipped, priorities


def markers_to_goalposts(text):
    sep = ";" if ";" in text else ","
    return [p.strip().rstrip(".") for p in text.split(sep) if p.strip()]


def emit(rows, skipped, priorities, roles):
    out = ["begin;"]
    ids = []
    for r in rows:
        f = r["fields"]
        pid = ID_PREFIX[r["kind"]] + r["slug"]
        ids.append(pid)
        markers = f.get("goalposts") or f.get("watchable markers")
        goalposts = json.dumps(markers_to_goalposts(markers)) if markers else "[]"
        horizon = q(f["horizon"]) if r["kind"] == "goal" else "null"
        out.append(
            f"select l1.upsert_purpose({q(pid)}, {q(r['kind'])}, {q(f['statement'])}, "
            f"{horizon}, {q(goalposts)}::jsonb, 'active');"
        )
    # priorities document: append a version only when the body changed (idempotent re-runs)
    out.append(
        "select case when (select body from l1.purpose_versions order by version desc limit 1) "
        f"is not distinct from {q(priorities)} then '\"priorities unchanged\"'::jsonb "
        f"else l1.new_purpose_version({q(priorities)}) end;"
    )
    for role in roles:
        weight = "null::real" if role.get("weight") is None else f"{role['weight']}::real"
        sens = int(role.get("default_sensitivity", 0))
        out.append(
            f"select l1.upsert_role({q(role['id'])}, {q(role['name'])}, {weight}, {sens}::smallint);"
        )
    # drift report: active purpose rows the signed contract no longer contains (never auto-retired)
    in_list = ", ".join(q(i) for i in ids)
    out.append(
        f"select 'DRIFT (in db, not in signed contract): ' || id from l1.purpose "
        f"where status = 'active' and id not in ({in_list});"
    )
    out.append("commit;")
    for s in skipped:
        print(f"seed: SKIPPED DRAFT row {s} (not Sam's words yet)", file=sys.stderr)
    print("\n".join(out))


def main():
    contract = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "purpose-contract.md"
    roles_path = Path(sys.argv[2]) if len(sys.argv) > 2 else HERE / "roles.json"
    rows, skipped, priorities = parse_contract(contract)
    roles = json.loads(roles_path.read_text())["roles"]
    emit(rows, skipped, priorities, roles)


if __name__ == "__main__":
    main()
