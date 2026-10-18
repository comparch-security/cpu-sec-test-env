#!/usr/bin/env bash
set -euo pipefail
# build_image.sh LANE   (LANE = riscv64)
#
# Deploys the riscv64 system lane's bootable image:
#   1. lane advisory lock + EXIT trap (make -C benchmark clean + submodule-
#      clean assert on every exit path - the corpus build dirties test/);
#   2. cross-builds the corpus with build_corpus.sh (derived registry +
#      145 staged units + 1 side file + finalized manifest);
#   3. cross-builds the scheduler (run-test) and lib/common/libcfi.so with
#      `make -B` (GNU make does not rebuild on variable changes alone);
#   4. asserts the pinned -cpu model is an RVA23 profile (rva23s64/rva23u64 -
#      the toolchain's glibc baseline is RVA23U64) and that every staged
#      ELF's Tag_RISCV_arch extensions fit the toolchain's own crt1.o
#      baseline - an illegal-instruction inside the guest is undiagnosable
#      after the fact;
#   5. stages the rootfs: /init (guest/init), static busybox + applet links,
#      the glibc NEEDED closure of every staged ELF under /lib, the /bench
#      tree (run-test, derived configure.json, libcfi.so, the corpus,
#      versions.host.txt);
#   6. normalizes mtimes (SOURCE_DATE_EPOCH), packs
#      `find . | LC_ALL=C sort | cpio -o -H newc --reproducible --owner=0:0` into
#      build/riscv64/rootfs.cpio, and writes the image manifest.

if [ $# -ne 1 ] || [ "$1" != riscv64 ]; then
  echo "usage: $0 riscv64" >&2
  exit 2
fi
LANE=$1

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=../../env.sh
. ./env.sh

die() { echo "riscv64/build_image ($LANE): $*" >&2; exit 1; }

RISCV64_CROSS="${RISCV64_CXX%%g++*}"
READELF="${RISCV64_OBJDUMP%objdump}readelf"

BUILDD="$ROOT/$BUILD_DIR/riscv64"
CORPUS="$BUILDD/corpus"
STAGE="$BUILDD/stage"
CPIO="$BUILDD/rootfs.cpio"
IMAGE="$BUILDD/Image"
MANIFEST="$BUILDD/manifest.json"

# ---- lane advisory lock (released when this script exits) ----
mkdir -p "$ROOT/$BUILD_DIR"
exec 9>"$ROOT/$BUILD_DIR/.lane.lock"
if ! flock -n 9; then
  die "lane busy: $(cat "$ROOT/$BUILD_DIR/.lane.lock" 2>/dev/null || echo unknown) holds $BUILD_DIR/.lane.lock"
fi
printf '%s\n' "$LANE" > "$ROOT/$BUILD_DIR/.lane.lock"

# ---- collect-and-clean on every exit path ----
cleanup() {
  rc=$?
  set +e
  make -C "$ROOT/benchmark" clean >/dev/null 2>&1
  if [ -n "$(git -C "$ROOT/benchmark" status --short)" ]; then
    echo "ERROR: benchmark submodule left dirty after clean:" >&2
    git -C "$ROOT/benchmark" status --short >&2
    rc=1
  fi
  exit "$rc"
}
trap cleanup EXIT

[ -f "$IMAGE" ] || die "$IMAGE missing - run build_kernel.sh first"
[ -x "$BUILDD/busybox-root/bin/busybox" ] ||
  die "$BUILDD/busybox-root/bin/busybox missing - run build_busybox.sh first"

# ---- corpus (derived registry + units + side files + manifest) ----
bash "$ROOT/scripts/common/build_corpus.sh" "$LANE" "$CORPUS"

# ---- scheduler + libcfi, cross-built with -B ----
SHIM_DIR="$BUILDD/shim"
bash "$ROOT/scripts/common/shim.sh" "${RISCV64_CROSS%-}" "$SHIM_DIR"
export PATH="$SHIM_DIR:$PATH"
make -B -C "$ROOT/benchmark" run-test lib/common/libcfi.so \
  ARCH="$LANE" CXX="$RISCV64_CXX" ASM="$RISCV64_AS" OBJDUMP="$RISCV64_OBJDUMP"

# ---- stage the rootfs ----
rm -rf "$STAGE"
# /proc, /sys, /dev, /tmp are the guest init's mountpoints/work dirs: the
# kernel only auto-mounts devtmpfs (DEVTMPFS_MOUNT), so proc and sysfs need
# their directories staged or init's first mount fails with ENOENT.
mkdir -p "$STAGE/bench/lib/common" "$STAGE/bench/test" "$STAGE/lib" "$STAGE/bin" \
         "$STAGE/proc" "$STAGE/sys" "$STAGE/dev" "$STAGE/tmp"

install -m 0755 "$ROOT/scripts/riscv64/guest/init" "$STAGE/init"
install -m 0755 "$ROOT/benchmark/run-test" "$STAGE/bench/run-test"
install -m 0644 "$CORPUS/configure.json" "$STAGE/bench/configure.json"
install -m 0755 "$ROOT/benchmark/lib/common/libcfi.so" \
                "$STAGE/bench/lib/common/libcfi.so"
cp -a "$CORPUS/test/." "$STAGE/bench/test/"
bash "$ROOT/scripts/common/version_stamp.sh" "$LANE" "$STAGE/bench/versions.host.txt"

# busybox + applet links
cp -a "$BUILDD/busybox-root/." "$STAGE/"

# ---- ISA gate: the pin is an RVA23 profile model; every staged ELF's ISA
# extension set must fit the toolchain's own crt1.o baseline (the linker
# unions input tags, so the baseline RVA23U64 tag of crt1.o/libc.so.6 lands
# in every linked executable) ----
case "$QEMU_CPU_RISCV64" in
  rva23s64|rva23u64) ;;
  *) die "QEMU_CPU_RISCV64=$QEMU_CPU_RISCV64 is not an RVA23 profile model - the pinned toolchain's glibc baseline is RVA23U64, so the -cpu pin must be rva23s64 (or the rva23u64 fallback)" ;;
