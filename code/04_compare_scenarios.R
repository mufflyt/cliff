#' @title Step 4: Compare Fellowship Scenarios
#' @description This script runs workforce projections across multiple fellowship scenarios
#' defined in 'cliff/config/fellowship_assumptions.yml' and creates comparison visualizations
#' and tables.
#' @author Tyler Muffly, MD / Claude Code
#' @date 2026-01-12
#' @return CSV and image files comparing different fellowship scenarios.
#' @seealso \code{\link{00_RUN_ALL.R}}, \code{\link{01_consolidate_workforce_data.R}}

#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 4: Compare Fellowship Scenarios
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Purpose: Run workforce projections across multiple fellowship scenarios
#          and create comparison visualizations
#
# Scenarios (from cliff/config/fellowship_assumptions.yml):
#   - default: Current best estimates
#   - optimistic: Increased fellowship positions
#   - pessimistic: Decreased fellowship positions
#   - historical_2025: Pre-2026 assumptions
#   - status_quo: Maintain current production
#
# Author: Tyler Muffly, MD / Claude Code
# Date: 2026-01-12
#
# Usage:
#   Rscript cliff/code/04_compare_scenarios.R
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# The 'suppressPackageStartupMessages' function prevents package startup messages from being printed.
suppressPackageStartupMessages({
  # The 'tidyverse' library is a collection of R packages designed for data science.
  # It includes ggplot2, dplyr, tidyr, readr, purrr, and tibble.
  library(tidyverse)
  # The 'here' library helps to create reproducible paths to files.
  library(here)
  # The 'yaml' library is used to read YAML configuration files.
  library(yaml)
  # The 'scales' library provides tools for customizing the scales of ggplot2 plots.
  library(scales)
})

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Configuration
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

CONFIG_FILE <- here("config/fellowship_assumptions.yml")
OUTPUT_DIR <- here("figures")

