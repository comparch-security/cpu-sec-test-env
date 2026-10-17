#!/usr/bin/env bash
set -euo pipefail
# build_emulator.sh (no args)
#
# Builds the two CHERI QEMU emulators through the pinned cheribuild tree
# (plan 2026-10-14-cheri-lanes-bringup, Step 2; executed as hosted Step 5):
#   qemu-system-riscv64xcheri and qemu-system-morello - the single `qemu`
#   cheribuild target, narrowed to the two lane targets via
#   --qemu/targets="$QEMU_TARGETS_CHERI".  The spelled names must be the
#   FINAL configure names: the pin rewrites riscv64cheri-softmmu to
#   riscv64xcheri-softmmu only when the option is at its default value, so
#   setting the option bypasses that rewrite.
#
# Uses the exact CHERIBUILD_LAYOUT flags from build_toolchains.sh
# (--source-root/--output-root/--build-root under build/cheri/,
# --skip-update), so the emulators land in build/cheri/output/sdk/bin
# (cheribuild installs qemu into the CHERI SDK bindir).  Preflights run
# before cheribuild is invoked:
#   (a) the staged source tree build/cheri/sources/qemu must exist (with
#       --skip-update a missing tree still makes cheribuild try to clone
#       it) and the cheribuild tree must be staged by build_toolchains.sh;
#   (b) pkg-config must resolve slirp and pixman-1 - the pinned cheribuild
#       checks slirp unconditionally for QEMU >= 7.2 and QEMU's configure
#       needs pixman for system emulation.
#
# Takes the shared lane lock; wraps the build in timeout
# $CHERI_BUILD_TIMEOUT.  Records the two emulator --version strings into
# build/cheri/versions-emulator.txt (append-only; version_stamp.sh
# truncates its output file, so it is never invoked on a shared file).
# Long-running (tens of minutes with the narrowed target list): the
# planner hosts it as a background job with a Monitor on the log.  A build
# failure is a planner blocker - report the failing step, never retry
# blindly from inside this script.

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=../../env.sh
. ./env.sh

die() { echo "cheri/build_emulator: $*" >&2; exit 1; }

CHERI_BROOT="$ROOT/$BUILD_DIR/cheri"
CHERIBUILD_PY="$CHERI_BROOT/cheribuild-src/cheribuild.py"
QEMU_SRC="$CHERI_BROOT/sources/qemu"
VERSIONS="$CHERI_BROOT/versions-emulator.txt"

# ---- pin assertions (before any use) ----
assert_token() { # label value
  local label=$1 value=$2
  [ -n "$value" ] || die "$label is empty - set it in env.sh"
  case "$value" in
    *[!A-Za-z0-9._-]*) die "$label=$value is not a valid binary name (^[A-Za-z0-9._-]+$)" ;;
  esac
}
assert_token QEMU_RISCV64XCHERI "$QEMU_RISCV64XCHERI"
assert_token QEMU_MORELLO "$QEMU_MORELLO"
[ -n "$QEMU_TARGETS_CHERI" ] || die "QEMU_TARGETS_CHERI is empty - set it in env.sh"
case "$CHERI_BUILD_TIMEOUT" in
  ''|*[!0-9]*) die "CHERI_BUILD_TIMEOUT=$CHERI_BUILD_TIMEOUT is not a positive integer" ;;
esac
# every comma-separated member must be a valid configure name, and both
# lane targets must be among them (the final names, per the header).
# Split on the comma directly: an empty IFS on read -a disables
# word-splitting entirely, so the whole string would land in one element
# and fail validation as a single bogus member.
qemu_targets=()
IFS=',' read -r -a _tgt_split <<< "$QEMU_TARGETS_CHERI"
for t in "${_tgt_split[@]}"; do
  assert_token "QEMU_TARGETS_CHERI member" "$t"
  qemu_targets+=("$t")
