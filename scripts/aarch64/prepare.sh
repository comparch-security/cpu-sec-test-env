#!/usr/bin/env bash
set -euo pipefail
# prepare.sh LANE   (LANE = aarch64 | aarch64-pa | aarch64-bti | aarch64-mte)
#
# Provisions and pre-builds the aarch64 qemu-user lane:
#   - asserts the pinned cross toolchain, qemu-aarch64 at the env.sh pin and
#     the pinned cross sysroot (loader present and runnable through binfmt;
#     for the MTE lane the hwasan runtime resolvable);
#   - verifies the binfmt handler by READING
#     /proc/sys/fs/binfmt_misc/qemu-aarch64 (exists, enabled, interpreter
#     names the pinned qemu-aarch64) - never writes to the node;
#   - creates the objdump shim (the bare-`objdump` safety net; the extraction
#     itself is routed through the OBJDUMP knob);
#   - builds the scheduler as a HOST binary with `make -B` and only
#     ARCH/CXX/ASM/OBJDUMP on the command line (never any scheduler-cxxflags
#     override - the bench Makefile's own assembly, including
#     -DCSB_TARGET_ARCH from ARCH, stays authoritative), then stages the
#     binary as
#     build/<lane>/run-test.host so the x86-64 evidence survives the
#     end-of-lane clean;
#   - overwrites benchmark/test/sys_info.txt with the lane's guest-truth
#     header: the qemu-aarch64 version, CPU model, the binfmt interpreter
#     line, sysroot + glibc, the composed MAKEFLAGS (including
#     $ENABLE_FLAG=yes when set), and the host kernel - qemu-user runs on
#     the host kernel, and saying so is the honest record.

if [ $# -ne 1 ]; then
  echo "usage: $0 LANE   (LANE = aarch64 | aarch64-pa | aarch64-bti | aarch64-mte)" >&2
  exit 2
fi
LANE=$1
case "$LANE" in
  aarch64|aarch64-pa|aarch64-bti|aarch64-mte) ;;
  *)
    echo "usage: $0 LANE   (unknown lane '$LANE')" >&2
    exit 2
    ;;
esac

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=../../env.sh
. ./env.sh

die() { echo "aarch64/prepare ($LANE): $*" >&2; exit 1; }

# ---- lane advisory lock (released when this script exits) ----
mkdir -p "$BUILD_DIR"
exec 9>"$BUILD_DIR/.lane.lock"
if ! flock -n 9; then
  die "lane busy: $(cat "$BUILD_DIR/.lane.lock" 2>/dev/null || echo unknown) holds $BUILD_DIR/.lane.lock"
fi
printf '%s\n' "$LANE" > "$BUILD_DIR/.lane.lock"

ARCH=aarch64
ENABLE_FLAG=${ENABLE_FLAG:-}
LANE_DIR="$BUILD_DIR/$LANE"
SHIM_DIR="$LANE_DIR/shim"

# ---- pinned toolchain + emulator + sysroot ----
for tool in "$AARCH64_CXX" "$AARCH64_AS" "$AARCH64_OBJDUMP"; do
  command -v "$tool" >/dev/null 2>&1 || die "cross tool '$tool' not on PATH (prerequisite apt install missing)"
done
command -v "$QEMU_AARCH64" >/dev/null 2>&1 || die "$QEMU_AARCH64 not on PATH (prerequisite apt install missing)"
qemu_ver=$("$QEMU_AARCH64" --version | head -1)
case "$qemu_ver" in
  *"$QEMU_VERSION"*) ;;
  *) die "$QEMU_AARCH64 reports '$qemu_ver' but env.sh pins $QEMU_VERSION" ;;
esac

loader="$AARCH64_SYSROOT/lib/ld-linux-aarch64.so.1"
[ -x "$loader" ] || die "sysroot loader $loader missing (pinned sysroot $AARCH64_SYSROOT not provisioned)"
# Run the loader through binfmt: this doubles as an end-to-end handler smoke.
glibc_ver=$("$loader" --version 2>/dev/null | head -1) ||
  die "cannot execute $loader through binfmt - the qemu-aarch64 handler is not working"

