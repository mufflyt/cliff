# SSOT guard: the NRMP certified-positions benchmark (URPS 74 / GO 88 / MIGS 51) has ONE
# canonical source (engine WC_ENTRANTS_NRMP). The frozen benchmark CSV that the manuscript
# reads (via get_nrmp_entrants) must match it, and it must stay DISTINCT from the separate
# NRMP filled/appointed counts (URPS 70 / GO 86 / MIGS 47) — an intentional difference.
library(testthat)
library(here)

# Repository integration test: sources R/ or data/ from the SOURCE TREE via
# here(). An installed package has no R/*.R files, so this is inapplicable
# rather than broken there. See helper-cliff-root.R.
skip_if_no_repo()
suppressPackageStartupMessages(library(readr))

ee <- new.env()
suppressPackageStartupMessages(source(here::here("R", "workforce_cliff_engine.R"), local = ee))

NRMP <- ee$WC_ENTRANTS_NRMP

test_that("canonical NRMP benchmark is a named integer vector (74/88/51)", {
  expect_type(NRMP, "integer")
  expect_setequal(names(NRMP), c("URPS", "GO", "MIGS"))
  expect_identical(NRMP[["URPS"]], 74L)
  expect_identical(NRMP[["GO"]],   88L)
  expect_identical(NRMP[["MIGS"]], 51L)
})

test_that("frozen benchmark CSV nrmp_entrants matches the canonical constant (drift guard)", {
  b <- read_csv(here::here("data", "workforce_projection_benchmark_nrmp.csv"), show_col_types = FALSE)
  for (k in names(NRMP)) {
    expect_identical(as.integer(b$nrmp_entrants[b$subspecialty_abbrev == k]), NRMP[[k]],
                     info = paste("benchmark CSV nrmp_entrants drifted from WC_ENTRANTS_NRMP for", k))
  }
})

test_that("certified-positions benchmark stays DISTINCT from NRMP filled counts (intentional difference)", {
  f <- read_csv(here::here("data", "nrmp_fellowship_entrants.csv"), show_col_types = FALSE)
  # 2025 filled/appointed: URPS 70, GO 86 — must NOT be collapsed into the 74/88 benchmark.
  expect_identical(as.integer(f$annual_entrants[f$subspecialty_abbrev == "URPS"]), 70L)
  expect_identical(as.integer(f$annual_entrants[f$subspecialty_abbrev == "GO"]),   86L)
  expect_false(as.integer(f$annual_entrants[f$subspecialty_abbrev == "URPS"]) == NRMP[["URPS"]])  # 70 != 74
  expect_false(as.integer(f$annual_entrants[f$subspecialty_abbrev == "GO"])   == NRMP[["GO"]])    # 86 != 88
})

test_that("[adversarial] engine-sourcing scripts do not re-hardcode the NRMP benchmark", {
  rfiles <- list.files(here::here("scripts"), pattern = "\\.R$", full.names = TRUE)
  offenders <- character()
  for (f in rfiles) {
    ls <- readLines(f, warn = FALSE)
    if (!any(grepl("workforce_cliff_engine\\.R", ls))) next   # standalone scripts: separate documented case
    hit <- grepl("(ENTRANTS_NRMP|NRMP)\\s*<-\\s*c\\(", ls)
    if (any(hit)) offenders <- c(offenders, sprintf("%s:%s", basename(f), paste(which(hit), collapse = ",")))
  }
  expect_equal(offenders, character(0),
               info = paste("NRMP benchmark re-hardcoded in engine-sourcing script(s):", paste(offenders, collapse = "; ")))
})
