# Incorporating `simulation` (DPMM) Supply & Demand Numbers into `cliff`

**Status:** Planning / review — no pipeline code changed by this document.
**Scope:** How the supply and demand numbers produced in the
[`simulation`](https://github.com/mufflyt/simulation) microsimulation repo (DPMM)
should feed the [`cliff`](https://github.com/mufflyt/cliff) workforce-cliff analysis.
**Companion:** `urps_microsimulation_improvement_plan_20260730` (the URPS microsimulation
improvement plan), whose §6, §10, §8, and §16 define the target data contract used below.

---

## TL;DR — the direction is not what it looks like

The intuitive reading of "incorporate the simulation's supply/demand numbers into cliff"
is *copy the numbers down from `simulation` into `cliff`*. **That is backwards for supply
and only partially right for demand.** As the code stands today:

- **`cliff`'s supply model is materially more advanced than `simulation`'s.** `cliff` already
  has confidence intervals, an age-structured departure-hazard engine, an age–productivity
  ("effective supply") conversion, and an ABOG/ABU pathway split. `simulation`'s supply is a
  flat deterministic headcount (`1,169 + 55 in − 55 out` → flat 1,169), national-only, no CIs,
  no pathway, no age structure. **Do not overwrite cliff's supply with simulation's.**
- **`simulation`'s demand *engine* is the genuinely additive piece — but not its current
  numbers.** The SWAN-based incontinence microsimulation is exactly the dynamic,
  patient-level prevalence model that cliff's demand denominators currently *lack* (cliff uses
  published-anchor extrapolations: Wu 2009/2011, Kirby 2013, Nygaard 2008). Once calibrated, it
  should **back cliff's demand-denominator hierarchy** (improvement-plan §10, tiers 3–5).
  But its present output ("8% → 99% prevalence over 50 years") is uncalibrated and must not be
  ingested as-is.

So the productive flow is: **`simulation` demand engine → cliff demand denominators**, mediated
by a **versioned contract** (improvement-plan §16), *after* three prerequisites are cleared.
Supply flows the other way conceptually: `simulation` should adopt the structure cliff already
has (this is literally what improvement-plan §6 asks it to build).

---

## 1. What each repo actually computes today

### 1a. `simulation` (DPMM) — supply

| Property | Value | Source |
|---|---|---|
| Model form | Deterministic linear headcount stock-flow: `supply[y] = supply[y-1] + fellows − retirements` | `R/supply_of_the_urogyn_workforce.R:1614-1621`; `R/workforce.R:37-51` |
| Baseline | **1,169** FPMRS providers (base year **2022**) | `supply_...R:108,1253`; `workforce.R:27` |
| Inflow / outflow | **55** fellows/yr, **55** retirements/yr → **flat 1,169** under status quo | `workforce.R:28-29` |
| Scenarios | Status quo (0), Enhanced training (+6/yr), Delayed retire (+15/yr), Early retire (−15/yr) | `supply_...R:1558-1575` |
| "FTE" | **Label only** — no productivity/clinical-FTE conversion; provider = 1 | `workforce.R:45-51` (multiply-then-divide no-op) |
| Geography | **None** (national only) | `README.md:6` (flagged TODO) |
| ABOG/ABU split | **None** | grep: no pathway variable anywhere |
| Output | In-memory list (`workforce_projections`: `year_value, workforce_fte_supply, scenario`); CSVs only in a driver block | `supply_...R:1401-1407, 2020-2025` |

### 1b. `simulation` (DPMM) — demand (two disconnected engines)

**Engine 1 — epidemiological prevalence (the DPMM microsimulation, files `03`/`04`/`05`).**
Patient-level Markov onset/progression/mortality over urinary-incontinence state, SWAN-fitted.

- Scales to national counts via `us_women_40plus_2025 = 85,000,000` → "millions affected".
- **Stops at prevalence.** No conversion to visits, procedures, or provider FTE.
- Current headline result **8% (2025) → ~99% (2075)** is uncalibrated (transition probs are
  placeholders per `README.md:5`; runs used `n_simulations` = 2–5). **Illustrative, not validated.**
- Refs: `R/05-dppm_50_year_national_incontinence.R:498-504, 803, 822`; `R/04-...R`.

**Engine 2 — provider-FTE demand (`workforce.R`).** Population × utilization ÷ productivity.

- `required_fte = population × 1.5 visits ÷ 1,728 hrs` → **~1,118 FTE** (65+ OB/GYN UI) and
  **~2,254 FTE** (all office UI, women 18+). `workforce.R:336-340, 365-367`.
- **Not wired to Engine 1** — population-driven, not prevalence-driven. `README.md:7` flags this.
- A third calc in `supply_...R:1829-1841` yields **~48,700 FTE** demand (raw visits/hour) — ~20×
  larger. **`simulation` is internally inconsistent on demand scale by an order of magnitude.**

### 1c. `cliff` — supply (multiple lineages, ~2050 horizon)

| Lineage | Baseline (2025) | Engine | Where |
|---|---|---|---|
| A. Consolidated hazard pipeline | ~~**1,295**~~ **retired** | Reads an archived 2025-09-28 Monte-Carlo table. **Cannot run: that archive is absent from the repository.** It also wrote the SSOT, and was the only non-canonical writer not locked; it is now locked behind `WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE=1` like the other two | `code/01_consolidate_workforce_data.R:43-48,146-148` |
| B. Age-structured supply | **1,339** | `length(URPS_AGES)` + age-band Beta-posterior hazards + entrant inflow (`GRAD_URPS` mean 64/yr) | `shiny_urps_scenarios/urps_model_data.R:7,13,19-20`; `scripts/urps_supply_demand_national_2026-07-23.R:40-64` |
| C. mufflyaccess contract | **1,306** (2023 active, v3.0.0) / 1,027 ABOG-only / **1,339** (2025 roster snapshot); 1,332/1,329 are RETIRED v2.1.0 cells | `mufflyaccess::urps_count()` — the intended canonical server | `R/urps_baseline.R:21-29`; `tests/testthat/test-mufflyaccess-contract.R` |
| — Figure literals | 1,700; 1,283/1,301; 1,196 | Standalone hardcoded series | `scripts/fig_urogyn_supply_demand.R:13-15`; `scripts/fig_fpmrs_supply_line.R:24-44` |

- **Effective (productivity-adjusted) supply** exists: Module A weights each physician-year by an
  age–productivity curve, normalized so 2025 effective == headcount. `scripts/urps_module_a_effective_supply_2026-07-23.R`.
- **With CIs** (2.5/97.5 MC quantiles) throughout the national table.

### 1d. `cliff` — demand (four constructs, deliberately un-blended)

- **Demographic driver:** Census 2023 NPP female population → `women_65plus`, `women_40plus`,
  `women_with_pfd` (Nygaard 2008 age-specific PFD prevalence). `R/demand_denominator.R`, `R/pfd_prevalence.R`.
- **Module B/C — procedure-based required FTE:** 2024 Medicare volume × urogyn-attributable share
  ÷ work-per-FTE → **required_fte_mid 963 (2025)**, adequacy 1.39. `scripts/urps_demand_module_bc_2026-07-23.R`.
- **Demand-denominator sensitivity (D1/D2/D3):** D1 prevalent PFD (Wu 2009), D2 new consultations
  (Kirby 2013), D3 SUI+POP surgery (Wu 2011); all indexed 2025=100. `scripts/urps_demand_denominators_sensitivity.R`.
- These are **published-anchor extrapolations, not a dynamic patient-level model** — the exact gap
  `simulation`'s Engine 1 is built to fill.

### 1e. Side-by-side

| | `simulation` (DPMM) | `cliff` |
|---|---|---|
| Supply baseline | 1,169 (2022) | **1,306** (2023 active, adopted); 1,295 legacy-frozen, 1,339 roster snapshot |
| Supply CIs | No | Yes |
| Age structure / hazards | No | Yes (Module A + Beta hazards) |
| Productivity-adjusted FTE | No (label only) | Yes (Module A "effective") |
| ABOG/ABU split | No | Yes |
| Demand: dynamic prevalence | **Yes (SWAN microsim)** | No (published anchors) |
| Demand → provider FTE | Disconnected / inconsistent | Yes (Module B/C, Medicare-anchored) |
| Geography / travel-time | No | Partial (Module D access map) |
| Horizon | 2022–2100 | 2025–2050 |

---

## 2. Three blockers before *any* number can be incorporated

1. **Baseline reconciliation.** ✅ **Resolved on the cliff side (2026-08-14).** The agreed
   cell is **1,306** = 2023 board-certified active, national, both-pathway (ABOG 1,027 + ABU
   net-new 279), defined by the isochrones v3.0.0 snapshot's `active_2023` gate and served by
   `mufflyaccess::urps_count()`. Neither candidate in the old 1,295-vs-1,339 clash won: 1,295
   is retained only as the frozen legacy SGS projection cohort, and 1,339 is the 2025 roster
   snapshot, a different measure. `tests/testthat/test-no-unqualified-urps-baseline.R` fails on
   any unqualified use of either in production code. **Still open:** `simulation`'s 1,169@2022
   must be roll-forwarded and pathway-decomposed to be comparable.
   `simulation`'s 1,169@2022 must be roll-forwarded and pathway-decomposed to even be comparable.

2. **`simulation`'s demand engine must be (a) calibrated and (b) wired to FTE.** The prevalence
   engine is uncalibrated (§1b) and never connects to visits/procedures/FTE. Until Engine 1 →
   Engine 2 is a single pipeline with credible transition probabilities, its numbers cannot back
   a cliff denominator.

3. **`simulation`'s supply is not additive to cliff.** Feeding a flat, CI-less, national,
   pathway-agnostic 1,169 into cliff would *degrade* cliff. Supply integration means `simulation`
   **adopting cliff's structure** (improvement-plan §6's four measures), not exporting its own.

