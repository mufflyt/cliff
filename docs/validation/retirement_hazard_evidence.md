# Validation: can `retirement_source = "observed_hazard"` be built and back-tested?

**Date:** 2026-08-16
**Verdict: NO — not yet, and not for the reason the plan assumed.**
**The default remains `legacy_modeled`. Nothing was promoted, and no evidence was manufactured.**

This is the report that must exist before the default changes. It answers three
questions: is the seam correct, does the evidence exist, and can a held-out back-test
discriminate between the two sources.

---

## Summary

| question | answer |
|---|---|
| Is the `legacy_modeled` / `observed_hazard` seam built and fail-closed? | **Yes**, already, and it behaves correctly |
| Does `mufflyaccess` serve observed exit evidence? | **No** — `urps_retirement_status()` is `not_ascertained` |
| Can the workforce count series back-test a retirement model? | **No** — it contains zero exits by construction |
| Does an observed exit panel exist anywhere? | **Yes** — upstream in the isochrones cohort, 297 exits |
| Is `legacy_modeled` actually "modeled"? | **No** — it is already an *observed* hazard from that panel |

The headline correction: **`legacy_modeled` and `observed_hazard` are not
"assumption vs evidence."** Both are empirical. They differ in **vintage, window,
pooling, and anchoring**. The work ahead is to promote the panel into `mufflyaccess`
as a versioned artifact, not to replace a guess with a measurement.

## 1. The seam is correct

`R/wc_retirement_hazard.R` already satisfies most of the stated requirements:

| requirement | status |
|---|---|
| 1. `/mufflyaccess` sole source; no cohort logic re-created in cliff | **met** — the observed path calls only `urps_retirement_status()` and `urps_exit_hazard_by_age_year()` |
| 2. `legacy_modeled` preserved bit-for-bit | **met** — the legacy branch echoes the caller's frozen constants back with provenance |
| 3. explicit confirmation window | **partial** — recorded in provenance, but not enforced against the producer's manifest |
| 4. exits distinguished from unknown / lost-to-follow-up | **not met upstream** — see §5 |
| 5. principled smoothing for sparse cells | **not met** — the observed path sums raw counts onto bands; that is aggregation, not smoothing |
| 6. uncertainty propagated stochastically | **met** — `hz ~ Beta(ev + ½, py − ev + ½)` drawn per MC iteration, not a fixed mean |
| 7. provenance recorded | **met** — source, artifact, version, hash, ascertainment status, window, uncertainty method |
| 8. fail closed when evidence absent/invalid | **met, and verified firing** — see §2 |

## 2. The evidence does not exist

```r
mufflyaccess::urps_retirement_status()
#> "not_ascertained"

mufflyaccess::urps_exit_hazard_by_age_year()
#> Error: observed exit hazards are 'not_ascertained' in contract 3.0.0:
#>   n_retired is served as NA, never 0. Observed historical departures are
#>   unavailable; modeled retirement/departure is cliff's responsibility.
#>   Do NOT substitute 0.
```

`urps_exit_counts()` refuses identically. This is the *correct* behaviour: the producer
refuses to serve a zero it cannot justify, and cliff's seam refuses to project it.
Requesting `observed_hazard` today fails closed, as designed.

## 3. The workforce count series cannot back-test any retirement model

This is the finding that changes the plan. `urps_counts_long()` serves annual national
active counts for 2013–2023, which looks like exactly the held-out series a back-test
needs. It is not.

Applying the accounting identity `exits(t) = active(t−1) + entrants(t) − active(t)`:

| year | `n_active` | entrants | **implied exits** |
|---:|---:|---:|---:|
| 2013 | 655 | 655 | — |
| 2014 | 830 | 175 | **0** |
| 2015 | 932 | 102 | **0** |
| 2016 | 968 | 36 | **0** |
| 2017 | 1001 | 33 | **0** |
| 2018 | 1041 | 40 | **0** |
| 2019 | 1089 | 48 | **0** |
| 2020 | 1099 | 10 | **0** |
| 2021 | 1180 | 81 | **0** |
| 2022 | 1234 | 54 | **0** |
| 2023 | 1306 | 72 | **0** |

**Zero implied exits in every year.** Two further checks confirm it is structural, not
coincidental:

* `n_active == n_ever_certified` in **every row**;
* cumulative entrants from 2013 = **1,306** = `n_active(2023)`, exactly.

The series is a **cumulative sum of entrants**. It is not an independent measurement of
workforce size, and `n_retired` is `NA` throughout, consistent with
`retirement_status = "not_ascertained"`.

**Consequence.** Scoring any retirement model against this series would reward the model
that predicts zero exits. A back-test run against it would report the legacy hazard as
badly biased — and that finding would be an ascertainment artifact, not evidence.

This also **reinterprets a previously noted result**. The earlier observation that
2020→2023 forecasts "under-predicted observed workforce" with intervals that were "too
narrow" is expected under this construction: the reference series is an upper bound in
which nobody ever leaves, so *any* model with exits under-predicts it by design. That
observation should not be treated as evidence that the retirement model is too
aggressive.

