#!/usr/bin/env bash
set -euo pipefail
# build_busybox.sh (no args)
#
# Builds the pinned busybox for the riscv64 guest as a STATIC binary:
#   - fetches the env.sh-pinned busybox tarball (.part + sha256-verified +
#     atomic rename; bounded retries with backoff on network failure; a hash
#     mismatch is reported distinctly and never retried);
#   - defconfig, then forces CONFIG_STATIC=y (the guest rootfs stages no
#     dynamic loader for busybox);
#   - builds with SOURCE_DATE_EPOCH pinned from env.sh;
#   - installs into build/riscv64/busybox-root/ (bin/busybox + applet links).
#
# build_image.sh stages this tree into the initramfs.

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=../../env.sh
. ./env.sh

die() { echo "riscv64/build_busybox: $*" >&2; exit 1; }

BBVER="$BUSYBOX_VERSION"
BBDIR="$ROOT/$BUILD_DIR/riscv64/busybox-src"
BBROOT="$ROOT/$BUILD_DIR/riscv64/busybox-root"
DL_DIR="$ROOT/$BUILD_DIR/downloads"
TARBALL="$DL_DIR/$(basename "$BUSYBOX_URL")"

export SOURCE_DATE_EPOCH
RISCV64_CROSS="${RISCV64_CXX%%g++*}"

# ---- fetch: the shared pinned-tarball fetcher (scripts/common/fetch.sh) ----
. "$ROOT/scripts/common/fetch.sh"

fetch "busybox-$BBVER" "$BUSYBOX_URL" "$BUSYBOX_SHA256" "$TARBALL"

# ---- extract fresh ----
rm -rf "$BBDIR" "$BBROOT"
mkdir -p "$BBDIR"
tar -xjf "$TARBALL" --strip-components=1 -C "$BBDIR"

# ---- config: defconfig + static ----
make -C "$BBDIR" defconfig
# busybox's defconfig leaves CONFIG_STATIC unset; the rootfs stages no
# dynamic loader for busybox itself, so it must be static.
if grep -q '^# CONFIG_STATIC is not set' "$BBDIR/.config"; then
  sed -i 's/^# CONFIG_STATIC is not set$/CONFIG_STATIC=y/' "$BBDIR/.config"
elif ! grep -q '^CONFIG_STATIC=y' "$BBDIR/.config"; then
  echo 'CONFIG_STATIC=y' >> "$BBDIR/.config"
fi
grep -qx 'CONFIG_STATIC=y' "$BBDIR/.config" || die "failed to enable CONFIG_STATIC"

# busybox's tc applet no longer compiles against modern kernel headers
# (CBQ constants removed); the guest needs no traffic control.
sed -i 's/^CONFIG_TC=y$/# CONFIG_TC is not set/' "$BBDIR/.config"
grep -qx '^# CONFIG_TC is not set$' "$BBDIR/.config" || die "failed to disable CONFIG_TC"

# ---- build + install (SOURCE_DATE_EPOCH exported above) ----
make -C "$BBDIR" -j"$(nproc)" \
  ARCH=riscv CROSS_COMPILE="$RISCV64_CROSS" CC="$RISCV64_CC"
make -C "$BBDIR" ARCH=riscv CROSS_COMPILE="$RISCV64_CROSS" \
  CONFIG_PREFIX="$BBROOT" install

[ -x "$BBROOT/bin/busybox" ] || die "install produced no bin/busybox"
# The staged binary must actually be static riscv64 (no PT_INTERP).
if readelf -l "$BBROOT/bin/busybox" | grep -q INTERP; then
  die "busybox is dynamically linked - CONFIG_STATIC did not take effect"
fi
echo "riscv64/build_busybox: ok - $BBROOT/bin/busybox ($(stat -c%s "$BBROOT/bin/busybox") bytes, static)"
