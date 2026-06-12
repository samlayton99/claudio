#!/usr/bin/env bash
# Edge component tests: fixture chat.db, echo send mode, spool round-trip. Run after dev.sh reset.
set -uo pipefail
source "$(dirname "$0")/../red-team/lib.sh"
DIR="$(cd "$(dirname "$0")" && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CLAUDIO_CHATDB="$TMP/chat.db" CLAUDIO_STATE_DIR="$TMP/state" CLAUDIO_SPOOL_DIR="$TMP/spool"
export CLAUDIO_EDGE_SEND=echo

echo "== edge: build fixture chat.db =="
sqlite3 "$CLAUDIO_CHATDB" <<'SQL'
create table handle (ROWID integer primary key, id text);
create table chat (ROWID integer primary key, chat_identifier text);
create table message (ROWID integer primary key, guid text, text text, handle_id integer, date integer, is_from_me integer);
create table chat_message_join (chat_id integer, message_id integer);
insert into handle values (1, '+14155550130'), (2, '+19995550000');
insert into chat values (1, 'self-sam'), (2, '+14155550130'), (3, 'group-unwatched');
insert into message values
  (1, 'g-001', 't: pick up Jamie''s prescription before 6', null, 0, 1),
  (2, 'g-002', 'line one' || char(10) || 'line two', 1, 0, 0),
  (3, 'g-003', 'should never be captured', 2, 0, 0);
insert into chat_message_join values (1, 1), (2, 2), (3, 3);
SQL

echo "== edge: configure the term (watch list + user handle) =="
expect_ok "set-config" claudio_core "update l1.components set config = config || '{\"watch\":[\"self-sam\",\"+14155550130\"],\"user_handles\":[\"+14355550100\"]}' where id = 'edge-imessage'"

echo "== edge: inbound sweep (capture-first) =="
"$DIR/main.sh" >/dev/null
expect_eq "captured-watched"   claudio_core "select count(*) from l1.intake where adapter = 'edge-imessage'" "2"
expect_eq "unwatched-excluded" claudio_core "select count(*) from l1.intake where raw like '%never be captured%'" "0"
expect_eq "from-me-verified"   claudio_core "select sender->>'verified_user' from l1.intake where locator = 'imsg-g-001'" "true"
expect_eq "stranger-unverified" claudio_core "select sender->>'verified_user' from l1.intake where locator = 'imsg-g-002'" "false"
expect_eq "newline-verbatim"   claudio_core "select raw from l1.intake where locator = 'imsg-g-002'" "line one
line two"

echo "== edge: second sweep is a no-op (cursor + locator dedup) =="
"$DIR/main.sh" >/dev/null
expect_eq "no-dupes" claudio_core "select count(*) from l1.intake where adapter = 'edge-imessage'" "2"

echo "== edge: incremental message gets picked up =="
sqlite3 "$CLAUDIO_CHATDB" "insert into message values (4, 'g-004', 'm: met Daniel at the mixer', null, 0, 1); insert into chat_message_join values (1, 4);"
"$DIR/main.sh" >/dev/null
expect_eq "incremental" claudio_core "select count(*) from l1.intake where locator = 'imsg-g-004'" "1"

echo "== edge: outbound drain (echo mode) =="
MID=$(sql claudio_panel "select (l1.post_message('user', 'notification', '{\"summary\":\"Task due Fri 09:00: Send agenda\"}'))->>'id'")
"$DIR/main.sh" >/dev/null
expect_eq "delivered-resolved" claudio_core "select status from l1.messages where id = '$MID'::uuid" "done"
if grep -q "Task due Fri 09:00" "$CLAUDIO_STATE_DIR/sent.log"; then PASS=$((PASS+1)); echo "PASS  sent-log-has-text";
else FAIL=$((FAIL+1)); FAILED_NAMES+=("sent-log-has-text"); echo "FAIL  sent-log-has-text"; fi

echo "== edge: spool when db is unreachable, replay on reconnect =="
sqlite3 "$CLAUDIO_CHATDB" "insert into message values (5, 'g-005', 'captured during outage', null, 0, 1); insert into chat_message_join values (1, 5);"
CLAUDIO_PGPORT=59999 python3 "$DIR/inbound.py" >/dev/null 2>&1 || true
if [ -s "$CLAUDIO_SPOOL_DIR/edge.jsonl" ]; then PASS=$((PASS+1)); echo "PASS  outage-spooled";
else FAIL=$((FAIL+1)); FAILED_NAMES+=("outage-spooled"); echo "FAIL  outage-spooled"; fi
"$DIR/main.sh" >/dev/null
expect_eq "spool-replayed" claudio_core "select count(*) from l1.intake where locator = 'imsg-g-005'" "1"
if [ ! -s "$CLAUDIO_SPOOL_DIR/edge.jsonl" ]; then PASS=$((PASS+1)); echo "PASS  spool-drained";
else FAIL=$((FAIL+1)); FAILED_NAMES+=("spool-drained"); echo "FAIL  spool-drained"; fi

echo ""
echo "==== $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
