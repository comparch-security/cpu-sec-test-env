#!/usr/bin/env bash
set -euo pipefail
# version_stamp.sh LANE OUT_FILE
#
# Writes the host-provenance record: env.sh pins + dpkg-query versions of the
# pinned host packages + the host `uname -a`.  The uname line is tagged
# "host-uname:" so scripts/riscv64/guest/init can drop it when seeding the
# guest's test/sys_info.txt (the guest records its own kernel, never this one).
# An optional ENABLE_FLAG in the environment is recorded as the lane's
# flag line so variant lanes remain distinguishable.

if [ $# -ne 2 ]; then
  echo "usage: $0 LANE OUT_FILE" >&2
  exit 2
fi
LANE=$1
OUT=$2

case "$LANE" in
  x86_64|riscv64|riscv64-nemu|cheri_riscv64|aarch64|aarch64-*|aarch64-morello) ;;
  *)
    echo "usage: $0 LANE OUT_FILE  (LANE must be a known lane name, got '$LANE')" >&2
    exit 2
    ;;
esac

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=../../env.sh
. ./env.sh

mkdir -p -- "$(dirname -- "$OUT")"
{
  echo "# lane: ${LANE}"
  if [ -n "${ENABLE_FLAG:-}" ]; then
    echo "${ENABLE_FLAG}=yes"
  fi
  echo "# pins (env.sh)"
  cat env.sh
  echo "# host packages (dpkg-query)"
  for p in ${STAMP_PACKAGES}; do
    dpkg-query -W -f='${Package} ${Version}\n' "$p" 2>/dev/null || echo "$p MISSING"
  done
  echo "# host kernel"
  echo "host-uname: $(uname -a)"
} > "$OUT"
