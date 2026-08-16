# Adjudication: `urps_row_1306_regenerated.csv` + `urps_uncertainty_1306.csv`

**Uncertainty question: CLOSED 2026-08-16 — legitimate methodological revision, per-provider aleatory uncertainty added.**
**Hazard-pool question: OPEN — carried forward (see §8).**
**Queue:** `scripts/ci/artifact_drift_debt.txt` (2 of 10)

The two artifacts were adjudicated as one scientific unit. The published
parameter-only model is preserved and remains exactly reproducible; the current
artifacts were regenerated under the expanded model and are now labelled with which
model produced them.

---

## 1. Artifact and generator

| | |
|---|---|
| Artifacts | `scripts/urps_scenario_cube/urps_row_1306_regenerated.csv`, `urps_uncertainty_1306.csv` |
| Generator | `scripts/urps_scenario_cube/regen_urps_1306_projection.R` (writes both) |
| Manuscript exposure | **none** |
| Consumers | **none.** No `.Rmd`, test, script or app reads either file |

The manuscript's URPS projection comes from `data/workforce_projections_consolidated.csv`
(`scripts/build_nrmp_benchmark.R`). These files are a second, independent computation
of the same estimand.

## 2. They are one model run

Committed three days apart (`797f36b` 2026-08-02, `91cc2f6` 2026-08-05), but the row's
dispersion columns are exactly `round()` of the uncertainty file's: sd 13.91666→13.92,
1468.23067→1468, 1522.51922→1523. Any refresh must move both, and did.

## 3. Test state: zero-regression relative to `HEAD`, **not** "green"

| | failures/errors |
|---|---:|
| pristine `HEAD` | **7** |
| adjudication branch | **7** |
| new failures introduced | **0** |

All seven are in `tests/testthat/test-cliff-workforce-scripts.R`, the same test and
the same seven assertions in both runs. **No changed file references, reads or
produces any input of that test.**

**Root cause, corrected.** The first reading of these failures was "missing
`data/table1_physicians.csv`". That is wrong, and the correction matters. The test
spawns each pipeline script as a *child* R process; under this local runner the child
dies with `ignoring environment value of R_HOME` and a segfault (status 139) while
loading a namespace. The same script run directly under the same library succeeds
(`exit=0`). The missing-CSV message is a downstream symptom: `07_create_table1.R`
never completed, so its output was never written, and the test then asserts
`file.exists()` on it.

The branch is therefore classified **zero-regression relative to `HEAD`**. It is
explicitly *not* claimed to be green, and these seven failures are evidence about the
local runner, not about repository health. Tracked separately as **issue #43**; the
adjudication does not fix them.

## 4. Does the `/mufflyaccess` accessor reproduce the canonical URPS cohort exactly?

**Yes, exactly, in all four strata.**

| geography | pathway | local extract | `urps_active_ages()` | |
|---|---|---:|---:|---|
| national | ABOG | 1027 | 1027 | identical age-by-age |
| national | ABU | 279 | 279 | identical |
| conus | ABOG | 1026 | 1026 | identical |
| conus | ABU | 277 | 277 | identical |
| national | combined | 1306 | 1306 | identical |

Equality was checked age-by-age, not just on totals. The accessor additionally
reconciles against `urps_count()` on every call, so the cube can no longer project a
cohort the SSOT does not recognise.

## 5. Does swapping the input to `/mufflyaccess` change the deterministic projection?

**No.**

```
projected_2029  = 1510.0614   (both)
departures_4yr  =   51.9386   (both)
```

The accessor returns ages **sorted**; the extract returned them grouped by pathway.
`wc_project()` tabulates ages before projecting, so it is order-invariant, as is
`build_nrmp_benchmark.R`'s `project()`. Only `wc_project_micro()` consumes the vector
in order; ordering moves its draws by mean −0.47 and sd +0.29 against an sd of ~22,
i.e. simulation noise.

**All six** consumers of the local extract now use the accessor and the local copy is
deleted. With it deleted, every generator was re-run: all artifacts are
**byte-identical** to committed, except the two under adjudication here.

## 6. Pre/post-`7c05c87` under identical seed and MC settings

`7c05c87` (2026-08-08) changed one line inside the MC loop: `wc_project()` →
`wc_project_micro(n_sims = 1L, seed = NULL)`. Three configurations were run on the
same cohort at `MC_SEED = 20260718`, `MC_DRAWS = 10000`, varying only which sources of
randomness are active:

