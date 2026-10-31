#!/usr/bin/env bash
set -euo pipefail
# run.sh LANE   (LANE = riscv64)
#
# Boots the deployed riscv64 image under qemu-system-riscv64 (virt machine,
# OpenSBI default firmware, the env.sh-pinned -cpu rva23s64 profile model)
# with the stamped results directory exported to the guest over virtio-9p.
# The guest
# (scripts/riscv64/guest/init) runs the prebuilt corpus with
# `./run-test no-make corpus exhausted-run` and copies its results onto the
# share;
# no console parsing, no privileges.
#
# An EXIT trap collects whatever the guest left on the share into
# results/<lane>/<stamp>/, writes versions.txt, runs `make -C benchmark
# clean` and asserts the submodule clean - on failure paths too.  A run that
# hits the lane timeout (exit 124) aborts without publishing anything.  The
# lane is green only if the extracted results.json carries the full record
# set of the tracked registry.

if [ $# -ne 1 ] || [ "$1" != riscv64 ]; then
  echo "usage: $0 riscv64" >&2
  exit 2
fi
LANE=$1

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=../../env.sh
. ./env.sh

die() { echo "riscv64/run ($LANE): $*" >&2; exit 1; }

# ---- lane advisory lock ----
mkdir -p "$BUILD_DIR"
exec 9>>"$BUILD_DIR/.lane.lock"
if ! flock -n 9; then
  die "lane busy: $(cat "$BUILD_DIR/.lane.lock" 2>/dev/null || echo unknown) holds $BUILD_DIR/.lane.lock"
fi
printf '%s\n' "$LANE" > "$BUILD_DIR/.lane.lock"

BUILDD="$ROOT/$BUILD_DIR/riscv64"
IMAGE="$BUILDD/Image"
CPIO="$BUILDD/rootfs.cpio"
SHARE="$BUILDD/share"          # 9p export while the guest runs
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
DEST="$RESULTS_DIR/$LANE/$STAMP"

[ -f "$IMAGE" ] || die "$IMAGE missing - run make ARCH=riscv64 deploy first"
[ -f "$CPIO" ] || die "$CPIO missing - run make ARCH=riscv64 deploy first"

rm -rf "$SHARE"
mkdir -p "$SHARE"

# ---- collect + clean + assert, on every exit path ----
cleanup() {
  rc=$?
  set +e
  if [ "$rc" -eq 124 ]; then
    echo "riscv64 lane ($LANE) aborted on timeout (124): publishing nothing" >&2
  else
    mkdir -p "$DEST"
    for f in results.json results.dat variables.json guest-status.txt boot.log; do
      [ -f "$SHARE/$f" ] && cp -f "$SHARE/$f" "$DEST/"
    done
    ENABLE_FLAG="" RUN_STATUS="$rc" bash scripts/common/version_stamp.sh "$LANE" "$DEST/versions.txt"
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

# The pinned CPU model is QEMU_CPU_RISCV64=rva23s64 in env.sh (qemu 10.2.1's
# named RVA23 Linux-capable hart profile; -cpu "$QEMU_CPU_RISCV64" below).
# Ubuntu's riscv64 cross glibc is RVA23U64-based, so a narrower model is a
# latent illegal-instruction in the guest's own libc; rva23u64 is the
# whitelisted fallback.  The machine/firmware/memory pins ride likewise.
# shellcheck disable=SC2086
set +e
timeout "$LANE_RUN_TIMEOUT" "$QEMU_SYSTEM_RISCV64" \
  -cpu "$QEMU_CPU_RISCV64" -M "$QEMU_MACH_RISCV64" -bios "$QEMU_BIOS_RISCV64" \
  -m "$QEMU_MEM_RISCV64" \
  -kernel "$IMAGE" -initrd "$CPIO" \
  -append 'console=ttyS0 earlycon' \
  -fsdev "local,id=fs0,path=$SHARE,security_model=none" \
  -device virtio-9p-device,mount_tag=host0,fsdev=fs0 \
  -nographic 2>&1 | tee "$SHARE/boot.log"
qemu_rc=${PIPESTATUS[0]}
set -e
[ "$qemu_rc" -eq 124 ] && exit 124
[ "$qemu_rc" -eq 0 ] ||
  die "qemu-system-riscv64 exited $qemu_rc (see $SHARE/boot.log)"

# ---- the guest's status handshake ----
[ -f "$SHARE/guest-status.txt" ] ||
  die "guest-status.txt missing from the 9p share - the guest did not complete (see $SHARE/boot.log)"
grep -q 'run-test-exit: 0' "$SHARE/guest-status.txt" ||
  die "guest did not report a clean run: $(cat "$SHARE/guest-status.txt")"

# ---- completeness gate: the full tracked record set ----
[ -f "$SHARE/results.json" ] || die "results.json missing from the 9p share"
python3 - "$SHARE/results.json" "$ROOT/benchmark/configure.json" <<'PY'
import json, sys
res, reg = (json.load(open(p)) for p in sys.argv[1:3])
missing = sorted(set(reg) - set(res))
extra = sorted(set(res) - set(reg))
if missing or extra:
    sys.exit("results.json record set != tracked registry "
             "(missing=%d e.g. %s; extra=%d e.g. %s)"
             % (len(missing), missing[:3], len(extra), extra[:3]))
print("riscv64/run: results.json carries all %d tracked records" % len(res))
PY

echo "riscv64/run ($LANE): ok"
