#!/usr/bin/env Rscript
# ==============================================================================
# safe_divide.R -- SSOT SHIM.
# The safe-division family (safe_divide, safe_divide_manu, safe_pct_manu,
# safe_percent, safe_rate, safe_ratio) was promoted VERBATIM to the shared
# mufflyaccess package (single source of truth across isochrones / cliff). This
# file now loads the package so the consumers that source() it
# (R/calculate_retirement_cliff_statistics.R and the test suite) keep working;
# no local definition remains, so cross-repo drift is impossible.
#
# BEHAVIOR-PRESERVED: all six functions verified byte-for-byte identical to the
# package before replacement (deparse(body(.)) match).
#   install: renv::install("mufflyt/mufflyaccess")   # pin >= 0.1.4
# ==============================================================================
if (!requireNamespace("mufflyaccess", quietly = TRUE))
  stop("Package 'mufflyaccess' is required. Install: renv::install(\"mufflyt/mufflyaccess\").",
       call. = FALSE)
suppressPackageStartupMessages(library(mufflyaccess))
