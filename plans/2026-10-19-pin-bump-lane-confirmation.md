# Plan: Pin-bump lane confirmation — move BENCH_COMMIT to c8c6000 and re-run all seven lanes for the sweep's real-lane evidence
**Project:** /home/wsong83/proj/xiangshan/cpu-sec-test-env
**Plan ID:** 2026-10-19-pin-bump-lane-confirmation
**Created:** 2026-10-19

## Issue Log

Rows ordered newest-first.

| Issue | Status | Found | Resolved | Resolved By |
|-------|--------|-------|----------|-------------|
| [aarch64-func-opcode-extraction-host-objdump](./tmp/reports/defer-issue-aarch64-func-opcode-extraction-host-objdump.json) — cross-repo (bench) + env residual: at pin `c8c6000` the four aarch64 lanes' `acc-read-func` extraction ran with an aarch64-incapable objdump (the host `/usr/bin/objdump` signature, reproduced verbatim); the sweep's hard no-opcode error turned it into a unit build failure (`result 1025`; was a genuine `0` at `33f6f84`); the per-lane shim is correct on disk today — why it did not take effect for these runs is the open env question. | Open | 2026-10-19 | — | — |
| [cheri-riscv64-opcode-extraction-deploy-abort](./tmp/reports/defer-issue-cheri-riscv64-opcode-extraction-deploy-abort.json) — cross-repo (bench): at pin `c8c6000` the `cheri_riscv64` corpus build aborts — `acc-read-func.gen`'s opcode side file is extracted by the x64 fallback extractor (no `cheri_riscv64` branch in Makefile:237-241) and hard-fails on the xcheri binary; reproduced in-sandbox and out-of-sandbox; no `cheri_riscv64` stamp can exist at this pin. | Open | 2026-10-19 | — | — |
| [pycache-not-ignored](./tmp/reports/defer-issue-pycache-not-ignored.json) | Open | 2026-10-19 | — | — |
| Pending real-lane confirmations from the sweep chain (bench `c8c6000`): `acc-read-func` → 0 on riscv64/aarch64; the declared `290` SIGPROT records and `mss-write-by-stack-pointer`'s `1` observed within `expect-results`; the remaining handoff set exactly the known-undeclared classes — no report file (this plan is their confirmation vehicle) | Resolved | 2026-10-19 | 2026-10-19 | this plan — Step 2 stamps + the result analysis (riscv64 confirmed; the aarch64 `acc-read-func` part is deferred to the aarch64-func-opcode-extraction-host-objdump row) |

## Guidance for Coder

**Files to modify:**

- `./env.sh`

**Do NOT:** edit any file under `benchmark/` (the submodule is checked out read-only at the pin); change any lane script (this cycle re-runs the existing machinery unchanged); reintroduce any `disable_independent_assembly` / skip workaround; touch `README.md` (planner-owned).

**Step-by-step with verification:** `(auto)` checks are mechanical commands whose output is the check. Step 1 is coder-owned; Step 2 is planner-hosted; Steps 3 and 4 are tester- and planner-owned.

## Guidance for Tester

