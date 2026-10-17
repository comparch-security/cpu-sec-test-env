#!/usr/bin/env bash
set -euo pipefail
# build_corpus.sh LANE OUT_DIR [--bring-up] [--env-lane ENV_LANE] [--enable-flag NAME]
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
#
# Lanes (bench ARCH tokens): riscv64 | cheri_riscv64 | aarch64.  The two CHERI
# lanes are system-mode like riscv64 and share this builder: cheri_riscv64 uses
# the CHERI-LLVM SDK clang++ with the purecap sysroot, and the Morello lane uses
# the aarch64 token + --enable-flag enable_aarch64_morello (the bench Makefile
# forces ARCH := aarch64 under that flag) with the Morello SDK.  Every CHERI
# cross compile carries --sysroot=<that lane's CHERI_SYSROOT_* env.sh pin> -
# without it #include <stdio.h> resolves against the host include root.
#
# --bring-up: the tolerant mode for the first CHERI bring-up run.  The three
#   abort paths below (a unit failure, a missing derived side file, the finalize
#   step) each record the offending artifact as a non-built manifest entry and
#   continue instead of exiting - the CHERI lanes' predicted failure class is
#   exactly the missing-side-file case (test/acc-read-func-func-opcode.tmp is a
#   byproduct of the acc-read-func.gen unit, whose extraction is expected to
#   fail there).  Strict mode - the default, and what the final acceptance run
#   uses - still exits non-zero.
#
# --env-lane: env lane name forwarded to derive_registry.py for its skip table
#   (defaults to LANE).  --enable-flag: the bench enable flag name to pass to
#   every make invocation (empty for the plain riscv64 lane).

di() { echo "build_corpus: $*" >&2; }

LANE=""
OUT_DIR=""
BRING_UP=0
ENV_LANE=""
ENABLE_FLAG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bring-up)    BRING_UP=1 ;;
    --env-lane)    ENV_LANE=${2:-}; shift ;;
    --enable-flag) ENABLE_FLAG=${2:-}; shift ;;
    -*)            di "unknown option '$1'"; exit 2 ;;
    *)
      if [ -z "$LANE" ]; then LANE=$1
      elif [ -z "$OUT_DIR" ]; then OUT_DIR=$1
      else di "too many positional arguments"; exit 2
      fi ;;
  esac
  shift
done
if [ -z "$LANE" ] || [ -z "$OUT_DIR" ]; then
  echo "usage: $0 LANE OUT_DIR [--bring-up] [--env-lane ENV_LANE] [--enable-flag NAME]" >&2
  exit 2
fi
[ -n "$ENV_LANE" ] || ENV_LANE=$LANE

