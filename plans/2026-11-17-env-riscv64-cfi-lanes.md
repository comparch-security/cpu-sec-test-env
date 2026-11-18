# Plan: Enable the armed RISC-V CFI lanes (kernel 7.3.4, OpenSBI v1.9, bench 182652b)
**Project:** cpu-sec-test-env (lane dispatcher for cpu-sec-bench)
**Plan ID:** 2026-11-17-env-riscv64-cfi-lanes
**Created:** 2026-11-17

## Issue Log

| Issue | Status | Found | Resolved | Resolved By |
|-------|--------|-------|----------|-------------|
| [step10-docs-unexecuted](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-step10-docs-unexecuted.json) | Resolved | 2026-11-19 | 2026-11-19 | planner — Step 10 executed in this run: README (pins, kernel/firmware figures, lane bullets, usage table, nine-lane sentences, known caveats), CLAUDE.md (purpose, structure, commands, architecture), and the three doc pages; the doc-structure gate passes 4/4 |
| [bench-pin-moved-past-rev11](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-bench-pin-moved-past-rev11.json) | Resolved | 2026-11-18 | 2026-11-19 | tester — tester round 7: the static battery is 96/96 with S1.1d passing (every pin literal, `env.sh`, the submodule HEAD and the commit gate all at `182652b`) |
| [nemu-cfi-clean-swallowed-bench-arch-guard](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-nemu-cfi-clean-swallowed-bench-arch-guard.json) | Resolved | 2026-11-18 | 2026-11-18 | tester — tester round 6: the three sites' extracted invocations clean under the inherited MAKEFLAGS (rc=0, `benchmark/run-test` removed) while the pre-fix shape still dies rc=2 and leaves the residue (9/9 teeth), and the real order (`riscv64-nemu-cfi` → `x86_64`) publishes `x86_64`'s own stamp rc=0 with the tree clean (18/18 lane steps) |
| [riscv64-cfi-class-registry-gaps (deferral)](./tmp/reports/defer-issue-riscv64-cfi-class-registry-gaps.json) | Deferred | 2026-11-18 | — | bench cycle 3 (separate repo) at `182652b`: item (a) **done** (the two 262 rows declared and clear); item (b) **done on NEMU** (calibrators publish; declared-30 2/16 → 12/16) and **open on qemu** (calibrators still 30/30/30, declared-30 2/16, out-of-expect 25); item (c) the qemu-vs-NEMU divergence **open** (unadjudicated; named an env/research gate by the bench cycle) |
| [stale-bench-pin-literals](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-stale-bench-pin-literals.json) | Resolved | 2026-11-18 | 2026-11-18 | tester — tester round 5: static S1.1 asserts the `2aaf895` prefix + full sha and S1.1b asserts the submodule HEAD equals the pin and the tree is clean |
| [cfi-closure-assert-interp](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-cfi-closure-assert-interp.json) | Resolved | 2026-11-18 | 2026-11-18 | tester — tester round 4: the qemu deploy completes past the assert and both variants publish complete stamps; the teeth harness (12/12) proves the exemption is interpreter-only |
| [cfi-self-arm-lock-arg (deferral)](./tmp/reports/defer-issue-cfi-self-arm-lock-arg.json) | Resolved | 2026-11-18 | 2026-11-18 | tester — tester round 5: bench `2aaf895` is in force and no CFI record returns 20 on either lane (B1 passes); the arm blob locks with `a1 = 0` and the shadow stack is armed and enforcing. The standalone deferral retires with this row |
| [cfi-guest-loader-search-path](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-cfi-guest-loader-search-path.json) | Resolved | 2026-11-18 | 2026-11-18 | tester — tester round 4: both CFI lanes execute all 246 records from the GCC 16 closure (placement verified end to end) |
| [nemu-plain-kernel-ssp-panic](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-nemu-plain-kernel-ssp-panic.json) | Resolved | 2026-11-17 | 2026-11-18 | tester — tester round 2: the plain lane boots an advertisement-free DT and publishes a 246-record green stamp (225/21) |
| [stage-corpus-class-flag-env](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-stage-corpus-class-flag-env.json) | Resolved | 2026-11-17 | 2026-11-18 | tester — tester round 2: both variant deploys staged their corpus cleanly (STEP rc=0) |
| [venue-cfi-toolchain-asymmetry](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-venue-cfi-toolchain-asymmetry.json) | Resolved | 2026-11-17 | 2026-11-18 | tester — tester round 2: the variant deploy builds the whole guest with the GCC 16 toolchain and the static S7 battery passes |
| [venue-dts-template-regenerated](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-venue-dts-template-regenerated.json) | Resolved | 2026-11-17 | 2026-11-18 | tester — tester round 2: two-sided compiled-DTB evidence on real deploys (plain lane neither, variant both) |
| [stage-corpus-lane-flag-assert](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-stage-corpus-lane-flag-assert.json) | Resolved | 2026-11-17 | 2026-11-18 | tester — tester rounds 1–2 S5 battery (S5.1-S5.11d): the flag-conditional assert is in the built script and both variant lanes stage their corpus green |
| [coder-steps-lack-verification](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-coder-steps-lack-verification.json) | Resolved | 2026-11-17 | 2026-11-18 | tester — the plan declares the coder `(auto)` tier (rev 3) and the tester's S9.1 static check passes in rounds 1–2 |
| [mega-audit 2026-11-17 (76 findings: 26 High / 29 Medium / 21 Low)](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-mega-audit-2026-11-17.json) | Resolved | 2026-11-17 | 2026-11-17 | rev 2 — 74 accepted, 2 rejected ([41] premise refuted: the Kconfig `cc-option` includes `-mabi=lp64` and that exact command passes on GCC 16.1.0, measured; [18] rejected: the repo's scripts do not depend on the user-global tracer) |

## Guidance for Coder

- Read `env.sh` end to end before editing anything: every pin, URL, SHA256, timeout and
  root lives there and nowhere else. New pins are added there and exported there.
- The bench submodule is read-only at `BENCH_COMMIT`. Never edit inside `benchmark/`;
  everything this cycle needs on the bench side already landed (`enable_riscv64_cfi`
  build class, `-DCSB_CFI_SELF_ARM` self-arm, SEGV_CPERR 30/31 delivery, 19 registry
  rows) at bench commit `182652b` (bench cycle 3: `2aaf895` fixed the arm blob's lock
  argument, `216da4ee` fixed the CFI-class stack-offset calibration and declared the
  allocator aborts, `182652b` re-anchored that calibration at the call's return site;
  `d9cc4cd` beneath them carried the wrong lock argument).
- The two new lanes are **variants**, not new lanes: one env flag
  (`enable_riscv64_cfi=yes`) applied to `ARCH=riscv64` yields lane `riscv64-cfi`, and
  to `ARCH=riscv64-nemu` yields `riscv64-nemu-cfi`. It maps 1:1 onto the bench class
  flag of the same spelling, which `stage_corpus.sh` exports into the corpus
  invocation's environment (the mechanism at `scripts/common/stage_corpus.sh:262`).
- **The variant lane name is a first-class identifier in every lane-keyed consumer**:
  `stage_corpus.sh`'s lane case + enable-flag whitelist + toolchain case,
  `version_stamp.sh`'s lane whitelist, `compare_lanes.py`'s `KNOWN_LANES`, the lane
  scripts' arg asserts, and every build/results path. Half-way adoption (a variant name
  into some dispatches and not others) is how the audit's High findings happened —
  each such miss is a hard exit or a silent cross-lane publish.
- **Variant build trees are lane-keyed, not leaf-suffixed**: `build/riscv64-cfi/…` and
  `build/riscv64-nemu-cfi/…`. The shared kernel `Image` and `fw_jump.bin` stay under
  `build/riscv64/` and are read-only inputs for the variant. Never write a variant's
  corpus, stage tree, rootfs or results into the plain lane's trees — and never let the
  variant's stamp land under `results/riscv64-nemu/` (the plain lane's newest-stamp
  selection would silently read the armed run).
