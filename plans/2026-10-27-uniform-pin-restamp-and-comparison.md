# Plan: uniform bench pin, lane-guard hardening, and the first cross-lane comparison
**Project:** cpu-sec-test-env (lane dispatcher for cpu-sec-bench)
**Plan ID:** 2026-10-27-uniform-pin-restamp-and-comparison
**Created:** 2026-10-27

## Issue Log

Rows ordered newest-first (latest issues at top). New issues are prepended; resolved issues stay in place with updated status. Every row marked Resolved below retires its report through `/update-and-commit` once the plan's evidence lands (presence of `./tmp/reports/defer-issue-*.json` means open).

| Issue | Status | Found | Resolved | Resolved By |
|-------|--------|-------|----------|-------------|
<!-- UPDATED 2026-10-27: two tester-filed findings prepended as Fix Planned (post-tester revision, user-approved: env-side bti fix); both Resolved by coder round 3 + the tester's bti re-stamp and gate re-run (exit 0, 178/178) -->
| `<plan-id>-bti-lane-build-class-sigills-on-default-cpu-model` — bench f9e4ba7's STRIP_PAC() emits xpaci under the bti class's `-march=armv8.5-a`, and the lane's unset QEMU_CPU has no FEAT_PAuth: five records SIGILL (260), the gate exits 1 | Resolved | 2026-10-27 | 2026-10-27 | coder round 3 (`QEMU_CPU_AARCH64_BTI=max` + bti deploy smoke) + tester (re-stamp: the five records read 0; gate exit 0) ([report](../reports/2026-10-27-uniform-pin-restamp-and-comparison-bti-lane-build-class-sigills-on-default-cpu-model.json)) |
| `<plan-id>-retired-stamp-dir-shadows-newest-selection` — the plan-mandated `retired-<pin>/` directories sort after timestamps and become the comparison tool's "newest stamp", so the default-selection gate command exits 2 | Resolved | 2026-10-27 | 2026-10-27 | coder round 3 (versions.txt-based selection filter) + tester (selection-filter controls 12/12; the plan's literal gate command exits 0) ([report](../reports/2026-10-27-uniform-pin-restamp-and-comparison-retired-stamp-dir-shadows-newest-selection.json)) |
<!-- UPDATED 2026-10-27: two coder-filed gaps prepended as Fix Planned (see History, Spec revision); both Resolved by the round-2 implementation and the tester's controls replay -->
| `<plan-id>-riscv64-cheri-stamps-default-run-status-ok` — the riscv64 and both CHERI collectors never pass RUN_STATUS, so a failed run's evidence stamp would record `run-status: ok` | Resolved | 2026-10-27 | 2026-10-27 | coder round 2 (implementation) + tester (stamp controls 12/12, riscv64 lane re-stamp) ([report](../reports/2026-10-27-uniform-pin-restamp-and-comparison-riscv64-cheri-stamps-default-run-status-ok.json)) |
| `<plan-id>-lane-lock-truncating-open-elsewhere` — nine lane scripts still truncating-open the lane lock, wiping the holder's name before the contention check | Resolved | 2026-10-27 | 2026-10-27 | coder round 2 (implementation) + tester (lock controls 14/14) ([report](../reports/2026-10-27-uniform-pin-restamp-and-comparison-lane-lock-truncating-open-elsewhere.json)) |
| `defer-issue-env-docs-registry-swap-text` — the env CLAUDE.md and riscv64_nemu diagnostics describe the bench registry swap the bench removed | Resolved | 2026-10-27 | 2026-10-27 | Step 2 controls (swap 7/7) + planner doc edits ([report](../reports/defer-issue-env-docs-registry-swap-text.json)) |
| `defer-issue-aarch64-pa-calibration-cascade` — the pa lane's RA-offset calibration cannot run under PAC-ret; 10 return-hijack records were precondition failures | Resolved | 2026-10-27 | 2026-10-27 | tester (Step 6 pa evidence: offsets stored, both heap-memcpy records 0, `cfi-return-without-call` 19) ([report](../reports/defer-issue-aarch64-pa-calibration-cascade.json)) |
| `defer-issue-aarch64-collector-required-artifacts` — an absent results.json/results.dat publishes a versions-only stamp and reports success | Resolved | 2026-10-27 | 2026-10-27 | tester (collect-aarch64 8/8, collect-x86 5/5) ([report](../reports/defer-issue-aarch64-collector-required-artifacts.json)) |
| `defer-issue-aarch64-run-lock-gap` — the aarch64 `run` recipe releases the lane lock between prepare.sh and run.sh | Resolved | 2026-10-27 | 2026-10-27 | tester (lock controls 14/14: single acquisition across both legs, verified marker, fd closure) ([report](../reports/defer-issue-aarch64-run-lock-gap.json)) |
| `defer-issue-aarch64-smoke-flags-pin-coupling` — prepare.sh's lane-representative smokes duplicate the corpus build flags with no cross-check against the pinned benchmark/Makefile | Resolved | 2026-10-27 | 2026-10-27 | tester (flags controls 26/26) ([report](../reports/defer-issue-aarch64-smoke-flags-pin-coupling.json)) |
| `defer-issue-submodule-pin-unverified` — the aarch64 and system-lane scripts never assert the benchmark submodule HEAD equals env.sh's BENCH_COMMIT | Resolved | 2026-10-27 | 2026-10-27 | tester (pin controls 8/8; flags controls' pin-drift refusals) ([report](../reports/defer-issue-submodule-pin-unverified.json)) |

## Immediate Actions

<!-- UPDATED 2026-10-27 (third revision): Steps 1-8 are implemented and verified — coder rounds 1-3 and tester rounds 1-2 (178/178, gate exit 0 over all seven lanes). This round has ONE item: the stale env.sh comment the round-3 report's out_of_scope note flags. Do not redo any earlier step. -->

**This section is for the final micro coder round.** All plan steps are done and verified. The single open item:

1. **env.sh MTE comment** — the round-3 report's out_of_scope note 4: the MTE comment block (~line 68) still reads "which is why the pa pin below is load-bearing and this one is not". The MTE half stays true; the pa half now understates — the bti pin below is load-bearing too (see the bti comment block and [the tester's Step 8 verification](../reports/2026-10-27-uniform-pin-restamp-and-comparison-tester-2026-10-27-2.json)). Update the sentence to name both load-bearing pins ("the pa and bti pins below are load-bearing and this one is not"). Touch nothing else in env.sh.

