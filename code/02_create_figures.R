#' @title Step 2: Create Figures for Workforce Cliff Manuscript
#' @description This script generates Figure 1 (Workforce projection trajectories) and Figure 2 (Replacement gap visualization)
#' for the workforce cliff manuscript. It requires the consolidated data from '01_consolidate_workforce_data.R' to be run first.
#' @author Tyler Muffly, MD / Claude Code
#' @date 2026-01-12
#' @return PNG and TIFF image files of Figure 1 and Figure 2 saved to 'cliff/figures/'.
#' @seealso \code{\link{00_RUN_ALL.R}}, \code{\link{01_consolidate_workforce_data.R}}

#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 2: Create Figures for Workforce Cliff Manuscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Figure 1: Workforce projection trajectories (2025-2029)
# Figure 2: Replacement gap visualization
#
# Requires: 01_consolidate_workforce_data.R must be run first
#
# Author: Tyler Muffly, MD / Claude Code
# Date: 2026-01-12
#
# Usage:
#   Rscript cliff/code/02_create_figures.R
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

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Figure 1: Workforce Projection Trajectories
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("[", as.character(Sys.time()), "] Creating Figure 1: Workforce trajectories\n", sep = "")

# Generate year-by-year trajectory data (linear interpolation)
years <- 2025:2029

trajectory_data <- workforce_summary %>%
  # The 'crossing' function creates all combinations of inputs.
  crossing(year = years) %>%
  # The 'mutate' function adds new variables to a tibble.
  mutate(
    # Linear interpolation between baseline and projected
    mean_workforce = baseline_2025 +
      (projected_2029 - baseline_2025) * (year - 2025) / 4,
    # Approximate ribbon (constant relative SD)
    lower_ci = mean_workforce - sd_2029 * 1.96,
    upper_ci = mean_workforce + sd_2029 * 1.96,
    # Clean subspecialty names for legend
    subspec_label = case_when(
      subspecialty_abbrev == "FPMRS" ~ "Female Pelvic Medicine and\nReconstructive Surgery",
      subspecialty_abbrev == "GO" ~ "Gynecologic Oncology",
      subspecialty_abbrev == "MIG" ~ "Minimally Invasive\nGynecologic Surgery",
      TRUE ~ subspecialty
    )
  )

# Create figure with ObGyn journal styling
# The 'ggplot' function initializes a ggplot object.
fig1 <- ggplot(trajectory_data,
               aes(x = year, y = mean_workforce,
                   color = subspec_label, fill = subspec_label)) +
  # The 'geom_ribbon' function creates a ribbon plot.
  geom_ribbon(aes(ymin = lower_ci, ymax = upper_ci),
              alpha = 0.15, color = NA) +
  # The 'geom_line' function creates a line plot.
  geom_line(linewidth = 1.0) +
  # The 'geom_point' function creates a scatter plot.
  geom_point(size = 2.5, shape = 21, fill = "white", stroke = 1.5) +
  # The 'scale_color_manual' function sets the colors for the plot.
  scale_color_manual(
    values = c(
      "Female Pelvic Medicine and\nReconstructive Surgery" = "#D62728",
      "Gynecologic Oncology" = "#1F77B4",
      "Minimally Invasive\nGynecologic Surgery" = "#2CA02C"
    )
  ) +
  # The 'scale_fill_manual' function sets the fill colors for the plot.
  scale_fill_manual(
    values = c(
      "Female Pelvic Medicine and\nReconstructive Surgery" = "#D62728",
      "Gynecologic Oncology" = "#1F77B4",
      "Minimally Invasive\nGynecologic Surgery" = "#2CA02C"
    )
  ) +
  # The 'scale_y_continuous' function sets the y-axis limits and breaks.
  scale_y_continuous(
    labels = comma,
    limits = c(650, 1450),
    breaks = seq(700, 1400, by = 100)
  ) +
  # The 'scale_x_continuous' function sets the x-axis limits and breaks.
  scale_x_continuous(breaks = 2025:2029) +
  # The 'labs' function sets the plot labels.
  labs(
    x = "Year",
    y = "Active Physicians (No.)",
    color = NULL,
    fill = NULL
  ) +
  # The 'theme_classic' function sets the plot theme.
  theme_classic(base_size = 11) +
  # The 'theme' function modifies the plot theme.
  theme(
    legend.position = "bottom",
    legend.text = element_text(size = 9),
    legend.key.width = unit(1.5, "cm"),
    panel.grid.major.y = element_line(color = "gray90", linewidth = 0.3),
    axis.line = element_line(color = "black", linewidth = 0.5),
    axis.ticks = element_line(color = "black", linewidth = 0.5)
  ) +
  # The 'guides' function sets the legend guides.
  guides(
    color = guide_legend(nrow = 3, byrow = TRUE),
    fill = guide_legend(nrow = 3, byrow = TRUE)
  )

