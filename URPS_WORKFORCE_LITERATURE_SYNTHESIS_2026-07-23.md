# URPS Workforce Analysis: Literature Synthesis & Method Recommendations

Reviewed 2026-07-23 for the urogynecology (URPS) supply–demand–capacity model. Seven
surgical/oncology workforce papers supplied by the PI. **Framing caveat:** six of the
seven are geographic-access studies or methodological *critiques*, not supply-demand
projection models; the AAMC/GlobalData 2024 report remains the only full modeling
template. Their value is concentrated in (i) the "beyond head count" supply argument,
(ii) plasticity/substitution, and (iii) geographic-access method choices.

## Papers reviewed

| # | Citation | Type | Relevance |
|---|---|---|---|
| 1 | Herb et al. *Am J Surg* 2021;222:305-310 — travel distance & cancer surgery (systematic review) | Access review | Differential distance; distance-bias caveat; network > Euclidean |
| 2 | Herb, Stitzenberg, Holmes. *J Surg Res* 2022;270:341-347 — rural-urban definitions & surgeon supply | Access methods | Rurality by urban-population share, not binary metro/rural |
| 3 | Ross et al. *J Am Coll Cardiol* 2017;69:1347-52 — pediatric cardiology 2015 workforce | Society survey | Work-time/FTE basis; retirement-omission caution; job-openings ≠ need |
| 4 | Stitzenberg et al. *Arch Dermatol* 2007;143:991-998 — distance to diagnosing provider (melanoma) | Access study | Realized vs potential access; continuous + clinical-cutoff distance |
| 5 | Stitzenberg et al. *Ann Surg* 2014;259:556-562 — surgical oncology workforce | Supply characterization | Claims-based "who delivers care"; generalist–specialist overlap; per-100k benchmark |
| 6 | Joint AAST/ACS-COT/EAST/WTA. *J Trauma Acute Care Surg* 2026;100:380-385 — acute care surgery | Consensus statement | Time-based FTE; burnout-workload attrition; roster/terminology discipline |
| 7 | Stitzenberg. *J Oncol Pract* 2015;11(1) — "Moving Beyond the Head Count" | Commentary/critique | Plasticity; services-not-bodies; activity-space access |

## What the literature validates in our current approach

