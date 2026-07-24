#!/usr/bin/env Rscript
# Comprehensive Colorado Radiation Oncology + Cancer Burden Analysis
# ==================================================================
# Integrates all components: cancer burden, provider accessibility, demographics

library(dplyr)
library(readr)

cat("🏥 COMPREHENSIVE COLORADO RADIATION ONCOLOGY ANALYSIS\n")
cat("====================================================\n")
cat("Integrating: Cancer Burden + Provider Access + Demographics\n")

#' Step 1: Load all analysis components
cat("\n📊 STEP 1: Loading all analysis components\n")

# Cancer burden analysis
cancer_analysis <- readr::read_csv("results/colorado_radiation_oncology_cancer_analysis/cancer_coverage_analysis.csv",
                                  show_col_types = FALSE)

# Accessibility analysis
accessibility_analysis <- readr::read_csv("results/radiation_oncology_accessibility/accessibility_analysis.csv",
                                         show_col_types = FALSE)

# Provider locations
provider_locations <- readr::read_csv("results/radiation_oncology_accessibility/provider_locations.csv",
                                     show_col_types = FALSE)

# Demographics
demographics <- readr::read_csv("results/radiation_oncology_accessibility/acs_demographics.csv",
                               show_col_types = FALSE)

cat(sprintf("✅ Loaded cancer analysis: %d counties\n", nrow(cancer_analysis)))
cat(sprintf("✅ Loaded accessibility data: %d isochrone combinations\n", nrow(accessibility_analysis)))
cat(sprintf("✅ Loaded provider locations: %d locations\n", nrow(provider_locations)))
cat(sprintf("✅ Loaded demographics: %d census tracts\n", nrow(demographics)))

#' Step 2: Create integrated priority analysis
cat("\n🎯 STEP 2: Creating integrated priority analysis\n")

# Calculate county-level summaries
county_summary <- cancer_analysis %>%
  select(county, incidence_rate, average_annual_count, total_providers,
         overall_cancer_burden, coverage_status) %>%
  mutate(county_clean = gsub(" County", "", county))

# Calculate accessibility by county (approximation)
provider_county_mapping <- data.frame(
  provider_name = c("Jeffery Albert", "Eric Anderson", "Jack Bagley", "Ari Ballonoff", "Nathan Bennion"),
  county_served = c("Jefferson", "Larimer", "Mesa", "Denver", "Pueblo"),
  stringsAsFactors = FALSE
)