cat("\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("FELLOWSHIP SCENARIO COMPARISON\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("\n")

# Load config to get available scenarios
if (!file.exists(CONFIG_FILE)) {
  stop(sprintf("Config file not found: %s", CONFIG_FILE))
}

# The 'read_yaml' function reads a YAML file and returns it as a list.
config <- read_yaml(CONFIG_FILE)
scenarios <- names(config)

cat(sprintf("Found %d scenarios in config:\n", length(scenarios)))
for (s in scenarios) {
  cat(sprintf("  - %s\n", s))
}
cat("\n")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Run Projections for Each Scenario
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("Running projections for each scenario...\n\n")

all_results <- list()

# Load the SSOT directly (single-source projection baseline)
ssot_file <- here("data/workforce_projections_consolidated.csv")
if (!file.exists(ssot_file)) stop(sprintf("SSOT not found: %s", ssot_file))
ssot <- read_csv(ssot_file, show_col_types = FALSE)

# YAML config uses FPMRS/GO/MIG keys; map to SSOT abbreviations URPS/GO/MIGS
abbrev_map <- c(URPS = "FPMRS", GO = "GO", MIGS = "MIG")

for (scenario in scenarios) {
  cat(sprintf("[%s] Running scenario: %s\n", Sys.time(), scenario))

  scenario_cfg <- config[[scenario]]
  if (is.null(scenario_cfg)) {
    warning(sprintf("  ⚠ Scenario '%s' has no config entries", scenario))
    next
  }

  # Apply scenario fellowship numbers; recalculate projections from SSOT baseline
  results <- ssot %>%
    mutate(
      annual_entrants = case_when(
        subspecialty_abbrev == "URPS" ~ as.numeric(scenario_cfg[["FPMRS"]] %||% annual_entrants),
        subspecialty_abbrev == "GO"   ~ as.numeric(scenario_cfg[["GO"]]    %||% annual_entrants),
        subspecialty_abbrev == "MIGS" ~ as.numeric(scenario_cfg[["MIG"]]   %||% annual_entrants),
        TRUE ~ annual_entrants
      ),
      projected_2029  = baseline_2025 + 4 * (annual_entrants - avg_annual_retirements),
      percent_change  = 100 * (projected_2029 - baseline_2025) / baseline_2025,
      replacement_ratio = annual_entrants / avg_annual_retirements,
      fellowship_total_4yr = as.integer(annual_entrants) * 4L,
      scenario = scenario
    )

  all_results[[scenario]] <- results

  # Save scenario-specific snapshot
  scenario_file <- here(
    "data",
    sprintf("workforce_projections_consolidated_%s.csv", scenario)
  )
  write_csv(results, scenario_file)
  cat(sprintf("  ✓ Completed: %s\n", scenario))
  cat(sprintf("    ↳ Snapshot saved to %s\n", basename(scenario_file)))
}

cat("\n")

# The 'bind_rows' function combines data frames by row.
# Combine all results
comparison_data <- bind_rows(all_results)

# Save combined comparison data
comparison_file <- here("data/scenario_comparison.csv")
write_csv(comparison_data, comparison_file)
cat(sprintf("✓ Saved comparison data: %s\n\n", comparison_file))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Create Comparison Table
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("SCENARIO COMPARISON: 2029 Projected Workforce\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("\n")

if (nrow(comparison_data) == 0) {
  cat("  ⚠ No scenario results available; skipping comparison table.\n")
} else {

comparison_table <- comparison_data %>%
  # The 'select' function keeps or drops variables from a tibble.
  select(all_of(c("scenario", "subspecialty_abbrev", "projected_2029", "annual_entrants"))) %>%
  # The 'arrange' function reorders rows.
  arrange(subspecialty_abbrev, scenario) %>%
  # The 'pivot_wider' function reshapes data from long to wide format.
  pivot_wider(
    names_from = scenario,
    values_from = c(projected_2029, annual_entrants),
    names_glue = "{scenario}_{.value}"
  ) %>%
  select(subspecialty_abbrev, contains("projected"), contains("annual"))

print(comparison_table, width = Inf)

} # end if (nrow(comparison_data) > 0)

cat("\n")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Create Comparison Figure: Workforce by Scenario
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

if (nrow(comparison_data) == 0) {
  cat("[", as.character(Sys.time()), "] No scenario data — skipping figures.\n", sep = "")
} else {

cat("[", as.character(Sys.time()), "] Creating scenario comparison figure\n", sep = "")

# Build scenario order dynamically, keeping alphabetical order but ensuring default is first
scenario_order <- unique(comparison_data$scenario)
if ("default" %in% scenario_order) {
  scenario_order <- c("default", sort(setdiff(scenario_order, "default")))
} else {
  scenario_order <- sort(scenario_order)
}

plot_data <- comparison_data %>%
  mutate(
    scenario = factor(scenario, levels = scenario_order),
    scenario_label = str_replace_all(stringr::str_to_title(str_replace_all(scenario, "_", " ")), "Default", "Default (Current)")
  )

# The 'ggplot' function initializes a ggplot object.
# Create figure
fig_comparison <- ggplot(plot_data,
                          aes(x = scenario_label, y = projected_2029,
                              fill = subspecialty_abbrev)) +
  # The 'geom_col' function creates a column plot.
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  # The 'geom_text' function adds text to the plot.
  geom_text(aes(label = format(round(projected_2029), big.mark = ",")),
            position = position_dodge(width = 0.8),
            vjust = -0.5, size = 3) +

  # The 'facet_wrap' function creates a layout of panels defined by a single variable.
  # Facet by subspecialty
  facet_wrap(~ subspecialty_abbrev, nrow = 1, scales = "free_y") +

  # Styling
  # The 'scale_fill_viridis_d' function provides a set of colorblind-friendly colors.
  scale_fill_viridis_d(option = "plasma", begin = 0.2, end = 0.8) +
  # The 'scale_y_continuous' function sets the y-axis limits and breaks.
  scale_y_continuous(labels = comma, expand = expansion(mult = c(0.05, 0.15))) +

  # The 'labs' function sets the plot labels.
  labs(
    title = "Workforce Projections by Fellowship Scenario (2029)",
    subtitle = "Comparing different fellowship production assumptions",
    x = "Scenario",
    y = "Projected Active Physicians (2029)",
    fill = "Subspecialty"
  ) +

  # The 'theme_minimal' function sets the plot theme.
  theme_minimal(base_size = 12) +
  # The 'theme' function modifies the plot theme.
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(color = "gray40", size = 11),
    axis.text.x = element_text(angle = 45, hjust = 1),
    legend.position = "none",
    strip.text = element_text(face = "bold", size = 11),
    panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank()
  )

# The 'ggsave' function saves a ggplot object to a file.
# Save figure
ggsave(here("figures/scenario_comparison.png"),
       fig_comparison, width = 12, height = 6, dpi = 600, bg = "white")
cat("  Saved: cliff/figures/scenario_comparison.png\n")

ggsave(here("figures/scenario_comparison.tiff"),
       fig_comparison, width = 12, height = 6, dpi = 600, bg = "white",
       compression = "lzw")
cat("  Saved: cliff/figures/scenario_comparison.tiff\n")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Create Line Plot: Workforce Change by Scenario
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("[", as.character(Sys.time()), "] Creating percent change comparison\n", sep = "")

fig_change <- ggplot(plot_data,
                      aes(x = scenario_label, y = percent_change,
                          group = subspecialty_abbrev, color = subspecialty_abbrev)) +
  # The 'geom_line' function creates a line plot.
  geom_line(linewidth = 1.2) +
  # The 'geom_point' function creates a scatter plot.
  geom_point(size = 3) +
  # The 'geom_hline' function adds a horizontal line to the plot.
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  # The 'geom_text' function adds text to the plot.
  geom_text(aes(label = sprintf("%.1f%%", percent_change)),
            vjust = -1, size = 3.5, fontface = "bold",
            show.legend = FALSE) +

  # Styling
  # The 'scale_color_viridis_d' function provides a set of colorblind-friendly colors.
  scale_color_viridis_d(option = "plasma", begin = 0.2, end = 0.8) +
  # The 'scale_y_continuous' function sets the y-axis limits and breaks.
  # The 'label_percent' function formats numbers as percentages.
  scale_y_continuous(labels = label_percent(scale = 1),
                      expand = expansion(mult = c(0.15, 0.15))) +

  # The 'labs' function sets the plot labels.
  labs(
    title = "Workforce Change by Fellowship Scenario (2025 → 2029)",
    subtitle = "Percent change in active physicians under different assumptions",
    x = "Scenario",
    y = "Percent Change",
    color = "Subspecialty"
  ) +

  # The 'theme_minimal' function sets the plot theme.
  theme_minimal(base_size = 12) +
  # The 'theme' function modifies the plot theme.
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(color = "gray40", size = 11),
    axis.text.x = element_text(angle = 45, hjust = 1),
    legend.position = "bottom",
    panel.grid.minor = element_blank()
  )

# The 'ggsave' function saves a ggplot object to a file.
# Save figure
ggsave(here("figures/scenario_comparison_change.png"),
       fig_change, width = 10, height = 7, dpi = 600, bg = "white")
cat("  Saved: cliff/figures/scenario_comparison_change.png\n")

ggsave(here("figures/scenario_comparison_change.tiff"),
       fig_change, width = 10, height = 7, dpi = 600, bg = "white",
       compression = "lzw")
cat("  Saved: cliff/figures/scenario_comparison_change.tiff\n")

} # end if (nrow(comparison_data) > 0) for figures

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Restore Default Scenario Output (no-op: SSOT is already the default)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Summary Report
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("SCENARIO COMPARISON SUMMARY\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("\n")

summary <- comparison_data %>%
  # The 'group_by' function groups a tibble by one or more variables.
  group_by(scenario) %>%
  # The 'summarise' function creates a new tibble with summary statistics.
  summarise(
    total_workforce_2029 = sum(projected_2029),
    net_change = sum(projected_2029) - sum(baseline_2025),
    pct_change = 100 * net_change / sum(baseline_2025),
    .groups = "drop"
  ) %>%
  arrange(desc(total_workforce_2029))

cat("Total projected workforce across all subspecialties:\n\n")

summary_display <- summary %>%
  # The 'transmute' function is similar to 'mutate', but it drops all other variables.
  transmute(
    Scenario = scenario,
    `2029 Total` = format(round(total_workforce_2029), big.mark = ","),
    `Net Change` = sprintf("%+.0f", net_change),
    `% Change` = sprintf("%.1f%%", pct_change)
  )

print(summary_display, width = Inf)

cat("\n")
cat("Interpretation:\n")
cat("  • Best case (optimistic): +", format(round(summary$net_change[summary$scenario == "optimistic"]), big.mark = ","), " physicians\n", sep = "")
cat("  • Base case (default): +", format(round(summary$net_change[summary$scenario == "default"]), big.mark = ","), " physicians\n", sep = "")
cat("  • Worst case (pessimistic): ", format(round(summary$net_change[summary$scenario == "pessimistic"]), big.mark = ","), " physicians\n", sep = "")

cat("\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("\n")

if (!interactive()) {
  cat("[", as.character(Sys.time()), "] Script completed successfully\n", sep = "")
}
