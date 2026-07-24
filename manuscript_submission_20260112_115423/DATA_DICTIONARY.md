# Data Dictionary for Manuscript Submission

---

## File: workforce_projections_consolidated.csv

**Description:** Primary workforce projection data with updated fellowship assumptions

**Columns:**
- `subspecialty` - Full subspecialty name
- `subspecialty_abbrev` - Abbreviation (FPMRS, GO, MIG)
- `baseline_2025` - Active physicians in 2025
- `projected_2029` - Projected active physicians in 2029
- `sd_2029` - Standard deviation of 2029 projection
- `ci95_lower` - Lower bound of 95% confidence interval
- `ci95_upper` - Upper bound of 95% confidence interval
- `percent_change` - Percent change from 2025 to 2029
- `annual_retirement_rate` - Percentage retiring annually
- `avg_annual_retirements` - Average retirements per year
- `annual_entrants` - Fellowship graduates entering workforce annually
- `replacement_ratio` - Ratio of entrants to retirements
- `replacement_assessment` - Categorical assessment (Adequate/Marginal/Insufficient)
- `fellowship_total_5yr` - Total fellows over 5 years
- `total_retirements_4yr` - Total retirements over 4-year projection period

**Rows:** 3 (one per subspecialty)

---

## File: scenario_comparison.csv

**Description:** Fellowship sensitivity analysis comparing 5 scenarios

**Columns:**
- All columns from workforce_projections_consolidated.csv
- `scenario` - Scenario identifier (default, optimistic, pessimistic, historical_2025, status_quo)

**Fellowship Assumptions by Scenario:**
- `default`: FPMRS 60, GO 50, MIG 45
- `optimistic`: FPMRS 70, GO 60, MIG 55
- `pessimistic`: FPMRS 50, GO 40, MIG 35
- `historical_2025`: FPMRS 47, GO 60, MIG 51
- `status_quo`: FPMRS 55, GO 55, MIG 45

**Rows:** 15 (3 subspecialties × 5 scenarios)

---

## File: retirement_sensitivity.csv

**Description:** Retirement threshold sensitivity analysis with 7 scenarios

**Columns:**
- `subspecialty` - Subspecialty abbreviation
- `subspecialty_abbrev` - Same as subspecialty
- `baseline_workforce` - 2025 baseline
- `projected_workforce` - 2029 projection
- `percent_change` - Percent change 2025→2029
- `annual_entrants` - Fellowship entrants (from default scenario)
- `avg_annual_retirements` - Retirements per year (adjusted by scenario)
- `replacement_ratio` - Entrants/retirements
- `avg_retirement_rate` - Original retirement rate (%)
- `baseline_rate` - Original rate before adjustment
- `adjusted_rate` - Rate after threshold adjustment
- `scenario_id` - Scenario identifier
- `scenario_name` - Human-readable scenario name
- `retirement_adjustment` - Proportion adjustment applied (-0.30 to +0.30)

**Retirement Scenarios:**
- `baseline`: Current rates (0% adjustment)
- `threshold_minus_1yr`: Stricter detection (+15% rates)
- `threshold_plus_1yr`: Looser detection (-15% rates)
- `conservative_higher`: +10% rates
- `conservative_lower`: -10% rates
- `aggressive_higher`: +30% rates
- `aggressive_lower`: -30% rates

**Rows:** 21 (3 subspecialties × 7 scenarios)

---

## File: table1_physicians.csv

**Description:** Physician demographic and practice characteristics for three subspecialties

**Columns:**
- `Subspecialty` - Subspecialty category (FPMRS (Urogynecology), Gynecologic Oncology, MIGS)
- `Age` - Physician age in years (continuous)
- `Years in Practice` - Years since board certification (continuous)
- `Gender` - Physician gender (Female, Male)
- `ACOG District` - ACOG geographic district (1-12)
- `Practice Size` - Practice size category (Solo, Small, Medium, Large, Very Large, Unknown)
- `Multi-Location Practice` - Multi-location practice indicator (Yes, No)
- `Practice Type` - Practice type category (Single Specialty, OB/GYN Dedicated, Multi-Specialty, Unknown)
- `Bills Medicare` - Medicare billing status (Yes, No, Opted Out)

**Practice Size Definitions:**
- Solo (1): 1 physician (257 total, 8.4%)
- Small (2-5): 2-5 physicians (325 total, 10.6%)
- Medium (6-20): 6-20 physicians (642 total, 20.9%)
- Large (21-100): 21-100 physicians (1,484 total, 48.4%)
- Very Large (>100): >100 physicians (331 total, 10.8%)
- Unknown: 27 total (0.9%)

**Practice Type Definitions:**
- Single Specialty: Subspecialty-focused practices (492 total, 16.0%)
- OB/GYN Dedicated: OB/GYN only practices (460 total, 15.0%)
- Multi-Specialty: Multiple medical specialties (147 total, 4.8%)
- Unknown: 1,967 total (64.2%)

**Medicare Participation:**
- Yes: Bills Medicare (2,597 total, 84.7%)
- No: Does not bill Medicare (447 total, 14.6%)
- Opted Out: Opted out of Medicare (22 total, 0.7%)

**Rows:** 3,066 (1,196 FPMRS + 1,197 GO + 673 MIGS)

**Source:** ABOG-NPI matched data with enrichment pipeline (January 2026)

**Use:** Baseline demographic characteristics for Table 1 in manuscript

---

## Data Source and Validation

**Baseline Data:**
- Source: 7-source hierarchical retirement detection system
- Validation: 92.4% sensitivity, 89.7% specificity vs state medical boards
- Reference year: 2025
- Database: DuckDB with NPPES, Medicare, ABOG data

**Fellowship Data:**
- Source: ACGME fellowship position allocations (2026)
- Updated: January 2026

**Retirement Rates:**
- FPMRS: 4.4% annually (95% CI: 3.9-4.9%)
- GO: 5.2% annually (95% CI: 4.7-5.7%)
- MIG: 3.4% annually (95% CI: 2.9-3.9%)

**Projection Method:**
- Linear approximation: projected = baseline - (4 × retirements) + (4 × entrants)
- Validated against Monte Carlo simulation (1,000 iterations)
- Mean agreement: 4.51%

---

## Missing Data

**No missing data:** All fields complete for all rows

**Data Quality Checks:**
- ✓ No missing values in critical columns
- ✓ Replacement ratios mathematically correct
- ✓ Confidence intervals reasonable (<50% of mean)
- ✓ All workforce projections positive

---

## Usage Notes

**For analysis:**
- Use `workforce_projections_consolidated.csv` for main results
- Use `scenario_comparison.csv` for fellowship sensitivity
- Use `retirement_sensitivity.csv` for retirement threshold sensitivity

**For visualization:**
- All data files ready for import into R, Python, or Excel
- CSV format with header row
- UTF-8 encoding

**For reproducibility:**
- See `documentation/fellowship_assumptions.yml` for exact parameters
- See `documentation/metadata.json` for pipeline version and git commit

