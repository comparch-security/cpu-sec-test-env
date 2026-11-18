#!/usr/bin/env bash
#
# The riscv64-nemu lane's image builder (absorbed from the bench's
# platform/riscv64-nemu-linux at f9e4ba7, which the portable-core pin
# cbe3bf9 removed): assemble the bootable guest image $DEST/fw_payload.bin
# from the staged corpus.  The corpus itself is staged by
# scripts/common/stage_corpus.sh (CORPUS must be exported); this script owns
# what is unique to the NEMU venue: the cross-built guest scheduler, the
# runtime-library closure and the guest-truth sys_info.  The image is the
# classic NEMU layout assembled by workload-builder:
#
#   0x80000000 +0     gcpt (LibCheckpointAlpha startup, <= 1 MiB)
#   0x80100000 +1 MiB OpenSBI fw_jump
#   0x80200000 +2 MiB device tree (xiangshan, 128 MiB DRAM, 1 hart)
#   0x80400000 +4 MiB Linux Image
#   ...        MB-aligned  initramfs (rootfs.cpio, uncompressed newc)
#
# and out/meta.json records the image/input provenance.
#
# Pinned inputs (cloned/downloaded once into $OUT/src, then reused; the pins
# live in env.sh): workload-builder, OpenSBI, LibCheckpointAlpha, the kernel
# and busybox tarballs.  They may be seeded from $BUILD_DIR/downloads before
# any download.
#
# Kernel 7.3.4 (the 7.x line is the first with CONFIG_RISCV_USER_CFI, which
# the armed guests' Zicfiss self-arm needs at boot).  Arming is gated on the
# PLATFORM's ISA advertisement, not on the binary: the kernel writes the U-mode
# ssp CSR at the first return to userspace only when the guest DT advertises
# zicfiss (measured 2026-11-17: an advertising DT plus the plain pinned
# interpreter - NEMU master, no ssp CSR - panics at boot), which is why the
# advertisement below is scoped to the CFI variant lane.  The kernel is built
# by the GCC 16 toolchain pin: the
# symbol's Kconfig gate is a cc-option probe that gcc-13 fails, after which the
# symbol silently vanishes.  The 6.x rationale below still holds and is why
# the vector pair stays pinned: the guest userspace is built by the apt cross
# toolchain whose glibc is RVA23U64 vector-using code, and kernel-side
# userspace vector support only exists from Linux 6.5 (arch/riscv/kernel/
# vector.c, CONFIG_RISCV_ISA_V).  On 6.1.83 every guest process dies with
# SIGILL on its first vector instruction -- measured 2026-10-20: the static
# busybox dies in a glibc memset `vsetivli` at init, and a *dynamic* probe
# built with the same cross g++-13 dies even earlier, inside ld-linux itself.
# The env repo's riscv64 lane pins this same kernel for this same reason; they
# are pinned into the config here and asserted against the built .config.
#
# The guest device tree advertises Zicfilp/Zicfiss for the CFI VARIANT lane
# only (ENABLE_FLAG=enable_riscv64_cfi; the venue interposes on dtc, see
# venue/dtc-cfi.sh): OpenSBI v1.9 gates its FWFT SHADOW_STACK advertisement on
# the DT hart features and the kernel's user-CFI probe reads the same node, so
# without it both are blind to CFI.  The plain lane compiles an
# advertisement-free DT and asserts the NEGATIVE - with the advertisement its
# pinned interpreter (no ssp CSR) panics at the first userspace return.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
# shellcheck source=../../../env.sh
. "$ROOT/env.sh"

die() { echo "riscv64_nemu/venue/build-image: $*" >&2; exit 1; }

OUT="${OUT:?OUT must be exported by the lane prepare script}"
CORPUS="${CORPUS:?CORPUS must be exported by the lane prepare script (the stage_corpus OUT_DIR)}"
DEST="$OUT"
SRC="$OUT/src"
DL="$SRC/downloads"
JOBS="${JOBS:-$(nproc)}"

