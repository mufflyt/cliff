#!/usr/bin/env Rscript
# Flexible Multi-Specialty Pipeline Runner
# ========================================
# Command-line interface for running any specialty workforce analysis

library(optparse)
library(dplyr)

# Source all required functions
source("R/specialty_config_loader.R")
source("R/external_provider_loader.R")
source("R/geographic_filter.R")
source("R/provider_list_validator.R")
source("R/schema_validation_functions.R")
source("R/specialty_data_enrichment.R")
source("R/specialty_retirement_model.R")
source("R/geographic_workforce_analysis.R")

#' Main Specialty Analysis Pipeline
#' @param args Command line arguments parsed by optparse
#' @return Analysis results
run_specialty_analysis_pipeline <- function(args) {

  start_time <- Sys.time()

  cat("🚀 MULTI-SPECIALTY WORKFORCE ANALYSIS PIPELINE\n")
  cat("==============================================\n")
  cat(sprintf("🕐 Started: %s\n", start_time))
  cat(sprintf("🏥 Specialty: %s\n", args$specialty))
  cat(sprintf("📁 Provider list: %s\n", args$provider_list))
  cat(sprintf("🌍 Geographic scope: %s\n", args$geography %||% "All available"))

  # Step 1: Comprehensive Data Enrichment
  cat("\n🔄 PHASE 1: COMPREHENSIVE DATA ENRICHMENT\n")
  cat("=========================================\n")

  # Set up geographic filtering if specified
  geographic_filter <- NULL
  if (!is.null(args$geography)) {
    geographic_filter <- parse_geographic_filter(args$geography)
  }

  # Run complete data enrichment pipeline
  enrichment_results <- enrich_specialty_provider_data(
    provider_list_file = args$provider_list,
    specialty_name = args$specialty,
    geographic_filter = geographic_filter,
    enrichment_sources = args$data_sources,
    validation_level = args$validation_level
  )

  enriched_providers <- enrichment_results$enriched_providers
  specialty_config <- enrichment_results$specialty_config

  cat(sprintf("✅ Data enrichment complete: %d providers\n", nrow(enriched_providers)))

  # Step 2: Retirement Analysis
  cat("\n🔄 PHASE 2: RETIREMENT ANALYSIS\n")
  cat("===============================\n")

  # Prepare data for retirement analysis
  analysis_ready_data <- prepare_for_retirement_analysis(
    enriched_data = enriched_providers,
    specialty_config = specialty_config,
    quality_threshold = args$quality_threshold
  )

  # Apply retirement model
  retirement_analyzed <- apply_specialty_retirement_model(
    provider_data = analysis_ready_data,
    specialty_config = specialty_config,
    model_type = args$retirement_model
  )

  cat(sprintf("✅ Retirement analysis complete: %d providers analyzed\n", nrow(retirement_analyzed)))

  # Step 3: Geographic Analysis
  cat("\n🔄 PHASE 3: GEOGRAPHIC WORKFORCE ANALYSIS\n")
  cat("=========================================\n")

  geographic_results <- analyze_geographic_distribution(
    provider_data = retirement_analyzed,
    specialty_config = specialty_config,
    analysis_level = args$geographic_level
  )

  # Step 4: Workforce Projections
  cat("\n🔄 PHASE 4: WORKFORCE PROJECTIONS\n")
  cat("=================================\n")

  workforce_projections <- create_geographic_workforce_projections(
    provider_data = retirement_analyzed,
    geographic_analysis = geographic_results,
    projection_years = args$projection_years
  )

  cat(sprintf("✅ Workforce projections complete: %d geographic units\n",
             length(unique(workforce_projections$geographic_unit))))

  # Step 5: Results Export
  cat("\n🔄 PHASE 5: RESULTS EXPORT\n")
  cat("=========================\n")

  # Create output directory
  output_dir <- file.path(args$output_dir,
                         paste0(args$specialty, "_", format(Sys.Date(), "%Y%m%d")))
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  # Export comprehensive results
  export_success <- export_comprehensive_results(
    enriched_providers = enriched_providers,
    retirement_analyzed = retirement_analyzed,
    geographic_results = geographic_results,
    workforce_projections = workforce_projections,
    enrichment_summary = enrichment_results$enrichment_summary,
    specialty_config = specialty_config,
    output_dir = output_dir,
    args = args
  )

  # Generate final summary
  end_time <- Sys.time()
  total_duration <- difftime(end_time, start_time, units = "mins")

  final_summary <- create_pipeline_summary(
    enrichment_results = enrichment_results,
    retirement_analyzed = retirement_analyzed,
    geographic_results = geographic_results,
    workforce_projections = workforce_projections,
    execution_metadata = list(
      start_time = start_time,
      end_time = end_time,
      duration_minutes = as.numeric(total_duration),
      args = args
    )
  )

  cat("\n🎉 PIPELINE COMPLETE\n")
  cat("===================\n")
  cat(sprintf("⏱️  Total execution time: %.1f minutes\n", as.numeric(total_duration)))
  cat(sprintf("📁 Results saved to: %s\n", output_dir))
  cat(sprintf("📊 Final analysis: %d providers, %d geographic units\n",
             nrow(retirement_analyzed), geographic_results$analysis_metadata$geographic_units))

  return(final_summary)
}