- **The bench ARCH/CSB token stays `riscv64` for both variants** (as the venue already
  does): the variant name selects env-side paths and results only. Every
  `make -C benchmark` in a deploy leg runs with `ARCH=riscv64` and with `MAKEFLAGS`
  cleared, or the bench Makefile's own guard dies (`enable_riscv64_cfi=yes requires
  ARCH=riscv64`) or keys `lib/riscv64-cfi/` (no such tree).
- The kernel config is **lane-agnostic**: both riscv64 lanes boot the one 7.3.4 Image,
  and both NEMU lanes the venue's kernel, all with `CONFIG_RISCV_USER_CFI=y`.
  <!-- UPDATED: /update-plan rev 4 - nemu-plain-kernel-ssp-panic: the original
       "(inert for unarmed binaries — the kernel arms per thread)" premise is refuted
       by measurement: with the guest DT advertising zicfiss, the kernel writes the
       U-mode ssp CSR (0x011) at the FIRST return to userspace, and the plain NEMU
       (master, no Zicfiss) raises illegal instruction - a total boot failure. CFI
       arming is gated on the PLATFORM ADVERTISEMENT, so the advertisement is scoped
       to the CFI variant lanes and the plain lanes boot an advertisement-free DT/CPU
       (measured: the plain qemu lane boots the same CONFIG_RISCV_USER_CFI kernel with
       an advertisement-free DT and runs 246 records green). -->
  Consequently no kernel cache-name suffix is introduced; the assert runs on the
  built `.config` before the cache write.
- Every new failure path names the missing thing and the command that produces it.
  Every new assert compares against a **built** artifact (`.config` in the kernel tree,
  the staged ELF, the DTB, `versions.txt`), never against the input you just wrote.
- Record, in the plan's History, anything the measurements in this plan predicted but
  the implementation measured differently (the plan carries several measured facts;
  they are the contract, not prose).
- **Round 8 was the pin bump; the pin has since moved once more** <!-- UPDATED:
     /update-plan rev 12 - bench-pin-moved-past-rev11 -->. Benchmark cycle 3 landed
  three commits: `2aaf895` (self-arm lock argument), `216da4ee` ("Fix the CFI-class
  stack-offset calibration and declare the allocator aborts"), and
  `182652b7efaadca7900beb3ce2a74ec3282e2565` ("Anchor the CFI-class calibration at the
  call's return site"). `182652b` supersedes `216da4ee`'s ra-capture, which the bench
  cycle measured dead (the helper has already scanned by then; reading `ra` into a
  caller local after the call helps nothing) and instead anchors the calibration at the
  call's return site; it is the pin `env.sh` now carries (the edit landed mid-round-6,
  unattested by a coder report — the tester filed it). The only env change here is
  `BENCH_COMMIT` `2aaf895…` → `182652b7efaadca7900beb3ce2a74ec3282e2565` plus the
  comment block above it. Do not touch `benchmark/` or any script. The pin bump again
  invalidates every stamp (the gate is pin-uniform), so the next tester round re-stamps
  all nine lanes.
- The bench-side defect ([defer-issue-cfi-self-arm-lock-arg](./tmp/reports/defer-issue-cfi-self-arm-lock-arg.json))
  is resolved bench-side; its retirement here rides the armed observation.
- **Round 7 is one defect, at three cleanup sites** <!-- UPDATED: /update-plan rev 10 -
     nemu-cfi-clean-swallowed-bench-arch-guard -->.
  [nemu-cfi-clean-swallowed-bench-arch-guard](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-nemu-cfi-clean-swallowed-bench-arch-guard.json)
  is measured evidence: `scripts/riscv64_nemu/prepare.sh:168` and
  `scripts/riscv64_nemu/run.sh:248` run `make -C benchmark clean >/dev/null 2>&1`
  under the recipe's inherited `MAKEFLAGS='ARCH=riscv64-nemu enable_riscv64_cfi=yes'`;
  the bench Makefile's guard dies (`enable_riscv64_cfi=yes requires ARCH=riscv64,
  not ARCH=riscv64-nemu`), the rc is discarded, and the venue's RISC-V
  `benchmark/run-test` survives — gitignored, so `git status --short` stays empty
  and the lane's clean assert passes — until the next host lane executes it under
  binfmt and fails. Apply the discipline `scripts/common/stage_corpus.sh:277`
  already uses at all three sites (`scripts/riscv64/run.sh:116` carries the same
  unchecked rc; both of its lanes pass today but the shape is the latent hazard):
  - run the clean as `env -u MAKEFLAGS -u MFLAGS -u ARCH -u enable_riscv64_cfi make -C benchmark clean`;
  - **treat a non-zero clean rc as a lane failure** — no `>/dev/null 2>&1` discard;
    the error text is the diagnosis;
  - assert `benchmark/run-test` is absent after the clean (a future variant cannot
    regress this silently), and keep `git -C benchmark status --short` empty as the
    existing invariant.
  The venue's in-submodule host-runner build (`venue/build-image.sh`) is deliberate
  and must not change. Round 7 is implemented and tester round 6 verified it with teeth
  (9/9) and in the real lane order.

### Coder `(auto)` checks by step
<!-- UPDATED: /update-plan rev 3 - coder-steps-lack-verification: the plan declared no
     coder-verifiable tier; these are the checks the round-1 report actually ran. -->
- **Step 1:** `grep -q '^BENCH_COMMIT=182652b' env.sh`; `grep -q QEMU_CPU_RISCV64_CFI
  env.sh`; `grep -q '^QEMU_BIOS_RISCV64=build/riscv64/fw_jump.bin' env.sh`;
  `grep -q RISCV64_GNU_PREFIX env.sh`; `grep -q NEMU_CFI_BIN_SHA256 env.sh`; sourcing
  `env.sh` under both `sh` and `bash` exits 0.
- **Step 2:** `make ARCH=riscv64 enable_riscv64_cfi=yes -n deploy` expands to
  `build_sbi.sh` then `build_image.sh riscv64-cfi` under the recipe-held lock;
  `make ARCH=riscv64-nemu enable_riscv64_cfi=yes -n run` names `riscv64-nemu-cfi`;
  `ARCH=aarch64` with the flag and `enable_riscv64_cheri=yes` alongside it both refuse.
- **Step 3:** `bash -n scripts/riscv64/build_kernel.sh`; `grep -q
  '^CONFIG_RISCV_USER_CFI=y' scripts/riscv64/qemu-virt.fragment`; the gate probe
  `"${RISCV64_GNU_PREFIX}gcc" -mabi=lp64 -march=rv64ima_zicfiss_zicfilp
  -fcf-protection=full -c -x c /dev/null -o /dev/null` exits 0.
- **Step 4:** `bash -n scripts/riscv64/build_sbi.sh`; the file names
  `NEMU_OPENSBI_COMMIT` and stages `build/riscv64/fw_jump.bin`; `run.sh` refuses a
  non-`default` `QEMU_BIOS_RISCV64` that is not a file.
- **Step 6:** `bash -n` on `build_image.sh` and `run.sh`; both select
  `QEMU_CPU_RISCV64_CFI` only for `riscv64-cfi`; `build_image.sh riscv64-nemu` and
  a missing `ENABLE_FLAG` refuse; the ISA-gate allowlist is scoped to the variant.
- **Step 7:** see the Step 7 bullet's `(auto)` check.
- **Step 8:** `bash -n scripts/common/version_stamp.sh`; `python3 -m py_compile
  scripts/common/compare_lanes.py`; `version_stamp.sh riscv64-cfi <tmp>` writes the
  stamp; `compare_lanes.py --lanes riscv64,riscv64-cfi --reference riscv64 --help`
  parses (the two variant names are in `KNOWN_LANES`).
- **Round 7 (cleanup):** `bash -n` on `scripts/riscv64_nemu/prepare.sh`,
  `scripts/riscv64_nemu/run.sh` and `scripts/riscv64/run.sh`; each of the three cleanup
  sites runs
  `env -u MAKEFLAGS -u MFLAGS -u ARCH -u enable_riscv64_cfi make -C benchmark clean`
  with its rc checked (no `>/dev/null 2>&1` discard); each asserts `benchmark/run-test`
  is absent afterwards and `git -C benchmark status --short` is empty; and a measured
  reproduction shows the pre-fix shape exiting 2 at the bench ARCH guard while the
  post-fix shape exits 0 and removes the artifact.

## Guidance for Tester

- Evidence over claims: every battery below writes its own log under
  `./tmp/verification/` and is invoked by a script listed in `## Plan Metadata`.
- The decisive test of this cycle is the **arming observation**: the CFI lanes' own
  results. If arming failed, every instrumented record exits 20 — that is a deployment
  defect, not a measurement. Diagnosis order (each has a measured failure signature):
  1. **Platform ISA advertisement** — the guest DT must carry `zicfiss` and `zicfilp`
     (qemu: the variant CPU pin's properties; NEMU: the patched venue DTS). Check the
     boot log's CPU node / `dmesg | grep -i -E 'zicfiss|zicfilp'` before anything else.
  2. **Kernel support** — the built `.config` had the symbol (deploy asserted it) and
     the live kernel did not boot with `riscv_nousercfi=` in its cmdline.
  3. **Firmware** — the boot log names the firmware; the kernel's FWFT probe must have
     succeeded (OpenSBI v1.9 advertises LANDING_PAD + SHADOW_STACK).
  4. **Self-arm** — the arm blob's canary: a locked enable that refuses a clear, and
     `ssrdp` non-zero (`benchmark/lib/posix/signal.cpp`).
- Expected residues are enumerated, never waved through: undeclared deliveries of 30 on
  records the registry does not declare for it (risk R5) are collected into an explicit
  list and deferred to a bench amendment cycle — the gate's non-zero exit is
  acceptable only with that list attached.
- Machine hygiene: the benchmark submodule worktree must be byte-clean before any lane
  run (`git -C benchmark status --short` empty). It is clean as of rev 9 (checked
  2026-11-18 after coder round 6; the foreign untracked entries R6 records were moved
  out of the tree).
- **Tester round 5 re-stamps ALL nine lanes at the new pin.** The bench amendment
  cycle's commit `2aaf895` replaces `d9cc4cd`, and the gate is pin-uniform: every
  existing stamp predates the bump and is not comparable. Run the full nine-lane
  battery (`x86_64`, `aarch64` ×4 variants, `riscv64`, `riscv64-nemu`, `riscv64-cfi`,
  `riscv64-nemu-cfi`) in the plan's Step 9 order. Kernel/venue caches warm the system
  lanes; the riscv64 deploy still rebuilds its Image.
- **This is the decisive armed observation.** With the bench lock argument fixed, the
  two CFI lanes should deliver the declared 30s (16 declared rows per lane); the three
  declared-31 rows stay benign-unfired. Collect the R5 residue (any undeclared 30) for
  a bench cycle if non-empty. A CFI record at 20 is still an arming failure; at 30 it
  is the expected delivery.
- **The round-4 code-20 expectation is historical.** In tester round 4 every CFI record
  returned 20 because of the bench lock-argument defect; that cycle was recorded FAILURE
  and the plan stayed open. The bench amend (commit `2aaf895`) supersedes it — round 5
  measured zero code-20 records, so arming is confirmed behaviourally.
- **Tester round 6's measurement, and what the next full round expects** <!-- UPDATED:
     /update-plan rev 12 - round-6 evidence + bench-pin-moved-past-rev11 -->. Round 6
  ran at `182652b` (the pin moved mid-round from `216da4ee`) and measured: all nine
  lanes deploy+run rc=0 and re-stamp 246 records with `run-status ok`; the seven
  established lanes gate-clean; the armed observation positive (no record at 20, ISA
  tags and `sspush`/`sspopchk`/`lpad` present, `.init_array` wired to
  `cfi_self_arm_entry` locking with `a1 = 0` and checking `ssrdp`, OpenSBI v1.9
  firmware identity, both venue DTBs two-sided); the gate exits 1 with all 25 findings
  dispositioned (3 R5 residue + 22 CFI-class registry gaps). Corrections to the rev-11
  predicted set, measured: the harness encodes a calibration success as result **0**
  (`run-test.cpp` maps `int(gvar())+32` and the frame-size 64 to 0), there are **three**
  ACC calibrators (`acc-get-frame-size`, `acc-get-ra-offset-v-p-g0/g1`), and the 200
  family measured as **136**.
  - **NEMU CFI lane:** declared-30 delivery went 2/16 → **12/16**; four offset-sweep
    rows still return 1 (`cfi-return-to-parent-non-call-site-by-vfunc`,
    `-same-call-site`, `-same-call-site-diffargs`, `-wrong-call-site-fakefunc`).
    Out-of-expect 0.
  - **qemu CFI lane:** unchanged from round 5 — calibrators 30/30/30, declared-30
    delivery **2/16**, out-of-expect 25 (3 residue + 22 registry gaps).
  Both are the deferred package
  ([defer-issue-riscv64-cfi-class-registry-gaps](./tmp/reports/defer-issue-riscv64-cfi-class-registry-gaps.json)):
  item (a) is done (the two 262 rows are declared and clear), item (b) is done on NEMU
  and open on qemu, item (c) (the qemu-vs-NEMU divergence) is open. The gate's
  non-zero exit remains an accepted outcome **only with the full disposition list
  attached and matched against that deferral**. Any new family is a finding, not a pass.
- **Tester round 7 is the closure round: static and scoring only, no lane run.**
  <!-- UPDATED: /update-plan rev 13 - finalize decision, user 2026-11-19: finalize now
       with the deferral --> The pin, the tree and all nine stamps are unchanged since
  round 6 (`182652b`, submodule clean) and no env code moved; a lane re-run would
  produce byte-identical evidence. Scope:
  - re-run the static battery, including **S1.1d** — every pin literal must now match
    `182652b` (rev 12 moved them; this closes [bench-pin-moved-past-rev11](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-bench-pin-moved-past-rev11.json));
  - verify the working tree is round 6's end state (pin, submodule cleanliness, the
    round-6/7/8 source sets, no new delta) — a new measured delta here is a BLOCKED
    round, never a pass;
  - **re-score round 6's armed-observation evidence against the deferral**: J1
    [riscv64-cfi] (calibrators 30/30/30) and C1 (2/16 qemu, 12/16 NEMU, four sweep
    rows at 1) are **expected with the disposition list attached** — they are
    [defer-issue-riscv64-cfi-class-registry-gaps](./tmp/reports/defer-issue-riscv64-cfi-class-registry-gaps.json)'s
    items (b)-qemu and (c), not round failures; verify the 25-finding gate disposition
    list still matches that deferral record exactly;
  - no deploy, no run, no new stamp.
  A SUCCESS here closes the plan's verification: the planner writes Final Results and
  hands off to /update-and-commit.
