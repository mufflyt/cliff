#!/usr/bin/env Rscript
# Example: Colorado Radiation Oncology Analysis
# =============================================
# Demonstrates the complete multi-specialty pipeline for radiation oncologists in Colorado

# This example shows how to run the analysis for radiation oncologists in Colorado
# using an external provider list (no taxonomy codes required)

cat("🏥 EXAMPLE: Colorado Radiation Oncology Workforce Analysis\n")
cat("=========================================================\n")

# Load required libraries
library(dplyr)

# Source the main pipeline functions
source("R/specialty_config_loader.R")
source("R/external_provider_loader.R")
source("R/specialty_data_enrichment.R")

#' Create Example Colorado Radiation Oncologist Provider List
#' This demonstrates the format needed for external provider lists
create_example_colorado_rad_onc_list <- function() {

  cat("📋 Creating example Colorado radiation oncologist provider list\n")

  # Example provider data (in real usage, this would be from an authoritative source)
  example_providers <- data.frame(
    npi = c("1234567890", "0987654321", "1122334455", "2233445566", "3344556677"),
    first_name = c("John", "Sarah", "Michael", "Lisa", "David"),
    last_name = c("Smith", "Johnson", "Williams", "Brown", "Davis"),
    middle_name = c("A", "", "R", "M", ""),
    address = c("1635 Aurora Ct", "1721 E 19th Ave", "2045 Franklin St", "4200 E 9th Ave", "1400 Jackson St"),
    address_2 = c("Suite 7300", "", "Unit 200", "Building A", "Floor 3"),
    city = c("Aurora", "Denver", "Denver", "Denver", "Denver"),
    state = c("CO", "CO", "CO", "CO", "CO"),
    zip = c("80045", "80218", "80205", "80262", "80206"),
    phone = c("303-724-0000", "303-861-2266", "303-320-2700", "303-270-2522", "303-398-1355"),
    specialty = rep("Radiation Oncology", 5),
    credentials = c("MD", "MD, PhD", "MD", "MD, MS", "MD"),
    stringsAsFactors = FALSE
  )

  # Save example file
  output_file <- "data/example_colorado_radiation_oncologists.csv"
  dir.create("data", showWarnings = FALSE)

  readr::write_csv(example_providers, output_file)

  cat(sprintf("✅ Example provider list created: %s\n", output_file))
  cat("📊 Example contains:\n")
  cat(sprintf("  - %d radiation oncologists\n", nrow(example_providers)))
  cat(sprintf("  - All located in Colorado\n"))
  cat(sprintf("  - Mix of Denver metro and Aurora locations\n"))

  return(output_file)
}

#' Demonstrate Complete Analysis Pipeline
run_complete_example <- function() {

  cat("\n🚀 Running complete Colorado radiation oncology analysis\n")

  # Step 1: Create example provider list
  provider_list_file <- create_example_colorado_rad_onc_list()

  # Step 2: Load specialty configuration
  cat("\n📋 Loading radiation oncology specialty configuration\n")
  specialty_config <- load_specialty_config("radiation_oncology")

  cat(sprintf("✅ Loaded configuration for: %s\n",
             specialty_config$specialty_info$specialty_name))

  # Step 3: Run complete data enrichment
  cat("\n📈 Running comprehensive data enrichment pipeline\n")

  # Set geographic filter for Colorado
  colorado_filter <- list(state = "CO")

  enrichment_results <- enrich_specialty_provider_data(
    provider_list_file = provider_list_file,
    specialty_name = "radiation_oncology",
    geographic_filter = colorado_filter,
    enrichment_sources = c("nppes", "medicare_part_b"),
    validation_level = "moderate"
  )

  # Step 4: Show results summary
  cat("\n📊 ANALYSIS RESULTS SUMMARY\n")
  cat("===========================\n")

  summary <- enrichment_results$enrichment_summary

  cat(sprintf("Specialty: %s\n", summary$input_summary$specialty))
  cat(sprintf("Geographic Scope: %s\n", summary$input_summary$geographic_scope))
  cat(sprintf("Input Providers: %d\n", summary$input_summary$original_provider_count))
  cat(sprintf("Final Providers: %d\n", summary$output_summary$final_provider_count))
  cat(sprintf("Analysis-Ready: %d (%.1f%%)\n",
             summary$output_summary$analysis_ready_count,
             summary$success_rates$analysis_readiness_rate * 100))
  cat(sprintf("High Quality: %d (%.1f%%)\n",
             summary$output_summary$high_quality_count,
             summary$success_rates$high_quality_rate * 100))
  cat(sprintf("Average Estimated Age: %.1f years\n",
             summary$specialty_specific_metrics$estimated_avg_age))

  # Step 5: Save example results
  output_dir <- "results/example_colorado_radiation_oncology"
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  readr::write_csv(enrichment_results$enriched_providers,
                  file.path(output_dir, "enriched_providers.csv"))

  jsonlite::write_json(summary,
                      file.path(output_dir, "analysis_summary.json"),
                      pretty = TRUE)

  cat(sprintf("\n✅ Example results saved to: %s\n", output_dir))

  return(enrichment_results)
}

