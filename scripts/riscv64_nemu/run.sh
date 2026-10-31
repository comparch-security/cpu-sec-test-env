#!/usr/bin/env bash
set -euo pipefail
# run.sh LANE   (LANE = riscv64-nemu)
#
# Runs the deployed riscv64-nemu image under XiangShan NEMU and publishes the
# stamp: the absorbed venue package (scripts/riscv64_nemu/venue/run.sh) boots
# the guest image, the guest prints the result files between ===CSB-...===
# markers, and the driver carves them out of boot.log into runs/<ts>/.  This
# wrapper owns the lane lock, the preflights, the process supervision, the
# completeness gate and the stamp collection - no venue mechanism is
# re-implemented here.
#
# Publish policy (the repository's family rule): a timeout (rc 124, either the
# lane watchdog or the venue's own boot-timeout diagnosis) publishes
# NOTHING; every other failure publishes a boot.log-only evidence stamp; a
# success publishes the full stamp.  The completeness gate is evaluated
# against the venue's run dir BEFORE any result file is copied, so a stamp
# never carries results that failed the gate.
#
# Process supervision: the venue leg runs in its own session (with the
# lane-lock fd closed, `9>&-`, so no descendant can hold the lock), and a
# TERM/INT trap kills that whole session and exits non-zero, so the EXIT path
# still runs.  The driver re-groups inside the session (its inner
# `timeout "$NEMU_TIMEOUT" "$NEMU_BIN"` is a process group of its own), so
# killing the leg leader's group alone would leave the emulator alive: the
# kill sweeps every process whose session id is the leg's, then SIGKILLs the
# survivors.  The run leg's bound is the lane's own watchdog
# (LANE_RUN_TIMEOUT + 120 s), not the outer `timeout`, so the lane performs
# that kill itself in the trap and on the 124 path.  (This host's timeout -
# uutils coreutils 0.10.0 - does kill the child's process group when it
# expires; a marker probe confirmed it, and an earlier note claiming otherwise
# came from a self-matching `pgrep -f`.)  NEMU_TIMEOUT=$LANE_RUN_TIMEOUT lets
# the venue diagnose its own boot timeout first.
#
# The image carries the full tracked registry; the run boots exactly the
# deployed one (the deploy meta's image sha is re-verified below).

if [ $# -ne 1 ] || [ "$1" != riscv64-nemu ]; then
  echo "usage: $0 riscv64-nemu" >&2
  exit 2
fi
LANE=$1

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=../../env.sh
. ./env.sh

die() { echo "riscv64_nemu/run ($LANE): $*" >&2; exit 1; }

# LANE_RUN_TIMEOUT reaches this script from the environment (env.sh's default
# or the Makefile's forward) and is evaluated as a bash arithmetic expression
# by the watchdog; validate it before any arithmetic.
case "$LANE_RUN_TIMEOUT" in
  ''|*[!0-9]*) die "LANE_RUN_TIMEOUT='$LANE_RUN_TIMEOUT' is not a positive integer" ;;
  0) die "LANE_RUN_TIMEOUT=0 is not a positive integer" ;;
esac

# ---- lane advisory lock ----
mkdir -p "$BUILD_DIR"
exec 9>>"$BUILD_DIR/.lane.lock"
if ! flock -n 9; then
  die "lane busy: $(cat "$BUILD_DIR/.lane.lock" 2>/dev/null || echo unknown) holds $BUILD_DIR/.lane.lock"
fi
printf '%s\n' "$LANE" > "$BUILD_DIR/.lane.lock"

VENUE="$ROOT/scripts/riscv64_nemu/venue"
OUT="$ROOT/$BUILD_DIR/riscv64-nemu/platform"
LANE_DIR="$ROOT/$BUILD_DIR/riscv64-nemu"
LOG="$LANE_DIR/run.log"

