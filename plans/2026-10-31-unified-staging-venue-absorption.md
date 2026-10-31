# Plan: Unified runner-driven corpus staging + absorb the NEMU venue into the env lane
**Plan ID:** 2026-10-31-unified-staging-venue-absorption
**Created:** 2026-10-31

## Issue Log

| Issue | Status | Found | Resolved | Resolved By |
|-------|--------|-------|----------|-------------|
| [enable-flag-wording](./tmp/reports/2026-10-31-unified-staging-venue-absorption-enable-flag-wording.json) | Resolved | 2026-10-31 (coder round, step 4) | 2026-10-31 | Step 4 reworded per the issue's fix (see that step): `scripts/morello/prepare.sh` alone keeps `--enable-flag`; the cheri_riscv64 lane's `enable_riscv64_cheri=yes` comes from `stage_corpus.sh`'s lane table. Implementation had already resolved it by the more-specific clause — wording defect only, no behaviour difference. |
| [makefile-stale-venue-comment](./tmp/reports/2026-10-31-unified-staging-venue-absorption-makefile-stale-venue-comment.json) | Resolved | 2026-10-31 (tester round, step 2) | 2026-10-31 | The Makefile's header lane list and the riscv64-nemu recipe comment still named the bench's `benchmark/platform/riscv64-nemu-linux/` (Step 2's verify greps only `scripts/`). Both comments reworded to the absorbed `scripts/riscv64_nemu/venue/` package; staged. Comment-only, no behaviour change. |

No deferred issues are adopted. The env's one open deferral (`lane-script-hardening-batch`) is an unrelated maintenance batch and stays open.

## Guidance for Coder

**Files to modify:**

- `./env.sh`
- `benchmark` (the submodule gitlink — staged in the same commit, see Step 1)
- `scripts/common/stage_corpus.sh` (new)
- `scripts/common/corpus_manifest.py` (new)
- `scripts/common/derive_registry.py` (deleted)
- `scripts/common/build_corpus.sh` (deleted)
- `scripts/riscv64/build_image.sh`
- `scripts/riscv64/guest/init`
- `scripts/riscv64_nemu/prepare.sh`
- `scripts/riscv64_nemu/run.sh`
- `scripts/riscv64_nemu/venue/` (new — absorbed package, see Step 2)
- `scripts/cheri_riscv64/prepare.sh`
- `scripts/morello/prepare.sh`
- `scripts/morello/run.sh`
- `scripts/cheri/guest/runner`

**Constraints:**

- **One commit.** The pin bump (env.sh text AND the `benchmark` gitlink), the staging swap, the absorption and the deletions land together — a pin bump without the staging swap is the exact Morello token-mismatch breakage the bench plan's risk table names.
- **`/refactor-split` first.** This plan extracts a package, relocates a shared module and consolidates two staging paths into one: per the global refactoring rule, the implementation session runs `/refactor-split` and reads `~/.claude/guides/refactor-split-guidance.md` before editing, and the session report records the cluster-membership rationale, the verbatim-move plan for the absorbed files, and the blast-radius ordering (stage_corpus.sh lands before the old pair is deleted).
- Repo mode Private: commit messages in English, house style of `ef6d7dc`, never any mention of AI tooling.
- **Stage, never commit.** The one commit above lands at `/update-and-commit` finalize, after approval. During rounds: stage explicit paths only (`git add <path>`, never `-A`) — including `git add benchmark` at Step 1 — and never run `git commit`. Step 1's "at commit time" gitlink check is the finalize pass's check, not a round's.
- **Long lane legs (Step 7).** One lane leg per command. A leg can legitimately outlast a single call's cap (the lane's own `LANE_DEPLOY_TIMEOUT`/`LANE_RUN_TIMEOUT` bound it at up to 7200/3600 s), so such a leg runs detached — `setsid make ARCH=<lane> <leg> > tmp/logs/<plan-id>-<leg>.log 2>&1 &` — and is harvested by polling that log with short foreground checks, appending each leg's verdict to the round evidence the moment it lands. At most two guest boots at once; never end the round with a leg still pending without naming it in the session report; a retry round harvests the previous round's completed logs before launching anything new.
- `benchmark/` stays read-only at the pin: staging runs in a **scratch tree** (a private copy of the bench tree under the lane's `build/` area), never in the submodule worktree; the deploy preflight (worktree HEAD == `BENCH_COMMIT`) and post-assert (`git -C benchmark status --short` empty) stay invariants.
- **The invariant this plan exists to establish:** env staging drives the pinned runner (`./run-test corpus make-only exhausted-run` / `./run-test no-make corpus exhausted-run`) — it never recomputes corpus keys, never derives a registry, and never rewrites a skip token. The guest's `configure.json` is the tracked bench registry, copied verbatim.
- **Lock discipline:** `stage_corpus.sh` is caller-locked — every caller (deploy legs) already holds the flock on `build/.lane.lock`; the script documents this in its header and refuses to run if it can verify it is NOT under a held lane lock (same fd-9 inheritance check the aarch64 run path uses). No standalone unlocked invocation is sanctioned.
- Collectors, `version_stamp.sh`, `compare_lanes.py` and the stamp format are untouched — the verdict contract reads record names and result codes, not binary paths.
- `make ARCH=<lane> clean` and the clean asserts stay as they are; `git -C benchmark status --short` (must be empty) before leaving any leg.

## Guidance for Tester

**Tests to create:**

- **Temporary** (all under `./tmp/verification/2026-10-31-unified-staging-venue-absorption/`, all Python, deleted after plan completion):
  - `staged-set.py` — for a staging output dir + lane token: every staged unit is `test/<program>__<key>` (all-keyed); the unit set is computed from the tracked registry (distinct program+key pairs, minus the records whose `skip` names the token) — computed, never hard-coded (246 records enumerate to 145 distinct units on riscv64 today; 143 on cheri_riscv64, 144 on aarch64-morello — the script derives these, prose never carries them); registry-referenced side files present; the plain-name support file `test/acc-check-ASLR` present (its consumer shells out a fixed path — see Summary); `configure.json` byte-identical to `benchmark/configure.json` at the pin; manifest carries `skipped` with reasons and no `expected_failures`.
  - `runner-contract.py` — staging log + guest console evidence: the host leg invoked `run-test corpus make-only exhausted-run` with the lane's skip lines (`Skipped case: …`) present on skip-declaring lanes and absent on riscv64; no env-orchestrated per-unit `make -B test/<prog> K=V` lines; the guest leg's runner command carries `corpus`; the riscv64 `boot.log` shows only `__`-keyed executions.
  - `distribution-equal.py` — record-by-record equality of each re-stamped lane's `results.json` against its standing 2026-10-27 baseline stamp: same records, same verdict codes per record (riscv64 and riscv64-nemu each {225 clean, 21 declared}), timing fields ignored.
  - `comparison-gate.py` — runs `compare_lanes.py` over all seven lanes post-restamp; asserts exit 0 and captures the report.
  - `sys-info-prefix.py` — the new riscv64-nemu `results.dat` still begins with a `test/sys_info.txt` prefix carrying the lane line, the corpus compiler/objdump versions and `BENCH_COMMIT` (the venue's provenance contract, re-produced by the absorbed image builder).
- **Legacy verification scripts — retire in the same commit** (they assert the deleted scripts and the deleted mechanisms; superseded by the four scripts above):
  - `tmp/verification/2026-10-12-test-env-all-archs-step2.py` (asserts `derive_registry.py`/`build_corpus.sh` existence, `-B` per-unit makes, plain-name manifest shape) — retire.
  - `tmp/verification/2026-10-14-cheri-lanes-bringup-bringup-mode.sh` (exercises `--bring-up`) — retire with the tolerance mode.
  - `tmp/verification/2026-10-18-drop-indepassembly-workarounds-step2.py` (asserts `--bring-up` must remain and the SKIP_TABLE rows) — retire; the skip-row knowledge now lives in the bench registry.
  - `tmp/verification/2026-10-19-cheri-objdump-supply-and-aarch64-shim-step12.py` — retarget its `find_sdk_objdump`/stanza assertions to `scripts/common/stage_corpus.sh` (the stanzas are carried verbatim), then keep.
  - `tmp/verification/2026-10-20-riscv64-nemu-lane-step2.py`, `-step3.py`, `-acceptance.sh` (assert the platform path, the RUNSET mechanism, `meta.json runset`, the runset-keyed image layout) — retire; their successors are `runner-contract.py` + `distribution-equal.py` + the gate.
- **Cheri staging legs** (bring-up stays deferred): run the cheri_riscv64 and aarch64-morello deploy-staging legs far enough to produce a corpus; assert `staged-set.py` (skip counts 2 and 1) and that the staging logs record the declared skips as runner 1025-skipped. The CHERI guest boot is NOT exercised — the guest runners' `corpus` word is text-verified only, marked unverified-until-bring-up in the session report.
- **Tests to investigate for retirement:** the five listed above plus any candidate the tester identifies.
- **Scope note:** NO bench-side verification here. This cycle owns the env end-to-end proof at the new pin.

## Summary

**Problem.** Bench `cbe3bf9` deleted `platform/` and moved the CHERI/Morello build skips into the tracked registry. The env repo still pins `f9e4ba7` — and the submodule worktree is ALREADY checked out at `cbe3bf9`, so every deploy preflight (`worktree HEAD == BENCH_COMMIT`) is red right now; the pin bump is a repair, not future-proofing. The env's staging (`build_corpus.sh` + `derive_registry.py`) reimplements the bench's corpus keying in Python and rewrites skip tokens; the riscv64-nemu lane drives `benchmark/platform/riscv64-nemu-linux/` — a directory the new pin no longer has.

**Approach.** One commit that lands the whole successor state:

1. Bump `BENCH_COMMIT` to `cbe3bf9` **and stage the submodule gitlink** (`git add benchmark`) — env.sh text and the recorded pointer must agree in the same commit.
2. A new `scripts/common/stage_corpus.sh` becomes the ONE staging path for every system lane. Algorithm (all inside a **scratch tree** — a fresh copy of the bench tree under the lane's `build/` area, wiped at the start of every staging run): copy the worktree excluding `.git`/`tmp`/`test`/`trace-log`, `make clean` in the copy, purge the arch-scoped stale objects `make clean` leaves (`lib/*/assembly.o`, `lib/*/indepassembly*.o` — `rubbish` is `$(ARCH)`-scoped); build a **host runner** with a scrubbed environment (`env -u CXX -u ASM -u OBJDUMP -u MAKEFLAGS -u MFLAGS -u ARCH make -B run-test CSB_TARGET_ARCH=<token>` plus the lane's enable flag where applicable), assert it is a host ELF; then run `./run-test corpus make-only exhausted-run` with `MAKEFLAGS`/`MFLAGS` scrubbed and the lane's `ARCH`/`CXX`/`ASM`/`OBJDUMP`/`enable_*=yes` exported — **the runner owns keying and skip handling**. Strictness: check the runner's rc and `results.json` presence; abort if any record carries `make-status` (a non-skip build failure is a hard staging error — `--bring-up` dies with the undeclared-failure era). `scripts/common/corpus_manifest.py` (adapted from the venue verifier) then verifies and writes the manifest: expected set = registry units minus records whose `skip` names the lane's token (the venue verifier had no skip branch — the tracked registry now does); manifest fields `units`, `side_files`, `support_files`, `skipped` (with reasons); `expected_failures` is gone.
3. **Staged tree = manifest-driven**: the keyed units, the registry's `test/`-relative side files, and the declared plain-name support files — at minimum `test/acc-check-ASLR`, whose record shells out the fixed relative path `test/acc-check-ASLR 1 <flag>` (`acc/check-ASLR.cpp:53`); without it both ASLR records drift 1→2 and the gate fails. Non-unit build byproducts (plain binaries, objects, the scratch sys_info) are never staged.
4. The NEMU venue package is absorbed into `scripts/riscv64_nemu/venue/` (guest overlay, image builder, boot driver — retrieved from `git show f9e4ba7:platform/riscv64-nemu-linux/…`); the runset mechanism dies everywhere (the lane stages the full registry, as the standing comparison already ran); `prepare.sh`'s corpus leg calls `stage_corpus.sh riscv64-nemu` and its RUNSET plumbing (validation, `OUT/$RUNSET` layout, the recorded runset file) is deleted; `run.sh`'s completeness gate re-points at the staged verbatim registry. The absorbed image builder gains the venue `build-corpus.sh` steps it uniquely owned: the **cross-built guest scheduler** and the **NEEDED + PT_INTERP library closure** staging, plus the guest-truth `bench/test/sys_info.txt` (lane line, corpus compiler/objdump versions, `BENCH_COMMIT`, worktree describe) that prefixes the NEMU lane's `results.dat`. `SEED_DIRS`-style machine-local absolute paths in the absorbed builder become env-relative (`BUILD_DIR`).
5. All guest runners converge on `./run-test no-make corpus exhausted-run`: riscv64 `guest/init` and the CHERI runner default gain `corpus`; the NEMU guest's `bench.sh` already has it; the cross-built guest runners inherit the right baked tokens from their own make invocations (bench `cbe3bf9`'s Morello fix).
6. `derive_registry.py` + `build_corpus.sh` are deleted; `SKIP_TABLE` knowledge retires into the bench registry's declared rows; the image-manifest embedding switches to the new schema (`skipped`, no `expected_failures`).
7. **All seven lanes re-stamp at the new pin** (the five host lanes' runs are untouched by this change — re-stamping is for pin-uniform stamps, exactly why the 2026-10-27 cycle moved all seven) — then the `compare_lanes.py` gate can exit 0.

**Guest filename scheme:** single-map programs gain the `__811c9dc5`-style key suffix; the one consumer of a plain name (`acc-check-ASLR`) is handled by the declared support file, and the Summary's earlier "no consumer reads those names" claim was wrong and is corrected here.

**Out of scope:** CHERI guest bring-up; the in-guest-compiler route (SD-card rootfs); the bench repo (owned by `2026-10-30-portable-core-platform-removal`); `lane-script-hardening-batch`.

## Repo Mode

Private (detected via `detect_repo_mode.py`, 2026-10-31). Commit message: English, house style of `ef6d7dc`, no AI mentions, no Claude artifacts staged.

## Document Overrides

| Document | Rule Overridden | Reason |
|----------|----------------|--------|

Zero overrides. `CLAUDE.md`'s "all pins live in env.sh only" becomes *more* true; the staging swap follows the documented read-only-submodule rule (staging now runs in a scratch tree, which is what that rule's existing text already describes).

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| The deploy preflight is red RIGHT NOW (worktree at `cbe3bf9`, env.sh pinning `f9e4ba7`) | No lane can deploy until this commit lands | Step 1 is the first change; no lane runs happen before it; the commit is atomic so no half-state persists |
| Guest filename scheme change (single-map units keyed) | The one known plain-name consumer (`acc-check-ASLR`'s `system()` call) breaks silently as a 1→2 verdict drift | The declared support file rides the staged tree; `staged-set.py` asserts its presence; `distribution-equal.py` proves both ASLR records kept their verdicts |
| The absorbed verifier's path-length budget | Keyed names are longer than plain names; a stale budget would false-fail staging | `corpus_manifest.py` re-measures its budget against the longest keyed path instead of keeping the venue constant |
| The absorbed image builder regresses NEMU reproducibility or provenance | Image hashes / `results.dat` prefix change | Pinned tarballs and `SOURCE_DATE_EPOCH` are env-owned; `sys-info-prefix.py` asserts the prefix; tester rebuilds one image twice and compares hashes |
| CHERI staging legs exercise new code with deferred bring-up | A staging bug surfaces only when CHERI bring-up resumes | `staged-set.py` runs against both CHERI corpora this cycle; the legs share the orchestrator with the verified riscv64 lane, so only the toolchain stanza differs |
| `MAKEFLAGS` leaks `ARCH=<lane>` from the deploy invocation into the runner's child makes | Units built for the wrong layout | The corpus invocation scrubs `MAKEFLAGS`/`MFLAGS` (the pattern `riscv64_nemu/prepare.sh` already uses) and re-exports the lane's ARCH explicitly |
| Stale cross-built `benchmark/run-test` survives a variable-only change | Wrong-token runner → wrong skips or exec-format failure | `make -B run-test` in a scrubbed env + a host-ELF readelf assertion before use |

## Rollback

- Single-commit revert on the env repo restores env.sh **and the gitlink**; then sync the submodule worktree: `git -C benchmark checkout f9e4ba7addc2865aacdf70f51e9fd203854f4727` (a revert alone moves the pointer, not the worktree — without this the preflights stay red). Consistent resting pair: env `ef6d7dc` ↔ bench `f9e4ba7`, worktree at `f9e4ba7`.
- If the revert happens after a re-stamp, retire the new stamps (move aside) so `compare_lanes.py`'s newest-stamp selection picks the standing 2026-10-27 stamps again.
- The user performs all reverts (push control).

## Proposed Changes

1. **Step 1:** Bump the bench pin — text AND gitlink (`./env.sh`, `benchmark` gitlink)
   → `BENCH_COMMIT=cbe3bf9…` (full 40-hex); update the adjacent comment block (env.sh:15 region) that describes the pinned commit's venue staging — those scripts no longer exist at this pin. Stage the submodule pointer in the same commit: `git add benchmark` (the worktree already sits at `cbe3bf9`; today `git ls-tree HEAD benchmark` records `f9e4ba7` — a commit without the gitlink desyncs every later checkout).
   → coder verify (auto): `grep -c '^BENCH_COMMIT=cbe3bf9' env.sh` is 1; `git -C benchmark status --short` is empty; at commit time `git ls-tree HEAD benchmark` equals the same 40-hex commit.
   → tester verify: `comparison-gate.py`'s stamp gates accept the pin (exactly one 40-hex assignment, parseable registry at the pin).

2. **Step 2:** Absorb the NEMU venue package (`scripts/riscv64_nemu/venue/`)
   → Disposition of the venue tree at `f9e4ba7` (ten files, hyphenated spellings): **absorb** `guest/bench.sh`, `guest/inittab`, `guest/nemu-trap.c`, `build-image.sh` → `venue/build-image.sh`, `run.sh` → `venue/run.sh` (the boot driver), `corpus-manifest.py` → `scripts/common/corpus_manifest.py` (all lanes consume it); **die** `build-corpus.sh` (its unique steps — cross scheduler, lib closure, sys_info — move into `venue/build-image.sh`; its corpus build is superseded by `stage_corpus.sh`), `env.sh` (its toolchain defaults duplicate env.sh's `RISCV64_*` pins; its NEMU/timeout/epoch knobs are already env.sh-owned), `README.md`, `run-native.sh` (host-reference distribution — the comparison gate superseded it). Adaptation rules: (a) source the repo `env.sh` exports (`NEMU_DIR`/`NEMU_BIN`/`NEMU_COMMIT`, `SOURCE_DATE_EPOCH`, `RISCV64_*`), never a venue-local env file; (b) the runset mechanism dies — `prepare.sh`'s RUNSET validation/export and `OUT/$RUNSET` layout, the recorded `build/riscv64-nemu/runset` file, `run.sh`'s runset re-read and the runset-keyed `meta.json`/image paths are deleted; the completeness gate compares against the staged verbatim registry; (c) internal path plumbing points into the absorbed tree; (d) `corpus_manifest.py` gains a lane-token argument and skip-awareness (expected set excludes records whose `skip` names the token; emits `skipped` with reasons; re-measures its path-length budget against keyed names); (e) the absorbed image builder's machine-local absolute `SEED_DIRS` becomes env-relative via `BUILD_DIR`; (f) re-verify the absorbed boot driver's timeout message still matches the literal `run.sh` wrapper greps for (`"NEMU timed out"`), and note the negative (timeout) branch stays covered by that wrapper's existing handling.
   → coder verify (auto): `git grep -rn "benchmark/platform" scripts/` is empty; every path `prepare.sh`/`run.sh` reference under `scripts/riscv64_nemu/venue/` exists; `scripts/common/corpus_manifest.py --help` runs; `git grep -n "RUNSET" scripts/riscv64_nemu/` is empty.
   → tester verify: the riscv64-nemu deploy completes using only absorbed scripts (Step 7).

3. **Step 3:** The unified staging orchestrator (`scripts/common/stage_corpus.sh`)
   → Interface: `stage_corpus.sh LANE OUT_DIR [--enable-flag enable_aarch64_morello]` — the flag is accepted only in that exact spelling and only for the `aarch64-morello` lane; no `--env-lane`, no `--bring-up`. Header documents caller-locked semantics. Input guards carried verbatim from the old script: the LANE whitelist and the OUT_DIR block (normalize to absolute; refuse `/`, the repo root, and anything under `benchmark/`) — before any `rm -rf`. Lane table: `riscv64`→(riscv64 stanza, ARCH=riscv64, token riscv64, no flag), `riscv64-nemu`→(same stanza/tools, ARCH=riscv64, token riscv64), `cheri_riscv64`→(CHERI stanza, ARCH=cheri_riscv64, token cheri_riscv64, `enable_riscv64_cheri=yes`), `aarch64-morello`→(Morello stanza, ARCH=aarch64, token aarch64-morello, `enable_aarch64_morello=yes`) — the bench-ARCH and skip-token columns are distinct on purpose; the old stanza's `ARCH="$LANE"` line and its case labels are NOT carried verbatim. Algorithm: (a) wipe + create the scratch tree (copy excluding `.git`/`tmp`/`test`/`trace-log`; `make clean` in the copy; purge `lib/*/assembly.o` and `lib/*/indepassembly*.o`; place the registry copy); (b) per-lane toolchain stanza (carried from the old script's SDK-resolution helpers and tool blocks); (c) host runner: scrubbed-env `make -B run-test CSB_TARGET_ARCH=<token>` (+ the Morello flag forwarded so the distinct token bakes), then readelf-assert a host ELF; (d) corpus invocation: `unset MAKEFLAGS MFLAGS ARCH`, export `ARCH`/`CXX`/`ASM`/`OBJDUMP` and `<enable_flag>=yes` (the flag must ride the ENVIRONMENT — the runner's child makes take no command-line flags), run `./run-test corpus make-only exhausted-run`; check rc and `results.json` presence, abort naming the leg and log; (e) strictness: no record may carry `make-status`; (f) `corpus_manifest.py --lane <token>` verifies and writes the manifest; (g) stage OUT_DIR: keyed units + registry side files + the support file `test/acc-check-ASLR`, plus `configure.json` (verbatim tracked registry) and `manifest.json`; assert the staged unit set is non-empty and equals the expected registry-minus-skips set before publishing. Scratch path under the lane's `build/` area; wiped at the start of every run so a killed run leaks nothing.
   → coder verify (auto): usage with no args exits 2; `OUT_DIR=/` and `OUT_DIR=benchmark/x` exit 2 with nothing deleted; a riscv64 staging via the locked deploy leg produces the three outputs; the staging log contains the runner's `corpus:` snapshot lines, no env-computed keys, and — on a skip-declaring lane — the runner's `Skipped case:` lines.
   → tester verify: `staged-set.py` (riscv64) and `runner-contract.py` pass.

4. **Step 4:** Rewire the staging consumers
   → `scripts/riscv64/build_image.sh`: call `stage_corpus.sh`, install `$CORPUS/configure.json` (tracked registry), update the image-manifest embedding to the new schema (`skipped`, no `expected_failures`). `scripts/cheri_riscv64/prepare.sh` and `scripts/morello/prepare.sh`: swap the call AND drop `--env-lane "$LANE"` (the skip token now rides the runner's baked token). Only `scripts/morello/prepare.sh` keeps `--enable-flag enable_aarch64_morello` — the flag accepted by Step 3's interface; the cheri_riscv64 lane's `enable_riscv64_cheri=yes` comes from `stage_corpus.sh`'s lane table, so its call takes no flag (issue `enable-flag-wording`). `scripts/riscv64_nemu/prepare.sh`: the corpus leg (`run_leg "$PLATFORM/build-corpus.sh"` today) calls `stage_corpus.sh riscv64-nemu`; the absorbed `venue/build-image.sh` consumes stage_corpus's OUT_DIR and performs the cross-built guest scheduler + the NEEDED/PT_INTERP library closure + `bench/test/sys_info.txt` (the steps that were venue `build-corpus.sh`'s alone).
   → coder verify (auto): `git grep -n "build_corpus.sh" scripts/` is empty in live code; `git grep -n -- "--env-lane" scripts/` is empty; the image manifest parses with `skipped` and no `expected_failures`; `scripts/riscv64_nemu/prepare.sh` references `stage_corpus.sh`.
   → tester verify: `staged-set.py` passes for both CHERI corpora (skip counts 2 and 1); the riscv64 image manifest parses with the new schema.

5. **Step 5:** Guest runners converge on corpus mode
   → `scripts/riscv64/guest/init` (runner line + header comment): `./run-test no-make corpus exhausted-run`. `scripts/cheri/guest/runner`: `RUN_TEST_ARGS` default becomes `no-make corpus exhausted-run`. `scripts/morello/run.sh`: the comment at line 16 updated to match. The absorbed NEMU `bench.sh` already carries the corpus line — untouched.
   → coder verify (auto): every guest runner invocation carries `corpus`; zero bare `no-make exhausted-run` runners remain.
   → tester verify: `runner-contract.py` passes on the riscv64 boot evidence; CHERI guest runners marked text-verified only.

6. **Step 6:** Delete the duplicated staging
   → `git rm scripts/common/derive_registry.py scripts/common/build_corpus.sh`. The `SKIP_TABLE` and its classification-artifact pointer retire — the knowledge lives in the bench registry's declared rows.
   → coder verify (auto): `git ls-files scripts/common` shows exactly `compare_lanes.py`, `shim.sh`, `version_stamp.sh`, `stage_corpus.sh`, `corpus_manifest.py`; `git grep -rn "derive_registry\|SKIP_TABLE\|build_corpus" scripts/ Makefile env.sh` is empty (doc files are the planner round's gate, below).
   → tester verify: no live reference to the deleted scripts anywhere in `scripts/`, `Makefile`, `env.sh`.

7. **Step 7:** Re-stamp ALL SEVEN lanes and gate
   → `make ARCH=riscv64 deploy run`, `make ARCH=riscv64-nemu deploy run`, and the five host lanes' runs (`make ARCH=x86_64 run`; `make ARCH=aarch64 run` and the `pa`/`bti`/`mte` variants) — the host lanes' behavior is untouched by this change, but `compare_lanes.py` refuses any stamp whose `bench-head` differs from the pin, so pin-uniform stamps require all seven (the same reason the 2026-10-27 cycle moved all seven in one cycle). Expected: riscv64 and riscv64-nemu each at 246 records {225 clean, 21 declared}, record-for-record equal to each other and to the standing stamps; the host lanes' distributions unchanged; gate exit 0. The riscv64 `boot.log` shows all-keyed executions.
   → coder verify (auto): seven fresh stamps with `run-status: ok` and parseable `results.json` + `results.dat`.
   → tester verify: `distribution-equal.py` passes for all seven lanes against the 2026-10-27 baselines; `comparison-gate.py` exits 0; `runner-contract.py` and `sys-info-prefix.py` pass.

## Guidance for Planner

Documentation tasks you will execute yourself (not the coder):

- **Files to modify:**
  - `./CLAUDE.md`
  - `./README.md`
  - `./doc/architecture.html`
  - `./doc/lanes.html`
  - `./doc/content.html`
- **Never-silently-delete compliance:** CLAUDE.md's compactness rule forbids silent removal — list every sentence slated for deletion (the `derive_registry`/`build_corpus.sh` Architecture sentences, the runset exception paragraph, the Purpose paragraph's venue attribution) in the session report with the reason each is outdated, and obtain the user's explicit approval before removing; replace rather than delete wherever a statement of the new contract is needed anyway.
- **When:** after the coder round finishes; the tester's comparison gate runs after this round.
- **What to sync:**
  - `CLAUDE.md` Purpose: the riscv64-nemu lane is the absorbed in-repo venue package, not "the bench's own NEMU venue". Rules: the read-only-submodule bullet keeps its scratch-tree invariant (staging runs under the lane's `build/` area). Architecture: replace the `derive_registry.py`/`build_corpus.sh` sentences with the unified contract (one orchestrator drives the pinned runner's corpus mode; the guest's `configure.json` is the tracked registry; the runset exception paragraph dies with the runset — pending the approval above). Structure: the `scripts/common/` listing and the `riscv64_nemu/` entry (absorbed venue package). Commands: the dump-refusal rationale widens to all system lanes' staged corpora.
  - `README.md`: the Pins row and Known-caveats pin claims (README:253, 452-460) — after this cycle all seven executable lanes carry `cbe3bf9` stamps; mark any stamp that predates a bump honestly; re-derive or remove the staged-units figure (README:318-319) — describe the keyed scheme, never a count; the manifest paragraph (README:196-198) → new schema (`units`, `side_files`, `skipped`); the venue-path bullet, NEMU caveat and Usage row (README:31, 113, 116, 390) → the absorbed package; the runset passages (README:28, 152, 166-170, 186, 348-349) → the tracked registry; the Comparing-lanes paragraph (206-218) stays accurate (pin-uniform after this cycle).
  - `doc/architecture.html`: the Deploy section's staging sentences AND the manifest sentence (lines 90-92) → new schema.
  - `doc/lanes.html`: the riscv64-nemu section (lines 219, 229-236, 248-250) — absorbed package, no runset, completeness gate vs. the tracked registry; the CHERI sections' corpus wording; per-lane guest-runner corpus lines; the pin rationale row for the bench commit.
  - `doc/content.html`: the introduction's venue/build-corpus/runset sentence and the derived-registry phrase (lines 23-27, 87).
  - No exact counts in prose anywhere — describe mechanisms, never unit/record figures.
  - The timeout wrapper's `"NEMU timed out"` grep source-of-truth note moves to the lanes page with the absorbed driver.

## History

| Date | Event | Conclusion | Dismissed |
|------|-------|------------|-----------|
| 2026-10-31 | Tester round (14:53–15:40, one attempt, exit 0) | SUCCESS, 12/12 checks, zero blocking failures, one declared skip class (CHERI guest boot — the plan's deferral; the runners' corpus mode is text-verified only, unverified-until-bring-up). Five planned scripts + image-repro (the Risks-table mitigation: two byte-identical rebuilds of the absorbed image builder) all PASS; staged-set verified on all four system lanes (145/145/143/144 units; skips 0/0/2/1 with runner-declared reasons recorded at 1025); distribution-equal: all seven lanes record-for-record equal to the 2026-10-27 baselines, riscv64/riscv64-nemu each {225 clean, 21 declared}; gate exit 0 at the pin; NEMU `results.dat` provenance prefix holds; CHERI staging legs executed green. Legacy verification: 12 scripts retired, 2 retargeted and kept (`2026-10-19-…-step12.py` → `stage_corpus.sh`; `2026-10-24-skip-recheck.py` → the tracked registry's skip rows). One non-blocking issue filed (`makefile-stale-venue-comment` — resolved above). One out-of-scope bench-side observation: at `cbe3bf9` the tracked registry's cheri_riscv64 `acc-get-frame-size` skip row is stale (the unit now compiles) — the bench-internal cycle owns the registry, no plan-scoped issue. | — |
| 2026-10-31 | Coder round (13:18–14:37, one attempt, exit 0) | All 7 steps completed and staged, HEAD unmoved, no commit (stage-only held). Session report + issue `enable-flag-wording` (resolved, above). Tree-verified by the operating session: invariant greps empty, `scripts/common` = the five declared files, staged gitlink `cbe3bf9`, seven fresh stamps all `run-status: ok`, guest runners carry `corpus` (CHERI text-verified), `compare_lanes.py` exit 0 with riscv64/riscv64-nemu each {225 clean, 21 declared}. Extra files touched beyond the plan's list — each a one-line stale reference the swap itself created: `Makefile` (dump comment naming $OUT/$RUNSET), `scripts/riscv64/run.sh` + `scripts/cheri_riscv64/run.sh` (guest-runner comment lines naming the bare runner), `scripts/cheri/build_image.sh` (comment naming build_corpus.sh); env.sh additionally gained the venue's upstream pins (NEMU_WB_*/NEMU_OPENSBI_*/NEMU_LCA_*). Venue scripts carry mode 0644 (sandbox denied chmod); every caller invokes `bash <path>`, bench.sh installs 0755. CHERI staging legs left to the tester per plan. | — |
| 2026-10-31 | Pre-launch revision (operating session) | Two execution-mechanics constraints added to Guidance for Coder, no step or file-list change: stage-never-commit (the consolidated commit belongs to `/update-and-commit` finalize — the standing single-commit doctrine) and the long-lane-leg detach-and-harvest pattern (Step 7's system-lane boots can outlast one headless call cap; the coder definition carries no such discipline, and rounds 28–29 of the CHERI plan lost in-flight boots without it) | — |
| 2026-10-31 | Mega-audit (pre-implementation, run wf_1be80cad-efb) | 86 findings (20 High, 51 Medium, 15 Low); report at [2026-10-31-unified-staging-venue-absorption-mega-audit-2026-10-31.json](../tmp/reports/2026-10-31-unified-staging-venue-absorption-mega-audit-2026-10-31.json). All Highs fixed by the rewrite: all-seven re-stamp (the gate refused mixed pins), the NEMU staging contract (corpus leg → stage_corpus.sh; cross scheduler + lib closure + sys_info owned by the absorbed image builder), skip-aware corpus_manifest.py, the `acc-check-ASLR` plain-path support file (the "no consumer reads plain names" claim was false), scratch-tree hygiene absorbed (arch-scoped object purge), OUT_DIR/LANE guards carried, env-scrubbed `make -B` host runner, enable-flag-via-environment, gitlink staging + submodule-aware rollback, the "no window" risk claim corrected (worktree already at cbe3bf9 — preflights red now), and the seven legacy verification scripts retired/retargeted. Mediums folded: RUNSET plumbing deletions enumerated, records-vs-units distinction (compute, never hard-code), manifest-schema doc sync, morello/run.sh in the file lists, /refactor-split gate, never-silently-delete compliance, metadata path shapes | [30 stanza-line-hint](../tmp/reports/2026-10-31-unified-staging-venue-absorption-mega-audit-2026-10-31.json) (helper lives at :111, not :112 — cosmetic), [38 quarantine](../tmp/reports/2026-10-31-unified-staging-venue-absorption-mega-audit-2026-10-31.json) (script retirement/quarantine is the established post-commit sweep), [73 acceptance-classifier](../tmp/reports/2026-10-31-unified-staging-venue-absorption-mega-audit-2026-10-31.json) (field reads superseded by retiring the script) |
| 2026-10-31 | Initial plan | Drafted from the bench cycle's hand-off: pin bump, unified runner-driven staging, venue absorption, guest-runner convergence, deletions, re-stamps + gate | — |

## Plan Metadata

```json
{
  "plan_id": "2026-10-31-unified-staging-venue-absorption",
  "steps": [
    "Step 1: Bump the bench pin — text AND gitlink (./env.sh, benchmark gitlink)",
    "Step 2: Absorb the NEMU venue package (scripts/riscv64_nemu/venue/)",
    "Step 3: The unified staging orchestrator (scripts/common/stage_corpus.sh)",
    "Step 4: Rewire the staging consumers",
    "Step 5: Guest runners converge on corpus mode",
    "Step 6: Delete the duplicated staging",
    "Step 7: Re-stamp ALL SEVEN lanes and gate"
  ],
  "coder_files": [
    "./env.sh",
    "benchmark",
    "./Makefile",
    "scripts/common/stage_corpus.sh",
    "scripts/common/corpus_manifest.py",
    "scripts/common/derive_registry.py",
    "scripts/common/build_corpus.sh",
    "scripts/riscv64/build_image.sh",
    "scripts/riscv64/run.sh",
    "scripts/riscv64/guest/init",
    "scripts/riscv64_nemu/prepare.sh",
    "scripts/riscv64_nemu/run.sh",
    "scripts/riscv64_nemu/venue/",
    "scripts/cheri_riscv64/prepare.sh",
    "scripts/cheri_riscv64/run.sh",
    "scripts/cheri/build_image.sh",
    "scripts/morello/prepare.sh",
    "scripts/morello/run.sh",
    "scripts/cheri/guest/runner"
  ],
  "tester_files": [
    "./tmp/verification/2026-10-31-unified-staging-venue-absorption-staged-set.py",
    "./tmp/verification/2026-10-31-unified-staging-venue-absorption-runner-contract.py",
    "./tmp/verification/2026-10-31-unified-staging-venue-absorption-distribution-equal.py",
    "./tmp/verification/2026-10-31-unified-staging-venue-absorption-comparison-gate.py",
    "./tmp/verification/2026-10-31-unified-staging-venue-absorption-sys-info-prefix.py"
  ],
  "doc_files": ["./CLAUDE.md", "./README.md", "./doc/architecture.html", "./doc/lanes.html", "./doc/content.html"],
  "verification_scripts": [
    "./tmp/verification/2026-10-31-unified-staging-venue-absorption-staged-set.py",
    "./tmp/verification/2026-10-31-unified-staging-venue-absorption-runner-contract.py",
    "./tmp/verification/2026-10-31-unified-staging-venue-absorption-distribution-equal.py",
    "./tmp/verification/2026-10-31-unified-staging-venue-absorption-comparison-gate.py",
    "./tmp/verification/2026-10-31-unified-staging-venue-absorption-sys-info-prefix.py"
  ],
  "repo_mode": "Private",
  "document_overrides": []
}
```

## Audit Accumulation

| Counter | Value | Last Updated |
|---------|-------|--------------|
| issues_resolved_since_audit | 1 (`enable-flag-wording`) | 2026-10-31 |
| steps_changed_since_audit | 1 (Step 4 parenthetical reworded — no semantic change) | 2026-10-31 |
| files_changed_since_audit | 4 added to coder_files (Makefile, riscv64/run.sh, cheri_riscv64/run.sh, cheri/build_image.sh — one-line stale-reference fixes) | 2026-10-31 |

## Documentation

Docs sync is concentrated in Guidance for Planner (`CLAUDE.md`, `README.md`, `doc/architecture.html`, `doc/lanes.html`, `doc/content.html`), with explicit line-level stale passages enumerated there. The pins' README table already carries the NEMU entries; only the bench-commit value changes. No exact counts in prose per the workspace documentation rule.

## Final Results

Landed 2026-10-31 as one staged change set (committed at finalize). The bench pin is
`cbe3bf9` (env.sh text + gitlink, one commit). One staging path (`scripts/common/stage_corpus.sh`)
drives the pinned runner's corpus mode for every system lane in a scratch tree;
`corpus_manifest.py` verifies and writes the new-schema manifest; the NEMU venue package
is absorbed at `scripts/riscv64_nemu/venue/`; the runset mechanism and the old staging pair
are gone. All seven executable lanes re-stamped at the pin (2026-10-31T05-06Z stamps,
all `run-status: ok`), record-for-record equal to their 2026-10-27 baselines
(riscv64 and riscv64-nemu each {225 clean, 21 declared}); `compare_lanes.py` exits 0.
Verified end-to-end by the tester round (12/12; CHERI guest boots remain deferred bring-up,
their staging legs green). Two issues found and resolved in-cycle (`enable-flag-wording`,
`makefile-stale-venue-comment`); one out-of-scope bench-side observation recorded in the
tester report (stale cheri skip row, bench-owned). Follow-ups that own their own cycles:
the bench registry's stale row, CHERI bring-up, `lane-script-hardening-batch`.
