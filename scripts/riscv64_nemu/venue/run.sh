#!/usr/bin/env bash
#
# The riscv64-nemu lane's boot driver (absorbed from the bench's
# platform/riscv64-nemu-linux at f9e4ba7, which the portable-core pin
# cbe3bf9 removed): boot the guest image under XiangShan NEMU and extract the
# guest's results.
#
#   scripts/riscv64_nemu/venue/run.sh
#
# Booting: `timeout $NEMU_TIMEOUT $NEMU_BIN -b $OUT/fw_payload.bin`; the guest
# console (including the ===CSB-...=== result markers printed by
# guest/bench.sh) lands in runs/<ts>/boot.log, and the three result files are
# carved out of it between the markers.  The guest hands its exit code to NEMU
# through nemu-trap; NEMU reports HIT GOOD TRAP and exits 0 for code 0 and HIT
# BAD TRAP (exit 1) for anything else -- both are asserted here.  A timeout
# (rc 124) is diagnosed before any marker is parsed and publishes nothing;
# scripts/riscv64_nemu/run.sh greps the literal "NEMU timed out" from this
# script's stdout to classify that case, so the message text is load-bearing.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
# shellcheck source=../../../env.sh
. "$ROOT/env.sh"

OUT="${OUT:?OUT must be exported by the lane run script}"
DEST="$OUT"
IMAGE="$DEST/fw_payload.bin"
BENCH_DIR="$ROOT/benchmark"
NEMU_TIMEOUT="${NEMU_TIMEOUT:-$LANE_RUN_TIMEOUT}"
TS="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$DEST/runs/$TS"
[ -e "$RUN_DIR" ] && RUN_DIR="$RUN_DIR-$$"   # two runs in the same second must not share a directory

# NEMU_DIR/NEMU_BIN are one overridable pair; a relative value resolves
# against the repository root (env.sh keeps its default relative on purpose).
case "$NEMU_BIN" in /*) ;; *) NEMU_BIN="$ROOT/$NEMU_BIN" ;; esac

[ -x "$NEMU_BIN" ] || { echo "ERROR: NEMU binary not found/executable: $NEMU_BIN" >&2; exit 1; }
[ -f "$IMAGE" ] || { echo "ERROR: no image at $IMAGE; run the lane's deploy first" >&2; exit 1; }
mkdir -p "$RUN_DIR"

echo "== booting $IMAGE under $NEMU_BIN (timeout ${NEMU_TIMEOUT}s)"
set +e
timeout "$NEMU_TIMEOUT" "$NEMU_BIN" -b "$IMAGE" > "$RUN_DIR/boot.log" 2>&1
nemu_rc=$?
set -e
echo "nemu exit: $nemu_rc"

python3 - "$RUN_DIR" "$DEST" "$NEMU_BIN" "$BENCH_DIR" "$nemu_rc" "$NEMU_TIMEOUT" <<'PY'
import hashlib, json, os, re, subprocess, sys

run_dir, dest, nemu_bin, bench_dir, nemu_rc, timeout_s = sys.argv[1:7]
nemu_rc = int(nemu_rc)
log = open(os.path.join(run_dir, "boot.log"), encoding="utf-8", errors="replace").read()

def fail(msg):
    sys.stderr.write("ERROR: " + msg + "\n")
    sys.exit(1)

def block(tag):
    m = re.search(r"===CSB-%s-BEGIN===\r?\n(.*?)\r?\n===CSB-%s-END===" % (tag, tag), log, re.S)
    return m.group(1).strip() if m else None

good_trap = "HIT GOOD TRAP" in log
bad_trap = "HIT BAD TRAP" in log

# A timeout is the one failure mode that leaves no guest evidence at all -- the
# guest is still running and no marker has been printed -- so it is diagnosed
# before the markers are parsed, and nothing is published.
if nemu_rc == 124:
    fail("NEMU timed out after %s s; nothing is published (boot.log kept)" % timeout_s)
if nemu_rc not in (0, 1):
    fail("NEMU exited %d (neither a good nor a bad trap); nothing is published" % nemu_rc)

m = re.search(r"===CSB-EXIT-CODE===(\d+)===", log)
guest_rc = int(m.group(1)) if m else None
if guest_rc is None:
    fail("no ===CSB-EXIT-CODE=== marker; the guest did not finish")

# The guest's exit code is the scheduler's, and every non-zero scheduler exit is a
# hard error -- an unreadable configure.json, a dependency ring, a failed spawn,
# or the corpus-missing fail-fast.  It therefore fails the run rather than being
# recorded as an outcome; the trap agreement below is only the diagnostic.
if guest_rc != 0:
    fail("the in-guest scheduler exited %d (NEMU rc=%d, bad_trap=%s); nothing is published"
         % (guest_rc, nemu_rc, bad_trap))
if not (nemu_rc == 0 and good_trap):
    fail("guest exited 0 but NEMU rc=%d good_trap=%s" % (nemu_rc, good_trap))

results = block("RESULTS-JSON")
if results is None:
    fail("results.json markers not found in boot.log")
records = json.loads(results)  # loud failure on a corrupted block
# The registry the guest actually read is the one the image carries: the
# tracked bench registry, copied verbatim at deploy time.
total = len(json.load(open(os.path.join(dest, "bench/configure.json"))))
if len(records) != total:
    fail("the in-guest run did not complete: results.json holds %d of %d records"
         % (len(records), total))

# Only now, with the run proven complete, are the result files published.
with open(os.path.join(run_dir, "results.json"), "w") as f:
    f.write(results + "\n")

variables = block("VARIABLES-JSON")
if variables is not None:
    json.loads(variables)
    with open(os.path.join(run_dir, "variables.json"), "w") as f:
        f.write(variables + "\n")

results_dat = block("RESULTS-DAT")
if results_dat is not None:
    with open(os.path.join(run_dir, "results.dat"), "w") as f:
        f.write(results_dat + "\n")

def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()

meta = {
    "platform": "riscv64-nemu (absorbed venue package)",
    "bench_commit": subprocess.run(["git", "-C", bench_dir, "rev-parse", "HEAD"],
                                   capture_output=True, text=True).stdout.strip(),
    # `-dirty` means the venue ran against an uncommitted bench tree: the commit
    # alone would not reproduce the scheduler that produced these results.
    "bench_tree": subprocess.run(["git", "-C", bench_dir, "describe", "--always", "--dirty"],
                                 capture_output=True, text=True).stdout.strip(),
    "image": {"path": os.path.join(dest, "fw_payload.bin"), "sha256": sha(os.path.join(dest, "fw_payload.bin"))},
    "nemu_bin": {"path": nemu_bin, "sha256": sha(nemu_bin) if os.path.exists(nemu_bin) else None},
    "nemu_exit_code": nemu_rc,
    "guest_exit_code": guest_rc,
    "hit_good_trap": good_trap,
    "records_reported": len(records),
    "records_expected": total,
}
with open(os.path.join(run_dir, "meta.json"), "w") as f:
    json.dump(meta, f, indent=2, sort_keys=True)
    f.write("\n")
print("records in results.json: %d/%d" % (len(records), total))
print("run dir: %s" % run_dir)
PY

echo "== done: $RUN_DIR"
