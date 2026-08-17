# Adjudication: `urps_demand_denominators_sensitivity_2026-07-24.csv`

**Status:** **OPEN — classified, regeneration recommended, not performed.**
**Classification: legitimate input revision. No generator defect, and no change to any demand denominator.**
**Date:** 2026-08-16
**Queue:** `scripts/ci/artifact_drift_debt.txt` (5 of 10)

Neither the artifact nor the generator was modified.

---

## Headline

Approached as a denominator-science problem, the answer is that **the denominators did
not change at all.** All three demand series are byte-identical between the committed
and regenerated artifacts. The entire drift is a **supply-side re-basing**: the 2025
denominator of the supply index moved from **1,339** (2025 `roster_snapshot`) to
**1,306** (2023 `board_certified_active`), the estimand this repository adopted. It is
the same migration behind artifact 3.

## 1. Exact drift

25 of 26 rows differ. Only the 2025 base row matches, by construction.

| column | unit | committed 2050 | regenerated 2050 | abs | rel |
|---|---|---:|---:|---:|---:|
| `supply_index` | dimensionless (2025=100) | 179.1000 | 184.0000 | +4.9000 | **+2.736%** |
| `d1_prevalence_index` | dimensionless | 119.3000 | 119.3000 | 0 | **0.000%** |
| `d2_consultations_index` | dimensionless | 145.5185 | 145.5185 | 0 | **0.000%** |
| `d3_surgery_index` | dimensionless | 127.4077 | 127.4077 | 0 | **0.000%** |
| `coverage_vs_prevalence` | dimensionless | 150.1257 | 154.2330 | +4.1073 | +2.736% |
| `coverage_vs_consultations` | dimensionless | 123.0771 | 126.4444 | +3.3673 | +2.736% |
| `coverage_vs_surgery` | dimensionless | 140.5724 | 144.4183 | +3.8459 | +2.736% |

**No denominator definition changed.** The three coverage columns move by exactly the
supply change, which is arithmetically forced: `coverage = 100 · S / D` with `D` fixed.

**Directions and rankings are unchanged.** Only magnitudes move.

## 2. Every denominator traced to source, with units

| | D1 prevalence | D2 consultations | D3 surgery | Supply |
|---|---|---|---|---|
| **Source** | Wu 2009 *Obstet Gynecol*; Nygaard 2008 age-specific prevalence | Kirby 2013 *Am J Obstet Gynecol* 209(6):584.e1-5 | Wu 2011 *Am J Obstet Gynecol* | cliff URPS workforce projection |
| **Vintage** | prevalence Nygaard 2008 × population Census 2023 NPP | anchors 2010, 2030 | anchors 2010, 2050 | 2023 board-certified active |
| **Universe** | US national, women | US national | US national | US national, both pathways |
| **Eligibility** | adult women (carried as `women_40plus`, `women_65plus`) | PFD-care seekers | SUI + POP surgical candidates | ABOG + ABU net-new |
| **Quantity** | prevalent **persons** — a **STOCK** | new visits **per year** — a **FLOW** | procedures **per year** — a **FLOW** | physicians — a **STOCK** |
| **Raw unit** | `cases` | `visits · yr⁻¹` | `procedures · yr⁻¹` | `physicians` |
| **Anchors** | 28.1M (2010) → 43.8M (2050) | 1,218,371 → 1,644,804 | 376,700 → 555,020 | 1,306 (2025) → 2,403 (2050) |
| **Implied growth** | from Census × age-specific rates | **1.5118 %·yr⁻¹** | **0.9736 %·yr⁻¹** | — |
| **Transform to index** | `100 · women_with_pfd(y) / women_with_pfd(2025)` | `100 · v₀g^(y−y₀) / v₀g^(2025−y₀)` | same geometric form | `100 · supply(y) / supply(2025)` |

## 3. Stock vs flow — checked explicitly, and clean

The three denominators genuinely mix kinds: **D1 is a stock**, **D2 and D3 are flows**.
That is a real hazard, and the generator handles it correctly. It states that the three
meanings "must NOT be averaged or used interchangeably", keeps them as three
independent estimands, and reports **concordance** (Spearman ρ, category agreement,
and whether the conclusion holds under all three) rather than a blended number.

