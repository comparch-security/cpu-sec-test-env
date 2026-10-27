#!/usr/bin/env bash
set -euo pipefail
# build_image.sh (no args)
#
# Builds the CHERI guest artifacts through the pinned cheribuild tree
# (plan 2026-10-14-cheri-lanes-bringup, Step 3; executed as hosted Step 6),
# in this order:
#   1. preflights: the staged cheribsd tree and the staged bbl firmware
#      tree must exist (with --skip-update a missing tree still makes
#      cheribuild fetch it - and for bbl that would silently clone the
#      branch TIP instead of the pin), the glibc C23 shim
#      headers must exist (CHERI_CROSS_CPATH), the
#      --list-targets output must name every target this script invokes
#      (a mismatch is a hard failure), and the CheriBSD host prerequisites
#      must be present (libarchive, bsdtar);
#   2. the SSH extra-files guard: sources/extra-files/root/.ssh/
#      authorized_keys is pre-seeded with ONLY the test key's .pub (mode
#      0600) so the disk-image build cannot self-answer yes to globbing
#      the developer's personal public keys (disk_image.py's non-tty
#      default); the test key pair is generated on first use, mirroring
#      cheribuild's own lazy generation;
#   3. first the riscv64 boot firmware: bbl-baremetal-riscv64-purecap
#      (cheap, and the riscv64 lane's -bios prerequisite), then per lane,
#      world-first: cheribsd-<xtarget> (the world build —
#      cheribsd-sysroot-<xtarget> only PACKAGES output/rootfs-<xtarget>
#      and fatals with "does not contain libc.so.7" if the world has not
#      populated it; cheribuild checks that declared dependency but does
#      not build it), then cheribsd-sysroot-<xtarget> (purecap sysroot),
#      then disk-image-<xtarget> (bootable full-userland disk);
#   4. record the observed artifacts into build/cheri/versions-image.txt
#      and fill env.sh's pins with the OBSERVED values - per-lane disk
#      image path + sha256 of the pristine post-build artifact, the
#      sysroot path as built (usr/include/stdio.h + lib/libc.so.7 under
#      the xtarget dir, never an assumed layout), and the riscv64 boot
#      kernel path (QEMU_KERNEL_CHERI_RISCV64 - the riscv64 lane's
#      -kernel input, read back from the built world tree), and the riscv64
#      boot firmware (QEMU_BIOS_CHERI_RISCV64 - read back from the emulator
#      datadir, output/sdk/share/qemu/, where the bbl target installs it).
#
# There is deliberately NO makefs leg and NO MAKEFS_CMD override (removed
# 2026-10-15, user decision "remove it fully"): the disk-image leg needs
# makefs only for the EFI FAT partition (-t msdos), and the previously
# pinned Engil/makefs fork (frozen 2021-10-15) has no msdos support at
# all.  disk_image.py:969 reads MAKEFS_CMD only as an OPTIONAL override;
# :974-979 otherwise falls back to the FreeBSD host-tools makefs the world
# build itself produces, which HAS msdos (verified: real FAT12 image).
# Leaving the old override in place while dropping its pin would also kill
# this script on an unbound variable under set -u (bash -n cannot see
# that - check for it explicitly).
#
# The riscv64 lane boots with -bios + -kernel: a disk-only virt boot
# leaves kernel_entry = 0, and -kernel alone is not enough either - the
# machine loads the BBL firmware into M-mode and jumps to the payload
# from there, which is why this script builds bbl-baremetal-riscv64-
# purecap and pins the result (QEMU_BIOS_CHERI_RISCV64) next to the
# kernel.  A rebuild re-runs this script and re-fills the pins; a
# hand-edited image is never the supported way to change a pinned
# artifact.
#
# Takes the shared lane lock; every cheribuild invocation is wrapped in
# timeout $CHERI_BUILD_TIMEOUT (the shared LANE_DEPLOY_TIMEOUT cannot
# wrap a multi-hour world build).  Long-running (hours per lane): the
# planner hosts it as a background job with a Monitor on the log.  A
# build failure is a planner blocker - report the failing step, never
# retry blindly from inside this script.

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=../../env.sh
. ./env.sh

die() { echo "cheri/build_image: $*" >&2; exit 1; }

