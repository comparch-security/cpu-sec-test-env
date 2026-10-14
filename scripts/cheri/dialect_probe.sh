#!/usr/bin/env bash
set -euo pipefail
# dialect_probe.sh (no args)
#
# Assembles the four CHERI dialect probe groups with the toolchains built by
# scripts/cheri/build_toolchains.sh and writes every raw command, exit code
# and stderr into results/cheri/probe-<UTC-date>.json with a one-line verdict
# per dialect (plan 2026-10-12-test-env-all-archs, Step 5).
#
# Probe matrix (the as-is variants are expected to fail - their
# assembly_return_site is the untranslated x86 body the deferred issue
# indepassembly-return-site-untranslated records; what the probe measures is
# whether the *dialect* is accepted by the toolchain):
#   cheri_riscv64 / as-is     benchmark/lib/cheri_riscv64/indepassembly.asm
#   cheri_riscv64 / fix-text  same file, assembly_return_site replaced by the
#                             vendored scripts/cheri/fix-text/cheri_riscv64.asm
#     both: --target=riscv64-unknown-freebsd -march=rv64gcxcheri
#           -mabi=l64pc128d -cheri-bounds=very-aggressive
#   morello / as-is           benchmark/lib/aarch64/indepassembly.asm
#   morello / fix-text        same file, assembly_return_site replaced by the
#                             vendored scripts/cheri/fix-text/aarch64.asm
#     both: --target=aarch64-unknown-freebsd -march=morello -mabi=purecap
#           -cheri-bounds=very-aggressive
#
# Output layout: results/cheri/probe-<date>.json (the durable verdict; shape:
# cheribuild_commit, toolchains, probes[], verdicts{}), build/cheri/probe/
# (per-probe .cmd/.exit/.stderr scratch + assembled .asm/.o intermediates).

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=../../env.sh
. ./env.sh

die() { echo "cheri/dialect_probe: $*" >&2; exit 1; }

CHERI_BROOT="$ROOT/$BUILD_DIR/cheri"
# both cheribuild targets are SDK targets: they install under the output
# root's sdk/ (CHERI-LLVM) and morello-sdk/ (Morello-LLVM) dirs
CHERI_BINDIR="$CHERI_BROOT/output/sdk/bin"
MORELLO_BINDIR="$CHERI_BROOT/output/morello-sdk/bin"
FIX="$ROOT/scripts/cheri/fix-text"
LIB="$ROOT/benchmark/lib"
PROBE_DIR="$CHERI_BROOT/probe"
RESULTS_DIR="$ROOT/results/cheri"

