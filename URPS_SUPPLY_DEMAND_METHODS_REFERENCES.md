# URPS Supply–Demand Model: Methods Language & Variable References

Companion to the effective-adequacy explorer
(`cliff/shiny_urps_adequacy/`) and the Module A / capacity-gap exhibits.
Terminology follows the AAMC physician workforce-projection convention.

## Manuscript methods sentence (AAMC alignment)

> Following the AAMC workforce-projection convention, we expressed
> physician supply as productivity-adjusted clinical capacity
> equivalents (a productivity-weighted index normalized to a 2025
> reference physician, distinct from an hours-based FTE) and modeled a
> status-quo demand scenario in which current utilization rates were
> held constant as the population changed. Because no validated estimate
> of the current national urogynecology shortfall exists, supply and
> utilization-equivalent demand were normalized to balance in 2025;
> subsequent positive gaps therefore represent the additional capacity
> equivalents required to maintain 2025 realized utilization rather than
> an estimate of current unmet clinical need.

## Conditional capacity-gap definition

Conditional capacity gap(t) = demand-equivalent capacity equivalents(t)
− supply capacity equivalents(t)

- **Positive** — additional capacity equivalents required to preserve
  2025 realized utilization.
- **Zero** — projected supply matches status-quo utilization.
- **Negative** — projected supply exceeds the utilization-equivalent
  requirement (**conditional capacity margin**; do not call this a
  “surplus,” which is reserved for an external-benchmark comparison).

Demand-equivalent capacity equivalents(t) = supply(2025) × \[women
65+(t) / women 65+(2025)\] × (demand multiplier). The 2025 normalization
to balance is an assumption, **not** a finding that the 2025 workforce
is adequate; the geographic analysis (Module D) shows substantial
maldistribution. The AAMC-style band reflects **retirement timing
alone** (Retire Early −2 yr to Retire Late +2 yr); entrant, attrition,
and attribution uncertainty are held fixed for the headline band and
belong in a factorial sensitivity appendix.

## Terminology (use consistently; do not switch between synonyms)

| Concept | Canonical label |
|----|----|
| Demographic demand at held-constant utilization | **Demand (Status Quo)** |
| Productivity-weighted supply, normalized to a 2025 reference physician (**may exceed headcount**) | **Supply, productivity-adjusted capacity equivalents** |
| Hours-based clinical FTE, bounded ≤1.0 per physician (**not currently computed** — needs patient-care-hours data) | **Supply, clinical FTE (hours-based)** |
| Unweighted physician count | **Supply, headcount** |
| Demand-equivalent minus productivity-adjusted supply, conditional on 2025 balance | **Conditional capacity gap** |
| Supply growth ÷ realized-utilization demand growth (2025 = 1.00) | **Relative capacity ratio** |

### Terminology contract (do not use a term outside its row)

| Quantity | Allowed wording | Never call it |
|----|----|----|
| Supply growth ÷ realized-utilization demand growth (2025 = 1.00) | **Relative capacity ratio** | “adequacy ratio” |
| Demand-equivalent capacity equivalents − supply capacity equivalents (conditional on 2025 balance) | **Conditional capacity gap** / **conditional capacity margin** (if negative) | “shortage” / “surplus” |
| Supply ÷ an **independently justified** need target | **Adequacy** | — (this is the ONLY licensed use of “adequate”) |
| (Independently justified need) − supply, using an **external benchmark** | **Shortage** | — |

- **“FTE” naming caution.** The productivity-weighted quantity is
  normalized to a 2025 reference physician and **can exceed 1.0 per
  physician / exceed headcount**; that is a *capacity-equivalent index*,
  not an hours-based FTE. Do not label it “FTE” unqualified. Reserve
  “clinical FTE” for an hours-based quantity bounded at 1.0 (which this
  model does not yet compute).
- **“Shortfall”** is reserved for describing the AAMC report itself
  (Exhibits ES-1, 2, 8, …); our conditional-on-2025-balance chart uses
  “conditional capacity gap.”
