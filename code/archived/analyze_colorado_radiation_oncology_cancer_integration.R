#!/usr/bin/env Rscript
# Real-World Analysis: Colorado Radiation Oncology + Cancer Burden Integration
# ==========================================================================
# Integrates actual Colorado radiation oncologist locations with cervical cancer incidence data

library(dplyr)
library(readr)
library(stringr)

# Source required functions
source("R/cancer_data_integration.R")

cat("🏥 REAL COLORADO RADIATION ONCOLOGY + CANCER BURDEN ANALYSIS\n")
cat("===========================================================\n")

#' Step 1: Load and process real radiation oncologist data
cat("\n👩‍⚕️ STEP 1: Processing real Colorado radiation oncologist data\n")

rad_onc_data <- readr::read_csv("data/colorado_radiation_oncologists_real.csv",
                               show_col_types = FALSE)

cat(sprintf("✅ Loaded %d radiation oncologists in Colorado\n", nrow(rad_onc_data)))

# Extract primary locations and standardize addresses
process_provider_addresses <- function(data) {

  # Extract city and county from primary address
  data$primary_city <- NA_character_
  data$primary_county <- NA_character_

  # Parse primary addresses to extract cities
  for (i in 1:nrow(data)) {
    addr <- data$address_1[i]
    if (!is.na(addr)) {
      # Look for common Colorado city patterns
      cities <- c("LAKEWOOD", "LONGMONT", "LOVELAND", "GRAND JUNCTION", "DENVER",
                 "COLORADO SPRINGS", "PUEBLO", "DURANGO", "LAFAYETTE", "FORT COLLINS",
                 "GLENWOOD SPRINGS", "BOULDER", "AURORA", "LONE TREE", "HIGHLANDS RANCH",
                 "THORNTON", "EDWARDS", "GOLDEN", "GREELEY")

      for (city in cities) {
        if (grepl(city, addr, ignore.case = TRUE)) {
          data$primary_city[i] <- str_to_title(gsub("\\s+", " ", city))
          break
        }
      }

      # Extract state and zip for validation
      if (grepl("CO\\s+\\d{5}", addr)) {
        data$primary_state <- "CO"
      }
    }
  }

  # Map cities to counties (approximate mapping)
  city_to_county <- list(
    "Lakewood" = "Jefferson",
    "Longmont" = "Boulder",
    "Loveland" = "Larimer",
    "Grand Junction" = "Mesa",
    "Denver" = "Denver",
    "Colorado Springs" = "El Paso",
    "Pueblo" = "Pueblo",
    "Durango" = "La Plata",
    "Lafayette" = "Boulder",
    "Fort Collins" = "Larimer",
    "Glenwood Springs" = "Garfield",
    "Boulder" = "Boulder",
    "Aurora" = "Arapahoe",
    "Lone Tree" = "Douglas",
    "Highlands Ranch" = "Douglas",
    "Thornton" = "Adams",
    "Edwards" = "Eagle",
    "Golden" = "Jefferson",
    "Greeley" = "Weld"
  )

  for (i in 1:nrow(data)) {
    city <- data$primary_city[i]
    if (!is.na(city) && city %in% names(city_to_county)) {
      data$primary_county[i] <- city_to_county[[city]]
    }
  }

  return(data)
}

# Process the provider data
processed_providers <- process_provider_addresses(rad_onc_data)

# Show distribution by county
county_dist <- table(processed_providers$primary_county, useNA = "always")
cat("\n📊 Radiation oncologists by county:\n")
for (county in names(county_dist)) {
  if (!is.na(county)) {
    cat(sprintf("   • %s County: %d providers\n", county, county_dist[[county]]))
  }
}

# Count providers with multiple locations
multi_location <- sum(!is.na(processed_providers$address_2))
cat(sprintf("\n🏢 Providers with multiple locations: %d (%.1f%%)\n",
           multi_location, multi_location/nrow(processed_providers)*100))

#' Step 2: Load processed cancer data
cat("\n📊 STEP 2: Loading Colorado cervical cancer incidence data\n")