| config | model | mean | median | sd | variance | 95% PI |
|---|---|---:|---:|---:|---:|---|
| **A** | parameter only (**pre**) | 1497.420 | 1498.10 | **13.917** | 193.67 | [1468.2, 1522.5] |
| **B** | aleatory only | 1510.092 | 1510.00 | 17.277 | 298.50 | [1477.0, 1544.0] |
| **C** | both (**post**) | 1497.304 | 1497.00 | **22.647** | 512.87 | [1453.0, 1542.0] |

Config A reproduces the published 2026-08-05 artifact to five decimal places
(sd 13.91666, mean 1497.42, PI [1468.231, 1522.519]), confirming it is exactly the
pre-`7c05c87` model.

**The point estimate is unchanged at 1510.0614 in every configuration.** Only
dispersion moved.

## 7. Variance decomposition

Not an sd comparison, a decomposition, with the aleatory component **measured
directly** rather than inferred by subtraction:

| component | variance | sd | share of total |
|---|---:|---:|---:|
| parameter (Beta hazards + graduate bootstrap) | 193.67 | 13.92 | 37.8% |
| **aleatory (per-provider Bernoulli + Poisson entry)** | **298.50** | **17.28** | **58.2%** |
| sum, if independent | 492.18 | 22.19 | |
| **observed total** | **512.87** | **22.65** | |
| interaction (super-additivity) | **+20.69** | | **+4.0%** |

The independence approximation predicts sd 22.19; the measured total is 22.65. The
+4.0% gap is a real hazard × cohort interaction, not noise: higher sampled hazards
raise both the mean and the per-provider Bernoulli variance, so the two components are
mildly positively coupled rather than orthogonal.

The headline: **`7c05c87` added an aleatory component of variance 298.5, sd 17.28** —
larger than the parameter uncertainty that was already there. Individual variation is
the majority of the total, and the pre-`7c05c87` interval omitted all of it.

## 8. Why the deterministic 1510.0614 sits above the MC mean of ~1497.3

This is the finding with the most scientific consequence, and it is **not** caused by
`7c05c87`. It is present identically in the old model.

| step | value | shift |
|---|---:|---:|
| `f(point hazards)` — the published point estimate | 1510.0614 | |
| `f(Beta posterior mean hazards)` | 1495.4984 | **−14.563** |
| `E[f(h)]`, parameter MC (config A) | 1497.4197 | +1.921 |
| `E[f(h)]`, plus aleatory (config C) | 1497.3039 | −0.116 |
| **total offset** | | **−12.758** |

The point estimate and the interval **use different hazard estimators**. The point uses
the MLE `ev/py`; every MC draw uses `Beta(ev + 0.5, py − ev + 0.5)`, whose posterior
mean is `(ev + 0.5)/(py + 1)` — the Jeffreys prior adds half an event to every band.
That raises departures from 51.94 to 66.50 and drags the projection down 14.56, of
which Jensen's inequality returns +1.92. The aleatory layer is mean-unbiased (−0.116),
confirming `wc_project_micro()` does not shift the centre.

**Two-thirds of the entire offset comes from one band.** Switching each band alone from
point to Beta-mean hazard:

| band | point | Beta mean | shift |
|---|---:|---:|---:|
| <45 | 0.003388 | 0.003517 | −0.233 |
| 45–49 | 0.002932 | 0.003443 | −0.534 |
| 50–54 | 0.004326 | 0.004936 | −0.648 |
| 55–59 | 0.008201 | 0.009207 | −0.705 |
| 60–64 | 0.023493 | 0.025640 | −1.140 |
| 65–69 | 0.082792 | 0.090519 | −1.622 |
| **70+** | **0.000000** | **0.125000** | **−9.747** |

The 70+ hazard is estimated on **3 person-years with 0 events**. The Jeffreys prior
turns that into a **12.5% annual departure rate**, which is then applied to a group
growing from 13 providers in 2025 to 46 by 2029. A band with essentially no data
supplies 67% of the gap between the published point estimate and its own interval.

This affects the SSOT too: `build_nrmp_benchmark.R` uses the same
deterministic-point-plus-Beta-bootstrap pattern.

## 9. Is the newer uncertainty estimate authoritative?

