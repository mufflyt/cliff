# SSOT refactor ledger

Cumulative record for the `/loop` SSOT audit (one candidate per iteration, no re-audits).
The loop runs every 30 min (cron `ce5e69e9`); it will keep firing past the intended
8 hours until cancelled with `CronDelete ce5e69e9` or the 7-day auto-expiry.

Rules: audit before editing; never collapse intentional differences; one refactor per
iteration; do NOT commit/push; leave the tree valid each iteration.

---

## Iteration 1 — projection horizon (`WORKFORCE_PROJECTION_HORIZON_YEARS` / `WC_HORIZON`)

**Candidate:** the 4-year projection horizon (2025 → 2029).

**Why high-risk vs alternatives:** it is a *formula component* multiplied into published
numbers (`projected_2029 = baseline + horizon·(entrants − retirements)`,
`fellowship_total_4yr`, `total_retirements_4yr`), it is defined as **two independent
literals** (`WORKFORCE_PROJECTION_HORIZON_YEARS <- 4L` in the contract and
`WC_HORIZON <- 4L` in the engine, which does **not** source the contract), and the repo
still carries a **stale 5-year** variant (`annual_entrants * 5` in
`code/01_consolidate_workforce_data.R`) that the contract says was removed 2026-07-15.
A drift between the two 4L literals would silently change every projection.

**Provenance table (audit):**

| File:line | Value/formula | Purpose | Status | Deps |
|---|---|---|---|---|
| `manuscript/R/workforce_data_contract.R:45` | `WORKFORCE_PROJECTION_HORIZON_YEARS <- 4L` | canonical constant | **authoritative** | consumed by contract validation, manuscript, tests |
| `R/workforce_cliff_engine.R:21` | `WC_HORIZON <- 4L` | engine projection default | **duplicate literal** | `wc_project()`, `graduate_growth_scenarios.R` |
| `R/manuscript_consolidate_existing_results.R:170,210,211` | `* WORKFORCE_PROJECTION_HORIZON_YEARS` | derived totals | correct (references canonical) | — |
| `manuscript/R/workforce_statistics.R:277` | `entrants * WORKFORCE_PROJECTION_HORIZON_YEARS` | fellowship total | correct | — |
| `manuscript/R/create_figure1_workforce_projection.R:43` | `horizon <- WORKFORCE_PROJECTION_HORIZON_YEARS` | figure | correct | — |
| `scripts/rebuild_ssot_from_nrmp.R:24` | `HZ <- WORKFORCE_PROJECTION_HORIZON_YEARS` | SSOT rebuild | correct | — |
| `scripts/graduate_growth_scenarios.R:23` | `HORIZON <- WC_HORIZON` | scenario grid | derived from engine dup | — |
| `code/01_consolidate_workforce_data.R:147` | `(4 * avg_annual_retirements) + (4 * annual_entrants)` | legacy consolidation | **hardcoded 4** (legacy `code/` pipeline) | — |
| `code/01_consolidate_workforce_data.R:181` | `annual_entrants * 5` | `fellowship_total_5yr` | **STALE 5-year** (removed from contract) | — |

**Adjudication:** the two `4L` literals are the same value → collapse to one canonical.
The `code/01` hardcoded `4` and stale `* 5` live in the separate legacy `code/` pipeline
(`code/00_RUN_ALL.R`), produce a `fellowship_total_5yr` column the current manuscript
does not use, and changing them alters that pipeline's output — that is a behavior
decision, **deferred** (documented, not touched this iteration, per "never change
behavior unless the audit proves it wrong / avoid unrelated refactoring").

**Canonical contract:** `WORKFORCE_PROJECTION_HORIZON_YEARS` — the study projection
horizon in whole years (2025→2029 = 4). Units: years. Range: positive integer. Source:
study design. Moved into `R/workforce_constants.R` (a named constant in a shared module),
sourced by both the data contract and the engine so it cannot drift.

**Canonical implementation:** `R/workforce_constants.R` — `WORKFORCE_PROJECTION_HORIZON_YEARS <- 4L`
with provenance + fail-loud validation (integer, scalar, non-NA, ≥ 1). Sourced with
`local = TRUE` by both `manuscript/R/workforce_data_contract.R` and
`R/workforce_cliff_engine.R`; the engine's `WC_HORIZON` now derives from it.

**Hardcoded copies removed:** 1 (`WC_HORIZON <- 4L` in the engine → references the canonical).
The contract's literal `WORKFORCE_PROJECTION_HORIZON_YEARS <- 4L` moved into the module.

**Guards/tests added:** `R/workforce_constants.R` fail-loud `stopifnot`; new
`tests/testthat/test-ssot-horizon.R` (6 tests, 10 assertions): canonical is a valid
positive-integer scalar; engine `WC_HORIZON` derives from and equals the canonical (== 4L
pin); contract and engine cannot drift; `wc_project()` defaults to the canonical;
propagation (mutating the SSOT moves `WC_HORIZON`); **adversarial** — scans all R files
(incl. untracked) and fails if any reintroduces an independent horizon literal.

**Test results:** ssot-horizon 10/0; contract 63/0; data-analysis 272/0; data-properties
166/0. Engine loads; URPS `wc_project` → projected_2029 = 1544 (**unchanged** — behavior
preserved, 4L == 4L). Initial 2 failures were test env-isolation only (nested `source()`
defaulted to globalenv); fixed by `local = TRUE` on the nested sources — a genuine
robustness improvement, not a workaround.

**Deferred (documented, not changed):** `code/01_consolidate_workforce_data.R:147` hardcodes
`4`, and `:181` carries the STALE 5-year `annual_entrants * 5` (`fellowship_total_5yr`) that
the contract removed 2026-07-15. This is the separate legacy `code/` pipeline; aligning it
changes that pipeline's output (a behavior decision) → its own future iteration.

**Remaining risks:** the legacy `code/` pipeline still computes horizon-dependent numbers
with its own literals; if it is ever re-activated it can diverge from the canonical.

**Recommended next candidate:** `WORKFORCE_MONTE_CARLO_ITERATIONS` (= 1000L, contract line
48) — check the frozen MC artifacts, `urps_model_data.R` seed/iteration references, and any
`10000`/`1000` literals in sensitivity scripts for drift; or the age-band definition
(`WC_BANDS` / `WC_BAND_LABELS` vs the Shiny `BAND_LABELS` duplicate).

**Status:** ✅ complete. Uncommitted (loop rule: no commits).

---

## Iteration 2 — NRMP certified-positions benchmark (`WC_ENTRANTS_NRMP`, 74/88/51)

**Candidate:** the NRMP certified-positions entrant benchmark — URPS 74, GO 88, MIGS 51.

**Why high-risk vs alternatives:** it is an inflow the optimistic scenario multiplies into
projected workforce, it feeds a *published* manuscript number (`get_nrmp_entrants()`), and it
was defined **4×** — the engine constant, the frozen benchmark CSV the manuscript reads, and
two script literals (one dropping MIGS). It also sits next to a **look-alike** value
(NRMP *filled* counts 70/86/47) that must never be merged with it. Chosen over the age-band
lookup (blocked partly by deliberate Shiny self-containment) and MC iterations (needs a
frozen-artifact authority check first).

**Provenance table (audit):**

| File:line | Value | Purpose | Status | Deps |
|---|---|---|---|---|
| `R/workforce_cliff_engine.R:31` | `WC_ENTRANTS_NRMP <- c(URPS=74L, GO=88L, MIGS=51L)` | benchmark inflow constant | **authoritative** | scenario scripts |
| `data/workforce_projection_benchmark_nrmp.csv` (`nrmp_entrants`) | 74/88/51 + derived projections | frozen benchmark read by `get_nrmp_entrants()` | derived artifact (must match constant) | manuscript |
| `scripts/graduate_growth_scenarios.R:23` | `c(GO=88, URPS=74)` | optimistic scenario | **duplicate literal** (drops MIGS) | sources engine → had canonical available |
| `scripts/scenario_projection_trajectories.R:28` | `c(GO=88, URPS=74, MIGS=51)` | optimistic trajectory | **duplicate literal** | standalone (no engine source) |
| `data/nrmp_fellowship_entrants.csv` | URPS 70 / GO 86 / MIGS 47 | NRMP *filled* 2025 | **DIFFERENT quantity** — do NOT merge | manuscript ("87 and 70 filled") |

**Adjudication:** 74/88/51 is one value duplicated 4× → canonical = engine `WC_ENTRANTS_NRMP`.
70/86/47 is the NRMP *filled* count — an intentional difference, preserved (guarded, not
merged). `graduate_growth_scenarios.R` only iterates GO/URPS, so referencing the canonical is
behavior-preserving (88/74 match; dropped MIGS never accessed). `scenario_projection_trajectories.R`
does NOT source the engine and independently duplicates SUBS/GRAD/NRMP — fully de-duplicating it
(source the engine, drop all three) is a bigger change → **deferred** to its own iteration.

**Canonical:** `WC_ENTRANTS_NRMP` (engine) — NRMP certified positions, 2026 appointment year;
named integer vector by subspecialty; source = NRMP SMS report. The benchmark CSV is a derived
artifact whose `nrmp_entrants` must equal it.

**Files changed:** `scripts/graduate_growth_scenarios.R` (→ references `WC_ENTRANTS_NRMP`);
new `tests/testthat/test-ssot-nrmp-entrants.R`.

**Hardcoded copies removed:** 1 (graduate_growth_scenarios). 1 remains (scenario_projection_trajectories, deferred).

**Guards/tests added:** `test-ssot-nrmp-entrants.R` (13 assertions): canonical is a named
integer 74/88/51; frozen benchmark CSV matches the constant (drift guard); the 74/88 benchmark
stays DISTINCT from the 70/86 filled counts (intentional-difference guard); **adversarial** —
no engine-sourcing script re-hardcodes the benchmark.

**Test results:** ssot-nrmp 13/0; ssot-horizon 10/0 (unaffected); refactored script parses,
GO=88/URPS=74 unchanged. No initial failures.

**Remaining risks/ambiguities:** `scenario_projection_trajectories.R` still carries the literal
(standalone, deferred). The benchmark CSV also stores derived projections computed from the
entrants; if regenerated it must use the canonical (its producer, `rebuild_ssot_from_nrmp.R`,
not audited this iteration).

**Recommended next candidate:** `scenario_projection_trajectories.R`'s standalone constant block
(SUBS/GRAD/NRMP) — make it source the engine; or the fellowship graduate counts `WC_GRAD`
(`GO=c(70,73,78,79), URPS=c(61,66,63,66), MIGS=c(47,50,45,47)`) which is duplicated in
`scenario_projection_trajectories.R:27` and the Shiny model_data.

**Status:** ✅ complete. Uncommitted (loop rule).

---

## Iteration 3 — ACGME fellowship graduate counts (`WC_GRAD`)

**Candidate:** the ACGME 4-year graduate-count vectors — `WC_GRAD` = GO c(70,73,78,79),
URPS c(61,66,63,66), MIGS c(47,50,45,47). The engine derives `WC_ENTRANTS <- sapply(WC_GRAD, mean)`
(the SSOT annual_entrants 64/75/47), so this is the *root input* behind the primary entrant flow.

**Why high-risk vs alternatives:** it is the source of every projection's inflow (means feed
`annual_entrants`, which drives `projected_2029` and the completion-to-departure ratio), and it
was duplicated wholesale in `scenario_projection_trajectories.R` — a script that re-declared the
**entire** engine constant block as literals (bands, window, ages, YEAR0, an un-guarded
`HORIZON <- 4L`, SUBS, GRAD, NRMP) and sourced only `wc_path`, so any engine change silently
diverged from it.

