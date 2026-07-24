# Archived Monte Carlo Simulation Code

**Source:** Legacy workforce forecasting analysis (September 2025)
**Copied to cliff:** January 12, 2026

---

## Overview

This folder contains the complete archived code from the original Monte Carlo simulation-based workforce forecasting analysis. This code generated the initial results that were presented in the SGS abstract submission.

**Original Location:**
```
/Users/tmuffly/isochrones/R/@archive/legacy_matching_strategies_2025-12-05/
research_forecasting/comprehensive_forecasting/
```

---

## Key Scripts (41 R files)

### Core Simulation Engine

**monte_carlo_simulation.R** (16KB)
- Main simulation framework
- 1,000 iterations per subspecialty/year
- Generates empirical confidence intervals
- Includes visualization function `create_projection_visualization()`
- Uses retirement hazard functions

**Key function:**
```r
monte_carlo_workforce_projection(
  hazard_results,
  n_simulations = 1000,
  projection_years = 5,
  start_year = 2026,
  entrants_plan = fellowship_data
)
```

---

### Orchestration

**comprehensive_analysis.R** (13KB)
- Master pipeline script
- Coordinates all analysis steps
- Sources other scripts
- Generates combined visualizations
- Saves comprehensive reports

**Workflow:**
1. Extract cohort data (from DuckDB)
2. Build retirement hazard model
3. Load fellowship pipeline data
4. Run Monte Carlo projections
5. Create visualizations
6. Generate reports

---

### Retirement Modeling

**retirement_hazard_model.R** (13KB)
- Age-stratified hazard functions
- Subspecialty-specific rates
- Confidence weighting
- Data extraction from databases

**real_7_source_retirement_system.R** (30KB)
- **Most comprehensive script**
- Seven-source hierarchical detection:
  1. ABMS certification lapse (0.95 confidence)
  2. NPPES deactivation (0.90)
  3. Open Payments cessation (0.70)
  4. PECOS disenrollment (0.80)
  5. Medicare Part D cessation (0.60)
  6. Medicare Part B cessation (0.60)
  7. Physician Compare changes (0.55)
- Validated: 92.4% sensitivity, 89.7% specificity

---

### Statistical Summaries

**enhanced_statistical_summaries.R** (11KB)
- Generates variance measures from raw simulations
- Creates markdown reports
- Proper standard deviation calculation from Monte Carlo distribution

**generate_workforce_statistical_summaries.R** (8.4KB)
- Summary table generation
- Confidence interval calculations
- Subspecialty comparisons

---

### Visualization

**generate_hazard_curves_figure.R** (9.6KB)
- Retirement hazard visualization
- Age-stratified curves
- Subspecialty comparisons

**create_projection_visualization()** (in monte_carlo_simulation.R)
- Creates three-panel figure:
  1. Workforce projections with CI ribbons
  2. Annual retirement rates
  3. Fellowship entrants (if available)
- Uses viridis "plasma" color palette
- 90% and 50% confidence intervals

---

## How the SGS Abstract Figure Was Created

### Original Figure

**File:** `workforce_crisis_labeled.png` (250KB)
**Title:** "Gynecologic Surgical Subspecialty Workforce Crisis"
**Subtitle:** "5-year projections with 90% confidence intervals • Labels show total change 2026-2030"

**Characteristics:**
- Custom colors: Pink (GO), Purple (URPS), Orange (MIGS)
- 90% confidence ribbons (not 95%)
- Endpoint percentage labels
- Clean, minimal design for abstract submission

### Recreation Process

The original code for this specific figure was **not found** in the repository (likely created interactively). However, we successfully **reverse-engineered** it by:

1. **Analyzing the visual style** from the PNG
2. **Studying the simulation output structure** from archived scripts
3. **Identifying the plot components**:
   - Year-by-year trajectories
   - 90% confidence intervals (q05-q95 quantiles)
   - Endpoint labels with percentage changes
   - Custom color palette
4. **Creating new script**: `../03_create_abstract_figure.R`

### Key Differences from Original Code

| Feature | Original (archived) | Recreated (03_create_abstract_figure.R) |
|---------|-------------------|----------------------------------------|
| **Data Source** | Monte Carlo simulation results (RDS files) | Simplified CSV from 01_consolidate script |
| **Confidence Intervals** | Empirical quantiles from 1,000 simulations | Parametric (mean ± 1.645*SD) |
| **Color Palette** | Viridis "plasma" | Custom (pink/purple/orange) |
| **Complexity** | Full simulation pipeline | Simplified linear projection |
| **Runtime** | ~5-10 minutes | ~1 second |

---

## Data Files Included

### Simulation Results

**enhanced_comparison_table_20250928_030546.csv** (254B)
- **This is the file currently used in cliff/code!**
- Contains:
  - Baseline workforce by subspecialty
  - Projected workforce (2029)
  - Percent change
  - Annual retirement rates
  - Fellowship entrants (original assumptions)
  - Replacement ratios

**Format:**
```csv
subspecialty,baseline_workforce,projected_workforce,percent_change,annual_entrants,avg_annual_retirements,replacement_ratio,avg_retirement_rate
FPMRS,1283,1193.1,-7,47,55.6,0.85,4.4
GO,1352,1249.3,-7.6,60,68.5,0.88,5.2
MIG,767,831.4,8.4,51,27.9,1.83,3.4
```

### Reference Figure

**workforce_crisis_labeled.png** (250KB)
- Original SGS abstract figure
- Reference for visual styling
- Shows original fellowship assumptions

---

## Key Differences: Archived vs Current Implementation

### Methodology

