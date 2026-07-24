# Handoff: Workforce-Cliff Manuscript — Major-Revision Reviewer Triage

**Date:** 2026-07-19
**Paper:** "The Surgical Workforce Cliff: Gynecologic Subspecialty Retirements Outpace Fellowship Pipeline Despite Training Expansion" (GO + URPS/urogynecology; completion-to-departure headcount-flow analysis).
**Purpose:** Freeze the state of the peer-review triage so work can resume cold in a later session. A reviewer returned a **major-revision-before-submission** verdict with 14 numbered items (4 framed as publication-blocking). This doc records what each item needs, what already exists in code, what is blocked, and the recommended order of attack.

> Reviewer's overall stance (paraphrase): strong, potentially important workforce paper; estimand handling and stock/pipeline alignment are unusually careful; result is directionally robust (ratios far from 1.0). But **do not submit yet** because the primary departure endpoint is provisionally classified, two prespecified analyses are unfinished, and death under-ascertainment biases the headline ratio in the favorable direction.

---

## 0. ACTION ZERO — branch reconciliation (do this FIRST)

The reviewed manuscript and essentially all of the sensitivity machinery are **NOT on the currently checked-out branch.**

- Current working branch: `manuscript/green-journal-bibtex` (HEAD carries an **older 3-arm FPMRS/GO/MIG** version of the cliff paper with *frozen archival* CIs and more policy-forward language).
- The revised paper the reviewer actually read lives on branch **`fix/workforce-cliff-data-contract`**, tip **`0f10e59f6`** ("Fix-forward: reconcile 5 stale round-3 test pins to the MIGS-excluded headline"). Anchor commit referenced in notes: `2fa1aa4aa`.
- Verified: `git merge-base --is-ancestor 2fa1aa4aa HEAD` → **NO**. The data-contract branch is not merged into HEAD.
- The cliff files (`manuscript/manuscript_WORKFORCE_CLIFF.Rmd`, `cliff/data/workforce_projections_consolidated.csv`) exist on BOTH branches but differ: HEAD = stale 3-arm; `fix/workforce-cliff-data-contract` = revised 2-arm.

**Consequence:** Any edits made on `manuscript/green-journal-bibtex` land on stale files. All revision work must be done on `fix/workforce-cliff-data-contract` (or after merging it). Decide the merge/rebase plan before touching anything.

### Which version the reviewer read
Numbers match the `fix/workforce-cliff-data-contract` tip, not HEAD:
- Headline completion-to-departure ratios: **GO 7.11 / URPS 5.61** (branch tip; **MIGS excluded** from the primary pooled hazard). The older `2fa1aa4aa` value was GO 7.35 / URPS 5.83; HEAD/3-arm differs again.
- Empirical annual departure rates ≈ GO 2.0% / URPS 1.8%.
- Baseline active counts: **GO 1,052 / URPS 1,295** (URPS = 1,031 ABOG-pathway + 264 ABU net-new).
- Tipping point "75%–86% of departures must be missed to reverse" is **computed live** from the SSOT (`workforce_statistics.R`), so it will have drifted from any quoted value.

---

## 1. Estimand & design context (so we don't relitigate settled choices)

- Primary inflow = **ACGME completers** (not NRMP positions or fellows *starting*). Correct choice; reviewer praised it.
- URPS combines **OB/GYN-sponsored + Urology-sponsored** pathways in *both* the active workforce and the graduate count (avoids one-pathway-workforce vs two-pathway-pipeline error).
- Primary observation window **2016–2021** (fully observable under the 3-year cessation rule); later years right-censored, treated as a conservative floor.
- The estimand is explicitly a **headcount-flow** measure, NOT confirmed active-practice replacement, FTE adequacy, or operative capacity. Keep this framing.
- "Real" departure classifier = 24-source **consensus** gated by a **non-Open-Payments anchor** (`has_nonop_anchor = medicare_part_b OR part_d OR nppes_deactivation OR abms_cert_lapse`). The baseline cohorting gate (`is_retired_for_cohorting`) is a *separate* rule and is deliberately unchanged.

