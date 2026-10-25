# Plan: Uniform pin at the return-code commit — nine lanes re-run and the comparison snapshot
**Project:** /home/wsong83/proj/xiangshan/cpu-sec-test-env
**Plan ID:** 2026-10-24-uniform-pin-comparison-snapshot
**Created:** 2026-10-24

## Issue Log

Rows ordered newest-first.

| Issue | Status | Found | Resolved | Resolved By |
|-------|--------|-------|----------|-------------|
| [new-out-of-expect-codes](../reports/2026-10-24-uniform-pin-comparison-snapshot-new-out-of-expect-codes.json) — intent check (2026-10-25): `214`/`50` are one defect (the landing block's delivery lost its argument; the value is the label address's low byte), `262` is a mis-aimed RA write caught by main's canary, cheri_riscv64's declared `cfi-return-without-call`=1 is vacuous, `260` (Morello) is held for one guest-side observation | Fix-first, delivered to the bench (`benchmark/tmp/reports/defer-issue-cfi-delivery-defects.json`); `214`/`50`/`262` must not be declared | 2026-10-24 | — | — |
| [f2-267-not-closed](../reports/2026-10-24-uniform-pin-comparison-snapshot-f2-267-not-closed.json) — F2/267 is not closed: both riscv64 venues still deliver `267`, the crash reproduces outside the guest at the case's own attack jump, so the declared `1` is unreachable | Fix-first, delivered to the bench (`benchmark/tmp/reports/defer-issue-f2-267-not-closed.json`); this row stays open | 2026-10-24 | — | — |
| [defer-issue-mte-lane-pin-not-in-effect](../reports/defer-issue-mte-lane-pin-not-in-effect.json) — the aarch64-mte lane's MTE claim is unbacked (the pin is rejected by this host's qemu-aarch64; the lane's 246 verdicts equal the plain aarch64 lane's, record for record); both riders unprovable on the lane | Deferred to a new env cycle (standalone env deferral; the plan-scoped duplicate awaits the user's `rm`) | 2026-10-24 | — | — |
| [claude-dir-untracked](../reports/2026-10-24-uniform-pin-comparison-snapshot-claude-dir-untracked.json) — `./.claude/` is neither tracked nor ignored in a public repo | Resolved (Step 4 lands the `.gitignore` entry; policy: ignore the directory wholesale, user 2026-10-24) | 2026-10-24 | 2026-10-25 | planner |
| pycache-not-ignored — folded into Step 1 (the env `.gitignore`); its report was retired by Step 1 and the tree is clean of `__pycache__` at the pin | Resolved (Step 1; planner-verified) | 2026-10-19 | 2026-10-25 | coder + planner |
| [cpio-inode-image-nondeterminism](../../benchmark/tmp/reports/defer-issue-cpio-inode-image-nondeterminism.json) + [guest-bench-tree-dirty-marker](../../benchmark/tmp/reports/defer-issue-guest-bench-tree-dirty-marker.json) — the two bench-side platform defects, delivered from this repo's outbox as bench deferrals; the bench copies exist, so this repo's pending envelopes retired here. The defects' **fixes** stay open on the bench side (their own cycle) | Envelopes retired by this cycle; fixes remain open bench-side | 2026-10-20 | — | — |

## Immediate Actions

Brief for the Step 3 tester round — facts observed by the planner while hosting Step 2. Re-derive each independently from the stamps and the tree; the brief exists to prevent a false start (the plan's own F2 premise is falsified below), never to be taken on trust.

**Stamps.** Nine at `f4c916a`, every lane deploy rc 0 / run rc 0, the submodule clean at the pin before and after each lane: map `./tmp/logs/2026-10-24-uniform-pin-comparison-snapshot-stamps.tsv`, per-lane deploy/run logs alongside it.

**1. The F2 closure premise is falsified on both riscv64 venues.** `cfi-jump-func-ra-from-heap-memcpy-implicit-arith` delivers `267` at `f4c916a` on `results/riscv64/20261024T131545Z` and `results/riscv64-nemu/20261024T132019Z` — not the declared `1` this plan's Issue Log row and Step 3 assert. x86_64 and the four aarch64 lanes deliver `0`. Classify the row out-of-expect with its evidence line; do not assert closure. (The deployed record is identical to the tracked registry and both corpora were rebuilt at the pin, so this is not a staging artifact.)

**2. Two further riscv64-venue changes vs the previous riscv64 stamp `results/riscv64/20261018T231030Z`:** `cfi-call-mid-func` 0 → `214` (undeclared; its source carries no `-42`, so classify the provenance rather than assuming one) and `cfi-return-to-peer-asmfunc` 0 → `262` (256+SIGABRT). Both venues identical. `cfi-return-to-parent-wrong-call-site-fakefunc` 255 → `1` (declared) as the contract intends.

**3. The aarch64-mte lane's CPU claim is contradicted by live evidence — both MTE riders are gated on this.** Its `results.dat`/`sys_info.txt` header claims `CPU: max,mte=on (emulated by qemu-aarch64)`, but that header is written from the env.sh pin (`scripts/aarch64/prepare.sh:131-135`), never observed. Planner probes (2026-10-24; `./tmp/verification/2026-10-24-mte-cpu-probe.c` + binary): an aarch64 ELF executed through the binfmt handler with `QEMU_CPU=max,mte=on` fails outright on this host's qemu-aarch64 10.2.1 — `can't apply global max-arm-cpu.mte=on: Property 'max-arm-cpu.mte' not found`, rc 1; the `QEMU_CPU=bogusmodel` negative control errors too (so the variable is honoured), and an empty value errors as `-cpu option cannot be empty`. Yet the lane's run executed all 246 cases successfully with no qemu error line anywhere in its log, and its 246 verdict codes are identical to the base `aarch64` lane's. The pin therefore cannot have been in effect for the executions: verify, trace the chain (`scripts/aarch64/run.sh:110` exports it before the scheduler; `run-test.cpp:503` passes `run_env` through `posix_spawnp`), and record the mechanism as a finding. Both rider questions presuppose a lane with MTE live; if it is not live, say so rather than probing an unreachable path.

**Planner's unverified read of the other lanes** (the tester's classification is authoritative): x86_64 and aarch64 ×4 show no out-of-expect rows; `cheri_riscv64` — 246 records, 2×`1025` (its two declared skips), codes `{0:81, 1:9, 2:6, 50:1, 262:3, 290:144}` to be classified against the lane's derived registry (`build/cheri_riscv64/payload/configure.json`), not the tracked one; `aarch64-morello` — 246 records, 1×`1025` (its declared skip), codes `{0:72, 1:20, 2:4, 16:12, 260:1, 262:3, 290:133, 1025:1}`, where `260` (new) and the now-absent `255` deserve their own classification.

## Intent Verification (2026-10-25)

The user's directive after the tester round: before deciding to declare anything, check whether each out-of-expect value really is the test case's designed result on its platform. The check ran on the host — the deployed corpora survive under `build/<lane>/` (`build/riscv64/corpus/test/`, `build/cheri_riscv64/payload/test/`, `build/aarch64-morello/payload/test/`, all at `f4c916a`) — so no lane re-run was needed; the riscv64 rows additionally reproduce under `qemu-riscv64` user-mode.

**Root cause of `214`/`50` (one defect).** The pin's refactor made `gvar` stop being a verdict, so the landing block's delivery became a bare constant. On RISC-V `a0` is both `gvar()`'s return and `exit()`'s first argument, so the guard `if(gvar()==0)` proves the argument is already zero and the compiler deletes the argument setup; the landed jump then calls `exit(<label address>)` and POSIX keeps the low byte (`0x1fd6` → 214, `0x8032` → 50). x86_64/aarch64 guard on rax/x0 while the delivery wants edi/w0 — distinct registers, nothing folds; verified in the emitted assembly (`.L2: xorl %edi,%edi; call exit`, `.L2: mov w0,0; bl exit`). The values are deterministic functions of the binary layout, hence impossible to declare; and the earlier "`-42`" and "parameter-band 32+18" readings were both wrong.

**Per-row verdicts** (each reproduced; details in the issue reports):
- `cfi-call-mid-func` `214` (riscv64, riscv64-nemu) / `50` (cheri_riscv64): one defect, as above; the attack itself *lands* (the sibling lanes' designed `0` is the real posture).
- `cfi-return-to-peer-asmfunc` `262` (both riscv64 venues): reproduced as `*** stack smashing detected ***` (rc 134). `helper`'s frame is 16 bytes with its `ra` at `sp+8`; the calibrated write (offset 24) lands at `helper_sp+24 = main_sp+8` — main's canary slot (main's `ra` sits at `main_sp+40`) — so `__stack_chk_fail` aborts when main returns. A mis-aimed write, not a defence engaging (the intended attack writes the RA directly and never touches the canary).
- F2/267: reproduced SIGSEGV; `-d in_asm` shows the last translated block ending at main's `jr t0` — the `JMP_DAT_PTR` attack jump — so the fault is in the case's own path and the declared `1` is unreachable.
- `cfi-return-without-call` `260` (aarch64-morello): **held** (user decision). The Morello build compiles the case into a capability sequence (block address sealed with the return-block key, 16-byte capability stores at 8-byte decrements, epilogue `ret c30`); the record already declares the illegal-push family (`16`/`266`, both "bus error"). Whether SIGILL is that family's architectural rendering on Morello or an un-ported push macro / emulation gap needs one guest-side observation — neither declared nor fixed until then.
- **New finding**: `cfi-return-without-call` on cheri_riscv64 records its *declared* `1` vacuously — the record passes `-vframe-size` but the lane never records `frame-size` (its calibration record is a lane skip), so the literal token fails `strtol` and the case returns `1` before the attack is attempted. A declared code delivered for the wrong reason; the outcome-only scan cannot see it.

**Completeness method** (the user's "can you find all of them"). The class needs a dynamically-entered *compiler-generated* block plus a delivery from it; every other dynamic entry lands in hand-written asm (`lib/*/indepassembly*.asm`), which sets its arguments by construction. So the candidate set is exactly the sources that materialize a label address: 16 files (12 `cfi/`, 3 `acc/`, 1 `cpi/`). A per-binary structural scan of the deployed riscv64 corpus (`tmp/verification/2026-10-25-landing-block-scan.py`; log `tmp/logs/2026-10-25-landing-block-scan.txt`) reviewed every landing block of that family: exactly one genuine delivery defect — `cfi-call-mid-func`, matching the one row that misfired; `jump-mid-func`, `return-to-peer-func`/`-mfunc` and the same-call-site family set `li a0,0` in-block; `return-to-parent-*`'s labels are return sites into the case's own code, not delivery blocks; the residue was libstdc++ code. CHERI/Morello still need one discriminator (their objdumps do not annotate call targets, so block addresses and ordinary function addresses look alike).

**Dispositions (user, 2026-10-25).** Fix-first, delivered to the bench tracker: `benchmark/tmp/reports/defer-issue-cfi-delivery-defects.json` (make the dynamic-entry delivery blocks self-contained across the 16-source family; re-anchor the peer-asmfunc offset; handle cheri's frame-size consumption or gate the vacuous record) and `benchmark/tmp/reports/defer-issue-f2-267-not-closed.json` (the F2 re-open). `214`/`50`/`262` are not declarable; `260` is held for verification. The MTE finding goes to a new env cycle as the standalone deferral `../reports/defer-issue-mte-lane-pin-not-in-effect.json`.

## Guidance for Coder

**Files to modify:**

- `./env.sh` (the bench pin)
- `./scripts/common/derive_registry.py` (only if the skip re-validation shows a stale row — with evidence)
- `./.gitignore` (the pycache fix)
- nothing else

**Do NOT:** edit anything inside `benchmark/` (its pin `f4c916a` is fixed; the platform's registry swap remains the one consumed transient — see the repo Rules); change any lane script, the Makefile dispatch, or `version_stamp.sh`; touch `README.md`, `CLAUDE.md`, `doc/**`, `plans/` (planner-owned); delete the two bench-side `benchmark/tmp/reports/defer-issue-{cpio-inode-image-nondeterminism,guest-bench-tree-dirty-marker}.json` files (the submodule is read-only; the bench tracker owns them now).

**Step-by-step with verification:** `(auto)` checks are mechanical commands whose output is the check. Step 1 is coder-owned; Step 2 is planner/user-hosted (nine lane runs, one at a time); Step 3 is tester-owned; Step 4 is planner-owned.

## Guidance for Tester

**Tests to create:**

- **Temporary:** `./tmp/verification/2026-10-24-uniform-pin-comparison.py` — the snapshot builder: read the nine stamps' `results.json` + the tracked `benchmark/configure.json`; emit (a) the per-lane acceptance table — record count vs the lane's derivation (skips included as such), every verdict classified against the record's `expect-results` **meanings** (declared hit / `0` / out-of-expect, out-of-expect rows named with lane, record, code and a one-line hypothesis each); (b) the **cross-lane comparison table** — per category (`acc cfi cpi mss mts`), per lane, counts of `0` / declared / out-of-expect; (c) the divergence list versus the `x86_64` reference lane, one row per differing record with both codes and their declared meanings. Outputs `./tmp/verification/2026-10-24-uniform-pin-comparison.tsv` + `...-comparison.md` (the cycle's headline artifact).
- **Temporary:** `./tmp/verification/2026-10-24-uniform-pin-comparison-classification.json` — the standard classification artifact over the nine stamps (the shim cycle's shape), with every out-of-expect row's terminal disposition.
- **Riders (the return-code plan's named live checks):** on the `aarch64-mte` lane — (i) whether the targeted MTE registration's `RT_SICODE_MTESERR` (9) predicate can match a hardware tag fault at all (the `99` observed recently is HWASan's own runtime exit, a different mechanism); (ii) whether `SA_EXPOSE_TAGBITS` yields a tagged `si_addr` on this lane (the flag was accepted at the bench fix, so the EINVAL/degraded path is unproven). Design the smallest probe that raises a synchronous tag check on the lane (a `./tmp/verification/` probe built with the lane's toolchain), observe the handler's registration/match path and the address's tag bits, and record the outcome; an unprovable predicate or an untagged address is a **finding** (bench-side deferral), never silently green.
- **The F2/267 closure check:** the journey record delivers its declared `1` on `riscv64` and `riscv64-nemu` (and not 267); record the evidence line for the Issue Log row.
- **Skip-row re-validation (Step 1's evidence, re-checked here):** the three `SKIP_TABLE` rows — `cheri_riscv64`'s `acc-get-frame-size` and `mss-write-by-stack-pointer`, `aarch64-morello`'s `cfi-call-mid-func` — still fail to build at `f4c916a` (the return-code cycle edited mss and cfi sources; a row whose unit now builds is stale and must have been removed with evidence in Step 1). Probe each: the derived registry's skip marking must match a real attempt.
- **Tests to update or retire:** none machine-local requires re-pointing beyond the above.

**Boundary to state in the tester report:** this cycle's stamps are the uniform baseline; the two bench platform defects' fixes and any rider fallout are named follow-ups, not this cycle's work.

## Summary

**Problem.** Every lane's newest stamp sits at a different bench pin — `x86_64` at `c2c7039` (2026-10-13, the pre-sweep world), `riscv64` and `aarch64-morello` at `c8c6000`, `aarch64` ×4 and `cheri_riscv64` at `74195c4`, `riscv64-nemu` at `a09f570` — while the bench has since landed the return-code contract (`f4c916a`: every case's process status is a declared, meaning-carrying value; the registry's `expect-results` now document their codes; the F2/267 defect is fixed at the source). No cross-platform comparison can be honest across four pins, and the F2 row's closure — and the new codes' real-lane confirmation — wait on the lanes.

**Approach.** Bump `env.sh`'s `BENCH_COMMIT` to `f4c916a` and re-run **all nine lane configurations** at the one pin, one lane at a time under the shared lane lock: `x86_64`, `aarch64`, `aarch64-pa`, `aarch64-bti`, `aarch64-mte`, `riscv64`, `riscv64-nemu`, `cheri_riscv64`, `aarch64-morello`. Classify every stamp against the new registry meanings, verify the F2/267 closure and the two MTE riders, and produce the **comparison snapshot** — the per-category cross-lane table with every divergence traced to a named record and its declared meaning. That table is the aim's deliverable: XiangShan/NEMU (via `riscv64-nemu`) tested and compared against x86, aarch, and CHERI on identical software.

Deploys are warm (the pinned CHERI emulator/images, the riscv64 kernel/rootfs and the NEMU caches exist from prior cycles; verify the pinned hashes before trusting warmth). Step 1 also retires this repo's two pending envelopes (their bench copies exist) and folds the pycache fix.

**Out of scope:** the two bench platform defects' fixes (their own bench cycle — the `-dirty` marker and cpio `--reproducible`; they affect provenance text and image bytes, not verdicts); the bench-side scratch-tree redesign; any new lane; durable doc pages for the comparison (the artifact is machine-local; a doc page is a follow-up decision once the table stabilizes).

## Repo Mode

Public

## Document Overrides

| Document | Rule Overridden | Reason |
|----------|----------------|--------|

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| A deploy leg is colder than assumed (NEMU corpus rebuilds every unit — the registry changed) | wall-clock, not correctness | warm caches verified in Step 1; the NEMU corpus cross-build is minutes; deploy under `LANE_DEPLOY_TIMEOUT` |
| New codes surface new out-of-expect rows on some lane | noise or a real finding | every row classified with a hypothesis; real defects become deferrals — the classification artifact's point is that nothing is silently green |
| A skip row went stale (a case the return-code cycle edited now builds on CHERI/Morello) | a runnable record marked skip | Step 1 probes each row against a real build; stale rows removed with evidence; the tester re-checks |
| An MTE rider is inconclusive on this host | an unproven path stays unproven | record the observed mechanism and file a bench-side deferral naming the missing evidence; never mark green |
| A lane run times out (124) | no stamp for that lane | the fence holds (nothing published); re-run after diagnosis; the cycle stalls on findings, never on a truncated stamp |

## Proposed Changes

1. **Step 1 (coder):** Pins + housekeeping. `env.sh`: `BENCH_COMMIT` → `f4c916a821a6f3fa7024a75b1a25304ae4555729` with a one-line comment (the return-code contract: declared meanings, the F2/267 fix). Retire the two pending envelopes (`./tmp/reports/pending-defer-*.json` — the bench copies exist at `benchmark/tmp/reports/defer-issue-{cpio-inode-image-nondeterminism,guest-bench-tree-dirty-marker}.json`; the bench-side fixes stay open). Fold the pycache fix per its report (the env `.gitignore`) and retire it. Re-validate the three `SKIP_TABLE` rows at the new pin: attempt each unit's build under its lane's toolchain; a row whose unit now builds is removed from `derive_registry.py` with the probe evidence recorded, a row still failing stays with its reason. Verify warmth: the pinned cheribuild emulator, the CHERI disk images (sha256-pinned), `build/riscv64/` kernel/rootfs, and `build/riscv64-nemu/` platform caches.
   → coder verify (auto): `bash -c '. ./env.sh && echo $BENCH_COMMIT'` prints the new pin; `git -C benchmark rev-parse HEAD` equals it; the envelopes are absent; `git status --short` shows no `__pycache__`; the skip probe's per-row log is on disk
2. **Step 2 (planner/user-hosted):** The nine lane runs at `f4c916a`, one at a time (the lane lock enforces it), each with its fixed log under `./tmp/logs/` and its deploy/run rcs recorded: (i) `x86_64` (run only); (ii) `aarch64` and its three variants (run only); (iii) `riscv64` (deploy will re-stage the corpus at the new pin, then run); (iv) `riscv64-nemu` (deploy re-builds the corpus + image at the new pin, then run); (v) `cheri_riscv64` and `aarch64-morello` (deploy re-stages the corpus at the new pin, then run). Record each stamp path.
   → Evidence: nine new stamps — one per `results/<lane>/` — with deploy rc 0 / run rc 0 per the fixed logs
3. **Step 3 (tester):** Acceptance, classification, comparison, riders: per-stamp classification against the registry meanings; the F2/267 closure line; the MTE rider probes; the skip-row re-check; the comparison snapshot (`...-comparison.md`/`.tsv`) with every divergence traced; every out-of-expect row given a terminal disposition.
   → tester verify: both artifacts on disk; zero unclassified rows; the riders' outcomes recorded (green or filed); the comparison table's every cell attributed
4. **Step 4 (planner):** Docs + commit. `README.md`: the pins row becomes a single uniform `f4c916a` row and the mixed-pin qualifications (the pins table's parenthetical, the "predate the bump" clauses in Known caveats) are consolidated against the new stamps; the Known-caveats text re-marked against the new stamps (the F2 row stays open — the pin did not close it; the aarch64-mte lane's MTE claim gains an honest caveat); `doc/lanes.html`: the pin rationale refreshed; `.gitignore`: `.claude/` ignored wholesale; record the retirements (the two envelopes, pycache) and the F2 falsification + bench delivery in the plan's History and Issue Log; commit (the repo's hooks: `git -C benchmark rev-parse HEAD` == `BENCH_COMMIT`, submodule clean).
   → Evidence: doc-structure gate PASS; README shows one pin and no stale mixed-pin clause; the hook checks green at commit

## Guidance for Planner

- **Files to modify (docs):** `./README.md`, `./doc/lanes.html`, `./.gitignore` (the `.claude/` entry).
- **Retirement list:** the two pending envelopes (bench copies verified to exist first) ✔ retired by Step 1; `pycache-not-ignored` ✔ retired by Step 1 (verified). Still to retire at closure: `claude-dir-untracked` (on the Step 4 ignore landing; its plan-scoped report is deleted with the row), and the superseded plan-scoped MTE duplicate — `rm` is denied to the session, so hand the user `! rm /home/wsong83/proj/xiangshan/cpu-sec-test-env/tmp/reports/2026-10-24-uniform-pin-comparison-snapshot-mte-lane-pin-not-in-effect.json`. `submodule-pin-unverified` and `lane-script-hardening-batch` stay open (their remaining scopes are the sibling lanes' scripts, not this cycle's).
- **The comparison artifact** is machine-local (`tmp/verification/`); announce in Final Results where it lives and that a durable doc page is a follow-up decision.
- **Successors to name in Final Results:** the bench workstreams delivered this cycle (the platform-fixes cycle — cpio `--reproducible`, the `-dirty` marker, the scratch-tree redesign; the cfi delivery defects; the F2 re-open) + the NEMU-lane-only re-run afterwards; the new env cycle for the aarch64-mte lane (repair or drop the claim, name the drop point with one instrumented lane re-run); and the Morello `260` guest-side verification that gates any declaration.

## History

| Date | Event | Conclusion | Dismissed |
|------|-------|------------|-----------|
| 2026-10-24 | Initial plan | Researcher-drafted: the return-code plan's named successor; nine-lane re-run at `f4c916a`, classification against the new meaning-carrying registry, the comparison snapshot, the two MTE riders, and the envelope/pycache retirements. | — |
| 2026-10-25 | Intent verification + dispositions | The user's directive — check whether each out-of-expect value really is the case's designed result on its platform, before declaring anything — executed against the deployed corpora: `214`/`50` are one delivery defect (label-address low byte), `262` a mis-aimed RA write caught by main's canary, F2/267 re-confirmed as a real defect, cheri's declared `1` vacuous, `260` held; a structural scan reviewed the whole 16-source label family on the riscv64 corpus and found exactly the one genuine defect. Dispositions: fix-first to the bench (two delivered tracker items), MTE to a new env cycle (standalone deferral), `.claude/` ignored wholesale in Step 4. | The plan's F2 closure premise and the "declare four codes" framing; the earlier `-42` and 32+18 readings of `214`/`50` |

## Plan Metadata

```json
{
  "plan_id": "2026-10-24-uniform-pin-comparison-snapshot",
  "steps": ["Step 1: Pin bump + housekeeping (envelopes, pycache, skip re-validation, warmth)", "Step 2: Nine lane runs at the new pin (planner/user-hosted)", "Step 3: Acceptance + classification + comparison snapshot + riders (tester)", "Step 4: Docs sync + retirements + commit (planner)"],
  "coder_files": ["./env.sh", "./scripts/common/derive_registry.py", "./.gitignore"],
  "tester_files": ["./tmp/verification/2026-10-24-uniform-pin-comparison.py", "./tmp/verification/2026-10-24-uniform-pin-comparison-classification.json", "./tmp/verification/2026-10-24-uniform-pin-comparison.tsv", "./tmp/verification/2026-10-24-uniform-pin-comparison.md"],
  "doc_files": ["./README.md", "./doc/lanes.html"],
  "verification_scripts": ["./tmp/verification/2026-10-24-uniform-pin-comparison.py"],
  "repo_mode": "Public",
  "document_overrides": []
}
```

## Audit Accumulation

| Counter | Value | Last Updated |
|---------|-------|--------------|
| issues_resolved_since_audit | 3 | 2026-10-25 |
| steps_changed_since_audit | 1 | 2026-10-25 |
| files_changed_since_audit | 5 | 2026-10-25 |

## Documentation

Documentation owned by the planner (Step 4): `./README.md` (the uniform pins row; the Known-caveats re-marking; the aarch64-mte caveat — the lane's `max,mte=on` claim is unbacked by live evidence, so the caveats must describe what the lane actually exercises until a new env cycle repairs or drops the claim), `./doc/lanes.html` (pin rationale), `./.gitignore` (the `.claude/` ignore, per the user's 2026-10-24 policy decision). `./CLAUDE.md` needs no change (it never restates pin values; the lane set is unchanged) — though its Rules bullet listing machine-local trees will gain `.claude/` once the ignore lands, if the wording still reads exhaustively.

## Final Results

**Delivered.** All nine lane configurations carry a stamp at the uniform pin `f4c916a` (deploy rc 0 / run rc 0, submodule clean, 246 records each; map `./tmp/logs/2026-10-24-uniform-pin-comparison-snapshot-stamps.tsv`), and the cycle's headline artifact is the cross-lane comparison snapshot (`./tmp/verification/2026-10-24-uniform-pin-comparison.md` + `.tsv` + `-classification.json`): per-category 0/declared/out-of-expect tables, 442 divergences from the `x86_64` reference each carrying both codes and their declared meanings, 8/8 out-of-expect rows classified and disposed. Docs synced: README's pins table is one uniform row, its caveats re-marked against the new stamps (plus the honest aarch64-mte claim caveat), `doc/lanes.html` refreshed, `.claude/` ignored wholesale (`.gitignore` + `CLAUDE.md`).

**Findings and dispositions (all user-decided, 2026-10-25).**

- F2/267 is **not closed** by the pin: both riscv64 venues still deliver 267, the crash reproduces on the deployed corpus at the case's own attack jump (`jr t0`), and the declared 1 is unreachable. Delivered to the bench tracker as `defer-issue-f2-267-not-closed.json`.
- The four undeclared statuses are **case-delivery defects, not missing declarations** (the user's intent check, executed against the deployed corpora): 214/50 are one defect — the landing block's delivery lost its argument, so the status is the label address's low byte, an address fragment that changes per rebuild and can never be declared; 262 is a mis-aimed RA write caught by main's canary; and cheri_riscv64's *declared* `cfi-return-without-call`=1 is **vacuous** (the lane records no `frame-size`, so the case returns before attacking). Delivered as `defer-issue-cfi-delivery-defects.json`; 260 (Morello) is held for one guest-side observation before any declaration. The completeness scan (16-source label family × per-binary landing-block review) found exactly the one genuine delivery defect on riscv64.
- The aarch64-mte lane's MTE claim is unbacked (the pin is rejected by this host's qemu-aarch64; the lane's 246 verdicts match the plain lane's, record for record) and both MTE riders are unprovable on it — deferred to a new env cycle as the standalone deferral `./tmp/reports/defer-issue-mte-lane-pin-not-in-effect.json`.

**Boundaries.** The comparison artifact is machine-local (`tmp/verification/`); a durable doc page is a follow-up decision once the table stabilizes. The bench-side fixes and any declaration decision are bench-repo work; the env lane harness needed no change for any finding.

**Successors.** The bench workstreams delivered this cycle (the platform-fixes cycle — cpio `--reproducible`, the `-dirty` marker, the scratch-tree redesign; the cfi delivery defects; the F2 re-open) plus the NEMU-lane-only re-run afterwards; the new env cycle for the aarch64-mte lane (repair or drop the claim, naming the drop point with one instrumented lane re-run); and the Morello `260` guest-side verification that gates any declaration.