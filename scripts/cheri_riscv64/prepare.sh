#!/usr/bin/env bash
set -euo pipefail
# prepare.sh LANE [BENCH_FLAG]   (LANE = cheri_riscv64)
#
# Provisions the cheri_riscv64 system lane (plan 2026-10-14-cheri-lanes-bringup,
# Step 8).  It is the aarch64-style provisioning (lane lock, toolchain asserts,
# objdump shim, a host scheduler smoke build) *plus* the riscv64-style corpus
# staging the two CHERI lanes need (they are system-mode, not qemu-user):
#
#   - lane advisory lock (released when this script exits);
#   - asserts the pinned CHERI-LLVM clang++ and the purecap sysroot pin (an
#     earlier draft guessed output/sdk/sysroot-riscv64-purecap; the sysroot is
#     the env.sh CHERI_SYSROOT_RISCV64 pin, the path OBSERVED from the built
#     tree in Step 6 - consumed, never guessed);
#   - an objdump shim so any bare-`objdump` call resolves to the SDK's own
#     CHERI-capable objdump (the host riscv64-linux-gnu-objdump cannot decode
#     an xcheri binary); the extraction itself gets that tool via OBJDUMP;
#   - a host scheduler smoke build (ARCH=cheri_riscv64 CXX=g++, no enable flag)
#     staged as build/cheri_riscv64/run-test.host, mirroring aarch64/prepare.sh;
#   - the corpus staged by scripts/common/build_corpus.sh (derived registry via
#     --env-lane, one cross compile per unit carrying the purecap --sysroot) into
#     the lane payload dir;
#   - the cross-built guest scheduler run-test + lib/common/libcfi.so and the
#     guest runner staged into the same payload dir - that dir is the corpus-in
#     9p share root run.sh hands the guest.
#
# The CHERI cross compiler is only the SDK clang++ with the sysroot; the CHERI
# -march/-mabi/-cheri-bounds flags ride the bench Makefile's own enable flag
# (enable_riscv64_cheri), which is forwarded here as BENCH_FLAG.

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "usage: $0 LANE [BENCH_FLAG]   (LANE = cheri_riscv64; BENCH_FLAG = enable_riscv64_cheri=yes)" >&2
  exit 2
fi
LANE=$1
[ "$LANE" = cheri_riscv64 ] || { echo "usage: $0 LANE (unknown lane '$LANE')" >&2; exit 2; }
BENCH_FLAG=${2:-enable_riscv64_cheri=yes}
ENABLE_FLAG=${BENCH_FLAG%=yes}          # the make flag name
[ "$ENABLE_FLAG" = enable_riscv64_cheri ] ||
  { echo "usage: $0 LANE BENCH_FLAG   (BENCH_FLAG must be enable_riscv64_cheri=yes)" >&2; exit 2; }

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=../../env.sh
. ./env.sh

die() { echo "cheri_riscv64/prepare ($LANE): $*" >&2; exit 1; }

# ---- lane advisory lock ----
mkdir -p "$BUILD_DIR"
exec 9>"$BUILD_DIR/.lane.lock"
if ! flock -n 9; then
  die "lane busy: $(cat "$BUILD_DIR/.lane.lock" 2>/dev/null || echo unknown) holds $BUILD_DIR/.lane.lock"
fi
printf '%s\n' "$LANE" > "$BUILD_DIR/.lane.lock"

# ---- collect-and-clean on every exit path ----
cleanup() {
  rc=$?
  set +e
  make -C "$ROOT/benchmark" clean >/dev/null 2>&1
  if [ -n "$(git -C "$ROOT/benchmark" status --short)" ]; then
    echo "ERROR: benchmark submodule left dirty after clean:" >&2
    git -C "$ROOT/benchmark" status --short >&2
    rc=1
  fi
  exit "$rc"
}
trap cleanup EXIT

CHERI_BROOT="$ROOT/$BUILD_DIR/cheri"
TOKEN=$LANE                             # bench ARCH token == env lane here
LANE_DIR="$ROOT/$BUILD_DIR/$LANE"
PAYLOAD="$LANE_DIR/payload"             # the corpus-in share root run.sh exports
SHIM_DIR="$LANE_DIR/shim"
SDK_BIN="$CHERI_BROOT/output/sdk/bin"
SYSROOT="$ROOT/$CHERI_SYSROOT_RISCV64"

