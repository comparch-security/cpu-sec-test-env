#!/usr/bin/env bash
set -euo pipefail
# stage_corpus.sh LANE OUT_DIR [--enable-flag enable_aarch64_morello]
#
# The ONE corpus-staging path for every system lane.  It drives the pinned
# runner's own corpus mode and stages the result under OUT_DIR:
#   OUT_DIR/configure.json  the tracked bench registry, copied verbatim
#   OUT_DIR/manifest.json   verified manifest (units/side files/support/skips)
#   OUT_DIR/test/<unit>     one test/<program>__<key> file per build unit
#   OUT_DIR/test/<side>     the registry-referenced side files
#   OUT_DIR/test/<support>  the declared plain-name support files
#
# The invariant: the runner owns corpus keying and skip handling.  This script
# never recomputes a key, never derives a registry and never rewrites a skip
# token - it builds a HOST runner with the lane's skip token baked in, runs
# `./run-test corpus make-only exhausted-run` in a scratch tree with the lane's
# toolchain in the environment, and verifies the outcome against the tracked
# registry (scripts/common/corpus_manifest.py).
#
# CALLER-LOCKED: every caller is a system lane's deploy leg, which already
# holds the flock on $BUILD_DIR/.lane.lock and passes the descriptor down.
# There is no standalone unlocked invocation: the script verifies that fd 9
# is the held lane lock and refuses (exit 2) otherwise.  It closes the
# descriptor before it runs any child, so no descendant can hold the lock.
#
# The build runs in a scratch copy of the bench tree under the lane's
# $BUILD_DIR area, outside the submodule worktree, wiped at the start of every
# run: the tracked `benchmark/` tree is never built, never cleaned and never
# written, so the deploy's pin preflight and clean-tree post-assert hold.
#
# Lanes (env lane -> bench token, the spelling the registry's skip rows use):
#   riscv64          ARCH=riscv64      token riscv64
#   riscv64-nemu     ARCH=riscv64      token riscv64
#   cheri_riscv64    ARCH=cheri_riscv64 token cheri_riscv64  (enable_riscv64_cheri)
#   aarch64-morello  ARCH=aarch64      token aarch64-morello (enable_aarch64_morello)
# --enable-flag is accepted only as exactly `enable_aarch64_morello`, and only
# for the aarch64-morello lane; the flag rides the corpus invocation's
# ENVIRONMENT because the runner's child makes take no command-line flags.

di() { echo "stage_corpus: $*" >&2; }

LANE=""
OUT_DIR=""
ENABLE_FLAG_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --enable-flag) ENABLE_FLAG_ARG=${2:-}; shift ;;
    -*)            di "unknown option '$1'"; exit 2 ;;
    *)
      if [ -z "$LANE" ]; then LANE=$1
      elif [ -z "$OUT_DIR" ]; then OUT_DIR=$1
      else di "too many positional arguments"; exit 2
      fi ;;
  esac
  shift
done
if [ -z "$LANE" ] || [ -z "$OUT_DIR" ]; then
  echo "usage: $0 LANE OUT_DIR [--enable-flag enable_aarch64_morello]" >&2
  exit 2
fi

case "$LANE" in
  riscv64|riscv64-nemu|cheri_riscv64|aarch64-morello) ;;
  *)
    di "unknown lane '$LANE' (expected riscv64 | riscv64-nemu | cheri_riscv64 | aarch64-morello)"
    exit 2
    ;;
esac
case "${ENABLE_FLAG_ARG:-none}:$LANE" in
  none:*) ;;
  enable_aarch64_morello:aarch64-morello) ;;
  *)
    di "--enable-flag is accepted only as '--enable-flag enable_aarch64_morello' for the aarch64-morello lane"
    exit 2
    ;;
esac

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=../../env.sh
. ./env.sh

