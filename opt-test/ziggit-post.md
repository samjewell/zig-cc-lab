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

I also tried the obvious escape hatch, and it doesn't work for compile-to-object: **`-Xclang -O3` is a no-op**. `-###` shows why — both zig's injected `-O2` and my appended `-O3` land on the `-cc1` line, and the earlier `-O2` wins:

```
"-O2"   # injected by zig (early)
"-O3"   # from -Xclang -O3 (later, ignored)
```

Interestingly, `zig build-obj -cflags -O3 -- t.cpp` **does** pass `-O3` through to clang (its object differs from the `-cflags -O2` one) — but only in Zig's default **Debug** mode, where `ZIG_VERBOSE_CC=1` shows clang also gets `-O0` (overridden by the `-O3`), `-fsanitize=undefined`, and frame-pointer flags. Switching to `-OReleaseFast` to drop those re-collapses the level back to `-O2`. So I couldn't get a clean `-O3`-*release* object via either path. There's an open issue tracking the perf angle: ziglang/zig#16704.

**Questions:**

1. Is the `-O1`/`-O2`/`-O3` → `ReleaseFast` (→ clang `-O2`) collapse considered final/intended, or a rough edge that might change?
2. Is there a supported way to get a clean `-O3`-*release* object? `-Xclang -On` on `zig cc -c` is a no-op, and `build-obj -cflags -O3` only takes effect in Debug mode (which drags in `-fsanitize=undefined` etc.), while `-OReleaseFast` re-collapses it to `-O2`.
3. In your experience, is `-O2`-vs-`-O3` worth caring about for large C/C++ like DuckDB? (For my case the `-O2` build is totally fine — mostly asking out of curiosity and drop-in-`cc` parity.)

Thanks! Happy to run experiments or test patches.
