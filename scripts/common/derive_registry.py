#!/usr/bin/env python3
"""derive_registry.py - deploy-time derived registry + manifest skeleton.

Usage:
    derive_registry.py --lane LANE --registry PATH --out-dir DIR

Reads the tracked bench registry (benchmark/configure.json) and writes:

  DIR/configure.json  the derived registry: every program with 2+ distinct
                      conf-macro maps gets one unit name per map,
                      <prog>__<key>, where key is FNV-1a-32 of the canonical
                      map string (sorted "K=V" pairs, comma-joined; empty map
                      hashes to 811c9dc5); programs the lane's SKIP_TABLE row
                      declares skip are marked skip with a reason (their unit
                      files do not exist and are never staged) - the "*" row
                      is the deferred disable_independent_assembly translation,
                      lane rows are recorded corpus build failures.

  DIR/manifest.json   the manifest SKELETON: bench_commit, lane,
                      expected_failures, units[] (one entry per STAGED unit -
                      143 on the shared lanes, fewer where a lane row removes
                      programs - as {program, map, file, status:"pending"})
                      and side_files[] derived from the records' argument
                      strings (paths under test/); build_corpus.sh finalizes
                      it in place with sha256/mode/status.

The unit key scheme matches the bench plan's corpus mode so a future
bench-side implementation can replace this 1:1.  Python stdlib only.
"""

import argparse
import hashlib
import json
import os
import sys

# The two programs whose assembly_return_site translation is deferred; their
# records are declared skip and their units are not staged (see the bench's
# deferred issue indepassembly-return-site-untranslated).
EXPECTED_FAILURES = [
    "cfi-return-to-parent-non-call-site-by-asmfunc",
    "cfi-return-to-peer-asmfunc",
]
SKIP_REASON = (
    "independent assembly not translated on this platform; build fails under "
    "disable_independent_assembly (deferred issue "
    "indepassembly-return-site-untranslated)"
)

# Lane tokens that equal a bench ARCH token (the skip lists and CSB_TARGET_ARCH
# must use the same spelling the bench Makefile bakes).
VALID_LANES = {"x86_64", "aarch64", "riscv64", "cheri_riscv64"}

# Deploy-time skip table, keyed by ENV lane name (the --env-lane argument;
# defaults to --lane, so non-CHERI callers are unchanged).  A program listed
# under a lane's key is declared skip for THAT lane only; the "*" row applies to
# every lane.  The asmfunc deferral is a "*" row, so the riscv64 derived output
# stays byte-identical.  The lane rows below are the tester's bucket-(a) build
# failures (the only skip candidates; the emitted skip token is still the bench
# token, --lane).  Evidence:
# tmp/verification/2026-10-14-cheri-lanes-bringup-classification.json.
CLASSIFICATION_ARTIFACT = (
    "tmp/verification/2026-10-14-cheri-lanes-bringup-classification.json"
)
SKIP_TABLE = {
    "*": {p: SKIP_REASON for p in EXPECTED_FAILURES},
    "cheri_riscv64": {
        "acc-get-frame-size": (
            "corpus unit fails to build on cheri_riscv64 (GET_SP_LOC undeclared "
            "against the pinned sysroot); the run records raw result 2 with "
            "unit status build-failed (" + CLASSIFICATION_ARTIFACT + ")"
        ),
        "mss-write-by-stack-pointer": (
            "corpus unit fails to build on cheri_riscv64 (inline-asm constraint "
            "'C' unavailable in the pinned clang); the run records raw result 2 "
            "with unit status build-failed (" + CLASSIFICATION_ARTIFACT + ")"
        ),
    },
    "aarch64-morello": {
        "cfi-call-mid-func": (
            "corpus unit fails to build on aarch64-morello (LLVM backend crash: "
            "Should only get a blockaddress for the current function); the run "
            "records raw result 2 with unit status build-failed ("
            + CLASSIFICATION_ARTIFACT + ")"
        ),
    },
}


def skip_reason(env_lane, prog):
    """The skip-reason for `prog` under the ENV lane, or None."""
    for key in (env_lane, "*"):
        row = SKIP_TABLE.get(key)
        if row and prog in row:
            return row[prog]
    return None

FNV_OFFSET = 0x811C9DC5
FNV_PRIME = 0x01000193


def fnv1a32(text):
    h = FNV_OFFSET
    for b in text.encode("utf-8"):
        h = ((h ^ b) * FNV_PRIME) & 0xFFFFFFFF
    return "%08x" % h


def canonical(m):
    return ",".join("%s=%s" % (k, m[k]) for k in sorted(m))


def unit_key(canonical_str):
    return fnv1a32(canonical_str)