- **Code/app naming lag (flagged, Tier 3):** `model.R`/`app.R` still use
  `adeq_eff`/“Adequacy ratio” and `shortfall`/“shortage” in code and UI
  text. Reconciling those identifiers with this contract is a Tier-3
  change (touches code) and is deliberately **not** done in this
  docs-only pass.

AAMC FTE definition (the hours-based construct, for contrast): *“an FTE
is defined for each specialty category as the average weekly
patient-care hours for that specialty category”* (AAMC/GlobalData 2024).
Our productivity-adjusted capacity equivalents are a *different*
construct and must not be conflated with this hours-based FTE.

## Variable sources & links

| Variable | Source | Link |
|----|----|----|
| Urogynecologists, OB/GYN pathway | American Board of Obstetrics & Gynecology (ABOG) board certification | <https://www.abog.org> |
| Urogynecologists, urology pathway | American Board of Urology (ABU) verification portal | <https://www.abu.org> |
| Baseline active workforce (1,339) | This study: ABOG + ABU rosters, active in Medicare / clinical practice | — (derived) |
| Age-productivity curve (work by age) | CMS Medicare Physician & Other Practitioners, by Provider and Service (2013–2024) | <https://data.cms.gov/provider-summary-by-type-of-service/medicare-physician-other-practitioners-by-provider-and-service> |
| Departure / retirement hazard by age band | This study: Medicare activity, board-certification lapse, NPPES, death records | — (derived) |
| Aging-women demand driver: women 65+, 2025-2050 | U.S. Census Bureau, **2023 National Population Projections**, main series (np2023_d1_mid; low/hi for the band). Produced by `scripts/urps_supply_demand_national_2026-07-23.R`. **Supersedes P25-1144** (2017-vintage; 46.9M women 65+ in 2050) — the 2023 revision is lower (44.8M by 2050) for COVID mortality and reduced immigration/fertility. | <https://www.census.gov/programs-surveys/popproj.html> |
| Geographic denominator (Module D map): women 65+ by county | U.S. Census Bureau, ACS 5-year, Table B01001 (Sex by Age); cross-sectional, not the temporal driver | <https://data.census.gov/table/ACSDT5Y2023.B01001> |
| Pelvic floor disorder prevalence (context) | Nygaard et al., JAMA 2008;300(11):1311–16; Wu et al., Obstet Gynecol 2009 | <https://jamanetwork.com/journals/jama/fullarticle/182579> · <https://pubmed.ncbi.nlm.nih.gov/19935030/> |
| Procedure-based demand (Modules B/C) | CMS Physician/Supplier Procedure Summary (PSPS) & Medicare Part B | <https://www.cms.gov/data-research/statistics-trends-reports/medicare-provider-utilization-payment-data> |
| Procedure codes (HCPCS/CPT) | 57288 sling; 57282 apical suspension (colpopexy); 51728 complex cystometrogram; 52287 bladder chemodenervation (onabotulinumtoxinA) | <https://www.cms.gov/medicare/coding-billing/healthcare-common-procedure-system> |
| Retirement age default (65), FTE definition, scenario names | AAMC / GlobalData 2024, *The Complexities of Physician Supply and Demand: Projections From 2021 to 2036* | <https://www.aamc.org/media/75236/download> |

## AAMC scenario mapping (what we adopt vs. omit)

- **Adopted:** Demand (Status Quo); Supply scenarios varying retirement
  age (Retire Early / Status Quo / Retire Late, ±2 yr); FTE as the
  supply unit; the range-not-point presentation.
- **Omitted (do not apply to a single subspecialty):** AAMC demand
  scenarios for care-delivery models — Managed Care, Retail Clinics,
  Population Health, APRN/PA Moderate, APRN/PA High; and the 0%/1%
  GME-growth supply variants (our entrant count is modeled directly, not
  via national GME).

------------------------------------------------------------------------

## Four-module framework (nomenclature and what each module does)

The explorer and manuscripts decompose “is the urogynecology workforce
adequate?” into four modules. This section fixes the vocabulary and
states, per module, the methodological refinements adopted from the
2026-07-23 literature review. It changes no code, inputs, outputs, or
published numbers — it is documentation.