---

## 2. The 14 items — detailed triage

Category key: ✅ Done · 🟢 Can-do-now (no external/human dep) · ⛔ Blocked (external dep) · 👤 Human-only.
Effort: S = hours · M = 1–2 days · L = multi-day / new modeling.
All file paths below are on **`fix/workforce-cliff-data-contract`** unless noted.

### #1 — Departure classifier not individually validated  [BLOCKING · 👤 + 🟢]
**Reviewer wants:** complete two-reviewer adjudication; report sampling strategy + instrument, specialty- and age-stratified PPV, inter-rater agreement, false-positive reasons, evidence of missed departures among classifier-negatives, recomputed hazards after adjudication; ideally **probabilistic misclassification correction**, not just descriptive PPV. Absent this, frame the paper as "administrative-disappearance projection," not "clinical-practice departure." Warning signal: URPS median classified-departure age of 47 could be genuine non-retirement exits or misclassification.
**Current state:**
- Scaffolding only. `scripts/build_adjudication_sample.R` builds the stratified draw + blank scoring sheet (`cliff/data/adjudication_sample.csv`; blank `reviewer1_*`, `reviewer2_*`, `adjudicated_label`, `reviewer_agreement`; **not published**, contains NPIs).
- `scripts/classifier_adjudication.R` computes an **automated corroboration rate = provisional PPV *proxy*** (`ppv_proxy_corroborated`) — explicitly not a real PPV (corroboration cannot validate an endpoint that requires corroboration by construction).
- `scripts/validate_departure_classifier_external.R` computes a **real** confusion matrix (sensitivity/specificity/PPV/NPV/kappa) but against an **independent state-board license registry**, not human chart review → `cliff/data/classifier_validation_external.csv`.
- No probabilistic misclassification-correction code exists.
**Split:** human adjudication itself = 👤 (needs two reviewers). Misclassification-correction machinery + elevating the external-registry validation = 🟢 (M).

### #2 — Baseline and historical endpoint use different definitions  [BLOCKING · 🟢]
**Reviewer wants:** complete the consistent/anchored-definition baseline sensitivity; rerun 2025 active counts, age distributions, weighted departure rates, annual departures, 2029 projections, and completion-to-departure ratios under the SAME anchored rule; promote from limitations to a **principal** sensitivity table.
**Current state:** ABSENT by design. Baseline uses the broad multi-source gate; the code and supplement deliberately state "baseline does not move with the anchor." Only baseline-side sensitivity present is ABOG-only vs both-pathway (`build_audit_table.R` variant; `abu_pathway_sensitivity.R`).
**Do:** apply the `departure_anchor.csv` non-OP gate to the baseline cohort, re-run through the `rebuild_ssot_revised.R` dynamic machinery, emit a principal sensitivity table. Effort M.

### #3 — Known deaths omitted from baseline and hazard  [BLOCKING · ⛔ + 🟢]
**Reviewer wants:** incorporate verified deaths where possible; at minimum apply **age-specific mortality** as a sensitivity and show its effect on baseline stock, departure-event count, age-band hazard, ratio, and 2029 projection. A flat percentage add is inadequate (deaths concentrate in older bands).
**Current state:**
- Zero deceased physicians removed; death handled only as a narrative limitation (direction of bias acknowledged: missed deaths inflate the ratio). No mortality/actuarial code wired in (grep clean across cliff CSVs, Rmd, `workforce_statistics.R`, `workforce_data_contract.R`, `R/calculate_retirement_cliff_statistics.R`).
- Verified-death path is **BLOCKED**: `obgyn_death/` obituary pipeline is stuck at the Google Custom Search stage (`SETUP.md`: CSE key returns `PERMISSION_DENIED`; legacy.com Cloudflare-blocked/403). Collected data is tiny and biased: `physician_obits_confirmed.csv` 76 rows / only 15 `is_physician=True`; `obgyn_mortality_analysis.csv` n≈20, median decedent age 96.5 — not board-confirmed, not usable as a mortality table. Deliberately firewalled from the cliff pipeline.
- No SSA/CDC age-specific life table (`qx`) exists in the repo. Reusable scaffolding: age-bracket retirement-hazard framework in `R/comprehensive_retirement_analysis.R` and `manuscript/retirement_results_section.R`; active-survival KM-style code in `R/retirement_sources/16_retirement_rates_corrected_interpretation.R`.
**Split:** verified deaths = ⛔ (needs GCP Custom Search API enabled + adjudication). Age-specific mortality **sensitivity** = 🟢 — import an external SSA/CDC life table and layer onto the age-band hazard. Effort M.

