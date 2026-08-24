# Guards data/ against silent CSV truncation (#33).
#
# Five files were recorded as "malformed". They are not: all five are valid
# RFC-4180 and parse cleanly with read.csv() and readr. The real defect is the
# reader. utils::read.table() defaults to quote = "\"'", so a lone apostrophe
# opens a quoted string and everything up to the next apostrophe is swallowed:
#
#   abog_all_urps_2026-07-22.csv          1135 rows -> 938   (O'SHAUGHNESSY, O'LEARY, O'NEIL)
#   abu_all_urps_ENRICHED_2026-07-22.csv   365 rows -> 163   (apostrophe + embedded newline)
#
# That is a ~17% and ~55% silent row loss behind a warning, which is worse than
# a hard parse error. These tests pin the true dimensions so any regression --
# a corrupted file, or a consumer switching to a quote-naive parser -- fails
# loudly instead of quietly analysing a subset of the cohort.
suppressWarnings(suppressMessages(library(testthat)))

skip_if_no_repo()

data_path <- function(...) testthat::test_path("..", "..", "data", ...)

# Exact dimensions, read with a correct parser.
CSV_CONTRACT <- list(
  "urps_module_bc_FROZEN_provenance_2026-07-23.csv"  = c(rows = 3L,    cols = 10L),
  "urps_module_bc_corrected_summary_2026-07-23.csv"  = c(rows = 4L,    cols = 19L),
  "urps_module_bc_scenario_params_2026-07-23.csv"    = c(rows = 2L,    cols = 4L),
  "abog_all_urps_2026-07-22.csv"                     = c(rows = 1135L, cols = 6L),
  "abu_all_urps_ENRICHED_2026-07-22.csv"             = c(rows = 365L,  cols = 81L)
)

test_that("the five files reported as malformed are in fact valid CSV", {
  for (f in names(CSV_CONTRACT)) {
    p <- data_path(f)
    skip_if_not(file.exists(p), paste("absent:", f))
    expect_error(utils::read.csv(p, check.names = FALSE), NA, info = f)
  }
})

test_that("each parses to its recorded dimensions", {
  for (f in names(CSV_CONTRACT)) {
    p <- data_path(f)
    skip_if_not(file.exists(p), paste("absent:", f))
    d <- suppressWarnings(readr::read_csv(p, show_col_types = FALSE, progress = FALSE))
    expect_identical(nrow(d), unname(CSV_CONTRACT[[f]]["rows"]), info = paste(f, "rows"))
    expect_identical(ncol(d), unname(CSV_CONTRACT[[f]]["cols"]), info = paste(f, "cols"))
  }
})

test_that("apostrophes in surnames do not truncate the ABOG roster", {
  # The specific regression: read.table() would stop at O'SHAUGHNESSY.
  p <- data_path("abog_all_urps_2026-07-22.csv")
  skip_if_not(file.exists(p), "absent")
  d <- utils::read.csv(p, check.names = FALSE)
  expect_identical(nrow(d), 1135L)
  expect_true(any(grepl("'", d[[3]], fixed = TRUE)))   # the apostrophes are still there
  # and a quote-naive read really does lose rows, which is why this guard exists
  naive <- suppressWarnings(utils::read.table(p, header = TRUE, sep = ","))
  expect_lt(nrow(naive), nrow(d))
})

test_that("every CSV in data/ is parseable, so none is silently unreadable", {
  files <- list.files(data_path(), pattern = "[.]csv$", full.names = TRUE)
  skip_if(length(files) == 0, "no CSVs found")
  bad <- character()
  for (p in files) {
    ok <- tryCatch({ utils::read.csv(p, nrows = 5, check.names = FALSE); TRUE },
                   error = function(e) FALSE)
    if (!ok) bad <- c(bad, basename(p))
  }
  expect_identical(bad, character(0))
})
