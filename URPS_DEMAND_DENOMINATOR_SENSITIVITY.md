# URPS demand-denominator sensitivity

**Why this exists.** A scoping review of the URPS supply/demand/access literature
(2026-07-24) made one methodological point sharply: **"demand" for urogynecologic
care has four distinct meanings, and they must not be combined or used
interchangeably.** A supply-and-demand paper that reports a single demand
denominator (here, any-PFD prevalence) invites the objection that the conclusion
is an artifact of that choice. This analysis answers that objection by carrying
three independent demand estimands through the same supply comparison and
reporting their **concordance**, not a blended number.

Producer: `scripts/urps_demand_denominators_sensitivity.R`
Output:   `data/urps_demand_denominators_sensitivity_2026-07-24.csv`,
          `augs_application/figures/demand_denominator_sensitivity.png`

## The three estimands (national, indexed to 2025 = 100, 2025-2050)

| ID | Construct | Primary source (verified 2026-07-24) | What it represents |
|----|-----------|--------------------------------------|--------------------|
| D1 | Prevalent PFD cases | Wu 2009 *Obstet Gynecol*; Nygaard 2008 *JAMA* | Upper-bound disease burden (women with **any** modeled PFD) |
| D2 | New specialty consultations | Kirby 2013 *Am J Obstet Gynecol* | Realized new-patient demand (closest to clinic workload) |
| D3 | Surgical volume (SUI + POP) | Wu 2011 *Am J Obstet Gynecol* | Projected operative workload |

**Verified anchors used.**
- Wu 2009: any-PFD 28.1M (2010) → 43.8M (2050). Already in the supply-demand CSV as
  `women_with_pfd` (Nygaard age-specific prevalence × Census 2023 NPP), so D1 uses
  `pfd_index` directly.
- Kirby 2013: new PFD visits 1,218,371 (2010) → 1,644,804 (2030), +35% over 20 yr.
- Wu 2011: SUI 210,700 + POP 166,000 = 376,700 (2010) → 310,050 + 245,970 = 555,020
  (2050), +47.2%. Age-specific rates (per 1,000 women/yr, IP+OP), bands
  20-39 / 40-59 / 60-79 / ≥80: SUI 0.473 / 2.390 / 3.094 / 1.684;
  POP 0.500 / 1.645 / 2.719 / 1.069 (captured in the script for the age-specific
  refinement below).

## Result (first pass)

| | Supply | D1 prevalence | D2 consultations | D3 surgery |
|---|---|---|---|---|
| 2050 demand index (2025=100) | **179** | 119 | 146 | 127 |
| 2050 coverage = supply / demand | — | 150 | **123** | 141 |

Implied demand growth: D2 1.51%/yr, D3 0.97%/yr (D1 from the age-specific CSV).

**Robustness verdict: supply outpaces demand through 2050 under all three demand
definitions (YES).** The tightest margin is D2 (consultations), the fastest-growing
construct: even there, per-capita coverage rises ~23% by 2050. Spearman ρ between
the three coverage series = 1.0 (all monotone increasing), so the ordering is
identical across constructs; what differs is the magnitude of the improvement.

## What is and is not claimed (per the review)

- Coverage is reported as **relative** (supply growth vs demand growth), **not** as
  a proportion of clinical need met. The literature does not establish a normative
  number of PFD patients, consultations, or operations one urogynecologist can serve.
- The demand estimands are **not averaged**. They are reported side by side with a
  concordance statistic, because they measure different quantities.
- D1 (any-PFD prevalence) is explicitly an **upper-bound epidemiologic denominator**,
  not a count of subspecialty visits.

## Honest limitations of the first pass

1. **D2 and D3 are constant-growth extrapolations** from their published anchor
   years (Kirby to 2030; Wu-2011 to 2050) under fixed proportional growth. That is
   an explicit assumption, flagged in the script output, not a measured trajectory.
   Real aging deceleration would lower D2 after 2030; accelerating care-seeking
   would raise it (the direction that most erodes the conclusion).
2. **The age-specific Wu-2011 model is not yet wired.** The faithful D3 applies the
   four-band rate table to Census 2023 NPP **female population by age band**
   (20-39 / 40-59 / 60-79 / ≥80). The current supply-demand CSV carries only
   `women_40plus` and `women_65plus`, so the script embeds the rate table and a
   ready `apply_age_specific_surgery_demand()` function but runs the national-anchor
   version. **Next data step:** pull Census-by-age and swap in the age-specific D3.
3. Practice change since the baseline periods (mesh restrictions, office procedures,
   neuromodulation, bulking, payer shifts) is not modeled; Wu-2011 assumes rates
   constant. This makes D3 a stable-practice scenario, not a forecast.

## To integrate into the manuscript

- Add a Methods sentence and a Results paragraph reporting the three-denominator
  concordance and the robustness verdict.
- Cite `kirby2013` and `wu2011` (bib entries pending verification of vol/pages/DOI).
- Reference `demand_denominator_sensitivity.png` (or an Appendix table).