### #4 — Pooled hazard may conceal specialty differences  [IMPORTANT · ✅ + 🟢]
**Reviewer wants:** hierarchical discrete-time survival or Bayesian partial-pooling (shared age effects + specialty deviations + uncertainty on the deviations); at minimum put unpooled and pooled projections side-by-side in a primary sensitivity table. Also fold ABU-hazard uncertainty (0.5×–2×) into the total envelope.
**Current state:** a pooled-vs-unpooled **comparison already exists** — `scripts/build_hazard_comparison.R` → `cliff/data/hazard_by_band_pooled_vs_unpooled.csv`, `hazard_rate_pooled_vs_unpooled.csv`. The authoritative model is ONE pooled age-band hazard applied to each specialty's active-age distribution (`compute_empirical_retirement_rate_nppes.R:110-151`, echoed in `build_audit_table.R:59-64`). **No** hierarchical/Bayesian variant (no brms/rstan/lme4/glmer anywhere).
**Split:** surface the existing unpooled-vs-pooled into a primary sensitivity table = 🟢 S. Hierarchical/partial-pool model = new work = L.

### #5 — 2025 baseline is estimated, not observed  [IMPORTANT · 🟢]
**Reviewer wants:** call them "Estimated 2025 active baseline counts"; report last directly-supported admin-year counts, N carried forward, N added as presumed entrants, N unresolved, and a baseline-lag sensitivity range; feed baseline-classification uncertainty into the main uncertainty analysis.
**Current state:** presentation gap. Cohort-flow inputs exist (`cliff/data/consort_cohort_flow.csv`, `scripts/audit_cohort_per_year.R`). Effort S–M.

### #6 — Monte Carlo intervals too narrow / false precision  [IMPORTANT/analytic · ✅ + 🟢]
**Reviewer wants:** two clearly separated displays — (a) conditional parameter interval under immediate-entry, (b) **structural scenario envelope** incorporating baseline, conversion, entry timing, hazard definition, deaths, pooling, ABU; move the narrow Monte Carlo to the supplement.
**Current state:** the parameter-vs-scenario separation is **already stated** (`manuscript_WORKFORCE_CLIFF.Rmd:129`). Authoritative interval is a **10,000-iteration bootstrap**, seed 20260718 (`rebuild_ssot_revised.R:106-122`), propagating only (a) per-band hazard via `Beta(events+0.5, PY−events+0.5)` and (b) graduate-count variability via empirical resampling of the 4 annual counts → a *prediction* interval, not a CI. Scenario envelope producer: `scripts/scenario_projection_trajectories.R` → `scenario_projection_trajectories.csv`, `scenario_comparison.csv`. Grid one-way-vs-combined columns `oneway_min` vs `worst_ratio` (`sensitivity_grid_summary.csv`).
**⚠️ Note:** `manuscript/R/workforce_statistics.R:24-31` claims "NO live re-runnable simulation … frozen archival CI (n=1,000)" — this describes the OLDER path and **contradicts** the live 10k bootstrap. Competing-SSOT hazard; reconcile which builder last wrote the CSV.
**Do:** assemble one structural envelope from the existing pieces, demote the narrow bootstrap to supplement. Effort M.