# The 'ggsave' function saves a ggplot object to a file.
ggsave(here("figures/figure1_workforce_trajectories.png"),
       fig1, width = 7, height = 5, dpi = 600, bg = "white")

ggsave(here("figures/figure1_workforce_trajectories.tiff"),
       fig1, width = 7, height = 5, dpi = 600, bg = "white", compression = "lzw")

cat("  Saved: cliff/figures/figure1_workforce_trajectories.png\n")
cat("  Saved: cliff/figures/figure1_workforce_trajectories.tiff\n")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Figure 2: Replacement Gap Visualization
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("[", as.character(Sys.time()), "] Creating Figure 2: Replacement gap\n", sep = "")

# Prepare data for grouped bar chart
gap_data <- workforce_summary %>%
  # The 'transmute' function is similar to 'mutate', but it drops all other variables.
  transmute(
    subspecialty = factor(
      case_when(
        subspecialty_abbrev == "FPMRS" ~ "Female Pelvic Medicine\nand Reconstructive Surgery",
        subspecialty_abbrev == "GO" ~ "Gynecologic\nOncology",
        subspecialty_abbrev == "MIG" ~ "Minimally Invasive\nGynecologic Surgery",
        TRUE ~ subspecialty
      ),
      levels = c(
        "Female Pelvic Medicine\nand Reconstructive Surgery",
        "Gynecologic\nOncology",
        "Minimally Invasive\nGynecologic Surgery"
      )
    ),
    Annual_Retirements = avg_annual_retirements,
    Annual_Fellows = annual_entrants
  ) %>%
  # The 'pivot_longer' function reshapes data from wide to long format.
  pivot_longer(cols = c(Annual_Retirements, Annual_Fellows),
               names_to = "category",
               values_to = "count") %>%
  mutate(
    category = factor(
      category,
      levels = c("Annual_Retirements", "Annual_Fellows"),
      labels = c("Average Annual Retirements", "Fellowship Graduates per Year")
    )
  )

fig2 <- ggplot(gap_data, aes(x = subspecialty, y = count, fill = category)) +
  # The 'geom_col' function creates a column plot.
  geom_col(position = position_dodge(width = 0.75), width = 0.65, color = "black", linewidth = 0.3) +
  # The 'geom_text' function adds text to the plot.
  geom_text(
    aes(label = sprintf("%.0f", count)),
    position = position_dodge(width = 0.75),
    vjust = -0.5, size = 3, fontface = "bold"
  ) +
  scale_fill_manual(
    values = c(
      "Average Annual Retirements" = "#D62728",
      "Fellowship Graduates per Year" = "#2CA02C"
    )
  ) +
  scale_y_continuous(
    expand = expansion(mult = c(0, 0.15)),
    breaks = seq(0, 80, by = 10)
  ) +
  labs(
    x = NULL,
    y = "Physicians per Year (No.)",
    fill = NULL
  ) +
  theme_classic(base_size = 11) +
  theme(
    legend.position = "bottom",
    legend.text = element_text(size = 9),
    axis.text.x = element_text(size = 9, hjust = 0.5),
    axis.line = element_line(color = "black", linewidth = 0.5),
    axis.ticks = element_line(color = "black", linewidth = 0.5),
    panel.grid.major.y = element_line(color = "gray90", linewidth = 0.3)
  )

ggsave(here("figures/figure2_replacement_gap.png"),
       fig2, width = 7, height = 5, dpi = 600, bg = "white")

ggsave(here("figures/figure2_replacement_gap.tiff"),
       fig2, width = 7, height = 5, dpi = 600, bg = "white", compression = "lzw")

cat("  Saved: cliff/figures/figure2_replacement_gap.png\n")
cat("  Saved: cliff/figures/figure2_replacement_gap.tiff\n")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Summary
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("Figure Generation Complete\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("Created 2 figures in 2 formats (PNG and TIFF)\n")
cat("Output directory: cliff/figures/\n")
cat("\nFiles:\n")
cat("  - figure1_workforce_trajectories.png (600 DPI)\n")
cat("  - figure1_workforce_trajectories.tiff (600 DPI, LZW compression)\n")
cat("  - figure2_replacement_gap.png (600 DPI)\n")
cat("  - figure2_replacement_gap.tiff (600 DPI, LZW compression)\n")
cat("\n")

if (!interactive()) {
  cat("[", as.character(Sys.time()), "] Script completed successfully\n", sep = "")
}