### Module A — Supply as productivity-adjusted capacity equivalents (who is working, and how much)

Supply is built from two **separable** quantities that must not be
collapsed into one undifferentiated “FTE”:

1.  **Participation** — the probability a physician is clinically
    active, governed by the age-band **departure hazard** (survival
    cohort). The frozen manuscript scenario collapses this to a hard
    age-65 departure; the observed age-band hazard (physicians working
    past 65) is retained as a comparison run.
2.  **Clinical productivity** — workload *per active physician-year*,
    governed by the age-productivity curve `rel_to_peak(age)` (Medicare
    work-proxy, normalized so 2025 averages 1.0).

Supply capacity equivalents(t) = Σ_age \[ P(active \| age, t) ×
clinical-productivity(age) × pathway weight \]. Reporting
`Supply, productivity-adjusted capacity equivalents` and
`Supply, headcount` side by side makes the participation×productivity
gap visible. **This capacity-equivalent index is normalized to a 2025
reference physician and can exceed 1.0 per physician / exceed
headcount** when the workforce is younger than the 2025 reference
(documented precedent: Fraher 2013). It is therefore **not** an
hours-based FTE and must not be labeled “FTE” unqualified; an
hours-based clinical FTE (bounded ≤1.0) would be a separate quantity
requiring patient-care-hours data the model does not currently use.

*Second-packet evidence:* Plaska 2025 shows urology-trained URPS
physicians spend only ~49% of encounters on URPS work and run a 3.9:1
clinic-to-procedure ratio (1.5:1–111:1 by diagnosis) — so a single
`uro_fte` scalar understates the clinic/general-urology split; where
feasible, allocate capacity by service family (clinic / diagnostic /
office procedure / surgery) rather than one procedural constant.
Rotenstein 2026 (female-vs-male attrition adj HR 1.43; women exit at
median 49 vs 64) motivates a **sex-stratified departure-hazard
sensitivity** for the increasingly female OB-GYN-pathway entrant pool —
kept as a sensitivity because it is national and all-specialty; the
empirical URPS Medicare-disappearance hazard remains primary.

### Module B — Demand (two clearly-labeled constructs, never conflated)

- **Realized-utilization demand (primary, “Demand — Status Quo”):** the
  FTE capacity required to **maintain 2024/2025 realized Medicare FFS
  utilization** as the population changes. This is the headline series
  and is normalized to balance in 2025. It is explicitly **not** a need
  estimate; observed utilization reflects supply, access, and practice
  patterns, not disease burden.

- **Prevalence-based need (bracketing sensitivity, not the headline):**
  what the workforce would have to be if care-seeking rose toward
  underlying pelvic-floor-disorder prevalence. Anchors, used only as
  directional context: Mou 2022 (only ~37% of symptomatic women use
  *any* PFD service), Kirby 2013 (+35% PFD-care demand 2010→2030), Wu
  2009 (PFD prevalence 28.1M→43.8M by 2050).

  **Do NOT convert the 37% into a direct 1/0.37 (≈2.7×)
  specialist-demand multiplier.** “Used any health service” is not
  “needed urogynecology care,” not “needed surgery,” not “needed a
  board-certified urogynecologist,” and not “needed the same service mix
  as current users.” The 37% supports only the qualitative claim that *a
  large gap exists between symptoms and realized service use*. Any
  quantitative extrapolation is an **illustrative upper-bound access-gap
  scenario** that requires explicit, separately-sourced referral,
  treatment, and specialty-attribution probabilities; defer the number
  until those exist.

**Discipline:** report realized-utilization demand as the headline and
prevalence-need as a labeled, directional sensitivity. Never present a
prevalence-need number as though it were observed demand, and never turn
a service-utilization rate into a specialist-FTE multiplier without the
intervening referral/treatment/attribution probabilities.

