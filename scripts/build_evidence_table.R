#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# data/table_evidence_supporting_scenarios.csv -- keep its quoted numbers derived
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# This table is EDITORIAL: its Scenario/Implementation/Evidence prose is written
# by a human and has no upstream computation, so unlike every other artifact in
# data/ it has no generator and never had one. Searching isochrones history for a
# writer of it returns nothing.
#
# What it does contain is numbers quoted from artifacts, and those had drifted.
# Three copies of this table existed, all different vintages:
#   data/table_evidence_supporting_scenarios.csv
#   scripts/urps_baseline_scenarios/table_evidence_supporting_scenarios.csv
#   scripts/urps_baseline_scenarios/table_evidence_supporting_scenarios.md
# The scripts/ CSV still carried the retired pooled/unpooled pair (4.83 / 5.61)
# after the data/ copy was corrected, and the mortality figure was stale in both.
#
# So this script does not invent the prose. It takes the committed CSV as the
# prose source, re-derives every number the table quotes from the artifact that
# owns it, and writes both CSV copies from that one result, so they cannot
# diverge again. Each substitution must match exactly once; a miss is an error,
# not a silent no-op, because a reworded sentence would otherwise stop being
# checked without anyone noticing.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
suppressPackageStartupMessages({library(here)})

.d <- function(f) here::here("data", f)
OUT_DATA    <- .d("table_evidence_supporting_scenarios.csv")
OUT_SCRIPTS <- here::here("scripts", "urps_baseline_scenarios",
                          "table_evidence_supporting_scenarios.csv")

tbl <- utils::read.csv(OUT_DATA, stringsAsFactors = FALSE, check.names = FALSE)

haz  <- utils::read.csv(.d("hierarchical_hazard_comparison.csv"), stringsAsFactors = FALSE)
mort <- utils::read.csv(.d("mortality_sensitivity.csv"), stringsAsFactors = FALSE)
bench <- utils::read.csv(.d("workforce_projection_benchmark_nrmp.csv"), stringsAsFactors = FALSE)
hv <- function(m) haz[haz$subspecialty_abbrev == "URPS" & haz$method == m, ]
u <- hv("unpooled"); p <- hv("pooled")
stopifnot(nrow(u) == 1L, nrow(p) == 1L)

# pattern -> replacement, each derived from the artifact that owns the number
SUBS <- list(
  # hierarchical pooling comparison
  list("unpooled [0-9.]+ \\[[0-9.-]+\\] vs pooled [0-9.]+ \\[[0-9.-]+\\]",
       sprintf("unpooled %.2f [%.2f-%.2f] vs pooled %.2f [%.2f-%.2f]",
               u$replacement_ratio, u$ci_lo, u$ci_hi,
               p$replacement_ratio, p$ci_lo, p$ci_hi)),
  # events / person-years behind the pooled hazard
  list("[0-9]+ URPS departures / [0-9,]+ person-years",
       sprintf("%d URPS departures / %s person-years",
               as.integer(u$events), format(as.integer(u$person_years), big.mark = ","))),
  # expected mortality added to observed departures
  list("~[0-9.]+ URPS deaths/y",
       sprintf("~%.1f URPS deaths/y",
               mort$expected_mortality_per_yr[mort$subspecialty_abbrev == "URPS"])),
  # NRMP benchmark entrants
  list("NRMP certified-position benchmark \\([0-9]+\\)",
       sprintf("NRMP certified-position benchmark (%d)",
               as.integer(bench$nrmp_entrants[bench$subspecialty_abbrev == "URPS"])))
)

for (s in SUBS) {
  hits <- sum(vapply(tbl, function(col) sum(grepl(s[[1]], col, perl = TRUE)), integer(1)))
  if (hits != 1L)
    stop(sprintf(paste0("[build_evidence_table] pattern matched %d times, expected 1:\n  %s\n",
                        "The prose was reworded; update the pattern so this number ",
                        "keeps being derived."), hits, s[[1]]), call. = FALSE)
  tbl[] <- lapply(tbl, function(col) sub(s[[1]], s[[2]], col, perl = TRUE))
}

utils::write.csv(tbl, OUT_DATA, row.names = FALSE)
utils::write.csv(tbl, OUT_SCRIPTS, row.names = FALSE)
cat("wrote", basename(OUT_DATA), "and the scripts/urps_baseline_scenarios copy\n")
for (s in SUBS) cat("  derived:", s[[2]], "\n")
