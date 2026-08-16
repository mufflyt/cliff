# Adjudication: `sensitivity_grid.csv` + `sensitivity_grid_summary.csv`

**Status:** **CLOSED 2026-08-16 — MIGS withdrawn from scope; generator and supplement now fail closed.**
**Date:** 2026-08-16
**Queue:** `scripts/ci/artifact_drift_debt.txt` (3 of 10)

Sections 1-10 are the adjudication as performed, *before* anything was changed.
Section 11 records the decision and what was then modified.

## Classification — three findings, only two of them drift

This artifact must **not** be filed as "drift". Three distinct things happened and they
carry different verdicts:

| # | finding | verdict |
|---|---|---|
| 1 | URPS ratios 5.61 → 5.38 (and 6.01 → 5.75, 3.69 → 3.57) | **legitimate** upstream re-basing, the 1,295 → 1,306 cohort migration |
| 2 | MIGS absent from the window sensitivity | **legitimate** upstream scope change; the current generator intentionally produces only URPS and GO |
| 3 | `sensitivity_grid.R` manufactures an `NA` MIGS row when MIGS is absent | **DEFECT** in the published generator, not drift. The supplement's reindexing has the same defect |

The upstream scope change is correct. **The downstream failure to adapt to it is a
generator/contract defect**, and it is what makes the regenerated artifact corrupt
rather than merely different. Regenerating would ship a syntactically valid CSV whose
third row is `NA,NA,NA,...` into a published supplement table.

---

## 1. Artifact and generator

| | |
|---|---|
| Artifacts | `data/sensitivity_grid.csv` (81 rows), `data/sensitivity_grid_summary.csv` (3 rows) |
| Generator | `scripts/sensitivity_grid.R` (writes both) |
| Sole input | `data/departure_window_sensitivity.csv` |
| **Manuscript exposure** | **YES** — `supplement_WORKFORCE_CLIFF.Rmd` Table S17, and six getters in `manuscript/R/workforce_statistics.R` |
| Test consumers | 4 test files |

Unlike artifacts 1 and 2, **this one is published.** Both artifacts were committed
together at `ac273bb` (2026-07-24), the extraction commit.

The generator is a pure deterministic transform: it crosses window × rate-multiplier ×
conversion and computes `ratio = dynamic_ratio * conv / mult`. It has no randomness and
no other input, so *everything* here is inherited from upstream.

## 2. Committed vs regenerated

| cohort | | n_cells | above | at | below | worst_ratio | oneway_min |
|---|---|---:|---:|---:|---:|---:|---:|
| GO | committed | 27 | 26 | 1 | 0 | 1.003 | 2.37 |
| GO | regenerated | 27 | 26 | 1 | 0 | 1.003 | 2.37 |
| URPS | committed | 27 | 25 | 1 | 1 | **0.861** | **1.87** |
| URPS | regenerated | 27 | 25 | 1 | 1 | **0.833** | **1.793** |
| MIGS | committed | 27 | 27 | 0 | 0 | 1.703 | 3.707 |
| MIGS | regenerated | — | — | — | — | — | — |

Grid rows: **81 → 54**. Summary rows: **3 → 2 plus a corrupt row** (below).

## 3. Three separate causes, not one

### (a) URPS re-based to the 1,306 cohort — legitimate

The upstream `dynamic_ratio` values moved:

| window | committed | current |
|---|---:|---:|
| fully_obs | 5.61 | 5.38 |
| drop2 | 6.01 | 5.75 |
| full | 3.69 | 3.57 |

