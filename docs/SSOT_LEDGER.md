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
**NOTE:** iterations 1-16 + the reframed manuscript were committed & pushed to `origin/main` as `2380210`
(2026-07-25, at Tyler's explicit instruction). The loop otherwise never commits; this was a one-off sync.

---

## Iteration 17 — CONUS geographic scope (non-CONUS FIPS list + lon/lat bounding box) → `R/conus.R`

**Selected candidate: the CONUS (contiguous-US) geographic scope.** Confirmed with Tyler as the next
iteration. Two representations, both previously copy-pasted per script:
- **non-CONUS FIPS list** `c("02","15","72","60","66","69","78")` (AK, HI, PR, AS, GU, MP, VI) — **4 verbatim
  copies** + a variant positive encoding `setdiff(1:56, c(2,15))`.
- **CONUS lon/lat bounding box** `lon ∈ (-125,-66), lat ∈ (24,50)` — **3 copies** (keep + De-Morgan negation).

**Why higher-risk than alternatives:** the highest raw duplication remaining in the repo (7 literal copies
across 4 files), it defines the **study's geographic denominator** for every Module-D access map/metric, and
it is *not* baseline-entangled (unlike the workforce-size numbers) — so it is both high-impact and cleanly
refactorable. Fix a territory in one copy and the maps silently disagree.

**Provenance table:**
| file:line | literal | mechanism | verdict |
|---|---|---|---|
| `differential_distance.R:19,56,27` | NONCONUS list; STATEFP filter; bbox | both | duplicated → canonical |
| `differential_map.R:9,13,15` | NONCONUS list; STATEFP ×2 | FIPS | duplicated → canonical |
| `geographic_access.R:25,61,66,43,44` | NONCONUS; GEOID-prefix; `setdiff(1:56,c(2,15))`; bbox ×2 | both | duplicated + variant → canonical |
| `map.R:11,19` | NONCONUS list; STATEFP | FIPS | duplicated → canonical |
| `test-yoy-...saboteurs.R:456` | latitude `[24,50]` | coord-repair heuristic | **intentional — left** (geocoding lon-sign fix oracle, not CONUS scope) |
| parent isochrones repo `NON_CONTIGUOUS_CODES` | — | — | separate repo, cannot source; cliff needs its own |

**Discrepancies / adjudication:** the FIPS list and the bbox are *different mechanisms* (administrative
geography vs raw coordinates) for the same scope — kept as two named canonicals in one module, not collapsed.
The `setdiff(1:56, c(2,15))` at `geographic_access:66` is a redundant positive encoding: combined with the
NONCONUS exclusion it selects the 48 states + DC; on the tigris `counties(cb=TRUE)` STATEFP domain
(`{01..56 real, 60,66,69,72,78}`) `is_conus_fips()` alone yields the **identical** set, so the two conditions
were replaced by the single canonical call (the only FORM change; documented, equivalence proven by the known
STATEFP domain). The yoy-saboteur test's `[24,50]` latitude is a coordinate-repair heuristic, not the CONUS
box — left untouched.

**Canonical contract:** new **`R/conus.R`** (pure constants + functions, no path deps):
- `CONUS_EXCLUDE_FIPS` — 7 zero-padded 2-digit FIPS; `is_conus_fips(fips)` (works on STATEFP and GEOID prefix).
- `CONUS_LON = c(-125,-66)`, `CONUS_LAT = c(24,50)`; `in_conus_bbox(lon,lat)` (open box, 3-valued: NA→NA, so
  De Morgan holds and `!in_conus_bbox()` is the exact prior "outside" test).

**Files changed:** new `R/conus.R`; `scripts/urps_module_d_{differential_distance,differential_map,
geographic_access,map}.R` (source the module; use `is_conus_fips()` / `in_conus_bbox()`); new
`tests/testthat/test-ssot-conus-scope.R`.

**Hardcoded copies removed:** 4 NONCONUS list literals + 3 bbox literal expressions + 1 `setdiff(1:56,c(2,15))`
variant. Behavior-preserving: FIPS-filter, bbox-keep, De-Morgan negation, and the explicit-`is.na` keep form
all verified byte-identical to the prior literals (including NA edge cases) over a test grid.

**Validation guards (fail-loud, in the module):** exactly 7 two-digit FIPS incl 02+15, no dups; bbox
west<east / south<north within a sane North-American window.

**Tests added:** `test-ssot-conus-scope.R` (28 assertions): FIPS list well-formed; `is_conus_fips` semantics
(STATEFP + GEOID prefix, AK/HI/PR/DC); `in_conus_bbox` semantics (interior/exterior/open-boundary/NA);
**behavior-preserving** (helpers == prior literal expressions incl NA + De Morgan); **adversarial** (no
Module-D script re-defines NONCONUS, re-hardcodes a bbox coordinate literal, or fails to source `R/conus.R`);
**consistency** (every Module-D script references a canonical helper).

**Initial failures:** 1 — the adversarial bbox-literal grep false-matched `-66` inside the age-band comment
`65-66,67-69` (`geographic_access:54`). Cause: too-loose regex. Fix: require the minus not be preceded by a
digit (`(?<![0-9])-66`, perl), so coordinate literals match but age ranges don't. Re-ran green.

**Final results:** conus-scope 28/0; all **17 SSOT guards 216/0**. (Module-D scripts are standalone geographic
producers — no contract/integration suite consumes them; the geo data files needed to fully *run* them aren't
in-tree, so validation is parse + equivalence + guards.)

**Remaining risks:** the module-D scripts can only be parsed + unit-checked here (their ACS/roster/shapefile
inputs aren't vendored), so a full end-to-end render wasn't exercised — but every value is provably identical.
The parent isochrones repo has its own `NON_CONTIGUOUS_CODES`; the two canonicals are intentionally separate
(different repos) and could theoretically drift from each other — acceptable, documented.

**Recommended next candidate:** the `MI <- 1609.344` metres-per-mile constant (duplicated in
`differential_distance` + `geographic_access`, likely more); OR the stale `calculate_retirement_cliff_statistics.R:35`
"5-year projection window" doc comment; OR the ACS women-65+ variable set `B01001_044:049` (appears in the
demand modules — verify one definition).

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = this iteration's files (+ the prior
`docs/FLAG_stale_workforce_table_hardcode.md` note).
**NOTE:** iteration 17 (+ the flag note) was committed & pushed to `origin/main` as `eb6862b`
(2026-07-25, Tyler's instruction).

---

## Iteration 18 — metres-per-mile conversion (`MI <- 1609.344`) → `R/units.R`

**Selected candidate: the metres↔miles conversion factor `1609.344`.** Defined as `MI <- 1609.344` in **2
Module-D producer scripts** and used in both directions: `/ MI` (metres→miles) at
`differential_distance.R:33` and `geographic_access.R:73`; `mi * MI` (miles→metres) at
`geographic_access.R:74`. The map scripts (`differential_map`, `map`) read the precomputed `*_miles` columns
and do not convert.

**Why higher-risk than alternatives:** a duplicated **physical constant** that drives every published access
distance (median 29 extra miles, 50/100-mile catchments, miles-to-nearest choropleth). Fewer copies than the
CONUS list (2 vs 7), but it feeds headline numbers in BOTH directions, so a rounded copy in one script (1609
or 1609.34) would silently skew one metric relative to the other. Cleaner/atomic vs the alternatives (stale
doc comment = doc-only; ACS B01001 var set = a lookup needing its own iteration).

**Provenance table:**
| file:line | literal / use | direction | verdict |
|---|---|---|---|
| `differential_distance.R:20` def, `:33` `/MI` | `1609.344`; m→mi | convert | duplicated → canonical |
| `geographic_access.R:24` def, `:73` `/MI`, `:74` `mi*MI` | `1609.344`; m→mi + mi→m | convert | duplicated → canonical |
| `differential_map.R`, `map.R` | read `differential_miles`/`miles_to_nearest` cols | — | no conversion — not touched |
| catchment radii `within(50)`, `within(100)` | 50 / 100 miles | threshold | **intentional — left** (catchment radii, not the factor) |

**Discrepancies / adjudication:** both copies are the exact statute mile (`1609.344`), no drift today. The
`50`/`100` in `within(50)/within(100)` are catchment **radii** (a different quantity) — not collapsed. No
ambiguity.

**Canonical contract:** new **`R/units.R`** (pure constant + functions, no path deps; units ≠ geographic
scope, so a separate module from `conus.R`):
- `METERS_PER_MILE <- 1609.344` — metres per international/statute mile, exact by the 1959 yard-and-pound
  agreement (1 yd = 0.9144 m). Range: exactly 1609.344.
- `meters_to_miles(m)`, `miles_to_meters(mi)` — pure, vectorised, NA-preserving.

**Files changed:** new `R/units.R`; `scripts/urps_module_d_differential_distance.R` (+`source`, `/MI`→
`meters_to_miles()`); `scripts/urps_module_d_geographic_access_2026-07-23.R` (+`source`, `/MI`→
`meters_to_miles()`, `mi*MI`→`miles_to_meters()`); new `tests/testthat/test-ssot-meters-per-mile.R`.

**Hardcoded copies removed:** 2 `MI <- 1609.344` definitions (+ 3 bare `MI` use-sites rerouted through the
helpers). Behavior-preserving: `meters_to_miles(x) == x/MI` and `miles_to_meters(x) == x*MI` verified
byte-identical incl NA; no bare `MI` symbol remains in either script.

**Validation guard (fail-loud, in the module):** `METERS_PER_MILE == 1609.344` (exact self-check, rejects a
rounded copy) AND `all.equal(., 5280*12*0.0254)` (proves it is THE statute mile; `all.equal` because the
ft·in·m decomposition is `1609.3439999…` in double precision — an exact `==` would false-fail).

**Tests added:** `test-ssot-meters-per-mile.R` (17 assertions): exact value + statute-mile decomposition +
rejects rounded copies (1609 / 1609.34); conversion correctness + round-trip + NA; **behavior-preserving**
(helpers == prior `/MI` and `*MI` incl NA); **adversarial** (neither converter redefines `MI` or hardcodes
1609; both source `R/units.R` and use the helpers).

**Initial failures:** 1 (caught pre-test) — the module's `METERS_PER_MILE == 5280*12*0.0254` guard would have
failed because that product is `1609.3439999…998` in floating point, not exactly `1609.344`. Fixed by
`isTRUE(all.equal(...))` before running any test.

**Final results:** meters-per-mile 17/0; all **18 SSOT guards 233/0**. (Module-D inputs aren't vendored, so
validation is parse + equivalence + guards, as in iter 17.)

**Remaining risks:** none specific to this factor. As with iter 17, the Module-D scripts can't be run
end-to-end here (their shapefile/roster inputs aren't in-tree), but every converted value is provably identical.

**Recommended next candidate:** the ACS women-65+ variable set `B01001_%03d` `44:49` (in `geographic_access`
+ the demand modules — likely duplicated, defines the demand denominator age bands); OR the stale
`calculate_retirement_cliff_statistics.R:35` "5-year projection window" doc comment; OR the next display-name
hardcoder migration (`manuscript/R/create_workforce_table.R`, once the PI decides the stale-copy flag).

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = this iteration's files only.

---

## Iteration 19 — temporal demand-denominator age range (women 65+, `POP_65:POP_100`) → `R/demand_denominator.R`

**Candidate considered first (STOPPED, not duplicated): the ACS variable set `B01001_044:049`.** The queued
candidate turned out to appear **only once** (`geographic_access.R:54`) — nothing to single-source — and it is
*intentionally* a separate source from the temporal driver (the shiny app documents ACS B01001 as the
cross-sectional access-map count, "not the temporal driver"). So it is neither duplicated nor collapsible →
stopped, recorded.

**Selected candidate: the temporal demand-denominator age range `sprintf("POP_%d", 65:100)`.** "Women 65+"
(the pelvic-floor-disorder demand denominator) is summed from the Census 2023 NPP single-year-of-age columns
POP_65..POP_100. That range was **hardcoded in 2 demand producers** and asserted as a bare string
`"POP_65..POP_100"` in the freeze-gate audit.

**Why higher-risk than alternatives:** it defines the **denominator of every demand and adequacy number** in
the paper (women-65+ per urogyn, per-100k, supply-to-demand index, all growth factors). Two producers compute
it independently; a change to `65:99` or `66:100` in one would silently desynchronise the demand series, and
the audit's "definition-fixed" gate would still pass on a stale string. Cleanly single-sourceable.

**Provenance table:**
| file:line | literal | role | verdict |
|---|---|---|---|
| `urps_demand_module_bc:53` | `sprintf("POP_%d",65:100)` | women65 sum | duplicated → canonical |
| `urps_module_bc_corrected:89` | `sprintf("POP_%d",65:100)` | w65 sum | duplicated → canonical |
| `urps_module_bc_gate_audit:165` | `"POP_65..POP_100"` (label) | audit's stated 65+ definition | duplicated string → derived from constants |
| `urps_supply_demand_national:16` | `sprintf("POP_%d", 0:100)` | ALL ages (full pop vector) | **different range/purpose — left** (only NPP_MAX_AGE=100 is shared; not wired this iter) |
| `geographic_access:54` | `B01001_%03d`, `44:49` | ACS spatial county count | **intentional separate source — left** |

**Discrepancies / adjudication:** the ACS `44:49` and NPP `65:100` are different sources (spatial vs temporal)
and different encodings (band index vs single-year age) — NOT collapsed. `supply_demand_national`'s `0:100` is
"all ages," a different range — left (a future iter could share `NPP_MAX_AGE`). Both producers use identical
`65:100` today; no drift.

**Canonical contract:** new **`R/demand_denominator.R`** — `DEMAND_AGE_MIN <- 65L` (inclusive lower age of the
older-women demand denominator), `NPP_MAX_AGE <- 100L` (NPP top single-year bucket), and
`npp_women_65plus_cols()` → `sprintf("POP_%d", DEMAND_AGE_MIN:NPP_MAX_AGE)`. Pure constants + function.

**Files changed:** new `R/demand_denominator.R`; `urps_demand_module_bc` + `urps_module_bc_corrected` (source
the module; `.SDcols=npp_women_65plus_cols()`); `urps_module_bc_gate_audit` (source via its own `h()` resolver;
gate 98 label now `sprintf("POP_%d..POP_%d", DEMAND_AGE_MIN, NPP_MAX_AGE)`); new
`tests/testthat/test-ssot-demand-age-denominator.R`.

**Hardcoded copies removed:** 2 `sprintf("POP_%d",65:100)` computations + 1 `"POP_65..POP_100"` audit label.
Behavior-preserving: `npp_women_65plus_cols()` == the prior literal (36 cols, POP_65..POP_100); gate label
reproduces "POP_65..POP_100" exactly.

**Validation guards (fail-loud, in the module):** integer, ordered `DEMAND_AGE_MIN < NPP_MAX_AGE`, and pinned
`== 65L` / `== 100L` (a change to the published 65+ definition must be deliberate).

**Tests added:** `test-ssot-demand-age-denominator.R` (24 assertions): constants pinned + reject 60/66;
**behavior-preserving** (cols == prior literal, length 36, POP_65..POP_100); **semantic** (cols derived from
the constants; gate label derived); **adversarial** (no producer/gate hardcodes 65:100 or the string; all
reference the SSOT); **intentional-difference** (the ACS `44:49` spatial path is NOT wired to the NPP helper).

**Initial failures:** none — narrow 24/0 first run.

**Final results:** demand-age-denominator 24/0; all **19 SSOT guards 257/0**. (Demand modules read a Census NPP
file + DuckDB not vendored in-tree, so validation is parse + equivalence + guards.)

**Remaining risks:** `urps_supply_demand_national:16` still hardcodes `0:100` (all-ages vector); it shares only
the `100` top-age with this denominator — a future iter could route its `100` through `NPP_MAX_AGE`. The demand
modules can't be run end-to-end here (NPP/DuckDB inputs absent), but every value is provably identical.

**Recommended next candidate:** share `NPP_MAX_AGE` into `urps_supply_demand_national:16`'s `0:100`; OR the
stale `calculate_retirement_cliff_statistics.R:35` "5-year projection window" doc comment; OR the AUGS-app
palette constants (`CMS_DK`/`CMS_CY`/`TEAL`/`ORANGE`/`RED`, repeated across `cms_supply_demand_10styles` +
`make_supply_demand_figure`).

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 18-19 files (uncommitted since
the `eb6862b` push).

---

## Iteration 20 — shared AUGS supply-demand figure palette (TEAL/ORANGE/RED/GREY) → `R/augs_palette.R`

**Candidate considered first (STOPPED, not a dedup): the all-ages NPP vector `sprintf("POP_%d", 0:100)`.**
The recommended `NPP_MAX_AGE`-share turned out to have only ONE site (`urps_supply_demand_national:16`) — a
single tidy, not a duplication. Recorded, skipped.

**Selected candidate: the shared AUGS supply-demand figure palette** — `TEAL="#1b7f79"`, `ORANGE="#c77d1a"`,
`RED="#d1495b"`, `GREY="#8a97a8"`, copy-pasted **byte-identical with identical names in 2 AUGS scripts**
(`make_supply_demand_figure.R:8`, `cms_supply_demand_10styles.R:29`), each mapping Supply=TEAL /
Demand=ORANGE / PFD=RED / neutral=GREY.

**Why higher-risk than alternatives:** a real verbatim cross-file duplication (vs the single-site NPP tidy),
and the two figures are the SAME semantic family (supply-vs-demand), so a colour tweak in one would silently
desynchronise the paired figures. iter 7 stopped *manuscript* palettes for having intentional themes; here
the four values are identical copies, not themes, so this slice is safely collapsible.

**Provenance table:**
| file:line | literal | verdict |
|---|---|---|
| `make_supply_demand_figure.R:8` | `TEAL/ORANGE/RED/GREY` (+ `INK`) | dup → canonical; `INK` local |
| `cms_supply_demand_10styles.R:29` | `TEAL/ORANGE/RED/GREY` (+ `GREEN`, `CMS_*`) | dup → canonical; `GREEN`/`CMS_*` local |
| `shiny_urps_adequacy/app.R:22` | `TEAL/ORANGE/RED/GREY` inline | **intentional — LEFT** (self-contained app; pinned by test-guards-app.R:95) |
| `workforce_figures.R:11` `.wf_URPS="#d1495b"` | same red hex, diff name/role | **intentional — LEFT** (separate figure family) |
| `create_urps_taxonomy_*.R`, inline per-panel/dark-theme hex | per-figure | **intentional — LEFT** |

**Discrepancies / adjudication:** the ONLY thing collapsed is four byte-identical, identically-named constants
in the two AUGS supply-demand scripts. Everything else is a deliberate non-collapse: the Shiny app keeps its
inline copy **by requirement** (a deployed app cannot source repo modules; the inline literal is a
self-containment guard in `test-guards-app.R`); the workforce-figure/taxonomy `#d1495b` are separate families
with their own names; `GREEN`/`INK`/`CMS_*`/inline dark-theme hex are file-specific. None collapsed.

**Canonical contract:** new **`R/augs_palette.R`** — `AUGS_SD_PALETTE` (named 4-colour vector:
supply/demand_statusquo/demand_pfd/neutral) plus the bare `TEAL/ORANGE/RED/GREY` constants derived from it
(kept so the consumer call sites are byte-for-byte unchanged). Fail-loud validation: 4 unique named entries,
all valid `#RRGGBB`.

**Files changed:** new `R/augs_palette.R`; `make_supply_demand_figure.R` (source it; keep `INK`);
`cms_supply_demand_10styles.R` (source it; keep `GREEN`, `CMS_*`); new `tests/testthat/test-ssot-augs-palette.R`.

**Hardcoded copies removed:** 2 (the shared 4-colour block in each AUGS script). Behavior-preserving:
`TEAL/ORANGE/RED/GREY` resolve to the exact prior hex; `GREEN`/`INK`/`CMS_*` and all inline hex untouched;
both scripts parse.

**Validation guards (fail-loud, in the module):** 4 entries, unique non-empty names, all valid hex.

**Tests added:** `test-ssot-augs-palette.R` (19 assertions): palette well-formed; **behavior-preserving**
(bare constants == prior literals + derived from the named vector); **adversarial** (neither AUGS script
re-hardcodes the palette; both source the module); **intentional-difference preserved** (GREEN/INK/CMS_* stay
local; the workforce-figure `.wf_URPS` and the self-contained Shiny app keep their own copies and are NOT
wired to the module).

**Initial failures:** none from tests. The step-10 re-grep DID surface a 3rd copy (`shiny app.R:22`); on
inspection it is an intentional self-contained copy (guarded by `test-guards-app.R`), so it was documented +
added as a preserved-difference guard rather than refactored (test grew 17→19 assertions).

**Final results:** augs-palette 19/0; all **20 SSOT guards 276/0**. (AUGS figures need the demand CSV to
render; validation is parse + value-equivalence + guards.)

**Remaining risks:** the same 4 colours still live in the Shiny app inline — by deployment requirement, not
drift; if the palette ever changes, both the module AND the guarded app copy must be updated together (the
guard makes that explicit). `#d1495b` recurs across figure families by intent.

**Recommended next candidate:** the AUGS `CMS_*` federal-brand ramp (`#112e51/#205493/#0071bc/#02bfe7`) if it
recurs beyond `cms_supply_demand_10styles`; OR the stale `calculate_retirement_cliff_statistics.R:35` "5-year
projection window" doc comment; OR the physician at-risk retirement-age threshold (65) in
`calculate_retirement_cliff_statistics.R` — verify whether it is duplicated as a supply-side parameter.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 18-20 files (uncommitted since
the `eb6862b` push).

---

## Iteration 21 — demographic-growth rebase year (`w65[YEAR==2024]`) → `DEMAND_REBASE_YEAR`

**Candidate considered first (STOPPED, parameterized): the physician at-risk retirement age (65).** In
`calculate_retirement_cliff_statistics.R` the "65+/at-risk" appear only in DOCSTRINGS — the functions take
`at_risk` COUNTS as parameters, so no age-65 threshold is hardcoded there; the projection engine uses age-BAND
hazards (already SSOT'd, iter 5). Not a hardcoded value → stopped. Also checked CMS_* ramp (single file, not a
dedup) and FTE weights (parameterized) — neither qualifies.

**Selected candidate: the demographic-growth REBASE YEAR `2024`.** Both demand producers divide the projected
women-65+ series by the base-year count to form the growth index — `urps_demand_module_bc:55`
(`w65_2024 <- w65[YEAR==2024]`) and `urps_module_bc_corrected:91` (`base65 <- w65[YEAR==2024]`, "rebased to
2024"), asserted by the audit's `g2024=1` gates.

**Why higher-risk than alternatives:** it is the denominator of the demographic **growth factor** that scales
ALL projected demand volume and required-FTE; the two modules rebase independently, so a change to 2025 in one
would silently desynchronise the demand projections. A real duplicated modeling parameter (vs the stopped
candidates).

**Discrepancy investigation — `2024`/`2025` are heavily overloaded; only the two base-row sites are the
rebase:**
| site | literal | concept | verdict |
|---|---|---|---|
| `module_bc:55`, `module_bc_corrected:91` | `w65[YEAR==2024]` | demographic growth REBASE year | → canonical |
| `medicare_part_b_by_service_2024`, `national_2024`, `cohort_2024`, `req_fte_confirmed_2024` | 2024 | Medicare-claims DATA VINTAGE (table/column names) | **intentional — LEFT** |
| `module_a:47`, `supply_demand_national:70` (`YEAR==2025`) | 2025 | SUPPLY-side reporting INDEX base (=WC_YEAR0) | **intentional — LEFT** |
| `gate_audit` `year==2024` checks + `g2024=1` label | 2024 | audit base-row (entangled with vintage) | **LEFT this iter** (too entangled to touch safely; residual) |

**Adjudication:** the two `w65[YEAR==2024]` sites are unambiguously the demographic rebase (they filter the
women-65+ population table to the base year) and cleanly separable from the same-literal Medicare vintage and
the different-value 2025 supply index base. Those are NOT collapsed. The gate audit's `2024` is entangled with
the vintage and the projection base row, so it was left literal (documented residual) rather than risk a FATAL
audit refactor.

**Canonical contract:** `R/demand_denominator.R::DEMAND_REBASE_YEAR <- 2024L` — the year at which the older-women
demographic growth factor equals 1. Constant (fixed year). Consumers: the two demand producers. Doc block
explicitly warns it is NEITHER the Medicare data vintage NOR the 2025 supply index base.

**Files changed:** `R/demand_denominator.R` (+ constant + validation); `urps_demand_module_bc` +
`urps_module_bc_corrected` (`YEAR==2024` → `YEAR==DEMAND_REBASE_YEAR`); new
`tests/testthat/test-ssot-demand-rebase-year.R`.

**Hardcoded copies removed:** 2 (`w65[YEAR==2024]` in each producer). Behavior-preserving: `2024L` (int) vs the
prior `2024` (double) yields an identical row mask; both scripts parse and already source the module (iter 19).

**Validation guard (fail-loud):** integer, 2000–2100, pinned `== 2024L`.

**Tests added:** `test-ssot-demand-rebase-year.R` (17 assertions): pinned value + != 2025; **behavior-preserving**
(YEAR==constant selects the same row as ==2024); **adversarial** (no producer hardcodes `w65[YEAR==2024]`; both
use the constant + source the module); **intentional-difference** (the Medicare vintage `medicare_part_b_by_service_2024`
and the module_a `YEAR==2025` index base are NOT wired to the constant).

**Initial failures:** none — narrow 17/0 first run.

**Final results:** demand-rebase-year 17/0; all **21 SSOT guards 293/0**.

**Remaining risks:** the audit gate (`urps_module_bc_gate_audit`) still asserts "growth rebased to 2024" as a
literal string/`g2024=1`, entangled with the Medicare vintage and base-row checks — left un-canonicalized to
avoid a risky FATAL-audit refactor; if `DEMAND_REBASE_YEAR` ever changes, that gate must be updated by hand
(documented). The demand modules can't be run end-to-end here (NPP/DuckDB inputs absent).

**Recommended next candidate:** the AUGS `CMS_*` federal-brand ramp is single-file (not a dedup) — instead try
the supply-side **index base year 2025** (`module_a:47`, `supply_demand_national:70`, = `WC_YEAR0`) if it can be
shared with the engine's `WC_YEAR0` without crossing the self-contained-shiny boundary; OR the stale
`calculate_retirement_cliff_statistics.R:35` "5-year projection window" doc comment (doc↔SSOT); OR the
Medicare data-vintage year `2024` if it recurs as a bare literal beyond table names.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 18-21 files (uncommitted since
the `eb6862b` push).

---

## Iteration 22 — reporting index base year (`[YEAR==2025]`) → `DEMAND_INDEX_BASE_YEAR`

**Candidates considered first (STOPPED):**
- **FPMRS procedure code set.** A canonical `config/subspecialty_hcpcs_codes.yml` (89 "defining" codes) exists
  and is read by `enrich_rosters` + `module_a_age_productivity`, but `urps_demand_module_bc:27-31` hardcodes
  its own 22-code, procedure-**grouped** set (sling/prolapse/urodynamics/oab_botox/pessary). Compared the two:
  they genuinely **differ** (module_bc includes `57284`, absent from the YAML; the YAML has `57280`, absent
  from module_bc) because they serve different purposes — practitioner *identification* vs demand *volume
  attribution*. Intentional difference → not collapsed. The sling anchor `57288` is also entangled with
  FROZEN producers (`module_bc_FROZEN`) → not a clean atomic candidate.

**Selected candidate: the reporting INDEX BASE year `2025`** — `[YEAR==2025]` used as the index/adequacy
denominator (index 2025=100, adequacy 2025=1.00) and baseline endpoint: `module_a:47,72`,
`supply_demand_national:70,91`.

**Why higher-risk than alternatives:** it is the denominator of every supply/demand/adequacy INDEX in the
paper; two modules pick "2025" independently, so a drift would desync the reported indices. A real
demand-lineage dedup (4 sites → 1), parallel to iter 21's `DEMAND_REBASE_YEAR`.

**Discrepancy / adjudication:** `2025` is overloaded — the index base (canonicalised) vs the `2025:2050`
projection span and the `YEAR==2050` horizon-end endpoint reporting (a separate, iter-7-stopped value, LEFT
literal). Only the index-base/baseline filters were touched. The **2024 growth rebase** (iter 21) stays
distinct. **Cross-lineage note:** `DEMAND_INDEX_BASE_YEAR` EQUALS the supply engine's `WC_YEAR0` (the same 2025
projection baseline), but the demand modules are a separate lineage that does not source the engine.
Formalising the 4 demand copies into 1 does not create a NEW duplicate SSOT — it reduces an existing
duplication and DOCUMENTS the residual (`WC_YEAR0` vs this) as the next step: a shared `PROJECTION_BASELINE_YEAR`
in `workforce_constants.R` that both alias. A **cross-lineage test guard** now asserts `WC_YEAR0 ==
DEMAND_INDEX_BASE_YEAR` so they cannot silently diverge before that unification.

**Canonical contract:** `R/demand_denominator.R::DEMAND_INDEX_BASE_YEAR <- 2025L` — the projection baseline to
which reporting indices are rebased. Constant. Validated `> DEMAND_REBASE_YEAR` and pinned `== 2025L`.

**Files changed:** `R/demand_denominator.R` (+ constant + validation); `urps_module_a_effective_supply`
(source + 2 sites); `urps_supply_demand_national` (source + 2 sites); new
`tests/testthat/test-ssot-demand-index-base-year.R`; **updated** `tests/testthat/test-ssot-demand-rebase-year.R`
(one obsolete assertion — see failures).

**Hardcoded copies removed:** 4 (`[YEAR==2025]` index-base/baseline filters). Behavior-preserving: `2025L`
(int) vs `2025` (double) yields an identical row mask; both scripts parse and now source the module; the
`YEAR==2050` horizon-end literals are intentionally retained.

**Validation guard (fail-loud):** integer, `> DEMAND_REBASE_YEAR`, pinned `== 2025L`; plus the cross-lineage
`WC_YEAR0 ==` guard in the test.

**Tests added:** `test-ssot-demand-index-base-year.R` (15 assertions): pinned value + != 2050 + >
rebase-year; **behavior-preserving** (mask == ==2025); **adversarial** (both consumers use the constant, no bare
`[YEAR==2025]`, source the module, keep the 2050 endpoint literal); **cross-lineage guard** (engine `WC_YEAR0`
== this — the engine sourced cleanly, guard ran, not skipped).

**Initial failures:** 1 — `test-ssot-demand-rebase-year.R` (iter 21) asserted module_a still contained a
literal `YEAR==2025` (its supply index base). Classified as **obsolete test tied to the old duplication**: iter
22 correctly canonicalised that literal. Updated the assertion to `grepl("YEAR==DEMAND_INDEX_BASE_YEAR", ma)`
while KEEPING `expect_false(grepl("DEMAND_REBASE_YEAR", ma))` (the two demand base years stay distinct). No
production behavior changed.

**Final results:** demand-index-base-year 15/0; all **22 SSOT guards 308/0** (after the obsolete-assertion fix).

**Remaining risks:** the cross-lineage duplication `WC_YEAR0` (engine) vs `DEMAND_INDEX_BASE_YEAR` (demand) is
real but now GUARDED (they must stay equal) — the proper fix is a single `PROJECTION_BASELINE_YEAR` in
`workforce_constants.R` aliased by both (needs an engine + demand-module edit done together, verified; deferred
as its own iteration). Demand modules can't be run end-to-end here (NPP/DuckDB absent).

**Recommended next candidate:** the cross-lineage `PROJECTION_BASELINE_YEAR` unification (move 2025 into
`workforce_constants.R`; alias `WC_YEAR0` and `DEMAND_INDEX_BASE_YEAR` to it) — the guarded next step; OR the
`config/subspecialty_hcpcs_codes.yml` FPMRS set if a consumer is found that SHOULD read it but reimplements it
(module_bc's grouped set is intentional, so look elsewhere); OR the per-100k rate multiplier `1e5` if it
recurs across producers (low drift risk).

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 18-22 files (uncommitted since
the `eb6862b` push).

---

## Iteration 23 — cross-lineage projection baseline year → shared `PROJECTION_BASELINE_YEAR`

**Selected candidate: the 2025 projection baseline, unified across the supply and demand lineages.** This is
the guarded next step recorded in iter 22: the SAME 2025 baseline was defined independently as the supply
engine's `WC_YEAR0` (`workforce_cliff_engine.R`) and the demand `DEMAND_INDEX_BASE_YEAR` (`demand_denominator.R`).
iter 22 only *guarded* that they were equal; iter 23 makes them the SAME source.

**Why higher-risk than alternatives:** it is the most fundamental temporal anchor of the whole projection
(supply ages forward from it; every reporting index rebases to it; baseline + horizon fixes the 2029 endpoint).
Two independent literals in two lineages = a latent cross-lineage drift the earlier guard could only *detect*,
not *prevent*. Eliminating it is strictly better than any remaining fresh candidate.

**Discrepancy / adjudication:** no discrepancy (both were 2025); the risk was structural (two definitions).
The proper home is `R/workforce_constants.R` — the shared study-design module BOTH lineages already reach (the
engine sources it since iter 1; the demand lineage now sources it too). No intentional difference exists to
preserve.

**Canonical contract:** `R/workforce_constants.R::PROJECTION_BASELINE_YEAR <- 2025L` — the projection
baseline / first projected year. Constant, integer, pinned `== 2025L`. Consumers: `WC_YEAR0` (engine) and
`DEMAND_INDEX_BASE_YEAR` (demand) both ALIAS it.

**Files changed:** `R/workforce_constants.R` (+ constant + validation); `R/workforce_cliff_engine.R`
(`WC_YEAR0 <- PROJECTION_BASELINE_YEAR`); `R/demand_denominator.R` (sources workforce_constants with
`local = TRUE`; `DEMAND_INDEX_BASE_YEAR <- PROJECTION_BASELINE_YEAR` + an `identical(...)` guard); new
`tests/testthat/test-ssot-projection-baseline-year.R`.

**Hardcoded copies removed:** 2 (`WC_YEAR0 <- 2025L` and `DEMAND_INDEX_BASE_YEAR <- 2025L` are now aliases).
After this, `2025L`-the-baseline has EXACTLY ONE definition (`workforce_constants.R:40`). Behavior-preserving:
`WC_YEAR0` and `DEMAND_INDEX_BASE_YEAR` both still resolve to `2025L`; the engine and every engine-consuming
test are unchanged. Env-isolation verified: `demand_denominator`'s nested `source(..., local = TRUE)` places
`PROJECTION_BASELINE_YEAR` in the caller's scope (so test `new.env()` sourcing still sees it).

**Validation guards (fail-loud):** the module pins `PROJECTION_BASELINE_YEAR == 2025L`; `demand_denominator`
adds `identical(DEMAND_INDEX_BASE_YEAR, PROJECTION_BASELINE_YEAR)` (it IS the shared baseline, not a parallel
copy).

**Tests added:** `test-ssot-projection-baseline-year.R` (11 assertions): constant pinned; demand alias ===
shared; **engine alias === shared (cross-lineage, ran not skipped)**; both lineages equal by construction;
**semantic** (baseline + horizon = 2029); **adversarial** (neither lineage re-hardcodes 2025 for the baseline;
both alias the constant).

**Initial failures:** none — narrow 11/0 first run; the engine sourced cleanly so the cross-lineage assertion
ran (not skipped); all 23 SSOT guards + contract (63/0) + horizon/obs-window/age-bands engine-consumers green.

**Final results:** projection-baseline-year 11/0; all **23 SSOT guards 319/0**; engine-consuming suites
unchanged.

**Remaining risks:** none for this value — the cross-lineage duplication is gone (single definition, two
aliases, guarded). The demand modules still can't be run end-to-end here (NPP/DuckDB absent), but the aliasing
is value-identical and structurally verified.

**Recommended next candidate:** the per-100k rate multiplier `1e5` if it recurs across ≥2 producers (low drift
risk); OR the demand horizon END year `2050` (`2025:2050`, `YEAR==2050`) — iter 7 stopped it for "three
meanings", but if all active uses are the single demographic-projection horizon end it may now be cleanly
canonicalisable as `DEMAND_HORIZON_END_YEAR`; OR the stale `calculate_retirement_cliff_statistics.R:35`
"5-year projection window" doc comment IF its horizon is confirmed to be the 4-year canonical (currently
ambiguous — may be an intentional 2024-2029 5-year at-risk window).

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 18-23 files (uncommitted since
the `eb6862b` push).

---

## Iteration 24 — demand/supply projection HORIZON END year (`2050`) → `DEMAND_HORIZON_END_YEAR`

**Selected candidate: the projection horizon END year `2050`** (iter 7 stopped it for "three meanings"; a fuller
audit found the study-horizon uses ARE cleanly separable from the overloaded ones). Canonicalised in
`R/demand_denominator.R::DEMAND_HORIZON_END_YEAR`, and the demand horizon LENGTH (`HORIZON <- 25L`) is now
DERIVED from it (`DEMAND_HORIZON_END_YEAR - PROJECTION_BASELINE_YEAR`).

**Why higher-risk than alternatives:** it bounds every long-horizon supply/demand/adequacy number (through
2050); it was hardcoded as spans, the horizon length (25L), `YEAR==2050` endpoint filters, `gf(2050)`, and
milestone sets across **6** scripts — a change would desync them, and the length (25) could drift from the
endpoints independently. Making the length derived removes that whole class of drift.

**Discrepancy / adjudication (the "three meanings"):**
| use | verdict |
|---|---|
| spans `2025:2050`, `seq(2025,2050,5)`, `HORIZON<-25L`, `YEAR==2050` filters, `gf(2050)`, milestone sets | study horizon → **canonical** |
| `anchor_index(..., 2050, WU2011_SURG_2050)` (Wu-2011) and `..., 2030, ...` (Kirby) | **LEFT** — literature projection target years, fixed by the SOURCE data (coincide numerically, different concept) |
| `vol_2050`, `req_fte_confirmed_2050`, `req_fte_mid_2050` | **LEFT** — data-COLUMN schema identifiers, not the year value |
| `cov_2050` variable name, "2050" display strings, `end <- filter(YEAR==max(YEAR))` | **LEFT** — labels / already dynamic |

**Canonical contract:** `DEMAND_HORIZON_END_YEAR <- 2050L` — final projection year; `> DEMAND_INDEX_BASE_YEAR`;
pinned `== 2050L`. The horizon length and all spans/endpoints derive from it + `PROJECTION_BASELINE_YEAR`.

**Files changed:** `R/demand_denominator.R` (+ constant + validation); `urps_module_a_effective_supply`
(HORIZON derived; `YEAR==2050`→const ×6; milestone→`seq`); `urps_demand_module_bc` (span; `YEAR==2050`→const
×4; milestone); `urps_module_bc_corrected` (`YRS` end; `gf(2050)`→const); `urps_supply_demand_national` (span;
`YEAR==2050`→const ×3; milestone); `urps_module_bc_gate_audit` (span in gate 95); new
`tests/testthat/test-ssot-demand-horizon-end-year.R`; **updated 2 obsolete prior tests** (see failures).

**Hardcoded copies removed:** ~16 horizon-end value literals across 6 scripts → 0 (fully single-sourced).
Behavior-preserving: HORIZON=25, span `2025:2050`, and milestone `seq(...,5)` all verified byte-identical to
the prior literals; `2050L` (int) vs `2050` (double) is the same row mask; all scripts parse.

**Validation guards:** module pins `== 2050L` and `> DEMAND_INDEX_BASE_YEAR`.

**Tests added:** `test-ssot-demand-horizon-end-year.R` (17): pinned value; **behavior-preserving** (length/span/
milestone == prior literals); **adversarial** (consumers derive it, no bare `YEAR==2050`/`2025:2050`/`HORIZON<-25L`);
**intentional-difference** (Wu-2011 anchor + `_2050` column identifiers stay literal).

**Initial failures:** 2 — **obsolete assertions in prior tests** invalidated by this refactor: (1)
`test-ssot-demand-index-base-year.R` (iter 22) asserted module_a keeps a literal `YEAR==2050` — updated to
accept the canonical form; (2) `test-ssot-urps-entrants-derived.R` (iter 7) pinned the literal `HORIZON <- 25L`
— updated to assert the DERIVED length (`== 25L`, still != WC_HORIZON). Both preserved the original intent
(horizon-end distinct from index base; demand horizon 25 not collapsed to 4). No production behavior changed.

**Final results:** demand-horizon-end-year 17/0; all **24 SSOT guards 337/0** (after the 2 obsolete-assertion fixes).

**Remaining risks:** none for this value — fully single-sourced across all 6 scripts, length derived. Demand
modules still can't be run end-to-end here (NPP/DuckDB absent); value-equivalence + parse + guards verified.

**Recommended next candidate:** the per-100k rate multiplier `1e5` if it recurs across ≥2 producers (low drift
risk); OR the `2024` demographic base year in the remaining display milestone `c(2024,...)` (could alias
`DEMAND_REBASE_YEAR`); OR the ambiguous `calculate_retirement_cliff_statistics.R:35` "5-year projection window"
doc comment (verify whether its 2024-2029 window is an intentional 5-year at-risk horizon before touching).

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 18-24 files (uncommitted since
the `eb6862b` push).

---

## Iteration 25 — per-100,000 population rate base (`1e5`) → `R/units.R::RATE_PER_100K`

**Selected candidate: the per-100k rate multiplier `1e5`** — `1e5 * numer / denom`, duplicated across **3
producers / 7 sites** (`module_a:53,54`; `geographic_access:112,123`; `supply_demand_national:66,67,68`) to
report "urogynecologists per 100,000 women 65+" and the per-capita coverage benchmarks.

**Why higher-risk than alternatives:** it drives every published per-100k rate in the paper and is duplicated
across 3 files; naming it ALSO disambiguates it from the identical literal `1e5` used as a `guess_max` row hint
(a different concept in ~7 other scripts). The `c(2024,...)` milestone alternative is now a single site (not a
dedup); the "5-year projection window" doc comment has unclear authority.

**Discrepancy / adjudication (same literal, two concepts):**
| use | verdict |
|---|---|
| `1e5 * x / denom` (rate) in module_a / geographic_access / supply_demand_national | → **canonical** `RATE_PER_100K` |
| `guess_max = 1e5` in read_csv/fread (abu_pathway_sensitivity, build_hazard_comparison, departure_anchor, hierarchical_hazard, scenario_projection, validate_departure_classifier) | **LEFT** — a data-loading row-count hint, NOT a rate base |

The 3 rate-producer files contain ONLY rate `1e5*` uses (verified — no `guess_max` in them), so the
`replace_all "1e5*"` was surgical (the `*` distinguishes the rate multiply from `guess_max=1e5)`).

**Canonical contract:** `R/units.R::RATE_PER_100K <- 1e5` — the per-100,000 population rate normalisation base
(rate = RATE_PER_100K * numer / denom). Named constant; validated `== 1e5`. Home = `units.R` (the rate/units
module, already sourced by `geographic_access` since iter 18). Doc explicitly excludes the `guess_max` hint.

**Files changed:** `R/units.R` (+ constant + validation); `urps_module_a_effective_supply` (source units;
`1e5*`→`RATE_PER_100K*` ×2); `urps_module_d_geographic_access` (`1e5*`→const ×2; already sourced units);
`urps_supply_demand_national` (source units; `1e5*`→const ×3); new `tests/testthat/test-ssot-rate-per-100k.R`.

**Hardcoded copies removed:** 7 (`1e5*` rate multipliers) → 0 (fully single-sourced). Behavior-preserving:
`RATE_PER_100K == 1e5`, so every rate is numerically identical; all 3 scripts parse.

**Validation guards (fail-loud):** numeric scalar, `== 1e5`.

**Tests added:** `test-ssot-rate-per-100k.R` (15): value pinned; **behavior-preserving** (rate with the constant
== the prior `1e5` literal); **adversarial** (all 3 producers use `RATE_PER_100K`, no bare `1e5*`, source units);
**intentional-difference** (a `guess_max=1e5` script keeps the literal and does NOT reroute through the constant).

**Initial failures:** none — narrow 15/0 first run.

**Final results:** rate-per-100k 15/0; all **25 SSOT guards 352/0**.

**Remaining risks:** low — per-100k is a fixed epidemiological convention (near-zero drift); the value of this
iteration is the dedup + disambiguation from `guess_max=1e5`. Demand modules can't be run end-to-end here.

**Recommended next candidate:** the `guess_max = 1e5` row-count hint itself (recurs in ~6 read scripts — a
`READ_GUESS_MAX_ROWS` constant if worth the churn); OR the `c(2024,...)` display milestone aliasing
`DEMAND_REBASE_YEAR` (single site, tiny); OR the ACGME graduate-count window / any remaining hardcoded
literature anchor (Kirby 2010/2030, Wu 2010/2050) if a second consumer of the same anchor appears. The clean
in-repo candidate pool is now largely exhausted; consider a pass to VERIFY prior SSOTs still hold (re-run all
25 guards) rather than force low-value new ones.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 18-25 files (uncommitted since
the `eb6862b` push).

---

## Iteration 26 — fellowship-graduate ENTRY AGE (34) cross-lineage unification → `WORKFORCE_ENTRY_AGE`

**Candidate: the entry age `34`.** iter 6 wired the engine-sourcing scripts to `WC_ENTRY_AGE`, but
`urps_module_a_effective_supply:23` (demand lineage, does NOT source the engine) still hardcoded
`ENTRY_AGE <- 34L` — the one un-wired copy. Same iter-23 baseline-year pattern.

**Why higher-risk than alternatives (`guess_max=1e5`, `c(2024,...)` alias):** entry age drives the
age-structured effective-supply projection (each annual entrant cohort is injected at this age); a divergence
between module_a's 34 and the engine's 34 would silently make the demand-side projection age its entrants
differently from the supply projection. `guess_max` affects no published number.

**Canonical:** `R/workforce_constants.R::WORKFORCE_ENTRY_AGE <- 34L` (the shared module both lineages reach:
the engine sources it; module_a reaches it via `demand_denominator → workforce_constants`, exactly as it
already reaches `PROJECTION_BASELINE_YEAR`). `WC_ENTRY_AGE` and module_a's `ENTRY_AGE` both alias it.

**Files changed:** `R/workforce_constants.R` (+ constant + validation); `R/workforce_cliff_engine.R`
(`WC_ENTRY_AGE <- WORKFORCE_ENTRY_AGE`); `urps_module_a_effective_supply` (`ENTRY_AGE <- WORKFORCE_ENTRY_AGE`);
new `tests/testthat/test-ssot-entry-age.R`.

**Hardcoded copies removed:** 2 → `34`-the-entry-age now has ONE definition (`workforce_constants.R`).
Behavior-preserving (both resolve to 34L); engine + all engine-consuming tests unchanged.

**Guards:** pinned `== 34L`, range 25-45; cross-lineage test asserts `WC_ENTRY_AGE == WORKFORCE_ENTRY_AGE` and
`> WC_AGE_AT_CERT` (graduates enter after certification).

**Tests added:** `test-ssot-entry-age.R` (10): pinned value; **cross-lineage** (engine aliases + entry > cert,
ran not skipped); **adversarial** (neither engine nor module_a re-hardcodes 34).

**Final results:** entry-age 10/0; all **26 SSOT guards 362/0**. No initial failures.

**Remaining risks:** none for this value. Note `WC_AGE_AT_CERT` (30) is engine-only (not duplicated in the
demand lineage) so it stays `WC_*`; if a demand consumer of age-at-cert ever appears, unify it the same way.

**Recommended next candidate:** the `guess_max = 1e5` read hint (`READ_GUESS_MAX_ROWS`, ~9 sites, low drift);
OR a verification/commit pass — the clean in-repo pool is now essentially exhausted (26 iterations).

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 18-26 files (uncommitted since
the `eb6862b` push).
**NOTE:** iterations 18-26 were committed & pushed to `origin/main` as `bacb1a5` (2026-07-25).

---

## Iteration 27 — read_csv `guess_max` default (1e5) → `R/wc_path.R::READ_GUESS_MAX_ROWS`

**Candidate: the `guess_max=1e5` read default.** Copy-pasted across **6 scripts / 10 sites** (the read-heavy
regeneration + sensitivity scripts). The last cross-file literal duplicate in the repo.

**Why (and why it's low-value but legitimate):** `N_BOOT` was audited first and STOPPED — it is explicitly
script-specific (300 in hierarchical-hazard, 2000 in scenario-projection, both documented "script-specific"),
an intentional difference. `guess_max=1e5` is a genuine cross-file duplicate; it affects no published number
(a type-inference row hint, near-zero drift), but single-sourcing it (a) removes the last bare `1e5` in the
repo and completes the disambiguation started in iter 25 (per-100k `RATE_PER_100K` vs this read hint), and
(b) prevents a future script silently using a different `guess_max` and mis-typing a wide column.

**Canonical:** `R/wc_path.R::READ_GUESS_MAX_ROWS <- 1e5` — the shared, lightweight, side-effect-free I/O module
every consumer already reaches (4 via `workforce_cliff_engine.R` → `wc_path.R`; 2 source `wc_path.R` directly),
so ZERO new source lines. Numeric, pinned `== 1e5`.

**Discrepancy / adjudication:** the same literal `1e5` is ALSO `R/units.R::RATE_PER_100K` (the per-100k rate
base) — a **different concept**, kept as a separate constant (guarded both ways). `N_BOOT` differences are
intentional (not touched).

**Files changed:** `R/wc_path.R` (+ constant + validation); the 6 consumer scripts (`guess_max=1e5` →
`guess_max=READ_GUESS_MAX_ROWS`, 10 sites); new `tests/testthat/test-ssot-read-guess-max.R`; **updated**
`tests/testthat/test-ssot-rate-per-100k.R` (one obsolete assertion — see failures).

**Hardcoded copies removed:** 10 → 0. Behavior-preserving (`READ_GUESS_MAX_ROWS == 1e5`, `read_csv` unchanged);
all 6 scripts parse; reachable in real execution (engine-global and direct-source paths both confirmed).

**Validation guards:** numeric scalar, pinned `== 1e5`.

**Tests added:** `test-ssot-read-guess-max.R` (19): value pinned; behavior-preserving; **adversarial** (all 6
use the constant, no bare `guess_max=1e5`); **intentional-difference** (it lives in `wc_path.R` and is a
distinct constant from `units.R::RATE_PER_100K` despite the equal value).

**Initial failures:** 1 — `test-ssot-rate-per-100k.R` (iter 25) pinned the literal `guess_max=1e5` in
`build_hazard_comparison.R` as its intentional-difference example; iter 27 canonicalised it. Classified as
**obsolete test tied to the old literal**; updated to assert `guess_max=READ_GUESS_MAX_ROWS` (intent
preserved + stronger — both concepts now named constants).

**Final results:** read-guess-max 19/0; all **27 SSOT guards 381/0**.

**Remaining risks:** none for this value. **The clean in-repo cross-file duplicate pool is now exhausted**
(27 iterations). Remaining hardcoded values are single-site, intentional (N_BOOT, literature anchors, the
Medicare table-name vintage 2024), frozen, or shiny-self-contained. Further iterations would be low-value;
recommend shifting to a **verification pass** (re-run all 27 guards periodically) rather than forcing new SSOTs.

**Recommended next candidate:** none clean remaining. If pressed: the Medicare data-vintage `2024` in table
names (`medicare_part_b_by_service_2024`) — but it is DB-schema-tied and risky, so likely STOP. Better: a
verification/commit cadence.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iteration 27 files only.

---

## Iteration 28 — PRIMARY pooled subspecialties (GO+URPS) → wire `build_hazard_comparison` to `WC_PRIMARY`

**Candidate: the primary-subspecialty pair `c("GO","URPS")`.** `WC_PRIMARY` (the GO+URPS pool used for the
pooled age-band hazard, MIGS excluded) is the engine SSOT and is consumed via `PRIMARY <- WC_PRIMARY` by
`graduate_growth_scenarios` and `hierarchical_hazard_partial_pooling` — but `build_hazard_comparison.R`
hardcoded `c("GO","URPS")` twice (the pool filter at :54 and the `rate_tbl` label at :84). An un-wired consumer
of an established SSOT (the iter-26 pattern). So the iter-27 "pool exhausted" note was slightly premature —
this one remained.

**Why higher-risk than alternatives:** it defines WHICH subspecialties are pooled for the published hazard
comparison. If the hardcoded pair drifted from `WC_PRIMARY` (e.g. the study scope changed, or MIGS were
un-excluded), `build_hazard_comparison` would silently pool the wrong set and mis-estimate the hazard — a
published model input. Higher-value than the remaining read/display literals.

**Canonical:** `R/workforce_cliff_engine.R::WC_PRIMARY <- c("GO","URPS")` (unchanged). This iteration wires the
last un-wired consumer.

**Discrepancy / adjudication:** the `:54` filter (`%in%`) is unambiguously the pool (order-independent) → wired
to `PRIMARY`. The `:84` `rate_tbl` block lists the pair as the row LABEL, aligned with value columns hardcoded
in GO-then-URPS order (`rate_of("GO",…)`, `rate_of("URPS",…)`). The label now derives from `PRIMARY`, and a
fail-loud `stopifnot(identical(PRIMARY, c("GO","URPS")))` guards the order the hardcoded value vectors assume
(so the label can't silently misalign if `WC_PRIMARY` is ever reordered). The per-subspecialty `rate_of("GO"/
"URPS")` calls stay (they are inherently per-subspecialty computations, now order-guarded); fully deriving them
via a `sapply(PRIMARY, …)` + HZ-lookup restructure is out of scope (behaviour-risky, unrunnable here).

**Files changed:** `scripts/build_hazard_comparison.R` (+ `PRIMARY <- WC_PRIMARY`; `%in% PRIMARY`;
`subspecialty_abbrev = PRIMARY` + the alignment guard); new `tests/testthat/test-ssot-primary-subspecialties.R`.

**Hardcoded copies removed:** 2 (the filter + the label). The only remaining `c("GO","URPS")` is the alignment
**guard** (a contract assertion, not a data definition). Behavior-preserving: `%in% PRIMARY == %in% c("GO",
"URPS")` and `subspecialty_abbrev = PRIMARY` == the prior label (verified); script parses.

**Validation guard:** the fail-loud `identical(PRIMARY, c("GO","URPS"))` before `rate_tbl`.

**Tests added:** `test-ssot-primary-subspecialties.R` (10): `WC_PRIMARY == c("GO","URPS")` + MIGS excluded;
**behavior-preserving** (`%in%` mask identical); **adversarial** (build_hazard uses `PRIMARY` for alias/filter/
label, no literal filter/label remains); **consistency** (the two sibling scripts also alias `PRIMARY <- WC_PRIMARY`).

**Initial failures:** none — narrow 10/0 first run.

**Final results:** primary-subspecialties 10/0; all **28 SSOT guards 391/0**.

**Remaining risks:** none for this value. The `rate_of("GO"/"URPS")` per-subspecialty calls remain (order-
guarded); a future full `sapply(PRIMARY,…)` restructure would remove even those but needs the data to verify.
**With this, the clean cross-file duplicate pool is genuinely exhausted** — remaining literals are single-site,
intentional (N_BOOT), frozen, schema-tied, or shiny-self-contained.

**Recommended next candidate:** none clean remaining — recommend the verification/commit cadence (re-run the
28 guards periodically). If a specific new number enters the manuscript, add its SSOT + guard then.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 27-28 files (uncommitted since
the `bacb1a5` push).
**NOTE:** iterations 27-28 committed & pushed as `7f2a6ac` (2026-07-25).

---

## Iteration 29 — Census vintage year (2023) → `R/conus.R::CENSUS_VINTAGE_YEAR`

**Candidate: the Census vintage year `2023`** — the tigris boundary vintage (`counties/states(year=2023)`, 5
sites) AND the ACS data year (`get_acs(year=2023)`, 1 site), 6 sites across the 4 module-D scripts. Found via a
verification-pass broad scan (all 28 prior guards re-confirmed 391/0 first).

**Why high-risk:** `geographic_access` merges ACS county estimates onto tigris county polygons **by GEOID**;
the ACS data year and the boundary year MUST match or the join silently breaks (the 2022+ Connecticut
planning-region GEOIDs vs 2020 county GEOIDs — a documented failure mode). Two independent literals per the
project's own "boundary vintage keyed off the ACS year" rule → one concept that must move together.

**Discrepancy / adjudication:** the tigris `year=` and the ACS `year=` are the SAME concept (not intentionally
different) — the boundary vintage is keyed off the ACS year, and both must produce matching GEOIDs. Single-
sourcing enforces that. Not the isochrone TARGET_YEAR (a different concept, not present here).

**Canonical:** `R/conus.R::CENSUS_VINTAGE_YEAR <- 2023L` (the geographic module all 4 scripts already source
since iter 17 — zero new source lines). Integer, pinned `== 2023L`.

**Files changed:** `R/conus.R` (+ constant + validation); the 4 `urps_module_d_*` scripts (`year=2023` →
`year=CENSUS_VINTAGE_YEAR`, 6 sites); new `tests/testthat/test-ssot-census-vintage-year.R`.

**Hardcoded copies removed:** 6 → 0. Behavior-preserving (`== 2023L`); all 4 scripts parse.

**Validation guard:** integer, range, pinned `== 2023L`.

**Tests added:** `test-ssot-census-vintage-year.R` (18): value pinned; **adversarial** (all 4 derive it, no
bare `year=2023`, source conus.R); **semantic** (geographic_access's `get_acs(year=)` and `counties(year=)`
share the ONE constant — the GEOID-match contract).

**Initial failures:** none. **Final: census-vintage-year 18/0; all 29 SSOT guards 409/0.**

**Remaining risks:** none for this value. Pool remains otherwise exhausted; verification cadence recommended.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iteration 29 files only.

---

## Iteration 30 — tigris cartographic-boundary resolution ("20m") → `R/conus.R::CENSUS_CB_RESOLUTION`

**Candidate: `resolution="20m"`** — the tigris cartographic-boundary generalization in every module-D
county/state pull (`counties/states(cb=TRUE, resolution="20m")`), 5 sites across the 4 module-D scripts. Sits
alongside the iter-29 `CENSUS_VINTAGE_YEAR` in the same calls.

**Why (chosen over `crs=4326`):** the differential-distance and geographic-access steps both compute county-
CENTROID-to-provider distances; a different boundary generalization shifts the centroids, giving different
distances for the same county — so the resolution must be consistent for the two distance metrics to be
comparable. `crs=4326` (WGS84) was the alternative but it is a universal standard with ~zero drift (like
per-100k / guess_max) → lower value; noted, not taken.

**Canonical:** `R/conus.R::CENSUS_CB_RESOLUTION <- "20m"` (the geographic module all 4 scripts already source;
zero new source lines). Validated: single non-NA character, one of tigris's valid cb resolutions.

**Files changed:** `R/conus.R` (+ constant + validation); the 4 `urps_module_d_*` scripts (`resolution="20m"`
→ `resolution=CENSUS_CB_RESOLUTION`, 5 sites); new `tests/testthat/test-ssot-census-cb-resolution.R`.

**Hardcoded copies removed:** 5 → 0. Behavior-preserving (`== "20m"`); all 4 scripts parse.

**Validation guard:** character scalar, in {"20m","5m","500k"}.

**Tests added:** `test-ssot-census-cb-resolution.R` (17): value pinned; **adversarial** (all boundary pulls
derive it, no bare `"20m"`, source conus.R); **semantic** (both distance-computing scripts share the ONE
constant so centroids align).

**Initial failures:** none. **Final: census-cb-resolution 17/0; all 30 SSOT guards 426/0.**

**Remaining risks:** none for this value. `crs=4326` remains hardcoded (universal WGS84 standard, deliberately
not canonicalised — over-engineering). The pool is otherwise exhausted; verification cadence recommended.

**Recommended next candidate:** none clean/high-value remaining. `crs=4326` only if a future re-projection
introduces a second CRS worth naming. Otherwise: verify + commit cadence.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 29-30 files (uncommitted since
the `7f2a6ac` push).
**NOTE:** iterations 29-30 committed & pushed as `8550b70` (rebased onto the other window's `02637e5`); tip `90dc7dc`.

---

## Iteration 31 — Census-NPP total-female row filter (SEX==2 & ORIGIN==0 & RACE==0) → `npp_total_female()`

**Candidate: the NPP total-female row filter `[SEX==2 & ORIGIN==0 & RACE==0]`** — the demand population base
(total US females, all origins, all races) BEFORE the women-65+ age selection, copy-pasted across **3 demand
producers** (`urps_demand_module_bc:53`, `urps_module_bc_corrected:89`, `urps_supply_demand_national:24`). iter
19 canonicalised the age COLUMNS (`POP_65:100`) but left this ROW filter untouched.

**Why higher-risk than alternatives (`crs=4326`):** it defines WHICH population is the demand denominator; a
wrong ORIGIN or RACE code (ORIGIN==1 Hispanic-only, RACE==1 White-only) would silently narrow it to a subgroup
and corrupt every downstream demand/adequacy number — a silent, high-impact drift. `crs=4326` is a universal
WGS84 standard with ~zero drift (deliberately left).

**Canonical:** `R/demand_denominator.R::npp_total_female(dt)` — a **function** (the filter applies to a
data.table), returning `dt[SEX==2 & ORIGIN==0 & RACE==0]` with a fail-loud column-existence `stopifnot`. Codes
documented per the Census 2023 NPP file layout. All 3 producers already source the module (zero new source lines).

**Files changed:** `R/demand_denominator.R` (+ helper + guard); the 3 producers (`fread(...)[filter]` →
`npp_total_female(fread(...))`); new `tests/testthat/test-ssot-npp-total-female.R`.

**Hardcoded copies removed:** 3 → 0. Behavior-preserving: `npp_total_female(dt)` returns the identical rows to
the literal filter (verified on a synthetic data.table); all 3 scripts parse and use the helper.

**Validation guard:** `stopifnot(all(c("SEX","ORIGIN","RACE") %in% names(dt)))` — fail loud if the NPP schema
changes.

**Tests added:** `test-ssot-npp-total-female.R` (16): behavior-preserving (== literal filter); **semantic**
(keeps only total-female/all-origins/all-races, excludes males/Hispanic-only/race-specific); **fail-loud**
(missing column errors); **adversarial** (all 3 producers use the helper, no bare filter, source the module).

**Initial failures:** none. **Final: npp-total-female 16/0; all 31 SSOT guards 442/0.**

**Remaining risks:** none for this value. `crs=4326` remains (universal standard, intentionally not
canonicalised). The pool is otherwise exhausted; verification cadence recommended.

**Recommended next candidate:** none clean/high-value remaining — verify + commit cadence. If pressed: the ACS
`survey="acs5"` string (single site, not a dedup) or `crs=4326` (universal, over-engineering) — both likely STOP.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iteration 31 files only.

---

## Iteration 32 — Census NPP projection file path (`SCR` + `np2023_d1_<series>.csv`) → `npp_projection_path()`

**Candidate: the NPP projection file path.** `SCR <- here::here("data", "census")` was duplicated identically
in **3 demand producers**, and `file.path(SCR, "np2023_d1_<series>.csv")` referenced the NPP mid file in all 3
(plus low/hi in `supply_demand_national`). It is the demand DATA SOURCE — a wrong dir or file would silently
swap the population base.

**Why higher-risk than alternatives:** it selects which population-projection file feeds the entire demand
model; a drift (different dir, different NPP vintage) corrupts every demand/adequacy number silently. The
remaining `crs=4326` / `survey="acs5"` are universal-standard / single-site (STOP).

**Discrepancy / adjudication:** `SCR` is used ONLY for NPP files (mid in all 3 producers; low/hi additionally in
`supply_demand_national`) — verified. So a single **function** capturing the whole path contract (dir +
`np2023_d1_<series>.csv`) subsumes both the dir and the filename pattern and lets the now-unused `SCR` be
removed. Not the isochrone/Medicare paths (those go through `wc_path()`; the NPP file is in-repo `data/census/`).

**Canonical:** `R/demand_denominator.R::npp_projection_path(series = c("mid","low","hi"))` — returns
`here::here("data","census", sprintf("np2023_d1_%s.csv", series))` with a `match.arg` guard. Function (the path
depends on the series input). The module already uses `here::here` (iter 23), so no new dependency.

**Files changed:** `R/demand_denominator.R` (+ function); the 3 producers (`file.path(SCR,"np2023_d1_*.csv")` →
`npp_projection_path(...)`; the 3 unused `SCR <- here::here("data","census")` lines removed); new
`tests/testthat/test-ssot-npp-projection-path.R`.

**Hardcoded copies removed:** 3 `SCR` dir literals + 5 NPP filename references → 0. Behavior-preserving:
`npp_projection_path("mid"/"low"/"hi")` resolves to the same `data/census/np2023_d1_*.csv` files; all 3 scripts
parse. Residual: the `gate_audit` documents `"np2023_d1_mid.csv"` as a descriptive audit string (left, like the
iter-19 gate label).

**Validation guard:** `match.arg(series)` rejects any series other than mid/low/hi; the semantic test asserts the
canonical mid path resolves to the real in-repo file.

**Tests added:** `test-ssot-npp-projection-path.R` (15): path resolves per series + default=mid; **semantic**
(mid file exists at the canonical path); **fail-loud** (unknown series errors); **adversarial** (all 3 producers
use the helper, no `SCR` / `file.path(SCR` literal remains).

**Initial failures:** none. **Final: npp-projection-path 15/0; all 32 SSOT guards 457/0.**

**Remaining risks:** none for this value. The clean pool is exhausted; `crs=4326`/`acs5` are deliberate STOPs.
Verification cadence recommended.

**Recommended next candidate:** none clean/high-value — verify + commit cadence.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 31-32 files only.

---

## Iteration 33 — URPS entrant inflow in supply_demand_national (hardcoded 64) → `mean(GRAD_URPS)`

**Candidate: the entrant inflow `64`** hardcoded TWICE in `supply_demand_national`'s `project()` calls (lines
49, 59). iter 7 established `ENTRANTS <- mean(GRAD_URPS)` (module_a); this producer bypassed it with a literal
64. `mean(GRAD_URPS) = mean(c(61,66,63,66)) = 64`, and `GRAD_URPS` is already in scope (sourced from
`shiny_urps_scenarios/urps_model_data.R`).

**Why higher-risk than alternatives (`entry_age=34L`, `HORIZON<-2050-2025` in the same script):** the entrant
count is the INFLOW driving the entire supply projection (and the Monte Carlo band); a change to the graduate
counts would leave this stale 64 and silently mis-project supply. The entry-age (single-site default) and the
2050-2025 horizon length (iter-24-adjacent) are lower-value follow-ons in the same file.

**Canonical:** `mean(GRAD_URPS)` (the ACGME graduate SSOT already in scope), aliased once as
`ENTRANTS <- mean(GRAD_URPS)` — matching module_a's pattern.

**Files changed:** `scripts/urps_supply_demand_national_2026-07-23.R` (+ `ENTRANTS <- mean(GRAD_URPS)`; both
`project(URPS_AGES, 64, ...)` → `project(URPS_AGES, ENTRANTS, ...)`); new
`tests/testthat/test-ssot-supply-demand-entrants.R`.

**Hardcoded copies removed:** 2 (`64` ×2) → 0. Behavior-preserving: `mean(GRAD_URPS) == 64` (verified); parses.

**Validation guard:** the derivation is the guard (entrants can no longer disagree with the graduate counts);
the test pins `mean(GRAD_URPS) == 64` and cross-checks the module_a pattern.

**Tests added:** `test-ssot-supply-demand-entrants.R` (8): behavior-preserving (`mean(GRAD_URPS) == 64`);
**semantic** (derived from the counts, tracks a change); **adversarial** (ENTRANTS derived, no bare
`project(..., 64)`); **consistency** (matches module_a's `ENTRANTS <- mean(GRAD_URPS)`).

**Initial failures:** none. **Final: supply-demand-entrants 8/0; all 33 SSOT guards 465/0.**

**Remaining risks:** none for this value. Same-file follow-ons: `entry_age=34L` → `WORKFORCE_ENTRY_AGE`
(reachable) and `HORIZON <- 2050-2025` → `DEMAND_HORIZON_END_YEAR - PROJECTION_BASELINE_YEAR` (both in scope) —
the last un-wired duplicates, recommended next.

**Recommended next candidate:** `supply_demand_national`'s `entry_age=34L` (wire to `WORKFORCE_ENTRY_AGE`) or
`HORIZON <- 2050-2025` (wire to the demand-horizon endpoints) — both established SSOTs, single-site each.

**Status:** ✅ complete. Committed `bdb62a4` (iterations 31-33 + ephemeral-formalization fixes).

---

## Iteration 34 — supply projection entry age (`entry_age=34L` → `WORKFORCE_ENTRY_AGE`)

**Candidate:** `scripts/urps_supply_demand_national_2026-07-23.R:40`, `project(ages, entrants, hz, horizon, entry_age=34L)`.

**Why higher-risk than alternatives:** the entry age is the cohort-injection age that reshapes the age
structure every projected year (both `supply_mid` and the 2000-draw Monte Carlo band call `project()` with the
default). It is a **third consumer** of the fellowship-graduate entry age already canonicalized in iter6/iter26
as `R/workforce_constants.R::WORKFORCE_ENTRY_AGE` (the engine's `WC_ENTRY_AGE` and module_a's `ENTRY_AGE` both
alias it); this site was the last un-wired copy, so a future change to the entry age would silently leave this
supply projection stale at 34. The `HORIZON <- 2050-2025` follow-on is lower-value (a length that already ties
to two pinned endpoints and is not itself a drift risk).

**Audit:** literal `34L` appears once, as the `entry_age` default (line 40); both call sites (lines 50, 60)
omit the argument and rely on the default. The comment at line 9 ("64 entrants/yr at age 34") is accurate
descriptive prose, not a used literal — left as-is (it still matches the canonical 34).

**Discrepancy adjudication:** none — same meaning, same value (`WORKFORCE_ENTRY_AGE == 34L`) as the engine and
module_a; no intentional scenario difference. Not an alias collision: reached at call time via the existing
`source(R/demand_denominator.R)` (line 19, before `project()` is defined), which sources `workforce_constants.R`.

**Canonical:** `WORKFORCE_ENTRY_AGE` (`R/workforce_constants.R`, iter26), the shared fellowship-graduate entry
age; the `project()` default now reads `entry_age = WORKFORCE_ENTRY_AGE` (lazy default resolves in globalenv at
call time).

**Files changed:** `scripts/urps_supply_demand_national_2026-07-23.R` (default `34L` → `WORKFORCE_ENTRY_AGE`);
`tests/testthat/test-ssot-entry-age.R` (extended — no new duplicate guard file).

**Hardcoded copies removed:** 1 (`entry_age=34L`) → 0. Behavior-preserving.

**Validation guard:** the existing `test-ssot-entry-age.R` pins `WORKFORCE_ENTRY_AGE == 34L` (integer, range
25-45); the new blocks fail loudly if this site re-hardcodes 34 or un-wires from the SSOT.

**Tests added (extended existing guard, +4 → 14/0):** **adversarial** (no `entry_age=34L`; default wired to
`WORKFORCE_ENTRY_AGE`; demand_denominator sourced so the SSOT is reachable); **behavior-preserving** (a local
re-implementation of `project()` yields an identical 2050 trajectory with explicit `34L` vs the new default,
proving the default resolves to the same value).

**Initial failures:** none. **Final: entry-age guard 14/0; all 33 SSOT guards 469/0.** Script parses; final grep
finds no bare `entry_age=34L` in `scripts/` or `R/`.

**Remaining risks:** none for this value. One un-wired duplicate remains: `HORIZON <- 2050-2025` (line 48) →
`DEMAND_HORIZON_END_YEAR - PROJECTION_BASELINE_YEAR` (both in scope via demand_denominator).

**Recommended next candidate:** `supply_demand_national`'s `HORIZON <- 2050-2025` (line 48) → wire to
`DEMAND_HORIZON_END_YEAR - PROJECTION_BASELINE_YEAR` — removes two hardcoded years (2050, 2025) by tying the
horizon length to the two canonical endpoints; last known cross-copy of a pinned SSOT.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iteration 34 files only
(`scripts/urps_supply_demand_national_2026-07-23.R`, `tests/testthat/test-ssot-entry-age.R`).

---

## Iteration 35 — supply projection horizon length (`HORIZON <- 2050-2025` → derived endpoints)

**Candidate:** `scripts/urps_supply_demand_national_2026-07-23.R:48`, `HORIZON <- 2050-2025`.

**Why higher-risk than alternatives:** this is an **internal inconsistency within a single file** — the same
producer already uses the named endpoints `PROJECTION_BASELINE_YEAR:DEMAND_HORIZON_END_YEAR` for its `YEAR`
axis (line 62) and `DEMAND_HORIZON_END_YEAR` for its endpoint filters (lines 86, 92), yet line 48 recomputed the
horizon *length* from bare literals. The trajectory has `HORIZON+1` points and is bound 1:1 to the `YEAR` axis in
the `supply` data.table (line 62); if someone revised the horizon via the constants (as iter24 set up for the
four demand scripts) but missed this bare arithmetic, the trajectory length would silently desync from the year
axis and malform the supply table. Last un-wired cross-copy of the iter24 endpoints. (The remaining literals in
the file — the line-3/91 "2025-2050" strings — are descriptive prose.)

**Audit:** `2050-2025` appears once as live code (line 48). Lines 3, 91 are accurate display/prose strings; the
year axis (62), milestone `seq` (86), and endpoint filters (92, 94) already use the named constants.

**Discrepancy adjudication:** none — `DEMAND_HORIZON_END_YEAR - PROJECTION_BASELINE_YEAR == 25L`, identical to
the old `2050-2025`. Integer-vs-double is behaviorally inert (HORIZON is used only as a length / `seq_len` /
`ncol`). No intentional difference (the Wu-2011 literature anchor `2050` and `_2050` column identifiers, called
out in iter24, live in other files and stay literal).

**Canonical:** `DEMAND_HORIZON_END_YEAR` (`R/demand_denominator.R`, iter24) and `PROJECTION_BASELINE_YEAR`
(`R/workforce_constants.R`), both in scope via the line-19 `demand_denominator.R` source; line 48 now reads
`HORIZON <- DEMAND_HORIZON_END_YEAR - PROJECTION_BASELINE_YEAR`.

**Files changed:** `scripts/urps_supply_demand_national_2026-07-23.R` (line 48);
`tests/testthat/test-ssot-demand-horizon-end-year.R` (extended — no new duplicate guard file).

**Hardcoded copies removed:** 2 literal years (`2050`, `2025`) in one expression → 0. Behavior-preserving.

**Validation guard:** the existing horizon-end-year guard already pins `DEMAND_HORIZON_END_YEAR == 2050L` and the
`- PROJECTION_BASELINE_YEAR == 25L` algebra; the new blocks fail loudly if this site re-hardcodes `2050-2025` or
if the derived length ever stops matching the `YEAR`-axis span.

**Tests added (extended existing guard, +5 → 22/0):** **adversarial** (no bare `2050-2025`; `HORIZON` derived
from the endpoints; same file uses `PROJECTION_BASELINE_YEAR:DEMAND_HORIZON_END_YEAR`); **semantic invariant**
(`HORIZON+1 == length(PROJECTION_BASELINE_YEAR:DEMAND_HORIZON_END_YEAR)` — the trajectory-length/year-axis tie
this refactor protects; plus the behavior-preserving `== 25L`).

**Initial failures:** none. **Final: horizon-end-year guard 22/0; all 33 SSOT guards 474/0.** Script parses;
final grep finds no live bare `2050-2025` in `scripts/`/`R/` (only a descriptive `2050-2025=25` comment in
module_a, already SSOT-derived since iter24).

**Remaining risks:** none for this value. The clean cross-file duplicate pool of pinned SSOTs is now exhausted —
subsequent iterations must open a genuinely new candidate (see below) rather than wire a known cross-copy.

**Recommended next candidate:** a *fresh* audit target, since the known cross-copies are done. Strong options:
(a) the six CPT/HCPCS procedure code lists in `urps_demand_module_bc_2026-07-23.R:26-32` (`grp`) — duplicated
across module_bc, module_bc_corrected, and any figure/table that reports per-service volume; a code drifting
between copies would silently mis-attribute Medicare volume. (b) the age-band cut breakpoints
`BANDS <- c(0,45,50,55,60,65,70,Inf)` + `BAND_LABELS` (line 36) vs the engine's own band definition — a
classic two-lineage band-edge drift risk.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 34-35 files
(`scripts/urps_supply_demand_national_2026-07-23.R`, `tests/testthat/test-ssot-entry-age.R`,
`tests/testthat/test-ssot-demand-horizon-end-year.R`, `docs/SSOT_LEDGER.md`) — iter34 remains validated/green
and awaits the next "land" instruction; both iterations are cleanly separated in this ledger.

---

## Iteration 36 — URPS anchor procedure codes (`c("57288","57282","51728","52287")` + surg/func split)

**Candidate:** the four "anchor" pelvic-floor HCPCS codes (one representative per procedure family) and their
surgical/functional (OBG/URO field) classification, used by the Module B+C plasticity/attribution audit.

**Why higher-risk than alternatives:** the *codes* were duplicated across **four files / eight sites** —
`module_bc_corrected` (line 39 + a **self-referential GATE-7 check** at 116 that re-lists the same four to
validate them against themselves), `gate_audit` (`ANCHORS` 25, `FUNC`/`SURG` 26, `DICT field` 64), and
`plasticity_stage0` (named-vector keys 22-23) — plus the `FROZEN` snapshot (59, 88). `gate_audit` even carried a
manual FATAL gate (`G(24)` "Identical HCPCS universe across files") whose whole job was to detect the drift this
SSOT structurally prevents. A code drifting between copies would silently mis-attribute Medicare procedure
volume to the urogyn cohort — a published-number risk. (The original recommendation named the full six-group
`grp` list, but the audit showed `grp` is **single-source** in `module_bc` and not a duplication; the anchor set
is the real one.)

**Audit / discrepancy adjudication:** the **codes are byte-identical and order-stable** across all sites → one
SSOT. The **surg/func split** recurs in three vocabularies (`FUNC`/`SURG`, `field=OBG/URO`) → canonicalized with
a 1:1 class↔field lockstep. The **family LABELS drift by design** — "Sling for SUI" (corrected) vs "Sling"
(gate_audit) vs "Sling (SUI)" (plasticity) — these are per-output display strings; **left literal, not
collapsed** (documented intentional difference). The `FROZEN` file is a reproducibility snapshot → **not wired**;
guarded by a parity check instead.

**Canonical:** `R/urps_procedure_codes.R` — a validated 4-row lookup `URPS_ANCHOR_PROCEDURES` (code, class,
field) with fail-loud `stopifnot` (4 unique codes, closed class/field vocab, class↔field lockstep) + accessors
`urps_anchor_codes(class=all/surgical/functional)` and `urps_anchor_field(codes)`. Chose a **lookup table +
accessors** over a bare vector because consumers need the split and the field, not just the codes.

**Files changed:** new `R/urps_procedure_codes.R`; wired `scripts/urps_module_bc_corrected_2026-07-23.R`
(source + line 39 + GATE-7 116), `scripts/urps_module_bc_gate_audit_2026-07-23.R` (source + ANCHORS 25 +
FUNC/SURG 26 + DICT field 64), `scripts/urps_plasticity_stage0_audit_2026-07-23.R` (source + named-vector 22-23);
new `tests/testthat/test-ssot-urps-anchor-procedures.R`. **FROZEN not touched.**

**Hardcoded copies removed:** 6 live literal copies across 3 non-frozen files (the full 4-code vector ×3, the
FUNC/SURG split, the OBG/URO field, the GATE-7 self-check) → 0. Behavior-preserving (accessors == prior
literals, order preserved; verified).

**Validation guards:** `stopifnot` in the canonical file; the guard's frozen-parity test catches the FROZEN
snapshot diverging from canonical without editing the freeze.

**Tests added (`test-ssot-urps-anchor-procedures.R`, 25/0):** well-formedness; **behavior-preserving** (accessors
reproduce every prior literal, in order); **semantic** (surg/func partition — disjoint + exhaustive; order
contract); **adversarial** (all 3 non-frozen consumers reference the accessor, no bare 4-code / FUNC / field
literal remains); **frozen-parity** (FROZEN literal still equals canonical); **adversarial malformed** (duplicate
code and broken class↔field lockstep both fail the validation).

**Initial failures:** none. **Final: anchor-procedures 25/0; all 34 SSOT guards 499/0; all 3 consumers parse.**

**Remaining risks:** the FROZEN snapshot stays a hand-maintained copy by design; the parity guard flags drift but
a deliberate re-bake requires updating the guard expectation (documented in the test). The three family-label
vocabularies remain intentionally distinct.

**Recommended next candidate:** iteration 37 (b) — the age-band breakpoints
`BANDS <- c(0,45,50,55,60,65,70,Inf)` + `BAND_LABELS` in `supply_demand_national` vs the engine's band
definition (two-lineage band-edge drift).

**Status:** ✅ complete. Uncommitted (loop rule).

---

## Iteration 37 — age-band breakpoints (`BANDS <- c(0,45,50,55,60,65,70,Inf)`, demand/app lineage)

**Candidate:** the numeric age-band breakpoints `c(0,45,50,55,60,65,70,Inf)` used with `cut()` to bucket
physician ages into the seven hazard bands.

**Why higher-risk than alternatives:** the band edges are the **axis of the entire hazard model** — an off-by-one
edge silently re-buckets every physician and shifts every projected departure. `BANDS` was hardcoded in **four**
demand/app files (`supply_demand_national:36`, `module_a:19`, `shiny_urps_scenarios/app.R:21`,
`shiny_urps_adequacy/model.R:30`), all of which already sourced `urps_model_data.R` for the *paired*
`BAND_LABELS` — so the labels were single-sourced but the numeric edges they pair with were not. The engine
lineage (`WC_BANDS`) was already canonical and guarded, and its adversarial grep only scans *engine-sourcing*
scripts, leaving these four (which source the snapshot, not the engine) unguarded — a real blind spot.

**Audit / discrepancy adjudication:** all four literals + both `WC_BANDS` + both snapshot copies are
byte-identical `c(0,45,50,55,60,65,70,Inf)` — no intentional difference. Two lineages by design: the engine
`WC_BANDS`/`WC_BAND_LABELS` (canonical) and the self-contained Shiny/demand snapshot `urps_model_data.R` (carries
`BAND_LABELS`, **parity-guarded** to the engine, not wired — so the apps deploy standalone). The snapshot files
carry an *"Auto-generated ... do not hand-edit"* header, but **no generator exists in the repo** and they already
hold hand-edits (the "+6 PI decision" block), so they are effectively the hand-maintained standalone snapshot;
`BANDS` was simply missing from them, forcing the four hardcodes.

**Canonical:** unchanged — `WC_BANDS` (`R/workforce_cliff_engine.R`) stays the one SSOT. The fix mirrors the
existing `BAND_LABELS` pattern: add `BANDS` to both `urps_model_data.R` snapshots (the demand/app lineage's local
mirror), parity-guarded to `WC_BANDS`, so the four consumers read it from the snapshot they already source. Chose
**snapshot constant + parity guard** (not wiring the apps to the engine) to preserve standalone Shiny
deployability.

**Files changed:** `shiny_urps_scenarios/urps_model_data.R` + `shiny_urps_adequacy/data/urps_model_data.R` (added
`BANDS`); removed the hardcoded copy from `scripts/urps_supply_demand_national_2026-07-23.R`,
`scripts/urps_module_a_effective_supply_2026-07-23.R`, `shiny_urps_scenarios/app.R`,
`shiny_urps_adequacy/model.R`; extended `tests/testthat/test-ssot-age-bands.R`.

**Hardcoded copies removed:** 4 (one per consumer) → 0. `BANDS` now lives in the 2 snapshots (parity-guarded) +
the engine (canonical). Behavior-preserving.

**Validation guards:** extended the Shiny parity test to assert snapshot `BANDS == WC_BANDS` and
`length(BANDS) == length(BAND_LABELS)+1` in *both* snapshot files; the engine's `WC_BANDS` well-formedness gate
is unchanged.

**Tests added (extended existing guard, +7 → 17/0):** parity (both snapshots' `BANDS` == canonical + length
invariant); **adversarial** (all four consumers still source the snapshot and none re-hardcode `BANDS`, snapshots
exempt); **semantic end-to-end** (`cut()` with the snapshot's own `BANDS`/`BAND_LABELS` assigns every test age to
the same band as the engine — wiring cannot change any assignment).

**Initial failures:** none. **Final: age-bands guard 17/0; all 34 SSOT guards 505/0; all 6 touched files parse.**
Final grep: no `BANDS <- c(...)` remains in any consumer (only the 2 snapshots + engine keep the literal).

**Remaining risks:** the two snapshots remain hand-maintained copies (the "auto-generated" header has no backing
generator); the parity guard catches any drift from `WC_BANDS`. If a generator is ever introduced it must emit
`BANDS` too. `BAND_EV`/`BAND_PY` (the per-band event/person-year vectors in the snapshots) are a *separate*
not-yet-audited quantity — candidate below.

**Recommended next candidate:** the per-band hazard inputs `BAND_EV` / `BAND_PY` (`urps_model_data.R:13-14`,
duplicated across both snapshots and derived in the engine/hazard CSV) — the numerators/denominators of the
departure hazard, higher-stakes than the band edges and currently three parallel copies.

**Status:** ✅ complete. Uncommitted (loop rule).

---

## Iteration 38 — per-band hazard inputs `BAND_EV` / `BAND_PY` (drift guard, no copy removed)

**Candidate:** `BAND_EV` (event-count numerators) and `BAND_PY` (person-year denominators) of the URPS departure
hazard, `urps_model_data.R:14-15`.

**Why higher-risk than alternatives:** these are the **highest-stakes numbers in the supply projection** — the
numerator/denominator of every band's departure hazard, which drives the entire 2025-2050 supply trajectory and
the Monte-Carlo fan. They are defined **identically in two self-contained Shiny snapshots** and consumed from
whichever snapshot each script sources; a silent drift between the two apps would make them display different
hazards from the same "model data".

**Audit / discrepancy adjudication:** the two snapshots (`shiny_urps_scenarios/urps_model_data.R`,
`shiny_urps_adequacy/data/urps_model_data.R`) are **byte-identical**; all consumers (`urps_module_a:21`,
`urps_supply_demand_national:38,54`, `shiny_urps_scenarios/app.R:85,123`) read from the snapshot they source, so
there is **no third live copy** — the engine does NOT define these (unlike `WC_BANDS`). Origin: the hierarchical
partial-pooling pipeline; `BAND_PY[["fully_obs"]] == c(3854,973,811,488,221,53,3)` **equals the frozen
`data/hazard_by_band_pooled_vs_unpooled.csv` `urps_py` column exactly** (verified). **Intentional differences
preserved:** the three windows differ by design — `fully_obs` = hierarchical partial-pooled *expected* events
(non-integer, penalized; manuscript primary), `drop2`/`full` = raw integer counts under alternative observation
windows; NOT collapsed.

**Canonical:** a **frozen-artifact + parity** contract, not a new constant. No shared code home is possible (both
snapshots must deploy standalone on shinyapps.io, so neither can source a repo-root file — the demand scripts
already single-source from the scenarios snapshot). The SSOT mechanism is therefore a drift guard: the two
snapshots must agree with each other, and `BAND_PY[fully_obs]` must agree with the frozen hazard CSV (its true
origin). This mirrors iter36's FROZEN-parity choice.

**Files changed:** none refactored (see below); new `tests/testthat/test-ssot-band-hazard-inputs.R`.

**Hardcoded copies removed:** 0 — and this is the correct outcome, not a shortfall: the duplication is
scenarios-snapshot vs adequacy-snapshot, two standalone Shiny apps that cannot share a code home without breaking
deployment. The iteration converts an **unguarded** byte-identical duplication into a **guarded** one.

**Validation guards / tests added (`test-ssot-band-hazard-inputs.R`, 24/0):** **cross-snapshot parity** (both
snapshots' `BAND_EV`/`BAND_PY` identical, all windows); **structure** (shared window names; one value per band);
**cross-artifact origin** (`BAND_PY[fully_obs]` == frozen CSV `urps_py`, band order matched); **intentional
differences preserved** (`fully_obs` EV non-integer/pooled vs `full` EV integer/raw, and the two windows are not
equal); **semantic** (hazards non-negative, events ≤ exposure, `HAZ_WINDOWS[fully_obs]` == EV/PY, hazard rises
45-49 → 55-59 → 65-69); **adversarial** (no window dropped/reordered between EV and PY; zero-exposure bands carry
zero events — no phantom hazard).

**Initial failures:** none. **Final: band-hazard-inputs 24/0; all 35 SSOT guards 529/0.**

**Remaining risks:** the whole `urps_model_data.R` file is duplicated between the two Shiny apps (an
architectural item beyond one SSOT iteration — a shared generator/build-time copy would remove it but risks
Shiny standalone deployment); the guard now catches any `BAND_EV`/`BAND_PY` drift. `BAND_EV[fully_obs]` is
model-derived (partial-pooled) and has no simple frozen-artifact to parity-check against beyond cross-snapshot —
if the pooling is re-fit, both snapshots must be regenerated together.

**Recommended next candidate:** `GRAD_URPS <- c(61,66,63,66)` (`urps_model_data.R`, the ACGME AY2020-24 completer
counts) — duplicated across both snapshots and the driver of `ENTRANTS <- mean(GRAD_URPS)` wired in iters 7/33;
same two-snapshot cross-parity pattern, and it feeds a published entrant-inflow number.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iteration 38 files only
(`tests/testthat/test-ssot-band-hazard-inputs.R`, `docs/SSOT_LEDGER.md`).

---

## Iteration 39 — `GRAD_URPS` was already audited (iter3); closed its residual second-snapshot gap

**Candidate selected:** `GRAD_URPS <- c(61,66,63,66)` (the ACGME AY2020-24 URPS completer counts), per iter38's
recommendation.

**Finding — already in the ledger:** this value is **Iteration 3** (`WC_GRAD`). It already has a canonical home
(engine `R/workforce_cliff_engine.R:29` `WC_GRAD$URPS`), `WC_ENTRANTS <- sapply(WC_GRAD, mean)` derivation, a
frozen-CSV drift guard against `workforce_projections_consolidated.csv`, and an adversarial re-hardcode scan, in
`tests/testthat/test-ssot-graduate-counts.R`. Per the no-double-audit rule I did **not** re-audit it. (iter38's
recommendation was mistaken — it did not check that GRAD_URPS was already covered.)

**Residual gap closed (coverage-completion of iter3, not a new audit):** iter3's Shiny-copy parity test predated
the `shiny_urps_adequacy` app, so it checked only the **scenarios** snapshot; the **adequacy** snapshot's
`GRAD_URPS <- c(61,66,63,66)` (`shiny_urps_adequacy/data/urps_model_data.R:8`) was **unguarded** (verified ==
canonical, 0 references in any guard). This is the identical second-snapshot gap closed for `BANDS` (iter37) and
`BAND_EV/PY` (iter38). Extended the existing test's parity check to loop over **both** snapshots.

**Files changed:** `tests/testthat/test-ssot-graduate-counts.R` (parity test now covers both snapshots).
**No production/consumer code touched; no new value canonicalized** (the value was already canonical).

**Hardcoded copies removed:** 0 (self-contained Shiny copies, cannot be removed; now both drift-guarded).

**Tests:** existing guard extended; **graduate-counts 14/0; all 35 SSOT guards 530/0.**

**Remaining risks:** none new. Same standing architectural item as iter38 (the two `urps_model_data.R` are
duplicated whole; a shared generator would remove the family of second-snapshot gaps at once).

**Process note:** before recommending a "next candidate", grep the ledger AND `tests/testthat/test-ssot-*` for an
existing guard — three of the recent snapshot-lineage values already had partial iter3-era guards.

**Recommended next candidate (genuinely fresh, ledger-checked):** `WORKFORCE_CONVERSION_FLOOR` usage vs the
`optimistic_nrmp`/`cautious_trend` scenario multipliers in `scripts/graduate_growth_scenarios.R:33` — the
scenario-conversion assumptions (e.g. the `0.70` floor is canonical in `workforce_constants.R`, but the sibling
scenario factors around it may be bare literals). Verify none are already ledgered first.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 38-39 files
(`tests/testthat/test-ssot-band-hazard-inputs.R`, `tests/testthat/test-ssot-graduate-counts.R`,
`docs/SSOT_LEDGER.md`) — iter38 remains validated/green and awaits the next "land" instruction.

---

## Architectural task — canonical `urps_model_data.R` + sync generator + whole-file drift guard

**Not a numbered SSOT iteration** — the structural fix for the family of second-snapshot gaps that iters 37, 38,
39 each patched constant-by-constant (`BANDS`, `BAND_EV/PY`, `GRAD_URPS`). Authorized by the user as a dedicated
task.

**Problem:** the whole `urps_model_data.R` file was duplicated as two independently hand-maintained copies —
`shiny_urps_scenarios/urps_model_data.R` and `shiny_urps_adequacy/data/urps_model_data.R` (byte-identical, but
nothing enforced it; each new constant added to one could silently miss the other).

**Why the duplication is unavoidable (not a smell to delete):** both apps deploy to shinyapps.io via
`rsconnect::deployApp(appDir=".", appFiles=<app-dir-relative list>)`. The bundle contains only those files, so
neither app can `source()` a repo-root file at runtime — each app dir must physically contain its own copy.
Confirmed by reading both `DEPLOY.R` bundles. So the fix is not de-duplication but **one canonical + synced
replicas + a drift guard**.

**Design chosen:**
- **Canonical:** `shiny_urps_scenarios/urps_model_data.R` (already sourced by the repo demand scripts
  `urps_supply_demand_national` / `urps_module_a`, and already the reference for every SSOT guard).
- **Replica:** `shiny_urps_adequacy/data/urps_model_data.R`, kept **byte-identical**.
- **Generator:** `scripts/sync_urps_model_data.R` — copies canonical → replicas and verifies by hash; `--check`
  mode verifies only and exits non-zero on drift (CI / deploy preflight). Fails loudly on any bad copy.
- **Whole-file drift guard:** `tests/testthat/test-ssot-urps-model-data-sync.R` — asserts every replica is
  byte-identical (line-for-line + md5) to canonical, plus a sourced-constant equality check and an adversarial
  one-byte-drift detection. This is a **superset** of the per-constant guards: any future drift — audited
  constant or not — now fails here.
- **Deploy fail-loud:** `shiny_urps_adequacy/DEPLOY.R` preflight now refuses to ship a replica that has drifted
  from canonical (guarded so it only checks when the canonical is reachable, i.e. deploying from the repo).
- **Header:** replaced the misleading "Auto-generated ... from R/workforce_cliff_engine.R" line (no such
  generator ever existed) with an accurate provenance header naming the canonical, the sync script, and the
  guard; propagated to the replica by the sync so both stay byte-identical.

**Files:** new `scripts/sync_urps_model_data.R`, new `tests/testthat/test-ssot-urps-model-data-sync.R`; edited
`shiny_urps_scenarios/urps_model_data.R` (header) + `shiny_urps_adequacy/data/urps_model_data.R` (synced) +
`shiny_urps_adequacy/DEPLOY.R` (preflight drift check).

**Behavior:** zero runtime change — the replica content is byte-identical to before (only the header comment
changed, identically in both). Both apps load all constants unchanged; both demand scripts unaffected.

**Validation:** sync guard 17/0; drift round-trip proven (tamper a replica → `--check` exits 1 → re-sync → exits
0 → byte-identity restored); all touched files parse; **all SSOT guards 547/0**.

**Residual:** the per-constant guards (iters 37-39 + iter3) are now redundant with the whole-file guard but kept
— they give human-readable, value-specific failure messages and check the engine-lineage canonical too. Future
model-data edits: change the canonical, run `Rscript scripts/sync_urps_model_data.R`, commit both.

**Status:** ✅ complete. Uncommitted — awaits a "land it" instruction.

---

## Iteration 40 — "Workforce Outlook" classification (Adequate/Marginal/Insufficient, cuts 0.8/1.2)

**Candidate:** the replacement-ratio → workforce-outlook classification: `Adequate` (RR≥1.2), `Marginal`
(0.8≤RR<1.2), `Insufficient` (RR<0.8).

**Why higher-risk than alternatives:** it produces a **published categorical claim** — the "Workforce Outlook"
per subspecialty (a subspecialty is called "Insufficient" vs "Adequate"). Unlike the contract's replacement
scheme (which HAS a canonical `classify_replacement()` + `WORKFORCE_REPLACEMENT_*` constants), this scheme had
**no canonical home**: the cutpoints `0.8`/`1.2` were computed with bare inline literals in the one live-logic
site (`graduate_growth_scenarios.R:46`) and independently re-stated in the published table caption
(`create_workforce_table.R:279`), the appendix math (`appendix_workforce_replacement_ratio.Rmd:96-98`), and the
manuscript text — four hand-synchronised copies of a classification with nothing tying them together. (The
recommended candidate, the `graduate_growth_scenarios` conversion multipliers, was already done: iter10
`WORKFORCE_CONVERSION_FLOOR`, iter7 NRMP — only a single-use `0.5` damping factor remained, too weak.)

**Audit / discrepancy adjudication:** **two distinct classification schemes coexist and must not be merged** —
Scheme 1 (contract) "Above/At/Below replacement" cuts 0.95/1.05, **already single-sourced (iter16, recorded)**;
Scheme 2 (this) "Adequate/Marginal/Insufficient" cuts 0.8/1.2. Within Scheme 2 the cutpoints agree at every site
(graduate_growth_scenarios.R:46, caption:279, appendix:96-98, manuscript txt) → authority clear. The manuscript
table's outlook column is reviewed **data** (a tribble) + a caption, not computed; left as-is and guarded.

**Canonical:** `R/workforce_constants.R` (the shared engine+manuscript constants home) — `WORKFORCE_OUTLOOK_ADEQUATE_MIN
= 1.2`, `WORKFORCE_OUTLOOK_MARGINAL_MIN = 0.8` (fail-loud: ordered, positive) + a pure function
`classify_workforce_outlook(ratio)`. Function (value depends on input) with the cutpoints as named constants.

**Files changed:** `R/workforce_constants.R` (new constants + classifier); `scripts/graduate_growth_scenarios.R:46`
(inline `ifelse` → `classify_workforce_outlook(ratio)`); new `tests/testthat/test-ssot-workforce-outlook.R`.

**Hardcoded copies removed:** 1 live classifier (the inline `ifelse(ratio>=1.2,...,ratio>=0.8,...)`). The 3
manuscript/appendix restatements stay literal (published prose/data) but are now **parity-guarded** against the
canonical. Behavior-preserving (verified: identical to the old `ifelse` across a boundary grid, `NA` propagates).

**Validation guards:** `stopifnot` (ordered, positive cutpoints); the guard's cross-doc parity test fails if the
table caption or appendix math drifts from the constants.

**Tests added (`test-ssot-workforce-outlook.R`, 20/0):** well-formed/ordered cutpoints; **behavior-preserving**
(reproduces the inline `ifelse` exactly, incl. boundaries + `NA`); **semantic** (boundary-exact `>=`, monotone
non-regression as RR rises); **intentional-difference** (outlook labels DISJOINT from the contract's Above/At/Below
labels — schemes not collapsed); **adversarial** (graduate_growth_scenarios references the SSOT, no inline
1.2/0.8 classifier remains); **cross-doc parity** (published caption + appendix math state the canonical cuts).

**Initial failures:** none. **Final: workforce-outlook 20/0; all 36 SSOT guards 567/0; graduate_growth_scenarios parses.**

**Remaining risks:** the manuscript prose/caption/appendix remain literal by design (they are published text); the
parity guard catches drift but a deliberate cutpoint change must be mirrored into the paper by hand. The manuscript
table's outlook values are a reviewed tribble, not computed from `classify_workforce_outlook` (a bigger wiring
change, deferred — the caption parity guard is the interim protection).

**Recommended next candidate:** the manuscript workforce table's per-row **data** in `create_workforce_table.R:90-91`
(baseline/retirement/ratio numbers hardcoded in a tribble) vs the frozen consolidated CSV — verify whether the
table reads the SSOT CSV or re-types the numbers (a re-typed published table would be a high-risk drift), and
whether it's already covered by the contract validator. Ledger-check first.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iteration 40 files only
(`R/workforce_constants.R`, `scripts/graduate_growth_scenarios.R`, `tests/testthat/test-ssot-workforce-outlook.R`,
`docs/SSOT_LEDGER.md`).

---

## Iteration 41 — Module C attribution-plasticity multipliers (mid=1.0/low=0.8/high=1.2)

**Candidate considered first, STOPPED (already flagged, PI-gated): the manuscript workforce table tribble
(`create_workforce_table.R:88`).** Thoroughly investigated: its hardcoded numbers (GO baseline 1352 vs SSOT
1052; ratios 1.08/0.73/1.61 vs 5.61/7.11/11.06; Scheme-2 labels; `fellowship_total_5yr`) disagree with the
frozen `workforce_projections_consolidated.csv` on nearly every field. Confirmed it is **dead/legacy** (sourced
by NO live manuscript Rmd; the paper uses `get_baseline()` → `workforce_statistics.R` → the CSV; the tribble's
labels would fail the contract validator). Already documented in `docs/FLAG_stale_workforce_table_hardcode.md`
and **entangled with the off-limits URPS baseline reconciliation** → PI decision, not a loop refactor. Not
touched; recorded so it isn't re-audited.

**Candidate selected:** the Module C attribution scenario multipliers `c(mid=1.0, low=0.8, high=1.2)` in
`scripts/urps_demand_module_bc_2026-07-23.R` — the ±20% sensitivity band on each service's urogyn-attributable
share, feeding the low/mid/high procedure-count and required-FTE demand projections.

**Why higher-risk than alternatives:** the triple was **duplicated within one file** — as literal args
`attr_proc(1.0)/attr_proc(0.8)/attr_proc(1.2)` (lines 65-67) AND as `c(mid=1.0,low=0.8,high=1.2)` in the
required-FTE loop (line 70). The two drive the *same* scenario columns; a change to the low/high band that
updated one and missed the other would silently make the procedure-count and FTE scenarios inconsistent. Feeds
published demand-adequacy bounds.

**Audit / discrepancy adjudication:** the triple appears only in `module_bc` (not in `module_bc_corrected`,
which uses the empirical field-residual attribution instead, nor in `FROZEN`) → intra-file duplication. The
three values are **distinct scenarios (low/mid/high) — preserved, not collapsed**. Same-numbers-different-meaning
vs iter40's outlook cutpoints (0.8/1.2): the attribution band is unrelated to the replacement-ratio
classification and must never be merged (guarded).

**Canonical:** file-local named vector `URPS_ATTRIB_MULT <- c(mid=1.0, low=0.8, high=1.2)` with fail-loud
`stopifnot` (ordered, mid=1.0, low<mid<high). File-local (not a shared constant) because the value is used only
in this one script — the right scope; a shared home would be over-engineering.

**Files changed:** `scripts/urps_demand_module_bc_2026-07-23.R` (canonical vector + both consumers wired to it);
new `tests/testthat/test-ssot-attribution-multipliers.R`.

**Hardcoded copies removed:** the duplicated triple (3 literal args + 1 inline named vector) → 1 canonical
vector. Behavior-preserving (values identical: 1.0/0.8/1.2).

**Validation guards:** `stopifnot` in the file; the guard evaluates only the constant line (the script opens a
DuckDB connection, so it cannot be sourced whole) and checks values + wiring.

**Tests added (`test-ssot-attribution-multipliers.R`, 16/0):** well-formed/ordered; **behavior-preserving**
(1.0/0.8/1.2); **semantic** (symmetric ±0.2 band); **adversarial** (both consumers reference `URPS_ATTRIB_MULT`,
no bare `attr_proc(0.8)`/`attr_proc(1.2)`/inline named-vector remains); **intentional-difference** (the
attribution band is file-local and did NOT leak into `workforce_constants.R`, keeping it distinct from the
outlook cutpoints).

**Initial failures:** none. **Final: attribution-multipliers 16/0; all 38 SSOT guards 583/0; module_bc parses.**

**Remaining risks:** none for this value (single-file, fully wired). The stale workforce-table tribble remains an
open PI-gated item (`docs/FLAG_stale_workforce_table_hardcode.md`), unrelated to this iteration.

**Recommended next candidate:** the FPMRS supply **figure** hardcodes in `scripts/fig_fpmrs_supply_line.R`
(1196/1283/1301/4.4/55.6/1.08/15.2/CI) — same class as the stale table but noted in the FLAG doc as PI-gated
(baseline-entangled); verify which of its numbers are baseline-independent (e.g. the CI z was already iter15,
the year axis iter14) and whether any remaining literal is safe to single-source without touching the baseline.
Otherwise scan `code/` (the older pipeline) for an un-audited duplicated constant. Ledger-check first.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 40-41 files
(`R/workforce_constants.R`, `scripts/graduate_growth_scenarios.R`, `scripts/urps_demand_module_bc_2026-07-23.R`,
`tests/testthat/test-ssot-workforce-outlook.R`, `tests/testthat/test-ssot-attribution-multipliers.R`,
`docs/SSOT_LEDGER.md`) — iter40 remains validated/green and awaits the next "land" instruction.

---

## Iteration 42 — study observed-window START year (`2013`) → `WORKFORCE_OBSERVED_START_YEAR`

**Candidate considered first, REJECTED: the FPMRS supply-figure hardcodes** (1196/1283/1301/4.4/55.6/15.2/1.08).
Same old-era supply numbers as the stale table, PI-gated + baseline-entangled per
`docs/FLAG_stale_workforce_table_hardcode.md`; horizon/CI-z/axis already single-sourced (iters 1/14/15). Not
touched.

**Candidate selected:** the study observed-administrative-data-window START year `2013` — a baseline-independent
design constant.

**Why higher-risk than alternatives:** it fixes the lower bound of the *observed* data the whole analysis rests
on (the Medicare panel, the observed supply series, and the truth-contract year gate), yet was a bare literal in
three code files across three lineages. A change to the study start that updated one and missed another would
silently mis-scope the age-productivity panel or let the validator admit/reject the wrong years — and unlike the
supply numbers it is NOT baseline-entangled, so it is safe to unify now.

**Audit / provenance:** `scripts/urps_module_a_age_productivity_2026-07-23.R:27` (`yrs <- 2013:2024`),
`scripts/fig_fpmrs_supply_line.R:16` (`OBS_START <- 2013L`), `R/validators/validate_workforce_truth_contract.R:98`
(`year_min_allowed <- 2013L`), and `config/expected_workforce_counts.yml:74` (`test_years` begins 2013).

**Discrepancy adjudication:** the START `2013` is consistent at every site → one SSOT. The window END is
**intentionally different and NOT collapsed**: the truth-contract study scope ends `2023` (`year_max_allowed`),
while the Medicare panel and observed supply series run to `2024` (latest available). Only the shared start is
unified; no end constant was introduced.

**Canonical:** `R/workforce_constants.R::WORKFORCE_OBSERVED_START_YEAR <- 2013L` (constant; fail-loud: integer,
pinned 2013, `< PROJECTION_BASELINE_YEAR`). Constant (a fixed study-design year), not a function.

**Files changed:** `R/workforce_constants.R` (new constant); `scripts/fig_fpmrs_supply_line.R:16`;
`scripts/urps_module_a_age_productivity_2026-07-23.R` (added `source(workforce_constants)` + wired `yrs`);
`R/validators/validate_workforce_truth_contract.R` (guarded top-of-file source + wired `year_min_allowed`); new
`tests/testthat/test-ssot-observed-start-year.R`. Config YAML left as data, parity-guarded.

**Hardcoded copies removed:** 3 live literals (age-productivity, figure, validator) → 0. Behavior-preserving
(`WORKFORCE_OBSERVED_START_YEAR == 2013L`; sequences identical; validator's own test 31/0, no regression).

**Validation guards:** `stopifnot` in the constant; the guard's cross-config parity test ties
`config/expected_workforce_counts.yml`'s `test_years[1]` to the constant.

**Tests added (`test-ssot-observed-start-year.R`, 17/0):** well-formed (precedes projection baseline);
**adversarial** (all 3 consumers reference the SSOT, no bare `2013` remains); **intentional-difference** (the 2023
study-scope end and 2024 panel end stay distinct, no end constant folded in); **cross-config parity** (config
`test_years` begins at the constant, contiguous); **behavior-preserving** (wired sequences equal the literals).

**Initial failures:** none. **Final: observed-start 17/0; validator test 31/0 (no regression); all 39 SSOT guards
600/0; all 4 touched files parse.**

**Remaining risks:** the FPMRS figure remains PI-gated for its supply numbers (unrelated to this year constant).
The study-scope END `2023` (validator `year_max_allowed` + config `test_years` end) is a *separate* value that may
also duplicate `WC_OBS_END` (iter5) — a candidate below.

**Recommended next candidate:** the study-scope END year `2023` — `validate_workforce_truth_contract.R`
`year_max_allowed <- 2023L` and `config/expected_workforce_counts.yml` `test_years` end; check whether it
duplicates the engine's `WC_OBS_END` (iter5's observation window) and can be unified without collapsing the
Medicare-panel 2024 end. Ledger-check first.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iteration 42 files only
(`R/workforce_constants.R`, `scripts/fig_fpmrs_supply_line.R`,
`scripts/urps_module_a_age_productivity_2026-07-23.R`, `R/validators/validate_workforce_truth_contract.R`,
`tests/testthat/test-ssot-observed-start-year.R`, `docs/SSOT_LEDGER.md`). Iterations 40-41 already landed in
`a72726c`.

---

## Iteration 43 — study observation-confirmable END year (`2023`) → `WORKFORCE_OBSERVED_END_YEAR`

**Candidate:** the study observation-confirmable END year `2023` — the 3-year-follow-up boundary through which a
departure can be confirmed; the upper bound of the truth-contract study scope (2013-2023).

**Why higher-risk than alternatives:** it defines which departures the analysis can confirm (right-censoring
boundary) and which panel years the truth contract admits. `WC_OBS_END <- 2023L` was the engine's authoritative
constant, but the truth-contract validator **re-hardcoded** the same 2023 as `year_max_allowed <- 2023L` — an
un-wired duplicate that could silently disagree if one changed (e.g. when 2024 becomes confirmable). The ledger
(line 374) had explicitly noted `WC_OBS_END` was "not yet individually guarded."

**Audit / provenance:** `R/workforce_cliff_engine.R:26` (`WC_OBS_END <- 2023L`, authoritative),
`R/validators/validate_workforce_truth_contract.R:103` (`year_max_allowed <- 2023L`, duplicate),
`config/expected_workforce_counts.yml:74` (`test_years` ends 2023, YAML data).

**Discrepancy adjudication:** both `2023` sites mean the last confirmable observed year → one SSOT. **NOT
collapsed:** the reference / latest-data year `2024` (engine `WC_REF_YEAR`; the Medicare panel + observed supply
series run to 2024, iter42) is a *separate* concept — the confirmable-observation end (2023) precedes the
latest-available-data year (2024) by the 3-year follow-up rule; they must stay distinct.

**Canonical:** `R/workforce_constants.R::WORKFORCE_OBSERVED_END_YEAR <- 2023L` (constant; fail-loud: integer,
pinned 2023, `> WORKFORCE_OBSERVED_START_YEAR`). Homed in the shared constants file (reachable by both the engine
and the validator) and the engine **aliases** `WC_OBS_END <- WORKFORCE_OBSERVED_END_YEAR` — matching the existing
`WC_YEAR0 <- PROJECTION_BASELINE_YEAR` / `WC_HORIZON` / `WC_ENTRY_AGE` engine-alias pattern. Pairs with iter42's
`WORKFORCE_OBSERVED_START_YEAR`.

**Files changed:** `R/workforce_constants.R` (new constant); `R/workforce_cliff_engine.R:26` (alias);
`R/validators/validate_workforce_truth_contract.R:103` (wired `year_max_allowed`); new
`tests/testthat/test-ssot-observed-end-year.R`. Config YAML left as data, parity-guarded.

**Hardcoded copies removed:** 2 live literals (engine + validator) → 0 (engine now aliases; validator references).
Behavior-preserving (`WC_OBS_END == 2023L` unchanged; the alias resolves at engine load).

**Validation guards:** `stopifnot` in the constant; the guard checks the engine alias + cross-config parity.

**Tests added (`test-ssot-observed-end-year.R`, 18/0):** well-formed + ordered (start < end < baseline);
**cross-lineage alias** (engine `WC_OBS_END` == constant, and `WC_WIN[2]=2021 <= WC_OBS_END`); **adversarial**
(engine + validator reference the SSOT, no bare 2023L); **intentional-difference** (2023 end never shares a symbol
with the 2024 latest-data year; `WC_REF_YEAR` stays 2024, panel stays `:2024`); **cross-config parity**
(`test_years` last == observation end, first == observed start).

**Initial failures:** 1 — `test-ssot-observed-start-year.R` (iter42) asserted the validator KEEPS
`year_max_allowed <- 2023L` as a bare literal (to prove the end wasn't folded into the START constant).
**Classification: obsolete-test-tied-to-old-literal** — iter43 legitimately gave the end its own constant.
**Fix:** updated that assertion to the canonical form (`year_max_allowed <- WORKFORCE_OBSERVED_END_YEAR`, and
`!= WORKFORCE_OBSERVED_START_YEAR`); the test's intent (end distinct from start) is preserved and strengthened.

**Final results:** observed-end 18/0; observed-start 18/0 (fixed); obs-window 9/0 + truth-contract 31/0 (no
regression); **all 40 SSOT guards 619/0**; all touched files parse; engine alias resolves to 2023.

**Remaining risks:** none for this value. `WC_REF_YEAR <- 2024L` (engine reference / latest-data year) remains a
bare literal that likely duplicates the age-productivity / fig panel end 2024 — a candidate below.

**Recommended next candidate:** the reference / latest-data year `2024` — engine `WC_REF_YEAR <- 2024L` vs the
`:2024` panel end in `urps_module_a_age_productivity` and `OBS_END`(=2024) in `fig_fpmrs_supply_line`; verify
they are the same "latest available Medicare year" concept and can be unified as `WORKFORCE_REFERENCE_YEAR`
without collapsing the 2023 observation end. Ledger-check first.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 42-43 files. Iterations 40-41 already
landed in `a72726c`.

---

## Iteration 44 — reference / latest-data year (`2024`) → `WORKFORCE_REFERENCE_YEAR`

**Candidate:** the reference / latest-available-data year `2024` — the year cohort ages are reckoned as-of, and
the most recent Medicare panel year.

**Why higher-risk than alternatives:** it anchors age reconstruction (`age = reference − cert_year + age-at-cert`)
and the age-productivity panel extent — a wrong reference year shifts every reconstructed age and therefore the
age-structured hazard. `WC_REF_YEAR <- 2024L` was authoritative and already aliased by 4 engine-sourcing scripts,
but the age-productivity script **re-hardcoded** the same reference year as bare `2024` (`birth := 2024-age24`,
panel end `:2024`) — un-wired duplicates outside the engine lineage.

**Audit / provenance:** `R/workforce_cliff_engine.R:24` (`WC_REF_YEAR <- 2024L`, authoritative; used at :77 for
age reconstruction; aliased by hierarchical_hazard / abu_pathway / scenario_projection / build_hazard_comparison),
`scripts/urps_module_a_age_productivity_2026-07-23.R:23` (`birth := 2024-age24`) + `:28` (panel end `:2024`).
Schema identifiers `medicare_part_b_by_service_2024` / `national_2024` / `w65_2024` in module_bc are Medicare
TABLE/COLUMN names — **intentional, left literal** (cf. iter24's `_2050` columns).

**Discrepancy adjudication:** the engine reference year and the age-productivity `2024`s are the SAME concept
(latest Medicare year / age-as-of year) → one SSOT. **NOT collapsed:** the observation-confirmable end `2023`
(`WORKFORCE_OBSERVED_END_YEAR`, iter43) is one year earlier by the 3-yr follow-up rule; and the module_bc Medicare
table/column identifiers stay literal (schema, not the value).

**Canonical:** `R/workforce_constants.R::WORKFORCE_REFERENCE_YEAR <- 2024L` (constant; fail-loud: integer, pinned
2024, `> WORKFORCE_OBSERVED_END_YEAR`, `< PROJECTION_BASELINE_YEAR`). Engine **aliases**
`WC_REF_YEAR <- WORKFORCE_REFERENCE_YEAR` (matching WC_OBS_END/WC_YEAR0). Completes the year-constants family:
START 2013 < END 2023 < REFERENCE 2024 < BASELINE 2025 (a `stopifnot` in the guard checks strict monotonicity).

**Files changed:** `R/workforce_constants.R` (new constant); `R/workforce_cliff_engine.R:24` (alias);
`scripts/urps_module_a_age_productivity_2026-07-23.R` (`birth`, panel end); new
`tests/testthat/test-ssot-reference-year.R`.

**Hardcoded copies removed:** 3 live literals (engine + 2 in age-productivity) → 0. Behavior-preserving
(`WC_REF_YEAR == 2024L`; age reconstruction identical; alias resolves at load).

**Validation guards:** `stopifnot` in the constant (ordering vs the neighbouring year constants); the guard checks
the engine alias, age-reconstruction invariance, and that the Medicare schema names stay literal.

**Tests added (`test-ssot-reference-year.R`, 18/0):** well-formed + full-family monotonicity; **cross-lineage alias**
(engine `WC_REF_YEAR` == constant, `WC_WIN[2] < WC_REF_YEAR`); **behavior-preserving** (age reconstruction
unchanged); **adversarial** (engine + age-productivity reference the SSOT, no bare `2024`); **intentional-difference**
(module_bc `medicare_part_b_by_service_2024` schema name stays literal; the constant did not leak into SQL).

**Initial failures:** 1 — the iter42 start-year guard (uncommitted) asserted the panel end reads literally
`WORKFORCE_OBSERVED_START_YEAR:2024`, in two blocks (adversarial + intentional-difference). Iter44 wired the panel
end to `:WORKFORCE_REFERENCE_YEAR`. Also the iter43 end-year guard asserted `WC_REF_YEAR <- 2024L` + the `:2024`
panel end. **Classification: obsolete-tests-tied-to-old-literals** (cascading from iter44's alias, exactly like the
iter42→43 cascade). **Fix:** updated all three assertions to the canonical `WORKFORCE_REFERENCE_YEAR` form;
intent preserved (reference year is still 2024, still one past the 2023 end).

**Final results:** reference-year 18/0; observed-start 18/0 + observed-end 19/0 (both fixed); age-at-cert 10/0 +
obs-window 9/0 (no regression — both consume `WC_REF_YEAR`); **all 41 SSOT guards 638/0**; engine alias resolves
to 2024; no bare reference-year literal remains.

**Remaining risks:** none for this value. The workforce year-constants family is now complete (START/END/REFERENCE/
BASELINE all single-sourced). The module_bc Medicare data-year schema identifiers remain intentional literals
(guarded).

**Recommended next candidate:** with the year constants exhausted, scan a fresh area — e.g. the older `code/`
pipeline for an un-audited duplicated constant, or the age-productivity model's spline `df`/age-range bounds
(`age>=30 & age<=80`, `ns(age, df=4)`) if those bounds are duplicated across the Module-A scripts. Ledger-check
first.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 42-44 files. Iterations 40-41 already
landed in `a72726c`.

---

## Iteration 45 — reference urology-pathway FTE default (`0.70`) → `URO_FTE_DEFAULT`

**Candidates considered first, STOPPED:** (a) the `1.96` CI z-multiplier in the live `code/` pipeline — already
ledgered (iter15), and iter15 **explicitly declared** `code/`'s copy "intentionally literal" (its adversarial
grep scopes to `scripts/`); re-wiring would reverse a recorded decision, so left as-is (iter15 stands). (b) the
age-productivity `30/80` age bounds + `ns(age, df=4)` — single-site, no duplication. (c) the "2025 averages 1.0"
normalization — a runtime-computed method (`WBAR`), not a duplicated constant. (d) `OB_BASE_SHARE` — already
derived (`N_OBGYN/N_TOT`) and single-sourced.

**Candidate selected:** the reference urology-pathway FTE default `0.70` (fraction of a urology-pathway
urogynecologist's clinical time spent in urogynecology, in the Reference scenario).

**Why higher-risk than alternatives:** it sets the reference/frozen-manuscript pathway blend that the adequacy
app's headline capacity index keys off. It was duplicated 5× — `model.R` DEFAULTS (`0.70`), `app.R` Reference
preset (`70`), `app.R` reset handler (`70`), and two guard tests (`0.70`) — while its **sibling `ob_share` was
already single-sourced** via `round(100*OB_BASE_SHARE)`. That asymmetry (one blend term single-sourced, the other
hardcoded) is the exact drift trap: a reference-blend change would update `OB_BASE_SHARE` consumers but silently
leave the `uro_fte` copies stale.

**Audit / provenance:** `shiny_urps_adequacy/model.R:42` (DEFAULTS `uro_fte=0.70`); `app.R:55` (Reference preset
`uro_fte=70`); `app.R:222` (reset handler `value=70`); `tests/testthat/test-guards-consistency.R:81`
(reset_target); `tests/testthat/test-guards-app.R:37` (positional in `project()`). All within the self-contained
adequacy app; `app.R` + both tests already `source(model.R)`.

**Discrepancy adjudication:** all five are the same reference value (fraction 0.70 = percent 70) → one SSOT.
**NOT collapsed:** (1) the slider RANGE `uro_fte=list(ref=c(55,85),...)` and the `±0.15` sensitivity perturbation
are distinct scenario knobs, left literal; (2) same number `0.70` as `WORKFORCE_CONVERSION_FLOOR` (iter10) but a
DIFFERENT concept (urology clinical-time vs graduate-to-practice conversion) — kept in separate homes, guarded;
(3) the independent-oracle test fixtures (`DEF_INPUTS`, the fingerprint `reference`/`higher_entr` lists) are
all-literal input snapshots (`retire=65, ob_share=77, uro_fte=70, …`) that serve as independent checks — left
literal per iter15's "test-oracle fixtures intentionally literal" precedent.

**Canonical:** `shiny_urps_adequacy/model.R::URO_FTE_DEFAULT <- 0.70` (constant; app-local, next to
`OB_BASE_SHARE`/`BASE_YEAR`). App-local (self-contained deployment; used only in this app) — the right scope.

**Files changed:** `model.R` (new constant + DEFAULTS); `app.R` (Reference preset + reset handler, now
`round(100*URO_FTE_DEFAULT)` mirroring `ob_share`); the two DEFAULTS-comparison guard tests; new
`tests/testthat/test-ssot-uro-fte-default.R`.

**Hardcoded copies removed:** 4 live copies (DEFAULTS + preset + reset + 2 comparison fixtures) → 0. The 3
independent-oracle fixtures stay literal by design. Behavior-preserving (`0.70` unchanged; `round(100*0.70)==70`).

**Validation guards:** the guard evaluates the constant line (model.R reads data, can't be sourced whole) and
checks value + wiring + that it did not leak into `workforce_constants.R`.

**Tests added (`test-ssot-uro-fte-default.R`, 19/0):** well-formed proportion; **behavior-preserving** (percent
form == 70); **adversarial** (model + app reference the SSOT, no bare `uro_fte=0.70`/`=70` preset);
**intentional-difference** (range `c(55,85)` + `±0.15` preserved; app-local, not in shared constants — same value
as `WORKFORCE_CONVERSION_FLOOR` but separate home); **consistency** (both adequacy guard tests key off the constant).

**Initial failures:** none. **Final: uro-fte 19/0; all 42 SSOT guards 657/0; adequacy own tests
(consistency 73/0, model 293/0) — no regression; all touched files parse.**

**Remaining risks:** none for this value. Sibling note: `test-guards-app.R:37`'s positional `0.77` (obgyn_share)
is a rounded literal of `OB_BASE_SHARE` (0.770) — a separate small test-fixture item, flagged as follow-on.

**Recommended next candidate:** the `test-guards-app.R:37` / fixture `0.77` obgyn_share literal vs the derived
`OB_BASE_SHARE` (0.770) — a rounded-copy test-fixture gap; OR the adequacy app's `end_year=2050L` default vs
`DEMAND_HORIZON_END_YEAR` (iter24, self-contained-app parity like BANDS). Both modest, app-local. Ledger-check first.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 42-45 files. Iterations 40-41 already
landed in `a72726c`.

---

## Iteration 46 — adequacy app projection horizon END year (`2050`) → `PROJECTION_END_YEAR`

**Candidate:** the adequacy app's projection horizon end year `2050` (the default + maximum of the `end_year`
slider).

**Why higher-risk than alternatives (vs the `0.77` obgyn fixture):** `2050` is the horizon over which the app's
entire supply-vs-demand adequacy trajectory is computed, and it is the app-local copy of the **published**
manuscript horizon end (`DEMAND_HORIZON_END_YEAR`, iter24). It was duplicated 4× within the app (DEFAULTS end,
slider MAX, slider DEFAULT, reset handler); a drift from the manuscript horizon (or between these copies) would
make the app project a different window than the paper. The `0.77` alternative is a rounded literal in
independent-oracle test fixtures (iter15 precedent → leave literal), lower value.

**Audit / provenance:** `shiny_urps_adequacy/model.R:50` (DEFAULTS `end_year=2050L`); `app.R:168`
(`sliderInput("end_year", …, 2035, 2050, 2050, …)` — min/max/default); `app.R:225` (reset `value=2050`). Prose
"2025-2050" comments (app.R:5,81) and the fingerprint fixtures (`end_year=2050` in test-guards-consistency:18-19)
are narrative / independent-oracle literals, left as-is.

**Discrepancy adjudication:** all four live copies are the same horizon end → one SSOT, and it must equal the
manuscript `DEMAND_HORIZON_END_YEAR` (parity-guarded). **NOT collapsed:** the slider MINIMUM `2035` (shortest
selectable horizon) and `BASE_YEAR 2025` (projection START, the app-local copy of `PROJECTION_BASELINE_YEAR`) are
distinct values, left literal.

**Canonical:** `shiny_urps_adequacy/model.R::PROJECTION_END_YEAR <- 2050L` (constant; app-local, next to
`BASE_YEAR`). App-local + parity-guarded because the app deploys standalone (cannot source R/), the same
mechanism used for `URO_FTE_DEFAULT` (iter45) and the `BANDS` snapshot (iter37).

**Files changed:** `model.R` (new constant + DEFAULTS); `app.R` (slider max/default + reset handler); new
`tests/testthat/test-ssot-adequacy-end-year.R`.

**Hardcoded copies removed:** 4 live copies → 0. Behavior-preserving (`2050` unchanged; `BASE_YEAR:end_year`
loop bound identical, 26 projected years).

**Validation guards:** the guard evaluates the constant line (model.R can't be sourced whole) and adds a
**cross-lineage parity** check that `PROJECTION_END_YEAR == DEMAND_HORIZON_END_YEAR` (sources
`R/demand_denominator.R`), so the app horizon can't silently drift from the manuscript.

**Tests added (`test-ssot-adequacy-end-year.R`, 15/0):** well-formed (end after start); **cross-lineage parity**
(== manuscript horizon end); **adversarial** (model + app reference the SSOT, no bare `2050` horizon literal);
**intentional-difference** (slider min `2035` + `BASE_YEAR 2025` distinct, left literal); **behavior-preserving**
(2025..2050 span + 26-year count unchanged).

**Initial failures:** none. **Final: adequacy-end-year 15/0; all 43 SSOT guards 672/0; adequacy own tests
(consistency 73/0, model 293/0) — no regression; both touched files parse.**

**Remaining risks:** none for this value. `BASE_YEAR 2025` in the adequacy app is a parallel app-local copy of
`PROJECTION_BASELINE_YEAR` (iter23) that could get the same parity treatment — a candidate below.

**Recommended next candidate:** the adequacy app's `BASE_YEAR <- 2025L` — the app-local projection START, a
copy of `PROJECTION_BASELINE_YEAR` (iter23); give it the same app-local-constant + parity-guard treatment as
`PROJECTION_END_YEAR`, or verify it's already covered. Ledger-check first.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 42-46 files. Iterations 40-41 already
landed in `a72726c`.

---

## Iteration 47 — adequacy app per-100k rate base (`1e5`) → app-local `RATE_PER_100K`

**Candidate:** the per-100,000-population rate base `1e5` in the adequacy app (the "urogynecologists per 100k
women 65+" headline metric).

**Why higher-risk than alternatives (vs `BASE_YEAR` parity-only):** `BASE_YEAR` is already single-sourced within
the app (defined once, referenced by name) — only a parity gap. The `1e5` was a genuine **within-app
duplication** (hardcoded twice, `per100k_2025` + `per100k_end`), and it is the same rate base iter25 canonicalized
as `R/units.R::RATE_PER_100K` — which the active scripts already reference but the self-contained app never wired.
So this is both a real refactor AND a coverage-completion of iter25 for the standalone app.

**Audit / provenance:** `shiny_urps_adequacy/model.R:172` (`per100k_2025 = 1e5 * headcount / w65`) + `:173`
(`per100k_end = 1e5 * …`). Only two `1e5` in the whole app; no `guess_max=1e5` (verified).

**Discrepancy adjudication:** both are the same rate base → one SSOT, and it must equal `R/units.R::RATE_PER_100K`
(parity-guarded). **NOT collapsed (iter25):** the identical literal `1e5` used as a read_csv/fread `guess_max`
row hint is a data-loading parameter, not a rate base — the app has none, so nothing to disambiguate here.

**Canonical:** `shiny_urps_adequacy/model.R::RATE_PER_100K <- 1e5` (constant; app-local, same NAME as the R/units.R
SSOT to make the parity relationship explicit — no collision since the app never sources R/). App-local +
parity-guarded because the app deploys standalone (cannot source R/), the mechanism used for
`URO_FTE_DEFAULT`/`PROJECTION_END_YEAR` (iters 45-46).

**Files changed:** `shiny_urps_adequacy/model.R` (new constant + both consumers); new
`tests/testthat/test-ssot-adequacy-rate-per-100k.R`.

**Hardcoded copies removed:** 2 live copies → 0. Behavior-preserving (`1e5` unchanged).

**Validation guards:** the guard evaluates the constant line (model.R can't be sourced whole) and adds a
**cross-lineage parity** check that the app `RATE_PER_100K == R/units.R::RATE_PER_100K`.

**Tests added (`test-ssot-adequacy-rate-per-100k.R`, 12/0):** well-formed (1e5); **cross-lineage parity** (==
R/units.R); **adversarial** (both consumers reference the constant, no bare `1e5 *`); **intentional-difference**
(no `guess_max=` argument, no other live `1e5`); **behavior-preserving** (per-100k computation identical).

**Initial failures:** 1 — the intentional-difference test `expect_false(any(grepl("guess_max", src)))` matched my
own **documentation comment** (which mentions "guess_max row hint"), not any code. **Classification:
test-authoring bug (over-broad literal match), not a refactor issue.** **Fix:** tightened the pattern to
`guess_max\\s*=` (matches the argument usage, not the prose). Re-ran green.

**Final results:** adequacy-rate 12/0; all 44 SSOT guards 684/0; adequacy own tests (consistency 73/0, model
293/0) — no regression; model.R parses; no bare `1e5 *` remains.

**Remaining risks:** none for this value. The adequacy app still holds an app-local `BASE_YEAR 2025` (already
single-sourced, but un-parity-guarded vs `PROJECTION_BASELINE_YEAR`) — a guard-only follow-on.

**Recommended next candidate:** a parity-only guard for the adequacy `BASE_YEAR <- 2025L` vs
`PROJECTION_BASELINE_YEAR` (iter23) — BASE_YEAR is already single-sourced in the app, so this is a guard-only
drift check completing the app's year-constant parity set (start + end). Or scan a fresh non-app area. Ledger-check
first.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 42-47 files. Iterations 40-41 already
landed in `a72726c`.

---

## Iteration 48 — adequacy app reference entrant inflow (`entrants=64`) → derived `ENTRANTS_DEFAULT`

**Candidate:** the adequacy app's reference annual entrant inflow `64` (the `entrants/yr` slider default).

**Why higher-risk than alternatives (vs `BASE_YEAR` parity-only):** it is duplicated 3× AND, unlike a fixed
parity constant, it is **derivable** — `64 = mean(GRAD_URPS)`, and the app already sources `GRAD_URPS` (its
`urps_model_data.R` snapshot). Hardcoding `64` means a change to the ACGME graduate counts would update the
scripts' `ENTRANTS <- mean(GRAD_URPS)` (iter7/33) and the engine `WC_ENTRANTS[["URPS"]]` but silently leave the
app's reference stale. Deriving it closes that gap with a true SSOT link (not just a parity check).

**Audit / provenance:** `shiny_urps_adequacy/model.R:57` (DEFAULTS `entrants=64L`); `app.R:55` (Reference preset
`entrants=64`); `app.R:223` (reset handler `value=64`). `GRAD_URPS` is in scope (snapshot sourced at model.R:22);
`mean(GRAD_URPS)=64`.

**Discrepancy adjudication:** the three reference copies are the same value → derive once. **NOT collapsed:** the
`Lower entrants=48` / `Higher entrants=80` scenario presets (and the `Stress test` `entrants=48`) are intentional
scenario values, left literal; the slider range and the independent-oracle test fixtures (`entrants=64`) stay
literal (iter15 precedent).

**Canonical:** `shiny_urps_adequacy/model.R::ENTRANTS_DEFAULT <- as.integer(round(mean(GRAD_URPS)))` — a **derived
value** (function of the sourced graduate counts), not a constant, so it tracks `GRAD_URPS`. Fail-loud
`stopifnot` (positive integer, plausible range). No `==64` pin — pinning would defeat the derivation.

**Files changed:** `shiny_urps_adequacy/model.R` (derived constant + DEFAULTS); `app.R` (Reference preset + reset
handler); new `tests/testthat/test-ssot-adequacy-entrants.R`.

**Hardcoded copies removed:** 3 live copies → 0 (now derived). Behavior-preserving (`round(mean(GRAD_URPS))==64`).

**Validation guards:** `stopifnot`; the guard sources the snapshot for `GRAD_URPS`, evaluates the derived line in
that scope, and cross-checks it equals the engine `WC_ENTRANTS[["URPS"]]`.

**Tests added (`test-ssot-adequacy-entrants.R`, 17/0):** derives to 64 (== `round(mean(GRAD_URPS))`); **semantic**
(derived from `GRAD_URPS`, not a bare 64 — a different cohort derives to a different value); **cross-lineage
consistency** (== engine URPS entrant mean); **adversarial** (model + app reference `ENTRANTS_DEFAULT`, no bare
`entrants=64`); **intentional-difference** (`entrants=48`/`80` scenario presets preserved).

**Initial failures:** 1 — the semantic test used `mean(c(60,66,63,66)) = 63.75`, which **rounds back to 64**, so
the "different vector differs from 64" assertion failed. **Classification: test-authoring bug (bad example
vector), not a refactor issue.** **Fix:** used `c(60,60,60,60) -> 60` as the clearly-different cohort. Re-ran green.

**Final results:** entrants 17/0; all 45 SSOT guards 701/0; adequacy own tests (consistency 73/0, model 293/0) —
no regression; model.R + app.R parse; no bare `entrants=64` remains outside the oracle fixtures.

**Remaining risks:** none for this value. The adequacy app still has app-local `entry_age=34` (== `WORKFORCE_ENTRY_AGE`,
iter26/34) and `BASE_YEAR=2025` (== `PROJECTION_BASELINE_YEAR`) that remain parity-eligible follow-ons.

**Recommended next candidate:** the adequacy app's `entry_age=34L` in DEFAULTS (== `WORKFORCE_ENTRY_AGE`, iter26/34)
— a self-contained-app parity/constant follow-on like this one; OR `BASE_YEAR` parity. Both app-local. Given 7
iterations (42-48) are now accumulated uncommitted, a **land** is recommended before continuing. Ledger-check first.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 42-48 files. Iterations 40-41 already
landed in `a72726c`. **NOTE: 7 iterations (42-48) accumulated uncommitted — recommend landing.**

---

## Iteration 49 — adequacy app physician entry-age default (`entry_age=34`) → `ENTRY_AGE_DEFAULT`

**Candidate:** the adequacy app's physician entry-age default `34` (the `entry_age` slider default).

**Why higher-risk than alternatives:** the entry age is where each annual entrant cohort is injected into the
age-structured projection — it shapes the whole supply trajectory. It was duplicated 3× in the app (DEFAULTS,
slider default, reset handler) and is an app-local copy of the study entry age `WORKFORCE_ENTRY_AGE` (iter26/34,
unified across the engine + demand scripts); a drift between the app and the study value would make the app
project a different entry cohort than the manuscript.

**Audit / provenance:** `shiny_urps_adequacy/model.R:64` (DEFAULTS `entry_age=34L`); `app.R:167`
(`sliderInput("entry_age", …, 30, 45, 34, …)` — default); `app.R:224` (reset `value=34`). Not derivable (fixed
study-design value), and the app is self-contained (cannot source R/).

**Discrepancy adjudication:** the three copies are the same value → one SSOT, parity-guarded against
`WORKFORCE_ENTRY_AGE`. **NOT collapsed:** the slider RANGE `30, 45` (selectable entry-age bounds) is a distinct
scenario knob, left literal; the independent-oracle test fixtures (`entry_age=34`) stay literal (iter15).

**Canonical:** `shiny_urps_adequacy/model.R::ENTRY_AGE_DEFAULT <- 34L` (constant; app-local, next to
`ENTRANTS_DEFAULT`; fail-loud `stopifnot` in [30,45]). App-local + parity-guarded, the mechanism used for
`URO_FTE_DEFAULT`/`PROJECTION_END_YEAR`/`RATE_PER_100K` (iters 45-47).

**Files changed:** `shiny_urps_adequacy/model.R` (new constant + DEFAULTS); `app.R` (slider default + reset
handler); new `tests/testthat/test-ssot-adequacy-entry-age.R`.

**Hardcoded copies removed:** 3 live copies → 0. Behavior-preserving (`34` unchanged, integer-typed).

**Validation guards:** `stopifnot`; the guard adds a **cross-lineage parity** check that
`ENTRY_AGE_DEFAULT == WORKFORCE_ENTRY_AGE`.

**Tests added (`test-ssot-adequacy-entry-age.R`, 15/0):** well-formed (in [30,45]); **cross-lineage parity**
(== `WORKFORCE_ENTRY_AGE`); **adversarial** (model + app reference the SSOT, no bare `entry_age=34`);
**intentional-difference** (slider range `30, 45` literal, default strictly inside); **behavior-preserving**
(34, integer).

**Initial failures:** none. **Final: entry-age 15/0; all 46 SSOT guards 716/0; adequacy own tests (consistency
73/0, model 293/0) — no regression; both touched files parse.**

**Remaining risks:** none for this value. The adequacy app's DEFAULTS/scenario parameters are now largely
single-sourced (uro_fte, entrants, entry_age, end_year, rate, bands, grad); the remaining raw defaults
(`retire=65`, `fte_new=0.90`, `haz_mult=1.0`, `demand_mult=1.0`) are app-specific scenario knobs with no external
canonical, and `BASE_YEAR 2025` is already single-sourced (parity-only follow-on).

**Recommended next candidate:** given the adequacy app is now heavily single-sourced and 8 iterations (42-49) are
accumulated uncommitted, **LAND first**, then either the `BASE_YEAR` parity guard (guard-only) or pivot to a fresh
non-app area (e.g. an un-audited duplicated value in `manuscript/R/` figure builders). Ledger-check first.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 42-49 files. Iterations 40-41 already
landed in `a72726c`. **NOTE: 8 iterations (42-49) accumulated uncommitted — landing strongly recommended.**

---

## Iteration 50 — manuscript Figure 1 baseline year (`base_year <- 2025L`) → `PROJECTION_BASELINE_YEAR`

**Candidate:** the projection baseline year `2025` in the manuscript Figure 1 trajectory builder
(`manuscript/R/create_figure1_workforce_projection.R:44`). Fresh non-app area (pivoted off the adequacy app).

**Why higher-risk than alternatives:** it is the x-axis start of the **published** workforce-projection figure,
and it is a bare copy of the shared `PROJECTION_BASELINE_YEAR` (iter23) — while the SAME function already wires
`horizon <- WORKFORCE_PROJECTION_HORIZON_YEARS` (iter1). So one half of the figure's `year = base_year + 0:horizon`
axis tracked the SSOT and the other half was hardcoded; a baseline change would move the horizon end but leave the
figure's start at 2025, silently mis-labelling the axis.

**Audit / provenance:** `create_figure1_workforce_projection.R:43` (`horizon <- WORKFORCE_PROJECTION_HORIZON_YEARS`,
already wired) + `:44` (`base_year <- 2025L`, the bare copy), used at `:56` (`year = base_year + 0:horizon`). The
`baseline_2025` COLUMN identifiers (`:57`, create_workforce_table, the contract) are schema names, left literal.

**Discrepancy adjudication:** `base_year` is the same 2025 as `PROJECTION_BASELINE_YEAR` (verified: `2025 + 4 =
2029`, the figure endpoint) → one SSOT. **NOT collapsed:** the `baseline_2025` column-name identifiers keep the
year baked in (schema, cf. iter24's `_2050`).

**Canonical:** `R/workforce_constants.R::PROJECTION_BASELINE_YEAR` (iter23), reachable in this figure builder via
the contract it already sources (`workforce_data_contract.R` → `workforce_constants.R`), the identical path that
already delivers `WORKFORCE_PROJECTION_HORIZON_YEARS`. Constant (fixed study year), no new home needed.

**Files changed:** `manuscript/R/create_figure1_workforce_projection.R:44` (bare `2025L` → `PROJECTION_BASELINE_YEAR`);
new `tests/testthat/test-ssot-figure1-base-year.R`.

**Hardcoded copies removed:** 1 → 0. Behavior-preserving (`PROJECTION_BASELINE_YEAR == 2025L`; axis 2025-2029
unchanged).

**Validation guards:** the guard confirms reachability via the contract and checks the axis algebra + cross-lineage
consistency.

**Tests added (`test-ssot-figure1-base-year.R`, 9/0):** **adversarial** (references the SSOT, no bare `base_year <-
2025L`); reachability (`PROJECTION_BASELINE_YEAR == 2025` via the contract, shares the horizon env);
**behavior-preserving** (`base_year + 0:horizon == 2025:2029`, endpoint 2029); **cross-lineage consistency**
(== the demand-lineage `DEMAND_INDEX_BASE_YEAR`, iter22); **intentional-difference** (`baseline_2025` column names
stay literal, the base_year assignment carries no `2025` literal).

**Initial failures:** none. **Final: figure1-base-year 9/0; all 47 SSOT guards 725/0; file parses; no bare
`base_year <- 2025L` remains.**

**Remaining risks:** none for this value. The stale `create_workforce_table.R` tribble (dead/PI-gated,
`docs/FLAG_stale_workforce_table_hardcode.md`) still carries `baseline_2025` data literals — out of scope.

**Recommended next candidate:** other manuscript figure builders (`workforce_figures.R`,
`create_figure_scenario_projection.R`) for a bare baseline/horizon/ratio-axis literal that duplicates a canonical;
OR the `BASE_YEAR` adequacy parity guard. Ledger-check first.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 42-50 files. Iterations 40-41 already
landed in `a72726c`. **NOTE: 9 iterations (42-50) accumulated uncommitted — landing strongly recommended before
continuing.**

---

## Iteration 51 — adequacy app projection START `BASE_YEAR` parity guard (guard-only)

**Candidates surveyed + stopped:** the remaining manuscript figure builders (`create_figure_scenario_projection.R`,
`workforce_figures.R`) carry `2025/2029` only as prose axis labels + `projected_2029` schema column names — no
computed-literal duplication. The live hardcoded hex colors (`workforce_figures.R:11`) are single-use (no
duplication); the table cell colors are in the dead/PI-gated `create_workforce_table.R`. `palette_green_journal`
is a single-sourced function. **The clean, genuinely-duplicated, un-audited SSOT vein is largely exhausted after
50 iterations.**

**Candidate selected (guard-only drift protection):** the adequacy app's projection START `BASE_YEAR <- 2025L`.

**Why:** `BASE_YEAR` is already single-sourced within the app (defined once at `model.R:36`, referenced 9× by
name), so there is no refactor — but nothing tied it to the study baseline `PROJECTION_BASELINE_YEAR` (iter23),
so the self-contained-app copy could silently drift. This completes the app's projection-window parity set:
`BASE_YEAR` (start) + `PROJECTION_END_YEAR` (end, iter46). A guard-only iteration, like iter38 (band-hazard
inputs) and iter39 (GRAD_URPS gap).

**Audit / provenance:** `shiny_urps_adequacy/model.R:36` (`BASE_YEAR <- 2025L`, the sole definition). The only
other `2025` in non-comment code is the `"SSOT: 2025 index != 100"` error string (message, not a value) and the
`per100k_2025` / `women_per_efte_2025` output column identifiers (schema).

**Discrepancy adjudication:** none — `BASE_YEAR == PROJECTION_BASELINE_YEAR == 2025`. **NOT collapsed:** the
`_2025` column-name identifiers (schema) and the diagnostic string stay literal.

**Canonical:** unchanged — `R/workforce_constants.R::PROJECTION_BASELINE_YEAR` (iter23) is the study SSOT;
`BASE_YEAR` is the app-local copy, now parity-guarded (the app cannot source R/). Added a provenance comment
only; no code behavior change.

**Files changed:** `shiny_urps_adequacy/model.R` (comment on `BASE_YEAR`); new
`tests/testthat/test-ssot-adequacy-base-year.R`. **No copies removed** (already single-sourced) — the iteration
converts an unguarded app-local copy into a guarded one.

**Validation guards / tests added (`test-ssot-adequacy-base-year.R`, 11/0):** well-formed (2025, before the
horizon end); **cross-lineage parity** (`== PROJECTION_BASELINE_YEAR`); **single-source** (one definition, no
bare `2025` value in live code beyond it — schema columns + error string excluded); **intentional-difference**
(`_2025` column names stay literal); **behavior-preserving** (`BASE_YEAR:PROJECTION_END_YEAR == 2025:2050`, 26
years).

**Initial failures:** none. **Final: base-year 11/0; all 48 SSOT guards 736/0; adequacy own tests (consistency
73/0, model 293/0) — no regression; model.R parses.**

**Remaining risks:** none for this value. **Strategic note: after 50 substantive refactors, the clean
duplicated-value vein is exhausted.** Remaining literals are prose labels, schema identifiers, single-site plot
params, PI-gated numbers, or dead code — none are clean SSOT refactors, and forcing them risks the loop's
"avoid unrelated cleanup" guardrail.

**Recommended next candidate:** none clean remains for a mechanical refactor. Next best moves are strategic, not
loop-mechanical: (a) **LAND** the 10 accumulated iterations (42-51) first; (b) resolve a PI-gated item (stale
workforce table, FPMRS figure supply numbers) with PI input; or (c) tackle the URPS baseline reconciliation
(explicitly out of loop scope). A further loop iteration would likely produce only marginal guard-only or
schema-adjacent work.

**Status:** ✅ complete. Uncommitted (loop rule). Working tree = iterations 42-51 files. Iterations 40-41 already
landed in `a72726c`. **NOTE: 10 iterations (42-51) accumulated uncommitted — landing strongly recommended; clean
SSOT vein now exhausted.**

---

## Iteration 52 — geographic-access distance bands: investigated, STOPPED (no clean SSOT); vein confirmed exhausted

**Candidate investigated:** the urogyn geographic-access distance bands (`25` / `50` / `100` miles; the `>60`-mile
underserved-county cutoff) in `scripts/urps_module_d_geographic_access_2026-07-23.R` and
`scripts/urps_module_d_map_2026-07-23.R` — the last plausible cross-file duplication after the fresh
demand-module sweep.

**Why STOPPED (loop step 3 — authority unclear + intentional differences + display-coupled):**
- The two files use **different band schemes**: `geographic_access` reports `≤25 / ≤50 / ≤100 / >100` (a coarse
  summary table), while `map` uses finer bins `<25 / 25-50 / 50-100 / 100-150 / >150 mi (desert)` with a
  map-only 150-mi "desert" cutoff. They share `25/50/100` but embed them in **different structures for different
  outputs** — collapsing them would erase intentional per-output granularity.
- The shared values live inside **hand-written display-label strings** ("% women 65+ within 25 mi", "25-50 mi",
  "> 150 mi (desert)") tightly coupled to each file's bins; a constant cannot drive the labels without a larger
  string-templating refactor.
- The `>60`-mile underserved cutoff is single-site (`geographic_access:130`) — no duplication.
- `module_d` already single-sources what it can: `meters_to_miles`/`miles_to_meters` (iter18) and
  `RATE_PER_100K` (iter25).
- Authority for "the canonical access-band scheme" cannot be established (table vs map are legitimately
  different), so per the loop this candidate is stopped, not forced.

**Files changed:** none (ledger note only — records the distance-band investigation so it is not re-audited).

**Conclusion — the clean SSOT vein is exhausted (confirmed twice, iters 51-52).** After **50 substantive
single-source-of-truth refactors** (iters 1-50) plus guard-completions (iters 38/39/51), every remaining
hardcoded literal in the active codebase falls into a non-refactorable class:
- **prose / narrative labels** (figure titles "2025-2029", "Change from 2025 baseline");
- **schema identifiers** (`baseline_2025`, `_2050`, `medicare_part_b_by_service_2024`, `per100k_2025` column and
  table names);
- **single-site plot/model params** (spline `df=4`, age bounds `30/80`, axis padding `1.12`, line colors);
- **per-output display granularities** (the distance bands above);
- **PI-gated numbers** (the stale workforce-table tribble + FPMRS-figure supply numbers, both baseline-entangled,
  `docs/FLAG_stale_workforce_table_hardcode.md`);
- **deliberately-literal legacy/test-oracle fixtures** (iter15's `code/` scoping; the adequacy fingerprint
  fixtures);
- **dead code** (`create_workforce_table.R`).
Forcing any of these would violate the loop's own "avoid unrelated cleanup / broad architectural refactoring"
and "never collapse intentional differences" guardrails.

**Recommended next action (NOT a further loop iteration):**
1. **LAND** the 10 accumulated iterations (42-51) — strongly recommended before anything else.
2. Then **pause the mechanical SSOT loop** — the clean vein is worked out. Genuinely valuable remaining work is
   PI-gated (stale table / FPMRS figure) or the out-of-scope URPS baseline reconciliation, none of which is a
   mechanical single-value refactor.

**Status:** ✅ documented stop (no refactor). Working tree unchanged except this ledger note (iterations 42-51 +
this entry). Iterations 40-41 already landed in `a72726c`. **NOTE: landing recommended; loop vein exhausted.**

### Iteration 53 addendum — config-vs-code class swept, no clean candidate (exhaustion re-confirmed)

Swept the last un-checked SSOT class — **config YAML values duplicated in code**:
- `config/fellowship_assumptions.yml` (default `FPMRS:60 / GO:50 / MIG:45`) is **config-single-sourced**: read by
  the legacy `code/` pipeline (`code/01,04,06`); no `.R` script re-hardcodes it. Its only duplicate is stale
  legacy manuscript prose (`manuscript/Surgical_workforce_cliff_REVISED.txt`, a pre-reframe `.txt` that also
  carries the dead fixed retirement rates `4.4/5.2/3.4%`) — not code-refactorable, same PI-gated/legacy class as
  the stale workforce table. It is a **different lineage** from the current-scripts `WC_GRAD` (iter3;
  70/73/78/79 · 61/66/63/66 · 47/50/45/47) — legacy config-driven vs current pipeline, intentionally separate.
- `config/expected_workforce_counts.yml`: regression test-threshold RANGES (intentionally approximate bounds) +
  `test_years` (already parity-guarded, iters 42/43).
No refactor. **Every SSOT class is now swept; the clean vein is exhausted.** Firm recommendation: LAND iters
42-51 and pause the mechanical loop.
