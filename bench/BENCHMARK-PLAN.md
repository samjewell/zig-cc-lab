# DuckDB `-O2` vs `-O3` benchmark — overnight runbook

> Self-contained plan for a fresh chat. Goal: measure how much performance DuckDB
> loses at `-O2` vs `-O3`, because `zig cc` forces our cross-compiled DuckDB to `-O2`.

## Background (the "why")

- We cross-compile DuckDB's C++ amalgamation with `zig c++`. **Verified finding:** `zig cc`/`zig c++` maps `-O1`/`-O2`/`-O3`/`-O4`/`-Ofast` all to clang **`-O2`** (`ReleaseFast` → `-O2`). Source: [`src/main.zig#L2161`](https://github.com/ziglang/zig/blob/738d2be9d6b6ef3ff3559130c05159ef53336224/src/main.zig#L2161-L2174) and [`src/Compilation.zig#L7054`](https://github.com/ziglang/zig/blob/738d2be9d6b6ef3ff3559130c05159ef53336224/src/Compilation.zig#L7054-L7060) (also see the repo root `PLAN.md` Stage 4 finding).
- **DuckDB Labs ship releases at `-O3`** (their CMake `CMAKE_CXX_FLAGS_RELEASE`). So our zig build is effectively `-O2`.
- **Question this answers:** does `-O3` actually make DuckDB meaningfully faster than `-O2`? If not, zig's `-O2` default costs us nothing and we can stop worrying. If yes, we've quantified the cost (a much stronger data point than the single case in ziglang/zig#16704).

## Scope

- **Tonight = Step 1 + Step 4 only.** (Steps 2 & 3 are documented under "Follow-ups" — do NOT do them tonight.)
  - **Step 1 (control):** build the *same* amalgamation with real `clang` at `-O2` and `-O3` (identical flags except `-O`), one machine → isolates the pure `-O` effect (no zig, no libc/toolchain confounds).
  - **Step 4 (rigor):** warm-up + **median of N=5** per query, fixed thread count, idle machine.
- This is a **native** build (measuring the optimizer's relative effect, which is ~arch-independent) — NOT the musl cross-build. We're measuring `-O`, not deployment.

## Files (already in this repo)

- `bench/bench.c` — DuckDB C-API harness: generates ~50M rows, runs group-by / filter / sort-topN / join, prints median/min/max ms per query.
- `bench/run.sh` — builds `libduckdb` at `-O2` and `-O3`, links the harness against each, runs, writes `bench/results-<timestamp>.md`.

## Prerequisites

1. **Amalgamation present** at `stage4-duckdb/duckdb.cpp` + `stage4-duckdb/duckdb.h` (gitignored, so may be absent on a fresh clone). If missing, re-fetch:
   ```bash
   cd stage4-duckdb
   curl -fL -o s.zip https://github.com/duckdb/duckdb/releases/download/v1.5.4/libduckdb-src.zip
   unzip -o s.zip && rm s.zip && cd ..
   ```
2. **A real `clang++`** (Apple clang or Homebrew LLVM) — NOT zig. `clang++ --version` should work.

## RUN IT (tonight)

1. **Smoke-test FIRST (a few minutes) — do not skip:**
   ```bash
   SMOKE=1 bash bench/run.sh
   ```
   This does a fast `-O0` build on 100k rows to validate the harness compiles, links, and the queries run. **If anything fails, fix it here** (most likely a missing link flag/framework — edit the link line in `bench/run.sh`; e.g. macOS sometimes needs extra `-framework`s, Linux needs `-ldl` which is already added).

2. **Full overnight run** (the two `-O2`/`-O3` compiles of the 24 MB TU are the slow part — ~10–20 min each, several GB RAM at `-O3`):
   ```bash
   bash bench/run.sh
   # or detached:  nohup bash bench/run.sh > bench/run.log 2>&1 &   (or run inside tmux)
   ```
   Results: `bench/results-<timestamp>.md`.

   Tunables (env): `ROWS` (default 50000000), `ITERS` (5), `THREADS` (4), `CXX` (clang++ path).

## Read the result (in the morning)

Compare `clangO3` vs `clangO2` median ms, per query:

- **Within a few % / overlapping min–max** → `-O3` doesn't meaningfully help DuckDB → **zig's `-O2` default costs ~nothing**. (Great evidence; we can relax and say so on Ziggit.)
- **`-O3` consistently faster by a clear margin** → that's the **quantified cost** of zig's `-O2` → justifies asking Zig for a real `-O3` opt-in (and worth a benchmark table in the post).
- `-O3` *slower* anywhere is possible (code bloat / i-cache) — note it if so.

If the two come out **close/ambiguous**, escalate rigor: pin cores (`taskset -c` on Linux), raise `ITERS`, report percentiles — then re-run.

## Environment notes

- **18 GB Mac:** `-O3` is RAM-tight (we saw memory pressure on earlier builds). Close apps, or prefer a bigger box. Overnight + idle already covers most of "Step 4" (no contention).
- **K8s:** a **dedicated node / guaranteed-resources pod** is ideal (more RAM, quiet CPU, Linux ≈ deploy target). **Shared / CPU-limited pods are too noisy** for timing — in that case a quiet idle Mac is the better measurement box.
- Pin DuckDB version to **1.5.4** (matches the amalgamation + the plugin's bindings).

## Follow-ups (a LATER session — not tonight)

- **Step 2 — vs the shipped build:** benchmark our zig `-O2` (musl) and/or a self-built clang `-O3` against the **official DuckDB Labs release** (`-O3`, glibc) on the same box + workload. Caveat: confounds libc + exact LLVM version + possible LTO/PGO/`-march`/allocator, so it's the "real-world gap," with Step 1 as the clean isolation.
- **Step 3 — real workload suite:** swap the synthetic queries for a standard suite — **ClickBench** (DuckDB participates) or **TPC-H** (`INSTALL tpch; CALL dbgen(sf=10); PRAGMA tpch(N);` if the amalgamation includes the tpch extension; else generated data) — for representative numbers.
- **Optional — zig vs clang at `-O2`:** build a third lib with native `zig c++ -O2` and confirm it matches `clang -O2` (validates that zig's "optimized" really is clang `-O2`). Link it *with zig* (`zig c++ bench.o lib.a -o ...`) to avoid mixing libc++/libstdc++ runtimes.

## Honesty / caveats

- There is no "zig `-O3`" for C — what we ship is `-O2`. This benchmark answers "what would `-O3` buy us," via plain clang.
- A single run is noise; the median-of-N is what makes this trustworthy.
- Step 1 (clang `-O2` vs `-O3`, same box) is the *clean* isolation of the `-O` effect; the official-release comparison (Step 2) mixes in other variables.
