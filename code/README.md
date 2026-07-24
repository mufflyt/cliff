# Workforce Cliff Analysis - Code Pipeline

**Last Updated:** January 12, 2026

This folder contains all scripts needed to reproduce the workforce retirement analysis from start to finish.

---

## Quick Start

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

**IMPORTANT:** You MUST run from the isochrones project directory. The script will check and show a helpful error if you're in the wrong location.

This will:
1. Consolidate data with updated fellowship assumptions
2. Generate figures (PNG + TIFF)
3. Render manuscript (HTML + Word)

**Runtime:** ~2 seconds

---

## Scripts (Execution Order)

### 00_RUN_ALL.R
**Master pipeline script** - Runs all steps in correct order

**Usage:**
```bash
Rscript cliff/code/00_RUN_ALL.R
```

**Outputs:**
- `cliff/data/workforce_projections_consolidated.csv`
- `cliff/figures/` (4 figure files)
- `cliff/manuscript/WORKFORCE_CLIFF_ObGyn.html`
- `cliff/manuscript/WORKFORCE_CLIFF_ObGyn.docx`

---

### 01_consolidate_workforce_data.R
**Data consolidation with updated fellowship assumptions**

**Purpose:** Load archived Monte Carlo simulation results and apply 2026 fellowship data

**Fellowship Assumptions (2026):**
- **FPMRS:** 60 fellows/year (updated from 47)
- **Gynecologic Oncology:** 50 fellows/year (updated from 60)
- **MIGS:** 45 fellows/year (updated from 51)

**Inputs:**
- `docs/isochrones_deep_archive/.../enhanced_comparison_table_20250928_030546.csv`

**Outputs:**
- `cliff/data/workforce_projections_consolidated.csv`

**Usage:**
```bash
Rscript cliff/code/01_consolidate_workforce_data.R
```

**Key Calculations:**
- Recalculates replacement ratios based on new fellowship numbers
- Recalculates 2029 projections: `baseline - (4 × retirements) + (4 × entrants)`
- Computes 95% confidence intervals using parametric method

**Validation Checks:**
- No missing values in critical columns
- Replacement ratios mathematically correct
- Confidence intervals reasonable (<50% of mean)
- No negative projections

---

### 02_create_figures.R
**Generate publication-ready figures**

**Purpose:** Create workforce trajectory and replacement gap visualizations

**Requires:** Must run `01_consolidate_workforce_data.R` first

**Outputs:**
- `cliff/figures/figure1_workforce_trajectories.png` (600 DPI)
- `cliff/figures/figure1_workforce_trajectories.tiff` (600 DPI, LZW)
- `cliff/figures/figure2_replacement_gap.png` (600 DPI)
- `cliff/figures/figure2_replacement_gap.tiff` (600 DPI, LZW)

**Usage:**
```bash
Rscript cliff/code/02_create_figures.R
```

**Figure Specifications:**
- **Figure 1:** Workforce projection trajectories (2025-2029)
  - Line plot with 95% confidence ribbons
  - Three subspecialties color-coded
  - Year-by-year linear interpolation

- **Figure 2:** Replacement gap visualization
  - Grouped bar chart
  - Compares annual retirements vs fellowship graduates
  - Highlights surplus/deficit by subspecialty

---

### workforce_statistics.R
**Helper functions library** (not run directly)

**Purpose:** Provide accessor functions for R Markdown inline statistics

**Functions:**
- `get_baseline(subspecialty)` - 2025 baseline count
- `get_projected(subspecialty)` - 2029 projected count
- `get_ci_lower(subspecialty)` - Lower 95% CI
- `get_ci_upper(subspecialty)` - Upper 95% CI
- `get_percent_change(subspecialty)` - Percent change
- `get_annual_rate(subspecialty)` - Annual retirement rate
- `get_replacement_ratio(subspecialty)` - Replacement ratio
- `get_replacement_assessment(subspecialty)` - Classification
- `get_annual_entrants(subspecialty)` - Fellowship graduates/year
- `get_avg_retirements(subspecialty)` - Average retirements/year

**Total Functions:**
- `get_total_baseline()` - Total baseline workforce
- `get_total_projected()` - Total projected workforce
- `get_total_net_change()` - Net change across all subspecialties
- `get_total_percent_change()` - Percent change across all

**Usage in Rmd:**
```r
source(here("code/workforce_statistics.R"))

# Example inline code
`r get_baseline("FPMRS")` physicians in 2025
`r get_projected("GO")` projected for 2029
Replacement ratio: `r get_replacement_ratio("MIG")`
```

---

## Code Style and Conventions

To maintain consistency and readability across the codebase, please adhere to the following guidelines when contributing:

