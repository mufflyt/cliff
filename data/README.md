# Workforce-cliff data

## `workforce_projections_consolidated.csv` — canonical SSOT (tracked)

This file is the **single source of truth** for the workforce-cliff manuscript.
It is consumed by the manuscript render and by the data-contract tests, and is
deliberately tracked in Git (via a narrow `!` exception to the repo-wide `*.csv`
ignore) so a clean CI checkout can exercise the **real** data contract rather
than a fixture or a skipped test.

- **Content:** aggregate, **non-patient-level** workforce projections — one row
  per surgical subspecialty (FPMRS, GO, MIG). No PHI/PII.
- **Grain / schema:** 3 rows × 15 columns; validated by
  `manuscript/R/workforce_data_contract.R::validate_workforce_data()`.
- **Estimand:** exactly the three gynecologic *surgical* subspecialties
  (FPMRS, GO, MIG); a 7-row table is rejected by the contract.
- **Producer / source archive:** derived from the frozen Monte Carlo comparison
  table `docs/.../comprehensive_forecasting/enhanced_comparison_table_20250928_030546.csv`
  via `R/manuscript_consolidate_existing_results.R` (default scenario). The
  historical_2025 scenario variant is *not* this file.
- **Replacement rule:** any replacement MUST pass the contract guard
  (`validate_workforce_data`) — no zero / `Unknown` / wrong-shape / stub table.

Consumers resolve this path through `resolve_workforce_data_path()` (env
override: `WORKFORCE_DATA_CSV`).
