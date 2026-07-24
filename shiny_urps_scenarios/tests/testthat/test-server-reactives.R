# Fast (no-browser) reactive tests via shiny::testServer on the app's main_server.
# These cover card/verdict/story wording and values, the conditional replacement
# card, dynamic badges, scenario status, the reset observer, and the CSV export,
# without launching a browser. Loaded via helper-load-app.R.

set_best_estimate <- function(session) do.call(session$setInputs, best_estimate_inputs())

test_that("model() reproduces the headline under Best estimate", {
  e <- load_app_env()
  shiny::testServer(e$main_server, {
    set_best_estimate(session)
    m <- model()
    expect_equal(round(m$avg_dep, 1), 12.8)
    expect_equal(round(m$ratio, 2), 5.02)
    expect_equal(round(m$proj), 1538)
  })
})

test_that("the executive flow visual shows enter/leave/net and supporting counts", {
  e <- load_app_env()
  shiny::testServer(e$main_server, {
    set_best_estimate(session)
    ec <- output$exec_cards$html
    expect_true(grepl("ENTER PRACTICE", ec))
    expect_true(grepl("AVERAGE LEAVING", ec))                 # departures are an average, not a constant
    expect_true(grepl("rises from about", ec))                # note that departures climb as the cohort ages
    expect_true(grepl(">64</div>", ec))                       # enter value in the bar
    expect_true(grepl(">13</div>", ec))                       # leave value in the bar
    expect_true(grepl("Net gain: about \\+51 per year", ec))
    expect_true(grepl("1,339", ec) && grepl("estimated active headcount in 2025", ec))
    expect_true(grepl("1,544", ec) && grepl("projected active headcount in 2029", ec))
    expect_true(grepl("Headcount replacement ratio: 5.0 to 1", ec))
    expect_false(grepl("specialists", ec))
    expect_false(grepl("1,466", ec))                          # ramp figure moved to Research details
    expect_false(grepl("gradual ramp-up", ec))
  })
})

test_that("the ramp-adjusted 1,461 estimate lives in Research details, not the headline", {
  e <- load_app_env()
  shiny::testServer(e$main_server, {
    set_best_estimate(session)
    expect_false(grepl("1,466", output$exec_cards$html))       # not on the primary card
    expect_true(grepl("1,466", output$assumptions$html))       # present as a labeled sensitivity
    expect_true(grepl("Ramp-up-adjusted 2029 estimate", output$assumptions$html))
  })
})

test_that("the model reports both the immediate and transition-adjusted 2029 counts", {
  e <- load_app_env()
  shiny::testServer(e$main_server, {
    set_best_estimate(session)
    m <- model()
    expect_equal(round(m$proj), 1538)                       # immediate-entry
    expect_lt(abs(m$proj_ramped - 1466), 5)                 # transition-adjusted (manuscript)
    expect_lt(m$proj_ramped, m$proj)
  })
})

test_that("the verdict states Yes with the access caveat under Best estimate", {
  e <- load_app_env()
  shiny::testServer(e$main_server, {
    set_best_estimate(session)
    v <- output$verdict$html
    expect_true(grepl("Bottom line: Yes", v))
    expect_true(grepl("adequate access to care", v))
  })
})

test_that("the replacement card falls below 1-to-1 under a severe scenario", {
  e <- load_app_env()
  shiny::testServer(e$main_server, {
    set_best_estimate(session)
    session$setInputs(comp = 55, conv = 70, mult = 2.0, win = "full", mort = 100)
    m <- model()
    expect_lt(m$ratio, 1)
    expect_false(grepl("Bottom line: Yes", output$verdict$html))
  })
})

test_that("story cards show the baseline, flows, and the all-99 message", {
  e <- load_app_env()
  shiny::testServer(e$main_server, {
    set_best_estimate(session)
    expect_true(grepl("1,339", output$story1$html))
    expect_true(grepl("64", output$story2$html))
    expect_true(grepl("12.8", output$story2$html))
    # the robustness card reports the fixed prespecified grid, not the current scenario
    expect_true(grepl("99 of 99", output$story3$html))
    expect_true(grepl("prespecified sensitivity", output$story3$html))
    expect_true(grepl("not the current custom scenario", output$story3$html))
  })
})

test_that("the reverse break-even lists the three levers", {
  e <- load_app_env()
  shiny::testServer(e$main_server, {
    set_best_estimate(session)
    rv <- output$reverse$html
    expect_true(grepl("5.0 times", rv))                     # departures x fold
    expect_true(grepl("fell from 64", rv))                  # completions floor
    expect_true(grepl("entered active practice", rv))       # conversion floor
  })
})

test_that("scenario status reads Best estimate, then flips to a Custom header with chips", {
  e <- load_app_env()
  shiny::testServer(e$main_server, {
    set_best_estimate(session)
    ss <- output$scenario_status$html
    expect_true(grepl("Best-estimate assumptions", ss))
    expect_true(grepl("The study.s primary assumptions", ss))
    expect_true(grepl("64 completions", ss) && grepl("100% enter practice", ss))  # assumption chips
    session$setInputs(preset = "Custom scenario", conv = 85)
    ss2 <- output$scenario_status$html
    expect_true(grepl("Custom scenario", ss2))
    expect_true(grepl("Modified from Best estimate", ss2))
    expect_true(grepl("85% enter practice", ss2))                                   # changed chip reflects the edit
  })
})

test_that("extending only the horizon stays best-estimate assumptions, not Custom", {
  e <- load_app_env()
  shiny::testServer(e$main_server, {
    set_best_estimate(session)
    session$setInputs(horizon = 7)                    # 2032, assumptions unchanged
    ss <- output$scenario_status$html
    expect_true(grepl("Best-estimate assumptions", ss))       # still the study's assumptions
    expect_true(grepl("Projection extended through 2032", ss))# horizon is a view control
    expect_false(grepl("Custom scenario", ss))                # not flagged as a modification
    # the through-year chip is present but not highlighted as a changed assumption
    expect_true(grepl("through 2032", ss))
  })
})

test_that("input badges are informative, never alarming", {
  e <- load_app_env()
  shiny::testServer(e$main_server, {
    set_best_estimate(session)
    expect_true(grepl("Observed", output$lab_comp$html))    # 64 = observed
    session$setInputs(comp = 74)
    expect_true(grepl("Benchmark", output$lab_comp$html))    # NRMP value
    session$setInputs(comp = 40)                             # far out of range
    expect_true(grepl("User-defined", output$lab_comp$html))
    expect_false(grepl("Extreme|Stress test", output$lab_comp$html))
  })
})

test_that("the reset observer restores the Best estimate base", {
  e <- load_app_env()
  shiny::testServer(e$main_server, {
    set_best_estimate(session)
    session$setInputs(conv = 70, mult = 2)
    session$setInputs(reset = 1)
    expect_equal(st$base, "Best estimate")
  })
})

test_that("the scenario CSV export includes the key fields and trajectory", {
  e <- load_app_env()
  shiny::testServer(e$main_server, {
    set_best_estimate(session)
    tmp <- tempfile(fileext = ".csv")
    scenario_csv(tmp)                                       # local helper, in scope here
    csv <- readLines(tmp)
    expect_true(any(grepl("entrants_per_departure", csv)))
    expect_true(any(grepl("mean_annual_departures", csv)))
    expect_true(any(grepl("active_2029", csv)))
  })
})