---

## 3. The target contract (improvement-plan §16, §6, §10)

Per §16: *"Downstream repositories such as cliff, twostep, and isochrones should consume the same
versioned outputs rather than independently rebuilding the assumptions."* The meeting point already
exists in cliff: **`mufflyaccess`** ("isochrones builds the roster, mufflyaccess serves the number,
cliff models what happens next" — `R/urps_baseline.R:6-7`).

**Supply contract — the four measures (§6), served per year × geography × pathway:**

| Measure | Definition | cliff consumer |
|---|---|---|
| A. Nominal headcount | active provider = 1 | `mufflyaccess::urps_count(measure="roster_snapshot")`, Lineage A/B baseline |
| B. Professional FTE | age/sex professional hours ÷ 40 | Module A input |
| C. URPS clinical workforce equivalent | B × clinical-time × URPS-time fractions | Module A "effective" |
| D. Surgical URPS capacity | C × surgical-participation weight | Module B/C surgical demand match |

**Demand contract — the denominator hierarchy (§10), served indexed + absolute:**

| Tier | Denominator | Today in cliff | `simulation` role |
|---|---|---|---|
| 1 | Adult women | Census NPP | (shared input) |
| 2 | Women 65+ | Census NPP | (shared input) |
| 3 | Prevalent PFD cases | Nygaard/Wu **static** | **DPMM Engine 1 (dynamic)** ← primary win |
| 4 | Symptomatic disease | not modeled | **DPMM severity (Sandvik) output** |
| 5 | Care-seeking cases | Kirby extrapolation (D2) | **DPMM + care-seeking layer** |
| 6 | Procedural/surgical demand | Medicare Module B/C, Wu (D3) | keep cliff's; validate vs DPMM |

Every served cell carries the §16 provenance envelope: parameter/estimate/distribution, source,
population, years, transformation, uncertainty, **model version**, and a frozen manifest
(roster hash, parameter-table hash, geography/population vintage, seed, code commit, scenario).

---

## 4. Recommended incorporation — staged

### Stage 0 — Reconcile the baseline (blocker #1)
- Make the PI decision on the canonical 2025 baseline cell; document in
  `dev/archive/URPS_CONTAINMENT_AND_BASELINE_NOTES.md` (archived).
- Roll `simulation`'s 1,169@2022 forward and split by ABOG/ABU so it is comparable; record the
  delta against cliff's chosen baseline as a reconciliation line, not a silent overwrite.

### Stage 1 — Establish the versioned contract (no numbers move yet)
- Freeze the schemas in §3 as the `mufflyaccess::urps_count()` supply cells and a new
  `mufflyaccess::urps_demand()` (or CSV) demand-hierarchy contract.
- `simulation` emits **versioned artifacts** to that contract (add a `save_dpmm_outputs()` target
  that writes tidy, versioned CSV/parquet with the provenance envelope).
- cliff consumes via the **already-blessed seams**: `mufflyaccess::urps_count()` (`R/urps_baseline.R`)
  for baselines, and `config/cliff_paths.yml` + `wc_path()` for file-based artifacts. **No consumer
  code changes** — cliff already reads producer CSVs by path.

### Stage 2 — First real number to move: demand tier 3–4 (the additive win)
- Calibrate DPMM Engine 1 (blocker #2); wire Engine 1 → Engine 2 so prevalence drives cases.
- Publish a **dynamic prevalent-PFD + symptomatic trajectory** as demand tiers 3–4.
- In cliff, swap D1 (currently static Nygaard/Wu) to read the DPMM trajectory **behind a feature
  flag**, and add a **concordance panel**: DPMM-dynamic vs published-anchor (D1/D2/D3) side by side.
  This is the highest-value, lowest-risk integration — it strengthens exactly the weakest part of
  cliff's demand story while keeping the published anchors as a validation backstop.

> **Wired (2026-08-02): HDMM life-course demand as a tier-6 comparison series.**
> `scripts/urps_demand_denominators_sensitivity.R` now also consumes the
> reproductive **life-course (HDMM)** contract behind `CLIFF_USE_HDMM_DEMAND=1`,
> using the same tier/model-agnostic ingestion helpers in `R/dpmm_contract.R`. It
> reads `tier6_procedural` (the closest analogue to the URPS surgical workforce),
> rebases to 2025 = 100, and adds `coverage_vs_hdmm` plus a `prev_vs_hdmm`
> concordance entry. Like the DPMM series it is **comparison-only** (the HDMM
> coefficient tables are placeholders; its cohort exposure marginals are cited)
> and is gated on `calibration_status`, so it never replaces the published anchors
> or the robustness verdict. Config path `hdmm_demand_contract` already exists in
> `config/cliff_paths.yml`; tests in `tests/testthat/test-dpmm-contract.R`.

> **Wired (2026-08-03): literature POP transitions with per-tier provenance.**
> The `simulation` DMDM now models prolapse as graded and regressing (R/33,
> `dmdm_transitions_with_pop_literature()`, from MOAD/WHI/SWEPOP). Passing those
> transitions to `export_dmdm_demand_contract(transitions = )` stamps a
> `tier_calibration_status` column, so the contract carries provenance **per tier**:
> `dmdm_pop` = `derived_by_analogy` while `dmdm_ui`/`dmdm_ai` stay placeholders and
> `tier3_prevalent_pfd` takes the weakest input status. cliff's ingestion
> (`R/dpmm_contract.R`) gained `read_dpmm_demand_contract()$tier_status` and
> `dpmm_tier_status(ct, tier)` to read a tier's provenance (falling back to the
> object-level status for older contracts). Under `CLIFF_USE_DMDM_DEMAND=1`,
> `scripts/urps_demand_denominators_sensitivity.R` now also surfaces the
> POP-specific `dmdm_pop` series (`coverage_vs_dmdm_pop`, `prev_vs_dmdm_pop`) with
> its `derived_by_analogy` label — still comparison-only, still excluded from the
> robustness verdict. Tests extended in `tests/testthat/test-dpmm-contract.R`.

### Stage 3 — Supply structure flows *up*, not down
- Port cliff's age-structure + hazards + pathway + age–productivity into `simulation` (this *is*
  improvement-plan §6). `simulation` then produces the four supply measures per year/geo/pathway.
