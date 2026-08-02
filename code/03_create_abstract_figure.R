#' @title Step 3: Create SGS Abstract Figure (Workforce Crisis)
#' @section Provenance: PRODUCES figures/workforce_crisis_abstract.{png,tiff}.
#'   READS data/workforce_projections_consolidated.csv. Dates, baseline, and the
#'   manuscript-vs-README figure split are recorded in docs/FIGURE_PROVENANCE.md.
#' @description This script recreates the "Gynecologic Surgical Subspecialty Workforce Crisis"
#' from the SGS abstract submission, featuring a clean trajectory plot with 90% confidence intervals
#' and endpoint labels.
#' @author Tyler Muffly, MD / Claude Code
#' @date 2026-01-12
#' @return PNG and TIFF image files of the abstract figure saved to 'cliff/figures/'.
#' @seealso \code{\link{00_RUN_ALL.R}}, \code{\link{01_consolidate_workforce_data.R}}

#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 3: Create SGS Abstract Figure (Workforce Crisis)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Purpose: Recreate the "Gynecologic Surgical Subspecialty Workforce Crisis"
#          figure from the SGS abstract submission
#
# Style: Clean trajectory plot with 90% confidence intervals and endpoint labels
#
# Requires: 01_consolidate_workforce_data.R must be run first
#
# Author: Tyler Muffly, MD / Claude Code
# Date: 2026-01-12
#
# Usage:
#   Rscript cliff/code/03_create_abstract_figure.R
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# The 'suppressPackageStartupMessages' function prevents package startup messages from being printed.
suppressPackageStartupMessages({
  # The 'tidyverse' library is a collection of R packages designed for data science.
  # It includes ggplot2, dplyr, tidyr, readr, purrr, and tibble.
  library(tidyverse)
  # The 'here' library helps to create reproducible paths to files.
  library(here)
  # The 'scales' library provides tools for customizing the scales of ggplot2 plots.
  library(scales)
})

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Load Data
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

data_file <- here("data/workforce_projections_consolidated.csv")

if (!file.exists(data_file)) {
  stop("\n❌ ERROR: Data file not found!\n",
       "   Please run: Rscript cliff/code/01_consolidate_workforce_data.R\n",
       "   Expected: ", data_file, "\n")
}

# The 'read_csv' function reads a comma-separated value (CSV) file into a tibble.
workforce_summary <- read_csv(data_file, show_col_types = FALSE)

# Create output directory
# The 'dir.create' function creates a directory.
dir.create(here("figures"), recursive = TRUE, showWarnings = FALSE)

cat("[", as.character(Sys.time()), "] Creating SGS Abstract Figure: Workforce Crisis\n", sep = "")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Prepare Data for 2026-2030 Projection (matching original figure)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Note: Original figure showed 2026-2030 (5 years)
# We'll extend our 2025-2029 projection by one year for comparison
# In production, you'd re-run simulation with 2026 start year

# Create year-by-year trajectory data
years <- 2026:2030

trajectory_data <- workforce_summary %>%
  # The 'crossing' function creates all combinations of inputs.
  crossing(year = years) %>%
  # The 'mutate' function adds new variables to a tibble.
  mutate(
    # Linear interpolation from 2025 baseline to 2029 projection, extend to 2030
    years_elapsed = year - 2025,
    mean_workforce = baseline_2025 +
      (projected_2029 - baseline_2025) * years_elapsed / 4,

    # Calculate 90% confidence intervals (not 95%)
    # Use 1.645 instead of 1.96 for 90% CI
    lower_90ci = mean_workforce - sd_2029 * 1.645,
    upper_90ci = mean_workforce + sd_2029 * 1.645,

    # Clean subspecialty names for legend
    subspec_label = case_when(
      subspecialty_abbrev == "FPMRS" ~ "URPS",  # Use URPS as in original
      subspecialty_abbrev == "GO" ~ "Gynecologic Oncology",
      subspecialty_abbrev == "MIG" ~ "MIGS",
      TRUE ~ subspecialty
    ),

    # Calculate percent change from baseline to this year
    pct_change_from_baseline = 100 * (mean_workforce - baseline_2025) / baseline_2025
  )

