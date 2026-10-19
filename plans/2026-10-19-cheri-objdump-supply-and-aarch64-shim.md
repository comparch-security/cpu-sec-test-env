# Plan: Supply the CHERI-capable objdump to the cheri lane, fix the aarch64 shim's PATH entry, and re-run the five lanes at a bench pin carrying the extraction fix
**Project:** /home/wsong83/proj/xiangshan/cpu-sec-test-env
**Plan ID:** 2026-10-19-cheri-objdump-supply-and-aarch64-shim
**Created:** 2026-10-19

## Issue Log

Rows ordered newest-first: the coder-filed revision issue, then this plan's input, then the two sibling env-filed deferrals this cycle's re-runs confirm and retire.

| Issue | Status | Found | Resolved | Resolved By |
|-------|--------|-------|----------|-------------|
| [stale-step12-sh-verifier-reference](../reports/2026-10-19-cheri-objdump-supply-and-aarch64-shim-stale-step12-sh-verifier-reference.json) — the plan's Immediate Actions and Guidance for Coder still named the superseded `step12.sh`; both now name the `.py`. Plan-text defect only; no tree change implied. | Resolved | 2026-10-20 | 2026-10-20 | planner |
| [cheri-riscv64-needs-cheri-capable-objdump](../../benchmark/tmp/reports/defer-issue-cheri-riscv64-needs-cheri-capable-objdump.json) — cross-repo (filed in the `benchmark` submodule, `target_repo: cpu-sec-test-env`): the env must pass the CTSRD SDK's CHERI-capable objdump as `OBJDUMP` for the cheri lane (`scripts/common/build_corpus.sh` cheri case + `scripts/cheri_riscv64/prepare.sh:120`); until then the cheri corpus build stops loudly at the extraction. | Resolved | 2026-10-19 | 2026-10-20 | tester |
| [aarch64-func-opcode-extraction-host-objdump](../reports/defer-issue-aarch64-func-opcode-extraction-host-objdump.json) — cross-repo (bench) + env residual: the four aarch64 lanes' extraction ran with the host objdump. Env residual answered this cycle: `scripts/aarch64/run.sh` prepends a **repo-relative** shim dir to `PATH` and then runs the scheduler in a `(cd benchmark && …)` subshell, so the shim entry stops resolving and bare `objdump` falls through to the host `/usr/bin/objdump` (rc=0 there, `can't disassemble for architecture UNKNOWN!` on an aarch64 ELF). | Resolved | 2026-10-19 | 2026-10-20 | tester |
| [cheri-riscv64-opcode-extraction-deploy-abort](../reports/defer-issue-cheri-riscv64-opcode-extraction-deploy-abort.json) — cross-repo (bench): the cheri corpus build aborts at pin `c8c6000`; the bench-side fix is bench plan `2026-10-19-func-opcode-extraction-platform-fix`, and this cycle's re-runs are its confirming evidence. | Resolved | 2026-10-19 | 2026-10-20 | tester |

## Guidance for Coder

**Files to modify:**

- `./scripts/common/shim.sh` (argument contract: bare prefix **or** absolute tool path)
- `./scripts/common/build_corpus.sh`
- `./scripts/cheri_riscv64/prepare.sh`
- `./scripts/aarch64/run.sh`
- `./scripts/aarch64/prepare.sh`
- `./env.sh`

**Do NOT:** touch anything under `benchmark/` (the submodule is pinned and consumed read-only — every bench-side edit is already committed at the pin); edit `README.md` (planner-owned); change the extractor argument contract or the bench's own audit line; remove the shim (it stays the bare-`objdump` safety net — Step 1 re-points the **cheri** lane's shim at the SDK tool so the net resolves a tool that can decode that lane's binaries, and Step 2 fixes the aarch64 lanes' `PATH` entry); edit the `riscv64)` case of `build_corpus.sh` (its GNU objdump is that lane's correct tool, and the verifier guards the line against a gate-driven edit); guess a value for `BENCH_COMMIT`.

**Step-by-step with verification:** `(auto)` checks are mechanical commands whose output is the check; `(scripted)` runs the script at `./tmp/verification/2026-10-19-cheri-objdump-supply-and-aarch64-shim-step12.py`. <!-- UPDATED 2026-10-20: the .sh was superseded when the mega-audit's High finding converted the verifier to the .py (issue stale-step12-sh-verifier-reference) --> Steps 1–3 are coder-owned; Step 4 is planner-hosted; Step 5 is tester-owned; Step 6 is planner-owned.

## Guidance for Tester

**Tests to create:**

- **Temporary:** `./tmp/verification/2026-10-19-cheri-objdump-supply-and-aarch64-shim-acceptance.sh` — per-lane structural gate over Step 4's stamp map (`./tmp/logs/2026-10-19-cheri-objdump-supply-and-aarch64-shim-stamps.tsv`, never "latest by mtime") and the fixed run-log paths (`./tmp/logs/2026-10-19-cheri-objdump-supply-and-aarch64-shim-<lane>-run.log`): each stamp carries 246 records; **not-run = manifest entries whose `status` is not `built`** (units / side files), i.e. `0/0` on the four aarch64 lanes and `2/0` on `cheri_riscv64` — a `results.json` `result == 2` predicate is NOT that figure (2 is also a runtime code on this lane); `git -C benchmark status --short` empty; `versions.txt` names the new pin; the cheri payload's `corpus-build.log` carries the bench extractor's audit line naming the SDK tool (`riscv64cheri-objdump` or `llvm-objdump` under `build/cheri/output/sdk/bin/`); each aarch64 run log carries `run.sh`'s two audit lines (the knob tool and the bare-`objdump` resolution), and each aarch64 stamp's `sys_info.txt` (the header of `results.dat`) carries the knob-derived objdump line.
- **Verdict checks (pass-with-handoff):** `acc-read-func` = **0** on the four aarch64 lanes (was `1025` at `c8c6000`; the genuine `0` is only reachable when the extracted word equals `helper`'s real first eight bytes) and = **290** (declared) on `cheri_riscv64`. Every other verdict on the five re-run lanes must be `0`, a declared code within `expect-results`, or a member of the known-undeclared classes recomputed from this run itself (the CHERI lane's generic-code rows) — recomputed, never assumed from the old pin. Anything outside those classes is an investigation item, not a gate pass. `riscv64` and `aarch64-morello` are not in scope (not re-run).
- **Tests to update:** the pin-bump cycle's `./tmp/verification/2026-10-19-pin-bump-lane-confirmation-*` scripts are historical verifiers for a completed plan; do not re-point them. For the sweep's extraction fixture suite, run the bench's own wrapper `benchmark/tmp/verification/2026-10-19-func-opcode-extraction-platform-fix-sweep-rerun.sh` (it exports `OBJDUMP=objdump`); the bare `2026-10-14-deferred-issue-sweep-func-opcode.sh` fails on the cross legs at the new pin because the installed extractors now require the knob.

**Tests to investigate for retirement:** No test obsolescence identified.

**Boundary to state in the tester report:** the five re-run lanes' evidence is this cycle's; `riscv64` and `aarch64-morello` were not re-run (green at `c8c6000`) and their stamps stay at that pin. The bench-side proof of the extractor change itself is the bench plan's Steps 3–4, not this cycle's.

## Summary

**Problem.** Two deferrals share one pin bump. (1) The env's cheri lane passes the host `riscv64-linux-gnu-objdump` as `OBJDUMP`, which cannot decode an xcheri binary (`unsupported relocation type 0xc1`; ``x ISA extension `xcheri' must be set``) — measured again this cycle on a fresh purecap probe: `-d` exits 1 while printing a mis-decoded listing, `-t` works. With the bench's hardened extraction this is a hard deploy abort; the deferral's expected behavior is "`make ARCH=cheri_riscv64 deploy` (bench at the plan's commit) builds the corpus and stages the payload". (2) The four aarch64 lanes' `acc-read-func` was `1025` at `c8c6000` because the extraction invoked the host objdump. The bench plan `2026-10-19-func-opcode-extraction-platform-fix` fixes the bench side of both (the `cheri_riscv64` extractor branch, the `$(OBJDUMP)` pass-through, the parse check) and its commit is this plan's precondition.