## 4. An observed exit panel does exist — upstream

From the isochrones cohort (`manuscript/tables/table1_physician_characteristics.csv`),
2,985 providers across the three subspecialties:

| | |
|---|---:|
| providers with `cert_year` (⇒ person-time start) | 2,985 |
| providers with an observed `retirement_year` (⇒ exit date) | **297** |
| of which URPS | **104** |
| GO / MIGS | 138 / 55 |

`cert_year → retirement_year` is exactly a provider-year exit panel. So the raw material
for `observed_hazard` exists; it simply has never been promoted into `mufflyaccess` as a
frozen, versioned artifact.

## 5. Right-censoring is real, large, and already handled

URPS annual exit rate reconstructed from the panel:

| window | exits | person-years | rate |
|---|---:|---:|---:|
| fully observable 2016–2021 | 41 | 6,397 | **0.641 %/yr** |
| provisional 2022–2023 | 63 | 2,173 | **2.899 %/yr** |
| | | | **4.5× higher** |

2023 alone runs at 4.45 %/yr. This is precisely the artifact the frozen model's window
choice exists to exclude — with Medicare/NPPES data through 2023 and a 3-year cessation
rule, 2022–2023 exits are unconfirmable and pile up as provisional over-flags. **The
empirical panel confirms the 2016–2021 window was the right call.** Any future observed
hazard must apply the same confirmation window, or it will roughly quadruple the
projected departure rate on an artifact.

Two further cautions the panel raises, both bearing on requirement 4:

* **Median age at exit is 48** (IQR 39–60, min 30). That is not retirement in the
  ordinary sense. The signal is practice cessation / loss to follow-up, and it must be
  labelled as such. An `observed_hazard` presented as "retirement" would overstate what
  is measured.
* Exits before 2016 are absent entirely (0 in 2013–2015), which is an observation-window
  boundary, not a period of no departures.

## 6. `legacy_modeled` is already the observed hazard

The frozen URPS-only band table is **35 events / 6,403 person-years = 0.547 %/yr**. The
panel reconstruction above gives **41 events / 6,397 person-years** over the same window.

The person-years agree to 0.1 %. The 6-event difference is the **non-Open-Payments
anchor rule**: `scripts/build_nrmp_benchmark.R` nulls departures whose only evidence is
Open Payments, so 41 raw − 6 unanchored = 35. The reconciliation is exact.

So the current default is not an assumption. It is the same observed panel, over the
fully observable window, with a corroboration rule applied. The naming
`legacy_modeled` / `observed_hazard` is misleading and should be revisited —
something like `frozen_2016_2021` / `mufflyaccess_panel` would describe the real
distinction.

## 7. What `mufflyaccess` must serve before this can proceed

`observed_hazard` needs one artifact and one status flag:

1. **`urps_exit_hazard_by_age_year()`** — columns `age`, `year`, `n_at_risk`, `n_exits`
   (cliff already requires `age`, `n_at_risk`, `n_exits`), built from the provider-year
   panel with:
   * an explicit **confirmation window**, defaulting to the 2016–2021 fully observable
     window, with the manifest recording `exit_confirmation_months`;
   * **exit vs lost-to-follow-up distinguished**, never collapsed — a provider who
     disappears is censored, not exited;
   * the corroboration rule stated (the non-Open-Payments anchor, or its successor).
2. **`urps_retirement_status()` returning `"observed"`** only once the above is frozen
   and validated. Until then the current `not_ascertained` is the correct answer.

Then cliff needs one change of its own: **requirement 5 is genuinely unmet.** The
observed path currently sums raw age × year counts onto bands. With 41 events spread
over seven bands, several bands will have 0–2 events, and raw proportions there are
unstable. Partial pooling (a hierarchical or penalised age curve, or an explicit prior)
should be added *before* the hazard is used, not after.

## 8. The back-test, when it becomes possible

It cannot be run today, because the only held-out series contains no exits (§3). When
the panel exists, the defensible design is to hold out **the panel itself**, not the
count series:

* fit the hazard on exits observed through year *t*, project *t+1…t+3*;
* score against **observed exits by age band** in the held-out years, not total
  headcount — headcount is contaminated by the entrant accumulator;
* report bias, MAE/RMSE, and interval coverage of the Beta-posterior draws;
* repeat across several origin years, subject to the confirmation window leaving enough
  fully observable follow-up (with 2016–2021 observable, realistically 2018 and 2019
  origins);
* compare against a naïve constant-hazard baseline. A hierarchical age model must beat
  "last year's rate, applied to everyone."

## 9. Recommendation

1. **Do not promote `observed_hazard`.** The default stays `legacy_modeled`.
2. **Do not run a back-test against `urps_counts_long()`**, and treat the earlier
   2020→2023 "under-prediction" as an artifact of that series until re-examined.
3. **Build the exit panel in the `mufflyaccess` producer**, with the confirmation window
   and the exit/LTFU distinction as first-class fields.
4. **Add partial pooling to cliff's observed path** before it is ever used.
5. **Rename the sources** to describe what actually differs.
6. Consider whether "retirement" is the right word for a signal whose median age is 48.
