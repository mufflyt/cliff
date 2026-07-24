#!/usr/bin/env Rscript
# Process Colorado GYN Cancer Data for Workforce Analysis Integration
# ===================================================================
# Demonstrates integration of cancer incidence data with provider workforce analysis

library(dplyr)
library(readxl)

# Source required functions
source("R/cancer_data_integration.R")

#' Process Colorado GYN Cancer Data
#' @param file_path Path to the cancer data Excel file
#' @return Processed and standardized cancer dataset
process_colorado_cancer_data <- function(file_path) {

  cat("🏥 PROCESSING COLORADO GYN CANCER DATA\n")
  cat("=====================================\n")

  # Read the Excel file with proper skip parameter
  cancer_raw <- readxl::read_excel(file_path, skip = 7)

  cat(sprintf("✅ Loaded cancer data: %d counties, %d columns\n",
             nrow(cancer_raw), ncol(cancer_raw)))

  # Clean and standardize the data
  cancer_clean <- cancer_raw %>%
    # Remove state and national summary rows
    filter(!is.na(FIPS), FIPS > 0, FIPS < 9000) %>%

    # Standardize column names
    select(
      county = County,
      fips = FIPS,
      rural_urban_code = `2023 Rural-Urban Continuum Codes([rural urban note])`,
      incidence_rate = `Age-Adjusted Incidence Rate([rate note]) - cases per 100,000`,
      incidence_lower_ci = `Lower 95% Confidence Interval`,
      incidence_upper_ci = `Upper 95% Confidence Interval`,
      rank = `CI*Rank([rank note])`,
      average_annual_count = `Average Annual Count`
    ) %>%

    # Clean county names (remove footnote numbers)
    mutate(
      county = gsub("\\([0-9]+\\)$", "", county),
      county = trimws(county)
    ) %>%

    # Convert data types
    mutate(
      fips = sprintf("%05d", as.numeric(fips)),  # 5-digit FIPS
      incidence_rate = as.numeric(incidence_rate),
      incidence_lower_ci = as.numeric(incidence_lower_ci),
      incidence_upper_ci = as.numeric(incidence_upper_ci),
      average_annual_count = as.numeric(average_annual_count),
      rank = as.numeric(rank)
    ) %>%

    # Add metadata
    mutate(
      state = "CO",
      cancer_type = "Cervical Cancer",
      time_period = "2017-2021",
      data_source = "Colorado Cancer Registry"
    )

  # Calculate burden metrics
  cancer_with_burden <- calculate_cancer_burden_metrics(cancer_clean)

  cat(sprintf("✅ Processed %d Colorado counties with cancer data\n", nrow(cancer_with_burden)))

  # Show summary
  cat("\n📊 CANCER DATA SUMMARY\n")
  cat("=====================\n")
  cat(sprintf("Cancer Type: %s\n", unique(cancer_with_burden$cancer_type)))
  cat(sprintf("Time Period: %s\n", unique(cancer_with_burden$time_period)))
  cat(sprintf("Counties: %d\n", nrow(cancer_with_burden)))
  cat(sprintf("Average Incidence Rate: %.1f per 100,000\n",
             mean(cancer_with_burden$incidence_rate, na.rm = TRUE)))
  cat(sprintf("Range: %.1f - %.1f per 100,000\n",
             min(cancer_with_burden$incidence_rate, na.rm = TRUE),
             max(cancer_with_burden$incidence_rate, na.rm = TRUE)))

  # Show top counties by incidence
  cat("\n🔝 TOP 5 COUNTIES BY CERVICAL CANCER INCIDENCE\n")
  top_counties <- cancer_with_burden %>%
    arrange(desc(incidence_rate)) %>%
    head(5) %>%
    select(county, incidence_rate, average_annual_count, overall_cancer_burden)

  print(top_counties)

  return(cancer_with_burden)
}

