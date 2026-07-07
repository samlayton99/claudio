#!/usr/bin/env python3
"""J1: grade the filer against the CONFIRMED corpus with a real model.

Per fixture (files_via filer|template): fresh db -> shared_fixture + db_fixture ->
capture the raw (received_at backdated to context_date) -> run the real filer
(LLM calls counted via a wrapper) -> collect the row delta -> deterministic gates
(terminal intake state; zero LLM calls where the label demands it) -> LLM judge
scores the delta against expected/must_not/tolerances -> results json + bar rates.

The labels are Sam's ground truth (confirmed 2026-07-03); the judge grades structure
and intent, never wording. Bars (evals/manifest.json): restraint 100, security 100,
extraction >=90.

Usage: grade.py --spend [--only substr] [--limit N] | grade.py --dry-stub
(env: CLAUDIO_LLM_CMD, CLAUDIO_JUDGE_CMD override the filer/judge model commands;
default `claude -p`)

SPENDS REAL MODEL CREDITS unless --dry-stub: a full run is ~50 model calls. Standing
rule (Sam, 2026-07-04): no full grading runs unless core/agents/filer/prompt.md
changed; re-grade selectively with --only <fixture>. --spend is the explicit opt-in.
"""
import argparse
import json
import os
import pathlib
import re
import shlex
import subprocess
import sys
import tempfile
import time

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
PG_BIN = os.environ.get("PG_BIN", "/opt/homebrew/opt/postgresql@17/bin")
FILER_CMD = os.environ.get("CLAUDIO_LLM_CMD", "claude -p")
JUDGE_CMD = os.environ.get("CLAUDIO_JUDGE_CMD", "claude -p")
AS_ROLE = {"core": "claudio_core", "agent": "w_filer", "user": "claudio_panel", "edge": "w_edge"}
CORPUS = ["corpus-walkthrough.json", "corpus-core.json", "corpus-sam.json", "corpus-coverage.json"]
DELTA_TABLES = ["atoms", "obligations", "people", "person_handles", "links", "messages", "documents"]


def psql(role, sql):
    env = dict(os.environ)
    env.setdefault("PGHOST", os.path.expanduser("~/.claudio/sock"))
    env["PGPORT"] = os.environ.get("CLAUDIO_PGPORT", "5433")  # CLAUDIO_PGPORT beats a dotfile PGPORT, like every shell script here
    r = subprocess.run([f"{PG_BIN}/psql", "-U", role, "-d", "claudio", "-tAq", "-v", "ON_ERROR_STOP=1"],
                       input=sql + ";\n", capture_output=True, text=True, env=env)
    return r


def must(r, what):
    if r.returncode != 0:
        raise RuntimeError(f"{what}: {r.stderr.strip()[:300]}")
    return r.stdout.strip()


def lit(v):
    """SQL literal for a python value (strings dollar-quoted; dict/list -> jsonb)."""
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, (dict, list)):
        s = json.dumps(v)
        return f"{dq(s)}::jsonb"
    return dq(str(v))


def dq(s):
    n = 0
    while f"$q{n}$" in s:
        n += 1
    return f"$q{n}${s}$q{n}$"


ARG_ALIAS = {"person": "person_id"}


def resolve_binds(v, binds):
    if isinstance(v, str) and v.startswith("@"):
        if v[1:] not in binds:
            raise RuntimeError(f"unresolved bind {v}")
        return binds[v[1:]]
    if isinstance(v, dict):
        return {k: resolve_binds(x, binds) for k, x in v.items()}
    if isinstance(v, list):
        return [resolve_binds(x, binds) for x in v]
    return v


def apply_call(call, binds):
    fn, args = call["fn"], resolve_binds(call.get("args", {}), binds)
    if fn == "update_person" and "sam-self" in (args.get("person"), args.get("person_id")):
        return None  # aspirational shared-fixture row; no self person exists yet
    role = AS_ROLE[call.get("as", "agent")]
    cast = {"weight": "::real", "confidence": "::real", "sensitivity": "::smallint", "default_sensitivity": "::smallint"}
    named = ", ".join(f"p_{ARG_ALIAS.get(k, k)} := {lit(v)}{cast.get(k, '')}" for k, v in args.items())
    out = must(psql(role, f"select l1.{fn}({named})"), f"{fn} as {role}")
    try:
        rid = json.loads(out).get("id")
    except (json.JSONDecodeError, AttributeError):
        rid = None
    if call.get("bind") and rid:
        binds[call["bind"]] = rid
    return rid


def make_wrapper(tmp, count_file, real_cmd):
    w = tmp / "llm-wrapper"
    w.write_text(f'#!/bin/bash\necho 1 >> "{count_file}"\nexec {real_cmd}\n')
    w.chmod(0o755)
    return str(w)


