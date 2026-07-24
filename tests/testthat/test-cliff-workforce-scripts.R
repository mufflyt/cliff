# tests/testthat/test-cliff-workforce-scripts.R
# Integration-style regression tests for workforce cliff scripts

library(testthat)
library(here)
library(readr)

run_cliff_script <- function(script_path, args = character()) {
  output <- system2(
    command = "Rscript",
    args = c(script_path, args),
    stdout = TRUE,
    stderr = TRUE
  )

  status <- attr(output, "status")
  if (is.null(status)) {
    status <- 0
  }

  list(
    status = status,
    output = paste(output, collapse = "\n")
  )
}

expect_successful_run <- function(result, script_name) {
  if (result$status != 0) {
    fail(sprintf("%s failed with status %d\nOutput:\n%s",
                 script_name, result$status, result$output))
  } else {
    succeed()
  }
}

test_that("04_compare_scenarios produces scenario comparison artifacts", {
  script <- here("code", "04_compare_scenarios.R")
  result <- run_cliff_script(script)
  expect_successful_run(result, basename(script))

  comparison_file <- here("data", "scenario_comparison.csv")
  expect_true(file.exists(comparison_file))

  comparison_data <- read_csv(comparison_file, show_col_types = FALSE)
  expect_true(all(c("scenario", "subspecialty_abbrev", "projected_2029") %in%
                    names(comparison_data)))
  expect_true("default" %in% unique(comparison_data$scenario))

  default_snapshot <- here("data", "workforce_projections_consolidated_default.csv")
  expect_true(file.exists(default_snapshot))
})

test_that("05_validate_with_monte_carlo generates validation snapshot", {
  script <- here("code", "05_validate_with_monte_carlo.R")
  result <- run_cliff_script(script)
  expect_successful_run(result, basename(script))

  validation_file <- here(
    "data", "workforce_projections_consolidated_historical_2025_validation.csv"
  )
  expect_true(file.exists(validation_file))

  validation_data <- read_csv(validation_file, show_col_types = FALSE)
  expect_equal(nrow(validation_data), 3)
  expect_true(all(c("subspecialty", "baseline_2025", "projected_2029") %in%
                    names(validation_data)))
})

test_that("06_retirement_sensitivity recalculates sensitivity dataset", {
  script <- here("code", "06_retirement_sensitivity.R")
  result <- run_cliff_script(script)
  expect_successful_run(result, basename(script))

  sensitivity_file <- here("data", "retirement_sensitivity.csv")
  expect_true(file.exists(sensitivity_file))

  sensitivity <- read_csv(sensitivity_file, show_col_types = FALSE)
  expect_true("baseline" %in% unique(sensitivity$scenario_id))

  baseline_rows <- subset(sensitivity, scenario_id == "baseline")
  expect_equal(nrow(baseline_rows), 3)
  expect_true(all(baseline_rows$projected_workforce > 0))
})

test_that("07_create_table1 pipeline generates artifacts", {
  script <- here("code", "07_create_table1.R")
  result <- run_cliff_script(script)

  if (result$status != 0 &&
      grepl("OMP: Error #", result$output) &&
      grepl("Operation not permitted", result$output)) {
    skip("Table 1 pipeline requires shared memory not available in this environment")
  }
  if (result$status != 0 &&
      grepl("No such file or directory", result$output)) {
    skip("Table 1 sub-pipeline script not present in this environment")
  }

  expect_successful_run(result, basename(script))

  table1_data <- here("data", "table1_physicians.csv")
  table1_doc <- here("manuscript", "tables", "table1_demographics.docx")

  expect_true(file.exists(table1_data))
  expect_true(file.exists(table1_doc))

  tbl <- read_csv(table1_data, show_col_types = FALSE)
  expect_equal(nrow(tbl), sum(tbl$Subspecialty == "FPMRS (Urogynecology)" |
                               tbl$Subspecialty == "Gynecologic Oncology" |
                               tbl$Subspecialty == "MIGS"))
})
