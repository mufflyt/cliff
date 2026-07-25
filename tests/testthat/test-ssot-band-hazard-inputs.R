# SSOT guard: the per-band hazard INPUTS BAND_EV / BAND_PY (iter38) — the event-count numerators and
# person-year denominators of the URPS departure hazard, the highest-stakes numbers in the supply projection.
# They are defined identically in TWO self-contained Shiny snapshots (shiny_urps_scenarios/urps_model_data.R and
# shiny_urps_adequacy/data/urps_model_data.R) and consumed from whichever snapshot each script sources. Because
# both snapshots must deploy standalone (no repo-root source on shinyapps.io), no shared code home is possible —
# so the SSOT mechanism here is a DRIFT GUARD, not a copy removal: the two snapshots must agree with each other
# and, for the manuscript-primary window, with the frozen hazard artifact that is their true origin.
#
# INTENTIONALLY NOT collapsed: the three observation windows differ by design —
#   fully_obs = URPS-specific HIERARCHICAL PARTIAL-POOLED expected events (non-integer, penalized; manuscript
#               primary), with person-years == the frozen CSV's urps_py column;
#   drop2 / full = RAW integer event/person-year counts under alternative observation windows.
# Collapsing them would destroy the pooled-vs-raw distinction.
library(testthat)
library(here)

sc <- new.env(); source(here::here("shiny_urps_scenarios", "urps_model_data.R"), local = sc)
ad <- new.env(); source(here::here("shiny_urps_adequacy", "data", "urps_model_data.R"), local = ad)

test_that("[cross-snapshot parity] the two Shiny snapshots define identical BAND_EV / BAND_PY (all windows)", {
  expect_identical(sc$BAND_EV, ad$BAND_EV)          # a drift between the two apps would show different hazards
  expect_identical(sc$BAND_PY, ad$BAND_PY)
})

test_that("[structure] BAND_EV / BAND_PY share window names and are one value per age band", {
  expect_identical(names(sc$BAND_EV), names(sc$BAND_PY))
  expect_setequal(names(sc$BAND_EV), c("fully_obs", "drop2", "full"))
  n <- length(sc$BAND_LABELS)
  expect_true(all(lengths(sc$BAND_EV) == n))
  expect_true(all(lengths(sc$BAND_PY) == n))
})

test_that("[cross-artifact origin] BAND_PY[fully_obs] equals the frozen hazard CSV's urps_py column, in order", {
  csv <- read.csv(here::here("data", "hazard_by_band_pooled_vs_unpooled.csv"), stringsAsFactors = FALSE)
  # the CSV band order must match the model's band order for the comparison to be meaningful
  expect_identical(as.character(csv$band), sc$BAND_LABELS)
  expect_identical(as.numeric(sc$BAND_PY[["fully_obs"]]), as.numeric(csv$urps_py))
})

test_that("[intentional differences preserved] fully_obs EV is pooled (non-integer); full EV is raw counts", {
  fo <- sc$BAND_EV[["fully_obs"]]; fu <- sc$BAND_EV[["full"]]
  expect_false(isTRUE(all.equal(fo, round(fo))))    # partial-pooled expected events are NOT whole numbers
  expect_true(isTRUE(all.equal(fu, round(fu))))     # the raw window IS integer counts
  expect_false(isTRUE(all.equal(fo, fu)))           # the two windows are genuinely different, not copies
})

test_that("[semantic] the derived fully_obs hazard is well-formed and rises through the working-age tail", {
  ev <- sc$BAND_EV[["fully_obs"]]; py <- sc$BAND_PY[["fully_obs"]]
  haz <- ifelse(py > 0, ev / py, NA_real_)
  expect_true(all(haz[py > 0] >= 0))                       # hazards are non-negative rates
  expect_true(all(ev[py > 0] <= py[py > 0]))               # events cannot exceed exposure
  # HAZ_WINDOWS (the snapshot's own derived hazard) must equal EV/PY — the derivation is not a separate copy
  expect_equal(unname(sc$HAZ_WINDOWS[["fully_obs"]]), haz)
  # retirement risk climbs from the late-40s band into the late-60s band (60-64/65-69 > 55-59 > 45-49)
  labs <- sc$BAND_LABELS
  expect_gt(haz[match("65-69", labs)], haz[match("55-59", labs)])
  expect_gt(haz[match("55-59", labs)], haz[match("45-49", labs)])
})

test_that("[adversarial] neither snapshot silently drops or reorders a window between EV and PY", {
  for (e in list(sc, ad)) {
    expect_identical(names(e$BAND_EV), names(e$BAND_PY))    # same windows, same order in EV and PY
    # every window that has zero exposure in the oldest band also has zero events there (no phantom hazard)
    for (w in names(e$BAND_PY)) {
      zero_py <- e$BAND_PY[[w]] == 0
      expect_true(all(e$BAND_EV[[w]][zero_py] == 0), info = paste("window", w))
    }
  }
})
