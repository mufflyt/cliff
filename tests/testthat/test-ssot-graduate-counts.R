# SSOT guard: the ACGME fellowship graduate counts have ONE canonical source
# (engine WC_GRAD). Annual entrants are derived means of it; the frozen SSOT and the
# self-contained Shiny copy must agree; engine-sourcing scripts must not re-hardcode it.
library(testthat)
library(here)
suppressPackageStartupMessages(library(readr))

ee <- new.env()
suppressPackageStartupMessages(source(here::here("R", "workforce_cliff_engine.R"), local = ee))
GRAD <- ee$WC_GRAD

test_that("WC_GRAD is the ACGME graduate-count source (named list, 4 years each)", {
  expect_setequal(names(GRAD), c("GO", "URPS", "MIGS"))
  expect_identical(GRAD$URPS, c(61, 66, 63, 66))
  expect_identical(GRAD$GO,   c(70, 73, 78, 79))
  expect_identical(GRAD$MIGS, c(47, 50, 45, 47))
  for (g in GRAD) expect_length(g, 4L)
})

test_that("engine WC_ENTRANTS is the mean of WC_GRAD (derived, not an independent value)", {
  expect_equal(ee$WC_ENTRANTS, sapply(GRAD, mean))
})

test_that("frozen SSOT annual_entrants matches the WC_GRAD graduate means (drift guard)", {
  s  <- read_csv(here::here("data", "workforce_projections_consolidated.csv"), show_col_types = FALSE)
  ae <- setNames(s$annual_entrants, s$subspecialty_abbrev)
  expect_equal(ae[["URPS"]], mean(GRAD$URPS))          # 64 (exact)
  expect_equal(ae[["GO"]],   mean(GRAD$GO))            # 75 (exact)
  expect_equal(ae[["MIGS"]], round(mean(GRAD$MIGS)))   # 47.25 -> 47
})

test_that("Shiny GRAD_URPS (self-contained deployment copy) matches canonical WC_GRAD$URPS", {
  se <- new.env(); source(here::here("shiny_urps_scenarios", "urps_model_data.R"), local = se)
  expect_identical(se$GRAD_URPS, GRAD$URPS)
})

test_that("[adversarial] no engine-sourcing script re-hardcodes WC_GRAD as a list literal", {
  rfiles <- list.files(here::here("scripts"), pattern = "\\.R$", full.names = TRUE)
  offenders <- character()
  for (f in rfiles) {
    ls <- readLines(f, warn = FALSE)
    if (!any(grepl("workforce_cliff_engine\\.R", ls))) next
    hit <- grepl("GRAD\\s*<-\\s*list\\(", ls)
    if (any(hit)) offenders <- c(offenders, sprintf("%s:%s", basename(f), paste(which(hit), collapse = ",")))
  }
  expect_equal(offenders, character(0),
               info = paste("WC_GRAD re-hardcoded in engine-sourcing script(s):", paste(offenders, collapse = "; ")))
})