cancer_data <- readr::read_csv("data/processed/colorado_cervical_cancer_by_county.csv",
                              show_col_types = FALSE)

cat(sprintf("✅ Loaded cancer data for %d Colorado counties\n", nrow(cancer_data)))

# Show cancer burden by county
cancer_by_county <- cancer_data %>%
  filter(!is.na(incidence_rate), !county %in% c("Colorado")) %>%
  select(county, incidence_rate, average_annual_count, overall_cancer_burden) %>%
  arrange(desc(incidence_rate))

cat("\n📈 Top 10 counties by cervical cancer incidence:\n")
top_cancer <- head(cancer_by_county, 10)
for (i in 1:nrow(top_cancer)) {
  cat(sprintf("   %2d. %-15s: %.1f per 100,000 (%2.0f cases/year, %s)\n",
             i,
             gsub(" County", "", top_cancer$county[i]),
             top_cancer$incidence_rate[i],
             top_cancer$average_annual_count[i],
             top_cancer$overall_cancer_burden[i]))
}

#' Step 3: Create geographic workforce summary
cat("\n🗺️ STEP 3: Creating geographic workforce analysis\n")

# Count providers by county
provider_by_county <- processed_providers %>%
  filter(!is.na(primary_county)) %>%
  group_by(primary_county) %>%
  summarise(
    total_providers = n(),
    health_systems = paste(unique(hospital_affiliation), collapse = "; "),
    .groups = "drop"
  )

# Get all Colorado counties from cancer data for complete analysis
all_counties <- cancer_data %>%
  filter(!county %in% c("Colorado"), !is.na(fips)) %>%
  select(county, fips) %>%
  mutate(county_name = gsub(" County", "", county))

# Create complete geographic summary
geographic_summary <- all_counties %>%
  left_join(provider_by_county, by = c("county_name" = "primary_county")) %>%
  mutate(
    total_providers = ifelse(is.na(total_providers), 0, total_providers),
    geographic_unit = county,
    geographic_unit_name = paste0(county, ", CO")
  ) %>%
  select(geographic_unit, geographic_unit_name, fips, total_providers, health_systems)

cat(sprintf("✅ Created geographic analysis for %d Colorado counties\n", nrow(geographic_summary)))
cat(sprintf("   • Counties with radiation oncologists: %d\n",
           sum(geographic_summary$total_providers > 0)))
cat(sprintf("   • Counties without radiation oncologists: %d\n",
           sum(geographic_summary$total_providers == 0)))
cat(sprintf("   • Total radiation oncologists: %d\n",
           sum(geographic_summary$total_providers)))

#' Step 4: Integrate with cancer burden data
cat("\n🔗 STEP 4: Integrating radiation oncology workforce with cancer burden\n")

geographic_results <- list(
  geographic_summary = geographic_summary,
  analysis_metadata = list(
    specialty = "Radiation Oncology",
    analysis_date = Sys.Date(),
    data_source = "Real Colorado provider data"
  )
)

integrated_results <- integrate_cancer_data_with_workforce(
  geographic_results = geographic_results,
  cancer_data = cancer_data,
  join_method = "fips"
)

#' Step 5: Analyze coverage gaps and priorities
cat("\n🎯 STEP 5: Analyzing coverage gaps and priority areas\n")

# Create detailed analysis of cancer burden vs provider availability
coverage_analysis <- integrated_results$geographic_summary %>%
  filter(!is.na(incidence_rate)) %>%
  mutate(
    coverage_status = case_when(
      total_providers == 0 & overall_cancer_burden == "High Burden" ~ "Critical Gap",
      total_providers == 0 & overall_cancer_burden == "Moderate Burden" ~ "Significant Gap",
      total_providers == 0 & overall_cancer_burden == "Low Burden" ~ "Moderate Gap",
      total_providers > 0 & overall_cancer_burden == "High Burden" ~ "High Burden Covered",
      total_providers > 0 ~ "Covered",
      TRUE ~ "Unknown"
    ),
    patients_per_provider = ifelse(total_providers > 0,
                                  average_annual_count / total_providers,
                                  Inf)
  ) %>%
  arrange(desc(incidence_rate))