- **The lane-order defect must be re-exercised in the order that found it.** Tester
  round 5 found `nemu-cfi-clean-swallowed-bench-arch-guard` only because
  `riscv64-nemu-cfi` is immediately followed by `x86_64`; any re-run that skips the
  adjacency proves nothing about the fix. Record the post-clean state explicitly
  (`benchmark/run-test` absent, `git -C benchmark status --short` empty, the next host
  lane's own artifacts published).
- **Tester round 2 must not re-derive the two defects as passes.** The decisive
  checks: the CFI lanes produce stamps whose records include the declared 30s (not
  20s), and the plain `riscv64-nemu` stamp boots (the panic is gone). A CFI record
  at 20 is still an arming failure, not a measurement.

## Summary

Bench cycle 2 (self-arm, `d9cc4cd`) made every corpus binary arm Zicfiss at startup; the
delivery path (SIGSEGV/SEGV_CPERR → 30 backward / 31 forward) and the 19 registry rows
are in place. Nothing can observe them yet — user-mode CFI is blocked by **four**
independent gaps, each measured on this host:

1. **Kernel**: 6.18.56 has no `RISCV_USER_CFI` symbol at all (first release line: 7.0).
2. **Kernel toolchain**: the symbol's Kconfig gate is
   `$(cc-option,-mabi=lp64 -march=rv64ima_zicfiss_zicfilp -fcf-protection=full)`
   (v7.3.4 `arch/riscv/Kconfig:1206-1207`, fetched from the tag); gcc-13 fails it, so
   the symbol silently vanishes despite `def_bool y`. The exact command passes on
   GCC 16.1.0 (`rc 0`, measured; without `-mabi=lp64` it fails — the toolchain's
   default ABI is lp64d and the probe `-march` omits D).
3. **Firmware**: the kernel probes SBI FWFT for the LANDING_PAD/SHADOW_STACK features;
   OpenSBI v1.9 (already pinned as `NEMU_OPENSBI_COMMIT=cbf9f673…`) advertises them,
   QEMU's bundled firmware does not.
4. **Platform ISA advertisement**: neither platform advertises the extensions today.
   Measured 2026-11-17: `qemu-system-riscv64 -M virt,dumpdtb=… -cpu rva23s64` emits a
   guest DT with **no** `zicfiss`/`zicfilp` (0 hits over the decoded DTS), while
   `-cpu rva23s64,zicfiss=on,zicfilp=on` advertises both (2 hits); and the NEMU venue's
   generated guest DTS says `riscv,isa-extensions = "i","m","a","f","d","c","v","h"`
   (`build/riscv64-nemu/platform/generated-dts/xiangshan.dts.in:33-35`). RVA23 does not
   include the CFI extensions — they are opt-in CPU properties in QEMU and a template
   edit in the venue.

This cycle closes all four and performs the first armed observation:

- **Pin bump** `BENCH_COMMIT` `cbe3bf9` → `182652b` (via `d9cc4cd`, `2aaf895` and
  `216da4ee`, the pins the bench cycles corrected; full sha in Step 1).
- **Kernel 7.3.4** with `CONFIG_RISCV_USER_CFI=y`, built by **GCC 16.1.0**
  (`riscv64-unknown-linux-gnu-*`), asserted on the built `.config`.
- **OpenSBI v1.9** built as a generic `fw_jump` for the qemu-virt lane, replacing the
  `-bios default` pin.
- **CFI CPU model** for the qemu lane: `rva23s64,zicfiss=on,zicfilp=on`.
- **Venue DTS patch**: the generated guest DTS gains `zicfiss`/`zicfilp` before the
  firmware and DTB are compiled (env-side; the workload-builder pin stays frozen) —
  **CFI variant lanes only**; the plain NEMU lane boots an advertisement-free DT
  (user-CFI arming is gated on the platform advertisement; an advertised DT plus the
  plain interpreter is a measured boot panic).
- **Two variant lanes**: `riscv64-cfi` and `riscv64-nemu-cfi`, selected with
  `enable_riscv64_cfi=yes`, staging the corpus through the bench class (GCC 16
  toolchain, `-march=rv64gc_zicfilp_zicfiss -fcf-protection=full`, self-arm enabled).
  The NEMU variant pins the workspace `NEMU-cfi` checkout (`cfi-merge` @
  `668eb688a7478fa8863220d8f81033ed786f6bb9`, PR #1211, CFI-verified by the four
  cycles; interpreter sha256 `87091a763f1341b55cdaa7dfadc58efb97489d0d7f64092702ade5af6f747492`).
- **Re-stamp and gate** at the new pin across all nine host/guest qemu lanes, plus the
  armed observation the bench cycle made its precondition (R1): declared 30 on the 16
  declared rows; the undeclared-30 residue collected for a later bench amendment.

Cost model, stated honestly: the kernel tarball is cached (sha256-verified) but the qemu
lane's builder extracts a **fresh kernel tree and rebuilds `Image` on every deploy**
(`build_kernel.sh:72-76` — there is no version-keyed Image cache); the venue caches
`Image-$KERNEL_VER` per venue OUT. Each variant deploy therefore pays one kernel build
on its own OUT; a second riscv64 deploy reuses the shared `build/riscv64/Image` only if
it is still on disk (the kernel builder always rebuilds it, so in practice each deploy of
either qemu lane pays it). Deploys are serialized (lane lock across the whole recipe).

Out of scope (unchanged): x86 CET, CHERI guest boots, Zicfilp (forward-edge, 31) actual
enforcement — the pinned glibc 2.44 has no RISC-V CFI, so uninstrumented indirect
dispatch in any libc path makes LPE arming infeasible; the three 31 declarations stay
benign-unfired (attacks land at 0/1, which always pass). Note the CPU/DTS advertisement
closes the *platform* half of the Zicfilp question only; the libc half is the blocker.

## Repo Mode

Private

## Document Overrides

None.

## Risks

- **R1 — kernel 7.3.4 build under GCC 16.** New toolchain × new kernel line. The venue
  already passes `WERROR=0`; the qemu-lane builder gets the same treatment only if a
  warning blocks, and the change is stated in the step rather than silently applied.
  There is **no** Image cache to soften a failure: the tarball is cached, the build is
  not — a failed attempt costs one full rebuild.
- **R2 — firmware CFI chain.** User CFI needs an SBI advertising FWFT LANDING_PAD +
  SHADOW_STACK; OpenSBI v1.9 (`cbf9f673`) advertises them, QEMU's bundled firmware does
  not. If the generic `fw_jump` build or the kernel's FWFT probe fails under qemu-virt,
  the smoke evidence is exit 20 on every armed record (the self-arm blob's fail path) —
  diagnose from that plus the boot log, do not soften the assert.
- **R3 — platform ISA advertisement is a precondition of its own** (measured, fourth
  blocker): without the qemu variant CPU pin and the venue DTS patch, arming fails even
  with all three other gaps closed. These are the plan's cheapest fixes and the easiest
  to regress (a CPU-pin edit, a template patch) — the tester asserts the guest-visible
  ISA before trusting any armed result.
- **R4 — NEMU variant boots a 7.3.4 guest.** The NEMU venue was last measured on
  6.18.56; the kernel runs as guest code under the interpreter, and its SBI calls are
  executed by the OpenSBI build the venue already carries (v1.9, same commit). Risk is
  new kernel code paths (SBI version probes, FWFT calls) hitting an NEMU corner. The
  lane's boot log and console parse are the evidence; a failure is diagnosed, not
  worked around by dropping the kernel bump for this lane.
- **R5 — corpus-wide arming delivers 30 where the registry does not declare it.** Every
  corpus binary is armed (the class flag reaches the whole corpus build), so test
  families that write a return address on the stack outside the CFI classification —
  the ACC family's stack-offset calibrators and stack-corrupting cases, the mss
  stack-write records — may now be caught by the shadow stack and exit 30 where the
  registry expects 0/1. (The `cfi-return-*` family is **not** an example: 16 of its rows
  already declare 30.) This is intended security behaviour and an expected registry
  gap — collect the exact set and defer it to a bench amendment cycle. The gate's exit
  is non-zero for those rows and that is recorded, not silenced.
- **R6 — submodule worktree dirt blocks every lane run (measured 2026-11-17).** The
  benchmark submodule root carries **nine** untracked entries: eight zero-byte dotfiles
  (`.bash_profile .bashrc .gitconfig .mcp.json .profile .ripgreprc .zprofile .zshrc`)
  plus `.gitmodules`, all dated 2026-11-16 23:42, none part of the bench repo. The
  lanes' post-run "submodule clean" asserts will trip on them. They must be moved out of
  the tree by the user (the workflow never deletes files; these are not workflow
  artifacts) before the first lane run — Step 1 carries the preflight that names them.
- **R7 — the plain riscv64 lane's boot changes too.** The new kernel, the built
  firmware and the CFI CPU-model-less boot are lane-wide pins for the riscv64 family;
  the plain lane's stamps move with them. That is deliberate (one environment, one
  pin), but the README's Known caveats and the stamps' firmware/provenance lines must
  say so — a stamp must name the firmware it booted.
- **R8 — the armed class's corpus-wide effect is wider than R5 anticipated (measured
  2026-11-18).** Tester round 5 measured 29 records outside their declared sets (not
  only 30s: 260/267/262/216/192/184/200 on qemu, code 2 on NEMU), only 2/16 declared-30
  rows delivering because the ACC calibration rows are themselves caught, and a
  qemu-vs-NEMU divergence on byte-identical corpus binaries. That package is
  [deferred to a bench amendment cycle](./tmp/reports/defer-issue-riscv64-cfi-class-registry-gaps.json);
  until it lands, the CFI lanes' gate result is an expected non-zero with the
  disposition list attached, never a silent pass.

## Rollback

Revert is the cycle's single consolidated commit: restore `env.sh` (all pins), the
`Makefile` variant block, and the modified scripts. The two variant lanes are purely
additive — they vanish with their Makefile entries and their lane-keyed trees. `build/`
and `results/` are generated and gitignored (a re-deploy is required after a revert;
`results/` stamps stay as historical evidence). The `benchmark` submodule pointer moves
with `BENCH_COMMIT` in the same commit and reverts with it. No bench-repo or
workload-builder pin is edited, so no external state needs unwinding.

## Proposed Changes