done
case ",$QEMU_TARGETS_CHERI," in
  *,riscv64xcheri-softmmu,*) ;;
  *) die "QEMU_TARGETS_CHERI=$QEMU_TARGETS_CHERI does not name riscv64xcheri-softmmu" ;;
esac
case ",$QEMU_TARGETS_CHERI," in
  *,morello-softmmu,*) ;;
  *) die "QEMU_TARGETS_CHERI=$QEMU_TARGETS_CHERI does not name morello-softmmu" ;;
esac

# ---- shared lane lock (released when this script exits) ----
mkdir -p "$ROOT/$BUILD_DIR"
exec 9>"$ROOT/$BUILD_DIR/.lane.lock"
if ! flock -n 9; then
  die "lane busy: $(cat "$ROOT/$BUILD_DIR/.lane.lock" 2>/dev/null || echo unknown) holds $BUILD_DIR/.lane.lock"
fi
printf '%s\n' "cheri/build_emulator" > "$ROOT/$BUILD_DIR/.lane.lock"

# ---- preflight (a): staged trees ----
[ -d "$QEMU_SRC" ] ||
  die "missing staged source tree $QEMU_SRC - run scripts/cheri/stage_sources.sh first (with --skip-update a missing tree would still make cheribuild clone it; this script never clones)"
[ -f "$CHERIBUILD_PY" ] ||
  die "cheribuild not staged at $CHERIBUILD_PY - run scripts/cheri/build_toolchains.sh first"

# ---- preflight (b): qemu host prerequisites ----
if ! pkg-config --exists slirp; then
  die "pkg-config cannot resolve slirp - install libslirp-dev (the pinned cheribuild checks it for QEMU >= 7.2)"
fi
if ! pkg-config --exists pixman-1; then
  die "pkg-config cannot resolve pixman-1 - install libpixman-1-dev (QEMU's configure needs pixman for system emulation)"
fi

# ---- build (network-free: --skip-update reuses the staged tree) ----
CHERIBUILD_LAYOUT=(--source-root "$CHERI_BROOT/sources"
                   --output-root "$CHERI_BROOT/output"
                   --build-root "$CHERI_BROOT/build"
                   --skip-update)
echo "cheri/build_emulator: building qemu targets '$QEMU_TARGETS_CHERI' at $(date -u +%Y-%m-%dT%H:%M:%SZ) - this takes tens of minutes"
rc=0
timeout "$CHERI_BUILD_TIMEOUT" python3 "$CHERIBUILD_PY" "${CHERIBUILD_LAYOUT[@]}" \
  qemu --qemu/targets="$QEMU_TARGETS_CHERI" || rc=$?
if [ "$rc" -eq 124 ]; then
  die "cheribuild qemu build timed out after ${CHERI_BUILD_TIMEOUT}s (CHERI_BUILD_TIMEOUT)"
fi
if [ "$rc" -ne 0 ]; then
  die "cheribuild qemu build FAILED (exit $rc) - see the log above for the exact failing step"
fi

# ---- assert both lane binaries and record their versions ----
EMU_BINDIR="$CHERI_BROOT/output/sdk/bin"
EMU_RISCV="$EMU_BINDIR/$QEMU_RISCV64XCHERI"
EMU_MORELLO="$EMU_BINDIR/$QEMU_MORELLO"
[ -x "$EMU_RISCV" ] || die "$EMU_RISCV missing after the build"
[ -x "$EMU_MORELLO" ] || die "$EMU_MORELLO missing after the build"
{
  echo "# cheri/build_emulator $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "qemu-targets: $QEMU_TARGETS_CHERI"
  echo "$QEMU_RISCV64XCHERI: $("$EMU_RISCV" --version | head -n1)"
  echo "$QEMU_MORELLO: $("$EMU_MORELLO" --version | head -n1)"
} >> "$VERSIONS"
echo "cheri/build_emulator: ok - $EMU_RISCV, $EMU_MORELLO (versions in $VERSIONS)"
