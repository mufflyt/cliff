# Retirement-hazard source: `legacy_modeled` vs `observed_hazard`

The scientific rule this seam enforces:

> **Historical exits are OBSERVED in `mufflyaccess`; future exits are SIMULATED in
> `cliff` from a hazard calibrated to those observations.**

`cliff` never re-derives retirement from provider records — that re-derivation
lives in the `mufflyaccess` producer (`analysis/urps_exit_panel/`), which freezes
the observed provider-month panel and the empirical age × year departure hazard.
`cliff` only *consumes* the frozen hazard and *projects forward stochastically*.

## The seam

`R/wc_retirement_hazard.R` is the single source of truth for **which** hazard the
projection runs on. `build_urps_projection.R` selects it via the
`CLIFF_RETIREMENT_SOURCE` environment variable:

| source | hazard | default? |
|---|---|---|
| `legacy_modeled` | the reviewed frozen band model (`BAND_EV`/`BAND_PY`, 2016–2021 primary window) | **yes** |
| `observed_hazard` | `mufflyaccess::urps_exit_hazard_by_age_year()` — the frozen empirical hazard | no |

```sh
Rscript scripts/urps_projection/build_urps_projection.R                       # legacy_modeled
CLIFF_RETIREMENT_SOURCE=observed_hazard Rscript scripts/urps_projection/build_urps_projection.R
```

Every run writes `urps_projection_2023_2040_v1.provenance.json` alongside the CSV,
recording `retirement_source`, the hazard artifact / version / hash, ascertainment
status, confirmation window, and the uncertainty method — so an `observed_hazard`
run can never be mistaken for a frozen-model run.

## Guarantees (what the tests pin)

1. **`observed_hazard` reads only `mufflyaccess`.** The hazard comes solely from
   `mufflyaccess::urps_exit_hazard_by_age_year()`; there is no duplicated
   retirement derivation inside `cliff`.
2. **Fail-loud unless observed.** `observed_hazard` stops unless
   `mufflyaccess::urps_retirement_status() == "observed"`. An unascertained or
   partially-observed retirement is never projected as if it were observed.
3. **`legacy_modeled` is byte-identical.** With the same seed the projection CSV is
   reproduced bit-for-bit (verified: the resolver echoes the frozen constants
   unchanged, and the committed artifact is unchanged by this seam).
4. **Future retirements stay stochastic.** The hazard calibrates the *forward
   process*; historical exit counts are never spliced into future years. The
   recurrence is the same real `wc_project_trajectory()`.
5. **The empirical hazard carries uncertainty.** The Monte Carlo draws
   `hz ~ Beta(band_ev + 0.5, band_py − band_ev + 0.5)` per band **per iteration**
   for both sources — the hazard is drawn, never fixed to its mean (no `cv = 0`).
6. **Sparse cells are pooled.** The observed age × year cells are aggregated onto
   the engine's age bands using provider-years as the risk set, pooling over ages
   within a band and over calendar years (the observed history is short). A band
   with no person-years gets `NA`, which the engine fills with the max hazard.
7. **Provenance is recorded** on every run (the sidecar above).

## Why `observed_hazard` is NOT the default yet

Making it the default now would merely route the architecture through the
**synthetic/example** artifacts and declare victory before the empirical retirement
calibration exists. The seam is built and tested so it is *ready*; promoting it is
gated on real data and a back-test.

### Promotion sequence

1. **Merge the `mufflyaccess` exit panel** (PR #8) and bump this repo's
   `mufflyaccess` pin to a build that ships `urps_exit_hazard_by_age_year()`.
2. **Populate the real provider-month evidence** and run
   `analysis/urps_exit_panel/build_exit_panel.R` in `mufflyaccess` to freeze
   `urps_exit_hazard_by_age_year.csv` from actual records (not the example).
3. **Validate the frozen hazard** and flip the `mufflyaccess` manifest to
   `retirement_ascertainment = "observed"` so the fail-loud guard opens.
4. **Back-test both sources** (below).
5. **Only then** change the default to `observed_hazard`.

### The back-test that must pass first

The bar is **not** "does `observed_hazard` draw a nicer curve." It is:

> Using provider activity observed through year *t*, does the `observed_hazard`
> model predict actual departures and active supply in *t+1*, *t+2*, *t+3* better
> than the frozen 2016–2021 model — with **calibrated** intervals?

This is the exact weakness the supply back-test already surfaced in the frozen
model: **systematically low forecasts and intervals that were far too narrow.**
Hold out the most recent observed years, project both sources from the earlier
history, and compare point error **and** interval coverage against the held-out
truth. `observed_hazard` becomes the default only if it reduces forecast error and
its intervals actually cover at their nominal rate.
