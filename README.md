# Gynecologic Subspecialty Workforce Cliff

**Title:** Gynecologic Subspecialty Workforce Vulnerability: Retirement Approaches or Exceeds Fellowship Replacement Capacity

**Authors:** Tyler Muffly, MD · Sydney Archer, MD, MPH  
**Affiliation:** Denver Health Medical Center / University of Colorado School of Medicine  
**Target Journal:** Obstetrics & Gynecology  
**Status:** Under review (2026)

> **Presented** as an oral presentation at the 52nd Annual Meeting of the Society of Gynecologic Surgeons, Phoenix, AZ, March 2026.

---

## Quick Start

```bash
git clone git@github.com:mufflyt/cliff.git
cd cliff
Rscript code/00_RUN_ALL.R
```

Produces all figures, tables, and a rendered manuscript in ~4 seconds. No external data required — seed data is committed to `data/`.

---

## Prerequisites

R ≥ 4.3 and the following packages:

```r
install.packages(c(
  "tidyverse", "here", "yaml", "scales",
  "knitr", "kableExtra", "rmarkdown",
  "gtsummary", "flextable", "jsonlite", "testthat"
))
```

---

## Repository Structure

```
cliff/
├── code/
│   ├── 00_RUN_ALL.R                    # Master pipeline (run this)
│   ├── 01_consolidate_workforce_data.R # Re-run Monte Carlo (optional)
│   ├── 02_create_figures.R             # Figure 1 & 2
│   ├── 03_create_abstract_figure.R     # SGS abstract figure
│   ├── 04_compare_scenarios.R          # Fellowship sensitivity
│   ├── 05_validate_with_monte_carlo.R  # Monte Carlo validation
│   ├── 06_retirement_sensitivity.R     # Retirement threshold sensitivity
│   ├── 07_create_table1.R             # Demographics table
│   ├── 08_pairwise_comparisons.R       # Pairwise scenario comparisons
│   └── workforce_statistics.R          # Inline statistics helpers
├── config/
│   └── fellowship_assumptions.yml      # 5 fellowship scenarios
├── data/
│   └── workforce_projections_consolidated.csv   # Seeded from manuscript
├── manuscript/
│   ├── WORKFORCE_CLIFF_ObGyn.Rmd       # Manuscript source (ObGyn format)
│   ├── Surgical_workforce_cliff_FINAL.txt
│   ├── Surgical_workforce_cliff_REVISED.txt
│   └── Surgical_workforce_cliff_CORRECTED.txt
├── figures/                            # Generated at runtime
├── app/
│   ├── app.R                           # Standalone Shiny retirement cliff app
│   └── R/helpers_retirement_cliff.R
├── scripts/
│   └── fig_fpmrs_supply_line.R         # Static FPMRS supply/demand figure
├── tests/testthat/
│   └── test-cliff-workforce-scripts.R
└── outputs/runs/                        # Timestamped run archives
```

---

## Pipeline Scenarios

```bash
Rscript code/00_RUN_ALL.R                # default (current best estimates)
Rscript code/00_RUN_ALL.R optimistic     # +10 fellows/yr each subspecialty
Rscript code/00_RUN_ALL.R pessimistic    # -10 fellows/yr each subspecialty
Rscript code/00_RUN_ALL.R historical_2025
Rscript code/00_RUN_ALL.R status_quo
```

Step 1 is skipped when `data/workforce_projections_consolidated.csv` already exists. To force a rebuild from raw Monte Carlo inputs:

```bash
CLIFF_FORCE_REBUILD=1 Rscript code/00_RUN_ALL.R
```

---

## Key Findings

### Workforce Projections (2025 → 2029, Monte Carlo 10,000 iterations)

| Subspecialty | 2025 | 2029 (95% CI) | Change | Fellows/yr | Retirements/yr | Ratio | Status |
|---|---|---|---|---|---|---|---|
| **FPMRS** | 1,283 | 1,301 (1,271–1,330) | +1.4% | 60 | 55.6 | **1.08** | Marginal |
| **Gynecologic Oncology** | 1,352 | 1,278 (1,246–1,310) | −5.5% | 50 | 68.5 | **0.73** | Insufficient |
| **MIGS** | 767 | 835 (814–857) | +8.9% | 45 | 27.9 | **1.61** | Adequate |

### Annual Retirement Rates
- GO: 5.2% — highest risk, replacement ratio **insufficient** (0.73)
- FPMRS: 4.4% — marginal replacement (1.08); clinical capacity is the bottleneck
- MIGS: 3.4% — youngest subspecialty, robust growth

### Validation
- Retirement algorithm validated against state medical board records: **94.4% agreement** (472/500)
- Observation period: 2013–2023 (3,066 active subspecialists in 2024)

