# SSOT guard: the PRIMARY pooled subspecialties (GO + URPS, MIGS excluded), canonical as
# R/workforce_cliff_engine.R::WC_PRIMARY. The sibling scripts alias PRIMARY <- WC_PRIMARY, but
# build_hazard_comparison.R hardcoded c("GO","URPS") for both the pool filter and the rate_tbl label; both
# now derive from PRIMARY. (The rate_tbl value columns are hardcoded GO-then-URPS, guarded by a fail-loud
# identical() assertion so the labels can derive from PRIMARY without misaligning the values.)
library(testthat)
library(here)

ee <- new.env()
ok <- tryCatch({ suppressMessages(suppressWarnings(source(here::here("R", "workforce_cliff_engine.R"), local = ee))); TRUE },
               error = function(e) FALSE)

test_that("WC_PRIMARY is the GO+URPS primary pool (MIGS excluded)", {
  skip_if_not(ok, "engine could not be sourced")
  expect_identical(ee$WC_PRIMARY, c("GO", "URPS"))
  expect_false("MIGS" %in% ee$WC_PRIMARY)   # MIGS is the sensitivity pool, not primary
})

test_that("[behavior-preserving] filtering %in% WC_PRIMARY selects the same rows as %in% c('GO','URPS')", {
  skip_if_not(ok, "engine could not be sourced")
  ab <- c("GO", "URPS", "MIGS", "GO")
  expect_identical(ab %in% ee$WC_PRIMARY, ab %in% c("GO", "URPS"))
})

test_that("[adversarial] build_hazard_comparison derives the pair from PRIMARY, not literals", {
  ls <- readLines(here::here("scripts", "build_hazard_comparison.R"), warn = FALSE)
  expect_true(any(grepl("PRIMARY\\s*<-\\s*WC_PRIMARY", ls)))          # aliases the SSOT
  expect_true(any(grepl("%in%\\s*PRIMARY", ls)))                      # pool filter uses it
  expect_true(any(grepl("subspecialty_abbrev\\s*=\\s*PRIMARY", ls)))  # rate_tbl label uses it
  expect_false(any(grepl("%in%\\s*c\\(\"GO\",\"URPS\"\\)", ls)))      # the literal filter is gone
  expect_false(any(grepl("subspecialty_abbrev\\s*=\\s*c\\(\"GO\",\"URPS\"\\)", ls)))  # literal label gone
})

test_that("[consistency] the sibling hazard/graduate scripts also alias PRIMARY <- WC_PRIMARY", {
  for (b in c("hierarchical_hazard_partial_pooling.R", "graduate_growth_scenarios.R")) {
    ls <- readLines(here::here("scripts", b), warn = FALSE)
    expect_true(any(grepl("PRIMARY\\s*<-\\s*WC_PRIMARY", ls)), info = b)
  }
})