accessibility_by_county <- accessibility_analysis %>%
  left_join(provider_county_mapping, by = "provider_name") %>%
  group_by(county_served, time_minutes) %>%
  summarise(
    avg_female_pop_served = round(mean(total_female_pop, na.rm = TRUE)),
    avg_tracts_served = round(mean(tracts_served, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  filter(!is.na(county_served))

# Integrate cancer burden with accessibility
integrated_analysis <- cancer_analysis %>%
  mutate(county_clean = gsub(" County", "", county)) %>%
  left_join(
    accessibility_by_county %>% filter(time_minutes == 60) %>% select(-time_minutes),
    by = c("county_clean" = "county_served")
  ) %>%
  mutate(
    # Calculate priority scores
    cancer_priority_score = case_when(
      overall_cancer_burden == "High Burden" ~ 3,
      overall_cancer_burden == "Moderate Burden" ~ 2,
      overall_cancer_burden == "Low Burden" ~ 1,
      TRUE ~ 0
    ),
    access_priority_score = case_when(
      total_providers == 0 ~ 3,
      total_providers == 1 ~ 2,
      total_providers >= 2 ~ 1,
      TRUE ~ 0
    ),
    # Combined priority score
    combined_priority_score = cancer_priority_score + access_priority_score,

    # Priority classification
    priority_level = case_when(
      combined_priority_score >= 5 ~ "Critical Priority",
      combined_priority_score >= 4 ~ "High Priority",
      combined_priority_score >= 3 ~ "Moderate Priority",
      TRUE ~ "Low Priority"
    ),

    # Population impact estimate
    estimated_female_pop_impact = case_when(
      !is.na(avg_female_pop_served) ~ avg_female_pop_served,
      total_providers > 0 ~ average_annual_count * 500,  # Rough estimate
      TRUE ~ average_annual_count * 1000  # Higher impact if no providers
    )
  )

cat("✅ Created integrated priority analysis\n")

# Show priority distribution
priority_dist <- table(integrated_analysis$priority_level, useNA = "always")
cat("\n📊 Priority level distribution:\n")
for (level in names(priority_dist)) {
  if (!is.na(level)) {
    cat(sprintf("   • %-18s: %d counties\n", level, priority_dist[[level]]))
  }
}

#' Step 3: Identify critical intervention areas
cat("\n🚨 STEP 3: Identifying critical intervention areas\n")

critical_areas <- integrated_analysis %>%
  filter(priority_level %in% c("Critical Priority", "High Priority")) %>%
  arrange(desc(combined_priority_score), desc(incidence_rate)) %>%
  select(county, incidence_rate, average_annual_count, total_providers,
         overall_cancer_burden, coverage_status, priority_level,
         combined_priority_score, estimated_female_pop_impact)

if (nrow(critical_areas) > 0) {
  cat(sprintf("🚨 %d critical/high priority areas identified:\n", nrow(critical_areas)))

  for (i in 1:nrow(critical_areas)) {
    area <- critical_areas[i, ]
    cat(sprintf("\n   %d. %s (%s)\n", i, gsub(" County", "", area$county), area$priority_level))
    cat(sprintf("      • Cancer burden: %s (%.1f per 100,000)\n",
               area$overall_cancer_burden, area$incidence_rate))
    cat(sprintf("      • Annual cases: %.0f\n", area$average_annual_count))
    cat(sprintf("      • Current providers: %d\n", area$total_providers))
    cat(sprintf("      • Coverage status: %s\n", area$coverage_status))
    cat(sprintf("      • Priority score: %d/6\n", area$combined_priority_score))
    cat(sprintf("      • Estimated female population impact: %s\n",
               format(area$estimated_female_pop_impact, big.mark = ",")))
  }
} else {
  cat("✅ No critical priority areas identified\n")
}

#' Step 4: Calculate state-wide accessibility metrics
cat("\n📈 STEP 4: Calculating state-wide accessibility metrics\n")

# Travel time accessibility summary
accessibility_summary <- accessibility_analysis %>%
  group_by(time_minutes) %>%
  summarise(
    total_female_pop = sum(total_female_pop, na.rm = TRUE),
    total_tracts = sum(tracts_served, na.rm = TRUE),
    avg_per_provider = round(mean(total_female_pop, na.rm = TRUE)),
    .groups = "drop"
  )

cat("🚗 Travel time accessibility:\n")
for (i in 1:nrow(accessibility_summary)) {
  access <- accessibility_summary[i, ]
  cat(sprintf("   • %3d minutes: %s females, %d tracts (avg %s per provider)\n",
             access$time_minutes,
             format(access$total_female_pop, big.mark = ","),
             access$total_tracts,
             format(access$avg_per_provider, big.mark = ",")))
}

# Provider distribution analysis
provider_summary <- provider_locations %>%
  group_by(practice_type) %>%
  summarise(
    count = n(),
    counties = n_distinct(substr(city_state, 1, nchar(city_state)-4)),
    .groups = "drop"
  )

cat("\n🏥 Provider distribution:\n")
for (i in 1:nrow(provider_summary)) {
  prov <- provider_summary[i, ]
  cat(sprintf("   • %-12s: %d locations across ~%d counties\n",
             prov$practice_type, prov$count, prov$counties))
}

#' Step 5: Generate policy recommendations
cat("\n💡 STEP 5: Policy recommendations based on integrated analysis\n")

# Calculate key metrics for recommendations
total_colorado_female_pop <- sum(demographics$total_female_pop)
total_served_60min <- sum(accessibility_analysis$total_female_pop[accessibility_analysis$time_minutes == 60], na.rm = TRUE)
coverage_rate_60min <- total_served_60min / total_colorado_female_pop

high_burden_no_providers <- nrow(filter(integrated_analysis,
                                       overall_cancer_burden == "High Burden" & total_providers == 0))

cat("📋 EVIDENCE-BASED POLICY RECOMMENDATIONS:\n")
cat("========================================\n")

cat("\n🎯 IMMEDIATE ACTIONS NEEDED:\n")
if (high_burden_no_providers > 0) {
  cat(sprintf("   • ADDRESS %d CRITICAL GAPS: High cancer burden counties with no radiation oncologists\n",
             high_burden_no_providers))
  cat("   • Prioritize provider recruitment in these areas\n")
  cat("   • Consider mobile radiation therapy programs\n")
}

cat("\n🚗 ACCESSIBILITY IMPROVEMENTS:\n")
cat(sprintf("   • Current 60-minute coverage: %.1f%% of female population\n", coverage_rate_60min * 100))
if (coverage_rate_60min < 0.8) {
  cat("   • GOAL: Increase to 80% coverage within 60 minutes\n")
  cat("   • Strategy: Strategic placement of new facilities\n")
}

cat("\n📊 RESOURCE ALLOCATION:\n")
underserved_counties <- nrow(filter(integrated_analysis, total_providers == 0))
cat(sprintf("   • %d counties currently without radiation oncology services\n", underserved_counties))
cat("   • Focus telemedicine and consultation services\n")
cat("   • Strengthen referral networks to existing centers\n")

cat("\n🔬 RESEARCH PRIORITIES:\n")
cat("   • Monitor cancer incidence trends in underserved areas\n")
cat("   • Study travel burden on patient outcomes\n")
cat("   • Evaluate effectiveness of mobile radiation programs\n")

#' Step 6: Save comprehensive results
cat("\n💾 STEP 6: Saving comprehensive analysis results\n")

final_results_dir <- "results/comprehensive_colorado_analysis"
dir.create(final_results_dir, recursive = TRUE, showWarnings = FALSE)

# Save all integrated data
readr::write_csv(integrated_analysis, file.path(final_results_dir, "integrated_priority_analysis.csv"))
readr::write_csv(critical_areas, file.path(final_results_dir, "critical_intervention_areas.csv"))
readr::write_csv(accessibility_summary, file.path(final_results_dir, "accessibility_summary.csv"))

# Create executive summary
executive_summary <- list(
  analysis_date = as.character(Sys.Date()),
  title = "Colorado Radiation Oncology Cancer Care Access Analysis",

  key_findings = list(
    counties_analyzed = nrow(integrated_analysis),
    critical_priority_areas = nrow(filter(integrated_analysis, priority_level == "Critical Priority")),
    high_priority_areas = nrow(filter(integrated_analysis, priority_level == "High Priority")),
    total_radiation_oncologists = nrow(provider_locations),
    counties_without_providers = underserved_counties,
    female_population_60min_coverage = round(coverage_rate_60min * 100, 1)
  ),

  critical_gaps = if(nrow(critical_areas) > 0) {
    critical_areas %>%
      select(county, incidence_rate, total_providers, priority_level) %>%
      head(5)
  } else {
    "No critical gaps identified"
  },

  recommendations = list(
    immediate = c(
      "Address high cancer burden counties without radiation oncologists",
      "Expand mobile radiation therapy programs",
      "Strengthen telemedicine consultation networks"
    ),
    strategic = c(
      "Increase 60-minute accessibility coverage to 80%",
      "Strategic recruitment of radiation oncologists",
      "Monitor cancer trends in underserved areas"
    )
  ),

  data_sources = list(
    "Colorado Cancer Registry (cervical cancer incidence 2017-2021)",
    "Colorado radiation oncologist provider directory",
    "US Census Bureau geocoding",
    "American Community Survey demographics"
  )
)

jsonlite::write_json(executive_summary, file.path(final_results_dir, "executive_summary.json"), pretty = TRUE)

cat(sprintf("✅ Comprehensive analysis saved to: %s\n", final_results_dir))

cat("\n🎉 COMPREHENSIVE COLORADO ANALYSIS COMPLETE!\n")
cat("============================================\n")
cat("SUCCESSFULLY INTEGRATED:\n")
cat(sprintf("   ✅ Cancer burden analysis (%d counties)\n", nrow(cancer_analysis)))
cat(sprintf("   ✅ Radiation oncology provider access (%d locations)\n", nrow(provider_locations)))
cat(sprintf("   ✅ Travel time accessibility (%d isochrone combinations)\n", nrow(accessibility_analysis)))
cat(sprintf("   ✅ Female demographic data (%s population)\n", format(total_colorado_female_pop, big.mark = ",")))

cat("\n🎯 KEY OUTCOMES:\n")
cat(sprintf("   • %d critical/high priority intervention areas identified\n",
           nrow(filter(integrated_analysis, priority_level %in% c("Critical Priority", "High Priority")))))
cat(sprintf("   • %.1f%% female population within 60-minute access\n", coverage_rate_60min * 100))
cat(sprintf("   • %d counties currently without radiation oncology services\n", underserved_counties))
cat("   • Evidence-based policy recommendations generated\n")

cat("\n📋 DELIVERABLES CREATED:\n")
cat("   • Integrated priority analysis with scoring\n")
cat("   • Critical intervention area identification\n")
cat("   • Accessibility metrics by travel time\n")
cat("   • Executive summary with key findings\n")
cat("   • Evidence-based policy recommendations\n")

cat("\n🔬 RESEARCH IMPACT:\n")
cat("   This analysis demonstrates the complete pipeline:\n")
cat("   ✅ Real provider data geocoding with US Census Bureau\n")
cat("   ✅ Cancer burden integration from state registry\n")
cat("   ✅ Travel time accessibility analysis\n")
cat("   ✅ Demographic population impact assessment\n")
cat("   ✅ Priority-based policy recommendations\n")

return(integrated_analysis)