- **"Beyond the head count" — supply as services, not bodies.** Stitzenberg (#5, #7):
  *"Workforce projections must move beyond … simply counting numbers of physicians by
  specialty."* Our effective-FTE + age-productivity weighting already does this.
- **Cert-based roster is a strength.** The acute-care-surgery consensus (#6) shows the
  ambiguity when a field lacks a board-cert standard and benchmarking surveys define the
  specialty inconsistently. Our ABOG+ABU cert roster is defensible by contrast.
- **Network isochrones > straight-line.** Every access paper used ZIP-centroid Euclidean
  distance and flagged it as a limitation; #4 excluded mountainous/coastal areas, *under*-
  stating disparities. Our Valhalla road-network + water-clip is the stronger method.
- **Our uncertainty handling exceeds the comparators.** These papers report point
  estimates and subjective adequacy (#3: 49% "felt" supply adequate). Our scenario ranges,
  plausibility bands, and fuzz testing are more rigorous (AAMC is the exception).

## High-value additions (ranked)

1. **Claims-based "who actually delivers the care"** (#5). Attribute procedures to operating
   providers; generalists did 48% of oncologic procedures vs 12% for specialists. We already
   have this in Module B/C (HCPCS 57288/57282/51728/52287; the "large low-volume clinician
   tail"). *Formalize and cite Stitzenberg* to justify not attributing the hidden tail to
   certified urogynecologists.
2. **Plasticity / substitution** (#7, citing **Holmes 2013**): the same need is met by many
   provider configurations, so *supply and demand cannot be projected independently*. Add an
   explicit **substitution scenario** (general OB/GYN + APP absorb some URPS demand) — the most
   sophisticated idea in the set.
3. **Differential distance + activity-space caveat** (#1, #7). Use **extra travel to reach a
   urogynecologist beyond the nearest OB/GYN** (maps onto the ABOG+ABU split). Flag 30-min
   deserts as *potential* access; *"normal activity space is a more important determinant of
   access than distance"* (Nemet & Bailey 2000); patients bypass nearest providers (realized ≠ potential).
4. **Rurality by urban-population share, not a binary flag** (#2): county Census urban-% predicts
   subspecialist supply ~3× better than metro/non-metro (adj R² 0.31 vs 0.10). Upgrade Module D.
5. **Two benchmarks reviewers expect:** urogynecologists **per 100,000** (≈3.86/100k women 65+)
   for comparability; and **translate the capacity gap into a patient-level consequence**
   (women 65+ per productivity-adjusted capacity equivalent), not an abstract capacity number.
6. **Ground the FTE definition and attrition:** pull **Murphy 2022** ("defining 1.0 FTE in
   trauma/ACS"; *J Trauma* 2022;92:648-655) and the pediatric-cardiology work-time basis
   (70% direct care, ~60 h/wk). Consider a **burnout/workload modifier on the departure hazard**
   (#6 ties turnover to workload), not age alone.
7. **Demand: bracket need vs utilization.** Every paper warns against conflating
   job-openings/utilization with population need. Add a **prevalence-based demand sensitivity**
   (Nygaard PFD prevalence) alongside status-quo-utilization demand; present both.

## Caveats to state explicitly in the manuscript

- **Distance bias / selection artifact** (#1, #4): registry/claims data only see patients who
  *reached* care, so they can spuriously show more care at longer distances. Our county
  women-65+ denominator avoids this for *potential* access; any utilization-derived rate inherits it.
- **Willingness to travel** varies by age/rurality; older women may not travel our 30-min ring.
- **Provider presence is a marker of overall local supply, not a direct driver** (#4) — don't
  over-read county counts (isochrones mitigate).
- **Single-metric access understates reachable care**; report multiple bands (we already do 30/60/120/180).

## Citations to pull next

Stitzenberg *Ann Surg* 2014 & *J Oncol Pract* 2015 (beyond-head-count); **Holmes 2013**
(plasticity); **Murphy 2022** (1.0 FTE definition); Herb *J Surg Res* 2022 (rural definitions);
Nemet & Bailey 2000 (activity space); Nygaard 2008 JAMA (PFD prevalence, already cited).
**Framework/precedent (web-verified 2026-07-23):** HRSA Bureau of Health Workforce, *HWSM
Technical Documentation: Physician Model Components* 2025 (stock-and-flow + 1 FTE = 40 hr/wk +
status-quo-demand = starting-year balance; gov resource, lift a verbatim quote in-browser before
submission since the live page 403s); Silvestre & Lazenby 2026, *Arch Gynecol Obstet* 313(1):95,
doi:10.1007/s00404-026-08322-5, PMID 41691088 (OB/GYN adequacy = supply FTE ÷ demand FTE, with
geographic variation — the adequacy-ratio precedent); Shao & Luo 2022, *Soc Sci Med* 296:114727,
doi:10.1016/j.socscimed.2022.114727, PMID 35091130 (SDA-2SFCA, supply-demand- and need-adjusted
floating catchment, for Module D). The last three were staged into `manuscript/e2sfca_extra_refs.bib`
only where directly relevant to the geographic-access paper (Shao & Luo, Silvestre & Lazenby, plus
Mou 2022); the Module A/B/C papers (Kirby, Wu, Stone, Huang, Berger, HRSA) remain doc-only.

## Benchmark numbers extracted (for comparison tables)

- Surgical-subspecialist density 20/100k (SD 26); metro 31 vs non-metro-adjacent 12/100k (#2).
- Generalists performed 48% vs specialists 12% of oncologic procedures (#5).
- 1,183 US counties (93% rural, ~15M people) had no general surgeon in 2009 (#5).
- Cancer demand projected +48% by 2020 vs medical-oncology supply +14% (#5) — the supply–demand gap framing.
- Acute care surgery workload norm: 15–18 twelve-hour shifts/month (#6).

---

## URPS-specific modeling papers (PI-supplied, PDF-verified 2026-07-23)

Six urogynecology-specific PDFs supplied to anchor the four-module model. Every number
below was read directly from the source PDF (not from a secondary summary). Each maps to a
specific module.

| # | Citation | Module | Verified headline numbers |
|---|---|---|---|
| K | Kirby AC, Luber KM, Menefee SA. An update on the current and future demand for care of pelvic floor disorders in the United States. *Am J Obstet Gynecol* 2013;209(6):584.e1-5. doi:10.1016/j.ajog.2013.09.011 | B (demand) | **+35% demand for PFD care, 2010→2030**; 1,218,371 new-patient visits (2010) → 1,644,804 (2030). Workforce: **3,735 PFD specialists needed by 2030 (~1 per 100,000)** vs ~1,400 then in AUGS. |
| W | Wu JM, Hundley AF, Fulton RG, Myers ER. Forecasting the prevalence of pelvic floor disorders in U.S. women: 2010 to 2050. *Obstet Gynecol* 2009;114(6):1278-83. | B (population need) | Women with ≥1 PFD **28.1M (2010) → 43.8M (2050)**; UI 18.3→28.4M, FI 10.6→16.8M, POP 3.3→4.9M. |
| S | Stone DE, Barenberg BJ, Pickett SD, O'Leary DE, Quiroz LH. Characteristics of providers performing urogynecologic procedures on Medicare patients 2012-2014. *Female Pelvic Med Reconstr Surg* 2017;23(2):75-79. doi:10.1097/SPV.0000000000000349 | C (substitution) | **629 FPMRS vs 833 non-FPMRS** providers billed urogyn procedures. FPMRS share by service: **SUI 60.5%, POP 70.5%, mesh/sling removal 84.9%** — substitutability is procedure-specific. |
| H | Huang Z, Cohen T, Ieong K, et al. Trends in urogynecologic and reconstructive pelvic surgery among early-career urologists: analysis of American Board of Urology case logs from 2009-2020. *Urology* 2026;207:66-70. doi:10.1016/j.urology.2025.09.023 | C (time-varying substitution) | Of 3,113 early-career urologists, **20.5% URPS-trained**; non-URPS = **>80% of the workforce and >50% of total URPS case volume**. Per-physician volumes (URPS vs non): sling 11 vs 5; Botox 10 vs 4.5; sacral neuromod 13.2 vs 7.9. |
| B | Berger AA, Tan-Kim J, Menefee SA. Surgeon volume and reoperation risk after midurethral sling surgery. *Am J Obstet Gynecol* 2019;221(5):523.e1-8. doi:10.1016/j.ajog.2019.09.006 | C (quality weight, sensitivity only) | Higher-volume surgeons: **all-cause reoperation 3.6% vs 4.2% (P=.04)**; reoperation for recurrent SUI 2.7% vs 3.6% (**RR 0.75**). Not counting-equivalence — supports a *sensitivity* quality weight, not the primary count. |
| M | Mou T, Gonzalez J, Gupta A, et al. Barriers and promotors to health service utilization for pelvic floor disorders in the United States: systematic review and meta-analysis. *Urogynecology (Phila)* 2022;28(9):574-581. doi:10.1097/SPV.0000000000001215 | B (latent demand) | **Pooled PFD service-utilization rate 37% (95% CI 30-45%)** across 44 studies — only ~one third of symptomatic women seek care. Anchors a reduced-barriers demand scenario. |

### How these wire into the modules
- **Module B (demand):** Kirby +35% and Wu 28.1→43.8M give a *population-need* upper bracket to set alongside the status-quo (maintain-2024-utilization) demand. Mou's **37%** documents a symptom-to-use gap; **do not convert it into a 1/0.37 specialist-demand multiplier** — "used any PFD service" is not "needed a board-certified urogynecologist." Any quantitative reduced-barriers scenario is an *illustrative upper bound* requiring separately-sourced referral/treatment/specialty-attribution probabilities (see methods-doc Module B).
- **Module C (substitution):** Stone's per-service FPMRS shares (SUI 60.5 / POP 70.5 / removal 84.9%) and Huang's time-trend are the empirical basis for a **per-procedure substitution matrix**, replacing a single overall "urogynecologist share." Berger's volume-outcome finding is the justification for keeping any quality weight as a *labeled sensitivity*, not the headline.
- **Module A / benchmark:** Kirby's "3,735 needed ≈ 1/100,000" is a reviewer-recognized density benchmark to compare against our per-100k figures.

### Integrity corrections to the PI's review summary
1. **RESOLVED 2026-07-23.** The **"~3.9 clinic visits per surgery / ~1.1 per procedure"** ratio was
   originally (mis)attributed to the ABU case-log paper (Huang, *Urology* 2026), which contains **no
   clinic-visit metric**. The true source — the *Practice Patterns of Surgeons Seeking Board
   Certification in URPS* paper — has since been supplied and PDF-verified: **Plaska et al.,
   *Neurourol Urodyn* 2025;44(6):811-818** (overall clinic-to-procedure **3.9:1**; **1.1:1** including
   diagnostic procedures; ~49% of encounters URPS-related). Cite **Plaska**, not Huang, for the ratio.
2. **"51% delayed care"** is still **not in Mou 2022**; Mou reports only the **37% pooled utilization**.
   Attribute the delay statistic to its true source (a separate study) or drop it. (Unresolved.)

## URPS parameter-source papers (second packet, verified 2026-07-23)

Seven papers the PI prioritized because each pins a parameter the four-module model currently
estimates or treats as a scenario. Two verified from supplied PDFs (Plaska, Rotenstein), five from
PubMed. Full DOI/PMID + page locators are in the methods-doc citation-to-module matrix. Review
misattributions were corrected on verification.

| # | Paper | Module | What it pins | Verified numbers |
|---|---|---|---|---|
| 1 | Plaska 2025, *Neurourol Urodyn* 44(6):811-818 | A/C | Clinic-to-procedure workload; urology-trained practice mix | ~49% encounters URPS-related; **3.9:1** clinic:procedure (1.5:1–111:1 by dx; 1.1:1 incl. diagnostics). Case logs **2010–2021** (abstract's 2013–2021 is an internal inconsistency) |
| 2 | Rotenstein 2026, *J Gen Intern Med* (online-first) | A | Sex-/age-specific departure hazard (sensitivity) | Female-vs-male attrition **adj HR 1.43**; OB/GYN HR 1.41; women exit **median 49 vs 64**. National, all-specialty → sensitivity only |
| 3 | Wu 2014, *Obstet Gynecol* 123(6):1201-1206 | B | Age-specific surgical demand | Lifetime SUI/POP surgery risk **20.0%** by 80; SUI bimodal (~46, ~70-71), POP rises to ~71-73 |
| 4 | Tabakin 2024, *Neurourol Urodyn* 43(8):1970-1976 | C | Entrant heterogeneity by pathway | Gyn fellows: more POP/slings/hysterectomies; uro fellows: more urinary-system surgery + sacral neuromod |
| 5 | Dubinskaya 2021, *Am J Obstet Gynecol* 225(5):566.e1-5 | A/C | Pathway split + productivity (validation) | N=**578**; **gyn 89% / uro 11%**; larger sex pay/volume gap in uro-trained. *(Review said 2024; actually 2021, AJOG)* |
| 6 | Akapo 2023, *Cureus* 15(12):e51403 | D | Urogyn-specific drive-time comparator | Median **214 min** to nearest OB-GYN subspecialist; urogyn **>4 h**. *(Review said 2024; actually 2023, Cureus; incl. Muffly TM)* |
| 7 | Brioso 2025, *Urogynecology (Phila)* (online-ahead) | B/D | Realized ≠ potential access | 17 FQHC patients missed referred urogyn appts **despite on-site subspecialists**; **all** cited ≥1 barrier |

**Discipline applied (per PI):** Rotenstein and Wu 2014 inform *shapes and sensitivity ranges*, not
primary parameters (empirical URPS hazard and CMS-2024 volume stay the anchors). Dubinskaya/Akapo are
external validation/comparators, not parameters. **APP substitution stays out** — the literature (a
single-center urotherapist study; a colorectal APP model) supports feasibility of task-shifting but
gives no nationally generalizable substitution fraction, so no APP capacity is credited for the
primary reconstructive surgeon. The old "female OB/GYNs ~85% as productive" figure is **not** used as a
parameter (survey-era, confounded); our longitudinal claims-based productivity is preferred.