# Show coverage gap analysis
gap_summary <- table(coverage_analysis$coverage_status)
cat("\n📊 Cancer coverage gap analysis:\n")
for (status in names(gap_summary)) {
  cat(sprintf("   • %-20s: %d counties\n", status, gap_summary[[status]]))
}

cat("\n🚨 CRITICAL COVERAGE GAPS (High cancer burden, no radiation oncologists):\n")
critical_gaps <- coverage_analysis %>%
  filter(coverage_status == "Critical Gap") %>%
  select(county, incidence_rate, average_annual_count, total_providers)

if (nrow(critical_gaps) > 0) {
  for (i in 1:nrow(critical_gaps)) {
    cat(sprintf("   %d. %s\n", i, gsub(" County", "", critical_gaps$county[i])))
    cat(sprintf("      • Incidence: %.1f per 100,000\n", critical_gaps$incidence_rate[i]))
    cat(sprintf("      • Annual cases: %.0f\n", critical_gaps$average_annual_count[i]))
    cat(sprintf("      • Radiation oncologists: %d\n", critical_gaps$total_providers[i]))
  }
} else {
  cat("   ✅ No critical gaps identified - all high-burden counties have providers\n")
}

cat("\n⚠️  SIGNIFICANT COVERAGE GAPS (Moderate cancer burden, no radiation oncologists):\n")
significant_gaps <- coverage_analysis %>%
  filter(coverage_status == "Significant Gap") %>%
  select(county, incidence_rate, average_annual_count, total_providers)

if (nrow(significant_gaps) > 0) {
  for (i in 1:nrow(significant_gaps)) {
    cat(sprintf("   %d. %s\n", i, gsub(" County", "", significant_gaps$county[i])))
    cat(sprintf("      • Incidence: %.1f per 100,000\n", significant_gaps$incidence_rate[i]))
    cat(sprintf("      • Annual cases: %.0f\n", significant_gaps$average_annual_count[i]))
  }
} else {
  cat("   ✅ No significant gaps identified\n")
}

#' Step 6: Analyze provider density and workload
cat("\n📊 STEP 6: Provider density and workload analysis\n")

workload_analysis <- coverage_analysis %>%
  filter(total_providers > 0, !is.infinite(patients_per_provider)) %>%
  arrange(desc(patients_per_provider))

cat("Counties with highest patient load per radiation oncologist:\n")
for (i in 1:min(5, nrow(workload_analysis))) {
  cat(sprintf("   %d. %s\n", i, gsub(" County", "", workload_analysis$county[i])))
  cat(sprintf("      • %.1f cancer cases/year per provider\n",
             workload_analysis$patients_per_provider[i]))
  cat(sprintf("      • %d providers, %.1f incidence rate\n",
             workload_analysis$total_providers[i],
             workload_analysis$incidence_rate[i]))
}

#' Step 7: Health system analysis
cat("\n🏥 STEP 7: Health system coverage analysis\n")

health_system_coverage <- processed_providers %>%
  filter(!is.na(primary_county)) %>%
  group_by(hospital_affiliation) %>%
  summarise(
    providers = n(),
    counties_served = n_distinct(primary_county),
    counties_list = paste(unique(primary_county), collapse = ", "),
    .groups = "drop"
  ) %>%
  arrange(desc(providers))

cat("Major health systems providing radiation oncology in Colorado:\n")
for (i in 1:nrow(health_system_coverage)) {
  cat(sprintf("   %d. %s\n", i, health_system_coverage$hospital_affiliation[i]))
  cat(sprintf("      • %d providers across %d counties\n",
             health_system_coverage$providers[i],
             health_system_coverage$counties_served[i]))
  cat(sprintf("      • Serves: %s\n", health_system_coverage$counties_list[i]))
}

#' Step 8: Export comprehensive results
cat("\n💾 STEP 8: Exporting comprehensive analysis\n")

