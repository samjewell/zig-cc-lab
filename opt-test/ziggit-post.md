Title: Would Zig consider an opt-in to pass a real clang -O3 for C?

Posted to: https://ziggit.dev/t/would-zig-consider-an-opt-in-to-pass-a-real-clang-o3-for-c/16405

---

Hey team.

I'm trying to build DuckDB (C++) from my mac for other architectures. I want to embed it into a Go program (Grafana), which doesn't yet use cgo, but would need to in future. In order to switch to cgo I need to find a way to cross-compile, hence trying out Zig.
But DuckDB has some pretty great performance, and it is built with `-O3` by the DuckLabs team. I tried to cross-compile with `-O3`, but it was overridden to `-O2`

That's happening in the source code here:
https://github.com/ziglang/zig/blob/738d2be9d6b6ef3ff3559130c05159ef53336224/src/Compilation.zig#L7054-L7060

And the code comment there says:
```
                .ReleaseFast => {
                    // Here we pass -O2 rather than -O3 because, although we do the equivalent of
                    // -O3 in Zig code, the justification for the difference here is that Zig
                    // has better detection and prevention of undefined behavior, so -O3 is safer for
                    // Zig code than it is for C code. Also, C programmers are used to their code
                    // running in -O2 and thus the -O3 path has been tested less.
                    try argv.append("-O2");
```

~~The comment there implies that, although we pass `-O2` instead of `-O3` here, the performance will be equivalent to using `-O3` in C code.~~

**EDIT** I didn't want to violate the AI policy, but I did want to post something correct.

My AI says:

> Parsed precisely:
> 
> * Zig source compiled in `ReleaseFast` gets an `-O3`-*equivalent* pipeline (Zig does that itself).
> * C/C++ source (your DuckDB, via the clang frontend) is deliberately given clang `-O2` — *not* `-O3` — because (a) C has more undefined behavior that `-O3` exploits more aggressively (Zig code is UB-checked, C isn't), and (b) the `-O3`-for-C path is less tested.
> 
> So the comment is not a performance-equivalence claim. It's the opposite: C code is intentionally left at `-O2` (potentially slower than a real `-O3` C build), purely for *safety + testing* reasons. Your DuckDB is genuinely an `-O2` build.

So I'm wondering whether Zig might implement an `-O3` optimization level, even if it also has to exploit undefined behaviour aggressively, in order to get to the same level of performance?

Again, quoting my AI (trying not to violate AI policy): 

> *Would Zig consider **an opt-in to pass a real clang `-O3` for C** — accepting that it's less-tested and that more aggressive optimization can expose latent UB in C code?"*

I also found github issue:
https://github.com/ziglang/zig/issues/16704
Which seems to imply that Zig is sometimes slower (I'm not allowed to post on that issue). 

I suppose I'm mostly posting here to ask if that github issue is still relevant, or out of date. I'd love if we could just post an issue on that GH post, saying "we've addressed all performance gaps now" or something. Thanks!
