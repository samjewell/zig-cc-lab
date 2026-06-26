Still reproduces on **Zig 0.16.0** (Homebrew build, bundled LLVM/clang 21.1.8), macOS 15.7.7 / Apple M3 Pro (arm64), cross-compiling to `aarch64-linux-musl`. Posting a minimal repro plus two findings that extend the original report, in case they're useful.

### Minimal repro

```sh
printf 'long f(const int*a,unsigned long n){long s=0;for(unsigned long i=0;i<n;i++)s+=a[i];return s;}\n' > t.cpp
for O in O0 O1 O2 O3 Os Oz; do zig c++ -target aarch64-linux-musl -$O -c t.cpp -o z-$O.o; done
shasum -a 256 z-*.o
```

`zig c++` collapses into three buckets (sha256):

```
7dd0b6f6…  z-O0.o
29b269da…  z-O1.o
29b269da…  z-O2.o   # == O1
29b269da…  z-O3.o   # == O1
5c9135cf…  z-Os.o
5c9135cf…  z-Oz.o   # == Os
```

So `-O1`, `-O2`, `-O3` produce **byte-identical** objects. Worth highlighting that it's not only `-O3`→`-O2`: **`-O1` is folded in too**, so there's also no way to get a genuine `-O1` (lighter optimization / faster compiles) via `zig cc`.

The same source through host **Apple clang 17** keeps `-O1` distinct, confirming the source is optimization-sensitive and the collapse is the zig wrapper (consistent with the `ReleaseFast → -O2` mapping discussed above):

```
57fcdcd9…  c-O1.o
492858da…  c-O2.o   # ≠ O1
492858da…  c-O3.o
```

### Escape hatches for object output — what works, what doesn't

- `zig cc` / `zig c++ -c` with `-Xclang -O3` (or `-Xclang -Ofast`) is a **no-op**:

```sh
zig c++ -target aarch64-linux-musl -O2 -c t.cpp -o a.o
zig c++ -target aarch64-linux-musl -O3 -Xclang -O3 -c t.cpp -o b.o
cmp a.o b.o   # identical
```
`-###` shows why — both `-O2` (injected by zig) and the appended `-O3` reach the `-cc1` line, and the earlier `-O2` wins.

- `zig build-obj -cflags -O3 -- t.cpp` **does** pass `-O3` through (the `-cflags -O3` object differs from the `-cflags -O2` one). But it only works in Zig's **Debug** mode — `ZIG_VERBOSE_CC=1` shows clang also gets `-O0` (overridden by the `-O3`), plus `-fsanitize=undefined`, `-fno-omit-frame-pointer`, `-fno-stack-protector`. Adding `-OReleaseFast` to drop those re-collapses the level back to `-O2` (ReleaseFast overrides the cflags `-O`). So I couldn't find a clean `-O3`-**release** object path.

### Context

Hit this cross-compiling DuckDB's amalgamation to musl: `-O1`/`-O2`/`-O3` produced three byte-identical 456 MB objects, each a genuine ~4.5-min compile, which was initially very confusing (a shared cache also makes the 2nd/3rd return instantly). The resulting `-O2`-equivalent build works fine, so this isn't urgent — but a documented way to produce a clean `-O3`-**release** object would help (either `zig cc -c` honoring the level, or `build-obj` without the Debug-mode `-O0`/sanitizers when you pass `-cflags -O3`). Happy to test patches.
