# Age Estimation Validation Using Washington Birth Year Data
# Tests our assumption: graduation_year + 26 ≈ actual age
# Created: 2025-09-28

library(DBI)
library(duckdb)
library(dplyr)
library(ggplot2)
library(viridis)

# Connect to database
db_path <- "/Volumes/MufflySamsung/nber_my_duckdb.duckdb"
conn <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path)
on.exit({
  if (DBI::dbIsValid(conn)) {
    DBI::dbDisconnect(conn)
  }
})

cat("=== AGE ESTIMATION VALIDATION ===\n")
cat("Testing graduation_year + 26 formula against Washington birth year data\n\n")

# Get Washington physicians with birth year data
washington_validation_query <- "
SELECT DISTINCT
  n.npi,
  n.first_name,
  n.last_name,
  w.birth_year,
  n.graduation_year,
  w.birth_year,
  (2025 - w.birth_year) as actual_age_2025,
  (n.graduation_year + 26) as estimated_age_formula,
  ABS((n.graduation_year + 26) - (2025 - w.birth_year)) as age_error
FROM npidata n
INNER JOIN washington_physician_licenses w ON n.npi = w.npi
WHERE w.birth_year IS NOT NULL
  AND n.graduation_year IS NOT NULL
  AND w.birth_year > 1940  -- Reasonable birth year
  AND w.birth_year < 2005  -- Not too young
  AND n.graduation_year > 1970  -- Reasonable graduation
"

validation_data <- DBI::dbGetQuery(conn, washington_validation_query)

cat(sprintf("Found %d physicians with both birth year and graduation year data\n", nrow(validation_data)))

if (nrow(validation_data) > 0) {

  # Calculate validation statistics
  mean_error <- mean(validation_data$age_error, na.rm = TRUE)
  median_error <- median(validation_data$age_error, na.rm = TRUE)
  max_error <- max(validation_data$age_error, na.rm = TRUE)
  within_5_years <- sum(validation_data$age_error <= 5, na.rm = TRUE)
  accuracy_rate <- within_5_years / nrow(validation_data) * 100

  cat("\n=== VALIDATION RESULTS ===\n")
  cat(sprintf("Mean age estimation error: %.1f years\n", mean_error))
  cat(sprintf("Median age estimation error: %.1f years\n", median_error))
  cat(sprintf("Maximum error: %.0f years\n", max_error))
  cat(sprintf("Accuracy within 5 years: %.1f%% (%d/%d)\n",
              accuracy_rate, within_5_years, nrow(validation_data)))

  # Create validation plot
  validation_plot <- ggplot(validation_data, aes(x = actual_age_2025, y = estimated_age_formula)) +
    geom_point(alpha = 0.6, size = 3, color = "#1f77b4") +
    geom_abline(slope = 1, intercept = 0, color = "red", linetype = "dashed", linewidth = 1) +
    geom_smooth(method = "lm", se = TRUE, color = "#ff7f0e", linewidth = 1) +
    labs(
      title = "Age Estimation Formula Validation",
      subtitle = sprintf("Washington Birth Year Data (n=%d) • Mean Error: %.1f years",
                        nrow(validation_data), mean_error),
      x = "Actual Age (2025 - Birth Year)",
      y = "Estimated Age (Graduation Year + 26)",
      caption = "Red dashed line = perfect accuracy • Orange line = actual relationship"
    ) +
    theme_minimal(base_size = 14) +
    theme(
      plot.title = element_text(size = 16, face = "bold"),
      plot.subtitle = element_text(size = 12, color = "gray50")
    ) +
    coord_equal() +
    scale_x_continuous(limits = c(30, 80), breaks = seq(30, 80, 10)) +
    scale_y_continuous(limits = c(30, 80), breaks = seq(30, 80, 10))

  # Save validation plot
  ggsave("age_estimation_validation.png", validation_plot,
         width = 8, height = 8, dpi = 300, bg = "white")

  cat(sprintf("\nValidation plot saved as: age_estimation_validation.png\n"))

  # Flag large errors for investigation
  large_errors <- validation_data %>%
    filter(age_error > 10) %>%
    select(npi, first_name, last_name, actual_age_2025, estimated_age_formula, age_error, graduation_year, birth_year)

  if (nrow(large_errors) > 0) {
    cat(sprintf("\n⚠️  %d physicians with >10 year age estimation errors:\n", nrow(large_errors)))
    print(large_errors)
  }

  # Save validation results
  write.csv(validation_data, "age_estimation_validation_data.csv", row.names = FALSE)
  cat(sprintf("Detailed validation data saved as: age_estimation_validation_data.csv\n"))

} else {
  cat("❌ No validation data found. Check Washington birth year data availability.\n")
}

cat("\n=== VALIDATION COMPLETE ===\n")
