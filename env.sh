# env.sh - the single source of truth for pins, URLs, timeouts and roots.
#
# Sourced by every shell script (scripts/**) and read by the Makefile through
# `$(shell . ./env.sh && echo $$VAR)`.  POSIX sh only: keep every line
# sourceable from plain /bin/sh (no bashisms, no side effects).  All version
# pins, URLs and timeouts live HERE - no script hard-codes them.

# ---- bench pin (submodule commit; prerequisite for the whole lane set) ----
# 74195c4 carries the opcode-extraction platform fix: the cheri_riscv64
# extractor branch, the $(OBJDUMP) pass-through, the extractor hardening and
# the acc/read-func.cpp parse check (on top of c8c6000's sweep: the continue
# fix, warning cleanup, catalog hardening, five .asm .size directives,
# registry diff).
BENCH_COMMIT=74195c4378e3cd97a7677555d66e473f19370962

# ---- cross toolchains (Ubuntu gcc-13 cross packages) ----
RISCV64_CXX=riscv64-linux-gnu-g++-13
RISCV64_CC=riscv64-linux-gnu-gcc-13
RISCV64_AS=riscv64-linux-gnu-as
RISCV64_OBJDUMP=riscv64-linux-gnu-objdump
AARCH64_CXX=aarch64-linux-gnu-g++-13
AARCH64_CC=aarch64-linux-gnu-gcc-13
AARCH64_AS=aarch64-linux-gnu-as
AARCH64_OBJDUMP=aarch64-linux-gnu-objdump
AARCH64_SYSROOT=/usr/aarch64-linux-gnu

# ---- qemu pins ----
QEMU_VERSION=10.2.1
QEMU_SYSTEM_RISCV64=qemu-system-riscv64
QEMU_AARCH64=qemu-aarch64
# rva23s64: qemu 10.2.1's named RVA23 Linux-capable hart profile.  Ubuntu's
# riscv64 cross glibc is built to the RVA23U64 profile (crt1.o/libc.so.6 carry
# that Tag_RISCV_arch and the linker unions input tags), so every executable
# this toolchain links declares RVA23U64 - a narrower model (rv64) is a latent
# illegal-instruction in the guest's own libc.  rva23u64 is the whitelisted
# fallback if the guest kernel mishandles an S-mode extension of rva23s64.
QEMU_CPU_RISCV64=rva23s64
QEMU_CPU_AARCH64_MTE=max,mte=on
QEMU_BIOS_RISCV64=default
QEMU_MACH_RISCV64=virt
QEMU_MEM_RISCV64=256

# ---- kernel pin (guest kernel for the riscv64 system lane) ----
# 6.18 LTS: the apt cross glibc is RVA23U64 machine code whose memcpy executes
# vector instructions, so the guest kernel must support userspace vector
# (landed in 6.5; 6.1.83 has no CONFIG_RISCV_ISA_V at all) and default it on
# (the fragment forces RISCV_ISA_V + RISCV_ISA_V_DEFAULT_ENABLE).
KERNEL_VERSION=6.18.56
KERNEL_URL=https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.18.56.tar.xz
KERNEL_SHA256=4633bbda2ab95eaf2a7af4041236451d6759c72e6946265531af4b3aacefbf89

# ---- busybox pin (static guest userspace) ----
BUSYBOX_VERSION=1.36.1
BUSYBOX_URL=https://busybox.net/downloads/busybox-1.36.1.tar.bz2
BUSYBOX_SHA256=b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314

# ---- reproducibility pins (kernel build identity + generic SOURCE_DATE_EPOCH) ----
KBUILD_BUILD_TIMESTAMP="Tue Oct 12 00:00:00 UTC 2026"
KBUILD_BUILD_USER=cpu-sec-test-env
KBUILD_BUILD_HOST=cpu-sec-test-env
SOURCE_DATE_EPOCH=1791763200

# ---- cheribuild pin (CHERI dialect probe toolchains) ----
CHERIBUILD_COMMIT=db2f0360381e5fa2d50379e92ad119bb98db25c4
CHERIBUILD_URL=https://codeload.github.com/CTSRD-CHERI/cheribuild/tar.gz
CHERIBUILD_NAME=cheribuild

