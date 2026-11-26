# Adversarial guards for state normalization in fellowship enrichment and Census
# region assignment. These regressions covered mixed case and full state names
# being silently classified as mismatches / Unknown.
library(testthat)

test_that("[adversarial] classify_us_region accepts canonical state spellings", {
  classify_us_region <- getFromNamespace("classify_us_region", "cliff")
  expect_identical(
    classify_us_region(c("co", "Colorado", " texas ", "Puerto Rico", "pr", NA_character_)),
    c("West", "West", "South", "Puerto Rico", "Puerto Rico", "Unknown")
  )
  expect_identical(classify_us_region("New York"), "Northeast")
})

test_that("[adversarial] table enrichment normalizes practice and inference states", {
  skip_if_not_installed("dplyr")
  skip_if_not_installed("mufflyaccess")

  testthat::local_mocked_bindings(
    create_otolaryngology_fellowship_programs = function() {
      data.frame(
        program_name = "Synthetic Fellowship",
        specialty = "Synthetic Specialty",
        stringsAsFactors = FALSE
      )
    },
    infer_fellowship_training = function(physicians, programs, temporal_db_path) {
      dplyr::mutate(
        physicians,
        inferred_state = c("co", "Texas", "Colorado", NA_character_),
        inference_confidence = 0,
        inferred_acgme_id = NA_character_,
        inferred_program = NA_character_,
        inference_state = c("Colorado", "tx", "New York", NA_character_),
        training_annual_births = NA_real_,
        training_nicu_beds = NA_real_,
        training_total_beds = NA_real_,
        training_trauma_center = NA_character_
      )
    },
    .package = "cliff"
  )

  physicians <- data.frame(
    npi = c("1234567893", "1234567894", "1234567895", "1234567896"),
    state = c("Colorado", "Texas", "New York", NA_character_),
    stringsAsFactors = FALSE
  )
  out <- add_fellowship_to_table1(physicians, temporal_db_path = "unused-by-mock")

  expect_identical(out$fellowship_region, c("West", "South", "West", "Unknown"))
  expect_identical(out$trained_in_practice_state, c("Yes", "Yes", "No", NA_character_))
  expect_identical(out$geo_plausible, c(TRUE, TRUE, FALSE, NA))
})
