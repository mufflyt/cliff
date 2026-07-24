# Fast (no-browser) unit tests for the app's pure model functions. These lock the
# scientific core: the projection, the age-band hazard handling (including the sparse
# 70+ treatment), break-even, the sensitivity grid, the deterministic Monte Carlo,
# and the validation gate. Loaded via helper-load-app.R without launching the app.

test_that("adjusted_haz returns a fully named, non-NA band-hazard vector", {
  e <- load_app_env()
  hz <- e$adjusted_haz("fully_obs", 1, "obs")
  expect_setequal(names(hz), e$BAND_LABELS)
  expect_false(anyNA(hz))
  # every distinct age joins to a hazard by name (the names-stripping regression guard)
  ages <- sort(unique(e$URPS_AGES))
  expect_equal(sum(is.na(hz[e$band_of(ages)])), 0)
})

test_that("the 70+ hazard treatments behave as documented", {
  e <- load_app_env()
  obs   <- e$adjusted_haz("fully_obs", 1, "obs")
  carry <- e$adjusted_haz("fully_obs", 1, "carry")
  pool  <- e$adjusted_haz("fully_obs", 1, "pool")
  expect_equal(unname(obs["70+"]), 0)                       # sparse: no events observed
  expect_equal(unname(carry["70+"]), unname(carry["65-69"])) # carry-forward
  expect_equal(unname(pool["65-69"]), unname(pool["70+"]))   # pooled 65+
  expect_gt(carry["70+"], 0)
})

test_that("the primary projection reproduces the frozen headline numbers", {
  e <- load_app_env()
  r <- e$project_traj(e$URPS_AGES, 64, e$adjusted_haz("fully_obs", 1, "obs"), 4)
  expect_equal(round(r$avg_dep, 1), 12.8)
  expect_equal(round(64 / r$avg_dep, 2), 5.02)
  expect_equal(round(tail(r$traj, 1)), 1544)
  expect_length(r$traj, 5)                                   # baseline + 4 years
})

test_that("the transition ramp defers entry and reproduces the manuscript's ~1,461", {
  e <- load_app_env()
  hz <- e$adjusted_haz("fully_obs", 1, "obs")
  imm  <- e$project_traj(e$URPS_AGES, 64, hz, 4)
  ramp <- e$project_traj(e$URPS_AGES, 64, hz, 4, ramp = e$RAMP_CUM_URPS)
  expect_equal(round(tail(imm$traj, 1)), 1538)              # immediate-entry (partial-pooled primary)
  expect_lt(tail(ramp$traj, 1), tail(imm$traj, 1))          # ramp defers some entry
  expect_lt(abs(tail(ramp$traj, 1) - 1461), 50)             # dynamic ramp vs manuscript deferral method: within a few percent
  expect_equal(e$RAMP_CUM_URPS[1], 0.329)                   # curve pinned to the transition CSV
})

test_that("the Monte Carlo seed matches the manuscript bootstrap", {
  e <- load_app_env()
  expect_equal(e$MC_SEED, 20260718L)
})

test_that("canonical figures load from the manuscript CSVs and match the model", {
  e <- load_app_env()
  expect_equal(e$CANON$source, "graduation_active_transition CSVs")   # SSOT, not the frozen fallback
  expect_equal(e$CANON$baseline, 1339L)
  expect_equal(e$CANON$proj_immediate, 1544)
  expect_equal(e$CANON$proj_ramped, 1466)
  expect_equal(e$RAMP_CUM_URPS, e$CANON$ramp_cum)                     # curve comes from the CSV
  # the live model reproduces the published immediate and transition-adjusted counts
  hz <- e$adjusted_haz("fully_obs", 1, "obs")
  expect_lt(abs(round(tail(e$project_traj(e$URPS_AGES, 64, hz, 4)$traj, 1)) - e$CANON$proj_immediate), 5)
  expect_lt(abs(round(tail(e$project_traj(e$URPS_AGES, 64, hz, 4, ramp = e$RAMP_CUM_URPS)$traj, 1)) - e$CANON$proj_ramped), 0.06 * e$CANON$proj_ramped)
})

test_that("projected departures rise as the cohort ages", {
  e <- load_app_env()
  r <- e$project_traj(e$URPS_AGES, 64, e$adjusted_haz("fully_obs", 1, "obs"), 4)
  expect_true(all(diff(r$dep_yr) > 0))                      # each year > the last
})

test_that("first-year departures do not depend on the projection horizon", {
  e <- load_app_env()
  hz <- e$adjusted_haz("fully_obs", 1, "obs")
  d4 <- e$project_traj(e$URPS_AGES, 64, hz, 4)$dep_yr[1]
  d8 <- e$project_traj(e$URPS_AGES, 64, hz, 8)$dep_yr[1]
  expect_equal(d4, d8)
})

test_that("headcount responds monotonically to each lever", {
  e <- load_app_env()
  H <- function(comp, conv, mult) e$headcount_at(comp, conv, mult, "fully_obs", 0, 34, 4, "obs")
  expect_gt(H(74, 100, 1), H(55, 100, 1))                   # more completions -> larger
  expect_gte(H(64, 100, 1), H(64, 80, 1))                   # higher conversion -> not smaller
  expect_lt(H(64, 100, 2), H(64, 100, 1))                   # higher departure rate -> smaller
})

test_that("break-even departure multiplier is far outside the plausible range at primary", {
  e <- load_app_env()
  be <- e$breakeven_mult("fully_obs", 64, 4, 34, 0, "obs")
  expect_true(is.na(be) || be > 3)                          # ~7x; well past 0.5-3.0x
})

test_that("the sensitivity grid stays above replacement at the primary completions", {
  e <- load_app_env()
  g <- e$sensitivity_surface("fully_obs", 64, 4, 34, 0, "obs")
  expect_equal(nrow(g), 99)                                 # 11 mult x 9 conv
  expect_true(all(g$ratio >= 1))
})

test_that("age_table has non-NA hazards and a sparse 70+ under as-observed", {
  e <- load_app_env()
  at <- e$age_table("fully_obs", 1, "obs")
  expect_false(anyNA(at$hazard))
  expect_equal(at$hazard[at$band == "70+"], 0)              # sparse marker
  expect_equal(round(sum(at$n)), 1339)
})

test_that("run_mc is deterministic under its fixed seed and brackets the point ratio", {
  e <- load_app_env()
  a <- e$run_mc("fully_obs", 1, 1, 4, 34, 0, 200, "obs")
  b <- e$run_mc("fully_obs", 1, 1, 4, 34, 0, 200, "obs")
  expect_identical(a$ratio, b$ratio)                        # same seed -> identical draws
  expect_lt(a$ratio_lo, 5.02)
  expect_gt(a$ratio_hi, 5.02)
})

test_that("validate_model passes with the frozen engine", {
  e <- load_app_env()
  v <- e$validate_model()
  expect_true(v$ok)
  expect_length(v$failures, 0)
})

test_that("an unnamed hazard vector breaks the by-name lookup (regression rationale)", {
  # documents why adjusted_haz must keep names: stripping them makes haz_for fall back
  # to the worst-observed hazard for every age (the 92.8-departures bug).
  e <- load_app_env()
  hz <- e$adjusted_haz("fully_obs", 1, "obs")
  bad <- e$project_traj(e$URPS_AGES, 64, unname(hz), 4)
  good <- e$project_traj(e$URPS_AGES, 64, hz, 4)
  expect_gt(bad$avg_dep, good$avg_dep * 3)                  # fallback inflates departures
})
