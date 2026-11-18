#!/usr/bin/env bash
set -euo pipefail
# prepare.sh LANE   (LANE = riscv64-nemu | riscv64-nemu-cfi)
#
# Deploys a riscv64-nemu lane: the absorbed NEMU venue package
# (scripts/riscv64_nemu/venue/) driven as one lane of this dispatcher.  This
# script owns the lane lock, the ordered preflights and the two supervised
# build legs; every venue mechanism (the guest image assembly, the boot
# driver, the publish-on-success manifest) stays in the venue package, and the
# corpus is staged by the same orchestrator as every other system lane
# (scripts/common/stage_corpus.sh).
#
# The CFI variant (riscv64-nemu-cfi) stages through the bench's CFI build class
# and boots the workspace NEMU-cfi interpreter (env.sh NEMU_CFI_*): its tree is
# lane-keyed (build/riscv64-nemu-cfi/platform + /corpus), so its clean covers
# it and its deploys never publish into the plain lane's trees.  Its OUT is a
# cold source root; it is seeded from the plain lane's $OUT/src when present.
# Offline precondition, per OUT: with the seed (or a prior build of that OUT)
# in place the deploy needs no network; a cold OUT without the seed needs
# network for the three pinned checkouts (and the kernel/busybox tarballs seed
# from build/downloads).
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

case "${1:-}" in
  riscv64-nemu|riscv64-nemu-cfi) ;;
  *) echo "usage: $0 riscv64-nemu|riscv64-nemu-cfi" >&2; exit 2 ;;
esac
if [ $# -ne 1 ]; then
  echo "usage: $0 riscv64-nemu|riscv64-nemu-cfi" >&2
  exit 2
fi
LANE=$1

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=../../env.sh
. ./env.sh

die() { echo "riscv64_nemu/prepare ($LANE): $*" >&2; exit 1; }

# The variant's bench class flag must accompany its lane name: an unarmed
# gcc-13 duplicate must not pass as a "cfi" deploy.
case "$LANE" in
  riscv64-nemu)     EXPECT_FLAG="" ;;
  riscv64-nemu-cfi) EXPECT_FLAG=enable_riscv64_cfi ;;
esac
[ "${ENABLE_FLAG:-}" = "$EXPECT_FLAG" ] ||
  die "ENABLE_FLAG=${ENABLE_FLAG:-<unset>} for lane $LANE, expected '${EXPECT_FLAG}' (make ARCH=riscv64-nemu enable_riscv64_cfi=yes deploy selects the variant)"

# ---- lane advisory lock ----
mkdir -p "$BUILD_DIR"
exec 9>>"$BUILD_DIR/.lane.lock"
if ! flock -n 9; then
  die "lane busy: $(cat "$BUILD_DIR/.lane.lock" 2>/dev/null || echo unknown) holds $BUILD_DIR/.lane.lock"
fi
printf '%s\n' "$LANE" > "$BUILD_DIR/.lane.lock"

VENUE="$ROOT/scripts/riscv64_nemu/venue"
OUT="$ROOT/$BUILD_DIR/$LANE/platform"
CORPUS="$ROOT/$BUILD_DIR/$LANE/corpus"
PLAIN_OUT="$ROOT/$BUILD_DIR/riscv64-nemu/platform"

