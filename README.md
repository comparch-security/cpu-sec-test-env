# cpu-sec-test-env

Build and run [`cpu-sec-bench`](https://github.com/comparch-security/cpu-sec-bench)
on every supported architecture from a single repository:

- **x86_64** — native host processes (the reference lane).
- **aarch64** — the benchmark's own scheduler is a host binary; the corpus runs
  through the kernel's `binfmt_misc` handler under `qemu-aarch64`, with variants
  for pointer-authentication (`pa`), branch-target-identification (`bti`) and
  memory-tagging (`mte`). The `pa` variant requests an explicit CPU model
  (`QEMU_CPU=max` — this venue's default model *plus* PAuth), and for `pa` that
  request is what makes its build executable here at all: the default model has
  no PAuth, and the lane's PAC-ret epilogue faults without it. The `mte` variant
  requests the same model to make its claim explicit — the default already
  advertises MTE, and the old `max,mte=on` spelling was rejected outright, so it
  had never reached a guest. Every
  aarch64-family stamp **before 2026-10-25** is a non-execution record: an
  exported `QEMU_VERSION` made each case print the emulator's version and exit 0,
  so those stamps carry no test information (see *Known caveats* before comparing
  anything against them).
- **riscv64** — host-built corpus booted inside a Linux 7.3.4 guest under
  `qemu-system-riscv64` (`-M virt`), results extracted over a virtio-9p share.
  The guest boots the `fw_jump.bin` this repository builds from its pinned
  OpenSBI v1.9 (not QEMU's bundled blobs).
- **riscv64-cfi**, **riscv64-nemu-cfi** — the *armed* variants of the two lanes
  above: the same corpus built with the bench's RISC-V ISA-CFI build class
  (`enable_riscv64_cfi=yes`, GCC 16.1.0, `-march=rv64gc_zicfilp_zicfiss
  -fcf-protection=full`), so every corpus binary arms a Zicfiss shadow stack at
  startup and reports a hardware control-flow-protection violation as the CFI
  delivery codes (30 backward edge, 31 forward edge). Arming is gated on the
  **platform's** ISA advertisement, so the two variants alone boot a
  CFI-advertising platform: the qemu variant requests
  `-cpu rva23s64,zicfiss=on,zicfilp=on`, and the NEMU variant's venue DTS gains
  the two extension strings through a dtc interposer. The plain lanes keep an
  advertisement-free platform, because an advertising DT in front of an
  interpreter without the `ssp` CSR is a boot panic.
- **CHERI** — two real lanes, `cheri_riscv64` and `aarch64-morello`: purecap
  CheriBSD 15.0-CURRENT guests under CHERI-LLVM's `qemu-system-riscv64xcheri`
  and `qemu-system-morello`, booted from pinned disk images with the corpus
  handed in over a read-only virtio-9p share and results collected from a
  writable one. Both lanes run the strict corpus; the only not-run records are
  platform build failures declared in the tracked bench registry's `skip`
  rows (see *Known caveats*).
- **riscv64-nemu** — the absorbed in-repo NEMU venue package
  (`scripts/riscv64_nemu/venue/`): the host-built corpus and the
  riscv64 scheduler run inside a Linux 7.3.4 guest emulated by the workspace's
  XiangShan NEMU (`../NEMU`, commit-pinned), with results extracted from the
  guest console. Deploy-first, like the system lanes; the NEMU location is a
  relative default, so the lane follows the workspace layout without an
  absolute path in `env.sh`. The `riscv64-nemu-cfi` variant instead boots the
  workspace's CFI-verified checkout (`../NEMU-cfi`, commit- **and**
  binary-sha256-pinned).

The benchmark itself lives in the `benchmark/` git submodule
(`comparch-security/cpu-sec-bench`), consumed read-only at the commit pinned in
`env.sh`. The old `riscv-linux-sdk` submodule has been removed: the riscv64 lane
builds its own kernel, busybox and rootfs image from pinned sources.

## Prerequisites

One-time host setup (sudo needs a password, so this is a manual step):

```bash
sudo apt install qemu-system-riscv qemu-system-data qemu-user qemu-user-binfmt \
                 gcc-13-riscv64-linux-gnu g++-13-riscv64-linux-gnu \
                 gcc-13-aarch64-linux-gnu g++-13-aarch64-linux-gnu \
                 libhwasan0-arm64-cross
```

- `qemu-system-riscv` / `qemu-system-data` (10.2.1) — host-package provenance
  for the riscv64 lanes only: since the 2026-11-22 pin those lanes execute the
  source-built QEMU 11.1.3 (next bullet), so the distro packages are executed
  by no lane any more; they stay in this list and in every stamp's package
  record as host provenance. The lanes boot the `fw_jump.bin` built from the
  pinned OpenSBI, so
  `qemu-system-data`'s bundled blobs are no longer the lane's firmware source;
  the riscv64 guest kernel is built with the GCC 16.1.0 toolchain below, because
  its `CONFIG_RISCV_USER_CFI` Kconfig gate is a `cc-option` probe that gcc-13
  fails (the symbol then vanishes silently).
- The riscv64 lanes' emulator is a **one-time source build** of QEMU 11.1.3
  into `build/qemu-11.1.3/` (see Pins → QEMU). Configure
  `--target-list=riscv64-softmmu --without-default-features
  --enable-fdt=internal --disable-werror --enable-virtfs --enable-attr` and
  `ninja build/qemu-system-riscv64`; the release tarball is sha256-pinned in
  `env.sh`'s provenance comment (staged in `build/downloads/`), and the dtc
  wrap must be staged offline (copy the `subprojects/dtc` checkout from a
  verified extraction — meson would otherwise fetch it). **virtfs/9p is a hard
  requirement**: both riscv64 lanes extract their results over a virtio-9p
  share and have no fallback path, and `--without-default-features` silently
  disables the auto `attr` option the virtfs gate requires (the configure then
  dies with a misleading "requires libattr-devel" message — the headers are
  not the problem), so both feature flags are mandatory. The cycle's
  capability gate (config-host.h `CONFIG_VIRTFS` define, the
  `CONFIG_FSDEV_9P`-gated `fsdev_qemu-fsdev.c.o` object, `-device help`
  listing `virtio-9p-device`) keeps a silently virtfs-less build from ever
  passing.
- `qemu-user` + `qemu-user-binfmt` (10.2.1) — the aarch64 lane's execution path:
  every aarch64 ELF runs under `qemu-aarch64` via the kernel's binfmt handler
  (registering that handler is root-only, which is why it is in this list).
- The cross toolchains (13.4.0) build the plain riscv64 family's corpus, the
  guest image and the aarch64 corpus; `libhwasan0-arm64-cross` supplies the MTE
  lane's `-fsanitize=hwaddress` runtime.
- A built XiangShan NEMU interpreter for the `riscv64-nemu` lane: a sibling
  `NEMU` checkout resolved by the repo-relative default
  `NEMU_DIR=../NEMU` with `NEMU_BIN=$NEMU_DIR/build/riscv64-nemu-interpreter`
  built from it, at the pinned `NEMU_COMMIT`. `NEMU_DIR`/`NEMU_BIN` are one
  overridable pair (absolute paths allowed); the lane records the binary's
  sha256 and compares it run-to-run rather than pinning it, so a stale local
  build is disclosed, not silently reused.
- **GCC 16.1.0 riscv64 toolchain** (`riscv64-unknown-linux-gnu-*`) for the guest
  kernel and the two CFI variant lanes — the workspace's `riscv-gnu-toolchain`
  build, resolved by the repo-relative default
  `RISCV64_GNU_PREFIX=../riscv/bin/riscv64-unknown-linux-gnu-` (an absolute
  override wins). gcc-13 has neither Zicfilp/Zicfiss nor the user-CFI Kconfig
  gate, so the kernel and the armed corpus cannot be built with it. The plain
  lanes' corpus stays on the apt cross toolchains above.
- A CFI-verified NEMU checkout for the `riscv64-nemu-cfi` lane: a sibling
  `NEMU-cfi` at the pinned `NEMU_CFI_COMMIT` (NEMU master plus the Zicfiss/
  Zicfilp implementation, validated by the workspace's CFI research cycles),
  with `NEMU_CFI_BIN=$NEMU_CFI_DIR/build/riscv64-nemu-interpreter` — the
  binary's sha256 is a hard pin here, because an interpreter that is not the
  CFI-verified build must not publish an armed stamp.

The CHERI lanes additionally build their two emulators and their guests with the
pinned `cheribuild`, which needs five more host packages:

```bash
sudo apt install libarchive-dev libarchive-tools libpixman-1-dev \
                 libslirp-dev libcap-ng-dev
```

- `libarchive-dev` — every CheriBSD build (`pkg-config libarchive`).
- `libarchive-tools` — supplies `bsdtar` for the sysroot packaging step.
- `libpixman-1-dev`, `libslirp-dev`, `libcap-ng-dev` — the pinned QEMU build's
  system-emulation dependencies (the 9pfs block needs `libcap-ng`).

Two CheriBSD-build quirks are handled *in the repository*, so no host change is
needed: `scripts/cheri/glibc-c23-shim/` is injected as `CPATH` to neutralise
this host's glibc-2.43 C23 `strchr` macro during the world build (self-scoping —
CPATH is searched after every `-I`), and the build script unsets
`SOURCE_DATE_EPOCH` for the cheribuild invocation because BSD `newvers.sh`
validates it with `date -r <epoch>`, which GNU `date` misreads as a filename.

Also required: the bench pin (`env.sh` `BENCH_COMMIT`) must exist on the public
`comparch-security/cpu-sec-bench` remote — a clean submodule checkout resolves
exactly that commit, and the lanes depend on the machinery it carries.

Every lane's `deploy`/`prepare` step re-checks the pinned items and fails fast
naming whatever is missing.

## Usage

```bash
make ARCH=<lane> [enable_aarch64_<pa|bti|mte>=yes] [enable_riscv64_cfi=yes] <deploy|run|clean|dump>
```

The `enable_riscv64_cfi=yes` flag turns a riscv64-family lane into its armed
variant: on `ARCH=riscv64` it selects lane `riscv64-cfi`, on `ARCH=riscv64-nemu`
lane `riscv64-nemu-cfi` (it is refused on every other lane, and so is combining
it with `enable_riscv64_cheri`).

| Command | What it does |
|---|---|
| `make ARCH=x86_64 run` | Builds and runs the bench natively; results in `results/x86_64/<stamp>/` |
| `make ARCH=aarch64 run` | Plain aarch64 lane (through binfmt) |
| `make ARCH=aarch64 enable_aarch64_pa=yes run` | Pointer-auth variant (same for `bti`, `mte`; one variant at a time) |
| `make ARCH=riscv64 deploy` | Builds the OpenSBI firmware, kernel + busybox + rootfs image + corpus (`build/riscv64/`) |
| `make ARCH=riscv64 run` | Boots the image, runs the corpus in the guest, extracts results |
| `make ARCH=riscv64 enable_riscv64_cfi=yes deploy` / `run` | The armed variant (`riscv64-cfi`): the same deploy plus the CFI corpus build and a CFI-advertising CPU pin; artifacts under `build/riscv64-cfi/` and `results/riscv64-cfi/` |
| `make ARCH=cheri_riscv64 deploy` | Builds the CHERI riscv64 emulator, the CheriBSD disk image and the corpus (a cold `deploy` is a world build — hours) |
| `make ARCH=cheri_riscv64 run` | Boots the pinned image under `qemu-system-riscv64xcheri`, runs the corpus in the guest, collects results in `results/cheri_riscv64/<stamp>/` |
| `make ARCH=aarch64-morello deploy` / `run` | The Morello lane (`qemu-system-morello`, UEFI + `loader(8)`); results in `results/aarch64-morello/<stamp>/` |
| `make ARCH=riscv64-nemu deploy` | Stages the corpus through the shared orchestrator and builds the guest image and its rootfs through the absorbed venue package (`build/riscv64-nemu/`); seeded caches make it run offline |
| `make ARCH=riscv64-nemu run` | Boots the image under the pinned NEMU, runs the whole suite in the guest, extracts the results from the console |
| `make ARCH=riscv64-nemu enable_riscv64_cfi=yes deploy` / `run` | The armed NEMU variant (`riscv64-nemu-cfi`): boots the pinned `../NEMU-cfi` interpreter over a CFI-advertising venue DTB; artifacts under `build/riscv64-nemu-cfi/` and `results/riscv64-nemu-cfi/` |
| `make ARCH=<lane> clean` | Removes that lane's build tree and the bench's generated files |
| `make ARCH=x86_64 dump` | The bench's own dump target (the system lanes refuse: their corpora are staged corpus-keyed — riscv64's and the CHERI lanes' binaries live inside their guest images) |

`ARCH` defaults to the host architecture. `deploy` is implicit for the host
lanes — `run` does everything. For the riscv64 family (both plain and armed
variants), riscv64-nemu and CHERI lanes,
run `deploy` first, then `run` (each is wrapped in its own `timeout`, except the
riscv64-nemu family: its run leg carries no outer `timeout`, and its bound is
two-tier instead — the platform's inner NEMU timeout at `LANE_RUN_TIMEOUT` and
the lane's own watchdog at `LANE_RUN_TIMEOUT + 120 s`, so the platform's
diagnosis fires first). The
riscv64-nemu lane's NEMU location is a *relative* default —
`NEMU_DIR=../NEMU`, `NEMU_BIN=$NEMU_DIR/build/riscv64-nemu-interpreter`,
resolved against this repo's root — so a checkout elsewhere overrides both
together (absolute paths allowed); the lane asserts the checkout's `HEAD`
equals the pinned `NEMU_COMMIT` on deploy **and** on run, and compares the live
binary's sha256 against the **deploy** meta's `nemu_bin.sha256` (as well as the
run meta's own value), so a rebuild between deploy and run is caught instead of
silently booted. A first cold deploy needs
the network (three source checkouts) and takes roughly an hour and a half; with
the caches seeded the deploy is offline and settles in minutes. The CHERI
lanes' run legs are the long pole, not their deploys: a guest boot drives the
full corpus over the console and is bounded by `LANE_RUN_TIMEOUT` (+120 s outer
watchdog) — observed boots land comfortably inside the cap, and the lane
timeout, not the wall clock, is the contract. The CHERI lanes'
`deploy` splits its timeouts deliberately: the cheap legs (source staging,
`prepare.sh`) carry `LANE_DEPLOY_TIMEOUT`, while the emulator and image builds
carry `CHERI_BUILD_TIMEOUT` (86400 s) — an outer `LANE_DEPLOY_TIMEOUT` would
fire in the middle of a world build and make the inner bound dead.

**One lane at a time.** The bench tree is a single mutable workdir: every
lane entry point takes an advisory lock on `build/.lane.lock` and a second
concurrent lane fails fast, naming the holder. Every lane run — success or
failure — copies its artifacts into `results/`, cleans the bench submodule and
verifies it is clean; a run that hits its timeout (exit 124) aborts without
publishing anything.

## Output layout

```
build/<lane>/               lane build trees
                            riscv64: kernel/ busybox/ stage/ Image rootfs.cpio manifest.json
                                     (plus fw_jump.bin, built from the pinned OpenSBI)
                            riscv64-cfi: its own stage/ manifest.json and corpus; the
                                     kernel Image and fw_jump.bin are shared, read-only
                            riscv64-nemu-cfi: its own platform/ + corpus/, seeded from
                                     the plain lane's platform sources
                            (the image manifest lives at build/<lane>/manifest.json
                             and the staged corpus manifest at
                             build/<lane>/corpus/manifest.json — under build/,
                             never in results/)
results/<lane>/<UTC-stamp>/ results.json  results.dat  versions.txt
                            (+ variables.json on x86_64, riscv64, and the
                             aarch64 family except `aarch64-mte` — its set-var
                             producer does not survive the HWASan build;
                             + boot.log and guest-status.txt on riscv64)
results/cheri/probe-<date>.json   CHERI dialect probe evidence
build/cheri/                CHERI lane build root (sources, SDK, emulators,
                            pinned disk images, versions-spike.txt)
results/cheri_riscv64/<UTC-stamp>/   results.json  results.dat  versions.txt
results/aarch64-morello/<UTC-stamp>/     + guest-status.txt  variables.json (both lanes)
                                     the full guest console transcript is
                                     build/<lane>/console.log, outside results/
results/riscv64-nemu/<UTC-stamp>/   results.json  results.dat  boot.log
                            meta.json  meta.deploy.json  versions.txt
                            (+ variables.json when the registry's set-var
                             records ran; the deploy's image lives under
                             build/riscv64-nemu/platform/, its staged corpus
                             under build/riscv64-nemu/corpus/)
results/riscv64-cfi/<UTC-stamp>/     results.json  results.dat  versions.txt
                            boot.log  guest-status.txt  (the armed qemu variant)
results/riscv64-nemu-cfi/<UTC-stamp>/   results.json  results.dat  boot.log
                            meta.json  meta.deploy.json  versions.txt
                            (the armed NEMU variant; same shape as its plain lane)
results/comparison-<UTC>/   comparison.json  comparison.md — the lane-comparison
                            snapshot (machine-local; see *Comparing lanes*)
```

`versions.txt` is the host-provenance record: the env.sh pins, the dpkg versions
of the packages above, the host `uname`, the bench checkout (`bench-head:` and
`bench-tree:` — the commit and a dirty-aware describe; a failing `git` records an
`unavailable` sentinel with its rc, never a value), and the run's outcome
(`run-status: ok`, or `run-status: failed (rc=N)` from the collector's own final
rc). On the host lanes (x86_64 and the aarch64 family) the collector treats
`results.json` and `results.dat` as required and parseable — absence, emptiness
or malformed JSON fails the collection — and `variables.json` stays optional. On
the riscv64 lane the guest's
`test/sys_info.txt` carries the guest-side truth (guest kernel and cpuinfo plus
only the pin lines — never the host `uname`). On the riscv64-nemu lane the stamp
adds the run's `meta.json` (platform, bench commit/tree, image and NEMU
sha256s, the record counts, the guest exit code and the good-trap flag) and the
deploy's `meta.deploy.json` (the corpus compiler, the pinned inputs, the image
and rootfs sha256s), and `versions.txt` gains a `# nemu` section: the binary's
path, its `HEAD`, `describe --always --dirty` and its sha256. Those two metas
are the authoritative tree/provenance record for this lane — since the venue's
scratch-tree rebuild, a clean bench checkout no longer carries a spurious
`-dirty`; the suffix now means the tree an image or corpus came from really was
uncommitted (see *Known caveats*).

`manifest.json` records the corpus as deployed: the bench commit, the lane, the
keyed per-unit file list with sha256 and mode, the registry's side files and the
declared support files, and the records the lane skips — each with the reason its
registry row declares.

Within `results.json` and `results.dat` the `run-time` and `make-time` fields
are per-run wall-clock timers: they differ between any two runs by construction
and carry no code meaning — stamp-to-stamp equivalence is asserted
record-level (whole documents equal minus those timers, every `result` and
`file-size` identical), never byte-level.

### Comparing lanes

`python3 scripts/common/compare_lanes.py` classifies the newest stamp of each
selected lane against the pin itself: the registry is read with
`git show <pin>:configure.json`, so the classification source is pinned by
construction and immune to checkout drift between the lane runs and the gate.
The default lane set is the seven executable lanes (x86_64, the four aarch64
variants, riscv64, riscv64-nemu); the two armed variants (`riscv64-cfi`,
`riscv64-nemu-cfi`) and the two CHERI lanes (`cheri_riscv64`,
`aarch64-morello`) are **not** in the default set — they are named explicitly
with `--lanes` and are part of the pin-uniform set whenever they carry stamps,
because their results are only meaningful against the same pin (the
eleven-lane gate of the 2026-11-25 re-stamp names all five).
`--reference` (default `x86_64`) is the lane
every other lane's codes are compared against; `--out` (default
`results/comparison-<UTC>-<pid>`) is where the snapshot's `comparison.json` and
`comparison.md` land.

