#!/usr/bin/env bash
# END-TO-END SMOKE: one story through every hop of the daily loop —
# seed (signed contract) -> edge inbound (fixture chat.db) -> filer (stub LLM) ->
# scanner -> brief -> edge outbound (echo). Every hop is proven alone in its own
# suite; this catches contract drift BETWEEN them. Run after dev.sh reset.
set -uo pipefail
source "$(dirname "$0")/../../core/pipes/red-team/lib.sh"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CLAUDIO_CHATDB="$TMP/chat.db" CLAUDIO_STATE_DIR="$TMP/state" CLAUDIO_SPOOL_DIR="$TMP/spool"
export CLAUDIO_WIKI_DIR="$TMP/wiki" CLAUDIO_EDGE_SEND=echo

# One stub serves both LLM consumers. Order matters: the brief's notable prompt
# quotes atom summaries, which contain the capture text — match it first.
cat > "$TMP/stub-llm" <<'STUB'
#!/usr/bin/env bash
IN="$(cat)"
if echo "$IN" | grep -q "Closed reason vocabulary"; then
  echo '[]'
elif echo "$IN" | grep -q "t: send Bishop the agenda"; then
  DUE=$(date -u -v+6H '+%Y-%m-%dT%H:%M:%SZ')
  echo "{\"action\":\"file\",\"actions\":[{\"fn\":\"create_task\",\"args\":{\"description\":\"Send Bishop the agenda\",\"due\":\"$DUE\",\"primary_role_id\":\"general\"}}]}"
elif echo "$IN" | grep -q "met Daniel Cho at the mixer"; then
  echo '{"action":"file","actions":[{"fn":"create_person","args":{"name":"Daniel Cho","primary_role_id":"general"}},{"fn":"record_atom","args":{"ts":"2026-06-12T19:00:00-07:00","kind":"meeting","summary":"Met Daniel Cho at the mixer — wants an intro.","primary_role_id":"general","links":[{"to_type":"person","to_id":{"$ref":0},"kind":"participant"}]}}]}'
else
  echo 'Good morning, Sam — the loop is closed.'
fi
STUB
chmod +x "$TMP/stub-llm"
export CLAUDIO_LLM_CMD="$TMP/stub-llm"

echo "== e2e hop 0: seed the signed term (purpose contract + roles) =="
if "$REPO/core/l1/seeds/seed.sh" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "PASS  seed";
else FAIL=$((FAIL+1)); FAILED_NAMES+=("seed"); echo "FAIL  seed"; fi
expect_eq "contract-readable-by-workers" w_filer "select count(*) from l1.purpose" "22"

echo "== e2e hop 1: two texts land in the fixture chat.db; edge captures =="
sqlite3 "$CLAUDIO_CHATDB" <<'SQL'
create table handle (ROWID integer primary key, id text);
create table chat (ROWID integer primary key, chat_identifier text);
create table message (ROWID integer primary key, guid text, text text, handle_id integer, date integer, is_from_me integer);
create table chat_message_join (chat_id integer, message_id integer);
insert into handle values (1, '+14155550130');
insert into chat values (1, 'self-sam'), (2, '+14155550130');
insert into message values
  (1, 'e2e-001', 't: send Bishop the agenda by tonight', null, 0, 1),
  (2, 'e2e-002', 'met Daniel Cho at the mixer, wants an intro', 1, 0, 0);
insert into chat_message_join values (1, 1), (2, 2);
SQL
expect_ok "edge-config" claudio_core "update l1.components set config = config || '{\"watch\":[\"self-sam\",\"+14155550130\"],\"user_handles\":[\"+14355550100\"]}' where id = 'edge-imessage'"
"$REPO/core/pipes/edge/main.sh" >/dev/null
expect_eq "captured" claudio_core "select count(*) from l1.intake where adapter = 'edge-imessage' and status = 'pending'" "2"

echo "== e2e hop 2: filer files both =="
python3 "$REPO/core/agents/filer/main.py" >"$TMP/filer.log" 2>&1 || cat "$TMP/filer.log"
expect_eq "task-open"     claudio_core "select count(*) from l1.obligations where description = 'Send Bishop the agenda' and status = 'open' and due is not null" "1"
expect_eq "atom-filed"    claudio_core "select count(*) from l1.atoms where summary like 'Met Daniel Cho%'" "1"
expect_eq "ref-injected"  claudio_core "select refs->0->>'locator' from l1.atoms where summary like 'Met Daniel Cho%'" "imsg-e2e-002"
expect_eq "person-created" claudio_core "select count(*) from l1.people where name = 'Daniel Cho'" "1"
expect_eq "nothing-pending" claudio_core "select count(*) from l1.intake where status = 'pending'" "0"

echo "== e2e hop 3: scanner fires the due reminder =="
"$REPO/core/pipes/scanner/main.sh" >/dev/null
expect_eq "reminder-posted" claudio_core "select count(*) from l1.messages where kind = 'notification' and payload->>'trigger' = 'due' and payload->>'summary' like '%Send Bishop the agenda%'" "1"

echo "== e2e hop 4: brief assembles the morning message =="
python3 "$REPO/core/agents/brief/main.py" >"$TMP/brief.log" 2>&1 || cat "$TMP/brief.log"
expect_eq "brief-posted"   claudio_core "select count(*) from l1.messages where payload->>'workflow' = 'brief'" "1"
expect_eq "brief-has-task" claudio_core "select count(*) from l1.messages where payload->>'workflow' = 'brief' and payload->>'summary' like '%Send Bishop the agenda%'" "1"
expect_eq "brief-opener"   claudio_core "select count(*) from l1.messages where payload->>'workflow' = 'brief' and payload->>'summary' like 'Good morning, Sam — the loop is closed.%'" "1"

echo "== e2e hop 5: edge drains the user queue; the loop closes =="
"$REPO/core/pipes/edge/main.sh" >/dev/null
expect_eq "queue-drained" claudio_core "select count(*) from l1.messages where queue = 'user' and status = 'posted'" "0"
for text in "Send Bishop the agenda" "the loop is closed"; do
  if grep -q "$text" "$CLAUDIO_STATE_DIR/sent.log"; then PASS=$((PASS+1)); echo "PASS  sent: $text";
  else FAIL=$((FAIL+1)); FAILED_NAMES+=("sent: $text"); echo "FAIL  sent: $text"; fi
done

summary
