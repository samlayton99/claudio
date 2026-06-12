#!/usr/bin/env bash
# Shared assertion helpers for the red-team suite and contract tests.
PG_BIN="${PG_BIN:-/opt/homebrew/opt/postgresql@17/bin}"
export PGHOST="${PGHOST:-$HOME/.claudio/sock}" PGPORT="${CLAUDIO_PGPORT:-5433}"
DB="claudio"
PASS=0; FAIL=0; FAILED_NAMES=()

sql() {  # sql <role> <sql> -> stdout (tuples only); nonzero on error
  local role="$1"; shift
  "$PG_BIN/psql" -U "$role" -d "$DB" -tAq -v ON_ERROR_STOP=1 -c "$1" 2>&1
}

expect_ok() {  # expect_ok <name> <role> <sql>
  local name="$1" role="$2" q="$3" out
  if out=$(sql "$role" "$q"); then
    PASS=$((PASS+1)); echo "PASS  $name"
  else
    FAIL=$((FAIL+1)); FAILED_NAMES+=("$name"); echo "FAIL  $name"; echo "      as $role: $q"; echo "      $out" | head -3
  fi
}

expect_fail() {  # expect_fail <name> <role> <sql> <stderr-pattern>
  local name="$1" role="$2" q="$3" pat="$4" out
  if out=$(sql "$role" "$q"); then
    FAIL=$((FAIL+1)); FAILED_NAMES+=("$name"); echo "FAIL  $name (succeeded; must fail)"; echo "      as $role: $q"
  elif echo "$out" | grep -qiE "$pat"; then
    PASS=$((PASS+1)); echo "PASS  $name"
  else
    FAIL=$((FAIL+1)); FAILED_NAMES+=("$name"); echo "FAIL  $name (failed with the WRONG error)"
    echo "      wanted /$pat/, got: $(echo "$out" | head -2)"
  fi
}

expect_eq() {  # expect_eq <name> <role> <sql> <expected-output>
  local name="$1" role="$2" q="$3" want="$4" out
  out=$(sql "$role" "$q") || { FAIL=$((FAIL+1)); FAILED_NAMES+=("$name"); echo "FAIL  $name (errored: $(echo "$out"|head -1))"; return; }
  if [ "$out" = "$want" ]; then
    PASS=$((PASS+1)); echo "PASS  $name"
  else
    FAIL=$((FAIL+1)); FAILED_NAMES+=("$name"); echo "FAIL  $name"; echo "      want [$want] got [$out]"
  fi
}

summary() {
  echo
  echo "==== $PASS passed, $FAIL failed ===="
  if [ "$FAIL" -gt 0 ]; then printf '  failed: %s\n' "${FAILED_NAMES[@]}"; exit 1; fi
}