CHERI_BROOT="$ROOT/$BUILD_DIR/cheri"
CHERIBUILD_PY="$CHERI_BROOT/cheribuild-src/cheribuild.py"
CHERIBSD_SRC="$CHERI_BROOT/sources/cheribsd"
BBL_SRC="$CHERI_BROOT/sources/bbl"
EXTRA_FILES="$CHERI_BROOT/sources/extra-files"
VERSIONS="$CHERI_BROOT/versions-image.txt"
TEST_KEY="$CHERI_BROOT/build/insecure_test_ssh_key"

# ---- pin assertions (before any use) ----
case "$CHERI_BUILD_TIMEOUT" in
  ''|*[!0-9]*) die "CHERI_BUILD_TIMEOUT=$CHERI_BUILD_TIMEOUT is not a positive integer" ;;
esac
[ -n "$QEMU_BIOS_CHERI_MORELLO" ] ||
  die "QEMU_BIOS_CHERI_MORELLO is empty - set it in env.sh"
# The riscv64 -bios pin must be a bare datadir filename (no path
# separators): QEMU resolves it through its own datadir lookup, exactly
# like the Morello pin, so a host-absolute path would bake this machine's
# layout into a portable pin.
case "$QEMU_BIOS_CHERI_RISCV64" in
  '')  die "QEMU_BIOS_CHERI_RISCV64 is empty - set it in env.sh" ;;
  */*) die "QEMU_BIOS_CHERI_RISCV64=$QEMU_BIOS_CHERI_RISCV64 is not a bare datadir filename - it must carry no path separators (QEMU resolves it through its datadir, like QEMU_BIOS_CHERI_MORELLO)" ;;
esac

# ---- shared lane lock (released when this script exits) ----
mkdir -p "$ROOT/$BUILD_DIR"
exec 9>>"$ROOT/$BUILD_DIR/.lane.lock"
if ! flock -n 9; then
  die "lane busy: $(cat "$ROOT/$BUILD_DIR/.lane.lock" 2>/dev/null || echo unknown) holds $BUILD_DIR/.lane.lock"
fi
printf '%s\n' "cheri/build_image" > "$ROOT/$BUILD_DIR/.lane.lock"

# ---- preflight (a): staged trees ----
[ -d "$CHERIBSD_SRC" ] ||
  die "missing staged source tree $CHERIBSD_SRC - run scripts/cheri/stage_sources.sh first (with --skip-update a missing tree would still make cheribuild fetch it; this script never fetches)"
# The bbl tree is load-bearing for the same reason, and worse: a MISSING
# one would be silently re-cloned at the branch TIP instead of the pin
# (ensure_cloned runs before skip_update), leaving the firmware unversioned.
[ -d "$BBL_SRC" ] ||
  die "missing staged source tree $BBL_SRC - run scripts/cheri/stage_sources.sh first (with --skip-update a missing tree would still make cheribuild fetch the BBL source at its branch tip instead of BBL_SRC_COMMIT; this script never fetches)"
[ -f "$CHERIBUILD_PY" ] ||
  die "cheribuild not staged at $CHERIBUILD_PY - run scripts/cheri/build_toolchains.sh first"
[ -f "$ROOT/$CHERI_CROSS_CPATH/string.h" ] ||
  die "glibc C23 shim missing: $ROOT/$CHERI_CROSS_CPATH/string.h does not exist (CHERI_CROSS_CPATH) - without the shim headers the CheriBSD world build dies in stage 1.1 on glibc 2.43's const-preserving string macros"

CHERIBUILD_LAYOUT=(--source-root "$CHERI_BROOT/sources"
                   --output-root "$CHERI_BROOT/output"
                   --build-root "$CHERI_BROOT/build"
                   --skip-update)

# ---- preflight (b): --list-targets must name every target invoked here ----
# bbl-baremetal-riscv64-purecap is FIRST: it is the riscv64 lane's -bios
# prerequisite and the cheapest build here - if the pinned cheribuild does
# not provide it, fail before any world build starts.
IMAGE_TARGETS=(bbl-baremetal-riscv64-purecap
               cheribsd-riscv64-purecap cheribsd-sysroot-riscv64-purecap disk-image-riscv64-purecap
               cheribsd-morello-purecap cheribsd-sysroot-morello-purecap disk-image-morello-purecap)
listed=$(python3 "$CHERIBUILD_PY" "${CHERIBUILD_LAYOUT[@]}" --list-targets 2>/dev/null) ||
  die "cheribuild --list-targets failed - the staged cheribuild tree cannot enumerate targets"
for t in "${IMAGE_TARGETS[@]}"; do
  grep -q -- "$t" <<< "$listed" ||
    die "--list-targets does not name $t - refusing to invoke a target the pinned cheribuild does not provide"
done

# ---- preflight (c): CheriBSD host prerequisites ----
if ! pkg-config --exists libarchive; then
  die "pkg-config cannot resolve libarchive - install libarchive-dev (BuildFreeBSDBase.check_system_dependencies fatals on a non-FreeBSD host without it, before any world build starts)"
fi
command -v bsdtar >/dev/null 2>&1 ||
  die "bsdtar not on PATH - install libarchive-tools (the cheribsd-sysroot targets require it)"

# ---- cheribuild invocation helper (timeout-bounded) ----
run_cheribuild() {
  local rc=0
  timeout "$CHERI_BUILD_TIMEOUT" env -u SOURCE_DATE_EPOCH python3 "$CHERIBUILD_PY" "${CHERIBUILD_LAYOUT[@]}" "$@" || rc=$?
  if [ "$rc" -eq 124 ]; then
    die "cheribuild $* timed out after ${CHERI_BUILD_TIMEOUT}s (CHERI_BUILD_TIMEOUT)"
  fi
  if [ "$rc" -ne 0 ]; then
    die "cheribuild $* FAILED (exit $rc) - see the log above for the exact failing step"
  fi
}

# ---- pre-seed the SSH extra-files guard (before any image build) ----
# cheribuild generates the test key pair lazily on first use; create it
# now if absent so its public half can be staged into the image's
# extra-files, satisfying disk_image.py's is_file() guard.
if [ ! -f "$TEST_KEY.pub" ]; then
  mkdir -p "$(dirname "$TEST_KEY")"
  if [ -f "$TEST_KEY" ]; then
    ssh-keygen -y -f "$TEST_KEY" > "$TEST_KEY.pub"
  else
    ssh-keygen -t ed25519 -N '' -C cheri-lanes-test-key -f "$TEST_KEY"
  fi
  chmod 0600 "$TEST_KEY"
fi
AUTH_KEYS="$EXTRA_FILES/root/.ssh/authorized_keys"
if [ -f "$AUTH_KEYS" ]; then
  echo "cheri/build_image: $AUTH_KEYS already present - keeping it (staged extra-files content survives rebuilds)"
else
  mkdir -p "$(dirname "$AUTH_KEYS")"
  cp "$TEST_KEY.pub" "$AUTH_KEYS"
  echo "cheri/build_image: pre-seeded $AUTH_KEYS with the test key only (satisfies the is_file guard so the build cannot self-answer yes to globbing personal public keys)"
fi
chmod 0600 "$AUTH_KEYS"

# ---- per-lane world + sysroot + disk image ----
# The world build (cheribsd-<xtarget>) is named explicitly: the sysroot
# target only packages output/rootfs-<xtarget> and fatals with "does not
# contain libc.so.7" if the world has not populated it (cheribuild checks
# the declared dependency rather than building it; --pretend shows that
# listing the world target yields Building -> installworld ->
# installsysroot -> installkernel, in that order).
#
# The glibc 2.43 C23 shim (CHERI_CROSS_CPATH) rides on these CheriBSD
# invocations only, injected as --cheribsd/extra-env=CPATH=<shim>: stage
# 1.1's bootstrap tools compile against the host libc, where glibc 2.43's
# const-preserving strchr macro trips Makefile.boot's
# -Werror=incompatible-pointer-types-discards-qualifiers.  CPATH is read
# by the COMPILER directly, so it needs no make-variable cooperation and
# reaches the bootstrap-tools compile; it is searched after every -I, so
# the FreeBSD sysroot's headers still win in the cross stages
# (self-scoping to the host-tools stage that needs it).
#
# SOURCE_DATE_EPOCH must be UNSET for these legs, not emptied - the
# "env -u SOURCE_DATE_EPOCH" carried by run_cheribuild above is
# load-bearing.  FreeBSD's stand/common/newvers.sh:47-51 validates the
# variable with BSD "date -ur" semantics, but GNU date -r on this Linux
# host reads its argument as a FILENAME, so the bench pin env.sh:56/:85
# (exported at :85, sourced into every child by build_image.sh:60)
# always fails the vers.c build with "Invalid SOURCE_DATE_EPOCH".  The
# first fix assigned an EMPTY value in these extra-env values instead,
# and attempt 7 died in 2 seconds: clang validates the variable itself
# and rejects empty ("must be a non-negative decimal integer <=
# 253402300799") even though newvers.sh tolerates it.  Only unset
# satisfies both consumers, so only unset is neutralisation - an empty
# value is not a neutralisation at all.  env.sh itself is untouched:
# other lanes keep the pin.  Do NOT tidy the env -u away and do NOT
# re-add a SOURCE_DATE_EPOCH entry to extra-env - both would re-break
# the world build.
#
# extra-env therefore carries CPATH alone, as ONE space-separated
# value, NOT as two --cheribsd/extra-env flags: a second flag
# OVERWRITES the first and silently drops CPATH (re-breaking stage
# 1.1; verified with --pretend - two flags resolve to the second
# flag's entries alone).  Each KEY=VALUE pair's value must stay
# space-free.
# The riscv64 boot firmware first (cheap; needs no CPATH shim - it is the
# firmware payload built with the CHERI SDK clang, not a CheriBSD leg).
echo "cheri/build_image: building bbl-baremetal-riscv64-purecap (the riscv64 lane's M-mode boot firmware) at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
run_cheribuild bbl-baremetal-riscv64-purecap
echo "cheri/build_image: building cheribsd-riscv64-purecap + cheribsd-sysroot-riscv64-purecap + disk-image-riscv64-purecap at $(date -u +%Y-%m-%dT%H:%M:%SZ) - multi-hour"
run_cheribuild --cheribsd/extra-env="CPATH=$ROOT/$CHERI_CROSS_CPATH" cheribsd-riscv64-purecap cheribsd-sysroot-riscv64-purecap disk-image-riscv64-purecap
echo "cheri/build_image: building cheribsd-morello-purecap + cheribsd-sysroot-morello-purecap + disk-image-morello-purecap at $(date -u +%Y-%m-%dT%H:%M:%SZ) - multi-hour"
run_cheribuild --cheribsd/extra-env="CPATH=$ROOT/$CHERI_CROSS_CPATH" cheribsd-morello-purecap cheribsd-sysroot-morello-purecap disk-image-morello-purecap

# ---- observe the built artifacts (never assume a layout) ----
# The --pretend run observed: installsysroot writes the packaged sysroot
# to output/sdk/sysroot-<xtarget> (the value the CHERI_SYSROOT_* pins
# must carry - what build_corpus.sh consumes in Step 8), and installkernel
# writes into output/rootfs-<xtarget> (so the riscv64 lane's -kernel
# input lives under output/rootfs-<xtarget>/boot/kernel/). Both are
# discovered post-build here; the sdk sysroot form is preferred, then the
# rootfs form, then a single match - never a hard-coded layout.
discover_sysroot() { # xtarget -> repo-relative path on stdout
  local xtarget=$1 c
  local -a cands=() valid=()
  while IFS= read -r c; do cands+=("$c"); done < <(
    find "$CHERI_BROOT/output" -maxdepth 4 -type d -name "*${xtarget}*" 2>/dev/null | sort)
  for c in "${cands[@]}"; do
    if [ -f "$c/usr/include/stdio.h" ] && [ -e "$c/lib/libc.so.7" ]; then
      valid+=("$c")
    fi
  done
  [ "${#valid[@]}" -gt 0 ] ||
    die "no built sysroot for $xtarget: no directory under $CHERI_BROOT/output matching *${xtarget}* carries usr/include/stdio.h + lib/libc.so.7 - inspect the built tree"
  for c in "${valid[@]}"; do
    case "$c" in
      */sysroot-"$xtarget") printf '%s\n' "${c#$ROOT/}"; return 0 ;;
    esac
  done
  for c in "${valid[@]}"; do
    case "$c" in
      */rootfs-"$xtarget") printf '%s\n' "${c#$ROOT/}"; return 0 ;;
    esac
  done
  if [ "${#valid[@]}" -eq 1 ]; then
    printf '%s\n' "${valid[0]#$ROOT/}"
    return 0
  fi
  die "ambiguous sysroots for $xtarget: ${valid[*]}"
}