# NEMU_DIR/NEMU_BIN are one overridable pair; relative values resolve against
# the repository root (env.sh keeps its default relative on purpose).
case "$NEMU_DIR" in /*) ;; *) NEMU_DIR="$ROOT/$NEMU_DIR" ;; esac
case "$NEMU_BIN" in /*) ;; *) NEMU_BIN="$ROOT/$NEMU_BIN" ;; esac

# ---- preflights: before the traps, so a failed preflight publishes nothing ----
# The deploy's invariants: the submodule's HEAD is BENCH_COMMIT and its tree is
# clean (the venue builds its corpus in a scratch tree and never edits the
# tracked tree, so any dirt is a real edit).  Every git read checks its rc: a
# failing git reports the unverifiable state instead of reading as a valid pin
# or a clean tree.
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
  echo "dirt is a real edit to the submodule.  Restore it with:" >&2
  echo "  git -C benchmark checkout -- ." >&2
  exit 1
fi
{ [ -f "$NEMU_BIN" ] && [ -x "$NEMU_BIN" ]; } ||
  die "NEMU_BIN=$NEMU_BIN is not an executable regular file (NEMU_DIR=$NEMU_DIR) - build it, or override NEMU_DIR/NEMU_BIN together"
nemu_head=$(git -C "$NEMU_DIR" rev-parse HEAD 2>/dev/null) ||
  die "NEMU_DIR=$NEMU_DIR is not a git checkout - override NEMU_DIR/NEMU_BIN together"
[ "$nemu_head" = "$NEMU_COMMIT" ] ||
  die "NEMU checkout $NEMU_DIR is at $nemu_head but NEMU_COMMIT pins $NEMU_COMMIT"

[ -f "$OUT/fw_payload.bin" ] ||
  die "no image at $OUT/fw_payload.bin - run make ARCH=riscv64-nemu deploy first"
# The deploy writes fw_payload.bin before its own meta.json, so a deploy that
# died between the two leaves an image whose provenance is absent or stale;
# booting it would publish a full stamp with contradictory evidence.
[ -f "$OUT/meta.json" ] ||
  die "no deploy meta at $OUT/meta.json - the deploy did not finish; run make ARCH=riscv64-nemu deploy first"
live_image_sha=$(sha256sum "$OUT/fw_payload.bin" | cut -d' ' -f1)
deploy_image_sha=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["fw_payload_bin"]["sha256"] or "")' "$OUT/meta.json") ||
  die "cannot read the deploy meta $OUT/meta.json - re-run make ARCH=riscv64-nemu deploy"
[ "$live_image_sha" = "$deploy_image_sha" ] ||
  die "the image at $OUT/fw_payload.bin (sha256 $live_image_sha) does not match its deploy meta ($OUT/meta.json records ${deploy_image_sha:-nothing}) - re-run make ARCH=riscv64-nemu deploy"
export OUT

mkdir -p "$LANE_DIR"
RUNS="$OUT/runs"
SNAP="$LANE_DIR/runs.snapshot"
: > "$SNAP"
[ -d "$RUNS" ] && find "$RUNS" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort > "$SNAP"
RUN_DIR=""
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
DEST="$RESULTS_DIR/riscv64-nemu/$STAMP"

new_run_dirs() { # names of the run dirs created since the snapshot
  local d name
  [ -d "$RUNS" ] || return 0
  for d in "$RUNS"/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    grep -qxF -- "$name" "$SNAP" || printf '%s\n' "$name"
  done
  return 0
}

# Best-effort resolution for the failure paths (the trap runs before the leg's
# own resolution): exactly one new run dir selects it; none or several leave
# RUN_DIR empty and the publish falls back to the lane's own $LOG.
resolve_run_dir() {
  local -a names=()
  mapfile -t names < <(new_run_dirs)
  if [ "${#names[@]}" -eq 1 ]; then RUN_DIR="$RUNS/${names[0]}"; fi
  return 0
}

# ---- the completeness gate: against the venue's run dir, before any copy ----
# The reference is the registry the image carries - the tracked bench registry,
# copied verbatim at deploy time (stage_corpus.sh verified it byte-identical).
completeness_gate() { # results.json
  python3 - "$1" "$OUT/bench/configure.json" <<'PY'
import json, sys
res, reg = (json.load(open(p)) for p in sys.argv[1:3])
missing = sorted(set(reg) - set(res))
extra = sorted(set(res) - set(reg))
if missing or extra:
    sys.exit("results.json record set != the deployed registry "
             "(missing=%d e.g. %s; extra=%d e.g. %s)"
             % (len(missing), ", ".join(map(repr, missing[:3])),
                len(extra), ", ".join(map(repr, extra[:3]))))
print("riscv64_nemu/run: results.json carries all %d deployed records" % len(res))
PY
}

# ---- collect + clean + assert, on every exit path (the publish policy) ----
cleanup() {
  rc=$?
  set +e
  if [ "$rc" -eq 124 ]; then
    echo "riscv64-nemu lane ($LANE) aborted on timeout (124): publishing nothing" >&2
  else
    mkdir -p "$DEST"
    # Console evidence is mandatory on every non-timeout path: the run dir's
    # boot.log when one was resolved, else the lane's own log (the venue's
    # stdout/stderr, created before the leg launches).
    if [ -n "$RUN_DIR" ] && [ -f "$RUN_DIR/boot.log" ]; then
      cp -f "$RUN_DIR/boot.log" "$DEST/"
    elif [ -f "$LOG" ]; then
      cp -f "$LOG" "$DEST/boot.log"
    fi
    if [ "$rc" -eq 0 ]; then
      for f in results.json results.dat variables.json; do
        [ -f "$RUN_DIR/$f" ] && cp -f "$RUN_DIR/$f" "$DEST/"
      done
      cp -f "$RUN_DIR/meta.json" "$DEST/"
      cp -f "$OUT/meta.json" "$DEST/meta.deploy.json"
    fi
    ENABLE_FLAG="" RUN_STATUS="$rc" bash scripts/common/version_stamp.sh riscv64-nemu "$DEST/versions.txt"
    nemu_bin_path=$(realpath "$NEMU_BIN" 2>/dev/null || printf '%s\n' "$NEMU_BIN")
    {
      echo "# nemu"
      echo "nemu-bin: $nemu_bin_path"
      echo "nemu-commit: $(git -C "$NEMU_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
      echo "nemu-describe: $(git -C "$NEMU_DIR" describe --always --dirty 2>/dev/null || echo unknown)"
      echo "nemu-sha256: $(sha256sum "$NEMU_BIN" 2>/dev/null | cut -d' ' -f1 || echo unknown)"
    } >> "$DEST/versions.txt"
    # Publication is the one irreversible act: a failed copy or stamp write
    # must not leave a silently incomplete "full" stamp behind an exit 0.
    if [ "$rc" -eq 0 ]; then
      missing_stamp=()
      for f in results.json results.dat boot.log meta.json meta.deploy.json versions.txt; do
        [ -f "$DEST/$f" ] || missing_stamp+=("$f")
      done
      if [ "${#missing_stamp[@]}" -gt 0 ]; then
        echo "ERROR: the stamp $DEST is missing mandatory file(s): ${missing_stamp[*]}" >&2
        rc=1
      fi
    fi
    echo "collected riscv64-nemu lane artifacts into $DEST"
  fi
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

# Kill the venue leg's whole session.  The driver re-groups inside it (its
# inner `timeout NEMU`), so the leg leader's process group is not enough: TERM
# the group, TERM the rest of the session, give it a moment, then SIGKILL the
# survivors.  The children run with fd 9 closed, so no survivor can hold
# build/.lane.lock.
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
  # The venue driver creates its run dir before booting; resolve it here so the
  # EXIT publish can carry its boot.log (falling back to $LOG otherwise).
  resolve_run_dir
  exit 130
}
trap term_leg TERM INT
trap cleanup EXIT

echo "== booting the deployed image under $NEMU_BIN (NEMU_TIMEOUT=${LANE_RUN_TIMEOUT}s, watchdog $((LANE_RUN_TIMEOUT + 120))s)"
echo "   venue log: $LOG"
export NEMU_TIMEOUT="$LANE_RUN_TIMEOUT"
: > "$LOG"
setsid timeout "$((LANE_RUN_TIMEOUT + 120))" bash "$VENUE/run.sh" >"$LOG" 2>&1 9>&- &
LEG_PID=$!
leg_rc=0
wait "$LEG_PID" || leg_rc=$?

# A timeout is the one outcome that publishes nothing: the lane watchdog
# (124) or the venue's own boot-timeout diagnosis.  The text match mirrors
# scripts/riscv64_nemu/venue/run.sh, whose inner timeout fires first
# (NEMU_TIMEOUT is forwarded above) and prints "NEMU timed out after <n> s";
# that message is the venue package's own, so a reword there must re-verify
# this match - a changed message would silently turn a timeout into a
# boot.log-only evidence stamp.  LEG_PID is kept through these checks so the
# whole leg session is killed here: a timed-out venue leg must leave no
# descendant writing the venue tree.
if [ "$leg_rc" -eq 124 ] || grep -q "NEMU timed out" "$LOG"; then
  kill_leg
  LEG_PID=""
  exit 124
fi
LEG_PID=""

# The venue driver creates its run dir before booting; the leg must leave
# exactly one new one under runs/.
mapfile -t new_runs < <(new_run_dirs)
if [ "$leg_rc" -ne 0 ]; then
  if [ "${#new_runs[@]}" -eq 1 ]; then RUN_DIR="$RUNS/${new_runs[0]}"; fi
  die "the venue run.sh exited $leg_rc (see $LOG); new run dirs under $RUNS: ${#new_runs[@]} (${new_runs[*]:-none})"
fi
[ "${#new_runs[@]}" -eq 1 ] ||
  die "expected exactly one new run dir under $RUNS, found ${#new_runs[@]} (${new_runs[*]:-none})"
RUN_DIR="$RUNS/${new_runs[0]}"

# ---- the recorded binary must be the executed one ----
live_sha=$(sha256sum "$NEMU_BIN" | cut -d' ' -f1)
recorded_sha=$(python3 -c 'import json,sys; print((json.load(open(sys.argv[1])).get("nemu_bin") or {}).get("sha256") or "")' "$RUN_DIR/meta.json") ||
  die "cannot read the run meta $RUN_DIR/meta.json - the venue run did not finish its meta write"
[ "$live_sha" = "$recorded_sha" ] ||
  die "NEMU binary changed across the run: live sha256 $live_sha, run meta records $recorded_sha ($NEMU_BIN)"
# ... and the deployed binary: a rebuild between deploy and run is caught here,
# not only the same-run value above.
deploy_nemu_sha=$(python3 -c 'import json,sys; print((json.load(open(sys.argv[1])).get("nemu_bin") or {}).get("sha256") or "")' "$OUT/meta.json") ||
  die "cannot read the deploy meta $OUT/meta.json - re-run make ARCH=riscv64-nemu deploy"
[ "$live_sha" = "$deploy_nemu_sha" ] ||
  die "the NEMU binary $NEMU_BIN (sha256 $live_sha) is not the one the deploy recorded (${deploy_nemu_sha:-nothing} in $OUT/meta.json) - restore it, or rebuild and re-deploy"

# The run meta's image sha must be the deploy meta's: a deploy that died
# between the image write and its meta write would otherwise reach the full
# stamp as contradictory provenance.  A mismatch takes the evidence-stamp path
# with a non-zero exit.
run_image_sha=$(python3 -c 'import json,sys; print((json.load(open(sys.argv[1])).get("image") or {}).get("sha256") or "")' "$RUN_DIR/meta.json") ||
  die "cannot read the run meta $RUN_DIR/meta.json - the venue run did not finish its meta write"
[ "$run_image_sha" = "$deploy_image_sha" ] ||
  die "the run booted image sha256 $run_image_sha but meta.deploy.json records $deploy_image_sha - refusing the full stamp"

# ---- completeness gate, then the EXIT trap publishes ----
completeness_gate "$RUN_DIR/results.json"

echo "riscv64_nemu/run ($LANE): ok"
