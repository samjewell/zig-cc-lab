# zig-cc-lab

A hands-on lab that reproduces Andrew Kelley's [`zig cc`: a Powerful Drop-In Replacement for GCC/Clang](https://andrewkelley.me/post/zig-cc-powerful-drop-in-replacement-gcc-clang.html)
and then pushes it to a real goal: **cross-compiling DuckDB (a CGo dependency) to musl from a Mac**, so a
DuckDB-backed Grafana plugin can run on Alpine Linux.

## Why

The [Grafana DuckDB datasource plugin](https://github.com/motherduckdb/grafana-duckdb-datasource) can't run on
Grafana Cloud's Alpine (musl) infrastructure — its DuckDB engine is glibc-only
([issue #80](https://github.com/motherduckdb/grafana-duckdb-datasource/issues/80)). This repo explores using
`zig cc`/`zig c++` to produce a **fully static, musl-compatible** DuckDB build that runs on Alpine, by climbing a
validation ladder from "hello world" up to the real thing.

## The validation ladder

Each stage de-risks the next. Full commands, output, and status live in [`PLAN.md`](./PLAN.md).

| Stage | What | Proves |
| ----- | ---- | ------ |
| 0 | Install zig + Docker | toolchain |
| 1 | `hello.c` → aarch64/x86_64 · musl/glibc, run via Docker | C cross-compile + the no-host-QEMU workflow |
| 2 | tiny C++ (iostream + exceptions), static musl | the C++ runtime (libc++/unwind) on musl |
| 3 | tiny Go + `cgo`, static musl | Go + cgo + zig + musl end-to-end |
| 4 | build `libduckdb.a` for `aarch64-linux-musl` | the big C++ amalgamation compiles under zig |
| 5 | build the plugin backend against that `.a` | a real CGo binary links against our musl DuckDB |
| 6 | run it on Alpine | the #80 fix — no glibc/`libstdc++` loader errors |
| 7 | productionize + PR #94 | CI can build/test static-musl plugin binaries |
| 8 | bake in `httpfs` | static-musl DuckDB can keep remote-file extension behavior |

See the **Progress** checklist at the top of [`PLAN.md`](./PLAN.md) for current status.

## Notable findings

- **`zig cc` is a genuinely great drop-in cross-compiler.** From an arm64 Mac, with no sysroot assembly, it builds
  static musl binaries for multiple architectures that run unmodified on Alpine.
- **No host QEMU on macOS.** The blog runs foreign binaries with user-mode QEMU (Linux-only). On a Mac you run them
  via Docker (`--platform`), which bundles the emulation. (Answers the "do we need QEMU?" question: not on the host.)
- **`zig cc` collapses `-O1`/`-O2`/`-O3` into one `-O2`-equivalent level.** Discovered while building DuckDB: three
  builds at different `-O` produced byte-identical objects. Root cause is Zig's `-O*` → `ReleaseFast` → clang `-O2`
  mapping (Zig deliberately avoids `-O3` for C/C++). Minimal repro: [`opt-test/probe-opt.sh`](./opt-test/probe-opt.sh).
  Reported upstream ([ziglang/zig#16704](https://github.com/ziglang/zig/issues/16704)) and the Zig forum; the
  `-O2`-vs-`-O3` perf delta is small for DB workloads (see the cited justification in `PLAN.md`).

## Layout

- `stage1-c/`, `stage2-cpp/`, `stage3-cgo/`, `stage4-duckdb/`, `stage6-duckdb-run/` — per-stage scratch (each isolated so `cgo` doesn't
  pick up a sibling's source).
- `opt-test/` — the optimization-level investigation: the repro script plus the writeups posted upstream.
- `PLAN.md` — the detailed, living plan: commands, measurements, findings, and decisions.

Build artifacts (`.o`/`.a`/cross-compiled binaries, and the downloaded ~25 MB DuckDB amalgamation) are **gitignored**
— they're large and fully regenerable from the commands in `PLAN.md`.

## Reproduce

1. `brew install zig jq` and have Docker running (see `PLAN.md` Stage 0).
2. Run a stage's commands from `PLAN.md`. Quick taste — the `-O`-collapse repro:

```sh
sh opt-test/probe-opt.sh   # -O1 == -O2 == -O3; -O0 and -Os/-Oz differ
```

## Environment used

macOS 15.7.7 · Apple M3 Pro (arm64) · Zig 0.16.0 (LLVM 21) · Go 1.26 · Docker 29. Primary target:
`aarch64-linux-musl`; DuckDB v1.5.4.

## License

MIT — do whatever's useful. This is an exploratory lab, shared in case the journey or the `zig cc` findings help others.
