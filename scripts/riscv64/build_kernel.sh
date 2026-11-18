#!/usr/bin/env bash
set -euo pipefail
# build_kernel.sh (no args)
#
# Builds the pinned guest kernel for the riscv64 system lanes (plain and CFI
# variant alike - one lane-agnostic Image): the kernel is built by the GCC 16
# toolchain pin (env.sh RISCV64_GNU_PREFIX), because CONFIG_RISCV_USER_CFI's
# Kconfig gate is `$(cc-option,-mabi=lp64 -march=rv64ima_zicfiss_zicfilp
# -fcf-protection=full)` and gcc-13 fails it, silently dropping the symbol
# that user-mode CFI needs.
#   - fetches the env.sh-pinned kernel.org tarball (.part + sha256-verified +
#     atomic rename; bounded retries with backoff on network failure; a hash
#     mismatch is reported distinctly and never retried);
#   - runs the Kconfig gate's exact probe once, before any build: a toolchain
#     without -fcf-protection support would otherwise fail only as a missing
#     symbol after a full kernel build;
#   - defconfig for ARCH=riscv with the env.sh KBUILD_BUILD_* reproducibility
#     pins applied to every make invocation;
#   - merges scripts/riscv64/qemu-virt.fragment through the kernel's own
#     scripts/config, then olddefconfig;
#   - builds Image and asserts the required symbol set against the built
#     .config (the 9p/console/devtmpfs/initrd set the guest depends on, plus
#     CONFIG_RISCV_USER_CFI);
#   - stages the result as build/riscv64/Image.
#
# Cost: there is NO Image cache - every deploy of either riscv64 lane extracts
# a fresh tree and pays one full kernel build (the tarball alone is cached).
#
# Output layout: build/riscv64/kernel/ (source + build tree),
# build/riscv64/Image, build/downloads/linux-<ver>.tar.xz (verified cache).

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=../../env.sh
. ./env.sh

die() { echo "riscv64/build_kernel: $*" >&2; exit 1; }

KDIR="$ROOT/$BUILD_DIR/riscv64/kernel"
DL_DIR="$ROOT/$BUILD_DIR/downloads"
TARBALL="$DL_DIR/$(basename "$KERNEL_URL")"
FRAG="$ROOT/scripts/riscv64/qemu-virt.fragment"
IMAGE="$ROOT/$BUILD_DIR/riscv64/Image"

