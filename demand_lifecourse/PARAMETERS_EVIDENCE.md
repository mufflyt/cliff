# Parameter evidence — reproductive life-course demand model

Cited coefficients and data inputs for the demand model
(`DEMAND_LIFECOURSE_MODEL_SPEC.md`). **Every value is attributed to a real
published source; nothing here is invented.** Confidence grades and the honest
gaps below must be read before any number enters a published workforce estimate.

## Reliability caveat (read first)

The coefficients were assembled via a structured literature scan. Publisher and
PubMed/PMC **full-text pages were not directly openable in the build environment
(HTTP 403)**, so figures were extracted from search-engine summaries of those
exact abstracts and from reviews quoting the primary source. Consequences:

- **High-confidence** landmark figures (Gyhagen 2013, Rortveit 2003 NEJM, Wu
  2014, Giri 2017, Nygaard 2008, LaCross 2015) are internally consistent with the
  well-established literature.
- **Medium-confidence** figures reaching us only through secondary paraphrase
  (Hendrix/WHI, Mant/Oxford FPA) are flagged `confidence = medium` in the CSVs
  and **must be verified against full text before publication.**
- Where nothing could be sourced, it is listed under **Gaps**, not filled.

## Files

| File | Contents |
|---|---|
| `params/parity_disease_dose_response.csv` | Vaginal delivery / parity / OASI → POP, UI, AI effect sizes |
| `params/risk_modifiers.csv` | Obesity, birth weight, hysterectomy, smoking (modifiers, not the driver) |
| `params/care_pathway.csv` | Prevalence anchor, care-seeking, lifetime surgery risk, treatment mix |
| `params/staffing_conversion.csv` | Services→FTE denominators (**largely gaps/placeholders — see below**) |
| `data/us_cesarean_rate_by_year_2026-08-02.csv` | Total cesarean rate 1965–2024 (NHDS pre-1989, NVSS 1989+) |
| `data/us_completed_parity_by_cohort_2026-08-02.csv` | Mean completed parity + parity distribution by birth cohort |

## What the exposure layer shows

Derived by `02_birth_history.R` from the two cited data series, mean vaginal
deliveries per woman falls from **~2.9 (born ~1935)** to **~1.3 (born ~1985)** —
driven by both falling completed parity (~3.0 → ~1.9) and the rising cesarean
fraction (~5% → ~32%). Future 65+ cohorts therefore carry roughly **half** the
cumulative vaginal-delivery exposure embedded in the Nygaard 2008 cross-section,
which is the demand-relevant signal a static age-only denominator misses.

## Strongest usable relationships

- **Mode of delivery → POP:** vaginal vs cesarean (single birth) OR **2.55**
  (1.98–3.28), Gyhagen 2013 — the cleanest mode-isolating estimate.
- **Parity dose-response → POP:** Mant 1997 RR **8.4** (2 vaginal births) →
  **10.9** (4) vs nulliparous (medium; verify). Hendrix per-additional-birth
  OR ~1.10–1.21 by compartment (medium; verify).
- **Mode → UI:** vaginal vs cesarean-only OR **1.7** (1.3–2.1), Rortveit 2003
  NEJM; cesarean itself raises UI above nulliparous (OR 1.5).
- **OASI → AI:** OR **2.66** (1.77–3.98), LaCross 2015.
- **Obesity (modifier) → POP:** obese vs normal RR **1.47** self-report / **1.71**
  objective, Giri 2017 — real but secondary to delivery history.
- **Care pathway anchors:** ≥1 PFD prevalence **23.7%** (Nygaard 2008); lifetime
  SUI/POP surgery risk **20%** by age 80 (Wu 2014); **<25%** of women with UI
  seek care (Minassian 2012).

## Gaps (do NOT fabricate to fill)

1. **Per-woman joint distribution of vaginal vs cesarean deliveries by cohort** —
   no off-the-shelf published table; needs a custom NSFG microdata tabulation.
   The current vaginal/cesarean split is *derived* (parity × period cesarean
   fraction over the childbearing window) with documented assumptions in
   `02_birth_history.R`.
2. **Clean 1/2/3/4+ vaginal-parity POP ladder with CIs** — only single-birth
   (Gyhagen), per-birth increments (Hendrix), and stepped RRs (Mant) exist.
3. **SUI-subtype-specific dose-response by delivery count** — only "any UI" and
   age strata sourced.
4. **Obesity → UI per-5-kg/m² OR with CI**, and quantified menopause/smoking
   modifiers — direction only.
5. **Services→FTE conversion — RESOLVED via work RVUs (was a placeholder gap).**
   Rather than a "visits per FTE" constant, `07_staffing_conversion.R` converts
   service volumes to required FTE with CMS Physician Fee Schedule work RVUs
   (RVU25A 2025, `params/urps_service_workload_rvu.csv`) and a wrvu-per-FTE that
   is *solved* from a base-year anchor (Dall 2013), grossed up for indirect time.
   Ported from the simulation package's R/17/R/23. An external benchmark
   (3,500 / 7,500 / 12,000 wRVU per FTE) is used only as a plausibility check.
   The full provider-delegation and setting-allocation engine remains in
   simulation (SSOT); cliff carries only the URPS-attributed wRVU path.
6. **Hendrix (WHI) and Mant (Oxford FPA) exact estimates/CIs** — verify full
   text before locking.

## Reference list

Gyhagen 2013 BJOG · Hendrix 2002 AJOG (WHI) · Mant 1997 Br J Obstet Gynaecol
(Oxford FPA) · Rortveit 2003 NEJM & 2001 Obstet Gynecol (EPINCONT) · Hannestad
2003 BJOG · LaCross 2015 J Midwifery Womens Health · Giri 2017 AJOG · Nygaard
2008 JAMA · Minassian 2012 Int Urogynecol J · Wu 2014 Obstet Gynecol · Zarek 2025
Phys Ther · CDC/NCHS Natality & Data Briefs (35, 477, 535) · US Census CPS
Fertility Supplement / P20 series · BGSU NCFMR FP-20-04.