**Provenance table (audit):**

| File:line | Value | Status | Notes |
|---|---|---|---|
| `R/workforce_cliff_engine.R:29` | `WC_GRAD <- list(...)` | **authoritative** | `WC_ENTRANTS <- sapply(WC_GRAD, mean)` derived here |
| `data/workforce_projections_consolidated.csv` (`annual_entrants`) | 64/75/47 | derived (means, MIGS rounded) | must match |
| `scripts/scenario_projection_trajectories.R:20-28` | full literal block incl. `GRAD <- list(...)`, `NRMP <- c(...)`, `HORIZON <- 4L` | **duplicate block** → fixed | now sources engine + aliases WC_* |
| `scripts/graduate_growth_scenarios.R:23` | `GRAD <- WC_GRAD` | correct (iteration prior) | — |
| `scripts/hierarchical_hazard_partial_pooling.R:31` | `GRAD <- list(GO,URPS)` | **duplicate** (standalone, no engine) | **deferred** → next candidate |
| `shiny_urps_scenarios/urps_model_data.R` | `GRAD_URPS <- c(61,66,63,66)` | deliberate self-contained copy | drift-guarded |
| `scenario_projection_trajectories.R:101-102` | `GRAD_SPLIT` / `NRMP_SPLIT` (obg/uro) | **DIFFERENT quantity** (pathway decomposition) | not collapsed; future candidate |

**Adjudication:** the flat `WC_GRAD` value duplicated in `scenario_projection_trajectories`'s
constant block → re-pointed to the engine (all 12 values verified identical, so behavior-preserving).
The pathway-split `GRAD_SPLIT`/`NRMP_SPLIT` are distinct (obg/uro decomposition summing to the
canonical) → preserved. `hierarchical_hazard_partial_pooling.R` is a separate standalone script →
deferred (one refactor per iteration).

**Canonical:** engine `WC_GRAD` (named list, ACGME Table D.5, AY2020-21…2023-24; source of the
derived `WC_ENTRANTS`).

**Files changed:** `scripts/scenario_projection_trajectories.R` (source `wc_path` → source the
engine; the entire literal constant block → `WC_*` aliases, removing bands/window/ages/YEAR0/
HORIZON/SUBS/SUBS_FULL/GRAD/NRMP duplicates in one re-point); new
`tests/testthat/test-ssot-graduate-counts.R`.

**Hardcoded copies removed:** the full standalone block in `scenario_projection_trajectories`
(~12 engine constants, incl. the previously un-guarded `HORIZON <- 4L` and the last NRMP literal
outside a canonical). Also completes iteration 2's deferred NRMP dedup for this script.

**Guards/tests added:** `test-ssot-graduate-counts.R` (13 assertions): WC_GRAD value/shape pin;
`WC_ENTRANTS == means`; SSOT `annual_entrants == WC_GRAD means`; Shiny `GRAD_URPS` matches
canonical (self-contained drift guard); **adversarial** — no engine-sourcing script re-hardcodes
`GRAD <- list(`.

**Test results:** ssot-graduate-counts 13/0; ssot-nrmp 13/0 (still green — the re-pointed script
now uses `WC_ENTRANTS_NRMP`, so the NRMP adversarial passes with it as an engine-sourcing script);
ssot-horizon 10/0; refactored script parses. No initial failures.

**Remaining risks/ambiguities:** (1) `hierarchical_hazard_partial_pooling.R:31` still duplicates
WC_GRAD (standalone). (2) The iteration-1 horizon adversarial scans only `R/`+`manuscript/R/`, not
`scripts/`; this iteration incidentally removed the `scripts/` horizon literal, but the guard should
be widened. (3) `GRAD_SPLIT`/`NRMP_SPLIT` pathway decomposition is unguarded (should sum to canonical).

**Recommended next candidate:** de-duplicate `hierarchical_hazard_partial_pooling.R`'s standalone
constant block against the engine (same pattern as this iteration); or widen the horizon adversarial
guard to `scripts/`; or the pathway-split consistency (`GRAD_SPLIT`/`NRMP_SPLIT` sum to WC_ENTRANTS/NRMP).

**Status:** ✅ complete. Uncommitted (loop rule).

---

## Iteration 4 — age-band definition (`WC_BANDS` / `WC_BAND_LABELS`)

**Candidate:** the age-band grid — `WC_BANDS <- c(0,45,50,55,60,65,70,Inf)` and
`WC_BAND_LABELS <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")`.

**Why high-risk vs alternatives:** the bands are the **axis of the entire hazard model** — every
person-year, band count, band hazard, and the hazard CSV's `band` column key off them; a drift in
one copy (a boundary or a label) would silently misclassify ages and mis-join hazards, quietly
changing every projection. It is duplicated across **11 non-canonical sites** (6 standalone scripts,
4 Shiny copies, 1 test) — the widest-spread value found so far.

**Provenance table (audit):**

