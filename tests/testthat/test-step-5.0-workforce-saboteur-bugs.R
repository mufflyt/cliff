
# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()
# =============================================================================
# Regression tests for the 13 saboteur-audit bugs in
# R/manuscript_consolidate_existing_results.R  (Step 5.0)
# (audit date: 2026-04-25)
# =============================================================================
# Each test guards a specific defect that the saboteur audit identified. If
# someone reverts a fix, the matching test fails with an actionable message.
# =============================================================================

# (context() removed: deprecated in testthat 3)

src_path <- here::here("R", "manuscript_consolidate_existing_results.R")
src_text <- readLines(src_path, warn = FALSE)

contains <- function(pattern, text = src_text) {
  any(grepl(pattern, text, perl = TRUE))
}

# Bug 1 — is_test_mode() is sourced unconditionally at file scope.
testthat::test_that("Bug 1: is_test_mode() is sourced before main() can call it", {
  testthat::expect_true(
    contains('source\\(here::here\\("R", "test_mode_contracts\\.R"\\)\\)'),
    info = paste(
      "is_test_mode() is called inside main() but lives in",
      "R/test_mode_contracts.R. Without an unconditional source at file",
      "scope, Rscript standalone runs crash before any work happens."
    )
  )
})

# Bug 2 — output_paths$workforce_csv is the canonical key (DAG-aligned).
testthat::test_that("Bug 2: workforce_csv key (DAG canonical) is read first", {
  testthat::expect_true(
    contains('output_paths\\$workforce_csv'),
    info = "Must read the DAG-set key output_paths$workforce_csv."
  )
  # workforce_projections legacy fallback is still allowed (backwards compat).
  testthat::expect_true(
    contains('output_paths\\$workforce_projections'),
    info = "Legacy workforce_projections key kept as fallback for old callers."
  )
})

# Bug 3 — TEST_MODE stub uses doubles for ci95 columns (matches production).
testthat::test_that("Bug 3: TEST_MODE stub uses doubles for ci95_lower / ci95_upper", {
  testthat::expect_false(
    contains('ci95_lower\\s*=\\s*0L'),
    info = "TEST_MODE stub must not use integer 0L for ci95_lower (production writes doubles)."
  )
  testthat::expect_false(
    contains('ci95_upper\\s*=\\s*0L'),
    info = "TEST_MODE stub must not use integer 0L for ci95_upper (production writes doubles)."
  )
  # Belt-and-suspenders: the stub block must include the schema-match comment.
  testthat::expect_true(
    contains("match production column TYPES"),
    info = "Comment documenting the type-match invariant must remain."
  )
})

# Bug 4 — required source columns checked up front with a clear error.
testthat::test_that("Bug 4: required source CSV columns asserted before mutate chain", {
  testthat::expect_true(
    contains("required_source_cols <-"),
    info = "An upfront required_source_cols vector must exist."
  )
  testthat::expect_true(
    contains("missing_source_cols <- setdiff"),
    info = "A setdiff against names(enhanced_table) must compute the missing set."
  )
  testthat::expect_true(
    contains("Source workforce CSV is missing required column"),
    info = "Stop message must name the missing columns and the source file."
  )
})

# Bug 5 — subspecialty normalized (trim + uppercase) before case_when.
testthat::test_that("Bug 5: subspecialty is normalized (trimws + toupper) before join", {
  testthat::expect_true(
    contains("subspecialty = toupper\\(trimws\\(subspecialty\\)\\)"),
    info = paste(
      "Normalization is required so 'FPMRS ' / 'fpmrs' / 'FPMRS' all join",
      "to the SD table; otherwise CIs silently become NA."
    )
  )
})

# Bug 6 — percent_change zero-guarded against baseline = 0.
testthat::test_that("Bug 6: percent_change zero-guarded against baseline_workforce", {
  testthat::expect_true(
    contains("percent_change\\s*=\\s*dplyr::if_else\\("),
    info = "percent_change must use dplyr::if_else with zero/NA guard."
  )
  testthat::expect_true(
    contains("baseline_workforce\\s*==\\s*0"),
    info = "Zero-baseline branch must be handled."
  )
})

# Bug 7 — ci_percent zero-guarded against projected_2029 = 0.
testthat::test_that("Bug 7: Check 3 ci_percent zero-guarded against projected_2029", {
  testthat::expect_true(
    contains("ci_percent\\s*=\\s*dplyr::if_else\\("),
    info = "ci_percent must use dplyr::if_else with zero/NA guard."
  )
  testthat::expect_true(
    contains("projected_2029\\s*==\\s*0"),
    info = "Zero-projection branch must be handled."
  )
})