*Second-packet refinement (age-specific demand):* the headline applies
women-65+ growth uniformly to every service, but Wu 2014 shows the age
curves differ by procedure — SUI surgery is **bimodal** (~age 46 and
~70-71) while POP surgery **rises progressively** to ~71-73 (lifetime
primary-surgery risk 20.0% by age 80). A defensible Module-B sensitivity
weights each procedure family *p* by its Wu age profile `r^Wu(p,a)`
across the population age structure, **normalized so the modeled 2024
total still equals the observed CMS volume** `V(p,2024)` — i.e., use Wu
for the *relative* age shape only, keeping the CMS 2024 count as the
empirical anchor. This is a Tier-3 code change; documented here, not
implemented.

### Module C — Delivery mix and substitutable capacity (“who can actually do each procedure”)

Not a single overall “urogynecologist share.” Estimate a **per-procedure
substitution profile** (share of each service delivered by ABOG-URPS /
ABU-URPS / general OB-GYN / general urology / APP), because
substitutability is procedure-specific and time-varying: - Stone 2017
(Medicare 2012-2014): FPMRS delivered **60.5% of SUI, 70.5% of POP,
84.9% of mesh/sling removal** — the certified share differs sharply by
procedure. - Huang 2026 (ABU case logs 2009-2020): non-URPS urologists
are **\>80% of the workforce but ~half of URPS case volume**, and their
share of SUI/POP surgery fell while OAB-procedure share rose —
substitution shifts over time. - **Quality weighting stays a
sensitivity, not the headline:** higher-volume sling surgeons have lower
reoperation (Berger 2019, 3.6% vs 4.2%; SUI-reoperation RR 0.75). A
volume/training quality weight may be shown as a labeled sensitivity;
the primary count treats a delivered procedure as a delivered procedure.
**A volume–outcome association does not establish that services
delivered by another specialty should receive a lower capacity weight.**
Any quality adjustment requires procedure-specific outcome data,
comparable patient risk (case-mix adjustment), and an explicit estimand;
it must not become a disguised specialty-preference weight. - **Entrant
heterogeneity (second-packet):** Tabakin 2024 shows gyn-based fellows
log more POP/slings/hysterectomies while uro-based fellows log more
urinary-system surgery and sacral neuromodulation — so the ~64 annual
entrants are **not 64 identical units**. A future entrant cohort should
be represented as a pathway mix (π_gyn, π_uro) × pathway
procedure-family capacity, consistent with the per-procedure
substitution profile. Dubinskaya 2021 (N=578 FPMRS; **89% gyn / 11%
uro**) **externally validates** the OB-GYN-vs-urology pathway split and
pathway-specific volume — a validation cross-check, not a primary
parameter source.

### Module D — Geographic access (two distinct constructs, never conflated)

- **Isochrone coverage / nearest-provider travel:** who lives within a
  30/60/120/180-min drive of the nearest urogynecologist, plus
  **differential distance** (extra travel beyond the nearest general
  OB-GYN). This is *potential proximity*; it carries **no
  supply-vs-demand information**.
- **E2SFCA supply–demand accessibility:** a need- and capacity-weighted
  floating-catchment score (provider capacity ÷ distance-decayed demand
  in each catchment). This is a *ratio* that competition for finite
  capacity can lower even where proximity is good.

**Discipline:** never describe a good isochrone-coverage number as
“adequate access.” Coverage answers “can they reach a provider?”; E2SFCA
answers “is there enough provider capacity for everyone who would reach
it?” (For the fuller supply-demand-adjusted variant that also lets need
vary by age/sex, see Shao & Luo 2022 SDA-2SFCA.) They are **not stages
of one metric** — one is proximity, the other a capacity ratio.

**Neither isochrone coverage nor E2SFCA measures *realized* access.**
Both are *potential* spatial access and must not be read as completed
care. Both omit the non-spatial barriers between reaching a location and
receiving care: insurance acceptance, appointment availability and wait
time, referral requirements, transportation access, language, and
patient preferences. A tract can show excellent proximity and adequate
catchment capacity and still deliver little realized care once these
barriers apply — which is why “potential spatial access” is never a
synonym for “access.”

