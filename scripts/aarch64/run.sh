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
  if [ "$rc" -eq 124 ]; then
    echo "aarch64 lane ($LANE) aborted on timeout (124): publishing nothing" >&2
  else
    mkdir -p "$DEST"
    for f in results.json results.dat variables.json; do
      [ -f "benchmark/$f" ] && cp -f "benchmark/$f" "$DEST/"
    done
    ENABLE_FLAG="$ENABLE_FLAG" bash scripts/common/version_stamp.sh "$LANE" "$DEST/versions.txt"
    echo "collected $LANE lane artifacts into $DEST"
  fi
  make -C benchmark clean >/dev/null 2>&1
  assert_rc=0
  if [ -n "$(git -C benchmark status --short)" ]; then
    echo "ERROR: benchmark submodule left dirty after clean:" >&2
    git -C benchmark status --short >&2
    assert_rc=1
  fi
  if [ "$rc" -ne 0 ]; then exit "$rc"; fi
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
# env.sh AARCH64_CXX pin).  For the MTE lane QEMU_CPU=max,mte=on (the env.sh
# QEMU_CPU_AARCH64_MTE pin) rides the environment through binfmt into
# qemu-aarch64.
mf="ARCH=$ARCH CXX=$AARCH64_CXX ASM=$AARCH64_AS OBJDUMP=$AARCH64_OBJDUMP"
if [ -n "$ENABLE_FLAG" ]; then
  mf="$mf $ENABLE_FLAG=yes"
fi
export MAKEFLAGS="$mf"
if [ "$LANE" = aarch64-mte ]; then
  export QEMU_CPU="$QEMU_CPU_AARCH64_MTE"
fi

# Subshell cd: the EXIT trap must fire with cwd at the repo root, or every
# relative path in it (results/, benchmark/$f, make -C benchmark) resolves
# inside the submodule and the collection silently does nothing.
(cd benchmark && timeout "$LANE_RUN_TIMEOUT" ./run-test exhausted-run)
