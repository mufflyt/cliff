# Archived Code Discovery Report

**Date:** January 12, 2026
**Trigger:** SGS abstract submission figure `workforce_crisis_labeled.png`
**Location Found:** `/docs/isochrones_deep_archive/2025-12-07/legacy_matching_strategies_2025-12-05/research_forecasting/comprehensive_forecasting/`

---

## Figure Found

**File:** `workforce_crisis_labeled.png`
**Title:** "Gynecologic Surgical Subspecialty Workforce Crisis"
**Subtitle:** "5-year projections with 90% confidence intervals • Labels show total change 2026-2030"

**Content:**
- **Time Period:** 2026-2030 (5 years)
- **Confidence Intervals:** 90% (vs our current 95%)
- **Subspecialties:**
  - URPS (old term for FPMRS): -7.8% decline
  - Gynecologic Oncology: -8.2% decline
  - MIGS: +8.4% growth

**Visual Style:**
- Three colored trajectories with confidence ribbons
- Pink (GO), Purple (URPS/FPMRS), Orange (MIGS)
- Year-by-year projections with endpoints labeled
- Professional formatting suitable for abstract submission

---

## Archived Code Located

**Base Directory:** `/Users/tmuffly/isochrones/R/@archive/legacy_matching_strategies_2025-12-05/research_forecasting/comprehensive_forecasting/`

### Key Simulation Scripts

1. **monte_carlo_simulation.R** (16KB)
   - Main Monte Carlo simulation engine
   - 1,000 iterations per subspecialty/year
   - Retirement hazard modeling

2. **ultimate_monte_carlo_with_confidence_weighting.R** (9.3KB)
   - Advanced version with confidence-weighted retirement detection
   - 7-source hierarchical retirement system
   - Subspecialty-specific modeling

3. **retirement_hazard_model.R** (13KB)
   - Hazard function estimation
   - Age-stratified retirement probabilities
   - Subspecialty-specific rates

4. **real_7_source_retirement_system.R** (30KB)
   - Comprehensive 7-source detection framework
   - Confidence weighting algorithm
   - Validation against state medical boards

### Statistical Summary Scripts

5. **enhanced_statistical_summaries.R** (11KB)
   - Generates variance measures from simulation data
   - Creates markdown reports
   - Calculates proper SDs from Monte Carlo runs

6. **generate_workforce_statistical_summaries.R** (8.4KB)
   - Statistical summary generation
   - Confidence interval calculations
   - Subspecialty-specific metrics

### Data Analysis Scripts

7. **data_driven_retirement_rates.R** (17KB)
   - Empirical retirement rate estimation
   - Multi-source integration
   - Age-stratified analysis

8. **analyze_subspecialty_retirement_rates.R** (7.6KB)
   - Subspecialty-specific retirement patterns
   - Comparison across specialties
   - Validation checks

### Visualization Scripts

9. **generate_hazard_curves_figure.R** (9.6KB)
   - Retirement hazard visualization
   - Age-stratified curves
   - Subspecialty comparisons

### Comprehensive Analysis

10. **comprehensive_analysis.R** (13KB)
    - Full pipeline orchestration
    - Data loading and preparation
    - Results consolidation

11. **run_specialty_analysis.R** (18KB)
    - Specialty-specific workflow
    - Fellowship integration
    - Projection generation

---

## Data Files Found

**Location:** Same directory

### Simulation Results

- `real_7source_retirement_results_*.csv` (multiple timestamped versions)
  - Full 7-source detection results
  - 526KB each (largest/most complete)

- `enhanced_comparison_table_20250928_030546.csv` (254B)
  - **This is the file we're currently using in cliff/code!**
  - Contains baseline, projected workforce, retirement rates
  - Fellowship entrants data

### Summary Tables

- `ultimate_workforce_summary_20250928_035635.csv` (698B)
  - Consolidated projections
  - Replacement ratios
  - Confidence intervals

- `workforce_summary_table_*.csv` (multiple versions)
  - Various summary tables
  - Different projection scenarios

### Model Outputs

- `confidence_weighted_hazard_model_20250928_035356.rds` (792B)
  - Saved hazard model
  - Confidence weights
  - Subspecialty-specific parameters

---

## Missing: Figure Generation Code

**Status:** ❌ NOT FOUND

The specific R script that generated `workforce_crisis_labeled.png` is **not in the repository**.

**Likely Explanation:**
- Figure was generated interactively in RStudio
- Code was in an unsaved script or console commands
- Only the output PNG was preserved

**Evidence:**
- No R script contains "workforce_crisis" filename
- No script contains the exact figure title
- Figure timestamp (Sept 28, 00:26) doesn't match any script timestamps

---

## What We Can Recover

### ✅ Available

1. **Complete Monte Carlo Simulation Engine**
   - 1,000 iteration simulations
   - Confidence interval calculations
   - Subspecialty-specific modeling

2. **7-Source Retirement Detection System**
   - Hierarchical evidence integration
   - Confidence weighting
   - State medical board validation (92.4% sensitivity)

3. **Raw Simulation Data**
   - Full results from September 2025 runs
   - Can regenerate all statistics
   - Can create new visualizations

4. **Statistical Framework**
   - Proper variance estimation
   - Monte Carlo distribution analysis
   - Confidence interval methodology