### #7 — Immediate-entry projection is an optimistic upper bound  [IMPORTANT/analytic · ✅ + 🟢]
**Reviewer wants:** make the transition-adjusted status-quo projection the main visual, immediate-entry as an upper structural scenario (or paired solid/dashed). The ratio can stay primary (entry-timing-independent).
**Current state:** transition ramp **exists** — `scripts/graduation_to_active_transition.R` (empirical cert→active timing from `first_billing_year`) → `graduation_active_transition.csv`, `graduation_active_transition_projection.csv` (`projected_2029_immediate` vs `_ramped`). Deferral ≈ 20% GO / 37% URPS of projected growth. **Figure 1 is a static asset** (`cliff/figures/figure1_workforce_trajectories.{tiff,png}`, generator not in the active tree; the clean Rmd has no ggplot chunk). Immediate-entry assumption stated at `manuscript_WORKFORCE_CLIFF.Rmd:150`.
**Do:** rebuild the Figure 1 generator to show ramp as the main line + immediate as dashed upper. Effort M.

### #8 — 4-year grad average ignores secular program growth  [analytic · 🟡→🟢]
**Reviewer wants:** add flat recent-mean, cohort-accounting (fellows already in training), contraction (recent fill rates), and cautious trend scenarios; 2025–2027 graduates are largely already in training and can be projected more directly.
**Current state:** partial. `scripts/scenario_projection_trajectories.R` has conservative-70% / status-quo-mean / optimistic-NRMP; `scripts/acgme_graduate_crosswalk.R` defines `nrmp_filled`, `acgme_grad_mean4yr` (GO 75 / URPS 48), `conservative_85pct`. Distinct flat/trend/cohort-accounting/contraction scenarios mostly ABSENT. NRMP entrants: `scripts/fetch_nrmp_fellowship_entrants.R` → `nrmp_fellowship_entrants.csv`. Effort M.

### #9 — Inactivity-threshold sensitivity (2/3/4-yr absence)  [analytic · 🟢]
**Reviewer wants:** a dedicated sensitivity varying the **required inactivity duration** (2 vs 3 vs 4 years), which is NOT the same as varying the calendar window.
**Current state:** ABSENT. Uniform 3-year cessation rule (`config/retirement_specialty_thresholds.yml` via `R/retirement_config_loader.R`; supplement states "no subspecialty-specific threshold"). Only the calendar-**window** sensitivity exists (`departure_window_sensitivity.csv`, `rebuild_ssot_revised.R:158-169`). NOTE: repo-wide `scripts/sensitivity_analysis_grace_period.R` / `sensitivity_analysis_activity_bounds.R` belong to the isochrone pipeline, not this paper.
**Do:** re-derive departure events at 2/3/4-yr thresholds and re-run the projection. Effort M–L (re-running classification per threshold is real work).

### #10 — Specialty-specific / holdout temporal calibration  [analytic · 🟡→🟢]
**Reviewer wants:** back-testing split by GO / ABOG-URPS / ABU-URPS / earlier-vs-later period / age band; a true holdout-period prediction is more persuasive than same-period calibration.
**Current state:** partial. `scripts/temporal_backtest.R` → `temporal_backtest.csv`, two modes (calibration + out-of-sample), split by GO/URPS/MIG × base-year × target-year. "Within ~1%" reported (`manuscript:125`, supplement Table S4). **Not** split ABOG-vs-ABU (ABU net-new not in the backtest cohort), **not** by age band.
**Do:** add age-band axis; report ABOG-only vs note ABU absence; emphasize the existing out-of-sample mode. Effort M.

### #11 — Fellowship-expansion conclusion too policy-forward  [interpretation · 🟢]
**Reviewer wants:** soften to e.g. "Under the modeled assumptions, we found no evidence of a near-term national aggregate headcount replacement gap that, by itself, would require fellowship expansion."
**Current state:** HEAD/3-arm text is explicitly forward ("expand FPMRS 60→67", "GO 50→60", "expand by 15–20%": `manuscript_WORKFORCE_CLIFF.Rmd:249,287,79,288`). The data-contract branch may already be softer — **confirm on the branch reviewed** before conceding. Effort S.