# ---- locate the built clangs (SDK bin dir: prefer clang, fall back to a
# target-prefixed *-clang; the resolved path must be absolute because the
# step-5 verifier re-runs the recorded command) ----
find_clang() { # bindir
  local bindir=$1 c
  for c in "$bindir/clang" "$bindir"/*-clang; do
    [ -x "$c" ] && { realpath "$c"; return 0; }
  done
  return 1
}
CHERI_CLANG=$(find_clang "$CHERI_BINDIR") ||
  die "CHERI-LLVM clang not found under $CHERI_BINDIR - run scripts/cheri/build_toolchains.sh first"
MORELLO_CLANG=$(find_clang "$MORELLO_BINDIR") ||
  die "Morello-LLVM clang not found under $MORELLO_BINDIR - run scripts/cheri/build_toolchains.sh first"

mkdir -p "$PROBE_DIR" "$RESULTS_DIR"

# ---- construct the fix-text variants: bench file truncated at the x86
# assembly_return_site label, then the vendored translation appended ----
make_fixed() { # src.asm fix.asm dst.asm
  awk '/^assembly_return_site:/{exit} {print}' "$1" > "$3"
  cat "$2" >> "$3"
}
make_fixed "$LIB/cheri_riscv64/indepassembly.asm" "$FIX/cheri_riscv64.asm" \
           "$PROBE_DIR/cheri_riscv64-fixed.asm"
make_fixed "$LIB/aarch64/indepassembly.asm" "$FIX/aarch64.asm" \
           "$PROBE_DIR/morello-fixed.asm"

# ---- run one probe: argv in, .cmd/.exit/.stderr recorded, re-runnable ----
run_probe() { # dialect variant argv...
  local dialect=$1 variant=$2
  shift 2
  local tag="$dialect-$variant"
  printf '%s\n' "$@" > "$PROBE_DIR/$tag.cmd"
  set +e
  "$@" 2> "$PROBE_DIR/$tag.stderr"
  local rc=$?
  set -e
  printf '%s\n' "$rc" > "$PROBE_DIR/$tag.exit"
  echo "dialect_probe: $dialect/$variant -> exit $rc"
}

CFLAGS_CHERI=(--target=riscv64-unknown-freebsd -march=rv64gcxcheri
              -mabi=l64pc128d -cheri-bounds=very-aggressive)
CFLAGS_MORELLO=(--target=aarch64-unknown-freebsd -march=morello
                -mabi=purecap -cheri-bounds=very-aggressive)

run_probe cheri_riscv64 as-is \
  "$CHERI_CLANG" "${CFLAGS_CHERI[@]}" -c \
  "$LIB/cheri_riscv64/indepassembly.asm" -o "$PROBE_DIR/cheri_riscv64-as-is.o"
run_probe cheri_riscv64 fix-text \
  "$CHERI_CLANG" "${CFLAGS_CHERI[@]}" -c \
  "$PROBE_DIR/cheri_riscv64-fixed.asm" -o "$PROBE_DIR/cheri_riscv64-fix-text.o"
run_probe morello as-is \
  "$MORELLO_CLANG" "${CFLAGS_MORELLO[@]}" -c \
  "$LIB/aarch64/indepassembly.asm" -o "$PROBE_DIR/morello-as-is.o"
run_probe morello fix-text \
  "$MORELLO_CLANG" "${CFLAGS_MORELLO[@]}" -c \
  "$PROBE_DIR/morello-fixed.asm" -o "$PROBE_DIR/morello-fix-text.o"

# ---- assemble results/cheri/probe-<date>.json ----
PROBE_DIR="$PROBE_DIR" RESULTS_DIR="$RESULTS_DIR" \
CHERI_CLANG="$CHERI_CLANG" MORELLO_CLANG="$MORELLO_CLANG" \
CHERIBUILD_COMMIT="$CHERIBUILD_COMMIT" \
python3 - <<'PY'
import datetime
import json
import os

probe_dir = os.environ["PROBE_DIR"]
results_dir = os.environ["RESULTS_DIR"]
probes = []
for dialect in ("cheri_riscv64", "morello"):
    for variant in ("as-is", "fix-text"):
        tag = "%s-%s" % (dialect, variant)
        with open(os.path.join(probe_dir, tag + ".cmd")) as fh:
            command = fh.read().splitlines()
        with open(os.path.join(probe_dir, tag + ".exit")) as fh:
            exit_code = int(fh.read().strip())
        with open(os.path.join(probe_dir, tag + ".stderr")) as fh:
            stderr = fh.read()
        probes.append({"dialect": dialect, "variant": variant,
                       "command": command, "exit_code": exit_code,
                       "stderr": stderr})

verdicts = {}
for dialect in ("cheri_riscv64", "morello"):
    codes = {p["variant"]: p["exit_code"] for p in probes
             if p["dialect"] == dialect}
    if any(c == 0 for c in codes.values()):
        # never use the substring "reject" in an accepted verdict (the step-5
        # verifier keys on it)
        verdicts[dialect] = (
            "accepted: fix-text variant exit %d; as-is exit %d "
            "(the untranslated x86 body fails any riscv/morello assembler - "
            "the dialect verdict is grounded in the fix-text variant)"
            % (codes["fix-text"], codes["as-is"]))
    else:
        verdicts[dialect] = (
            "rejected: as-is exit %d, fix-text exit %d - this toolchain does "
            "not accept the dialect (or the vendored translation text); "
            "stderr in the probe records carries the assembler diagnostics"
            % (codes["as-is"], codes["fix-text"]))

out = {
    "cheribuild_commit": os.environ["CHERIBUILD_COMMIT"],
    "toolchains": {
        "cheri_riscv64": os.environ["CHERI_CLANG"],
        "morello": os.environ["MORELLO_CLANG"],
    },
    "probes": probes,
    "verdicts": verdicts,
}
path = os.path.join(results_dir, "probe-%s.json"
                    % datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d"))
with open(path, "w") as fh:
    json.dump(out, fh, indent=2)
    fh.write("\n")
print("cheri/dialect_probe: wrote %s" % path)
for dialect in ("cheri_riscv64", "morello"):
    print("cheri/dialect_probe: %s verdict: %s" % (dialect, verdicts[dialect]))
PY