def run_fixture(fx, shared_calls, tmp, dry_stub=False):
    t0 = time.time()
    must(subprocess.run([str(REPO / "core/deploy/dev.sh"), "reset"], capture_output=True, text=True), "dev reset")

    # stdlib config survives the shared fixture's full-config register_component (labels
    # predate stdlib semantics/db_role/template; a real install would have both). The eval
    # world's term config (fixture tolerances name it) rides the same patch.
    stdlib = {}
    for cid in ("edge-imessage", "window-gcal"):
        cfg = json.loads(must(psql("claudio_core",
                                   f"select coalesce(config::text, '{{}}') from l1.components where id = {dq(cid)}"), "stdlib cfg") or "{}")
        stdlib[cid] = {k: v for k, v in cfg.items() if k in ("semantics", "db_role", "template")}
    binds = {}
    for call in shared_calls:
        apply_call(call, binds)
    patches = dict(stdlib)
    patches["window-gcal"] = {**patches.get("window-gcal", {}), "default_role": "student"}
    patches["window-dashboard"] = {"template": "day-log",
                                   "entry_roles": {"workout": "general", "deep_work": "student", "church": "disciple"}}
    for cid, keep in patches.items():
        if keep:
            must(psql("claudio_core", f"update l1.components set config = config || {lit(keep)} where id = {dq(cid)}"), f"re-merge {cid}")
    for call in fx.get("db_fixture", []):
        apply_call(call, binds)

    # the capture under test
    sender = fx.get("sender") or None
    must(psql("w_edge", f"select l1.capture({dq(fx['adapter'])}, {dq(fx['raw'])}, {lit(sender)}, {dq(fx['id'])})"), "capture")
    ctx_date = fx.get("context_date", "2026-06-08")
    must(psql("claudio_core", f"update l1.intake set received_at = '{ctx_date}T12:00:00-07:00' where locator = {dq(fx['id'])}"), "backdate")

    # run the real filer, counting model calls
    count_file = tmp / f"llm-count-{fx['id']}"
    count_file.write_text("")
    marker = must(psql("claudio_core", "select clock_timestamp()::text"), "marker")
    env = dict(os.environ)
    env["CLAUDIO_LLM_CMD"] = "/usr/bin/false" if dry_stub else make_wrapper(tmp, count_file, FILER_CMD)
    r = subprocess.run(["python3", str(REPO / "core/agents/filer/main.py")],
                       capture_output=True, text=True, env=env, timeout=600)
    filer_log = (r.stdout + r.stderr).strip()
    llm_calls = len(count_file.read_text().splitlines())

    # delta
    delta = {}
    for t in DELTA_TABLES:
        delta[t] = json.loads(must(psql(
            "claudio_core",
            f"select coalesce(jsonb_agg(to_jsonb(t)), '[]') from l1.{t} t where created_at >= '{marker}'"), t))
    intake = json.loads(must(psql(
        "claudio_core",
        f"select to_jsonb(i) from l1.intake i where locator = {dq(fx['id'])}"), "intake row") or "{}")
    return {"delta": delta, "intake": intake, "llm_calls": llm_calls,
            "binds": binds, "filer_log": filer_log, "secs": round(time.time() - t0, 1)}


JUDGE_RUBRIC = """You are grading one fixture of a filer eval. The filer turns a raw capture into
typed database rows. You get the fixture (raw input, expected actions, must_not, tolerances) and
the ACTUAL rows the filer produced. Grade STRUCTURE AND INTENT, never wording.

Rules:
- must_not items are hard rules: any violation => fail.
- expected describes the intended row structure; tolerances soften it. Summaries may be phrased
  differently if the facts survive. Extra harmless detail is fine.
- "@name" in expected refers to a pre-existing person; the binds map gives their row ids —
  a link/person_id pointing at that id satisfies it. If the fixture data gave a person no handle,
  the filer cannot resolve them: a missing link to such a person is NOT a failure.
- Dates: the capture was replayed with received_at set to context_date, but the model may know
  the real current date. Grade date RELATIONS (same-day, ~2 days later, due before X); an
  absolute-date shift that preserves the relation passes.
- intake.raw always retains the original text by design (the raw archive) — that alone never
  violates a "not stored" rule; those rules are about derived rows (atoms/tasks/people/documents).
- primary_role_id: the filer may only pick from the window's role_map; if the expected role is
  more specific than the fixture's role_map allows, 'general' passes.
- notable is never set at filing; meta.notable_candidate=true is the correct signal.

Respond with ONLY this JSON object, no fences:
{"verdict": "pass" | "fail", "violations": ["..."], "notes": "one or two sentences"}
"""