*Second-packet evidence:* Akapo 2023 gives a urogynecology-specific
drive-time comparator (median 214 min to the nearest OB-GYN
subspecialist nationally; urogyn worst-case \>4 h), useful for
benchmarking the isochrone bands. Brioso 2025 is the empirical anchor
for the realized-vs-potential caveat: at an FQHC *with urogynecologists
on site*, every one of 17 patients who missed a referred appointment
identified at least one non-spatial barrier (scheduling/communication,
transportation, language, cost) — good proximity did not produce
realized care.

## Overarching ratio — relative capacity ratio, not absolute adequacy

The 2025-normalized ratio is a **relative capacity ratio** (supply
growth ÷ realized-utilization demand growth, 2025 = 1.00), conditional
on the *assumption* that 2025 supply equalled 2025 realized-utilization
demand. It is **not** a finding that 2025 care was adequate — because
only ~37% of symptomatic women use services (Mou 2022), an unqualified
“adequacy” reading would enshrine current unmet need as the benchmark.
Per the terminology contract above, reserve **“adequacy”** for supply ÷
an independently-justified need target (e.g., Kirby’s 1-per-100,000) and
**“shortage”** for (external-benchmark need − supply); never apply
either word to this conditional ratio. This mirrors HRSA HWSM’s
status-quo convention (starting-year supply assumed equal to
starting-year demand absent an external shortfall estimate —
*provisional; see matrix note*) and the OB/GYN supply/demand/adequacy
precedent (Silvestre & Lazenby 2026).

## Citation-to-module matrix (added 2026-07-23)

Every reference appears **exactly once**. Six URPS-specific papers were
verified against the primary PDF; three framework/method precedents were
web-verified (HRSA remains **provisional — not manuscript-ready**, see
note); and a **second packet of seven parameter-source papers (added
2026-07-23)** was verified from two supplied PDFs (Plaska 2025,
Rotenstein 2026) plus PubMed (Wu 2014, Tabakin 2024, Dubinskaya 2021,
Akapo 2023, Brioso 2025). Each row states the **exact methodological
claim it supports**, its module, and a page/table/figure locator for
every numeric claim. References not directly supporting a claim are not
added; no reference is cited for a stronger claim than it supports.

