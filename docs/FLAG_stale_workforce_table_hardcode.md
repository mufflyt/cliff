# FLAG: `manuscript/R/create_workforce_table.R` holds a STALE hardcoded workforce table that contradicts the SSOT

**Status:** open, PI-gated (not a loop refactor — changes a published table + touches the off-limits URPS baseline).
**Found:** 2026-07-25, during the "could workforce sizes be standardized?" audit.

## What

`create_workforce_table.R:88` builds a manuscript table from a **hardcoded `tribble`** (captured 2026-01-12,
per its own comment) whose numbers disagree with the current single source of truth,
`data/workforce_projections_consolidated.csv`:

| field | create_workforce_table tribble | frozen SSOT CSV |
|---|---|---|
| GO `baseline_2025` | **1352** | **1052** (−300) |
| MIG `baseline_2025` | **767** | **605** |
| FPMRS/URPS `baseline_2025` | 1283 | 1295 (see baseline reconciliation) |
| `replacement_ratio` | 1.08 / 0.730 / 1.61 | 5.61 / 7.11 / 11.06 |
| `replacement_assessment` | "Marginal" / "Insufficient" / "Adequate" | "Above replacement" ×3 |
| fellowship column | `fellowship_total_5yr` (5-year) | `fellowship_total_4yr` (4-year) |

The assessment labels ("Marginal"/"Insufficient"/"Adequate") are **not** members of
`WORKFORCE_VALID_ASSESSMENTS` (`Above/At/Below replacement`), so this table's data would **fail the contract
validator** — strong evidence it is a **pre-reframe artifact left behind**, not the live manuscript path (the
live path reads the consolidated CSV and the manuscript Rmd uses inline `get_baseline()`).

## Why it is NOT a loop iteration

- The fix is "delete this builder, or repoint it at the frozen CSV," which **changes published table numbers**.
- The GO 1352→1052 / MIG 767→605 shifts and the FPMRS/URPS row are entangled with the **off-limits
  1,295-vs-1,339 baseline reconciliation** (`docs/SSOT_URPS_BASELINE_RECONCILIATION.md`), which is blocked on
  a full re-run.
- Therefore this needs a **PI decision**, not a mechanical single-value refactor.

## Recommended resolution (for PI sign-off)

1. Confirm `create_workforce_table.R` is dead/superseded (grep shows it referenced only from
   `manuscript/R/workforce_data_contract.R`; verify no live manuscript chunk calls it). If dead → **delete it**.
2. If still used → **repoint** it to read `data/workforce_projections_consolidated.csv` (like
   `create_figure1_workforce_projection.R` and the Rmd's `get_baseline()`), remove the tribble, and let the
   contract validator enforce label validity. This will change the rendered table's numbers — requires PI review.

## Companion

The FPMRS supply **figure** (`scripts/fig_fpmrs_supply_line.R`) still hardcodes its supply numbers
(1196 / 1283 / 1301 / 4.4 / 55.6 / 1.08 / 15.2 / CI) rather than reading the CSV — same class of gap, same
baseline entanglement. Its **year axis** and **CI z-multiplier** were single-sourced in SSOT iterations 14-15;
its supply numbers remain for the same PI-gated reason.