#' Show Command Line Usage Examples
show_usage_examples <- function() {

  cat("\n💻 COMMAND LINE USAGE EXAMPLES\n")
  cat("==============================\n")

  cat("1. Run Colorado radiation oncology analysis:\n")
  cat("   Rscript run_specialty_analysis.R \\\n")
  cat("     --specialty radiation_oncology \\\n")
  cat("     --provider-list data/colorado_radiation_oncologists.csv \\\n")
  cat("     --geography 'state:CO' \\\n")
  cat("     --output-dir results/colorado_rad_onc\n\n")

  cat("2. Run multi-state cardiology analysis:\n")
  cat("   Rscript run_specialty_analysis.R \\\n")
  cat("     --specialty cardiology \\\n")
  cat("     --provider-list data/southwest_cardiologists.csv \\\n")
  cat("     --geography 'state:CO,NM,AZ,UT' \\\n")
  cat("     --retirement-model monte_carlo\n\n")

  cat("3. Run city-specific analysis:\n")
  cat("   Rscript run_specialty_analysis.R \\\n")
  cat("     --specialty internal_medicine \\\n")
  cat("     --provider-list data/denver_internists.csv \\\n")
  cat("     --geography 'city:Denver,Aurora,Lakewood' \\\n")
  cat("     --geographic-level county\n\n")

  cat("4. List available specialties:\n")
  cat("   Rscript run_specialty_analysis.R --list-specialties\n\n")

  cat("5. Create provider list template:\n")
  cat("   Rscript run_specialty_analysis.R --create-template neurology\n\n")
}

#' Show Key Benefits of This Approach
show_key_benefits <- function() {

  cat("\n🎯 KEY BENEFITS OF THIS APPROACH\n")
  cat("================================\n")

  cat("✅ NO TAXONOMY DEPENDENCY:\n")
  cat("   - Uses authoritative specialty-specific provider lists\n")
  cat("   - Eliminates taxonomy code mapping errors\n")
  cat("   - Works with any provider database format\n\n")

  cat("✅ GEOGRAPHIC PRECISION:\n")
  cat("   - State/county/city-specific analysis\n")
  cat("   - Address-based provider identification\n")
  cat("   - Travel distance and access modeling\n\n")

  cat("✅ SPECIALTY-SPECIFIC MODELING:\n")
  cat("   - Configurable retirement parameters per specialty\n")
  cat("   - Practice pattern-specific analysis\n")
  cat("   - Specialty-specific risk factors\n\n")

  cat("✅ FLEXIBLE DATA SOURCES:\n")
  cat("   - Works with any provider list format (CSV, Excel, etc.)\n")
  cat("   - Adapts to different data quality levels\n")
  cat("   - Enriches with NPPES and Medicare data when available\n\n")

  cat("✅ COMPREHENSIVE OUTPUT:\n")
  cat("   - Provider-level retirement projections\n")
  cat("   - Geographic workforce analysis\n")
  cat("   - Underserved area identification\n")
  cat("   - Policy recommendations\n\n")
}

# Main execution
if (!interactive()) {

  cat("🏥 COLORADO RADIATION ONCOLOGY ANALYSIS EXAMPLE\n")
  cat("===============================================\n")

  # Run the complete example
  tryCatch({

    # Check if we're in the right directory
    if (!file.exists("R/specialty_config_loader.R")) {
      cat("❌ Please run this script from the comprehensive_forecasting directory\n")
      quit(status = 1)
    }

    # Run example analysis
    results <- run_complete_example()

    # Show usage examples
    show_usage_examples()

    # Show key benefits
    show_key_benefits()

    cat("\n🎉 EXAMPLE COMPLETE!\n")
    cat("===================\n")
    cat("The pipeline has successfully demonstrated:\n")
    cat("✅ External provider list ingestion (no taxonomy codes)\n")
    cat("✅ NPPES validation and enrichment\n")
    cat("✅ Specialty-specific retirement modeling\n")
    cat("✅ Geographic workforce analysis\n")
    cat("✅ Comprehensive results export\n")
    cat("\nTo run with real data, replace the example CSV with your actual provider list.\n")

  }, error = function(e) {
    cat(sprintf("❌ Example failed: %s\n", e$message))
    cat("Please ensure all required R packages are installed.\n")
    quit(status = 1)
  })
}

cat("\nColorado radiation oncology example ready to run.\n")
