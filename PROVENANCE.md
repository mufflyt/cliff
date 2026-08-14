# Data provenance — where every workforce-cliff number comes from

Purpose: so this analysis can be rebuilt from primary sources in six months without
tribal knowledge. Traced 2026-07-24 from the canonical isochrones source
(`feature/seven-subspecialty-expansion @ 655d279e9`). Items marked **⚠ CONFIRM** need a
second look before submission.

---

## 1. The single source of truth (SSOT)

**`data/workforce_projections_consolidated.csv`** — the one table every manuscript number,
figure, and table is computed from. Validated on load by the fail-loud contract in
`manuscript/R/workforce_data_contract.R` (structure, no-placeholder, and the arithmetic that
ties the columns together), and by `tests/testthat/test-ssot-derived-column-identities.R`,
which checks each derived column against its defining expression at full precision.

**Producer: `scripts/rebuild_ssot_revised.R`** — the only script authorised to write it.
Only measured inputs are typed there; `annual_retirement_rate`, `replacement_ratio`,
`percent_change`, `replacement_assessment`, `fellowship_total_4yr` and
`total_retirements_4yr` are computed, and the identities are asserted before the write.

> **Corrected 2026-08-14.** This section previously stated that the SSOT was hand-frozen
> with no committed regeneration script, and that its entrant vector was 60/50/45. Both were
> true when written and are now false: the producer above exists, and the entrants are
> **64 / 75 / 47** (URPS / GO / MIGS). That is precisely the drift this document exists to
> prevent, in this document. The generator-to-artifact map is therefore **generated**, not
> written by hand: see **[`docs/PIPELINE.md`](docs/PIPELINE.md)**, rebuilt by
> `scripts/build_pipeline_map.R` and guarded by `tests/testthat/test-pipeline-map-current.R`.

Every artifact the manuscript and supplement read now has a generator in `scripts/`. Most
were recovered from isochrones history after the extraction carried their outputs across
without their code; `CLAUDE.md` records how to search for one, and the ways that search
goes wrong.

---

## 2. Per-column lineage of the SSOT

| Column | Origin (primary source) | Vintage / notes |
|---|---|---|
| `baseline_2025` | **ABOG board certification** — count of active board-certified subspecialists (subspecialty is the gold standard, superseding taxonomy codes) | through Dec 2024; active-practice restricted |
| `annual_retirement_rate` | **6-source hierarchical departure detection**: ABMS cert lapse, NPPES deactivation, CMS Open Payments cessation, PECOS disenrollment, Medicare Part D + Part B claims cessation | Medicare 2013-2022; Open Payments 2013-2023; hazard estimated on the fully-observable window (see revised model note) |
| `avg_annual_retirements` | measured; `annual_retirement_rate` is derived from it as `100 × avg_annual_retirements / baseline_2025` | the arithmetic is guarded, not hand-verified |
| `annual_entrants` | **ACGME** accredited fellowship completions, multi-year means: URPS 64 (OB/GYN-sponsored 48 + urology-sponsored ~16), GO 75, MIGS 47. The NRMP filled-position benchmark (74/88/51) is reported separately in `data/workforce_projection_benchmark_nrmp.csv` | steady-state caps assumed |
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
2. ~~**No SSOT producer.**~~ **Resolved 2026-08-14** — `scripts/rebuild_ssot_revised.R` (§1).
3. **154-byte archival input.** The historical-scenario producer depends entirely on a 154-byte
   CSV from a 2025-09-28 run that no longer has a live simulation behind it.
4. ~~**Entrant-scenario ambiguity.**~~ **Resolved** — the paper adopts the ACGME multi-year
   means (64/75/47). The NRMP benchmark is reported as a named alternative, not a competing
   default, in `data/workforce_projection_benchmark_nrmp.csv`.
5. **HRSA citation** (if used) was flagged provisional pending a primary-source PDF.

---

## 5. Integrity check

`SHA256SUMS` (repo root) hashes every `data/`, `data-raw/`, `inst/` input. Verify before a
rebuild: `shasum -a 256 -c SHA256SUMS`. Any mismatch means an input drifted — stop and
investigate rather than publishing a silently-changed number.
