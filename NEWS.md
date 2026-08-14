# cliff (development version)

## Publication integrity

* `scripts/rebuild_ssot_revised.R`, the canonical SSOT writer, hand-entered six
  algebraically derived columns as rounded literals (`replacement_ratio` 5.38
  for 5.384894, `percent_change` 24.506 for 24.506264). The artifact therefore
  disagreed with its own definitions, which is what the identity checks in
  `test-workforce-cliff-contract.R` and `test-workforce-cliff-data-properties.R`
  had been reporting. The writer now computes `annual_retirement_rate`,
  `replacement_ratio`, `percent_change`, `replacement_assessment`,
  `fellowship_total_4yr` and `total_retirements_4yr` from the measured inputs
  and asserts the identities before writing.

* Regenerating propagated to eight downstream artifacts through the repository's
  own generators. Only the three derived columns changed anywhere, by at most
  9.1e-04 relative; no measured column moved and no published value changes at
  reported precision (URPS 5.38, GO 7.11, MIGS 11.06; 16.0%, 24.5%, 28.3%).

* Added `test-ssot-derived-column-identities.R`: one guard per derived column,
  checked at full precision against the written artifact, plus a guard that the
  columns are not re-rounded on write.

* The scenario-cube registry tie now derives the supply-side scenario set from
  `mufflyaccess::urps_scenarios()` rather than mirroring it as a literal. The
  five `family == "demand"` scenarios added in mufflyaccess 0.10.0 are out of
  scope for a supply cube and are asserted absent rather than silently missing.

* Two test suites pinned pre-migration constants that outlived the 1295 -> 1306
  baseline change (`abu_identified` 270/6, and a hardcoded URPS ratio of 5.6
  that contradicted its own comment's 5.38). They now read the SSOT.

## Housekeeping

* Added `tests/testthat.R`, so the 88-file `tests/testthat/` suite is actually
  run by `R CMD check` and `devtools::test()`. It was previously invisible to
  both. Declared `Config/testthat/edition: 3`.

* Trimmed `Imports` from 55 packages to the 23 that `R/` genuinely uses. The 35
  packages used only by `scripts/`, `manuscript/` and the Shiny apps moved to
  `Suggests`, so installing the package no longer pulls in `shiny`, `plotly`,
  `leaflet`, `lme4`, `tidyverse` and friends. Added `splines`, `stats` and
  `utils`, which the CHIA demand-bridge calibration engine and the workforce
  engine use but which were never declared.

* `manuscript_consolidate_existing_results.R` now attaches `dplyr`, `readr` and
  `tibble` instead of `tidyverse`; `glue` was attached but never called.

* Expanded `.Rbuildignore` to exclude the analysis, manuscript, figure, output
  and Shiny trees, the working-note documents at the repository root, and the
  editor scaffolding. Only package sources now enter the build.

# cliff 0.1.0

* Initial release: reproducible analysis and manuscript for near-term
  fellowship-completion versus clinical-practice-departure balance in
  gynecologic oncology and urogynecology (2025-2029).