#' Parse Geographic Filter from Command Line Argument
#' @param geography_string Geographic filter string
#' @return List with geographic filter criteria
parse_geographic_filter <- function(geography_string) {

  if (is.null(geography_string) || geography_string == "") {
    return(NULL)
  }

  filter_list <- list()

  # Parse state filter (e.g., "state:CO" or "state:CO,CA,TX")
  if (grepl("state:", geography_string)) {
    state_match <- regmatches(geography_string, regexpr("state:[A-Z,]+", geography_string))
    if (length(state_match) > 0) {
      states <- unlist(strsplit(gsub("state:", "", state_match), ","))
      filter_list$state <- trimws(states)
    }
  }

  # Parse city filter (e.g., "city:Denver,Boulder")
  if (grepl("city:", geography_string)) {
    city_match <- regmatches(geography_string, regexpr("city:[A-Za-z ,]+", geography_string))
    if (length(city_match) > 0) {
      cities <- unlist(strsplit(gsub("city:", "", city_match), ","))
      filter_list$city <- trimws(cities)
    }
  }

  return(filter_list)
}

#' Export Comprehensive Analysis Results
#' @param enriched_providers Enriched provider dataset
#' @param retirement_analyzed Retirement analysis results
#' @param geographic_results Geographic analysis results
#' @param workforce_projections Workforce projection results
#' @param enrichment_summary Data enrichment summary
#' @param specialty_config Specialty configuration
#' @param output_dir Output directory
#' @param args Command line arguments
#' @return TRUE if export successful
export_comprehensive_results <- function(enriched_providers,
                                        retirement_analyzed,
                                        geographic_results,
                                        workforce_projections,
                                        enrichment_summary,
                                        specialty_config,
                                        output_dir,
                                        args) {

  cat("💾 Exporting comprehensive analysis results\n")

  tryCatch({

    # 1. Core provider datasets
    readr::write_csv(enriched_providers,
                    file.path(output_dir, "01_enriched_providers.csv"))

    readr::write_csv(retirement_analyzed,
                    file.path(output_dir, "02_retirement_analysis.csv"))

    # 2. Geographic analysis
    export_geographic_analysis(geographic_results, output_dir, "03_geographic")

    # 3. Workforce projections
    readr::write_csv(workforce_projections,
                    file.path(output_dir, "04_workforce_projections.csv"))

    # 4. Summary reports
    jsonlite::write_json(enrichment_summary,
                        file.path(output_dir, "05_enrichment_summary.json"),
                        pretty = TRUE)

    # 5. Configuration and metadata
    yaml::write_yaml(specialty_config,
                    file.path(output_dir, "06_specialty_config.yaml"))

    # 6. Execution metadata
    execution_log <- list(
      pipeline_version = "1.0.0",
      execution_date = Sys.time(),
      command_line_args = args,
      r_version = R.version.string,
      package_versions = list(
        dplyr = as.character(packageVersion("dplyr")),
        yaml = as.character(packageVersion("yaml"))
      )
    )

    jsonlite::write_json(execution_log,
                        file.path(output_dir, "07_execution_log.json"),
                        pretty = TRUE)

    # 7. Quick summary report
    create_summary_report(retirement_analyzed, geographic_results, specialty_config, output_dir)

    cat("✅ All results exported successfully\n")
    return(TRUE)

  }, error = function(e) {
    cat(sprintf("❌ Export failed: %s\n", e$message))
    return(FALSE)
  })
}

