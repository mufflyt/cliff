# Workforce-Cliff Manuscript — Session Handoff (2026-07-19)

Branch: `fix/workforce-cliff-data-contract` (in sync with origin)
Tip commits: `0f10e59f6` (test reconciliation) → `0da3a494e` (MIGS exclusion) → `8a1005fcc` (round-4 text).

## Current headline (authoritative)

Primary age-band departure hazard pools **GO + ABOG-URPS only** (MIGS excluded, PI
decision 2026-07-19, reviewer #1). Completion-to-departure ratios:

| Cohort | Baseline 2025 | Projected 2029 | Ratio | Rate |
|--------|---------------|----------------|-------|------|
| GO     | 1052 | 1309.8 | **7.11** | 1.00% |
| URPS (both-pathway) | 1295 | 1505.4 | **5.61** | 0.88% |
| MIGS (exploratory)  | 605  | 776.0  | 11.06 | 0.70% |

Both board-certified cohorts remain well above replacement; qualitative conclusion
unchanged. Was 7.35 / 5.83 before the MIGS exclusion. Primary pooled hazard = 71
events (GO 36 + URPS 35); MIGS-inclusive = 81 (Appendix S6b sensitivity only).

## What is DONE (peer-review rounds 1–4)

- Rounds 1–3: classifier/anchor/hazard reconciliation, title → "Fellowship Pipeline
  Balance", fabricated classifier tables replaced with the real consensus+anchor gate,
  ABU flow (270→6→264), sensitivity-grid labels, etc.
- Round 4 decision-independent text fixes (#2,#3,#5,#6,#7,#8,#10,#11): ordering caveat,
  pooled-hazard-implied rate wording, removed internal drafting notes, graduates =
  training output, abstract conclusion softened, external comparison made descriptive,
  omitted-uncertainty list expanded, tipping point conditioned.
- Round 4 #1/#9: **MIGS excluded from the primary hazard** (this session). Five
  producers restricted to `which(coh$ab %in% c("GO","URPS"))`:
  `rebuild_ssot_revised.R`, `build_audit_table.R`, `build_hazard_comparison.R`,
  `age_shift_sensitivity.R`, `dynamic_stockflow_projection.R`. Full downstream cascade
  regenerated and reconciled; manuscript + supplement re-rendered clean.
- Test suites all green: data-analysis 272, data-bva 50, data-properties 166,
  data-resilience 64, step5-contract 36, peer-review 130 pass / **3 skip**.

## OUTSTANDING ISSUES (resume here)

### 1. BLOCKED on signals DuckDB (Full-Disk-Access / TCC) — highest priority
The signals DB `/Volumes/MufflySamsung 1/DuckDB/nber_my_duckdb.duckdb` is `EPERM`
("Operation not permitted") from this Claude Code session even with sandbox disabled —
a macOS TCC block on the host terminal (Ghostty). **Fix: grant Ghostty Full Disk Access
in System Settings → Privacy, then Cmd-Q and relaunch Ghostty** (the grant is captured
at process launch). `dangerouslyDisableSandbox` does NOT help (it is TCC, not the
harness sandbox). Until then these three remain undone:

- **#4B Death correction.** No board-confirmed deaths are folded in
  (`consort_cohort_flow.csv` `removed_deceased = 0` for all cohorts). Missed deaths
  leave deceased physicians in the active stock and drop true departure events →
  **lowers the estimated hazard and inflates the ratio** (known directional error,
  now disclosed in Limitations). Need: the board-confirmed death list, fold into the
  hazard life table + baseline, re-run.
  - Test that auto-activates: `R4#4B` expects `consort_cohort_flow.csv$removed_deceased > 0`.

- **#4C Consistent-definition baseline rerun.** The active baseline uses the
  multi-source cohorting classification; historical outflow events require a
  non-Open-Payments anchor. These are not identical (a stock-flow consistency gap).
  Need: regenerate the 2025 stock under the anchored departure rule and compare.
  - Test that auto-activates: `R4#4C` expects `cliff/data/consistent_definition_baseline_sensitivity.csv`.

### 2. BLOCKED on human chart review
- **#4A Physician-level adjudication.** Two-reviewer chart adjudication is the biggest
  measurement-validity gap. Sample + instrument exist
  (`cliff/data/classifier_adjudication_sample.csv`) but results are pending. Must report
  PPV among classified departures, false-negative rate among active controls,
  reviewer agreement (kappa), departure-year accuracy, and adjudication-corrected
  hazards/ratios. Cannot be fabricated.
  - Test that auto-activates: `R4#4A` expects `cliff/data/classifier_adjudication_results.csv` with `ppv`/`kappa` columns.

### 3. QUEUED code fix (PI-gated, manuscript-impacting) — NOT applied
**Criterion 7 off-by-one:** `R/apply_cohort_inclusion_exclusion_criteria.R:2305` and
`:2309` use `ret_year <= config$start` (and `abms_ret_year <= config$start`). With
`config$start == 2013` this wrongly excludes physicians with `retirement_year == 2013`,
violating Criterion 7 ("retired before study" = `retirement_year < 2013`, strict `<`).
The function's own audit message (line 2330) and docstring say `< cohort_start_year`, so
the code contradicts its documented intent. One-line fix: `<=` → `<` on both lines.
- Does NOT affect the frozen workforce-cliff SSOT now (cliff scripts read the frozen
  `table1_physician_characteristics.csv`), but a from-scratch rebuild would add 2013
  retirees back and shift baselines → the drift pins would (correctly) trip.
- When applied: pair with a BVA regression test (`ret_year == 2013` kept,
  `ret_year == 2012` excluded). Related existing guard:
  `tests/testthat/test-retirement-criterion7-silent-disable.R`.

### 4. Presentation / length (round-4, not yet done — cosmetic)
- Abstract ~422 words; reviewer suggests trimming 75–100 (shorten operative sentence,
  reduce sensitivity-grid detail, drop qualifications repeated in the Conclusion).
- Main text ~6,341 words (Intro→Conclusion) — condense the repeated headcount-vs-capacity
  explanation after the pending analyses land.
- Table 2 headings split awkwardly on page 15 — consider landscape or shorter headings
  ("2029 immediate entry", "2029 Medicare-timing adjusted", "95% interval: immediate
  entry", "Completion/departure ratio").

## Reproduction recipe (regenerate the SSOT cascade)

Inputs live in the SIBLING checkout `/Users/tylermuffly/isochrones/` (table1, ABU
crosswalk); outputs write to THIS worktree's `cliff/data/`. Run in order:

```bash
cd /Users/tylermuffly/isochrones-workforce-cliff
Rscript scripts/rebuild_ssot_revised.R          # SSOT + window sens + NRMP benchmark
Rscript scripts/build_hazard_comparison.R       # Appendix S6b (pooled GO+URPS + incl_migs sensitivity)
Rscript scripts/build_audit_table.R             # reconciler; primary row must == SSOT
Rscript scripts/age_shift_sensitivity.R
Rscript scripts/sensitivity_grid.R
Rscript scripts/breakeven_thresholds.R
Rscript scripts/graduation_to_active_transition.R
Rscript scripts/dynamic_stockflow_projection.R
# open_payments_sensitivity.csv has NO script producer — regenerate its two rules
# (non_op_anchored primary = SSOT; op_inclusive = audit "OP-inclusive consensus") by hand/snippet.
# Render:
cd manuscript && Rscript -e 'rmarkdown::render("manuscript_WORKFORCE_CLIFF.Rmd")'
Rscript -e 'rmarkdown::render("supplement_WORKFORCE_CLIFF.Rmd")'
```

After any headline change, update the drift pins: `PIN_RATIO` and E1/E2 in
`test-workforce-cliff-data-analysis.R`; SNAP signature + getter strings + mutation
invariant in `test-workforce-cliff-data-properties.R`; gold-standard hand-calcs in
`test-workforce-cliff-data-resilience.R`; the round-1/2 headline guard + hazard counts
in `test-workforce-cliff-peer-review-fixes.R`. **Always run the FULL testthat file**
(not just direct data checks) — direct checks missed 5 stale pins this session.

## Test suites (workforce-cliff)

- `test-workforce-cliff-data-analysis.R` (272) — SSOT identities, contract validator
  adversarial, getters, cross-file reconciliation, hazard decomposition, grid, breakeven,
  CONSORT, classifier, operative, comparator, LOSO, dynamic, NRMP.
- `test-workforce-cliff-data-bva.R` (50) — boundary value analysis on classify cutoffs
  (0.95/1.05), validator guards, tolerances, sign boundary.
- `test-workforce-cliff-data-properties.R` (166) — invariant/cardinality/idempotency/
  snapshot/boundary/temporal/statistical/mutation/metamorphic.
- `test-workforce-cliff-data-resilience.R` (64) — metamorphic/chaos-fault-injection/
  gold-standard/production-schema.
- `test-workforce-cliff-peer-review-fixes.R` (130 pass / 3 skip) — one test per review
  item across rounds 1–4; the 3 skips (R4#4A/#4B/#4C) auto-activate when the blocked work lands.
- `test-step5-manuscript-contract-interface.R` (36) — pure Step-5 contract tests
  (data_contracts.yml ↔ pipeline_registry.yml ↔ 05_generate_manuscript_inputs.R).

Run one: `Rscript -e 'testthat::test_file("tests/testthat/<file>.R")'` (each carries
~2–3 min of project-wide setup; run singly to avoid CPU contention).

## Housekeeping notes

- Working tree has uncommitted test byproducts (`data/checksums/manifest.csv`,
  `tests/testthat/RESTORATION_TEST_DIR/*`, `tests/testthat/_snaps/*.new.md`) from a
  full-suite run — NOT our work; left untouched. Safe to `git checkout` / delete.
- The full 4607-file testthat run was never completed (killed for CPU contention); most
  of it is gated on the DuckDB/Valhalla/external-volume that are unavailable here anyway.
- Standing rules honored: no em/en dashes in prose; "proceed"/bare words ≠ push approval
  unless the action is named; this machine = runner/truth; commit-first, stage only own
  files; never `git pull --rebase --autostash`; never bare `git stash pop`.
