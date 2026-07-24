# URPS Supply–Demand Model: Methods Language & Variable References

Companion to the effective-adequacy explorer (`cliff/shiny_urps_adequacy/`) and the
Module A / capacity-gap exhibits. Terminology follows the AAMC physician
workforce-projection convention.

## Manuscript methods sentence (AAMC alignment)

> Following the AAMC workforce-projection convention, we expressed physician supply as
> full-time-equivalent clinical capacity and modeled a status-quo demand scenario in which
> current utilization rates were held constant as the population changed. Because no
> validated estimate of the current national urogynecology shortfall exists, supply and
> utilization-equivalent demand were normalized to balance in 2025; subsequent positive gaps
> therefore represent the additional effective FTE capacity required to maintain 2025 realized
> utilization rather than an estimate of current unmet clinical need.

## Capacity-gap definition

Capacity gap(t) = demand-equivalent effective FTEs(t) − effective supply FTEs(t)

- **Positive** — additional effective FTEs required to preserve 2025 realized utilization.
- **Zero** — projected supply matches status-quo utilization.
- **Negative** — projected supply exceeds the utilization-equivalent requirement (surplus).

Demand-equivalent FTEs(t) = effective supply(2025) × [women 65+(t) / women 65+(2025)] × (demand multiplier).
The 2025 normalization to balance is an assumption, **not** a finding that the 2025 workforce is
adequate; the geographic analysis (Module D) shows substantial maldistribution. The AAMC-style
band reflects **retirement timing alone** (Retire Early −2 yr to Retire Late +2 yr); entrant,
attrition, and attribution uncertainty are held fixed for the headline band and belong in a
factorial sensitivity appendix.

## Terminology (use consistently; do not switch between synonyms)

| Concept | Canonical label |
|---|---|
| Demographic demand at held-constant utilization | **Demand (Status Quo)** |
| Age-productivity × clinical-time weighted supply | **Supply, effective FTE** |
| Unweighted physician count | **Supply, headcount** |
| Demand-equivalent minus effective supply | **Capacity gap** |
| Supply growth ÷ demand growth (2025 = 1.00) | **Adequacy ratio** |

"Shortfall" is reserved for describing the AAMC report itself (Exhibits ES-1, 2, 8, …); our
conditional-on-2025-balance chart uses "capacity gap."

AAMC FTE definition (cite for the effective-FTE construct): *"an FTE is defined for each specialty
category as the average weekly patient-care hours for that specialty category"* (AAMC/GlobalData 2024).

## Variable sources & links

| Variable | Source | Link |
|---|---|---|
| Urogynecologists, OB/GYN pathway | American Board of Obstetrics & Gynecology (ABOG) board certification | https://www.abog.org |
| Urogynecologists, urology pathway | American Board of Urology (ABU) verification portal | https://www.abu.org |
| Baseline active workforce (1,339) | This study: ABOG + ABU rosters, active in Medicare / clinical practice | — (derived) |
| Age-productivity curve (work by age) | CMS Medicare Physician & Other Practitioners, by Provider and Service (2013–2024) | https://data.cms.gov/provider-summary-by-type-of-service/medicare-physician-other-practitioners-by-provider-and-service |
| Departure / retirement hazard by age band | This study: Medicare activity, board-certification lapse, NPPES, death records | — (derived) |
| Aging-women demand driver: women 65+, 2025-2050 | U.S. Census Bureau, **2023 National Population Projections**, main series (np2023_d1_mid; low/hi for the band). Produced by `scripts/urps_supply_demand_national_2026-07-23.R`. **Supersedes P25-1144** (2017-vintage; 46.9M women 65+ in 2050) — the 2023 revision is lower (44.8M by 2050) for COVID mortality and reduced immigration/fertility. | https://www.census.gov/programs-surveys/popproj.html |
| Geographic denominator (Module D map): women 65+ by county | U.S. Census Bureau, ACS 5-year, Table B01001 (Sex by Age); cross-sectional, not the temporal driver | https://data.census.gov/table/ACSDT5Y2023.B01001 |
| Pelvic floor disorder prevalence (context) | Nygaard et al., JAMA 2008;300(11):1311–16; Wu et al., Obstet Gynecol 2009 | https://jamanetwork.com/journals/jama/fullarticle/182579 · https://pubmed.ncbi.nlm.nih.gov/19935030/ |
| Procedure-based demand (Modules B/C) | CMS Physician/Supplier Procedure Summary (PSPS) & Medicare Part B | https://www.cms.gov/data-research/statistics-trends-reports/medicare-provider-utilization-payment-data |
| Procedure codes (HCPCS/CPT) | 57288 sling; 57282 apical suspension (colpopexy); 51728 complex cystometrogram; 52287 bladder chemodenervation (onabotulinumtoxinA) | https://www.cms.gov/medicare/coding-billing/healthcare-common-procedure-system |
| Retirement age default (65), FTE definition, scenario names | AAMC / GlobalData 2024, *The Complexities of Physician Supply and Demand: Projections From 2021 to 2036* | https://www.aamc.org/media/75236/download |

## AAMC scenario mapping (what we adopt vs. omit)

- **Adopted:** Demand (Status Quo); Supply scenarios varying retirement age (Retire Early / Status
  Quo / Retire Late, ±2 yr); FTE as the supply unit; the range-not-point presentation.
- **Omitted (do not apply to a single subspecialty):** AAMC demand scenarios for care-delivery
  models — Managed Care, Retail Clinics, Population Health, APRN/PA Moderate, APRN/PA High; and the
  0%/1% GME-growth supply variants (our entrant count is modeled directly, not via national GME).
