# Data provenance — where every workforce-cliff number comes from

Purpose: so this analysis can be rebuilt from primary sources in six months without
tribal knowledge. Traced 2026-07-24 from the canonical isochrones source
(`feature/seven-subspecialty-expansion @ 655d279e9`). Items marked **⚠ CONFIRM** need a
second look before submission.

---

## 1. The single source of truth (SSOT)

**`data/workforce_projections_consolidated.csv`** — the one table every manuscript number,
figure, and table is computed from. It is **hand-frozen** (a deliberate, PI-sanctioned
freeze), validated on load by the fail-loud contract in
`manuscript/R/workforce_data_contract.R` (structure, no-placeholder, and the arithmetic that
ties the columns together).

**⚠ There is no committed script that regenerates the live SSOT from raw inputs.** Two
*candidate* producers exist but neither writes this file:
- `R/manuscript_consolidate_existing_results.R` → writes a **historical-scenario** table
  (entrants 47/60/51) to `manuscript/data/`, NOT the SSOT. Its input is a **154-byte** archival
  CSV (`enhanced_comparison_table_20250928_030546.csv`) from the 2025-09-28 forecasting run.
- `scripts/rebuild_ssot_from_nrmp.R` → writes an **NRMP-corrected candidate**
  (`workforce_projections_NRMP_corrected.csv`, entrants 70/86/47) but does **not** overwrite
  the SSOT (adopting it reverses the GO finding and needs a contract-test update).

So the live SSOT's entrant values (default **60/50/45**) are a frozen editorial choice, not a
script output. **Rebuild note:** to reproduce, treat the CSV as an input artifact; to *re-derive*
it, you must reconcile the three scenarios (default 60/50/45, historical 47/60/51, NRMP 70/86/47).

---

## 2. Per-column lineage of the SSOT

| Column | Origin (primary source) | Vintage / notes |
|---|---|---|
| `baseline_2025` | **ABOG board certification** — count of active board-certified subspecialists (subspecialty is the gold standard, superseding taxonomy codes) | through Dec 2024; active-practice restricted |
| `annual_retirement_rate` | **6-source hierarchical departure detection**: ABMS cert lapse, NPPES deactivation, CMS Open Payments cessation, PECOS disenrollment, Medicare Part D + Part B claims cessation | Medicare 2013-2022; Open Payments 2013-2023; hazard estimated on the fully-observable window (see revised model note) |
| `avg_annual_retirements` | `baseline_2025 × annual_retirement_rate` | derived (verify: 1283×.044≈56.5, 1352×.052≈70.3, 767×.034≈26.1) |
| `annual_entrants` | **ACGME** accredited fellowship positions (default scenario 60/50/45); NRMP "positions filled" is the alternative (70/86/47, see `rebuild_ssot_from_nrmp.R`) | steady-state caps assumed |
| `sd_2029` | **Frozen Monte-Carlo run** (2025-09-28, `enhanced_workforce_statistical_summaries`); **manually transcribed** into `manuscript_consolidate_existing_results.R` (FPMRS 15.2 / GO 16.1 / MIG 11.0) | no live re-runnable simulation exists in the repo |
| `projected_2029` | `baseline + 4×(entrants − retirements)` via the contract formula | derived |
| `ci95_lower/upper` | **⚠ parametric** `projected ± 1.96 × SD` | **contradiction to reconcile — see §4** |
| `percent_change`, `replacement_ratio`, `replacement_assessment` | derived via the shared contract constants (`workforce_data_contract.R`) | — |

Population/demand inputs (for the supply–demand module, `scripts/urps_supply_demand_national*`):
US Census **2023 National Population Projections** (women 65+, 2025–2050) and **ACS 5-yr B01001**;
PFD prevalence from **Nygaard 2008 JAMA** / **Wu 2009**.

---

## 3. Revised model (the canonical manuscript) — additional inputs

The current paper uses a **partial-pooling age-band departure hazard** for GO + URPS
(MIGS exploratory), not the simple Monte-Carlo of the frozen SSOT. Key inputs:
- `data/nrmp_fellowship_entrants.csv` — NRMP filled fellowship positions.
- `data/hazard_by_band_pooled_vs_unpooled.csv` — the partial-pooled vs pooled/unpooled hazards.
- Departure events estimated over the **2016–2021** window (three-year administrative
  follow-up rule; 2022–2023 right-censored).
- ABU (urology-pathway) roster via the `scripts/abu_*` acquisition pipeline (board-cert
  verification portal scrape → NPI → geocode).

**⚠ CONFIRM:** the frozen SSOT (§1–2, FPMRS/GO/MIG Monte-Carlo) and the revised partial-pooling
model (GO/URPS) are two lineages. Confirm which drives the *submitted* tables, and that the
contract/tests point at the right one.

---

## 4. Known provenance issues to resolve before submission

1. **CI method contradiction.** The manuscript Methods state 95% CIs are the **5th/95th
   empirical percentiles** of the simulation, but the code computes **parametric `mean ± 1.96·SD`**
   (`manuscript_consolidate_existing_results.R`; SDs manually transcribed). One is wrong — reconcile.
2. **No SSOT producer.** The live SSOT is hand-frozen with no committed regeneration script (§1).
3. **154-byte archival input.** The historical-scenario producer depends entirely on a 154-byte
   CSV from a 2025-09-28 run that no longer has a live simulation behind it.
4. **Entrant-scenario ambiguity.** Three coexisting entrant vectors: default 60/50/45 (frozen),
   historical 47/60/51, NRMP 70/86/47. Document which the paper adopts and why.
5. **HRSA citation** (if used) was flagged provisional pending a primary-source PDF.

---

## 5. Integrity check

`SHA256SUMS` (repo root) hashes every `data/`, `data-raw/`, `inst/` input. Verify before a
rebuild: `shasum -a 256 -c SHA256SUMS`. Any mismatch means an input drifted — stop and
investigate rather than publishing a silently-changed number.
