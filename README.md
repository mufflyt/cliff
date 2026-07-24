# Gynecologic Subspecialty Workforce Retirement Analysis

**Title:** Retirement Rates Among U.S. Gynecologic Surgical Subspecialists Exceed Fellowship Replacement Capacity

**Authors:** Tyler Muffly, MD (Denver Health Medical Center, University of Colorado School of Medicine)

**Date:** January 12, 2026

---

## Getting Started

This project contains the complete code, data, and manuscript materials for the gynecologic subspecialty workforce retirement analysis. To get started, follow these steps:

### Prerequisites

You will need R installed on your system.
The following R packages are required:
```r
install.packages(c("tidyverse", "here", "knitr", "kableExtra", "scales", "rmarkdown", "gtsummary", "flextable", "yaml"))
```

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/your_username/isochrones.git
    cd isochrones/cliff
    ```
    (Note: Replace `https://github.com/your_username/isochrones.git` with the actual repository URL if this project is hosted publicly.)

2.  **Ensure you are in the correct directory:**
    All scripts in this project are designed to be run from the root of the `isochrones` project directory. For example, if your project is located at `/Users/youruser/isochrones`, you should navigate to this directory before running any R scripts.

    ```bash
    cd /Users/youruser/isochrones
    ```
    The master pipeline script (`cliff/code/00_RUN_ALL.R`) includes checks to ensure you are in the correct directory and will provide helpful error messages if not.

### Running the Analysis

Once prerequisites are met and the repository is cloned, you can run the entire analysis pipeline using the master script.

---

## Project Organization

This folder contains all code, data, and manuscript materials for the workforce retirement analysis.

```
cliff/
├── code/           # R scripts and analysis code
├── data/           # Processed data files
├── manuscript/     # Manuscript source files
├── figures/        # Publication-ready figures
└── docs/           # Documentation and supplementary materials
```

---

## Key Files

### Manuscript
- **`manuscript/WORKFORCE_CLIFF_ObGyn.Rmd`** - Main manuscript in Obstetrics & Gynecology format
  - Includes précis, structured abstract, introduction, methods, results, discussion
  - All inline statistics are dynamically generated from data
  - Formatted for journal submission

### Code
- **`code/workforce_statistics.R`** - Statistics helper functions for inline calculations
- **`code/manuscript_consolidate_existing_results.R`** - Data consolidation script
- **`code/create_figures.R`** - Figure generation script (600 DPI PNG and TIFF)

### Data
- **`data/workforce_projections_consolidated.csv`** - Primary analysis dataset
  - Baseline workforce counts (2025)
  - Projected workforce (2029)
  - Retirement rates by subspecialty
  - Replacement ratios
  - 95% confidence intervals

### Figures
- **`figures/figure1_workforce_trajectories.png/.tiff`** - Workforce projection trajectories (2025-2029)
- **`figures/figure2_replacement_gap.png/.tiff`** - Replacement gap visualization

---

## Key Findings

### Retirement Rates (Annual)
- **Gynecologic Oncology:** 5.2%
- **FPMRS:** 4.4%
- **MIGS:** 3.4%

### Workforce Projections (2025-2029)
| Subspecialty | 2025 Baseline | 2029 Projected | Change | Replacement Ratio |
|--------------|---------------|----------------|--------|-------------------|
| **FPMRS** | 1,283 | 1,193 | -7.0% | 0.85 (marginal) |
| **Gynecologic Oncology** | 1,352 | 1,249 | -7.6% | 0.88 (marginal) |
| **MIGS** | 767 | 831 | +8.4% | 1.83 (adequate) |

### Replacement Capacity
- **FPMRS:** 47 fellowship graduates/year vs 55.6 retirements/year → **Insufficient**
- **Gynecologic Oncology:** 60 graduates/year vs 68.5 retirements/year → **Insufficient**
- **MIGS:** 51 graduates/year vs 27.9 retirements/year → **Adequate**

---

## Methodology Summary

### Retirement Detection System
Seven-source hierarchical detection integrating:
1. ABMS board certification lapse (Confidence 0.95)
2. NPPES deactivation (Confidence 0.90)
3. Open Payments cessation (Confidence 0.70)
4. PECOS disenrollment (Confidence 0.80)
5. Medicare Part D cessation (Confidence 0.60)
6. Medicare Part B cessation (Confidence 0.60)
7. Physician Compare changes (Confidence 0.55)

**Validation:** 92.4% sensitivity, 89.7% specificity (n=500 vs state license records)

### Monte Carlo Simulation
- **1,000 iterations** projecting 2025-2029
- Subspecialty-, age-, and sex-specific retirement probabilities
- Fellowship entrants: FPMRS 47/yr, GO 60/yr, MIGS 51/yr
- 95% CI from empirical quantiles (5th-95th percentiles)

---

## Running the Analysis Pipeline

### From Command Line

```bash
cd /Users/tmuffly/isochrones
Rscript cliff/code/00_RUN_ALL.R
```

### From RStudio

```r
setwd("/Users/tmuffly/isochrones")
source("cliff/code/00_RUN_ALL.R")
```

The master pipeline script (`cliff/code/00_RUN_ALL.R`) will:
1. Consolidate data with updated fellowship assumptions.
2. Generate all figures (main and abstract) in PNG and TIFF formats.
3. Render the manuscript into HTML and Word documents.
4. Archive all outputs with metadata for reproducibility.

You can also run specific scenarios:
```bash
Rscript cliff/code/00_RUN_ALL.R optimistic
Rscript cliff/code/00_RUN_ALL.R pessimistic
```

For more details on individual scripts and their functionalities, please refer to `cliff/code/README.md`.

---

## Data Sources

### Primary Data (2013-2023)
- **ABOG Certification Data** - Subspecialty certification records
- **NPPES** - National Provider Identifier System (longitudinal locations)
- **Medicare Part B Claims** - Billing activity (2013-2022)
- **Medicare Part D Prescriber** - Prescribing activity (2013-2022)
- **CMS Open Payments** - Industry payments (2013-2023)
- **PECOS** - Provider enrollment status
- **Physician Compare** - Practice status changes
- **State Medical Boards** - License validation (CA, TX, FL, WA)

### Fellowship Pipeline Data
- **ACGME Program Data** - Fellowship graduates 2022-2024 (3-year average)

---

## Publication Status

**Journal Target:** Obstetrics & Gynecology

**Manuscript Format:**
- Précis (50 words)
- Structured abstract (250 words)
- Main text (~3,500 words)
- 14 references
- 2 figures (600 DPI TIFF)
- 2 tables

**Key Points:**
- Question, Findings, Meaning format
- STROBE compliant
- All statistics dynamically generated
- Reproducible analysis pipeline

---

## Contact

**Corresponding Author:**
Tyler Muffly, MD
Department of Obstetrics and Gynecology
Denver Health Medical Center
University of Colorado School of Medicine
777 Bannock Street, Denver, CO 80204
Email: tyler.muffly@dhha.org

---

---

## License

This project is licensed under the [MIT License](LICENSE).

### Data Availability

All data sources used in this project are publicly available and de-identified. Institutional Review Board (IRB) review was not required. Code and analysis scripts are available in this repository for reproducibility.

---

**Last Updated:** January 12, 2026