The classification pin is `env.sh`'s `BENCH_COMMIT`; `--registry-pin` names it
explicitly for the registry-only-delta evidence mode. A pin bump that does not
re-stamp renders every existing stamp non-comparable — unless the bench delta
between the stamps' recorded pin and the registry pin names `configure.json`
and plan archives only (a delta that cannot move a corpus key), in which case
the stamps are accepted and the delta is recorded in the snapshot's
`comparison.json` (`registry.mode: registry-only-delta`, the accepted deltas
listed under `registry.accepted_deltas`); any other delta keeps the refusal.

The tool refuses rather than guesses (exit 2): a mixed pin outside the
registry-only-delta rule, a stamp that is not a completed run (`run-status` missing or failed, an
evidence-only stamp, a missing or unparsable `results.json`), a `bench-tree`
that is absent, `unavailable`, or `-dirty`, a missing reference lane, a pin not
in the submodule's object store, or input past the size cap or malformed. A lane
may be named deliberately absent with `--allow-absent` — recorded in the
snapshot, not gate-failing.

Retired stamps live under `results/<lane>/retired-<pin>/` (the pre-restamp
relocation each lane's run performs). Selection considers only directories that
carry a `versions.txt` at their top, so retirement directories are inert: a
lane whose only entries are retirement directories reads as absent, and a
newest stamp that exists but fails the completeness checks is still a named
exit-2 refusal.

The exit code is the gate: `0` — every selected lane complete and every record
in {`clean`, `declared`, `not-run-skipped`, `class-masked`}; `1` — a gate
failure (`out-of-expect`, `build-failed`, `prerequisite-unsatisfied`,
`missing-from-lane`, `extra-record`, an absent lane without `--allow-absent`, a
stamp whose `run-status` is failed); `2` — a refusal. **A nonzero exit IS the
finding** — disposition it in a report or a deferred issue; it is never bypassed.

Two verdicts need their class spelled out. `not-run` splits by the scheduler's
own two counts: the count without a make status is a declared platform skip
(`not-run-skipped`, benign); the same count with a make status is a build
failure (`build-failed`, and the status is named). `class-masked` is scoped to
the HWASan lane: on the `aarch64-mte` stamp, a `99` on a `set-var` producer is
the calibration producer whose HWASan build aborts before it can measure (the
constant is left undeclared by design); the same code on a producer anywhere
else is `out-of-expect`.

Snapshots are machine-local (`results/` is gitignored and never committed); the
tool under `scripts/common/` is the durable artifact, and this section carries
the command, never a recorded result.

## Pins

All pins live in `env.sh` only — no script hard-codes them.

| Item | Pin |
|---|---|
| bench commit | `0eb79b6aaf4ed5b77c5c20ad858ff343f1ae003e` — the deferral-disposition batch ("Resolve six open deferrals: ARCH-forcing hoist, skip-row retirement, evidence closure"): the bench Makefile hoists both flag forcings above the first ARCH consumer (flag-only invocations compose the forced ARCH everywhere — nine mis-compositions fixed, including the morello extractor — with the lane forms verified byte-identical bench-side), and the falsified `acc-get-frame-size` skip row is retired (GET_SP_LOC exists against the pinned purecap sysroot; compile proven bench-side), which puts the record live on `cheri_riscv64` and unlocks its consumer `cfi-return-without-call` from the literal-token `-vframe-size` fallback — the bench's successor-obligation note names both records. Not a registry-only delta (the Makefile changes), so the consuming env cycle re-stamped **all eleven** lanes at the pin: the 2026-11-25 eleven-lane re-stamp — the nine established lanes record-identical to their predecessor stamps (zero result/file-size diffs, variables byte-identical where published), the two CHERI lanes' first full grading at the current registry, and the eleven-lane comparison gate (explicit `--lanes`, same-pin) green except its single pre-declared finding (morello's `cfi-return-without-call`=260 — the held-row observation, reproduced, filed bench-side for the declare-or-fix decision). Beneath it, `83bb545d194d935f655729a4ca5857c07ff8b1c5` — the scheduler-safety batch ("Bound the scheduler's argv pool and initialise read-cross-segment's tc"): `argv_conv`'s copies into the fixed 32×256 argument pool now guard `i >= 32` and `length >= 256` with the named Parse-abnormality fail-fast (exit 1, no result code minted; in-range behavior unchanged), and `mss/read-cross-segment.cpp`'s `tc` is initialised to `'?'` in the `rv = 1` house-sentinel form (it used to be read uninitialised when `des_type` fell outside its switch; scope unchanged) — registry, catalog and result-code contract untouched. Its behavioural evidence is this repository's 2026-11-24 nine-lane re-stamp: every lane record-identical to its predecessor stamp (whole documents equal minus the per-run `run-time`/`make-time` wall-clock timers, every `result` and `file-size` identical, `variables.json` byte-identical where published), the comparison gate green with identical graded counts and an identical divergence table. Beneath it, `04f880b998565138c5697ca769811113914d603b` — the registry-realignment bookkeeping; its `configure.json` is byte-identical to the realignment beneath it, `73747ad` ("Retire the defect-era qemu CFI declarations from the registry"), which retires the declaration layer of `92f7deb` (the 25 armed-qemu declarations), `216da4ee` (the 262 allocator-abort pair) and `eb19132` (the open-ended residue restatement) plus the four `1aa6928`-era sweep-row 30 predictions — 34 entries across 31 records, each proven undelivered across the eleven 2026-11-22 stamps after the healed qemu falsified the defect-era predictions, and `cfi-return-to-peer-func`'s 30/1 reworded to the class-standard truths; registry-only (corpus keys unchanged, declared-30 delivery 12/19 → 12/12), re-graded green at this pin by the evidence-mode gate (`tmp/verification/2026-11-23-env-bench-realign-gate*`). Beneath it, the correctness batch `9645e57` ("Fix five correctness deferrals: sentinel UB, dangling requires, stale declarations, redzone publication") and its adjudication amendment `eb19132` ("Declare the armed-qemu peer-func outcome structural; open the residue set"). The batch restores four `int rv = 1;` sentinels and eight dangling require references, replaces `acc-check-IBT`'s impossible 290 with the observed 99, declares `mts-write-after-free-stack`'s residue space, and makes the redzone calibration publish the matched alignment distance (`rewrite_temp_file` plus the case's match-arm rewrite) — whose behavioural evidence is this repository's 2026-11-20 re-stamp, where the published values certified unchanged on this host. The amendment retracts the qemu-side claim on `cfi-return-to-peer-func` — on qemu the g1 calibration is itself caught and publishes nothing, so the case exits 1 before staging its attack and the prior 30 was an accidental exit-path fault of the old layout (30 stays scoped to the NEMU lane, where the calibration publishes; the qemu-vs-NEMU divergence record stands) — and restates the residue set open-ended, with 120 joining 136/200/248 (a restatement the `73747ad` realignment retired). Beneath them, `92f7deb` is bench cycle 4's registry amendment, "Declare the armed CFI class's observed qemu outcomes in the registry": 25 `expect-results` declarations record what the armed RISC-V ISA-CFI class does under qemu (the calibration chain's SEGV_CPERR exit 30, the corruption families' diagnostic deaths, the rows that collapse to a declared not-demonstrated code), each stated as a qemu-platform observation, never as CFI delivery, with the qemu-vs-NEMU divergence left under adjudication. That delta is registry-only (its plan-archive files ride along): no scheduler, test or source change, so the scheduler's collapse rule leaves every lane's recorded code identical to `182652b`'s. Beneath it, `182652b` is bench cycle 3's class-gap commit: `216da4ee` fixed the CFI-class stack-offset calibration and declared the armed class's allocator aborts, `182652b` anchored that calibration at the call's return site (`lpad 0` plus 4-byte label alignment defeats a label-address scan), and its parent `2aaf895` fixed the Zicfiss self-arm lock argument (the RISC-V `PR_LOCK_SHADOW_STACK_STATUS` takes `0`). Beneath them `cbe3bf9` made the benchmark a portable core: the embedded venue (`platform/riscv64-nemu-linux/`) is gone (this repository stages every system lane's corpus itself and carries the NEMU venue package), and the CHERI/Morello build skips are declared in the tracked registry, whose `skip` rows name the arch token a record does not build on and its cause (the Morello build bakes a distinct token, so its rows cannot collide with the healthy aarch64 lanes). All nine executable lanes carry stamps on the current pin chain (the 2026-11-20 re-stamp, the riscv64 family re-stamped 2026-11-22 at the healed qemu; the 2026-11-23 evidence-mode gate re-graded all nine against the realigned registry, the registry-only deltas between their recorded pins and this one being the gate's audited `accepted_deltas`); the two CHERI lanes kept their previous-pin stamps and were excluded from the pin-uniform comparison by design at that pin (superseded 2026-11-25: the eleven-lane re-stamp at the pin above graded both CHERI lanes into the pin-uniform gate) |
| NEMU | `../NEMU` @ `ae1ec3cd869b9c5e1783af691538d5c26f37ee55` — the workspace checkout; `NEMU_DIR`/`NEMU_BIN` are a relative-default pair, and the binary's sha256 is recorded and compared run-to-run, **not** pinned |
| NEMU-cfi | `../NEMU-cfi` @ `668eb688a7478fa8863220d8f81033ed786f6bb9` (NEMU master plus the Zicfiss/Zicfilp implementation, CFI-verified by the workspace's research cycles) — the `riscv64-nemu-cfi` lane's interpreter; `NEMU_CFI_DIR`/`NEMU_CFI_BIN` are a relative-default pair and the binary's sha256 **is** pinned (`NEMU_CFI_BIN_SHA256`) |
| NEMU venue inputs | workload-builder `b7c321dec6ad6f4c78abcaefc722b59b4043503c`, OpenSBI `cbf9f6734dd85a982c63e3cb5db7ffe09da839ca`, LibCheckpointAlpha `5169da768d18f4682a489eaabe7c071df6d6ef88` — the absorbed image builder's upstream sources, one pin per input in `env.sh` |
| riscv64 toolchain | `riscv64-linux-gnu-{g++-13,gcc-13,as,objdump}` (Ubuntu gcc-13 cross 13.4.0) — the plain lanes |
| riscv64 CFI toolchain | `riscv64-unknown-linux-gnu-{gcc,g++,as,objdump}` (GCC 16.1.0, `RISCV64_GNU_PREFIX=../riscv/bin/…`) — the guest kernel and the two CFI variant lanes |
| aarch64 toolchain / sysroot | `aarch64-linux-gnu-{g++-13,gcc-13,as,objdump}`, `/usr/aarch64-linux-gnu` |
| QEMU (riscv64 system lanes) | source-built **11.1.3** — `QEMU_PIN_VERSION_RISCV64=11.1.3`, `QEMU_SYSTEM_RISCV64=build/qemu-11.1.3/build/qemu-system-riscv64`. Built once from the release tarball (sha256-pinned in `env.sh`'s provenance comment) with `--enable-virtfs --enable-attr` (virtfs/9p is a hard requirement of the lanes' result extraction — see Prerequisites). The binary's sha256 is recorded per stamp (the stamp's `# emulator` section) and compared run-to-run, **not** pinned — build paths embed. Why source-built: QEMU ≤11.1.0's RISC-V translator poisons the translation block's `pc_save` on every *successful* `sspopchk` under CF_PCREL (upstream #4118, fixed by `6187f92`, first carried by 11.1.1), and the distro 10.2.1 package can never receive the fix — the defect produced the entire qemu-side half of the armed class's qemu↔NEMU divergence (see *Known caveats*). Why the split: the defect is riscv-translator-only, so `qemu-aarch64` is untouched and the aarch64 family stays on the distro binary |
| QEMU (aarch64 family) | distro 10.2.1 (`qemu-aarch64` via the qemu-user packages; `QEMU_PIN_VERSION`) — unchanged by the riscv64 pin split |
| QEMU CPU models | riscv64 `rva23s64` (`-M virt`, 256 MiB, the built `build/riscv64/fw_jump.bin`); `riscv64-cfi` `rva23s64,zicfiss=on,zicfilp=on` (RVA23 does not include the CFI extensions, and QEMU only advertises them as opt-in properties — measured: the base profile emits a guest DT with zero `zicfiss`/`zicfilp` hits, the property form two); the aarch64 `pa`, `bti` and `mte` lanes each request `QEMU_CPU=max` (under three per-lane names in `env.sh`) — the venue's default model **plus** PAuth (`max` is *not* the default: left unset, this `qemu-aarch64` behaves as `max,pauth=off`, byte-identical HWCAP). The `pa` request is load-bearing (its `retaa` epilogue SIGILLs without FEAT_PAuth) and so is the `bti` request at this pin (the bti class's `-march=armv8.5-a` implies PAuth, and the bench's `STRIP_PAC()` compiles to `xpaci`, which traps without FEAT_PAuth) — see *Known caveats* |
| riscv64 firmware | OpenSBI v1.9 `cbf9f6734dd85a982c63e3cb5db7ffe09da839ca`, built as a generic `fw_jump` into `build/riscv64/fw_jump.bin` and booted by both riscv64 lanes — it advertises the SBI FWFT LANDING_PAD + SHADOW_STACK features user-mode CFI needs, which QEMU's bundled firmware does not |
| guest kernel | Linux 7.3.4 (kernel.org tarball, sha256-verified) — the 7.x line is the first with `CONFIG_RISCV_USER_CFI`; one lane-agnostic config serves all four riscv64-family lanes |
| busybox | 1.36.1 (static, sha256-verified) |
| cheribuild | `db2f0360381e5fa2d50379e92ad119bb98db25c4` |
| CHERI QEMU | `CHERI-Alliance/qemu` @ `32bf55e2965dcdcfb0139d209e7a7b9dd1314583` — targets `riscv64xcheri-softmmu,morello-softmmu` (QEMU 7.2.0) |
| CheriBSD | `CTSRD-CHERI/cheribsd` (commit pinned in `env.sh`) — purecap `riscv64` and `morello` disk images, each sha256-pinned |
| CHERI boot firmware | riscv64: `CTSRD-CHERI/riscv-pk` @ `0cb596cf6e49c0014256300b614c5cd30cb90d57` → `bbl-riscv64cheri-virt-fw_jump.bin`; Morello: `edk2-aarch64-code.fd` |
| CHERI CPU pins | riscv64 `rv64,sstc=off` (Sstc workaround — the pinned riscv-pk firmware never sets `menvcfg.STCE`); Morello `morello`, `virt,gic-version=3` |
| CHERI sysroots | `CHERI_SYSROOT_RISCV64`, `CHERI_SYSROOT_MORELLO` — purecap, under two different SDK roots |
| reproducibility | `KBUILD_BUILD_TIMESTAMP/USER/HOST`, `SOURCE_DATE_EPOCH` (unset for the CheriBSD legs); the riscv64 and riscv64-nemu images are byte-reproducible (identity pins, normalized staging, `cpio --reproducible`, and the venue's fixed build timestamp) |
| timeouts | lane run 3600 s, lane deploy 7200 s; CHERI emulator/image legs 86400 s (`CHERI_BUILD_TIMEOUT`) |

The riscv64 image is byte-reproducible: the kernel/busybox builds carry the
identity pins above, the rootfs staging normalizes mtimes and sorts entries with
`LC_ALL=C`, the archive is written device-independent (`cpio --reproducible`, so
inode and device numbers stay out of the newc headers — without it a clean
re-stage leaks fresh `st_ino` values and the bytes differ), and the fetches
verify their sha256 before use.

## Trust boundary

The corpus consists of deliberately-attacking binaries built from the pinned
bench: trusted code from a trusted source, but **adversarial by design**. The
host-run lanes (x86_64, aarch64) execute them **unsandboxed with the invoking
user's privileges — deliberately, and only on this workstation**; the
virtual-machine lanes (riscv64, cheri_riscv64, aarch64-morello) are isolated by
their disposable qemu guests, each booted `-snapshot` from its pinned image. The
riscv64-nemu lane sits between the two models: no corpus instruction ever
executes as a host process — every one is interpreted by the pinned NEMU — and
the guest's devices are NEMU's own models over the image the deploy assembles
under `build/`, so its host surface is the NEMU binary and those build files
rather than the corpus. Do not repoint a host lane at an untrusted registry or
corpus without adding isolation first.

## Known caveats

- **The riscv64-nemu lane runs all 246 records at the uniform pin.** The guest
  exits 0 with the good-trap flag, and at the current pin every record
  classifies `clean` or `declared` — the case-delivery rows the previous pin
  left outside the registry's `expect-results` are declared at the source
  (the bench declares the crash-code classes the two riscv64 venues produce),
  so the comparison gate carries no out-of-expect row for either riscv64
  venue. The two venues agree with each other record for record and diverge
  from the `x86_64` reference where the platforms genuinely differ; the
  divergence matrix is in the lane-comparison snapshot (see *Comparing
  lanes*). Results are extracted by parsing the guest console, so every
  non-timeout stamp carries console evidence as `boot.log` — the run dir's own
  log when one was created, else the lane's platform log copied under that
  name; a run whose completeness gate fails publishes `boot.log` +
  `versions.txt` only, and a timeout publishes nothing.
- **Stamps carry host-local absolute paths.** This lane's `versions.txt`
  `nemu-bin:` line (the binary's `realpath`) and the copied metas'
  `nemu_bin.path` / `image.path` name this workstation's directories — scrub a
  stamp before sharing it off the machine.
- **This repository has no permanent test suite.** There is no test catalog and
  no CI gate: the lanes' verification lives in the machine-local plan scripts
  under `tmp/verification/` (step verifiers, acceptance and negative drivers)
  and in the lane runs' own stamps, all uncommitted by design.
- **The riscv64 lane runs the full registry at the uniform pin.**
  The independent-assembly translation is in the pinned bench
  commit, so the tracked registry declares no skips for the riscv64 token and
  the corpus stages every unit the registry enumerates — the deployed
  `manifest.json`'s `units` list is the measure-on-demand record, and the
  staging log names the runner's own skip census. At the current pin every
  record classifies `clean` or `declared` —
  the case-delivery verdicts the previous pin left outside the registry's
  `expect-results` are declared at the source, and the earlier expectation gap
  delivers its declared value under the exit-code contract. The opcode-extraction
  fix stays lane-confirmed: `acc-read-func` exits 0 (before the sweep it
  exited 1 — the extractor matched the translated `assembly_helper` symbol and
  wrote an empty side file), and `mss-write-by-stack-pointer` is declared in
  the registry's `expect-results`.
- **The two lane deviations recorded at the pre-uniform pin are closed.**
  (Measured at `74195c43`, the pin before the `a09f570`/`f4c916a` bumps.) Both
  were bench-side defects in the opcode-extraction path (deferrals
  `cheri-riscv64-opcode-extraction-deploy-abort` and
  `aarch64-func-opcode-extraction-host-objdump`), fixed in the pinned bench: the
  `cheri_riscv64` lane deploys and stamps (its corpus build routes the
  extraction through the SDK's own CHERI `riscv64cheri-objdump`), and the four
  aarch64 host lanes' `acc-read-func` exits 0 — it was recorded not-built
  (`1025`) at the earlier pin — with the extraction tool and the shim's
  bare-`objdump` PATH entry both named in each lane's run log. The fresh
  stamps (most recently the 2026-11-24 uniform re-stamp, see *Pins*) re-confirm it on every
  host lane: `acc-read-func` delivers its declared result in each.
- **The CHERI lanes run the strict corpus at the current pin.**
  Both boot their pins and run the corpus end-to-end over virtio-9p; the
  2026-11-25 eleven-lane re-stamp moved them to the current pin together with
  the nine established lanes, and they join the pin-uniform comparison through
  the gate's explicit `--lanes` argument (the comparison tool's default lane
  set still names seven — variant and CHERI lanes join by argument). The
  independent-assembly translation is in the pinned bench, so the corpus builds
  under strict mode — no `disable_independent_assembly`, no `--bring-up`. The
  remaining not-run records are CHERI-platform build failures declared in the
  tracked registry's `skip` rows with a reason (`mss-write-by-stack-pointer`
  on `cheri_riscv64`; `cfi-call-mid-func` on `aarch64-morello` — the falsified
  `acc-get-frame-size` skip row was retired at the current pin, and the record
  now runs, delivering clean 0 on both CHERI lanes). Verdicts outside the
  registry's `expect-results` are recorded as handoff rows for the bench, never
  skipped: the fresh stamps record one — `cfi-return-without-call` = 260 on
  `aarch64-morello`, reproduced from the Oct-24 stamp and held by the 2026-10-25
  intent check for exactly this guest-side observation, now measured and filed
  bench-side for the declare-or-fix decision (the Oct-24-era `cheri_riscv64`
  `cfi-call-mid-func` = 50 delivery defect is gone at the current pin: the
  delivery-block fix reaches the CHERI port and the record now delivers clean
  0). The former *declared but hollow* row is no longer hollow:
  `acc-get-frame-size` publishes `frame-size`, and `cfi-return-without-call`
  attacked with the real `-vframe-size` on `cheri_riscv64`, delivering its
  declared 16 (bus error). The `cheri_riscv64` lane's corpus build routes the extraction
  through the SDK's CHERI objdump (see the closed-deviations caveat above).
  `scripts/cheri/dialect_probe.sh` remains available and still records
  the raw dialect probe into `results/cheri/probe-<date>.json`.
- **The two CHERI lanes do not boot the same way, on purpose.** riscv64 loads
  `bbl-riscv64cheri-virt-fw_jump.bin` into M-mode and jumps to an external
  `-kernel` (the firmware, the kernel and the `rv64,sstc=off` CPU pin are all
  load-bearing — without the pin the guest panics at clock init); Morello is
  UEFI (`edk2-aarch64-code.fd`) and `loader(8)` reads the kernel from the disk
  image — it takes **no** `-kernel`. Do not "simplify" riscv64 to a disk-only
  boot: that path has no transition that can succeed.
- **The riscv64 CPU model is an RVA23 profile, not `rv64`.** The apt cross
  toolchain's glibc is built to the **RVA23U64** profile: its `crt1.o` and
  `libc.so.6` carry that `Tag_RISCV_arch`, and the linker unions input tags —
  so *every* executable this toolchain links declares RVA23U64, whatever
  `-march` the bench compiles with. A narrower qemu model (e.g. `rv64`, the
  lane's original pin) would be a latent illegal-instruction inside the guest's
  own libc. The lane therefore pins `-cpu rva23s64` (the named
  Linux-capable RVA23 profile model, present at both the distro 10.2.1 and
  the source-built 11.1.3 qemu), and the deploy asserts both that pin and that
  no staged ELF's tag exceeds the toolchain's own `crt1.o` baseline.
  The same argument applies to the **guest kernel**: it must support userspace
  vector (RISC-V V landed in Linux 6.5 — the original 6.1.83 pin had no
  `CONFIG_RISCV_ISA_V` and trapped the first `vsetivli` with signal 4), and it
  must *default* vector on (`CONFIG_RISCV_ISA_V_DEFAULT_ENABLE=y` — the kernel
  backs `abi/riscv_v_default_allow` with `IS_ENABLED(…)`), because Ubuntu's
  glibc never issues the V prctl itself. The lane pins 7.3.4 (the 7.x line is
  the first with `CONFIG_RISCV_USER_CFI`) and its kernel fragment forces the
  vector symbols plus the user-CFI symbol.
- **The NEMU / XiangShan venue has its own lane, not a riscv64-lane boot.** The
  riscv64 lane's image is qemu-virt-only by decision, not NEMU-bootable; the NEMU
  route is `riscv64-nemu`, which builds its own image through the absorbed
  venue package under `scripts/riscv64_nemu/venue/`.
- **Every aarch64-family stamp before 2026-10-25 is a non-execution record.**
  `env.sh` used to export `QEMU_VERSION`, and this venue's `qemu-aarch64` reads
  that name itself: for any value it printed its version banner and exited 0
  *before* parsing `-cpu` and before loading a guest. Every case of every stamp
  from 2026-10-13 to 2026-10-24 — all four variants — therefore "ran" as a
  banner print and the scheduler recorded `0` for all of them; those stamps
  carry **no test information** and are not a baseline to compare against. The
  version pin is renamed (`QEMU_PIN_VERSION`) and no longer exported, and the
  deploy smoke now asserts the guest loader's own output instead of an exit
  code, so a zero-execution route fails the deploy rather than publishing a
  stamp. The three variant lanes (`pa`, `bti`, `mte`) each pin a CPU request
  under their own name in `env.sh` (see *Pins*), and the plain lane clears an
  ambient `QEMU_CPU` rather than inheriting one; both scripts drop an
  inherited `QEMU_VERSION`, so the request a stamp records is the one that
  executed. The family's first real executions are the `f4c916a`-era stamps;
  the current evidence base is the 2026-11-24 uniform re-stamp (see *Pins*).
- **The `mte` variant really exercises MTE now.** The old request was spelled
  `max,mte=on`, which this venue rejects outright (`can't apply global
  max-arm-cpu.mte=on: Property 'max-arm-cpu.mte' not found`) and which therefore
  never reached a guest; the request is now `max`, the venue's default model
  **plus** PAuth. Under it the guest reports `HWCAP2_MTE`, a tag check on a
  `PROT_MTE` mapping faults synchronously with `si_code 9` (the
  `RT_SICODE_MTESERR`-class predicate), and the lane's `-fsanitize=hwaddress`
  build aborts with the HWASan runtime's `99` on the tag-touching cases — the
  `aarch64-mte` stamps are the only aarch64 stamps that carry that class. The
  lane's deploy smoke executes the same build class under the request and
  asserts the program's own line — deliberately not a clean exit, because
  qemu-user cannot run the runtime's LeakSanitizer leg and it aborts with `99`
  after the line. A
  tagged `si_addr` is observable as well; on this emulator the tag comes back
  whether or not `SA_EXPOSE_TAGBITS` is installed, which the rider records
  rather than assuming the flag is what exposes it.
- **The `pa` variant's CPU request is what makes it executable at all.** The
  lane builds the corpus with `-march=armv8.3-a+pauth -mbranch-protection=pac-ret`,
  so its function epilogues carry `retaa` — a real instruction, not a hint-space
  NOP like BTI's — and the venue's default model has no FEAT_PAuth. Before the
  request was pinned, that class dominated the lane's first really-executing
  stamp (dated snapshot, 2026-10-25: `256+4` = SIGILL on 226 of 246 records);
  with `QEMU_CPU=max` pinned it is gone. The calibration limitation the
  request's arrival exposed is also closed at this pin: the bench's RA-offset
  producers now derive and store a real offset under PAC-ret (recorded in the
  stamp's `variables.json` as the stack-offset values), the ten return-hijack
  records that used to deliver the shared precondition `1` execute their
  measurement, and `cfi-return-without-call`'s PAuth fault class is declared at
  the source — a stamp whose `variables.json` lacks the offsets, or whose ten
  records read the shared guard again, is evidence of a regression, not of the
  limitation. The deploy smoke executes
  a PAC-ret probe under the lane's request, so a request this venue cannot
  honour fails the deploy instead of poisoning the stamp.
- **The `bti` variant needs the same request, for a different reason.** BTI
  hints themselves execute as NOPs on a model without FEAT_BTI — but the bti
  class builds with `-march=armv8.5-a`, which implies PAuth, and the bench's
  `STRIP_PAC()` compiles to `xpaci` under it: on a PAuth-less model that
  instruction traps, and the return-hijack records that call it die with SIGILL
  before they measure anything. The first uniform-pin stamp caught exactly that
  (a handful of return-hijack rows at `260` that every earlier bti stamp scored
  `0`); the lane now pins `QEMU_CPU=max` like its sibling variants and its
  deploy smoke builds an `xpaci`-bearing binary and requires it to execute —
  the built binary's opcode census must find `xpaci`, so the leg cannot pass
  vacuously. A bti stamp carrying SIGILL-class results on its return-hijack
  records is an execution-venue failure, never a defence observation.
- **The bench pin is uniform across the eleven executable lanes.** The
  2026-11-25 re-stamp moved all eleven lanes to the current pin
  (`0eb79b6`) in one cycle (the 2026-11-24 cycle did the same for the
  nine then-executable lanes at `83bb545`; the 2026-11-19, 2026-11-20 and
  2026-11-22 cycles
  did the same for the pins before it); the comparison gate names all eleven
  by explicit `--lanes` and graded green except its single pre-declared
  finding (the morello-260 row, filed bench-side — see the CHERI caveat
  above). The earliest cycles relocated each lane's
  older stamps under `results/<lane>/retired-<pin>/`; the re-stamps since
  2026-11-19 have left
  the previous stamps in place beside the new ones, so the newest stamp per lane
  is the current-pin stamp and the older ones stay as run-to-run evidence (the
  re-stamp's own R1 delta check against the previous stamps is what identified
  the wild-death jitter record below; a stale-pin `riscv64-cfi` residue from
  the 2026-11-18 cycle corroborated it). Every statement in this file measured
  "at `f4c916a`", "`47d6f9d`" or the pins between has been re-derived or is
  explicitly dated to
  those eras; the lane-comparison snapshot is the measure-on-demand record of
  how the eleven lanes classify at the current pin.
- **The armed class's qemu-side profile was a QEMU translator defect and is
  healed at the 2026-11-22 pin.** Every corpus
  binary of the CFI class arms a shadow stack at startup, so the armed lanes
  legitimately move records outside their plain-lane declared sets. The qemu
  variant's defect-era profile — calibrators caught with 30, backward-edge
  rows stuck at their not-demonstrated codes, the wild-death families
  (260/267/262/216/192/184/136) — is adjudicated (2026-11-22,
  `tmp/research/nemu-divergence-adjudication-2026-11-20.md`) as artifacts of
  QEMU ≤11.1.0's RISC-V translator defect (`trans_sspopchk` skipping the
  PC-sync on the success path under CF_PCREL; upstream #4118, fixed by
  `6187f92`): a successful sspopchk left the translation block's `pc_save`
  stale and derailed every later PC-relative target, so benign calibration
  chains were genuinely caught and corrupted control flow died wild before any
  epilogue check ran. The source-built 11.1.3 (Pins → QEMU) carries the fix,
  and the healed restamp reproduced the adjudicated prediction
  record-for-record: the calibration publishes the same stack values the NEMU
  variant publishes, the declared-30 backward-edge rows deliver on the rows
  whose attacks stage, the wild-death rows complete benignly, and the armed
  lanes' recorded codes became identical (next bullet). The defect-era qemu
  declarations the bench registry carried (`92f7deb`/`eb19132`) were retired
  at the realignment `73747ad` — each proven undelivered across the eleven
  2026-11-22 stamps — and the set re-graded green at the current pin by the
  evidence-mode gate (`tmp/verification/2026-11-23-env-bench-realign-gate*`):
  every removed declaration named a code the healed qemu no longer delivers,
  no delivered code lost its declaration, and the armed lanes' recorded codes
  stayed identical. The `mts-write-after-free-stack` open-ended residue
  allowance retired with them — the wild-return path was the defect's
  derailment; a raw residue value a future run brings home re-enters by
  routine bench amendment, recorded, never a stop. The env-side arming chain itself is
  green on both lanes: platform advertisement, OpenSBI v1.9 FWFT, kernel
  `CONFIG_RISCV_USER_CFI`, the self-arm blob's lock and `ssrdp` readback, and the
  GCC 16 corpus all verify. Compare the armed lanes against each other and
  against their plain counterparts, never as a pass/fail gate against the
  seven-lane baseline.
- **Recorded codes are not universally stable run-to-run.** One record
  remains a measured mover: the aarch64 `pa` lane's
  `cfi-return-to-instruction-in-stack`, which delivered the registry's PAuth
  rejection code at one stamp and its generic illegal-call code at the next —
  both codes are declared for the record, so the gate scores it `declared`
  either way, but a code-identity comparison against an older stamp can flag
  it. The 2026-11-20 re-stamp fixed that record's baseline on the PAuth
  rejection (19): every stamp except the 2026-11-19 one carries it, all four
  runs at the current pin reproduce it with identical calibration inputs, and
  the one generic-exception stamp is adjudicated the one-off draw (the aarch64
  lanes pin no ASLR). The qemu armed variant's `mts-write-after-free-stack` —
  the second mover this bullet used to carry — retired at the realignment
  `73747ad`: the wild-return path was the defect's derailment and the healed
  pin lands a benign completion, so a raw residue value a future run brings
  home re-enters by routine bench amendment, recorded, never a stop. The
  scheduler's collapse rule cannot absorb this: a mover is a single-run
  record whose value comes from the death path itself, not from a
  chosen observation. Compare stamps on the gate's classification (per-record
  `clean`/`declared`/out-of-expect), not on raw code equality.
- **`riscv64-cfi` and `riscv64-nemu-cfi` stage byte-identical corpus binaries
  and, since the healed 2026-11-22 pin, record identical codes.** The
  defect-era divergence — the qemu variant trapping records the NEMU variant
  completed benignly — is closed: the workspace's adjudication
  (`tmp/research/nemu-divergence-adjudication-2026-11-20.md`) pinned it on the
  QEMU translator defect above (NEMU conformant; the qemu side healed by the
  11.1.3 upgrade), and the healed stamps are record-for-record identical
  across the two lanes. Any future divergence between the two armed lanes is
  a measurement worth investigating, not a lane failure.
- **`.claude/` is machine-local and ignored wholesale.** Agent-tooling
  configuration in the repo root is machine-local by the 2026-10-24 policy:
  `.gitignore` covers it alongside `build/`, `results/` and `tmp/`. Unlike the
  sibling bench repository, this repo does not track a `.claude/settings.json`.

### Historical note

An old Ubuntu-18 `libmpfr.so.4` workaround for the former RISC-V Linux SDK
toolchain used to live here; it went away with the `riscv-linux-sdk` submodule
removal — the riscv64 lane now uses the distro cross toolchain.