### ❌ Not Available

1. **Exact Figure Code**
   - Specific ggplot2 commands for workforce_crisis figure
   - Color palette specifications
   - Annotation placement logic

2. **Interactive Pipeline**
   - No master script to run everything
   - Scripts reference each other but no orchestration
   - Would require manual step-by-step execution

---

## Comparison: Archived vs Current Implementation

| Feature | Archived Code | Current cliff/code | Notes |
|---------|---------------|-------------------|-------|
| **Time Period** | 2026-2030 (5 years) | 2025-2029 (4 years) | We use more recent baseline |
| **Confidence Intervals** | 90% | 95% | More conservative |
| **Simulation** | 1,000 Monte Carlo iterations | **Simplified linear model** | ❗ Lost complexity |
| **Fellowship Data** | 47, 60, 51 (original) | 60, 50, 45 (updated) | Reflects 2026 changes |
| **Retirement Detection** | 7-source hierarchical | Not re-run | Uses archived results |
| **Uncertainty** | Empirical from simulations | **Parametric (mean ± 1.96*SD)** | Simpler approach |

### Key Difference

**Archived System:**
```r
# Monte Carlo: Simulate 1,000 futures
for (i in 1:1000) {
  simulate_retirements()
  simulate_entrants()
  calculate_workforce()
}
# Empirical distribution → confidence intervals
```

**Current System:**
```r
# Simple linear projection
projected_2029 = baseline_2025 - (4 × retirements) + (4 × entrants)
ci_lower = projected - 1.96 * sd
ci_upper = projected + 1.96 * sd
```

---

## Recommendation: Which Code to Integrate?

### Option 1: Keep Simple (Current Approach) ✅ RECOMMENDED
**Pros:**
- Fast (2 seconds vs minutes)
- Easy to understand and modify
- Transparent calculations
- Good enough for manuscript

**Cons:**
- No individual-level stochasticity
- Assumes constant rates
- No complex uncertainty modeling

### Option 2: Integrate Full Monte Carlo System
**Pros:**
- Rigorous statistical framework
- Captures stochastic variability
- Publishable methodology
- More defensible confidence intervals

**Cons:**
- Much slower (~5-10 minutes)
- Requires DuckDB access to retirement data
- Complex dependencies
- Harder to modify fellowship assumptions

### Option 3: Hybrid Approach
**Pros:**
- Keep simple projections for quick updates
- Add Monte Carlo option for manuscript validation
- Best of both worlds

**Cons:**
- More code to maintain
- Two systems to document

---

## What to Copy to cliff/code?

### If You Want Monte Carlo Simulation

**Minimal Set (just simulation):**
1. `monte_carlo_simulation.R` - Core simulation engine
2. `retirement_hazard_model.R` - Hazard functions
3. Modify to use your `enhanced_comparison_table` CSV

**Full Set (complete system):**
1. All scripts listed above (42 R files)
2. Create master pipeline script
3. Add documentation
4. Test thoroughly

**Estimated Effort:**
- Minimal: 2-4 hours of adaptation/testing
- Full: 1-2 days of integration work

---

## Files to Copy for Figure Recreation

To recreate something similar to `workforce_crisis_labeled.png`:

**Start with:**
- Current `cliff/code/02_create_figures.R` (already similar!)
- Modify to add:
  - 90% confidence intervals (change 1.96 to 1.645)
  - Different color palette (pink/purple/orange)
  - Endpoint labels with percentage changes
  - 5-year projection (2026-2030) if desired

**Or extract from archived scripts:**
- Check `generate_hazard_curves_figure.R` for ggplot patterns
- Check test scripts in `tests/testthat/test_visualization.R`

---

## Action Items

### Immediate (No Code Changes)

- [x] Document what was found
- [x] Compare archived vs current approach
- [ ] Decide: simple vs Monte Carlo?

### If Keeping Simple Approach

- [ ] Update README to reference archived code location
- [ ] Note methodology differences in manuscript
- [ ] Cite "simplified from Monte Carlo" in methods

### If Integrating Monte Carlo

- [ ] Copy key simulation scripts to `cliff/code/`
- [ ] Create `03_monte_carlo_simulation.R` (optional)
- [ ] Adapt to read `enhanced_comparison_table` CSV
- [ ] Test with current fellowship assumptions
- [ ] Update documentation

### If Just Recreating Figure Style

- [ ] Modify `02_create_figures.R` with:
  - 90% CI option (parameter)
  - Pink/purple/orange colors
  - Endpoint percentage labels
  - Title format from SGS figure

---

## Bottom Line

**Good News:** 🎉
- Found extensive archived simulation code
- Found the exact data file you're using
- Current approach is simpler but valid

**Reality Check:** ⚠️
- Exact figure code is lost
- Full Monte Carlo system is complex
- Current simple approach is publishable

**Recommendation:**
1. **Keep current simple system** for the manuscript
2. **Document** that it's a simplified linear projection
3. **Cite** the archived Monte Carlo work in methods
4. **If reviewer asks:** Point to archived code as validation

Your current implementation is good enough for publication. The archived code proves you did rigorous modeling, but the simplified version is easier to explain and defend.

---

**Report Prepared By:** Claude Code
**Date:** January 12, 2026
**Status:** Complete discovery, awaiting user decision on integration