# ---- lane timeouts (seconds); empty values are rejected by the Makefile ----
# Overridable form (plan 2026-10-14-cheri-lanes-bringup): a pre-set value in
# the environment survives this source, so the CHERI run recipe's forwarded
# LANE_RUN_TIMEOUT=$(LANE_RUN_TIMEOUT) can exercise the timeout-killed (124)
# no-publish path.  Defaults are unchanged; no other lane's behavior moves.
: "${LANE_RUN_TIMEOUT:=3600}"
: "${LANE_DEPLOY_TIMEOUT:=7200}"

# ---- roots (relative to the repository root) ----
BUILD_DIR=build
RESULTS_DIR=results

# ---- host packages recorded into versions.txt by version_stamp.sh ----
STAMP_PACKAGES="qemu-system-riscv qemu-user qemu-user-binfmt gcc-13-riscv64-linux-gnu g++-13-riscv64-linux-gnu gcc-13-aarch64-linux-gnu g++-13-aarch64-linux-gnu binutils-riscv64-linux-gnu libhwasan0-arm64-cross"

export BENCH_COMMIT
export RISCV64_CXX RISCV64_CC RISCV64_AS RISCV64_OBJDUMP
export AARCH64_CXX AARCH64_CC AARCH64_AS AARCH64_OBJDUMP AARCH64_SYSROOT
export QEMU_VERSION QEMU_SYSTEM_RISCV64 QEMU_AARCH64 QEMU_CPU_RISCV64
export QEMU_CPU_AARCH64_MTE QEMU_BIOS_RISCV64 QEMU_MACH_RISCV64 QEMU_MEM_RISCV64
export KERNEL_VERSION KERNEL_URL KERNEL_SHA256
export BUSYBOX_VERSION BUSYBOX_URL BUSYBOX_SHA256
export KBUILD_BUILD_TIMESTAMP KBUILD_BUILD_USER KBUILD_BUILD_HOST SOURCE_DATE_EPOCH
export CHERIBUILD_COMMIT CHERIBUILD_URL CHERIBUILD_NAME
export LANE_RUN_TIMEOUT LANE_DEPLOY_TIMEOUT
export BUILD_DIR RESULTS_DIR
export STAMP_PACKAGES

# ---- CHERI lanes pins (plan 2026-10-14-cheri-lanes-bringup, Step 1) ----
# Pinned source trees, staged by scripts/cheri/stage_sources.sh as REAL git
# repositories at the pinned commits (design A 2026-10-15: git init + fetch
# --depth 1 + detached checkout) into build/cheri/sources/; the staged
# commits' tree hashes are TOFU-recorded in build/cheri/versions-stage.txt.
# A tarball extract cannot satisfy cheribuild (ensure_cloned runs before
# skip_update and clones whenever .git is absent), so the *_URL pins are
# git remotes, not codeload routes.
CHERI_QEMU_COMMIT=32bf55e2965dcdcfb0139d209e7a7b9dd1314583
CHERI_QEMU_URL=https://github.com/CHERI-Alliance/qemu
CHERIBSD_SRC_COMMIT=88f39900c32928d807dba245fba138808c666f34
CHERIBSD_SRC_URL=https://github.com/CTSRD-CHERI/cheribsd
# riscv-pk - the source of the riscv64 lane's BBL boot firmware (the CHERI
# riscv64 machine loads the BBL into M-mode and jumps to the -kernel payload
# from there, so -kernel alone cannot boot the lane).  Cheribuild's directory
# name for this tree is "bbl", so stage_sources.sh stages it at sources/bbl
# - the *_URL pin is the git remote, same design-A staging as the two trees
# above.  BBL_SRC_COMMIT is the resolved cheri_purecap tip (2026-10-16).
BBL_SRC_URL=https://github.com/CTSRD-CHERI/riscv-pk
BBL_SRC_COMMIT=0cb596cf6e49c0014256300b614c5cd30cb90d57

