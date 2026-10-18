# cpu-sec-test-env

Build and run [`cpu-sec-bench`](https://github.com/comparch-security/cpu-sec-bench)
on every supported architecture from a single repository:

- **x86_64** — native host processes (the reference lane).
- **aarch64** — the benchmark's own scheduler is a host binary; the corpus runs
  through the kernel's `binfmt_misc` handler under `qemu-aarch64`, with variants
  for pointer-authentication (`pa`), branch-target-identification (`bti`) and
  memory-tagging (`mte`).
- **riscv64** — host-built corpus booted inside a Linux 6.18.56 guest under
  `qemu-system-riscv64` (`-M virt`), results extracted over a virtio-9p share.
- **CHERI** — two real lanes, `cheri_riscv64` and `aarch64-morello`: purecap
  CheriBSD 15.0-CURRENT guests under CHERI-LLVM's `qemu-system-riscv64xcheri`
  and `qemu-system-morello`, booted from pinned disk images with the corpus
  handed in over a read-only virtio-9p share and results collected from a
  writable one. Both lanes run the strict corpus; the only not-run records are
  platform build failures declared in the lane's derived registry (see *Known
  caveats*).

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
| `make ARCH=<lane> clean` | Removes that lane's build tree and the bench's generated files |
| `make ARCH=x86_64 dump` | The bench's own dump target (riscv64 has no dump: binaries live inside the guest image) |

`ARCH` defaults to the host architecture. `deploy` is implicit for the host
lanes — `run` does everything. For the riscv64 and CHERI lanes, run `deploy`
first, then `run` (each is wrapped in its own `timeout`). The CHERI lanes'
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
                            (+ variables.json on x86_64 and riscv64;
                             + boot.log and guest-status.txt on riscv64)
results/cheri/probe-<date>.json   CHERI dialect probe evidence
build/cheri/                CHERI lane build root (sources, SDK, emulators,
                            pinned disk images, versions-spike.txt)
results/cheri_riscv64/<UTC-stamp>/   results.json  results.dat  versions.txt
results/aarch64-morello/<UTC-stamp>/     + guest-status.txt  variables.json (both lanes)
                                     the full guest console transcript is
                                     build/<lane>/console.log, outside results/
```

`versions.txt` is the host-provenance record: the env.sh pins, the dpkg versions
of the packages above, and the host `uname`. On the riscv64 lane the guest's
`test/sys_info.txt` carries the guest-side truth (guest kernel and cpuinfo plus
only the pin lines — never the host `uname`).

`manifest.json` records the corpus as deployed: the bench commit, the lane, the
per-unit file list with sha256 and mode, the derived side file(s), and the
declared expected failures.

## Pins

All pins live in `env.sh` only — no script hard-codes them.

| Item | Pin |
|---|---|
| bench commit | `33f6f84b10080888d98eed535dda8313a914d161` |
| riscv64 toolchain | `riscv64-linux-gnu-{g++-13,gcc-13,as,objdump}` (Ubuntu gcc-13 cross 13.4.0) |
| aarch64 toolchain / sysroot | `aarch64-linux-gnu-{g++-13,gcc-13,as,objdump}`, `/usr/aarch64-linux-gnu` |
| QEMU | 10.2.1 (`qemu-system-riscv64`, `qemu-aarch64`) |
| QEMU CPU models | riscv64 `rva23s64` (`-M virt`, `-bios default`, 256 MiB); aarch64 MTE `max,mte=on` |
| guest kernel | Linux 6.18.56 (kernel.org tarball, sha256-verified) |
| busybox | 1.36.1 (static, sha256-verified) |
| cheribuild | `db2f0360381e5fa2d50379e92ad119bb98db25c4` |
| CHERI QEMU | `CHERI-Alliance/qemu` @ `32bf55e2965dcdcfb0139d209e7a7b9dd1314583` — targets `riscv64xcheri-softmmu,morello-softmmu` (QEMU 7.2.0) |
| CheriBSD | `CTSRD-CHERI/cheribsd` (commit pinned in `env.sh`) — purecap `riscv64` and `morello` disk images, each sha256-pinned |
| CHERI boot firmware | riscv64: `CTSRD-CHERI/riscv-pk` @ `0cb596cf6e49c0014256300b614c5cd30cb90d57` → `bbl-riscv64cheri-virt-fw_jump.bin`; Morello: `edk2-aarch64-code.fd` |
| CHERI CPU pins | riscv64 `rv64,sstc=off` (Sstc workaround — the pinned riscv-pk firmware never sets `menvcfg.STCE`); Morello `morello`, `virt,gic-version=3` |
| CHERI sysroots | `CHERI_SYSROOT_RISCV64`, `CHERI_SYSROOT_MORELLO` — purecap, under two different SDK roots |
| reproducibility | `KBUILD_BUILD_TIMESTAMP/USER/HOST`, `SOURCE_DATE_EPOCH` (unset for the CheriBSD legs) |
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
their disposable qemu guests, each booted `-snapshot` from its pinned image.
Do not repoint a host lane at an untrusted registry or corpus without adding
isolation first.

## Known caveats

- **All 246 records run on the riscv64 lane.**
  The independent-assembly translation (`cfi-return-to-peer-asmfunc` and
  `cfi-return-to-parent-non-call-site-by-asmfunc`) is in the pinned bench
  commit, so the derived registry declares no skips and the corpus stages 145
  units. Four riscv64 verdicts lie outside the registry's `expect-results` and
  are handoff rows, not skips: `acc-read-func` exits 1 at this pin because the
  bench's opcode-extraction script matches the translated `assembly_helper`
  symbol and writes an empty side file (deferral
  `func-opcode-gen-helper-symbol-match`, fixed in the bench sweep); and
  `cfi-jump-func-ra-from-heap-memcpy-implicit-arith` (267),
  `cfi-return-to-parent-wrong-call-site-fakefunc` (255) and
  `mss-write-by-stack-pointer` (1) are pre-existing bench-side expectation gaps
  (deferral `review-lines-bench-expectation-gaps`).
- **The CHERI lanes run the strict corpus.**
  Both boot their pins and run the corpus end-to-end over virtio-9p. The
  independent-assembly translation is in the pinned bench, so the corpus builds
  under strict mode — no `disable_independent_assembly`, no `--bring-up`. The
  remaining not-run records are CHERI-platform build failures declared in the
  lane's derived registry with a reason (`acc-get-frame-size`,
  `mss-write-by-stack-pointer` on `cheri_riscv64`; `cfi-call-mid-func` on
  `aarch64-morello`). Verdicts outside the registry's `expect-results` are
  recorded as handoff rows for the bench sweep, never skipped.
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
- **The NEMU / XiangShan venue is deliberately not covered.** The riscv64 image
  is qemu-virt-only by decision, not NEMU-bootable.
- **`tmp/` is machine-local** (untracked): plans, reports and verification
  scripts live there by repo convention and are re-runnable artifacts, not
  tracked deliverables.

### Historical note

An old Ubuntu-18 `libmpfr.so.4` workaround for the former RISC-V Linux SDK
toolchain used to live here; it went away with the `riscv-linux-sdk` submodule
removal — the riscv64 lane now uses the distro cross toolchain.