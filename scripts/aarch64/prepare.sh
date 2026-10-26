#!/usr/bin/env bash
set -euo pipefail
# prepare.sh LANE   (LANE = aarch64 | aarch64-pa | aarch64-bti | aarch64-mte)
#
# Provisions and pre-builds the aarch64 qemu-user lane:
#   - asserts the pinned cross toolchain, qemu-aarch64 at the env.sh pin and
#     the pinned cross sysroot (loader present and runnable through binfmt;
#     for the MTE lane the hwasan runtime resolvable; for the PA lane a build
#     of the lane's own -march=armv8.3-a+pauth -mbranch-protection=pac-ret
#     class executable under the lane's CPU request);
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
#     header: the qemu-aarch64 version, the CPU request set beside the
#     execution actually observed under it, the binfmt interpreter line,
#     sysroot + glibc, the composed MAKEFLAGS (including $ENABLE_FLAG=yes
#     when set), and the host kernel - qemu-user runs on the host kernel, and
#     saying so is the honest record.

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

# Defence in depth, before any qemu-aarch64 invocation: env.sh never exports
# QEMU_VERSION, but an inherited one (the invoking shell, a wrapper) makes
# qemu-aarch64 print its version banner and exit 0 for ANY value - before
# parsing -cpu and before loading a guest - which is how 21 aarch64 stamps
# became non-execution records.
unset QEMU_VERSION

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
  *"$QEMU_PIN_VERSION"*) ;;
  *) die "$QEMU_AARCH64 reports '$qemu_ver' but env.sh pins $QEMU_PIN_VERSION" ;;
esac

loader="$AARCH64_SYSROOT/lib/ld-linux-aarch64.so.1"
[ -x "$loader" ] || die "sysroot loader $loader missing (pinned sysroot $AARCH64_SYSROOT not provisioned)"

# ---- the effective CPU request (run.sh applies the same rule) ----
# The request-bearing lanes SET the pin; the request-less lanes explicitly
# UNSET an ambient QEMU_CPU, so a value inherited from the invoking shell (or
# `make ... QEMU_CPU=...`, which GNU make exports into recipe environments)
# cannot ride through binfmt into all 246 cases while the header below records
# "unset".  The smokes and the header read the RESULT of this rule, never the
# lane rule.
case "$LANE" in
  aarch64-mte) export QEMU_CPU="$QEMU_CPU_AARCH64_MTE" ;;
  aarch64-pa)  export QEMU_CPU="$QEMU_CPU_AARCH64_PA" ;;
  *)           unset QEMU_CPU ;;
esac
# The guest side of the smokes: run.sh exports the same prefix, and a
# dynamically linked guest binary needs it to resolve the sysroot's loader and
# libraries.
export QEMU_LD_PREFIX="$AARCH64_SYSROOT"

# Run the loader through binfmt under that request: an end-to-end handler smoke
# AND a pin-acceptance check (a rejected QEMU_CPU fails here).  It asserts
# CONTENT, not rc alone: rc alone is what let an exported QEMU_VERSION make
# every case print the emulator's version banner and exit 0 - that made
# 21 void aarch64 stamps (2026-10-13..24, the derived `# LIBC:` banner census).
# Only a line produced by the guest's own loader proves the guest executed.
smoke_out=$("$loader" --version 2>&1) || {
  smoke_rc=$?
  die "binfmt smoke failed (QEMU_CPU='${QEMU_CPU:-unset}', rc=$smoke_rc): $smoke_out"
}
glibc_ver=${smoke_out%%$'\n'*}
case "$glibc_ver" in
  *"ld.so (Ubuntu GLIBC"*) ;;
  *)
    die "binfmt smoke executed nothing (QEMU_CPU='${QEMU_CPU:-unset}'): expected the loader's 'ld.so (Ubuntu GLIBC ...)' line, saw '$glibc_ver' - a zero-execution route (e.g. an exported QEMU_VERSION makes qemu-aarch64 print its banner and exit 0)"
    ;;
esac

# Lane-representative execution: the loader smoke above runs the sysroot's own
# loader, which is PAC-free and MTE-free, so it cannot catch a build class the
# venue cannot execute.  Each request-bearing lane therefore builds and runs a
# program of its corpus's own class under its request, so an unusable request
# fails the deploy instead of poisoning a stamp.
# The bti lane deliberately has NO leg: -mbranch-protection=bti emits BTI
# landing-pad hints, which a CPU model without FEAT_BTI executes as NOPs -
# nothing can fault, so a leg there would assert nothing.  The pa leg exists
# because retaa is a real instruction: the corpus is built with
# -march=armv8.3-a+pauth -mbranch-protection=pac-ret (bench Makefile), and on
# a model without FEAT_PAuth 226 of 246 records of the lane's first
# really-executing stamp became 256+SIGILL (2026-10-25).
if [ "$LANE" = aarch64-pa ]; then
  pa_dir="tmp/aarch64-prepare-smoke/$LANE"
  mkdir -p "$pa_dir"
  cat > "$pa_dir/pa-smoke.c" <<'SMOKE_SRC'
