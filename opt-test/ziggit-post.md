Title: `zig cc` maps `-O1`/`-O2`/`-O3` to one level (`-O2`) — intended? and is there an escape hatch for `-c`?

---

Hi all — sharing a finding plus a couple of questions after a confusing afternoon, in case it helps others and to sanity-check my understanding.

I was cross-compiling DuckDB's amalgamation (~24 MB single translation unit) to `aarch64-linux-musl` with `zig c++`, building three times changing only `-O1` / `-O2` / `-O3`. All three produced **byte-identical** 456 MB objects — and each was a genuine ~4.5-minute compile, not a cache hit. After digging (the trail leads to Zig's `ReleaseFast → clang -O2` mapping), here's the minimal, reproducible picture.

**Environment:** Zig 0.16.0 (Homebrew build, bundled LLVM/clang 21.1.8), macOS 15.7.7, Apple M3 Pro, target `aarch64-linux-musl`.

**Minimal repro:**

```sh
printf 'long f(const int*a,unsigned long n){long s=0;for(unsigned long i=0;i<n;i++)s+=a[i];return s;}\n' > t.cpp
for O in O0 O1 O2 O3 Os Oz; do zig c++ -target aarch64-linux-musl -$O -c t.cpp -o z-$O.o; done
shasum -a 256 z-*.o
```

`zig c++` collapses into three buckets:

```
z-O0.o   distinct
z-O1.o ┐
z-O2.o ├─ byte-identical
z-O3.o ┘
z-Os.o ┐
z-Oz.o ┘─ byte-identical
```

So it isn't only `-O3`→`-O2`: **`-O1` is folded in too**, i.e. there's no way to get a genuine `-O1` (lighter optimization / faster compiles) either. The same source through host **Apple clang 17** keeps `-O1` distinct from `-O2`, so the source *is* optimization-sensitive and the collapse is the zig wrapper.

**The mechanism, traced in the Zig source:**

- [`src/main.zig` — the `.optimize` case](https://github.com/ziglang/zig/blob/738d2be9d6b6ef3ff3559130c05159ef53336224/src/main.zig#L2161-L2174) ORs `-O1`/`-O2`/`-O3`/`-O4`/`-Ofast` into the **same** `optimize_mode = .ReleaseFast` (only `-Os`/`-Oz` → `ReleaseSmall`, `-O0`/`-Og` → `Debug`).
- [`src/Compilation.zig` — `.ReleaseFast =>`](https://github.com/ziglang/zig/blob/738d2be9d6b6ef3ff3559130c05159ef53336224/src/Compilation.zig#L7054-L7060) then appends clang **`-O2`**, with the comment: *"we pass -O2 rather than -O3 because … -O3 is safer for Zig code than it is for C code … the -O3 path has been tested less."*

So `-O1/-O2/-O3 → ReleaseFast → clang -O2` is by design. (Permalinks pinned to `master @ 738d2be`; 0.16.0 isn't separately tagged on GitHub, but the code is identical — it's at `src/main.zig:2231` / `src/Compilation.zig:6658` in the `zig-0.16.0.tar.xz` source.)

I tried both workarounds suggested in ziglang/zig#16704, for the compile-to-object (`.o`) case:

- The **`-Xclang -Ofast` / `-Xclang -O3`** idea (from a commenter in that thread) is a **no-op** here. `-###` shows why — both zig's injected `-O2` and the appended `-O3` land on the `-cc1` line, and the earlier `-O2` wins:

```
"-O2"   # injected by zig (early)
"-O3"   # from -Xclang -O3 (later, ignored)
```

- The maintainer's recommended **`-cflags … --`** path *does* get through for object output: `zig build-obj -cflags -O3 -- t.cpp` produces an object that differs from the `-cflags -O2` one. But it only takes effect in Zig's default **Debug** mode, where `ZIG_VERBOSE_CC=1` shows clang also gets `-O0` (overridden by the `-O3`), `-fsanitize=undefined`, and frame-pointer flags. Adding `-OReleaseFast` to drop those re-collapses the level back to `-O2`.

So neither gives a clean `-O3`-*release* object. (This is the open issue tracking the perf angle: ziglang/zig#16704.)

**Questions:**

1. The `Compilation.zig` comment says the `-O3` path "has been tested less" for C (which is why `ReleaseFast` passes clang `-O2`). **Is there any plan to test/support a real `-O3` path for C** in future — i.e. could `zig cc -O3` eventually emit clang `-O3`?
2. **In the meantime, is there a supported way to opt into real `-O3`**, accepting the "tested less" caveat? For object builds I couldn't find a clean one: `-Xclang -O3` on `zig cc -c` is a no-op; `zig build-obj -cflags -O3` reaches clang but only in Debug mode (drags in `-fsanitize=undefined` etc.); and `-OReleaseFast` re-collapses to `-O2`.
3. Motivation, in case it's relevant: DuckDB's own releases build with `-O3` (its CMake `CMAKE_CXX_FLAGS_RELEASE`), so I'm trying to match that when compiling its amalgamation with `zig c++`. In practice, how much does `-O2`-vs-`-O3` matter for a large C++ codebase like this — is parity with upstream's `-O3` worth chasing, or is `-O2` genuinely fine? (#16704 suggests it can matter for hot loops.)

Thanks! Happy to run experiments or test patches.
