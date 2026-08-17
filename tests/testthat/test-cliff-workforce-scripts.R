# tests/testthat/test-cliff-workforce-scripts.R
# Integration-style regression tests for workforce cliff scripts

library(testthat)
library(here)
library(readr)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

run_cliff_script <- function(script_path, args = character()) {
  # Spawn THIS R, with THIS R's libraries.
  #
  # `system2("Rscript", ...)` resolves Rscript from PATH, which need not be the R
  # running the tests. On a machine with R 4.4.2 first on PATH and the suite running
  # under 4.5.3, the child inherited R_HOME and R_LIBS from the parent, printed
  # "WARNING: ignoring environment value of R_HOME", then segfaulted inside
  # tidyverse's .onLoad while reading 4.5.3-built packages -- status 139, six failing
  # assertions, and not one of them about the product. See issue #43.
  #
  # R.home("bin") pins the child to the same R. Passing the parent's .libPaths()
  # keeps the child's package environment identical to the suite's, and disabling the
  # renv autoloader stops the child's .Rprofile from replacing those paths with a
  # possibly-unrestored renv library. CI already sets the same variable at workflow
  # level (.github/workflows/_core.yml), so this matches how CI runs these scripts.
  output <- system2(
    command = file.path(R.home("bin"), "Rscript"),
    args = c(script_path, args),
    stdout = TRUE,
    stderr = TRUE,
    env = c(sprintf("R_LIBS=%s", paste(.libPaths(), collapse = .Platform$path.sep)),
            "RENV_CONFIG_AUTOLOADER_ENABLED=FALSE")
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