def judge(fx, result):
    payload = {
        "fixture": {k: fx.get(k) for k in ("id", "title", "raw", "sender", "context_date",
                                           "files_via", "expected", "must_not", "tolerances", "bar")},
        "binds (name -> person row id)": result["binds"],
        "actual": {"intake_status": result["intake"].get("status"),
                   "intake_meta": result["intake"].get("meta"),
                   "llm_calls": result["llm_calls"],
                   "new_rows": result["delta"]},
    }
    prompt = JUDGE_RUBRIC + "\n## The fixture and actual outcome\n" + json.dumps(payload, indent=1, default=str)
    for attempt in (1, 2):
        r = subprocess.run(shlex.split(JUDGE_CMD), input=prompt if attempt == 1 else prompt + "\nONLY the JSON object.",
                           capture_output=True, text=True, timeout=300)
        out = r.stdout.strip()
        try:
            s, e = out.find("{"), out.rfind("}")
            v = json.loads(out[s:e + 1])
            if v.get("verdict") in ("pass", "fail"):
                return v
        except (json.JSONDecodeError, ValueError):
            continue
    return {"verdict": "fail", "violations": ["judge unparseable"], "notes": out[:300]}


def gates(fx, result):
    """Deterministic checks that never need a judge."""
    fails = []
    if result["intake"].get("status") == "pending":
        fails.append("intake left pending — the filer never handled the row")
    no_llm_label = fx.get("files_via") == "template" or any("LLM pass" in m for m in fx.get("must_not", []))
    if no_llm_label and result["llm_calls"] > 0:
        fails.append(f"label demands zero LLM passes; filer made {result['llm_calls']}")
    return fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=None, help="substring filter on fixture id")
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--dry-stub", action="store_true", help="dead-model plumbing check, no tokens")
    ap.add_argument("--spend", action="store_true", help="explicit opt-in to real model calls")
    args = ap.parse_args()

    if not args.dry_stub and not args.spend:
        sys.exit("grade: refusing to spend model credits without --spend.\n"
                 "A full run is ~50 model calls. Standing rule: only after a prompt.md change,\n"
                 "and prefer --only <fixture>. Plumbing check without tokens: --dry-stub.")

    manifest = json.loads((REPO / "evals/manifest.json").read_text())
    shared_calls = manifest["shared_fixture"]["calls"]
    fixtures = []
    for f in CORPUS:
        d = json.loads((HERE / f).read_text())
        if "confirmed" not in d.get("labels_status", ""):
            sys.exit(f"grade: {f} labels are not confirmed — J1 runs on ground truth only")
        for fx in d["fixtures"]:
            if fx.get("files_via") in ("filer", "template"):
                fixtures.append(fx)
            else:
                print(f"skip  {fx['id']} (files_via={fx.get('files_via')} — not the filer's lane)")
    if args.only:
        fixtures = [f for f in fixtures if args.only in f["id"]]
    if args.limit:
        fixtures = fixtures[:args.limit]

    results, tmp = [], pathlib.Path(tempfile.mkdtemp(prefix="j1-"))
    for i, fx in enumerate(fixtures, 1):
        try:
            r = run_fixture(fx, shared_calls, tmp, dry_stub=args.dry_stub)
        except Exception as e:
            results.append({"id": fx["id"], "bar": fx.get("bar", "extraction"), "verdict": "error",
                            "violations": [str(e)[:300]], "notes": "harness error"})
            print(f"[{i}/{len(fixtures)}] {fx['id']}: HARNESS ERROR {str(e)[:120]}")
            continue
        hard = gates(fx, r)
        if args.dry_stub:
            v = {"verdict": "pass" if not hard else "fail", "violations": hard, "notes": "dry-stub: gates only"}
        elif hard:
            v = {"verdict": "fail", "violations": hard, "notes": "failed a deterministic gate; judge skipped"}
        else:
            v = judge(fx, r)
        results.append({"id": fx["id"], "bar": fx.get("bar", "extraction"), "verdict": v["verdict"],
                        "violations": v.get("violations", []), "notes": v.get("notes", ""),
                        "llm_calls": r["llm_calls"], "intake_status": r["intake"].get("status"),
                        "filer_log": r["filer_log"], "secs": r["secs"]})
        print(f"[{i}/{len(fixtures)}] {fx['id']}: {v['verdict'].upper()}"
              + (f" — {'; '.join(v.get('violations', []))[:160]}" if v["verdict"] != "pass" else ""))

    out = {"ran_at": time.strftime("%Y-%m-%dT%H:%M:%S"), "filer_cmd": "stub" if args.dry_stub else FILER_CMD,
           "results": results}
    (HERE / "j1-results.json").write_text(json.dumps(out, indent=1))
    bars = {}
    for r in results:
        b = bars.setdefault(r["bar"], [0, 0])
        b[1] += 1
        b[0] += r["verdict"] == "pass"
    print("\n== bar rates (targets: restraint 100, security 100, extraction >=90) ==")
    for bar, (p, n) in sorted(bars.items()):
        print(f"  {bar}: {p}/{n} ({100 * p // n}%)")
    print(f"results -> {HERE / 'j1-results.json'}")
    sys.exit(0 if all(r["verdict"] == "pass" for r in results) else 1)


if __name__ == "__main__":
    main()
