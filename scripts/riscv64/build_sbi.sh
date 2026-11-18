#!/usr/bin/env bash
set -euo pipefail
# build_sbi.sh (no args)
#
# Builds the qemu-virt lanes' -bios firmware from the pinned OpenSBI
# (env.sh NEMU_OPENSBI_URL/NEMU_OPENSBI_COMMIT - one pin per input: the NEMU
# venue builds its own firmware from the same commit, and v1.9 is the OpenSBI
# that advertises the SBI FWFT LANDING_PAD + SHADOW_STACK features user-mode
# CFI needs; QEMU's bundled firmware does not):
#   - ensures a cached checkout under build/riscv64/opensbi-src at the pin.  A
#     cached checkout is reused only when `git rev-parse HEAD` equals the pin
#     AND `git status --short` is empty; a directory that is not a git
#     checkout dies instead of being cloned into.  OpenSBI's own .gitignore
#     covers build/, so an in-source build keeps the checkout clean;
#   - builds PLATFORM=generic with CROSS_COMPILE="${RISCV64_GNU_PREFIX}" (the
#     GCC 16 pin: the same toolchain the kernel and the CFI variants use);
#   - stages build/platform/generic/firmware/fw_jump.bin as
#     build/riscv64/fw_jump.bin and asserts it is non-empty.
#
# Offline once the source cache exists; a cold run needs network for the one
# clone.  The staged firmware is a SHARED input for both riscv64 lanes (the
# variant reads it read-only); its sha256 is recorded in the lane stamp
# (scripts/riscv64/run.sh) - a stamp must name the firmware it booted.

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=../../env.sh
. ./env.sh

die() { echo "riscv64/build_sbi: $*" >&2; exit 1; }

SRC="$ROOT/$BUILD_DIR/riscv64/opensbi-src"
FW_SRC="$SRC/build/platform/generic/firmware/fw_jump.bin"
FW_STAGED="$ROOT/$BUILD_DIR/riscv64/fw_jump.bin"

case "$RISCV64_GNU_PREFIX" in /*) ;; *) RISCV64_GNU_PREFIX="$ROOT/$RISCV64_GNU_PREFIX" ;; esac
[ -x "${RISCV64_GNU_PREFIX}gcc" ] ||
  die "CROSS_COMPILE not found: ${RISCV64_GNU_PREFIX}gcc (RISCV64_GNU_PREFIX=$RISCV64_GNU_PREFIX; the GCC 16 toolchain pin) - install it or override RISCV64_GNU_PREFIX"

# ---- the pinned source cache ----
mkdir -p "$(dirname -- "$SRC")"
if [ ! -d "$SRC" ]; then
  echo "riscv64/build_sbi: clone $NEMU_OPENSBI_URL -> $SRC"
  git clone --quiet "$NEMU_OPENSBI_URL" "$SRC" ||
    die "cannot clone $NEMU_OPENSBI_URL (a cold run needs network) - fix the network or seed $SRC from another checkout"
fi
[ -d "$SRC/.git" ] ||
  die "$SRC exists but is not a git checkout - remove it and re-run (a partial or foreign tree is never cloned into)"
if ! git -C "$SRC" cat-file -e "$NEMU_OPENSBI_COMMIT^{commit}" 2>/dev/null; then
  git -C "$SRC" fetch --quiet origin "$NEMU_OPENSBI_COMMIT" ||
    die "cannot fetch $NEMU_OPENSBI_COMMIT into $SRC (a cold run needs network)"
fi
git -C "$SRC" checkout --quiet --detach "$NEMU_OPENSBI_COMMIT" ||
  die "cannot check out $NEMU_OPENSBI_COMMIT in $SRC"
head=$(git -C "$SRC" rev-parse HEAD) ||
  die "cannot read the HEAD of $SRC - remove it and re-run"
[ "$head" = "$NEMU_OPENSBI_COMMIT" ] ||
  die "$SRC is at $head, expected the OpenSBI pin $NEMU_OPENSBI_COMMIT - remove it and re-run"
git_rc=0
dirty=$(git -C "$SRC" status --short) || git_rc=$?
[ "$git_rc" -eq 0 ] ||
  die "cannot verify the OpenSBI checkout is clean: 'git -C $SRC status --short' failed (rc=$git_rc)"
if [ -n "$dirty" ]; then
  echo "ERROR: the OpenSBI checkout $SRC is dirty (OpenSBI's .gitignore covers build/, so any dirt is a real edit):" >&2
  printf '%s\n' "$dirty" >&2
  exit 1
fi

# ---- build PLATFORM=generic (in-source; build/ is gitignored) ----
echo "riscv64/build_sbi: building OpenSBI (PLATFORM=generic, CROSS_COMPILE=$RISCV64_GNU_PREFIX)"
make -C "$SRC" PLATFORM=generic CROSS_COMPILE="$RISCV64_GNU_PREFIX" -j"$(nproc)" ||
  die "the OpenSBI generic build failed (see the make output above)"

# ---- stage + assert ----
[ -s "$FW_SRC" ] ||
  die "the OpenSBI build produced no $FW_SRC"
mkdir -p "$(dirname -- "$FW_STAGED")"
install -m 0644 "$FW_SRC" "$FW_STAGED"
[ -s "$FW_STAGED" ] ||
  die "staged firmware $FW_STAGED is empty"
echo "riscv64/build_sbi: ok - $FW_STAGED ($(stat -c%s "$FW_STAGED") bytes), sha256 $(sha256sum "$FW_STAGED" | cut -d' ' -f1) (OpenSBI NEMU_OPENSBI_COMMIT=$NEMU_OPENSBI_COMMIT)"