| Ref | Module | Methodological claim it supports | Locator (page/table/fig) | DOI / PMID | Verification |
|----|----|----|----|----|----|
| Kirby 2013, *Am J Obstet Gynecol* 209(6):584.e1-5 | B (population-need bracket) | +35% PFD-care demand 2010→2030; density benchmark ≈1 specialist/100,000 (3,735 needed by 2030 vs ~1,400 in AUGS) | +35%: Abstract Conclusion, p.584.e1. 3,735/1,400: Discussion, p.584.e5 | 10.1016/j.ajog.2013.09.011 | PDF read in full (`module_1-s2.0-S0002937813009526-main.pdf`) |
| Wu 2009, *Obstet Gynecol* 114(6):1278-83 | B (population need) | PFD prevalence 28.1M (2010) → 43.8M (2050) — directional upper bracket, not a demand multiplier | Abstract Results, p.1278; Table 1 “One or more PFDs” row, p.1280 | (no DOI on PDF); PMID 19935030 | PDF read in full |
| Stone 2017, *Female Pelvic Med Reconstr Surg* 23(2):75-79 | C (substitution) | Per-procedure certified share differs (FPMRS 60.5% SUI / 70.5% POP / 84.9% removal); 629 FPMRS vs 833 non | 629/833: Abstract Results, p.75. SUI 60.5%/POP 70.5%/removal 84.9%: Results, p.76 | 10.1097/SPV.0000000000000349 | PDF read in full |
| Huang 2026, *Urology* 207:66-70 | C (time-varying substitution) | Non-URPS = \>80% of workforce, ~50% of URPS case volume; substitution shares shift over time | 20.5% URPS-trained & \>80%/\>50%: Results, p.1 (66); per-physician volumes: Table 1 | 10.1016/j.urology.2025.09.023 | PDF read in full |
| Berger 2019, *Am J Obstet Gynecol* 221(5):523.e1-8 | C (quality-weight sensitivity ONLY) | Volume-outcome: reoperation 3.6% vs 4.2%; SUI-reoperation RR 0.75 — justifies a labeled quality sensitivity, never a specialty-preference weight | 3.6% vs 4.2%: Results, p.523.e3. RR 0.75 (SUI reop): Abstract Conclusion + Table 2, p.523.e7 | 10.1016/j.ajog.2019.09.006 | PDF read in full |
| Mou 2022, *Urogynecology (Phila)* 28(9):574-581 | B (symptom–use gap; **not** a multiplier) | Pooled PFD service-utilization 37% (95% CI 30-45%) — evidence of a symptom-to-use gap only | Abstract Results, p.574; Results, pp.576-577 | 10.1097/SPV.0000000000001215 | PDF read in full |
| HRSA Bureau of Health Workforce, *Health Workforce Simulation Model (HWSM) Technical Documentation: Physician Model Components*, 2025 | A/B (framework) | Stock-and-flow supply; 1 FTE = 40 weekly hours; status-quo demand anchors starting-year national demand to starting-year supply | **No page-level primary source captured yet** (live page 403s) | URL (gov resource): bhw.hrsa.gov/…/physician-model-components | **PROVISIONAL — not manuscript-ready.** Facts from Google-indexed excerpts only; before any manuscript use, retrieve the official downloadable HWSM technical documentation and record title, year, version, page, and the exact passage |
| Silvestre & Lazenby 2026, *Arch Gynecol Obstet* 313(1):95 | Ratio (adequacy precedent) | Adequacy = supply FTE ÷ demand FTE ×100%; *reports* geographic variation (non-metro 51.4% vs metro 85.1%); uses HWSM | Adequacy def + metro/non-metro: Results/Abstract, PMC12906581 | 10.1007/s00404-026-08322-5; PMID 41691088; PMCID PMC12906581 | Web-verified (open-access PMC record). Online-first / 2026 vol 313(1); confirm final pagination at submission |
| Shao & Luo 2022 (SDA-2SFCA), *Soc Sci Med* 296:114727 | D (method) | Supply-demand- and need-adjusted floating catchment (need varies by age/sex; finite provider capacity) beyond E2SFCA | Method described in Methods (no single numeric locator; conceptual citation) | 10.1016/j.socscimed.2022.114727; PMID 35091130 | Web-verified (PubMed + ScienceDirect) |
| Plaska 2025, *Neurourol Urodyn* 44(6):811-818 | A/C (workload mix) | Urology-trained URPS split practice: only **~49% of encounters URPS-related**; overall **clinic-to-procedure 3.9:1** (1.5:1–111:1 by diagnosis; **1.1:1** incl. diagnostic procedures) → capacity is not four procedures | 49% & 3.9:1: Abstract p.811 + Results 3.3 pp.3-4; by-diagnosis (IC 111:1, OAB 3.18:1, SUI 1.7-1.8:1): Discussion p.6 | 10.1002/nau.70018 (no PMID on PDF) | PDF read in full. **Case-log years 2010–2021** per Methods/Results/Table 1 (abstract’s “2013–2021” is an internal inconsistency) |
| Rotenstein 2026, *J Gen Intern Med* (online-first) | A (sex/age hazard — SENSITIVITY only) | Female-vs-male clinical-practice attrition **adj HR 1.43** (1.41-1.44); within OB/GYN **HR 1.41** (1.36-1.47); women exit younger (**median 49 vs 64**) | HR 1.43 & 49/64: Abstract p.1 + pp.4-5; OB/GYN HR 1.41: Results p.4 + Table 2 p.5 | 10.1007/s11606-026-10362-1 (**online-first — no vol/pages/PMID yet**) | PDF read in full. National, all-specialty (not URPS) → sex-stratified **sensitivity**; empirical URPS hazard stays primary |
| Wu 2014, *Obstet Gynecol* 123(6):1201-1206 | B (age-specific surgical demand) | Lifetime risk primary SUI/POP surgery **20.0%** by age 80; **SUI surgery bimodal (~46, ~70-71), POP rises to ~71-73** → sling ≠ prolapse age curve | 20.0%: Abstract/Results; age-specific curves: Results | 10.1097/AOG.0000000000000286; PMID 24807341 | Web-verified (PubMed). Use for the **relative age profile**; retain CMS-2024 total as the anchor |
| Tabakin 2024, *Neurourol Urodyn* 43(8):1970-1976 | C (entrant heterogeneity) | Gyn-based fellows log more POP/slings/hysterectomies (p\<0.01); uro-based more urinary-system surgery (p=.03) + sacral neuromodulation (p=.02) → 64 entrants ≠ 64 identical units | Results (case-log comparison) | 10.1002/nau.25533; PMID 38934488 | Web-verified (PubMed) |
| Dubinskaya 2021, *Am J Obstet Gynecol* 225(5):566.e1-566.e5 | A/C (pathway validation) | N=**578** FPMRS: **gyn 517 (89%) vs uro 61 (11%)**; larger sex payment/volume gap among urology-trained | N & split: Abstract/Results | 10.1016/j.ajog.2021.08.032; PMID 34473964 | Web-verified (PubMed). External **validation**, not a primary parameter. (Review said “2024” — actually **2021, AJOG**) |
| Akapo 2023, *Cureus* 15(12):e51403 | D (urogyn drive-time comparator) | Median **214 min** to nearest OB/GYN subspecialist; urogyn longest **\>240 min (\>4 h)**; new-patient wait 13.6 business days | Mystery-caller Abstract/Results | 10.7759/cureus.51403; PMID 38292990 | Web-verified (PubMed; urogyn \>240 min is abstract-sourced). (Review said “2024” — actually **2023, Cureus**; author incl. Muffly TM) |
| Brioso 2025, *Urogynecology (Phila)* (online-ahead) | B/D (realized ≠ potential access) | 17 FQHC patients who missed referred urogyn appts **despite on-site subspecialists**; **all identified ≥1 barrier** (scheduling/communication, transportation, language, cost) | Abstract/Results | 10.1097/SPV.0000000000001782; PMID 41428457; PMCID PMC12885760 | Web-verified (PubMed; **online-ahead-of-print — no pagination yet**) |

