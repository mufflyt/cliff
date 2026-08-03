# Figure provenance (cliff workforce manuscript)

This file is the single source of truth for **where each figure came from**: the
script that draws it, the data file(s) it reads, the day it was generated, and
which workforce baseline it reflects. Dates are git commit dates (authoritative)
with the on-disk file modification time noted where it differs. Last audited
2026-08-02.

> Scope: this covers the figures used by the URPS supply-and-demand ("workforce
> cliff") manuscript and embedded in `README.md`. Exploratory or archived figures
> under `augs_application/figures/`, `code/archived/`, and `scripts/make_exec_*`
> are not part of the manuscript deliverable and are not tracked here.

## Data lineage (upstream to figure)

The figures do not read raw board or Medicare data. They read one of two derived
inputs, both of which trace back to the isochrones pipeline:

1. **URPS roster and count** are produced in the **isochrones** repo, not here:
   `scripts/build_urps_workforce_artifact.R` (created 2026-07-27, last commit
   2026-07-29) writes `artifacts/workforce/urps_counts_by_year.csv`,
   `urps_provider_snapshot.parquet`, `urps_manifest.json`, and
   `urps_release_contract.json` (method `urps-workforce-v3.0.0`, contract v3.0.0).
   The contract declares the canonical 2023 `board_certified_active` count as
   **1,306 national / 1,303 CONUS** (roster snapshot 1,339 / 1,336).
2. **mufflyaccess 0.10.0** (GitHub `mufflyt/mufflyaccess`, SHA
   `1fc2221e9c2d77212828c63ad563989e49a96cd6`, pinned in `renv.lock`) validates
   and serves that number via `mufflyaccess::urps_count()`.
3. **cliff's dynamic model** writes `data/workforce_projections_consolidated.csv`
   (last rebuilt 2026-08-02, commit `42fefcd`, "correct primary to 5.38 +
   regenerate generator-backed sensitivities on 1306"). This is the shared table
   most figures read: it carries `baseline_2025`, `projected_2029`, the 95%
   Monte Carlo interval, and `replacement_ratio` on the 1,306 baseline with the
   primary pooled age-band hazard (GO 7.11, URPS 5.38).
4. The concentration/equity figure instead reads the committed enriched rosters
   directly (`data/abog_all_urps_ENRICHED_2026-07-22.csv`,
   `data/abu_all_urps_ENRICHED_2026-07-22.csv`, roster N = 1,339) through the
   shared `inmodel()` filter (`R/in_model_baseline.R`).

## Per-figure record

"Generated" is the git commit date of the figure file (on-disk mtime in
parentheses when it is later, i.e. a working-copy regeneration not yet committed).
`.tiff` companions at publication resolution sit beside each `.png`.

| Figure | File(s) | Generator | Reads | Generated | Baseline | Status |
|---|---|---|---|---|---|---|
| Manuscript Fig 1 (stock-flow design schematic) | `manuscript/figures/figure-stock-flow-design-1.png` (render) + `figure_stock_flow_design.{png,tiff}` (standalone) | `manuscript/R/create_figure_stock_flow_design.R` `fig_stock_flow_design()` (called by the Rmd at render) | constructed schematic, NO data input | 2026-08-02 | n/a (design) | CURRENT |
| Manuscript Fig 2 (trajectories) | `manuscript/figures/figure1-1.png` | `manuscript/R/workforce_figures.R` `fig_trajectory()` (called by the Rmd at render) | `data/workforce_projections_consolidated.csv` (via `load_workforce_data`) + `data/graduation_active_transition_projection.csv` | rendered 2026-08-02 | 1,306 / pooled | CURRENT |
| Manuscript Fig 3 (robustness) | `manuscript/figures/figure2-1.png` | `manuscript/R/workforce_figures.R` `fig_robustness()` (called by the Rmd at render) | `data/workforce_projections_consolidated.csv` + `data/hierarchical_hazard_comparison.csv` + sensitivity CSVs | rendered 2026-08-02 | 1,306 / pooled | CURRENT |
| README hero (abstract, 2026 to 2030) | `figures/workforce_crisis_abstract.{png,tiff}` | `code/03_create_abstract_figure.R` | `data/workforce_projections_consolidated.csv` | 2026-08-02 | 1,306 | CURRENT |
| README Fig 1 (workforce trajectories) | `figures/figure1_workforce_trajectories.{png,tiff}` | `code/02_create_figures.R` | `data/workforce_projections_consolidated.csv` | 2026-08-02 | 1,306 | CURRENT |
| README Fig 2 (replacement gap) | `figures/figure2_replacement_gap.{png,tiff}` | `code/02_create_figures.R` | `data/workforce_projections_consolidated.csv` | 2026-08-02 | 1,306 | CURRENT |
| Fellowship scenarios, 2029 level | `figures/scenario_comparison.{png,tiff}` | `code/04_compare_scenarios.R` | `data/workforce_projections_consolidated.csv` + `data/scenario_comparison.csv` | 2026-08-02 | 1,306 | CURRENT |
| Fellowship scenarios, % change | `figures/scenario_comparison_change.{png,tiff}` | `code/04_compare_scenarios.R` | `data/workforce_projections_consolidated.csv` + `data/scenario_comparison.csv` | 2026-08-02 | 1,306 | CURRENT |
| Retirement sensitivity, 2029 level | `figures/retirement_sensitivity_workforce.{png,tiff}` | `code/06_retirement_sensitivity.R` | `data/workforce_projections_consolidated.csv` + `data/retirement_sensitivity.csv` | 2026-08-02 | 1,306 | CURRENT |
| Retirement sensitivity, % change | `figures/retirement_sensitivity_change.{png,tiff}` | `code/06_retirement_sensitivity.R` | `data/workforce_projections_consolidated.csv` + `data/retirement_sensitivity.csv` | 2026-08-02 (commit `a3f5ab7`) | 1,306 | CURRENT |
| Concentration Lorenz curves | `figures/urps_concentration_lorenz_2026-08-01.{png,tiff}` | `scripts/urps_concentration_equity_2026-08-01.R` | `data/abog_all_urps_ENRICHED_2026-07-22.csv` + `data/abu_all_urps_ENRICHED_2026-07-22.csv` | 2026-08-02 | roster N = 1,339 | CURRENT |
| Differential distance map | `outputs/urps_differential_distance_map_2026-07-23.png` | `scripts/urps_module_d_differential_map.R` | enriched roster (N = 1,339) | 2026-07-23 (in filename) | roster N = 1,339 | dated by filename |

## Prior inconsistency (resolved 2026-08-02)

Through 2026-07-24 the README embedded three **pre-1,306** figures
(`workforce_crisis_abstract.png`, `figure1_workforce_trajectories.png`,
`figure2_replacement_gap.png`) that were drawn from the version of
`data/workforce_projections_consolidated.csv` predating the 2026-08-02 "1,306
rebuild + correct primary to 5.38" (commit `42fefcd`), so they did not match the
manuscript's live-rendered Figure 1/2. On **2026-08-02** all three were
regenerated on the current 1,306 CSV and now agree with the manuscript:

```bash
Rscript code/02_create_figures.R         # -> figure1_workforce_trajectories, figure2_replacement_gap
Rscript code/03_create_abstract_figure.R # -> workforce_crisis_abstract
```

All README and manuscript workforce figures are now on the same 1,306 baseline.
If `data/workforce_projections_consolidated.csv` changes again, re-run those two
scripts (and re-render the manuscript) so the committed figures stay in sync.

## How to regenerate any figure

Each figure is reproducible from the committed data with one script (all read
through `here()` from the repo root):

| Script | Produces |
|---|---|
| `code/02_create_figures.R` | `figure1_workforce_trajectories`, `figure2_replacement_gap` |
| `code/03_create_abstract_figure.R` | `workforce_crisis_abstract` |
| `code/04_compare_scenarios.R` | `scenario_comparison`, `scenario_comparison_change` |
| `code/06_retirement_sensitivity.R` | `retirement_sensitivity_workforce`, `retirement_sensitivity_change` |
| `scripts/urps_concentration_equity_2026-08-01.R` | `urps_concentration_lorenz_2026-08-01` |
| `scripts/urps_module_d_differential_map.R` | `urps_differential_distance_map_2026-07-23` |
| `manuscript/R/create_figure_stock_flow_design.R` | `figure_stock_flow_design` (Fig 1 design schematic; standalone or via render) |
| render of `manuscript/manuscript_WORKFORCE_CLIFF.Rmd` | `figure-stock-flow-design-1.png` (Fig 1), `figure1-1.png` (Fig 2), `figure2-1.png` (Fig 3) |

`code/00_RUN_ALL.R` runs the full `code/` pipeline and writes a machine-readable
run manifest to `outputs/runs/<timestamp>/metadata.json` (git commit, R version,
data file, and the figure list). A compact machine-readable copy of the table
above is kept at `docs/figure_provenance.csv`.