1. **Step 1:** Add the cycle's pins to `env.sh` and export them.
   - `BENCH_COMMIT=182652b7efaadca7900beb3ce2a74ec3282e2565` (the bench
     amendment cycle's commit; superseded the earlier `d9cc4cd` pin at rev 9).
   - `KERNEL_VERSION=7.3.4`, `KERNEL_URL=https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.3.4.tar.xz`,
     `KERNEL_SHA256=b11b6df8295e8e991ff040b71aaa4994a8b55caa23b6b092907f195b5840fd1f`
     (from kernel.org's signed `sha256sums.asc`).
   - `RISCV64_GNU_PREFIX` — the GCC 16.1.0 toolchain prefix, **repo-relative sibling
     default** `: "${RISCV64_GNU_PREFIX:=../riscv/bin/riscv64-unknown-linux-gnu-}"`,
     resolved against the repo root like `NEMU_DIR`/`NEMU_BIN` (the same
     `case … /*)` absolute-override handling), with a preflight
     `[ -x "${RISCV64_GNU_PREFIX}gcc" ]` that dies naming the path. It supplies the
     kernel CC for both kernel builds and the corpus CXX/AS/OBJDUMP for the CFI
     variants. The existing `RISCV64_CXX/CC/AS/OBJDUMP` (gcc-13) stay the lane default —
     busybox and the plain lanes' corpus do not move.
   - `QEMU_CPU_RISCV64_CFI=rva23s64,zicfiss=on,zicfilp=on` — the CFI variant's CPU
     request (measured: the base `rva23s64` advertises neither extension, the property
     form advertises both). The plain lane's `QEMU_CPU_RISCV64` is unchanged.
   - `QEMU_BIOS_RISCV64` changes from `default` to `build/riscv64/fw_jump.bin`
     (repo-relative; `scripts/riscv64/run.sh` passes it to `-bios` with cwd at the repo
     root). This applies to **both** riscv64 lanes — one firmware pin per platform
     (R7); the change is deliberate and documented, not an accident of the variant.
   - NEMU variant pair, in the documented overridable form:
     `: "${NEMU_CFI_DIR:=../NEMU-cfi}"`,
     `: "${NEMU_CFI_BIN:=$NEMU_CFI_DIR/build/riscv64-nemu-interpreter}"`,
     `NEMU_CFI_COMMIT=668eb688a7478fa8863220d8f81033ed786f6bb9`,
     `NEMU_CFI_BIN_SHA256=87091a763f1341b55cdaa7dfadc58efb97489d0d7f64092702ade5af6f747492`
     (measured). The NEMU lane scripts swap the `NEMU_DIR`/`NEMU_BIN`/`NEMU_COMMIT`
     trio for the `NEMU_CFI_*` values **and export them** (Step 7). Do not repoint the
     plain `riscv64-nemu` lane.
   - **No new OpenSBI URL pin**: `build_sbi.sh` clones `NEMU_OPENSBI_URL` at
     `NEMU_OPENSBI_COMMIT` — add a comment on that block that the pin now also feeds the
     qemu lane's `fw_jump` build. One pin per input.
   - Preflight (stated in the lane-header comments and re-stated in the hand-off):
     `git -C benchmark status --short` empty, with the nine-entry R6 list named in the
     die message.
   **Files to modify:**
   - `./env.sh`

2. **Step 2:** Wire the variant lanes into the root `Makefile`.
   - Mirror the aarch64 variant pattern (`Makefile:71-97`): when
     `enable_riscv64_cfi=yes` and `ARCH` ∈ {`riscv64`, `riscv64-nemu`},
     `ENABLE_FLAG := enable_riscv64_cfi`, `LANE_NAME := $(ARCH)-cfi`; `$(error …)` for
     any other ARCH, and for combining it with `enable_riscv64_cheri`.
   - Thread `ENABLE_FLAG=$(ENABLE_FLAG)` and `LANE_NAME` into the riscv64 recipes
     (`Makefile:231-253`) and the riscv64-nemu recipes (`Makefile:255-275`): the
     scripts take `$(LANE_NAME)` as their lane argument and read `ENABLE_FLAG` from the
     environment. Their `run` legs pass `LANE_RUN_TIMEOUT` as today.
   - `riscv64` deploy: take the lane lock for the **whole recipe** (today only
     `build_image.sh` locks, `Makefile:233-241`; the kernel and firmware builders write
     the shared `build/riscv64/` outside it) and gain the firmware leg:
     `timeout $(LANE_DEPLOY_TIMEOUT) bash scripts/riscv64/build_sbi.sh` before
     `build_kernel.sh`.
   - `clean`: variant trees now live under `build/$(LANE_NAME)` (Step 6), so
     `rm -rf build/$(LANE_NAME)` is complete **and** the shared kernel/`Image` and
     `fw_jump.bin` under `build/riscv64/` survive. State in the recipe comment that a
     plain-lane `rm -rf build/riscv64` also removes the shared inputs (re-deploy
     required) but not the variant trees.
   **Files to modify:**
   - `./Makefile`

3. **Step 3:** Kernel 7.3.4 + user CFI in the qemu-lane kernel builder.
   - `scripts/riscv64/build_kernel.sh`: switch the kernel make to the GCC 16 toolchain —
     `CROSS_COMPILE="${RISCV64_GNU_PREFIX}"`, `CC="${RISCV64_GNU_PREFIX}gcc"` (the
     prefix already ends in `-`; do not append another). The header comment states the
     rebuild-per-deploy cost (no Image cache). Before `olddefconfig`, run the Kconfig
     gate's exact probe once
     (`"${RISCV64_GNU_PREFIX}gcc" -mabi=lp64 -march=rv64ima_zicfiss_zicfilp -fcf-protection=full -c -x c /dev/null -o /dev/null`)
     and die naming the toolchain if it fails — the failure otherwise only appears as a
     missing symbol after a full kernel build.
   - `scripts/riscv64/qemu-virt.fragment`: add `CONFIG_RISCV_USER_CFI=y` (the fragment
     merge accepts exactly `CONFIG_X=y` lines, `build_kernel.sh:84-95`).
   - Extend the built-`.config` assert list (`build_kernel.sh:102-109`) with
     `CONFIG_RISCV_USER_CFI` and adjust the die message: the symbol's absence under a
     toolchain without `-fcf-protection` support is the expected failure and the message
     must say the kernel CC is the GCC 16 pin.
   **Files to modify:**
   - `./scripts/riscv64/build_kernel.sh`
   - `./scripts/riscv64/qemu-virt.fragment`

4. **Step 4:** Build the qemu-virt firmware from the pinned OpenSBI.
   - New `scripts/riscv64/build_sbi.sh`: clone/refresh `NEMU_OPENSBI_URL` at
     `NEMU_OPENSBI_COMMIT` into a cached source dir under `build/` (the venue's
     `ensure_checkout` idiom: a cached checkout is reused only after
     `git rev-parse HEAD` equals the pin **and** `git status --short` is empty; a
     partial/foreign tree dies rather than being cloned into), build `PLATFORM=generic`
     with `CROSS_COMPILE="${RISCV64_GNU_PREFIX}"`, stage
     `build/platform/generic/firmware/fw_jump.bin` as `build/riscv64/fw_jump.bin`, and
     assert the staged file is non-empty. Offline once the source cache exists; a cold
     run needs network — the header states that, as the venue's does. The staged file's
     `sha256sum` is recorded in the lane stamp (Step 6).
   - `scripts/riscv64/run.sh`: **add** the firmware existence preflight
     (`[ -f "$QEMU_BIOS_RISCV64" ] || die "… missing - run make ARCH=<lane> deploy
     first"`, with the literal-`default` keyword still accepted for backward
     compatibility) — today only `$IMAGE`/`$CPIO` are checked and `-bios` takes the raw
     pin (`:49-50`, `:89`).
   **Files to modify:**
   - `./scripts/riscv64/build_sbi.sh`
   - `./scripts/riscv64/run.sh`

5. **Step 5:** Teach the one staging orchestrator both CFI variants.
   - `scripts/common/stage_corpus.sh`: the lane case (`:62-68`) gains
     `riscv64-cfi|riscv64-nemu-cfi` (with its die message updated); the enable-flag
     whitelist (`:69-76`) gains `enable_riscv64_cfi:riscv64-cfi` and
     `enable_riscv64_cfi:riscv64-nemu-cfi` — the whitelist keys on the value that will
     actually arrive (`${ENABLE_FLAG_ARG}:$LANE`), so the variant's own lane name is the
     key and its scratch tree/log under `build/$(LANE)/` are truly separate; an empty
     `--enable-flag` value becomes a usage error (exit 2), not `none`.
   - The toolchain case (`:154-168`) gains the two variant arms:
     `CXX="${RISCV64_GNU_PREFIX}g++"`, `ASM="${RISCV64_GNU_PREFIX}as"`,
     `OBJDUMP="${RISCV64_GNU_PREFIX}objdump"`, `VER_CXX` likewise, and
     `SHIM_PREFIX=$OBJDUMP` (the **absolute tool path**, which `shim.sh`'s `/*` branch
     accepts — an absolute *prefix* is not a valid shim argument and dies "not an
     executable"); `BENCH_ARCH=riscv64`, `TOKEN=riscv64`, `LANE_FLAG=enable_riscv64_cfi`
     — the existing export at `:262` then puts the class flag into the corpus
     invocation's environment, which is the whole interface the bench needs.
   - **The class flag must not reach the host-side makes.** The parent deploy's
     `make ARCH=… enable_riscv64_cfi=yes` exports the flag into this script's
     environment (a command-line make variable rides the environment into every
     child). The two host-side invocations — the `[1/5]` scratch-tree clean and the
     `[2/5]` host-runner build — clear `MAKEFLAGS`/`MFLAGS`/`ARCH` but must also drop
     the incoming class flag itself (unset it by its own name after the whitelist, or
     add `-u enable_riscv64_cfi` to both `env` invocations), or the bench Makefile's
     own guard fires (`enable_riscv64_cfi=yes requires ARCH=riscv64, not
     ARCH=x86_64`). Only the `[3/5]` corpus build may see it, re-exported there from
     `LANE_FLAG`.
     <!-- UPDATED: /update-plan rev 4 - stage-corpus-class-flag-env (tester round 1):
          measured - both variant deploys aborted at the [1/5] scratch clean with the
          bench ARCH guard; the round-1 code cleared MAKEFLAGS/ARCH but not the flag. -->
   - Add a default arm to the toolchain case (`*) di "unknown lane"; exit 2`) and,
     before `:262`, assert `BENCH_ARCH` and `TOKEN` are non-empty for every lane and
     `LANE_FLAG` is non-empty exactly when `--enable-flag` was supplied (`set -u` does
     not catch a case-arm that forgot an assignment; the unflagged `riscv64` /
     `riscv64-nemu` arms legitimately set an empty `LANE_FLAG`, so a blanket non-empty
     assert would break them).
     <!-- UPDATED: /update-plan rev 3 - stage-corpus-lane-flag-assert: the original
          "LANE_FLAG non-empty" contradicted the unflagged lanes it must not break;
          the flag-conditional assert preserves the intent. -->
   - `(auto)` check: `bash -n scripts/common/stage_corpus.sh`; the arg/whitelist
     probes the round-1 coder report lists (empty `--enable-flag` exits 2; the CFI
     flag on `riscv64` exits 2; the CFI flag on each variant lane is accepted).
   **Files to modify:**
   - `./scripts/common/stage_corpus.sh`

6. **Step 6:** Variant the qemu-lane image and run scripts.
   - `scripts/riscv64/build_image.sh`: accept `riscv64` **or** `riscv64-cfi` as the lane
     argument (today it rejects anything but `riscv64`, `:27-30`). When the variant is
     selected: `ENABLE_FLAG` must equal `enable_riscv64_cfi` (die otherwise), the
     staging call passes `--enable-flag enable_riscv64_cfi` **and** the variant lane
     argument, and `BUILDD` becomes `$ROOT/$BUILD_DIR/$LANE` (i.e. `build/riscv64-cfi`)
     — one lane-keyed tree, no leaf suffixes; the shared `build/riscv64/Image` is a
     read-only input (`IMAGE="$ROOT/$BUILD_DIR/riscv64/Image"`), with its own existence
     preflight naming the deploy.
   - **The variant's toolchain override must cover every consumer**, set once near the
     top: `RISCV64_CXX/RISCV64_CC/RISCV64_AS/RISCV64_OBJDUMP` (hence `RISCV64_CROSS`,
     `READELF` and the shim) → the GCC 16 pins. The consumers are: the shim call
     (`:81`), the scheduler/libcfi build (`:84`), the crt1.o baseline (`:113`, via
     `$RISCV64_CC -print-file-name=crt1.o`) and the glibc NEEDED/PT_INTERP closure
     (`:186-188`, via `$RISCV64_CXX -print-file-name`) — the corpus links against the
     GCC 16 sysroot's glibc 2.44, so staging gcc-13's 2.43 libc would ship the wrong
     runtime.
   - **Closure placement is the second half of that requirement.** Resolving the right
     files is not enough: this loader searches its own compiled-in dirs. Measured
     2026-11-18 — the GCC 16 `ld-linux-riscv64-lp64d.so.1` searches
     `/lib64/lp64d/` and `/usr/lib64/lp64d/` only (its PT_INTERP is
     `/lib/ld-linux-riscv64-lp64d.so.1`), while the apt gcc-13 loader also searches
     `/lib/`. A variant closure staged flat under `/lib` therefore fails the first
     userspace exec (`libstdc++.so.6: cannot open shared object file`). For the
     variant, stage the NEEDED closure into `/lib64/lp64d/` and keep the loader at its
     PT_INTERP path `/lib/ld-linux-riscv64-lp64d.so.1`; the plain lane's flat `/lib`
     staging is unchanged. Add a deploy assert that every staged ELF's NEEDED sonames
     exist in a directory the staged loader actually searches — **with the ELF
     interpreter exempt**: the loader's own soname (`ld-linux-riscv64-lp64d.so.1`)
     appears as an ordinary NEEDED of `libc.so.6`, but it is opened at `execve` from
     the PT_INTERP path and is never searched for; the assert must accept the staged
     PT_INTERP path for interpreter sonames while keeping every other NEEDED
     search-dir-bound.
     <!-- UPDATED: /update-plan rev 5 - cfi-guest-loader-search-path (tester round 2):
          user decision 2026-11-18: stage into the GCC 16 loader's own dir. -->
     <!-- UPDATED: /update-plan rev 6 - cfi-closure-assert-interp (tester round 3): the
          rev-5 assert as written rejected libc.so.6's NEEDED on the interpreter's own
          soname and aborted the qemu variant deploy; the exemption is part of the
          requirement, mirrored at the venue (Step 7). -->
   - The scheduler/libcfi cross-build (`:83-84`) runs with **`ARCH=riscv64`** (the bench
     token, as the venue already does) and with `env -u MAKEFLAGS -u MFLAGS` — the
     deploy's own `enable_riscv64_cfi=yes` in MAKEFLAGS otherwise trips the bench
     Makefile's ARCH guard, and `lib/riscv64-cfi/` has no sources.
   - The RVA23 ISA gate (`assert_rva23_fit`, `:113-137`): the GCC 16 toolchain's own
     crt1.o baseline does **not** carry `zicfilp`/`zicfiss`/`zimop`, but every class-built
     ELF's `Tag_RISCV_arch` does (measured) — so for the CFI variant the accepted set is
     the toolchain baseline **plus a class allowlist** (`zicfilp`, `zicfiss`, `zimop`),
     scoped strictly to the variant so the plain lane's gate is byte-identical. The
     assert keeps its teeth: anything outside both sets still dies.
   - `scripts/riscv64/run.sh`: accept the variant lane; `BUILDD` reads the variant tree
     (`rootfs.cpio` under `build/$(LANE)`) while `IMAGE` stays the shared
     `build/riscv64/Image`; keep `DEST="$RESULTS_DIR/$LANE/$STAMP"` (already lane-keyed,
     `:47`); pass the real `ENABLE_FLAG` into `version_stamp.sh` (today `:66` hardcodes
     `ENABLE_FLAG=""`); record the firmware (`sha256sum "$QEMU_BIOS_RISCV64"` or its
     `NEMU_OPENSBI_COMMIT`) in the stamp's provenance; assert `versions.txt` was written
     before publishing (mirroring the aarch64 lane's stamp assert).
   - The variant's `make ARCH=riscv64 enable_riscv64_cfi=yes run` boots with
     `QEMU_CPU_RISCV64_CFI` — this is where the pinned CPU request takes effect.
   **Files to modify:**
   - `./scripts/riscv64/build_image.sh`
   - `./scripts/riscv64/run.sh`

7. **Step 7:** Variant the NEMU lane.
   - `scripts/riscv64_nemu/prepare.sh` / `scripts/riscv64_nemu/run.sh`: accept
     `riscv64-nemu-cfi`; when the variant is active, `OUT` becomes
     `build/riscv64-nemu-cfi/platform` and `CORPUS` `build/riscv64-nemu-cfi/corpus`
     (lane-keyed, so the variant `clean` covers them; its own venue OUT means its own
     kernel build, and the variant OUT is a cold source root — seed `$OUT/src` from the
     plain lane's `build/riscv64-nemu/platform/src` when present so the three pinned
     clones are not re-fetched, and state the offline precondition per OUT), and the
     `NEMU_DIR`/`NEMU_BIN`/`NEMU_COMMIT` trio is replaced by the `NEMU_CFI_*` values
     **and exported before each venue leg** — the venue scripts re-source `env.sh`,
     whose `:=` defaults then preserve the exported values; without the export the
     venue records and boots the plain interpreter. Preflights: the checkout's HEAD
     equals `NEMU_CFI_COMMIT`, `git status --short` empty (warn + stamp marker
     otherwise, mirroring the plain lane), and `sha256sum "$NEMU_CFI_BIN"` equals
     `NEMU_CFI_BIN_SHA256` (die naming the rebuild command) — a HEAD check alone says
     nothing about the binary.
   - `prepare.sh:202`'s staging call gains `--enable-flag enable_riscv64_cfi` and the
     variant lane argument; post-condition: the variant's `manifest.json`/captured build
     log names the GCC 16 toolchain (an unarmed gcc-13 duplicate must not pass as a
     "cfi" deploy).
   - `scripts/riscv64_nemu/run.sh`: `DEST` lane-keyed (`$RESULTS_DIR/$LANE/$STAMP` —
     today hardcoded `riscv64-nemu` at `:129`), `version_stamp.sh` receives `$LANE` and
     the real `ENABLE_FLAG` (`:193`), the provenance block records the CFI checkout and
     binary sha, and `versions.txt` is asserted before publishing. The venue's deploy
     meta must record the CFI binary so run.sh's "binary is not the one the deploy
     recorded" check passes.
   - `scripts/riscv64_nemu/venue/build-image.sh`, guest-kernel leg (lane-agnostic —
     both NEMU lanes get the same kernel): `CONFIG_RISCV_USER_CFI=y` joins the printf
     block at `:193`; the kernel make (`:196-197`) uses
     `CROSS_COMPILE="${RISCV64_GNU_PREFIX}"` and `CC="${RISCV64_GNU_PREFIX}gcc"`
     (local to the kernel leg — busybox, gcpt and opensbi ride the exported knobs, see
     the toolchain-coherence bullet); the symbol assert loop (`:198-201`) gains
     `CONFIG_RISCV_USER_CFI` with a message naming the toolchain requirement; the cache
     name stays `Image-$KERNEL_VER` (the version bump invalidates every existing cache,
     and the assert runs before the cache write — a config-hash suffix would be dead
     machinery for a lane-agnostic config).
   - **Variant toolchain coherence (whole guest, not just the kernel).** For the variant
     lane the guest scheduler/libcfi cross-build (`[5/8]`), the NEEDED/PT_INTERP glibc
     closure (`[6/8]`, resolved through `$CXX -print-file-name`) and the `sys_info`
     compiler line must all use the GCC 16 pin, because the corpus staged by Step 5 is
     GCC 16-built. When the variant is active, `prepare.sh` replaces the exported
     `CXX/CC/ASM/OBJDUMP/CROSS_COMPILE/READELF` with `RISCV64_GNU_PREFIX` tools before
     either venue leg (mirroring Step 6); the plain `riscv64-nemu` lane keeps gcc-13
     byte-for-byte. busybox/gcpt/OpenSBI then ride the same exported knobs for the
     variant (one toolchain, one sysroot). The variant's closure must also be PLACED in
     the GCC 16 loader's own search dirs (`/lib64/lp64d/`, loader at its PT_INTERP
     path), exactly as Step 6 requires for the qemu lane — resolving the right files is
     not enough — including the interpreter-soname exemption in the reachability
     assert, so the two asserts agree. The plain lane keeps the flat `/lib` placement
     its gcc-13 loader searches.
     <!-- UPDATED: /update-plan rev 3 - venue-cfi-toolchain-asymmetry: the original
          "busybox, gcpt, opensbi and the corpus keep the existing pins" left the guest
          scheduler and glibc closure on gcc-13 while the corpus is GCC 16-built -
          exactly the closure mismatch Step 6 names as its reason to override every
          consumer. The variant's whole guest toolchain moves together; plain lane
          unchanged. -->
   - **Guest DTS ISA advertisement** (measured blocker): the venue's generated
     `$OUT/generated-dts/xiangshan.dts.in` advertises no `zicfiss`/`zicfilp`
     (`:33-35`), and OpenSBI v1.9's FWFT SHADOW_STACK is gated on its DT hart-feature
     detection, so both firmware and kernel are blind to the extensions. Raise it with
     the env-side **dtc interposer** `scripts/riscv64_nemu/venue/dtc-cfi.sh`: the venue
     installs it into `$OUT` at mode 0755 and passes it to `build-firmware-linux.sh`
     through that script's own `DTC` environment hook. The interposer appends
     `zicfilp`/`zicfiss` to `riscv,isa-extensions` (and `riscv,isa`) on the DTS dtc is
     handed, then execs the real dtc; the venue asserts the **compiled** DTB (not the
     template) carries both, since workload-builder regenerates the template inside
     `build-firmware-linux.sh`. The workload-builder pin stays frozen. **Scoped to the
     CFI variant lane only**: the interposer runs when `ENABLE_FLAG=enable_riscv64_cfi`
     (the value the Makefile hands `prepare.sh`, which reaches the venue leg through
     the environment); the plain `riscv64-nemu` lane compiles an advertisement-free DT
     and the venue asserts the **negative** — its compiled DTB carries neither string —
     because with an advertisement the 7.3.4 kernel writes the `ssp` CSR at the first
     userspace return and the plain pinned interpreter (no Zicfiss) panics (measured,
     tester round 1: `build/riscv64-nemu/platform/runs/20261117-210859/boot.log`).
     <!-- UPDATED: /update-plan rev 3 - venue-dts-template-regenerated: the planned
          "patch the generated template" point does not survive - workload-builder
          rewrites the template milliseconds before dtc reads it; the DTC env hook is
          the surviving patch point. Implemented in coder round 1. -->
     <!-- UPDATED: /update-plan rev 4 - nemu-plain-kernel-ssp-panic (tester round 1):
          the rev-2/3 "apply for both NEMU lanes (inert for unarmed guests)" premise
          is refuted - user-CFI arming is gated on the platform advertisement, so the
          advertisement moves lanes with the variant, and the plain lane gains a
          negative DTB assert. User decision 2026-11-17: scope-to-variant. -->
   - `(auto)` check: `bash -n` on `prepare.sh`, `run.sh`, `venue/build-image.sh` and
     `venue/dtc-cfi.sh`; the dtc interposer's smoke run compiles a DTB carrying
     `zicfiss`/`zicfilp`; `make -n ARCH=riscv64-nemu enable_riscv64_cfi=yes deploy` and
     `run` expand with lane `riscv64-nemu-cfi` and `ENABLE_FLAG=enable_riscv64_cfi`.
   **Files to modify:**
   - `./scripts/riscv64_nemu/prepare.sh`
   - `./scripts/riscv64_nemu/run.sh`
   - `./scripts/riscv64_nemu/venue/build-image.sh`
   - `./scripts/riscv64_nemu/venue/dtc-cfi.sh`

8. **Step 8:** Teach the gate tooling the variant lanes.
   - `scripts/common/version_stamp.sh`: the lane whitelist (`:30-36`) gains
     `riscv64-cfi|riscv64-nemu-cfi` (explicit entries mirroring the aarch64 precedent;
     a `riscv64-*` wildcard would also accept a typo). Verified today: the script exits
     2 for the new names, and both run wrappers call it under `set +e` — a refused
     stamp is silent, and `compare_lanes.py` then reports the lane absent.
   - `scripts/common/compare_lanes.py`: `KNOWN_LANES` (`:50-58`) gains the two variant
     names so `--lanes …` and `--stamp` overrides parse; decide the default `LANES`
     tuple explicitly in the code comment — the default stays the seven established
     lanes (a variant lane's presence is a deliberate gate argument), and Step 9's gate
     invocation names all nine.
   **Files to modify:**
   - `./scripts/common/version_stamp.sh`
   - `./scripts/common/compare_lanes.py`

9. **Step 9:** Deploy, run, re-stamp and gate — the armed observation (tester-executed).
   - Deploy order (the lane lock is global and now held across each deploy recipe):
     `riscv64` → `riscv64-cfi` → `riscv64-nemu` → `riscv64-nemu-cfi`; run each after
     its deploy. Then the established lanes for a pin-uniform gate: `x86_64`, `aarch64`
     (plain, `pa`, `bti`, `mte`), plus the four riscv64 lanes above. CHERI lanes stay
     outside (guest boots still deferred).
   - **Spot-check the two measured preconditions before believing any armed result**:
     the qemu variant's guest DT carries `zicfiss`/`zicfilp` (dump DTB / boot log), and
     the QEMU firmware is the built `fw_jump` (boot log / sha).
   - `compare_lanes.py` at the new pin across the nine lanes with an **explicit
     `--stamp` per lane** (the newest-stamp heuristic refuses a stamp that carries a
     `versions.txt` but no `results.json`; a failed run must not mask the compare —
     record an exit-2 refusal as its own outcome, never as a pass). Expected: the armed
     lanes' 16 declared rows deliver 30 (declared verdict); the three 31 rows stay
     unfired; R5 residue = every other record where the CFI lanes return 30 —
     enumerated with record name, plain-lane code, CFI-lane code.
   - Arming-discrimination check before believing any armed result: the CFI lanes'
     results must not be 20 across the instrumented records (arming failure — walk the
     Guidance-for-Tester diagnosis order); cross-check one staged binary host-side
     (`readelf -A` for `zicfiss`/`zicfilp` in `Tag_RISCV_arch`, `objdump -d` for the
     `.init_array`-pointed arm entry).
   - The R5 residue list is deferred through `/defer-issue` to a bench amendment cycle
     (the bench repo owns the registry). The gate's exit code and the residue list are
     recorded together; neither is presented without the other.
   **Files to modify:**
   - `./tmp/verification/2026-11-17-env-riscv64-cfi-gate.py`
   - `./tmp/verification/2026-11-17-env-riscv64-cfi-armed-observation.py`

10. **Step 10:** Documentation and pin bookkeeping at the new pins.
   - `README.md`: Pins table (`BENCH_COMMIT`, kernel, OpenSBI, GCC 16 pin, NEMU-cfi,
     CPU models row's `-bios` wording); lane bullets and Usage table (two variant
     lanes); **the kernel figures in the riscv64 and riscv64-nemu lane bullets
     ("Linux 6.18.56" → 7.3.4)**; the Prerequisites bullet that says the riscv64 lane
     boots "`-bios default`" (now the built `fw_jump`, qemu-system-data's blobs no
     longer the lane's firmware source); the **seven-lane sentences** in "Comparing
     lanes" and "Known caveats" (nine executable lanes; the default gate set stays
     seven and the variants are explicit `--lanes` arguments — or the final intended
     set, decided once in Step 8's comment and mirrored here); the Output-layout tree
     (`fw_jump.bin`, the lane-keyed variant trees); exact record counts touched by the
     registry growth replaced with measure-on-demand phrasing (the
     `configure.json`/`compare_lanes.py` command) or a dated snapshot; Known caveats'
     stamps honestly marked as predating/preceding the bump, and the plain riscv64
     lane's kernel/firmware move recorded (R7).
   - `CLAUDE.md`: Purpose (the two CFI variants named), Structure (new script, venue
     variant), Commands (the variant flag), Architecture (variant wiring, the
     lane-keyed-tree rule: shared kernel/firmware, separate corpus/stage/rootfs).
   - `doc/lanes.html`: both riscv64 lane pages gain the variant section (arming chain:
     platform ISA advertisement → kernel USER_CFI → FWFT → self-arm blob → 30/31
     delivery), the built-firmware wording replacing "OpenSBI's default firmware", the
     firmware build leg in the deploy description, and the GCC 16 prefix in the
     riscv64-family Host-prerequisites cells; `doc/architecture.html`: the staging flag
     path, the variant tree layout and the deploy paragraph; `doc/content.html`: the
     lane table rows (including their "Linux 6.18.56" cells → 7.3.4).
   - Commit gate: `git -C benchmark rev-parse HEAD` equals `env.sh`'s `BENCH_COMMIT`
     (`182652b`), `git -C benchmark status --short` empty.
   **Files to modify:**
   - `./README.md`
   - `./CLAUDE.md`
   - `./doc/lanes.html`
   - `./doc/architecture.html`
   - `./doc/content.html`

## Guidance for Planner

- This plan was authored by the researcher session that ran the two bench cycles
  (`benchmark` commits `1aa6928`, `d9cc4cd`) and verified their landings; the source
  note is `./tmp/research/nemu-cfi-verification-bench-proposals-2026-11-16.md` (§6.5 for
  the self-arm cycle, §2 for the kernel facts). The 7.3.4 Kconfig text and the two
  platform-ISA measurements were taken this session (rev 2).
- Both bench cycles' plans were pre-audited by this session; this plan's pre-audit is
  `./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-mega-audit-2026-11-17.json` (76
  findings; the two rejected ones and their refutations are in the Issue Log row).
- The load-bearing assumptions are the four measured blockers in the Summary — three of
  them (kernel toolchain gate, qemu CPU advertisement, venue DTS) are cheap to verify
  and were the audit's High findings. Step 9's discrimination check decides the rest
  empirically.
- Do not let a R5 residue be folded into "expected": it is a registry gap for the bench
  repo and travels as a deferred issue.
- Step 9 re-stamps seven established lanes; if the wall-clock cost is unacceptable the
  planner may split the re-stamp into its own cycle, but then the gate must still run
  the CFI lanes against their plain counterparts at one pin, with the split stated in
  the plan's History.

## History

| Date | Event | Outcome |
|------|-------|---------|
| 2026-11-17 | Plan drafted (researcher session; facts from bench cycles 1–2 + kernel/OpenSBI/GCC16 measurements) | — |
| 2026-11-17 | Mega-audit pre-audit (76 findings: 26 High / 29 Medium / 21 Low) persisted to `./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-mega-audit-2026-11-17.json` | rev 2 — 74 accepted, 2 rejected ([41] premise refuted by measurement; [18] repo-convention conflict). Material additions: the CFI CPU-model pin (measured: `rva23s64` advertises no zicfilp/zicfiss, the property form advertises both), the venue DTS ISA patch (measured), the GCC-16 toolchain override covering every build_image consumer (glibc 2.44 vs 2.43 closure), lane-keyed variant trees replacing leaf suffixes, `version_stamp.sh`/`compare_lanes.py` in the change set, the NEMU `${NEMU_CFI_*}` export to venue children + binary sha pin, the firmware preflight, the metadata-contract fix, and the doc-sync items |
| 2026-11-17 | Coder round 1 + spec revision (/update-plan rev 3) | Steps 1–8 implemented (14 files; session report `tmp/reports/2026-11-17-env-riscv64-cfi-lanes-coder-2026-11-17.json`), no tester evidence yet — the four new issues are `Fix Planned`, not `Resolved`. Changes: Step 5's assert reworded to "LANE_FLAG non-empty iff `--enable-flag` supplied" (the original contradicted the unflagged lanes); Step 7's template-patch point replaced by the measured mechanism — workload-builder regenerates the template inside `build-firmware-linux.sh`, so the venue interposes on the builder's `DTC` env hook (`scripts/riscv64_nemu/venue/dtc-cfi.sh`, asserted on the compiled DTB); Step 7 gains variant toolchain coherence — the guest scheduler, glibc closure and `sys_info` move to the GCC 16 pin with the corpus (plain lane unchanged); Steps 1–8 gain explicit `(auto)` checks. Round 2 is a delta: only Step 7's toolchain export remains. |
| 2026-11-17 | Coder round 2 (delta) | Step 7's variant toolchain coherence implemented (`prepare.sh` selects the GCC 16 knobs for `riscv64-nemu-cfi`, gcc-13 for the plain lane; `venue/build-image.sh` now honours the exported knobs with `:-` fallbacks, since it previously re-derived them from the env pins and would have clobbered the export — the plan's "busybox/gcpt/OpenSBI ride the same exported knobs" required this). Report `tmp/reports/2026-11-17-env-riscv64-cfi-lanes-coder-2026-11-17-2.json`; no new issues. All four plan-scoped issues remain `Fix Planned` pending tester evidence. |
| 2026-11-17 | Tester round 1 (full nine-lane Step 9) + spec revision (/update-plan rev 4) | Round result FAILURE (session report `tmp/reports/2026-11-17-env-riscv64-cfi-lanes-tester-2026-11-17.json`, 106 checks: 96 pass / 10 fail). Static battery 74/74 twice; the Kconfig gate, GCC 16 kernel build, OpenSBI v1.9 fw_jump, CFI CPU-model advertisement (and its plain negative control), and the venue kernel config + compiled DTB all verified closed at the new pin; riscv64/x86_64/aarch64×4 green; six-lane pin-uniform comparison exit 0. Two blocking defects filed: [stage-corpus-class-flag-env](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-stage-corpus-class-flag-env.json) — the exported class flag reaches stage_corpus's host-side makes and trips the bench ARCH guard (both variant deploys abort); [nemu-plain-kernel-ssp-panic](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-nemu-plain-kernel-ssp-panic.json) — the "USER_CFI is inert for unarmed binaries" premise is refuted: with the DT advertising zicfiss the 7.3.4 kernel writes the ssp CSR at the first userspace return and the plain pinned interpreter panics. Rev 4: the class flag is dropped from the host-side staging makes; the DTS advertisement is scoped to the CFI variant with a plain-lane negative DTB assert (user decision 2026-11-17: scope-to-variant); Guidance premise corrected. The nine-lane gate refused (exit 2) on the mixed pin — riscv64-nemu has no new-pin stamp; it completes after the fixes re-run. |
| 2026-11-17 | Coder round 3 (defect fixes) | Both Fix Planned defects implemented: `stage_corpus.sh` drops the exported class flag from its two host-side makes (reproduced the bench ARCH guard before, clean recipe after); `venue/build-image.sh` selects the dtc interposer only for the CFI variant and makes the compiled-DTB check two-sided (positive for the variant, negative for the plain lane). The refuted "inert for unarmed binaries" claim is restated in `env.sh`, `qemu-virt.fragment`, `venue/dtc-cfi.sh` and `venue/build-image.sh`. Report `tmp/reports/2026-11-17-env-riscv64-cfi-lanes-coder-2026-11-17-3.json`; no new issues. Tester round 2 scoped to the three affected lanes + the nine-lane gate (six green stamps reused, rev-4 Guidance). |
| 2026-11-18 | Tester round 2 + spec revision (/update-plan rev 5) | Round result FAILURE (report `tmp/reports/2026-11-17-env-riscv64-cfi-lanes-tester-2026-11-18.json`; 103 checks: 96 pass / 7 fail). Both round-1 defects verified fixed: the plain `riscv64-nemu` lane boots an advertisement-free DT and publishes a 246-record green stamp (225/21), and both CFI variant deploys stage and build cleanly — the four `Fix Planned` rows move to `Resolved` on tester evidence. One new blocking defect: [cfi-guest-loader-search-path](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-cfi-guest-loader-search-path.json) — the GCC 16 closure is staged flat under `/lib`, but that loader searches only `/lib64/lp64d/` and `/usr/lib64/lp64d/` (measured 2026-11-18; the apt gcc-13 loader also searches `/lib/`), so both variant runs die at the first userspace exec (`libstdc++.so.6: cannot open shared object file`). Rev 5 adds closure placement into the GCC 16 loader dirs at both closure sites with a NEEDED-resolution deploy assert (user decision 2026-11-18: stage-into-loader-dir). Seven-lane pin-uniform gate green at `d9cc4cd` (riscv64-nemu 225/21, identical to riscv64); the nine-lane gate refused on the two absent variant stamps. |
| 2026-11-18 | Coder round 4 (closure placement) | The remaining defect fixed at both closure sites: the CFI variants now stage their NEEDED closure into the GCC 16 loader's own dir (`/lib64/lp64d/`, loader at its `/lib` PT_INTERP path), the plain lanes keep flat `/lib` byte-equivalently, and a deploy-side reachability assert fails a NEEDED soname outside the staged loader's search dirs before the rootfs is packed. Two-sided probe: 154/153 ELFs, 0 unreachable on both plain trees, 652/599 unreachable (every one staged elsewhere) on the pre-fix variant trees. Report `tmp/reports/2026-11-17-env-riscv64-cfi-lanes-coder-2026-11-18.json`; no new issues. The two remaining planner-side rows (`stage-corpus-lane-flag-assert`, `coder-steps-lack-verification`) are closed on the tester batteries' evidence. Tester round 3 re-deploys/runs only the two variants and completes the nine-lane gate. |
| 2026-11-18 | Tester round 3 + spec revision (/update-plan rev 6) | Round result FAILURE (report `tmp/reports/2026-11-17-env-riscv64-cfi-lanes-tester-2026-11-18-2.json`; 118 checks: 110 pass / 7 fail / 1 skipped). The loader-search-path placement fix is verified at the venue — `riscv64-nemu-cfi` boots on the pinned CFI interpreter and executes all 246 records from the GCC 16 closure — and the qemu variant's staged tree is measured correct. Two new blocking findings: [cfi-closure-assert-interp](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-cfi-closure-assert-interp.json) (env-side: the reachability assert rejects `libc.so.6`'s NEEDED on the interpreter's own soname, aborting the qemu deploy) and [cfi-self-arm-lock-arg](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-cfi-self-arm-lock-arg.json) (bench-side: the arm blob passes `-1` to `PR_LOCK_SHADOW_STACK_STATUS`, but kernel 7.3.4's `arch_lock_shadow_stack_status` requires `0`; all 246 records exit 20). Rev 6: the interpreter exemption joins the assert (both sites); the bench defect is DEFERRED to a bench amendment cycle (out of this repo's write scope; user decision 2026-11-18: fix + re-run + keep the plan open). The platform/firmware/kernel/DTS/toolchain half of the arming chain is measured green. |
| 2026-11-18 | Tester round 4 (env acceptance met; bench defect remains) + Issue Log dedup | Report `tmp/reports/2026-11-17-env-riscv64-cfi-lanes-tester-2026-11-18-3.json` (143 checks: 139 pass / 4 fail). The round-5 interpreter exemption is verified statically (89/89), behaviourally (12/12 teeth harness: the exemption admits the real GCC 16 closure and the plain shape; an unstaged interpreter, an unstaged ordinary NEEDED, and INTERP_NAMES membership without a staged file all still die at both sites) and end to end: `riscv64-cfi` deploy rc=0 (10m09s) and both CFI variants publish complete 246-record stamps at `d9cc4cd` with `flag enable_riscv64_cfi=yes`. Nine-lane gate exit 1 (recorded) whose entire 246-row-per-lane diff is code 20; armed observation B1 = 246×20, C1 = 0/16, R5 residue empty. Every env-side requirement is met; the only remaining blocker is the deferred bench defect `cfi-self-arm-lock-arg`. Issue Log duplicates collapsed; `cfi-closure-assert-interp` and `cfi-guest-loader-search-path` Resolved. The plan stays OPEN (user decision 2026-11-18) until a bench amendment cycle lands (lock arg 0) and `BENCH_COMMIT` is bumped, then the two variants re-run and the cycle finalizes. |
| 2026-11-18 | Bench amendment cycle landed — resume (rev 8) | Benchmark commit `2aaf895bc29eab29fb7f38a6a4737aec5d62beca` is DONE: the self-arm blob's lock step now `li a1, 0` and its mask comment is rewritten to the RISC-V truth; the bench plan `benchmark/plans/2026-11-18-bench-cfi-self-arm-lock-arg.md` records implementation + 19-check static verification, with the behavioural gate explicitly this cycle's. Resume: coder round 6 bumps `BENCH_COMMIT` `d9cc4cd…` → `2aaf895…`; tester round 5 then re-stamps ALL nine lanes at the new pin (the gate is pin-uniform; no `d9cc4cd` stamp is comparable). Expected outcome: the 16 declared-30 rows per CFI lane deliver 30, the three declared-31 rows stay benign-unfired, and the R5 residue is collected (or empty) for a bench cycle if non-empty. |
| 2026-11-18 | Coder round 6 landed + spec revision (/update-plan rev 9) | Coder round 6 did exactly the delta: `env.sh`'s `BENCH_COMMIT` is `2aaf895bc29eab29fb7f38a6a4737aec5d62beca`, `git -C benchmark rev-parse HEAD` matches it and the submodule is clean; no other file touched (report `tmp/reports/2026-11-17-env-riscv64-cfi-lanes-coder-2026-11-18-3.json`). It filed [stale-bench-pin-literals](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-stale-bench-pin-literals.json): rev 8's bump mandate left three `d9cc4cd` literals in the plan, one of them Step 1's `(auto)` check, which was unsatisfiable in the round's mandated final state. Rev 9 rewrites those three (Step 1 `(auto)` check, Proposed Changes Step 1 bullet, Step 10 commit gate) plus the title, the premise bullet and the step-narrative pin chain to `2aaf895`; remaining `d9cc4cd` mentions are historical narrative. Tester round 5 is the decisive armed observation. |
| 2026-11-18 | Tester round 5 + spec revision (/update-plan rev 10) | Report `tmp/reports/2026-11-17-env-riscv64-cfi-lanes-tester-2026-11-18-4.json` (177 checks: 173 pass / 4 fail). **The decisive armed observation succeeds**: zero records at 20 on either CFI lane, so the deferred bench defect `cfi-self-arm-lock-arg` is fixed behaviourally and its row goes Resolved (the standalone deferral retires with it); SEGV_CPERR 30 deliveries measured (5 qemu / 2 NEMU), ISA tags + `sspush`/`sspopchk`/`lpad` in the staged corpus, advertisement / OpenSBI v1.9 FWFT / kernel `.config` / venue DTB scoping / NEMU binary identity all green, and all nine lanes re-stamp 246 records at `2aaf895` with `run-status ok` (the seven established lanes gate-clean). Two findings: [nemu-cfi-clean-swallowed-bench-arch-guard](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-nemu-cfi-clean-swallowed-bench-arch-guard.json) — blocking env-side: the NEMU-CFI lane's `make -C benchmark clean` inherits the class flag, dies at the bench ARCH guard with the rc discarded, leaves the venue's RISC-V `run-test` (gitignored, so the clean assert passes) and the next host lane executes it under binfmt (`x86_64` rc=2; reproduced 7/7 and passes on a clean tree); and [riscv64-cfi-class-registry-gaps](./tmp/reports/defer-issue-riscv64-cfi-class-registry-gaps.json) — the armed class moves 29 records outside their declared sets, only 2/16 declared-30 rows deliver (the ACC calibration rows are themselves caught so dependents report 1), and qemu vs NEMU diverge on byte-identical binaries. Rev 10: coder round 7 fixes the cleanup at all three sites (drop MAKEFLAGS/MFLAGS/ARCH/class flag, fail on a non-zero rc, assert `benchmark/run-test` absent); the CFI-class package is DEFERRED to a bench amendment cycle and the full nine-lane re-stamp (tester round 6) waits for it (user decision 2026-11-18: wait for the bench fix, then the full re-run). The plan stays OPEN. |
| 2026-11-18 | Coder round 7 (lane-cleanup defect) | The blocking env defect implemented at all three sites: `scripts/riscv64_nemu/prepare.sh`, `scripts/riscv64_nemu/run.sh` and `scripts/riscv64/run.sh` now run the submodule clean as `env -u MAKEFLAGS -u MFLAGS -u ARCH -u enable_riscv64_cfi make -C benchmark clean`, treat a non-zero rc as a lane failure (no `>/dev/null 2>&1` discard), and assert `benchmark/run-test` is absent afterwards so a future variant cannot regress the residue silently. Report `tmp/reports/2026-11-17-env-riscv64-cfi-lanes-coder-2026-11-18-4.json` (build_result pass, no new issues, exactly the three files). Tester verification belongs to round 6 at the post-bench-cycle pin (user decision 2026-11-18: bench fix first, then the full nine-lane re-run). |
| 2026-11-18 | Bench class-gap commit landed + spec revision (/update-plan rev 11) | Benchmark cycle 3's second commit `216da4ee575e22e0c5084153b15609d15690a926` ("Fix the CFI-class stack-offset calibration and declare the allocator aborts") is in the submodule and the worktree is clean: `acc/get-ra-offset.cpp` now captures the call's return site from `ra` on the class (the `lpad 0` at the computed-goto label plus 4-byte alignment defeats a label-address scan), and code 262 is declared on the two large-count data rows. Its message names the behavioural re-run and the qemu-vs-NEMU divergence as this cycle's gates. Rev 11: pin literals/title/premise/commit gate move to `216da4ee`; coder round 8 is the delta pin bump; tester round 6 is the final full nine-lane re-stamp with an explicit predicted set (calibrators publish, the two 262 rows clear, the remaining qemu out-of-expect families stay the deferred package). |
| 2026-11-18 | Tester round 6 + spec revision (/update-plan rev 12) | Report `tmp/reports/2026-11-17-env-riscv64-cfi-lanes-tester-2026-11-18-5.json` (183 checks: 179 pass / 4 fail). The round-7 env fix is RESOLVED with teeth: the three cleanup sites' extracted invocations clean under the real inherited MAKEFLAGS (rc=0, `benchmark/run-test` removed) while the pre-fix shape still dies rc=2 and leaves the residue (9/9), and in the battery's own order `riscv64-nemu-cfi` -> `x86_64` publishes its own stamp rc=0 with the tree clean (18/18 lane steps). All nine lanes re-stamp 246 records, `run-status ok`, seven lanes gate-clean; the armed observation is positive; the gate exits 1 with all 25 findings dispositioned to the deferral. The pin moved mid-round: `182652b` ("Anchor the CFI-class calibration at the call's return site") supersedes `216da4ee`'s ra-capture as measured dead; `env.sh` carries it, the submodule is clean, but no coder report attests the edit (filed). Substance: qemu CFI stays 2/16 (calibrators 30/30/30, out-of-expect 25, identical to round 5) while NEMU improves 2/16 -> 12/16 (four offset-sweep rows at 1) - both are the open deferral's items (b)-qemu and (c), with item (a) now done. Rev 12 moves every pin literal to `182652b`, corrects the predicted set to the measured encoding (calibration success = 0; three calibrators; 136 not 200), and records the deferral's per-item state. |
| 2026-11-19 | Tester round 7 (closure) + spec revision (/update-plan rev 13) | Report `tmp/reports/2026-11-17-env-riscv64-cfi-lanes-tester-2026-11-19.json`: **SUCCESS, 130/130**, static and scoring only (no deploy, no run, no new stamp). The tree is round 6's end state (pin `182652b`, submodule HEAD == pin and clean, no newer coder file or stamp); the static battery is 96/96 with S1.1d closing the stale-pin finding; the re-scored armed evidence matches rev 12's expected set exactly (zero at 20; qemu 2/16 with calibrators 30/30/30; NEMU 12/16 with exactly the four named sweep rows at 1; R5 residue 3 qemu / 0 NEMU; 22 non-30 qemu out-of-expect by code {260:14, 267:4, 216:1, 192:1, 184:1, 136:1}; zero on NEMU; no new family), and a fresh gate reproduces the byte-identical 25-finding disposition set, every record mapping onto the open deferral. One plan step is unexecuted and filed: [step10-docs-unexecuted](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-step10-docs-unexecuted.json) — the five keep-in-sync pages still pin bench `cbe3bf9`, kernel 6.18.56, `-bios default` and seven lanes; the planner executes Step 10 inside /update-and-commit. The env-side product is complete; the cycle finalizes (user decision 2026-11-19: finalize now with the deferral). |

## Plan Metadata

```json
{
  "plan_id": "2026-11-17-env-riscv64-cfi-lanes",
  "steps": [
    "Step 1: Add the cycle's pins to env.sh and export them.",
    "Step 2: Wire the variant lanes into the root Makefile.",
    "Step 3: Kernel 7.3.4 + user CFI in the qemu-lane kernel builder.",
    "Step 4: Build the qemu-virt firmware from the pinned OpenSBI.",
    "Step 5: Teach the one staging orchestrator both CFI variants.",
    "Step 6: Variant the qemu-lane image and run scripts.",
    "Step 7: Variant the NEMU lane.",
    "Step 8: Teach the gate tooling the variant lanes.",
    "Step 9: Deploy, run, re-stamp and gate — the armed observation (tester-executed).",
    "Step 10: Documentation and pin bookkeeping at the new pins."
  ],
  "coder_files": [
    "./env.sh",
    "./Makefile",
    "./scripts/common/stage_corpus.sh",
    "./scripts/common/version_stamp.sh",
    "./scripts/common/compare_lanes.py",
    "./scripts/riscv64/build_kernel.sh",
    "./scripts/riscv64/build_sbi.sh",
    "./scripts/riscv64/build_image.sh",
    "./scripts/riscv64/qemu-virt.fragment",
    "./scripts/riscv64/run.sh",
    "./scripts/riscv64_nemu/prepare.sh",
    "./scripts/riscv64_nemu/run.sh",
    "./scripts/riscv64_nemu/venue/build-image.sh",
    "./scripts/riscv64_nemu/venue/dtc-cfi.sh"
  ],
  "tester_files": [
    "./tmp/verification/2026-11-17-env-riscv64-cfi-gate.py",
    "./tmp/verification/2026-11-17-env-riscv64-cfi-armed-observation.py"
  ],
  "verification_scripts": [
    "./tmp/verification/2026-11-17-env-riscv64-cfi-gate.py",
    "./tmp/verification/2026-11-17-env-riscv64-cfi-armed-observation.py"
  ],
  "doc_files": [
    "./README.md",
    "./CLAUDE.md",
    "./doc/lanes.html",
    "./doc/architecture.html",
    "./doc/content.html"
  ],
  "repo_mode": "Private",
  "document_overrides": []
}
```

## Audit Accumulation

| Audit | Date | Findings | Accepted | Rejected | Outcome |
|-------|------|----------|----------|----------|---------|
| [mega-audit](./tmp/reports/2026-11-17-env-riscv64-cfi-lanes-mega-audit-2026-11-17.json) | 2026-11-17 | 76 (26H/29M/21L) | 74 | 2 | rev 2 |

## Documentation

See Step 10. The keep-in-sync pages bind to `env.sh` and `scripts/`: `README.md` (pins,
lanes, prerequisites, output layout, known caveats), `doc/lanes.html` (per-lane mechanics
and pin rationale), `doc/architecture.html` (dispatcher, staging, deploy), `doc/content.html`
(lane table), `CLAUDE.md` (purpose, structure, commands, architecture).

## Final Results

**Status: COMPLETED (2026-11-19).** Two armed RISC-V CFI lanes (`riscv64-cfi`,
`riscv64-nemu-cfi`) exist, deploy and execute the full 246-record corpus at bench pin
`182652b`, publishing provenance-stamped results; the nine-lane dispatcher is
pin-uniform and gate-clean on the seven established lanes.

### Files changed

- `env.sh` — bench pin, kernel 7.3.4, OpenSBI pin, GCC 16 prefix, CFI CPU model,
  built firmware path, `NEMU_CFI_*` pins, all exported with rationale blocks.
- `Makefile` — the two variant lanes (flag → lane name), the riscv64 deploy's
  recipe-wide lock with inheritance, the variant run legs.
- `scripts/common/stage_corpus.sh` — variant lanes, enable-flag whitelist and asserts,
  the class-flag drop from both host-side makes.
- `scripts/common/version_stamp.sh`, `scripts/common/compare_lanes.py` — variant lane
  names in the whitelist and `KNOWN_LANES`.
- `scripts/riscv64/build_kernel.sh` — GCC 16 cross build with the exact `USER_CFI`
  Kconfig gate probe; `scripts/riscv64/build_sbi.sh` (new) — OpenSBI v1.9 `fw_jump`;
  `scripts/riscv64/build_image.sh` — GCC 16 closure, `/lib64/lp64d` placement with the
  interpreter exemption, ISA allowlist scoping, `cpu_model` provenance;
  `scripts/riscv64/run.sh` — variant CPU pin, firmware preflight and provenance.
- `scripts/riscv64/qemu-virt.fragment` — `CONFIG_RISCV_USER_CFI=y`.
- `scripts/riscv64_nemu/prepare.sh`, `run.sh` — variant lane, `NEMU_CFI_*` pins and
  binary sha, venue seeding, GCC 16 knobs.
- `scripts/riscv64_nemu/venue/build-image.sh`, `venue/dtc-cfi.sh` (new) — variant
  kernel/toolchain legs and the DTS ISA advertisement scoped to the variant.
- All three lane-cleanup sites — `env -u MAKEFLAGS -u MFLAGS -u ARCH -u
  enable_riscv64_cfi make -C benchmark clean`, non-zero rc fails the lane,
  `benchmark/run-test` must be absent.
- `benchmark` submodule pointer — `cbe3bf9` → `182652b` (read-only; no bench source
  edited from this repo).

### Test results

- Tester round 7 (closure): **130/130 SUCCESS**, static + scoring.
- Tester round 6 (full battery at `182652b`): 179/183; the four failures were the
  plan's stale pin (closed by rev 12/13) and the deferred bench deliveries.
- All nine lanes deploy+run rc=0, 246 records each, `run-status ok`; nine-lane gate
  exits 1 with all 25 findings dispositioned (3 R5 residue + 22 CFI-class registry
  gaps), seven established lanes clean.
- Armed observation: zero records at code 20; SEGV_CPERR 30 deliveries; `zicfiss`/
  `zicfilp` in `Tag_RISCV_arch` with `sspush`/`sspopchk`/`lpad`; `.init_array` wired to
  `cfi_self_arm_entry` (lock with `a1 = 0`, `ssrdp` readback); OpenSBI v1.9 firmware
  identity; both venue DTBs two-sided; kernel 7.3.4 `USER_CFI` `.config`.

### Issues resolved

Fourteen rows: the mega-audit, seven implementation defects, the closure/loader/
interpreter chain, the plain-lane ssp panic, the plan-verification gap, the two
stale-pin bookkeepings and the test-toolchain asymmetry.

### Deferred

**riscv64-cfi-class-registry-gaps** (bench/research package; report
`defer-issue-riscv64-cfi-class-registry-gaps.json`). The armed class's corpus-wide
effects are wider than the registry declares:

- item (a) **done** — the two 262 rows are declared and clear;
- item (b) **done on NEMU** (calibrators publish; declared-30 delivery 2/16 → 12/16)
  and **open on qemu** (calibrators still 30/30/30, declared-30 2/16, out-of-expect 25:
  260 ×14, 267 ×4, 216, 192, 184, 136);
- item (c) **open** — the qemu-vs-NEMU divergence on byte-identical corpus binaries is
  unadjudicated; one implementation is not enforcing what the other does.

The four NEMU offset-sweep rows still at 1
(`cfi-return-to-parent-non-call-site-by-vfunc`, `-same-call-site`,
`-same-call-site-diffargs`, `-wrong-call-site-fakefunc`) belong to the same package.
These are registry/attack-staging and implementation-conformance questions owned by
the bench repo and the NEMU CFI research cycles — not env-side defects.
