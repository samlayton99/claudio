#!/usr/bin/env bash
# The watchdog (P6 CRITICAL): pure SQL + filesystem, no LLM, deterministic. Four checks from
# 03 §Reliability — schedule misses (v_run_misses), stuck runs (> 2x trailing median, floored),
# stale posted messages, expired claims (reap_expired_claims) — plus the backup-FAILED marker.
# One alert per incident: every alert carries a watchdog_key; a key that has ever been posted
# never posts again (a NEW incident gets a NEW key). Runs as w_watchdog (clearance 0 — s1
# messages are invisible here; the scanner at c1 owns reminder-critical sweeps).
# The heartbeat file is food for the external dead-man: the alarm must not depend on the db.
set -euo pipefail

PG_BIN="${PG_BIN:-/opt/homebrew/opt/postgresql@17/bin}"
export PGHOST="${PGHOST:-$HOME/.claudio/sock}" PGPORT="${CLAUDIO_PGPORT:-5433}"
ROLE="${CLAUDIO_DB_ROLE:-w_watchdog}"
MARKER="${CLAUDIO_BACKUP_MARKER:-$HOME/.claudio/backup-FAILED}"
HEARTBEAT="${CLAUDIO_WATCHDOG_HEARTBEAT:-$HOME/.claudio/watchdog-heartbeat}"

"$PG_BIN/psql" -U "$ROLE" -d claudio -v ON_ERROR_STOP=1 -tAq <<'SQL' >/dev/null
select l1.reap_expired_claims();

do $$
declare
  stale_h   integer := coalesce((select (value->>'stale_message_hours')::integer from l1.parameters where key = 'watchdog'), 48);
  floor_min integer := coalesce((select (value->>'stuck_floor_min')::integer    from l1.parameters where key = 'watchdog'), 30);
  r record; k text;
begin
  -- 1. schedule misses: enabled scheduled components silent past their declared max_silence_min
  for r in select component_id, reliability, last_run from l1.v_run_misses loop
    k := 'miss:' || r.component_id || ':' || coalesce(r.last_run::text, 'never');
    if not exists (select 1 from l1.messages where payload->>'watchdog_key' = k) then
      perform l1.post_message('user', 'notification', jsonb_build_object(
        'summary', 'Watchdog: ' || r.component_id || ' (' || r.reliability || ') has not run since '
                   || coalesce(to_char(r.last_run, 'Mon DD HH24:MI'), 'ever'),
        'component_id', r.component_id, 'trigger', 'watchdog', 'check', 'miss', 'watchdog_key', k),
        0::smallint, null);
    end if;
  end loop;

  -- 2. stuck runs: unfinished past greatest(2x trailing 7-day median duration, floor)
  for r in
    with med as (
      select component_id,
             percentile_cont(0.5) within group (order by extract(epoch from finished_at - started_at)) as med_s
      from l1.runs where finished_at is not null and started_at > now() - interval '7 days'
      group by component_id)
    select ru.id, ru.component_id, ru.started_at
    from l1.runs ru left join med m using (component_id)
    where ru.finished_at is null
      and now() - ru.started_at > make_interval(secs => greatest(coalesce(2 * m.med_s, 0), floor_min * 60))
  loop
    k := 'stuck:' || r.id;
    if not exists (select 1 from l1.messages where payload->>'watchdog_key' = k) then
      perform l1.post_message('user', 'notification', jsonb_build_object(
        'summary', 'Watchdog: ' || r.component_id || ' run stuck since ' || to_char(r.started_at, 'Mon DD HH24:MI'),
        'component_id', r.component_id, 'run_id', r.id, 'trigger', 'watchdog', 'check', 'stuck', 'watchdog_key', k),
        0::smallint, null);
    end if;
  end loop;

  -- 2b. failed runs, last 24h (P6 failure policy: failures alert, never silently; one alert
  -- per run — a repeatedly failing critical component alerts on every failed run by design)
  for r in
    select id, component_id, started_at, error from l1.runs
    where outcome = 'failed' and started_at > now() - interval '24 hours'
  loop
    k := 'failed:' || r.id;
    if not exists (select 1 from l1.messages where payload->>'watchdog_key' = k) then
      perform l1.post_message('user', 'notification', jsonb_build_object(
        'summary', 'Watchdog: ' || r.component_id || ' run FAILED at ' || to_char(r.started_at, 'Mon DD HH24:MI')
                   || coalesce(': ' || left(r.error, 120), ''),
        'component_id', r.component_id, 'run_id', r.id, 'trigger', 'watchdog', 'check', 'failed', 'watchdog_key', k),
        0::smallint, null);
    end if;
  end loop;

  -- 3. stale posted messages, per queue (oldest row keys the incident; own alerts excluded)
  for r in
    select queue, count(*) as n, min(posted_at) as oldest_at,
           (array_agg(id order by posted_at))[1] as oldest_id
    from l1.messages
    where status = 'posted' and posted_at < now() - make_interval(hours => stale_h)
      and (expires_at is null or expires_at > now())
      and coalesce(payload->>'trigger', '') <> 'watchdog'
    group by queue
  loop
    k := 'stale:' || r.queue || ':' || r.oldest_id;
    if not exists (select 1 from l1.messages where payload->>'watchdog_key' = k) then
      perform l1.post_message('user', 'notification', jsonb_build_object(
        'summary', 'Watchdog: ' || r.n || ' message(s) stale in queue ' || r.queue
                   || ' since ' || to_char(r.oldest_at, 'Mon DD HH24:MI'),
        'queue', r.queue, 'trigger', 'watchdog', 'check', 'stale', 'watchdog_key', k),
        0::smallint, null);
    end if;
  end loop;
end $$;
SQL

# 4. backup-FAILED marker (left by core/pipes/backup/run-live.sh; cleared on next success).
#    Key includes the marker content (a date) — every failed backup is a fresh incident.
if [ -f "$MARKER" ]; then
  K="backup:$(head -1 "$MARKER")"
  "$PG_BIN/psql" -U "$ROLE" -d claudio -v ON_ERROR_STOP=1 -tAq -v k="$K" >/dev/null <<'SQL'
select l1.post_message('user', 'notification', jsonb_build_object(
  'summary', 'Watchdog: backup FAILED (' || :'k' || ') — see ~/.claudio/backup.err',
  'trigger', 'watchdog', 'check', 'backup', 'watchdog_key', :'k'), 0::smallint, null)
where not exists (select 1 from l1.messages where payload->>'watchdog_key' = :'k');
SQL
fi

mkdir -p "$(dirname "$HEARTBEAT")"
date > "$HEARTBEAT"

# external dead-man for the watchdog itself (same convention as the edge: the alarm
# that says "the watchdog died" must not depend on the watchdog or the db)
if [ -n "${CLAUDIO_WATCHDOG_DEADMAN_URL:-}" ]; then
  curl -fsS -m 10 "$CLAUDIO_WATCHDOG_DEADMAN_URL" >/dev/null 2>&1 || true
fi

echo "watchdog: swept"
