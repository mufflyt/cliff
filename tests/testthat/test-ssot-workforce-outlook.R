# SSOT guard: the "Workforce Outlook" classification (Adequate / Marginal / Insufficient) of a replacement
# ratio (iter40). Cutpoints RR>=1.2 (Adequate), 0.8<=RR<1.2 (Marginal), RR<0.8 (Insufficient). Previously the
# ONLY site that computed the label did so with bare inline literals (graduate_growth_scenarios.R:46), while the
# same cutpoints are re-stated in the published manuscript table caption and the replacement-ratio appendix math.
# Now canonical in R/workforce_constants.R (WORKFORCE_OUTLOOK_ADEQUATE_MIN / _MARGINAL_MIN + classify_workforce_outlook()).
#
# INTENTIONALLY DISTINCT from the contract's classify_replacement() (Above/At/Below replacement, cuts 0.95/1.05).
# Two separate schemes for two separate tables; this guard must NOT collapse them.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

wc <- new.env(); source(here::here("R", "workforce_constants.R"), local = wc)

test_that("canonical outlook cutpoints are well-formed and ordered", {
  expect_type(wc$WORKFORCE_OUTLOOK_ADEQUATE_MIN, "double")
  expect_type(wc$WORKFORCE_OUTLOOK_MARGINAL_MIN, "double")
  expect_gt(wc$WORKFORCE_OUTLOOK_ADEQUATE_MIN, wc$WORKFORCE_OUTLOOK_MARGINAL_MIN)
  expect_gt(wc$WORKFORCE_OUTLOOK_MARGINAL_MIN, 0)
  expect_identical(wc$WORKFORCE_OUTLOOK_ADEQUATE_MIN, 1.2)   # pin the published cutpoints
  expect_identical(wc$WORKFORCE_OUTLOOK_MARGINAL_MIN, 0.8)
})

test_that("[behavior-preserving] classify_workforce_outlook reproduces the prior inline ifelse exactly", {
  old <- function(ratio) ifelse(ratio >= 1.2, "Adequate", ifelse(ratio >= 0.8, "Marginal", "Insufficient"))
  grid <- c(0, 0.5, 0.79, 0.8, 0.99, 1.0, 1.19, 1.2, 1.61, 5, NA)
  expect_identical(wc$classify_workforce_outlook(grid), old(grid))
})

test_that("[semantic] the bands are correct and boundary-exact (>= is inclusive at each cut)", {
  f <- wc$classify_workforce_outlook
  expect_identical(f(0.79), "Insufficient")
  expect_identical(f(0.80), "Marginal")       # lower cut is inclusive
  expect_identical(f(1.19), "Marginal")
  expect_identical(f(1.20), "Adequate")        # upper cut is inclusive
  # monotone: as the ratio rises the outlook only improves, never regresses
  rank <- c(Insufficient = 1L, Marginal = 2L, Adequate = 3L)
  r <- seq(0, 3, by = 0.05)
  ranks <- rank[f(r)]
  expect_true(all(diff(ranks) >= 0))
})

test_that("[intentional difference] outlook labels are DISJOINT from the contract's replacement scheme", {
  # do not collapse Scheme 2 (Adequate/Marginal/Insufficient) into Scheme 1 (Above/At/Below replacement).
  outlook_labels <- unique(wc$classify_workforce_outlook(c(0.5, 1.0, 1.5)))
  scheme1_labels  <- c("Above replacement", "At replacement", "Below replacement")
  expect_length(intersect(outlook_labels, scheme1_labels), 0L)
})

test_that("[adversarial] graduate_growth_scenarios.R uses the SSOT, not inline 1.2/0.8 literals", {
  ls <- readLines(here::here("scripts", "graduate_growth_scenarios.R"), warn = FALSE)
  expect_true(any(grepl("classify_workforce_outlook\\(", ls)))                       # references the SSOT
  expect_false(any(grepl('ratio\\s*>=\\s*1\\.2.*"Adequate"', ls)))                   # inline classifier gone
  expect_false(any(grepl('ratio\\s*>=\\s*0\\.8.*"Marginal"', ls)))
})

test_that("[cross-doc parity] the published caption + appendix math state the canonical cutpoints", {
  # the manuscript prose/caption stays literal (it is published text) but MUST match the canonical numbers,
  # so a change to the constants that isn't mirrored in the paper is caught here.
  am <- as.character(wc$WORKFORCE_OUTLOOK_ADEQUATE_MIN)   # "1.2"
  mm <- as.character(wc$WORKFORCE_OUTLOOK_MARGINAL_MIN)   # "0.8"
  cap <- grep("Workforce outlook categories",
              readLines(here::here("manuscript", "R", "create_workforce_table.R"), warn = FALSE), value = TRUE)
  expect_length(cap, 1L)
  expect_true(grepl(am, cap, fixed = TRUE) && grepl(mm, cap, fixed = TRUE),
              info = paste("table caption cutpoints drifted from canonical:", cap))
  app <- readLines(here::here("manuscript", "appendix_workforce_replacement_ratio.Rmd"), warn = FALSE)
  adeq_line <- grep("Adequate", app, value = TRUE)
  insf_line <- grep("Insufficient", app, value = TRUE)
  expect_true(any(grepl(am, adeq_line, fixed = TRUE)), info = "appendix Adequate cut drifted from 1.2")
  expect_true(any(grepl(mm, insf_line, fixed = TRUE)), info = "appendix Insufficient cut drifted from 0.8")
})
