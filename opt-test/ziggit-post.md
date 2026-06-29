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

The comment there implies that, although we pass `-O2` instead of `-O3` here, the performance will be equivalent to using `-O3` in C code.

And yet I found github issue:
https://github.com/ziglang/zig/issues/16704
Which seems to imply that Zig is sometimes slower (I'm not allowed to post on that issue). 

I suppose I'm mostly posting here to ask if that github issue is still relevant, or out of date. I'd love if we could just post an issue on that GH post, saying "we've addressed all performance gaps now" or something. Thanks!