#' Create Quick Summary Report
#' @param retirement_analyzed Retirement analysis data
#' @param geographic_results Geographic analysis results
#' @param specialty_config Specialty configuration
#' @param output_dir Output directory
create_summary_report <- function(retirement_analyzed, geographic_results, specialty_config, output_dir) {

  specialty_name <- specialty_config$specialty_info$specialty_name

  summary_text <- sprintf("
# %s Workforce Analysis Summary
# Generated: %s

## Key Findings

### Current Workforce
- **Total Providers**: %d
- **Average Age**: %.1f years
- **Providers 65+**: %d (%.1f%%)

### Retirement Projections
- **Expected Retirements (5 years)**: %.1f providers
- **Expected Retirements (10 years)**: %.1f providers
- **High Retirement Risk**: %d providers (%.1f%%)

### Geographic Distribution
- **Geographic Units Analyzed**: %d
- **Units with No Providers**: %d
- **Coverage Rate**: %.1f%%

### Data Quality
- **Analysis-Ready Providers**: %d (%.1f%%)
- **High Quality Data**: %d (%.1f%%)
- **NPPES Validation Rate**: %.1f%%

## Recommendations
%s

---
Generated by Multi-Specialty Workforce Analysis Pipeline
",
    specialty_name,
    format(Sys.time(), "%Y-%m-%d %H:%M:%S"),

    # Current workforce
    nrow(retirement_analyzed),
    mean(retirement_analyzed$estimated_age, na.rm = TRUE),
    sum(retirement_analyzed$estimated_age >= 65, na.rm = TRUE),
    mean(retirement_analyzed$estimated_age >= 65, na.rm = TRUE) * 100,

    # Retirement projections
    sum(retirement_analyzed$retirement_prob_5yr, na.rm = TRUE),
    sum(retirement_analyzed$retirement_prob_10yr, na.rm = TRUE),
    sum(retirement_analyzed$retirement_risk_5yr == "Very High", na.rm = TRUE),
    mean(retirement_analyzed$retirement_risk_5yr == "Very High", na.rm = TRUE) * 100,

    # Geographic
    geographic_results$analysis_metadata$geographic_units,
    nrow(geographic_results$underserved_areas$no_providers),
    geographic_results$access_analysis$coverage_rate * 100,

    # Data quality
    sum(retirement_analyzed$analysis_ready, na.rm = TRUE),
    mean(retirement_analyzed$analysis_ready, na.rm = TRUE) * 100,
    sum(retirement_analyzed$overall_data_quality >= 0.8, na.rm = TRUE),
    mean(retirement_analyzed$overall_data_quality >= 0.8, na.rm = TRUE) * 100,
    mean(retirement_analyzed$validation_confidence > 0, na.rm = TRUE) * 100,

    # Recommendations
    generate_recommendations(retirement_analyzed, geographic_results, specialty_config)
  )

  writeLines(summary_text, file.path(output_dir, "00_SUMMARY_REPORT.md"))
}

#' Generate Analysis Recommendations
#' @param retirement_analyzed Retirement analysis data
#' @param geographic_results Geographic analysis results
#' @param specialty_config Specialty configuration
#' @return Recommendation text
generate_recommendations <- function(retirement_analyzed, geographic_results, specialty_config) {

  recommendations <- c()

  # Retirement-based recommendations
  high_retirement_rate <- mean(retirement_analyzed$retirement_prob_5yr, na.rm = TRUE) > 0.3
  if (high_retirement_rate) {
    recommendations <- c(recommendations,
                        "- **Urgent**: High retirement rate detected. Consider recruitment incentives.")
  }

  # Geographic recommendations
  no_provider_areas <- nrow(geographic_results$underserved_areas$no_providers)
  if (no_provider_areas > 0) {
    recommendations <- c(recommendations,
                        sprintf("- **Geographic Access**: %d areas with no providers need attention.",
                               no_provider_areas))
  }

  # Data quality recommendations
  low_quality_rate <- mean(retirement_analyzed$overall_data_quality >= 0.8, na.rm = TRUE) < 0.7
  if (low_quality_rate) {
    recommendations <- c(recommendations,
                        "- **Data Quality**: Improve data collection for more accurate projections.")
  }

  if (length(recommendations) == 0) {
    recommendations <- c("- Workforce appears stable with adequate geographic distribution.")
  }

  return(paste(recommendations, collapse = "\n"))
}

#' Create Pipeline Summary
#' @param enrichment_results Data enrichment results
#' @param retirement_analyzed Retirement analysis data
#' @param geographic_results Geographic analysis results
#' @param workforce_projections Workforce projections
#' @param execution_metadata Execution metadata
#' @return Pipeline summary
create_pipeline_summary <- function(enrichment_results,
                                   retirement_analyzed,
                                   geographic_results,
                                   workforce_projections,
                                   execution_metadata) {

  summary <- list(
    pipeline_metadata = execution_metadata,
    data_summary = enrichment_results$enrichment_summary,
    analysis_results = list(
      total_providers_analyzed = nrow(retirement_analyzed),
      geographic_units = geographic_results$analysis_metadata$geographic_units,
      projection_years = max(workforce_projections$projection_year) - 2025,
      high_retirement_risk_providers = sum(retirement_analyzed$retirement_risk_5yr == "Very High", na.rm = TRUE)
    ),
    key_findings = list(
      average_age = round(mean(retirement_analyzed$estimated_age, na.rm = TRUE), 1),
      expected_retirements_5yr = round(sum(retirement_analyzed$retirement_prob_5yr, na.rm = TRUE), 1),
      coverage_rate = round(geographic_results$access_analysis$coverage_rate * 100, 1),
      data_quality_rate = round(mean(retirement_analyzed$overall_data_quality >= 0.8, na.rm = TRUE) * 100, 1)
    )
  )

  return(summary)
}