#include <stdio.h>
static __attribute__((noinline)) int pa_smoke_leaf(int x) { return x + 1; }
int main(void) {
  int v = pa_smoke_leaf(41);
  printf("aarch64-pa smoke: pac-ret executed (%d)\n", v);
  return v == 42 ? 0 : 1;
}
SMOKE_SRC
  "$AARCH64_CXX" -O1 -static -march=armv8.3-a+pauth -mbranch-protection=pac-ret \
    -o "$pa_dir/pa-smoke" "$pa_dir/pa-smoke.c" ||
    die "pa smoke build failed ($AARCH64_CXX -march=armv8.3-a+pauth -mbranch-protection=pac-ret)"
  pa_out=$("$pa_dir/pa-smoke" 2>&1) || {
    pa_rc=$?
    die "pa smoke did not execute the lane's own build class under QEMU_CPU='${QEMU_CPU:-unset}' (rc=$pa_rc): $pa_out"
  }
  case "$pa_out" in
    *"aarch64-pa smoke: pac-ret executed"*) ;;
    *)
      die "pa smoke ran, but not the lane's own build class (QEMU_CPU='${QEMU_CPU:-unset}'): saw '$pa_out'"
      ;;
  esac
fi

if [ "$LANE" = aarch64-mte ]; then
  hwasan=$("$AARCH64_CXX" -print-file-name=libhwasan.so)
  case "$hwasan" in
    /*) [ -f "$hwasan" ] || die "libhwasan.so resolved to $hwasan but the file is absent" ;;
    *)  die "libhwasan.so not resolvable via $AARCH64_CXX - libhwasan0-arm64-cross missing" ;;
  esac
  mte_dir="tmp/aarch64-prepare-smoke/$LANE"
  mkdir -p "$mte_dir"
  cat > "$mte_dir/mte-smoke.c" <<'SMOKE_SRC'
#include <unistd.h>
int main(void) {
  static const char msg[] = "aarch64-mte smoke: hwasan class executed\n";
  return write(1, msg, sizeof msg - 1) == (long)(sizeof msg - 1) ? 0 : 1;
}
SMOKE_SRC
  "$AARCH64_CXX" -O1 -march=armv8.5-a+memtag -fsanitize=hwaddress \
    -o "$mte_dir/mte-smoke" "$mte_dir/mte-smoke.c" ||
    die "mte smoke build failed ($AARCH64_CXX -march=armv8.5-a+memtag -fsanitize=hwaddress)"
  # The program's own line is the primary proof: when main printed it, the
  # lane's build class executed.  The HWASan runtime still aborts at exit on
  # this venue - qemu-user cannot run its LeakSanitizer leg ("does not work
  # under ptrace"), so a clean exit is not this venue's shape and must not be
  # an acceptance condition.  When the runtime aborts BEFORE any output (rc 99,
  # the sanitizer's own process value) its own report is the same evidence that
  # the class ran.  Anything else - SIGILL from a model without FEAT_MTE, a
  # missing loader, wrong output - fails the deploy loudly.
  if mte_out=$("$mte_dir/mte-smoke" 2>&1); then
    mte_rc=0
  else
    mte_rc=$?
  fi
  case "$mte_out" in
    *"aarch64-mte smoke: hwasan class executed"*)
      echo "aarch64/prepare ($LANE): mte smoke executed the lane's build class (rc=$mte_rc): $(printf '%s' "$mte_out" | grep 'aarch64-mte smoke')" >&2
      ;;
    *)
      case "$mte_out" in
        *HWAddressSanitizer*|*LeakSanitizer*) mte_report=1 ;;
        *) mte_report=0 ;;
      esac
      if [ "$mte_rc" -eq 99 ] && [ "$mte_report" -eq 1 ]; then
        echo "aarch64/prepare ($LANE): mte smoke ran the HWASan runtime (rc=99, its own report)" >&2
      else
        die "mte smoke did not execute the lane's own build class under QEMU_CPU='${QEMU_CPU:-unset}' (rc=$mte_rc): $mte_out"
      fi
      ;;
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
# The CPU line records the REQUEST actually in effect (the request-less lanes
# cleared any inherited value above) and, separately, the OBSERVATION - the
# loader line the smoke produced under that request - so a stamp says what was
# in effect, never what was intended.  The header used to be written from the
# pin alone, which advertised a CPU model that was never applied.
if [ -n "${QEMU_CPU:-}" ]; then
  cpu_request_text="QEMU_CPU=$QEMU_CPU"
else
  cpu_request_text="unset (qemu-aarch64's default CPU model)"
fi
mkdir -p benchmark/test
{
  echo "lane: $LANE"
  echo "CPU request: $cpu_request_text"
  echo "CPU observation: the guest executed under that request - $glibc_ver"
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
