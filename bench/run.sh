#!/usr/bin/env bash
# DuckDB -O2 vs -O3 control benchmark (Step 1 + Step 4 rigor).
# Builds the SAME amalgamation with real clang at -O2 and -O3, links the harness
# against each, runs median-of-N, and writes bench/results-<timestamp>.md.
#
#   bench/run.sh            full run (-O2 and -O3, ROWS rows)
#   SMOKE=1 bench/run.sh    fast validation only (-O0, tiny data) — DO THIS FIRST
#
# Env knobs: ROWS (default 50000000), ITERS (5), THREADS (4), CXX (clang++ path).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/stage4-duckdb"          # must contain duckdb.cpp + duckdb.h
B="$ROOT/bench"; OUT="$B/build"; mkdir -p "$OUT"
CXX="${CXX:-$(command -v clang++ || true)}"
ROWS="${ROWS:-50000000}"; ITERS="${ITERS:-5}"; THREADS="${THREADS:-4}"
STAMP="$(date +%Y%m%d-%H%M%S)"; RES="$B/results-$STAMP.md"
DL=""; uname | grep -qi linux && DL="-ldl"

[ -n "$CXX" ]            || { echo "ERROR: no clang++ found (set CXX=, and use REAL clang, not zig)"; exit 1; }
[ -f "$SRC/duckdb.cpp" ] || { echo "ERROR: missing $SRC/duckdb.cpp — re-fetch amalgamation (see BENCHMARK-PLAN.md)"; exit 1; }
[ -f "$SRC/duckdb.h" ]   || { echo "ERROR: missing $SRC/duckdb.h"; exit 1; }

log(){ printf '%s\n' "$*" | tee -a "$RES"; }

log "# DuckDB -O benchmark — $STAMP"
log ""
log "- host: \`$(uname -srm)\`"
log "- compiler: \`$($CXX --version | head -1)\`"
log "- rows=$ROWS  iters=$ITERS  threads=$THREADS"
log ""

echo ">> compiling harness (bench.c)"
"$CXX" -O2 -I "$SRC" -c "$B/bench.c" -o "$OUT/bench.o"

build_and_run(){ # name  optflag  rows  iters
  local name="$1" opt="$2" rows="$3" iters="$4"
  echo ">> [$name] compiling duckdb.cpp $opt  (slow: ~minutes, GBs of RAM at -O3) ..."
  local t0; t0=$(date +%s)
  "$CXX" "$opt" -std=c++11 -DNDEBUG -fPIC -w -c "$SRC/duckdb.cpp" -o "$OUT/duckdb-$name.o"
  ar rcs "$OUT/libduckdb-$name.a" "$OUT/duckdb-$name.o"
  local bt=$(( $(date +%s) - t0 ))
  echo ">> [$name] linking + running"
  "$CXX" "$OUT/bench.o" "$OUT/libduckdb-$name.a" -o "$OUT/bench-$name" -lpthread -lm $DL
  log "## $name  ($opt, built in ${bt}s)"
  log '```'
  "$OUT/bench-$name" "$rows" "$iters" "$THREADS" "$name" | tee -a "$RES"
  log '```'
  log ""
}

if [ "${SMOKE:-0}" = "1" ]; then
  echo "=== SMOKE TEST: fast -O0 build, 100k rows — validates harness/link/queries ==="
  build_and_run smoke -O0 100000 2
  echo "Smoke OK. Results: $RES   (now run without SMOKE for the real thing)"
  exit 0
fi

build_and_run clangO2 -O2 "$ROWS" "$ITERS"
build_and_run clangO3 -O3 "$ROWS" "$ITERS"
log "Compare **clangO3** vs **clangO2** median ms per query. Within noise ⇒ -O2 (zig's default) costs ~nothing."
echo "All done. Results: $RES"
