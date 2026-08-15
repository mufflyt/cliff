# SSOT guard: the Kirby-2013 / Wu-2011 demand-anchor citation numbers used by the
# demand-denominator sensitivity. They drive the D2/D3 demand curves and are quoted in the
# methods doc; a code<->doc drift would make the analysis and the writeup disagree on cited numbers.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

# Evaluate ONLY the scalar citation-anchor constant lines (not the age-specific rate tribble).
src <- readLines(here::here("scripts", "urps_demand_denominators_sensitivity.R"), warn = FALSE)
const_lines <- grep("^(KIRBY_VISITS_|WU2011_SURG_20)", src, value = TRUE)
ce <- new.env(); eval(parse(text = const_lines), envir = ce)

test_that("citation anchors carry the verified values (Kirby 2013 / Wu 2011)", {
  expect_length(const_lines, 4L)
  expect_identical(ce$KIRBY_VISITS_2010, 1218371L)
  expect_identical(ce$KIRBY_VISITS_2030, 1644804L)
  expect_identical(ce$WU2011_SURG_2010,  376700L)
  expect_identical(ce$WU2011_SURG_2050,  555020L)   # frozen analysis value (see discrepancy below)
})

test_that("Wu 2011 2010 total is the sum of its SUI + POP components", {
  expect_identical(210700L + 166000L, ce$WU2011_SURG_2010)   # 376,700 checks out
})

test_that("the known 2050 arithmetic discrepancy is TRACKED, not silently changed", {
  # Wu's reported components sum to 556,020, but the frozen analysis/doc use 555,020 (a 1,000-off
  # slip). This pins the discrepancy so it is corrected deliberately, not drifted away or hidden.
  expect_identical(310050L + 245970L, 556020L)
  expect_identical(556020L - ce$WU2011_SURG_2050, 1000L)
})

test_that("code<->doc: the methods doc quotes the same anchor numbers as the frozen analysis", {
  doc <- paste(readLines(here::here("URPS_DEMAND_DENOMINATOR_SENSITIVITY.md"), warn = FALSE), collapse = "\n")
  for (v in c("1,218,371", "1,644,804", "376,700", "555,020",
              "210,700", "166,000", "310,050", "245,970")) {
    expect_true(grepl(v, doc, fixed = TRUE), info = paste("methods doc missing anchor:", v))
  }
})

test_that("[adversarial] anchor_index calls reference the named constants, not bare literals", {
  ai <- grep("anchor_index\\(d\\$YEAR", src, value = TRUE)
  expect_false(any(grepl("1218371|1644804|376700|555020", ai)),
               info = "anchor_index still uses a bare literal instead of a named constant")
})