---

## Shiny Apps

Interactive explorers built from this repo's model:

| App | What it does | Launch |
|---|---|---|
| **Urogynecology Workforce Replacement Explorer** | Projects active urogynecologist headcount under adjustable fellowship-inflow, departure-rate, and graduate-conversion scenarios | **[▶ Live app](https://tyler-muffly.shinyapps.io/urps-workforce-explorer/)** · `shiny::runApp("shiny_urps_scenarios")` |
| **Urogynecology Effective-Adequacy Explorer** | Supply-vs-demand adequacy and capacity margin, with a slider for urologists' share of clinical time in urogynecology — productivity-adjusted capacity, "beyond the head count" | **[▶ Live app](https://tyler-muffly.shinyapps.io/urps-adequacy-explorer/)** · `shiny::runApp("shiny_urps_adequacy")` |

Both apps can also be run locally from a clone with `shiny::runApp()`.

### Interactive map

**Urogynecology geographic access** — a self-contained Leaflet map: county choropleth of
straight-line miles to the nearest urogynecologist, with every provider marked by board
pathway (ABU urology vs ABOG OB/GYN).

- File: [`outputs/urps_module_d_access_map_2026-07-23.html`](outputs/urps_module_d_access_map_2026-07-23.html) — download and open in a browser for the interactive version
- Rendered: [view online](https://htmlpreview.github.io/?https://github.com/mufflyt/cliff/blob/main/outputs/urps_module_d_access_map_2026-07-23.html) (via htmlpreview; may take a moment to load the ~2.4 MB widget)
- Regenerate: `Rscript scripts/urps_module_d_map_2026-07-23.R`

---

## Data Sources

| Source | Years | Purpose |
|---|---|---|
| ABOG certification records | 2013–2024 | Subspecialty identification |
| NPPES | 2013–2024 | Practice locations, demographics |
| Medicare Part B claims | 2013–2022 | Retirement detection |
| Medicare Part D prescriber | 2013–2022 | Retirement detection |
| CMS Open Payments | 2013–2023 | Retirement detection |
| PECOS enrollment | 2013–2024 | Retirement detection |
| Physician Compare | 2013–2023 | Status changes |
| State medical boards (CA, TX, FL, WA) | Validation | Algorithm validation |
| ACGME program data | 2022–2024 | Fellowship pipeline |

All sources are publicly available and de-identified. IRB review not required.

---

## Provenance & upstream (`isochrones` monorepo)

This repository was extracted from the private **[`isochrones`](https://github.com/mufflyt/isochrones)** monorepo, which is where the raw
physician-level data (identifiable NPPES/ABOG/ABU/Medicare records) is assembled and
where many of the committed artifacts in `data/` are first produced. **cliff vends the
derived, de-identified artifacts** (departure hazards, roster crosswalks, workforce
projections, the supply-demand tables) — not the raw inputs.

Practically, this means:

- **Self-contained for analysis.** Rendering the manuscript and running the model from
  the committed artifacts needs only this repo (paths resolve through `here()` at the
  repo root; package versions are pinned in `renv.lock`).
- **Not self-contained for re-derivation.** A handful of *upstream* regeneration scripts
  (`scripts/departure_anchor.R`, `scripts/hierarchical_hazard_partial_pooling.R`,
  `scripts/build_hazard_comparison.R`, `scripts/abu_pathway_sensitivity.R`,
  `scripts/scenario_projection_trajectories.R`) read raw data from the isochrones
  monorepo (e.g. `<isochrones>/manuscript/tables/table1_physician_characteristics.csv`,
  `<isochrones>/data/abu_urology/…`). To rebuild the vended artifacts from scratch you
  need that monorepo; the raw identifiable data intentionally does not live here.

See [`URPS_CONTAINMENT_AND_BASELINE_NOTES.md`](URPS_CONTAINMENT_AND_BASELINE_NOTES.md)
for the exact boundary and the one open reconciliation item (the 1,295 vs 1,339
both-pathway baseline).

---

## From RStudio

Open `RUN_FROM_RSTUDIO.R` and click **Source**, or:

```r
setwd("~/cliff")
source("code/00_RUN_ALL.R")
```

---

## Contact

**Tyler Muffly, MD**  
Department of Obstetrics and Gynecology  
Denver Health Medical Center · University of Colorado School of Medicine  
777 Bannock Street, Denver, CO 80204  
tyler.muffly@dhha.org  
GitHub: [mufflyt/cliff](https://github.com/mufflyt/cliff)

---

## License

MIT License — see [LICENSE](LICENSE).  
All data sources are publicly available and de-identified.

---

*Last updated: 2026-07-24*
