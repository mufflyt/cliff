#!/usr/bin/env Rscript
# Complete Demonstration: Cancer Data + Workforce Analysis Integration
# ===================================================================
# Shows how Colorado cervical cancer incidence data enhances workforce analysis

library(dplyr)
library(readr)

# Source required functions
source("R/cancer_data_integration.R")
source("R/specialty_config_loader.R")
source("R/external_provider_loader.R")
source("R/specialty_data_enrichment.R")

cat("🏥 COMPLETE CANCER-WORKFORCE INTEGRATION DEMONSTRATION\n")
cat("=====================================================\n")

#' Step 1: Load the processed cancer data
cat("\n📊 STEP 1: Loading processed Colorado cervical cancer data\n")
cancer_data <- readr::read_csv("data/processed/colorado_cervical_cancer_by_county.csv",
                              show_col_types = FALSE)

cat(sprintf("✅ Loaded cancer data for %d Colorado counties\n", nrow(cancer_data)))
cat(sprintf("   - Cancer type: %s\n", unique(cancer_data$cancer_type)))
cat(sprintf("   - Time period: %s\n", unique(cancer_data$time_period)))
cat(sprintf("   - Average incidence: %.1f per 100,000\n",
           mean(cancer_data$incidence_rate, na.rm = TRUE)))

# Show highest burden counties
high_burden <- cancer_data %>%
  filter(overall_cancer_burden == "High Burden") %>%
  arrange(desc(incidence_rate))

cat(sprintf("   - High burden counties: %d\n", nrow(high_burden)))
if (nrow(high_burden) > 0) {
  cat("     Top counties by incidence:\n")
  for (i in 1:min(3, nrow(high_burden))) {
    cat(sprintf("     • %s: %.1f per 100,000 (%d annual cases)\n",
               high_burden$county[i],
               high_burden$incidence_rate[i],
               high_burden$average_annual_count[i]))
  }
}

#' Step 2: Create example gynecologic oncology provider data for Colorado
cat("\n👩‍⚕️ STEP 2: Creating example gynecologic oncology provider list\n")

# Create realistic example provider data based on actual Colorado locations
colorado_gyn_onc_providers <- data.frame(
  npi = c("1234567890", "2345678901", "3456789012", "4567890123", "5678901234"),
  first_name = c("Sarah", "Michael", "Jennifer", "David", "Lisa"),
  last_name = c("Johnson", "Williams", "Brown", "Davis", "Miller"),
  middle_name = c("E", "R", "L", "A", "M"),
  address = c(
    "1635 Aurora Ct",           # UCHealth - Aurora
    "1721 E 19th Ave",          # National Jewish Health - Denver
    "4200 E 9th Ave",           # University of Colorado Hospital
    "1400 Jackson St",          # Presbyterian/St. Joseph - Denver
    "2045 Franklin St"          # Rose Medical Center - Denver
  ),
  address_2 = c("Suite 7300", "", "Building A", "Floor 3", "Suite 200"),
  city = c("Aurora", "Denver", "Denver", "Denver", "Denver"),
  state = rep("CO", 5),
  zip = c("80045", "80218", "80262", "80206", "80205"),
  phone = c("303-724-0000", "303-861-2266", "303-270-2522", "303-398-1355", "303-320-2700"),
  specialty = rep("Gynecologic Oncology", 5),
  credentials = c("MD", "MD, PhD", "MD", "MD, MS", "MD"),
  county = c("Arapahoe", "Denver", "Denver", "Denver", "Denver"),
  stringsAsFactors = FALSE
)

# Save example provider list
provider_file <- "data/example_colorado_gyn_onc_providers.csv"
dir.create("data", showWarnings = FALSE)
readr::write_csv(colorado_gyn_onc_providers, provider_file)

cat(sprintf("✅ Created example provider list: %s\n", provider_file))
cat(sprintf("   - %d gynecologic oncologists\n", nrow(colorado_gyn_onc_providers)))
cat(sprintf("   - Located in: %s\n", paste(unique(colorado_gyn_onc_providers$county), collapse = ", ")))

#' Step 3: Simulate geographic workforce analysis results
cat("\n🗺️ STEP 3: Creating geographic workforce analysis results\n")

# Create realistic geographic summary that matches Colorado counties
# Focus on counties that appear in both cancer data and provider locations
colorado_counties <- c(
  "Adams", "Arapahoe", "Boulder", "Denver", "El Paso", "Jefferson",
  "Larimer", "Mesa", "Pueblo", "Weld"
)