**Dimensional check of the coverage ratio.** Each series is indexed to its own 2025
value, so each index is dimensionless:

```
supply_index  = physicians(y)        / physicians(2025)          -> dimensionless
d2_index      = visits·yr⁻¹(y)       / visits·yr⁻¹(2025)         -> dimensionless
coverage      = 100 · supply_index / d2_index                    -> dimensionless
```

Units cancel within each index before the ratio is taken, so comparing a stock's growth
to a flow's growth is dimensionally valid. It measures **relative growth**, and the
generator says so explicitly: *"this is RELATIVE, not a proportion of clinical need
met."* That caveat is doing real work and should not be dropped.

**No "per entering patient" multiplier exists in this generator.** The readiness-class
defect (a per-entrant rate applied to a prevalent stock) has no analogue here: D2 and D3
are scaled by dimensionless geometric growth factors, never by a per-patient rate
applied to a mismatched denominator.

## 4. Historical reconstruction — exact

The sole input is `data/urps_supply_demand_national_2026-07-23.csv`.

| | reproduces |
|---|---|
| input at `ac273bb` (the commit that added the artifact) → committed artifact | **exact** — `supply_index` and `pfd_index` match bit-for-bit |
| current input → regenerated artifact | **exact** |

So the cause is **updated input data**, and specifically:

* **not** revised prevalence or incidence assumptions — `women_with_pfd`,
  `women_65plus`, `women_40plus` are all unchanged;
* **not** revised eligibility definitions;
* **not** code changes — the generator is unmodified since the artifact was written;
* **not** rounding or serialization;
* **yes** a changed provider cohort — the supply projection was rebuilt on the 1,306
  cohort in `b50f96d` (2026-08-02).

## 5. Numerical bridge

```
committed supply_index(2050)                                     179.1000
  numerator effect    supply(2050)  2,398 -> 2,403  physicians   +0.209 %
  denominator effect  supply(2025)  1,339 -> 1,306  physicians   -2.465 %   (base shrinks)
  combined            (1+0.00209)/(1-0.02465) - 1                +2.741 %
                                                                 --------
predicted                                                        184.01
observed regenerated supply_index(2050)                          184.0000
residual                                                         +0.005 pp
```

The residual is the input's storage of `supply_index` to **one decimal place**; it is
rounding, not an unexplained term. The three coverage columns then follow exactly from
`coverage = 100 · S / D` with `D` unchanged — verified to floating-point equality.

**The drift is not a uniform rescale.** The whole supply trajectory was rebuilt, so both
the base and every projected year moved, in opposite directions at the two ends:

| YEAR | supply old | supply cur | Δ physicians | shift in index |
|---|---:|---:|---:|---:|
| 2025 | 1,339 | 1,306 | −33 | 0.0000% |
| 2026 | 1,392 | 1,360 | −32 | +0.0962% |
| 2030 | 1,593 | 1,564 | −29 | +0.6723% |
| 2040 | 2,026 | 2,009 | −17 | +1.6523% |
| 2050 | 2,398 | 2,403 | **+5** | +2.7359% |

A single scale factor cannot describe it: the cohort starts 33 physicians smaller and
ends 5 larger.

## 6. Denominator invariants

| invariant | unit | result |
|---|---|---|
| `women_65plus ≤ women_40plus` (subset ≤ parent) | persons | **PASS** |
| `women_with_pfd ≤ women_40plus` | persons | **PASS** |
| all population series strictly positive (no zero denominators) | persons | **PASS** |
| no `Inf`/`NaN` anywhere in the output | dimensionless | **PASS** |
| every index = 100 at the 2025 base | dimensionless | **PASS** (to 1e−9) |
| all series monotone non-decreasing | dimensionless | **PASS** |
| changing the supply basis did not alter clinical prevalence | cases·person⁻¹ | **PASS** (PFD/women40+ = 0.382695 both) |
| changing the supply basis did not alter source population counts | persons | **PASS** |
| coverage identity `100·S/D` holds exactly | dimensionless | **PASS** |

Two findings from invariants that did *not* simply pass:

