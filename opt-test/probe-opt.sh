#!/bin/sh
# Demonstrates that `zig c++` collapses -O1/-O2/-O3 (and -Ofast) to ONE optimization
# level, while -O0 and -Os/-Oz stay distinct.
#
# Expected output: -O1, -O2, -O3 share one sha256; -O0 differs; -Os == -Oz differ again.
# (For contrast, real clang/gcc produce a distinct -O1.)
set -eu
DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

cat > "$DIR/t.cpp" <<'EOF'
#include <cstddef>
long   sum(const int* a, size_t n){ long s=0; for(size_t i=0;i<n;i++) s+=a[i]; return s; }
static inline int sq(int x){ return x*x; }
long   sumsq(const int* a, size_t n){ long s=0; for(size_t i=0;i<n;i++) s+=sq(a[i]); return s; }
double fsum(const double* a, size_t n){ double s=0; for(size_t i=0;i<n;i++) s+=a[i]; return s; }
int    classify(int x){ if(x<0)return -1; else if(x==0)return 0; else if(x<10)return 1; else if(x<100)return 2; return 3; }
EOF

for L in O0 O1 O2 O3 Os Oz; do
  zig c++ -target aarch64-linux-musl -std=c++11 "-$L" -DNDEBUG -fPIC -w -c "$DIR/t.cpp" -o "$DIR/zig-$L.o" 2>/dev/null
  printf '%-4s %s\n' "$L" "$(shasum -a 256 "$DIR/zig-$L.o" | cut -c1-16)"
done
