#!/usr/bin/env bash
set -euo pipefail
# build_toolchains.sh (no args)
#
# Builds the CHERI dialect-probe toolchains for the cheri lane:
#   - fetches the cheribuild tree at the env.sh pin through the sandbox-safe
#     codeload.github.com tarball route (no git clone of github.com anywhere
#     in this script);
#   - the fetched tarball's observed sha256 is recorded in
#     build/cheri/versions.txt (the cheribuild pin is a commit id, not a
#     content hash - codeload tarballs of a commit are stable, but the plan
#     records the observed hash rather than pinning one);
#   - runs `cheribuild.py --source-root ... --output-root ... --build-root
#     ... --skip-update llvm` (CHERI-LLVM, the decisive toolchain, first),
#     then `morello-llvm`.  The LLVM source trees are pre-staged by the
#     planner at build/cheri/sources/{llvm-project,morello-llvm-project};
#     --skip-update makes cheribuild skip every git pull/fetch, so the build
#     is network-free.  (A missing source dir would still make cheribuild try
#     to clone it, hence the explicit existence assert below.)
#
# Both builds are hours-long source builds: run this script in the background
# and monitor.  A build failure is a planner blocker - report it with the
# failing step, never add a retry loop.
#
# Output layout: build/cheri/{cheribuild-src,sources,output,build,versions.txt}
# (cheribuild's source/output/build trees stay under the gitignored build/),
# build/downloads/cheribuild-<pin>.tar.gz (fetched tarball).

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=../../env.sh
. ./env.sh

die() { echo "cheri/build_toolchains: $*" >&2; exit 1; }

CHERI_BROOT="$ROOT/$BUILD_DIR/cheri"
DL_DIR="$ROOT/$BUILD_DIR/downloads"
TARBALL="$DL_DIR/cheribuild-$CHERIBUILD_COMMIT.tar.gz"
SRC="$CHERI_BROOT/cheribuild-src"
VERSIONS="$CHERI_BROOT/versions.txt"

# ---- fetch: .part + atomic rename (no pinned sha256 for the cheribuild
# tarball - the observed hash is recorded in versions.txt below) ----
fetch_cheribuild() {
  local url="$CHERIBUILD_URL/$CHERIBUILD_COMMIT" attempt
  if [ -f "$TARBALL" ]; then
    echo "cheribuild: using cached $TARBALL"
    return 0
  fi
  mkdir -p "$(dirname "$TARBALL")"
  for attempt in 1 2 3; do
    if curl -fsSL --connect-timeout 30 -o "$TARBALL.part" "$url"; then
      mv "$TARBALL.part" "$TARBALL"
      echo "cheribuild: fetched $url"
      return 0
    fi
    rm -f "$TARBALL.part"
    echo "cheribuild: network failure fetching $url (attempt $attempt/3)" >&2
    sleep $((attempt * 2))
  done
  die "cheribuild: DOWNLOAD FAILED after 3 attempts: $url"
}

fetch_cheribuild

mkdir -p "$CHERI_BROOT"
TARBALL_SHA256=$(sha256sum "$TARBALL" | awk '{print $1}')

# ---- record provenance (env.sh pins + the observed tarball hash) ----
bash "$ROOT/scripts/common/version_stamp.sh" cheri_riscv64 "$VERSIONS"
{
  echo "cheribuild-tarball-url: $CHERIBUILD_URL/$CHERIBUILD_COMMIT"
  echo "cheribuild-tarball-sha256: $TARBALL_SHA256"
} >> "$VERSIONS"
echo "cheribuild: tarball sha256 $TARBALL_SHA256 (recorded in $VERSIONS)"

# ---- extract (fresh tree each run) ----
rm -rf "$SRC"
mkdir -p "$SRC"
tar -xzf "$TARBALL" --strip-components=1 -C "$SRC"
CHERIBUILD_PY="$SRC/cheribuild.py"
[ -f "$CHERIBUILD_PY" ] || die "extracted cheribuild tree has no cheribuild.py"

# ---- assert the planner-provided LLVM source trees (with --skip-update a
# missing dir would still make cheribuild try to clone it) ----
LLVM_SRC="$CHERI_BROOT/sources/llvm-project"
MORELLO_SRC="$CHERI_BROOT/sources/morello-llvm-project"
[ -d "$LLVM_SRC" ] || die "missing planner-provided source tree $LLVM_SRC (CHERI-LLVM); the planner stages it - this script never clones"
[ -d "$MORELLO_SRC" ] || die "missing planner-provided source tree $MORELLO_SRC (Morello-LLVM); the planner stages it - this script never clones"

# ---- build CHERI-LLVM first (the decisive dialect toolchain), then Morello ----
CHERIBUILD_LAYOUT=(--source-root "$CHERI_BROOT/sources"
                   --output-root "$CHERI_BROOT/output"
                   --build-root "$CHERI_BROOT/build"
                   --skip-update)
START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "cheribuild: building llvm (CHERI-LLVM) at $START - this takes hours"
if ! python3 "$CHERIBUILD_PY" "${CHERIBUILD_LAYOUT[@]}" llvm; then
  die "cheribuild llvm (CHERI-LLVM) build FAILED - see the log above for the exact failing step"
fi
echo "cheribuild: building morello-llvm (Morello-LLVM)"
if ! python3 "$CHERIBUILD_PY" "${CHERIBUILD_LAYOUT[@]}" morello-llvm; then
  die "cheribuild morello-llvm (Morello-LLVM) build FAILED - see the log above (CHERI-LLVM is already built; the planner resolves this)"
fi

END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "cheri/build_toolchains: ok - CHERI-LLVM and Morello-LLVM built ($START .. $END)"
echo "cheri/build_toolchains: next - scripts/cheri/dialect_probe.sh"
