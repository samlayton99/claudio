-- 0009: the GV channel edge (Sam's channel decision, 2026-07-19). The conversational
-- channel moves from iMessage-in-the-user's-session to a Google Voice number forwarded to
-- a dedicated Gmail: headless, reboot-proof, no third party in the message path beyond GV
-- itself, user's own Messages account untouched (window-imessage keeps the passive capture).
-- edge-imessage retires as the channel (status only — code and registry row remain; the
-- documented upgrade path back to blue bubbles is a second-user session, specs/06).
set role claudio_core;

insert into l1.components (id, kind, circle, status, definition_path, trigger, config, reliability) values
  ('edge-gv', 'pipe', 'inner', 'disabled', 'core/pipes/edge-gv',
   '{"type":"cron","interval_min":1,"max_silence_min":10}',
   -- account + user_handles are term deploy config (set at go-live, like edge-imessage handles);
   -- db_role w_edge: same trust tier, same queue, same sender-of-record role
   '{"db_role":"w_edge","account":"","user_handles":[],"replayable":true,"default_sensitivity":0}',
   'critical')
on conflict (id) do nothing;

-- the channel of record is edge-gv; edge-imessage stands down (idempotent: seeds start disabled)
update l1.components set status = 'disabled' where id = 'edge-imessage';

reset role;
