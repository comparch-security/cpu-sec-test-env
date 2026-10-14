#!/usr/bin/env bash
set -euo pipefail
# shim.sh PREFIX SHIM_DIR
#
# The bench's script/get_{aarch64,riscv64}_func_inst.sh call bare `objdump`;
# every lane whose scheduler builds cross-target units must put a shim dir
# first on PATH so that call resolves to the cross objdump instead of the
# host's single-target binutils.  Creates SHIM_DIR/objdump -> PREFIX-objdump.

if [ $# -ne 2 ]; then
  echo "usage: $0 PREFIX SHIM_DIR" >&2
  exit 2
fi
PREFIX=$1
SHIM_DIR=$2

target=$(command -v "${PREFIX}-objdump") || {
  echo "shim: ${PREFIX}-objdump not found on PATH" >&2
  exit 1
}
mkdir -p "$SHIM_DIR"
ln -sfn "$target" "${SHIM_DIR}/objdump"
