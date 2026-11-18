#!/usr/bin/env bash
set -euo pipefail
# build_image.sh LANE   (LANE = riscv64 | riscv64-cfi)
#
# Deploys a riscv64 system lane's bootable image:
#   1. lane advisory lock + EXIT trap (make -C benchmark clean + submodule-
#      clean assert on every exit path - the scheduler cross build dirties
#      test/; the corpus staging itself never touches the worktree);
#   2. stages the corpus with scripts/common/stage_corpus.sh (the tracked
#      registry verbatim + the runner's corpus-keyed units + the registry's
#      side files + the declared support files + the verified manifest);
#      the CFI variant (riscv64-cfi) stages through the bench's CFI build
#      class - --enable-flag enable_riscv64_cfi - and builds with the GCC 16
#      toolchain, which covers EVERY consumer below (shim, scheduler build,
#      crt1.o baseline, glibc closure);
#   3. cross-builds the scheduler (run-test) and lib/common/libcfi.so with
#      `make -B` (GNU make does not rebuild on variable changes alone), always
#      with the bench's ARCH=riscv64 token;
#   4. asserts the pinned -cpu model's RVA23 profile (rva23s64/rva23u64 - the
#      toolchain's glibc baseline is RVA23U64) and that every staged ELF's
#      Tag_RISCV_arch extensions fit the toolchain's own crt1.o baseline (plus,
#      for the CFI variant only, the class allowlist zicfilp/zicfiss/zimop,
#      which every class-built ELF carries and the baseline does not) - an
#      illegal-instruction inside the guest is undiagnosable after the fact;
#   5. stages the rootfs: /init (guest/init), static busybox + applet links,
#      the glibc NEEDED closure of every staged ELF - under /lib for the plain
#      lane, under the GCC 16 loader's own /lib64/lp64d for the variant, with
#      the loader itself always at its /lib PT_INTERP path - plus the assert
#      that every NEEDED name resolves in a directory the staged loader
#      searches (the interpreter's own soname, staged at its PT_INTERP path
#      and never searched, is the sole exemption); the /bench tree (run-test, derived configure.json, libcfi.so,
#      the corpus, versions.host.txt);
#   6. normalizes mtimes (SOURCE_DATE_EPOCH), packs
#      `find . | LC_ALL=C sort | cpio -o -H newc --reproducible --owner=0:0` into
#      build/<lane>/rootfs.cpio, and writes the image manifest.
#
# Trees are lane-keyed: build/riscv64-cfi/ carries the variant's corpus, stage
# tree, rootfs.cpio and manifest, while the shared kernel Image and
# busybox-root under build/riscv64/ are READ-ONLY inputs for it.

case "${1:-}" in
  riscv64|riscv64-cfi) ;;
  *) echo "usage: $0 riscv64|riscv64-cfi" >&2; exit 2 ;;
esac
if [ $# -ne 1 ]; then
  echo "usage: $0 riscv64|riscv64-cfi" >&2
  exit 2
fi
LANE=$1

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=../../env.sh
. ./env.sh

die() { echo "riscv64/build_image ($LANE): $*" >&2; exit 1; }

# ---- variant selection ----
# The variant is selected by its lane name and its bench class flag must
# accompany it: an unarmed gcc-13 duplicate must not pass as a "cfi" deploy.
case "$LANE" in
  riscv64)     EXPECT_FLAG="" ;;
  riscv64-cfi) EXPECT_FLAG=enable_riscv64_cfi ;;
esac
[ "${ENABLE_FLAG:-}" = "$EXPECT_FLAG" ] ||
  die "ENABLE_FLAG=${ENABLE_FLAG:-<unset>} for lane $LANE, expected '${EXPECT_FLAG}' (make ARCH=${LANE%-cfi} enable_riscv64_cfi=yes deploy selects the variant)"

