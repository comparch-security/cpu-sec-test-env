# CLAUDE.md

Project-level guidance for Claude Code and its subagents working in this repository.

## Purpose

The lane dispatcher that builds and runs the cpu-sec-bench security benchmark on every
supported architecture from one repository: x86_64 (native host processes — the reference
lane), aarch64 (through the kernel's binfmt handler under qemu-aarch64, with pa/bti/mte
variants), riscv64 (a Linux guest under qemu-system-riscv64), and the two CheriBSD lanes,
cheri_riscv64 and aarch64-morello. The benchmark itself lives in the `benchmark/` submodule,
consumed read-only at the commit pinned in `env.sh`.

## Rules

- **One lane at a time.** Every lane entry point that mutates the bench worktree — the
  run and clean paths, and the corpus-staging deploy legs — takes an advisory flock on
  `build/.lane.lock` and fails fast naming the holder (`dump` is the exception: it takes
  no lock). Every lane run, success or failure, collects its artifacts into `results/`,
  cleans the submodule and asserts it is clean; a run that hits its timeout (exit 124)
  publishes nothing.
- **All pins live in `env.sh` only.** The Makefile and the scripts never hard-code a pin,
  and this file never restates pin values — README's "Pins" table is the prose copy, kept
  in sync by the hooks below.
- **`benchmark/` is read-only at the pin.** Never edit inside the submodule from this
  repo: bench-side changes land in the bench repo and are consumed here by bumping
  `BENCH_COMMIT` in `env.sh`.
- **Never commit generated or machine-local trees.** `build/` and `results/` are
  generated; `tmp/` (plans, reports, verification scripts) is machine-local. All three
  are gitignored.
- **Deferred issues live as `./tmp/reports/defer-issue-*.json`** — presence means open.
  Record them with `/defer-issue` and retire them through `/update-and-commit`; never
  create or delete a report by hand.

## Structure

```
Makefile                    the dispatcher — `make ARCH=<lane> <target>`
env.sh                      every pin, URL, timeout and root — the single source of truth
scripts/
  common/                   shared machinery: derive_registry.py, build_corpus.sh,
                            shim.sh, version_stamp.sh
  aarch64/                  prepare.sh / run.sh — the binfmt lane (+ pa/bti/mte variants)
  riscv64/                  kernel + busybox + rootfs image builders; run.sh
  cheri/                    source staging, toolchain/emulator/image builds,
                            console driver, dialect probe
  cheri_riscv64/  morello/  prepare.sh / run.sh for the two CheriBSD lanes
benchmark/                  cpu-sec-bench submodule — read-only at the env.sh pin
plans/                      archived implementation plans (the design record)
build/  results/            generated lane trees and result stamps (gitignored)
tmp/                        machine-local plans/reports/verification (gitignored)
```

## Commands

```bash
make ARCH=<lane> [enable_aarch64_<pa|bti|mte>=yes] <deploy|run|clean|dump>
```

- `ARCH` defaults to the host architecture. The host lanes' `run` does everything;
  riscv64 and the CHERI lanes are `deploy` first, then `run`.
- Every lane run carries its own `timeout` (`LANE_RUN_TIMEOUT`); the system lanes'
  deploy legs carry `LANE_DEPLOY_TIMEOUT`, and the CHERI emulator and image builds carry
  `CHERI_BUILD_TIMEOUT` (a cold CHERI deploy is a world build — hours).
- `deploy` re-checks its pinned items and fails fast when one is missing.
- `dump` delegates to the bench's own dump target; the riscv64 and both CHERI lanes
  refuse by design — their binaries live inside the guest image.

## Architecture

- The Makefile reads the few `env.sh` values its recipes need and dispatches to
  `scripts/<lane>/` (the x86_64 lane is implemented inline in the Makefile). The system
  lanes' deploy derives the lane's registry (`scripts/common/derive_registry.py` —
  per-lane skips and expected failures are declared at deploy time, never hard-coded)
  and stages the corpus (`scripts/common/build_corpus.sh`, which also writes
  `manifest.json`); the host lanes build only their scheduler and compile the corpus on
  demand during the run.
- The aarch64 lanes execute the host-built corpus through the kernel's binfmt handler
  under qemu-aarch64; `scripts/common/shim.sh` puts the lane-appropriate tool shim
  (notably the objdump the bench's opcode extraction calls) first on `PATH`.
- The riscv64 lane boots a byte-reproducible guest image under qemu-system-riscv64 and
  extracts results over a virtio-9p share; the CHERI lanes boot pinned CheriBSD images
  (riscv64: bbl firmware plus an external kernel; Morello: UEFI and `loader(8)` — no
  `-kernel`) and hand the corpus in over virtio-9p. Per-lane mechanics:
  [doc/lanes.html](doc/lanes.html).
- Provenance: every stamp's `versions.txt` is the host record (pins, dpkg versions,
  `uname`); on the riscv64 lane the guest-side truth is the guest's own
  `test/sys_info.txt`.
- Trust boundary: the corpus is adversarial by design. The host lanes run it unsandboxed
  with the invoking user's privileges — deliberately, and only on this workstation; the
  VM lanes are isolated by disposable `-snapshot` guests. Do not repoint a host lane at
  an untrusted corpus without adding isolation first.

## Documentation

- [README.md](README.md) — user-facing reference: prerequisites, per-lane usage, output
  layout, pins, trust boundary, known caveats. **(keep in sync — see Update and Commit)**
- [doc/content.html](doc/content.html) — documentation landing page.
- [doc/architecture.html](doc/architecture.html) — how the lane dispatcher works.
  **(keep in sync with the Makefile and `scripts/`)**
- [doc/lanes.html](doc/lanes.html) — the per-lane reference.
  **(keep in sync with `env.sh` and `scripts/`)**
- [doc/style.css](doc/style.css) — the shared stylesheet for the tree.
- [plans/](plans/) — archived implementation plans — the design record for every cycle.

## Update and Commit

- **Pins changed in `env.sh`** (bench commit, toolchains, qemu, kernel, busybox,
  cheribuild): update README's "Pins" table, any pin/stamp claims in its "Known
  caveats" — stamps that predate a bump must stay honestly marked — and the pin
  rationale in `doc/lanes.html`.
- **Lane set, variant flags or make targets changed:** update README's lane bullets and
  Usage table, this file's Structure and Commands sections, and the matching text in the
  keep-in-sync pages (`doc/architecture.html`, `doc/lanes.html`, and `doc/content.html`'s
  lane table).
- **Before concluding any commit:** `git -C benchmark rev-parse HEAD` equals `env.sh`'s
  `BENCH_COMMIT`, and `git -C benchmark status --short` is empty.
- **Deferred issues:** record with `/defer-issue`; retire through `/update-and-commit` —
  presence of `./tmp/reports/defer-issue-*.json` means open.

## Subagents

Lane boundaries for the rounds working this repo (the repo's product is the lane harness,
not a source tree):

- **Coder — the harness:** `scripts/`, `Makefile`, `env.sh`.
- **Tester — verification:** `./tmp/verification/` scripts, lane runs and their evidence,
  session reports.
- **Planner — documentation:** `README.md`, `CLAUDE.md`, `doc/**`, `plans/`.
- Anything inside `benchmark/` belongs to the bench repo's own cycles, never this repo's
  rounds.