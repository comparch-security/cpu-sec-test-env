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
- **riscv64** — host-built corpus booted inside a Linux 6.18.56 guest under
  `qemu-system-riscv64` (`-M virt`), results extracted over a virtio-9p share.
- **CHERI** — two real lanes, `cheri_riscv64` and `aarch64-morello`: purecap
  CheriBSD 15.0-CURRENT guests under CHERI-LLVM's `qemu-system-riscv64xcheri`
  and `qemu-system-morello`, booted from pinned disk images with the corpus
  handed in over a read-only virtio-9p share and results collected from a
  writable one. Both lanes run the strict corpus; the only not-run records are
  platform build failures declared in the lane's derived registry (see *Known
  caveats*).
- **riscv64-nemu** — the bench's own NEMU venue
  (`benchmark/platform/riscv64-nemu-linux/`): the host-built corpus and the
  riscv64 scheduler run inside a Linux 6.18.56 guest emulated by the workspace's
  XiangShan NEMU (`../NEMU`, commit-pinned), with results extracted from the
  guest console. Deploy-first, like the system lanes; the NEMU location is a
  relative default, so the lane follows the workspace layout without an
  absolute path in `env.sh`.

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

- `qemu-system-riscv` / `qemu-system-data` (10.2.1) — the riscv64 lane's emulator
  and the OpenSBI blobs that `-bios default` uses.
- `qemu-user` + `qemu-user-binfmt` (10.2.1) — the aarch64 lane's execution path:
  every aarch64 ELF runs under `qemu-aarch64` via the kernel's binfmt handler
  (registering that handler is root-only, which is why it is in this list).
- The cross toolchains (13.4.0) build the riscv64 corpus and guest image and the
  aarch64 corpus; `libhwasan0-arm64-cross` supplies the MTE lane's
  `-fsanitize=hwaddress` runtime.
- A built XiangShan NEMU interpreter for the `riscv64-nemu` lane: a sibling
  `NEMU` checkout resolved by the repo-relative default
  `NEMU_DIR=../NEMU` with `NEMU_BIN=$NEMU_DIR/build/riscv64-nemu-interpreter`
  built from it, at the pinned `NEMU_COMMIT`. `NEMU_DIR`/`NEMU_BIN` are one
  overridable pair (absolute paths allowed); the lane records the binary's
  sha256 and compares it run-to-run rather than pinning it, so a stale local
  build is disclosed, not silently reused.

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
make ARCH=<lane> [enable_aarch64_<pa|bti|mte>=yes] <deploy|run|clean|dump>
```

| Command | What it does |
|---|---|
| `make ARCH=x86_64 run` | Builds and runs the bench natively; results in `results/x86_64/<stamp>/` |
| `make ARCH=aarch64 run` | Plain aarch64 lane (through binfmt) |
| `make ARCH=aarch64 enable_aarch64_pa=yes run` | Pointer-auth variant (same for `bti`, `mte`; one variant at a time) |
| `make ARCH=riscv64 deploy` | Builds kernel + busybox + rootfs image + corpus (`build/riscv64/`) |
| `make ARCH=riscv64 run` | Boots the image, runs the corpus in the guest, extracts results |
| `make ARCH=cheri_riscv64 deploy` | Builds the CHERI riscv64 emulator, the CheriBSD disk image and the corpus (a cold `deploy` is a world build — hours) |
| `make ARCH=cheri_riscv64 run` | Boots the pinned image under `qemu-system-riscv64xcheri`, runs the corpus in the guest, collects results in `results/cheri_riscv64/<stamp>/` |
| `make ARCH=aarch64-morello deploy` / `run` | The Morello lane (`qemu-system-morello`, UEFI + `loader(8)`); results in `results/aarch64-morello/<stamp>/` |
| `make ARCH=riscv64-nemu deploy` | Builds the corpus, the guest image and its rootfs through the venue's platform scripts (`build/riscv64-nemu/`); seeded caches make it run offline |
| `make ARCH=riscv64-nemu run` | Boots the image under the pinned NEMU, runs the whole suite in the guest, extracts the results from the console |
| `make ARCH=<lane> clean` | Removes that lane's build tree and the bench's generated files |
| `make ARCH=x86_64 dump` | The bench's own dump target (riscv64 has no dump: binaries live inside the guest image; riscv64-nemu refuses too — its corpus is staged corpus-keyed) |

`ARCH` defaults to the host architecture. `deploy` is implicit for the host
lanes — `run` does everything. For the riscv64, riscv64-nemu and CHERI lanes,
run `deploy` first, then `run` (each is wrapped in its own `timeout`, except the
riscv64-nemu lane: its run leg carries no outer `timeout`, and its bound is
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
the caches seeded the deploy is offline and settles in minutes. The CHERI lanes'
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
                            (the image manifest and the derived corpus manifest live under
                             build/, not in results/)
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
                             records ran; the deploy's corpus and image live
                             under build/riscv64-nemu/platform/<runset>/)
```

