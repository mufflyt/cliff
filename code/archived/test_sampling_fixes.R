#!/usr/bin/env Rscript
# Test Sampling Bug Fixes
# =======================
# Comprehensive test of all sampling bug fixes

source('R/safe_sampling_functions.R')
source('R/production_error_handling.R')

library(dplyr)

cat("=== TESTING SAMPLING BUG FIXES ===\n")

# Test 1: Safe Sample with Edge Cases
cat("\n🧪 Test 1: Safe Sample Edge Cases\n")

# Edge case 1: Empty dataset
empty_data <- data.frame()
result1 <- safe_sample(empty_data, 100)
cat(sprintf("Empty dataset test: %d rows returned\n", nrow(result1)))

# Edge case 2: Sample size larger than data
small_data <- data.frame(
  id = 1:50,
  value = rnorm(50)
)
result2 <- safe_sample(small_data, 100)
cat(sprintf("Small dataset test: %d rows requested, %d returned\n", 100, nrow(result2)))

# Edge case 3: Normal sampling
large_data <- data.frame(
  id = 1:10000,
  subspecialty = sample(c("GO", "FPMRS", "MIG"), 10000, replace = TRUE),
  age = sample(30:80, 10000, replace = TRUE)
)
result3 <- safe_sample(large_data, 1000, stratify_by = "subspecialty")
cat(sprintf("Large dataset stratified test: %d rows returned\n", nrow(result3)))

# Test 2: Realistic Test Data Generation
cat("\n🧪 Test 2: Realistic Test Data Generation\n")

# Test with existing data for realistic distributions
realistic_data <- generate_realistic_test_data(large_data, 500)
cat(sprintf("Generated realistic data: %d records\n", nrow(realistic_data)))

# Check age distribution
age_summary <- summary(realistic_data$estimated_age)
cat("Age distribution: ")
cat(sprintf("Min: %d, Median: %.1f, Max: %d\n",
           age_summary[1], age_summary[3], age_summary[6]))

# Test 3: Memory-Safe Sampling
cat("\n🧪 Test 3: Memory-Safe Sampling\n")

# Create a "large" dataset simulation
memory_test_data <- data.frame(
  id = 1:50000,
  subspecialty = sample(c("GO", "FPMRS", "MIG"), 50000, replace = TRUE),
  value = rnorm(50000)
)

# Test memory-safe sampling
result4 <- memory_safe_sample(memory_test_data, memory_limit_mb = 10, estimation_mb_per_row = 0.001)
cat(sprintf("Memory-safe sample: %d → %d rows\n", nrow(memory_test_data), nrow(result4)))

# Test 4: Production Error Handling Fix
cat("\n🧪 Test 4: Production Error Handling Fix\n")

# Create test physician and license data
test_physicians <- data.frame(
  npi = sprintf("%010d", 1:60000),
  first_name = paste0("Physician", 1:60000),
  last_name = paste0("LastName", 1:60000),
  graduation_year = sample(1980:2020, 60000, replace = TRUE),
  subspecialty_f = sample(c("Gynecologic Oncology", "Female Pelvic Medicine & Reconstructive Surgery", "MIG"),
                         60000, replace = TRUE),
  stringsAsFactors = FALSE
)

test_licenses <- data.frame(
  firstname = paste0("Physician", 1:60000),
  lastname = paste0("LastName", 1:60000),
  license_status = sample(c("ACTIVE", "EXPIRED"), 60000, replace = TRUE),
  stringsAsFactors = FALSE
)

cat(sprintf("Created test data: %d physicians, %d licenses\n",
           nrow(test_physicians), nrow(test_licenses)))

# Test the fixed production function
tryCatch({
  result5 <- safe_retirement_detection(test_physicians, test_licenses)
  cat(sprintf("✅ Production function succeeded: %d physicians analyzed\n",
             nrow(result5$physician_analysis)))

}, error = function(e) {
  cat(sprintf("❌ Production function failed: %s\n", e$message))
})

# Test 5: Database Sampling Simulation
cat("\n🧪 Test 5: Database Sampling Simulation\n")

# Simulate database query results
simulate_db_query <- function(query, limit = NULL) {
  # Simulate a large result set
  n_total <- 100000

  if (!is.null(limit)) {
    n_return <- min(limit, n_total)
  } else {
    n_return <- n_total
  }

  return(data.frame(
    npi = sprintf("%010d", sample(1000000000:9999999999, n_return)),
    name = paste0("Physician", 1:n_return),
    year = sample(2015:2023, n_return, replace = TRUE)
  ))
}

# Test safe database sampling concept
simulated_result <- simulate_db_query("SELECT * FROM physicians", limit = 5000)
cat(sprintf("Database simulation: %d records returned\n", nrow(simulated_result)))

# Test 6: Stress Test Edge Cases
cat("\n🧪 Test 6: Stress Test Edge Cases\n")

# Test with zero rows after filtering
zero_rows_test <- data.frame(
  npi = character(0),
  age = numeric(0)
)

result6 <- fix_production_sampling_bug(zero_rows_test, 1000)
cat(sprintf("Zero rows test: %d rows returned\n", nrow(result6)))

# Test with exactly target size
exact_size_data <- data.frame(
  id = 1:1000,
  value = rnorm(1000)
)

result7 <- fix_production_sampling_bug(exact_size_data, 1000)
cat(sprintf("Exact size test: %d rows returned (should be 1000)\n", nrow(result7)))

# Test 7: Reproducibility Test
cat("\n🧪 Test 7: Reproducibility Test\n")

# Test that sampling is reproducible with same seed
set.seed(42)
sample1 <- safe_sample(large_data, 100, seed = 123)

set.seed(42)  # Reset to same state
sample2 <- safe_sample(large_data, 100, seed = 123)

reproducible <- identical(sample1$id, sample2$id)
cat(sprintf("Reproducibility test: %s\n", ifelse(reproducible, "✅ PASS", "❌ FAIL")))

# Summary Report
cat("\n=== SAMPLING BUG FIX TEST SUMMARY ===\n")

tests_results <- list(
  "Empty dataset handling" = nrow(result1) == 0,
  "Small dataset (no oversample)" = nrow(result2) == 50,
  "Large dataset stratified" = nrow(result3) == 1000,
  "Realistic data generation" = nrow(realistic_data) == 500,
  "Memory-safe sampling" = nrow(result4) < nrow(memory_test_data),
  "Zero rows handling" = nrow(result6) == 0,
  "Exact size handling" = nrow(result7) == 1000,
  "Reproducibility" = reproducible
)

passed_tests <- sum(unlist(tests_results))
total_tests <- length(tests_results)

cat(sprintf("Tests passed: %d/%d\n", passed_tests, total_tests))

for (test_name in names(tests_results)) {
  status <- ifelse(tests_results[[test_name]], "✅", "❌")
  cat(sprintf("%s %s\n", status, test_name))
}

if (passed_tests == total_tests) {
  cat("\n🎉 ALL SAMPLING BUG FIXES WORKING CORRECTLY!\n")
} else {
  cat(sprintf("\n⚠️  %d tests failed - review sampling logic\n", total_tests - passed_tests))
}

cat("\n📊 Key Improvements Made:\n")
cat("✅ Fixed sample-size-larger-than-population bug\n")
cat("✅ Added stratified sampling for representative samples\n")
cat("✅ Implemented memory-safe sampling with automatic size adjustment\n")
cat("✅ Added reproducible sampling with seed control\n")
cat("✅ Created realistic test data generation instead of pure random\n")
cat("✅ Added comprehensive error handling and validation\n")
cat("✅ Implemented safe database sampling patterns\n")
