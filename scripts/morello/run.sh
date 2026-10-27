#!/usr/bin/env bash
set -euo pipefail
# run.sh LANE   (LANE = aarch64-morello)
#
# Runs the bench suite on the aarch64-morello system lane.  Boots the pinned
# CheriBSD Morello purecap disk image under the Morello emulator with the
# Step-7 winner - virtio-9p on both lanes, two-way, nothing baked: a read-only
# corpus-in share carrying the prepared payload and a writable results-out
# share.  A host-side console driver (scripts/cheri/console-driver.py) logs in
# as root, drives the guest to mount both shares, copy the payload to a
# writable dir and run the guest runner, then publish the handshake.
#
# The guest boots from the disk through UEFI - the edk2-aarch64-code.fd
# firmware the pinned QEMU ships - and reaches its kernel through loader(8);
# Morello takes no direct kernel entry (unlike the riscv64 lane).  The guest
# scheduler runs `run-test no-make exhausted-run` (the corpus is prebuilt
# host-side; the guest must never make), writes results.json into the writable
# dir, and the runner copies results out and writes guest-status.txt on the
# results-out share - the same handshake contract as the riscv64 lane.  The
# host never parses console output.
#
# An EXIT trap collects the results-out share into results/<lane>/<stamp>/,
# appends the emulator + image lines to versions.txt, runs `make -C benchmark
# clean` and asserts the submodule clean - on failure paths too.  A run that
# hits the lane timeout (exit 124) aborts without publishing anything.

