#!/usr/bin/env bash
set -euo pipefail
# build_corpus.sh LANE OUT_DIR
#
# Builds the full cross-target corpus for a system lane and stages it under
# OUT_DIR:
#   OUT_DIR/configure.json  derived registry (from derive_registry.py)
#   OUT_DIR/manifest.json   finalized manifest (sha256/mode/status per artifact)
#   OUT_DIR/test/<unit>     one binary per build unit (mode 0755)
#   OUT_DIR/test/<side>     the derived run-time side files
#
# Each unit is built by issuing the scheduler's own command against the
# ORIGINAL program name - `make -B test/<prog> <K=V>... disable_... ARCH=...
# CXX=... ASM=... OBJDUMP=...` from the bench root with the objdump shim first
# on PATH - then snapshotted to the unit's file name.  Any build failure
# outside the manifest's expected_failures aborts non-zero naming the unit.
# The tracked benchmark/configure.json is never written.

if [ $# -ne 2 ]; then
  echo "usage: $0 LANE OUT_DIR" >&2
  exit 2
fi
LANE=$1
OUT_DIR=$2

case "$LANE" in
  riscv64) ;;
  *)
    echo "usage: $0 LANE OUT_DIR  (only the riscv64 corpus is provisioned; got '$LANE')" >&2
    exit 2
    ;;
esac

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
# shellcheck source=../../env.sh
. "$ROOT/env.sh"