**Yes, for the interval.** 1,306 individual physicians either do or do not depart. The
aggregate model propagates uncertainty about the *rate* but treats the cohort as
infinitely divisible, so it cannot express individual variation at all — and that
variation is 58% of total variance. A 95% interval of [1468, 1523] on a 1,306-person
cohort was too narrow by construction, not by parameter choice.

The parameter-only model is **not wrong**; it answers a narrower question ("how
uncertain are we about the hazards and the graduate count?"). It is retained, labelled,
and reproducible.

**Scope of the closure.** This closes the *uncertainty* question only. It does not
close, and must not be read as closing, the finding in §10.

## 10. Still open: the cube has never agreed with the SSOT

Independent of everything above, this projection disagrees with the published SSOT:

```
cube : 1306 + 256 − 51.9386 = 1510.0614
SSOT : 1306 + 256 − 47.5404 = 1514.4596
```

Baseline, entrants and inflow are identical; the whole 4.3982 gap is departures. The
cause is two undocumented estimator differences, both confirmed by direct computation:

1. **Pool.** Re-running `band_counts(WIN, rows = which(coh$ab == "URPS"))` reproduces
   the cube's person-years **exactly in every band** (3854, 973, 811, 488, 221, 53, 3).
   The cube uses a **URPS-only** hazard; the SSOT pools **GO + ABOG-URPS**, a documented
   reviewer decision (2026-07-19).
2. **Event weighting.** URPS-only integer events total 35; the cube carries 33.001,
   **fractional**, so probability-weighted rather than hard-anchored. `band_counts()`
   sums indicators and can only return integers, so the cube's table cannot be a
   snapshot of it.

Net: a hazard **7.3%–11.5% higher than the SSOT's in every band**.

The generator called this table *"same as the frozen model"* and the README called it
*"the published pooled GO+URPS age-band hazards"*. **Both were false**; the README is
corrected.

**It never agreed.** At `797f36b` — the commit that introduced these artifacts — the
SSOT already said 1514.56. Pooling entered the SSOT on 2026-07-24, before the cube was
written. This is an orphaned parallel implementation, not drift.

Also unresolved: `annual_retirement_rate` is a **proportion** in the cube (0.00994) and
a **percent** in the SSOT (0.9100383) — same column name, same claimed estimand, 100×
apart. Each is internally consistent, so no test catches it.

## 11. Action taken

1. **Cohort source → SSOT accessor**, all six consumers; local extract deleted
   (§4, §5). Every other artifact byte-identical.
2. **Both uncertainty models are now emitted and labelled.** `uncertainty_model` is a
   column in both artifacts.
   * `urps_uncertainty_1306.csv` — `parameter_plus_aleatory` (current, authoritative)
   * `urps_uncertainty_1306_parameter_only.csv` — `parameter_only` (superseded,
     preserved)
3. **The published parameter-only model is preserved exactly.** The new
   `parameter_only` artifact reproduces the 2026-08-05 values in **every column**:
   median 1498.099, mean 1497.42, sd 13.91666, PI [1468.231, 1522.519]. It is now
   checkable rather than merely believed.
4. **The row artifact's deterministic columns are unchanged** — `projected_2029`,
   `percent_change`, `annual_retirement_rate`, `avg_annual_retirements`,
   `replacement_ratio`, `total_retirements_4yr` all identical. Only `sd_2029`,
   `ci95_lower`, `ci95_upper` moved (13.92→22.65, [1468,1523]→[1453,1542]).

## 12. Carried forward

* **The URPS-only vs pooled hazard divergence (§10)** — a decision is still owed:
  either label the cube as a deliberate URPS-only sensitivity and state the contrast,
  or retire it. Do not refresh it again until that is settled.
* **The point/interval estimator mismatch (§8)** — shared with the SSOT generator, so
  it is a *shared root cause* to check against the remaining queue, especially the four
  `urps_baseline_scenarios/table*_v3.0.0.csv` artifacts, which sit behind this pair.
* **The sparse-band prior** — 0 events in 3 person-years becoming a 12.5% hazard is a
  modelling choice worth an explicit decision (collapse 65+ into one band, or cap the
  top band's hazard).
* **The `annual_retirement_rate` unit collision.**
* **Issue #43** — the seven local test failures, deliberately out of scope here.
