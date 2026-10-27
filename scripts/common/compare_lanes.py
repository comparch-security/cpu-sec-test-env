#!/usr/bin/env python3
"""compare_lanes.py - the pin-uniform, cross-lane comparison gate.

Every selected lane contributes one stamp under results/<lane>/ (the newest
directory by name that carries a versions.txt at its top, or the one named with
--stamp; retirement directories without one are never candidates).  A stamp is
comparable only
when it records the pin this checkout pins (env.sh's BENCH_COMMIT), the same
bench checkout (bench-head equal to the pin, bench-tree the pin's tree and not
-dirty), a finished run (run-status: ok) and a parseable results.json object.
The registry is read from the object store at that pin
(`git show <pin>:configure.json`), so the classification source is pinned by
construction and immune to checkout drift.

Verdict vocabulary (closed):
  clean                     result 0
  declared                  the record's expect-results declares this code
  not-run-skipped           result 1025 with no make-status (a declared skip)
  build-failed              result 1025 with a make-status (named in the report)
  prerequisite-unsatisfied  result 1024 (an incomplete measurement)
  missing-from-lane         a registry record with no row in this lane
  extra-record              a lane row that is not a registry record
  class-masked              result 99 on a set-var producer, HWASan lane only
                            (the calibration producer the HWASan build aborts
                            before it can measure; scoped to a stamp whose flag
                            line is enable_aarch64_mte=yes)

Exit contract:
  0  every selected lane is complete and every row is clean / declared /
     not-run-skipped / class-masked
  1  a gate-failing row, an absent lane without --allow-absent, or a lane whose
     run-status is failed - the finding is dispositioned, never bypassed
  2  an input or configuration refusal (mixed pin, missing reference, unreadable
     registry or pin, a non-comparable selected stamp, a malformed CLI)

Outputs comparison.json (machine) and comparison.md (human) under --out.
stdlib only; the single shell-out is `git`.
"""

import argparse
import datetime
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# The seven executable lanes; the two CHERI lanes exist but are not part of the
# pin-uniform default set (passing one explicitly is legal and refuses on its
# own pin mismatch).
LANES = (
    "x86_64", "aarch64", "aarch64-pa", "aarch64-bti", "aarch64-mte",
    "riscv64", "riscv64-nemu",
)
CHERI_LANES = ("cheri_riscv64", "aarch64-morello")
KNOWN_LANES = LANES + CHERI_LANES

BENIGN = {"clean", "declared", "not-run-skipped", "class-masked"}
GATE_FAILING = {
    "out-of-expect", "build-failed", "prerequisite-unsatisfied",
    "missing-from-lane", "extra-record",
}

PIN_RE = re.compile(r"^BENCH_COMMIT=([0-9a-fA-F]{40})$", re.M)
HEAD_RE = re.compile(r"^bench-head:[ \t]*(.*)$", re.M)
TREE_RE = re.compile(r"^bench-tree:[ \t]*(.*)$", re.M)
STATUS_RE = re.compile(r"^run-status:[ \t]*(.*)$", re.M)
FLAG_RE = re.compile(r"^(enable_[A-Za-z0-9_]+)=yes$", re.M)
FAILED_RE = re.compile(r"^failed \(rc=([0-9]+)\)$")


class Refusal(Exception):
    """An input or configuration refusal (exit 2)."""


def sanitize(text):
    """Strip control characters from a recorded string before rendering it."""
    if not isinstance(text, str):
        text = str(text)
    return "".join(ch for ch in text if ch == "\t" or (ch >= " " and ch != "\x7f"))


def main(argv=None):
    args = parse_args(argv)
    try:
        report = compare(args)
    except Refusal as exc:
        print("compare_lanes: %s" % exc, file=sys.stderr)
        return 2
    write_outputs(args.out, report)
    print_summary(report, args.out)
    return report["gate"]["exit"]


# ---------------------------------------------------------------- CLI ------