if [ $# -ne 1 ] || [ "$1" != aarch64-morello ]; then
  echo "usage: $0 aarch64-morello" >&2
  exit 2
fi
LANE=$1

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=../../env.sh
. ./env.sh

die() { echo "morello/run ($LANE): $*" >&2; exit 1; }

# ---- lane advisory lock ----
mkdir -p "$BUILD_DIR"
exec 9>>"$BUILD_DIR/.lane.lock"
if ! flock -n 9; then
  die "lane busy: $(cat "$BUILD_DIR/.lane.lock" 2>/dev/null || echo unknown) holds $BUILD_DIR/.lane.lock"
fi
printf '%s\n' "$LANE" > "$BUILD_DIR/.lane.lock"

CHERI_BROOT="$ROOT/$BUILD_DIR/cheri"
LANE_DIR="$ROOT/$BUILD_DIR/$LANE"
PAYLOAD="$LANE_DIR/payload"                 # corpus-in share root (read-only)
SHARE_OUT="$LANE_DIR/results-out"           # results-out share (writable)
QEMU="$CHERI_BROOT/output/sdk/bin/$QEMU_MORELLO"
IMAGE="$CHERI_DISK_IMAGE_MORELLO"
LOG="$LANE_DIR/console.log"
CMD="$LANE_DIR/console-cmd.txt"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
DEST="$RESULTS_DIR/$LANE/$STAMP"

[ -x "$QEMU" ] || die "$QEMU missing - run make ARCH=$LANE deploy first"
[ -f "$IMAGE" ] || die "$IMAGE missing - run make ARCH=$LANE deploy first"
[ -f "$PAYLOAD/run-test" ] || die "$PAYLOAD/run-test missing - run make ARCH=$LANE deploy first"

# ---- pre-boot image hash assert: the boot must never mutate the pinned
# artifact (also booted -snapshot), so a mismatch here is a hard stop ----
have=$(sha256sum "$IMAGE" | cut -d' ' -f1)
[ "$have" = "$CHERI_DISK_IMAGE_MORELLO_SHA256" ] ||
  die "pinned image sha256 mismatch: $IMAGE is $have but env.sh pins $CHERI_DISK_IMAGE_MORELLO_SHA256"

rm -rf "$SHARE_OUT"
mkdir -p "$SHARE_OUT"

# ---- collect + clean + assert, on every exit path ----
cleanup() {
  rc=$?
  set +e
  if [ "$rc" -eq 124 ]; then
    echo "aarch64-morello lane ($LANE) aborted on timeout (124): publishing nothing" >&2
  else
    mkdir -p "$DEST"
    for f in results.json results.dat variables.json guest-status.txt; do
      # a guest can plant a name whose target escapes the share; accept only a
      # regular, non-symlink file whose realpath stays under the share root.
      [ -f "$SHARE_OUT/$f" ] || continue
      [ ! -L "$SHARE_OUT/$f" ] || continue
      case "$(realpath -- "$SHARE_OUT/$f")" in
        "$SHARE_OUT"/*) cp -f "$SHARE_OUT/$f" "$DEST/" ;;
        *) echo "morello/run: refusing out-of-share path $SHARE_OUT/$f" >&2 ;;
      esac
    done
    ENABLE_FLAG="" RUN_STATUS="$rc" bash scripts/common/version_stamp.sh "$LANE" "$DEST/versions.txt"
    {
      echo "emulator: $QEMU"
      echo "image: $IMAGE"
    } >> "$DEST/versions.txt"
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

# ---- console command script (fixed patterns; never eval/source guest text) ----
# The corpus-in share is read-only by doctrine, so the payload is copied to a
# writable dir (/tmp/bench) before the guest runner runs from there.  The p9fs
# modules are loaded best-effort (the round-31 spike proved this order).
cat > "$CMD" <<'EOF'
kldload p9fs 2>&1 || true
kldload virtio_p9fs 2>&1 || true
mkdir -p /tmp/corpus-in /tmp/results-out /tmp/bench
mount -t p9fs -o ro CIN /tmp/corpus-in
mount -t p9fs COUT /tmp/results-out
cp -a /tmp/corpus-in/. /tmp/bench/
CORPUS_IN_TAG=CIN RESULTS_OUT_TAG=COUT BENCH_DIR=/tmp/bench sh /tmp/bench/runner
cat /tmp/results-out/guest-status.txt
EOF

# Every QEMU parameter is read from env.sh; nothing is hard-coded.  Morello
# boots UEFI (edk2-aarch64-code.fd is the -bios firmware, resolved from QEMU's
# datadir) and reaches its kernel through loader(8) from the disk, so it takes
# no direct kernel entry line at all.
# ---- fail closed on the guest-network pin ----
# An emptied or mistyped pin must never silently restore QEMU's default slirp
# netdev (restrict=off), which would let attack code in the guest route IP out
# through the host.  Only `-net none` or an explicit user,restrict=on spelling
# may boot.
net_pin="$QEMU_NET_CHERI_MORELLO"
if [ -z "$net_pin" ] ||
   { [ "$net_pin" != "-net none" ] && [[ "$net_pin" != *"user,restrict=on"* ]]; }; then
  die "QEMU_NET_CHERI_MORELLO='$net_pin' is neither '-net none' nor an explicit user,restrict=on netdev - refusing to boot on QEMU's default slirp"
fi
read -r -a netargs <<< "$net_pin"

# The driver bound is the lane timeout; the outer `timeout` is a paranoid
# backstop (a strictly larger bound), so the driver self-caps first and kills
# its own qemu cleanly - no orphaned guest.
DRIVER_CAP="$LANE_RUN_TIMEOUT"
set +e
timeout "$((LANE_RUN_TIMEOUT + 120))" python3 scripts/cheri/console-driver.py \
  --qemu "$QEMU" --log "$LOG" --cap "$DRIVER_CAP" --login-wait "$DRIVER_CAP" \
  --cmd "$CMD" \
  -- "$QEMU" \
  -M "$QEMU_MACH_CHERI_MORELLO" \
  -cpu "$QEMU_CPU_CHERI_MORELLO" \
  -m "$QEMU_MEM_CHERI_MORELLO" \
  -bios "$QEMU_BIOS_CHERI_MORELLO" \
  -drive "file=$IMAGE,format=raw,if=virtio" \
  -fsdev "local,id=fsin,path=$PAYLOAD,security_model=mapped-xattr" \
  -device "virtio-9p-device,mount_tag=CIN,fsdev=fsin" \
  -fsdev "local,id=fsout,path=$SHARE_OUT,security_model=mapped-xattr" \
  -device "virtio-9p-device,mount_tag=COUT,fsdev=fsout" \
  -nographic -snapshot \
  "${netargs[@]}"
driver_rc=$?
set -e
# The driver reaching its own cap (or the login wait) is the lane timing out.
if [ "$driver_rc" -eq 124 ] ||
   grep -q "# driver: cap " "$LOG" 2>/dev/null ||
   grep -q "# driver: login not reached" "$LOG" 2>/dev/null; then
  exit 124
fi
[ "$driver_rc" -eq 0 ] ||
  die "console driver exited $driver_rc (see $LOG)"

# ---- the guest's status handshake ----
[ -f "$SHARE_OUT/guest-status.txt" ] ||
  die "guest-status.txt missing from the results-out share - the guest did not complete (see $LOG)"
grep -q 'run-test-exit: 0' "$SHARE_OUT/guest-status.txt" ||
  die "guest did not report a clean run: $(cat "$SHARE_OUT/guest-status.txt")"

# ---- completeness gate: the full derived record set ----
[ -f "$SHARE_OUT/results.json" ] || die "results.json missing from the results-out share"
python3 - "$SHARE_OUT/results.json" "$PAYLOAD/configure.json" <<'PY'
import json, sys
res, reg = (json.load(open(p)) for p in sys.argv[1:3])
missing = sorted(set(reg) - set(res))
extra = sorted(set(res) - set(reg))
if missing or extra:
    sys.exit("results.json record set != derived registry "
             "(missing=%d e.g. %s; extra=%d e.g. %s)"
             % (len(missing), missing[:3], len(extra), extra[:3]))
print("morello/run: results.json carries all %d derived records" % len(res))
PY

echo "morello/run ($LANE): ok"