case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$PWD/$OUT_DIR" ;;
esac
case "$OUT_DIR" in
  /|"$ROOT"|"$ROOT"/)
    di "refusing to use '$OUT_DIR' as OUT_DIR"
    exit 2
    ;;
  "$ROOT"/benchmark/*)
    di "OUT_DIR must not live inside the benchmark submodule"
    exit 2
    ;;
esac

# ---- caller-locked: fd 9 must be the held lane lock (see the header) ----
mkdir -p "$BUILD_DIR"
LANE_LOCK="$BUILD_DIR/.lane.lock"
fd9_target=$(readlink -f /proc/self/fd/9 2>/dev/null || true)
lock_target=$(readlink -f "$LANE_LOCK" 2>/dev/null || printf '%s\n' "$LANE_LOCK")
if [ -z "$fd9_target" ] || [ "$fd9_target" != "$lock_target" ] || ! flock -n 9; then
  di "not running under the lane lock: fd 9 is not the held $LANE_LOCK (callers are the lanes' deploy legs, which hold it)"
  exit 2
fi
exec 9>&-

# ---- pinned bench checkout: HEAD must be BENCH_COMMIT ----
# The scratch tree copies the worktree, so what it copies must be the pin.
git_rc=0
bench_head=$(git -C "$ROOT/benchmark" rev-parse HEAD) || git_rc=$?
if [ "$git_rc" -ne 0 ]; then
  di "cannot verify the benchmark pin: 'git -C benchmark rev-parse HEAD' failed (rc=$git_rc)"
  exit 1
fi
if [ "$bench_head" != "$BENCH_COMMIT" ]; then
  di "benchmark submodule is at $bench_head but env.sh pins BENCH_COMMIT=$BENCH_COMMIT"
  exit 1
fi

# ---- per-lane toolchain (bench ARCH, skip token, enable flag, tools) ----
CHERI_BROOT="$ROOT/$BUILD_DIR/cheri"
# Emit the clang++ path AS-IS: clang picks its driver mode (C vs C++) from
# argv[0], and the SDK's clang++ is a symlink to clang-17.  Resolving that
# symlink makes the compiler run in C mode and silently skip the C++ runtime
# at link.  The verifier enforces this -- do not "simplify" it back.
find_sdk_clang() {  # bindir
  local bindir=$1 c
  for c in "$bindir/clang++" "$bindir"/*-clang++; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}
# The SDK's own CHERI-capable objdump: the riscv64cheri-objdump wrapper
# (llvm-objdump --mattr=+m,+a,+f,+d,+c,+xcheri) with bare llvm-objdump as
# the fallback candidate.
find_sdk_objdump() {  # bindir
  local bindir=$1 c
  for c in "$bindir/riscv64cheri-objdump" "$bindir/llvm-objdump"; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

BENCH_ARCH=""
TOKEN=""
LANE_FLAG=""
CXX=""
ASM=""
OBJDUMP=""
VER_CXX=""      # the bare compiler path, for the manifest's version line
SHIM_PREFIX=""
case "$LANE" in
  riscv64)
    BENCH_ARCH=riscv64; TOKEN=riscv64; LANE_FLAG=""
    CXX=$RISCV64_CXX; ASM=$RISCV64_AS; OBJDUMP=$RISCV64_OBJDUMP
    VER_CXX=$RISCV64_CXX
    SHIM_PREFIX="${RISCV64_OBJDUMP%-objdump}"
    ;;
  riscv64-nemu)
    # The bench's own token for the NEMU lane is riscv64: the guest image is
    # the same cross build, only the interpreter differs.
    BENCH_ARCH=riscv64; TOKEN=riscv64; LANE_FLAG=""
    CXX=$RISCV64_CXX; ASM=$RISCV64_AS; OBJDUMP=$RISCV64_OBJDUMP
    VER_CXX=$RISCV64_CXX
    SHIM_PREFIX="${RISCV64_OBJDUMP%-objdump}"
    ;;
  cheri_riscv64)
    BENCH_ARCH=cheri_riscv64; TOKEN=cheri_riscv64; LANE_FLAG=enable_riscv64_cheri
    CLANG=$(find_sdk_clang "$CHERI_BROOT/output/sdk/bin") ||
      { di "CHERI-LLVM clang++ not found under $CHERI_BROOT/output/sdk/bin - run the image leg first"; exit 1; }
    OBJDUMP=$(find_sdk_objdump "$CHERI_BROOT/output/sdk/bin") ||
      { di "CHERI-capable objdump (riscv64cheri-objdump or llvm-objdump) not found under $CHERI_BROOT/output/sdk/bin - run the image leg first"; exit 1; }
    SYSROOT="$ROOT/$CHERI_SYSROOT_RISCV64"
    [ -d "$SYSROOT" ] || { di "purecap sysroot pin $SYSROOT absent"; exit 1; }
    # The pinned bench flag block carries the triple and the -march/-mabi on
    # every path; --sysroot is env-only and is mandatory (without it
    # #include <stdio.h> resolves against the host include root).  OBJDUMP is
    # the SDK's own CHERI objdump: the host riscv64-linux-gnu-objdump cannot
    # decode an xcheri binary (unsupported relocation type 0xc1).  The shim
    # gets the same absolute tool path, so bare `objdump` resolves there too.
    CXX="$CLANG --target=riscv64-unknown-freebsd --sysroot=$SYSROOT"
    ASM="$CLANG"
    VER_CXX=$CLANG
    SHIM_PREFIX="$OBJDUMP"
    ;;
  aarch64-morello)
    BENCH_ARCH=aarch64; TOKEN=aarch64-morello; LANE_FLAG=enable_aarch64_morello
    CLANG=$(find_sdk_clang "$CHERI_BROOT/output/morello-sdk/bin") ||
      { di "Morello-LLVM clang++ not found under $CHERI_BROOT/output/morello-sdk/bin - run the image leg first"; exit 1; }
    SYSROOT="$ROOT/$CHERI_SYSROOT_MORELLO"
    [ -d "$SYSROOT" ] || { di "purecap sysroot pin $SYSROOT absent"; exit 1; }
    # The pinned enable_aarch64_morello block carries the triple and the
    # Morello -march/-mabi on every path; --sysroot is env-only and is
    # mandatory here, same as the cheri lane above.
    CXX="$CLANG --target=aarch64-unknown-freebsd --sysroot=$SYSROOT"
    ASM="$CLANG"
    OBJDUMP=$AARCH64_OBJDUMP
    VER_CXX=$CLANG
    SHIM_PREFIX="${AARCH64_OBJDUMP%-objdump}"
    ;;
esac

SHIM_DIR="$ROOT/$BUILD_DIR/$LANE/shim"
bash "$ROOT/scripts/common/shim.sh" "$SHIM_PREFIX" "$SHIM_DIR"
export PATH="$SHIM_DIR:$PATH"

LOG="$ROOT/$BUILD_DIR/$LANE/corpus-build.log"
mkdir -p "$ROOT/$BUILD_DIR/$LANE"
SCRATCH="$ROOT/$BUILD_DIR/$LANE/stage-tree"

# ---- [1/5] scratch tree: the worktree copied out, never built in place ----
echo "== stage_corpus ($LANE): scratch tree -> $SCRATCH"
rm -rf "$SCRATCH"
mkdir -p "$SCRATCH"
tar -C "$ROOT/benchmark" \
    --exclude=./.git --exclude=./tmp --exclude=./test --exclude=./trace-log \
    -cf - . | tar -C "$SCRATCH" -xf -
# Nothing generated may be inherited from the work tree: an earlier lane's
# run-test, objects or libcfi.so in the copy would be staged as if this run had
# built them (the build products are gitignored, so a clean `git status` says
# nothing about them).  The clean recipe is `-rm -rf ...` -- the leading dash
# makes make ignore a failing `rm` -- so its exit status cannot carry the
# guarantee; assert the generated roots are actually gone instead.
env -u MAKEFLAGS -u MFLAGS -u ARCH make -C "$SCRATCH" clean
# The clean list is ARCH-scoped (lib/$(ARCH)/...), so a work tree cross-built
# for another lane keeps lib/riscv64/*.o and lib/aarch64/*.o across this
# host-ARCH clean -- exactly the objects the corpus build would reuse.
# Remove them directly; the assertion below stays the observable guarantee.
rm -f "$SCRATCH"/lib/*/assembly.o "$SCRATCH"/lib/*/indepassembly*.o
[ ! -e "$SCRATCH/run-test" ] || { di "inherited generated artifact $SCRATCH/run-test survived the scratch tree's clean"; exit 1; }
[ ! -e "$SCRATCH/lib/common/libcfi.so" ] || { di "inherited generated artifact $SCRATCH/lib/common/libcfi.so survived the scratch tree's clean"; exit 1; }
stale_obj="$(find "$SCRATCH/lib" -name '*.o' -print -quit)"
[ -z "$stale_obj" ] || { di "inherited generated artifact $stale_obj survived the scratch tree's clean"; exit 1; }

# ---- [2/5] host runner, the lane's skip token baked in ----
# The host leg must not inherit a cross toolchain or the deploy's own make
# variables: the documented override (env.sh) exports CXX/ASM/OBJDUMP, the
# Makefile's `?=` honours the environment, and MAKEFLAGS would carry the
# deploy's ARCH into the child makes.  `env -u` restores the Makefile's own
# defaults for this one invocation; CSB_TARGET_ARCH on the command line wins
# over the Makefile's own assignment, so the runner decides skips by the token
# the registry's rows are written in.
echo "== stage_corpus ($LANE): host runner (token $TOKEN)"
(cd "$SCRATCH" && env -u CXX -u ASM -u OBJDUMP -u MAKEFLAGS -u MFLAGS -u ARCH \
    make -B run-test CSB_TARGET_ARCH="$TOKEN" >/dev/null)
machine=$(readelf -h "$SCRATCH/run-test" | awk -F: '/Machine:/{gsub(/^[ \t]+/,"",$2); print $2}')
case "$machine" in
  *X86-64*) ;;
  *) di "the host runner is '$machine', not x86-64 - the host scheduler build went cross"; exit 1 ;;
esac

# ---- [3/5] corpus build: the runner owns keying and skip handling ----
# ARCH/CXX/ASM/OBJDUMP and the lane's enable flag ride the ENVIRONMENT (the
# scheduler spawns its child makes without extra arguments); MAKEFLAGS/MFLAGS
# are cleared so no ARCH from the deploy invocation leaks in.
echo "== stage_corpus ($LANE): corpus build (ARCH=$BENCH_ARCH) -> $LOG"
cd "$SCRATCH"
unset MAKEFLAGS MFLAGS ARCH
export ARCH="$BENCH_ARCH" CXX ASM OBJDUMP
if [ -n "$LANE_FLAG" ]; then export "$LANE_FLAG=yes"; fi
set +e
./run-test corpus make-only exhausted-run 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e
[ "$rc" -eq 0 ] ||
  { di "the corpus run './run-test corpus make-only exhausted-run' (ARCH=$BENCH_ARCH) exited $rc - see $LOG"; exit 1; }
[ -f results.json ] || { di "the corpus run wrote no results.json - see $LOG"; exit 1; }

# A record the lane does not skip must not fail to build: the tracked
# registry declares every platform skip explicitly, so any make-status here is
# an undeclared build failure and a hard staging error.
if grep -q '"make-status"' results.json; then
  python3 -c 'import json,sys; [print("  build failed: " + k + " (make-status " + str(v.get("make-status")) + ")", file=sys.stderr) for k,v in json.load(open(sys.argv[1])).items() if "make-status" in v]' results.json >&2 || true
  di "the corpus run reports undeclared build failures (make-status) - see $LOG"
  exit 1
fi

# ---- [4/5] stage OUT_DIR from the manifest plan ----
# The plan comes from the tracked registry and the lane's skip token, so the
# staged set is exactly the expected registry-minus-skips set: keyed units,
# registry side files, and the declared plain-name support files.  Non-unit
# build byproducts (plain binaries, objects, the scratch sys_info) are never
# staged.
mapfile -t PLAN < <(python3 "$ROOT/scripts/common/corpus_manifest.py" \
  --registry "$ROOT/benchmark/configure.json" --lane "$TOKEN" --print-plan)
[ "${#PLAN[@]}" -gt 0 ] || { di "the registry enumerates no stageable artifact for lane $LANE (token $TOKEN)"; exit 1; }

echo "== stage_corpus ($LANE): staging -> $OUT_DIR"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
cp "$ROOT/benchmark/configure.json" "$OUT_DIR/configure.json"
for row in "${PLAN[@]}"; do
  kind=${row%%$'\t'*}
  rel=${row#*$'\t'}
  [ -f "$SCRATCH/$rel" ] ||
    { di "$rel ($kind) was not produced by the corpus build - see $LOG"; exit 1; }
  mkdir -p "$OUT_DIR/$(dirname "$rel")"
  install -m 0755 "$SCRATCH/$rel" "$OUT_DIR/$rel"
done

# ---- [5/5] verify the staged set and publish the manifest ----
# corpus_manifest.py publishes manifest.json only when every check passes, so
# its presence is the deploy's proof that staging completed.
python3 "$ROOT/scripts/common/corpus_manifest.py" \
  --registry "$ROOT/benchmark/configure.json" \
  --lane "$TOKEN" \
  --tree "$OUT_DIR" \
  --out "$OUT_DIR/manifest.json" \
  --bench-commit "$bench_head" \
  --bench-tree "$(git -C "$ROOT/benchmark" describe --always --dirty)" \
  --toolchain "$("$VER_CXX" --version | head -n1)" \
  --objdump "$("$OBJDUMP" --version | head -n1)" ||
  { di "the staged corpus failed verification - see the PASS/FAIL lines above"; exit 1; }

echo "stage_corpus ($LANE): ok - $(find "$OUT_DIR/test" -type f | wc -l) files staged under $OUT_DIR/test"