GO is **unchanged** (7.11 / 6.37 / 4.30). The URPS move is the repo-wide 1,295 → 1,306
cohort migration, landed in `b50f96d` (2026-08-02, *"rebuild supply/age-vector/window
artifacts on the 1,306 cohort"*). 5.61 is the legacy frozen-SGS ratio; 5.38 is the
current SSOT `replacement_ratio`. This is an input change, correctly propagated.

### (b) MIGS dropped upstream — deliberate

`scripts/build_departure_window_sensitivity.R` now builds only two cohorts:

```r
ages_of <- list(URPS = urps_ages, GO = go_ages)
```

This matches the documented reviewer decision (2026-07-19) that MIGS is an exploratory
focused-practice cohort, not pooled with the board-certified ones. The upstream at
`ac273bb` did carry MIGS (11.12 / 13.16 / 7.30); it does not now.

### (c) The generator does not handle (b) — **a real defect**

`scripts/sensitivity_grid.R:45` reindexes on a hardcoded three-cohort list:

```r
summ <- summ[match(c("GO","URPS","MIGS"), summ$subspecialty_abbrev), ]
```

With MIGS absent, `match()` returns `NA` and the row is written out literally:

```
GO,27,26,1,0,1.003,2.37,full,3,0.7
URPS,27,25,1,1,0.833,1.793,full,3,0.7
NA,NA,NA,NA,NA,NA,NA,NA,NA,NA
```

**Running the generator today produces a corrupt artifact.** It does not fail; it emits
a row of `NA`s. This is the reason the artifact must not simply be regenerated.

`supplement_WORKFORCE_CLIFF.Rmd:1078` performs the **same** hardcoded reindex, so
Table S17 would render an all-`NA` row rather than dropping the cohort.

## 4. The supplement already contradicts its own table

Independent of any drift, in the committed state:

* **Table S17** renders `sprintf("%.2f", worst_ratio)` from the artifact:
  **GO 1.00, URPS 0.86**.
* **The prose two lines below** (`supplement_WORKFORCE_CLIFF.Rmd:1092`) states:
  *"Gynecologic Oncology was at replacement (1.03) and URPS was below replacement
  (0.88)"*.

These disagree, and both were committed on 2026-07-24.

**The prose is not fabricated — it was correct, for a vintage that no longer exists.**
Traced to isochrones `b0d6c2f96` (2026-07-19, *"Peer review round 3: textual-consistency
corrections"*), where the grid summary read:

```
GO,27,26,1,0,1.027,2.45,full,3,0.7        -> "1.03"
URPS,27,26,0,1,0.882,1.943,full,3,0.7     -> "0.88"
```

driven by upstream `full`-window ratios of GO 4.40 and URPS 3.78. Those are exactly the
values the prose implies (4.414 and 3.771 back-solved from `ratio = dr * 0.7 / 3`).

The literal then froze while the artifact moved twice:

| vintage | GO worst | URPS worst | |
|---|---:|---:|---|
| isochrones `b0d6c2f96`, 2026-07-19 | 1.027 | 0.882 | **the prose was written here and never updated** |
| cliff `ac273bb`, 2026-07-24 (committed) | 1.003 | 0.861 | prose already stale on arrival |
| current, 1,306 basis | 1.003 | 0.833 | |

**Authoritative side: the artifact.** The prose is a frozen snapshot of a superseded
computation, and it was already inconsistent with the table beside it on the day both
were migrated into this repository. Regeneration widens the URPS gap further, prose 0.88
against artifact 0.83.

The fix is not to re-type the number. It is to make the prose an inline expression
reading the same artifact the table reads, so the two cannot diverge again.

## 5. Authoritative side

**The regenerated URPS numbers are right; the regenerated MIGS handling is wrong; the
prose is wrong in every version.**

* URPS 0.833 / 1.793 is correct for the adopted 1,306 cohort. The committed 0.861 / 1.87
  is correct only for the retired 1,295 basis.
* Dropping MIGS is the correct scientific decision, but emitting `NA` is not a way of
  dropping it.
* The prose literals must become inline R expressions reading the artifact, like the
  table beside them, or they will go stale again on the next re-basing.

The scientific conclusion is **unchanged in direction**: every one-way sensitivity stays
above replacement (URPS one-way minimum 1.87 → 1.79, still > 1.05), and the only
below-replacement cell remains the compound worst case. The headline claim survives; the
numbers behind it do not.

## 6. Recommended action (not taken)

1. **Fix the generator first.** Replace the hardcoded `match(c("GO","URPS","MIGS"), ...)`
   with an intersection against the cohorts actually present, and **fail loudly** if a
   cohort named in the manuscript is missing. A silent `NA` row in a published table is
   the worst available outcome.
2. **Decide MIGS explicitly.** Either it is out of the grid (then remove it from
   Table S17 and the surrounding prose), or it is in (then the upstream window
   sensitivity must build it again). Right now the supplement asks for it and the data
   no longer supplies it.
3. **Replace the hardcoded prose numbers** at `:1092` with inline expressions from the
   artifact.
4. **Then regenerate** on the 1,306 basis, in a commit that says the URPS ratios were
   re-based and MIGS was withdrawn, citing this record.
5. Re-check the four dependent tests and the six `workforce_statistics.R` getters, which
   will start returning `NA` for MIGS.

## 7. Shared root cause carried forward

This is the **same 1,295 → 1,306 cohort migration** behind artifact 2's divergence, seen
from a different angle: there the cube kept a stale hazard, here the grid kept a stale
inherited ratio. Expect it again in the remaining queue, particularly the four
`urps_baseline_scenarios/table*_v3.0.0.csv` artifacts.

The new and more general lesson is the **hardcoded cohort list**. Three places name
`c("GO","URPS","MIGS")` as a literal — the generator, the supplement chunk, and the
supplement prose — and none of them notices when the data stops containing one. That
pattern, not the numbers, is what should be searched for across the remaining artifacts.


---

## 11. Resolution (2026-08-16)

**Decision: MIGS is withdrawn. The current scope of this sensitivity is URPS + GO.**

MIGS was not resurrected to preserve a historical table shape. The upstream window
generator defines the scientific scope, and it builds only URPS and GO; downstream
publication code now follows that scope rather than manufacturing a MIGS result from
another pathway.

**What changed**

1. `scripts/sensitivity_grid.R` declares `REQUIRED_COHORTS` and `WITHDRAWN_COHORTS`,
   with `MIGS` listed as withdrawn and the reason recorded inline. A required cohort
   that is absent and not explicitly withdrawn stops the run, naming it.
2. **The artifact was regenerated on the URPS + GO scope**: 81 → 54 grid rows,
   3 → 2 summary rows, and URPS `worst_ratio` 0.861 → **0.833**,
   `oneway_min` 1.87 → **1.793**. GO is unchanged at 1.003 / 2.37.
3. **Appendix Tables S17 and S7 now derive their cohort set from the artifact**
   instead of a hardcoded vector, and five further two-cohort reindexes elsewhere in
   the supplement were routed through one fail-closed helper, `.cohort_rows()`.
4. **The stale S17 prose is now generated.** `(1.03)` and `(0.88)` are replaced by
   inline expressions reading the same object the table reads, so the two cannot
   diverge again. It renders GO **1.00** and URPS **0.83**.

**The scientific conclusion is unchanged in direction.** Every one-way sensitivity
still exceeds replacement (URPS one-way minimum 1.87 → 1.79, still > 1.05), and the
only below-replacement cell is still the compound worst case.

**Historical provenance, preserved here rather than in the artifact**

| vintage | GO worst | URPS worst | MIGS worst |
|---|---:|---:|---:|
| isochrones `b0d6c2f96`, 2026-07-19 | 1.027 | 0.882 | 1.72 |
| cliff `ac273bb`, 2026-07-24 | 1.003 | 0.861 | 1.703 |
| **current, URPS + GO scope** | **1.003** | **0.833** | withdrawn |

The three-cohort result was valid for the three-cohort analysis. It is no longer part
of the current analysis, and it is recorded here rather than carried in a published
table.

**Tests updated, and one of them was holding the defect in place**

* `test-workforce-cliff-data-properties.R` now derives the grid's expected cohort set
  from `departure_window_sensitivity.csv` instead of pinning `SUBS`.
* `test-workforce-cliff-data-analysis.R` asserts MIGS is *absent* rather than
  asserting on a MIGS row.
* `test-workforce-cliff-peer-review-fixes.R` asserted the supplement contained the
  literal strings `(1.03)` and `(0.88)`. **Pinning a frozen number in a test froze the
  defect too**: it would have failed had anyone corrected the prose. It now asserts the
  prose is generated, and that the generated values agree with the artifact.

**A gate caught a mistake in this very fix.** The first version of the S17 helper was
named `.w()`, and `test-ssot-no-stale-published-numbers.R` flagged it as rebound at
lines 993/995 — the gate builds a regex from the helper name, and the unescaped `.`
made `.w` match `ow <-` two chunks away. Renamed to `s17_worst()`. This is the same
class of failure as the `cf()` incident in CLAUDE.md, caught before rendering.

**Contract to carry forward:** manuscript numerical prose should be generated from the
same authoritative object as its table whenever practical. Prose and artifact holding
independent frozen copies of the same number is what produced this, not carelessness.