discover_disk_image() { # xtarget -> repo-relative path
  local xtarget=$1 img
  local -a matches=()
  # cheribuild's own name for this target, not an assumed one:
  # disk_image.py computes output_root / (disk_image_prefix +
  # build_configuration_suffix() + ".img") with prefix "cheribsd" — i.e.
  # output/cheribsd-<xtarget>.img. Try it first; the names below are
  # fallbacks for other layouts.
  img="$CHERI_BROOT/output/cheribsd-$xtarget.img"
  if [ -f "$img" ]; then
    printf '%s\n' "${img#$ROOT/}"
    return 0
  fi
  img="$CHERI_BROOT/output/rootfs-$xtarget/disk.img"
  if [ -f "$img" ]; then
    printf '%s\n' "${img#$ROOT/}"
    return 0
  fi
  while IFS= read -r img; do matches+=("$img"); done < <(
    find "$CHERI_BROOT/output" -maxdepth 4 -type f \
      \( -name disk.img -o -name "cheribsd-*${xtarget}*.img" \) \
      -path "*${xtarget}*" 2>/dev/null | sort)
  if [ "${#matches[@]}" -eq 1 ]; then
    printf '%s\n' "${matches[0]#$ROOT/}"
    return 0
  fi
  if [ "${#matches[@]}" -eq 0 ]; then
    die "no disk image found for $xtarget: expected $CHERI_BROOT/output/cheribsd-$xtarget.img (or exactly one disk.img/cheribsd-*.img under $CHERI_BROOT/output matching *${xtarget}*) - inspect the built tree"
  fi
  die "ambiguous disk images for $xtarget: ${matches[*]}"
}