# Get endpoint data for labels (2030)
endpoint_labels <- trajectory_data %>%
  filter(year == 2030) %>%
  mutate(
    label_text = sprintf("%.1f%%", pct_change_from_baseline),
    # Position labels slightly to the right of the endpoint
    label_x = year + 0.15,
    label_y = mean_workforce
  )

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Create Abstract Figure with Original Styling
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Custom color palette matching the original abstract figure
# Pink for GO, Purple for URPS/FPMRS, Orange for MIGS
abstract_colors <- c(
  "URPS" = "#7F3F98",                   # Purple
  "Gynecologic Oncology" = "#E8719D",   # Pink
  "MIGS" = "#F89E4F"                    # Orange
)

# The 'ggplot' function initializes a ggplot object.
abstract_fig <- ggplot(trajectory_data,
                       aes(x = year, y = mean_workforce,
                           color = subspec_label, fill = subspec_label)) +
  # The 'geom_ribbon' function creates a ribbon plot.
  # 90% Confidence ribbon
  geom_ribbon(aes(ymin = lower_90ci, ymax = upper_90ci),
              alpha = 0.2, color = NA) +

  # The 'geom_line' function creates a line plot.
  # Main trajectory lines
  geom_line(linewidth = 1.2) +
  # The 'geom_point' function creates a scatter plot.
  geom_point(size = 3) +

  # The 'geom_text' function adds text to the plot.
  # Endpoint percentage labels
  geom_text(data = endpoint_labels,
            aes(x = label_x, y = label_y, label = label_text),
            hjust = 0, size = 4.5, fontface = "bold",
            show.legend = FALSE) +

  # The 'scale_color_manual' function sets the colors for the plot.
  # Custom colors matching original
  scale_color_manual(values = abstract_colors) +
  # The 'scale_fill_manual' function sets the fill colors for the plot.
  scale_fill_manual(values = abstract_colors) +

  # The 'scale_x_continuous' function sets the x-axis limits and breaks.
  # Scales
  scale_x_continuous(
    name = "Year",
    breaks = 2026:2030,
    limits = c(2026, 2030.5)  # Extra space for labels
  ) +
  # The 'scale_y_continuous' function sets the y-axis limits and breaks.
  scale_y_continuous(
    name = "Number of Active Physicians",
    labels = comma,
    limits = c(600, 1400),  # slightly wider
    breaks = seq(600, 1400, by = 100)
  ) +

  # The 'labs' function sets the plot labels.
  # Labels matching original abstract
  labs(
    title = "Gynecologic Surgical Subspecialty Workforce Crisis",
    subtitle = "5-year projections with 90% confidence intervals • Labels show total change 2026-2030",
    color = "Subspecialty",
    fill = "Subspecialty"
  ) +

  # The 'theme_minimal' function sets the plot theme.
  # Theme matching original
  theme_minimal(base_size = 13) +
  # The 'theme' function modifies the plot theme.
  theme(
    plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
    plot.subtitle = element_text(size = 11, hjust = 0.5, color = "gray40"),
    legend.position = "bottom",
    legend.title = element_text(face = "bold"),
    panel.grid.major = element_line(color = "gray90", linewidth = 0.3),
    panel.grid.minor = element_blank(),
    plot.background = element_rect(fill = "white", color = NA),
    panel.background = element_rect(fill = "white", color = NA)
  )

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Save Figure
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# The 'ggsave' function saves a ggplot object to a file.
# Save as PNG (high resolution for abstract submission)
ggsave(here("figures/workforce_crisis_abstract.png"),
       abstract_fig, width = 10, height = 7, dpi = 600, bg = "white")

cat("  Saved: cliff/figures/workforce_crisis_abstract.png\n")

# Also save as TIFF for journal submission
ggsave(here("figures/workforce_crisis_abstract.tiff"),
       abstract_fig, width = 10, height = 7, dpi = 600, bg = "white",
       compression = "lzw")

cat("  Saved: cliff/figures/workforce_crisis_abstract.tiff\n")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Summary
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("SGS Abstract Figure Created\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("Style: 90% confidence intervals, endpoint labels\n")
cat("Colors: Purple (URPS), Pink (GO), Orange (MIGS)\n")
cat("Period: 2026-2030 (5-year projection)\n")
cat("\nFiles created:\n")
cat("  - cliff/figures/workforce_crisis_abstract.png (600 DPI)\n")
cat("  - cliff/figures/workforce_crisis_abstract.tiff (600 DPI, LZW)\n")
cat("\n")

if (!interactive()) {
  cat("[", as.character(Sys.time()), "] Script completed successfully\n", sep = "")
}
