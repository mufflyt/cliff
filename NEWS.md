# cliff (development version)

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
