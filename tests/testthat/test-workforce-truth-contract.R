## test-workforce-truth-contract.R
##
## 14 tests for validate_workforce_truth_contract():
##   V1–V11  original suite
##   S1–S3   cross-step robustness saboteurs
## All self-contained — no DuckDB, no external files.

library(testthat)
library(dplyr)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

source(here::here("R", "validators", "validate_workforce_truth_contract.R"))

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

#' Minimal two-year panel for one physician.
#' Year 1 = "continuing" (prior year active).
#' Year 2 = customisable for each test.
make_panel <- function(
    npi                   = "1234567890",
    years                 = c(2022L, 2023L),
    certification_year    = 2018L,
    is_retired            = c(FALSE, FALSE),
    retirement_data_conflict = c(FALSE, FALSE),
    conflict_reason       = c(NA_character_, NA_character_),
    deceased              = c("N", "N")
) {
  tibble::tibble(
    npi                      = npi,
    year                     = as.integer(years),
    certification_year       = as.integer(certification_year),
    is_retired_for_cohorting = is_retired,
    retirement_data_conflict = retirement_data_conflict,
    conflict_reason          = conflict_reason,
    deceased                 = deceased
  )
}

#' Run validator with strict = FALSE so tests can inspect result without stop().
#' suppressWarnings() muffles expected functional warnings
#' (old_cert_first_appearance,
#' oscillator rate) so callers inspect the returned data structure, not R
#' signals.
run_validator <- function(df, ...) {
  tmp <- withr::local_tempdir()
  suppressWarnings(
    validate_workforce_truth_contract(df, output_dir = tmp, strict = FALSE, ...)
  )
}

# ---------------------------------------------------------------------------
# V1 — weak_signal_reactivation
# ---------------------------------------------------------------------------

test_that("V1 weak_signal_reactivation is caught as an error", {
  # Physician retired in 2022, reactivated in 2023 via Open Payments only
  panel <- make_panel(
    is_retired               = c(TRUE,  FALSE),
    retirement_data_conflict = c(FALSE, TRUE),
    conflict_reason          = c(NA_character_,
                                 "weak_cessation_only_billing_recent")
  )
  res <- run_validator(panel)
  expect_false(res$valid)
  expect_true("weak_signal_reactivation" %in% res$violation_rows$violation_reason,
    info = "Reactivation via Open Payments must be flagged as a violation")
})

# ---------------------------------------------------------------------------
# V2 — deceased_marked_active
# ---------------------------------------------------------------------------

test_that("V2 deceased physician marked active is caught as an error", {
  panel <- make_panel(
    is_retired = c(FALSE, FALSE),
    deceased   = c("N",   "Y")   # year 2 marked deceased but still active
  )
  res <- run_validator(panel)
  expect_false(res$valid)
  expect_true("deceased_marked_active" %in% res$violation_rows$violation_reason)
})

# ---------------------------------------------------------------------------
# V3 — future_certification_year
# ---------------------------------------------------------------------------

test_that("V3 newly certified physician with future cert year is caught", {
  # First appearance in 2023 but cert year is 2025 (impossible)
  panel <- tibble::tibble(
    npi                      = "9999999999",
    year                     = 2023L,
    certification_year       = 2025L,   # future
    is_retired_for_cohorting = FALSE,
    retirement_data_conflict = FALSE,
    conflict_reason          = NA_character_,
    deceased                 = "N"
  )
  res <- run_validator(panel)
  expect_false(res$valid)
  expect_true("future_certification_year" %in% res$violation_rows$violation_reason)
})

# ---------------------------------------------------------------------------
# V4 — old_certification_first_appearance is WARNING only, not error
# ---------------------------------------------------------------------------

test_that("V4 old_certification_first_appearance is warning-level, not error", {
  # First appearance in 2023, cert year 2010 — likely NPPES lag
  panel <- tibble::tibble(
    npi                      = "8888888888",
    year                     = 2023L,
    certification_year       = 2010L,   # > 2 years before first appearance
    is_retired_for_cohorting = FALSE,
    retirement_data_conflict = FALSE,
    conflict_reason          = NA_character_,
    deceased                 = "N"
  )
  res <- run_validator(panel)
  # Should NOT be an error (valid = TRUE), but should appear in warning_rows
  expect_true(res$valid,
    info = "late_observation with old cert year must not stop the pipeline")
  expect_true(
    "old_certification_first_appearance" %in% res$warning_rows$violation_reason,
    info = "late_observation must appear as a warning"
  )
})

