#!/usr/bin/env bash
# Verify every archived DuckDB database is present, the right size, and READABLE.
#
# A backup that has never been read is not a verified backup. Size alone proves
# only that bytes exist; this opens each database over httpfs and reads real rows
# from a randomly chosen table, so corruption and truncation surface too.
#
# Reads are HTTP range requests -- the 84 GB database is never downloaded.
#
#   ./verify_s3_databases.sh                 # verify against the manifest
#   ./verify_s3_databases.sh --emit-manifest # print a fresh manifest from S3
set -uo pipefail

BUCKET="${S3_ARCHIVE_BUCKET:-tmuffly-samsung-archive-163531628641}"
REGION="${AWS_REGION:-us-east-2}"
MANIFEST="${MANIFEST:-$(dirname "$0")/databases.manifest}"
# day-of-year: a different table each day, reproducible within a day
SEED="${RANDOM_SEED:-$(date +%j)}"

if [[ "${1:-}" == "--emit-manifest" ]]; then
  aws s3 ls "s3://$BUCKET/" --recursive 2>/dev/null \
    | awk '$4 ~ /\.duckdb$/ {printf "%-13s %-4s %s\n", $3, "?", $4}'
  exit 0
fi

command -v duckdb >/dev/null || { echo "::error::duckdb CLI not found"; exit 1; }
command -v aws    >/dev/null || { echo "::error::aws CLI not found";    exit 1; }

fail=0; checked=0
declare -a PROBLEMS=()
note()    { printf '%s\n' "$*"; }
problem() { PROBLEMS+=("$1"); fail=1; }

# Boilerplate that attaches one database read-only over httpfs.
attach_sql() {
  printf "INSTALL httpfs; LOAD httpfs;
CREATE OR REPLACE SECRET s3sec (TYPE s3, PROVIDER credential_chain, REGION '%s');
ATTACH 's3://%s/%s' AS db (READ_ONLY);\n" "$REGION" "$BUCKET" "$1"
}

while read -r want_size min_tables key; do
  [[ -z "${key:-}" || "$want_size" == \#* ]] && continue
  checked=$((checked+1))
  note "── $key"

  # --- 1. present at the recorded size ----------------------------------------
  got_size=$(aws s3api head-object --bucket "$BUCKET" --key "$key" \
             --query ContentLength --output text 2>/dev/null)
  if [[ -z "$got_size" || "$got_size" == "None" ]]; then
    problem "$key: MISSING from s3://$BUCKET"; note "   x MISSING"; continue
  fi
  if [[ "$got_size" != "$want_size" ]]; then
    problem "$key: size $got_size != expected $want_size"
    note "   x SIZE MISMATCH: $got_size (expected $want_size)"; continue
  fi
  note "   ok present, $got_size bytes"

  # --- 2. opens, and still has at least the recorded number of tables ---------
  tables=$(duckdb -noheader -list -c "$(attach_sql "$key")
    SELECT count(*) FROM duckdb_tables() WHERE database_name='db';" 2>/dev/null | tail -1)
  if [[ ! "${tables:-}" =~ ^[0-9]+$ ]]; then
    problem "$key: could not be opened over httpfs"; note "   x UNREADABLE"; continue
  fi
  if (( tables < min_tables )); then
    problem "$key: $tables tables, expected at least $min_tables"
    note "   x TABLES LOST: $tables (expected >= $min_tables)"; continue
  fi
  if (( min_tables == 0 )); then
    note "   ok opens cleanly; known-empty ($tables tables), no read attempted"; continue
  fi

  # --- 3. read real rows from a randomly chosen table -------------------------
  picked=$(duckdb -noheader -list -c "$(attach_sql "$key")
    SELECT table_name FROM duckdb_tables() WHERE database_name='db'
    ORDER BY hash(table_name || '$SEED') LIMIT 1;" 2>/dev/null | tail -1)
  if [[ -z "${picked:-}" ]]; then
    problem "$key: has $tables tables but none could be selected"
    note "   x TABLE PICK FAILED"; continue
  fi

  rows=$(duckdb -noheader -list -c "$(attach_sql "$key")
    SELECT count(*) FROM query_table('db.main.' || '$picked');" 2>/dev/null | tail -1)
  if [[ ! "${rows:-}" =~ ^[0-9]+$ ]]; then
    problem "$key: could not read rows from '$picked'"
    note "   x READ FAILED on '$picked'"; continue
  fi
  note "   ok $tables tables; read $rows rows from '$picked'"
done < "$MANIFEST"

# --- 4. anything in S3 the manifest does not know about -------------------------
extra=$(comm -13 \
  <(grep -vE '^\s*#|^\s*$' "$MANIFEST" | awk '{print $3}' | sort) \
  <(aws s3 ls "s3://$BUCKET/" --recursive 2>/dev/null | awk '$4 ~ /\.duckdb$/ {print $4}' | sort))
if [[ -n "$extra" ]]; then
  note ""
  note "note: in S3 but not in the manifest, so unchecked -- add them:"
  sed 's/^/   + /' <<<"$extra"
fi

note ""
if (( fail )); then
  note "== FAIL: $checked databases checked =="
  for p in "${PROBLEMS[@]}"; do note "   x $p"; echo "::error::$p"; done
  exit 1
fi
note "== all $checked databases present and readable =="