# The kernel CC is the GCC 16 pin.  RISCV64_GNU_PREFIX is a repo-relative
# sibling in env.sh; a pre-set absolute value wins.  The prefix already ends
# in `-`, so CROSS_COMPILE takes it as-is and CC appends `gcc` (never another
# dash).
case "$RISCV64_GNU_PREFIX" in /*) ;; *) RISCV64_GNU_PREFIX="$ROOT/$RISCV64_GNU_PREFIX" ;; esac
[ -x "${RISCV64_GNU_PREFIX}gcc" ] ||
  die "kernel CC not found: ${RISCV64_GNU_PREFIX}gcc (RISCV64_GNU_PREFIX=${RISCV64_GNU_PREFIX}; the GCC 16 toolchain pin) - install it or override RISCV64_GNU_PREFIX"

KMAKE=(make -C "$KDIR" ARCH=riscv
       CROSS_COMPILE="$RISCV64_GNU_PREFIX" CC="${RISCV64_GNU_PREFIX}gcc"
       "KBUILD_BUILD_TIMESTAMP=$KBUILD_BUILD_TIMESTAMP"
       "KBUILD_BUILD_USER=$KBUILD_BUILD_USER"
       "KBUILD_BUILD_HOST=$KBUILD_BUILD_HOST")

# ---- fetch: .part + hash-verify + atomic rename; distinct failure modes ----
fetch() {  # name url sha256 dest
  local name=$1 url=$2 sha=$3 dest=$4 attempt
  if [ -f "$dest" ]; then
    if echo "$sha  $dest" | sha256sum -c --status -; then
      echo "$name: using verified cache $dest"
      return 0
    fi
    echo "$name: cached file fails sha256 verification, refetching: $dest" >&2
    rm -f "$dest"
  fi
  mkdir -p "$(dirname "$dest")"
  for attempt in 1 2 3; do
    if curl -fsSL --connect-timeout 30 -o "$dest.part" "$url"; then
      if echo "$sha  $dest.part" | sha256sum -c --status -; then
        mv "$dest.part" "$dest"
        echo "$name: fetched and sha256-verified $dest"
        return 0
      fi
      rm -f "$dest.part"
      echo "$name: CHECKSUM MISMATCH - downloaded content of $url does not match the env.sh pin (not a network failure; refusing to retry)" >&2
      return 1
    fi
    echo "$name: network failure fetching $url (attempt $attempt/3)" >&2
    sleep $((attempt * 2))
  done
  echo "$name: DOWNLOAD FAILED after 3 attempts: $url" >&2
  return 1
}

fetch "linux-$KERNEL_VERSION" "$KERNEL_URL" "$KERNEL_SHA256" "$TARBALL"

# ---- extract (fresh tree each run: config drift from a prior fragment edit
# must never survive) ----
rm -rf "$KDIR"
mkdir -p "$KDIR"
tar -xJf "$TARBALL" --strip-components=1 -C "$KDIR"

# ---- defconfig with the reproducibility pins ----
"${KMAKE[@]}" defconfig

# ---- merge the committed qemu-virt fragment through scripts/config ----
[ -f "$KDIR/scripts/config" ] || "${KMAKE[@]}" scripts/config
while IFS= read -r line; do
  case "$line" in
    ''|\#*) continue ;;
    CONFIG_*=y)
      sym=${line#CONFIG_}; sym=${sym%=y}
      "$KDIR/scripts/config" --file "$KDIR/.config" -e "$sym" ||
        die "scripts/config failed for $line"
      ;;
    *)
      die "qemu-virt.fragment: unsupported line '$line' (only CONFIG_X=y is merged)"
      ;;
  esac
done < "$FRAG"

# ---- the Kconfig gate's exact probe, once, before the build ----
# CONFIG_RISCV_USER_CFI is `def_bool y ... depends on` this cc-option probe
# (v7.3.4 arch/riscv/Kconfig); a toolchain that fails it loses the symbol in
# olddefconfig with no error of its own, which only surfaces as the assert
# below after a full build.  Run the probe verbatim so the failure names the
# toolchain instead.  -mabi=lp64 is load-bearing: the toolchain's default ABI
# is lp64d and the -march omits D, so without it the probe fails on any GCC.
"${RISCV64_GNU_PREFIX}gcc" -mabi=lp64 -march=rv64ima_zicfiss_zicfilp \
    -fcf-protection=full -c -x c /dev/null -o /dev/null ||
  die "the kernel CC ${RISCV64_GNU_PREFIX}gcc fails CONFIG_RISCV_USER_CFI's Kconfig probe (-mabi=lp64 -march=rv64ima_zicfiss_zicfilp -fcf-protection=full) - the kernel must be built by the GCC 16 toolchain pin (RISCV64_GNU_PREFIX); gcc-13 has no Zicfiss/Zicfilp or -fcf-protection support"

"${KMAKE[@]}" olddefconfig

# ---- assert the required symbol set against the BUILT config ----
# (RISCV_ISA_V / RISCV_ISA_V_DEFAULT_ENABLE: the guest userspace is RVA23U64
# vector-using code - the kernel must support userspace vector AND default it
# on, or every vector instruction in glibc traps SIGILL.  CONFIG_RISCV_USER_CFI:
# user-mode CFI has no kernel symbol before 7.0, and its Kconfig gate is the
# cc-option probe run above - a missing symbol here means the kernel CC is not
# the GCC 16 pin.)
required="CONFIG_NET_9P CONFIG_NET_9P_VIRTIO CONFIG_9P_FS CONFIG_VIRTIO_MMIO
CONFIG_SERIAL_8250_CONSOLE CONFIG_DEVTMPFS CONFIG_DEVTMPFS_MOUNT
CONFIG_BLK_DEV_INITRD CONFIG_RISCV_USER_CFI
CONFIG_RISCV_ISA_V CONFIG_RISCV_ISA_V_DEFAULT_ENABLE"
for sym in $required; do
  grep -qx "$sym=y" "$KDIR/.config" ||
    die "built .config lacks $sym=y (required by the riscv64 guest: 9p results share, console, devtmpfs, initrd, RISC-V userspace vector; CONFIG_RISCV_USER_CFI in particular needs the GCC 16 kernel CC pin RISCV64_GNU_PREFIX=$RISCV64_GNU_PREFIX - a toolchain without -fcf-protection support silently drops the symbol)"
done

# ---- Image ----
"${KMAKE[@]}" -j"$(nproc)" Image
[ -f "$KDIR/arch/riscv/boot/Image" ] || die "kernel build produced no Image"
mkdir -p "$(dirname "$IMAGE")"
cp -f "$KDIR/arch/riscv/boot/Image" "$IMAGE"
echo "riscv64/build_kernel: ok - $IMAGE ($(stat -c%s "$IMAGE") bytes)"