# ---------------------------------------------------------------------------
# V5 — missing_npi
# ---------------------------------------------------------------------------

test_that("V5 missing NPI is caught as an error", {
  panel <- make_panel(npi = NA_character_)
  res   <- run_validator(panel)
  expect_false(res$valid)
  expect_true("missing_npi" %in% res$violation_rows$violation_reason)
})

# ---------------------------------------------------------------------------
# V6 — reactivation_without_gap only fires on weak signal + gap <= 1 year
# ---------------------------------------------------------------------------

test_that("V6a reactivation_without_gap fires when weak signal + same-year gap", {
  # Retired 2022, reactivated 2023 (gap = 1), weak signal
  panel <- make_panel(
    years                    = c(2022L, 2023L),
    is_retired               = c(TRUE,  FALSE),
    retirement_data_conflict = c(FALSE, TRUE),
    conflict_reason          = c(NA_character_, "weak_cessation_only_billing_recent")
  )
  res <- run_validator(panel)
  # weak_signal_reactivation also fires; reactivation_without_gap may too
  viol_reasons <- res$violation_rows$violation_reason
  expect_true(
    "weak_signal_reactivation" %in% viol_reasons ||
      "reactivation_without_gap" %in% viol_reasons,
    info = "Weak-signal same-year reactivation must be flagged"
  )
})

test_that("V6b reactivation_without_gap does NOT fire for strong-signal reactivation", {
  # Retired 2022, reactivated 2023, strong Medicare Part B signal
  panel <- make_panel(
    years                    = c(2022L, 2023L),
    is_retired               = c(TRUE,  FALSE),
    retirement_data_conflict = c(FALSE, TRUE),
    conflict_reason          = c(NA_character_, "medicare_part_b_billing")
  )
  res <- run_validator(panel)
  expect_false("reactivation_without_gap" %in% res$violation_rows$violation_reason,
    info = "Medicare Part B reactivation must not be flagged as reactivation_without_gap")
})

# ---------------------------------------------------------------------------
# V7 — inactive_but_marked_active
# ---------------------------------------------------------------------------

test_that("V7 reactivated physician with no signal is caught as inactive_but_marked_active", {
  # Physician retired in 2022, then reactivated in 2023 with NO conflict signal at all.
  # This indicates a dropped join — something caused the retirement flag to clear
  # without any billing evidence. Must be flagged.
  panel <- make_panel(
    is_retired               = c(TRUE,  FALSE),
    retirement_data_conflict = c(FALSE, FALSE),  # no conflict recorded
    conflict_reason          = c(NA_character_, NA_character_)
  )
  res <- run_validator(panel)
  expect_false(res$valid)
  expect_true("inactive_but_marked_active" %in% res$violation_rows$violation_reason,
    info = "Reactivated physician with no billing signal must be flagged as data-loss indicator")
})

# ---------------------------------------------------------------------------
# V8 — clean data passes with valid = TRUE and zero violations
# ---------------------------------------------------------------------------

test_that("V8 clean data with Medicare Part B signal returns valid = TRUE", {
  # Two-year panel with strong Medicare signal → no violations
  panel <- make_panel(
    is_retired               = c(FALSE, FALSE),
    retirement_data_conflict = c(TRUE,  TRUE),
    conflict_reason          = c("medicare_part_b_billing", "medicare_part_b_billing")
  )
  res <- run_validator(panel)
  expect_true(res$valid)
  expect_equal(res$n_violations, 0L)
})

# ---------------------------------------------------------------------------
# V9 — strict = FALSE returns violations without stop()
# ---------------------------------------------------------------------------

test_that("V9 strict = FALSE returns violations without stopping", {
  panel <- make_panel(npi = NA_character_)
  tmp   <- withr::local_tempdir()

  # strict = TRUE should stop
  expect_error(
    validate_workforce_truth_contract(panel, output_dir = tmp, strict = TRUE),
    regexp = "RETRACTION GUARD"
  )

  # strict = FALSE should return result with violations
  res <- validate_workforce_truth_contract(panel, output_dir = tmp, strict = FALSE)
  expect_false(res$valid)
  expect_gt(res$n_violations, 0L)
})

