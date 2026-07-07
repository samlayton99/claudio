#!/usr/bin/env python3
"""The morning brief / daily pass (P6 CRITICAL, degraded-mode capable).

The scaffold computes; the model phrases (specs/05): sections are ordered by user-set role
weights, obligations by due-date, notables by recorded reason — the skeleton is fully
deterministic and SENDS EVEN IF EVERY MODEL STEP FAILS. The model owns two things only:
optional prose polish of the day-opener line, and the notable judgment (a selection from
the closed notable_reason vocabulary, P12).

Also writes the daily reflection page (documents row + wiki file) and rides the open
hold-questions as a batch. Dedup: one brief per local day.

No prompt.md/context.md in this folder BY DESIGN: the two tiny model prompts are inline
below (the skeleton is deterministic; there is no big prompt to tune). "Tune the brief"
means editing this file, role weights, or directives — not a prompt file.
"""
import datetime
import json
import os
import pathlib
import shlex
import subprocess

DIR = pathlib.Path(__file__).resolve().parent
REPO = DIR.parents[2]
PG_BIN = os.environ.get("PG_BIN", "/opt/homebrew/opt/postgresql@17/bin")
ROLE = os.environ.get("CLAUDIO_DB_ROLE", "w_brief")
LLM_CMD = os.environ.get("CLAUDIO_LLM_CMD", "claude -p")
WIKI = pathlib.Path(os.environ.get("CLAUDIO_WIKI_DIR", str(REPO / "wiki")))


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


def jget(sql, what, vars=None):
    out = must(psql(sql, vars), what)
    return json.loads(out) if out else []


def try_llm(prompt):
    try:
        r = subprocess.run(shlex.split(LLM_CMD), input=prompt, capture_output=True, text=True, timeout=120)
        return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None
    except Exception:
        return None


def fmt_due(iso):
    if not iso:
        return "no due date"
    try:
        dt = datetime.datetime.fromisoformat(iso)
        return dt.strftime("%a %b %d %H:%M")
    except ValueError:
        return iso


def daily_pass_notable(today):
    """The notable judgment: model SELECTS from the closed vocabulary (P12); failures skip silently
    (notable assignment is judgment, not a reminder — P6 does not apply)."""
    candidates = jget(
        "select coalesce(jsonb_agg(jsonb_build_object('id', id, 'summary', summary, 'kind', kind, 'ts', ts)), '[]') "
        "from l1.atoms where canonical_of is null and not notable "
        "and (meta->>'notable_candidate')::boolean is true "
        "and ts >= (current_date - interval '1 day') and ts < current_date + interval '1 day'",
        "notable candidates")
    if not candidates:
        return 0
    vocab = jget("select coalesce(jsonb_agg(jsonb_build_object('key', key, 'description', description)), '[]') "
                 "from l1.kinds where domain = 'notable_reason' and status = 'active'", "vocab")
    prompt = (
        "You judge which of yesterday's flagged moments are truly notable in the context of a whole life. "
        "Be conservative: most days have zero notables.\n"
        f"Closed reason vocabulary (you MUST pick from these keys):\n{json.dumps(vocab)}\n"
        f"Candidates:\n{json.dumps(candidates)}\n"
        'Respond with ONLY a JSON array: [{"id": "<atom id>", "notable": true|false, "reason": "<vocab key, required when notable>"}]'
    )
    out = try_llm(prompt)
    if not out:
        return 0
    try:
        verdicts = json.loads(out[out.find("["):out.rfind("]") + 1])
    except (ValueError, json.JSONDecodeError):
        return 0
    n = 0
    for v in verdicts:
        if v.get("notable") and v.get("reason"):
            r = psql("select l1.amend_atom((:'id')::uuid, jsonb_build_object('notable', true, 'notable_reason', :'reason'))",
                     {"id": v["id"], "reason": v["reason"]})
            if r.returncode == 0:
                n += 1  # junk reasons are rejected by the vocab trigger; the candidate stays correctable
    return n