- cliff continues to own supply projection but now reads the four measures from the contract
  instead of the hardcoded `URPS_AGES` / `GRAD_URPS` / `BAND_*` literals in
  `shiny_urps_scenarios/urps_model_data.R` (the main friction point) — then re-run
  `scripts/sync_urps_model_data.R` to propagate to the Shiny replicas.

### Stage 4 — Geography / isochrones (branch namesake, improvement-plan §8)
- Add `simulation`'s per-physician first-location + relocation modeling (§3, §7) and annual
  tract-level travel-time output (§8), sourced from the `isochrones` monorepo.
- cliff's Module D (`scripts/urps_module_d_*`) consumes the annual access surface, turning its
  one-shot access map into a projected access trajectory. This is the payoff the
  `demand-supply-isochrones` branch name points at.

---

## 5. Concrete first PRs (smallest useful units)

1. ~~**Baseline reconciliation note**~~ — ✅ **landed on the cliff side**: the chosen cell is
   1,306, its derivation is in `data/consort_cohort_flow.csv` (written by
   `scripts/algorithm_supplement_data.R`), and `PROVENANCE.md` carries the per-column lineage.
   What remains is reconciling `simulation`'s 1,169@2022 against it.
2. **`simulation` versioned demand export** — ✅ **landed** (`R/export_demand_contract.R`,
   `export_dpmm_demand_contract()`): writes tidy `dpmm_demand_contract_v<ver>.csv`
   (`model, model_version, calibration_status, denominator_tier, calendar_year, prevalence,
   prevalence_lo/hi, national_cases, denominator_index`) + a JSON provenance manifest; guarded
   call wired at the end of file 05.
