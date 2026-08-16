# shinytest2 (AppDriver) tests for the Urogynecology Workforce Replacement Explorer.
#
# These launch the real app in headless Chrome (via chromote), so they exercise the
# things testServer() cannot: that the app boots past the model-validation gate,
# that the rendered cards show the frozen headline numbers, that scenarios recompute
# live, and that a manual edit flips the Scenario selector to "Custom" (the
# updateSelectInput echo that testServer does not simulate).
#
# Value assertions only (no image snapshots), so they are portable across machines.
#
# Expected numbers are DERIVED FROM THE SSOT via the app's own CANON, never
# written as literals. The previous literals -- 1,339 baseline, 1,544 projected,
# ratio "5.0 to 1" -- were on the retired roster basis and kept asserting
# themselves long after the app moved to the 1,306 projection cohort.
.ssot <- local({
  e <- load_app_env()
  fmt <- function(x) formatC(round(x), format = "d", big.mark = ",")
  list(baseline   = fmt(e$CANON$baseline),
       immediate  = fmt(e$CANON$proj_immediate),
       ramped     = fmt(e$CANON$proj_ramped),
       ratio_txt  = sprintf("%.1f to 1", round(e$CANON$ratio, 1)),
       net_gain   = round((e$CANON$proj_immediate - e$CANON$baseline) / 4),
       top_band_n = as.character(round(e$age_table("fully_obs", 1, "obs")$n[1])))
})
# Created: 2026-07-21

library(shinytest2)
# new_app() is defined in helper-load-app.R

test_that("app boots past the validation gate and shows the baseline", {
  app <- new_app("boot")
  on.exit(app$stop(), add = TRUE)

  body <- app$get_html("body")
  expect_false(grepl("Model validation failed", body),
               info = "The model-validation gate should pass with the frozen engine.")

  cards <- app$get_html("#exec_cards")
  expect_true(grepl(.ssot$baseline, cards, fixed = TRUE))
  expect_true(grepl("estimated active headcount in 2025", cards))
  expect_true(grepl("ENTER PRACTICE", cards))
  # the readability pass removed "specialists"
  expect_false(grepl("specialists", cards))
})

test_that("Best estimate shows the frozen headline numbers", {
  app <- new_app("best-estimate")
  on.exit(app$stop(), add = TRUE)

  cards <- app$get_html("#exec_cards")
  expect_true(grepl(.ssot$immediate, cards, fixed = TRUE))   # projected 2029 headcount
  expect_true(grepl("projected active headcount in 2029", cards))
  expect_true(grepl(sprintf("Net gain: about .%d per year", .ssot$net_gain), cards))
  expect_true(grepl("ENTER PRACTICE", cards) && grepl("AVERAGE LEAVING", cards))
  expect_true(grepl(paste("Headcount replacement ratio:", .ssot$ratio_txt), cards, fixed = TRUE))
  expect_false(grepl(.ssot$ramped, cards, fixed = TRUE))     # ramp figure not on the headline

  verdict <- app$get_html("#verdict")
  expect_true(grepl("Bottom line: Yes", verdict))
  expect_true(grepl("adequate access to care", verdict))     # access caveat present
})

test_that("a severe stress scenario recomputes the cards and verdict", {
  app <- new_app("severe")
  on.exit(app$stop(), add = TRUE)

  # set the model inputs directly (the severe-preset values) and let the reactive
  # graph settle, rather than relying on the preset -> slider echo cascade.
  app$set_inputs(comp = 55, conv = 70, mult = 2.0, win = "full", mort = 100)
  app$wait_for_idle(duration = 500)

  cards <- app$get_html("#exec_cards")
  verdict <- app$get_html("#verdict")
  # under the severe combination the pipeline no longer clearly out-replaces losses
  expect_false(grepl(.ssot$immediate, cards, fixed = TRUE))
  expect_false(grepl("Bottom line: Yes", verdict))
})

test_that("a manual edit flips the Scenario selector to Custom", {
  app <- new_app("custom-flip")
  on.exit(app$stop(), add = TRUE)

  expect_equal(app$get_value(input = "preset"), "Best estimate")

  app$set_inputs(comp = 50)                                  # differs from the preset (64)
  # the edit-observer calls updateSelectInput; wait for that echo to land
  app$wait_for_value(input = "preset", ignore = list("Best estimate"), timeout = 15000)
  expect_equal(app$get_value(input = "preset"), "Custom scenario")

  app$wait_for_idle(duration = 500)
  expect_true(grepl("Custom", app$get_html("#scenario_status")),
              info = "Editing a control off the preset should flip the selector to Custom.")
})

test_that("the age table rounds counts and flags the sparse 70+ estimate", {
  app <- new_app("age-table")
  on.exit(app$stop(), add = TRUE)

  app$set_inputs(tabs = "Explore the model")
  tbl <- app$get_html("#agetab")
  expect_true(grepl("Number of urogynecologists", tbl))
  # The point of this test is ROUNDING, not any particular count, so assert the
  # property rather than a number. A specific count is exactly the kind of
  # literal that went stale when the cohort moved from 1,339 to 1,306, and it
  # tells you nothing about whether the table rounds.
  expect_false(grepl("[0-9][.][0-9]{2}\\s*<", tbl),
               info = "headcounts should render as integers, not 2-decimal numbers")
  expect_true(grepl("[>\\s]([0-9]{2,3}|1,[0-9]{3})\\s*<", tbl),
              info = "the table should show integer headcounts")
  # the 70+ group has no observed departures -> not shown as a precise 0
  expect_true(grepl("Not reliably estimated", tbl))
  expect_false(grepl(">\\s*0[.]0%\\s*<", tbl))
})
