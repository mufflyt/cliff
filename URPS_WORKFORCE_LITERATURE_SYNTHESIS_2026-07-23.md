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
   (women 65+ per effective FTE), not an abstract FTE number.
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

## Benchmark numbers extracted (for comparison tables)

- Surgical-subspecialist density 20/100k (SD 26); metro 31 vs non-metro-adjacent 12/100k (#2).
- Generalists performed 48% vs specialists 12% of oncologic procedures (#5).
- 1,183 US counties (93% rural, ~15M people) had no general surgeon in 2009 (#5).
- Cancer demand projected +48% by 2020 vs medical-oncology supply +14% (#5) — the supply–demand gap framing.
- Acute care surgery workload norm: 15–18 twelve-hour shifts/month (#6).