**Archived (Monte Carlo):**
```r
# For each simulation
for (i in 1:1000) {
  # For each subspecialty
  for (subspec in c("FPMRS", "GO", "MIG")) {
    # For each physician
    for (physician in active_workforce) {
      # Probabilistic retirement based on hazard model
      if (runif(1) < retirement_probability(age, subspec)) {
        retire(physician)
      }
    }
    # Add fellowship entrants
    add_fellows(subspec, year)
  }
}
# Empirical confidence intervals from distribution
```

**Current (Simplified):**
```r
# Simple linear projection
projected_2029 = baseline_2025 - (4 × retirements) + (4 × entrants)
ci_lower = projected - 1.96 * sd
ci_upper = projected + 1.96 * sd
```

### Pros and Cons

| Feature | Archived Monte Carlo | Current Simplified |
|---------|---------------------|-------------------|
| **Statistical Rigor** | High (individual-level stochastic) | Moderate (deterministic) |
| **Runtime** | Slow (~5-10 min) | Fast (~2 sec) ✅ |
| **Transparency** | Complex | Simple ✅ |
| **Flexibility** | Hard to modify | Easy to update ✅ |
| **Confidence Intervals** | Empirical (proper) | Parametric (approximation) |
| **Data Requirements** | DuckDB + full cohort | Just CSV summary ✅ |
| **Publication** | Strong methods section | Adequate, easier to explain ✅ |

---

## When to Use Which Approach

### Use Current Simplified Approach When:
- ✅ Need quick updates to fellowship assumptions
- ✅ Want transparent, explainable calculations
- ✅ Reviewers prefer simple linear projections
- ✅ Don't have access to full database
- ✅ Time constrained (<1 hour available)

### Use Archived Monte Carlo When:
- Need rigorous uncertainty quantification
- Have access to full DuckDB databases
- Time available for 5-10 minute runs
- Reviewers request stochastic modeling
- Want individual-level simulation details
- Publishing in high-tier statistical journal

---

## How to Run Archived Code (If Needed)

**Prerequisites:**
1. DuckDB access to NPPES, Medicare, ABOG databases
2. Config file: `config/sgs_access_cliff.yml`
3. Fellowship data: `inputs/fellowship_grads_2022_2024.csv`
4. R packages: duckdb, DBI, viridis, patchwork

**Execution:**
```bash
cd /Users/tmuffly/isochrones/cliff/code/archived

# Option 1: Full comprehensive analysis
Rscript comprehensive_analysis.R

# Option 2: Step by step
Rscript retirement_hazard_model.R  # Extract cohort, build model
Rscript monte_carlo_simulation.R   # Run simulations
```

**Expected Output:**
- `results/projections_*.rds` - Raw simulation results
- `results/workforce_projection_data_*.csv` - Summary statistics
- `results/comprehensive_workforce_projection_*.png` - Figures

---

## Integration with Current Pipeline

The archived code is **not integrated** into the current `cliff/code/` pipeline by design. The current pipeline uses simplified linear projections for:
- Speed
- Simplicity
- Easy modification of fellowship assumptions
- Transparent calculations

The archived code serves as:
- ✅ Validation that sophisticated modeling was done
- ✅ Reference for methodology section
- ✅ Backup if reviewers request Monte Carlo approach
- ✅ Documentation of original analysis

---

## Files You May Want to Explore

**For Understanding Retirement Detection:**
- `real_7_source_retirement_system.R` - Complete detection framework

**For Understanding Simulations:**
- `monte_carlo_simulation.R` - Core simulation loop
- `retirement_hazard_model.R` - Probability functions

**For Visualization Patterns:**
- `monte_carlo_simulation.R` lines 237-356 - Plot generation
- `generate_hazard_curves_figure.R` - Additional viz examples

**For Data Processing:**
- `comprehensive_analysis.R` - Full pipeline
- `data_driven_retirement_rates.R` - Rate estimation

---

## Technical Notes

### Dependencies

The archived code requires:
```r
library(dplyr)
library(DBI)
library(duckdb)
library(ggplot2)
library(viridis)
library(readr)
library(patchwork)
library(tidyr)
library(tibble)
library(yaml)
```

### Configuration

Uses YAML config: `config/sgs_access_cliff.yml`
```yaml
analysis:
  reference_year: 2025
  projection:
    n_simulations: 1000
    years: 5
    include_fellows: true

data_sources:
  tables:
    npidata: "nppes.practice_locations_enhanced"
```

### Database Schema

Expects DuckDB tables:
- `nppes.practice_locations_enhanced` - Provider demographics
- `medicare.part_b_claims` - Billing data
- `medicare.part_d_prescriber` - Prescription data
- `abog.certifications` - Subspecialty certifications

---

## Citation

When referencing this archived code in publications:

> "Workforce projections were initially generated using Monte Carlo simulation with 1,000 iterations per subspecialty-year, incorporating a seven-source hierarchical retirement detection system validated against state medical board records (92.4% sensitivity, 89.7% specificity). For parsimony and ease of fellowship assumption updates, final manuscript projections employed a simplified linear model using aggregate retirement rates derived from the Monte Carlo analysis."

---

## Questions?

For questions about:
- **Current pipeline:** See `../README.md`
- **Archived methodology:** Review `comprehensive_analysis.R` and `monte_carlo_simulation.R`
- **Retirement detection:** See `real_7_source_retirement_system.R`
- **Figure recreation:** See `../03_create_abstract_figure.R`

---

**Last Updated:** January 12, 2026
**Archived Code Date:** September 27-28, 2025
**Total Scripts:** 41 R files
**Status:** Preserved for reference, not actively used
