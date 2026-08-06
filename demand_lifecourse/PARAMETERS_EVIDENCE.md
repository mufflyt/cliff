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
- Hendrix/WHI is now **CONFIRMED against the abstract** and Mant's per-parity RRs
  were **removed as unconfirmed** — see the 2026-08-03 update at the bottom, which
  supersedes the medium-confidence flags below.
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

Derived by `demand-birth_history.R` from the two cited data series, mean vaginal
deliveries per woman falls from **~2.9 (born ~1935)** to **~1.3 (born ~1985)** —
driven by both falling completed parity (~3.0 → ~1.9) and the rising cesarean
fraction (~5% → ~32%). Future 65+ cohorts therefore carry roughly **half** the
cumulative vaginal-delivery exposure embedded in the Nygaard 2008 cross-section,
which is the demand-relevant signal a static age-only denominator misses.

## Strongest usable relationships

- **Mode of delivery → POP:** vaginal vs cesarean (single birth) OR **2.55**
  (1.98–3.28), Gyhagen 2013 — the cleanest mode-isolating estimate.
- **Parity dose-response → POP:** Hendrix WHI 2002 per-additional-birth OR
  ~1.10–1.21 by compartment (**confirmed**; see 2026-08-03 update). Mant's exact
  per-parity RRs are **unconfirmed and removed** — do not use a point estimate.
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
   `demand-birth_history.R`.
2. **Clean 1/2/3/4+ vaginal-parity POP ladder with CIs** — only single-birth
   (Gyhagen), per-birth increments (Hendrix), and stepped RRs (Mant) exist.
3. **SUI-subtype-specific dose-response by delivery count** — only "any UI" and
   age strata sourced.
4. **Obesity → UI per-5-kg/m² OR with CI**, and quantified menopause/smoking
   modifiers — direction only.
5. **Services→FTE conversion — RESOLVED via work RVUs (was a placeholder gap).**
   Rather than a "visits per FTE" constant, `supply-staffing_conversion.R` converts
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

---

## Update 2026-08-03 — coefficient verification, validation targets, cesarean-correlation refinement

**Coefficient verification (dose-response).** Verified `params/parity_disease_dose_response.csv`
against primary abstracts (publisher/PubMed PDFs were network-blocked, so this rests
on search-surfaced abstract text — do one confirmatory institutional read before
locking a published number):

- **CONFIRMED** (upgraded from "medium — verify"): Hendrix WHI 2002 — uterine prolapse
  first-birth OR 2.13 (1.67–2.72), per additional birth 1.10 (1.05–1.16); cystocele 1.91
  (1.67–2.19), per-birth 1.21 (1.17–1.24); rectocele 2.22 (1.84–2.68), per-birth 1.21
  (1.17–1.26). Rortveit NEJM 2003 — any-UI vaginal-vs-cesarean 1.7 (1.3–2.1), and
  moderate/severe UI vaginal-vs-cesarean 2.2 (1.5–3.1) added. Gyhagen 2013 (2.55) and
  Mant 1997 hysterectomy-for-prolapse RR 5.5 (3.1–9.7) confirmed.
- **CORRECTED**: the two Mant per-parity RR rows (previously 8.4 / 10.9) are **removed as
  point estimates** — those values were never confirmed against Mant's table and conflict
  with a secondary "~4 / 8 / 11-fold" paraphrase. The row now carries NA with a low-confidence
  note; do not use a per-parity RR until the full text is read.

**Validation targets (#2).** `params/validation_targets.csv` + `validation-targets.R` add an
external back-cast harness. Cited targets: Nygaard 2008 cross-sectional prevalence
(any-PFD 23.7%, UI 15.7%, POP 2.9%, FI 9.0%); SWAN/Waetjen 2007 midlife UI prevalence
46.7% (mean age 45.8) and annual incidence 11.1%; SWAN 2025 (Sci Rep) parity/mode
direction check. The participant-level SWAN validation stays in the simulation package's
legacy DPPM framework (needs the application-gated ICPSR SWAN microdata); this harness
validates against the **published** SWAN estimates.

**Cesarean within-woman correlation (#5).** The `mean_vaginal_deliveries` derivation is
**unbiased** by how cesareans cluster within a woman (expectation is linear), so the
cohort-cell model is unaffected. But the **stratum distribution** (0/1/2/3+ vaginal
births) needs the within-woman correlation: among US women with a prior cesarean,
**~85–87%** of next births are repeat cesareans vs a **~22%** primary rate (NCHS Data
Brief No. 359; VSRR No. 21) — committed in `params/us_cesarean_repeat_vbac.csv`.
`cesarean_births_correlated()` (demand-birth_history.R) implements a first-order sequence
draw for a per-woman microsimulation. **Remaining gap:** the exact per-woman joint
distribution of vaginal vs cesarean births by cohort is **not published** and requires a
custom NSFG Female Pregnancy File microdata tabulation.