discover_riscv64_kernel() { # -> repo-relative path
  local k="$CHERI_BROOT/output/rootfs-riscv64-purecap/boot/kernel/kernel"
  local -a matches=()
  if [ -f "$k" ]; then
    printf '%s\n' "${k#$ROOT/}"
    return 0
  fi
  while IFS= read -r k; do matches+=("$k"); done < <(
    find "$CHERI_BROOT/output" -maxdepth 6 -type f -path "*riscv64-purecap*/boot/kernel/kernel" 2>/dev/null | sort)
  if [ "${#matches[@]}" -eq 1 ]; then
    printf '%s\n' "${matches[0]#$ROOT/}"
    return 0
  fi
  if [ "${#matches[@]}" -eq 0 ]; then
    die "riscv64 boot kernel not found: expected $k - the riscv64 lane boots with -kernel and cannot boot without it; inspect the built world tree"
  fi
  die "ambiguous riscv64 boot kernels: ${matches[*]}"
}

SYSROOT_RISCV64=$(discover_sysroot riscv64-purecap)
SYSROOT_MORELLO=$(discover_sysroot morello-purecap)
DISK_RISCV64=$(discover_disk_image riscv64-purecap)
DISK_MORELLO=$(discover_disk_image morello-purecap)
KERNEL_RISCV64=$(discover_riscv64_kernel)
# The riscv64 boot firmware: path fixed by cheribuild itself (the bbl
# target objcopy's its built bbl into BuildQEMU's firmware dir, which is
# output/sdk/share/qemu - the same datadir directory lookup the bare
# -bios filename resolves through, and where the Morello edk2 firmware
# already lives). Assert it exists at the pin's name: if the observed
# firmware name differed from QEMU_BIOS_CHERI_RISCV64, this dies here
# rather than the lane later failing at boot.
BBL_FW="$CHERI_BROOT/output/sdk/share/qemu/$QEMU_BIOS_CHERI_RISCV64"
[ -f "$BBL_FW" ] ||
  die "riscv64 boot firmware not found at $BBL_FW - bbl-baremetal-riscv64-purecap must install it into the emulator datadir share/qemu (observed name must match the QEMU_BIOS_CHERI_RISCV64 pin); the cheri_riscv64 lane boots with -bios and cannot boot without it"