esac
CRT1=$("$RISCV64_CC" -print-file-name=crt1.o)
[ -f "$CRT1" ] || die "cannot resolve crt1.o via $RISCV64_CC -print-file-name (got '$CRT1')"
BASELINE_TAG=$("$READELF" -A "$CRT1" | sed -n 's/.*Tag_RISCV_arch: *"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p')
[ -n "$BASELINE_TAG" ] || die "$CRT1: no Tag_RISCV_arch attribute - cannot establish the toolchain baseline"
# extension name = token with its trailing version suffix (N or NpM) removed;
# names may embed digits (zic64b, zvl128b), so only the trailing version goes
ext_name() { printf '%s\n' "$1" | sed -E 's/[0-9]+(p[0-9]+)?$//'; }
baseline_exts=" "
for t in $(echo "${BASELINE_TAG#rv64}" | tr '_' ' '); do
  baseline_exts="$baseline_exts$(ext_name "$t") "
done

assert_rva23_fit() {  # elf
  local elf=$1 tag ext
  tag=$("$READELF" -A "$elf" | sed -n 's/.*Tag_RISCV_arch: *"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p')
  [ -n "$tag" ] || die "$elf: no Tag_RISCV_arch attribute"
  case "$tag" in rv64*) ;; *) die "$elf: Tag_RISCV_arch '$tag' is not rv64* - the pinned -cpu $QEMU_CPU_RISCV64 model cannot execute it" ;; esac
  for ext in $(echo "${tag#rv64}" | tr '_' ' '); do
    ext=$(ext_name "$ext")
    case "$baseline_exts" in
      *" $ext "*) ;;
      *) die "$elf: ISA extension '$ext' (Tag_RISCV_arch=$tag) is missing from the toolchain baseline (crt1.o Tag_RISCV_arch=$BASELINE_TAG)" ;;
    esac
  done
}

STAGED_ELFS=("$STAGE/bench/run-test" "$STAGE/bench/lib/common/libcfi.so")
while IFS= read -r -d '' f; do STAGED_ELFS+=("$f"); done < <(find "$STAGE/bench/test" -type f -print0)
# the derived side files (from the corpus manifest) are data words, not ELFs:
# they carry no ISA contract; any other non-ELF under bench/test is a defect
mapfile -d '' -t SIDE_BASENAMES < <(python3 - "$CORPUS/manifest.json" <<'PY'
import json, sys
for e in json.load(open(sys.argv[1]))["side_files"]:
    sys.stdout.buffer.write(e["file"].split("/")[-1].encode() + b"\0")
PY
)
is_side_file() { local b=${1##*/} s
  for s in ${SIDE_BASENAMES[@]+"${SIDE_BASENAMES[@]}"}; do
    [ "$b" = "$s" ] && return 0
  done
  return 1
}
CONFIRMED_ELFS=()
for elf in "${STAGED_ELFS[@]}"; do
  if [ "$(head -c 4 "$elf")" != $'\x7fELF' ]; then
    is_side_file "$elf" && continue
    die "$elf is not an ELF and is not a declared side file"
  fi
  machine=$("$READELF" -h "$elf" | awk -F: '/Machine:/{gsub(/^[ \t]+/,"",$2); print $2}')
  case "$machine" in
    *RISC-V*) ;;
    *) die "$elf is '$machine', not RISC-V - a non-cross binary leaked into the corpus" ;;
  esac
  assert_rva23_fit "$elf"
  CONFIRMED_ELFS+=("$elf")