# Save detailed results
output_dir <- "results/colorado_radiation_oncology_cancer_analysis"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Provider analysis
readr::write_csv(processed_providers,
                file.path(output_dir, "colorado_radiation_oncologists_processed.csv"))

# Coverage analysis
readr::write_csv(coverage_analysis,
                file.path(output_dir, "cancer_coverage_analysis.csv"))

# Health system analysis
readr::write_csv(health_system_coverage,
                file.path(output_dir, "health_system_coverage.csv"))

# Integrated geographic results
readr::write_csv(integrated_results$geographic_summary,
                file.path(output_dir, "geographic_summary_with_cancer_data.csv"))

# Summary statistics
summary_stats <- list(
  analysis_date = as.character(Sys.Date()),
  total_counties_analyzed = nrow(coverage_analysis),
  total_radiation_oncologists = sum(geographic_summary$total_providers),
  counties_with_providers = sum(geographic_summary$total_providers > 0),
  counties_without_providers = sum(geographic_summary$total_providers == 0),
  critical_gaps = nrow(filter(coverage_analysis, coverage_status == "Critical Gap")),
  significant_gaps = nrow(filter(coverage_analysis, coverage_status == "Significant Gap")),
  health_systems = nrow(health_system_coverage),
  avg_cancer_incidence = mean(coverage_analysis$incidence_rate, na.rm = TRUE)
)

jsonlite::write_json(summary_stats,
                    file.path(output_dir, "analysis_summary.json"),
                    pretty = TRUE)

cat(sprintf("✅ Analysis exported to: %s\n", output_dir))

#' Step 9: Policy recommendations
cat("\n💡 POLICY RECOMMENDATIONS\n")
cat("========================\n")

cat("🎯 IMMEDIATE PRIORITIES:\n")
if (nrow(critical_gaps) > 0) {
  cat(sprintf("   • Address %d critical coverage gaps in high cancer burden areas\n", nrow(critical_gaps)))
  cat("   • Consider mobile radiation therapy units for remote areas\n")
}
if (nrow(significant_gaps) > 0) {
  cat(sprintf("   • Plan for %d counties with moderate burden but no local providers\n", nrow(significant_gaps)))
}

cat("\n🏥 HEALTH SYSTEM STRATEGIES:\n")
cat(sprintf("   • %d major health systems provide radiation oncology in Colorado\n", nrow(health_system_coverage)))
cat("   • Encourage coordinated coverage across health system networks\n")
cat("   • Support telemedicine consultation capabilities\n")

max_workload <- max(workload_analysis$patients_per_provider, na.rm = TRUE)
if (max_workload > 20) {
  cat(sprintf("\n⚠️  WORKLOAD CONCERNS:\n"))
  cat(sprintf("   • Highest patient load: %.1f cases/year per provider\n", max_workload))
  cat("   • Consider provider recruitment in high-volume areas\n")
}

cat("\n🚀 STRATEGIC RECOMMENDATIONS:\n")
cat("   • Integrate cancer registry data into workforce planning\n")
cat("   • Monitor cancer incidence trends for future provider needs\n")
cat("   • Support professional development and retention programs\n")
cat("   • Evaluate travel burden for patients in underserved areas\n")

cat("\n✅ REAL-WORLD ANALYSIS COMPLETE!\n")
cat("================================\n")
cat("This analysis successfully integrated:\n")
cat(sprintf("   ✅ %d real Colorado radiation oncologists\n", nrow(processed_providers)))
cat(sprintf("   ✅ %d Colorado counties with cancer incidence data\n", nrow(coverage_analysis)))
cat(sprintf("   ✅ %d major health systems\n", nrow(health_system_coverage)))
cat("   ✅ Geographic coverage gap identification\n")
cat("   ✅ Provider workload and density analysis\n")
cat("   ✅ Evidence-based policy recommendations\n")

return(list(
  coverage_analysis = coverage_analysis,
  health_system_coverage = health_system_coverage,
  integrated_results = integrated_results,
  summary_stats = summary_stats
))