# ---- pinned toolchain + sysroot ----
# Keep the symlink path AS-IS: clang picks its driver mode from argv[0], and
# the SDK's clang++ links to clang-17 -- a resolved name runs in C mode and
# silently omits the C++ runtime at link.
CLANG=""
for c in "$SDK_BIN/clang++" "$SDK_BIN"/*-clang++; do
  if [ -x "$c" ]; then CLANG="$c"; break; fi
done
[ -n "$CLANG" ] || die "CHERI-LLVM clang++ not found under $SDK_BIN - run make ARCH=cheri_riscv64 deploy (the emulator/image leg builds the SDK)"
# The SDK's own CHERI-capable objdump (wrapper over llvm-objdump --mattr=...,
# +xcheri), with bare llvm-objdump as the fallback candidate.  The SDK bin dir
# is deliberately off PATH, so the resolved path is passed around explicitly.
OBJDUMP=""
for c in "$SDK_BIN/riscv64cheri-objdump" "$SDK_BIN/llvm-objdump"; do
  if [ -x "$c" ]; then OBJDUMP="$c"; break; fi
done
[ -n "$OBJDUMP" ] || die "CHERI-capable objdump (riscv64cheri-objdump or llvm-objdump) not found under $SDK_BIN - run make ARCH=cheri_riscv64 deploy (the emulator/image leg builds the SDK)"
[ -d "$SYSROOT" ] || die "purecap sysroot pin $SYSROOT absent - run make ARCH=cheri_riscv64 deploy to build it"
[ -f "$SYSROOT/usr/include/stdio.h" ] || die "$SYSROOT has no usr/include/stdio.h - not a usable sysroot"
[ -f "$SYSROOT/lib/libc.so.7" ] || die "$SYSROOT has no lib/libc.so.7 - not the riscv64-purecap sysroot"

# ---- pristine bench build state (GNU make does not rebuild on variable
# changes alone, and a stale object from another lane would be linked) ----
make -C "$ROOT/benchmark" clean >/dev/null 2>&1

# ---- objdump shim (bare-objdump safety net; the extraction uses OBJDUMP) ----
bash "$ROOT/scripts/common/shim.sh" "$OBJDUMP" "$SHIM_DIR"
export PATH="$SHIM_DIR:$PATH"

# ---- host scheduler smoke build (aarch64-style; no enable flag) ----
make -B -C "$ROOT/benchmark" run-test ARCH="$TOKEN" CXX=g++
mkdir -p "$LANE_DIR"
install -m 0755 "$ROOT/benchmark/run-test" "$LANE_DIR/run-test.host"
machine=$(readelf -h "$LANE_DIR/run-test.host" | awk -F: '/Machine:/{gsub(/^[ \t]+/,"",$2); print $2}')
case "$machine" in
  *X86-64*) ;;
  *) die "staged run-test.host is '$machine', not x86-64 - the host scheduler build went cross" ;;
esac

# ---- corpus staging (riscv64-style) into the payload dir ----
bash "$ROOT/scripts/common/build_corpus.sh" "$TOKEN" "$PAYLOAD" \
  --env-lane "$LANE" --enable-flag "$ENABLE_FLAG"

# ---- cross-built guest scheduler + libcfi, staged for the guest ----
# run-test and lib/common/libcfi.so link the purecap corpus; the CXX carries
# the sysroot (without it #include <stdio.h> resolves against the host root).
make -B -C "$ROOT/benchmark" run-test lib/common/libcfi.so \
  "${ENABLE_FLAG}=yes" \
  ARCH="$TOKEN" \
  CXX="$CLANG --target=riscv64-unknown-freebsd --sysroot=$SYSROOT" \
  ASM="$CLANG" OBJDUMP="$OBJDUMP"
install -m 0755 "$ROOT/benchmark/run-test" "$PAYLOAD/run-test"
mkdir -p "$PAYLOAD/lib/common"
install -m 0755 "$ROOT/benchmark/lib/common/libcfi.so" "$PAYLOAD/lib/common/libcfi.so"

# ---- the guest runner rides the corpus-in share ----
install -m 0755 "$ROOT/scripts/cheri/guest/runner" "$PAYLOAD/runner"

echo "cheri_riscv64/prepare ($LANE): ok - payload at $PAYLOAD ($(find "$PAYLOAD/test" -type f | wc -l) corpus files), run-test.host staged"