geographic_summary <- data.frame(
  geographic_unit = paste0(colorado_counties, " County"),
  geographic_unit_name = paste0(colorado_counties, " County, CO"),
  fips = c("08001", "08005", "08013", "08031", "08041",
          "08059", "08069", "08077", "08101", "08123"),
  total_providers = c(1, 2, 1, 2, 1, 1, 0, 0, 0, 1),
  active_providers = c(1, 2, 1, 2, 1, 1, 0, 0, 0, 1),
  avg_age = c(52, 48, 55, 50, 58, 53, NA, NA, NA, 46),
  providers_65_plus = c(0, 0, 1, 0, 1, 0, 0, 0, 0, 0),
  high_retirement_risk_5yr = c(0, 0, 1, 0, 2, 1, 0, 0, 0, 0),
  expected_retirements_5yr = c(0, 0, 0.8, 0, 1.5, 0.5, 0, 0, 0, 0),
  stringsAsFactors = FALSE
)

# Create mock geographic results structure
geographic_results <- list(
  geographic_summary = geographic_summary,
  analysis_metadata = list(
    geographic_units = nrow(geographic_summary),
    specialty = "Gynecologic Oncology",
    analysis_date = Sys.Date(),
    total_providers_analyzed = sum(geographic_summary$total_providers)
  )
)

cat(sprintf("✅ Created geographic analysis for %d Colorado counties\n",
           nrow(geographic_summary)))
cat(sprintf("   - Total providers: %d\n",
           sum(geographic_summary$total_providers)))
cat(sprintf("   - Counties with providers: %d\n",
           sum(geographic_summary$total_providers > 0)))
cat(sprintf("   - Counties without providers: %d\n",
           sum(geographic_summary$total_providers == 0)))

#' Step 4: Integrate cancer data with workforce analysis
cat("\n🔗 STEP 4: Integrating cancer burden with provider distribution\n")

integrated_results <- integrate_cancer_data_with_workforce(
  geographic_results = geographic_results,
  cancer_data = cancer_data,
  join_method = "fips"
)

cat("\n📊 Integration Results Summary:\n")
integration_summary <- integrated_results$cancer_integration
cat(sprintf("   - Join method: %s\n", integration_summary$join_method))
cat(sprintf("   - Areas matched: %d/%d (%.1f%%)\n",
           integration_summary$matched_areas,
           integration_summary$total_areas,
           integration_summary$match_rate * 100))

#' Step 5: Identify high-priority areas
cat("\n🎯 STEP 5: Identifying high-priority areas for intervention\n")

priority_areas <- identify_high_priority_cancer_areas(integrated_results)

# Show detailed priority area analysis
cat("\n🚨 CRITICAL PRIORITY AREAS (High cancer burden + provider shortage):\n")
if (nrow(priority_areas$critical_priority) > 0) {
  critical_areas <- priority_areas$critical_priority %>%
    select(geographic_unit_name, incidence_rate, total_providers,
           average_annual_count, overall_cancer_burden) %>%
    arrange(desc(incidence_rate))

  for (i in 1:nrow(critical_areas)) {
    cat(sprintf("   %d. %s\n", i, critical_areas$geographic_unit_name[i]))
    cat(sprintf("      • Cancer incidence: %.1f per 100,000\n", critical_areas$incidence_rate[i]))
    cat(sprintf("      • Annual cases: %.0f\n", critical_areas$average_annual_count[i]))
    cat(sprintf("      • Current providers: %d\n", critical_areas$total_providers[i]))
    cat(sprintf("      • Burden level: %s\n", critical_areas$overall_cancer_burden[i]))
  }
} else {
  cat("   None identified in this analysis\n")
}

cat("\n⚠️  MODERATE PRIORITY AREAS (Moderate cancer burden + no providers):\n")
if (nrow(priority_areas$moderate_priority) > 0) {
  moderate_areas <- priority_areas$moderate_priority %>%
    select(geographic_unit_name, incidence_rate, total_providers,
           average_annual_count, overall_cancer_burden) %>%
    arrange(desc(incidence_rate))

  for (i in 1:nrow(moderate_areas)) {
    cat(sprintf("   %d. %s\n", i, moderate_areas$geographic_unit_name[i]))
    cat(sprintf("      • Cancer incidence: %.1f per 100,000\n", moderate_areas$incidence_rate[i]))
    cat(sprintf("      • Annual cases: %.0f\n", moderate_areas$average_annual_count[i]))
    cat(sprintf("      • Current providers: %d\n", moderate_areas$total_providers[i]))
  }
} else {
  cat("   None identified in this analysis\n")
}