SHA_RISCV64=$(sha256sum "$ROOT/$DISK_RISCV64" | awk '{print $1}')
SHA_MORELLO=$(sha256sum "$ROOT/$DISK_MORELLO" | awk '{print $1}')
SHA_BBL_FW=$(sha256sum "$BBL_FW" | awk '{print $1}')
for v in "$SHA_RISCV64" "$SHA_MORELLO" "$SHA_BBL_FW"; do
  [ "${#v}" -eq 64 ] || die "artifact sha256 is not 64 hex chars: $v"
  case "$v" in *[!0-9a-f]*) die "artifact sha256 is not hex: $v" ;; esac
done

# ---- record the observed artifacts (append-only; version_stamp.sh
# ---- truncates its output file, so it is never invoked on this one) ----
mkdir -p "$CHERI_BROOT"
{
  echo "# cheri/build_image $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "cheribsd-sysroot-riscv64-purecap: $SYSROOT_RISCV64"
  echo "disk-image-riscv64-purecap: $DISK_RISCV64 sha256=$SHA_RISCV64"
  echo "qemu-kernel-cheri-riscv64: $KERNEL_RISCV64"
  echo "qemu-bios-cheri-riscv64: ${BBL_FW#$ROOT/} sha256=$SHA_BBL_FW"
  echo "cheribsd-sysroot-morello-purecap: $SYSROOT_MORELLO"
  echo "disk-image-morello-purecap: $DISK_MORELLO sha256=$SHA_MORELLO"
  echo "qemu-bios-cheri-morello: $QEMU_BIOS_CHERI_MORELLO"
} >> "$VERSIONS"