`versions.txt` is the host-provenance record: the env.sh pins, the dpkg versions
of the packages above, and the host `uname`. On the riscv64 lane the guest's
`test/sys_info.txt` carries the guest-side truth (guest kernel and cpuinfo plus
only the pin lines — never the host `uname`). On the riscv64-nemu lane the stamp
adds the run's `meta.json` (platform, runset, bench commit/tree, image and NEMU
sha256s, the record counts, the guest exit code and the good-trap flag) and the
deploy's `meta.deploy.json` (the corpus compiler, the pinned inputs, the image
and rootfs sha256s), and `versions.txt` gains a `# nemu` section: the binary's
path, its `HEAD`, `describe --always --dirty` and its sha256. Those two metas
are the authoritative tree/provenance record for this lane — the venue's
guest-side `# Bench tree` line reads `<pin>-dirty` even at a clean pin (see
*Known caveats*).

`manifest.json` records the corpus as deployed: the bench commit, the lane, the
per-unit file list with sha256 and mode, the derived side file(s), and the
declared expected failures.

## Pins

All pins live in `env.sh` only — no script hard-codes them.

| Item | Pin |
|---|---|
| bench commit | `47d6f9d0b99744d36bd857f6da7334036ce215c3` — the four `aarch64` variants carry stamps at this pin (2026-10-26 re-stamp); every other lane's newest stamp is at the previous pin `f4c916a821a6f3fa7024a75b1a25304ae4555729` (the 2026-10-24 uniform re-run) and therefore predates it — the riscv64-family re-stamp at this pin is a named successor, and the caveats below say when a measurement is older |
| NEMU | `../NEMU` @ `ae1ec3cd869b9c5e1783af691538d5c26f37ee55` — the workspace checkout; `NEMU_DIR`/`NEMU_BIN` are a relative-default pair, and the binary's sha256 is recorded and compared run-to-run, **not** pinned |
| riscv64 toolchain | `riscv64-linux-gnu-{g++-13,gcc-13,as,objdump}` (Ubuntu gcc-13 cross 13.4.0) |
| aarch64 toolchain / sysroot | `aarch64-linux-gnu-{g++-13,gcc-13,as,objdump}`, `/usr/aarch64-linux-gnu` |
| QEMU | 10.2.1 (`qemu-system-riscv64`, `qemu-aarch64`) |
| QEMU CPU models | riscv64 `rva23s64` (`-M virt`, `-bios default`, 256 MiB); aarch64 `pa` and `mte` each request `QEMU_CPU=max` — the venue's default model **plus** PAuth (`max` is *not* the default: left unset, this `qemu-aarch64` behaves as `max,pauth=off`, byte-identical HWCAP). The `pa` request is load-bearing (its `retaa` epilogue SIGILLs without FEAT_PAuth) — see *Known caveats* |
| guest kernel | Linux 6.18.56 (kernel.org tarball, sha256-verified) |
| busybox | 1.36.1 (static, sha256-verified) |
| cheribuild | `db2f0360381e5fa2d50379e92ad119bb98db25c4` |
| CHERI QEMU | `CHERI-Alliance/qemu` @ `32bf55e2965dcdcfb0139d209e7a7b9dd1314583` — targets `riscv64xcheri-softmmu,morello-softmmu` (QEMU 7.2.0) |
| CheriBSD | `CTSRD-CHERI/cheribsd` (commit pinned in `env.sh`) — purecap `riscv64` and `morello` disk images, each sha256-pinned |
| CHERI boot firmware | riscv64: `CTSRD-CHERI/riscv-pk` @ `0cb596cf6e49c0014256300b614c5cd30cb90d57` → `bbl-riscv64cheri-virt-fw_jump.bin`; Morello: `edk2-aarch64-code.fd` |
| CHERI CPU pins | riscv64 `rv64,sstc=off` (Sstc workaround — the pinned riscv-pk firmware never sets `menvcfg.STCE`); Morello `morello`, `virt,gic-version=3` |
| CHERI sysroots | `CHERI_SYSROOT_RISCV64`, `CHERI_SYSROOT_MORELLO` — purecap, under two different SDK roots |
| reproducibility | `KBUILD_BUILD_TIMESTAMP/USER/HOST`, `SOURCE_DATE_EPOCH` (unset for the CheriBSD legs); the riscv64-nemu image is **not** byte-reproducible — see the caveats |
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
  exits 0 with the good-trap flag; three rows lie outside the registry's
  `expect-results` at `f4c916a` — the same three the riscv64 lane carries
  (`cfi-jump-func-ra-from-heap-memcpy-implicit-arith` = 267,
  `cfi-call-mid-func` = 214, `cfi-return-to-peer-asmfunc` = 262) — and the
  earlier 255 expectation gap (`cfi-return-to-parent-wrong-call-site-fakefunc`)
  is closed: the record now delivers its declared `1`. The two riscv64 venues
  agree with each other record for record and diverge from the `x86_64`
  reference in the same eight records (seven `cfi` plus
  `mts-access-after-reclaim-heap`, the latter a legal pass verdict under the
  exit-code contract, never an anomaly). The three out-of-expect rows are
  case-delivery defects, not this lane's: the 2026-10-25 intent check reproduced
  each on the deployed corpus and delivered them to the bench tracker
  (`defer-issue-cfi-delivery-defects`, `defer-issue-f2-267-not-closed`);
  `214`/`262` are not declarable values. Results are extracted by parsing the
  guest console, so every non-timeout stamp carries console evidence as
  `boot.log` — the run dir's own log when one was created, else the lane's
  platform log copied under that name; a run whose completeness gate
  fails publishes `boot.log` + `versions.txt` only, and a timeout publishes
  nothing.
