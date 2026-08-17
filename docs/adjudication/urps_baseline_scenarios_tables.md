# Adjudication: the four `urps_baseline_scenarios/table*_v3.0.0.csv`

**Status:** **CLOSED 2026-08-16.**
**Classification: generator defect — historical reference state was incorrectly allowed to float with the current SSOT.**
**The four committed artifacts are authoritative and correct, and are unchanged.**
**Date:** 2026-08-16
**Queue:** `scripts/ci/artifact_drift_debt.txt` (6-9 of 10), adjudicated as **one unit**

No committed artifact was modified. Only the generator changed, and after the repair all
four artifacts reproduce **byte-identically**.

---

## 1. One generator, one unit

| artifact | |
|---|---|
| `table1_published_preservation_v3.0.0.csv` | frozen published 1,295 projection, preserved |
| `table2_controlled_sensitivity_v3.0.0.csv` | every scenario through the real engine |
| `table3_count_age_decomposition_v3.0.0.csv` | separates count effect from age-structure effect |
| `table4_same_horizon_h4_v3.0.0.csv` | same-horizon (h=4) comparison |

All four are written by **`scripts/urps_baseline_scenarios/urps_scenario_analysis_v3.R`**
in a single run, so they were adjudicated together rather than four times over.

A second script in the same directory, `urps_baseline_scenarios_v3_hardened.R`, writes
the *non*-`v3.0.0` variants (`table1_published_preservation.csv`,
`table2_controlled_sensitivity.csv`) plus `scenario_trajectories.csv`,
`decomposition_count_vs_age.csv`, `engine_equivalence.csv`. **There is no two-writer
conflict**: the filenames are disjoint. Consumers are one test file
(`test-urps-baseline-scenarios.R`) and the two generators. No manuscript exposure.

## 2. What running the generator did

`exit 1`, with `Error: frozen baseline changed!` — **after** overwriting all four
artifacts.

| table | committed | regenerated |
|---|---:|---:|
| **1** `baseline_count` | 1295 | **1306** |
| **1** `projected_count` | 1505.4 | **1514.5** |
| **1** `ci_lower` / `ci_upper` | 1476 / 1535 | **1494 / 1525** |
| **1** `sd` | 15.2 | **7.91** |
| **1** `avg_annual_retirements` | 11.41 | **11.89** |
| **1** `replacement_ratio` | 5.61 | **5.38** |
| **2** `legacy_rerun` baseline | 1295 | **1306** |
| **3** `count_effect` baseline | 1295 | **1306** |
| **3** `count_effect` projected | 1594.3 | **1605.1** |
| **3** `d_projected_vs_ref` | **−10.8** | **0** |
| **3** `d_avg_ret_vs_ref` | **−0.04** | **0** |
| **4** `legacy_h4` baseline | 1295 | **1306** |

Two things matter more than the individual numbers:

* **Table 1 is a *preservation* table.** Its stated purpose, in the generator's own
  header, is that the frozen published 1,295 projection is *"retained EXACTLY and NOT
  recalculated"*. Regeneration replaced **every field of it** with the current 1,306
  projection while still labelling the row `legacy_frozen` / `frozen`.
* **Table 3's decomposition collapses to zero.** `d_projected_vs_ref` goes from −10.8 to
  **exactly 0**, because the "count effect" contrast becomes 1,306 against a 1,306
  reference — a null contrast. The quantity the table exists to report is annihilated,
  and the result still looks like a valid number.

## 3. Root cause

`urps_scenario_analysis_v3.R` obtained an **immutable historical constant from a mutable
live source**:

```r
frozen <- utils::read.csv(file.path(root, "data", "workforce_projections_consolidated.csv"), ...)
u <- frozen[frozen$subspecialty_abbrev == "URPS", ]
LEGACY_N <- as.integer(u$baseline_2025)   # 1295, read from the frozen record (not hardcoded)
```

The comment is the defect in one line. `data/workforce_projections_consolidated.csv` is
**not a frozen record** — it is the live SSOT, and it migrated 1,295 → 1,306. The whole
`legacy_frozen` list (baseline, projected, sd, CI, average retirements, ratio) was read
from it, so the "frozen published result" was simply *whatever the SSOT currently says*.

This is the same shape as artifact 1, where the external validation reached its gold
standard through a mutable symlink. A published result must be pinned, not looked up.

## 4. The guard was right, and too late

The generator already contained the correct check:

```r
FROZEN_LEGACY_BASELINE <- 1295L
stopifnot("frozen baseline changed!" = LEGACY_N == FROZEN_LEGACY_BASELINE,
          "frozen endpoint changed!" = abs(as.numeric(u$projected_2029) - 1505.367) < 0.01, ...)
```

Both conditions fire on today's SSOT (baseline 1306, endpoint 1514.46). But it sat at
**line 174, after the four writes at lines 107, 125, 149 and 170.**

So the sequence was: corrupt all four published tables → detect the corruption → exit 1.
The artifacts on disk were already wrong. A **partial-write-on-failure** defect: the
non-zero exit is honest, and completely useless to anyone who then reads the files.

## 5. Verdict — this changes the estimand, it does not refresh an input

**Generator defect: the historical reference state was incorrectly allowed to float with
the current SSOT.** The four committed artifacts are authoritative and correct.

Stated explicitly, because the distinction is the whole finding:

* these four tables are a **decomposition of the frozen published 1,295-provider
  projection**;