cat("\n⏰ RETIREMENT RISK AREAS (Cancer burden + provider retirement risk):\n")
if (nrow(priority_areas$retirement_risk_priority) > 0) {
  retirement_areas <- priority_areas$retirement_risk_priority %>%
    select(geographic_unit_name, incidence_rate, total_providers,
           expected_retirements_5yr, overall_cancer_burden) %>%
    arrange(desc(expected_retirements_5yr))

  for (i in 1:nrow(retirement_areas)) {
    cat(sprintf("   %d. %s\n", i, retirement_areas$geographic_unit_name[i]))
    cat(sprintf("      • Cancer incidence: %.1f per 100,000\n", retirement_areas$incidence_rate[i]))
    cat(sprintf("      • Current providers: %d\n", retirement_areas$total_providers[i]))
    cat(sprintf("      • Expected retirements (5yr): %.1f\n", retirement_areas$expected_retirements_5yr[i]))
    cat(sprintf("      • Burden level: %s\n", retirement_areas$overall_cancer_burden[i]))
  }
} else {
  cat("   None identified in this analysis\n")
}

#' Step 6: Export comprehensive results
cat("\n💾 STEP 6: Exporting integrated analysis results\n")

output_dir <- "results/colorado_cancer_workforce_integration"
export_success <- export_cancer_integrated_analysis(
  enhanced_results = integrated_results,
  priority_areas = priority_areas,
  output_dir = output_dir
)

if (export_success) {
  cat(sprintf("✅ Complete analysis exported to: %s\n", output_dir))

  # List exported files
  exported_files <- list.files(output_dir, full.names = FALSE)
  cat("   Files created:\n")
  for (file in exported_files) {
    cat(sprintf("   • %s\n", file))
  }
}

#' Step 7: Show key insights and recommendations
cat("\n💡 KEY INSIGHTS FROM CANCER-WORKFORCE INTEGRATION\n")
cat("================================================\n")

# Calculate key metrics
total_counties_analyzed <- nrow(integrated_results$geographic_summary)
counties_with_cancer_data <- sum(!is.na(integrated_results$geographic_summary$incidence_rate))
counties_without_providers <- sum(integrated_results$geographic_summary$total_providers == 0, na.rm = TRUE)
high_burden_counties <- sum(integrated_results$geographic_summary$overall_cancer_burden == "High Burden", na.rm = TRUE)

cat(sprintf("📊 COVERAGE ANALYSIS:\n"))
cat(sprintf("   • Total counties analyzed: %d\n", total_counties_analyzed))
cat(sprintf("   • Counties with cancer data: %d\n", counties_with_cancer_data))
cat(sprintf("   • Counties without providers: %d\n", counties_without_providers))
cat(sprintf("   • High cancer burden counties: %d\n", high_burden_counties))

cat(sprintf("\n🎯 PRIORITY RECOMMENDATIONS:\n"))
cat(sprintf("   • Critical shortage areas: %d\n", priority_areas$summary$total_critical))
cat(sprintf("   • Moderate priority areas: %d\n", priority_areas$summary$total_moderate))
cat(sprintf("   • Retirement risk areas: %d\n", priority_areas$summary$total_retirement_risk))

cat("\n🚀 POLICY IMPLICATIONS:\n")
cat("   • Focus recruitment efforts on high-burden, no-provider counties\n")
cat("   • Plan succession for areas with retirement-risk providers\n")
cat("   • Consider telemedicine for isolated high-burden areas\n")
cat("   • Monitor cancer trends in underserved regions\n")

cat("\n✅ DEMONSTRATION COMPLETE!\n")
cat("=========================\n")
cat("This integration successfully demonstrates:\n")
cat("   ✅ Cancer incidence data processing and standardization\n")
cat("   ✅ Workforce distribution analysis\n")
cat("   ✅ Geographic matching using FIPS codes\n")
cat("   ✅ Priority area identification based on burden + shortage\n")
cat("   ✅ Retirement risk assessment in cancer care areas\n")
cat("   ✅ Comprehensive results export for decision-making\n")

cat(sprintf("\nTo run with real workforce data, replace the example provider list\n"))
cat(sprintf("with actual gynecologic oncology providers and run:\n"))
cat(sprintf("Rscript run_specialty_analysis.R --specialty gynecologic_oncology \\\\\n"))
cat(sprintf("  --provider-list real_providers.csv --geography 'state:CO'\n"))