# The pins are env.sh's (one pin per input, nowhere else).
WB_COMMIT="$NEMU_WB_COMMIT"
WB_URL="$NEMU_WB_URL"
OPENSBI_COMMIT="$NEMU_OPENSBI_COMMIT"
OPENSBI_URL="$NEMU_OPENSBI_URL"
LCA_COMMIT="$NEMU_LCA_COMMIT"
LCA_URL="$NEMU_LCA_URL"
KERNEL_VER="$KERNEL_VERSION"
KERNEL_TARBALL="linux-$KERNEL_VER.tar.xz"
KERNEL_SHA256="$KERNEL_SHA256"
KERNEL_URL="$KERNEL_URL"
BUSYBOX_VER="$BUSYBOX_VERSION"
BUSYBOX_TARBALL="busybox-$BUSYBOX_VER.tar.bz2"
BUSYBOX_SHA256="$BUSYBOX_SHA256"
BUSYBOX_URL="$BUSYBOX_URL"
SEED_DIRS=(
    "$ROOT/$BUILD_DIR/downloads"
)

# cross toolchain (the bench Makefile's child makes receive these through the
# environment; only this script's own cross builds pass them explicitly).
# The lane prepare script exports the lane's effective knobs - gcc-13 for the
# plain lane, the GCC 16 pin for the CFI variant (its corpus and its guest
# closure must share one sysroot) - and those win here; a direct invocation
# without them falls back to the env.sh pins.
CXX="${CXX:-$RISCV64_CXX}"
CC="${CC:-$RISCV64_CC}"
ASM="${ASM:-$RISCV64_AS}"
OBJDUMP="${OBJDUMP:-$RISCV64_OBJDUMP}"
CROSS_COMPILE="${CROSS_COMPILE:-${OBJDUMP%-objdump}-}"
READELF="${READELF:-${CROSS_COMPILE}readelf}"
# The guest KERNEL leg builds with the GCC 16 toolchain pin (CONFIG_RISCV_USER_CFI
# needs it); busybox, gcpt and OpenSBI ride the knobs above.
case "$RISCV64_GNU_PREFIX" in /*) ;; *) RISCV64_GNU_PREFIX="$ROOT/$RISCV64_GNU_PREFIX" ;; esac
[ -x "${RISCV64_GNU_PREFIX}gcc" ] ||
    die "kernel CC not found: ${RISCV64_GNU_PREFIX}gcc (RISCV64_GNU_PREFIX=$RISCV64_GNU_PREFIX; the GCC 16 toolchain pin) - install it or override RISCV64_GNU_PREFIX"
KERNEL_CROSS="$RISCV64_GNU_PREFIX"
KERNEL_CC="${RISCV64_GNU_PREFIX}gcc"
# NEMU_DIR/NEMU_BIN are one overridable pair; a relative value resolves
# against the repository root (env.sh keeps its default relative on purpose).
case "$NEMU_BIN" in /*) ;; *) NEMU_BIN="$ROOT/$NEMU_BIN" ;; esac
export SOURCE_DATE_EPOCH

# The staged corpus is the input: its manifest is written only after every
# staging step succeeded, so a half-staged tree can never be consumed.
[ -f "$CORPUS/manifest.json" ] || die "$CORPUS/manifest.json missing; stage_corpus.sh did not complete for this lane"
[ -d "$CORPUS/test" ] || die "$CORPUS/test missing; stage_corpus.sh did not complete for this lane"

# The DT ISA advertisement is scoped to the CFI variant lane (see the header):
# prepare.sh has already matched ENABLE_FLAG against the lane name, so this is
# the venue-side reading of the same switch - an unknown value means the lane
# wiring changed without this script.
case "${ENABLE_FLAG:-}" in
    "")                 CFI_VARIANT=0 ;;
    enable_riscv64_cfi) CFI_VARIANT=1 ;;
    *) die "ENABLE_FLAG='${ENABLE_FLAG}' is not a riscv64-nemu lane flag ('' or enable_riscv64_cfi)" ;;
esac

# The packing step below requires GNU cpio's --reproducible; probe it here,
# before any fetch or build, so a host without it fails with a diagnostic
# instead of dying at the archive step after the long build.  Capture the help
# text rather than piping it into grep -- the capture-then-case form keeps a
# nonzero `--help` from masking the match.
CPIO_HELP="$(cpio --help 2>/dev/null || true)"
case "$CPIO_HELP" in
    *--reproducible*) ;;
    *) die "this host's cpio does not support --reproducible (GNU cpio is required)" ;;
esac

# Provenance from the untouched work tree, captured before any build: the
# scratch tree the corpus was staged in is not provenance the guest should see,
# and a `-dirty` suffix here means the corpus really did come from an
# uncommitted bench tree.
BENCH_COMMIT="$(git -C "$ROOT/benchmark" rev-parse HEAD)"
BENCH_TREE="$(git -C "$ROOT/benchmark" describe --always --dirty)"

mkdir -p "$SRC" "$DL" "$OUT/generated-dts"

ensure_checkout() { # url dir commit
    local url="$1" dir="$2" commit="$3" head
    if [ ! -d "$dir/.git" ]; then
        echo "   clone $url"
        git clone --quiet "$url" "$dir"
    fi
    if ! git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null; then
        git -C "$dir" fetch --quiet origin "$commit"
    fi
    git -C "$dir" checkout --quiet --detach "$commit"
    head="$(git -C "$dir" rev-parse HEAD)"
    [ "$head" = "$commit" ] || die "$dir is at $head, expected $commit"
}

fetch_tarball() { # tarball sha256 url
    local name="$1" sha="$2" url="$3" seed
    if [ -f "$DL/$name" ] && echo "$sha  $DL/$name" | sha256sum -c --quiet -; then
        echo "   cached $name"; return 0
    fi
    for seed in "${SEED_DIRS[@]}"; do
        if [ -f "$seed/$name" ] && echo "$sha  $seed/$name" | sha256sum -c --quiet -; then
            echo "   seed $name from $seed"; cp "$seed/$name" "$DL/$name"; return 0
        fi
    done
    echo "   download $url"
    curl -fL --retry 3 -o "$DL/$name.part" "$url"
    echo "$sha  $DL/$name.part" | sha256sum -c --quiet - || { rm -f "$DL/$name.part"; die "sha256 mismatch for $name"; }
    mv "$DL/$name.part" "$DL/$name"
}

is_riscv_elf() { # file -> 0 when ELF64 riscv
    python3 - "$1" <<'PY'
import sys
h = open(sys.argv[1], "rb").read(20)
ok = len(h) >= 20 and h[:4] == b"\x7fELF" and h[4] == 2 and (h[18] | (h[19] << 8)) == 243
sys.exit(0 if ok else 1)
PY
}

echo "== [1/8] fetch pinned inputs into $SRC"
ensure_checkout "$WB_URL" "$SRC/workload-builder" "$WB_COMMIT"
mkdir -p "$SRC/bootloader"
ensure_checkout "$OPENSBI_URL" "$SRC/bootloader/opensbi" "$OPENSBI_COMMIT"
ensure_checkout "$LCA_URL" "$SRC/bootloader/LibCheckpointAlpha" "$LCA_COMMIT"
# build-sbi.sh reads its config and patch from the SBI source's parent dir
cp "$SRC/workload-builder/bootloader/opensbi.config" "$SRC/bootloader/opensbi.config"
cp "$SRC/workload-builder/bootloader/opensbi.patch" "$SRC/bootloader/opensbi.patch"
WB="$SRC/workload-builder"
fetch_tarball "$KERNEL_TARBALL" "$KERNEL_SHA256" "$KERNEL_URL"
fetch_tarball "$BUSYBOX_TARBALL" "$BUSYBOX_SHA256" "$BUSYBOX_URL"

echo "== [2/8] busybox (static)"
if [ ! -x "$OUT/busybox-$BUSYBOX_VER/_install/bin/busybox" ]; then
    [ -d "$OUT/busybox-$BUSYBOX_VER" ] || tar -C "$OUT" -xf "$DL/$BUSYBOX_TARBALL"
    make -C "$OUT/busybox-$BUSYBOX_VER" defconfig >/dev/null
    sed -i 's/^# CONFIG_STATIC is not set$/CONFIG_STATIC=y/' "$OUT/busybox-$BUSYBOX_VER/.config"
    # busybox 1.36.1's tc applet no longer compiles against modern kernel
    # headers (the CBQ constants are gone); the guest needs no traffic control
    sed -i 's/^CONFIG_TC=y$/# CONFIG_TC is not set/' "$OUT/busybox-$BUSYBOX_VER/.config"
    # CC= pins the versioned gcc-13: the unversioned riscv64-linux-gnu-gcc on
    # this workstation is a newer major (15.x), and the corpus is built with
    # g++-13; the env repo's riscv64 lane pins the same pair
    make -C "$OUT/busybox-$BUSYBOX_VER" -j"$JOBS" CROSS_COMPILE="$CROSS_COMPILE" CC="$CC" >/dev/null
    make -C "$OUT/busybox-$BUSYBOX_VER" install CROSS_COMPILE="$CROSS_COMPILE" CC="$CC" >/dev/null
fi
if "$READELF" -d "$OUT/busybox-$BUSYBOX_VER/_install/bin/busybox" | grep -q NEEDED; then
    die "busybox is not statically linked"
fi
is_riscv_elf "$OUT/busybox-$BUSYBOX_VER/_install/bin/busybox" || die "busybox is not a riscv64 ELF"
[ -e "$OUT/busybox-$BUSYBOX_VER/_install/sbin/init" ] || die "busybox has no init applet"

echo "== [3/8] Linux $KERNEL_VER Image"
mkdir -p "$OUT/kernel"
# the cache key carries the version, so a kernel bump can never silently reuse
# the previous kernel's Image; out/kernel/Image is the working copy stage [7/8]
# pads, the cached per-version file stays the pristine build product
if [ ! -f "$OUT/kernel/Image-$KERNEL_VER" ]; then
    [ -d "$OUT/linux-$KERNEL_VER" ] || tar -C "$OUT" -xf "$DL/$KERNEL_TARBALL"
    # wb's NEMU fragment minus CONFIG_INITRAMFS_SOURCE: the rootfs travels in
    # the DTB /chosen node instead (the firmware packer patches it in)
    grep -v '^CONFIG_INITRAMFS_SOURCE=' "$WB/br2-external/board/openxiangshan/nemu/linux.config" \
        > "$OUT/linux-$KERNEL_VER/.config"
    # userspace vector, the load-bearing pair (see the header): RISCV_ISA_V is
    # the kernel-side vector support, RISCV_ISA_V_DEFAULT_ENABLE makes
    # riscv_v_default_allow default to allow -- glibc never issues the V prctl.
    # CONFIG_RISCV_USER_CFI enables user-mode CFI; it arms per thread only when
    # the guest DT advertises zicfiss (that advertisement is scoped to the CFI
    # variant above).  Its Kconfig gate needs the GCC 16 kernel CC below.
    printf 'CONFIG_RISCV_ISA_V=y\nCONFIG_RISCV_ISA_V_DEFAULT_ENABLE=y\nCONFIG_RISCV_USER_CFI=y\n' \
        >> "$OUT/linux-$KERNEL_VER/.config"
    # CC= is the GCC 16 pin for this leg only (see the toolchain pin above)
    make -C "$OUT/linux-$KERNEL_VER" ARCH=riscv CROSS_COMPILE="$KERNEL_CROSS" CC="$KERNEL_CC" olddefconfig >/dev/null
    make -C "$OUT/linux-$KERNEL_VER" ARCH=riscv CROSS_COMPILE="$KERNEL_CROSS" CC="$KERNEL_CC" -j"$JOBS" WERROR=0 Image
    for sym in CONFIG_RISCV_ISA_V CONFIG_RISCV_ISA_V_DEFAULT_ENABLE CONFIG_RISCV_USER_CFI; do
        grep -qx "$sym=y" "$OUT/linux-$KERNEL_VER/.config" \
            || die "built .config lacks $sym=y; guest userspace vector would SIGILL (CONFIG_RISCV_USER_CFI in particular needs the GCC 16 kernel CC pin RISCV64_GNU_PREFIX=$RISCV64_GNU_PREFIX - a toolchain without -fcf-protection support silently drops the symbol)"
    done
    cp "$OUT/linux-$KERNEL_VER/arch/riscv/boot/Image" "$OUT/kernel/Image-$KERNEL_VER"
fi
cp "$OUT/kernel/Image-$KERNEL_VER" "$OUT/kernel/Image"

echo "== [4/8] gcpt and OpenSBI (DEFAULT_DTB=xiangshan)"
if [ ! -f "$OUT/gcpt/build/gcpt.bin" ]; then
    CROSS_COMPILE="$CROSS_COMPILE" DEFAULT_DTB=xiangshan DTS_TEMPLATE_DIR="$OUT/generated-dts" \
        bash "$WB/scripts/build-gcpt.sh" "$SRC/bootloader/LibCheckpointAlpha" "$OUT/gcpt"
fi
if [ ! -f "$OUT/opensbi/build/platform/generic/firmware/fw_jump.bin" ]; then
    CROSS_COMPILE="$CROSS_COMPILE" DEFAULT_DTB=xiangshan DTS_TEMPLATE_DIR="$OUT/generated-dts" \
        bash "$WB/scripts/build-sbi.sh" "$SRC/bootloader/opensbi" "$OUT/opensbi"
fi
# gcpt.bin is the raw payload the image carries; the ELF it was objcopy'd
# from is the sibling `gcpt`, and that one must be riscv64 (a host-compiled
# gcpt would boot nothing)
is_riscv_elf "$OUT/gcpt/build/gcpt" || die "gcpt (the ELF) is not a riscv64 ELF"
[ -s "$OUT/gcpt/build/gcpt.bin" ] || die "gcpt.bin is empty"

echo "== [5/8] stage the guest bench tree (cross scheduler, libcfi, corpus)"
rm -rf "$DEST/bench" "$DEST/lib" "$DEST/lib64"   # no stale staging from an earlier deploy may survive
rm -f "$DEST/manifest.json"        # and a stale manifest must not satisfy a consumer's guard
mkdir -p "$DEST/bench/test" "$DEST/bench/lib/common" "$DEST/lib"
# Cross-built guest scheduler: `-B` because GNU make does not rebuild on
# variable changes alone, and the worktree may carry a host build.  The
# scheduler's own CSB_TARGET_ARCH is $(ARCH) here, i.e. the riscv64 token the
# tracked registry's skip lists are written in (none for this lane).
make -B -C "$ROOT/benchmark" run-test lib/common/libcfi.so \
    ARCH=riscv64 CXX="$CXX" ASM="$ASM" OBJDUMP="$OBJDUMP" >"$DEST/scheduler-crossbuild.log" 2>&1
install -m 0755 "$ROOT/benchmark/run-test" "$DEST/bench/run-test"
cp -p "$ROOT/benchmark/lib/common/libcfi.so" "$DEST/bench/lib/common/libcfi.so"
# The guest's registry is the tracked bench registry, copied verbatim - never
# a derived subset (stage_corpus.sh verified it byte-identical).
cp "$CORPUS/configure.json" "$DEST/bench/configure.json"
cp -a "$CORPUS/test/." "$DEST/bench/test/"
install -m 0644 "$CORPUS/manifest.json" "$DEST/manifest.json"

# The guest's own system description: report_gen() prefixes results.dat with
# this file, so it must describe the venue the results came from -- not the
# host that built them (the Makefile's own test/sys_info.txt is the host's).
{
    echo "Venue: cpu-sec-bench inside a booted Linux guest under XiangShan NEMU (system mode, riscv64)"
    echo "Corpus compiler: $("$CXX" --version | head -n1)"
    echo "Corpus objdump: $("$OBJDUMP" --version | head -n1)"
    echo "Bench commit: $BENCH_COMMIT"
    echo "Bench tree: $BENCH_TREE"
    echo "Platform: scripts/riscv64_nemu/venue (absorbed from platform/riscv64-nemu-linux)"
} > "$DEST/bench/test/sys_info.txt"

echo "== [6/8] runtime libraries (NEEDED + PT_INTERP closure)"
# Runtime libraries: closure over NEEDED plus the PT_INTERP loader, resolved
# through the cross compiler's own search path.  libcfi.so is NOT staged to
# /lib: the cpi/cfi binaries reach it through their relative RUNPATH
# (lib/common/) with the guest's cwd at /bench.
#
# Placement follows the staged loader's own compiled-in search dirs (measured
# 2026-11-18): the GCC 16 loader looks in /lib64/lp64d/ and /usr/lib64/lp64d/
# only, the apt gcc-13 loader in /lib/ and /usr/lib/ (+ the riscv64-linux-gnu
# multiarch dirs).  The closure goes into CLOSURE_DIR; the loader itself stays
# at its PT_INTERP path - the kernel opens that absolute path at execve.
is_elf() { [ "$(head -c4 "$1" | od -An -tx1 | tr -d ' \n')" = "7f454c46" ]; }
if [ "$CFI_VARIANT" -eq 1 ]; then
    CLOSURE_DIR="$DEST/lib64/lp64d"
    CLOSURE_REL=/lib64/lp64d
    LOADER_SEARCH="/lib64/lp64d /usr/lib64/lp64d"
else
    CLOSURE_DIR="$DEST/lib"
    CLOSURE_REL=/lib
    LOADER_SEARCH="/lib /usr/lib"
fi
mkdir -p "$CLOSURE_DIR"
declare -a queue=()
queue+=("$DEST/bench/run-test")
for f in "$DEST/bench/test/"*; do queue+=("$f"); done
[ -f "$DEST/bench/lib/common/libcfi.so" ] && queue+=("$DEST/bench/lib/common/libcfi.so")
declare -A staged_seen=()
declare -A interp_paths=()
while [ "${#queue[@]}" -gt 0 ]; do
    f="${queue[0]}"; queue=("${queue[@]:1}")
    [ -n "${staged_seen[$f]:-}" ] && continue
    staged_seen[$f]=1
    is_elf "$f" || continue
    interp="$("$READELF" -l "$f" | sed -n 's/.*Requesting program interpreter: \(.*\)\]/\1/p')"
    [ -z "$interp" ] || interp_paths["$(basename "$interp")"]="$interp"
    for soname in $interp $("$OBJDUMP" -p "$f" | awk '$1=="NEEDED"{print $2}'); do
        base="$(basename "$soname")"
        if [ -n "$interp" ] && [ "$soname" = "$interp" ]; then
            dest="$DEST$soname"                             # PT_INTERP: an absolute guest path
        else
            dest="$CLOSURE_DIR/$base"
        fi
        [ -e "$dest" ] && continue
        [ -e "$DEST/bench/lib/common/$base" ] && continue   # relative-RUNPATH library
        src="$("$CXX" -print-file-name="$base")"
        if [ ! -f "$src" ]; then
            die "unresolved library $base (needed by $f)"
        fi
        cp -pL "$src" "$dest"
        queue+=("$dest")
    done
done
# Every staged ELF's NEEDED must live in a directory the staged loader actually
# searches (or at its relative-RUNPATH home): resolving the right files is not
# enough, a closure staged elsewhere is invisible at the first exec.  The one
# exemption is the ELF interpreter's own soname: the loader is staged at its
# PT_INTERP path, the kernel opens that absolute path at execve and the loader
# resolves its own soname from its link map, so it is never searched - but
# libc.so.6 still lists it as an ordinary NEEDED.
assert_closure_reachable() {  # elf...
    local elf dep d found ipath
    for elf in "$@"; do
        is_elf "$elf" || continue
        while IFS= read -r dep; do
            [ -n "$dep" ] || continue
            found=0
            for d in $LOADER_SEARCH; do
                [ -f "$DEST$d/$dep" ] && { found=1; break; }
            done
            if [ "$found" -eq 0 ]; then
                ipath="${interp_paths[$dep]:-}"
                if [ -n "$ipath" ] && [ -f "$DEST$ipath" ]; then found=1; fi
            fi
            if [ "$found" -eq 0 ] && [ ! -f "$DEST/bench/lib/common/$dep" ]; then
                die "$elf: NEEDED $dep is not staged in any directory the staged loader searches ($LOADER_SEARCH) - stage the closure into one of them"
            fi
        done < <("$READELF" -d "$elf" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
    done
}
closure_check=("$DEST/bench/run-test" "$DEST/bench/lib/common/libcfi.so")
for f in "$DEST/bench/test/"*; do closure_check+=("$f"); done
while IFS= read -r -d '' f; do closure_check+=("$f"); done \
    < <(find "$DEST/lib" "$CLOSURE_DIR" -maxdepth 1 -type f -print0 | sort -zu)
assert_closure_reachable "${closure_check[@]}"
echo "   staged libs ($CLOSURE_REL): $(find "$DEST/lib" "$CLOSURE_DIR" -maxdepth 1 -type f -printf '%f\n' | sort -u | tr '\n' ' ')"

echo "== [7/8] rootfs tree and cpio"
rm -rf "$OUT/rootfs"
mkdir -p "$OUT/rootfs"/{bench,lib,etc,proc,sys,tmp,dev}
mkdir -p "$OUT/rootfs$CLOSURE_REL"
cp -a "$OUT/busybox-$BUSYBOX_VER/_install/." "$OUT/rootfs/"
ln -sf bin/busybox "$OUT/rootfs/init"
install -m 0644 "$ROOT/scripts/riscv64_nemu/venue/guest/inittab" "$OUT/rootfs/etc/inittab"
cp -a "$DEST/bench/." "$OUT/rootfs/bench/"
cp -a "$DEST/lib/." "$OUT/rootfs/lib/"
[ "$CLOSURE_REL" = /lib ] || cp -a "$DEST$CLOSURE_REL/." "$OUT/rootfs$CLOSURE_REL/"
"$CC" -O2 -static -o "$OUT/rootfs/bench/nemu-trap" "$ROOT/scripts/riscv64_nemu/venue/guest/nemu-trap.c"
install -m 0755 "$ROOT/scripts/riscv64_nemu/venue/guest/bench.sh" "$OUT/rootfs/bench/bench.sh"
is_riscv_elf "$OUT/rootfs/bench/nemu-trap" || die "nemu-trap is not a riscv64 ELF"

# Byte reproducibility: the tree above was just assembled by mkdir/cp/install,
# whose wall-clock mtimes would otherwise be archived by cpio (the kernel and
# busybox builds already honour SOURCE_DATE_EPOCH).  Stamp every entry -- -h so
# symlinks are stamped themselves, not their targets -- and feed cpio a sorted
# file list so the archive does not depend on readdir order either.
# --reproducible (GNU cpio: --ignore-devno --ignore-dirnlink --renumber-inodes)
# finishes the job: device numbers are zeroed, inode numbers are renumbered
# deterministically in list order and directory link counts are pinned, so the
# host's own inode numbers never reach the newc headers.
find "$OUT/rootfs" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
( cd "$OUT/rootfs" && find . | LC_ALL=C sort | cpio -o -H newc --owner=0:0 --reproducible ) > "$DEST/rootfs.cpio" 2>/dev/null
echo "   rootfs.cpio: $(stat -c%s "$DEST/rootfs.cpio") bytes"

echo "== [8/8] assemble fw_payload.bin"
# The kernel's runtime footprint is larger than its Image file -- BSS lives
# past the last PROGBITS section -- so workload-builder's assembler, which
# places the initramfs at the first MiB boundary after the *file*, can land it
# inside the kernel's own reserved range; the kernel then discards it
# ("INITRD: ... overlaps in-use memory region") and panics with no root fs.
# Pad the Image until that boundary clears _end by a full MiB; the padded
# tail is zeros beyond the kernel that nothing ever reads (the kernel zeroes
# its own BSS).
source "$WB/scripts/dts-config.sh"
read -r MEM_BEGIN MEM_SIZE CLINT_MMIO <<< "$(dts_extract_config "$OUT/generated-dts/xiangshan.dts.in")"
# both spellings normalised here: dts_linux_kernel_address prints a DECIMAL
# address while System.map addresses are bare hex (an earlier version read the
# decimal through int(_, 16) as well, which garbled only the report line below
# -- the padding arithmetic never used that value)
KERNEL_BEGIN=$(( $(dts_linux_kernel_address "$MEM_BEGIN" $((4 * 1024 * 1024))) ))
KERNEL_START_V=$(( 0x$(awk '$3=="_start"{print $1; exit}' "$OUT/linux-$KERNEL_VER/System.map") ))
KERNEL_END_V=$(( 0x$(awk '$3=="_end"{print $1; exit}' "$OUT/linux-$KERNEL_VER/System.map") ))
python3 - "$OUT/kernel/Image" "$KERNEL_BEGIN" "$KERNEL_START_V" "$KERNEL_END_V" <<'PY'
import os, sys
image = sys.argv[1]
begin, start_v, end_v = (int(a) for a in sys.argv[2:5])
footprint = end_v - start_v      # link-time virtual span == the physical span here
mib = 1024 * 1024
need = (footprint + mib + mib - 1) // mib * mib
size = os.path.getsize(image)
if size < need:
    with open(image, "ab") as f:
        f.write(b"\0" * (need - size))
    print("   kernel Image padded %d -> %d bytes (clears _end by 1 MiB;" % (size, need))
    print("   initramfs will land at 0x%x, kernel _end at 0x%x)" % (begin + need, begin + footprint))
PY

# The guest DT advertisement is a precondition of arming (see dtc-cfi.sh):
# workload-builder regenerates the DTS template inside build-firmware-linux.sh,
# so the patch point is the builder's own DTC env hook.  The interposer is
# INSTALLED into the image build tree with an explicit mode - build-firmware
# execs "$DTC" directly, and this repository tracks its scripts without the
# executable bit.  Only the CFI variant interposes; the plain lane hands the
# real dtc, so its DT carries no advertisement (the assertion below pins that).
if [ "$CFI_VARIANT" -eq 1 ]; then
    DTC_TOOL="$OUT/dtc-cfi.sh"
    install -m 0755 "$ROOT/scripts/riscv64_nemu/venue/dtc-cfi.sh" "$DTC_TOOL"
else
    DTC_TOOL=$(command -v dtc) || die "dtc not found on PATH"
fi

CROSS_COMPILE="$CROSS_COMPILE" DTC="$DTC_TOOL" \
    DEFAULT_DTB=xiangshan \
    FIRMWARE_OUTPUT="$DEST/fw_payload.bin" \
    bash "$WB/scripts/build-firmware-linux.sh" \
        "$OUT/gcpt/build/gcpt.bin" "$OUT/opensbi" "$OUT/generated-dts" "$OUT/kernel/Image" "$DEST"

# The DT advertisement is a precondition of arming, so the CFI variant asserts
# it on the COMPILED tree the firmware embeds - never on the template that was
# handed in (workload-builder regenerates the template, and the interposer
# patches what dtc actually compiles).  The plain lane asserts the opposite:
# its pinned interpreter has no ssp CSR, and an advertising DT makes the 7.3.4
# kernel write it at the first userspace return - a measured boot panic.
DTB="$OUT/dt/xiangshan.dtb"
[ -f "$DTB" ] || die "the firmware build produced no $DTB"
dtb_dts=$(dtc -I dtb -O dts "$DTB" 2>/dev/null) ||
    die "cannot decompile $DTB to verify the guest DT's ISA advertisement"
for ext in zicfiss zicfilp; do
    if [ "$CFI_VARIANT" -eq 1 ]; then
        case "$dtb_dts" in
            *"$ext"*) ;;
            *) die "the compiled guest DTB $DTB advertises no $ext - the venue's dtc interposer (venue/dtc-cfi.sh) did not run or the DTS carries no riscv,isa-extensions; without the advertisement OpenSBI and the kernel are blind to CFI and every armed record would exit 20" ;;
        esac
    else
        case "$dtb_dts" in
            *"$ext"*) die "the compiled guest DTB $DTB advertises $ext on the PLAIN lane - the advertisement is scoped to enable_riscv64_cfi; with it the 7.3.4 kernel writes the ssp CSR at the first userspace return and the pinned interpreter (no such CSR) panics at boot" ;;
            *) ;;
        esac
    fi
done

python3 - "$DEST" "$NEMU_BIN" "$ROOT/benchmark" "$CXX" \
    "$WB_COMMIT" "$OPENSBI_COMMIT" "$LCA_COMMIT" \
    "$KERNEL_VERSION ($KERNEL_SHA256)" "$BUSYBOX_VERSION ($BUSYBOX_SHA256)" <<'PY'
import hashlib, json, os, subprocess, sys
dest, nemu, bench, cxx = sys.argv[1:5]
wb, opensbi, lca, linux_pin, busybox_pin = sys.argv[5:10]
def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""): h.update(c)
    return h.hexdigest()
meta = {
    "platform": "riscv64-nemu (absorbed venue package)",
    "bench_commit": subprocess.run(["git", "-C", bench, "rev-parse", "HEAD"],
                                   capture_output=True, text=True).stdout.strip(),
    # `-dirty` means the image was built from an uncommitted bench tree: the
    # commit alone would not reproduce the scheduler baked into it.
    "bench_tree": subprocess.run(["git", "-C", bench, "describe", "--always", "--dirty"],
                                 capture_output=True, text=True).stdout.strip(),
    "toolchain": subprocess.run([cxx, "--version"], capture_output=True, text=True).stdout.splitlines()[0].strip(),
    "fw_payload_bin": {"path": os.path.join(dest, "fw_payload.bin"), "sha256": sha(os.path.join(dest, "fw_payload.bin"))},
    "rootfs_cpio": {"path": os.path.join(dest, "rootfs.cpio"), "sha256": sha(os.path.join(dest, "rootfs.cpio"))},
    "nemu_bin": {"path": nemu, "sha256": sha(nemu) if os.path.exists(nemu) else None},
    "pins": {
        "workload_builder": wb,
        "opensbi": opensbi,
        "libcheckpointalpha": lca,
        "linux": linux_pin,
        "busybox": busybox_pin,
    },
}
with open(os.path.join(dest, "meta.json"), "w") as f:
    json.dump(meta, f, indent=2, sort_keys=True); f.write("\n")
print("   fw_payload.bin: %d bytes, sha256 %s" % (os.path.getsize(os.path.join(dest, "fw_payload.bin")), meta["fw_payload_bin"]["sha256"][:16]))
PY

echo "== done: $DEST/fw_payload.bin"