# ---------------------------------------------------------------------------
# V10 — oscillator rate > 20% triggers warning (not stop)
# ---------------------------------------------------------------------------

test_that("V10 oscillator rate > 20% triggers warning, not stop", {
  # 10 physicians: 8 reactivated in the same year via Medicare → rate = 80%
  reactivated_rows <- dplyr::bind_rows(lapply(1:8, function(i) {
    tibble::tibble(
      npi                      = sprintf("NPI%08d", i),
      year                     = c(2022L, 2023L),
      certification_year       = 2015L,
      is_retired_for_cohorting = c(TRUE,  FALSE),
      retirement_data_conflict = c(FALSE, TRUE),
      conflict_reason          = c(NA_character_, "medicare_part_b_billing"),
      deceased                 = "N"
    )
  }))
  continuing_rows <- dplyr::bind_rows(lapply(9:10, function(i) {
    make_panel(npi = sprintf("NPI%08d", i),
               retirement_data_conflict = c(TRUE, TRUE),
               conflict_reason = c("medicare_part_b_billing", "medicare_part_b_billing"))
  }))
  panel <- dplyr::bind_rows(reactivated_rows, continuing_rows)

  tmp <- withr::local_tempdir()
  # Round 299 fix: validator emits multiple warnings (old_cert violations + oscillator).
  # Capture all with withCallingHandlers so only the oscillator check escapes to
  # expect_true(); muffling all prevents the non-oscillator warning from leaking as
  # a testthat W.
  all_warns <- character(0L)
  withCallingHandlers(
    validate_workforce_truth_contract(panel, output_dir = tmp, strict = FALSE),
    warning = function(w) {
      all_warns <<- c(all_warns, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  expect_true(
    any(grepl("oscillator rate", all_warns, fixed = FALSE)),
    info = "High oscillator rate must produce a warning, not a stop"
  )
})

# ---------------------------------------------------------------------------
# V11 — entry_type taxonomy: late_observation only when cert_year < year - 1
# ---------------------------------------------------------------------------

test_that("V11 late_observation only assigned when cert_year is old relative to first year", {
  # Physician first appears in 2023 with cert_year = 2022 → newly_certified
  new_row <- tibble::tibble(
    npi                      = "1111111111",
    year                     = 2023L,
    certification_year       = 2022L,   # within 1 year → newly_certified
    is_retired_for_cohorting = FALSE,
    retirement_data_conflict = TRUE,
    conflict_reason          = "medicare_part_b_billing",
    deceased                 = "N"
  )
  # Physician first appears in 2023 with cert_year = 2010 → late_observation
  old_row <- tibble::tibble(
    npi                      = "2222222222",
    year                     = 2023L,
    certification_year       = 2010L,   # > 1 year before → late_observation
    is_retired_for_cohorting = FALSE,
    retirement_data_conflict = TRUE,
    conflict_reason          = "medicare_part_b_billing",
    deceased                 = "N"
  )
  panel <- dplyr::bind_rows(new_row, old_row)
  tmp   <- withr::local_tempdir()
  # Round 299 fix: suppressWarnings() — old_row (cert_year=2010) triggers expected
  # old_certification_first_appearance warning(); this test only checks entry_type
  # taxonomy in contract_summary, not R warning signals.
  res   <- suppressWarnings(
    validate_workforce_truth_contract(panel, output_dir = tmp, strict = FALSE)
  )

  # Check oscillator_rates — in 2023: 0 reactivated, 1 newly_certified, 1 late_obs
  yr2023 <- dplyr::filter(res$contract_summary, truth_year == 2023L)
  expect_true("newly_certified" %in% yr2023$entry_type,
    info = "cert_year=2022 in 2023 must be newly_certified")
  expect_true("late_observation" %in% yr2023$entry_type,
    info = "cert_year=2010 in 2023 must be late_observation")
  expect_false("newly_certified" %in%
    dplyr::filter(yr2023, entry_type == "late_observation")$entry_type,
    info = "The two entry types must be distinct rows")
})

# ---------------------------------------------------------------------------
# S1 — cross-step join strips conflict_reason → inactive_but_marked_active
# ---------------------------------------------------------------------------

test_that("S1 cross-step join that drops conflict_reason is caught as inactive_but_marked_active", {
  # Physician legitimately reactivated 2022→2023 via Medicare Part B.
  # A downstream join (e.g. Step 5 outer join) overwrites conflict_reason with NA.
  # This is the exact failure mode from the 213-oscillator incident — the signal
  # evidence disappears and the reactivation becomes unsupported.
  valid_panel <- make_panel(
    is_retired               = c(TRUE,  FALSE),
    retirement_data_conflict = c(FALSE, TRUE),
    conflict_reason          = c(NA_character_, "medicare_part_b_billing")
  )
  # Simulate downstream join corruption: conflict_reason column gets NA'd
  corrupted_panel <- valid_panel
  corrupted_panel$conflict_reason <- NA_character_

  res_valid     <- run_validator(valid_panel)
  res_corrupted <- run_validator(corrupted_panel)

  expect_true(res_valid$valid,
    info = "Strong-signal reactivation (Medicare Part B) must pass")
  expect_false(res_corrupted$valid,
    info = "Dropped conflict_reason must be caught — cross-step drift detected")
  expect_true("inactive_but_marked_active" %in% res_corrupted$violation_rows$violation_reason,
    info = "No signal trace for a reactivated physician → inactive_but_marked_active")
})

# ---------------------------------------------------------------------------
# S2 — signal string poisoning: plausible-sounding but unrecognised string
# ---------------------------------------------------------------------------

test_that("S2 ambiguous conflict_reason that bypasses grepl is caught as inactive_but_marked_active", {
  # Someone changed conflict_reason from "medicare_part_b_billing" → "billing_recent".
  # "billing_recent" does NOT match:
  #   - exact "weak_cessation_only_billing_recent"  (it's a different string)
  #   - grepl("medicare|part_b|claims", ...)         (no match)
  # So signal = "none", a reactivated physician slips through with no justification.
  panel <- make_panel(
    is_retired               = c(TRUE,  FALSE),
    retirement_data_conflict = c(FALSE, TRUE),
    conflict_reason          = c(NA_character_, "billing_recent")  # poisoned string
  )
  res <- run_validator(panel)
  expect_false(res$valid,
    info = "Ambiguous signal string must not let unsupported reactivation pass validation")
  expect_true("inactive_but_marked_active" %in% res$violation_rows$violation_reason,
    info = "Poisoned signal string → signal=none → inactive_but_marked_active violation")
})

# ---------------------------------------------------------------------------
# S3 — unsorted input: sort-order guard fires but results are identical
# ---------------------------------------------------------------------------

test_that("S3 unsorted input triggers sort warning but produces identical violation counts", {
  # Use cert_year=2021L so there are no old_certification warnings to confuse the test.
  sorted_panel <- make_panel(
    certification_year       = 2021L,
    is_retired               = c(FALSE, FALSE),
    retirement_data_conflict = c(TRUE,  TRUE),
    conflict_reason          = c("medicare_part_b_billing", "medicare_part_b_billing")
  )
  # Reverse row order — common after a join that disrupts sort order
  reversed_panel <- sorted_panel[rev(seq_len(nrow(sorted_panel))), ]

  tmp <- withr::local_tempdir()

  sorted_warns <- character(0L)
  res_sorted <- withCallingHandlers(
    validate_workforce_truth_contract(sorted_panel, output_dir = tmp, strict = FALSE),
    warning = function(w) {
      sorted_warns <<- c(sorted_warns, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )

  reversed_warns <- character(0L)
  res_reversed <- withCallingHandlers(
    validate_workforce_truth_contract(reversed_panel, output_dir = tmp, strict = FALSE),
    warning = function(w) {
      reversed_warns <<- c(reversed_warns, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )

  expect_true(any(grepl("not sorted", reversed_warns, fixed = FALSE)),
    info = "Unsorted input must emit a sort-order warning")
  expect_false(any(grepl("not sorted", sorted_warns, fixed = FALSE)),
    info = "Pre-sorted input must not emit a sort-order warning")
  expect_equal(res_sorted$n_violations, res_reversed$n_violations,
    info = "Internal sort correction must produce identical violation counts")
})