| Site | Kind | Status |
|---|---|---|
| `R/workforce_cliff_engine.R:17-18` | canonical | **authoritative** |
| `data/hazard_by_band_pooled_vs_unpooled.csv` (`band` col) | frozen artifact | must match labels (order-sensitive) |
| `scripts/hierarchical_hazard_partial_pooling.R:26` | standalone literal block | **fixed** → sources engine, aliases WC_* |
| `scripts/scenario_projection_trajectories.R` | (iteration 3) | references WC_* |
| `scripts/{abu_pathway_sensitivity, build_hazard_comparison, make_urps_only_figures, urps_module_a_effective_supply_2026-07-23, urps_supply_demand_national_2026-07-23}.R` | standalone literals | **deferred** (don't source engine) |
| `shiny_urps_scenarios/urps_model_data.R`, `shiny_urps_adequacy/data/urps_model_data.R` | self-contained deployment copies | drift-guarded |
| `shiny_urps_adequacy/model.R`, `shiny_urps_scenarios/app.R` | Shiny code | (use BAND_LABELS from model_data) |
| `tests/testthat/test-workforce-cliff-data-properties.R` | test literal | separate (test scaffold) |

**Adjudication:** all copies are the same grid (verified identical) → one canonical (engine). No
intentional differences. Fixed one standalone script (same whole-block re-point as iteration 3,
which also removed another un-guarded `HORIZON <- 4L` and a `GRAD` copy). The remaining 5 standalone
scripts don't source the engine → deferred (same pattern). Shiny + CSV can't reference the engine
→ drift-guarded instead.

**Canonical:** engine `WC_BANDS` / `WC_BAND_LABELS` (7 age bands, right-open; study design).

**Files changed:** `scripts/hierarchical_hazard_partial_pooling.R` (source `wc_path` → engine; whole
literal block → `WC_*`); new `tests/testthat/test-ssot-age-bands.R`.

**Hardcoded copies removed:** 1 script's full constant block (bands + window + ages + `HORIZON <- 4L`
+ SUBS + GRAD/PRIMARY). Behavior-preserving: `ENTRANTS[[k]]` indexes by name over PRIMARY (GO/URPS),
so `GRAD <- WC_GRAD` adding MIGS is inert.

**Guards/tests added:** `test-ssot-age-bands.R` (11 assertions): canonical well-formed (7 labels /
8 breakpoints / monotone / closed 0–Inf); hazard CSV `band` column matches labels (order-sensitive);
both Shiny `BAND_LABELS` copies match canonical (drift guard); **semantic** partition check (`cut`
right-open agrees with labels at boundaries 44/45/49/50/70); **adversarial** — no engine-sourcing
script redefines the bands as literals.

**Test results:** age-bands 11/0; graduate-counts 13/0; nrmp 13/0; horizon 10/0; script parses. No
initial failures.

**Remaining risks/ambiguities:** the 5 standalone scripts above still hold band literals that are NOT
value-guarded (only the Shiny copies + CSV are); they can still drift until re-pointed. Same for their
window/ages/SUBS duplicates. `test-workforce-cliff-data-properties.R` has its own band literal (test
scaffold, low risk).

**Recommended next candidate:** the observation window `WC_WIN <- c(2016L, 2021L)` (duplicated in the
same 5 standalone scripts + as prose "2016-2021" across the manuscript/figures); or continue de-pointing
one of the 5 standalone scripts (e.g. `urps_module_a_effective_supply`) against the engine.

**Status:** ✅ complete. Uncommitted (loop rule).

---

## Iteration 5 — primary observation window (`WC_WIN` = 2016-2021)

**Candidate:** the hazard-estimation observation window `WC_WIN <- c(2016L, 2021L)`.

**Why high-risk vs alternatives:** it is a *published methodological choice* (the
right-censoring-safe window over which every age-band hazard is estimated); a drifted bound
would silently change which departures count and therefore every hazard, rate, and projection.
Duplicated in the 5 standalone scripts + encoded in Shiny prose window labels ("2016-2021").

**Provenance table (audit):**

| Site | Kind | Status |
|---|---|---|
| `R/workforce_cliff_engine.R:19` | `WC_WIN <- c(2016L, 2021L)` | **authoritative** |
| `scripts/build_hazard_comparison.R:27` | `WIN <- c(2016L,2021L)` | **fixed** → sources engine, `WIN <- WC_WIN` |
| `scripts/{scenario_projection_trajectories, hierarchical_hazard_partial_pooling}.R` | (iterations 3-4) | reference `WC_WIN` |
| `scripts/{abu_pathway_sensitivity, make_urps_only_figures, urps_module_a_effective_supply_2026-07-23, urps_supply_demand_national_2026-07-23}.R` | standalone literals | **deferred** |
| `shiny_urps_scenarios/urps_model_data.R` `WINDOW_LABELS` | prose label "2016-2021" | consistency-guarded |
| manuscript/figure prose "2016-2021" | narrative | not code-refactorable (documented) |

**Adjudication:** one window, all copies identical → canonical (engine). No intentional differences
(the drop2/full sensitivity windows 2016-2019 / 2016-2023 are DISTINCT and preserved). Fixed the
producer of the hazard CSV (`build_hazard_comparison.R`) via the whole-block re-point; 4 standalone
scripts deferred; manuscript prose can't reference an R constant (documented).

**Canonical:** engine `WC_WIN` (primary observation window, whole years, 2016-2021; study design,
right-censoring-safe under the 3-year follow-up rule).

**Files changed:** `scripts/build_hazard_comparison.R` (source `wc_path` → engine; bands/BL/ages/
REF_YEAR/WIN/SUBS literals → `WC_*`); new `tests/testthat/test-ssot-obs-window.R`.

