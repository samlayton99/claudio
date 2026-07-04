#!/usr/bin/env bash
# Seeder tests: the signed contract lands verbatim, idempotently; DRAFT rows and
# unsigned contracts never seed. Run after dev.sh reset.
set -uo pipefail
source "$(dirname "$0")/../../pipes/red-team/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== seed: the signed contract applies =="
if "$HERE/seed.sh" >"$TMP/out1" 2>&1; then PASS=$((PASS+1)); echo "PASS  seed-runs"; else
  FAIL=$((FAIL+1)); FAILED_NAMES+=("seed-runs"); echo "FAIL  seed-runs"; cat "$TMP/out1"; fi

expect_eq "purpose-count"    claudio_core "select count(*) from l1.purpose" "22"
expect_eq "goal-count"       claudio_core "select count(*) from l1.purpose where kind = 'goal'" "6"
expect_eq "value-count"      claudio_core "select count(*) from l1.purpose where kind = 'value'" "10"
expect_eq "attribute-count"  claudio_core "select count(*) from l1.purpose where kind = 'attribute'" "6"
expect_eq "priorities-v1"    claudio_core "select max(version) from l1.purpose_versions" "1"
expect_eq "priorities-body"  claudio_core "select count(*) from l1.purpose_versions where body like '%My priorities, in order%'" "1"
expect_eq "goal-horizon"     claudio_core "select horizon from l1.purpose where id = 'goal-workout-daily'" "quarter"
expect_eq "covenant-markers" claudio_core "select jsonb_array_length(goalposts) from l1.purpose where id = 'value-the-covenant'" "3"
expect_eq "attr-goalposts"   claudio_core "select jsonb_array_length(goalposts) from l1.purpose where id = 'attr-anchored-to-christ'" "5"
expect_eq "workout-marker"   claudio_core "select jsonb_array_length(goalposts) from l1.purpose where id = 'goal-workout-daily'" "1"
expect_eq "statement-verbatim" claudio_core \
  "select count(*) from l1.purpose where id = 'value-holiness-over-greatness' and statement = 'I am not called to be great. I am called to be holy — and holiness will make me greater in ways ambition never could.'" "1"
expect_eq "roles-count"      claudio_core "select count(*) from l1.roles" "7"
expect_eq "disciple-s1"      claudio_core "select default_sensitivity from l1.roles where id = 'disciple'" "1"
expect_eq "ward-s1"          claudio_core "select default_sensitivity from l1.roles where id = 'ward-exec-sec'" "1"
expect_eq "weights-are-sams" claudio_core "select weight || '/' || (select weight from l1.roles where id='student') from l1.roles where id = 'disciple'" "10/0.5"

echo "== seed: re-run is a no-op (idempotent) =="
"$HERE/seed.sh" >"$TMP/out2" 2>&1
expect_eq "still-22"         claudio_core "select count(*) from l1.purpose" "22"
expect_eq "still-v1"         claudio_core "select max(version) from l1.purpose_versions" "1"

echo "== seed: drift is reported, never auto-retired =="
expect_ok "plant-drift"      claudio_core "select l1.upsert_purpose('goal-zzz-drift', 'goal', 'planted', 'year')"
"$HERE/seed.sh" >"$TMP/out3" 2>&1
if grep -q "DRIFT.*goal-zzz-drift" "$TMP/out3"; then PASS=$((PASS+1)); echo "PASS  drift-reported"; else
  FAIL=$((FAIL+1)); FAILED_NAMES+=("drift-reported"); echo "FAIL  drift-reported"; fi
expect_eq "drift-survives"   claudio_core "select status from l1.purpose where id = 'goal-zzz-drift'" "active"

echo "== seed: DRAFT rows skip; a changed priorities body appends a version =="
cat > "$TMP/synth.md" <<'EOF'
# Purpose Contract — synthetic

### goal: synth-approved [APPROVE]
- horizon: year
- statement: A synthetic approved goal.

### value: synth-draft [DRAFT]
- statement: Not his words yet.

## Priorities

A different priorities body for the version test.

## Signature

- [x] Signed by Sam — date: 2026-06-13
EOF
if "$HERE/seed.sh" "$TMP/synth.md" "$HERE/roles.json" >"$TMP/out4" 2>"$TMP/err4"; then
  PASS=$((PASS+1)); echo "PASS  synth-seeds"; else
  FAIL=$((FAIL+1)); FAILED_NAMES+=("synth-seeds"); echo "FAIL  synth-seeds"; cat "$TMP/err4"; fi
expect_eq "approved-landed"  claudio_core "select count(*) from l1.purpose where id = 'goal-synth-approved'" "1"
expect_eq "draft-skipped"    claudio_core "select count(*) from l1.purpose where id like '%synth-draft%'" "0"
if grep -q "SKIPPED DRAFT row value:synth-draft" "$TMP/err4"; then PASS=$((PASS+1)); echo "PASS  draft-skip-loud"; else
  FAIL=$((FAIL+1)); FAILED_NAMES+=("draft-skip-loud"); echo "FAIL  draft-skip-loud"; fi
expect_eq "new-version"      claudio_core "select max(version) from l1.purpose_versions" "2"

echo "== seed: an unsigned contract refuses to seed =="
sed 's/- \[x\] Signed by Sam/- [ ] Signed by Sam/' "$TMP/synth.md" > "$TMP/unsigned.md"
N=$(sql claudio_core "select count(*) from l1.purpose")
if "$HERE/seed.sh" "$TMP/unsigned.md" "$HERE/roles.json" >/dev/null 2>"$TMP/err5"; then
  FAIL=$((FAIL+1)); FAILED_NAMES+=("unsigned-refused"); echo "FAIL  unsigned-refused (seeded anyway)"; else
  PASS=$((PASS+1)); echo "PASS  unsigned-refused"; fi
expect_eq "unsigned-no-writes" claudio_core "select count(*) from l1.purpose" "$N"

summary