**(a) The shift is not uniform across years.** A hypothesis that the re-basing was a
pure rescale is *false*, for the reason tabulated in §5. Worth recording because a
future guard written as "coverage moved by a constant factor" would be wrong.

**(b) The base-year identity is off by one ulp.** `d2_consultations_index` at 2025 is
`100.00000000000001` and `coverage_vs_consultations` is `99.999999999999986`. Present
**identically in the committed and regenerated artifacts**, so it is pre-existing and
not drift. It arises in `anchor_index()`, which computes `100 · v₀g^(y−y₀) / v₀g^(base−y₀)`
rather than returning exactly 100 at `y = base`. Harmless numerically, but it means a
naive invariant `all(coverage >= 100)` **fails at the base year** — a flaky guard waiting
to be written. If a coverage guard is ever added, it must compare with a tolerance or
special-case the base year.

## 7. Downstream consequences

| | committed | regenerated |
|---|---|---|
| 2050 coverage: prevalence / consultations / surgery | 150.1 / 123.1 / 140.6 | 154.2 / 126.4 / 144.4 |
| robustness verdict (all > 100 in 2050) | **YES** | **YES** |
| weakest margin | consultations | consultations |
| ranking of the three series | — | **identical** |

* **Manuscript exposure: none.** No `.Rmd` reads this artifact and none of its numbers
  appear in any manuscript text.
* Consumers are three test files (`test-ssot-demand-anchors.R`,
  `test-ssot-demand-horizon-end-year.R`, `test-dpmm-contract.R`) and the generator.
* National demand, projected workforce need, calibration targets and scenario ordering
  are all unaffected: the demand side did not move.

The scientific conclusion **strengthens slightly** — coverage rises on every series —
because the supply baseline is smaller while the 2050 projection is marginally larger.

## 8. Two source-fidelity notes

**The Wu 2011 anchor carries a known 1,000-off slip, deliberately preserved.** The 2050
components are SUI 310,050 + POP 245,970 = **556,020 procedures·yr⁻¹**, but the analysis
uses **555,020**. This is documented in the generator and *enforced* by
`test-ssot-demand-anchors.R`, which asserts `556020 − WU2011_SURG_2050 == 1000` so the
discrepancy cannot be silently "fixed" or silently forgotten. Quantified here:

| | used (555,020) | component sum (556,020) |
|---|---:|---:|
| implied growth | 0.97360 %·yr⁻¹ | 0.97814 %·yr⁻¹ |
| D3 index 2050 | 127.4077 | 127.5511 (**+0.113%**) |
| coverage_vs_surgery 2050 | 144.418 | 144.256 (−0.162) |

Well inside the "<0.2%" the generator claims. Correcting it would not change the verdict.

**D2 and D3 are extrapolations, not measurements.** Both are constant-proportional-growth
projections from published anchor years (Kirby's series ends 2030; Wu's 2050). The
generator flags this in its output. D3's fully age-specific form is written but not
wired, awaiting Census NPP female population by the four Wu bands.

## 9. Classification and recommendation

**Legitimate input revision.** Not a generator defect, not an estimand change on the
demand side, not rounding. The committed artifact is a correct computation from the
inputs available when it was written; it is now **stale** because it encodes the retired
**1,339** supply baseline while the repository has adopted **1,306**.

Recommended, **not performed here**:

1. **Regenerate**, in a commit stating that the supply baseline moved 1,339 → 1,306 and
   that no demand denominator changed. Unlike artifact 3, no defect blocks this: the
   generator is correct and the regeneration is reproducible.
2. Consider giving `anchor_index()` an exact base-year return (`index[years == base] <- 100`)
   so the published table does not carry `99.999999999999986`. Cosmetic, but it removes
   a future flaky-guard trap.
3. Leave the Wu 2011 slip frozen and guarded as it is. It is documented, bounded at
   +0.113% on D3, and its guard is the right shape.

## 10. Shared root cause

This is the **third** artifact traced to the 1,295/1,339 → 1,306 estimand migration
(artifact 2's cube, artifact 3's grid, and now the supply index here). The migration is
legitimate; what differs each time is whether the downstream code adapted to it. Here it
did — the generator needed no change at all.