# The variant builds with the GCC 16 pin, set ONCE here so every consumer
# below inherits it: the shim call, the scheduler/libcfi cross build, the
# crt1.o baseline and the glibc NEEDED/PT_INTERP closure.  The corpus links
# against the GCC 16 sysroot's glibc, so staging gcc-13's older libc would
# ship the wrong runtime to the guest.
SHARED="$ROOT/$BUILD_DIR/riscv64"
if [ "$LANE" != riscv64 ]; then
  case "$RISCV64_GNU_PREFIX" in /*) ;; *) RISCV64_GNU_PREFIX="$ROOT/$RISCV64_GNU_PREFIX" ;; esac
  [ -x "${RISCV64_GNU_PREFIX}gcc" ] ||
    die "CFI toolchain not found: ${RISCV64_GNU_PREFIX}gcc (RISCV64_GNU_PREFIX=$RISCV64_GNU_PREFIX) - install it or override RISCV64_GNU_PREFIX"
  RISCV64_CXX="${RISCV64_GNU_PREFIX}g++"
  RISCV64_CC="${RISCV64_GNU_PREFIX}gcc"
  RISCV64_AS="${RISCV64_GNU_PREFIX}as"
  RISCV64_OBJDUMP="${RISCV64_GNU_PREFIX}objdump"
fi
RISCV64_CROSS="${RISCV64_CXX%%g++*}"
READELF="${RISCV64_OBJDUMP%objdump}readelf"

BUILDD="$ROOT/$BUILD_DIR/$LANE"
CORPUS="$BUILDD/corpus"
STAGE="$BUILDD/stage"
CPIO="$BUILDD/rootfs.cpio"
MANIFEST="$BUILDD/manifest.json"
# The kernel Image and busybox-root are lane-agnostic shared inputs (built by
# build_kernel.sh / build_busybox.sh into build/riscv64/); the variant reads
# them read-only and never writes that tree.
IMAGE="$SHARED/Image"
BUSYBOX_ROOT="$SHARED/busybox-root"

# ---- where the runtime closure is staged ----
# The staged loader searches only its own compiled-in dirs (measured
# 2026-11-18): the GCC 16 loader looks in /lib64/lp64d/ and /usr/lib64/lp64d/
# and NOT in /lib/, while the apt gcc-13 loader looks in /lib/, /usr/lib/ and
# the riscv64-linux-gnu multiarch dirs.  A closure staged flat under /lib is
# therefore invisible to the variant's loader at the first userspace exec
# (libstdc++.so.6: cannot open shared object file), so the variant stages it
# into the loader's own dir.  The loader itself always stays at its PT_INTERP
# path /lib/ld-linux-riscv64-lp64d.so.1 - the absolute path the kernel opens
# at execve.
if [ "$LANE" = riscv64 ]; then
  CLOSURE_DIR="$STAGE/lib"
  LOADER_SEARCH="/lib /usr/lib"
else
  CLOSURE_DIR="$STAGE/lib64/lp64d"
  LOADER_SEARCH="/lib64/lp64d /usr/lib64/lp64d"
fi

# ---- lane advisory lock (released when this script exits) ----
# The riscv64 deploy recipe holds the lock across the WHOLE recipe and passes
# the descriptor down (LANE_LOCK_INHERITED=1): flock is per
# open-file-description, so this script's own flock on a fresh descriptor
# would fail against the recipe's own lock.  The marker is honoured only when
# fd 9 verifiably IS the lane lock; a spoofed marker dies.  The descriptor is
# kept open through the staging call (stage_corpus.sh is caller-locked and
# verifies it) and closed right after, so no build child inherits the lock.
LOCK_INHERITED=${LANE_LOCK_INHERITED:-}
mkdir -p "$ROOT/$BUILD_DIR"
LANE_LOCK="$ROOT/$BUILD_DIR/.lane.lock"
if [ "$LOCK_INHERITED" = 1 ]; then
  fd9_target=$(readlink -f /proc/self/fd/9 2>/dev/null || true)
  lock_target=$(readlink -f "$LANE_LOCK" 2>/dev/null || printf '%s\n' "$LANE_LOCK")
  if [ -z "$fd9_target" ] || [ "$fd9_target" != "$lock_target" ] || ! flock -n 9; then
    die "LANE_LOCK_INHERITED=1 but fd 9 is not the held lane lock $LANE_LOCK (marker spoofed or descriptor lost)"
  fi
else
  exec 9>>"$LANE_LOCK"
  if ! flock -n 9; then
    die "lane busy: $(cat "$LANE_LOCK" 2>/dev/null || echo unknown) holds $BUILD_DIR/.lane.lock"
  fi
  printf '%s\n' "$LANE" > "$LANE_LOCK"
fi

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

[ -f "$IMAGE" ] ||
  die "$IMAGE missing - run make ARCH=riscv64 deploy first (scripts/riscv64/build_kernel.sh stages the shared build/riscv64/Image)"
[ -x "$BUSYBOX_ROOT/bin/busybox" ] ||
  die "$BUSYBOX_ROOT/bin/busybox missing - run make ARCH=riscv64 deploy first (scripts/riscv64/build_busybox.sh stages the shared busybox root)"

# ---- corpus (tracked registry verbatim + keyed units + side/support files) ----
# The CFI variant stages through the bench class flag; the staging orchestrator
# keys its own scratch tree on the variant lane name.
STAGE_ARGS=("$LANE" "$CORPUS")
[ -z "$EXPECT_FLAG" ] || STAGE_ARGS+=(--enable-flag "$EXPECT_FLAG")
bash "$ROOT/scripts/common/stage_corpus.sh" "${STAGE_ARGS[@]}"
# The staging leg verified and closed its own copy of the inherited descriptor;
# close this script's copy now so no build child below inherits the lock.
# Without an inherited lock fd 9 IS this script's lock and stays open to exit.
if [ "$LOCK_INHERITED" = 1 ]; then exec 9>&-; fi

# ---- scheduler + libcfi, cross-built with -B ----
# ARCH is the bench token (riscv64) for both lanes, and MAKEFLAGS/MFLAGS are
# cleared: the deploy's own enable_riscv64_cfi=yes would otherwise reach the
# bench Makefile (which guards the class to ARCH=riscv64) and key
# lib/riscv64-cfi/ (no such sources).
SHIM_DIR="$BUILDD/shim"
if [ "$LANE" = riscv64 ]; then
  SHIM_ARG="${RISCV64_CROSS%-}"
else
  SHIM_ARG="$RISCV64_OBJDUMP"   # shim.sh takes an absolute TOOL PATH, not a prefix
fi
bash "$ROOT/scripts/common/shim.sh" "$SHIM_ARG" "$SHIM_DIR"
export PATH="$SHIM_DIR:$PATH"
env -u MAKEFLAGS -u MFLAGS make -B -C "$ROOT/benchmark" run-test lib/common/libcfi.so \
  ARCH=riscv64 CXX="$RISCV64_CXX" ASM="$RISCV64_AS" OBJDUMP="$RISCV64_OBJDUMP"

# ---- stage the rootfs ----
rm -rf "$STAGE"
# /proc, /sys, /dev, /tmp are the guest init's mountpoints/work dirs: the
# kernel only auto-mounts devtmpfs (DEVTMPFS_MOUNT), so proc and sysfs need
# their directories staged or init's first mount fails with ENOENT.
mkdir -p "$STAGE/bench/lib/common" "$STAGE/bench/test" "$STAGE/lib" "$CLOSURE_DIR" \
         "$STAGE/bin" "$STAGE/proc" "$STAGE/sys" "$STAGE/dev" "$STAGE/tmp"

install -m 0755 "$ROOT/scripts/riscv64/guest/init" "$STAGE/init"
install -m 0755 "$ROOT/benchmark/run-test" "$STAGE/bench/run-test"
install -m 0644 "$CORPUS/configure.json" "$STAGE/bench/configure.json"
install -m 0755 "$ROOT/benchmark/lib/common/libcfi.so" \
                "$STAGE/bench/lib/common/libcfi.so"
cp -a "$CORPUS/test/." "$STAGE/bench/test/"
bash "$ROOT/scripts/common/version_stamp.sh" "$LANE" "$STAGE/bench/versions.host.txt"

# busybox + applet links
cp -a "$BUSYBOX_ROOT/." "$STAGE/"

# ---- ISA gate: the effective CPU request's profile base is an RVA23 model;
# every staged ELF's ISA extension set must fit the toolchain's own crt1.o
# baseline (the linker unions input tags, so the baseline RVA23U64 tag of
# crt1.o/libc.so.6 lands in every linked executable).  The CFI variant boots
# the CFI property form; its properties add only Zicfilp/Zicfiss, so the
# profile base is what the gate checks ----
if [ "$LANE" = riscv64 ]; then CPU_REQ="$QEMU_CPU_RISCV64"; else CPU_REQ="$QEMU_CPU_RISCV64_CFI"; fi
CPU_BASE=${CPU_REQ%%,*}
case "$CPU_BASE" in
  rva23s64|rva23u64) ;;
  *) die "CPU model $CPU_REQ (profile base $CPU_BASE) is not an RVA23 profile model - the pinned toolchain's glibc baseline is RVA23U64, so the -cpu pin must be rva23s64 (or the rva23u64 fallback)" ;;
esac
# The class's own ISA additions, scoped strictly to the variant: the GCC 16
# toolchain's crt1.o baseline does not carry them, but every class-built ELF's
# Tag_RISCV_arch does (measured).  Anything outside both sets still dies.
CLASS_EXTS=""
[ "$LANE" = riscv64 ] || CLASS_EXTS=" zicfilp zicfiss zimop "
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
  case "$tag" in rv64*) ;; *) die "$elf: Tag_RISCV_arch '$tag' is not rv64* - the pinned -cpu $CPU_REQ model cannot execute it" ;; esac
  for ext in $(echo "${tag#rv64}" | tr '_' ' '); do
    ext=$(ext_name "$ext")
    case "$baseline_exts$CLASS_EXTS" in
      *" $ext "*) ;;
      *) die "$elf: ISA extension '$ext' (Tag_RISCV_arch=$tag) is missing from the toolchain baseline (crt1.o Tag_RISCV_arch=$BASELINE_TAG)${CLASS_EXTS:+ and the CFI class allowlist ($CLASS_EXTS)}" ;;
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
    sys.stdout.buffer.write(e["name"].split("/")[-1].encode() + b"\0")
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

# ---- glibc NEEDED closure of every staged ELF, in the staged loader's dirs ----
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
    cp -L "$ROOT/benchmark/lib/common/libcfi.so" "$CLOSURE_DIR/libcfi.so"
    chmod 0644 "$CLOSURE_DIR/libcfi.so"
    return 0
  fi
  src=$("$RISCV64_CXX" -print-file-name="$name")
  case "$src" in
    /*) [ -f "$src" ] || die "cannot resolve $name via $RISCV64_CXX -print-file-name (got '$src')" ;;
    *)  die "cannot resolve $name via $RISCV64_CXX -print-file-name (not found)" ;;
  esac
  # the ELF interpreter stays at its PT_INTERP path ($STAGE/lib/<name> is
  # /lib/<name> in the guest): the kernel's open_exec() on PT_INTERP requires
  # MAY_EXEC, or every dynamic binary dies with EACCES ("Permission denied",
  # exit 126) at execve.  Every other NEEDED goes where the loader searches.
  if [ -n "${INTERP_NAMES[$name]:-}" ]; then
    cp -L "$src" "$STAGE/lib/$name"
    chmod 0755 "$STAGE/lib/$name"
  else
    cp -L "$src" "$CLOSURE_DIR/$name"
    chmod 0644 "$CLOSURE_DIR/$name"
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
# libcfi.so is always staged in the closure dir even if no NEEDED surfaced it
stage_lib libcfi.so

# ---- closure reachability ----
# Resolving the right files is not enough: the staged loader searches only its
# own compiled-in dirs, so a closure staged anywhere else is invisible at the
# first userspace exec - and the image would publish and boot to "cannot open
# shared object file".  Every NEEDED soname of every staged ELF (the bench
# binaries and the closure itself) must sit in one of LOADER_SEARCH's dirs.
# The one exemption is the ELF interpreter's own soname: the loader is staged
# at its PT_INTERP path ($STAGE/lib/<name>), the kernel opens that absolute
# path at execve and the loader resolves its own soname from its link map, so
# it is never searched - but libc.so.6 still lists it as an ordinary NEEDED.
assert_closure_reachable() {  # elf...
  local elf dep d found
  for elf in "$@"; do
    while IFS= read -r dep; do
      [ -n "$dep" ] || continue
      found=0
      for d in $LOADER_SEARCH; do
        [ -f "$STAGE$d/$dep" ] && { found=1; break; }
      done
      if [ "$found" = 0 ] && [ -n "${INTERP_NAMES[$dep]:-}" ] && [ -f "$STAGE/lib/$dep" ]; then
        found=1
      fi
      [ "$found" = 1 ] ||
        die "$elf: NEEDED $dep is not staged in any directory the staged loader searches ($LOADER_SEARCH) - stage the closure into one of them"
    done < <("$READELF" -d "$elf" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
  done
}
CLOSURE_CHECK=("${CONFIRMED_ELFS[@]}")
while IFS= read -r -d '' f; do CLOSURE_CHECK+=("$f"); done \
  < <(find "$CLOSURE_DIR" "$STAGE/lib" -maxdepth 1 -type f -print0 | sort -zu)
assert_closure_reachable "${CLOSURE_CHECK[@]}"

# ---- reproducibility: normalize mtimes, deterministic cpio ----
find "$STAGE" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
( cd "$STAGE" && find . | LC_ALL=C sort | cpio -o -H newc --reproducible --owner=0:0 ) > "$CPIO" 2>/dev/null
[ -s "$CPIO" ] || die "rootfs.cpio is empty"

# ---- image manifest (sha256s + pins) ----
python3 - "$MANIFEST" "$LANE" "$IMAGE" "$CPIO" "$CORPUS/manifest.json" "$CPU_REQ" <<'PY'
import hashlib, json, os, sys
out, lane, image, cpio, corpus_manifest, cpu_model = sys.argv[1:7]

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
    "cpu_model": cpu_model,
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
        "support_files": len(corpus["support_files"]),
        "skipped": corpus["skipped"],
    },
}
with open(out, "w") as fh:
    json.dump(manifest, fh, indent=2)
    fh.write("\n")
print("riscv64/build_image: wrote %s" % out)
PY

echo "riscv64/build_image ($LANE): ok - $IMAGE, $CPIO ($(stat -c%s "$CPIO") bytes), $(find "$STAGE/bench/test" -type f | wc -l) corpus files staged"