if [ "$LANE" = aarch64-mte ]; then
  hwasan=$("$AARCH64_CXX" -print-file-name=libhwasan.so)
  case "$hwasan" in
    /*) [ -f "$hwasan" ] || die "libhwasan.so resolved to $hwasan but the file is absent" ;;
    *)  die "libhwasan.so not resolvable via $AARCH64_CXX - libhwasan0-arm64-cross missing" ;;
  esac
fi

# ---- binfmt handler: read-only verification ----
node=/proc/sys/fs/binfmt_misc/qemu-aarch64
[ -e "$node" ] || die "binfmt handler $node absent - qemu-user-binfmt not provisioned (user action: apt install qemu-user-binfmt)"
first_line=$(head -1 "$node")
[ "$first_line" = enabled ] || die "binfmt handler $node is '$first_line', not enabled - the lane would not execute aarch64 ELFs"
pinned_qemu=$(command -v "$QEMU_AARCH64")
interp=$(awk '/^interpreter/{print $2}' "$node")
[ -n "$interp" ] || die "binfmt handler $node has no interpreter line"
[ "$interp" = "$pinned_qemu" ] ||
  die "binfmt handler $node interprets via '$interp' but env.sh pins '$pinned_qemu'"

# ---- pristine bench build state ----
# The scheduler's no-conf-macro child makes run a bare `make test/<prog>`
# without -B: object files left by a previous lane (cross-built for another
# ARCH) or by an interrupted run would be linked instead of rebuilt, and the
# link fails against this lane's freshly built objects.  Wipe them here,
# before this lane builds anything, so every unit make compiles from source.
# (GNU make does not rebuild on variable changes alone - the same trap the
# -B scheduler build below exists for.)
make -C "$ROOT/benchmark" clean

# ---- objdump shim (the bare-`objdump` safety net; extraction uses the knob) ----
bash "$ROOT/scripts/common/shim.sh" "${AARCH64_OBJDUMP%-objdump}" "$SHIM_DIR"

# ---- scheduler as a host binary ----
# make -B: GNU make does not rebuild on variable changes alone, and a stale
# scheduler from an interrupted lane must never be reused.  Only
# ARCH/CXX/ASM/OBJDUMP ride the command line; no scheduler-cxxflags override.
make -B -C benchmark run-test \
  ARCH="$ARCH" CXX=g++ ASM="$AARCH64_AS" OBJDUMP="$AARCH64_OBJDUMP"
mkdir -p "$LANE_DIR"
install -m 0755 benchmark/run-test "$LANE_DIR/run-test.host"
# The scheduler must never become a cross binary: machine 62 = x86-64.
machine=$(readelf -h "$LANE_DIR/run-test.host" | awk -F: '/Machine:/{gsub(/^[ \t]+/,"",$2); print $2}')
case "$machine" in
  *X86-64*) ;;
  *) die "staged run-test.host is '$machine', not x86-64 - the scheduler build went cross" ;;
esac

# ---- guest-truth header (overwrites the Makefile's generic sys_info.txt) ----
# The MAKEFLAGS composition below MUST match scripts/aarch64/run.sh exactly:
# this is the same string the scheduler's child makes will receive.
mf="ARCH=$ARCH CXX=$AARCH64_CXX ASM=$AARCH64_AS OBJDUMP=$AARCH64_OBJDUMP"
if [ -n "$ENABLE_FLAG" ]; then
  mf="$mf $ENABLE_FLAG=yes"
fi
if [ "$LANE" = aarch64-mte ]; then
  cpu_model="$QEMU_CPU_AARCH64_MTE"
else
  cpu_model="max (qemu-aarch64 default)"
fi
mkdir -p benchmark/test
{
  echo "lane: $LANE"
  echo "CPU: $cpu_model (emulated by $QEMU_AARCH64)"
  echo "System: qemu-user via binfmt_misc on host kernel $(uname -sr) - the scheduler is a host binary; test binaries are aarch64 ELFs executed by $QEMU_AARCH64"
  echo "emulator: $qemu_ver"
  echo "binfmt: $(awk '/^interpreter/{printf "%s %s", $1, $2}' "$node") (handler $node)"
  echo "MAKEFLAGS: $mf"
  echo "objdump (test binaries): $AARCH64_OBJDUMP -> $(command -v "$AARCH64_OBJDUMP") ($("$AARCH64_OBJDUMP" --version | head -1))"
  echo "sysroot: $AARCH64_SYSROOT"
  echo "LIBC: $glibc_ver"
  echo "Compiler (test binaries): $AARCH64_CXX ($("$AARCH64_CXX" --version | head -1))"
  echo "Scheduler compiler (host): g++ ($(g++ --version | head -1))"
} > benchmark/test/sys_info.txt

echo "aarch64/prepare ($LANE): ok - scheduler staged at $LANE_DIR/run-test.host, sys_info.txt written"