### R Code
-   **Style Guide:** Follow the [tidyverse style guide](https://style.tidyverse.org/).
-   **Naming:**
    -   Variables: `snake_case` (e.g., `my_variable`).
    -   Functions: `snake_case` (e.g., `my_function`).
    -   Files: `snake_case` and start with a two-digit number for ordering (e.g., `01_script_name.R`).
-   **Commenting:**
    -   Use `#` for inline comments.
    -   Use `#'` for roxygen2-style comments for functions and script headers.
    -   Explain *why* a piece of code exists or is complex, not just *what* it does.
-   **Piping:** Use the `%>%` operator (from `magrittr`, part of `tidyverse`) for chaining operations.
-   **Indentation:** 2 spaces.
-   **Line Length:** Aim for a maximum of 80 characters per line.

### Shell Scripts
-   **Style Guide:** Follow a consistent shell style, generally POSIX compliant.
-   **Naming:** `snake_case` (e.g., `my_script.sh`).
-   **Commenting:** Use `#` for comments.
-   **Error Handling:** Use `set -e` to exit immediately if a command exits with a non-zero status.

### General
-   **File Encoding:** UTF-8.
-   **Reproducibility:** Ensure scripts can be run independently and produce consistent results.
-   **Dependencies:** Clearly list all R package dependencies in the script header or a dedicated section.
-   **Paths:** Use `here::here()` for all file paths to ensure reproducibility across different environments.


---

## Data Flow

```
Input Data (archived simulation)
         ↓
01_consolidate_workforce_data.R
    - Apply new fellowship assumptions
    - Recalculate projections
    - Validate results
         ↓
workforce_projections_consolidated.csv
         ↓
    ┌────┴────┐
    ↓         ↓
02_create_figures.R    workforce_statistics.R
    ↓                          ↓
Figures                   Manuscript.Rmd
(PNG + TIFF)                   ↓
                          HTML + Word
```

---

## Dependencies

### R Packages Required:
- `tidyverse` (dplyr, tidyr, readr, ggplot2)
- `here` (path management)
- `scales` (number formatting)
- `knitr` (manuscript rendering)
- `kableExtra` (table formatting)
- `rmarkdown` (manuscript compilation)

### Install All:
```r
install.packages(c("tidyverse", "here", "scales", "knitr", "kableExtra", "rmarkdown"))
```

---

## Key Findings (2026 Updated Assumptions)

With the updated fellowship allocations:

| Subspecialty | 2025 Baseline | 2029 Projected | Change | Replacement Ratio | Assessment |
|--------------|---------------|----------------|--------|-------------------|------------|
| **FPMRS** | 1,283 | 1,301 | +1.4% | 1.08 | Marginal |
| **Gynecologic Oncology** | 1,352 | 1,278 | -5.5% | 0.73 | **Insufficient** |
| **MIGS** | 767 | 835 | +8.9% | 1.61 | Adequate |

**Key Changes from Original Assumptions:**
- **FPMRS:** Now shows modest growth (+1.4%) instead of decline (-7.0%)
  - Upgraded from marginal (0.85) to marginal (1.08) with new 60 fellows/year
- **Gynecologic Oncology:** Worsened decline (-5.5% vs -7.6%)
  - Downgraded from marginal (0.88) to insufficient (0.73) with reduced 50 fellows/year
- **MIGS:** Slightly reduced growth (8.9% vs 8.4%)
  - Remains adequate but lower ratio (1.61 vs 1.83) with 45 fellows/year

---

## Troubleshooting

### "Data file not found"
**Error:** `cliff/data/workforce_projections_consolidated.csv` not found

**Solution:** Run step 01 first:
```bash
Rscript cliff/code/01_consolidate_workforce_data.R
```

### "Package not installed"
**Error:** `there is no package called 'X'`

**Solution:** Install missing package:
```r
install.packages("package_name")
```

### "Archived data not found"
**Error:** `enhanced_comparison_table_20250928_030546.csv` not found

**Solution:** Verify path in script matches your archive location, or contact author for data access.

---

## Modifying Fellowship Assumptions

To change fellowship numbers, edit `01_consolidate_workforce_data.R`:

```r
# Line ~40-45
FELLOWSHIP_UPDATED <- tribble(
  ~subspecialty, ~annual_entrants,
  "FPMRS",       60,  # Change this number
  "GO",          50,  # Change this number
  "MIG",         45   # Change this number
)
```

Then re-run the pipeline:
```bash
Rscript cliff/code/00_RUN_ALL.R
```

---

## Contact

**Author:** Tyler Muffly, MD
**Institution:** Denver Health Medical Center, University of Colorado School of Medicine
**Email:** tyler.muffly@dhha.org

---

**Repository:** `/Users/tmuffly/isochrones/cliff/`
**License:** Public domain (de-identified publicly available data)
