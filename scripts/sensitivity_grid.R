#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Multidimensional sensitivity grid (review point #1): honestly report the
# fully-crossed grid, not a one-way claim. Crosses the observation window
# (fully-observable / drop-2 / full) x departure-rate multiplier (1x/2x/3x) x
# graduate practice-conversion (1.00/0.85/0.70). ratio = window_ratio * conv / mult.
# One-way sensitivities all stay above replacement; below-replacement cells occur
# only where multiple adverse assumptions combine. This produces the counts and
# worst cell the manuscript reports, so the abstract can no longer overclaim.
#
# OUTPUT: cliff/data/sensitivity_grid.csv (all cells) + sensitivity_grid_summary.csv
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(dplyr); library(tidyr); library(readr); library(here)})
source(here::here("manuscript", "R", "workforce_data_contract.R"))

ABOVE <- WORKFORCE_REPLACEMENT_ABOVE_MIN  # 1.05
AT_LO <- WORKFORCE_REPLACEMENT_AT_MIN     # 0.95

w <- read_csv(here::here("data","departure_window_sensitivity.csv"), show_col_types=FALSE)
MULT <- c(1,2,3); CONV <- c(1.00,0.85,0.70)

grid <- tidyr::expand_grid(
  subspecialty_abbrev = unique(w$subspecialty_abbrev),
  label = unique(w$label), mult = MULT, conv = CONV) %>%
  left_join(w %>% select(subspecialty_abbrev, label, dynamic_ratio),
            by=c("subspecialty_abbrev","label")) %>%
  mutate(ratio = round(dynamic_ratio * conv / mult, 3),
         one_way = (mult==1 & conv==1) | (label=="fully_obs" & conv==1) |
                   (label=="fully_obs" & mult==1))  # single-lever from the primary cell
write_csv(grid, here::here("data","sensitivity_grid.csv"))

summ <- grid %>% group_by(subspecialty_abbrev) %>% summarise(
  n_cells = dplyr::n(),
  n_above = sum(ratio > ABOVE),
  n_at    = sum(ratio >= AT_LO & ratio <= ABOVE),
  n_below = sum(ratio < AT_LO),
  worst_ratio = min(ratio),
  oneway_min  = min(ratio[one_way]),
  .groups="drop")
worst_cell <- grid %>% group_by(subspecialty_abbrev) %>%
  slice_min(ratio, n=1, with_ties=FALSE) %>%
  transmute(subspecialty_abbrev, worst_window=label, worst_mult=mult, worst_conv=conv)
summ <- summ %>% left_join(worst_cell, by="subspecialty_abbrev")
summ <- summ[match(c("GO","URPS","MIGS"), summ$subspecialty_abbrev), ]
write_csv(summ, here::here("data","sensitivity_grid_summary.csv"))

cat("=== #1 multidimensional sensitivity grid (window x rate-mult x conversion) ===\n")
print(as.data.frame(summ), row.names=FALSE)
cat("\nOne-way minima (all should be > 1.05):\n")
print(as.data.frame(summ %>% select(subspecialty_abbrev, oneway_min)), row.names=FALSE)
cat("Wrote cliff/data/sensitivity_grid.csv + sensitivity_grid_summary.csv\n")
