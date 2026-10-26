#!/usr/bin/env bash
set -euo pipefail
# run.sh LANE   (LANE = aarch64 | aarch64-pa | aarch64-bti | aarch64-mte)
#
# Runs the bench suite for the aarch64 qemu-user lane.  The scheduler is the
# host binary prepared by prepare.sh (CSB_TARGET_ARCH=aarch64 baked at build
# time); every test binary is an aarch64 ELF executed by the kernel's
# binfmt_misc handler (qemu-aarch64) - RUN_PREFIX in the bench is an
# environment injection, not a command prefix, so binfmt is the execution
# route.  The scheduler's own child makes receive the cross toolchain and the
# lane's enable flag through MAKEFLAGS at command-line strength (the bench's
# Makefile assigns CXX/ASM/OBJDUMP with :=, which beats the environment; the
# route is documented in doc/porting.html).  Never pass SCHEDULER_CXXFLAGS.
#
# An EXIT trap collects whatever artifacts exist into
# results/<lane>/<stamp>/, runs `make -C benchmark clean` and asserts the
# submodule is clean - on failure paths too.  A run that hits the lane
# timeout (exit 124) aborts without publishing anything.

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

die() { echo "aarch64/run ($LANE): $*" >&2; exit 1; }

# ---- lane advisory lock ----
mkdir -p "$BUILD_DIR"
exec 9>"$BUILD_DIR/.lane.lock"
if ! flock -n 9; then
  die "lane busy: $(cat "$BUILD_DIR/.lane.lock" 2>/dev/null || echo unknown) holds $BUILD_DIR/.lane.lock"
fi
printf '%s\n' "$LANE" > "$BUILD_DIR/.lane.lock"

ARCH=aarch64
ENABLE_FLAG=${ENABLE_FLAG:-}
SHIM_DIR="$ROOT/$BUILD_DIR/$LANE/shim"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
DEST="$RESULTS_DIR/$LANE/$STAMP"

# ---- collect + clean + assert, on every exit path ----
cleanup() {
  rc=$?
  set +e
  collect_rc=0
  if [ "$rc" -eq 124 ]; then
    echo "aarch64 lane ($LANE) aborted on timeout (124): publishing nothing" >&2
  else
    mkdir -p "$DEST"
    # variables.json is legitimately absent on the mte lane (no set-var
    # producer survives the HWASan build), so absence is not a collection
    # failure; a FAILED copy is, and names the artifact.
    for f in results.json results.dat variables.json; do
      [ -f "benchmark/$f" ] || continue
      cp -f "benchmark/$f" "$DEST/" || {
        echo "ERROR: could not collect benchmark/$f into $DEST" >&2
        collect_rc=1
      }
    done
    if ! ENABLE_FLAG="$ENABLE_FLAG" bash scripts/common/version_stamp.sh "$LANE" "$DEST/versions.txt" ||
       [ ! -s "$DEST/versions.txt" ]; then
      echo "ERROR: version_stamp.sh did not write $DEST/versions.txt" >&2
      collect_rc=1
    fi
    if [ "$collect_rc" -eq 0 ]; then
      echo "collected $LANE lane artifacts into $DEST"
    else
      echo "ERROR: the stamp in $DEST is INCOMPLETE (see the errors above)" >&2
    fi
  fi
  make -C benchmark clean >/dev/null 2>&1
  assert_rc=0
  # A failing git is not a clean tree: an absent binary, a broken .git, a held
  # index.lock or a dubious-ownership refusal yields empty output that would
  # otherwise read as "clean".  Only rc 0 with empty output means clean.
  dirty=$(git -C benchmark status --short)
  git_rc=$?
  if [ "$git_rc" -ne 0 ]; then
    echo "ERROR: cannot verify the benchmark submodule is clean: 'git -C benchmark status --short' failed (rc=$git_rc)" >&2
    assert_rc=1
  elif [ -n "$dirty" ]; then
    echo "ERROR: benchmark submodule left dirty after clean:" >&2
    printf '%s\n' "$dirty" >&2
    assert_rc=1
  fi
  if [ "$rc" -ne 0 ]; then exit "$rc"; fi
  if [ "$collect_rc" -ne 0 ]; then exit "$collect_rc"; fi
  exit "$assert_rc"
}
trap cleanup EXIT

