#!/usr/bin/env bash
# aarch64_makeflags.sh - the ONE composer of the aarch64 lanes' MAKEFLAGS string.
#
# Sourced by scripts/aarch64/prepare.sh (which records the string in the
# guest-truth sys_info header) and scripts/aarch64/run.sh (which exports it as
# MAKEFLAGS for the scheduler's child makes).  The two MUST agree - the header
# is the record of what the children receive - so the composition lives here
# once instead of in two hand-kept copies.  Reads the caller's ARCH,
# ENABLE_FLAG, AARCH64_CXX, AARCH64_AS and AARCH64_OBJDUMP.

aarch64_makeflags() {
  local mf="ARCH=$ARCH CXX=$AARCH64_CXX ASM=$AARCH64_AS OBJDUMP=$AARCH64_OBJDUMP"
  if [ -n "${ENABLE_FLAG:-}" ]; then
    mf="$mf $ENABLE_FLAG=yes"
  fi
  printf '%s\n' "$mf"
}
