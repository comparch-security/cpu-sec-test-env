#!/usr/bin/env bash
set -euo pipefail
# prepare.sh LANE   (LANE = riscv64-nemu)
#
# Deploys the riscv64-nemu lane: the absorbed NEMU venue package
# (scripts/riscv64_nemu/venue/) driven as one lane of this dispatcher.  This
# script owns the lane lock, the ordered preflights and the two supervised
# build legs; every venue mechanism (the guest image assembly, the boot
# driver, the publish-on-success manifest) stays in the venue package, and the
# corpus is staged by the same orchestrator as every other system lane
# (scripts/common/stage_corpus.sh).
#
# Process supervision: each venue leg runs in its own session
# (`setsid bash <leg> &`, with the lane-lock fd closed, `9>&-`, so no
# descendant can hold the lock) and a TERM/INT trap kills that whole session
# and exits non-zero, so the EXIT path still runs.  The deploy leg's bound is
# the Makefile's outer `timeout`, which signals this wrapper, and the lane's
# trap performs the kill itself: the leg leader's process group, then a sweep
# of the whole session (`sid == LEG_PID`) with SIGKILL for whatever survives,
# so a builder that re-groups inside the session cannot outlive the wrapper.
# (This host's timeout - uutils coreutils 0.10.0 - does kill the child's
# process group when it expires; a marker probe confirmed it, and an earlier
# note claiming otherwise came from a self-matching `pgrep -f`.)  Without the
# kill a timed-out deploy would orphan builders that keep writing the venue
# tree after the lock is released.
#
# The deploy is offline once the venue's input caches exist under $OUT/src;
# a cold deploy needs network for the three pinned checkouts.

