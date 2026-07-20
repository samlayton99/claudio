#!/usr/bin/env bash
# edge-gv component tests. Run after dev.sh reset. Fixture .eml files stand in for IMAP
# (CLAUDIO_GV_MAILDIR seam); outbound writes .eml to CLAUDIO_GV_OUTBOX instead of SMTP.
set -uo pipefail
source "$(dirname "$0")/../red-team/lib.sh"
DIR="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/mail" "$TMP/state"
export CLAUDIO_GV_MAILDIR="$TMP/mail" CLAUDIO_GV_OUTBOX="$TMP/outbox" \
       CLAUDIO_STATE_DIR="$TMP/state" CLAUDIO_GV_ATTACH_DIR="$TMP/attach" CLAUDIO_DB_ROLE=w_edge

run_gv() { python3 "$DIR/main.py" >/dev/null || { echo "FAIL gv-run"; exit 1; }; }

echo "== edge-gv: registry row from 0009; deploy config =="
expect_eq "seeded-disabled" claudio_core "select status || '|' || reliability from l1.components where id = 'edge-gv'" "disabled|critical"
sql claudio_core "update l1.components set config = config || '{\"account\":\"claudio.test@gmail.com\",\"user_handles\":[\"+18015551234\"]}' where id = 'edge-gv'" >/dev/null

cat > "$TMP/mail/01-sam.eml" <<'EOF'
From: "(801) 555-1234" <18015551234.14085554724.k3j2h@txt.voice.google.com>
Reply-To: <18015551234.14085554724.k3j2h@txt.voice.google.com>
Message-ID: <probe-1@txt.voice.google.com>
Subject: New text message from (801) 555-1234
Content-Type: text/plain; charset=UTF-8

Pick up the projector from Marco on Tuesday

YOUR ACCOUNT <https://voice.google.com>
To respond to this text message, reply to this email or visit Google Voice.
EOF

cat > "$TMP/mail/02-stranger.eml" <<'EOF'
From: "(212) 555-9999" <12125559999.14085554724.z9x8c@txt.voice.google.com>
Reply-To: <12125559999.14085554724.z9x8c@txt.voice.google.com>
Message-ID: <stranger-1@txt.voice.google.com>
Subject: New text message from (212) 555-9999
Content-Type: text/plain; charset=UTF-8

hey is this sam? it's Daniel from the accelerator
EOF

cat > "$TMP/mail/03-notgv.eml" <<'EOF'
From: newsletter@example.com
Message-ID: <spam-1@example.com>
Subject: 50 percent off everything
Content-Type: text/plain; charset=UTF-8

Big sale.
EOF

echo "== edge-gv: inbound sweep captures GV mail only, verbatim, footer stripped =="
run_gv
expect_eq "two-captured"    claudio_core "select count(*) from l1.intake where adapter = 'edge-gv'" "2"
expect_eq "non-gv-ignored"  claudio_core "select count(*) from l1.intake where raw like '%Big sale%'" "0"
expect_eq "verbatim-raw"    claudio_core "select raw from l1.intake where locator = 'gv-<probe-1@txt.voice.google.com>'" "Pick up the projector from Marco on Tuesday"
expect_eq "sender-verified" claudio_core "select sender->>'verified_user' from l1.intake where locator = 'gv-<probe-1@txt.voice.google.com>'" "true"
expect_eq "stranger-unverified" claudio_core "select sender->>'verified_user' from l1.intake where locator = 'gv-<stranger-1@txt.voice.google.com>'" "false"

echo "== edge-gv: locator dedup — second sweep is a no-op =="
run_gv
expect_eq "still-two" claudio_core "select count(*) from l1.intake where adapter = 'edge-gv'" "2"

echo "== edge-gv: outbound drains the user queue via reply-by-email, resolves on success =="
sql w_filer "select l1.post_message('user', 'notification', '{\"summary\":\"Reminder: agenda due at 6\"}')" >/dev/null
run_gv
expect_eq "resolved" claudio_core "select status from l1.messages where payload->>'summary' like 'Reminder%'" "done"
if grep -q "Reminder: agenda due at 6" "$TMP/outbox"/*.eml 2>/dev/null \
   && grep -q "To: 18015551234.14085554724.k3j2h@txt.voice.google.com" "$TMP/outbox"/*.eml; then
  PASS=$((PASS+1)); echo "PASS  reply-addressed"
else
  FAIL=$((FAIL+1)); FAILED_NAMES+=("reply-addressed"); echo "FAIL  reply-addressed"; ls "$TMP/outbox" 2>/dev/null
fi

echo "== edge-gv: no reply path -> outbound queued, never dropped =="
rm -f "$TMP/state/gv-replyto.json"
sql w_filer "select l1.post_message('user', 'notification', '{\"summary\":\"held until reply path\"}')" >/dev/null
run_gv
expect_eq "stays-posted" claudio_core "select status from l1.messages where payload->>'summary' = 'held until reply path'" "posted"

echo "== edge-gv: MMS attachment lands on disk and in meta =="
cat > "$TMP/mail/04-mms.eml" <<'EOF'
From: "(801) 555-1234" <18015551234.14085554724.k3j2h@txt.voice.google.com>
Reply-To: <18015551234.14085554724.k3j2h@txt.voice.google.com>
Message-ID: <mms-1@txt.voice.google.com>
Subject: New multimedia message from (801) 555-1234
Content-Type: multipart/mixed; boundary="BOUND"

--BOUND
Content-Type: text/plain; charset=UTF-8

whiteboard from the lab meeting
--BOUND
Content-Type: image/jpeg; name="photo.jpg"
Content-Disposition: attachment; filename="photo.jpg"
Content-Transfer-Encoding: base64

/9j/4AAQSkZJRg==
--BOUND--
EOF
run_gv
expect_eq "mms-captured" claudio_core "select raw from l1.intake where locator = 'gv-<mms-1@txt.voice.google.com>'" "whiteboard from the lab meeting"
ATT=$(sql claudio_core "select sender->'attachments'->>0 from l1.intake where locator = 'gv-<mms-1@txt.voice.google.com>'")
if [ -n "$ATT" ] && [ -f "$ATT" ]; then PASS=$((PASS+1)); echo "PASS  attachment-on-disk";
else FAIL=$((FAIL+1)); FAILED_NAMES+=("attachment-on-disk"); echo "FAIL  attachment-on-disk (meta: $ATT)"; fi

summary
