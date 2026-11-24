#!/usr/bin/env bash
# fetch.sh - the shared pinned-tarball fetcher for the riscv64 guest inputs.
#
# Sourced (never executed) by scripts/riscv64/build_kernel.sh and
# scripts/riscv64/build_busybox.sh.  The function was moved here verbatim from
# the two scripts, where it was byte-identical, so the two callers share one
# implementation: a .part download, sha256 verification against the env.sh pin,
# a bounded retry with backoff on network failure, and a distinct no-retry
# report on a checksum mismatch.

# ---- fetch: .part + hash-verify + atomic rename; distinct failure modes ----
fetch() {  # name url sha256 dest
  local name=$1 url=$2 sha=$3 dest=$4 attempt
  if [ -f "$dest" ]; then
    if echo "$sha  $dest" | sha256sum -c --status -; then
      echo "$name: using verified cache $dest"
      return 0
    fi
    echo "$name: cached file fails sha256 verification, refetching: $dest" >&2
    rm -f "$dest"
  fi
  mkdir -p "$(dirname "$dest")"
  for attempt in 1 2 3; do
    if curl -fsSL --connect-timeout 30 -o "$dest.part" "$url"; then
      if echo "$sha  $dest.part" | sha256sum -c --status -; then
        mv "$dest.part" "$dest"
        echo "$name: fetched and sha256-verified $dest"
        return 0
      fi
      rm -f "$dest.part"
      echo "$name: CHECKSUM MISMATCH - downloaded content of $url does not match the env.sh pin (not a network failure; refusing to retry)" >&2
      return 1
    fi
    echo "$name: network failure fetching $url (attempt $attempt/3)" >&2
    sleep $((attempt * 2))
  done
  echo "$name: DOWNLOAD FAILED after 3 attempts: $url" >&2
  return 1
}