- **The riscv64-nemu image is not byte-reproducible across deploys.** Its
  platform packs the rootfs with `cpio -o -H newc` but without `--reproducible`,
  so host inode numbers leak into the newc headers and two deploys at identical
  pins differ byte-for-byte at equal size (bench-side, pre-existing; recorded as
  a deferral — the fix, adding `--reproducible`, belongs to a bench cycle). The
  venue README's byte-reproducibility claim is wrong for now. Each stamp records
  the image sha256 it actually ran (`meta.json` and `meta.deploy.json` agree), so
  compare stamps within one image.
- **The riscv64-nemu guest records `# Bench tree: <pin>-dirty` even at a clean
  pin** — a bench-side artifact of the venue's corpus staging (the marker is
  computed while the platform's own registry swap is active), contradicting the
  same run's `meta.json` (`bench_tree: <pin>`). Two provenance records of one run
  disagree; treat `meta.json`/`meta.deploy.json` as authoritative. Filed
  bench-side.
- **The riscv64-nemu deploy consumes the venue's transient registry swap.** The
  platform's own `build-corpus.sh` swaps its derived registry over the tracked
  `benchmark/configure.json` for the build's duration and trap-restores it; the
  lane authors no in-submodule change and guards the swap from both sides — the
  deploy preflight fails fast on a leaked swap (naming the deferral
  `corpus-build-registry-swap-crash-safety` and the restore command), and every
  exit path re-asserts the submodule clean. A SIGKILL *inside* the swap window
  still leaks the subset; that crash-safety gap is the deferral's own,
  bench-side fix.
- **Stamps carry host-local absolute paths.** This lane's `versions.txt`
  `nemu-bin:` line (the binary's `realpath`) and the copied metas'
  `nemu_bin.path` / `image.path` name this workstation's directories — scrub a
  stamp before sharing it off the machine.
- **This repository has no permanent test suite.** There is no test catalog and
  no CI gate: the lanes' verification lives in the machine-local plan scripts
  under `tmp/verification/` (step verifiers, acceptance and negative drivers)
  and in the lane runs' own stamps, all uncommitted by design.
- **All 246 records run on the riscv64 lane at the uniform pin.**
  The independent-assembly translation (`cfi-return-to-peer-asmfunc` and
  `cfi-return-to-parent-non-call-site-by-asmfunc`) is in the pinned bench
  commit, so the derived registry declares no skips and the corpus stages 145
  units. Three riscv64 verdicts lie outside the registry's `expect-results` at
  `f4c916a` — `cfi-jump-func-ra-from-heap-memcpy-implicit-arith` (267),
  `cfi-call-mid-func` (214) and `cfi-return-to-peer-asmfunc` (262) — all three
  case-delivery defects under the 2026-10-25 intent check, delivered bench-side
  (see the riscv64-nemu caveat above); the earlier
  `cfi-return-to-parent-wrong-call-site-fakefunc` (255) row is closed by the
  contract (it delivers its declared `1`). The sweep's opcode-extraction fix
  stays lane-confirmed at this pin: `acc-read-func` exits 0 (before the sweep it
  exited 1 — the extractor matched the translated `assembly_helper` symbol and
  wrote an empty side file), and `mss-write-by-stack-pointer` (1) is declared in
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
  bare-`objdump` PATH entry both named in each lane's run log. For the aarch64
  half, the 2026-10-24 uniform re-run re-confirms nothing (those stamps are
  non-execution records — see the family caveat above); the real evidence is the
  fresh stamps, e.g. `results/aarch64/20261025T230008Z`: `acc-read-func` result
  `0` on a 77,360-byte binary.
- **The CHERI lanes run the strict corpus.**
  Both boot their pins and run the corpus end-to-end over virtio-9p. The
  independent-assembly translation is in the pinned bench, so the corpus builds
  under strict mode — no `disable_independent_assembly`, no `--bring-up`. The
  remaining not-run records are CHERI-platform build failures declared in the
  lane's derived registry with a reason (`acc-get-frame-size`,
  `mss-write-by-stack-pointer` on `cheri_riscv64`; `cfi-call-mid-func` on
  `aarch64-morello`). Verdicts outside the registry's `expect-results` are
  recorded as handoff rows for the bench, never skipped: at the uniform pin
  `cheri_riscv64` records one (`cfi-call-mid-func` = 50) and `aarch64-morello`
  one (`cfi-return-without-call` = 260), both classified by the 2026-10-25
  intent check (the first is the same case-delivery defect the riscv64 venues
  show as 214; the second is held for one guest-side observation before any
  declaration). One `cheri_riscv64` row is *declared but hollow*:
  `cfi-return-without-call` records its declared `1` without attempting the
  attack, because the lane records no `frame-size` and the record's
  `-vframe-size` token stays literal — delivered bench-side with the same
  findings. The `cheri_riscv64` lane's corpus build routes the extraction
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
  own libc. The lane therefore pins `-cpu rva23s64` (qemu 10.2.1's named
  Linux-capable profile model), and the deploy asserts both that pin and that
  no staged ELF's tag exceeds the toolchain's own `crt1.o` baseline.
  The same argument applies to the **guest kernel**: it must support userspace
  vector (RISC-V V landed in Linux 6.5 — the original 6.1.83 pin had no
  `CONFIG_RISCV_ISA_V` and trapped the first `vsetivli` with signal 4), and it
  must *default* vector on (`CONFIG_RISCV_ISA_V_DEFAULT_ENABLE=y` — the kernel
  backs `abi/riscv_v_default_allow` with `IS_ENABLED(…)`), because Ubuntu's
  glibc never issues the V prctl itself. The lane pins 6.18.56 and its kernel
  fragment forces both symbols.