# makefs: NO pins - the fork route was removed 2026-10-15 (user decision
# "remove it fully").  The disk-image leg uses makefs to build the EFI FAT
# partition (-t msdos), and the previously pinned Engil/makefs fork (last
# upstream commit 2021-10-15, i.e. exactly the old pin) has NO msdos
# support at all - hosted Step 6 attempt 5 died with
# `makefs: Unknown fs type 'msdos'`.  disk_image.py reads MAKEFS_CMD only
# as an OPTIONAL override and otherwise discovers the FreeBSD host-tools
# makefs that the world build itself produces (tmp/legacy/bin or
# tmp/usr/sbin) - that one has msdos and was verified producing a real
# FAT12 image.  So cheribuild needs no makefs pin, no makefs source tree
# and no CPPFLAGS waiver; MAKEFS_CMD, MAKEFS_SRC_{COMMIT,URL} and
# CHERI_MAKEFS_CPPFLAGS are deliberately absent.

# Emulator binaries and the narrowed cheribuild target list (the FINAL
# configure names - the pin's riscv64cheri-softmmu -> riscv64xcheri-softmmu
# rewrite is bypassed when --qemu/targets is set explicitly).
QEMU_RISCV64XCHERI=qemu-system-riscv64xcheri
QEMU_MORELLO=qemu-system-morello
QEMU_TARGETS_CHERI=riscv64xcheri-softmmu,morello-softmmu

# Host glibc 2.43 C23 shim for the CheriBSD world builds.  glibc 2.43
# declares strchr etc. as C23 _Generic macros returning const char * for
# a const argument, and FreeBSD's bootstrap makefile promotes the
# const-discard to an error (tools/build/mk/Makefile.boot:41), so stage
# 1.1's getopt.c/getopt_long.c fail on this host.  A make-variable waiver
# (CHERI_CROSS_BUILD_OPTIONS) was tried first and proved INEFFECTIVE:
# FreeBSD's build does not propagate an arbitrary command-line variable
# into the tools/build sub-make, which recomputes CWARNFLAGS.clang from
# scratch, and Makefile.boot's += wins last - so no externally supplied
# value can ever win, and the dead pin was removed (a pin that does
# nothing reads as a working control).  The shim #undef's the macro layer
# above glibc's own C17 declarations, restoring the pre-C23 return types;
# it reaches the compile via CPATH, which the compiler reads directly (no
# make cooperation) and which is searched after every -I, so the FreeBSD
# sysroot's headers still win in the cross stages - self-scoping to the
# host-tools stage that needs it.  Repo-relative, ONE space-free token
# (cheribuild splits list options on whitespace); build_image.sh passes
# it as --cheribsd/extra-env=CPATH=... on the CheriBSD legs ONLY.
CHERI_CROSS_CPATH="scripts/cheri/glibc-c23-shim"

# Per-lane disk-image pins - filled by scripts/cheri/build_image.sh after
# the image build (path repo-relative; sha256 of the pristine post-build
# artifact).  A rebuild re-fills them; a hand-edited image is never the
# supported way to change the pinned artifact.
CHERI_DISK_IMAGE_RISCV64=build/cheri/output/cheribsd-riscv64-purecap.img
CHERI_DISK_IMAGE_RISCV64_SHA256=afdcb05d293c9228b77b0cd50cc7e7f0471d74e3616ec96c5ac3d67f9a4e9121
CHERI_DISK_IMAGE_MORELLO=build/cheri/output/cheribsd-morello-purecap.img
CHERI_DISK_IMAGE_MORELLO_SHA256=00437fdd5258bfe05dc737142059e16f64905a592bdcb258995f34a2f49a9215

