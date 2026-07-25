# Containment status and the 1,295 vs 1,339 baseline

Two findings from the 2026-07-24 containment sweep, one resolved (paths) and one
that needs a PI decision (the baseline).

---

## 1. Path containment sweep (resolved)

The workforce/supply-demand code was extracted from the isochrones monorepo, where
everything lived under a `cliff/` subdirectory. The extraction left three classes of
stale path that escaped the standalone clone. All FUNCTIONAL (code) occurrences are
now fixed; only doc/comment prose still mentions the old layout.

| Stale form | Count | Fix |
|---|---|---|
| `cliff/data/...` in `fread`/`read_csv`/`here` (35 files) | many | `data/...` |
| `source("/Users/tylermuffly/isochrones-workforce-cliff/cliff/shiny_urps_scenarios/urps_model_data.R")` | 2 scripts | in-repo `source("shiny_urps_scenarios/urps_model_data.R")` (files are byte-identical) |
| `here_fn("cliff","data",...)` (3-arg) | 1 | `here_fn("data",...)` |

**Verification:** `here()` anchors to the clone (a `.here` marker sits at the root);
the manuscript renders hermetically from clone files only; the frozen Module B/C
adversarial suite passes (44/0); the escape-risk scan finds zero external paths in
any render input.

### The real containment boundary (by design, NOT a bug)

Five UPSTREAM regeneration scripts read RAW physician-level data from the isochrones
monorepo, because that raw data is large/identifiable and does not belong in the
standalone repo:

- `scripts/departure_anchor.R`, `scripts/hierarchical_hazard_partial_pooling.R`,
  `scripts/build_hazard_comparison.R`, `scripts/abu_pathway_sensitivity.R`,
  `scripts/scenario_projection_trajectories.R`
- Inputs: `/Users/tylermuffly/isochrones/manuscript/tables/table1_physician_characteristics.csv`,
  `/Users/tylermuffly/isochrones/data/abu_urology/abu_npi_crosswalk_2026-07-14.csv`,
  `.../abu_fpmrs_net_new_npis_active_2026-07-14.txt`
- They regenerate committed artifacts such as `data/departure_anchor.csv`,
  `data/hazard_by_band_pooled_vs_unpooled.csv`, `data/nrmp_fellowship_entrants.csv`.

**So:** cliff is fully self-contained for RENDERING and RUNNING the analysis from the
committed artifacts. It is NOT self-contained for RE-DERIVING those artifacts from raw
sources; that requires the isochrones monorepo. (Future option: parameterize these five
paths via a `ISOCHRONES_ROOT` env var so they are machine-independent, or migrate the
de-identified subset they need.)

---

## 2. The 1,295 vs 1,339 URPS baseline (needs PI decision — do NOT silently unify)

The manuscript carries two URPS baselines from two lineages, differing by **44
physicians**:

| Value | Source | Used by |
|---|---|---|
| **1,295** | `data/workforce_projections_consolidated.csv` `baseline_2025` (frozen SSOT) | the headcount hazard model; `get_baseline("URPS")` in the manuscript abstract/Table 1 |
| **1,339** | `length(URPS_AGES)` in `shiny_urps_scenarios/urps_model_data.R` | the age-structured SUPPLY engine (Module A, `urps_supply_demand_national`), i.e. the demand-section supply curve and the Effective-Adequacy Shiny app |

Both claim to be "the both-pathway active URPS workforce" (ABOG-certified active + the
net-new ABU urogynecologists), but they were assembled at slightly different vintages
with a slightly different ABU dedup / active filter, so the age-structured roster
(1,339) holds 44 more physicians than the frozen SSOT (1,295).

**Why it matters.** The reframed manuscript states the headcount baseline as 1,295 and
builds the supply-vs-demand section on the 1,339-based projection. The current draft
sidesteps a visible clash by reporting the supply trajectory in INDEX terms
(2025 = 100), so no two conflicting absolute counts appear side by side. But a careful
reviewer will notice the supply model starts from a different base than the headcount
baseline, and the two should be reconciled before submission.

**Options (PI decision — mirrors the dual-classifier rule: do not "fix" one to match
the other without sign-off):**
1. Rebuild `URPS_AGES` from the exact roster that produced the frozen SSOT baseline, so
   both lineages use 1,295. (Changes every supply-demand and adequacy number slightly.)
2. Re-freeze the SSOT `baseline_2025` to the current both-pathway roster (1,339), if that
   roster is the more current/correct both-pathway count. (Changes the headcount
   completion-to-departure ratios slightly.)
3. Keep both but add one explicit sentence reconciling them (e.g., "the age-structured
   supply model uses a marginally larger both-pathway roster (n = 1,339) than the frozen
   headcount baseline (n = 1,295); the 44-physician difference is a roster-vintage effect
   and does not affect the indexed trajectories").

Until then, the reframed manuscript's index framing is the safe interim.