def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="compare_lanes.py",
        description="Compare the latest stamps of the bench lanes at one pin.",
    )
    parser.add_argument(
        "--lanes", default=",".join(LANES),
        help="comma-separated lane list (default: the seven executable lanes)",
    )
    parser.add_argument(
        "--stamp", action="append", default=[], metavar="LANE=DIR",
        help="use DIR as LANE's stamp instead of the newest under results/LANE "
             "(relative paths resolve against the repository root; repeatable)",
    )
    parser.add_argument(
        "--reference", default="x86_64",
        help="the lane every other lane's codes are compared against (default: x86_64)",
    )
    parser.add_argument(
        "--allow-absent", action="append", default=[], metavar="LANE",
        help="record LANE as deliberately absent instead of gate-failing (repeatable)",
    )
    parser.add_argument(
        "--out", default=None,
        help="output directory (default: results/comparison-<UTC>-<pid>)",
    )
    parser.add_argument(
        "--max-bytes", type=int, default=8 * 1024 * 1024, metavar="N",
        help="maximum accepted results.json size (default: 8388608)",
    )
    args = parser.parse_args(argv)

    try:
        lanes = parse_lanes(args.lanes)
        overrides = parse_overrides(args.stamp)
        allow_absent = []
        for lane in args.allow_absent:
            lane = lane.strip()
            if lane not in KNOWN_LANES:
                raise Refusal("--allow-absent names unknown lane %r" % lane)
            if lane not in allow_absent:
                allow_absent.append(lane)
        for lane in overrides:
            if lane not in lanes:
                raise Refusal("--stamp names lane %r, which is not selected by --lanes" % lane)
        if args.reference not in lanes:
            raise Refusal("the reference lane %r is not in the selected lanes (%s)"
                          % (args.reference, ",".join(lanes)))
        if args.max_bytes <= 0:
            raise Refusal("--max-bytes must be a positive integer (got %d)" % args.max_bytes)
    except Refusal as exc:
        parser.error(str(exc))

    args.lane_list = lanes
    args.overrides = overrides
    args.allow_absent = allow_absent
    args.now = datetime.datetime.now(datetime.timezone.utc)
    if args.out is None:
        args.out = os.path.join(
            "results",
            "comparison-%s-%d" % (args.now.strftime("%Y%m%dT%H%M%SZ"), os.getpid()),
        )
    return args


def parse_lanes(text):
    lanes = []
    for lane in text.split(","):
        lane = lane.strip()
        if not lane:
            continue
        if lane not in KNOWN_LANES:
            raise Refusal("unknown lane %r (known: %s)" % (lane, ", ".join(KNOWN_LANES)))
        if lane not in lanes:
            lanes.append(lane)
    if not lanes:
        raise Refusal("--lanes selected no lane")
    return lanes


def parse_overrides(items):
    overrides = {}
    for item in items:
        lane, sep, path = item.partition("=")
        lane, path = lane.strip(), path.strip()
        if not sep or not lane or not path:
            raise Refusal("--stamp expects LANE=DIR (got %r)" % item)
        if lane not in KNOWN_LANES:
            raise Refusal("--stamp names unknown lane %r" % lane)
        if lane in overrides:
            raise Refusal("--stamp names lane %r twice" % lane)
        overrides[lane] = path
    return overrides


# ------------------------------------------------------------ inputs ------

def read_pin():
    path = os.path.join(ROOT, "env.sh")
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError as exc:
        raise Refusal("cannot read %s: %s" % (path, exc.strerror))
    pins = PIN_RE.findall(text)
    if len(pins) != 1:
        raise Refusal(
            "env.sh must carry exactly one BENCH_COMMIT=<40-hex> assignment line "
            "(found %d)" % len(pins))
    return pins[0].lower()