done

# ---- glibc NEEDED closure of every staged ELF, staged flat under /lib ----
declare -A SEEN_LIBS=()
LIB_QUEUE=()
declare -A INTERP_NAMES=()
stage_lib() {  # soname
  local name=$1 src dep
  [ -z "${SEEN_LIBS[$name]:-}" ] || return 0
  SEEN_LIBS[$name]=1
  if [ "$name" = libcfi.so ]; then
    # libcfi.so is a bench build artifact, not resolvable via
    # -print-file-name: stage it from the bench tree (the units' NEEDED
    # libcfi.so) alongside its rpath home bench/lib/common/.
    cp -L "$ROOT/benchmark/lib/common/libcfi.so" "$STAGE/lib/libcfi.so"
    chmod 0644 "$STAGE/lib/libcfi.so"
    return 0
  fi
  src=$("$RISCV64_CXX" -print-file-name="$name")
  case "$src" in
    /*) [ -f "$src" ] || die "cannot resolve $name via $RISCV64_CXX -print-file-name (got '$src')" ;;
    *)  die "cannot resolve $name via $RISCV64_CXX -print-file-name (not found)" ;;
  esac
  cp -L "$src" "$STAGE/lib/$name"
  # the ELF interpreter must be executable: the kernel's open_exec() on
  # PT_INTERP requires MAY_EXEC, or every dynamic binary dies with EACCES
  # ("Permission denied", exit 126) at execve.
  if [ -n "${INTERP_NAMES[$name]:-}" ]; then
    chmod 0755 "$STAGE/lib/$name"
  else
    chmod 0644 "$STAGE/lib/$name"
  fi
  while IFS= read -r dep; do
    [ -n "$dep" ] && LIB_QUEUE+=("$dep")
  done < <("$READELF" -d "$src" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
}

for elf in "${CONFIRMED_ELFS[@]}"; do
  while IFS= read -r dep; do
    [ -n "$dep" ] && LIB_QUEUE+=("$dep")
  done < <("$READELF" -d "$elf" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
  # the dynamic loader itself (PT_INTERP), staged at its absolute path
  interp=$("$READELF" -lW "$elf" | sed -n 's/.*Requesting program interpreter: \([^]]*\).*/\1/p')
  if [ -n "$interp" ]; then
    INTERP_NAMES["$(basename "$interp")"]=1
    LIB_QUEUE+=("$(basename "$interp")")
  fi
done
while [ ${#LIB_QUEUE[@]} -gt 0 ]; do
  stage_lib "${LIB_QUEUE[0]}"
  LIB_QUEUE=("${LIB_QUEUE[@]:1}")
done
# libcfi.so is always staged under /lib even if no NEEDED entry surfaced it
stage_lib libcfi.so

# ---- reproducibility: normalize mtimes, deterministic cpio ----
find "$STAGE" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
( cd "$STAGE" && find . | LC_ALL=C sort | cpio -o -H newc --reproducible --owner=0:0 ) > "$CPIO" 2>/dev/null
[ -s "$CPIO" ] || die "rootfs.cpio is empty"

# ---- image manifest (sha256s + pins) ----
python3 - "$MANIFEST" "$LANE" "$IMAGE" "$CPIO" "$CORPUS/manifest.json" <<'PY'
import hashlib, json, os, sys
out, lane, image, cpio, corpus_manifest = sys.argv[1:6]

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

env = {}
with open("env.sh") as fh:
    for line in fh:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        env[k] = v.strip('"')
with open(corpus_manifest) as fh:
    corpus = json.load(fh)
manifest = {
    "lane": lane,
    "bench_commit": env["BENCH_COMMIT"],
    "cpu_model": env["QEMU_CPU_RISCV64"],
    "kernel": {"version": env["KERNEL_VERSION"], "sha256": env["KERNEL_SHA256"],
               "image_sha256": sha256(image)},
    "busybox": {"version": env["BUSYBOX_VERSION"], "sha256": env["BUSYBOX_SHA256"]},
    "rootfs_cpio_sha256": sha256(cpio),
    "source_date_epoch": int(env["SOURCE_DATE_EPOCH"]),
    "corpus_manifest": {
        "path": os.path.relpath(corpus_manifest, os.getcwd()),
        "sha256": sha256(corpus_manifest),
        "units": len(corpus["units"]),
        "side_files": len(corpus["side_files"]),
        "expected_failures": corpus["expected_failures"],
    },
}
with open(out, "w") as fh:
    json.dump(manifest, fh, indent=2)
    fh.write("\n")
print("riscv64/build_image: wrote %s" % out)
PY

echo "riscv64/build_image ($LANE): ok - $IMAGE, $CPIO ($(stat -c%s "$CPIO") bytes), $(find "$STAGE/bench/test" -type f | wc -l) corpus files staged"