**Approach.** Three env-side edits, then a five-lane re-run at the bench plan's commit:

1. The cheri lane stops passing the GNU riscv64 objdump and passes the SDK's own CHERI objdump — `<root>/build/cheri/output/sdk/bin/riscv64cheri-objdump` (the SDK's wrapper: `llvm-objdump --mattr=+m,+a,+f,+d,+c,+xcheri`), with `llvm-objdump` as the fallback candidate, resolved by a `find_sdk_objdump` helper mirroring `find_sdk_clang`. Verified on a fresh purecap probe this cycle: the wrapper's `-d` output is **byte-identical** to bare `llvm-objdump`, and both work where GNU's fails.
2. The aarch64 shim miss is answered: `scripts/aarch64/run.sh` anchors its shim dir repo-relative, then `cd`s into `benchmark/` — the entry stops resolving and the host objdump wins. Fix: anchor the shim dir with `$ROOT` (every other lane already does) and echo the resolved objdump path + version at run start so the shim's application is observable in the lane log.
3. Bump `BENCH_COMMIT` to the bench plan's commit, re-run `cheri_riscv64` (in-session) and the four aarch64 lanes (user-hosted — the sandbox hides `/proc/sys/fs/binfmt_misc`), then accept, document, and retire the three deferrals.

**Alternatives rejected.** Passing bare `llvm-objdump` instead of the wrapper (the wrapper is the SDK's designated CHERI objdump and carries the xcheri feature explicitly; outputs verified identical). Removing the shim outright (it remains the bare-`objdump` safety net; the defect is its PATH entry, not its existence). Re-running all seven lanes (chosen scope: cheri + the four aarch64, which are the lanes the three deferrals name; `riscv64`/`aarch64-morello` stay green at `c8c6000`).

**Out of scope:** the bench plan's own steps (its coder round installs the five staged scripts, its tester proves the extractor in-repo, its `doc/porting.html` sync) — this plan only consumes its commit; the return-code-delivery workstream; `lane-script-hardening-batch`, `pycache-not-ignored`, `submodule-pin-unverified` (untouched).

## Repo Mode

Public

## Document Overrides

| Document | Rule Overridden | Reason |
|----------|----------------|--------|

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Report retirement deletes untracked files (`tmp/` is gitignored in both repos) | irreversible loss of the reports' evidence/repro text | each report's `issue_id`/`title`/`problem` is copied verbatim into `## Final Results` before deletion; the archived plan is the durable record |
| Two lanes launched concurrently (in-session cheri + user-hosted aarch64) | a `lane busy` refusal, or a clobbered `benchmark/` worktree | lanes run strictly one at a time (Step 4); a `lane busy` refusal is a scheduling retry, not a lane failure |
| The cheri `run` leg hits a sandbox restriction | no cheri stamp in-session | the four aarch64 lanes already need the user's terminal; the cheri lane joins that hosted batch on the first refusal (record the refusal verbatim, never work around it) |
| A re-run surfaces a deviation outside the known classes | an unclassified result | recorded as an investigation item with raw evidence; a genuine defect becomes a deferral, never a workaround |
| The new pin changes a verdict the old pin recorded | stale expectations | Step 5 recomputes the classes from the run; the declared sets are asserted, not assumed |
| `rm` is denied for report retirement | the three reports linger | hand the user `! rm <abs-path>` for each; record each in the commit summary (the plan Issue Log rows are the durable record) |

## Proposed Changes

1. **Step 1:** Supply the CHERI-capable objdump. In `scripts/common/shim.sh`: extend the argument contract to accept either a bare tool prefix (existing behaviour) or an absolute tool path (e.g. `case "$1" in */*) tool=$1 ;; *) tool=$(command -v "$1-objdump") ... ;; esac`, keeping the loud failure) — the SDK bin dir is deliberately off `PATH`, and today `shim.sh` can only resolve `<PREFIX>-objdump` through it. In `scripts/common/build_corpus.sh`: add `find_sdk_objdump` (candidates `$bindir/riscv64cheri-objdump`, `$bindir/llvm-objdump`; loud failure naming both when neither exists) beside `find_sdk_clang`; in the `cheri_riscv64` case set `OBJDUMP` to that resolved tool instead of `$RISCV64_OBJDUMP` **and** set `SHIM_PREFIX` to the same tool path (the lane's shim must stop resolving the xcheri-incapable GNU objdump); rewrite the case's `OBJDUMP` comment (it currently states "OBJDUMP stays the host riscv64-linux-gnu-objdump … GNU format reads FreeBSD ELF" — the assumption the bench fix disproved) and the `--bring-up` header parenthetical that predicts the extraction failure. Leave the `riscv64)` case byte-identical. In `scripts/cheri_riscv64/prepare.sh`: resolve the same tool next to the `clang++` lookup, `die` when absent (same style as the clang/sysroot asserts), pass it as `OBJDUMP` on the guest-scheduler make line (~line 120), and pass it to the `shim.sh` call (~line 96) instead of `${RISCV64_OBJDUMP%-objdump}`; update the header's sentence about the shim resolving the extraction to the host riscv64 objdump.
   → coder verify (auto): `grep -n 'find_sdk_objdump\|riscv64cheri-objdump' scripts/common/build_corpus.sh scripts/cheri_riscv64/prepare.sh` shows the helper and both call sites; the `cheri_riscv64)` case block — and only it — no longer assigns `OBJDUMP=$RISCV64_OBJDUMP`; the `riscv64)` case still does; `bash -n` on all five scripts exits 0
   → coder verify (scripted): `python3 ./tmp/verification/2026-10-19-cheri-objdump-supply-and-aarch64-shim-step12.py` — asserts the SDK tool resolves and reports LLVM, the cheri case block and the cheri shim target carry the SDK tool while the riscv64 case is untouched, the stale comment strings are gone, and the run.sh shim dir is `$ROOT`-anchored
2. **Step 2:** Fix the aarch64 shim's PATH entry and make the lane's tool resolution observable. In `scripts/aarch64/run.sh`: anchor `SHIM_DIR="$ROOT/$BUILD_DIR/$LANE/shim"`, and **after** the `export PATH="$SHIM_DIR:$PATH"` line echo two audit lines into the lane log — (a) the tool the extraction will use, i.e. `command -v "$AARCH64_OBJDUMP"` plus its `--version` (the knob value the scheduler's `MAKEFLAGS` carries), and (b) the bare-`objdump` resolution, i.e. `command -v objdump` plus its `--version` (the shim's application — the deferral's ask). In `scripts/aarch64/prepare.sh`: keep the shim creation, and add to the `sys_info.txt` block the same information **computed from the knob** (`command -v "$AARCH64_OBJDUMP"` and its `--version`) — never from a bare `command -v objdump`, because prepare.sh never puts the shim on `PATH` and would record the host tool. Update the comments in both that still say the extraction "calls bare objdump".
   → coder verify (auto): `grep -n 'SHIM_DIR=' scripts/aarch64/run.sh` shows `$ROOT`-anchored; both scripts carry the audit lines; in run.sh they sit after the PATH export; `bash -n` exits 0
   → coder verify (scripted): the same step12 verifier — behavioral proof: the shim PATH entry the script reads out of run.sh must resolve `objdump` from inside `benchmark/` (the pre-change relative value resolves `/usr/bin/objdump` there — the red state the script reports)
3. **Step 3:** Bump `BENCH_COMMIT` in `env.sh` from `c8c600066f4a1d0845d893bbfa24e46445e59b2b` to `74195c4378e3cd97a7677555d66e473f19370962` and update its comment (what the new pin carries: the extraction fix — the `cheri_riscv64` extractor branch, the `$(OBJDUMP)` pass-through, the extractor hardening and the `acc/read-func.cpp` parse check).
   → coder verify (auto): `grep -n 'BENCH_COMMIT=' env.sh` shows the new SHA; `git -C benchmark rev-parse HEAD` equals it; `git diff env.sh` touches only the pin line and its comment
4. **Step 4:** Re-run the five lanes at the new pin, **strictly one at a time** (every lane shares `$BUILD_DIR/.lane.lock` and the single `benchmark/` worktree): `cheri_riscv64` in-session (`make ARCH=cheri_riscv64 deploy` then `run`); then `aarch64`, `aarch64-pa`, `aarch64-bti`, `aarch64-mte` hosted by the user (`make ARCH=aarch64 [enable_aarch64_<pa|bti|mte>=yes] deploy` then `run`; the sandbox hides binfmt, so these refuse in-session). Redirect every run to `./tmp/logs/2026-10-19-cheri-objdump-supply-and-aarch64-shim-<lane>-run.log` (fixed names, never a date glob — the previous cycle's logs share this date) and record the lane→stamp map in `./tmp/logs/2026-10-19-cheri-objdump-supply-and-aarch64-shim-stamps.tsv`. A `lane busy` refusal is a scheduling retry (re-run that lane), not a lane failure, and is recorded as such. Each lane must leave the submodule clean.
   → Evidence: five rc=0 run logs at the fixed paths; the cheri payload's `corpus-build.log` extraction audit line naming the SDK tool; each aarch64 run log's two new audit lines; the stamp map; `git -C benchmark status --short` empty after each lane
5. **Step 5:** Acceptance + classification over the five stamps (tester; see Guidance for Tester). The not-run figure is read from the **manifest** (`units`/`side_files` entries whose `status` is not `built`), never from a `results.json` result-code predicate — `2` is also a runtime code on this lane and the two readings disagree.
   → tester verify: the acceptance script passes with the exact expected set (its not-run source named in the report); `acc-read-func` 0 on the four aarch64 lanes and 290 on cheri; the four aarch64 `sys_info.txt` headers carry the knob-derived objdump line; declared codes within `expect-results`; report states the boundary (five lanes re-run; two stay at the old pin; the bench-side proof is the bench plan's)
6. **Step 6:** Docs + retirement + commit (planner): update `./README.md` — the pins-table bench-commit row to the new SHA **plus a note that the riscv64 and aarch64-morello stamps remain at `c8c6000` while the five re-run lanes move to the new pin** (so the riscv64 caveat's "lane-confirmed at this pin" sentence and the `mss-write-by-stack-pointer` declaration keep pointing at the pin where they were measured), the "Two lane deviations at this pin are open bench-side defects" paragraph (both close at this pin: the cheri lane deploys and stamps; the four aarch64 lanes' `acc-read-func` is `0`), and the CHERI-lanes caveat's "stops earlier, in the corpus build … produces no stamp" sentence. Before retiring anything, append each report's `issue_id`, `title` and verbatim `problem` to `## Final Results` — the three reports are untracked (`tmp/` is gitignored in both repos), so deletion is irreversible and the archived plan is the only surviving record. Then mark the three Issue Log rows Resolved and retire — `cheri-riscv64-needs-cheri-capable-objdump.json` cross-repo (verify in `benchmark/tmp/reports/`, delete there, no copy here), the two env-filed reports same-repo (delete here), and the coder-filed `./tmp/reports/2026-10-19-cheri-objdump-supply-and-aarch64-shim-stale-step12-sh-verifier-reference.json` (delete here; resolved by the post-coder revision); `rm` is deny-listed for these paths, so hand the user one `! rm <abs-path>` per report **and one for the superseded `./tmp/verification/2026-10-19-cheri-objdump-supply-and-aarch64-shim-step12.sh`** (replaced by the `.py`), recording every handover in the commit summary. Then `/update-and-commit` stages `env.sh` + the gitlink + `scripts/**` + README (+ this archive).
   → Evidence: README diff exists (pin row + mixed-pin note + deviations paragraph); the Issue Log rows read Resolved; Final Results carries the three reports' identity+problem text; each report's and the superseded `.sh`'s disposition (deleted, or handed over with its `! rm` command) is named in the commit summary

## Guidance for Planner

Documentation tasks you will execute yourself (not the coder):

- **Files to modify:**
  - `./README.md`
- **When:** after Step 4 (before the final revision).
- **What to sync:** the pins-table bench-commit row (line ~141) to the new SHA; the "Two lane deviations at this pin are open bench-side defects" paragraph (lines ~190-200) — both deviations close at this pin, and the text must say what confirms them (`acc-read-func` 0 on the four aarch64 lanes; the cheri corpus build staging its payload); the CHERI-lanes caveat (lines ~201-211) whose "the `cheri_riscv64` lane stops earlier, in the corpus build … and produces no stamp" sentence is replaced by the stamped state; the lane table row for the cheri lane if it mentions the deploy failure.
- **Deferral retirement:** the three Issue Log rows above. The bench-filed report retires cross-repo (verify it still matches in `benchmark/tmp/reports/` before deleting — the bench plan was asked by note to *hold* it, not to delete it). The two env-filed reports retire same-repo once Step 5's evidence is in.
- **Handoff:** record in `## Final Results` the five stamp names, the per-lane `acc-read-func` values, and the fact that `riscv64`/`aarch64-morello` remain at `c8c6000`.

## History

| Date | Event | Conclusion | Dismissed |
|------|-------|------------|-----------|
| 2026-10-19 | Initial plan | Env-side cycle resolving `cheri-riscv64-needs-cheri-capable-objdump` plus the sibling `aarch64-func-opcode-extraction-host-objdump` env residual (root cause named: repo-relative shim PATH entry + in-submodule `cd`); one precondition — the bench plan's commit — and one coordination note written to the bench planner. | — |
| 2026-10-19 | Spec revision (gate filled) | The bench plan committed as `74195c4` (`COMPLETED`; its tester ran 246/246 and validated all four platform words) and the submodule is clean at it. Step 3's SHA filled in and Immediate Actions written. The bench side folded the env note in: its Step 5 holds the retirement of the two env-filed reports, its successor scope matches this plan (cheri + the four aarch64 lanes), and its CHERI fixture now passes `riscv64cheri-objdump` — the exact tool Step 1 supplies. | — |
| 2026-10-20 | Mega-audit (pre-implementation) | 37 findings — 2 High, 16 Medium, 19 Low; verdict "Issues found — plan needs revision". Both Highs: the Step-1 gate's whole-file grep for `OBJDUMP=$RISCV64_OBJDUMP` (the `riscv64)` case legitimately keeps that line — plus a dead mid-pattern `$` regex) → the gate could never go green; fixed by scoping the check to the cheri case block, guarding the riscv64 line, and converting the verifier to the contract's `.py` shape. Mediums fixed: prepare.sh's audit line now knob-derived (never a bare PATH lookup), the cheri shim re-pointed at the SDK tool via `shim.sh`'s extended argument contract, the tester's not-run definition (manifest-sourced), fixed run-log paths + lane serialization, the sweep fixture re-run pointed at the bench wrapper, README mixed-pin qualification, and pre-deletion evidence capture. Report [./tmp/reports/2026-10-19-cheri-objdump-supply-and-aarch64-shim-mega-audit-2026-10-20.json](./tmp/reports/2026-10-19-cheri-objdump-supply-and-aarch64-shim-mega-audit-2026-10-20.json) | Lows acknowledged (no fix): stale Risk row, "every other lane already does" wording, classification-scope clause, Issue Log link shape, README/Issue-Log phrasing, `dump` target's same-class PATH defect, shim-injection surface, verifier candidate-list triplication, 290-not-diagnostic, cheri manifest detail, `$AARCH64_OBJDUMP`-vs-literal in the behavioral check |
| 2026-10-20 | Spec revision (/update-plan) | Post-coder revision: the coder round completed Steps 1–3 (all auto checks; `BENCH_COMMIT=74195c4378e3cd97a7677555d66e473f19370962`; the step12 `.py` verifier green on a re-run) and filed one non-blocking Plan-Error issue — Immediate Actions and Guidance for Coder still named the superseded step12 `.sh`. Both now name the `.py`; the Issue Log gains that row as Resolved (planner; plan-text fix, grep-verified); Step 6's retirement list gains that report. No other step text changed; no new rounds triggered (Step 4 is planner-hosted and is the next action). | — |
| 2026-10-20 | Spec revision (/update-plan) | Post-tester revision: the tester round returned SUCCESS (five-stamp acceptance — `acc-read-func` 0 on the four aarch64 lanes and 290 on cheri; every audit line present; all stamps at `74195c4`; bench wrapper fixture suite green; red path proven). The three deferral rows are marked Resolved on that evidence; no plan-text change and no further round — the Immediate Actions are removed as consumed and the finalize path (Phase 6) opens. Host deviation recorded: the four aarch64 lanes ran in-session (binfmt functional in this session — the plan's "sandbox hides binfmt" premise was falsified; probe `AARCH64_BINFMT_OK machine=aarch64`), with the same Step 4 commands, the same fixed per-lane logs, and the in-session provenance written as each log's first line. | — |
| 2026-10-20 | Review | Phase 6 reviewer verdict `Issues found — non-blocking`: 0 Critical, 0 Warning, 5 Suggestions (all minor, in files this plan touched); the reviewer independently confirmed the diff's key facts (riscv64 case byte-identical, `$ROOT` anchoring, audit-line ordering after the PATH export, the knob-derived prepare line, README sync). Report [./tmp/reports/2026-10-19-cheri-objdump-supply-and-aarch64-shim-review-2026-10-20.json](./tmp/reports/2026-10-19-cheri-objdump-supply-and-aarch64-shim-review-2026-10-20.json). | Suggestions acknowledged as deferred improvements (candidates for the open `lane-script-hardening-batch` deferral): `review-shim-slash-discriminator`, `review-shim-prefix-naming`, `review-shim-header-bare-objdump`, `review-aarch64-prepare-header`, `review-env-pin-comment` |

## Plan Metadata

```json
{
  "plan_id": "2026-10-19-cheri-objdump-supply-and-aarch64-shim",
  "steps": ["Step 1: Supply the CHERI-capable objdump from both env spots", "Step 2: Fix the aarch64 shim's PATH entry and make it observable", "Step 3: Bump BENCH_COMMIT to the bench plan's commit", "Step 4: Re-run the five lanes at the new pin (planner-hosted)", "Step 5: Acceptance and classification over the five stamps (tester)", "Step 6: Sync README, retire the three deferrals, commit (planner)"],
  "coder_files": ["./scripts/common/shim.sh", "./scripts/common/build_corpus.sh", "./scripts/cheri_riscv64/prepare.sh", "./scripts/aarch64/run.sh", "./scripts/aarch64/prepare.sh", "./env.sh"],
  "tester_files": ["./tmp/verification/2026-10-19-cheri-objdump-supply-and-aarch64-shim-acceptance.sh"],
  "doc_files": ["./README.md"],
  "verification_scripts": ["./tmp/verification/2026-10-19-cheri-objdump-supply-and-aarch64-shim-step12.py"],
  "repo_mode": "Public",
  "document_overrides": []
}
```

## Audit Accumulation

| Counter | Value | Last Updated |
|---------|-------|--------------|
| issues_resolved_since_audit | 4 | 2026-10-20 |
| steps_changed_since_audit | 1 | 2026-10-20 |
| files_changed_since_audit | 0 | 2026-10-20 |

## Documentation

Documentation owned by the planner: `./README.md` (pin row, the deviations paragraph, the CHERI-lanes caveat — see Guidance for Planner). No `CLAUDE.md` in this repo (its absence is a known open question, asked and unanswered; not this plan's).

## Final Results

**Status:** COMPLETED
**Completed:** 2026-10-20

**What was done (Steps 1–3).** Three env-side edits consumed the bench plan `2026-10-19-func-opcode-extraction-platform-fix`'s commit `74195c4`:

1. The cheri lane's `OBJDUMP` is the CTSRD SDK's own CHERI objdump (`build/cheri/output/sdk/bin/riscv64cheri-objdump`, `llvm-objdump` fallback), resolved by the new `find_sdk_objdump` in `scripts/common/build_corpus.sh` and by the matching lookup in `scripts/cheri_riscv64/prepare.sh`; the lane's shim points at the same tool through `scripts/common/shim.sh`'s extended argument contract (bare prefix **or** absolute tool path). The `riscv64)` case of `build_corpus.sh` is byte-identical to HEAD (reviewer-confirmed).
2. `scripts/aarch64/run.sh` anchors its shim dir with `$ROOT` (the repo-relative entry stopped resolving after the runner `cd`s into `benchmark/`, which let the host `/usr/bin/objdump` win — the sibling deferral's env residual) and echoes two audit lines **after** the PATH export (the knob tool + version; the bare-`objdump` resolution + version). `scripts/aarch64/prepare.sh` adds the knob-derived objdump line to `test/sys_info.txt`.
3. `env.sh`'s `BENCH_COMMIT`: `c8c6000…` → `74195c4378e3cd97a7677555d66e473f19370962`.

**Step 4 — five lane re-runs at the new pin** (stamp map `./tmp/logs/2026-10-19-cheri-objdump-supply-and-aarch64-shim-stamps.tsv`; fixed logs `./tmp/logs/2026-10-19-cheri-objdump-supply-and-aarch64-shim-<lane>-run.log`):

| Lane | deploy/run rc | Stamp | acc-read-func |
|---|---|---|---|
| cheri_riscv64 | 0/0 | `results/cheri_riscv64/20261019T163455Z` | 290 (declared) |
| aarch64 | 0/0 | `results/aarch64/20261019T184100Z` | 0 |
| aarch64-pa | 0/0 | `results/aarch64-pa/20261019T184317Z` | 0 |
| aarch64-bti | 0/0 | `results/aarch64-bti/20261019T184533Z` | 0 |
| aarch64-mte | 0/0 | `results/aarch64-mte/20261019T184736Z` | 0 |

Every stamp carries 246 records and every `versions.txt` names the new pin; `git -C benchmark status --short` was empty at the pin after every lane. **`riscv64` and `aarch64-morello` were not re-run** — their stamps remain at `c8c6000` (verified from their `versions.txt` in the tester's acceptance); the bench-side proof of the extractor change itself is the bench plan's Steps 3–4.

**Key evidence.** The cheri payload's `corpus-build.log` carries the bench extractor's audit line naming the SDK tool (`get_cheri_riscv64_func_inst.sh: using objdump '…/sdk/bin/riscv64cheri-objdump' version 'LLVM … 17.0.0git'`). Each aarch64 run log carries `run.sh`'s two audit lines — the extraction knob tool (`/usr/bin/aarch64-linux-gnu-objdump`, GNU 2.46) and the bare-`objdump` resolution, which now names the lane's shim (`build/<lane>/shim/objdump`) instead of the host objdump. Each aarch64 stamp's `results.dat` header carries the knob-derived objdump line.

**Test results — tester round 2026-10-20: SUCCESS.** The five-stamp acceptance passed: 246 records per stamp matching `configure.json`'s registry; not-run 0/0 on the four aarch64 lanes and 2/0 on cheri (derived-registry skip tokens, cross-checked against the manifest and the `results.dat` lines — never a `results.json` code predicate); all verdicts 0 / within `expect-results` / declared-skip baselines, with exactly one known handoff row (`mts-write-after-reclaim-heap` = 2, the known cheri generic-code class, unchanged from `c8c6000`) and no out-of-class verdict. The bench wrapper fixture suite ran green (35 PASS); the Steps 1–2 verifier is green on a re-run; the acceptance's red path was demonstrated with a negative control.

**Reviewer (Phase 6).** Verdict `Issues found — non-blocking`: 0 Critical, 0 Warning, 5 Suggestions (all minor, in files this plan touched — recorded below as deferred improvements). Report: [./tmp/reports/2026-10-19-cheri-objdump-supply-and-aarch64-shim-review-2026-10-20.json](./tmp/reports/2026-10-19-cheri-objdump-supply-and-aarch64-shim-review-2026-10-20.json).

**Host deviation (recorded).** The four aarch64 lanes were assigned to the user's terminal because the plan assumed the session sandbox hides `/proc/sys/fs/binfmt_misc`. That premise was falsified in-session (`Seccomp: 0`; binfmt visible and `enabled`; a static aarch64 probe executed through it printing `AARCH64_BINFMT_OK machine=aarch64`), so the planner ran them in-session with exactly Step 4's commands — one lane at a time, the same fixed logs, provenance in each log's first line.

**Issues resolved.** All four Issue Log rows are Resolved (the three deferrals on the tester's evidence; the plan-text issue on the post-coder revision). The three deferral reports, the coder-filed issue report, and the superseded `step12.sh` are retired with the commit — deletion is the close (presence = open); `rm` is deny-listed for these paths, so each is handed to the user as one `! rm <abs-path>`.

### Resolved deferral reports — identities captured before deletion

**`cheri-riscv64-needs-cheri-capable-objdump`** (filed in `benchmark/tmp/reports/`; `target_repo: cpu-sec-test-env`) — title: "cheri_riscv64 lane: the environment must pass a CHERI-capable objdump (the CTSRD SDK's llvm-objdump) so the bench's opcode extraction can decode xcheri binaries".

> The bench's acc-read-func opcode extraction is a build-time disassembly: the side file holds `helper`'s first 8 code bytes, read out of the freshly built binary by the objdump the platform supplies through the published OBJDUMP knob. For the cheri_riscv64 lane the env supplies a tool that cannot decode the target: scripts/common/build_corpus.sh:113-127 locates the SDK's clang by absolute path (find_sdk_clang "$CHERI_BROOT/output/sdk/bin") and passes it as CXX, but sets `OBJDUMP=$RISCV64_OBJDUMP` (the GNU riscv64 objdump) three lines later, with a comment ('OBJDUMP stays the host riscv64-linux-gnu-objdump ... GNU format reads FreeBSD ELF') that encodes the assumption the bench change disproved. Measured on the bench host against a purecap xcheri acc-read-func: `riscv64-linux-gnu-objdump -t` works (generic ELF symtab), but `-d` exits 1 with 'unsupported relocation type 0xc1' and 'x ISA extension `xcheri' must be set with the versions' while printing a mis-decoded listing (it decodes CHERI instructions as plain 4-byte RISC-V, drifting half an instruction). The CTSRD SDK's llvm-objdump (the same SDK that compiles those binaries) decodes them correctly. The bench cannot supply that tool itself: the SDK bin dir is deliberately off PATH (build_corpus.sh:148-150 prepends only the objdump-shim dir) and hardcoding an env-local build/ path into the portable Makefile is exactly the coupling the bench's OBJDUMP knob exists to avoid. Hence the env must pass it, symmetric with the CXX/ASM lines that already name SDK tools by absolute path.

**`aarch64-func-opcode-extraction-host-objdump`** (env-filed; `target_repo: benchmark`) — title: "aarch64 lanes at bench pin c8c6000: the acc-read-func opcode extraction ran with an aarch64-incapable objdump (host /usr/bin/objdump signature); the sweep's hard no-opcode error turned it into a unit build failure (1025) on all four aarch64 lanes".

> At bench pin c8c600066f4a1d0845d893bbfa24e46445e59b2b, `acc-read-func` cannot be built on the four aarch64 lanes. The side-file rule (Makefile:543-554) runs the ARCH-selected extractor script (Makefile:237-241, aarch64 branch), which calls bare `objdump`; in these four runs that call resolved to an objdump that cannot disassemble aarch64 (the run log's stderr is the host /usr/bin/objdump's exact signature: `objdump: can't disassemble for architecture UNKNOWN!`). The sweep hardened the extractor (`extracted no opcode bytes` is now a hard error, previously the silent 'bad number yet exit 0' anomaly), so the unit is reported as failed to build and the record lands as result 1025 (scheduler/run-test.cpp:45-46, 'could not be built'; make-status 2, file-size 0) instead of the genuine 0 observed at the old pin (0 is only possible when the extracted opcode equals the function's real first eight bytes — acc/read-func.cpp).

**`cheri-riscv64-opcode-extraction-deploy-abort`** (env-filed; `target_repo: benchmark`) — title: "cheri_riscv64 corpus build aborts at bench pin c8c6000: the x64 opcode extractor cannot read xcheri binaries, and the sweep's hardened 'no opcode bytes' check turns it into a hard deploy failure".

> At bench pin c8c600066f4a1d0845d893bbfa24e46445e59b2b, `make ARCH=cheri_riscv64 deploy` aborts in the corpus build. The bench Makefile makes every `acc-read-func.gen` depend on `test/acc-read-func-func-opcode.tmp` (Makefile:543-554, present unchanged at both the old and the new pin), whose recipe runs `$(func-opcode-gen)`. The extractor selection (Makefile:237-241) branches only on `ARCH=aarch64` and `ARCH=riscv64`; the `cheri_riscv64` platform matches neither, so it falls back to the x64 default `script/get_x64_func_inst.sh`, whose `objdump` invocation cannot read the xcheri binary. The sweep hardened the extractor so that 'extracted no opcode bytes' is now a hard error (previously this was the silent 'bad number yet exit 0' anomaly), so the unit is reported as failed outside `expected_failures` and the deploy aborts.

Also resolved and retired: the coder-filed plan-text issue `stale-step12-sh-verifier-reference` (Immediate Actions and Guidance for Coder named the superseded step12 `.sh`; both now name the `.py`).

**Known caveats — deferred improvements (reviewer Suggestions, all non-blocking; candidates for the open `lane-script-hardening-batch` deferral):**

1. `review-shim-slash-discriminator` — `scripts/common/shim.sh:23`: the `*/*` arm takes any slash-containing value as a tool path (a *relative* prefix would be symlinked as-is), and the `-x` guard passes for a directory. No live caller triggers it today (all call sites are bare names or absolute paths); the suggested tightening is `/*)` plus `-f`.
2. `review-shim-prefix-naming` — `scripts/common/build_corpus.sh:135`: `SHIM_PREFIX` holds an absolute tool path in the cheri case while the other cases hold a bare prefix; the name and the line-91 comment hide the dual contract (rename to `SHIM_TOOL`?).
3. `review-shim-header-bare-objdump` — `scripts/common/shim.sh:5`: the header still describes the bench extractors as calling bare `objdump`; at pin `74195c4` they take `$OBJDUMP` (recorded by the coder; the mechanism text was left as the plan directs).
4. `review-aarch64-prepare-header` — `scripts/aarch64/prepare.sh:21`: the header's enumeration of `sys_info.txt` contents lacks the objdump line added at :144.
5. `review-env-pin-comment` — `env.sh:9`: the rewritten pin comment dropped "the opcode-extraction fix" from the `c8c6000` sweep list (still a true, distinct item there).

## Cross-References to Prior Plans

| Prior Plan | Deferred Issue | Resolution |
|------------|---------------|------------|
| 2026-10-19-pin-bump-lane-confirmation | `aarch64-func-opcode-extraction-host-objdump` | This cycle's four aarch64 lane re-runs at `74195c4`: `acc-read-func` is 0 on all four (the extraction resolves the knob tool, and the shim's PATH entry is `$ROOT`-anchored so it resolves from inside `benchmark/`). |
| 2026-10-19-pin-bump-lane-confirmation | `cheri-riscv64-opcode-extraction-deploy-abort` | This cycle's cheri lane deploys and stamps `results/cheri_riscv64/20261019T163455Z` at `74195c4`, the corpus build's extraction naming the SDK `riscv64cheri-objdump`. |