# demand_lifecourse/ — reproductive life-course demand model

A self-contained subsystem that reframes cliff's demand side around the
**obstetric life course**: cumulative vaginal-delivery exposure by birth cohort
drives pelvic-floor disease burden, which (via a care pathway and staffing
conversion, per Zarek) drives urogynecology workforce demand. BMI is a risk
modifier, not the engine. It does **not** touch the existing supply/manuscript
pipeline (`code/00_RUN_ALL.R`).

- **Design & decisions:** [`../DEMAND_LIFECOURSE_MODEL_SPEC.md`](../DEMAND_LIFECOURSE_MODEL_SPEC.md)
- **Cited parameters & gaps:** [`PARAMETERS_EVIDENCE.md`](PARAMETERS_EVIDENCE.md)

## Built so far

| Module | Status | What it does |
|---|---|---|
| `01_population.R` | ✅ done | Female population by single-year age × year (NPP SSOT); adds `birth_cohort` |
| `02_birth_history.R` | ✅ done | Derives mean vaginal/cesarean deliveries per woman by birth cohort |
| `params/*.csv` | ✅ cited | Dose-response, modifiers, care pathway, staffing (each row sourced) |
| `data/*.csv` | ✅ cited | Cesarean rate by year (1965–2024); completed parity by cohort |
| `03_pelvic_floor_risk.R` | ⬜ next | Exposure × modifiers → condition prevalences (fixed external ORs) |
| `04_condition_transitions.R` | ⬜ | Incidence / progression / recurrence / mortality |
| `05_care_seeking.R` | ⬜ | Recognition, seeking, referral (calibrate to observed volume) |
| `06_service_use.R` | ⬜ | Treatment mix × intensity → annual service units |
| `07_staffing_conversion.R` | ✅ done | Service volumes → required FTE via CMS work RVUs + calibrated wrvu-per-FTE (ported from simulation R/17/R/23) |
| `08_scenarios.R` | ⬜ | Baseline, mode-of-delivery, reduced barriers, prevention, substitution |
| `09_validation.R` | ⬜ | Back-cast vs Nygaard / Medicare / SWAN–WHI–Gyhagen |

## Quick check

```r
source("demand_lifecourse/01_population.R")
source("demand_lifecourse/02_birth_history.R")
cohort_vaginal_exposure(c(1935, 1965, 1985))
# mean vaginal deliveries/woman: ~2.9 (1935) -> ~1.5 (1965) -> ~1.3 (1985)
```

Tests: `tests/testthat/test-demand-lifecourse.R`.

## Honesty notes

- The vaginal/cesarean split is **derived** (parity × period cesarean fraction);
  no off-the-shelf per-woman joint distribution exists — refine with NSFG microdata.
- Medium-confidence dose-response rows (Hendrix, Mant) need full-text verification.
- Services→FTE conversion is now **CMS-work-RVU based** (`07_staffing_conversion.R`,
  `params/urps_service_workload_rvu.csv`; ported from simulation R/17/R/23). The
  productivity denominator is *solved* from a base-year anchor, not assumed. The
  earlier "visits per FTE" placeholder gap is closed; the full provider-delegation
  / setting engine remains in simulation (SSOT).
