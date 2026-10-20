# Plan: Initialize cpu-sec-test-env's CLAUDE.md and its doc surface
**Project:** /home/wsong83/proj/xiangshan/cpu-sec-test-env
**Plan ID:** 2026-10-20-initialize-claudemd-and-doc
**Created:** 2026-10-20

## Issue Log

| Issue | Status | Found | Resolved | Resolved By |
|-------|--------|-------|----------|-------------|
| [initialize-claudemd-and-doc](../reports/defer-issue-initialize-claudemd-and-doc.json) — the input deferral: the repo has no root `CLAUDE.md` (tracked or local), so `/update-and-commit` Steps 2/7/8 had nothing to act on and the Phase-6 documentation reconciliation had only `README.md`; the tracked-CLAUDE.md question was asked 2026-10-13 and again 2026-10-14 without an answer, and the doc surface (`README` + `plans/` vs a `doc/` tree) was undecided. Resolved by this cycle on the user's 2026-10-20 decisions. | Resolved | 2026-10-20 | 2026-10-20 | planner |

## Guidance for Coder

**No coder steps — this is a planner-only documentation plan.** `./CLAUDE.md` and `./doc/**` are planner-owned by doctrine; this plan changes no source, script, config or Makefile file. Do not launch a coder round.

## Guidance for Tester

