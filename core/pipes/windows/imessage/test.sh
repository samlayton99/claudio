#!/usr/bin/env bash
# window-imessage tests: thread-day grouping, closed-day-only, exclusion, dedup. Run after dev.sh reset.
set -uo pipefail
source "$(dirname "$0")/../../red-team/lib.sh"
DIR="$(cd "$(dirname "$0")" && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CLAUDIO_CHATDB="$TMP/chat.db" CLAUDIO_STATE_DIR="$TMP/state"

# apple-epoch timestamps (ns) for yesterday noon/evening and today noon, local time
read Y_NOON Y_EVE T_NOON YDAY <<<"$(python3 - <<'PY'
import datetime
APPLE=978307200
today=datetime.date.today(); yday=today-datetime.timedelta(days=1)
def ns(d,h): return int((datetime.datetime.combine(d,datetime.time(h)).timestamp()-APPLE)*1_000_000_000)
print(ns(yday,12), ns(yday,20), ns(today,12), yday.isoformat())
PY
)"

echo "== window-imessage: fixture =="
sqlite3 "$CLAUDIO_CHATDB" <<SQL
create table handle (ROWID integer primary key, id text);
create table chat (ROWID integer primary key, chat_identifier text);
create table message (ROWID integer primary key, guid text, text text, handle_id integer, date integer, is_from_me integer);
create table chat_message_join (chat_id integer, message_id integer);
insert into handle values (1, '+14155550130'), (2, '+18885550111');
insert into chat values (1, 'group-sibs'), (2, 'self-sam');
insert into message values
  (1, 'd-001', 'look at this meme', 1, $Y_NOON, 0),
  (2, 'd-002', 'hahaha', 2, $((Y_NOON + 60000000000)), 0),
  (3, 'd-003', 'one more', null, $Y_EVE, 1),
  (4, 'd-004', 'today msg must not sweep', 1, $T_NOON, 0),
  (5, 'd-005', 'excluded chat yesterday', null, $Y_NOON, 1);
insert into chat_message_join values (1,1),(1,2),(1,3),(1,4),(2,5);
SQL
expect_ok "set-config" claudio_core "update l1.components set config = config || '{\"watch\":[\"*\"],\"exclude\":[\"self-sam\"],\"days_back\":3}' where id = 'window-imessage'"

echo "== window-imessage: sweep =="
python3 "$DIR/sweep.py" >/dev/null
expect_eq "one-chat-day"     claudio_core "select count(*) from l1.intake where adapter = 'window-imessage'" "1"
expect_eq "locator"          claudio_core "select locator from l1.intake where adapter = 'window-imessage'" "imsg-day-group-sibs-$YDAY"
expect_eq "transcript-lines" claudio_core "select count(*) from l1.intake where adapter = 'window-imessage' and raw like '%meme%' and raw like '%hahaha%' and raw like '%one more%'" "1"
expect_eq "header-count"     claudio_core "select count(*) from l1.intake where raw like '[thread-day window: 3 messages in group-sibs%'" "1"
expect_eq "senders-in-lines" claudio_core "select count(*) from l1.intake where adapter = 'window-imessage' and raw like '%+14155550130: look at this meme%' and raw like '%me: one more%'" "1"
expect_eq "today-not-swept"  claudio_core "select count(*) from l1.intake where raw like '%must not sweep%'" "0"
expect_eq "excluded-skipped" claudio_core "select count(*) from l1.intake where raw like '%excluded chat yesterday%'" "0"

echo "== window-imessage: replay-safe (locator dedup) =="
python3 "$DIR/sweep.py" >/dev/null
expect_eq "no-dupes" claudio_core "select count(*) from l1.intake where adapter = 'window-imessage'" "1"

echo ""
echo "==== $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
