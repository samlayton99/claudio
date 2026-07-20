#!/usr/bin/env bash
# Brief tests: deterministic skeleton, degraded mode (model dead), notable daily pass via stub,
# reflection page, one-per-day dedup. Run after dev.sh reset.
set -uo pipefail
source "$(dirname "$0")/../../pipes/red-team/lib.sh"
DIR="$(cd "$(dirname "$0")" && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CLAUDIO_WIKI_DIR="$TMP/wiki"

echo "== brief: seed world =="
expect_ok "seed-role" claudio_panel "select l1.upsert_role('prod', 'PROD', 1.3)"
sql claudio_panel "select l1.create_task('Send the agenda', now() + interval '6 hours')" >/dev/null
sql claudio_panel "select l1.create_task('Review the deck', now() - interval '2 hours')" >/dev/null
sql claudio_panel "select l1.create_expectation('Deck from Daniel', null, now() + interval '1 day')" >/dev/null
sql w_filer "select l1.post_message('user', 'question', '{\"summary\":\"Which Mike?\"}')" >/dev/null
AID=$(sql w_filer "select (l1.record_atom(current_date - interval '12 hours', 'meeting', 'Met Nina from the Thiel Fellowship — intro call proposed', p_meta => '{\"notable_candidate\": true}'::jsonb))->>'id'")

echo "== brief: degraded mode — model totally dead, skeleton still sends (P6) =="
CLAUDIO_LLM_CMD=/usr/bin/false python3 "$DIR/main.py" >/dev/null 2>&1
expect_eq "brief-sent"      claudio_core "select count(*) from l1.messages where payload->>'workflow' = 'brief'" "1"
expect_eq "has-overdue"     claudio_core "select count(*) from l1.messages where payload->>'workflow' = 'brief' and payload->>'summary' like '%Review the deck%[OVERDUE]%'" "1"
expect_eq "has-waiting"     claudio_core "select count(*) from l1.messages where payload->>'workflow' = 'brief' and payload->>'summary' like '%WAITING ON%Deck from Daniel%'" "1"
expect_eq "has-question"    claudio_core "select count(*) from l1.messages where payload->>'workflow' = 'brief' and payload->>'summary' like '%Which Mike?%'" "1"
expect_eq "notable-skipped-on-dead-model" claudio_core "select notable from l1.atoms where id = '$AID'::uuid" "f"

echo "== brief: dedup — second run same day is a no-op =="
CLAUDIO_LLM_CMD=/usr/bin/false python3 "$DIR/main.py" >/dev/null 2>&1
expect_eq "one-per-day" claudio_core "select count(*) from l1.messages where payload->>'workflow' = 'brief'" "1"

echo "== brief: reflection page written + registered =="
TODAY=$(date +%F)
if [ -f "$CLAUDIO_WIKI_DIR/cadences/daily/$TODAY.md" ]; then PASS=$((PASS+1)); echo "PASS  page-file";
else FAIL=$((FAIL+1)); FAILED_NAMES+=("page-file"); echo "FAIL  page-file"; fi
expect_eq "page-registered" claudio_core "select count(*) from l1.documents where path = 'wiki/cadences/daily/$TODAY.md' and kind = 'digest' and chapter = 'cadences'" "1"

echo "== brief: notable daily pass with a working stub (fresh day) =="
sql claudio_core "delete from l1.messages where payload->>'workflow' = 'brief'" >/dev/null
cat > "$TMP/stub-llm" <<STUB
#!/usr/bin/env bash
IN="\$(cat)"
if echo "\$IN" | grep -q "Closed reason vocabulary"; then
  echo '[{"id":"$AID","notable":true,"reason":"first_contact"}]'
else
  echo "Good morning, Sam — a clear Friday ahead."
fi
STUB
chmod +x "$TMP/stub-llm"
CLAUDIO_LLM_CMD="$TMP/stub-llm" python3 "$DIR/main.py" >/dev/null 2>&1
expect_eq "notable-set"      claudio_core "select notable from l1.atoms where id = '$AID'::uuid" "t"
expect_eq "reason-from-vocab" claudio_core "select notable_reason from l1.atoms where id = '$AID'::uuid" "first_contact"
expect_eq "polished-opener"  claudio_core "select count(*) from l1.messages where payload->>'workflow' = 'brief' and payload->>'summary' like 'Good morning, Sam — a clear Friday ahead.%'" "1"
expect_eq "notable-in-brief" claudio_core "select count(*) from l1.messages where payload->>'workflow' = 'brief' and payload->>'summary' like '%Met Nina%(first_contact)%'" "1"

echo ""
echo "==== $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
