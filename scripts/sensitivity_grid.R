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

# ---- publication cohort contract: FAIL CLOSED --------------------------------
# This line used to read
#     summ[match(c("GO","URPS","MIGS"), summ$subspecialty_abbrev), ]
# and that is a defect, not a convenience. When a named cohort is absent from the
# source data match() returns NA and the reindex MANUFACTURES a row of NAs, which
# was then written to CSV and rendered into Appendix Table S17 as though it were a
# result. Nothing errored.
#
# MIGS was intentionally withdrawn upstream (exploratory focused-practice cohort,
# not pooled with the board-certified ones -- reviewer decision 2026-07-19;
# build_departure_window_sensitivity.R builds only URPS and GO). That scope change
# was correct. Silently rendering the consequence as NA was not.
#
# A change in scientific SCOPE must be decided by a person and declared here. A
# cohort that is required, absent, and not explicitly withdrawn stops the run.
REQUIRED_COHORTS  <- c("GO", "URPS", "MIGS")
# WITHDRAWN 2026-08-16: MIGS. The current scientific scope of this sensitivity is
# URPS + GO, as defined upstream by build_departure_window_sensitivity.R, which builds
# only those two (MIGS is an exploratory focused-practice cohort, not pooled --
# reviewer decision 2026-07-19). Downstream publication code follows the upstream
# scope; it does not manufacture a MIGS result from another pathway to preserve a
# historical table shape. The three-cohort result is preserved as provenance in
# docs/adjudication/sensitivity_grid.md, not resurrected here.
WITHDRAWN_COHORTS <- c("MIGS")

wanted  <- setdiff(REQUIRED_COHORTS, WITHDRAWN_COHORTS)
missing <- setdiff(wanted, unique(summ$subspecialty_abbrev))
if (length(missing)) {
  stop(sprintf(paste0(
    "[sensitivity_grid] cohort(s) unavailable in the source data: %s\n",
    "  source     : data/departure_window_sensitivity.csv\n",
    "  present    : %s\n",
    "  required   : %s\n",
    "This is a change in scientific SCOPE and will not be rendered as an NA row.\n",
    "Either restore the cohort upstream, or declare it in WITHDRAWN_COHORTS above\n",
    "and update Appendix Table S17 and its prose to match.\n",
    "See docs/adjudication/sensitivity_grid.md."),
    paste(missing, collapse = ", "),
    paste(sort(unique(summ$subspecialty_abbrev)), collapse = ", "),
    paste(wanted, collapse = ", ")), call. = FALSE)
}
summ <- summ[match(wanted, summ$subspecialty_abbrev), ]
stopifnot(!anyNA(summ$subspecialty_abbrev))
write_csv(summ, here::here("data","sensitivity_grid_summary.csv"))

cat("=== #1 multidimensional sensitivity grid (window x rate-mult x conversion) ===\n")
print(as.data.frame(summ), row.names=FALSE)
cat("\nOne-way minima (all should be > 1.05):\n")
print(as.data.frame(summ %>% select(subspecialty_abbrev, oneway_min)), row.names=FALSE)
cat("Wrote cliff/data/sensitivity_grid.csv + sensitivity_grid_summary.csv\n")
