# Adjudication: `table1_urps_characteristics_2026-07-23.csv`

**Status:** **OPEN — one-line fix identified, awaiting go-ahead.**
**Verdict: not drift. The generator is non-deterministic, so this artifact can never reproduce.**
**Date:** 2026-08-16
**Queue:** `scripts/ci/artifact_drift_debt.txt` (4 of 10)

Neither artifact nor generator was modified.

---

## 1. Artifact and generator

| | |
|---|---|
| Artifact | `data/table1_urps_characteristics_2026-07-23.csv` (28 rows) |
| Generator | `scripts/build_table1_urps_2026-07-23.R` (112 lines) |
| Inputs | `data/abu_all_urps_ENRICHED_2026-07-22.csv`, `data/abog_all_urps_ENRICHED_2026-07-22.csv`, `R/in_model_baseline.R` |
| Basis | **1,339** = ABU 308 + ABOG 1031 — the 2025 `roster_snapshot`, not the 1,306 projection cohort |
| **Manuscript exposure** | **none.** No `.Rmd` reads it and none of its numbers appear in any manuscript text |
| Consumers | **none** besides its own generator |

## 2. Committed vs regenerated

Of 28 rows, **exactly one differs**:

```
< "Rurality, n (%)","","","",0.323,100%      committed
> "Rurality, n (%)","","","",0.318,100%      regenerated
```

Every other cell — every count, percentage, median, IQR, coverage figure, and every
other p-value — is **byte-identical**. The two ENRICHED input files are unchanged, and
the 1,339 / 308 / 1031 basis is unchanged.

## 3. Root cause: an unseeded Monte Carlo p-value

`scripts/build_table1_urps_2026-07-23.R:50-52`:

```r
ex <- suppressWarnings(chisq.test(tb)$expected)
if (any(ex < 5)) suppressWarnings(fisher.test(tb, simulate.p.value = TRUE, B = 1e4)$p.value)
else            suppressWarnings(chisq.test(tb)$p.value)
```

`set.seed()` appears **zero times** in the generator. Rurality is the only
characteristic whose contingency table has an expected cell below 5, so it is the only
one routed to the simulated branch — which is exactly why it is the only row that moves.

Four independent runs:

| run | Rurality P |
|---|---:|
| committed | 0.323 |
| 1 | 0.318 |
| 2 | 0.327 |
| 3 | 0.324 |

This is **not drift**. The artifact never reproduced and never will: it is a random
draw. Re-running the generator a fourth time produces a fourth value.

## 4. The variation is exactly Monte Carlo error

| | |
|---|---|
| observed sd across 4 runs | 0.00374 |
| expected sd at `B = 1e4`, p ≈ 0.32 | 0.00468 |
| observed range | 0.318 – 0.327 (0.0090 ≈ 2 SE) |

Fully consistent. There is no second cause hiding underneath.

**The reported precision exceeds the achievable precision.** The artifact prints three
decimal places; at `B = 1e4` the Monte Carlo 95% band is [0.314, 0.332], which supports
roughly **one**. The third digit is noise being published as though it were a result.

| B | MC SE | 95% MC band | digits supported |
|---:|---:|---|---:|
| 1e4 | 0.0047 | [0.3138, 0.3322] | 1 |
| 1e5 | 0.0015 | [0.3201, 0.3259] | 2 |
| 1e6 | 0.00047 | [0.3221, 0.3239] | 2 |

## 5. Scientific consequence

**None inferential.** p ≈ 0.32 under every run, nowhere near any conventional
threshold, and the artifact has no manuscript exposure. No published claim depends on
it.

The consequence is to **reproducibility**, and it is total: a committed artifact that
cannot be regenerated even in principle. It also silently consumed a slot in the drift
registry, where it looked like the same class of problem as artifacts 1–3 and was not.

## 6. Recommended action (not taken)

1. **Seed the generator.** `set.seed()` near the top, following the repo convention
   (`MC_SEED <- 20260718L` is used elsewhere). One line.
2. **Raise `B` to `1e6`** so Monte Carlo error falls below the reported precision
   (SE 0.00047 against three printed decimals). Cheap for a single 2×k table.
3. **Then regenerate**, in a commit stating the p-value was previously unseeded and the
   new value is fixed. Expect the Rurality p to settle near 0.323 ± 0.001.
4. Alternatively, if an exact test is computationally feasible for this table, prefer
   `simulate.p.value = FALSE` and remove the randomness entirely rather than managing it.

Steps 1–3 are a one-line fix plus a regeneration and change no other cell in the table.
Held pending go-ahead only because it does alter a committed value.

## 7. Root-cause class — new, and worth a sweep

Artifacts 1–4 have now produced four *distinct* causes:

| artifact | cause |
|---|---|
| 1 `classifier_validation_external` | mutable gitignored reference standard |
| 2 `urps_row_1306` pair | deliberate engine/methodology revision |
| 3 `sensitivity_grid` | upstream scope change + hardcoded cohort list (a defect) |
| 4 `table1_urps_characteristics` | **non-determinism in the generator itself** |

The artifact-3 defect class does **not** explain this one, and a scan confirmed neither
`build_table1_urps_2026-07-23.R`, `urps_demand_denominators_sensitivity.R`, nor
`urps_scenario_analysis_v3.R` contains a hardcoded cohort reindex.

The new generalizable question is **unseeded randomness in any generator**, which is
worth sweeping across the whole pipeline rather than discovering one artifact at a
time. Note `urps_scenario_analysis_v3.R` — the single generator behind all four
remaining `urps_baseline_scenarios` tables — should be checked for this specifically.
