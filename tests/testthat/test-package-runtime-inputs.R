# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# What the INSTALLED package needs at runtime.
#
# data/ is excluded from the build (.Rbuildignore ^data$), on the evidence that
# nothing in the installed package needs it. That evidence has to stay true, so
# this file pins it: if someone adds a package-code read of data/, the exclusion
# silently breaks the installed package, and this test fails first.
#
# The classification behind the exclusion, from scanning all 96 CSVs by consumer:
#
#   read by R/ (package code)          1   departure_anchor.csv
#   read by manuscript/ or the apps   39   neither is installed
#   read by scripts/ or code/         40   pipeline material
#   read only by tests                 4   fixtures for repository tests
#   unreferenced                      11
#
# The single package-code read lives in wc_load_cohort(), which cannot run from
# an installed package in any case: its primary input, WC_COHORT_CSV, resolves
# through wc_path() into the isochrones monorepo, outside this repository. It
# also takes here_fn as a parameter, so a caller with the files can inject a
# resolver. Shipping departure_anchor.csv alone would not make it work.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
library(testthat)

.pkg_r_files <- function(root) {
  list.files(file.path(root, "R"), pattern = "[.]R$", recursive = TRUE, full.names = TRUE)
}

# Reads of data/ that appear in PACKAGE code, ignoring comments.
.data_reads_in_R <- function(root) {
  fs <- .pkg_r_files(root)
  out <- character(0)
  for (f in fs) {
    for (ln in readLines(f, warn = FALSE)) {
      if (grepl("^\\s*#", ln)) next
      if (!grepl("(read[._]csv|fread|read\\.table|readRDS)\\s*\\(", ln, perl = TRUE)) next
      if (!grepl('"data"|"data/', ln, perl = TRUE)) next
      m <- regmatches(ln, regexpr('"[A-Za-z0-9_./\\-]+\\.csv"', ln, perl = TRUE))
      out <- c(out, sprintf("%s: %s", basename(f), if (length(m)) gsub('"', "", m) else trimws(ln)))
    }
  }
  sort(unique(out))
}

test_that("package code reads exactly the known set of data/ files", {
  skip_if_no_repo()
  root <- cliff_repo_root()
  found <- .data_reads_in_R(root)

  # Adding one means either shipping the file under inst/extdata and reading it
  # with system.file(), or giving the caller an injectable path as
  # wc_load_cohort() does. It does NOT mean widening this list without thought:
  # data/ is not in the built package, so such a read fails once installed.
  expected <- "workforce_cliff_engine.R: departure_anchor.csv"
  expect_equal(found, expected)
})

test_that("data/ is excluded from the build", {
  skip_if_no_repo()
  ig <- readLines(file.path(cliff_repo_root(), ".Rbuildignore"), warn = FALSE)
  expect_true("^data$" %in% ig)
})

test_that("wc_load_cohort still exposes an injectable path resolver", {
  skip_if_no_repo()
  skip_if_not(exists("wc_load_cohort"), "engine not loaded")
  # here_fn is the seam that lets a caller who DOES have the files supply a
  # resolver. If it disappears, the function becomes unusable outside a checkout
  # and the reasoning above stops holding.
  expect_true("here_fn" %in% names(formals(wc_load_cohort)))
})
