# Plan: Drop the indepassembly workarounds — pin the bench at the translated + flag-complete commit, check out the submodule, and re-accept every non-x86 lane
**Project:** /home/wsong83/proj/xiangshan/cpu-sec-test-env
**Plan ID:** 2026-10-18-drop-indepassembly-workarounds
**Created:** 2026-10-18

## Issue Log

Rows ordered newest-first.

| Issue | Status | Found | Resolved | Resolved By |
|-------|--------|-------|----------|-------------|
| [func-opcode-gen-helper-symbol-match](./tmp/reports/defer-issue-func-opcode-gen-helper-symbol-match.json) — cross-repo (bench): the extraction scripts' `grep helper` matches the translated `assembly_helper` symbol, so the opcode side file is empty; riscv64 `acc-read-func` regressed 0 → 1 at the pin. Handoff row for the bench sweep. | Open | 2026-10-18 | — | — |
| [indepassembly-return-site-untranslated](./tmp/reports/defer-issue-indepassembly-return-site-untranslated.json) — env-side copy; the bench-side translation is committed (`db84315`) and the cheri flag gap it exposed is fixed by bench plan `2026-10-18-cheri-asmflags` (commit `33f6f84b10080888d98eed535dda8313a914d161`, pushed to `origin/master` 2026-10-18; this plan's pin). Both asmfunc records execute on all seven lanes (Step 3/4 evidence). | Resolved | 2026-10-11 | 2026-10-18 | tester |

## Guidance for Coder

**Files to modify:**

- `./env.sh`
- `./scripts/common/derive_registry.py`
- `./scripts/common/build_corpus.sh`
- `./scripts/riscv64/build_image.sh`
- `./scripts/cheri_riscv64/prepare.sh`
- `./scripts/morello/prepare.sh`
- `./scripts/aarch64/prepare.sh`
- `./scripts/aarch64/run.sh`

**Do NOT:** edit any file under `benchmark/` (Step 1 only *checks out* the pinned commit; the submodule's content is read-only at the pin); change the CHERI lanes' per-lane recorded-build-failure skip rows (`acc-get-frame-size`, `mss-write-by-stack-pointer`, `cfi-call-mid-func` — they are CHERI-platform facts, not the workaround this plan removes); remove the `--bring-up` mode from `build_corpus.sh` (the prepares simply stop passing it); add platform flags to any script (the bench's own flag block supplies them at the pinned commit); alter results layout or the lane lock discipline. The two CHERI prepares DO gain the same EXIT cleanup trap `riscv64/build_image.sh` already has (Step 2) — that is required by the strict-mode flip, not a discipline change.

**Step-by-step with verification:** `(auto)` checks are mechanical commands whose output is the check. Steps 1–2 are coder-owned; Step 3 is planner-hosted; Step 4 is tester-owned; Step 5 is planner-owned. The `(scripted)` check for Steps 1–2 is `python3 ./tmp/verification/2026-10-18-drop-indepassembly-workarounds-step2.py`, run from the repo root (exit 0 = pass; proven red against the pre-change tree).

## Guidance for Tester

**Tests to create:**

- **Temporary:** `./tmp/verification/2026-10-18-drop-indepassembly-workarounds-acceptance.sh` — per-lane acceptance over the seven stamps named by the Step 3 run log (the lane→stamp map written there: `./tmp/logs/2026-10-18-drop-indepassembly-workarounds-stamps.tsv`, never "latest by mtime"):
  - **Structural checks (hard gate):** each named stamp exists and carries 246 records; both asmfunc records executed (`result != 1025`); `results.dat` not-run counts exactly — `skipped for this platform` / `failed to build` = `0/0` (riscv64, aarch64, aarch64-pa, aarch64-bti, aarch64-mte), `2/0` (cheri_riscv64), `1/0` (aarch64-morello); `git -C benchmark status --short` empty; each stamp's `versions.txt` names the pin. A missing stamp is a loud failure, named.
  - **Verdict checks (pass-with-handoff):** a code outside `{0} ∪ expect-results` on any record is a **handoff row** (recorded with its evidence), not a gate failure — except `1025` on the asmfunc records, which is a structural failure. This is the branch Step 3/Risk 2 define; the gate must not make it unreachable.
  - `versions.txt` echoes `env.sh` (necessarily); the checkout evidence is the planner's run-time `rev-parse` log from Step 3 plus the Step 1 remote check.

**Tests to update (machine-local re-baseline targets — the `.py` targets are also listed in `verification_scripts`):**

- `./tmp/verification/2026-10-12-test-env-all-archs-step1.py` — (a) the env.sh `pins` presence list at line 46 still hard-codes `"c2c7039"`: delete it (the pin is checked separately); (b) replace the `BENCH_SHA = c2c7039…` literal (line 92) with the `BENCH_COMMIT` read from `env.sh`; (c) replace the substring check `BENCH_SHA in r.stdout` with **HTTP 200 AND `json.loads(body)["sha"] == pin`** — the API's 422 body echoes the requested SHA, so a substring test is a false-green; (d) distinguish curl failure / 403 rate-limit / 422 missing-commit as three outcomes.
- `./tmp/verification/2026-10-12-test-env-all-archs-step2.py` — **delete the stale `build/verify-step2/` corpus first** (the script reuses it if present). Remove the `if prog in INDEPASSEMBLY_PROGRAMS: continue` exclusion from the expected-files loop (line ~129) and the `expected_skips`/`expected_failures` non-empty assertions; 145 units enumerated, **145 built**; remove the `disable_independent_assembly=yes`-in-`build_corpus.sh` check (line ~168); `manifest["expected_failures"] == []`; fix the `registry pinned at c2c7039` message (line ~117); update the docstring and final message.
- `./tmp/verification/2026-10-12-test-env-all-archs-step3.py` — parameterize the lane: the script hard-codes `LANE = "aarch64"`; make it iterate the four lane/stamp names (`aarch64`, `aarch64-pa`, `aarch64-bti`, `aarch64-mte`). For each: 0 build-failure 1025s, both asmfunc records executed, no `disable_independent_assembly` check.
- `./tmp/verification/2026-10-12-test-env-all-archs-step4.py` — remove the `INDEPASSEMBLY_PROGRAMS` exclusion in `expected_unit_files()` (lines ~83-85) and the now-dead 1025 membership branch; `N_BUILT` 143 → 145; `n_skip` 2 → 0; `results.dat` `# not run (skipped for this platform): 0`; update the `(145 enumerated - 2 declared failures)` messages.
- `./tmp/verification/2026-10-14-cheri-lanes-bringup-scripts.py` — invert the Step 10 check at `:563`: the `"*"` row and `EXPECTED_FAILURES` are gone; the two per-lane rows remain exact. (`...-wiring.py` needs no change — the `--bring-up` capability remains.)
- `./tmp/verification/2026-10-14-cheri-lanes-bringup-classify.sh` — re-point the stamps; change `declared_skips != (ASMFUNC | lane_skip_rows)` to the lane skip rows only; scope or drop the run-5 bucket-(c) baseline equality so new asmfunc rows can be emitted as handoff entries (never an expectation failure); recompute the pass/expected_nonzero/skipped counts from the observed run.
- `./tmp/verification/2026-10-14-cheri-lanes-bringup-lanes.sh` — re-point to the new CHERI stamps and live payloads: `expected_failures` `[]`, declared skips 2 / 1, units 143 / 144, the line-43 pin comment; keep its independent checks (image hash, driver argv de-dup, 124-no-publish).

**Tests to investigate for retirement:**

- `./tmp/verification/2026-10-12-test-env-all-archs-step5.py` — checks the bench deferral file under `benchmark/tmp/reports/`, which the bench plan already retired; retire the check (or the script) and say so in the report.
- `./tmp/verification/2026-10-14-cheri-lanes-bringup-derive-regression.py` — asserts the riscv64 derived output is byte-identical to `git show HEAD`; red by design before this plan's commit and a tautology after it. Retire it (temporary artifact of the completed C1 plan).

## Summary

**Problem.** The bench's independent-assembly translation is committed and pushed (`db84315`), but the env still runs at the old pin with three layers of workaround: the `BENCH_COMMIT` pin, the `"*"` skip row for the two asmfunc records in `derive_registry.py`, and `disable_independent_assembly=yes` injected at six build sites. Until they are removed and the lanes re-run, the bench-side fix is never exercised — the two asmfunc records have never been built or run on any non-x86 lane, and B1's recorded caveats (link-stage unexercised; in-guest cross-arch unverified) remain open.

**Bench prerequisite (decided 2026-10-18).** Removing the knob exposed a bench-side gap: `enable_riscv64_cheri` carried no `--target` and no `ASMFLAGS`, so the SDK clang assembled the translated object for the host triple (`invalid instruction mnemonic 'addi'`, probe 2026-10-18). Platform support belongs in the bench (the `enable_aarch64_morello` block is the precedent), so bench plan `2026-10-18-cheri-asmflags` completed the cheri flag block and produced **this plan's pin**: `33f6f84b10080888d98eed535dda8313a914d161` ("Make enable_riscv64_cheri own its target triple on every build path"). The pin is not `db84315`; it is **pushed to `origin/master`** (verified 2026-10-18 via `api.github.com`: HTTP 200 and `master` tip = the pin). For reproducibility, the push (done) was `git -C benchmark push origin 33f6f84…:master` — note `git push origin HEAD` fails from a detached HEAD.

**Second requirement found in review (2026-10-18).** No lane checks out or asserts the submodule pin: only the x86_64 `deploy` recipe compares `git -C benchmark rev-parse HEAD` with `$BENCH_COMMIT` (`Makefile:120`), and `version_stamp.sh` records the *pin from env.sh* (`cat env.sh`), not the checkout. Bumping `BENCH_COMMIT` without an explicit checkout would build `c2c7039`'s tree while every manifest and `versions.txt` claims the new pin — the open deferral `submodule-pin-unverified`'s failure mode. Step 1 therefore checks out the pinned commit, stages the updated gitlink, and gates on remote provenance; the run-time `rev-parse` is recorded per deploy.

**Approach.** Bump the pin, check out the submodule, delete exactly the workaround surface, flip the CHERI prepares to strict corpus mode (with the cleanup trap strict mode now needs), and re-run every non-x86 lane: `riscv64`, plain `aarch64`, the three aarch64 variants (`pa`, `bti`, `mte` — the changed MAKEFLAGS are shared), `cheri_riscv64` and `aarch64-morello`. This is the plan that turns B1's object-level proof into execution evidence, including the **first execution of the Morello purecap body** (a deviating verdict is a bench-side decision, never an env skip).

**Workaround sites (located 2026-10-18):**

| Site | Workaround |
|------|-----------|
| `env.sh:9` | `BENCH_COMMIT=c2c7039…` → `33f6f84b10080888d98eed535dda8313a914d161` (the `2026-10-18-cheri-asmflags` commit) |
| `scripts/common/derive_registry.py:40,44,56-57,65-66` | the two-program contents of `EXPECTED_FAILURES` (the constant stays as `[]` for the manifest key) + `SKIP_REASON` + the `"*"` row in `SKIP_TABLE` (line 66) + the dead `"*"` fallback in `skip_reason()` |
| `scripts/common/build_corpus.sh:209` | `disable_independent_assembly=yes` in the unit make invocation |
| `scripts/riscv64/build_image.sh:83` | same, in the riscv64 corpus/scheduler build (also its header's "143 staged units") |
| `scripts/cheri_riscv64/prepare.sh:112` (+ `--bring-up` at :102 and its comment) | same + tolerant mode |
| `scripts/morello/prepare.sh:120` (+ `--bring-up` at :107 and its comment) | same + tolerant mode |
| `scripts/aarch64/prepare.sh:127` and `scripts/aarch64/run.sh:96` | same inside both MAKEFLAGS strings (recorded + exported — change together) |

**Post-change shape (verified against the current registry):** 246 records / 103 programs / 145 units; staged units `145 / 143 / 144` (riscv64 / cheri_riscv64 / aarch64-morello); derived skips `0 / 2 / 1`; `expected_failures` empty on every lane; `results.dat` not-run lines `0/0`, `0/0`, `2/0`, `1/0` (`skipped` / `failed to build`).

**Alternatives considered:** carrying the cheri assembler flags in the env's `ASM=` string — rejected by the user (2026-10-18): platform support belongs in the bench, and the env-side string would re-create a per-consumer workaround; keeping `--bring-up` on the CHERI prepares for a soft transition — rejected: after the translation every unit must build in strict mode, and a silently tolerated build failure is exactly the class this plan exists to eliminate; removing the `--bring-up` capability from the shared builder — rejected (it stays as the documented future-bring-up tool).

**Out of scope:** the bench sweep (`2026-10-14-deferred-issue-sweep` in the bench repo) — any CHERI-lane verdict for the asmfunc records or others outside `expect-results` is recorded and handed to that sweep as a bench-side decision, not skipped here; the durable per-lane pin assertion (`submodule-pin-unverified`, still open) — this plan performs the one-time checkout, gates on remote provenance and records the run-time HEAD, but the lane-script assertion remains the deferral's work; the aarch64 bucket-(c) semantics verdicts (unchanged by this plan); the workspace-level `CLAUDE.md` row update (a tracked planner follow-up — see Guidance for Planner).

## Repo Mode

Public

## Document Overrides

| Document | Rule Overridden | Reason |
|----------|----------------|--------|

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| The submodule is not at the pin, the pin is not on the remote, or the gitlink is not committed | lanes build the wrong tree while manifests/versions.txt claim the pin; a fresh clone cannot fetch the gitlink | Step 1's explicit checkout + `git add benchmark` + a remote-provenance check; the scripted verifier asserts pin == checkout HEAD, cleanliness, the bench ASMFLAGS line, and (API) that `master` carries the pin; the planner records `rev-parse HEAD` per deploy |
| The Morello purecap bodies misbehave at run time (never executed before) | a lane's asmfunc verdict deviates or the test aborts | the scheduler records any code — an out-of-`expect-results` verdict is a handoff row, never a skip and never a silent pass; a genuine defect becomes a bench-side deferral |
| Removing `disable_independent_assembly` exposes a latent link-stage problem the object-level checks could not see (B1 caveat 2) | strict-mode corpus build aborts on one lane | strict mode fails loudly at build (the intended signal); the prepares' new EXIT traps clean the submodule and re-exit non-zero; classify bench-side; do not re-add the workaround |
| A lane produces **no stamp** (deploy abort, or a run hitting `LANE_RUN_TIMEOUT` → exit 124 publishes nothing) | the seven-stamp acceptance has no row for it | Step 3 records it as a named lane failure with the log tail; a timeout may be retried once (same configuration, recorded), a deploy abort is classified, never retried; the acceptance script fails loudly on a missing stamp |
| The aarch64 variants' runtime behaviour under PAC/BTI/MTE differs from plain aarch64 | a variant's asmfunc verdict deviates | all three variants are re-run in Step 3; any deviation is a handoff row, never a skip |
| The derived-registry and lane verifiers encode the old shape | verifiers block the round | Step 4 re-baselines every named verifier first (the `.py` targets are in `verification_scripts`), records the exact diffs, and deletes the stale `build/verify-step2/` cache |
| aarch64's two MAKEFLAGS strings drift while edited | recorded evidence diverges from the build actually run | change both in the same edit; the scripted verifier asserts the two strings are identical |
| Seven lane runs (CHERI ≈ 25–30 min each; the host lanes quick) | round-cap pressure | lanes are planner-hosted per C1's precedent (through its PATH-fixing host-run driver), one at a time; the tester verifies published stamps rather than re-running them |
| The removal proves wrong in practice and must be backed out | the non-x86 lanes regress | rollback is one commit: `git revert` restores the `c2c7039` pin, the `"*"` skip row and the six knob sites; results stamps are append-only, so no artifact migration is involved |

## Proposed Changes

Each step includes verification checks tagged with confidence (see Prime Directive 4).
`(auto)` = mechanical, coder self-verifies. `(scripted)` = deterministic multi-step, coder runs the provided script.
Every step has at least one verification check executable by its owner.

1. **Step 1:** In `env.sh`, set `BENCH_COMMIT` to `33f6f84b10080888d98eed535dda8313a914d161` (the `2026-10-18-cheri-asmflags` commit, whose `Makefile` carries the `enable_riscv64_cheri` `ASMFLAGS` line; already pushed to `origin/master`) and update the accompanying comment. Check the submodule out at that commit (`git -C benchmark checkout 33f6f84b10080888d98eed535dda8313a914d161`) and stage the updated gitlink (`git add benchmark`); do not edit anything under `benchmark/`.
   → coder verify (auto): `grep -n 'BENCH_COMMIT=' env.sh` shows the new SHA; `git -C benchmark rev-parse HEAD` equals it; `git -C benchmark status --short` is empty; `git status --short` shows the gitlink staged (`M  benchmark`); `git -C benchmark log -1 --format=%s` is "Make enable_riscv64_cheri own its target triple on every build path"; the remote check `curl -sS https://api.github.com/repos/comparch-security/cpu-sec-bench/commits/33f6f84…` returns HTTP 200 and a JSON `sha` equal to the pin (the 422 body echoes the SHA — parse, do not substring-match)
   → coder verify (scripted): the step2 verifier's check A — pin is 40-hex, equals the checkout HEAD, the checkout is clean, the pinned bench `Makefile` carries the cheri `ASMFLAGS` line, and the public remote reports the pin
2. **Step 2:** Remove the workaround surface (see the Summary table): in `derive_registry.py`, delete the `"*"` row, `SKIP_REASON`, the two-program contents of `EXPECTED_FAILURES` (keep `EXPECTED_FAILURES = []`), and the dead `"*"` fallback in `skip_reason()`; update the docstring (145 units on riscv64, fewer only where a lane row removes programs) and the comment references. Drop `disable_independent_assembly=yes` from the six build sites; drop `--bring-up` from the two CHERI prepare invocations **and delete their now-stale five-line `--bring-up` comment blocks**; keep the capability in `build_corpus.sh`. Add the `riscv64/build_image.sh`-style EXIT cleanup trap (`make -C benchmark clean`, assert `git status --short` empty, re-exit the original rc) to both CHERI prepares, and update the now-false comments that say the bench flag blocks add `-march`/`-mabi` "but NOT the triple" (the pin's block now carries it) plus `build_image.sh`'s "143 staged units" header.
   → coder verify (auto): `grep -rn 'disable_independent_assembly' scripts/` returns zero non-comment hits; `grep -n '^\s*[^#].*bring-up' scripts/cheri_riscv64/prepare.sh scripts/morello/prepare.sh` returns zero (non-comment); both prepares carry `trap cleanup EXIT`; the aarch64 MAKEFLAGS strings match verbatim
   → coder verify (scripted): the step2 verifier's checks B–D — workaround surface gone, per-lane rows intact, derived shape `145/143/144` with skips `0/2/1` and empty `expected_failures`, aarch64 MAKEFLAGS identical
3. **Step 3 (planner-hosted):** Acceptance re-runs, strictly one lane at a time, via a detached harness (`./tmp/verification/2026-10-18-drop-indepassembly-workarounds-lanes.sh`) launched through the C1 PATH-fixing driver (`2026-10-14-cheri-lanes-bringup-host-run.sh`) and logging to `./tmp/logs/2026-10-18-drop-indepassembly-workarounds-lanes.log`. The harness maps seven explicit vectors — `(ARCH=riscv64)`, `(ARCH=aarch64)`, `(ARCH=aarch64, enable_aarch64_pa=yes)`, `(ARCH=aarch64, enable_aarch64_bti=yes)`, `(ARCH=aarch64, enable_aarch64_mte=yes)`, `(ARCH=cheri_riscv64)`, `(ARCH=aarch64-morello)` — to `make … deploy` + `run`, and records each vector's expected stamp directory (`results/{riscv64,aarch64,aarch64-pa,aarch64-bti,aarch64-mte,cheri_riscv64,aarch64-morello}/`) plus the actual stamp path and `git -C benchmark rev-parse HEAD` before and after every deploy. A lane with no stamp (deploy abort or run timeout 124) is recorded as a named lane failure with its log tail; a 124 may be retried once with the same configuration (recorded), a deploy abort is never retried. Classify each lane: the two asmfunc records executed (never `1025`); not-run counts as pinned in the Summary; strict corpora complete; submodule clean. A verdict outside `{0} ∪ expect-results` is recorded as a handoff row for the bench sweep (deferral `indepassembly-return-site-untranslated` stays Fix Planned until this step's evidence exists).
   → Evidence: the run log carries each vector's deploy/run exit codes, run-time `rev-parse HEAD`, and stamp paths; seven new stamps exist, each with 246 records; `git -C benchmark status --short` empty after the last run
4. **Step 4 (tester):** Re-baseline the named machine-local verifiers (see Guidance for Tester; delete the stale `build/verify-step2/` cache first), write and run the acceptance script over the seven stamps named by the Step 3 log, re-point the classification artifact, and write the handoff list for the bench sweep.
   → tester verify: the acceptance script's structural gate passes on all seven named stamps, and every out-of-`expect-results` verdict is in the handoff table; the updated step1/2/3/4 verifiers, the C1 scripts verifier, classify.sh and lanes.sh are green with the recorded diffs; the tester report carries the seven-lane table and the handoff list
5. **Step 5 (planner):** Update `./README.md` (see Guidance for Planner), set the Issue Log row to **Resolved** with Step 3/4's evidence (planner-owned; never before that evidence exists), then retire `./tmp/reports/defer-issue-indepassembly-return-site-untranslated.json` via `/update-and-commit` Step 9.6.
   → Evidence: README diff exists (line 17, the Pins-table bench row, the Known-caveats bullets); the deferral file is absent after commit

## Guidance for Planner

Documentation tasks you will execute yourself (not the coder):

- **Files to modify:**
  - `./README.md`
- **When:** after Step 4's acceptance (before final revision).
- **What to sync:**
  - line 17 (lane-list CHERI bullet): "Two bring-up workarounds are in force" → no bring-up workarounds are in force; both CHERI lanes run the strict corpus (keep the Known-caveats pointer).
  - the `## Pins` table's bench-commit row (`c2c703979ae3…`) → `33f6f84b10080888d98eed535dda8313a914d161`.
  - the Known-caveats riscv64 bullet: the two asmfunc records are no longer skipped (**246 run, 0 skipped**), and the sentence "On the host-run lanes the same two records are recorded as build failures" is false — they now build and execute on plain aarch64 and all three variants.
  - the Known-caveats CHERI bullet: `disable_independent_assembly=yes` and `--bring-up` gone; strict acceptance with the `indepassembly` corpus in place; the bench-side successor sweep still owns the CHERI-semantics verdict decisions. Note that plain aarch64 and its three variants were re-accepted.
  - the Usage/timeout notes stay as they are.
- **Deferral retirement:** `./tmp/reports/defer-issue-indepassembly-return-site-untranslated.json` — Step 9.6 on row resolution.
- **Handoff:** record the asmfunc verdicts (and any other deviations) in `## Final Results` so the bench sweep can pick them up without re-reading lane stamps.
- **Hosting script:** `./tmp/verification/2026-10-18-drop-indepassembly-workarounds-lanes.sh` (Step 3; planner-authored, detached, one lane at a time, through the C1 host-run driver, logs to `./tmp/logs/`).
- **Out-of-repo documentation follow-up (tracked):** after Step 1, update `/home/wsong83/proj/xiangshan/CLAUDE.md`'s directory-map row `benchmark @ c2c7039` → `benchmark @ 33f6f84` in the same planner session as Step 5. It is outside this repo, so it is not in `doc_files`; it is listed here so the drift is owned and timed.

## History

| Date | Event | Conclusion | Dismissed |
|------|-------|------------|-----------|
| 2026-10-18 | Initial plan | Pin bump + workaround removal + non-x86 acceptance, drafted after the bench translation pushed (`origin/master` = `db84315`). | — |
| 2026-10-18 | Spec revision (pre-audit) | Added the bench prerequisite `2026-10-18-cheri-asmflags` (cheri assembler target flags; pin is that commit, not `db84315`); added the missing submodule-checkout step; retargeted the tester re-baselines to the all-archs step1/3/4 verifiers and the C1 scripts/classify artifacts; extended acceptance to the three aarch64 variants; reordered to coder → coder → planner-hosted runs → tester → planner. | — |
| 2026-10-18 | Bench prerequisite completed | Bench plan `2026-10-18-cheri-asmflags` COMPLETED: commit `33f6f84b10080888d98eed535dda8313a914d161` (Makefile + porting.html + archived plan), verifier green, full suite byte-identical to the native reference. Submodule working tree at it, clean; **pushed to `origin/master`** (verified via `api.github.com`: HTTP 200, master tip = the pin). | — |
| 2026-10-18 | Review | Verdict "Issues found — non-blocking" (0 Critical, 0 Warning, 1 Suggestion). The README suggestion was fixed (the riscv64 caveat now names all four outside-expectation verdicts); the five hunches are recorded in Dismissed. Report: [2026-10-18-drop-indepassembly-workarounds-review-2026-10-18.json](./tmp/reports/2026-10-18-drop-indepassembly-workarounds-review-2026-10-18.json). | [reviewer-suggestion-readme-deviation-count](./tmp/reports/2026-10-18-drop-indepassembly-workarounds-review-2026-10-18.json) (fixed), [reviewer-hunch-morello-header](./tmp/reports/2026-10-18-drop-indepassembly-workarounds-review-2026-10-18.json), [reviewer-hunch-trap-failure-branches](./tmp/reports/2026-10-18-drop-indepassembly-workarounds-review-2026-10-18.json), [reviewer-hunch-bringup-mode-not-rerun](./tmp/reports/2026-10-18-drop-indepassembly-workarounds-review-2026-10-18.json), [reviewer-hunch-trap-rc-override](./tmp/reports/2026-10-18-drop-indepassembly-workarounds-review-2026-10-18.json), [reviewer-hunch-classification-pointer](./tmp/reports/2026-10-18-drop-indepassembly-workarounds-review-2026-10-18.json) |
| 2026-10-18 | Spec revision (/update-plan) | Tester round 1 SUCCESS (10/10): the seven-lane acceptance verified the structural gate and recorded 29 handoff rows; every named verifier was re-baselined and is green; `indepassembly-return-site-untranslated` set Resolved on the Step 3/4 evidence; README and the workspace `CLAUDE.md` pin updated; counters 1/0/0 (below the post-implementation audit trigger). Report: [tester](./tmp/reports/2026-10-18-drop-indepassembly-workarounds-tester-2026-10-18.json). | — |
| 2026-10-18 | Step 3 acceptance run (planner-hosted) | Seven lanes deployed and ran sequentially, all rc=0, each with a stamp (`results/{aarch64,aarch64-pa,aarch64-bti,aarch64-mte,riscv64,cheri_riscv64,aarch64-morello}/20261018T*`); the submodule was at the pin and clean before/after every deploy. Both asmfunc records executed on every lane: 0 on riscv64 and all four aarch64 lanes, 290 on cheri_riscv64 and aarch64-morello (the registry's declared "cheri capabilities enabled" code). Strict corpora: 145/143/144 units, all built, `expected_failures` `[]`; not-run counts `0/0` ×5, `2/0`, `1/0`. One new deviation: riscv64 `acc-read-func` 0 → 1 — the bench's `get_riscv64_func_inst.sh` matches the translated `assembly_helper` with its `grep helper`, yielding an empty opcode side file (cross-repo deferral [func-opcode-gen-helper-symbol-match](./tmp/reports/defer-issue-func-opcode-gen-helper-symbol-match.json) filed). Every other deviation is unchanged from the pre-change baselines (riscv64 267/255/1; the CHERI run-6 set; the Morello run-6 bucket-(c) set). | — |
| 2026-10-18 | Mega-audit (pre-implementation) | 6 High, 24 Medium, 22 Low — all High+Medium fixed: variant invocations corrected to `ARCH=aarch64 enable_aarch64_<v>=yes`; Step 1 gains the remote-provenance gate (HTTP-200 + parsed `sha`, not substring — the 422 body echoes the SHA); the `.py` re-baseline targets gained their line-level edits (INDEPASSEMBLY_PROGRAMS exclusions, the second `c2c7039` literal, message strings); the C1 `lanes.sh` verifier joins the re-baseline; the acceptance gate gains the pass-with-handoff branch and no-stamp outcomes; the CHERI prepares gain the EXIT cleanup trap; prepare comment blocks and stale "no triple" comments updated; README sync scope expanded (line 17, Pins table, host-lane sentence); metadata aligned (`verification_scripts` = the eight `.py` paths, `tester_files` = the create/retire union; the verifier's `"*"`/`SKIP_REASON` scans now use `code_only`). Every Low is folded into those fixes or fixed directly (grep wording, stale header count, rollback row, Issue-Log resolution owner); one Low is dispositioned out of scope. Report: [./tmp/reports/2026-10-18-drop-indepassembly-workarounds-mega-audit-2026-10-18.json](./tmp/reports/2026-10-18-drop-indepassembly-workarounds-mega-audit-2026-10-18.json). | `ma-low-48` — the durable per-lane pin assertion is left to the open deferral `submodule-pin-unverified`; this plan performs the one-time checkout and gates on remote provenance (see Out of scope). [Report](./tmp/reports/2026-10-18-drop-indepassembly-workarounds-mega-audit-2026-10-18.json). |

## Plan Metadata

```json
{
  "plan_id": "2026-10-18-drop-indepassembly-workarounds",
  "steps": ["Step 1: Pin the bench at the 2026-10-18-cheri-asmflags commit and check out the submodule", "Step 2: Remove the skip row and the disable_independent_assembly injections", "Step 3: Planner-hosted acceptance runs for the seven non-x86 lanes", "Step 4: Re-baseline the verifiers, acceptance and classification (tester)", "Step 5: Sync README and retire the deferral (planner)"],
  "coder_files": ["./env.sh", "./scripts/common/derive_registry.py", "./scripts/common/build_corpus.sh", "./scripts/riscv64/build_image.sh", "./scripts/cheri_riscv64/prepare.sh", "./scripts/morello/prepare.sh", "./scripts/aarch64/prepare.sh", "./scripts/aarch64/run.sh"],
  "tester_files": ["./tmp/verification/2026-10-18-drop-indepassembly-workarounds-acceptance.sh", "./tmp/verification/2026-10-12-test-env-all-archs-step5.py", "./tmp/verification/2026-10-14-cheri-lanes-bringup-derive-regression.py"],
  "doc_files": ["./README.md"],
  "verification_scripts": ["./tmp/verification/2026-10-18-drop-indepassembly-workarounds-step2.py", "./tmp/verification/2026-10-12-test-env-all-archs-step1.py", "./tmp/verification/2026-10-12-test-env-all-archs-step2.py", "./tmp/verification/2026-10-12-test-env-all-archs-step3.py", "./tmp/verification/2026-10-12-test-env-all-archs-step4.py", "./tmp/verification/2026-10-12-test-env-all-archs-step5.py", "./tmp/verification/2026-10-14-cheri-lanes-bringup-scripts.py", "./tmp/verification/2026-10-14-cheri-lanes-bringup-derive-regression.py"],
  "repo_mode": "Public",
  "document_overrides": []
}
```

## Audit Accumulation

| Counter | Value | Last Updated |
|---------|-------|--------------|
| issues_resolved_since_audit | 1 | 2026-10-18 |
| steps_changed_since_audit | 0 | 2026-10-18 |
| files_changed_since_audit | 0 | 2026-10-18 |

## Documentation

Documentation owned by the planner: `./README.md` (line 17 CHERI bullet, Pins table, Known-caveats bullets — see Guidance for Planner). The workspace-level `/home/wsong83/proj/xiangshan/CLAUDE.md` pin row is a tracked follow-up outside this repo (same planner session as Step 5). `env.sh` is self-documented; the bench submodule is untouched apart from the pin's checkout.

## Final Results

**Status:** COMPLETED
**Completed:** 2026-10-18

### What was implemented

- `./env.sh` — `BENCH_COMMIT` bumped to `33f6f84b10080888d98eed535dda8313a914d161`; the submodule checked out at it and the gitlink staged.
- `./scripts/common/derive_registry.py` — the `"*"` skip row, `SKIP_REASON`, the two-program `EXPECTED_FAILURES` contents and the dead `"*"` fallback in `skip_reason()` removed; `EXPECTED_FAILURES = []` retained for the manifest key; docstring re-worded (145 units on riscv64; lane rows are platform build failures).
- `./scripts/common/build_corpus.sh`, `./scripts/riscv64/build_image.sh`, `./scripts/cheri_riscv64/prepare.sh`, `./scripts/morello/prepare.sh`, `./scripts/aarch64/prepare.sh`, `./scripts/aarch64/run.sh` — `disable_independent_assembly=yes` removed from all six build sites (the two aarch64 MAKEFLAGS strings stay identical).
- `./scripts/cheri_riscv64/prepare.sh`, `./scripts/morello/prepare.sh` — `--bring-up` dropped from the corpus invocations (capability retained in `build_corpus.sh`), stale comment blocks removed, the `riscv64/build_image.sh`-style EXIT cleanup trap added (clean + dirty assert + original rc).
- Stale comments corrected (`build_image.sh` header 145 units; the "but NOT the triple" notes now describe the pinned flag blocks correctly).
- `./README.md` — lane bullet, the Pins-table bench row (`33f6f84…`), and both Known-caveats bullets (riscv64: all 246 records run, four handoff verdicts; CHERI: strict corpus, per-lane platform skips only). Workspace `/home/wsong83/proj/xiangshan/CLAUDE.md` directory-map pin row updated to `benchmark @ 33f6f84`.

### Verification

- **Coder round 1** (2026-10-18): `build_result: pass`. Steps 1–2 auto checks green; the plan-authored verifier passed (`PASS step1-2`: pin checked out and clean, cheri ASMFLAGS present, workaround surface gone, derived shape 145/143/144 with skips 0/2/1).
- **Step 3 acceptance run (planner-hosted)** (2026-10-18): seven lanes, one at a time, all deploy/run rc=0, submodule at the pin and clean before/after every deploy. Stamps: `aarch64` 20261018T071013Z, `aarch64-pa` 20261018T071246Z, `aarch64-bti` 20261018T071514Z, `aarch64-mte` 20261018T071726Z, `riscv64` 20261018T072802Z, `cheri_riscv64` 20261018T073415Z, `aarch64-morello` 20261018T080148Z. Both asmfunc records executed on every lane (0/0 on riscv64 and the four aarch64 lanes; 290/290 on cheri_riscv64; 0/290 on aarch64-morello — the registry's declared "cheri capabilities enabled" code). Strict corpora 145/143/144 units, all built, `expected_failures` `[]`; not-run counts 0/0 ×5, 2/0, 1/0.
- **Tester round 1** (2026-10-18): `overall_result: SUCCESS` (10/10). The new acceptance gate verified the seven named stamps (structural gate + pass-with-handoff verdicts; red-path proven on a missing stamp); the re-baselined step1/2/3/4, C1 scripts (116/116), classify, lanes (50/50) verifiers are green; the coder verifier and C1 wiring (32/32) re-ran green; 29 handoff rows recorded in `./tmp/verification/2026-10-18-drop-indepassembly-workarounds-handoff.json` and `…-classification.json`.
- **Reviewer** (2026-10-18, sonnet): "Issues found — non-blocking"; 0 Critical, 0 Warning, 1 Suggestion (README deviation count — fixed), 5 hunches (recorded in History). All nine staged paths read in full; the plan's verifier and two C1 verifiers re-run independently. Doc-structure gate: no docs to audit (repo has no tracked `CLAUDE.md`).

### Issues

- **Resolved:** `indepassembly-return-site-untranslated` — the bench translation is pinned and both asmfunc records execute on all seven lanes; the deferral report is retired at commit (`/update-and-commit` Step 9.6).
- **Deferred (cross-repo, open):** `func-opcode-gen-helper-symbol-match` — the bench's `get_*_func_inst.sh` extracts `func_addr` with an unanchored `grep helper`, which now also matches the translated `assembly_helper` symbol; the opcode side file is a lone newline and riscv64's `acc-read-func` exits 1 (was 0 on the 2026-10-13 stamps). Root cause commit `db843151e3187e2c136ecbdf4befc0794f1cea78`; fix (anchor the symbol match, strengthen the side-file regression) belongs to the bench sweep. Report: [defer-issue-func-opcode-gen-helper-symbol-match](./tmp/reports/defer-issue-func-opcode-gen-helper-symbol-match.json).
- **Handoff rows (not skips):** riscv64 4 verdicts (the new `acc-read-func` plus the pre-existing 267/255/1 from `review-lines-bench-expectation-gaps`); `cheri_riscv64` 5 (pre-existing, unchanged from run 6); `aarch64-morello` 20 (the pre-existing run-6 bucket-(c) set, unchanged).

### Known caveats

- The `cheri_riscv64` and `aarch64-morello` lanes depend on the same opcode extraction; their `acc-read-func` records return 290 via the capability-mode early exit, so the empty side file is masked there. The bench fix should also add a non-whitespace content check — the current all-archs verifier only asserts `st_size > 0`.
- The aarch64 run logs record the same `objdump --start-address: bad number` error yet still return 0 for `acc-read-func`; the mechanism is unexplained and is noted in the cross-repo deferral.
- The new CHERI prepare EXIT traps are verified structurally; their failure branches were not executed. The dirty-assert `rc=1` override mirrors `build_image.sh` and can mask a 124/143 classification in that corner (reviewer hunch, pre-existing pattern).
- The retained `--bring-up` capability's behavioural harness was not re-run (its synthetic paths do not touch the removed knob).
- `scripts/morello/prepare.sh`'s header note about the triple applies to the unit-compile flags, not `SCHEDULER_CXXFLAGS`; the explicit guest-scheduler `--target` stays load-bearing (reviewer hunch, pre-existing text).
- The 124-no-publish exercise overwrites `build/<lane>/console.log`; the accepted Step 3 consoles were preserved under `tmp/logs/2026-10-18-drop-indepassembly-workarounds-{cheri_riscv64,aarch64-morello}-console.log`.

### Cross-References to Prior Plans

| Prior Plan | Deferred Issue | Resolution |
|------------|---------------|------------|
| 2026-10-12-test-env-all-archs | `indepassembly-return-site-untranslated` | Translation pinned at `33f6f84`; both asmfunc records execute on all seven lanes (0/0 non-CHERI, 290/290 CHERI); derived skips are lane rows only (0/2/1). |