def side_candidates(record):
    """Repo-relative paths under test/ mentioned in a record's arguments."""
    out = set()
    for key in ("arguments", "default_args"):
        val = record.get(key)
        if val is None:
            continue
        items = []
        if isinstance(val, dict):
            for v in val.values():
                items.extend(v if isinstance(v, list) else [v])
        elif isinstance(val, list):
            items.extend(val)
        else:
            items.append(val)
        for s in items:
            if isinstance(s, str):
                s2 = s[2:] if s.startswith("./") else s
                if s2.startswith("test/"):
                    out.add(s2)
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="derive the per-unit registry and manifest skeleton "
                    "from the tracked bench registry")
    ap.add_argument("--lane", required=True, help="bench ARCH token (skip-list spelling)")
    ap.add_argument("--env-lane", default=None,
                    help="env lane name for the skip table; defaults to --lane")
    ap.add_argument("--registry", required=True, help="path to the tracked configure.json")
    ap.add_argument("--out-dir", required=True, help="directory for configure.json + manifest.json")
    args = ap.parse_args(argv)

    if args.lane not in VALID_LANES:
        sys.exit("derive_registry: unknown --lane %r (expected one of %s)"
                 % (args.lane, ", ".join(sorted(VALID_LANES))))
    env_lane = args.env_lane or args.lane

    with open(args.registry, "r", encoding="utf-8") as fh:
        registry = json.load(fh)

    # Group canonical maps per program; a record must never span maps (the
    # deploy-time unit model relies on it).
    prog_maps = {}
    record_map = {}
    for rec, r in registry.items():
        prog = r.get("program", rec)
        cm = r.get("conf-macro") or {}
        maps = {canonical(v) for v in cm.values()} if cm else {""}
        if len(maps) > 1:
            sys.exit("derive_registry: record %r spans %d conf-macro maps - "
                     "the derived-registry design requires <=1" % (rec, len(maps)))
        record_map[rec] = sorted(maps)[0]
        prog_maps.setdefault(prog, set()).update(maps)

    # Unit naming: single-map programs keep their name, multi-map programs get
    # <prog>__<key> per map.
    prog_units = {}
    for prog, maps in prog_maps.items():
        if len(maps) == 1:
            prog_units[prog] = {sorted(maps)[0]: prog}
        else:
            prog_units[prog] = {m: "%s__%s" % (prog, unit_key(m)) for m in maps}

    # Derived registry: rewrite multi-unit program names; declare the lane's
    # skipped programs skip.
    derived = {}
    for rec, r in registry.items():
        out = dict(r)
        prog = r.get("program", rec)
        out["program"] = prog_units[prog][record_map[rec]]
        reason = skip_reason(env_lane, prog)
        if reason is not None:
            out["skip"] = [args.lane]
            out["skip-reason"] = reason
        derived[rec] = out

    # Manifest skeleton: one entry per STAGED unit (a program skipped for this
    # lane produces no file and no units entry).
    units = []
    for prog in sorted(prog_units):
        if skip_reason(env_lane, prog) is not None:
            continue
        for mp in sorted(prog_maps[prog]):
            unit = prog_units[prog][mp]
            units.append({
                "program": prog,
                "map": mp,
                "file": "test/" + unit,
                "status": "pending",
            })
    units.sort(key=lambda u: u["file"])

    # Side files: derived from the records' argument strings, never hard-coded.
    side = set()
    for r in registry.values():
        side |= side_candidates(r)
    side_files = [{"file": f, "status": "pending"} for f in sorted(side)]

    manifest = {
        "bench_commit": os.environ.get("BENCH_COMMIT", ""),
        "lane": args.lane,
        "expected_failures": sorted(EXPECTED_FAILURES),
        "units": units,
        "side_files": side_files,
        "toolchain": {
            "arch": os.environ.get("ARCH", args.lane),
            "cxx": os.environ.get("CXX", ""),
            "asm": os.environ.get("ASM", ""),
            "objdump": os.environ.get("OBJDUMP", ""),
        },
    }

    os.makedirs(args.out_dir, exist_ok=True)
    with open(os.path.join(args.out_dir, "configure.json"), "w", encoding="utf-8") as fh:
        json.dump(derived, fh, indent=2, sort_keys=False)
        fh.write("\n")
    with open(os.path.join(args.out_dir, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
        fh.write("\n")

    n_units_all = sum(len(v) for v in prog_maps.values())
    print("derive_registry: %d records, %d programs, %d units enumerated, "
          "%d staged-unit entries, %d expected failures, %d side files -> %s"
          % (len(registry), len(prog_maps), n_units_all, len(units),
             len(EXPECTED_FAILURES), len(side_files), args.out_dir))


if __name__ == "__main__":
    main()
