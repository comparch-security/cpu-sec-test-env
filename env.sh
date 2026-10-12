# env.sh - the single source of truth for pins, URLs, timeouts and roots.
#
# Sourced by every shell script (scripts/**) and read by the Makefile through
# `$(shell . ./env.sh && echo $$VAR)`.  POSIX sh only: keep every line
# sourceable from plain /bin/sh (no bashisms, no side effects).  All version
# pins, URLs and timeouts live HERE - no script hard-codes them.

# ---- bench pin (submodule commit; prerequisite for the whole lane set) ----
BENCH_COMMIT=c2c703979ae3db86f36709e7299740760c8c7e1d

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
QEMU_CPU_RISCV64=rv64
QEMU_CPU_AARCH64_MTE=max,mte=on
QEMU_BIOS_RISCV64=default
QEMU_MACH_RISCV64=virt
QEMU_MEM_RISCV64=256

# ---- kernel pin (guest kernel for the riscv64 system lane) ----
KERNEL_VERSION=6.1.83
KERNEL_URL=https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.1.83.tar.xz
KERNEL_SHA256=88b69611093613ce4494527685f833af0c31b986dcbeda7086f69f18f9e0b190

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
LANE_RUN_TIMEOUT=3600
LANE_DEPLOY_TIMEOUT=7200

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