Verify: `bash -n env.sh`; the comment reads true against the two request blocks below it. Write the round report.

## Guidance for Coder

**Files to modify:** source code only — no CLAUDE.md, README.md, doc/**, or project .md files.

- `./env.sh`
- `./Makefile`
- `./scripts/common/version_stamp.sh`
- `./scripts/common/build_corpus.sh`
- `./scripts/common/compare_lanes.py` (new)
- `./scripts/aarch64/prepare.sh`
- `./scripts/aarch64/run.sh`
- `./scripts/riscv64_nemu/prepare.sh`
- `./scripts/riscv64_nemu/run.sh`
- `./scripts/riscv64/run.sh` <!-- UPDATED 2026-10-27: RUN_STATUS pass (Step 1 follow-up) and append-open (Step 4 follow-up) -->
- `./scripts/riscv64/build_image.sh` <!-- UPDATED 2026-10-27: append-open -->
- `./scripts/cheri_riscv64/prepare.sh` <!-- UPDATED 2026-10-27: append-open -->
- `./scripts/cheri_riscv64/run.sh` <!-- UPDATED 2026-10-27: RUN_STATUS pass and append-open -->
- `./scripts/morello/prepare.sh` <!-- UPDATED 2026-10-27: append-open -->
- `./scripts/morello/run.sh` <!-- UPDATED 2026-10-27: RUN_STATUS pass and append-open -->
- `./scripts/cheri/stage_sources.sh` <!-- UPDATED 2026-10-27: append-open -->
- `./scripts/cheri/build_image.sh` <!-- UPDATED 2026-10-27: append-open -->
- `./scripts/cheri/build_emulator.sh` <!-- UPDATED 2026-10-27: append-open -->

**Step-by-step with verification:** every coder step below carries its checks inline, tagged `(auto)` or `(scripted)`; the coder self-verifies `(auto)` checks and runs the provided script for `(scripted)` checks. Tester owns the behavioral checks. Step 6 is tester-owned (lane runs are verification), and Step 7's retirements happen through the Issue Log rows.

## Guidance for Tester

**Tests to create:**
- **Permanent:** none — this repo's permanent checks are its scripts' own guards; the plan commits one new tool (`scripts/common/compare_lanes.py`) whose behavioural contract is covered by a temporary fixture suite.
- **Temporary:**
  - `./tmp/verification/2026-10-27-uniform-pin-restamp-and-comparison-controls.py` — the guard controls: pin drift, smoke-flag drift (block removal and missing file), collector required/optional behaviour (both lanes), the lock pair including the holder-name and marker-spoof cases, and the comparison tool's fixture matrix (twelve cases below). <!-- UPDATED 2026-10-27 (Step 8): extends with the bti-smoke control (an xpaci-bearing bti-class build executes under the pinned request) and the selection-filter control (a planted retired-<pin> directory is never selected). -->
  - `./tmp/verification/2026-10-27-uniform-pin-restamp-and-comparison-restamp.py` — the seven-lane re-stamp driver. It uses the shared tracer (`live_trace` from `~/.claude/scripts/`) for per-lane progress, heartbeat, external-call counters and a flushed trace file under `./tmp/` (watchdog reports only, never terminates), and the post-run comparison invocation. <!-- UPDATED 2026-10-27 (Step 8): after the coder lands Step 8, re-stamp aarch64-bti only (its prior f9e4ba7 stamp retires first) and re-run the gate to exit 0. -->

**Tests to investigate for retirement:**
- Planner candidates: none — no lane or target is added, removed or renamed.
- Tester may identify additional candidates during test work.

**Retirement procedure:** For each candidate, verify the test exercises code being removed/changed. If obsolete: delete and note in session report. If still valid: document why in session report.

## Summary

### Problem

The bench moved to `f9e4ba7` (pushed to origin; verified) with two changes the env repo must absorb: the result-class declarations (the mte stamp's 229 out-of-expect rows — 228 at `99` of which 214 are newly declared and 4 were already, plus one at `260` now declared — become clean; the pa lane's `19` becomes declared) and the NEMU venue's staging rebuild (scratch-tree corpus build, `cpio --reproducible`, publish-on-success manifest). The env pin is still `47d6f9d`, the five non-aarch64 lanes sit at `f4c916a`, and the aarch64 family is at `47d6f9d`. There is no cross-lane comparison at a single pin — the standing gap to the final aim — and four small lane-script defects (pin not asserted, smoke flags not coupled to the pinned Makefile, collector treats required artifacts as optional, the aarch64 run recipe's lock gap) are all directly exercised by the pin bump and the re-stamp this cycle performs.

### Approach

Seven steps:

1. **Pin bump** — `env.sh` `BENCH_COMMIT` to `f9e4ba7addc2865aacdf70f51e9fd203854f4727`, the submodule checkout, and a rewritten pin comment. `version_stamp.sh` additionally records the bench checkout (`bench-head:`, `bench-tree:`) and a `run-status: ok|failed (rc=N)` marker, so every stamp carries the checkout state and whether its run finished.
2. **Swap-text rewrite** — every env text and diagnostic that describes the registry swap the bench removed: the `CLAUDE.md` Rules/Structure sentences, `doc/content.html`, and `scripts/riscv64_nemu/{prepare,run}.sh` (header and diagnostics). The deploy's invariants (HEAD equals the pin, the tree is clean) are named instead, and the nemu dirt checks gain the git-rc guard the aarch64 lane already has.
3. **Pin and flag assertions** — the aarch64 prepare and run scripts and the shared corpus builder assert `git -C benchmark rev-parse HEAD` equals `BENCH_COMMIT` (as x86_64's deploy and the nemu prepare already do), and prepare.sh cross-checks its lane-representative smokes' build flags against the pinned `benchmark/Makefile`, failing closed when the block or its flag lines cannot be read.
4. **Collector and lock hardening** — `results.json`/`results.dat` become required, non-empty and parseable artifacts in the aarch64 and x86_64 collectors, `variables.json` stays optional; the aarch64 `run` recipe holds the lane lock across both legs, with the lock file opened append-style (so a contender never wipes the holder's name) and the scripts honouring a marker only when the inherited descriptor verifiably is the lane lock.
5. **Comparison tool** — a committed `scripts/common/compare_lanes.py` with an explicit verdict vocabulary, a pinned-by-construction registry (`git show <pin>:configure.json`), stamp states, exit-code contract and input validation; the 14 `set-var` producers' `99` gets one documented verdict (`class-masked`) scoped to the HWASan lane.
6. **Uniform re-stamp** — retire each lane's older stamps under `results/<lane>/retired-<oldpin>/`, then deploy and run x86_64, aarch64, aarch64-pa, aarch64-bti, aarch64-mte, riscv64 and riscv64-nemu at `f9e4ba7`.
7. **Classification, snapshot, retirements** — run the tool as the gate, capture the snapshot under `results/comparison-<UTC>/`, disposition any nonzero outcome, and retire all six adopted reports.

### Key decisions and alternatives

- **The comparison tool is committed, not a one-off.** The final aim is a standing platform comparison; a script under `scripts/common/` (stdlib only) can be re-run at every pin. Snapshots stay machine-local under `results/` (gitignored) — the tool is the durable artifact, and docs carry the command, never a count.
- **The registry is read from git, not the worktree.** `git show <pin>:configure.json` makes the classification source pinned by construction, immune to checkout drift or a dirty submodule between the lane runs and the gate.
- **Pin uniformity and stamp completeness are enforced, not assumed.** Every selected stamp must record the pin and the same checkout, be a completed run (`run-status: ok`), and carry a parseable `results.json`; the default selection is the newest stamp by name and a newest stamp that fails these is a refusal naming it (never a silent fallback to an older era).
- **The verdict vocabulary is closed and the gate is three-valued.** Exit 0 = every selected lane complete and every row in {`clean`, `declared`, `not-run-skipped`, `class-masked`}; exit 1 = any gate-failing row (`out-of-expect`, `build-failed`, `prerequisite-unsatisfied`, `missing-from-lane`, `extra-record`, an absent lane without `--allow-absent`, a stamp whose `run-status` is failed); exit 2 = input/config refusal (mixed pin, missing reference, unreadable registry or pin, explicitly selected incomplete stamp, malformed CLI). A nonzero exit IS the finding and is dispositioned; it is never bypassed.
- **`not-run` splits by the scheduler's own two counts.** `1025` without `make-status` is a declared platform skip (`not-run-skipped`, benign — and for the seven lanes only a derived-registry skip can produce it); `1025` with `make-status` is a build failure (`build-failed`, gate-failing, naming the make status), exactly as `results.dat` counts them apart. `1024` (prerequisite unsatisfied) is gate-failing as an incomplete measurement.
- **`class-masked` is scoped to the HWASan lane.** A `99` on a `set-var` record is the calibration producer the HWASan build aborts before it can measure (`benchmark/lib/include/result.hpp:17-25` leaves that constant undeclared by design); the verdict applies only when the stamp itself records `enable_aarch64_mte=yes`, and a `99` on a producer anywhere else is out-of-expect.
- **Lock inheritance by a verified marker.** `flock` is per open-file-description; the Makefile recipe's lock is inherited by its children, whose own `flock -n` on a fresh descriptor would fail. The scripts honour `LANE_LOCK_INHERITED=1` only when `/proc/self/fd/9` resolves to the lane-lock file and `flock -n 9` on that descriptor succeeds; then they close fd 9 so no lane child (scheduler, qemu, corpus binary) inherits it. A spoofed marker with no lock dies.
- **`version_stamp.sh` records the checkout and the run status.** `bench-head`/`bench-tree` make the pin assertion's effect visible per stamp; `run-status` distinguishes a finished run from an evidence-only failure stamp. Both are git/rc-guarded so a broken git or a missing rc never reads as clean.

### Rollback and stamp retirement

- **Pin rollback** (if `f9e4ba7` proves defective mid-cycle): `BENCH_COMMIT` back to `47d6f9d0b99744d36bd857f6da7334036ce215c3`, `git -C benchmark checkout 47d6f9d`, stage the gitlink, restore the pin comment from `git show HEAD:env.sh`. Stamps already written at `f9e4ba7` stay valid evidence of the attempted pin and are named as such in the cycle's report; they are moved under `results/<lane>/retired-f9e4ba7/` if the cycle is re-run at the old pin.
- **Stamp retirement before the re-stamp:** each of the seven lanes' existing stamps move to `results/<lane>/retired-<their-pin>/` before that lane's Step 6 run, so the newest-stamp default can never select a mixed-era stamp. The move is reversible (`mv` back) and recorded in the session report.

### Out of scope

- CHERI re-stamp: both lanes hold complete `f4c916a` stamps and are deliberately excluded from this pin-uniform comparison (not absent, not re-stamped); the tool's default `--lanes` is the seven executable lanes, and passing a CHERI lane explicitly refuses on the pin mismatch.
- `defer-issue-lane-script-hardening-batch` (11 accumulated review items) — a separate maintenance cycle.
- Bench-side work of any kind: `benchmark/` is read-only at the pin.
- The workspace `CLAUDE.md` refresh.

## Repo Mode

Private

## Document Overrides

| Document | Rule Overridden | Reason |
|----------|----------------|--------|

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| The pa lane's first post-fix stamp reveals new out-of-expect rows (the 10 cascade consumers now execute with a real offset and may land on an undeclared code) | the comparison gate exits 1 | Step 7 dispositions every row: a real defect becomes a report, a missing declaration a deferred issue; exit 1 with every row filed is an accepted cycle outcome, never bypassed |
| The re-stamp is long (the riscv64-nemu deploy may run a cold image build) and the lanes are one-at-a-time | a stalled lane blocks the cycle | the driver runs one lane per invocation in the documented order with `live_trace` progress; a failed lane publishes its evidence stamp and the cycle reports it instead of continuing silently |
| A selected stamp could be a failed run's evidence-only or truncated stamp | a comparison over incomplete data | the tool requires `run-status: ok` plus a parseable `results.json`; the default newest-by-name stamp that fails this is an exit-2 refusal naming it; truncated runs surface as `missing-from-lane` rows (gate-failing) |
| The aarch64 lock inheritance leaks the lock descriptor into lane children | an adversarial corpus binary could hold the lock after the recipe exits | the scripts validate the inherited descriptor and then close fd 9 before running anything else; the recipe itself never passes the fd to children |
| The pin bump changes the NEMU venue's deploy mechanics under the env wrapper | the deploy's old swap guards become vacuous | the guards are retained as invariants (HEAD equals pin; tree clean) and Step 3 adds the missing HEAD assert to the shared builder; the nemu deploy in Step 6 is the end-to-end proof |
| A `git` failure could read as a clean tree or a valid pin | false provenance | every new and touched git call checks the rc and records/refuses on failure (`bench-head: unavailable (git rc=N)`, pin asserts die naming the unverifiable state) |

## Proposed Changes

1. **Step 1:** Bump the bench pin and record the checkout and run status in every stamp.
   - `./env.sh`: `BENCH_COMMIT=f9e4ba7addc2865aacdf70f51e9fd203854f4727`; rewrite the pin comment (lines 8-19) to name what the new commit carries — the aarch64 result-class declarations (99 on the observed MTE/HWASan set, 260 and 19 on the PAuth crash codes) and the NEMU venue's staging rebuild (scratch-tree corpus build, reproducible image, publish-on-success manifest).
   - Check out the submodule at that commit and stage the gitlink.
   - `./scripts/common/version_stamp.sh`: append a `# bench checkout` section with `bench-head: <rev-parse HEAD>` and `bench-tree: <describe --always --dirty>`, and a `run-status: ok` / `run-status: failed (rc=N)` line from a third argument or `RUN_STATUS` (collectors pass their final rc). Every git/rc read is guarded: a failure records `unavailable (git rc=N)` / `failed (rc=N)`, never a value or a crash.
   - Re-verify the NEMU venue's message literals at the new pin (the code mandates this on every `BENCH_COMMIT` move): `grep -F 'NEMU timed out' benchmark/platform/riscv64-nemu-linux/run.sh`, and the `fw_payload.bin`/`meta.json` path expectations in `prepare.sh`, must still match; adapt the matches if the venue reworded them.
   - <!-- UPDATED 2026-10-27 (follow-up, issue [riscv64-cheri-stamps-default-run-status-ok](../reports/2026-10-27-uniform-pin-restamp-and-comparison-riscv64-cheri-stamps-default-run-status-ok.json)) --> `scripts/riscv64/run.sh`, `scripts/cheri_riscv64/run.sh` and `scripts/morello/run.sh`: pass `RUN_STATUS="$rc"` to `version_stamp.sh` as the three touched collectors do, so no lane-run collector can publish a stamp claiming `run-status: ok` without its own rc. The build-time callers (`scripts/riscv64/build_image.sh:98`, `scripts/cheri/build_toolchains.sh:70`) stay two-argument — they record build provenance, not a run.
   → coder verify (scripted): `make ARCH=x86_64 deploy` passes; `git -C benchmark rev-parse HEAD` equals the pin; a `version_stamp.sh` run with `RUN_STATUS=ok` writes both new lines with the expected sha and a `-dirty`-free tree string; a `RUN_STATUS=0` failure and a git-unavailable control each record the guarded sentinel; the three venue literals are found.
   → tester verify: the pin-drift control (`git -C benchmark checkout 47d6f9d` → `make ARCH=x86_64 deploy` fails naming both hashes; restore) and an independent stamp inspection.

2. **Step 2:** Rewrite every env text that describes the removed registry swap.
   - `./scripts/riscv64_nemu/prepare.sh` — the header (line ~9) and the dirty-submodule diagnostics (~120-140, ~185-188); `./scripts/riscv64_nemu/run.sh` — the diagnostic (~80-90). Keep the restore advice generic and name the invariants (HEAD equals `BENCH_COMMIT`; the tree is clean; the platform no longer edits the tracked registry, so any dirt is a real edit). In the same blocks, capture and check the git exit status (`git_rc=$?` pattern from `scripts/aarch64/run.sh:89-98`), so a failing git never reads as clean.
   - Planner-owned (Guidance for Planner): `./CLAUDE.md` Rules/Structure, `./doc/content.html`, `./doc/lanes.html`.
   → coder verify (scripted): `grep -rn -i "swap" scripts/riscv64_nemu/` finds no description of the removed mechanism (the header included); the guarded dirt check reports `cannot verify` on a simulated git failure instead of reading clean.
   → tester verify: the dirtied-tree control (a transient untracked probe file inside `benchmark/`, removed immediately — never a tracked edit) makes the preflight name the invariants; the git-failure simulation names the unverifiable state.

3. **Step 3:** Assert the pin and couple the smokes to the pinned build flags.
   - `./scripts/aarch64/prepare.sh` and `./scripts/aarch64/run.sh`: assert `git -C benchmark rev-parse HEAD` equals `$BENCH_COMMIT`, dying on mismatch with both hashes; when git itself fails, die naming the unverifiable state (never pass).
   - `./scripts/common/build_corpus.sh`: the same assertion, anchored with `git -C "$ROOT/benchmark"` (the script resolves `ROOT` but does not `cd` to it).
   - `./scripts/aarch64/prepare.sh`: an `assert_bench_class_flags` helper. For each request-bearing lane it reads every line in the pinned Makefile's `ifdef enable_aarch64_<pa|mte>` block that carries class flags (`CXXFLAGS :=` and `OBJECT_CXXFLAGS +=`), and requires each such line's flag tokens to equal the smoke's own class-flag tokens (a fixed prefix set: `-march=…`, `-mbranch-protection=…`, `-fsanitize=…`). It fails closed — zero extracted tokens, a missing block, or an unreadable file is a named refusal — and reads the Makefile path from `BENCH_MAKEFILE` (documented override, default `benchmark/Makefile`) so the control can point at a modified copy without editing the submodule.
   → coder verify (scripted): the pin-drift control (submodule at another commit → aarch64 prepare, aarch64 run and `build_corpus.sh` all refuse, naming both hashes); the flag-drift controls (a copy with the whole `ifdef enable_aarch64_pa … endif` block removed → prepare refuses naming the lane; a copy with only the `CXXFLAGS` line removed → also refuses, because `OBJECT_CXXFLAGS` still carries the class and the comparison is per line; a missing `BENCH_MAKEFILE` → refuses, not vacuous pass); the unmodified copy and the normal `make ARCH=aarch64 deploy` pass.
   → tester verify: all controls replayed independently; the normal deploys of all four aarch64 lanes pass.

4. **Step 4:** Make required artifacts required and close the aarch64 lock gap.
   - `./scripts/aarch64/run.sh` cleanup: `results.json` and `results.dat` are required — absence, empty file, or (for results.json) unparseable JSON names the artifact and sets the collection failure; `variables.json` stays optional (the mte lane's producer does not survive its build class). `LANE_RUN_TIMEOUT` is validated (positive integer) before use, as `scripts/riscv64_nemu/run.sh` already does.
   - `./Makefile` x86_64 `run` recipe: the same required/optional split, with an explicit `collect_rc` checked before `assert_rc` (the trap currently has no collection-failure state), and the `version_stamp.sh` output verified as aarch64 does; pass `RUN_STATUS` from the trap's rc.
   - `./Makefile` aarch64 `run` recipe: acquire the lane lock around both legs and pass `LANE_LOCK_INHERITED=1` plus `RUN_STATUS` handling to the two scripts. `./scripts/aarch64/{prepare,run}.sh` skip their own flock only when the marker is exactly `1` **and** `/proc/self/fd/9` resolves to `$BUILD_DIR/.lane.lock` **and** `flock -n 9` on that descriptor succeeds; then they close fd 9 (`exec 9>&-`) before running children. `./Makefile`'s `acquire_lane_lock` and both scripts open the lock file append-style (`exec 9>>`) and write the holder name only after the lock is taken.
   - <!-- UPDATED 2026-10-27 (follow-up, issue [lane-lock-truncating-open-elsewhere](../reports/2026-10-27-uniform-pin-restamp-and-comparison-lane-lock-truncating-open-elsewhere.json)) --> the nine sibling lane scripts the issue lists (`scripts/riscv64/run.sh`, `scripts/riscv64/build_image.sh`, `scripts/cheri_riscv64/{prepare,run}.sh`, `scripts/morello/{prepare,run}.sh`, `scripts/cheri/{stage_sources,build_image,build_emulator}.sh`) open the lock append-style (`exec 9>>`) too — each already writes the name only after `flock` succeeds (verified by the issue report), so only the open mode changes; this keeps the append-open discipline uniform across every lane path instead of carving a nine-script exception into the doc text.
   → coder verify (scripted): a collection replay with `results.json` absent, empty and malformed each exits nonzero naming the artifact, and with only `variables.json` absent exits zero; the x86_64 replay does the same; the lock pair — a holder writes its name, a second acquisition refuses and the message **names the holder** (proving append-mode), a marker spoof with no held lock dies, and a marker run with a held lock proceeds and closes fd 9 (checked via `/proc/<pid>/fd` of the child or a child-side probe); a second `make ARCH=aarch64 run` while the first holds the lock refuses before prepare.
   → tester verify: the collector controls and the lock pair replayed; a full `make ARCH=aarch64 run` publishes a complete stamp.

5. **Step 5:** Commit the lane-comparison tool.
   Write `./scripts/common/compare_lanes.py` (stdlib only; no shell-out except `git`):
   - CLI: `--lanes` (default the seven executable lanes), `--stamp LANE=DIR` (override), `--reference x86_64`, `--allow-absent LANE` (repeatable; recorded in the summary), `--out DIR` (default `results/comparison-<UTC>-<pid>`), `--max-bytes` (default 8 MiB).
   - Inputs: `env.sh`'s `BENCH_COMMIT` (the assignment line specifically — `versions.txt` embeds `env.sh` verbatim, so `export BENCH_COMMIT` must not be matched); the registry from `git -C benchmark show <pin>:configure.json` (exit 2 when the pin is not in the object store); each stamp's `versions.txt` (`BENCH_COMMIT`, `bench-head`, `bench-tree`, `run-status`, and the lane's flag line) and `results.json`.
   - Stamp selection: the `--stamp` override or the newest directory by name under `results/<lane>/`. A selected stamp must carry a parseable `BENCH_COMMIT`, `run-status: ok`, a `bench-head` equal to the pin, a `bench-tree` equal to the pin's short/full form without a `-dirty` suffix, and a `results.json` that is a JSON object under the size cap; any failure is an exit-2 refusal naming lane, stamp and the failing input (never a traceback, never a fallback to an older stamp).
   - Validation of each `results.json`: keys a subset of the registry's record names (an extra key is an `extra-record`, never a row); every `result` a plain int (bool excluded) in 0-2047; the record set compared as a set against the registry.
   - Verdicts: `clean` (0), `declared`, `out-of-expect`, `not-run-skipped` (1025 without `make-status`), `build-failed` (1025 with `make-status`, naming it), `prerequisite-unsatisfied` (1024), `missing-from-lane`, `extra-record`, `class-masked` (99 on a `set-var` record **and** the stamp's flag line is `enable_aarch64_mte=yes`).
   - Gate: exit 0 iff every selected lane is complete and every row is in {`clean`, `declared`, `not-run-skipped`, `class-masked`}; exit 1 for any of the other classes, an absent lane without `--allow-absent`, a lane whose `run-status` is failed, or an `extra-record`; exit 2 for every input/config refusal above. A missing reference is exit 2.
   - Outputs: `comparison.json` (machine) and `comparison.md` (human) — per-lane summary (stamp, pin, distribution, verdict counts, excluded/absent lanes) and a divergence matrix against the reference where a `missing-from-lane` row is emitted as a null-code row. All recorded strings are sanitized before rendering (control characters stripped); record names and meanings come from the registry, result codes are validated ints.
   → coder verify (scripted): the fixture matrix — `--help`; mixed pin (2); absent reference (2); absent lane without/with `--allow-absent` (1/0); declared code (0); undeclared code (1, named); `not-run-skipped` (0); `build-failed` with make-status (1, named); `prerequisite-unsatisfied` (1); `missing-from-lane` (1, null-code row); `extra-record` (1); evidence-only stamp selected explicitly (2) and as the newest (2); stamp with `run-status: failed` (1); `bench-tree: unavailable` (2); unparseable `versions.txt` (2); `class-masked` on the mte lane (0) and a 99-on-producer elsewhere (1); oversized `results.json` (2); empty `results.json` (1 via missing rows).
   → tester verify: an independent fixture suite covering the same matrix.

6. **Step 6:** Re-stamp the seven executable lanes at the new pin.
   Before each lane's run, move that lane's existing stamps to `results/<lane>/retired-<their-pin>/` (Rollback section). Then, one lane at a time and in this order: `make ARCH=x86_64 deploy run`; `make ARCH=aarch64 deploy run`; `make ARCH=aarch64 enable_aarch64_pa=yes deploy run`; `make ARCH=aarch64 enable_aarch64_bti=yes deploy run`; `make ARCH=aarch64 enable_aarch64_mte=yes deploy run`; `make ARCH=riscv64 deploy run`; `make ARCH=riscv64-nemu deploy run`. The two CHERI lanes are not run; their `f4c916a` stamps stay in place and are named as excluded, never absent.
   → tester verify: each run exits 0 with its full record set (246 for the host lanes; each system lane's own completeness gate green); each stamp carries `results.json` and `results.dat` (plus `variables.json` where produced), a `versions.txt` with the new pin, `run-status: ok`, and a `bench-tree:` line that is present, not `unavailable`, and carries no `-dirty`; the nemu deploy leaves `git -C benchmark status --short` empty and its stamp's venue-side `# Bench tree:` line (the guest's sys_info header, a different line from the stamp's `bench-tree:`) also carries no `-dirty`; the pa lane's `variables.json` carries `stack-offset-v-p-g0`/`-g1`, both heap-memcpy records deliver 0, and `cfi-return-without-call` delivers the declared 19; the mte lane's non-benign set is exactly its `class-masked` producer rows.

7. **Step 7:** Classify, snapshot, and retire the evidence-backed deferrals. Run `python3 scripts/common/compare_lanes.py --lanes x86_64,aarch64,aarch64-pa,aarch64-bti,aarch64-mte,riscv64,riscv64-nemu`; write `results/comparison-<UTC>/comparison.{json,md}`.
   → tester verify: the gate's outcome is recorded verbatim — exit 0 is the expected result (the `class-masked` producer rows excepted by design); a nonzero exit is itself the finding, with every named row dispositioned in the session report (a real defect becomes a report, a missing declaration a deferred issue) — never bypassed. On this evidence the Issue Log rows for `defer-issue-aarch64-pa-calibration-cascade` and `defer-issue-env-docs-registry-swap-text` (and, through their implementing steps' verification, the four Step 3/Step 4 rows) move to Resolved, retiring all six reports at commit time.
8. <!-- UPDATED 2026-10-27 (post-tester, user-approved env lever) --> **Step 8:** Make the bti lane execute its own build class; make stamp selection retirement-proof.
   - `./env.sh`: `QEMU_CPU_AARCH64_BTI=max` beside the pa/mte requests, with the reason in the comment (the bti class's `-march=armv8.5-a` implies PAuth; bench `f9e4ba7`'s `STRIP_PAC()` emits `xpaci`, which traps without FEAT_PAuth — the lane must run the class it builds). Only `aarch64` remains request-less.
   - `./scripts/aarch64/{prepare,run}.sh`: the bti case reads the request like pa/mte, so it reaches the lane's environment and the stamp's `# CPU request:` record.
   - `./scripts/aarch64/prepare.sh`: a bti deploy smoke — an `xpaci`-bearing build executes under the request (the leg the dismissed mega-audit finding `bti-smoke-class-unchecked` asked for; its premise is evidence-dead at this pin) — and the header's "nothing can fault" text rewritten.
   - `./scripts/common/compare_lanes.py`: a directory under `results/<lane>/` is a stamp-selection candidate only when it carries `versions.txt`, so the plan-mandated retirement directories are inert to selection (issue: retired-stamp-dir-shadows-newest-selection).
   → coder verify (scripted): `make ARCH=aarch64 enable_aarch64_bti=yes deploy` passes with the smoke; a unit bti-class build executes under the request; a planted `retired-<pin>` directory is not selected and the newest real stamp is.
   → tester verify: the bti lane re-stamped at the pin (the five rows leave `260`, landing where the class executes), the Step 7 gate re-run to exit 0, and the controls suite extended with the bti-smoke and selection-filter checks replayed green.

## Guidance for Planner

Documentation tasks you will execute yourself (not the coder):

- **Files to modify:**
  - `./CLAUDE.md`
  - `./README.md`
  - `./doc/architecture.html`
  - `./doc/content.html`
  - `./doc/lanes.html`
- **When:** after the coder finishes (Steps 1-5) for the mechanism text; the pin-era and caveat statements after the Step 6 evidence.
- **What to sync:**
  - `CLAUDE.md` Rules (the `benchmark/` read-only bullet, ~26-31) and Structure (~54-58): remove the registry-swap exception; state that the venue builds its corpus in `out/build/<runset>/tree` and never writes the tracked registry, and that the deploy's preflight (HEAD equals `BENCH_COMMIT`) and post-assert (tree clean) remain invariants. Structure: add `scripts/common/compare_lanes.py`. Rules: the collector contract (results.json/results.dat required and parseable, variables.json optional) and the lock-inheritance rule (the aarch64 `run` recipe holds the lock across both legs; scripts honour `LANE_LOCK_INHERITED=1` only for a verified descriptor).
  - `README.md` "Pins" table and its stamp narrative: the new `BENCH_COMMIT`, its rationale, and which lanes are now at it. Results layout (~154): `versions.txt` carries `bench-head`/`bench-tree`/`run-status`; `results/comparison-<UTC>/` is where the tool writes. A short "Comparing lanes" subsection: the command, the pin-uniformity and completeness refusals, the `class-masked` carve-out described by class (the `set-var` producer records whose HWASan build aborts before they can measure, yielding `99`) — no numerals — and that snapshots are machine-local while the tool is the durable artifact.
  - `README.md` "Known caveats": re-derive every pin/stamp claim for `f9e4ba7` — delete the registry-swap caveat; delete or requalify the image-not-byte-reproducible and the `-dirty`-marker caveats against the venue README's post-fix statements; replace the `f4c916a` out-of-expect bullets and the "only the aarch64 family was re-stamped" narrative with the post-`f9e4ba7` state; update the pa calibration/`19` caveats to the post-fix stamps; delete the Pins-table sentence promising a riscv64-family re-stamp as a successor (it has happened). Do this after Step 6, from the stamps.
  - `doc/lanes.html`: the riscv64-nemu swap wording (~189); the aarch64 pa calibration paragraph (~150-163) rewritten to the post-fix state (the producer stores a real offset; the ten records execute) and the deferral reference dropped when Step 7 retires it; the aarch64 run flow (lock inherited across prepare+run; collector required/optional). <!-- UPDATED 2026-10-27 (Step 8): the CPU-request sentences change — only `aarch64` stays request-less, `aarch64-bti` joins pa/mte in requesting `max`, with the xpaci reason; the "bti lane deliberately has no leg" sentence becomes the bti smoke (an xpaci-bearing build executes under the request); the per-lane CPU-request table names the bti request. --> Note: this page carries no bench-pin hash — do not add one.
  - `doc/architecture.html` (declared keep-in-sync with the Makefile and `scripts/`): the lane-lock section (the aarch64 run recipe holds the lock across both legs; the marker is verified, fd 9 closed for children; the lock file is append-opened so a contender preserves the holder name — after the Step 4 follow-up this holds for every lane script, no exception to name); the pins section (the HEAD assertion now runs in aarch64 prepare/run and the shared builder too); the results/provenance section (`bench-head`/`bench-tree`/`run-status`, and the corrected `-dirty` statement). <!-- UPDATED 2026-10-27: append-open sentence widened to all lane scripts; README's run-status wording needs no lane exception (the Step 1 follow-up gives every run collector an rc) --> <!-- UPDATED 2026-10-27 (Step 8): the results/provenance section's selection statement gains the filter — a stamp is a directory carrying versions.txt, retirement directories are skipped by selection. -->
  - `README.md` Step 8 additions: the "Comparing lanes" subsection says retired stamps live under `results/<lane>/retired-<pin>/` and are skipped by selection; the Pins table's QEMU CPU row names the bti request; Known caveats records the bti class's PAuth dependency at this pin.
  - `doc/content.html`: the landing page's "one consumed exception … swaps its derived registry" sentence (lines ~17-28) — the same scratch-tree rewrite as CLAUDE.md.
  - `defer-issue-env-docs-registry-swap-text` is retired by this plan's Issue Log row once these edits land.

## History

| Date | Event | Conclusion | Dismissed |
|------|-------|------------|-----------|
| 2026-10-27 | Spec revision (/update-plan, post-tester, user-approved) | The Step 7 gate exited 1 on five aarch64-bti rows; the tester traced them to bench `f9e4ba7`'s new `STRIP_PAC()` compiling to `xpaci` under the bti class's `-march=armv8.5-a` while the lane runs on a PAuth-less default CPU model — an execution-venue regression, unit-reproduced. User decision: fix env-side now. **Step 8 added**: the bti lane gains a `QEMU_CPU=max` request and the deploy smoke the dismissed mega-audit finding `bti-smoke-class-unchecked` asked for (its premise — "nothing can fault" — is evidence-dead at this pin), and the comparison tool's stamp selection only considers directories carrying `versions.txt` (the plan-mandated retirement directories were shadowing the default selection). Tester follow-up scoped: bti re-stamp + gate re-run to exit 0. Reports: [bti-lane-build-class-sigills-on-default-cpu-model](../reports/2026-10-27-uniform-pin-restamp-and-comparison-bti-lane-build-class-sigills-on-default-cpu-model.json), [retired-stamp-dir-shadows-newest-selection](../reports/2026-10-27-uniform-pin-restamp-and-comparison-retired-stamp-dir-shadows-newest-selection.json). | Declaring `260` on the bti lane — rejected (enshrines a non-measurement as a defence result). Bench-side `STRIP_PAC` gating — the durable fix, but out of this repo's scope; recorded in the issue report as the named bench-side follow-up. Accepting the exit-1 cycle — rejected by the user in favour of the green gate. |
| 2026-10-27 | Spec revision (/update-plan) | Two coder-filed gaps folded in, both Plan-Gap scoping misses inside contemplated mechanisms: the three untouched run collectors now pass `RUN_STATUS` (Step 1 follow-up; without it a failed riscv64 run's evidence stamp would claim `run-status: ok` — exactly the failure path the stall-risk mitigation relies on) and the nine sibling lane scripts open the lock append-style (Step 4 follow-up; keeps the doc text exception-free). A follow-up coder round is directed via the new `## Immediate Actions` section; it also carries the `compare_lanes.py` 0755 mode fix the first round's sandbox refused. Reports: [riscv64-cheri-stamps-default-run-status-ok](../reports/2026-10-27-uniform-pin-restamp-and-comparison-riscv64-cheri-stamps-default-run-status-ok.json), [lane-lock-truncating-open-elsewhere](../reports/2026-10-27-uniform-pin-restamp-and-comparison-lane-lock-truncating-open-elsewhere.json). | Deferring both to `defer-issue-lane-script-hardening-batch` — rejected: the run-status gap corrupts this cycle's own gate input on a lane the seven-lane comparison reads, and the lock gap is the same defect family Step 4 fixes; a nine-character change now beats a doc carve-out plus a deferral row. |
| 2026-10-27 | Mega-audit (pre-implementation) | 76 findings (10 High, 39 Medium, 27 Low); all High and Medium fixed in this revision — the comparison gate gained a closed verdict vocabulary (1025 split by `make-status`, 1024, missing/extra records, absent lanes, stamp completeness and `run-status`), a git-pinned registry source and a three-valued exit contract; the lock gained append-mode opening, a verified inheritance marker and fd closure; the x86_64 collector gained its missing failure state; the plan gained a rollback/stamp-retirement section, the NEMU message re-verification, and the full doc-sync set (`architecture.html`, `content.html`, README Known caveats, `doc/lanes.html`); Repo Mode corrected to Private. Report: [2026-10-27-uniform-pin-restamp-and-comparison-mega-audit-2026-10-27.json](../reports/2026-10-27-uniform-pin-restamp-and-comparison-mega-audit-2026-10-27.json). | [bti-smoke-class-unchecked](../reports/2026-10-27-uniform-pin-restamp-and-comparison-mega-audit-2026-10-27.json) — the bti lane deliberately has no smoke leg (BTI hints are NOPs on a non-BTI model, so a leg would assert nothing); the plan keeps that deliberate exclusion. |
| 2026-10-27 | Initial plan | Seven steps: pin bump with checkout/run provenance, swap-text rewrite, pin/flag assertions, collector and lock hardening, a committed comparison tool, the seven-lane re-stamp, and the evidence-backed retirements. | — |

## Plan Metadata

```json
{
  "plan_id": "2026-10-27-uniform-pin-restamp-and-comparison",
  "steps": [
    "Step 1: Bump the bench pin and record the checkout and run status in every stamp",
    "Step 2: Rewrite every env text that describes the removed registry swap",
    "Step 3: Assert the pin and couple the smokes to the pinned build flags",
    "Step 4: Make required artifacts required and close the aarch64 lock gap",
    "Step 5: Commit the lane-comparison tool",
    "Step 6: Re-stamp the seven executable lanes at the new pin",
    "Step 7: Classify, snapshot, and retire the evidence-backed deferrals",
    "Step 8: Make the bti lane execute its own build class; make stamp selection retirement-proof"
  ],
  "coder_files": [
    "./env.sh",
    "./Makefile",
    "./scripts/common/version_stamp.sh",
    "./scripts/common/build_corpus.sh",
    "./scripts/common/compare_lanes.py",
    "./scripts/aarch64/prepare.sh",
    "./scripts/aarch64/run.sh",
    "./scripts/riscv64_nemu/prepare.sh",
    "./scripts/riscv64_nemu/run.sh",
    "./scripts/riscv64/run.sh",
    "./scripts/riscv64/build_image.sh",
    "./scripts/cheri_riscv64/prepare.sh",
    "./scripts/cheri_riscv64/run.sh",
    "./scripts/morello/prepare.sh",
    "./scripts/morello/run.sh",
    "./scripts/cheri/stage_sources.sh",
    "./scripts/cheri/build_image.sh",
    "./scripts/cheri/build_emulator.sh"
  ],
  "tester_files": [
    "./tmp/verification/2026-10-27-uniform-pin-restamp-and-comparison-controls.py",
    "./tmp/verification/2026-10-27-uniform-pin-restamp-and-comparison-restamp.py"
  ],
  "doc_files": [
    "./CLAUDE.md",
    "./README.md",
    "./doc/architecture.html",
    "./doc/content.html",
    "./doc/lanes.html"
  ],
  "verification_scripts": [
    "./tmp/verification/2026-10-27-uniform-pin-restamp-and-comparison-controls.py",
    "./tmp/verification/2026-10-27-uniform-pin-restamp-and-comparison-restamp.py"
  ],
  "repo_mode": "Private",
  "document_overrides": []
}
```

## Audit Accumulation

| Counter | Value | Last Updated |
|---------|-------|--------------|
| issues_resolved_since_audit | 10 | 2026-10-27 |
| steps_changed_since_audit | 1 | 2026-10-27 |
| files_changed_since_audit | 9 | 2026-10-27 |

## Documentation

- `./CLAUDE.md` — the swap-free venue statement, the collector contract, the lock-inheritance rule, the comparison tool in the Structure listing (Guidance for Planner).
- `./README.md` — pins and their stamp narrative, results layout, the "Comparing lanes" subsection, and the re-derived Known caveats (Guidance for Planner).
- `./doc/architecture.html`, `./doc/content.html`, `./doc/lanes.html` — the declared keep-in-sync pages (Guidance for Planner); `doc/content.html` needs no lane/target change, only the swap sentence.
- `benchmark/platform/riscv64-nemu-linux/README.md` — already rewritten by bench `f9e4ba7`; the env docs defer to it for the venue's own flow.

## Final Results

**Completed 2026-10-27. Status: COMPLETED.**

- **What was implemented:** the bench pin moved to `f9e4ba7addc2865aacdf70f51e9fd203854f4727` with the pin comment rewritten; every stamp now records its bench checkout (`bench-head:`/`bench-tree:`) and its run's outcome (`run-status:`); every env text describing the removed registry swap was rewritten to the scratch-tree invariants; the pin assertion and the smoke-flag cross-check against the pinned Makefile landed in the aarch64 prepare/run scripts and the shared corpus builder; the host-lane collectors treat `results.json`/`results.dat` as required and parseable; the aarch64 `run` recipe holds the lane lock across both legs with a verified inheritance marker and append-open everywhere; the committed lane-comparison tool (`scripts/common/compare_lanes.py`) classifies the seven lanes against the git-pinned registry with a closed verdict vocabulary and a three-valued exit contract; the bti lane gained its PAuth-capable CPU request and a non-vacuous deploy smoke; stamp selection skips non-stamp directories.
- **Files changed:** 22 tracked files modified plus the new `scripts/common/compare_lanes.py` (mode 0755); the `benchmark` gitlink staged at the pin; per the plan's file list plus the revision-added follow-up files.
- **Test results:** 178/178 checks pass across the two tester rounds (controls: 159 covering pin/stamp/venue/swap/flags/collect/timeout/lock/compare + the Step 8 bti-smoke and selection-filter sections; the re-stamp driver: seven lanes green, bti re-stamped green). All seven executable lanes re-stamped at the pin (246/246 records each, `run-status: ok`, checkout dirt-free); the plan's literal default-selection gate command exits 0 with an empty findings list (`results/comparison-20261027T081705Z/`; the earlier exit-1 snapshot is preserved beside it). The CHERI pair keeps its previous-pin stamps, excluded by design.
- **Issues resolved:** all ten Issue Log rows — the six adopted deferrals (registry-swap text, pa calibration cascade, collector required artifacts, run lock gap, smoke-flag coupling, submodule pin unverified), the two coder-filed gaps (RUN_STATUS passes, append-open discipline), and the two tester-filed findings (bti SIGILL class, selection shadowing). Their reports retire at commit time per `/update-and-commit`.
- **Rounds:** coder ×4 (Steps 1-5; RUN_STATUS/append-open/chmod; Step 8; env.sh comment), tester ×2 (seven-lane re-stamp + gate; bti re-stamp + gate re-run), plan revisions ×3 (two spec revisions, one post-tester user-approved), mega-audit ×1 (pre-implementation).
- **Known residue (accepted, recorded):** the durable STRIP_PAC runtime-capability gating stays a named bench-side follow-up (in the bti issue report); the deferred `lane-script-hardening-batch` remains open for its own maintenance cycle.