case "$LANE" in
  riscv64|cheri_riscv64|aarch64) ;;
  *)
    di "unknown lane '$LANE' (expected riscv64 | cheri_riscv64 | aarch64)"
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
    di "refusing to use '$OUT_DIR' as OUT_DIR"
    exit 2
    ;;
  "$ROOT"/benchmark/*)
    di "OUT_DIR must not live inside the benchmark submodule"
    exit 2
    ;;
esac

# ---- per-lane toolchain (CXX/ASM/OBJDUMP + objdump-shim prefix) ----
CHERI_BROOT="$ROOT/$BUILD_DIR/cheri"
# Emit the clang++ path AS-IS: clang picks its driver mode (C vs C++) from
# argv[0], and the SDK's clang++ is a symlink to clang-17.  Resolving that
# symlink makes the compiler run in C mode and silently skip the C++ runtime
# at link.  The verifier enforces this -- do not "simplify" it back.
find_sdk_clang() {  # bindir
  local bindir=$1 c
  for c in "$bindir/clang++" "$bindir"/*-clang++; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

case "$LANE" in
  riscv64)
    CXX=$RISCV64_CXX; ASM=$RISCV64_AS; OBJDUMP=$RISCV64_OBJDUMP
    SHIM_PREFIX="${RISCV64_OBJDUMP%-objdump}"
    ;;
  cheri_riscv64)
    CLANG=$(find_sdk_clang "$CHERI_BROOT/output/sdk/bin") ||
      { di "CHERI-LLVM clang++ not found under $CHERI_BROOT/output/sdk/bin - run the image leg first"; exit 1; }
    SYSROOT="$ROOT/$CHERI_SYSROOT_RISCV64"
    [ -d "$SYSROOT" ] || { di "purecap sysroot pin $SYSROOT absent"; exit 1; }
    # --target is mandatory here: the bench Makefile's enable_riscv64_cheri adds
    # the -march/-mabi but not the triple, and the SDK clang defaults to the
    # host.  OBJDUMP stays the host riscv64-linux-gnu-objdump (the plan's
    # objdump-shim boundary: GNU format reads FreeBSD ELF).
    CXX="$CLANG --target=riscv64-unknown-freebsd --sysroot=$SYSROOT"
    ASM="$CLANG"
    OBJDUMP=$RISCV64_OBJDUMP
    SHIM_PREFIX="${RISCV64_OBJDUMP%-objdump}"
    ;;
  aarch64)
    [ "$ENABLE_FLAG" = enable_aarch64_morello ] ||
      { di "the aarch64 corpus is the Morello lane; pass --enable-flag enable_aarch64_morello"; exit 2; }
    CLANG=$(find_sdk_clang "$CHERI_BROOT/output/morello-sdk/bin") ||
      { di "Morello-LLVM clang++ not found under $CHERI_BROOT/output/morello-sdk/bin - run the image leg first"; exit 1; }
    SYSROOT="$ROOT/$CHERI_SYSROOT_MORELLO"
    [ -d "$SYSROOT" ] || { di "purecap sysroot pin $SYSROOT absent"; exit 1; }
    # --target is mandatory here too: the bench enable flag adds the Morello
    # -march/-mabi but NOT the triple (verified 2026-10-17: without it the SDK
    # clang++ defaults to x86_64-unknown-linux-gnu and rejects -mabi=).
    CXX="$CLANG --target=aarch64-unknown-freebsd --sysroot=$SYSROOT"
    ASM="$CLANG"
    OBJDUMP=$AARCH64_OBJDUMP
    SHIM_PREFIX="${AARCH64_OBJDUMP%-objdump}"
    ;;
esac

ARCH="$LANE"
export BENCH_COMMIT ARCH CXX ASM OBJDUMP

SHIM_DIR="$ROOT/$BUILD_DIR/$LANE/shim"
bash "$ROOT/scripts/common/shim.sh" "$SHIM_PREFIX" "$SHIM_DIR"
export PATH="$SHIM_DIR:$PATH"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

python3 "$ROOT/scripts/common/derive_registry.py" \
  --lane "$LANE" --env-lane "$ENV_LANE" \
  --registry "$ROOT/benchmark/configure.json" --out-dir "$OUT_DIR"

MANIFEST="$OUT_DIR/manifest.json"
DERIVED="$OUT_DIR/configure.json"
LOG="$OUT_DIR/corpus-build.log"

# The bench enable flag (NAME=yes) rides every unit make when set.
ENABLE_ARG=()
[ -n "$ENABLE_FLAG" ] && ENABLE_ARG+=("$ENABLE_FLAG=yes")

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
[ ${#UNIT_ROWS[@]} -gt 0 ] || { di "no units enumerated"; exit 1; }

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
       "${ENABLE_ARG[@]+"${ENABLE_ARG[@]}"}" \
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

# Abort path 1 (the unit-failure exit): strict mode aborts here; --bring-up
# records the failures (already marked build-failed) and carries on.
if [ ${#failed_units[@]} -gt 0 ]; then
  if [ "$BRING_UP" = 1 ]; then
    echo "build_corpus: --bring-up: ${#failed_units[@]} unit(s) failed outside expected_failures, recorded build-failed: ${failed_units[*]}" >&2
  else
    di "aborting, ${#failed_units[@]} unit(s) failed outside expected_failures: ${failed_units[*]}"
    exit 1
  fi
fi

# Stage the derived side files (produced as byproducts of the unit builds).
cd "$ROOT/benchmark"
while IFS= read -r side; do
  [ -n "$side" ] || continue
  if [ ! -f "$side" ]; then
    # Abort path 2 (the side-file staging exit): --bring-up records the absent
    # side file as a non-built manifest entry and skips its staging; strict mode
    # still exits 1 (the final acceptance path uses strict mode).
    if [ "$BRING_UP" = 1 ]; then
      python3 - "$MANIFEST" "$side" <<'PY'
import json, sys
manifest_path, missing = sys.argv[1], sys.argv[2]
with open(manifest_path) as fh:
    manifest = json.load(fh)
for s in manifest["side_files"]:
    if s["file"] == missing:
        s["status"] = "not-built"
with open(manifest_path, "w") as fh:
    json.dump(manifest, fh, indent=2)
    fh.write("\n")
PY
      echo "build_corpus: --bring-up: derived side file $side not produced; recorded not-built" >&2
      continue
    fi
    di "derived side file $side was not produced by any unit build"
    exit 1
  fi
  mkdir -p "$OUT_DIR/$(dirname "$side")"
  install -m 0755 "$side" "$OUT_DIR/$side"
done < <(python3 -c 'import json,sys; [print(s["file"]) for s in json.load(open(sys.argv[1]))["side_files"]]' "$MANIFEST")

# Abort path 3 (the finalize step): --bring-up marks an un-staged unit or side
# file not-built instead of sys.exit-ing; strict mode still aborts.  Finalize
# the manifest in place: hash and record every staged artifact.
python3 - "$OUT_DIR" "$BRING_UP" <<'PY'
import hashlib, json, os, stat, sys
out, bring_up = sys.argv[1], sys.argv[2] == "1"
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

def not_built(entry):
    entry["status"] = "not-built"
    entry.pop("sha256", None)

for u in manifest["units"]:
    if u["status"] != "pending":
        continue
    if u["file"] is None or not os.path.isfile(os.path.join(out, u["file"])):
        if bring_up:
            not_built(u)
            continue
        sys.exit("build_corpus: manifest unit %r has no staged file" % u["file"])
    finalize(u, u["file"])

for s in manifest["side_files"]:
    if s["status"] != "pending":
        continue
    path = os.path.join(out, s["file"])
    if not os.path.isfile(path):
        if bring_up:
            not_built(s)
            continue
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