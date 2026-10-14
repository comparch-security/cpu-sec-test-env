#!/usr/bin/env bash
set -euo pipefail
# build_kernel.sh (no args)
#
# Builds the pinned guest kernel for the riscv64 system lane:
#   - fetches the env.sh-pinned kernel.org tarball (.part + sha256-verified +
#     atomic rename; bounded retries with backoff on network failure; a hash
#     mismatch is reported distinctly and never retried);
#   - defconfig for ARCH=riscv with the env.sh KBUILD_BUILD_* reproducibility
#     pins applied to every make invocation;
#   - merges scripts/riscv64/qemu-virt.fragment through the kernel's own
#     scripts/config, then olddefconfig;
#   - builds Image and asserts the required symbol set against the built
#     .config (the 9p/console/devtmpfs/initrd set the guest depends on);
#   - stages the result as build/riscv64/Image.
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

RISCV64_CROSS="${RISCV64_CXX%%g++*}"          # riscv64-linux-gnu-
KMAKE=(make -C "$KDIR" ARCH=riscv
       CROSS_COMPILE="$RISCV64_CROSS" CC="$RISCV64_CC"
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
"${KMAKE[@]}" olddefconfig

# ---- assert the required symbol set against the BUILT config ----
# (RISCV_ISA_V / RISCV_ISA_V_DEFAULT_ENABLE: the guest userspace is RVA23U64
# vector-using code - the kernel must support userspace vector AND default it
# on, or every vector instruction in glibc traps SIGILL)
required="CONFIG_NET_9P CONFIG_NET_9P_VIRTIO CONFIG_9P_FS CONFIG_VIRTIO_MMIO
CONFIG_SERIAL_8250_CONSOLE CONFIG_DEVTMPFS CONFIG_DEVTMPFS_MOUNT
CONFIG_BLK_DEV_INITRD
CONFIG_RISCV_ISA_V CONFIG_RISCV_ISA_V_DEFAULT_ENABLE"
for sym in $required; do
  grep -qx "$sym=y" "$KDIR/.config" ||
    die "built .config lacks $sym=y (required by the riscv64 guest: 9p results share, console, devtmpfs, initrd)"
done

# ---- Image ----
"${KMAKE[@]}" -j"$(nproc)" Image
[ -f "$KDIR/arch/riscv/boot/Image" ] || die "kernel build produced no Image"
mkdir -p "$(dirname "$IMAGE")"
cp -f "$KDIR/arch/riscv/boot/Image" "$IMAGE"
echo "riscv64/build_kernel: ok - $IMAGE ($(stat -c%s "$IMAGE") bytes)"
