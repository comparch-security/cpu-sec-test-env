#!/usr/bin/env bash
set -euo pipefail
# shim.sh PREFIX|TOOL SHIM_DIR
#
# The bench's script/get_{aarch64,riscv64}_func_inst.sh call bare `objdump`;
# every lane whose scheduler builds cross-target units must put a shim dir
# first on PATH so that call resolves to the cross objdump instead of the
# host's single-target binutils.  Creates SHIM_DIR/objdump -> the target tool.
#
# The first argument is either a bare tool prefix (resolved as PREFIX-objdump
# on PATH, the original contract) or an absolute tool path, used as-is - the
# CHERI SDK's bin dir is deliberately off PATH, so the cheri lane passes its
# resolved objdump path directly.

if [ $# -ne 2 ]; then
  echo "usage: $0 PREFIX|TOOL SHIM_DIR" >&2
  exit 2
fi
TOOL=$1
SHIM_DIR=$2

case "$TOOL" in
  */*) target=$TOOL ;;
  *)
    target=$(command -v "${TOOL}-objdump") || {
      echo "shim: ${TOOL}-objdump not found on PATH" >&2
      exit 1
    }
    ;;
esac
[ -x "$target" ] || {
  echo "shim: $target is not an executable" >&2
  exit 1
}
mkdir -p "$SHIM_DIR"
ln -sfn "$target" "${SHIM_DIR}/objdump"
