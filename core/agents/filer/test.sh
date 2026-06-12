#!/usr/bin/env bash
# Filer plumbing tests with a STUB LLM (no tokens): file/discard/hold/garbage paths,
# ref injection, $ref batches, quarantine isolation. Run after dev.sh reset.
set -uo pipefail
source "$(dirname "$0")/../../pipes/red-team/lib.sh"
DIR="$(cd "$(dirname "$0")" && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The stub: pattern-matches the capture in the prompt, emits a canned decision.
cat > "$TMP/stub-llm" <<'STUB'
#!/usr/bin/env bash
IN="$(cat)"
if echo "$IN" | grep -q "t: pick up the prescription"; then
  echo '{"action":"file","actions":[{"fn":"create_task","args":{"description":"Pick up the prescription","primary_role_id":"general"}}]}'
elif echo "$IN" | grep -q "verification code is 482910"; then
  echo '{"action":"discard","reason":"otp"}'
elif echo "$IN" | grep -q "its Mike — Thursday"; then
  echo '{"action":"hold","question":"Which Mike?"}'
elif echo "$IN" | grep -q "met Daniel Cho at the mixer"; then
  echo '{"action":"file","actions":[{"fn":"create_person","args":{"name":"Daniel Cho","primary_role_id":"general"}},{"fn":"record_atom","args":{"ts":"2026-06-12T19:00:00-07:00","kind":"meeting","summary":"Met Daniel Cho at the mixer — wants an intro.","primary_role_id":"general","links":[{"to_type":"person","to_id":{"$ref":0},"kind":"participant"}]}}]}'
elif echo "$IN" | grep -q "GARBLE ME"; then
  echo 'sorry, as an AI I cannot... lorem ipsum no json here'
elif echo "$IN" | grep -q "POISON PILL"; then
  echo '{"action":"file","actions":[{"fn":"create_task","args":{"description":null}}]}'
else
  echo '{"action":"file","actions":[{"fn":"record_atom","args":{"ts":"2026-06-12T12:00:00-07:00","kind":"capture","summary":"(stub default)"}}]}'
fi
STUB
chmod +x "$TMP/stub-llm"
export CLAUDIO_LLM_CMD="$TMP/stub-llm"

echo "== filer: seed captures via the edge function =="
for spec in \
  "msg-t1|t: pick up the prescription" \
  "msg-otp|Your Chase verification code is 482910. Don't share it." \
  "msg-mike|its Mike — Thursday still on?" \
  "msg-meet|m: met Daniel Cho at the mixer, wants an intro" \
  "msg-garble|GARBLE ME please" \
  "msg-poison|POISON PILL content"; do
  LOC="${spec%%|*}"; RAW="${spec#*|}"
  sql w_edge "select l1.capture('edge-imessage', '$(echo "$RAW" | sed "s/'/''/g")', '{\"source\":\"imessage\",\"handle\":\"+14355550100\",\"verified_user\":true}', '$LOC')" >/dev/null
done
expect_eq "six-pending" claudio_core "select count(*) from l1.intake where status = 'pending'" "6"

echo "== filer: run =="
python3 "$DIR/main.py" >"$TMP/out.log" 2>&1 || { cat "$TMP/out.log"; }

expect_eq "task-filed"       claudio_core "select count(*) from l1.obligations where description = 'Pick up the prescription' and status = 'open'" "1"
expect_eq "task-row-filed"   claudio_core "select status from l1.intake where locator = 'msg-t1'" "filed"
expect_eq "otp-discarded"    claudio_core "select status from l1.intake where locator = 'msg-otp'" "discarded"
expect_eq "otp-raw-retained" claudio_core "select count(*) from l1.intake where locator = 'msg-otp' and raw like '%482910%'" "1"
expect_eq "mike-held"        claudio_core "select status from l1.intake where locator = 'msg-mike'" "held"
expect_eq "mike-question"    claudio_core "select count(*) from l1.messages where kind = 'question' and payload->>'summary' = 'Which Mike?'" "1"
expect_eq "meeting-atom"     claudio_core "select count(*) from l1.atoms where summary like 'Met Daniel Cho%'" "1"
expect_eq "ref-injected"     claudio_core "select refs->0->>'locator' from l1.atoms where summary like 'Met Daniel Cho%'" "msg-meet"
expect_eq "person-linked"    claudio_core "select count(*) from l1.links where kind = 'participant' and to_type = 'person'" "1"
expect_eq "garble-unknown"   claudio_core "select count(*) from l1.atoms where kind = 'unknown' and (meta->>'filer_parse_failure')::boolean" "1"
expect_eq "garble-filed"     claudio_core "select status from l1.intake where locator = 'msg-garble'" "filed"
expect_eq "poison-quarantined" claudio_core "select status || ':' || coalesce(meta->>'quarantined','') from l1.intake where locator = 'msg-poison'" "held:true"

echo "== filer: second run is a no-op (nothing pending) =="
N=$(sql claudio_core "select count(*) from l1.atoms")
python3 "$DIR/main.py" >/dev/null 2>&1
expect_eq "idempotent" claudio_core "select count(*) from l1.atoms" "$N"

echo ""
echo "==== $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
