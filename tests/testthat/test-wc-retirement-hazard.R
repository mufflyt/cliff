# The retirement-hazard SOURCE seam (R/wc_retirement_hazard.R): the scientific
# rule is that historical exits are OBSERVED in mufflyaccess and future exits are
# SIMULATED in cliff from a hazard calibrated to them. This pins the seam's
# behavior: legacy is byte-identical, observed reads only mufflyaccess and fails
# loud unless retirement is observed, sparse cells pool onto the engine's bands,
# and every run records provenance.
suppressWarnings(suppressMessages(library(testthat)))

repo_root <- function() {
  d <- normalizePath(getwd(), winslash = "/")
  for (i in 1:8) { if (file.exists(file.path(d, "DESCRIPTION"))) return(d)
                   p <- dirname(d); if (identical(p, d)) break; d <- p }
  getwd()
}
ROOT <- repo_root()
source(file.path(ROOT, "R", "wc_retirement_hazard.R"))

# the engine's canonical banding (mirror of workforce_cliff_engine.R constants)
BANDS   <- c(0, 45, 50, 55, 60, 65, 70, Inf)
LABELS  <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
band_of <- function(age) as.character(cut(age, breaks = BANDS, labels = LABELS, right = FALSE))

LEG_EV <- c(13.058, 2.853, 3.508, 4.002, 5.192, 4.388, 0)
LEG_PY <- c(3854, 973, 811, 488, 221, 53, 3)

test_that("legacy_modeled echoes the frozen constants unchanged (byte-identical path)", {
  h <- wc_retirement_hazard("legacy_modeled", band_labels = LABELS, band_of = band_of,
                            legacy_band_ev = LEG_EV, legacy_band_py = LEG_PY)
  expect_identical(h$retirement_source, "legacy_modeled")
  expect_equal(unname(h$band_ev), LEG_EV)
  expect_equal(unname(h$band_py), LEG_PY)
  # hz_point is exactly the prior computation: ifelse(py>0, ev/py, NA), named by band
  expect_equal(h$hz_point, setNames(ifelse(LEG_PY > 0, LEG_EV / LEG_PY, NA_real_), LABELS))
  expect_identical(names(h$hz_point), LABELS)
})

test_that("legacy_modeled requires one ev/py per band", {
  expect_error(wc_retirement_hazard("legacy_modeled", band_labels = LABELS, band_of = band_of,
                                    legacy_band_ev = LEG_EV[-1], legacy_band_py = LEG_PY),
               "one per band")
})

test_that("an unknown source is rejected", {
  expect_error(wc_retirement_hazard("something_else", band_labels = LABELS, band_of = band_of),
               "should be one of|arg")
})

# ---- observed_hazard via injected stubs (no real observed manifest needed) -----

make_stub <- function(status = "observed", hazard = NULL) {
  if (is.null(hazard))
    hazard <- data.frame(
      age = c(44, 47, 52, 57, 62, 67, 72),
      year = 2022L,
      n_at_risk = c(200, 180, 150, 120, 90, 50, 20),
      n_exits   = c(1,   2,   3,   5,   6,   7,  8),
      exit_hazard = NA_real_, hazard_source = "stub")
  list(urps_retirement_status        = function() status,
       urps_exit_hazard_by_age_year   = function() hazard)
}

test_that("observed_hazard fails loud when retirement is not observed (req 2)", {
  expect_error(
    wc_retirement_hazard("observed_hazard", band_labels = LABELS, band_of = band_of,
                         ns = make_stub(status = "not_ascertained")),
    "not 'observed'")
  expect_error(
    wc_retirement_hazard("observed_hazard", band_labels = LABELS, band_of = band_of,
                         ns = make_stub(status = "partially_observed")),
    "not 'observed'")
})

test_that("observed_hazard bands the mufflyaccess risk set onto the engine bands (req 1, 6)", {
  h <- wc_retirement_hazard("observed_hazard", band_labels = LABELS, band_of = band_of,
                            ns = make_stub())
  expect_identical(h$retirement_source, "observed_hazard")
  # each stub age lands in exactly one band; py/ev are the summed risk set there
  expect_equal(unname(h$band_py), c(200, 180, 150, 120, 90, 50, 20))
  expect_equal(unname(h$band_ev), c(1, 2, 3, 5, 6, 7, 8))
  expect_equal(unname(h$hz_point), c(1, 2, 3, 5, 6, 7, 8) / c(200, 180, 150, 120, 90, 50, 20))
  # hazard rises into the older bands (the whole point of an age-based hazard)
  expect_true(h$hz_point[["70+"]] > h$hz_point[["<45"]])
})

test_that("empty bands get py=0 and NA hazard (engine fills with the max)", {
  # a risk set that never populates the 65-69 or 70+ bands
  sparse <- data.frame(age = c(44, 52, 62), year = 2022L,
                       n_at_risk = c(100, 80, 40), n_exits = c(1, 2, 4),
                       exit_hazard = NA_real_, hazard_source = "stub")
  h <- wc_retirement_hazard("observed_hazard", band_labels = LABELS, band_of = band_of,
                            ns = make_stub(hazard = sparse))
  expect_equal(unname(h$band_py[c("45-49","55-59","65-69","70+")]), c(0, 0, 0, 0))
  expect_true(all(is.na(h$hz_point[c("45-49","55-59","65-69","70+")])))
  expect_false(is.na(h$hz_point[["<45"]]))
})

# ---- provenance (req 7) --------------------------------------------------------

test_that("provenance records source, artifact/version/hash, status, window, uncertainty (req 7)", {
  leg <- wc_retirement_hazard("legacy_modeled", band_labels = LABELS, band_of = band_of,
                              legacy_band_ev = LEG_EV, legacy_band_py = LEG_PY)
  obs <- wc_retirement_hazard("observed_hazard", band_labels = LABELS, band_of = band_of,
                              ns = make_stub(), confirmation_window_months = 12L)
  for (p in list(leg$provenance, obs$provenance)) {
    expect_true(all(c("retirement_source", "hazard_artifact", "hazard_version",
                      "hazard_hash", "ascertainment_status", "confirmation_window_months",
                      "uncertainty_method") %in% names(p)))
    # the uncertainty method names the drawn Beta posterior -- NOT a fixed point (no cv=0)
    expect_match(p$uncertainty_method, "Beta", ignore.case = TRUE)
  }
  expect_identical(obs$provenance$ascertainment_status, "observed")
  expect_identical(obs$provenance$confirmation_window_months, 12L)
  # distinct sources hash to distinct provenance (can't be mistaken for each other)
  expect_false(identical(leg$provenance$hazard_hash, obs$provenance$hazard_hash))
})
