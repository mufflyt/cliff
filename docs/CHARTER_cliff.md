# cliff repository charter — consume the SSOT

**Adopted 2026-07-27.** One-sentence rule: **isochrones builds the roster, mufflyaccess certifies and serves the
number, and cliff models what happens next.**

## Dependency direction (no reverse arrows)

```
ABOG / ABU source files
          ↓
      isochrones            provider-level construction (owns provider truth)
          ↓
 canonical hashed artifacts artifacts/workforce/urps_provider_snapshot.parquet
          ↓                 urps_counts_by_year.csv, urps_manifest.json
     mufflyaccess           validated, stable R API (owns the published number)
          ↓
 cliff / twostep / manuscripts / apps   (transform the baseline; never redefine it)
```

## What cliff owns

- Workforce projections; entrants and retirement modeling; scenario analyses.
- Figures, tables, Shiny apps, and manuscript numbers.
- Tests that its baseline **agrees with** mufflyaccess.

## What cliff must NOT do (critical rule: cliff cannot redefine the baseline)

- No independent derivation of the national URPS count.
- No hardcoded headline counts (**1031, 1339, 1295, 264, 308**).
- No separate "canonical" reconciliation file used as a source of truth
  (`docs/SSOT_URPS_BASELINE_RECONCILIATION.md` is retained **archival / non-authoritative**).
- No reading raw ABOG/ABU rosters **solely to establish the baseline**. (Scripts that read the *enriched*
  rosters for procedure attribution, geography, or Table 1 are downstream analyses, not baseline derivation, and
  are retained — see "Open items" for the review of `build_table1_urps`.)

## How cliff obtains the baseline

Only through the single seam `R/urps_baseline.R`, which delegates to the mufflyaccess SSOT:

```r
urps_without_urology <- mufflyaccess::urps_count(year = 2023L, include_urology = FALSE)  # headline 1,031
urps_with_urology    <- mufflyaccess::urps_count(year = 2023L, include_urology = TRUE)   # headline 1,339
# in cliff, always via:  urps_baseline(2023L, include_urology = FALSE / TRUE)
```

Three time attributes must never be collapsed into one ambiguous year:
- **Measure year** — 2023 (the active-workforce year).
- **Source snapshot date** — e.g. 2026-07-22 (when isochrones froze the roster).
- **Model baseline year** — 2025 (the projection start).

## Guard

`tests/testthat/test-cliff-baseline-charter.R` fails if a hardcoded national baseline literal
(1339 / 1031 / 1295) is reintroduced into live cliff R code, if the seam stops delegating to
`mufflyaccess::urps_count()`, or (once the API ships) if the served values drift from 1,031 / 1,339.

## Status / blocked on the upstream chain (as of 2026-07-27)

The charter direction is **in place in cliff**, but activation is **blocked** because the upstream is not yet
built:

| Prerequisite | State |
|---|---|
| isochrones `artifacts/workforce/urps_provider_snapshot.parquet` + `urps_counts_by_year.csv` + `urps_manifest.json` | **not yet produced** |
| `mufflyaccess::urps_count()` / `urps_counts()` / `urps_provenance()` / `validate_urps_ssot()` | **not yet exported** (installed mufflyaccess lacks them) |
| cliff `R/urps_baseline.R` seam | **present**; fails loud until the API ships (does not fall back to deriving a baseline) |

### Remaining cliff work, gated on the upstream shipping

1. Switch the live baseline source from the frozen `data/workforce_projections_consolidated.csv` (currently
   **1,295**) to `urps_baseline()` → mufflyaccess (**1,339 / 1,031**). **This changes published manuscript
   numbers** (1,295 → 1,339) and must be done as a scoped, reviewed re-run once mufflyaccess serves the value.
2. Review `scripts/build_table1_urps_*.R` — the 2013-2023 active workforce table is charter-assigned to
   isochrones; decide whether cliff's Table 1 should consume the isochrones artifact instead of rebuilding.
3. Pin the mufflyaccess dependency to a released version in `DESCRIPTION` once the API is tagged.