### #12 — Qualify "replacement" throughout  [interpretation · 🟢]
**Reviewer wants:** use "headcount flow balance" / "potential headcount replacement" / "completion-to-classified-departure balance"; avoid bare "replacement fails / above replacement / headcount sufficiency."
**Current state:** replacement-ratio def + thresholds at `manuscript_WORKFORCE_CLIFF.Rmd:156-165`. Global terminology pass. Effort S.

### #13 — Tipping-point language ≠ validation  [interpretation · ✅ + 🟢]
**Reviewer wants:** present the tipping point as one axis of a multidimensional uncertainty analysis, not as evidence the classifier's performance is unimportant; note multiple moderate biases can compound (missed deaths, missed non-Medicare departures, lower conversion, reduced entrant FTE, baseline overcounting, specialty hazard differences).
**Current state:** live calc `get_tipping_missed_range()` (`workforce_statistics.R:481-489`); break-even thresholds `:468-479` → `breakeven_thresholds.csv` (supplement Appendix S10). Reframe only. Effort S.

### #14 — Manuscript too dense; trim 25–33%  [structure · 🟢 + ⚠️ conflation]
**Reviewer wants:** cut ~¼–⅓; keep cohort construction, primary departure definition, graduate counts, dynamic projection (message cut off there in the review paste).
**Current state:** the **clean main file is already ~3,200 words / tables-only** (Table 1 + Table 2; no figure chunks). Density lives in the supplement + fuller drafts (`manuscript/results_section.Rmd`, `retirement_results_section.Rmd`, `appendix_workforce_replacement_ratio.Rmd`).
**⚠️ Reviewer conflation flag:** two items the reviewer lists to trim — **"operative-workforce validity analysis"** and **"ABU hazard scaling"** — are **NOT in the cliff paper**; they belong to the *separate* accessibility / E2SFCA (Desjardins-7) manuscript. "MIGS exploratory," "match-position forecasting," "sex-stratified," "entrant-effort," "entry-timing" ARE present (mostly in drafts/supplement). Point this out in the response letter; some of the "density" the reviewer sees may be them reading across two papers.

---

## 3. Cross-cutting flags (raise in the response letter)

