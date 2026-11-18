#!/usr/bin/env bash
set -euo pipefail
# dtc-cfi.sh - the venue's DTC interposer for the CFI variant lane: compile the
# guest device tree with Zicfilp/Zicfiss advertised.
#
# Why an interposer and not a template edit: workload-builder REGENERATES
# $OUT/generated-dts/<name>.dts.in on every build-firmware-linux.sh run
# (dts_generate_template in scripts/dts-config.sh), so a patch applied to the
# template file never survives to the compile.  The compile itself is the
# venue's documented hook - build-firmware-linux.sh takes DTC from the
# environment - so this wrapper rewrites the .dts it is handed (appending the
# two extensions to riscv,isa-extensions and to the riscv,isa string) and runs
# the real dtc on the patched copy.  Env-side by design: the workload-builder
# pin stays frozen.
#
# The advertisement is a precondition of arming, not a cosmetic claim: OpenSBI
# v1.9 gates its FWFT LANDING_PAD/SHADOW_STACK advertisement on the DT hart
# features, and the kernel's user-CFI probe reads the same node.  Without it
# both firmware and kernel are blind to CFI and every armed record dies at the
# self-arm blob's fail path (exit 20).  It is therefore scoped to the CFI
# variant lane: arming follows this advertisement, so a plain-lane DT carrying
# it would make the 7.3.4 kernel write the ssp CSR at the first userspace
# return, and the plain pinned interpreter (no ssp CSR) panics at boot
# (measured 2026-11-17).  venue/build-image.sh selects this interposer by
# ENABLE_FLAG and asserts the plain lane's compiled DTB carries neither
# extension.
#
# Invoked as DTC=<this> with dtc's own argument vector; venue/build-image.sh
# installs it into $OUT with mode 0755 first (build-firmware execs "$DTC"
# directly, and this repository tracks its scripts without the executable
# bit).  A wrapper that cannot find its input, or a DTS with no
# riscv,isa-extensions property, fails the build rather than silently
# compiling an advertisement-free tree.

real_dtc=$(command -v dtc) || { echo "dtc-cfi: dtc not found on PATH" >&2; exit 1; }
if [ "$(readlink -f "$real_dtc")" = "$(readlink -f "$0")" ]; then
  echo "dtc-cfi: the dtc on PATH is this wrapper itself - refusing to recurse" >&2
  exit 1
fi

args=()
input=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o|-i|-d) args+=("$1" "${2:?}"); shift 2 ;;
    -*)       args+=("$1"); shift ;;
    *)
      if [ -f "$1" ]; then input=$1; args+=("__INPUT__"); else args+=("$1"); fi
      shift ;;
  esac
done
[ -n "$input" ] || { echo "dtc-cfi: no input .dts in the dtc argument list" >&2; exit 1; }

patched=$(mktemp)
trap 'rm -f "$patched"' EXIT

python3 - "$input" "$patched" <<'PY'
import re, sys

src, dst = sys.argv[1:3]
text = open(src, encoding="utf-8").read()

def add_extensions(match):
    body = match.group(1).rstrip()
    if '"zicfiss"' in body:
        return match.group(0)
    return 'riscv,isa-extensions = %s, "zicfilp", "zicfiss";' % body

def add_legacy(match):
    value = match.group(2)
    if "zicfiss" in value:
        return match.group(0)
    return '%s "%s_zicfilp_zicfiss"' % (match.group(1), value)

text, n_ext = re.subn(r'riscv,isa-extensions\s*=\s*([^;]*);', add_extensions, text, count=1)
if n_ext != 1:
    sys.exit("dtc-cfi: the DTS carries no riscv,isa-extensions property (cannot advertise Zicfilp/Zicfiss)")
# riscv,isa-base is a different property; the pattern below requires the
# assignment directly after `riscv,isa`, so it cannot match `-base`/`-extensions`.
text, n_isa = re.subn(r'(riscv,isa\s*=\s*)"([^"]*)"', add_legacy, text, count=1)
if n_isa != 1:
    sys.exit("dtc-cfi: the DTS carries no riscv,isa string (cannot advertise Zicfilp/Zicfiss)")

with open(dst, "w", encoding="utf-8") as fh:
    fh.write(text)
PY

for i in "${!args[@]}"; do
  [ "${args[$i]}" = "__INPUT__" ] && args[$i]=$patched
done
exec "$real_dtc" "${args[@]}"
