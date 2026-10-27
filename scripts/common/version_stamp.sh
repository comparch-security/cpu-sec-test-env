#!/usr/bin/env bash
set -euo pipefail
# version_stamp.sh LANE OUT_FILE [RUN_STATUS]
#
# Writes the host-provenance record: env.sh pins + dpkg-query versions of the
# pinned host packages + the host `uname -a`.  The uname line is tagged
# "host-uname:" so scripts/riscv64/guest/init can drop it when seeding the
# guest's test/sys_info.txt (the guest records its own kernel, never this one).
# An optional ENABLE_FLAG in the environment is recorded as the lane's
# flag line so variant lanes remain distinguishable.
#
# Two sections make every stamp self-describing for the lane comparison
# (scripts/common/compare_lanes.py):
#   # bench checkout - bench-head (rev-parse HEAD) and bench-tree
#     (describe --always --dirty), so a stamp states the checkout its results
#     came from.  A failing git records an "unavailable" sentinel with its rc,
#     never a value and never a crash.
#   # run status - "run-status: ok" when the run finished, "run-status: failed
#     (rc=N)" otherwise, from $3 or $RUN_STATUS.  Collectors pass their own
#     final rc; a caller that records no rc publishes "ok".

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "usage: $0 LANE OUT_FILE [RUN_STATUS]" >&2
  exit 2
fi
LANE=$1
OUT=$2
run_status=${3:-${RUN_STATUS:-ok}}

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
  echo "# bench checkout"
  git_rc=0
  bench_head=$(git -C benchmark rev-parse HEAD 2>/dev/null) || git_rc=$?
  if [ "$git_rc" -eq 0 ] && [ -n "$bench_head" ]; then
    echo "bench-head: $bench_head"
  else
    echo "bench-head: unavailable (git rc=$git_rc)"
  fi
  git_rc=0
  bench_tree=$(git -C benchmark describe --always --dirty 2>/dev/null) || git_rc=$?
  if [ "$git_rc" -eq 0 ] && [ -n "$bench_tree" ]; then
    echo "bench-tree: $bench_tree"
  else
    echo "bench-tree: unavailable (git rc=$git_rc)"
  fi
  echo "# run status"
  if [ "$run_status" = ok ] || [ "$run_status" = 0 ]; then
    echo "run-status: ok"
  else
    echo "run-status: failed (rc=$run_status)"
  fi
} > "$OUT"