# Per-lane boot parameters - no script hard-codes them.  The riscv64 lane
# boots with -kernel (a disk-only riscv virt boot leaves kernel_entry = 0
# and the pin ships no RISC-V S-mode firmware); the morello lane boots UEFI
# (edk2-aarch64-code.fd, shipped with the pinned QEMU) and reaches its
# kernel through loader(8) from the disk.  Memory sizes start at
# cheribuild's own default and are re-sized from the measured image in
# Step 7.
#
# QEMU_CPU_CHERI_RISCV64 = rv64,sstc=off, NOT empty: QEMU advertises Sstc
# (its CPU property defaults on, so the guest DT claims it) while gating
# S-mode stimecmp on menvcfg.STCE, and the pinned BBL never writes menvcfg
# - so the kernel's first csrw stimecmp trapped (Illegal instruction
# 0x14d51073).  Not advertising Sstc pushes the kernel onto its own
# sbi_set_timer fallback, which this BBL does implement.  The spelling is
# the machine's own default model (virt's default_cpu_type is the concrete
# rv64), so it is one property, not a CPU swap - CHERI lives in the xcheri
# binary.
QEMU_MACH_CHERI_RISCV64=virt
QEMU_MACH_CHERI_MORELLO=virt,gic-version=3
QEMU_CPU_CHERI_RISCV64=rv64,sstc=off
QEMU_CPU_CHERI_MORELLO=morello
QEMU_MEM_CHERI_RISCV64=2048
QEMU_MEM_CHERI_MORELLO=2048
QEMU_BIOS_CHERI_MORELLO=edk2-aarch64-code.fd
# riscv64 -bios firmware: a BARE datadir filename with no path separators,
# exactly like the Morello pin above - QEMU resolves it through its datadir
# (hw/riscv/boot.c qemu_find_file), the same lookup the working Morello boot
# already uses.  Built by build_image.sh (cheribuild target
# bbl-baremetal-riscv64-purecap) and read back from output/sdk/share/qemu/,
# where that target installs it.
QEMU_BIOS_CHERI_RISCV64=bbl-riscv64cheri-virt-fw_jump.bin
# riscv64 -kernel input - filled by build_image.sh, read back from the
# built world (output/rootfs-riscv64-purecap/boot/kernel/kernel).
QEMU_KERNEL_CHERI_RISCV64=build/cheri/output/rootfs-riscv64-purecap/boot/kernel/kernel

# Per-lane netdev pins (guest egress containment): QEMU's default slirp
# netdev has restrict=off, so every CHERI boot pins its netdev explicitly.
# Default = -net none for the non-network delivery winner; Step 7 replaces
# these with the restrict=on user netdev + loopback hostfwd only if the SSH
# candidate wins.
QEMU_NET_CHERI_RISCV64="-net none"
QEMU_NET_CHERI_MORELLO="-net none"

# Per-lane purecap sysroot pins - filled by build_image.sh with the path
# OBSERVED from the built tree (usr/include/stdio.h + lib/libc.so.7 under
# the xtarget dir), never an assumed layout.  Every CHERI cross-compile
# must pass --sysroot=<the lane's pin> explicitly: without it the SDK
# clang resolves #include <stdio.h> against the host include root.
CHERI_SYSROOT_RISCV64=build/cheri/output/sdk/sysroot-riscv64-purecap
CHERI_SYSROOT_MORELLO=build/cheri/output/morello-sdk/sysroot-morello-purecap

# Generous bound on a full hosted scripts/cheri/build_emulator.sh or
# build_image.sh run (the shared LANE_DEPLOY_TIMEOUT cannot wrap a
# multi-hour world build; the CHERI Makefile recipes wrap only the cheap
# legs in LANE_DEPLOY_TIMEOUT).
CHERI_BUILD_TIMEOUT=86400

export CHERI_QEMU_COMMIT CHERI_QEMU_URL
export CHERIBSD_SRC_COMMIT CHERIBSD_SRC_URL
export BBL_SRC_URL BBL_SRC_COMMIT QEMU_BIOS_CHERI_RISCV64
export QEMU_RISCV64XCHERI QEMU_MORELLO QEMU_TARGETS_CHERI
export CHERI_CROSS_CPATH
export CHERI_DISK_IMAGE_RISCV64 CHERI_DISK_IMAGE_RISCV64_SHA256
export CHERI_DISK_IMAGE_MORELLO CHERI_DISK_IMAGE_MORELLO_SHA256
export QEMU_MACH_CHERI_RISCV64 QEMU_MACH_CHERI_MORELLO
export QEMU_CPU_CHERI_RISCV64 QEMU_CPU_CHERI_MORELLO
export QEMU_MEM_CHERI_RISCV64 QEMU_MEM_CHERI_MORELLO
export QEMU_BIOS_CHERI_MORELLO QEMU_KERNEL_CHERI_RISCV64
export QEMU_NET_CHERI_RISCV64 QEMU_NET_CHERI_MORELLO
export CHERI_SYSROOT_RISCV64 CHERI_SYSROOT_MORELLO
export CHERI_BUILD_TIMEOUT
