#!/usr/bin/env Rscript
# Export vector (PDF) copies of the three main-manuscript figures alongside the
# Word-rendered PNGs, per the figure-revision standard. Uses the same builders the
# manuscript calls, so the vector copies match the rendered figures exactly.
suppressPackageStartupMessages({
  library(here); library(dplyr); library(readr); library(ggplot2)
  library(patchwork); library(scales); library(tibble); library(tidyr)
})
source(here::here("manuscript", "R", "workforce_statistics.R"))
source(here::here("manuscript", "R", "workforce_figures.R"))
source(here::here("manuscript", "R", "workforce_figures_expanded.R"))

out <- here::here("manuscript", "figures")
specs <- list(
  list(f = fig_trajectory,                 file = "figure1_trajectory.pdf",   w = 7.0, h = 4.2),
  list(f = fig_robustness,                 file = "figure2_sensitivity.pdf",  w = 7.0, h = 4.2),
  list(f = fig_supply_demand_integrated,   file = "figure3_supply_need.pdf",  w = 7.2, h = 7.0)
)
for (s in specs) {
  p <- s$f()
  ggplot2::ggsave(file.path(out, s$file), p, width = s$w, height = s$h,
                  device = cairo_pdf, bg = "white")
  cat("Wrote", file.path("manuscript/figures", s$file), "\n")
}
