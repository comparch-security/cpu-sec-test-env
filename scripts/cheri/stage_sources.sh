#!/usr/bin/env bash
set -euo pipefail
# stage_sources.sh (no args)
#
# Stages the three pinned source trees the CHERI emulator/image builds need
# (plan 2026-10-14-cheri-lanes-bringup, Step 1; executed as hosted Step 4):
#   build/cheri/sources/qemu          CHERI-Alliance/qemu  @ CHERI_QEMU_COMMIT
#   build/cheri/sources/cheribsd      CTSRD-CHERI/cheribsd @ CHERIBSD_SRC_COMMIT
#   build/cheri/sources/bbl           CTSRD-CHERI/riscv-pk @ BBL_SRC_COMMIT
#
# The third tree is the riscv64 lane's M-mode boot firmware source: the
# CHERI riscv64 machine loads the BBL firmware (RISCV64_BIOS_BIN) into
# M-mode and jumps to the -kernel payload from there, so the lane cannot
# boot without it (Step 7 round 1 proved this in one line).  Cheribuild's
# directory name for this tree is "bbl" - not the repo's own name - so it
# is staged at sources/bbl; staging it under any other name would leave
# sources/bbl empty and make cheribuild silently clone the branch tip
# instead of the pin (ensure_cloned runs before skip_update).
#
# (makefs is NOT staged: the Engil/makefs fork route was removed 2026-10-15 -
# the fork has no msdos support for the EFI FAT partition, and cheribuild
# discovers the FreeBSD host-tools makefs its own world build produces.
# A historical "makefs" TOFU line in versions-stage.txt stays: the file is
# append-only and this script only upserts its own names.)
#
# Staging route: a REAL git repository at the pinned commit (design A, user
# decision 2026-10-15 - superseding the retired codeload-tarball route).
# cheribuild cannot accept a non-git tree at all: Project.update() calls
# ensure_cloned() BEFORE its `if skip_update: return`
# (project.py:1354-1362) and GitRepository.ensure_cloned clones whenever
# (src_dir/".git") is absent (repository.py:371-390), so --skip-update can
# never stop it and --skip-clone only turns it into a fatal - proven by
# executing hosted Step 5, which died with `git clone ... sources/qemu:
# destination path already exists and is not an empty directory`.
# Each tree is therefore staged as
#   git init + git remote add origin <git-url>
#   + git fetch --depth 1 origin <commit> + git checkout --detach FETCH_HEAD
# (the sequence verified on build/cheri/scratch/gitprobe-1 before adoption).
# Hardening:
#   - every commit pin asserted 40-hex and every URL pin asserted to be the
#     expected github.com git remote before use (die naming the variable);
#   - fetches retried 3 times so a transient network failure is
#     distinguishable from a hard failure in the log;
#   - the staged commit's tree hash (git rev-parse HEAD^{tree}) is
#     TOFU-recorded in build/cheri/versions-stage.txt - at most one line per
#     pin name; a second run for the same pin appends nothing;
#   - idempotent: a dest that already IS a git repo checked out at the pin
#     (live `git rev-parse HEAD` equals the pin) is reused, never re-fetched;
#     a pin bump or a non-git leftover dest (e.g. the retired tarball
#     extracts) replaces the dest and refreshes that pin's TOFU line;
#   - the replacement rm -rf of build/cheri/sources/<name> is sanctioned:
#     the dest is a gitignored build artifact, and the plan's Rollback
#     section documents rm -rf build/cheri/{sources,output,build} as the
#     reclamation path;
#   - takes the shared lane lock ($BUILD_DIR/.lane.lock, flock -n, fail
#     fast naming the holder) exactly as the build scripts do - it writes
#     the shared sources/ tree and the TOFU record, and an unlocked staging
#     run could interleave with a lane build.
#
# version_stamp.sh truncates its output file, so this script never invokes
# it on versions-stage.txt - the TOFU lines below are the whole record.

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
# shellcheck source=../../env.sh
. ./env.sh

die() { echo "cheri/stage_sources: $*" >&2; exit 1; }

CHERI_BROOT="$ROOT/$BUILD_DIR/cheri"
SRC_ROOT="$CHERI_BROOT/sources"
TOFU="$CHERI_BROOT/versions-stage.txt"