# The shim may already exist from prepare.sh; recreate if the lane dir was
# cleaned in between (the bare-`objdump` safety net; the extraction itself is
# routed through the OBJDUMP knob).
[ -x "$SHIM_DIR/objdump" ] ||
  bash scripts/common/shim.sh "${AARCH64_OBJDUMP%-objdump}" "$SHIM_DIR"
export PATH="$SHIM_DIR:$PATH"

# ---- tool-resolution audit (the deferral's ask: which objdump is in play) ----
# (a) the tool the extraction will use - the knob value the child makes get
#     through MAKEFLAGS; (b) what a bare `objdump` resolves to through the
#     shim now that the shim dir is $ROOT-anchored.
echo "aarch64/run ($LANE): extraction objdump: $(command -v "$AARCH64_OBJDUMP") ($("$AARCH64_OBJDUMP" --version | head -1))"
echo "aarch64/run ($LANE): bare objdump resolves to: $(command -v objdump) ($(objdump --version | head -1))"

# QEMU_LD_PREFIX pins the loader/sysroot qemu-aarch64 resolves for every
# aarch64 ELF the kernel hands it through binfmt.
export QEMU_LD_PREFIX="$AARCH64_SYSROOT"

# The lane's MAKEFLAGS - MUST match the composition in prepare.sh (the
# sys_info header records the same string).  Command-line strength for the
# scheduler's child makes: CXX resolves to aarch64-linux-gnu-g++-13 (the
# env.sh AARCH64_CXX pin).  The CPU request (the same rule prepare.sh applies):
# for the MTE lane QEMU_CPU=max (the env.sh QEMU_CPU_AARCH64_MTE pin - the
# venue's default model plus PAuth, pinned so the lane's claim is legible; it
# already advertises HWCAP2_MTE and enforces tag checks, and unlike the pa pin
# it is not load-bearing) and for the PA lane QEMU_CPU=max (the env.sh
# QEMU_CPU_AARCH64_PA pin - a PAuth-capable model; the default model has no
# FEAT_PAuth and the lane's retaa epilogue would SIGILL).  Both ride the
# environment through binfmt into qemu-aarch64; prepare.sh runs the same request
# through its binfmt smokes, so a pin this emulator rejects - or cannot execute
# the lane's own build class under - fails the deploy instead of every case.
# The request-less lanes clear an ambient QEMU_CPU instead of inheriting it,
# and QEMU_VERSION is dropped outright: an inherited value makes qemu-aarch64
# print its banner and exit 0 before parsing -cpu or loading any guest.
mf="ARCH=$ARCH CXX=$AARCH64_CXX ASM=$AARCH64_AS OBJDUMP=$AARCH64_OBJDUMP"
if [ -n "$ENABLE_FLAG" ]; then
  mf="$mf $ENABLE_FLAG=yes"
fi
export MAKEFLAGS="$mf"
unset QEMU_VERSION
case "$LANE" in
  aarch64-mte) export QEMU_CPU="$QEMU_CPU_AARCH64_MTE" ;;
  aarch64-pa)  export QEMU_CPU="$QEMU_CPU_AARCH64_PA" ;;
  *)           unset QEMU_CPU ;;
esac

# Subshell cd: the EXIT trap must fire with cwd at the repo root, or every
# relative path in it (results/, benchmark/$f, make -C benchmark) resolves
# inside the submodule and the collection silently does nothing.
(cd benchmark && timeout "$LANE_RUN_TIMEOUT" ./run-test exhausted-run)