if [ $# -ne 1 ] || [ "$1" != riscv64-nemu ]; then
  echo "usage: $0 riscv64-nemu" >&2
  exit 2
fi
LANE=$1

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=../../env.sh
. ./env.sh

die() { echo "riscv64_nemu/prepare ($LANE): $*" >&2; exit 1; }

# ---- lane advisory lock ----
mkdir -p "$BUILD_DIR"
exec 9>>"$BUILD_DIR/.lane.lock"
if ! flock -n 9; then
  die "lane busy: $(cat "$BUILD_DIR/.lane.lock" 2>/dev/null || echo unknown) holds $BUILD_DIR/.lane.lock"
fi
printf '%s\n' "$LANE" > "$BUILD_DIR/.lane.lock"

VENUE="$ROOT/scripts/riscv64_nemu/venue"
OUT="$ROOT/$BUILD_DIR/riscv64-nemu/platform"
CORPUS="$ROOT/$BUILD_DIR/riscv64-nemu/corpus"

# NEMU_DIR/NEMU_BIN are one overridable pair; relative values resolve against
# the repository root (env.sh keeps its default relative on purpose).
case "$NEMU_DIR" in /*) ;; *) NEMU_DIR="$ROOT/$NEMU_DIR" ;; esac
case "$NEMU_BIN" in /*) ;; *) NEMU_BIN="$ROOT/$NEMU_BIN" ;; esac

# ---- process supervision (see the header) ----
LEG_PID=""
# Every live (non-zombie) process whose session id is $1.  /proc/<pid>/stat's
# fields after the command name are: state ppid pgrp session ...
leg_session_pids() { # sid
  local sid=$1 d pid rest state _ppid _pgrp sess _more
  for d in /proc/[0-9]*; do
    pid=${d#/proc/}
    [ "$pid" = "$$" ] && continue
    rest=$(cat "$d/stat" 2>/dev/null) || continue
    rest=${rest##*') '}
    read -r state _ppid _pgrp sess _more <<< "$rest" || continue
    if [ "$state" != Z ] && [ "${sess:-}" = "$sid" ]; then
      printf '%s\n' "$pid"
    fi
  done
  return 0
}

# Kill the venue leg's whole session: the leg leader's process group first,
# then a session sweep (a builder that re-groups inside the session would
# otherwise survive), with SIGKILL for whatever remains.  The children run with
# fd 9 closed, so no survivor can hold build/.lane.lock.
kill_leg() {
  [ -n "$LEG_PID" ] || return 0
  local sid=$LEG_PID i
  local -a pids=()
  kill -TERM -- "-$LEG_PID" 2>/dev/null || true
  mapfile -t pids < <(leg_session_pids "$sid")
  [ "${#pids[@]}" -eq 0 ] || kill -TERM "${pids[@]}" 2>/dev/null || true
  for i in 1 2 3 4 5 6 7 8 9 10; do
    mapfile -t pids < <(leg_session_pids "$sid")
    [ "${#pids[@]}" -eq 0 ] && break
    sleep 0.2
  done
  wait "$LEG_PID" 2>/dev/null || true
  mapfile -t pids < <(leg_session_pids "$sid")
  [ "${#pids[@]}" -eq 0 ] || kill -KILL "${pids[@]}" 2>/dev/null || true
}
term_leg() {
  trap - TERM INT
  kill_leg
  exit 130
}
trap term_leg TERM INT

run_leg() { # script -> its exit status
  local rc=0
  setsid bash "$1" 9>&- &
  LEG_PID=$!
  wait "$LEG_PID" || rc=$?
  LEG_PID=""
  return "$rc"
}

# The staging leg alone keeps the lane-lock descriptor: stage_corpus.sh is
# caller-locked, verifies that fd 9 IS the held lane lock, and closes it
# before it runs any child - so no descendant of the leg holds the lock
# either, and the supervisor's session sweep still reaches all of them.
run_leg_locked() { # script [args...] -> its exit status
  local rc=0
  setsid bash "$@" &
  LEG_PID=$!
  wait "$LEG_PID" || rc=$?
  LEG_PID=""
  return "$rc"
}

# ---- collect-and-clean on every exit path ----
cleanup() {
  rc=$?
  set +e
  make -C benchmark clean >/dev/null 2>&1
  assert_rc=0
  # A failing git is not a clean tree; only rc 0 with empty output means clean.
  dirty=$(git -C benchmark status --short)
  git_rc=$?
  if [ "$git_rc" -ne 0 ]; then
    echo "ERROR: cannot verify the benchmark submodule is clean: 'git -C benchmark status --short' failed (rc=$git_rc)" >&2
    assert_rc=1
  elif [ -n "$dirty" ]; then
    echo "ERROR: benchmark submodule left dirty after clean:" >&2
    printf '%s\n' "$dirty" >&2
    assert_rc=1
  fi
  if [ "$rc" -ne 0 ]; then exit "$rc"; fi
  exit "$assert_rc"
}
trap cleanup EXIT

# ---- preflights: one ordered block, before any build ----
# The deploy's invariants: the submodule's HEAD is BENCH_COMMIT and its tree is
# clean.  The venue builds its corpus in a scratch tree and never edits the
# tracked registry, so any dirt here is a real edit to the submodule.  Every git
# read checks its rc: a failing git reports the unverifiable state instead of
# reading as clean or as a valid pin.
git_rc=0
bench_head=$(git -C benchmark rev-parse HEAD) || git_rc=$?
[ "$git_rc" -eq 0 ] ||
  die "cannot verify the benchmark pin: 'git -C benchmark rev-parse HEAD' failed (rc=$git_rc)"
[ "$bench_head" = "$BENCH_COMMIT" ] ||
  die "benchmark submodule is at $bench_head but env.sh pins BENCH_COMMIT=$BENCH_COMMIT"
git_rc=0
bench_dirty=$(git -C benchmark status --short) || git_rc=$?
[ "$git_rc" -eq 0 ] ||
  die "cannot verify the benchmark submodule is clean: 'git -C benchmark status --short' failed (rc=$git_rc)"
if [ -n "$bench_dirty" ]; then
  echo "ERROR: benchmark submodule is dirty (HEAD must be $BENCH_COMMIT with a clean tree):" >&2
  printf '%s\n' "$bench_dirty" >&2
  echo "The venue builds its corpus in a scratch tree and never edits the tracked tree, so any" >&2
  echo "dirt is a real edit to the submodule.  Restore the submodule to the pinned commit with:" >&2
  echo "  git -C benchmark checkout -- ." >&2
  echo "  git -C benchmark clean -fd   (only after reviewing the listed paths)" >&2
  exit 1
fi
{ [ -f "$NEMU_BIN" ] && [ -x "$NEMU_BIN" ]; } ||
  die "NEMU_BIN=$NEMU_BIN is not an executable regular file (NEMU_DIR=$NEMU_DIR) - build it, or override NEMU_DIR/NEMU_BIN together"
nemu_head=$(git -C "$NEMU_DIR" rev-parse HEAD 2>/dev/null) ||
  die "NEMU_DIR=$NEMU_DIR is not a git checkout - override NEMU_DIR/NEMU_BIN together"
[ "$nemu_head" = "$NEMU_COMMIT" ] ||
  die "NEMU checkout $NEMU_DIR is at $nemu_head but NEMU_COMMIT pins $NEMU_COMMIT"
case "$(git -C "$NEMU_DIR" describe --always --dirty)" in
  *-dirty) echo "WARNING: NEMU checkout $NEMU_DIR is dirty; the stamp records the marker" >&2 ;;
esac
# ---- the env pins are the single source of truth for the cross knobs ----
CXX="$RISCV64_CXX"
CC="$RISCV64_CC"
ASM="$RISCV64_AS"
OBJDUMP="$RISCV64_OBJDUMP"
CROSS_COMPILE="${RISCV64_OBJDUMP%-objdump}-"
READELF="${CROSS_COMPILE}readelf"
export CXX CC ASM OBJDUMP CROSS_COMPILE READELF
export OUT CORPUS

# `make ARCH=riscv64-nemu deploy` exports ARCH=<lane> and the same assignment
# (via MAKEFLAGS) into every child, and the venue's child makes would then
# select lib/riscv64-nemu/ instead of lib/riscv64/ - the bench's own token for
# this lane is riscv64.  Clear both here.
unset ARCH MAKEFLAGS MFLAGS

# ---- the two build legs, each in its own session ----
echo "== staging the corpus"
run_leg_locked "$ROOT/scripts/common/stage_corpus.sh" riscv64-nemu "$CORPUS" ||
  die "the corpus staging failed"
echo "== building the guest image"
run_leg "$VENUE/build-image.sh" ||
  die "the venue's image build failed"

# ---- post-asserts ----
[ -f "$OUT/fw_payload.bin" ] ||
  die "image $OUT/fw_payload.bin missing after the image build"
git_rc=0
bench_dirty=$(git -C benchmark status --short) || git_rc=$?
[ "$git_rc" -eq 0 ] ||
  die "cannot verify the benchmark submodule is clean after the build: 'git -C benchmark status --short' failed (rc=$git_rc)"
if [ -n "$bench_dirty" ]; then
  echo "ERROR: benchmark submodule left dirty by the build (the corpus is staged in a scratch tree and the guest scheduler's build products are all gitignored, so any dirt is a real edit):" >&2
  printf '%s\n' "$bench_dirty" >&2
  exit 1
fi
echo "riscv64_nemu/prepare ($LANE): ok"
echo "  image: $OUT/fw_payload.bin sha256 $(sha256sum "$OUT/fw_payload.bin" | cut -d' ' -f1)"
echo "  nemu:  $NEMU_BIN sha256 $(sha256sum "$NEMU_BIN" | cut -d' ' -f1)"
