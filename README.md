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

## Shiny App

Interactive retirement cliff simulator:

```r
shiny::runApp("app")
```

Shows population coverage drop as the oldest physicians retire first, with rural/urban equity breakdown.

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