# ---- fill env.sh's pins with the observed values (atomic: temp copy,
# ---- per-pin line replace with post-check, sh -n, then commit) ----
set_pin_in() { # file name value
  local file=$1 name=$2 value=$3
  [ -n "$value" ] || die "refusing to fill $name with an empty value"
  case "$value" in
    *[!A-Za-z0-9._/-]*) die "refusing to fill $name with '$value' (only [A-Za-z0-9._/-] allowed)" ;;
  esac
  sed "s|^$name=.*|$name=$value|" "$file" > "$file.tmp" ||
    die "sed failed while filling $name - env.sh left untouched"
  grep -qxF "$name=$value" "$file.tmp" ||
    die "pin $name not found in env.sh (expected a line starting '$name=') - env.sh left untouched"
  mv "$file.tmp" "$file"
}

TMP_ENV="$ROOT/.env.sh.build-image.$$"
trap 'rm -f "$TMP_ENV" "$TMP_ENV.tmp"' EXIT
cp -p "$ROOT/env.sh" "$TMP_ENV"
set_pin_in "$TMP_ENV" CHERI_DISK_IMAGE_RISCV64 "$DISK_RISCV64"
set_pin_in "$TMP_ENV" CHERI_DISK_IMAGE_RISCV64_SHA256 "$SHA_RISCV64"
set_pin_in "$TMP_ENV" CHERI_SYSROOT_RISCV64 "$SYSROOT_RISCV64"
set_pin_in "$TMP_ENV" QEMU_KERNEL_CHERI_RISCV64 "$KERNEL_RISCV64"
# The firmware pin is re-filled with the OBSERVED file name: the value is
# what was just asserted to exist under share/qemu, so this doubles as the
# pin-vs-observed check (set_pin_in dies if env.sh carries no such line).
set_pin_in "$TMP_ENV" QEMU_BIOS_CHERI_RISCV64 "$QEMU_BIOS_CHERI_RISCV64"
set_pin_in "$TMP_ENV" CHERI_DISK_IMAGE_MORELLO "$DISK_MORELLO"
set_pin_in "$TMP_ENV" CHERI_DISK_IMAGE_MORELLO_SHA256 "$SHA_MORELLO"
set_pin_in "$TMP_ENV" CHERI_SYSROOT_MORELLO "$SYSROOT_MORELLO"
sh -n "$TMP_ENV" ||
  die "the filled env.sh copy fails sh -n - env.sh left untouched"
cat "$TMP_ENV" > "$ROOT/env.sh"
rm -f "$TMP_ENV" "$TMP_ENV.tmp"
trap - EXIT

echo "cheri/build_image: ok - artifacts recorded in $VERSIONS; env.sh pins re-filled (disk images, sysroots, riscv64 boot kernel, riscv64 boot firmware)"
