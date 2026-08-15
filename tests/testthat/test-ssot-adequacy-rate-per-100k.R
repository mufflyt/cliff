# SSOT guard: the per-100,000-population rate base 1e5 in the adequacy Shiny app (iter47). It was hardcoded twice
# in shiny_urps_adequacy/model.R (per100k_2025, per100k_end) — an un-wired self-contained-app copy of the value
# iter25 canonicalized as R/units.R::RATE_PER_100K (which the active scripts urps_module_a_effective_supply /
# urps_supply_demand_national / urps_module_d_geographic_access already reference). Now one app-local constant
# model.R::RATE_PER_100K drives both uses, parity-guarded against R/units.R.
#
# INTENTIONALLY NOT collapsed (iter25): the identical literal 1e5 used as a read_csv/fread `guess_max` row hint is
# a data-loading parameter, NOT a rate base — this app has no such use, asserted below.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

MODEL <- here::here("shiny_urps_adequacy", "model.R")
src   <- readLines(MODEL, warn = FALSE)

.eval_const <- function(name, lines) {
  hit <- grep(paste0("^\\s*", name, "\\s*<-"), lines, value = TRUE)
  stopifnot(length(hit) == 1L)
  eval(parse(text = sub("#.*$", "", hit)))
}
RATE <- .eval_const("RATE_PER_100K", src)

test_that("the canonical rate base is 1e5 (100,000), well-formed", {
  expect_type(RATE, "double")
  expect_length(RATE, 1L)
  expect_identical(RATE, 1e5)
  expect_gt(RATE, 0)
})

test_that("[cross-lineage parity] the app rate base matches R/units.R::RATE_PER_100K", {
  un <- new.env(); source(here::here("R", "units.R"), local = un)
  expect_identical(RATE, un$RATE_PER_100K)         # the self-contained-app copy must not drift from the SSOT
})

test_that("[adversarial] model.R references the SSOT rate base, not a bare 1e5 multiplier", {
  expect_true(any(grepl("RATE_PER_100K \\* b\\$headcount", src)))
  expect_true(any(grepl("RATE_PER_100K \\* e\\$headcount", src)))
  expect_false(any(grepl("1e5 \\* ", src)))         # no stranded rate literal remains
})

test_that("[intentional difference] the app has no guess_max=1e5 that could be mistaken for the rate base", {
  # iter25 keeps read_csv guess_max hints literal; this app has none, so the only 1e5 is the rate base (now wired).
  expect_false(any(grepl("guess_max\\s*=", src)))    # no guess_max ARGUMENT (matches usage, not this prose)
  expect_false(any(grepl("1e5", src[!grepl("^\\s*#", src) & !grepl("RATE_PER_100K <-", src)])))  # no other live 1e5
})

test_that("[behavior-preserving] the per-100k metric reproduces the prior computation", {
  # a cohort of 605 urogynecologists over 5,000,000 women 65+ -> ~12.1 per 100k, same as 1e5 * n / w.
  expect_equal(RATE * 605 / 5e6, 1e5 * 605 / 5e6)
  expect_equal(round(RATE * 605 / 5e6, 1), 12.1)
})