- **The NEMU / XiangShan venue has its own lane, not a riscv64-lane boot.** The
  riscv64 lane's image is qemu-virt-only by decision, not NEMU-bootable; the NEMU
  route is `riscv64-nemu`, which builds its own image through the venue's
  platform scripts under `benchmark/platform/riscv64-nemu-linux/`.
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
  stamp. The request-less lanes (`aarch64`, `aarch64-bti`) also clear an
  ambient `QEMU_CPU` rather than inheriting one, and both scripts drop an
  inherited `QEMU_VERSION`, so the request a stamp records is the one that
  executed. The family's first real executions are the `f4c916a`-era stamps
  (`results/aarch64*/20261025T09*Z/`); the `47d6f9d`-era stamps
  (`results/aarch64*/20261025T23*Z/`, produced late on 2026-10-25 UTC) re-base
  the family on the bumped bench pin (see *Pins*).
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
  with `QEMU_CPU=max` pinned it is gone, and the stamp's out-of-expect rows are
  two named classes — the calibration cascade below, and
  `cfi-return-without-call`'s undeclared `19` (a fault that matches no
  registration under PAuth; a bench-side declaration successor, not a defence
  observation). One of those classes is a
  **calibration limitation, not a defence observation**: the bench's RA-offset
  producers scan the stack with a raw compare, which cannot match a PAC-signed
  saved LR, so ten return-hijack records deliver the shared `1` as a
  precondition failure — recorded as the standalone deferral
  `aarch64-pa-calibration-cascade` (bench-side fix). The deploy smoke executes
  a PAC-ret probe under the lane's request, so a request this venue cannot
  honour fails the deploy instead of poisoning the stamp.
- **The bench pin moved on 2026-10-26; only the `aarch64` family was re-stamped.**
  The bench's `47d6f9d` commit carries five case-delivery fixes, so the
  `riscv64`, `riscv64-nemu` and CHERI lanes' newest stamps — and every statement
  in this file measured "at `f4c916a`" — predate the pin. Their re-stamp under
  `47d6f9d` is a named successor; the aarch64 family's 2026-10-26 stamps are the
  only ones at the current pin, and the bench fixes' effect is visible there
  (the `267` class the plain and `bti` lanes carried at `f4c916a` is gone).
- **`.claude/` is machine-local and ignored wholesale.** Agent-tooling
  configuration in the repo root is machine-local by the 2026-10-24 policy:
  `.gitignore` covers it alongside `build/`, `results/` and `tmp/`. Unlike the
  sibling bench repository, this repo does not track a `.claude/settings.json`.

### Historical note

An old Ubuntu-18 `libmpfr.so.4` workaround for the former RISC-V Linux SDK
toolchain used to live here; it went away with the `riscv-linux-sdk` submodule
removal — the riscv64 lane now uses the distro cross toolchain.