def read_registry(pin):
    proc = subprocess.run(
        ["git", "-C", os.path.join(ROOT, "benchmark"), "show", "%s:configure.json" % pin],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    if proc.returncode != 0:
        raise Refusal(
            "cannot read the registry at pin %s from the object store "
            "('git -C benchmark show %s:configure.json' rc=%d): %s"
            % (pin, pin, proc.returncode, proc.stderr.strip()))
    try:
        registry = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise Refusal("the registry at pin %s is not parseable JSON: %s" % (pin, exc))
    if not isinstance(registry, dict):
        raise Refusal("the registry at pin %s is not a JSON object" % pin)
    return registry


def stamp_dir_for(lane, overrides):
    if lane in overrides:
        path = overrides[lane]
        if not os.path.isabs(path):
            path = os.path.join(ROOT, path)
        if not os.path.isdir(path):
            raise Refusal("lane %s: --stamp %s is not a directory" % (lane, path))
        return path
    base = os.path.join(ROOT, "results", lane)
    if not os.path.isdir(base):
        return None
    # A stamp is a directory carrying versions.txt at its top; anything else
    # (notably the plan-mandated results/<lane>/retired-<pin>/ retirement
    # directories, whose names sort after every timestamp) is not a candidate.
    names = [name for name in os.listdir(base)
             if os.path.isfile(os.path.join(base, name, "versions.txt"))]
    if not names:
        return None
    return os.path.join(base, max(names))


def load_stamp(lane, stamp_dir, pin, max_bytes):
    """Validate one stamp; refuse (exit 2) when it is not comparable."""
    name = sanitize(os.path.basename(stamp_dir))
    where = "lane %s stamp %s" % (lane, name)
    vpath = os.path.join(stamp_dir, "versions.txt")
    if not os.path.isfile(vpath):
        raise Refusal("%s: versions.txt absent - not a published stamp" % where)
    try:
        with open(vpath, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError as exc:
        raise Refusal("%s: cannot read versions.txt: %s" % (where, exc.strerror))

    pins = PIN_RE.findall(text)
    if len(pins) != 1:
        raise Refusal("%s: versions.txt carries %d BENCH_COMMIT assignment lines, expected 1"
                      % (where, len(pins)))
    stamp_pin = pins[0].lower()
    if stamp_pin != pin:
        raise Refusal("%s: stamp pin %s != env.sh pin %s (mixed pin)"
                      % (where, stamp_pin, pin))

    for label, regex in (("bench-head", HEAD_RE), ("bench-tree", TREE_RE),
                         ("run-status", STATUS_RE)):
        if not regex.search(text):
            raise Refusal("%s: versions.txt does not record %s" % (where, label))

    head = HEAD_RE.search(text).group(1).strip()
    tree = TREE_RE.search(text).group(1).strip()
    status = STATUS_RE.search(text).group(1).strip()

    if head != pin:
        raise Refusal("%s: bench-head %r is not the pin %s" % (where, sanitize(head), pin))
    if "-dirty" in tree:
        raise Refusal("%s: bench-tree %r carries a -dirty marker - the results came "
                      "from an edited checkout" % (where, sanitize(tree)))
    if not (tree == pin or (7 <= len(tree) < len(pin) and pin.startswith(tree))):
        raise Refusal("%s: bench-tree %r is not the pin's tree" % (where, sanitize(tree)))

    if status == "ok":
        run_ok, run_rc = True, 0
    else:
        match = FAILED_RE.match(status)
        if not match:
            raise Refusal("%s: run-status %r is neither 'ok' nor 'failed (rc=N)'"
                          % (where, sanitize(status)))
        run_ok, run_rc = False, int(match.group(1))

    rpath = os.path.join(stamp_dir, "results.json")
    if not os.path.isfile(rpath):
        raise Refusal("%s: results.json absent - an evidence-only stamp is not comparable"
                      % where)
    size = os.path.getsize(rpath)
    if size > max_bytes:
        raise Refusal("%s: results.json is %d bytes, over the %d-byte cap"
                      % (where, size, max_bytes))
    try:
        with open(rpath, encoding="utf-8") as fh:
            results = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        raise Refusal("%s: results.json is not parseable JSON: %s" % (where, exc))
    if not isinstance(results, dict):
        raise Refusal("%s: results.json is not a JSON object" % where)

    flag_match = FLAG_RE.search(text)
    return {
        "lane": lane,
        "stamp": name,
        "pin": stamp_pin,
        "bench_head": sanitize(head),
        "bench_tree": sanitize(tree),
        "run_status": sanitize(status),
        "run_ok": run_ok,
        "run_rc": run_rc,
        "flag": flag_match.group(1) if flag_match else None,
        "absent": False,
        "results": results,
    }


# ------------------------------------------------------- classification ------

def classify(record, entry, registry, flag):
    """One record's verdict and its human detail."""
    code = entry["result"]
    if code == 0:
        return "clean", None
    if code == 1025:
        if "make-status" in entry:
            return "build-failed", "make-status %s" % sanitize(entry.get("make-status"))
        return "not-run-skipped", None
    if code == 1024:
        return "prerequisite-unsatisfied", None
    if code == 99 and "set-var" in (registry.get(record) or {}) \
            and flag == "enable_aarch64_mte":
        return "class-masked", None
    declared = (registry.get(record) or {}).get("expect-results") or {}
    meaning = declared.get(str(code))
    if meaning is not None:
        return "declared", sanitize(meaning)
    return "out-of-expect", None


def validate_results(lane, stamp_name, results, registry):
    for record, entry in results.items():
        where = "lane %s stamp %s record %s" % (lane, stamp_name, sanitize(record))
        if not isinstance(entry, dict):
            raise Refusal("%s is not a JSON object" % where)
        if "result" not in entry:
            raise Refusal("%s carries no result" % where)
        value = entry["result"]
        if isinstance(value, bool) or not isinstance(value, int) \
                or not 0 <= value <= 2047:
            raise Refusal("%s carries result %r, not an integer in 0-2047"
                          % (where, value))


def lane_rows(stamp, registry):
    """The lane's record rows keyed by record name, registry-ordered later."""
    validate_results(stamp["lane"], stamp["stamp"], stamp["results"], registry)
    rows = {}
    for record, entry in stamp["results"].items():
        if record not in registry:
            rows[record] = {"code": entry["result"], "verdict": "extra-record", "detail": None}
            continue
        verdict, detail = classify(record, entry, registry, stamp["flag"])
        rows[record] = {"code": entry["result"], "verdict": verdict, "detail": detail}
    for record in registry:
        if record not in rows:
            rows[record] = {"code": None, "verdict": "missing-from-lane", "detail": None}
    return rows


# --------------------------------------------------------------- driver ------

def compare(args):
    pin = read_pin()
    registry = read_registry(pin)

    lanes = {}
    findings = []
    for lane in args.lane_list:
        stamp_dir = stamp_dir_for(lane, args.overrides)
        allowed_absent = lane in args.allow_absent
        if stamp_dir is None:
            lanes[lane] = {
                "lane": lane, "stamp": None, "absent": True,
                "allowed_absent": allowed_absent, "rows": {}, "verdicts": {},
            }
            if not allowed_absent:
                findings.append("lane %s is absent (no stamp under results/%s/)" % (lane, lane))
            continue
        stamp = load_stamp(lane, stamp_dir, pin, args.max_bytes)
        stamp["allowed_absent"] = allowed_absent
        stamp["rows"] = lane_rows(stamp, registry)
        counts = {}
        for row in stamp["rows"].values():
            counts[row["verdict"]] = counts.get(row["verdict"], 0) + 1
        stamp["verdicts"] = dict(sorted(counts.items()))
        lanes[lane] = stamp
        if not stamp["run_ok"]:
            findings.append("lane %s stamp %s: run-status failed (rc=%d)"
                            % (lane, stamp["stamp"], stamp["run_rc"]))
        for record, row in stamp["rows"].items():
            if row["verdict"] in GATE_FAILING:
                findings.append(
                    "lane %s stamp %s: record %s: %s (code %s%s)"
                    % (lane, stamp["stamp"], sanitize(record), row["verdict"],
                       "null" if row["code"] is None else row["code"],
                       ", " + row["detail"] if row["detail"] else ""))

    reference = lanes[args.reference]
    if reference.get("absent"):
        raise Refusal("the reference lane %r has no stamp" % args.reference)

    report = {
        "tool": "scripts/common/compare_lanes.py",
        "generated": args.now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "pin": pin,
        "reference": args.reference,
        "lanes": [flatten_lane(lanes[lane]) for lane in args.lane_list],
        "absent_lanes": [lane for lane in args.lane_list if lanes[lane]["absent"]],
        "allowed_absent": [lane for lane in args.lane_list
                           if lanes[lane].get("allowed_absent")],
        "divergences": divergence_matrix(args.lane_list, lanes, args.reference),
        "gate": {"exit": 1 if findings else 0, "findings": findings},
    }
    return report


def flatten_lane(stamp):
    entry = {
        "lane": stamp["lane"],
        "stamp": stamp["stamp"],
        "absent": stamp["absent"],
        "allowed_absent": stamp.get("allowed_absent", False),
    }
    if stamp["absent"]:
        return entry
    entry.update({
        "pin": stamp["pin"],
        "bench_head": stamp["bench_head"],
        "bench_tree": stamp["bench_tree"],
        "run_status": stamp["run_status"],
        "flag": stamp["flag"],
        "records": len(stamp["rows"]),
        "verdicts": stamp["verdicts"],
    })
    return entry


def divergence_matrix(lane_list, lanes, reference):
    """Rows where any stamped lane's code differs from the reference's."""
    present = [lane for lane in lane_list if not lanes[lane]["absent"]]
    records = set()
    for lane in present:
        records.update(lanes[lane]["rows"])
    ref_rows = lanes[reference]["rows"]
    matrix = []
    for record in sorted(records):
        codes = {}
        for lane in present:
            row = lanes[lane]["rows"].get(record)
            codes[lane] = row["code"] if row else None
        ref_code = codes[reference]
        if all(codes[lane] == ref_code for lane in present):
            continue
        detail = None
        for lane in present:
            row = lanes[lane]["rows"].get(record)
            if row and row["detail"]:
                detail = row["detail"]
                break
        matrix.append({
            "record": sanitize(record),
            "declared-meaning": detail,
            "codes": codes,
        })
    return matrix


# --------------------------------------------------------------- output ------

def write_outputs(out_dir, report):
    path = out_dir if os.path.isabs(out_dir) else os.path.join(ROOT, out_dir)
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "comparison.json"), "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2, sort_keys=False)
        fh.write("\n")
    with open(os.path.join(path, "comparison.md"), "w", encoding="utf-8") as fh:
        fh.write(render_markdown(report))


def render_markdown(report):
    lines = [
        "# Lane comparison at %s" % report["pin"],
        "",
        "- Reference: `%s`" % report["reference"],
        "- Generated: %s" % report["generated"],
        "- Gate exit: **%d**" % report["gate"]["exit"],
        "",
        "## Lanes",
        "",
    ]
    verdicts = ["clean", "declared", "not-run-skipped", "class-masked",
                "out-of-expect", "build-failed", "prerequisite-unsatisfied",
                "missing-from-lane", "extra-record"]
    header = ["Lane", "Stamp", "Run"] + verdicts
    lines.append("| " + " | ".join(header) + " |")
    lines.append("|" + "|".join(["---"] * len(header)) + "|")
    for lane in report["lanes"]:
        if lane["absent"]:
            note = "absent (allowed)" if lane["allowed_absent"] else "absent"
            row = [lane["lane"], "-", note] + ["-"] * len(verdicts)
        else:
            row = [lane["lane"], lane["stamp"], lane["run_status"]]
            row += [str(lane["verdicts"].get(verdict, 0)) for verdict in verdicts]
        lines.append("| " + " | ".join(row) + " |")
    lines.append("")
    if report["absent_lanes"]:
        lines.append("Absent lanes: " + ", ".join(
            "`%s`%s" % (lane, " (allowed)" if lane in report["allowed_absent"] else "")
            for lane in report["absent_lanes"]))
        lines.append("")
    lines.append("## Divergences from `%s`" % report["reference"])
    lines.append("")
    if not report["divergences"]:
        lines.append("None: every stamped lane delivered the reference's codes for every record.")
    else:
        lanes = [lane["lane"] for lane in report["lanes"] if not lane["absent"]]
        lines.append("| Record | " + " | ".join("`%s`" % lane for lane in lanes) + " |")
        lines.append("|" + "|".join(["---"] * (len(lanes) + 1)) + "|")
        for row in report["divergences"]:
            cells = []
            for lane in lanes:
                code = row["codes"].get(lane)
                cells.append("null" if code is None else str(code))
            lines.append("| `%s` | %s |" % (row["record"], " | ".join(cells)))
    lines.append("")
    if report["gate"]["findings"]:
        lines.append("## Gate findings")
        lines.append("")
        for finding in report["gate"]["findings"]:
            lines.append("- %s" % finding)
        lines.append("")
    return "\n".join(lines) + "\n"


def print_summary(report, out_dir):
    print("compare_lanes: pin %s, reference %s" % (report["pin"], report["reference"]))
    for lane in report["lanes"]:
        if lane["absent"]:
            print("  %-13s absent%s"
                  % (lane["lane"], " (allowed)" if lane["allowed_absent"] else ""))
            continue
        counts = ", ".join("%s=%d" % (name, count)
                           for name, count in lane["verdicts"].items())
        print("  %-13s %s  %s" % (lane["lane"], lane["stamp"], counts))
    print("diff rows: %d; gate exit: %d; written to %s"
          % (len(report["divergences"]), report["gate"]["exit"], out_dir))


if __name__ == "__main__":
    sys.exit(main())