**No tester steps.** No test obsolescence identified (no source behavior changes; the `doc/` gate's mechanism is the committed checker, not a test). Do not launch a tester round.

## Summary

**Problem.** The deferral `initialize-claudemd-and-doc` (filed 2026-10-20, Batch C, machine-local) records three things: (1) the public-Claude-tooling question — whether the repo should track a root `CLAUDE.md` that explicitly addresses Claude Code — has been asked twice (2026-10-13, 2026-10-14) and never answered, and per the global rule it cannot be decided unilaterally; (2) the repo therefore has no CLAUDE.md at all, leaving `/update-and-commit`'s CLAUDE.md steps (read, Documentation section, content refresh) and the Step 9 project hooks with nothing to operate on; (3) the doc surface is undecided — `README.md` (user reference) plus the archived `plans/` (design record) currently carry everything, whereas the sibling `cpu-sec-bench` repo documents itself with an HTML `doc/` tree.

**Decisions (user, 2026-10-20, Phase-3 discussion).**

1. **Track it (bench-style):** the root `CLAUDE.md` is committed and pushed, explicitly Claude-facing — the same posture as `benchmark/CLAUDE.md` in the sibling repo. The question pending since 2026-10-12 is thereby answered in the affirmative.
2. **Doc surface — both:** `README.md` and `plans/` stay, **and** a new `doc/` HTML tree is added (bench-style).
3. **doc/ scope:** 3 pages + stylesheet — `doc/content.html` (landing/index), `doc/architecture.html` (dispatcher internals, keep in sync), `doc/lanes.html` (per-lane reference, keep in sync), `doc/style.css`.
4. **Update-and-Commit hooks — all four:** pin sync; lane/target sync; the pre-commit submodule-at-pin + clean check; the deferral record/retire norm. (The submodule check is the *manual* counterpart of the still-deferred `submodule-pin-unverified` script-side assert — that deferral stays deferred and untouched.)

**Approach.** A planner-only cycle in four steps: write the compact root `CLAUDE.md` (bench-shaped: Purpose / Rules / Structure / Commands / Architecture / Documentation / Update and Commit / Subagents); create the four-file `doc/` tree authored to the committed `/doc-structure` rules; run the committed checker (`doc_structure_check.py --mode public`) as the doc gate and fix any violations; close out — Issue Log row to Resolved, `## Final Results` carrying the deferral's identity text (captured before deletion), a Cross-References row to the 2026-10-12 plan's deferred CLAUDE.md text, retirement of the report handed to the user as one `! rm` (rm is deny-listed in this session), and `/update-and-commit`.

**Content split (no wholesale duplication).** `CLAUDE.md` is the Claude-facing quick reference (rules, commands, structure, hooks — the invariants a session must not break). `README.md` stays the operator reference and is **not rewritten** (it was refreshed through the 2026-10-19 cycle). `doc/` carries the maintainer-level narrative the two others lack: dispatcher internals in depth (`architecture.html`) and the per-lane mechanics consolidated (`lanes.html`); `content.html` is the index. Both doc pages carry keep-in-sync markers; `README`'s sync contract is expressed by the Update-and-Commit hooks.

**Alternatives rejected.** Local-only CLAUDE.md via `.git/info/exclude` (user chose tracked — bench precedent; the org is already public about it). `doc/` bench-parity with a `porting.html` (3 pages is right-sized; a porting page can be added later by a small plan). Minimal `doc/` (landing only) — rejected by the user in favor of the three-page shape. Dropping the submodule-at-pin hook (user kept all four).

**Out of scope.** No source/script/Makefile/env.sh change; `README.md` content untouched; the three other open deferrals (`lane-script-hardening-batch`, `pycache-not-ignored`, `submodule-pin-unverified`) — untouched; no `.claude/mega-audit-files.json` (this repo declares none — the 2026-10-12 plan's "Do not create the file" stands).

## Repo Mode

Public

## Document Overrides

| Document | Rule Overridden | Reason |
|----------|----------------|--------|

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| A `doc/` tree activates the `/doc-structure` gate on every future commit in this repo | a future commit's gate can fail on doc/ drift | pages authored to the committed checker's rules; the gate is run in Step 3 and its evidence recorded; keep-in-sync markers + the Update-and-Commit hooks name every sync target |
| A tracked CLAUDE.md makes the public repo explicitly about Claude tooling | public disclosure of the tooling posture | this is the user's explicit 2026-10-20 decision (bench-style precedent, same org) — recorded in Summary and `## Final Results` |
| Three prose surfaces (`README`, `CLAUDE.md`, `doc/`) can drift apart | contradictory docs | keep-in-sync markers on both content pages; hooks 1–2 name the exact files to update per change class |

## Proposed Changes

1. **Step 1:** Create the `doc/` tree (planner-only; bench house style — `<!DOCTYPE html>`, `<meta name="last-modified">`, `<title>`, `<link rel="stylesheet" href="style.css">`, relative cross-links only, a `Last updated:` footer): `doc/content.html` (landing — what the repo is, the lane table with each lane's execution model, and the index of the tree plus relative links to `../README.md` and `../plans/`), `doc/architecture.html` (dispatcher internals: the dispatch flow, the lane-lock protocol and publish rule, `env.sh` pin doctrine, corpus builder + derived registry, the aarch64 shim, result stamps and provenance `versions.txt`/`manifest.json`, the trust-boundary rationale), `doc/lanes.html` (per-lane reference table: execution path, prerequisites, deploy/run specifics, boot mechanics — riscv64 `-bios default` + external `-kernel` + `rva23s64`; cheri_riscv64 bbl firmware + `rv64,sstc=off`; aarch64-morello UEFI + `loader(8)` with no `-kernel` — and the load-bearing traps), `doc/style.css` (minimal shared stylesheet, no reserved class names needed here).
   → Evidence: the four files exist (`ls doc/`); `./tmp/verification/2026-10-20-initialize-claudemd-and-doc-step1.py` exits 0 printing `PASS step1` (proven red before the write), checking file existence and that every relative `<a href>` target in every `doc/*.html` resolves on disk — link *form* rules are deliberately left to the committed checker (no ad-hoc re-implementation). Authored first because CLAUDE.md's Documentation section links into this tree (the CLAUDE.md link check needs the targets on disk).

2. **Step 2:** Write the root `./CLAUDE.md` (planner-only, ~90 lines, bench-shaped). Sections and load-bearing content: **Purpose** (one paragraph — the lane dispatcher for `cpu-sec-bench`; the five lane families; `benchmark/` consumed read-only at the `env.sh` pin). **Rules** (one-lane-at-a-time advisory flock on `build/.lane.lock` with fail-fast naming the holder, and the publish rule — every lane collects artifacts + cleans + verifies the submodule clean, a timeout exits 124 and publishes nothing; all pins live in `env.sh` only — scripts and the Makefile never hard-code them, and this file never restates pin values; `benchmark/` read-only at `BENCH_COMMIT` — bench changes happen in the bench repo, consumed by a pin bump; `build/`/`results/` gitignored and `tmp/` machine-local — never commit; deferred issues live as `./tmp/reports/defer-issue-*.json`, presence = open, never create or delete a report by hand). **Structure** (the top-level map + the six `scripts/` subdirectories). **Commands** (the `make ARCH=<lane> [enable_aarch64_<pa\|bti\|mte>=yes] <deploy\|run\|clean\|dump>` form; ARCH defaults to the host; host lanes' `run` does everything, riscv64/CHERI are deploy-then-run; the timeout layering incl. `CHERI_BUILD_TIMEOUT`; `dump` exists on x86_64/aarch64, not riscv64). **Architecture** (dispatcher flow Makefile→`scripts/<lane>/`; the derived registry declares per-lane expected failures at deploy time, never hard-coded; the corpus builder and the aarch64 objdump shim; the VM lanes' virtio-9p result extraction; the trust boundary — host lanes run the adversarial corpus unsandboxed, deliberately and only on this workstation; VM lanes boot `-snapshot`). **Documentation** (lists `README.md`, `plans/`, and the four `doc/` files with keep-in-sync annotations). **Update and Commit** (the four hooks, verbatim in intent from the approved preview). **Subagents** (lane boundaries: coder = `scripts/`, `Makefile`, `env.sh`; tester = `./tmp/verification/` + run evidence; planner = `README.md`, `CLAUDE.md`, `doc/**`; bench-side work belongs to the bench repo).
   → Evidence: `./tmp/verification/2026-10-20-initialize-claudemd-and-doc-step2.py` exits 0 printing `PASS step2` (proven red before the write — exits 1 naming the missing file; run after Step 1 so the `doc/` link targets exist); the script checks the exact section set, resolvable repo-relative markdown links, the load-bearing markers (`build/.lane.lock`, `env.sh`, `tmp/`, `/defer-issue`, `benchmark/`), the Documentation section's five required references, and the pin-restatement guard (no 40-hex token at all in the file)

3. **Step 3:** Run the doc-structure gate from the repo root: `python3 ~/.claude/scripts/doc_structure_check.py --mode public`. Fix any violations (content files must be `.html`; `content.html` + `style.css` present; stylesheet linked from every page; relative hrefs only; non-empty `<title>`; a last-modified indicator per page), re-running until pass (max 3 fix loops, then skip/abort per the command).
   → Evidence: the checker's output — `## Doc-Structure: PASS` with its file count (4) — captured verbatim; NOTE lines (if any) do not fail the gate and are reported as-is. The committed checker IS the mechanism (per the global Verification-and-Audits rule); no custom checker is written.

4. **Step 4:** Close out (planner). Flip the Issue Log row to Resolved. Write `## Final Results` — **before any deletion**, capture the deferral report's `issue_id`, `title` and verbatim `problem` into it (the report is untracked; deletion is irreversible and the archived plan is the only surviving record) — plus the decisions record, the gate evidence, and the History rows for this cycle (the substitute evidence for absent coder/tester reports is the planner's own verification, per Phase 6). Add the `## Cross-References to Prior Plans` row: prior plan `2026-10-12-test-env-all-archs`, deferred text — the quoted "Optional, needs your explicit approval at plan review: a repo-level `./CLAUDE.md` (project instructions for future agent sessions)" — resolution: written and tracked on the user's 2026-10-20 decision, with the doc surface settled in the same cycle. Retire the report: `rm` is deny-listed in this session, so hand the user exactly one `! rm /home/wsong83/proj/xiangshan/cpu-sec-test-env/tmp/reports/defer-issue-initialize-claudemd-and-doc.json` and record the handover in the commit summary. Then run `/update-and-commit` (stages `CLAUDE.md`, `doc/**`, the archived plan copy + `plans/content.json`; commit message per its Steps; `Plan: ./plans/2026-10-20-initialize-claudemd-and-doc.md` footer).
   → Evidence: the Issue Log row reads Resolved; `## Final Results` carries the report's identity + verbatim problem and the four decisions; the `! rm` handover line is in the commit summary; `git log -1 --stat` shows `CLAUDE.md` + `doc/` + the plan archive in the plan's single commit with the `Plan:` footer

## Guidance for Planner

Documentation tasks you will execute yourself (not the coder):

- **Files to modify:**
  - `./CLAUDE.md`
  - `./doc/content.html`
  - `./doc/architecture.html`
  - `./doc/lanes.html`
  - `./doc/style.css`
- **`.claude/mega-audit-files.json`:** this repo declares none and the plan adds none — do not create the file (the 2026-10-12 plan's standing instruction).
- **When:** Steps 1–3 in this session, before the Phase 6 review; Step 4 after the review returns.
- **What to sync:** CLAUDE.md's Rules/Commands/Structure must match the Makefile header, `env.sh` and the `scripts/` tree as they stand today (line-level facts taken from README + Makefile, not invented); the doc pages' keep-in-sync markers name the Makefile + `scripts/` (architecture) and `env.sh` + `scripts/` (lanes); the pin-restatement guard means CLAUDE.md never carries a full SHA — README keeps the restated pins and is kept in sync by the hooks instead.
- **Loop caps / gates:** mega-audit **not triggered** (4 steps, 0 source files — below the ≥5 trigger). The doc-structure gate's fix loops: max 3, then skip/abort.

## History

| Date | Event | Conclusion | Dismissed |
|------|-------|------------|-----------|
| 2026-10-20 | Initial plan | Resolves the `initialize-claudemd-and-doc` deferral on four recorded user decisions (tracked bench-style CLAUDE.md; README + plans kept *and* a doc/ tree; 3 pages + css; all four Update-and-Commit hooks); planner-only, 4 steps, no mega-audit (below trigger), two step scripts proven red. | — |
| 2026-10-20 | Planner action (Steps 1–3) — `doc/` tree and root `CLAUDE.md` written; both step scripts green; doc-structure gate PASS | The four `doc/` files (`content.html` 84 lines, `architecture.html` 111, `lanes.html` 148, `style.css` 59) and the 123-line root `CLAUDE.md` are on disk (untracked; `git status --short` shows `?? CLAUDE.md`, `?? doc/`). Evidence: `./tmp/verification/2026-10-20-initialize-claudemd-and-doc-step1.py` → `PASS step1` (four files present; every relative `<a href>` target resolves; proven red pre-write), `...-step2.py` → `PASS step2` (agreed section set, resolvable markdown links, load-bearing markers, Documentation refs, pin-restatement guard; proven red pre-write), and the committed checker `python3 ~/.claude/scripts/doc_structure_check.py --mode public` → `## Doc-Structure: PASS`, 4 files checked, no violations, rc=0 (re-run on the final tree). The gate's advisory PostToolUse hook flagged the not-yet-written `style.css` mid-creation (the known first-run note) and cleared on the checker run. Step order swapped from the draft (doc/ first) because CLAUDE.md's link check needs its `doc/` targets on disk — a mechanical ordering fix, recorded here. | — |
| 2026-10-20 | Review | Phase 6 reviewer verdict `Issues found — non-blocking`: 0 Critical, 6 Warning, 8 Suggestions — report [2026-10-20-initialize-claudemd-and-doc-review-2026-10-20.json](./tmp/reports/2026-10-20-initialize-claudemd-and-doc-review-2026-10-20.json). All six Warnings were factual over-claims in the five new files, each traced to code by the reviewer and re-verified by the planner against the Makefile/scripts; with 5+ Warnings present the user confirmed the disposition (2026-10-20) and a single editing pass fixed all six plus seven Suggestions, after which both step scripts re-ran green and the committed gate re-printed PASS. One hunch was disproved with independent evidence: all four aarch64 stamps (`results/aarch64/*/`) carry no `variables.json`, so README's parenthetical is accurate. | Warnings (all fixed in-pass, verified valid): [w-sysinfo-riscv64-scope](./tmp/reports/2026-10-20-initialize-claudemd-and-doc-review-2026-10-20.json), [w-deploy-registry-corpus-scope](./tmp/reports/2026-10-20-initialize-claudemd-and-doc-review-2026-10-20.json), [w-riscv64-share-vs-stamp](./tmp/reports/2026-10-20-initialize-claudemd-and-doc-review-2026-10-20.json), [w-aarch64-prepare-corpus](./tmp/reports/2026-10-20-initialize-claudemd-and-doc-review-2026-10-20.json), [w-lock-claim-dump-exception](./tmp/reports/2026-10-20-initialize-claudemd-and-doc-review-2026-10-20.json), [w-timeout-host-deploys](./tmp/reports/2026-10-20-initialize-claudemd-and-doc-review-2026-10-20.json). Suggestions fixed: [s-cheri-dump-refusal](./tmp/reports/2026-10-20-initialize-claudemd-and-doc-review-2026-10-20.json), [s-doclist-style-css](./tmp/reports/2026-10-20-initialize-claudemd-and-doc-review-2026-10-20.json), [s-x86_64-inline-lane](./tmp/reports/2026-10-20-initialize-claudemd-and-doc-review-2026-10-20.json), [s-lanes-pin-absolutism](./tmp/reports/2026-10-20-initialize-claudemd-and-doc-review-2026-10-20.json), [s-hook2-doc-pages](./tmp/reports/2026-10-20-initialize-claudemd-and-doc-review-2026-10-20.json), [s-prereqs-host-toolchain](./tmp/reports/2026-10-20-initialize-claudemd-and-doc-review-2026-10-20.json), [s-trap-run-bodies](./tmp/reports/2026-10-20-initialize-claudemd-and-doc-review-2026-10-20.json). Acknowledged, not fixed: [s-porting-ref-comment](./tmp/reports/2026-10-20-initialize-claudemd-and-doc-review-2026-10-20.json) (a script-comment cross-reference — coder lane; candidate for the `lane-script-hardening-batch` deferral), [h-trap-rc-on-failure](./tmp/reports/2026-10-20-initialize-claudemd-and-doc-review-2026-10-20.json) (exit-code precedence on failure paths only). Disproved: [h-readme-variables-json](./tmp/reports/2026-10-20-initialize-claudemd-and-doc-review-2026-10-20.json) (stamp evidence above). |

## Plan Metadata

```json
{
  "plan_id": "2026-10-20-initialize-claudemd-and-doc",
  "steps": ["Step 1: Create the doc/ tree (content, architecture, lanes, style)", "Step 2: Write the root CLAUDE.md", "Step 3: Run the doc-structure gate", "Step 4: Close out — Issue Log, Final Results, deferral retirement, commit"],
  "coder_files": [],
  "tester_files": [],
  "doc_files": ["./CLAUDE.md", "./doc/content.html", "./doc/architecture.html", "./doc/lanes.html", "./doc/style.css"],
  "verification_scripts": ["./tmp/verification/2026-10-20-initialize-claudemd-and-doc-step1.py", "./tmp/verification/2026-10-20-initialize-claudemd-and-doc-step2.py"],
  "repo_mode": "Public",
  "document_overrides": []
}
```

## Audit Accumulation

| Counter | Value | Last Updated |
|---------|-------|--------------|
| issues_resolved_since_audit | 0 | 2026-10-20 |
| steps_changed_since_audit | 0 | 2026-10-20 |
| files_changed_since_audit | 0 | 2026-10-20 |

## Documentation

Documentation owned by the planner: `./CLAUDE.md` (new, tracked on the user's decision) and `./doc/{content,architecture,lanes}.html` + `./doc/style.css` (new, subject to the committed doc-structure gate). `./README.md` is deliberately unchanged. Keep-in-sync markers: `doc/architecture.html` ↔ Makefile + `scripts/`; `doc/lanes.html` ↔ `env.sh` + `scripts/`; the README sync contract lives in CLAUDE.md's `## Update and Commit` hooks.

## Final Results

**Status:** COMPLETED
**Completed:** 2026-10-20

**What was done (Steps 1–4).** The `initialize-claudemd-and-doc` deferral is resolved on four user decisions taken this cycle (2026-10-20, Phase-3 discussion): (1) the repo tracks a bench-style root `CLAUDE.md` — explicitly Claude-facing, the same posture as `benchmark/CLAUDE.md` in the sibling repo, so the public-tooling question pending since 2026-10-12 is answered in the affirmative; (2) `README.md` and `plans/` stay **and** a new `doc/` HTML tree is added; (3) the tree is three pages + stylesheet (`content.html`, `architecture.html`, `lanes.html`, `style.css`); (4) all four Update-and-Commit hooks are in force — pin sync, lane/target sync (now naming the keep-in-sync doc pages), the pre-commit submodule-at-pin + clean check (the manual counterpart of the still-deferred `submodule-pin-unverified` script assert — that deferral stays deferred and untouched), and the deferral record/retire norm.

New files (the cycle's only tree change; `README.md` deliberately untouched):
- `./CLAUDE.md` — eight sections (Purpose / Rules / Structure / Commands / Architecture / Documentation / Update and Commit / Subagents), pin-restatement-free (the guard is scripted).
- `./doc/content.html`, `./doc/architecture.html`, `./doc/lanes.html`, `./doc/style.css` — bench house style, authored to the committed checker's rules; keep-in-sync markers on the two content pages.

**Evidence.** `./tmp/verification/2026-10-20-initialize-claudemd-and-doc-step1.py` → `PASS step1` (four doc files present; every relative `<a href>` target resolves; proven red pre-write); `...-step2.py` → `PASS step2` (agreed section set, resolvable markdown links, load-bearing markers, Documentation references incl. `doc/style.css`, pin-restatement guard; proven red pre-write); the committed gate `python3 ~/.claude/scripts/doc_structure_check.py --mode public` → `## Doc-Structure: PASS`, 4 files checked, no violations, rc=0 — re-run on the final post-review tree. The execution-time step-order swap (doc/ authored first) is recorded in History.

**Review (Phase 6).** Verdict `Issues found — non-blocking`: 0 Critical, 6 Warning, 8 Suggestions — [report](./tmp/reports/2026-10-20-initialize-claudemd-and-doc-review-2026-10-20.json). All six Warnings were factual over-claims in the five new files; each was traced to code by the reviewer and re-verified by the planner, and with 5+ Warnings present the user confirmed the disposition — one editing pass fixed all six plus seven Suggestions, one Suggestion was acknowledged-not-fixed (a script-comment cross-reference; coder lane), one hunch was disproved with stamp evidence. Post-fix re-verification: both step scripts green, gate PASS. (Warnings/Suggestions are enumerated with linked slugs in the History row.)

**Test results.** No coder or tester rounds — planner-only plan (documentation is the planner's lane; no source change). Substitute evidence, per Phase 6's planner-only tolerance: the History rows above plus the two step scripts and the committed gate.

### Resolved deferral report — identity captured before deletion

**`initialize-claudemd-and-doc`** (env-filed; `plan_id: defer-issue`, Batch C standalone). Title: "Initialize cpu-sec-test-env's CLAUDE.md and decide its doc surface (the tracked-CLAUDE.md question is open)".

> The env repo has no CLAUDE.md — tracked or local — and no doc/ directory. /update-and-commit's CLAUDE.md steps (read, Documentation section, content refresh) had no file to operate on, and the Phase 6 documentation reconciliation had only README.md as a surface. The question of adding a tracked root CLAUDE.md has been asked of the user twice and never answered; per the global CLAUDE.md rule, making a root CLAUDE.md git-tracked requires explicitly asking the user whether the repo should be public about Claude tooling, so it cannot be created unilaterally. Separately undecided: whether the repo wants a doc/ tree at all — its documentation currently lives in README.md (user-facing) plus the archived plans under plans/ (design record), whereas the sibling benchmark repo documents itself with an HTML doc/ tree.

**Retirement.** The report retires with this plan's commit (Issue Log row at Resolved; the archived plan is the surviving record). `rm` is deny-listed in this session, so the deletion is handed to the user as one `! rm /home/wsong83/proj/xiangshan/cpu-sec-test-env/tmp/reports/defer-issue-initialize-claudemd-and-doc.json`, recorded in the commit summary.

## Cross-References to Prior Plans

| Prior Plan | Deferred Issue | Resolution |
|------------|---------------|------------|
| 2026-10-12-test-env-all-archs | "Optional, needs your explicit approval at plan review: a repo-level `./CLAUDE.md` (project instructions for future agent sessions). The global rule requires asking before tracking a root CLAUDE.md in a public repo — ask; if approved, write it after coder completion (compact: layout, lane commands, the `:=`-vs-MAKEFLAGS gotcha, submodule-read-only rule)." | Written and tracked on the user's 2026-10-20 decision (bench-style, Claude-facing), and the doc-surface question settled in the same cycle (README + plans kept, new `doc/` tree). The layout, lane-command and submodule-read-only rules are in `CLAUDE.md`'s Structure/Commands/Rules; the `:=`-vs-MAKEFLAGS route stayed documented at its point of effect (`scripts/aarch64/run.sh` header and the bench's own `doc/porting.html`), not restated in CLAUDE.md. |