# The NEMU pins: the plain lane's overridable pair (NEMU_DIR/NEMU_BIN, relative
# values resolved against the repository root), or for the variant the
# CFI-verified checkout whose binary carries the env.sh sha256 pin.  The
# variant's values are EXPORTED before each venue leg - the venue scripts
# re-source env.sh, whose `:=` defaults then preserve the exported NEMU_DIR/
# NEMU_BIN.  (NEMU_COMMIT is a plain assignment in env.sh, so an exported
# value does not survive the child's source; nothing in the venue reads it -
# the binary is identified by its sha256.)
case "$NEMU_DIR" in /*) ;; *) NEMU_DIR="$ROOT/$NEMU_DIR" ;; esac
case "$NEMU_BIN" in /*) ;; *) NEMU_BIN="$ROOT/$NEMU_BIN" ;; esac
if [ "$LANE" = riscv64-nemu ]; then
  NEMU_PIN="$NEMU_COMMIT"
else
  case "$NEMU_CFI_DIR" in /*) ;; *) NEMU_CFI_DIR="$ROOT/$NEMU_CFI_DIR" ;; esac
  case "$NEMU_CFI_BIN" in /*) ;; *) NEMU_CFI_BIN="$ROOT/$NEMU_CFI_BIN" ;; esac
  NEMU_DIR="$NEMU_CFI_DIR"
  NEMU_BIN="$NEMU_CFI_BIN"
  NEMU_PIN="$NEMU_CFI_COMMIT"
fi

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
  # The venue builds its guest scheduler inside the tracked submodule, so this
  # clean is what removes a RISC-V benchmark/run-test.  The recipe inherits the
  # deploy's MAKEFLAGS (ARCH plus the class flag), which the bench Makefile's
  # own guard refuses; drop those names here (stage_corpus.sh's discipline) and
  # let a failing clean fail the lane - the error text is the diagnosis.
  assert_rc=0
  if ! env -u MAKEFLAGS -u MFLAGS -u ARCH -u enable_riscv64_cfi make -C benchmark clean; then
    echo "ERROR: 'make -C benchmark clean' failed - the submodule may still carry generated artifacts" >&2
    assert_rc=1
  fi
  if [ -e benchmark/run-test ]; then
    echo "ERROR: generated benchmark/run-test survived the clean (a following host lane would run it under binfmt)" >&2
    assert_rc=1
  fi
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
[ "$nemu_head" = "$NEMU_PIN" ] ||
  die "NEMU checkout $NEMU_DIR is at $nemu_head but the lane pins $NEMU_PIN"
case "$(git -C "$NEMU_DIR" describe --always --dirty)" in
  *-dirty) echo "WARNING: NEMU checkout $NEMU_DIR is dirty; the stamp records the marker" >&2 ;;
esac
if [ "$LANE" != riscv64-nemu ]; then
  # The CFI binary is a hard pin: the checkout's HEAD says nothing about which
  # build the interpreter is, so an arming observation must only ever come
  # from the CFI-verified binary.
  live_sha=$(sha256sum "$NEMU_BIN" | cut -d' ' -f1)
  [ "$live_sha" = "$NEMU_CFI_BIN_SHA256" ] ||
    die "NEMU_CFI_BIN=$NEMU_BIN has sha256 $live_sha but env.sh pins NEMU_CFI_BIN_SHA256=$NEMU_CFI_BIN_SHA256 - rebuild it at NEMU_CFI_COMMIT (make -C $NEMU_CFI_DIR riscv64-xs-cfi_defconfig && make -C $NEMU_CFI_DIR) or restore the pinned binary"
  git_rc=0
  nemu_dirty=$(git -C "$NEMU_DIR" status --short) || git_rc=$?
  [ "$git_rc" -eq 0 ] ||
    die "cannot verify the CFI checkout is clean: 'git -C $NEMU_DIR status --short' failed (rc=$git_rc)"
  if [ -n "$nemu_dirty" ]; then
    echo "WARNING: NEMU checkout $NEMU_DIR is dirty; the stamp records the marker:" >&2
    printf '%s\n' "$nemu_dirty" >&2
  fi
fi
# ---- the cross knobs: one toolchain per lane (the env pins are the source) ----
# The plain lane keeps the gcc-13 pins byte-for-byte.  The CFI variant's corpus
# is staged by the GCC 16 toolchain (stage_corpus.sh, below), so its whole
# guest moves with it: the guest scheduler/libcfi cross build, the
# NEEDED/PT_INTERP glibc closure (resolved through $CXX -print-file-name - the
# gcc-13 sysroot's older libc would be the wrong runtime for a GCC 16 corpus),
# the guest-truth sys_info compiler line, and the busybox/gcpt/OpenSBI legs.
# One toolchain, one sysroot.  The values are exported before either venue leg;
# venue/build-image.sh honours them and falls back to these same pins when
# invoked directly.
if [ "$LANE" = riscv64-nemu ]; then
  CXX="$RISCV64_CXX"
  CC="$RISCV64_CC"
  ASM="$RISCV64_AS"
  OBJDUMP="$RISCV64_OBJDUMP"
else
  case "$RISCV64_GNU_PREFIX" in /*) ;; *) RISCV64_GNU_PREFIX="$ROOT/$RISCV64_GNU_PREFIX" ;; esac
  [ -x "${RISCV64_GNU_PREFIX}gcc" ] ||
    die "CFI toolchain not found: ${RISCV64_GNU_PREFIX}gcc (RISCV64_GNU_PREFIX=$RISCV64_GNU_PREFIX) - install it or override RISCV64_GNU_PREFIX"
  CXX="${RISCV64_GNU_PREFIX}g++"
  CC="${RISCV64_GNU_PREFIX}gcc"
  ASM="${RISCV64_GNU_PREFIX}as"
  OBJDUMP="${RISCV64_GNU_PREFIX}objdump"
fi
CROSS_COMPILE="${OBJDUMP%-objdump}-"
READELF="${CROSS_COMPILE}readelf"
export CXX CC ASM OBJDUMP CROSS_COMPILE READELF
export OUT CORPUS
# The variant's interpreter reaches the venue legs through the environment
# (see the pin block above): the venue re-sources env.sh and its := defaults
# keep these values.
export NEMU_DIR NEMU_BIN NEMU_COMMIT

# `make ARCH=riscv64-nemu deploy` exports ARCH=<lane> and the same assignment
# (via MAKEFLAGS) into every child, and the venue's child makes would then
# select lib/riscv64-nemu/ instead of lib/riscv64/ - the bench's own token for
# this lane is riscv64.  Clear both here.
unset ARCH MAKEFLAGS MFLAGS

# The variant's OUT is a cold source root: seed it from the plain lane's tree
# when that exists, so the three pinned checkouts are not re-fetched.  The
# tarball cache is NOT copied - the venue seeds those from build/downloads.
if [ "$LANE" != riscv64-nemu ] && [ -d "$PLAIN_OUT/src" ] && [ ! -e "$OUT/src" ]; then
  echo "== seeding $OUT/src from $PLAIN_OUT/src"
  mkdir -p "$OUT/src"
  ( cd "$PLAIN_OUT/src" && tar --exclude=./downloads -cf - . ) | tar -C "$OUT/src" -xf -
fi

# ---- the two build legs, each in its own session ----
STAGE_ARGS=("$LANE" "$CORPUS")
[ -z "$EXPECT_FLAG" ] || STAGE_ARGS+=(--enable-flag "$EXPECT_FLAG")
echo "== staging the corpus"
run_leg_locked "$ROOT/scripts/common/stage_corpus.sh" "${STAGE_ARGS[@]}" ||
  die "the corpus staging failed"
if [ -n "$EXPECT_FLAG" ]; then
  # The variant's corpus must be the GCC 16 build: the staged manifest records
  # the compiler version line, and the plain lane's gcc-13 line names a
  # different triple.
  corpus_toolchain=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("toolchain") or "")' "$CORPUS/manifest.json") ||
    die "cannot read $CORPUS/manifest.json"
  case "$corpus_toolchain" in
    *riscv64-unknown-linux-gnu*) ;;
    *) die "the staged corpus was not built by the GCC 16 toolchain pin (manifest toolchain='$corpus_toolchain') - an unarmed gcc-13 duplicate must not pass as a cfi deploy" ;;
  esac
fi
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
