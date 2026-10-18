#!/usr/bin/env bash
set -euo pipefail
# prepare.sh LANE [BENCH_FLAG]   (LANE = aarch64-morello)
#
# Provisions the aarch64-morello system lane (plan 2026-10-14-cheri-lanes-bringup,
# Step 8).  Structurally the twin of scripts/cheri_riscv64/prepare.sh: the
# aarch64-style provisioning (lane lock, toolchain asserts, objdump shim, a host
# scheduler smoke build) plus the riscv64-style corpus staging the two CHERI
# lanes need.  Lane-name vs bench-token: the ENV lane is "aarch64-morello" but
# the bench token is "aarch64" (the bench Makefile forces ARCH := aarch64 under
# enable_aarch64_morello), so the corpus and scheduler builds use ARCH=aarch64.
#
#   - lane advisory lock (released when this script exits);
#   - asserts the pinned Morello-LLVM clang++ and the purecap sysroot pin (the
#     env.sh CHERI_SYSROOT_MORELLO pin - the path OBSERVED from the built tree
#     in Step 6);
#   - an objdump shim so the bench's bare-`objdump` opcode extraction resolves
#     to the host aarch64-linux-gnu-objdump.  (Objdump-shim boundary decision:
#     the alternative for Morello - the SDK's llvm-objdump behind an adapter, or
#     excluding acc-read-func via the Step 10 skip map - is deferred; if the GNU
#     objdump cannot read a Morello purecap ELF, Step 10 takes one of those.)
#   - a host scheduler smoke build (ARCH=aarch64 CXX=g++, no enable flag) staged
#     as build/aarch64-morello/run-test.host, mirroring aarch64/prepare.sh;
#   - the corpus staged by scripts/common/build_corpus.sh (derived registry via
#     --env-lane aarch64-morello, one cross compile per unit carrying the purecap
#     --sysroot) into the lane payload dir;
#   - the cross-built guest scheduler run-test + lib/common/libcfi.so and the
#     guest runner staged into the same payload dir - the corpus-in 9p share root
#     run.sh hands the guest.
#
# The Morello cross compiler is the SDK clang++ with the sysroot; --target and
# -march=morello -mabi=purecap ride the bench Makefile's own enable flag
# (enable_aarch64_morello), forwarded here as BENCH_FLAG.

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "usage: $0 LANE [BENCH_FLAG]   (LANE = aarch64-morello; BENCH_FLAG = enable_aarch64_morello=yes)" >&2
  exit 2
fi
LANE=$1
[ "$LANE" = aarch64-morello ] || { echo "usage: $0 LANE (unknown lane '$LANE')" >&2; exit 2; }
BENCH_FLAG=${2:-enable_aarch64_morello=yes}
ENABLE_FLAG=${BENCH_FLAG%=yes}          # the make flag name
[ "$ENABLE_FLAG" = enable_aarch64_morello ] ||
  { echo "usage: $0 LANE BENCH_FLAG   (BENCH_FLAG must be enable_aarch64_morello=yes)" >&2; exit 2; }

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=../../env.sh
. ./env.sh

die() { echo "morello/prepare ($LANE): $*" >&2; exit 1; }

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
TOKEN=aarch64                           # bench ARCH token (the Morello flag forces it)
LANE_DIR="$ROOT/$BUILD_DIR/$LANE"
PAYLOAD="$LANE_DIR/payload"             # the corpus-in share root run.sh exports
SHIM_DIR="$LANE_DIR/shim"
SDK_BIN="$CHERI_BROOT/output/morello-sdk/bin"
SYSROOT="$ROOT/$CHERI_SYSROOT_MORELLO"

# ---- pinned toolchain + sysroot ----
# Keep the symlink path AS-IS: clang picks its driver mode from argv[0], and
# the SDK's clang++ links to clang-17 -- a resolved name runs in C mode and
# silently omits the C++ runtime at link.
CLANG=""
for c in "$SDK_BIN/clang++" "$SDK_BIN"/*-clang++; do
  if [ -x "$c" ]; then CLANG="$c"; break; fi
done
[ -n "$CLANG" ] || die "Morello-LLVM clang++ not found under $SDK_BIN - run make ARCH=aarch64-morello deploy (the emulator/image leg builds the SDK)"
[ -d "$SYSROOT" ] || die "purecap sysroot pin $SYSROOT absent - run make ARCH=aarch64-morello deploy to build it"
[ -f "$SYSROOT/usr/include/stdio.h" ] || die "$SYSROOT has no usr/include/stdio.h - not a usable sysroot"
[ -f "$SYSROOT/lib/libc.so.7" ] || die "$SYSROOT has no lib/libc.so.7 - not the morello-purecap sysroot"

# ---- pristine bench build state (GNU make does not rebuild on variable
# changes alone, and a stale object from another lane would be linked) ----
make -C "$ROOT/benchmark" clean >/dev/null 2>&1

# ---- objdump shim (the func-opcode extraction calls bare objdump) ----
bash "$ROOT/scripts/common/shim.sh" "${AARCH64_OBJDUMP%-objdump}" "$SHIM_DIR"
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
# The CXX carries the purecap sysroot: the pinned enable_aarch64_morello block
# puts the triple and the morello -march/-mabi on CXXFLAGS, but never the
# sysroot (without it #include <stdio.h> resolves against the host root).
make -B -C "$ROOT/benchmark" run-test lib/common/libcfi.so \
  "${ENABLE_FLAG}=yes" \
  ARCH="$TOKEN" \
  CXX="$CLANG --target=aarch64-unknown-freebsd --sysroot=$SYSROOT" \
  ASM="$CLANG" OBJDUMP="$AARCH64_OBJDUMP"
install -m 0755 "$ROOT/benchmark/run-test" "$PAYLOAD/run-test"
mkdir -p "$PAYLOAD/lib/common"
install -m 0755 "$ROOT/benchmark/lib/common/libcfi.so" "$PAYLOAD/lib/common/libcfi.so"

# ---- the guest runner rides the corpus-in share ----
install -m 0755 "$ROOT/scripts/cheri/guest/runner" "$PAYLOAD/runner"

echo "morello/prepare ($LANE): ok - payload at $PAYLOAD ($(find "$PAYLOAD/test" -type f | wc -l) corpus files), run-test.host staged"