1. **Some criticisms may be partly moot on the reviewed branch.** `#6` (frozen narrow MC) and `#11` (forward policy) partly describe the OLDER 3-arm text on `manuscript/green-journal-bibtex`; the data-contract branch already has a live 10k bootstrap and MIGS-excluded 2-arm framing. Confirm the reviewer read `0f10e59f6` and check whether these are already addressed before conceding.
2. **Competing SSOT writers.** `rebuild_ssot_revised.R` (10k bootstrap, authoritative), `rebuild_ssot_dynamic_acgme.R` (single-year ACGME, 1k MC), and `rebuild_ssot_final.R` (static, "no live MC") all write the SAME `workforce_projections_consolidated.csv`; nothing enforces which ran last. The `workforce_statistics.R:24-31` "frozen archival CI" comment is stale relative to the live bootstrap. Pin the authoritative builder and delete/retire the others' write paths before quoting any CI.
3. **Number drift.** Headline ratios differ by branch/commit (HEAD 3-arm ≠ 2fa1aa4aa 7.35/5.83 ≠ 0f10e59 7.11/5.61). Any quoted figure (including the reviewer's "75–86%") must be regenerated from the pinned SSOT, not copied.

---

## 4. Recommended next-session sequence

1. **Action zero:** decide merge/rebase of `fix/workforce-cliff-data-contract` into the line of work; do all edits there. Pin the authoritative SSOT builder (flag #2 above).
2. **Can-do-now analyses (highest value, no deps):** `#2` anchored-definition baseline (M) → `#4`-surface existing pooled-vs-unpooled as a primary table (S) → `#5` baseline relabel + lag sensitivity (S–M) → `#6` structural uncertainty envelope (M) → `#9` inactivity-threshold 2/3/4-yr (M–L) → `#10` backtest age-band granularity (M) → `#8` grad-growth scenarios (M).
3. **Mortality sensitivity `#3` (🟢 part):** import SSA/CDC age-specific life table, layer onto age-band hazard, report effect on stock/events/hazard/ratio/2029. (M)
4. **Figure `#7`:** rebuild Fig 1 generator (ramp main + immediate dashed). (M)
5. **Prose:** `#11`, `#12`, `#13`, `#14` conflation note → response letter. (S each)
6. **Blockers to escalate to PI / external:** `#1` two-reviewer human adjudication (👤); `#3` verified deaths via `obgyn_death` (⛔ — needs GCP Custom Search API enabled). Build the `#1` misclassification-correction code now so it is ready when labels arrive.

## 5. Key file index (branch `fix/workforce-cliff-data-contract`)

- Manuscript: `manuscript/manuscript_WORKFORCE_CLIFF.Rmd` (Table 2 chunk `:198-216`), `manuscript/supplement_WORKFORCE_CLIFF.Rmd`, drafts `manuscript/results_section.Rmd` / `retirement_results_section.Rmd` / `appendix_workforce_replacement_ratio.Rmd`.
- Stats getters: `manuscript/R/workforce_statistics.R` (tipping `:481-489`, breakeven `:468-479`, transition getters ~`:500-515`, frozen-CI comment `:24-31`), `manuscript/R/workforce_data_contract.R`.
- SSOT / projection: `scripts/rebuild_ssot_revised.R` (authoritative; bootstrap `:106-122`, window sensitivity `:158-169`), `rebuild_ssot_dynamic_acgme.R`, `rebuild_ssot_final.R`, `dynamic_stockflow_projection.R` (POC).
- Hazard: `scripts/compute_empirical_retirement_rate_nppes.R` (`:110-151`), `scripts/build_hazard_comparison.R` (pooled-vs-unpooled).
- Classifier / anchor / adjudication: `scripts/departure_anchor.R`, `scripts/build_adjudication_sample.R`, `scripts/classifier_adjudication.R`, `scripts/validate_departure_classifier_external.R`.
- Sensitivity: `scripts/sensitivity_grid.R` (mult `:16`, conv `:17`), `scripts/temporal_backtest.R`, `scripts/abu_pathway_sensitivity.R`, `scripts/age_shift_sensitivity.R`, `scripts/scenario_projection_trajectories.R`, `scripts/build_audit_table.R` (`:118-123` variants), `scripts/acgme_graduate_crosswalk.R`, `scripts/fetch_nrmp_fellowship_entrants.R`.
- Data: `cliff/data/*.csv` (esp. `workforce_projections_consolidated.csv`, `departure_audit_table.csv`, `departure_window_sensitivity.csv`, `breakeven_thresholds.csv`, `temporal_backtest.csv`, `hazard_*_pooled_vs_unpooled.csv`, `graduation_active_transition*.csv`, `departure_anchor.csv`).
- Death pipeline (blocked): `obgyn_death/` (`00_MASTER_SCRAPER.R`, `R/0[1-9]_*.R`, `SETUP.md`), data `obgyn_death/data/processed/`, outputs `obgyn_death/outputs/`.

## 6. Do-not-re-derive facts

- Reviewed branch = `fix/workforce-cliff-data-contract` @ `0f10e59f6`; NOT merged into `manuscript/green-journal-bibtex`.
- Ratios GO 7.11 / URPS 5.61 (MIGS excluded, branch tip). Regenerate, never copy, any quoted number.
- Blockers needing a human/external action: `#1` (two reviewers) and `#3`-verified-deaths (GCP Custom Search API `PERMISSION_DENIED`).
- Reviewer likely conflated two papers on `#14` (operative-workforce + ABU-hazard-scaling are the accessibility paper, not the cliff paper).