# Bug 8 — Check 4 stops on negative projections (does not just cat).
testthat::test_that("Bug 8: Check 4 negative-projection branch calls stop()", {
  # Find the ERROR cat line and verify a stop() follows in the same block.
  err_line <- grep("ERROR: Negative workforce projections detected", src_text)
  testthat::expect_length(err_line, 1L)
  # Look at the next ~12 lines — stop() must be present before the next
  # validation block ends (next blank line or QA Gate boundary).
  next_block <- src_text[err_line:(min(err_line + 12L, length(src_text)))]
  testthat::expect_true(
    any(grepl("stop\\(", next_block)),
    info = "Check 4's negative-projection branch must call stop(), not just cat()."
  )
})

# Bug 9 — legacy globals at the bottom are removed.
testthat::test_that("Bug 9: LEGACY GLOBALS block (duplicate SD_VALUES / INPUT_CSV) deleted", {
  testthat::expect_false(
    contains("LEGACY GLOBALS"),
    info = "The 'LEGACY GLOBALS' duplicate block must be removed (drift bait)."
  )
  # SD_VALUES should appear only inside main(), not at file scope.
  sd_value_lines <- grep("^SD_VALUES <- tribble", src_text)
  testthat::expect_length(
    sd_value_lines, 0L
  )
  # tribble/SD_VALUES still defined inside main() — assert at least one
  # in-function reference remains.
  testthat::expect_true(
    contains("\\s+SD_VALUES <- tribble"),
    info = "SD_VALUES must still be built inside main()."
  )
})

# Bug 10 — receipt-write tryCatch re-throws disk/IO errors.
testthat::test_that("Bug 10: receipt write re-throws disk/IO errors instead of swallowing them", {
  testthat::expect_true(
    contains("no space left\\|disk full\\|read-only file system\\|permission denied"),
    info = paste(
      "Disk/IO error pattern must trigger a re-stop because the OUTPUT_CSV",
      "write probably failed too if the receipt write hit those errors."
    )
  )
})

# Bug 11 — Gate 6 checks CI absurdity (catches SD typos).
testthat::test_that("Bug 11: Gate 6 flags CI width > 200% of projection (SD typo guard)", {
  testthat::expect_true(
    contains("Gate 6.*CI width"),
    info = "Gate 6 string must mention CI width."
  )
  testthat::expect_true(
    contains("width_ratio > 2\\.0"),
    info = "Threshold of 200% (width_ratio > 2.0) must be enforced."
  )
})

# Bug 12 — clamped CIs are surfaced (not silent).
testthat::test_that("Bug 12: ci95_lower_clamped flag column produced and reported", {
  testthat::expect_true(
    contains("ci95_lower_clamped = !is\\.na\\(ci95_lower_raw\\) & ci95_lower_raw < 0"),
    info = "ci95_lower_clamped boolean must be derived in the mutate."
  )
  testthat::expect_true(
    contains("ci95_lower_clamped = ci95_lower_clamped"),
    info = "ci95_lower_clamped must survive the transmute() so callers can inspect."
  )
  testthat::expect_true(
    contains("ci95_lower clamped from negative to 0"),
    info = "A QA NOTE must report any clamped rows with the affected subspecialties."
  )
})

# Bug 13 — TEST_MODE stub matches source-CSV row order.
testthat::test_that("Bug 13: TEST_MODE stub orders subspecialties as FPMRS, GO, MIG first", {
  abbrev_line <- grep("subspecialty_abbrev = c\\(", src_text, value = TRUE)
  testthat::expect_true(
    any(grepl('"FPMRS",\\s*"GO",\\s*"MIG"', abbrev_line)),
    info = "TEST_MODE stub abbrev order must start with FPMRS, GO, MIG (matches source)."
  )
})

# -------------------------------------------------------- Behavioural smoke
testthat::test_that("Sourcing the script does not auto-trigger main()", {
  e <- new.env()
  testthat::expect_no_error(
    capture.output(sys.source(src_path, envir = e), type = "output")
  )
  testthat::expect_true(
    exists("main", envir = e, inherits = FALSE),
    info = "Sourcing must define main() but not call it."
  )
})

testthat::test_that("is_test_mode() resolves after sourcing the script", {
  e <- new.env()
  capture.output(sys.source(src_path, envir = e), type = "output")
  testthat::expect_true(
    exists("is_test_mode", envir = e, inherits = TRUE) ||
      exists("is_test_mode", mode = "function"),
    info = "is_test_mode() must be resolvable after the script sources its dependencies."
  )
})
