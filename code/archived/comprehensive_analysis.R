#!/usr/bin/env Rscript
# Comprehensive Retirement Forecasting Analysis
# =============================================
# Complete end-to-end workforce projection analysis with robust error handling

suppressPackageStartupMessages({
  library(dplyr)
  library(DBI)
  library(duckdb)
  library(ggplot2)
  library(viridis)
  library(readr)
  library(patchwork)
  library(tidyr)
  library(tibble)
  library(yaml)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

# --- Config & Setup ----------------------------------------------------------
cfg_env <- Sys.getenv("SGS_CONFIG_PATH", unset = NA)
config_path <- if (!is.na(cfg_env)) cfg_env else {
  if (file.exists("config/sgs_access_cliff.yml")) "config/sgs_access_cliff.yml"
  else "../../config/sgs_access_cliff.yml"
}
config <- yaml::read_yaml(config_path)

reference_year <- config$analysis$reference_year %||% as.integer(format(Sys.Date(), "%Y"))
npidata_table  <- config$data_sources$tables$npidata %||% "nppes.practice_locations_enhanced"

# Projection parameters
n_sims    <- config$analysis$projection$n_simulations %||% 1000L
n_years   <- config$analysis$projection$years %||% 5L
add_fellows <- isTRUE(config$analysis$projection$include_fellows %||% TRUE)
start_year <- reference_year + 1

# Output setup
out_dir <- "results"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
ts <- format(Sys.time(), "%Y%m%d_%H%M%S")

# --- Source component functions from other scripts --------------------------
# Note: These scripts define extract_retirement_cohort() and build_retirement_hazard_model()
tryCatch({
  source("retirement_hazard_model.R", local = TRUE)
}, error = function(e) {
  stop("Could not source retirement_hazard_model.R: ", conditionMessage(e))
})

tryCatch({
  source("monte_carlo_simulation.R", local = TRUE)
}, error = function(e) {
  stop("Could not source monte_carlo_simulation.R: ", conditionMessage(e))
})

#' Generate comprehensive retirement forecast report
#'
#' @param timestamp Character timestamp for file naming
#' @param config_override List of config overrides
#' @return List with all analysis results
generate_comprehensive_forecast <- function(timestamp = ts, config_override = NULL) {

  cat("=== COMPREHENSIVE RETIREMENT FORECASTING ANALYSIS ===\n")
  cat("Config:", config_path, "\n")
  cat("Reference year:", reference_year, "\n")
  cat("Projection:", n_years, "years,", n_sims, "simulations\n")
  cat("Fellowship pipeline:", if(add_fellows) "ENABLED" else "DISABLED", "\n")
  cat("Start time:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

  tryCatch({
    # Step 1: Extract cohort and build hazard model
    cat("STEP 1: Data extraction and hazard modeling\n")
    cohort_data <- extract_retirement_cohort()
    hazard_results <- build_retirement_hazard_model(cohort_data)

    # Step 2: Load fellowship pipeline data
    cat("STEP 2: Loading fellowship pipeline data\n")
    fellowship_path <- if (file.exists("inputs/fellowship_grads_2022_2024.csv")) {
      "inputs/fellowship_grads_2022_2024.csv"
    } else {
      "../../inputs/fellowship_grads_2022_2024.csv"
    }
    entrants_plan <- NULL
    fellowship_summary <- NULL

    if(add_fellows && file.exists(fellowship_path)) {
      entrants_plan <- load_fellowship_plan(
        path = fellowship_path,
        start_year = start_year,
        projection_years = n_years,
        mode = "avg"
      )

      # Create fellowship summary for reporting
      fellowship_summary <- entrants_plan %>%
        group_by(subspecialty_f) %>%
        summarise(
          avg_annual_grads = mean(n_new),
          projected_5yr = sum(n_new),
          .groups = "drop"
        ) %>%
        mutate(
          subspecialty_clean = case_when(
            subspecialty_f == "Female Pelvic Medicine & Reconstructive Surgery" ~ "FPMRS/URPS",
            subspecialty_f == "Gynecologic Oncology" ~ "Gynecologic Oncology",
            subspecialty_f == "MIG" ~ "MIG",
            TRUE ~ as.character(subspecialty_f)
          )
        )

      cat("  • Fellowship entrants loaded:", sum(entrants_plan$n_new), "total over", n_years, "years\n")
    } else {
      cat("  • No fellowship data loaded (file missing or disabled)\n")
    }

    # Step 3: Monte Carlo workforce projections
    cat("STEP 3: Monte Carlo workforce projections\n")
    projection_results <- monte_carlo_workforce_projection(
      hazard_results,
      n_simulations = n_sims,
      projection_years = n_years,
      start_year = start_year,
      entrants_plan = entrants_plan
    )

    # Step 4: Create comprehensive visualizations
    cat("STEP 4: Generating visualizations\n")
    viz_results <- create_projection_visualization(projection_results)

    # Step 5: Comprehensive analysis and reporting
    cat("STEP 5: Comprehensive analysis and reporting\n")

    # Calculate baseline workforce by subspecialty
    baseline_by_subspecialty <- hazard_results$data %>%
      filter(retired_binary == 0) %>%
      group_by(subspecialty_f) %>%
      summarise(
        baseline_active = n(),
        mean_age = mean(estimated_age, na.rm = TRUE),
        pct_female = mean(gender_f == "Female", na.rm = TRUE) * 100,
        .groups = "drop"
      )

    # Generate final summary for end year
    end_year <- start_year + n_years - 1
    final_summary <- projection_results$summary %>%
      filter(year == end_year) %>%
      left_join(baseline_by_subspecialty, by = "subspecialty_f") %>%
      mutate(
        subspecialty_clean = case_when(
          subspecialty_f == "Female Pelvic Medicine & Reconstructive Surgery" ~ "FPMRS/URPS",
          subspecialty_f == "Gynecologic Oncology" ~ "Gynecologic Oncology",
          subspecialty_f == "MIG" ~ "MIG",
          TRUE ~ as.character(subspecialty_f)
        ),
        projected_loss = baseline_active - mean_active,
        pct_loss = round((projected_loss / baseline_active) * 100, 1),
        ci_lower_loss = baseline_active - q95_active,
        ci_upper_loss = baseline_active - q05_active
      )

    # Add fellowship comparison if available
    if(!is.null(fellowship_summary)) {
      final_summary <- final_summary %>%
        left_join(fellowship_summary, by = "subspecialty_clean") %>%
        mutate(
          net_replacement = projected_5yr - projected_loss,
          replacement_ratio = projected_5yr / projected_loss,
          adequacy = case_when(
            replacement_ratio >= 1.2 ~ "Adequate",
            replacement_ratio >= 0.8 ~ "Marginal",
            TRUE ~ "Insufficient"
          )
        )
    }

    # Geographic analysis
    geographic_analysis <- cohort_data %>%
      filter(retired_binary == 0, !is.na(practice_state)) %>%
      group_by(practice_state, subspecialty_name) %>%
      summarise(
        active_physicians = n(),
        .groups = "drop"
      ) %>%
      group_by(subspecialty_name) %>%
      mutate(
        pct_of_subspecialty = round(active_physicians / sum(active_physicians) * 100, 1)
      ) %>%
      arrange(subspecialty_name, desc(active_physicians))

    # Step 6: Save all results
    cat("STEP 6: Saving results\n")

    # Save main combined visualization
    if (!is.null(viz_results$combined)) {
      proj_path <- file.path(out_dir, sprintf("comprehensive_workforce_projection_%s.png", timestamp))
      ggsave(proj_path, viz_results$combined, width = 12, height = 14, dpi = 300, bg = "white")
      cat("  • Combined visualization:", proj_path, "\n")
    }

    # Save individual plots
    workforce_path <- file.path(out_dir, sprintf("workforce_projections_%s.png", timestamp))
    ggsave(workforce_path, viz_results$workforce_projection, width = 10, height = 6, dpi = 300, bg = "white")

    rates_path <- file.path(out_dir, sprintf("retirement_rates_%s.png", timestamp))
    ggsave(rates_path, viz_results$retirement_rates, width = 10, height = 6, dpi = 300, bg = "white")

    # Save entrants panel if available
    if (!is.null(viz_results$entrants_panel)) {
      entrants_path <- file.path(out_dir, sprintf("fellowship_entrants_%s.png", timestamp))
      ggsave(entrants_path, viz_results$entrants_panel, width = 10, height = 4.5, dpi = 300, bg = "white")
      cat("  • Fellowship entrants:", entrants_path, "\n")
    }

    # Save data files
    data_path <- file.path(out_dir, sprintf("workforce_projection_data_%s.csv", timestamp))
    write_csv(projection_results$summary, data_path)

    summary_path <- file.path(out_dir, sprintf("comprehensive_summary_%s.csv", timestamp))
    write_csv(final_summary, summary_path)

    geographic_path <- file.path(out_dir, sprintf("geographic_analysis_%s.csv", timestamp))
    write_csv(geographic_analysis, geographic_path)

    # Save R objects
    saveRDS(cohort_data, file.path(out_dir, sprintf("cohort_data_%s.rds", timestamp)))
    saveRDS(hazard_results, file.path(out_dir, sprintf("hazard_model_%s.rds", timestamp)))
    saveRDS(projection_results, file.path(out_dir, sprintf("projections_%s.rds", timestamp)))
    saveRDS(viz_results, file.path(out_dir, sprintf("visualizations_%s.rds", timestamp)))

    # Step 7: Generate interpretable summary report
    cat("\n")
    cat(strrep("=", 70), "\n")
    cat("COMPREHENSIVE WORKFORCE FORECAST SUMMARY\n")
    cat(strrep("=", 70), "\n")
    cat("Analysis timestamp:", timestamp, "\n")
    cat("Reference year:", reference_year, "\n")
    cat("Baseline workforce (", reference_year, "):", projection_results$baseline_workforce, "active physicians\n")
    cat("Projection horizon:", start_year, "-", end_year, "\n")
    cat("Monte Carlo simulations:", n_sims, "iterations\n")
    cat("Fellowship pipeline:", if(add_fellows) "INCLUDED" else "EXCLUDED", "\n\n")

    cat("SUBSPECIALTY PROJECTIONS (by", end_year, "):\n")
    cat(strrep("-", 50), "\n")
    for(i in 1:nrow(final_summary)) {
      row <- final_summary[i, ]
      cat(sprintf("• %s:\n", row$subspecialty_clean))
      cat(sprintf("  Baseline (%d): %d physicians\n", reference_year, row$baseline_active))
      cat(sprintf("  Projected (%d): %.0f (95%% CI: %.0f-%.0f)\n",
                 end_year, row$mean_active, row$q05_active, row$q95_active))
      cat(sprintf("  Expected loss: %.0f physicians (%.1f%%)\n",
                 row$projected_loss, row$pct_loss))

      if(!is.null(fellowship_summary) && !is.na(row$projected_5yr)) {
        cat(sprintf("  Fellowship pipeline (%d-%d): %d new graduates\n",
                   start_year, end_year, row$projected_5yr))
        cat(sprintf("  Net replacement: %+.0f physicians\n", row$net_replacement))
        cat(sprintf("  Adequacy assessment: %s\n", row$adequacy))
      }

      if(!is.na(row$mean_age)) {
        cat(sprintf("  Demographics: %.1f years mean age, %.0f%% female\n",
                   row$mean_age, row$pct_female))
      }
      cat("\n")
    }

    cat("GEOGRAPHIC DISTRIBUTION (Top 5 states by subspecialty):\n")
    cat(strrep("-", 55), "\n")
    for(subspecialty in unique(geographic_analysis$subspecialty_name)) {
      cat(sprintf("%s:\n", subspecialty))
      top_states <- geographic_analysis %>%
        filter(subspecialty_name == subspecialty) %>%
        head(5)

      for(j in 1:nrow(top_states)) {
        state_row <- top_states[j, ]
        cat(sprintf("  %s: %d physicians (%.1f%%)\n",
                   state_row$practice_state, state_row$active_physicians,
                   state_row$pct_of_subspecialty))
      }
      cat("\n")
    }

    cat("FILES GENERATED:\n")
    cat(strrep("-", 20), "\n")
    cat("• Workforce projections:", workforce_path, "\n")
    cat("• Retirement rates:", rates_path, "\n")
    cat("• Projection data:", data_path, "\n")
    cat("• Executive summary:", summary_path, "\n")
    cat("• Geographic analysis:", geographic_path, "\n")
    cat("• Model objects saved with timestamp", timestamp, "\n\n")

    cat("Analysis completed successfully!\n")
    cat("End time:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")

    return(list(
      config = list(
        reference_year = reference_year,
        projection_years = n_years,
        simulations = n_sims,
        fellowship_enabled = add_fellows,
        timestamp = timestamp
      ),
      cohort = cohort_data,
      model = hazard_results,
      projections = projection_results,
      visualizations = viz_results,
      summary = final_summary,
      geographic = geographic_analysis,
      fellowship = fellowship_summary,
      entrants_plan = entrants_plan
    ))

  }, error = function(e) {
    cat("ERROR in comprehensive forecast generation:", conditionMessage(e), "\n")
    cat("Traceback:\n")
    traceback()
    return(NULL)
  })
}

# Execute the comprehensive analysis when run as script
if(!interactive()) {
  cat("Starting comprehensive retirement forecasting analysis...\n")

  results <- generate_comprehensive_forecast()

  if(!is.null(results)) {
    cat("\n")
    cat(strrep("=", 70), "\n")
    cat("COMPREHENSIVE RETIREMENT FORECASTING ANALYSIS COMPLETE\n")
    cat(strrep("=", 70), "\n")
    cat("All artifacts saved in:", out_dir, "\n")
    cat("Timestamp:", ts, "\n")
  } else {
    cat("\n")
    cat("ANALYSIS FAILED - Check error messages above\n")
    quit(status = 1)
  }
}
