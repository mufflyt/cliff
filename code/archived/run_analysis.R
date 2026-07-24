#!/usr/bin/env Rscript
# Quick Test Runner for Comprehensive Retirement Forecasting
# ==========================================================
# Simple script to test the analysis with various configurations

# --- Quick test configurations -----------------------------------------------
test_configs <- list(

  # Quick test (100 simulations, 3 years)
  quick = list(
    n_simulations = 100,
    projection_years = 3,
    include_fellows = TRUE,
    description = "Quick test run (100 sims, 3 years)"
  ),

  # Standard test (1000 simulations, 5 years)
  standard = list(
    n_simulations = 1000,
    projection_years = 5,
    include_fellows = TRUE,
    description = "Standard analysis (1000 sims, 5 years)"
  ),

  # No fellowship pipeline
  no_fellows = list(
    n_simulations = 500,
    projection_years = 5,
    include_fellows = FALSE,
    description = "Without fellowship pipeline (500 sims, 5 years)"
  )
)

# --- Helper functions --------------------------------------------------------
run_test <- function(config_name, test_config) {
  cat("\n")
  cat(strrep("=", 60), "\n")
  cat("RUNNING TEST:", toupper(config_name), "\n")
  cat("Description:", test_config$description, "\n")
  cat(strrep("=", 60), "\n")

  # Create temporary config override
  temp_config_path <- "temp_config.yml"
  on.exit(if(file.exists(temp_config_path)) unlink(temp_config_path))

  # Write temporary config
  temp_config <- list(
    analysis = list(
      reference_year = 2025,
      projection = test_config
    ),
    data_sources = list(
      duckdb_path = "/Volumes/MufflySamsung/nber_my_duckdb.duckdb",
      tables = list(
        npidata = "npidata"
      )
    )
  )

  yaml::write_yaml(temp_config, temp_config_path)

  # Run analysis
  start_time <- Sys.time()

  tryCatch({
    source("comprehensive_analysis.R", local = TRUE)

    end_time <- Sys.time()
    runtime <- as.numeric(difftime(end_time, start_time, units = "mins"))

    cat("Test completed successfully!\n")
    cat("Runtime:", round(runtime, 2), "minutes\n")

    return(TRUE)

  }, error = function(e) {
    cat("Test FAILED with error:", conditionMessage(e), "\n")
    return(FALSE)
  })
}

# --- Main execution ----------------------------------------------------------
if(!interactive()) {

  # Parse command line arguments
  args <- commandArgs(trailingOnly = TRUE)

  if(length(args) == 0) {
    cat("Available test configurations:\n")
    for(name in names(test_configs)) {
      cat(sprintf("  %s: %s\n", name, test_configs[[name]]$description))
    }
    cat("\nUsage: Rscript run_analysis.R [config_name]\n")
    cat("Example: Rscript run_analysis.R quick\n")
    quit(status = 1)
  }

  config_name <- args[1]

  if(!config_name %in% names(test_configs)) {
    cat("Error: Unknown configuration '", config_name, "'\n")
    cat("Available: ", paste(names(test_configs), collapse = ", "), "\n")
    quit(status = 1)
  }

  # Load required libraries
  suppressPackageStartupMessages({
    library(yaml)
  })

  # Run the test
  success <- run_test(config_name, test_configs[[config_name]])

  if(success) {
    cat("\nTest completed successfully!\n")
  } else {
    cat("\nTest failed!\n")
    quit(status = 1)
  }
}