**Hardcoded copies removed:** 1 (build_hazard_comparison's block, incl. WIN + bands + ages + SUBS).
Behavior-preserving (values identical; SUBS keeps all 3 as the script pools GO+URPS+MIGS).

**Guards/tests added:** `test-ssot-obs-window.R` (9 assertions): WC_WIN value/shape pin; **cross-constant
consistency** (2016 ≥ 2013 floor; 2021 < WC_REF_YEAR=2024; 2021 ≤ WC_OBS_END=2023 — 3-yr follow-up
headroom); Shiny `WINDOW_LABELS[fully_obs]` contains `sprintf("%d-%d", WIN)` (prose tied to constant);
**adversarial** — no engine-sourcing script redefines `WIN <- c(20...`.

**Test results:** obs-window 9/0; age-bands 11/0; graduate-counts 13/0; nrmp 13/0; horizon 10/0; script
parses. No initial failures.

**Remaining risks:** 4 standalone scripts (`abu_pathway_sensitivity`, `make_urps_only_figures`,
`urps_module_a_effective_supply`, `urps_supply_demand_national`) still hold band/window/ages/SUBS
literals, un-value-guarded. Manuscript prose "2016-2021" is unguarded (narrative).

**Recommended next candidate:** continue re-pointing a standalone script to the engine
(`abu_pathway_sensitivity.R` or `make_urps_only_figures.R`) — each removes bands+window+ages+SUBS at
once; or `WC_SUBS`/`WC_SUBS_FULL` (subspecialty label mapping) as a lookup-table candidate; or the
per-analysis random seeds (20260718 vs 20260720 — verify intentional).

**Status:** ✅ complete. Uncommitted (loop rule).

---

## Iteration 6 — age-at-certification assumption (`WC_AGE_AT_CERT` = 30)

**Stopped (audited, not refactored):** the **subspecialty label mapping** (`WC_SUBS` vs `WC_SUBS_FULL`).
Authority is ambiguous: `WC_SUBS` (data-match: URPS → "Female Pelvic Medicine & Reconstructive Surgery")
and `WC_SUBS_FULL` (display: URPS → "Urogynecology and Reconstructive Pelvic Surgery") are *intentionally
different*, and the display names are also carried independently by the frozen SSOT csv `subspecialty`
column and by manuscript prose — so "which is canonical" between constant and frozen data cannot be
cleanly established in one iteration. Per the loop's stop-if-authority-unclear rule, deferred to a
dedicated iteration (would need a mapping table + a constant↔csv agreement guard). **Do not re-audit
blindly.**

**Candidate:** `WC_AGE_AT_CERT <- 30L` — the assumed age at board certification.

**Why high-risk vs alternatives:** it is the anchor of the age-reconstruction formula
`age = REF_YEAR − cert_year + AGE_AT_CERT` used across every hazard script; a drift shifts *everyone's*
reconstructed age and therefore their age band and departure hazard. Duplicated in the standalone scripts.

**Provenance (audit):** canonical `R/workforce_cliff_engine.R:20`; duplicated in
`scripts/abu_pathway_sensitivity.R:17` (fixed), and referenced correctly (post-iterations 3-5) in
`scenario_projection_trajectories`, `hierarchical_hazard_partial_pooling`, `build_hazard_comparison`.
Remaining standalone copies: `make_urps_only_figures`, `urps_module_a_effective_supply`,
`urps_supply_demand_national`.

**Adjudication:** one value, all copies identical (30) → canonical (engine). Comments in
`abu_pathway_sensitivity` describing scenario baselines (1031/1295) are prose, not code → untouched.

**Canonical:** engine `WC_AGE_AT_CERT` (assumed age at ABOG certification, whole years; source = study
age-reconstruction method; consumed by the `age = REF_YEAR − cert_year + AGE_AT_CERT` formula).

**Files changed:** `scripts/abu_pathway_sensitivity.R` (source `wc_path` → engine; whole block
bands/BL/WIN/AGE_AT_CERT/REF_YEAR/HORIZON/ENTRY_AGE → `WC_*`); new `tests/testthat/test-ssot-age-at-cert.R`.

**Hardcoded copies removed:** 1 (abu_pathway's block). Behavior-preserving (values identical).

**Guards/tests added:** `test-ssot-age-at-cert.R` (10 assertions): value/type pin (30L); **internal
consistency** (`WC_ENTRY_AGE` 34 > `WC_AGE_AT_CERT` 30 — graduates enter after certification);
**semantic** age-reconstruction (certified 2020 → age 34 → "<45"; certified 1979 → 75 → "70+");
**adversarial** — no engine-sourcing script redefines `AGE_AT_CERT`.

**Test results:** age-at-cert 10/0; obs-window 9/0; age-bands 11/0; graduate-counts 13/0; nrmp 13/0;
horizon 10/0; script parses. No initial failures.

**Remaining risks:** 3 standalone scripts (`make_urps_only_figures`, `urps_module_a_effective_supply`,
`urps_supply_demand_national`) still hold un-value-guarded block literals; `WC_ENTRY_AGE` (34) and the
year constants (`WC_REF_YEAR`/`WC_YEAR0`/`WC_OBS_END`) are not yet individually guarded.

**Recommended next candidate:** `WC_ENTRY_AGE` (34, graduate entry age) via the last standalone
re-points; or the figure color palette (TEAL/ORANGE/RED hex codes duplicated across `augs_application/`
and `scripts/` figure builders — a distinct UI-consistency SSOT); or the subspecialty mapping (needs the
dedicated mapping-table treatment noted above).

**Status:** ✅ complete. Uncommitted (loop rule).

---

## Iteration 7 — derived URPS entrant count (mean of ACGME graduates = 64)

**Stopped (audited, not refactored) this iteration:**
- **Figure color palette** — tangled: multiple *intentional* theme palettes (app TEAL/ORANGE/RED
  `#1b7f79/#c77d1a/#d1495b` vs CMS federal blues `#205493…` vs exec navy `#20355e` vs manuscript
  GO/URPS blues), a GREEN that legitimately differs (`#2e8b57` vs `#2a9d8f`), and the self-contained
  Shiny copy is already test-pinned (`test-guards-app.R`). A multi-theme palette system is a dedicated
  effort, low-risk (aesthetic) → deferred.
- **Demand horizon (2050 / 25 yr)** — "2050" serves three distinct roles (the supply-demand CSV data
  endpoint, the Wu-2011 citation anchor year `2010→2050`, and display of `max(YEAR)`), which must NOT
  be collapsed. The horizon is effectively *data-driven* (the CSV's YEAR range) → not a single literal.
  Deferred.

**Candidate:** the URPS annual-entrant count (64) — a **derived** value (mean of `GRAD_URPS`
`c(61,66,63,66)`), hardcoded as a literal in the supply-demand producer.

**Why high-risk vs alternatives:** `scripts/urps_module_a_effective_supply` is the **producer of the
supply-demand CSV** the manuscript's demand section is built on; it hardcoded `ENTRANTS <- 64` while
already sourcing `GRAD_URPS`. If the ACGME graduate counts change, its supply projection would silently
use a stale entrant count, diverging from the SSOT.

**Provenance (audit):** canonical raw source = `WC_GRAD`/`GRAD_URPS` (iteration 3); the entrant count 64
is its derived mean, appearing as: engine `WC_ENTRANTS[["URPS"]]` (derived), frozen SSOT `annual_entrants`
(derived), and hardcoded `64` in `urps_module_a:21` (fixed → `mean(GRAD_URPS)`).

**Adjudication:** 64 is one derived value; the producer must derive it, not hardcode it. `HORIZON <- 25L`
on the same line is the **demand horizon (2025-2050)** — an intentional difference from `WC_HORIZON=4`,
explicitly preserved and now guarded.

**Canonical:** derived value = `mean(GRAD_URPS)` (equivalently engine `WC_ENTRANTS[["URPS"]]`); raw source
is the graduate counts (iteration 3).

**Files changed:** `scripts/urps_module_a_effective_supply_2026-07-23.R` (`ENTRANTS <- 64` →
`ENTRANTS <- mean(GRAD_URPS)`); new `tests/testthat/test-ssot-urps-entrants-derived.R`.

**Hardcoded copies removed:** 1 (the derived-value literal `64`). Behavior-preserving (mean = 64).

**Guards/tests added:** `test-ssot-urps-entrants-derived.R` (7 assertions): entrants == mean(GRAD_URPS)
== `WC_ENTRANTS[URPS]` == SSOT annual_entrants (three-lineage consistency); **intentional-difference guard**
(HORIZON=25 preserved, WC_HORIZON≠25); **adversarial** — the producer derives ENTRANTS from GRAD_URPS and
holds no `ENTRANTS <- <number>` literal.

**Test results:** urps-entrants-derived 7/0; + all 6 prior guards green (10/9/11/13/13/10); script parses,
ENTRANTS=64. No initial failures.

**Remaining risks:** `urps_module_a`/`urps_supply_demand_national` still hold `BANDS`/`ENTRY_AGE` literals
(source `urps_model_data`, not the engine; different dependency structure). Palette + subspecialty +
demand-horizon are stopped-tangled (need dedicated treatments). The clean single-literal engine-constant
SSOT is now largely complete.

**Recommended next candidate:** the age-productivity curve reference / normalization ("2025 averages 1.0")
in the Module-A effective-supply weighting; or the PFD-prevalence rate behind `women_with_pfd`; or a
dedicated subspecialty **mapping table** (`WC_SUBS`/`WC_SUBS_FULL` ↔ SSOT csv agreement guard); or the
color-palette theme module. NOTE: engine scalar constants are largely exhausted — prefer data/derived and
UI-claim candidates now.

**Status:** ✅ complete. Uncommitted (loop rule).

---

## Iteration 8 — age-specific PFD prevalence (Nygaard 2008 lookup)

**Candidate:** the age-specific pelvic-floor-disorder prevalence lookup — `0.097` (20-39), `0.265`
(40-59), `0.368` (60-79), `0.497` (80+) — embedded as anonymous magic numbers in a nested `fifelse`
inside the supply-demand producer.

**Why high-risk vs alternatives:** it weights the female-population projections into `women_with_pfd`,
the **demand denominator** that drives every published demand-side number (women-with-PFD per
urogynecologist, the PFD-prevalence index, the adequacy claims). It had **no validation and no named
provenance** (just a comment); a single-digit typo (`0.256` for `0.265`) would silently shift the
entire demand curve and go undetected. Single-sourced today, but a magic-number formula "capable of
drifting" with zero guardrails — higher-value than the remaining tangled candidates (palette/subspecialty).

**Provenance (audit):** the values appear ONLY in `scripts/urps_supply_demand_national_2026-07-23.R:18`
(the `prev()` function). Elsewhere PFD prevalence is prose/labels (docs, manuscript, `cms_..._10styles`
label) that read the computed `women_with_pfd` from the CSV — no other code copy. The prevalence age
bands (20/40/60/80) are DISTINCT from `WC_BANDS` (hazard bands) — not conflated.

**Adjudication:** one lookup, one code site → make it a named, validated, provenanced canonical. The
manuscript's "nearly one in four" is the *aggregate* adult-women figure — a DIFFERENT quantity from the
age-specific bands — preserved, not collapsed.

**Canonical:** `R/pfd_prevalence.R` — `PFD_PREVALENCE_BY_AGE` lookup + `pfd_prevalence_by_age(age)`
function (vectorized). Source: Nygaard et al., JAMA 2008;300(11):1311-16 (NHANES). Units: proportion
[0,1]. Fail-loud `stopifnot` (5 rows; all in [0,1]; age breaks strictly increasing; prevalence
non-decreasing).

**Files changed:** `scripts/urps_supply_demand_national_2026-07-23.R` (inline `fifelse` ladder →
`source(pfd_prevalence.R); prev <- pfd_prevalence_by_age`); new `R/pfd_prevalence.R`,
`tests/testthat/test-ssot-pfd-prevalence.R`.

**Hardcoded copies removed:** 1 (the inline magic-number formula). Behavior-preserving — proven by a test
that the canonical reproduces the original formula for **all ages 0-120**.

**Guards/tests added:** `test-ssot-pfd-prevalence.R` (15 assertions): **behavior-preservation oracle**
(canonical == original formula, ages 0-120); boundary pins at every Nygaard age group (19/20/39/40/…/80/120);
valid-proportion + non-decreasing; **adversarial** — the producer references the canonical and holds no
inline `fifelse(age<20…` ladder. Plus the module's own fail-loud `stopifnot`.

**Test results:** pfd-prevalence 15/0; all 7 prior guards green (10/13/13/11/9/10/7); producer parses;
inline ladder 0 hits in the producer. No initial failures.

**Remaining risks:** the demand producer still holds `BANDS`/other literals (sources `urps_model_data`,
not the engine). The Nygaard aggregate "one in four" in prose is unguarded (narrative, different quantity).

**Recommended next candidate:** the Module-A age-productivity normalization / the `apc` curve reference;
the demand-anchor citation numbers (Kirby `1,218,371→1,644,804`, Wu-2011 `376,700→555,020`) that appear
in both `urps_demand_denominators_sensitivity.R` and `URPS_DEMAND_DENOMINATOR_SENSITIVITY.md` (code↔doc
drift); or a dedicated subspecialty mapping table.

**Status:** ✅ complete. Uncommitted (loop rule).

---

## Iteration 9 — Kirby/Wu demand-anchor citation numbers  ⚠ FOUND A BUG

**Candidate:** the demand-denominator citation anchors — Kirby 2013 (1,218,371 → 1,644,804) and
Wu 2011 (376,700 → 555,020) — hardcoded as bare literals in `anchor_index()` calls.

**Why high-risk vs alternatives:** they drive the D2 (consultation) and D3 (surgery) demand curves in
the sensitivity, are *published citation numbers*, and appear as bare literals in the code **and** in
prose in two docs → code↔doc↔citation drift on numbers a reviewer will check.

**⚠ BUG FOUND (the SSOT process caught it):** deriving the Wu-2011 2050 total from its reported
components exposed an arithmetic slip — **SUI 310,050 + POP 245,970 = 556,020, not the 555,020** used
by the frozen analysis and the methods doc. A 1,000-off error. Handled conservatively: kept the anchor
at **555,020** to preserve the frozen D3 output (verified unchanged: D3 index = 127), and **tracked** the
discrepancy in a guard test so it is corrected *deliberately* (it moves D3 by <0.2% and would require
regenerating the supply-demand CSV/figure + updating the doc) rather than silently changed here.

**Provenance (audit):** code literals in `scripts/urps_demand_denominators_sensitivity.R` (anchor_index
args + comments); prose in `URPS_DEMAND_DENOMINATOR_SENSITIVITY.md` and
`URPS_WORKFORCE_LITERATURE_SYNTHESIS_2026-07-23.md`. No other code use.

**Canonical:** named scalar constants in the script — `KIRBY_VISITS_2010/2030`, `WU2011_SURG_2010/2050`
— with citation provenance in-comment and a fail-loud `stopifnot` on the 2010 decomposition. (Kept as
script constants, not a module: single-script consumer.)

**Files changed:** `scripts/urps_demand_denominators_sensitivity.R` (added named anchor constants;
`anchor_index()` literals → constants); new `tests/testthat/test-ssot-demand-anchors.R`.

**Hardcoded copies removed:** 4 bare literals from the `anchor_index` calls. Behavior-preserving
(script re-run → identical 2050 indices 179/119/146/127).

**Guards/tests added:** `test-ssot-demand-anchors.R` (17 assertions): value pins; 2010 decomposition
(210,700+166,000=376,700); **tracked 2050 discrepancy** (310,050+245,970=556,020; frozen anchor 1,000
less); **code↔doc** (methods doc quotes all 8 numbers); **adversarial** — anchor_index holds no bare
literal.

**Test results:** demand-anchors 17/0; all 8 prior guards 0 failures; **script re-runs green with
identical output**. Initial failure: my first attempt DERIVED the 2050 total from components and the
`stopifnot`/script failed (556,020≠555,020) — which is exactly how the bug surfaced; fixed by pinning
the frozen 555,020 + tracking the discrepancy.

**Remaining risks:** the 555,020 arithmetic slip should be corrected deliberately (→556,020) with a
CSV/figure regenerate + doc update — a small manuscript-adjacent change deferred to the PI. Kirby/Wu
prose in the docs is still manually kept in sync (guarded now for the sensitivity doc, not the synthesis).

**Recommended next candidate:** the Module-A age-productivity curve / its "2025 averages 1.0"
normalization; a dedicated subspecialty mapping table (`WC_SUBS`/`WC_SUBS_FULL` ↔ SSOT csv guard); or the
figure-palette theme module. Note: **flag the 556,020 correction to the user** — it is a real (if tiny) bug.

**Status:** ✅ complete. Uncommitted (loop rule).

---

## Iteration 10 — graduate-to-practice conversion floor (`WORKFORCE_CONVERSION_FLOOR` = 0.70)

**Candidate:** the conservative graduate-to-practice conversion factor — 0.70 (70%) — a scenario
assumption used in both the scenario code and the manuscript.

**Why high-risk vs alternatives:** it is a *published sensitivity assumption* ("70% to 100% conversion")
that appears as a bare literal in **two different lineages** — `graduate_growth_scenarios.R` (`0.7*m`,
engine lineage) and the manuscript's `get_tipping_missed_range(0.70)` (contract lineage) — plus prose
and frozen sensitivity data. If one changed, the code and the paper would silently disagree on a stated
sensitivity value. First **cross-lineage** SSOT: both lineages reach the shared `R/workforce_constants.R`
(engine sources it directly; manuscript via workforce_statistics → contract → constants).

**Provenance (audit):** `scripts/graduate_growth_scenarios.R:33` (`0.7*m`);
`manuscript/manuscript_WORKFORCE_CLIFF.Rmd:105` (`get_tipping_missed_range(0.70)`); prose "70% to 100%"
(Rmd:105, 109) and scenario labels; frozen `data/sensitivity_grid_summary.csv` conversion column (0.7),
`data/graduate_growth_scenarios.csv` (label). No incompatible copies.

**Adjudication:** one value, two code sites + prose + data → canonical constant referenced by both code
sites. The `get_tipping_missed_range(1.0)` on the same manuscript line is the "all completers enter"
ceiling — a DIFFERENT value (100%), left as the self-evident 1.0.

**Canonical:** `R/workforce_constants.R::WORKFORCE_CONVERSION_FLOOR <- 0.70` — conservative conversion
floor; proportion (0,1]; study-design sensitivity floor; fail-loud validation. Verified in scope in BOTH
lineages (engine 0.7; manuscript 0.7).

**Files changed:** `R/workforce_constants.R` (+ constant); `scripts/graduate_growth_scenarios.R`
(`0.7*m` → `WORKFORCE_CONVERSION_FLOOR*m`); `manuscript/manuscript_WORKFORCE_CLIFF.Rmd`
(`get_tipping_missed_range(0.70)` → `…(WORKFORCE_CONVERSION_FLOOR)` — **first iteration to touch the
manuscript**, behavior-preserving, constant verified in render scope); new
`tests/testthat/test-ssot-conversion-floor.R`.

**Hardcoded copies removed:** 2 (one per lineage). Behavior-preserving (0.70 unchanged, in scope both places).

**Guards/tests added:** `test-ssot-conversion-floor.R` (10 assertions): value pin (0.70, proportion);
**both lineages reference the constant, not a literal** (adversarial, code + manuscript); prose "70%"
matches (`sprintf(100*CF)`); **frozen sensitivity-grid conversion axis contains the floor** (drift guard).

**Test results:** conversion-floor 10/0; ALL 10 SSOT guards 0 failures; contract 63/0 (no regression from
the new constant); scripts parse; constant resolves in manuscript scope. No initial failures.

**Remaining risks:** the manuscript prose "70% to 100%" is manually kept in sync (guarded on the 70).
`get_tipping_missed_range(1.0)` ceiling is a literal (trivial 100%). The manuscript Rmd was edited but not
re-rendered here (render deps exist; the change is a same-value substitution).

**Recommended next candidate:** the 3x departure-rate-multiplier sensitivity axis (also in
`sensitivity_grid_summary.csv` and prose); the subspecialty mapping table (`WC_SUBS_FULL` ↔ SSOT csv
guard); or the age-productivity curve normalization.

**Status:** ✅ complete. Uncommitted (loop rule).

---

## Iteration 11 — Monte-Carlo iteration count  ⚠ FIXED A CODE↔DOC BUG

**Stopped (audited, not refactored):** the **3× departure-rate multiplier** — lives almost entirely in
manuscript prose ("threefold"/"tripled"/"three times"), one figure label ("3x departure rate"), and the
frozen `sensitivity_grid_summary.csv`; there is no grid-producer script and no code computation using a
bare `3`, so nothing clean to consolidate. Deferred.

**Candidate:** the frozen projection Monte-Carlo iteration count.

**Why high-risk vs alternatives:** it is a *published number* ("10,000-iteration Monte Carlo") whose
named constant **disagreed with the paper by 10×**.

**⚠ BUG FOUND & FIXED:** `WORKFORCE_MONTE_CARLO_ITERATIONS <- 1000L` (contract) contradicted the
manuscript Methods ("10,000-iteration Monte Carlo parameter-uncertainty simulation") and the supply-line
figure caption ("10,000 iterations") — both describing the SAME projection MC. Audit: the constant was a
**dead alias** (only re-exported as `N_MONTE_CARLO_ITERATIONS`, never consumed; no test pins it), so
correcting it is behavior-preserving. Weight of evidence → the frozen run used **10,000**; the `1,000` was
stale/typo. (`code/07`'s `B=10000` is a separate table-1 bootstrap, not this MC.)

**Provenance (audit):** `manuscript/R/workforce_data_contract.R:50` (constant, was 1000);
`workforce_statistics.R:30` (alias); `manuscript_WORKFORCE_CLIFF.Rmd:129` (prose "10,000");
`scripts/fig_fpmrs_supply_line.R:84` (caption "10,000"); `code/07:304` (`B=10000`, different MC).

**Adjudication:** one value, authoritative = 10,000 (paper + figure). Corrected the dead constant to
10,000 and tied the manuscript's stated count to it (inline). `code/07` B is a different bootstrap → not
touched.

**Canonical:** `WORKFORCE_MONTE_CARLO_ITERATIONS <- 10000L` (contract), re-exported as
`N_MONTE_CARLO_ITERATIONS`. Meaning: iteration count of the frozen projection parameter-uncertainty MC.

**Files changed:** `manuscript/R/workforce_data_contract.R` (1000L → 10000L + provenance comment);
`manuscript/manuscript_WORKFORCE_CLIFF.Rmd` (`10,000-iteration` prose → `r format(WORKFORCE_MONTE_CARLO_ITERATIONS, big.mark=",")`);
new `tests/testthat/test-ssot-mc-iterations.R`.

**Hardcoded copies removed:** 1 (the manuscript prose literal now derives from the constant); constant
corrected. Behavior-preserving (dead constant; manuscript still renders "10,000" — verified in scope).

**Guards/tests added:** `test-ssot-mc-iterations.R` (8 assertions): constant == 10,000L; alias references
the constant; manuscript derives the count (no bare "10,000-iteration" literal); **code↔doc** (figure
caption contains the canonical count).

**Test results:** mc-iterations 8/0; contract 63/0 (no regression — constant is dead); all 11 SSOT guards
0 failures; manuscript scope renders "10,000".

**Remaining risks:** none for this value. The random seed `20260718` (manuscript) vs `20260720`
(hierarchical_hazard) may be intentional per-analysis seeds — needs a look before treating as SSOT.

**Recommended next candidate:** the subspecialty mapping table (`WC_SUBS_FULL` ↔ SSOT csv display-name
guard); the age-productivity curve normalization; or the per-analysis random seeds (verify intentional).
Note: **flag the 1,000→10,000 correction to the user** — the contract constant was wrong by 10×.

**Status:** ✅ complete. Uncommitted (loop rule).

---

## Iteration 12 — subspecialty name mappings (`WC_SUBS` / `WC_SUBS_FULL`)

**Candidate:** the subspecialty abbreviation→name mappings — `WC_SUBS` (data-match strings) and
`WC_SUBS_FULL` (display names). Stopped in iteration 6 for a *full* refactor; done here as a
canonical-move + code↔data guard.

**Why high-risk vs alternatives:** the display names are duplicated across ~10 files (manuscript table
builder, taxonomy scripts, legacy `code/`, NRMP fetch) AND held independently by the frozen SSOT csv
`subspecialty` column; a mislabel (e.g. the SSOT csv edited but the engine constant not) would misfilter
cohorts or mislabel published results. There is also an intentional trap: `WC_SUBS[URPS]` = "Female Pelvic
Medicine & Reconstructive Surgery" (the label the source data is stored under) differs from
`WC_SUBS_FULL[URPS]` = "Urogynecology and Reconstructive Pelvic Surgery" (display) — must not be collapsed.

**Provenance (audit):** canonical was engine-only (`R/workforce_cliff_engine.R:27-28`); frozen SSOT csv
`subspecialty` column (verified **exact match** to WC_SUBS_FULL); ~10 non-engine files hardcode the
display names (manuscript_consolidate, create_workforce_table, analyze_urps_taxonomy(_detailed),
fetch_nrmp_fellowship_entrants, code/*). None of them source the engine, so the engine-only constant
couldn't reach them.

**Adjudication:** one display mapping (all copies agree today) → move canonical to the shared module so
BOTH lineages can reach it; add a code↔data drift guard vs the SSOT csv; preserve the URPS match-vs-display
distinction (guarded). The non-engine hardcoders are deferred (now that the mapping is shared, a future
iteration can migrate them once they source `workforce_constants`).

**Canonical:** moved `WC_SUBS` + `WC_SUBS_FULL` into `R/workforce_constants.R` (shared, sourced by the
engine and reachable by the manuscript lineage via contract→constants), with fail-loud validation (URPS/GO/
MIGS keys; non-empty; URPS match≠display).

**Files changed:** `R/workforce_constants.R` (+ mappings + validation); `R/workforce_cliff_engine.R`
(removed the two local defs — now sourced from the module); new `tests/testthat/test-ssot-subspecialty-mapping.R`.

**Hardcoded copies removed:** 1 (the engine's local defs → shared module). Behavior-preserving: the engine
still exposes `WC_SUBS`/`WC_SUBS_FULL` (verified) and `wc_load_cohort` still filters by `WC_SUBS`.

**Guards/tests added:** `test-ssot-subspecialty-mapping.R` (13 assertions): well-formed named vectors;
**code↔data** (WC_SUBS_FULL == SSOT csv subspecialty column, per key); **intentional-difference guard**
(URPS match≠display; GO equal); engine still exposes the moved constants; adversarial — no engine-sourcing
script re-hardcodes `WC_SUBS_FULL`.

**Test results:** subspecialty-mapping 13/0; all 12 SSOT guards 0 failures; contract 63/0; engine loads and
exposes the moved constants. No initial failures.

**Remaining risks:** ~10 non-engine files still hardcode the display names (manuscript table builder,
taxonomy, legacy code/, NRMP fetch); they're consistent today but unguarded and could drift. Migrating them
to `WC_SUBS_FULL` (via sourcing `workforce_constants`) is the deferred follow-up.

**Recommended next candidate:** migrate one non-engine display-name hardcoder to the shared mapping
(e.g. `manuscript/R/create_workforce_table.R` or the taxonomy scripts); the age-productivity curve
normalization; or the per-analysis random seeds (verify intentional).

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 1-12 files only.

---

## Iteration 13 — NRMP entrants CSV `subspecialty` display names → shared `WC_SUBS_FULL`

**Candidate considered first (STOPPED): reproducibility random seeds.** Audited every `set.seed()`:
`20260718` (projection MC, manuscript-cited), `20260720` (hierarchical-hazard bootstrap), `20260723`
(supply-demand producer), plus a named `MC_SEED` already used in the shiny and test-only seeds (42, 424242,
20260719). These are **intentional per-analysis** seeds — each analysis owns its own reproducibility seed,
and the manuscript's `20260718` refers to the *frozen no-code archival* MC (no live literal to bind). No
clean single-source refactor exists and the "should these share one seed" authority is unclear → **stopped
per step 3** (never collapse intentional differences). Documented here so it isn't re-audited.

**Selected candidate: the `subspecialty` display-name column in `scripts/fetch_nrmp_fellowship_entrants.R`
(lines 49-51).** This was a THIRD independent copy of the canonical display names (`WC_SUBS_FULL`), and —
unlike the deferred hardcoders — it feeds a **canonical data file** (`data/nrmp_fellowship_entrants.csv`,
consumed by the NRMP-entrants sensitivity). A drift here would silently rename a subspecialty in a published
input. Directly reduces iteration 12's "remaining risk."

**Why higher-risk than alternatives:** it is (a) a producer of a canonical artifact, not just display text,
and (b) already reachable from the shared module (iter 12 made `WC_SUBS_FULL` shared), so the migration is
clean and low-blast-radius — the best available now that the seeds candidate is stopped.

**Discrepancy check:** the script holds TWO subspecialty-name columns — `subspecialty` (== `WC_SUBS_FULL`)
and `nrmp_label` ("Female Pelvic Medicine and Reconstructive", the string used to grep the NRMP PDF text).
Adjudication: `subspecialty` is a duplicated copy → derive from SSOT; `nrmp_label` is a **different value**
(PDF-search label ≠ display name) → **kept local**, distinctness guarded. Derived values verified byte-
identical to the prior literals AND to the on-disk CSV.

**Canonical:** unchanged — `R/workforce_constants.R::WC_SUBS_FULL` (from iter 12). This iteration wires a
consumer to it.

**Files changed:** `scripts/fetch_nrmp_fellowship_entrants.R` (sources `workforce_constants`; `subspecialty`
column now `unname(WC_SUBS_FULL[.nrmp_abbrev])`; two fail-loud `stopifnot` — abbrevs ⊆ SSOT keys, no NA/empty
names); new `tests/testthat/test-ssot-nrmp-display-names.R`.

**Hardcoded copies removed:** 1 (the display-name literal in the producer). `nrmp_label` intentionally retained.

**Guards/tests added:** `test-ssot-nrmp-display-names.R`: **code↔data** (emitted CSV `subspecialty` ==
`WC_SUBS_FULL` per key); **behavior-preserving** (derived == exact prior literals); **no re-typed literal**
(grep: derives via `WC_SUBS_FULL[`, sources the module, no `subspecialty = c("Urogynecology…`); **intentional-
difference** (`nrmp_label` for URPS stays distinct from the display name).

**Test results:** nrmp-display-names 4/0; all 13 SSOT guards 145/0; cliff-contract 63/0; script parses;
derived==old==CSV verified. No initial failures.

**Remaining risks:** ~9 non-engine files still hardcode the display names (manuscript table builder,
taxonomy, legacy `code/`); consistent today but unguarded. Same migration pattern applies to each.

**Recommended next candidate:** migrate the next display-name hardcoder (`manuscript/R/create_workforce_table.R`
or `analysis/taxonomy/*`) to `WC_SUBS_FULL`; OR the age-productivity curve normalization ("2025 averages 1.0"
in `urps_module_a`); OR the demand age thresholds (women 65+/40+) if used in more than the one producer.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 1-13 files only.

---

## Iteration 14 — FPMRS supply-line figure projection **year axis** → derived from the horizon SSOT

**Selected candidate: the projection year axis in `scripts/fig_fpmrs_supply_line.R`.** The endpoint
`2029` was hardcoded in many entangled forms — `year = 2025:2029` (data), `(0:4)/4` and `length.out = 5`
(horizon-encoding interpolation), three `year == 2029` anchor/CI filters, the `2024.5` observed↔projected
divider, the `c(2013,…,2029)` breaks list, and the title/subtitle/annotation year ranges. `2029` is not a
free number: it is `PROJ_YEAR0 (2025) + WORKFORCE_PROJECTION_HORIZON_YEARS`.

**Why higher-risk than alternatives:** the **sibling** figure `scenario_projection_trajectories.R` already
derives the *same* axis from `WC_YEAR0`/`WC_HORIZON` (`year = YEAR0 + 0:HORIZON`). This figure was the
manually-synchronized copy — change the horizon SSOT and the trajectory figure updates while this published
supply figure silently strands at 2029. Two representations of one axis, one derived and one literal, is the
textbook "capable of drifting" SSOT case. It is also an **active manuscript figure** (its caption is already
guarded by the iter-11 MC-iterations test).

**Discrepancy investigation / intentional differences preserved (step 3):**
- The `2025:2050` ranges elsewhere (`urps_demand_*`, module B/C) are the **25-year demand horizon** (iter 7),
  a *different* intentional horizon — **not** touched.
- The many hardcoded **supply** numbers in this file (`1196`, `1283`, `1301`, `4.4`, `55.6`, `1.08`, `15.2`,
  CI `1271/1330`) are a separate, larger SSOT risk (they should read `data/workforce_projections_consolidated.csv`),
  but they are *multiple* values and entangled with the **off-limits 1,295-vs-1,339 baseline** → out of scope
  for a single-value iteration; recorded as future work, **left untouched**.
- `2013` (observed start), `2024` (last observed / boundary), `2022–2024` (ACGME data window) are observational
  literals, not the projection horizon. `2024`/`2024.5` were re-expressed as `PROJ_YEAR0 - 1` / `- 0.5` (the
  projection boundary, genuinely horizon-adjacent); `2013` kept as `OBS_START`; `2022–2024` left literal.

**Canonical contract:** unchanged canonical = `R/workforce_constants.R::WORKFORCE_PROJECTION_HORIZON_YEARS`
(4L, integer). This iteration wires a consumer to it and adds local derived symbols `PROJ_YEAR0=2025L`,
`PROJ_HORIZON`, `PROJ_END`, `PROJ_YEARS`, `OBS_START`, `OBS_END`.

**Files changed:** `scripts/fig_fpmrs_supply_line.R` (sources the module; all plotted years derived);
new `tests/testthat/test-ssot-fig-projection-axis.R`.

**Hardcoded copies removed:** the literal projection axis (`2025:2029`), the `/4` + `length.out=5` horizon
encodings, 3× `year == 2029`, the `2024.5` divider, the literal breaks list, and 3 title/label year-range
literals — all now derived. No supply/rate/CI number changed.

**Validation guard (fail-loud):** `stopifnot(PROJ_END == 2029L, PROJ_HORIZON == 4L, length(PROJ_YEARS) == 5L)`
— the frozen supply endpoints (1,283→1,301) and CI are a published **4-year** result, so the figure refuses to
silently render a mislabeled axis over unchanged data if the horizon SSOT drifts (forces a data regen first).

**Tests added:** `test-ssot-fig-projection-axis.R` (17 assertions): derives-from-SSOT + no stranded literals
(grep); fail-loud pin present; **behavior-preserving** (horizon=4 re-derivation == prior literals, incl. the
9-element breaks, byte-value); **semantic tracking** (horizon=5 → endpoint 2030, span 2025:2030, 6 points —
proves derived not literal); **code↔SSOT** (endpoint == 2025 + sourced constant); **adversarial** (sibling
trajectory figure also derives from `WC_YEAR0`/`WC_HORIZON`, so the two can't diverge).

**Initial failures:** one — the behavior test compared integer `seq()` breaks against double literals via
`identical` (type mismatch only). Cause: `seq(…, 2L)` returns integer; the original `c(2013, …)` was double.
Fix: compare by value (`as.numeric`, `==`); values identical. End-to-end build (ggsave stubbed) succeeds;
PNG artifact unchanged.

**Final results:** fig-projection-axis 17/0; all **14 SSOT guards 162/0**; cliff-contract 63/0; figure parses
and builds.

**Remaining risks:** the figure's hardcoded **supply/rate/CI numbers** (1196/1283/1301/4.4/55.6/1.08/15.2/CI)
are still copied rather than read from the consolidated CSV — a genuine SSOT gap, but a multi-value one gated
on the off-limits baseline re-run. Also a stale doc comment in `R/calculate_retirement_cliff_statistics.R:35`
("2029 (5-year projection window)") mislabels the horizon as 5 — a doc-drift bug to fix in a future iteration.

**Recommended next candidate:** the stale "5-year projection window" doc comment (quick doc↔SSOT fix); OR the
next display-name hardcoder migration (`manuscript/R/create_workforce_table.R` / taxonomy); OR the
age-productivity curve normalization ("2025 averages 1.0" in `urps_module_a`).

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 1-14 files only.

---

## Iteration 15 — parametric **95% CI z-multiplier** (1.96) → shared `WORKFORCE_CI_Z95`

**Selected candidate: the 95% CI z-multiplier `1.96`.** A canonical `WORKFORCE_CI_Z95 <- 1.96` already
existed in `manuscript/R/workforce_data_contract.R:58` and two consumers referenced it, but a **literal
`1.96`** was stranded in the active supply-line figure (`scripts/fig_fpmrs_supply_line.R:42-43`, `15.2 * 1.96`).

**Why higher-risk than alternatives:** it multiplies the SD of **every published parametric CI** — projection
endpoints, the FPMRS supply figure, the replacement-ratio appendix. A drift between the canonical and the
stranded figure literal would silently mis-state a published interval. The canonical also lived only in the
*manuscript* contract, unreachable by the figure (which sources the shared module), so the two could diverge.

**Provenance table (active scope):**
| file:line | value | role | verdict |
|---|---|---|---|
| `manuscript/R/workforce_data_contract.R:58` | `WORKFORCE_CI_Z95 <- 1.96` | prior canonical (manuscript-only) | **relocated** to shared module |
| `scripts/fig_fpmrs_supply_line.R:42-43` | `15.2 * 1.96` | active figure CI | **refactored** → constant |
| `scripts/rebuild_ssot_from_nrmp.R:25` | `Z <- WORKFORCE_CI_Z95` | already references canonical | unchanged |
| `R/manuscript_consolidate_existing_results.R:182-183` | `WORKFORCE_CI_Z95 * sd_2029` | already references canonical | unchanged |
| `code/0{1,2}_*.R` | `1.96 * sd_2029` | **legacy** standalone dir | out of scope (not the active pipeline) |
| `code/03_create_abstract_figure.R:84-85` | `1.645` | **90% CI** (different conf level) | intentional — NOT collapsed |
| `R/calculate_retirement_cliff_statistics.R:296,312` | `qnorm(1-(1-conf_level)/2)` | general parametrized CI | intentional — NOT collapsed |
| `manuscript/appendix_workforce_replacement_ratio.Rmd:85` | `\pm 1.96 \times \sigma_t` | LaTeX display math (prose) | left as prose (flagged) |
| `tests/testthat/test-bug-workforce-go-loss-and-ci-label.R` | `1.96` ×N | regression **oracle** fixtures | left literal (independent oracle) |

**Discrepancies / adjudication:** the only genuine drift copy in active code was the figure literal. The
`1.645` (90%) and `qnorm(conf_level)` (general) are *different confidence semantics* — collapsing them would
be wrong, so both preserved and guarded. Test fixtures pin `1.96` deliberately (an SSOT test that referenced
the constant couldn't catch a wrong constant) → left literal.

**Canonical contract:** `R/workforce_constants.R::WORKFORCE_CI_Z95` — dimensionless two-sided 95% z-score,
value `1.96` (`== round(qnorm(0.975), 2)`), range (1.9, 2.0). Chosen as a **named constant in the shared
module** (fixed value, reached by both lineages). Consumers: contract (re-export), supply figure, NRMP
rebuild, consolidate producer.

**Files changed:** `R/workforce_constants.R` (+ constant + provenance + fail-loud validation incl. the
`round(qnorm(0.975),2)==1.96` source check); `manuscript/R/workforce_data_contract.R` (removed local literal;
`stopifnot(exists("WORKFORCE_CI_Z95"))` proves it arrives from the module); `scripts/fig_fpmrs_supply_line.R`
(`1.96` → `WORKFORCE_CI_Z95`, ×2); new `tests/testthat/test-ssot-ci-z95.R`.

**Hardcoded copies removed:** 2 (the figure's `15.2 * 1.96` ×2) + 1 relocated (the contract's local def).
Behavior-preserving: CI values byte-identical (`[1253..1271]` / `[1313..1330]`); contract still exposes 1.96;
figure builds; the ±1.96 regression oracle still passes (18/0).

**Validation guard (fail-loud):** the module `stopifnot` rejects a non-numeric, out-of-range, or non-95%
value — `round(qnorm(0.975),2) == WORKFORCE_CI_Z95` ties it to the actual 95% z so a typo (e.g. 1.69) fails
loudly at load.

**Tests added:** `test-ssot-ci-z95.R` (17 assertions): canonical well-formed + == qnorm(0.975); contract
re-exports & no local literal (behavior-preserving); exact interval reproduction; figure references the
constant / no stranded literal; **intentional-difference guards** (code/03 keeps 1.645 and does NOT reference
the constant; the qnorm-from-conf_level path stays a function); **adversarial** (no active `scripts/` file
multiplies an SD by a bare 1.96).

**Initial failures:** none — narrow 17/0 on first run; all 15 SSOT guards 179/0; contract 63/0; CI-label
oracle 18/0.

**Remaining risks:** the appendix LaTeX (`\pm 1.96 \times \sigma_t`) and the legacy `code/` dir still contain
literal `1.96` — the appendix is display math (prose) and `code/` is the retired standalone pipeline; neither
feeds the active outputs, but both would drift if the z ever changed. Tying the appendix to the constant via
inline R is a possible future doc↔SSOT fix.

**Recommended next candidate:** the stale `R/calculate_retirement_cliff_statistics.R:35` "5-year projection
window" doc comment (doc↔SSOT); OR the replacement-ratio label thresholds (1.05 / 0.95 / 1.20 in the contract
— verify no scattered literal copies in figures/labels); OR the next display-name migration.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 1-15 files only.

---

## Iteration 16 — TEST_MODE stub `replacement_assessment` → derived from `classify_replacement(ratio)`

**Candidate considered first (verified already-single-sourced): the replacement thresholds 1.05 / 0.95 / 1.20.**
Audited every use — they live once in the contract (`WORKFORCE_REPLACEMENT_ABOVE_MIN/AT_MIN/BUFFER`), the
classifier `classify_replacement()` consumes the constants, the fail-loud validator re-derives and checks the
frozen CSV against them (contract:232-234), and the manuscript only *describes* the band in prose. No
duplicated logic → not a refactor candidate. Recorded so it isn't re-audited.

**Selected candidate: the `replacement_assessment` label in the TEST_MODE stub of
`R/manuscript_consolidate_existing_results.R` (lines 52/56/60).** It hardcoded `"Above replacement"` three
times, once per subspecialty, **in parallel with** the stub's `replacement_ratio` (1.26 / 7.11 / 11.06) —
even though the file sources the contract and the assessment is a pure function of the ratio.

**Why higher-risk than alternatives:** the assessment is *independently calculated / manually synchronized*
against the ratio in the same row. The **production** path already derives it (`classify_replacement(ratio)`,
line ~215) and the contract validator guards the **frozen CSV** — so the stub was the *only* place in the
whole assessment chain that re-typed the value by hand. Edit a stub ratio for a new test scenario (e.g. to
exercise "Below replacement") and the hardcoded label silently disagrees, making the fixture lie to every
test that consumes it.

**Discrepancy investigation:** stub ratios 1.26/7.11/11.06 all classify to "Above replacement" (verified) —
consistent *today*, so this is latent, not an active bug. No intentional difference exists (the stub is meant
to mirror production, which derives). Production (line 215) and the frozen CSV (validator) are already clean —
**not touched**.

**Canonical contract:** `manuscript/R/workforce_data_contract.R::classify_replacement(ratio)` — a **pure
function** returning a `WORKFORCE_VALID_ASSESSMENTS` label from the ratio thresholds. (Function, not constant,
because the value depends on an input.) The right SSOT type for a derived-from-input value.

**Files changed:** `R/manuscript_consolidate_existing_results.R` (stub now builds the tribble without the
assessment column, then `dplyr::mutate(replacement_assessment = classify_replacement(replacement_ratio)) %>%
relocate(.after = replacement_ratio)`); new `tests/testthat/test-ssot-stub-replacement-assessment.R`.

**Hardcoded copies removed:** 3 (`"Above replacement"` ×3 in the stub tribble). Now derived by the same
function production uses. Behavior-preserving: 16 columns, `replacement_assessment` still at position 13
(immediately after `replacement_ratio`), all three values still "Above replacement" (byte-identical).

**Validation guard:** the derivation itself is the guard — the stub can no longer disagree with its own ratios
(self-consistent by construction), and it now shares the production classifier so a threshold change flows to
both. (No new constant added; reuses the existing fail-loud contract validator.)

**Tests added:** `test-ssot-stub-replacement-assessment.R` (9 assertions): **self-consistency** (stub
assessment == `classify_replacement(ratio)` every row); **behavior-preserving** (== the prior 3 literals +
column position after ratio + all ∈ `WORKFORCE_VALID_ASSESSMENTS`); **semantic** (classifier boundary:
1.06→Above, 1.00→At, 0.94→Below, proving it's a function not a constant); **adversarial** (no assessment label
literal remains inside the stub block; the stub derives via `classify_replacement`).

**Initial failures:** none — narrow 9/0 first run.

**Final results:** stub-assessment 9/0; all **16 SSOT guards 188/0**; cliff-contract 63/0; replacement-ratio
fallback 18/0; CI-label oracle 18/0; **all 7 stub-consumer suites 581/0** (schema/order fully preserved).

**Remaining risks:** the stub still hardcodes many *other* fixture numbers (baseline/projected/sd/CI/ratio) —
these are legitimate stub INPUTS (they seed the tested computation), not derived duplicates, so they stay. The
appendix LaTeX `1.96` and legacy `code/` copies (iter 15) remain.

**Recommended next candidate:** the stale `R/calculate_retirement_cliff_statistics.R:35` "5-year projection
window" doc comment (doc↔SSOT — mislabels the 4-year horizon); OR the `WORKFORCE_VALID_ASSESSMENTS` label
strings that appear as literals in `workforce_statistics.R` docstrings (449-453); OR the next display-name
migration (`manuscript/R/create_workforce_table.R`).

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 1-16 files only.