# ---- pin assertions (before any use, before any network) ----
assert_commit_pin() { # varname
  local name=$1 value=${!1:-}
  [ -n "$value" ] || die "$name is empty - set it in env.sh"
  case "$value" in
    *[!0-9a-f]*) die "$name=$value is not a 40-hex commit id (^[0-9a-f]{40}$)" ;;
  esac
  [ "${#value}" -eq 40 ] || die "$name=$value is not a 40-hex commit id (^[0-9a-f]{40}$)"
}
assert_git_url() { # varname expected-prefix
  local name=$1 value=${!1:-} prefix=$2
  [ -n "$value" ] || die "$name is empty - set it in env.sh"
  case "$value" in
    "$prefix"*) ;;
    *) die "$name=$value is not the $prefix git remote" ;;
  esac
}

assert_commit_pin CHERI_QEMU_COMMIT
assert_commit_pin CHERIBSD_SRC_COMMIT
assert_commit_pin BBL_SRC_COMMIT
assert_git_url CHERI_QEMU_URL "https://github.com/CHERI-Alliance/qemu"
assert_git_url CHERIBSD_SRC_URL "https://github.com/CTSRD-CHERI/cheribsd"
assert_git_url BBL_SRC_URL "https://github.com/CTSRD-CHERI/"

# ---- shared lane lock (released when this script exits) ----
mkdir -p "$ROOT/$BUILD_DIR"
exec 9>"$ROOT/$BUILD_DIR/.lane.lock"
if ! flock -n 9; then
  die "lane busy: $(cat "$ROOT/$BUILD_DIR/.lane.lock" 2>/dev/null || echo unknown) holds $BUILD_DIR/.lane.lock"
fi
printf '%s\n' "cheri/stage_sources" > "$ROOT/$BUILD_DIR/.lane.lock"

# ---- stage one tree as a git repo at the pin (TOFU: one line per pin name) ----
stage_tree() { # name url commit destdir
  local name=$1 url=$2 commit=$3 destdir=$4
  local head tree attempt

  # reuse only a REAL git repo already checked out at the pin - a
  # tarball-extracted tree (no .git) or any other commit falls through to
  # the staging path below, which replaces the dest
  if [ -d "$destdir/.git" ] &&
     head=$(git -C "$destdir" rev-parse HEAD 2>/dev/null) &&
     [ "$head" = "$commit" ]; then
    echo "cheri/stage_sources: $name already at $commit - reusing $destdir"
    return 0
  fi

  rm -rf "$destdir"
  mkdir -p "$destdir"
  git init "$destdir"
  git -C "$destdir" remote add origin "$url"
  for attempt in 1 2 3; do
    if git -C "$destdir" fetch --depth 1 origin "$commit"; then
      break
    fi
    echo "cheri/stage_sources: network failure fetching $url @ $commit (attempt $attempt/3)" >&2
    if [ "$attempt" -eq 3 ]; then
      die "FETCH FAILED after 3 attempts: $url @ $commit (tree $name)"
    fi
    sleep $((attempt * 2))
  done
  git -C "$destdir" checkout --detach FETCH_HEAD

  # the staged tree must BE the pin - a fetch that resolved to anything else
  # is a hard stop naming the tree, not a warning
  head=$(git -C "$destdir" rev-parse HEAD)
  [ "$head" = "$commit" ] ||
    die "$name: staged HEAD $head != pin $commit in $destdir"

  # upsert the TOFU line: at most one line per pin name, ever; the third
  # field is the staged commit's TREE hash (the retired codeload route's
  # tarball sha256 no longer exists)
  tree=$(git -C "$destdir" rev-parse 'HEAD^{tree}')
  mkdir -p "$CHERI_BROOT"
  if [ -f "$TOFU" ]; then
    grep -v "^$name " "$TOFU" > "$TOFU.tmp" || true
    mv "$TOFU.tmp" "$TOFU"
  fi
  printf '%s %s %s %s\n' "$name" "$commit" "$tree" "$url" >> "$TOFU"
  echo "cheri/stage_sources: staged $name@$commit -> $destdir (tree $tree)"
}

stage_tree qemu "$CHERI_QEMU_URL" "$CHERI_QEMU_COMMIT" "$SRC_ROOT/qemu"
stage_tree cheribsd "$CHERIBSD_SRC_URL" "$CHERIBSD_SRC_COMMIT" "$SRC_ROOT/cheribsd"
stage_tree bbl "$BBL_SRC_URL" "$BBL_SRC_COMMIT" "$SRC_ROOT/bbl"

echo "cheri/stage_sources: ok - three git trees under $SRC_ROOT, TOFU record $TOFU"