### Do-not-cite corrections (from the review summary)

- **RESOLVED (2026-07-23):** the **“~3.9 clinic visits/surgery,
  ~1.1/procedure”** ratio — previously flagged as misattributed to Huang
  2026 (which has no clinic-visit metric) — is now correctly sourced to
  **Plaska 2025** (*Neurourol Urodyn* 44(6):811-818, the
  Practice-Patterns paper, since supplied and PDF-verified): overall
  clinic-to-procedure **3.9:1**, and **1.1:1** when diagnostic
  procedures are counted. Cite Plaska, not Huang, for these ratios.
- **“51% delayed care”** is **not** in Mou 2022 (Mou gives only 37%
  utilization). Attribute the delay figure to its true source or drop
  it.

### Unresolved methodological questions (for review)

1.  **Prevalence-need denominator not wired into the headline ratio.**
    `urps_supply_demand_national` computes an age-specific
    PFD-prevalence-weighted `women_with_pfd`, but the Shiny adequacy
    ratio uses women-65+ only. Should the reduced-barriers scenario
    surface in the explorer, or stay a manuscript-only sensitivity?
    (Tier 3 decision.)
2.  **Three B/C code lineages coexist** (\$-weighted early vs
    count-weighted corrected/FROZEN). The FROZEN 4-anchor lineage is the
    gated source of truth; confirm the manuscript cites only it.
3.  **Substitution matrix vs field-transfer scalars.** Module C
    currently uses per-field transfer scalars + a primary-clinician
    plasticity matrix, not a full per-procedure substitution matrix with
    concentration (Gini, top-1/5%). Building that is Tier 3.
4.  **E2SFCA not wired to the URPS/OB-GYN point layers.** Module D is
    nearest-distance + differential only; the E2SFCA machinery exists in
    the accessibility pipeline but is not applied to the URPS supply
    layer. Tier 3.