def main():
    today = datetime.date.today().isoformat()

    # dedup: one brief per local day
    already = must(psql("select count(*) from l1.messages where kind = 'notification' "
                        "and payload->>'brief_date' = :'d'", {"d": today}), "dedup check")
    if already != "0":
        print(f"brief: already sent for {today}")
        return

    # ---- the deterministic packet (the scaffold computes) ----
    roles = jget("select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'weight', weight) "
                 "order by weight desc), '[]') from l1.roles where status = 'active'", "roles")
    tasks = jget("select l1.due_tasks('{}')", "due_tasks")
    exps = jget("select l1.pending_expectations('{}')", "pending_expectations")
    questions = jget("select coalesce(jsonb_agg(jsonb_build_object('id', id, 'q', payload->>'summary') order by posted_at), '[]') "
                     "from l1.messages where queue = 'user' and kind = 'question' and status = 'posted'", "questions")
    y_atoms = jget("select coalesce(jsonb_agg(jsonb_build_object('summary', summary, 'kind', kind, "
                   "'role', primary_role_id, 'notable', notable, 'reason', notable_reason) order by ts), '[]') "
                   "from l1.atoms where canonical_of is null "
                   "and ts >= current_date - interval '1 day' and ts < current_date", "yesterday")

    # the daily pass: judge notable candidates BEFORE rendering, so today's brief reflects it
    n_notable = daily_pass_notable(today)
    if n_notable:
        y_atoms = jget("select coalesce(jsonb_agg(jsonb_build_object('summary', summary, 'kind', kind, "
                       "'role', primary_role_id, 'notable', notable, 'reason', notable_reason) order by ts), '[]') "
                       "from l1.atoms where canonical_of is null "
                       "and ts >= current_date - interval '1 day' and ts < current_date", "yesterday refresh")

    # ---- the skeleton (deterministic; survives total model failure) ----
    human_date = datetime.date.today().strftime("%a %b %d")
    lines = [f"Good morning — {human_date}."]
    if tasks:
        lines.append("")
        lines.append(f"DUE ({len(tasks)}):")
        for t in tasks[:10]:
            overdue = " [OVERDUE]" if t.get("overdue") else ""
            lines.append(f"- {t['name']} — {fmt_due(t.get('due'))}{overdue}")
    if exps:
        lines.append("")
        lines.append(f"WAITING ON ({len(exps)}):")
        for e in exps[:10]:
            who = (e.get("person") or {}).get("name")
            lines.append(f"- {e['name']}" + (f" ({who})" if who else ""))
    if questions:
        lines.append("")
        lines.append(f"QUESTIONS FOR YOU ({len(questions)}):")
        for i, q in enumerate(questions[:5], 1):
            lines.append(f"{i}. {q['q']}")
    notables = [a for a in y_atoms if a.get("notable")]
    lines.append("")
    lines.append(f"YESTERDAY: {len(y_atoms)} moments recorded" + (f", {len(notables)} notable:" if notables else "."))
    for a in notables:
        lines.append(f"* {a['summary']} ({a.get('reason')})")
    skeleton = "\n".join(lines)

    # ---- optional polish: the model may rephrase the OPENER line only (never ordering/inclusion) ----
    brief = skeleton
    opener = try_llm("Rewrite this morning-brief opener as one warm, direct sentence (no emojis, "
                     f"no exclamation marks). Respond with the sentence only.\n{lines[0]}\n"
                     f"Context: {len(tasks)} due, {len(questions)} open questions.")
    if opener and "\n" not in opener and len(opener) < 200:
        brief = "\n".join([opener] + lines[1:])

    # ---- send (always) ----
    must(psql("select l1.post_message('user', 'notification', "
              "jsonb_build_object('summary', :'b', 'brief_date', :'d', 'workflow', 'brief'))",
              {"b": brief, "d": today}), "post brief")

    # ---- the daily reflection page (1:1 documents row + wiki file) ----
    page_rel = f"cadences/daily/{today}.md"
    page_abs = WIKI / page_rel
    page_abs.parent.mkdir(parents=True, exist_ok=True)
    if not page_abs.exists():
        body = [f"# {human_date}", "", f"{len(y_atoms)} moments recorded."]
        for a in y_atoms:
            mark = " **notable: " + a["reason"] + "**" if a.get("notable") else ""
            body.append(f"- ({a.get('kind')}/{a.get('role') or 'general'}) {a['summary']}{mark}")
        page_abs.write_text("\n".join(body) + "\n")
        r = psql("select l1.register_page(:'p', 'digest', :'t', 'cadences', null, null, "
                 "'tomorrow morning, and any agent asking about this day')",
                 {"p": f"wiki/{page_rel}", "t": f"Daily — {today}"})
        if r.returncode != 0:
            print(f"brief: page registration failed (file written): {r.stderr.strip()[:200]}")

    print(f"brief: sent for {today} ({len(tasks)} due, {len(questions)} questions, {n_notable} notables judged)")


if __name__ == "__main__":
    main()
