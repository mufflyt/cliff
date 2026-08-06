# Gate for the URPS projection producer (scripts/urps_projection/build_urps_projection.R):
# the committed artifact must conform to the mufflyaccess projection contract, tie
# to the served 2023 count, move each lever the right way, and be reproducible.
suppressWarnings(suppressMessages(library(testthat)))

repo_root <- function() {
  d <- normalizePath(getwd(), winslash = "/")
  for (i in 1:8) { if (file.exists(file.path(d, "DESCRIPTION"))) return(d)
                   p <- dirname(d); if (identical(p, d)) break; d <- p }
  getwd()
}
ROOT    <- repo_root()
out_csv <- file.path(ROOT, "scripts", "urps_projection", "urps_projection_2023_2040_v1.csv")
builder <- file.path(ROOT, "scripts", "urps_projection", "build_urps_projection.R")

skip_if_not(requireNamespace("mufflyaccess", quietly = TRUE), "mufflyaccess not installed")
skip_if_not(utils::packageVersion("mufflyaccess") >= "0.10.0", "mufflyaccess < 0.10.0 (no projection contract)")
skip_if_not(file.exists(out_csv), "projection artifact not built")

d <- utils::read.csv(out_csv, stringsAsFactors = FALSE)

test_that("the committed projection conforms to the contract and ties to urps_count(2023)", {
  expect_true(mufflyaccess::validate_urps_projection(d, baseline_tie = list(
    year = 2023, measure = "board_certified_active",
    geography_type = "national", certification_pathway = "ABOG_PLUS_ABU")))
})

test_that("shape: executable scenarios x 2023-2040, national ABOG_PLUS_ABU", {
  expect_setequal(unique(d$year), 2023:2040)
  expect_identical(unique(d$certification_pathway), "ABOG_PLUS_ABU")
  expect_identical(unique(d$geography_type), "national")
  # exactly the executable (non-demand) scenarios -- supply + FTE levers, not demand
  sc <- mufflyaccess::urps_scenarios()
  exec <- sc$scenario_id[!sc$requires_demand_model]
  expect_setequal(unique(d$scenario_id), exec)
  expect_true(all(c("lower_late_career_fte", "combined_pessimistic") %in% d$scenario_id))
})

test_that("clinical FTE is populated, non-negative, and never exceeds headcount", {
  expect_true(all(!is.na(d$supply_clinical_fte)))
  expect_true(all(d$supply_clinical_fte >= 0))
  expect_true(all(d$supply_clinical_fte <= d$supply_headcount + 1e-9))
  # the current age/pathway mix (age-productivity x ABU 0.70) discounts FTE below headcount
  b2023 <- d[d$scenario_id == "baseline" & d$year == 2023, ]
  expect_lt(b2023$supply_clinical_fte, b2023$supply_headcount)
})

test_that("the late-career FTE lever lowers FTE without changing headcount", {
  yr <- 2040
  base <- d[d$scenario_id == "baseline" & d$year == yr, ]
  lcf  <- d[d$scenario_id == "lower_late_career_fte" & d$year == yr, ]
  expect_equal(lcf$supply_headcount, base$supply_headcount)   # headcount unaffected
  expect_lt(lcf$supply_clinical_fte, base$supply_clinical_fte) # clinical FTE reduced
})

test_that("Monte Carlo intervals: NA at the index year, present and bracketing after", {
  idx <- d[d$year == 2023, ]
  fwd <- d[d$year >  2023, ]
  expect_true(all(is.na(idx$lower_95)) && all(is.na(idx$upper_95)))    # index year: point only
  expect_true(all(!is.na(fwd$lower_95)) && all(!is.na(fwd$upper_95)))  # forward: interval present
  # the deterministic point sits inside the 95% interval everywhere
  expect_true(all(fwd$lower_95 <= fwd$supply_headcount &
                  fwd$supply_headcount <= fwd$upper_95))
})

test_that("interval width grows with the forecast horizon", {
  b <- d[d$scenario_id == "baseline" & d$year > 2023, ]
  b <- b[order(b$year), ]
  w <- b$upper_95 - b$lower_95
  # not strictly monotone draw-to-draw, but the late-horizon band is much wider
  expect_gt(mean(utils::tail(w, 3)), 3 * mean(utils::head(w, 3)))
  expect_true(w[length(w)] > w[1])
})

test_that("every scenario starts at the SSOT 1306 in 2023", {
  s2023 <- d[d$year == 2023, ]
  expect_true(all(s2023$supply_headcount ==
                  mufflyaccess::urps_count(2023, "board_certified_active", "national", TRUE)))
})

test_that("the levers move supply the right way at the 2040 endpoint", {
  end <- setNames(d$supply_headcount[d$year == 2040], d$scenario_id[d$year == 2040])
  # retirement: earlier exit -> fewer; later -> more
  expect_lt(end[["retire_5yr_earlier"]], end[["retire_2yr_earlier"]])
  expect_lt(end[["retire_2yr_earlier"]], end[["baseline"]])
  expect_lt(end[["baseline"]], end[["retire_2yr_later"]])
  # entry: constrained -> fewer; +10% -> more
  expect_lt(end[["fellowship_constrained"]], end[["baseline"]])
  expect_lt(end[["baseline"]], end[["fellowship_plus_10pct"]])
  # combined investment (later retirement AND +10% entrants) is the most favourable
  expect_equal(unname(end[["combined_investment"]]), unname(max(end)))
})

test_that("re-running the builder reproduces the committed artifact (deterministic)", {
  # the full 2000-draw MC rebuild is ~75s; opt in with CLIFF_SLOW_TESTS=1
  skip_if(!nzchar(Sys.getenv("CLIFF_SLOW_TESTS")),
          "slow: set CLIFF_SLOW_TESTS=1 to re-run the 2000-draw builder")
  skip_if_not(file.exists(builder), "builder script not present")
  before <- readLines(out_csv)
  invisible(utils::capture.output(source(builder, local = new.env())))  # rewrites out_csv
  expect_identical(readLines(out_csv), before)   # set.seed + pure inputs -> byte-identical
})
