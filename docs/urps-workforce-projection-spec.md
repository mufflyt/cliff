# URPS Workforce Projection: Target Design + Methodology Spec

Status: planning spec for **cliff's** URPS projection layer, the layer cliff owns.
Companion to the cross-repo governance set (`REPO_CHARTERS.md`, `data-ownership.md`),
currently maintained in `twostep/docs`. This file changes no code and asserts no
new numbers; it is the design cliff builds toward.

## What this adapts, and what it does not

The reference is the UNC Sheps Center + American Board of Pediatrics Foundation
model, "The Future Supply of Pediatric Subspecialists" (the ABPv2 tool), built
with Strategic Modelling Analysis & Planning Ltd (SMAP), PI Erin Fraher. Methods:
Fraher et al., "Forecasting the Future Supply of Pediatric Subspecialists in the
United States: 2020-2040," *Pediatrics* Feb 2024 supplement (PubMed 38300007).

We adapt its **architecture and methodology**, NOT its data. ABPv2 covers 14
**pediatric** subspecialties; our target is the **URPS** (urogynecology and
reconstructive pelvic surgery) workforce with the ABOG/ABU dual pathway. Its CWE
ratios, exit rates, and counts are pediatric and are not reused. Where an input
has no URPS-specific source yet, this spec marks it TBD rather than borrowing a
pediatric value.

## Reference tool parameterization (target for cliff's URPS app)

ABPv2 encodes state in a URL, e.g.
`?proj=sscode-0_location-0_headcount-1_pop-0_scenario-72`. The axes map onto our
lineage almost one-to-one:

| ABPv2 axis | Meaning | URPS lineage equivalent |
|---|---|---|
| `sscode` | subspecialty (or all combined) | URPS (and, if generalized, the other six OB/GYN subspecialties) |
| `location` | national / census region / division | national / CONUS / state (our geography axis) |
| `headcount` (0/1) | headcount vs Clinical Workforce Equivalent | measure axis: `board_certified_active` vs a clinical-time-adjusted measure |
| `pop` (0/1) | total vs per 100,000 children | total count vs per-capita access (per 100k women / women 65+); the per-capita denominator is twostep's ACS demand |
| `scenario` | one of the "what if" scenarios | cliff's entrants / exit-rate / hours scenarios |

The target app should expose the same four toggles (subspecialty, geography,
headcount-vs-CWE, total-vs-per-capita) plus a scenario selector, with 2023 as the
baseline year and a projection horizon to be set (ABPv2 uses 2020 to 2040; we
should anchor on our baseline measure year 2023).

## Extracted methodology, mapped to cliff assumptions

ABPv2 is an individual-level **microsimulation** (stock-and-flow). The URPS analog:

1. **Baseline stock (t0).** The starting workforce is the SSOT count obtained via
   `mufflyaccess::urps_count(year = 2023L, measure = "board_certified_active",
   geography = ..., include_urology = ..., incomplete = "error")` (contract 3.0.0:
   national 1,306, CONUS 1,303; ABOG 1,027 + ABU net-new 279). cliff **consumes**
   this, it must never re-derive or hardcode it (guarded by the no-hardcoded-count
   tests: see the cliff consumer tests + the twostep guard for the pattern).

2. **Inflow (entrants).** ABPv2 varies "the number of fellows entering training."
   URPS analog: FPMRS fellowship graduates entering the ABOG pathway plus the ABU
   net-new contribution. This is cliff's entrants model; the entrant series is a
   cliff input, not a mufflyaccess count.

3. **Outflow (attrition / exit / retirement).** ABPv2 varies "the rate at which
   subspecialists leave the workforce." URPS analog: cliff's existing age-band
   retirement hazards and retire-at-65 scenarios. Keep cliff's frozen legacy
   projection cohort (e.g. 1,295) clearly labeled and separate from the SSOT
   baseline.

4. **Geographic mobility.** ABPv2 models moves after training and during career at
   region/division level. URPS analog: an enhancement, model state-to-state moves
   so subnational projections do not assume providers stay where they trained.
   Requires a mobility source (TBD).

5. **Clinical Workforce Equivalent (CWE).** ABPv2 CWE = headcount adjusted for the
   self-reported proportion of time in direct clinical care (pediatric CWE per 100k
   children ranged 0.23 to 4.36 in 2020). URPS analog: `CWE = headcount x
   clinical_time_fraction`. **The URPS clinical-time fraction has no source in the
   current lineage, TBD.** Do not borrow a pediatric ratio; leave CWE pending until
   a URPS clinical-effort source exists, and until then project headcount only.

6. **Population denominator (per-capita).** ABPv2 offers per 100,000 children.
   URPS analog: per 100,000 women, or women 65+ for the pelvic-floor-disorder
   demand framing. The denominator surface is **twostep-owned** (its ACS pulls),
   not mufflyaccess's and not cliff's.

## Scenario menu (ten "what ifs")

ABPv2 offers ten scenarios spanning three levers: fellow-supply change, exit-rate
change, and clinical-hours change. cliff should expose the same three levers for
URPS (entrants up/down, attrition up/down, clinical-effort up/down), realized
through its existing scenario machinery. Each scenario is a transformation of the
SSOT baseline, never a redefinition of it.

## Boundary compliance (non-negotiable)

This projection is cliff-owned and must obey the one-direction contract:

- **Numerator (baseline stock)**: `mufflyaccess::urps_count()` only. No hardcoded
  1,306 / 1,303 / 1,332 / 1,329 / 1,339 / 1,295 in cliff production code.
- **Per-capita denominator**: twostep's ACS demand surface, on the **same
  geography** as the numerator. cliff must enforce numerator/denominator geography
  agreement (mirror twostep's `assert_matching_geography()` precondition, or reuse
  it once the shared package exposes it).
- **Provider locations / reachability** (if the app maps access): isochrones
  artifacts.
- cliff may transform the baseline into futures; it may not redefine who, where, or
  how many.

## Open items (must be resolved before build, do not fabricate)

- URPS **clinical-time fraction** for CWE (no current source). Until then: headcount only.
- **Projection horizon** end year (ABPv2 uses 2040; confirm for URPS).
- **Entrant series** (FPMRS graduates + ABU net-new by year) source and cadence.
- **Geographic mobility** data for subnational projection.
- **Per-capita denominator** choice: all women vs women 65+ (demand framing).
- The national ACS reference-scalar seam (see `data-ownership.md` in the governance set).

## Prototype

An interactive target-design mockup of the four toggles + scenario selector driving
an illustrative projection chart was built as a design artifact (baseline 1,306 is
the only real value; all curves are schematic placeholders; CWE is disabled pending
a URPS source). Rebuild it in cliff's own app stack when the projection layer is
implemented.

## Sources

- ABPv2 tool: https://abpv2-dept-healthworkforce.apps.cloudapps.unc.edu/
- Overview: https://www.pedsubspecforecast.unc.edu/
- Methods paper (PubMed 38300007): https://pubmed.ncbi.nlm.nih.gov/38300007/
- ABP program page: https://www.abp.org/content/projecting-future-us-pediatric-subspecialty-workforce
- Sheps Center Health Workforce program: https://www.shepscenter.unc.edu/programs-projects/workforce/people/