* the **current SSOT contains 1,306 providers**;
* substituting the current SSOT **changes the scientific question** rather than merely
  refreshing an input — it asks "what does the 1,306 cohort project?" in place of "how
  does the published 1,295 projection decompose into count and age-structure effects?";
* in particular the **count-effect contrast changes from −10.8 to exactly 0**, because
  the reference and comparison counts become identical and the contrast becomes a cohort
  compared against itself;
* the **historical inputs reconstructed here reproduce all four committed artifacts
  byte-for-byte**, confirming the committed values are the correct output of the intended
  analysis.

This is the sharpest lesson in the queue: **reproducibility does not mean "run the old
analysis with today's inputs."** For a published historical decomposition, doing so
yields a pipeline that is perfectly reproducible and scientifically wrong.

**Do not "modernize" these tables to 1,306.** That would be a new analysis and would need
new artifact names and its own versioning.

## 6. Repair (applied; no published value changed)

1. **The frozen record is pinned**, to the published vintage `f8023845` (2026-07-24):

   ```r
   FROZEN_LEGACY_BASELINE <- 1295L
   legacy_frozen <- list(baseline = FROZEN_LEGACY_BASELINE, projected = 1505.3672,
     avg_annual_retirements = 11.408178, replacement_ratio = 5.61,
     sd = 15.2, lo = 1476, hi = 1535)
   ```

   These reproduce the committed table under the script's own rounding
   (`round(1505.3672, 1) = 1505.4`, `round(11.408178, 2) = 11.41`).

2. **Every write now happens after the guard.** Validate first, write second. The four
   `write.csv()` calls were lifted out of their inline positions and placed after the
   `stopifnot()` block, so a failed check leaves the artifacts untouched.

3. **The live SSOT is still read, but only to report divergence**, never to populate the
   frozen row:

   ```
   NOTE: live SSOT baseline_2025 = 1306, frozen legacy row = 1295.
         Divergence is expected since the 1,306 migration; the frozen row is pinned.
   ```

4. **The frozen record is validated before any computation**, not merely before the
   writes. A missing provenance field stops the run immediately:

   ```
   incomplete frozen historical reference: missing source_commit.
     These tables decompose the PUBLISHED 1295-provider projection. Without the
     complete frozen record the decomposition is undefined -- refusing to write.
   ```

5. Further guard conditions assert the frozen row is still labelled `frozen`, and that
   the frozen record is **internally consistent**: mass conservation
   (`projected ≈ baseline + 4·(entrants − avg_ret)`), the ratio identity
   (`replacement_ratio ≈ entrants / avg_ret`), and `lo < projected < hi`.

6. The current SSOT continues to be used for the scenario dimensions where "current" is
   genuinely the intended comparison — the observed 2023-active (1,306) and 2025-roster
   (1,339) cohorts in Tables 2-4. Only the *historical reference* is pinned.

**Result: exit 0, and all four artifacts reproduce byte-identically to the committed
versions.** They went from corrupting-on-run to reproducible with **no change to any
published number**.

## 7. Verification

* All four byte-identical to committed, after the repair.
* Deterministic: the generator is seeded (`SEED = 20260718`, `DRAWS = 2000`) and repeated
  runs agree byte-for-byte.
* `test-urps-baseline-scenarios.R`: 0 failed.
* Full suite via `scripts/ci/run_suite.R`: **6 failing assertions, identical to pristine
  `HEAD`**, all in `test-cliff-workforce-scripts.R` (issue #43). 4,760 passing. Zero
  regression; the repository is **not** green.

## 8. Pattern across the queue

This closes the queue's recurring theme. Six artifacts, and the 1,295/1,339 → 1,306
migration is implicated in four of them — but the *migration was legitimate every time*.
What differed was whether the downstream code adapted:

| artifact | downstream behaviour |
|---|---|
| 2 cube | kept a stale hazard; disagrees with the SSOT by construction |
| 3 sensitivity grid | hardcoded cohort list turned a scope change into a fabricated `NA` row |
| 5 demand denominators | **adapted correctly** — the generator needed no change |
| 6-9 baseline scenarios | read an immutable published constant from the mutable SSOT |

The generalizable rule these four support: **a value that is published history must be
pinned at its source, and every validation must run before the first write.** Both halves
were needed here — the guard existed and was correct, and the artifacts were corrupted
anyway.


## 9. Behavioural regression tests

`tests/testthat/test-baseline-scenarios-frozen-reference.R` runs the real generator in a
sandbox project and proves:

| property | how |
|---|---|
| all four committed artifacts regenerate **byte-identically** | full run, line-by-line comparison |
| changing the **live** provider count does not move the frozen side | live SSOT mutated to 9,999; frozen row and decomposition unchanged |
| the count-effect contrast stays the intended **nonzero** historical contrast | asserted \|Δ\| > 1 on the committed artifact |
| changing the **frozen** 1,295 reference changes the outputs | frozen baseline set to 1,200; either outputs move or the consistency guard fires |
| an incomplete frozen record fails **before any write** | `source_commit` removed; run errors naming it |
| **no partial writes** on failure | no artifact exists in the sandbox after any failed run |
| every guard precedes every write | static line-order check on the generator |

The tests never run the generator with the repository as the working directory, and the
four committed artifacts were verified byte-identical after the suite.

Suite after this work: **4,792 passing, 6 failing assertions — identical to pristine
`HEAD`**, all in `test-cliff-workforce-scripts.R` (issue #43). Zero regression; the
repository is **not** green.