**Tests to create (re-pointing the drop cycle's scripts to the new stamps and expectations):**

- **Temporary:** `./tmp/verification/2026-10-19-pin-bump-lane-confirmation-acceptance.sh` — per-lane structural gate over the Step 2 stamp map (`./tmp/logs/2026-10-19-pin-bump-lane-confirmation-stamps.tsv`, never "latest by mtime"): each stamp carries 246 records; both asmfunc records executed (never `1025`); not-run counts exactly `0/0` (riscv64, aarch64, aarch64-pa, aarch64-bti, aarch64-mte), `2/0` (cheri_riscv64), `1/0` (aarch64-morello); `git -C benchmark status --short` empty; `versions.txt` names the pin `c8c6000…`.
- **Verdict checks (pass-with-handoff):** `acc-read-func` = 0 on riscv64 and the four aarch64 lanes; the six SIGPROT records' codes within `expect-results` on the CHERI/Morello lanes; `mss-write-by-stack-pointer` = 1 within `expect-results` on riscv64 and CHERI lanes. Everything else outside `{0} ∪ expect-results` must fall in exactly the known-undeclared classes — riscv64 `{255, 267}` and the CHERI/Morello generic-code rows (codes 1/2/3/4/255; recompute the exact set from the run) — and is recorded as a handoff row; anything outside those classes is an investigation item, not a gate pass.
- **Temporary:** `./tmp/verification/2026-10-19-pin-bump-lane-confirmation-classify.py` — the drop cycle's classification, re-pointed: reads the seven new stamps against the derived registry, emits the per-lane handoff table plus the passed/expected-nonzero/skip counts, and asserts the declared records' membership. Keep both script revisions red-provable (run once against the pre-bump stamps it must fail on).
- **Tests to update:** `./tmp/verification/2026-10-18-drop-indepassembly-workarounds-*` — re-point stamps and the handoff expectation (the declared set shrinks the handoff list); the structural verifiers (step2/3/4, C1 wiring/scripts) need **no count change** — units 145/143/144 and skips 0/2/1 are untouched by the sweep; re-run them as regressions.

**Tests to investigate for retirement:** No test obsolescence identified.

**Boundary to state in the tester report:** the `continue` fix and `check_catalog.py` hardening are host-run/native surfaces (the in-guest lanes run `no-make exhausted-run`); their verification stays the sweep's native evidence — this cycle confirms the *lane-visible* effects only (extraction, registry declarations, `.asm` sizes in the corpus build).

## Summary

**Problem.** Every plan since B1 has closed with the same caveat: "real-lane confirmation is the env successor's pin-bump re-run." The bench is now at pushed `c8c600066f4a1d0845d893bbfa24e46445e59b2b` (the sweep: continue fix, warning cleanup, catalog hardening, extraction fix, five `.asm` `.size` directives, seven-record registry diff), while the env pins `33f6f84` — the sweep's lane-visible changes have never executed on any lane. The env working tree already shows the preparatory drift (` M benchmark`: the submodule is checked out at `c8c6000` on `master`; the recorded gitlink is `33f6f84`).

**Approach.** One-line pin bump, then re-run the existing seven-lane machinery (deploy rebuilds the corpora at the new pin; run collects stamps), then a tester acceptance/classification pass that turns each deferred confirmation into observed evidence: the extraction fix's real-lane proof (`acc-read-func` 0 on riscv64/aarch64), the declared codes observed within `expect-results`, and an exact accounting of the remaining handoff rows (the undeclared classes the return-code-delivery plan owns). No script changes: this cycle's value is that nothing but the pin changed.

**Expected results (the tester asserts exact, not approximate):** asmfunc executed everywhere; not-run counts `0/0 ×5, 2/0, 1/0` (unchanged — the CHERI rows are recorded platform build failures, not this workstream's); `acc-read-func` 0 on the five non-CHERI lanes (290 on CHERI/Morello, declared); SIGPROT records within `expect-results`; handoffs reduced to riscv64 `{255, 267}` + the CHERI/Morello generic-code rows (the sweep declared 290 on the six SIGPROT records and 1 on `mss-write-by-stack-pointer`, and left 255/267/14-generic undeclared by explicit decision).

**Out of scope:** the return-code-delivery plan (bench; owns 255 + the generic-code rows + the ~20 `gvar`-as-exit-status cases) and the `argv-conv-bounds` fix; C2/C3 (env deferrals); the workspace-level `CLAUDE.md` refresh.

## Repo Mode

Public

## Document Overrides

| Document | Rule Overridden | Reason |
|----------|----------------|--------|

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| A lane run surfaces a deviation outside the known-undeclared classes | an unclassified result | recorded as an investigation item with its raw evidence; classified before any claim of green; a genuine defect becomes a deferral — never a workaround |
| The sweep's registry diff changes the derived registry's shape | stale verifier expectations | Step 3 re-points the classification scripts; the structural verifiers are re-run as regressions and must stay green (units/skips unchanged) |
| CHERI corpora rebuild at the new pin hits the previously-noted aarch64 extraction anomaly ("bad number yet exit 0") | unexplained log noise | the sweep's fix may resolve it — record either way; if it persists, note it as an observation for the return-code plan, not a blocker |
| Lane time (seven lanes ≈ 50–60 min) inside a round cap | round pressure | planner-hosted runs per precedent; tester verifies published stamps rather than re-running |

## Proposed Changes

1. **Step 1:** In `env.sh`, bump `BENCH_COMMIT` from `33f6f84b10080888d98eed535dda8313a914d161` to `c8c600066f4a1d0845d893bbfa24e46445e59b2b` and update the accompanying comment (the sweep pin: extraction fix + declared codes; the gitlink is already checked out and will be staged by `/update-and-commit`).
   → coder verify (auto): `grep -n 'BENCH_COMMIT=' env.sh` shows the new SHA; `git -C benchmark rev-parse HEAD` equals it; `git diff env.sh` touches only the pin line and its comment
2. **Step 2:** Re-run the seven lanes (planner-hosted): `make ARCH=<lane> deploy` then `run` for `riscv64`, `aarch64`, `aarch64-pa`, `aarch64-bti`, `aarch64-mte`, `cheri_riscv64`, `aarch64-morello`; write the lane→stamp map to `./tmp/logs/2026-10-19-pin-bump-lane-confirmation-stamps.tsv`; each lane's run must leave the submodule clean.
   → Evidence: seven rc=0 run logs; the stamp map; `git -C benchmark status --short` empty after each lane
3. **Step 3:** Acceptance + classification over the seven stamps (tester; see Guidance for Tester).
   → tester verify: the acceptance script passes with the exact expected set; the classification table accounts for every non-conforming verdict in the known classes; declared records verified within `expect-results`; report states the boundary (native/host surfaces remain the sweep's evidence)
4. **Step 4:** Docs + commit (planner): update `./README.md`'s bench-commit pin row (`33f6f84…` → `c8c6000…`) and any caveat text that now reads stale; then `/update-and-commit` stages the pin + gitlink + README and commits.
   → Evidence: README diff exists; the commit carries the new gitlink and no other source change

## Guidance for Planner

Documentation tasks you will execute yourself (not the coder):

- **Files to modify:**
  - `./README.md`
- **When:** after Step 3 (before final revision).
- **What to sync:** the Pins-table bench-commit row (line 141) to `c8c600066f4a1d0845d893bbfa24e46445e59b2b`; the Known-caveats text where it promises pending confirmation (now confirmed); keep the one-sentence handoff that the return-code-delivery plan still owns 255 + the CHERI/Morello generic-code rows.
- **Deferral retirement:** none — this plan resolves no report file; its Issue Log row (in-plan) closes on Step 3's evidence.
- **Handoff:** record the per-lane confirmation table (acc-read-func values, declared-code observations, the exact remaining handoff set) in `## Final Results` so the return-code plan starts from it.

## History

| Date | Event | Conclusion | Dismissed |
|------|-------|------------|-----------|
| 2026-10-19 | Initial plan | Pin-bump confirmation cycle for the pushed sweep commit, drafted as the direct successor of the sweep (real-lane evidence for the extraction fix and the declared codes). | — |
| 2026-10-19 | Implementation round (coder) — failed round; retry used (1) | Round 1 died 35 s in on a transient upstream `API Error: 400 Upstream request failed` after three check-git-root tool calls; no report, no tree change (assessed: `env.sh` still pins `33f6f84`); relaunched once with the same brief. | — |
| 2026-10-19 | Step 2 acceptance run, attempt 1 (in-session) — aborted | The session's sandbox (bwrap/srt) hides `/proc/sys/fs/binfmt_misc`, so the four aarch64 deploys refused (rc=2, `binfmt handler … absent`); independently, `cheri_riscv64` aborted in the corpus build — the sweep's hardened `get_x64_func_inst.sh` runs for `acc-read-func.gen` on the CHERI lane (it matches neither the aarch64 nor the riscv64 extractor branch, so the x64 default is used) and hard-fails on the xcheri binary (`extracted no opcode bytes`; `objdump: x ISA extension 'xcheri' must be set with the versions`) — bench-side, not sandbox-caused (the old pin's CHERI deploys never invoked an extractor; the bench Makefile rule is unchanged at both pins). `riscv64` + `aarch64-morello` produced valid stamps (rc=0, 246 records, `run-test-exit 0`, pin recorded in `versions.txt`); map `./tmp/logs/2026-10-19-pin-bump-lane-confirmation-stamps.tsv`; full log preserved at [./tmp/verification/2026-10-19-pin-bump-lane-confirmation-aborted-run-sandbox.log](./tmp/verification/2026-10-19-pin-bump-lane-confirmation-aborted-run-sandbox.log). Out-of-sandbox re-run of the seven vectors follows (hosted by the user). | — |
| 2026-10-19 | Spec revision (/update-plan) | Coder round 2 (the retry) SUCCESS: Step 1 landed — `env.sh` pins `c8c6000`, comment updated, all auto checks green (`git diff env.sh` touches only the pin + comment; submodule clean), `build_result: pass` — report [./tmp/reports/2026-10-19-pin-bump-lane-confirmation-coder-2026-10-19.json](./tmp/reports/2026-10-19-pin-bump-lane-confirmation-coder-2026-10-19.json). The round's one finding (pre-existing `__pycache__` not ignored) deferred as [pycache-not-ignored](./tmp/reports/defer-issue-pycache-not-ignored.json) and added to the Issue Log. No step or Guidance text changed (non-substantive revision): Immediate Actions removed as stale; counters stay 0/0/0. | — |
| 2026-10-19 | Step 2 acceptance run, attempt 2 (out-of-sandbox, user-hosted) — complete | Six stamps at the pin — `aarch64` `20261018T225309Z`, `aarch64-pa` `20261018T225559Z`, `aarch64-bti` `20261018T225812Z`, `aarch64-mte` `20261018T230026Z`, `riscv64` `20261018T231030Z`, `aarch64-morello` `20261018T232205Z` — each 246 records, `versions.txt` records the pin, submodule clean, every HEAD reading at the pin; one named failure: `cheri_riscv64` deploy rc=2 (the bench extraction abort; deferral [cheri-riscv64-opcode-extraction-deploy-abort](./tmp/reports/defer-issue-cheri-riscv64-opcode-extraction-deploy-abort.json)). Two findings: (B) the CHERI abort above; (A) **`acc-read-func` = 1025 (not-run) on all four aarch64 lanes** (0 at the old pin) — the run-time extraction's bare `objdump` resolved to a host disassembler that cannot disassemble aarch64 (`can't disassemble for architecture UNKNOWN!`) even though the env's bare-`objdump` shim exists and is correct now (`shim.sh`'s stated purpose), and the sweep's new hard "no opcode bytes" error turns it into a unit-build failure (evidence: `aarch64-run.log` block at lines 658-671 vs the error-free old-pin block at 690-699; extractor diff `33f6f84..c8c6000`). riscv64 clean (`acc-read-func` 0, `mss-write-by-stack-pointer` 1, not-run 0/0); `aarch64-morello` as declared (290, 1, not-run 1/0). Map `./tmp/logs/2026-10-19-pin-bump-lane-confirmation-stamps.tsv`; logs under `./tmp/logs/2026-10-19-pin-bump-lane-confirmation-*`. Pending user sign-off: the Step 3 gate revision (six stamps + one named failure + Finding A recorded) and Finding A's disposition (both candidate owners open — bench extractor vs env shim effectiveness). | — |
| 2026-10-19 | Result analysis (user redirect — "no need to strictly follow the plan… analyze the results and report whether the results are reasonable… what is the defect") | Per-lane reasonableness verdicts and the defect statement recorded at [./tmp/reports/2026-10-19-pin-bump-lane-confirmation-result-analysis.md](./tmp/reports/2026-10-19-pin-bump-lane-confirmation-result-analysis.md). Every verdict conforms, is a declared platform code, or is in the known pre-existing undeclared set — except (1) the four aarch64 `acc-read-func` entries: a build failure (`1025` = could not be built; the extraction ran with the host objdump's exact signature; the old `0` was a genuine pass and the old extraction was already defective but masked) — env-side resolution newly surfaced by the sweep's hardening, deferred as [aarch64-func-opcode-extraction-host-objdump](./tmp/reports/defer-issue-aarch64-func-opcode-extraction-host-objdump.json); and (2) `cheri_riscv64`: the bench extractor selection (Makefile:237-241) has no CHERI branch, and the env's binary-substitution lever cannot supply the missing CHERI-capable invocation/flags. No test-case defect found; riscv64's only change is the sweep's fix working (`acc-read-func` 1→0); morello byte-identical. Findings A and B closed to the analysis; Steps 3/4 hold for user direction. | — |
| 2026-10-19 | Wrap-up (user directive: wrap up, `/update-and-commit` the useful changes, report every finding, hand back to the research) | Frozen with the two open bench-side defects deferred (the freeze-now option): README pin row + caveats synced to `c8c6000`, `## Final Results` populated with the per-lane confirmation table and the handoff set, this commit carries the pin + gitlink + README + archive. Step 3 stays superseded by the redirect (the result analysis is this cycle's acceptance evidence). Next move — fix the bench extraction path, then re-bump and re-run `cheri_riscv64` + the aarch64 lanes — left to the research. | — |

## Plan Metadata

```json
{
  "plan_id": "2026-10-19-pin-bump-lane-confirmation",
  "steps": ["Step 1: Bump BENCH_COMMIT to c8c6000", "Step 2: Re-run the seven lanes (planner-hosted)", "Step 3: Acceptance and classification over the new stamps (tester)", "Step 4: Sync README and commit (planner)"],
  "coder_files": ["./env.sh"],
  "tester_files": ["./tmp/verification/2026-10-19-pin-bump-lane-confirmation-acceptance.sh", "./tmp/verification/2026-10-19-pin-bump-lane-confirmation-classify.py"],
  "doc_files": ["./README.md"],
  "verification_scripts": [],
  "repo_mode": "Public",
  "document_overrides": []
}
```

## Audit Accumulation

| Counter | Value | Last Updated |
|---------|-------|--------------|
| issues_resolved_since_audit | 0 | 2026-10-19 |
| steps_changed_since_audit | 0 | 2026-10-19 |
| files_changed_since_audit | 0 | 2026-10-19 |

## Documentation

Documentation owned by the planner: `./README.md` (pin row + caveats — see Guidance for Planner). No other doc surface changes.

## Final Results

**Status:** COMPLETED — the pin bump is recorded with its per-lane evidence; the two bench-side defects the confirmation surfaced are open as deferrals (the plan's stated outcome for a genuine defect: a deferral, never a workaround).

**Step outcomes**

| Step | Outcome |
|------|---------|
| 1 — Bump `BENCH_COMMIT` to `c8c6000` | Done (coder round 2; `env.sh` pin + comment; report [./tmp/reports/2026-10-19-pin-bump-lane-confirmation-coder-2026-10-19.json](./tmp/reports/2026-10-19-pin-bump-lane-confirmation-coder-2026-10-19.json)) |
| 2 — Re-run the seven lanes | Done with one named failure: six stamps — `aarch64` `20261018T225309Z`, `aarch64-pa` `20261018T225559Z`, `aarch64-bti` `20261018T225812Z`, `aarch64-mte` `20261018T230026Z`, `riscv64` `20261018T231030Z`, `aarch64-morello` `20261018T232205Z` (map [./tmp/logs/2026-10-19-pin-bump-lane-confirmation-stamps.tsv](./tmp/logs/2026-10-19-pin-bump-lane-confirmation-stamps.tsv)); `cheri_riscv64` deploy rc=2 (the extraction abort) |
| 3 — Acceptance + classification (tester) | Superseded by the user's redirect ("analyze the results and report whether the results are reasonable… what is the defect"); replaced by the result analysis [./tmp/reports/2026-10-19-pin-bump-lane-confirmation-result-analysis.md](./tmp/reports/2026-10-19-pin-bump-lane-confirmation-result-analysis.md), which is this cycle's acceptance evidence |
| 4 — Docs + commit (planner) | Done: README pin row + caveats synced; `/update-and-commit` stages `env.sh` + the gitlink + README (+ this archive) |

**Per-lane confirmation table (the handoff)**

| Lane | `acc-read-func` | Declared codes observed | Outside `expect-results` |
|------|-----------------|-------------------------|--------------------------|
| riscv64 | **0** — the sweep's extraction fix lane-confirmed (was 1) | `mss-write-by-stack-pointer` 1 ✓ (newly declared by the sweep) | `{255, 267}` — handoff to the bench's return-code-delivery workstream |
| aarch64 ×4 | **not confirmed** — `1025` (build failure): the extraction ran with an aarch64-incapable objdump; deferred as `aarch64-func-opcode-extraction-host-objdump` | — | none — all other 245 verdicts conforming, unchanged from the old pin |
| aarch64-morello | 290 ✓ (declared) | the six SIGPROT 290 records ✓; `mss-write-by-stack-pointer` 1 ✓ | 13 generic codes `{1×4, 2×5, 3×1, 4×2, 255×1}` + `cfi-call-mid-func` (not-run, declared platform build failure) — handoff |
| cheri_riscv64 | — | — | cannot deploy at this pin; deferred as `cheri-riscv64-opcode-extraction-deploy-abort` |

**Findings (all recorded as machine-local deferrals; nothing retired)**

- `cheri-riscv64-opcode-extraction-deploy-abort` (bench) — the extractor selection has no CHERI variant; the x64 fallback script runs on an xcheri binary.
- `aarch64-func-opcode-extraction-host-objdump` (bench + env residual) — the extraction's bare `objdump` resolved to an aarch64-incapable binary on the four aarch64 lanes.
- `pycache-not-ignored` (env hygiene) — `scripts/cheri/__pycache__/` untracked; clear with `! rm -rf /home/wsong83/proj/xiangshan/cpu-sec-test-env/scripts/cheri/__pycache__`.
- Carried from earlier cycles, still open: `lane-script-hardening-batch`, `submodule-pin-unverified`.

**Known drift / next-move inputs for the research**

- **Bench fix (recommended first move):** route the opcode extraction through the bench's published `OBJDUMP` knob (`Makefile:543-554` + the three `get_*_func_inst.sh`) and give `cheri_riscv64` its extractor values; then bump once more and re-run `cheri_riscv64` + the four aarch64 lanes — the other five stamps stand. Design recorded in §5 of the result analysis.
- **Env companion:** make tool resolution auditable (echo the resolved `objdump --version` at lane start); the per-lane shim becomes belt-and-braces.
- **Workspace-level `CLAUDE.md` drift** (out of this repo, previously owned by the drop plan): `benchmark @ 33f6f84` → `c8c6000`; `cpu-sec-test-env @ f9a66c2` → current HEAD.