# Define command line options
option_list <- list(
  make_option(c("-s", "--specialty"), type = "character", default = NULL,
              help = "Specialty name (e.g., 'radiation_oncology')", metavar = "character"),

  make_option(c("-p", "--provider-list"), type = "character", default = NULL,
              help = "Path to provider list file", metavar = "character"),

  make_option(c("-g", "--geography"), type = "character", default = NULL,
              help = "Geographic filter (e.g., 'state:CO' or 'city:Denver,Boulder')", metavar = "character"),

  make_option(c("-o", "--output-dir"), type = "character", default = "results",
              help = "Output directory [default %default]", metavar = "character"),

  make_option(c("-m", "--retirement-model"), type = "character", default = "empirical",
              help = "Retirement model type [default %default]", metavar = "character"),

  make_option(c("-l", "--geographic-level"), type = "character", default = "county",
              help = "Geographic analysis level [default %default]", metavar = "character"),

  make_option(c("-v", "--validation-level"), type = "character", default = "moderate",
              help = "Data validation strictness [default %default]", metavar = "character"),

  make_option(c("-q", "--quality-threshold"), type = "numeric", default = 0.5,
              help = "Minimum data quality threshold [default %default]", metavar = "number"),

  make_option(c("-y", "--projection-years"), type = "integer", default = 10,
              help = "Years for workforce projections [default %default]", metavar = "number"),

  make_option(c("-d", "--data-sources"), type = "character",
              default = "nppes,medicare_part_b,medicare_part_d",
              help = "Data sources for enrichment [default %default]", metavar = "character"),

  make_option(c("--list-specialties"), action = "store_true", default = FALSE,
              help = "List available specialty configurations"),

  make_option(c("--create-template"), type = "character", default = NULL,
              help = "Create provider list template for specialty", metavar = "character")
)

# Parse command line arguments
opt_parser <- OptionParser(option_list = option_list)
args <- parse_args(opt_parser)

# Handle special commands
if (args$list_specialties) {
  cat("Available specialty configurations:\n")
  specialties <- get_available_specialties()
  for (specialty in specialties) {
    cat(sprintf("  - %s\n", specialty))
  }
  quit(status = 0)
}

if (!is.null(args$create_template)) {
  template_file <- paste0(args$create_template, "_template.csv")
  success <- create_provider_list_template(template_file, args$create_template)
  if (success) {
    cat(sprintf("Template created: %s\n", template_file))
  }
  quit(status = 0)
}

# Validate required arguments
if (is.null(args$specialty) || is.null(args$provider_list)) {
  print_help(opt_parser)
  stop("Both --specialty and --provider-list are required", call. = FALSE)
}

# Validate file exists
if (!file.exists(args$provider_list)) {
  stop(sprintf("Provider list file not found: %s", args$provider_list), call. = FALSE)
}

# Parse data sources
args$data_sources <- trimws(unlist(strsplit(args$data_sources, ",")))

# Run the analysis pipeline
tryCatch({
  results <- run_specialty_analysis_pipeline(args)
  cat("\n✅ Analysis pipeline completed successfully!\n")
}, error = function(e) {
  cat(sprintf("\n❌ Pipeline failed: %s\n", e$message))
  quit(status = 1)
})

cat("Multi-specialty analysis pipeline complete.\n")
cat("\nUsage examples:\n")
cat("# Colorado radiation oncologists:\n")
cat("Rscript run_specialty_analysis.R \\\n")
cat("  --specialty radiation_oncology \\\n")
cat("  --provider-list data/colorado_radiation_oncologists.csv \\\n")
cat("  --geography 'state:CO'\n")
cat("\n# Multiple state analysis:\n")
cat("Rscript run_specialty_analysis.R \\\n")
cat("  --specialty cardiology \\\n")
cat("  --provider-list data/southwest_cardiologists.csv \\\n")
cat("  --geography 'state:CO,NM,AZ,UT'\n")
