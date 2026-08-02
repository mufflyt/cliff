# Positioning cliff against the Sheps pediatric-subspecialty microsimulation

**Purpose.** The closest published analogue to cliff is the Cecil G. Sheps
Center / American Board of Pediatrics (ABP) Foundation pediatric-subspecialty
workforce model. This note records its methods, cites it correctly, and gives
paste-ready text positioning cliff's Monte Carlo projection against it — both to
strengthen the manuscript's Methods/Discussion and to guide future model design.

---

## The reference

> Fraher EP, Knapton A, McCartha E, Leslie LK. **Forecasting the Future Supply
> of Pediatric Subspecialists in the United States: 2020–2040.** *Pediatrics.*
> 2024;153(Suppl 2):e2023063678C. doi:10.1542/peds.2023-063678C. PMID 38300007.

- Interactive model & methods: <https://www.pedsubspecforecast.unc.edu/>
- Front-end source (Svelte): <https://github.com/gallowayevan/peds-subspec-workforce>
- Lead workforce group: Program on Health Workforce Research & Policy, Cecil G.
  Sheps Center, UNC–Chapel Hill (PI Erin Fraher), with Strategic Modelling
  Analysis & Planning Ltd. (SMAP) and the ABP Foundation.

**What their public GitHub actually contains:** the Svelte front end that
renders the model's outputs (`pedsubspecforecast.unc.edu`). The microsimulation
engine and the confidential provider roster are *not* in the public repo — the
transferable asset from Sheps is the **method**, published in the citation
above, not runnable code. (See the repo-level assessment that motivated this
work.)

---

## How their model works (from the methods paper)

- **Model class:** dynamic **microsimulation** — individual synthetic providers
  are aged forward one year at a time, each with entry, aging, and exit events,
  and results are aggregated. Contrast with cliff's **cohort Monte Carlo**, which
  resamples aggregate flows (entrants, departures) rather than simulating
  individuals.
- **Horizon:** 2020 → **2040** (20 years).
- **Population simulated:** clinically active subspecialists **aged ≤ 70**, for
  **14** ABP subspecialties.
- **Entry:** fellowship completions feed the pipeline; scenarios scale
  fellow counts and the share entering clinical practice.
- **Exit / attrition:** age-specific attrition and retirement; providers exit at
  the top of the age band. Scenarios vary attrition and hours.
- **Geography:** national **and subnational** — US **Census region and division**
  — which is the paper's central contribution: a national headcount can look
  adequate while divisions diverge sharply.
- **Output metric:** headcount **and** a clinical-workload / clinical-time
  equivalent, plus supply-vs-child-population ratios.
- **Scenarios:** fellowship expansion/contraction, exit-rate changes, and
  clinical-time changes — conceptually the same levers as cliff's fellowship and
  departure scenarios.

---

## cliff vs. peds-subspec: design comparison

| Dimension | cliff (this repo) | Sheps peds-subspec |
|---|---|---|
| Model class | Cohort Monte Carlo (10,000 iterations over aggregate flows) | Individual-level dynamic microsimulation |
| Unit simulated | Subspecialty cohorts | Synthetic individual providers |
| Horizon | 2025 → 2029 (5 yr) | 2020 → 2040 (20 yr) |
| Domain | 3 gyn subspecialties (FPMRS/URPS, GO, MIGS) | 14 pediatric subspecialties |
| Geography | National; URPS access mapped to county | National + Census region + division |
| Entry | ACGME/NRMP fellowship counts → active conversion | Fellowship completions → active conversion |
| Exit | Multi-source **empirical departure hazard** (NPPES/Medicare/PECOS/Open Payments), board-validated 94.4% | Age-specific attrition/retirement assumptions |
| Output | Headcount, replacement ratio; URPS supply-vs-demand & effective adequacy | Headcount + clinical-time equivalent; supply-vs-child-pop |
| Uncertainty | Monte Carlo 95% intervals | Scenario-based |

**The honest read:** their 20-year individual microsimulation with subnational
geography is a more elaborate *projection engine*; cliff's departure signal is a
more defensible *empirical input* (multi-registry, externally validated against
state boards) than assumed age-specific attrition, and cliff's near-term
(5-year) horizon is deliberately chosen for decision relevance. The two designs
are complementary, and cliff's is appropriate for its question.

---

## Paste-ready manuscript text

**Discussion — situating the approach (drop-in paragraph):**

> Our approach parallels the microsimulation framework recently used to forecast
> the United States pediatric subspecialty workforce through 2040, which ages
> individual providers forward under age-specific entry and attrition and reports
> supply at national and subnational levels.¹ We adopt the same conceptual
> levers — fellowship inflow, conversion to active practice, and departure — but
> differ deliberately in two respects. First, rather than assuming age-specific
> attrition, we estimate departure empirically from concordant national
> registries (NPPES, Medicare Part B/D, PECOS, and Open Payments) and validate it
> against state medical-board records, yielding 94.4% agreement. Second, we
> restrict the horizon to five years (2025–2029), the interval over which
> fellowship-capacity decisions can plausibly respond, and propagate uncertainty
> through a 10,000-iteration Monte Carlo rather than discrete scenarios. As in
> the pediatric work, a nationally adequate count can mask maldistribution; we
> therefore report the geographic concentration and demographic composition of
> the subspecialty workforce alongside the aggregate projection.

**Methods — one-line citation of the modeling precedent:**

> Cohort projections follow the workforce-modeling tradition applied to the US
> pediatric subspecialties,¹ adapted here to a five-year horizon with empirically
> estimated departure.

**Reference:**

> 1. Fraher EP, Knapton A, McCartha E, Leslie LK. Forecasting the Future Supply
>    of Pediatric Subspecialists in the United States: 2020–2040. *Pediatrics.*
>    2024;153(Suppl 2):e2023063678C. doi:10.1542/peds.2023-063678C.

---

## What this unlocked in cliff (Task B)

The pediatric model's subnational framing is the reason cliff now reports
**geographic concentration and workforce-equity metrics** on the existing
de-identified roster — Gini/HHI/Lorenz across counties, states, and ACOG
districts, plus a demographic and access composition (gender, medical-school
class, IMG status, rurality, HPSA). See
[`WORKFORCE_CONCENTRATION_EQUITY.md`](WORKFORCE_CONCENTRATION_EQUITY.md),
`R/workforce_concentration_metrics.R`, and
`scripts/urps_concentration_equity_2026-08-01.R`.