3. **cliff demand contract + concordance** — ✅ **landed**: registered `dpmm_demand_contract` in
   `config/cliff_paths.yml`; `scripts/urps_demand_denominators_sensitivity.R` reads it as an
   alternative D1 behind `CLIFF_USE_DPMM_DEMAND`, adds a `coverage_vs_dpmm` concordance series and
   figure line. Off by default; published anchors remain the default and the uncalibrated DPMM
   series is excluded from the robustness verdict. *Follow-up:* fixture-based unit test for the
   ingestion path.
4. **cliff baseline via mufflyaccess** — apply the not-yet-wired drop-in at `R/urps_baseline.R:31-38`
   so Lineage A stops reading the frozen archived table.

---

## 6. Risks / honest caveats

- **Do not ingest the "8% → 99%" prevalence** or the flat 1,169 supply as production inputs;
  both are illustrative/uncalibrated. Calibration (blocker #2) gates Stage 2.
- `simulation` has a **20× internal demand inconsistency** (~1,118 vs ~48,700 FTE) that must be
  resolved on its side before any FTE-level demand number is contract-worthy.
- The hardcoded literals in `shiny_urps_scenarios/urps_model_data.R` bypass mufflyaccess; until
  they read the contract, Lineage B will silently diverge from any incorporated numbers.
- Keep cliff's Medicare-anchored Module B/C and the published-anchor D1/D2/D3 as validation
  backstops even after DPMM is wired in — they are the credibility check on the microsimulation.

---

*Prepared as a review + integration plan in response to: "review the demand and supply numbers
from simulation and figure out how to incorporate those into cliff." Cross-references the URPS
microsimulation improvement plan (2026-07-30).*