#' Demonstrate Cancer Data Integration with Workforce Analysis
#' @param cancer_data Processed cancer data
#' @return Example integration results
demonstrate_cancer_workforce_integration <- function(cancer_data) {

  cat("\n🔗 DEMONSTRATING CANCER-WORKFORCE INTEGRATION\n")
  cat("============================================\n")

  # Create example geographic workforce data (in real usage, this comes from the pipeline)
  cat("📋 Creating example workforce data for demonstration\n")

  example_workforce <- data.frame(
    geographic_unit = paste0(cancer_data$county, ", CO"),
    geographic_unit_name = paste0(cancer_data$county, ", CO"),
    total_providers = c(
      # Major metro areas with more providers
      rep(c(8, 5, 3, 2, 1, 0), length.out = nrow(cancer_data))
    ),
    active_providers = c(
      rep(c(7, 4, 3, 2, 1, 0), length.out = nrow(cancer_data))
    ),
    avg_age = runif(nrow(cancer_data), 45, 65),
    providers_65_plus = c(
      rep(c(1, 1, 0, 0, 0, 0), length.out = nrow(cancer_data))
    ),
    high_retirement_risk_5yr = c(
      rep(c(2, 1, 1, 0, 0, 0), length.out = nrow(cancer_data))
    ),
    expected_retirements_5yr = c(
      rep(c(1.5, 0.8, 0.5, 0.2, 0.1, 0), length.out = nrow(cancer_data))
    )
  )

  # Add FIPS codes to workforce data for joining
  example_workforce$fips <- cancer_data$fips[1:nrow(example_workforce)]

  # Simulate geographic results structure
  example_geographic_results <- list(
    geographic_summary = example_workforce,
    analysis_metadata = list(
      geographic_units = nrow(example_workforce),
      specialty = "Gynecologic Oncology"
    )
  )

  # Integrate cancer data with workforce analysis
  cat("🔄 Integrating cancer burden with provider distribution\n")

  integrated_results <- integrate_cancer_data_with_workforce(
    geographic_results = example_geographic_results,
    cancer_data = cancer_data,
    join_method = "fips"
  )

  # Identify high-priority areas
  priority_areas <- identify_high_priority_cancer_areas(integrated_results)

  cat("\n🎯 HIGH-PRIORITY AREAS IDENTIFIED\n")
  cat("=================================\n")

  if (nrow(priority_areas$critical_priority) > 0) {
    cat("🚨 CRITICAL PRIORITY (High cancer burden + provider shortage):\n")
    critical <- priority_areas$critical_priority %>%
      select(geographic_unit_name, incidence_rate, total_providers, overall_cancer_burden) %>%
      head(5)
    print(critical)
  }

  if (nrow(priority_areas$moderate_priority) > 0) {
    cat("\n⚠️  MODERATE PRIORITY (Moderate cancer burden + no providers):\n")
    moderate <- priority_areas$moderate_priority %>%
      select(geographic_unit_name, incidence_rate, total_providers, overall_cancer_burden) %>%
      head(5)
    print(moderate)
  }

  return(list(
    integrated_results = integrated_results,
    priority_areas = priority_areas
  ))
}

#' Show Integration with Real Pipeline
show_real_pipeline_integration <- function() {

  cat("\n🚀 REAL PIPELINE INTEGRATION EXAMPLE\n")
  cat("===================================\n")

  cat("To integrate this cancer data with your actual pipeline:\n\n")

  cat("1. Run your specialty analysis first:\n")
  cat("   Rscript run_specialty_analysis.R \\\n")
  cat("     --specialty gynecologic_oncology \\\n")
  cat("     --provider-list colorado_gyn_onc.csv \\\n")
  cat("     --geography 'state:CO' \\\n")
  cat("     --output-dir results/colorado_gyn_onc\n\n")

  cat("2. Then integrate cancer data:\n")
  cat("   source('process_colorado_cancer_data.R')\n")
  cat("   cancer_data <- process_colorado_cancer_data('path/to/cancer_file.xlsx')\n")
  cat("   \n")
  cat("   # Load your geographic results\n")
  cat("   geographic_results <- readRDS('results/colorado_gyn_onc/geographic_results.rds')\n")
  cat("   \n")
  cat("   # Integrate\n")
  cat("   integrated <- integrate_cancer_data_with_workforce(\n")
  cat("     geographic_results, cancer_data, 'fips'\n")
  cat("   )\n")
  cat("   \n")
  cat("   # Identify priority areas\n")
  cat("   priorities <- identify_high_priority_cancer_areas(integrated)\n\n")

  cat("3. Export enhanced results:\n")
  cat("   export_cancer_integrated_analysis(\n")
  cat("     integrated, priorities, 'results/cancer_integrated/'\n")
  cat("   )\n\n")

  cat("🎯 KEY INSIGHTS THIS PROVIDES:\n")
  cat("===============================\n")
  cat("✅ Counties with high cancer burden but few/no providers\n")
  cat("✅ Areas where provider retirements will impact cancer care\n")
  cat("✅ Provider-to-cancer-case ratios for resource planning\n")
  cat("✅ Priority rankings for recruitment efforts\n")
  cat("✅ Geographic disparities in cancer care access\n")
}

# Main execution
if (!interactive()) {

  # Process the cancer data
  cancer_file <- "/Users/tmuffly/Downloads/CO GYN cancer incidence and mortality by county-FIPS.xlsx"

  if (file.exists(cancer_file)) {

    # Process cancer data
    cancer_data <- process_colorado_cancer_data(cancer_file)

    # Demonstrate integration
    integration_demo <- demonstrate_cancer_workforce_integration(cancer_data)

    # Show real pipeline integration
    show_real_pipeline_integration()

    # Save processed cancer data for future use
    output_dir <- "data/processed"
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

    readr::write_csv(cancer_data, file.path(output_dir, "colorado_cervical_cancer_by_county.csv"))

    cat(sprintf("\n✅ Processed cancer data saved to: %s\n",
               file.path(output_dir, "colorado_cervical_cancer_by_county.csv")))

  } else {
    cat("❌ Cancer data file not found. Please check the file path.\n")
  }
}

cat("\nColorado cancer data processing ready.\n")
cat("Run: Rscript process_colorado_cancer_data.R\n")