case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$PWD/$OUT_DIR" ;;
esac
case "$OUT_DIR" in
  /|"$ROOT"|"$ROOT"/)
    echo "build_corpus: refusing to use '$OUT_DIR' as OUT_DIR" >&2
    exit 2
    ;;
  "$ROOT"/benchmark/*)
    echo "build_corpus: OUT_DIR must not live inside the benchmark submodule" >&2
    exit 2
    ;;
esac

ARCH="$LANE"
CXX=$RISCV64_CXX
ASM=$RISCV64_AS
OBJDUMP=$RISCV64_OBJDUMP
export BENCH_COMMIT ARCH CXX ASM OBJDUMP

SHIM_DIR="$ROOT/$BUILD_DIR/$LANE/shim"
bash "$ROOT/scripts/common/shim.sh" riscv64-linux-gnu "$SHIM_DIR"
export PATH="$SHIM_DIR:$PATH"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

python3 "$ROOT/scripts/common/derive_registry.py" \
  --lane "$LANE" --registry "$ROOT/benchmark/configure.json" --out-dir "$OUT_DIR"

MANIFEST="$OUT_DIR/manifest.json"
DERIVED="$OUT_DIR/configure.json"
LOG="$OUT_DIR/corpus-build.log"

# Read per-unit make arguments and the original program name out of the
# derived registry + manifest, one TSV line per unit:
#   file<TAB>program<TAB>K=V K=V ...
# The K=V pairs come from the records' STRUCTURED conf-macro (never from the
# canonical comma-joined string - values themselves may contain commas).
mapfile -t UNIT_ROWS < <(python3 - "$OUT_DIR" <<'PY'
import json, sys
out = sys.argv[1]
derived = json.load(open(out + "/configure.json"))
manifest = json.load(open(out + "/manifest.json"))
recs_by_prog = {}
for rec, r in derived.items():
    recs_by_prog.setdefault(r.get("program", rec), []).append(r)
for u in manifest["units"]:
    unit = u["file"][len("test/"):]
    recs = recs_by_prog.get(unit, [])
    if not recs:
        sys.exit("build_corpus: no derived record resolves to unit %s" % unit)
    cm = recs[0].get("conf-macro") or {}
    if cm:
        m0 = next(iter(cm.values()))
        kvs = " ".join("%s=%s" % (k, m0[k]) for k in sorted(m0))
    else:
        kvs = ""
    print("%s\t%s\t%s" % (u["file"], u["program"], kvs))
PY
)
[ ${#UNIT_ROWS[@]} -gt 0 ] || { echo "build_corpus: no units enumerated" >&2; exit 1; }

expected_failures=$(python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["expected_failures"]))' "$MANIFEST")

cd "$ROOT/benchmark"
# The bench's clean removes test/ and the per-unit rules never recreate it
# (without this, every unit build fails writing test/<prog>.o).
mkdir -p test

staged=0
failed_units=()
for row in "${UNIT_ROWS[@]}"; do
  IFS=$'\t' read -r file prog kvs <<<"$row"
  read -r -a make_args <<<"$kvs"
  echo "== $prog ($file)" | tee -a "$LOG"
  if make -B "test/$prog" "${make_args[@]+"${make_args[@]}"}" \
       disable_independent_assembly=yes \
       ARCH="$ARCH" CXX="$CXX" ASM="$ASM" OBJDUMP="$OBJDUMP" \
       >>"$LOG" 2>&1; then
    mkdir -p "$OUT_DIR/$(dirname "$file")"
    install -m 0755 "test/$prog" "$OUT_DIR/$file"
    staged=$((staged + 1))
  else
    is_expected=0
    for ef in $expected_failures; do
      if [ "$prog" = "$ef" ]; then is_expected=1; fi
    done
    if [ "$is_expected" = 1 ]; then
      echo "== expected build failure (no units entry): $prog" | tee -a "$LOG"
      continue
    fi
    failed_units+=("$file")
    python3 - "$MANIFEST" "$file" <<'PY'
import json, sys
manifest_path, bad = sys.argv[1], sys.argv[2]
with open(manifest_path) as fh:
    manifest = json.load(fh)
for u in manifest["units"]:
    if u["file"] == bad:
        u["file"] = None
        u["status"] = "build-failed"
with open(manifest_path, "w") as fh:
    json.dump(manifest, fh, indent=2)
    fh.write("\n")
PY
    echo "build_corpus: unit $file (program $prog) failed to build - see $LOG" >&2
  fi
done

if [ ${#failed_units[@]} -gt 0 ]; then
  echo "build_corpus: aborting, ${#failed_units[@]} unit(s) failed outside expected_failures: ${failed_units[*]}" >&2
  exit 1
fi

# Stage the derived side files (produced as byproducts of the unit builds).
cd "$ROOT/benchmark"
while IFS= read -r side; do
  [ -n "$side" ] || continue
  if [ ! -f "$side" ]; then
    echo "build_corpus: derived side file $side was not produced by any unit build" >&2
    exit 1
  fi
  mkdir -p "$OUT_DIR/$(dirname "$side")"
  install -m 0755 "$side" "$OUT_DIR/$side"
done < <(python3 -c 'import json,sys; [print(s["file"]) for s in json.load(open(sys.argv[1]))["side_files"]]' "$MANIFEST")

# Finalize the manifest in place: hash and record every staged artifact.
python3 - "$OUT_DIR" <<'PY'
import hashlib, json, os, stat, sys
out = sys.argv[1]
manifest_path = os.path.join(out, "manifest.json")
with open(manifest_path) as fh:
    manifest = json.load(fh)

def finalize(entry, rel, mode="755"):
    path = os.path.join(out, rel)
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    entry["sha256"] = h.hexdigest()
    entry["mode"] = mode
    entry["status"] = "built"

for u in manifest["units"]:
    if u["status"] != "pending":
        continue
    if u["file"] is None or not os.path.isfile(os.path.join(out, u["file"])):
        sys.exit("build_corpus: manifest unit %r has no staged file" % u["file"])
    finalize(u, u["file"])

for s in manifest["side_files"]:
    if s["status"] != "pending":
        continue
    path = os.path.join(out, s["file"])
    if not os.path.isfile(path):
        sys.exit("build_corpus: side file %s not staged" % s["file"])
    actual = "%o" % (stat.S_IMODE(os.stat(path).st_mode))
    finalize(s, s["file"], mode=actual)

with open(manifest_path, "w") as fh:
    json.dump(manifest, fh, indent=2)
    fh.write("\n")

n_units = len(manifest["units"])
n_side = len(manifest["side_files"])
print("build_corpus: manifest finalized (%d staged units, %d side files)" % (n_units, n_side))
PY
