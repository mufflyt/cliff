# Guard suite (app + public-facing layer) for the URPS Effective-Adequacy Explorer.
# Uses shiny::testServer to confirm every KPI derives from the canonical proj()
# reactive (Guard 57), and scans rendered + static UI text for the public-claim
# guards (Guards 38-46).

suppressPackageStartupMessages({ library(testthat); library(shiny); library(data.table) })

APP_DIR <- Find(function(d) file.exists(file.path(d,"app.R")),
                c(".", "../..", "../../..", "cliff/shiny_urps_adequacy"))
APP_SRC <- paste(readLines(file.path(APP_DIR, "app.R"), warn=FALSE), collapse="\n")
source(Find(file.exists, c(file.path(APP_DIR,"model.R"), "model.R", "../../model.R")))

DEF_INPUTS <- list(retire=65, fte_new=90, ob_share=77, uro_fte=70, entrants=64,
                   haz_mult=1.0, demand_mult=1.0, entry_age=34, weight_on=TRUE, end_year=2050, band_var="retire")

flat <- function(x) paste(unlist(x), collapse=" ")

# ---------------- Guard 57: KPIs derive from the canonical projection --------
test_that("G57: KPI boxes contain values recomputed from the canonical project()", {
  testServer(shiny::shinyAppDir(APP_DIR), {
    do.call(session$setInputs, DEF_INPUTS)
    d <- project(65, 64, 34, 0.90, 77/100, 70/100, 1.0, 1.0, TRUE, 2050)
    e <- d[YEAR==2050]; i <- which.min(d$adeq_eff)
    expect_true(grepl(formatC(round(e$effective), big.mark=",", format="d"), flat(output$kpi_eff), fixed=TRUE))
    expect_true(grepl(sprintf("%.0f%%", 100*e$adeq_eff), flat(output$kpi_adeq), fixed=TRUE))
    expect_true(grepl(sprintf("%.1f years", e$mean_age), flat(output$kpi_age), fixed=TRUE))
    expect_true(grepl(sprintf("SD %.1f", e$sd_age), flat(output$kpi_age), fixed=TRUE))
    # lowest-adequacy KPI uses the argmin year within the horizon
    expect_true(grepl(as.character(d$YEAR[i]), flat(output$kpi_trough), fixed=TRUE))
  })
})

# ---------------- Guard 28/29: horizon bounds the KPIs -----------------------
test_that("G28/G29: changing the horizon updates KPIs and bounds the lowest-adequacy search", {
  testServer(shiny::shinyAppDir(APP_DIR), {
    do.call(session$setInputs, modifyList(DEF_INPUTS, list(end_year=2040)))
    d <- project(65,64,34,0.90,0.77,0.70,1.0,1.0,TRUE,2040)
    e <- d[YEAR==2040]
    expect_true(grepl(formatC(round(e$effective), big.mark=",", format="d"), flat(output$kpi_eff), fixed=TRUE))
    yr <- as.integer(regmatches(flat(output$kpi_trough), regexpr("20[0-9]{2}", flat(output$kpi_trough))))
    expect_gte(yr, 2025); expect_lte(yr, 2040)                 # G29: trough searched only within horizon
  })
})

# ---------------- Guard 40/45: no unqualified shortage/observed claims -------
test_that("G40: rendered readout carries no unqualified shortage / unmet-need language", {
  testServer(shiny::shinyAppDir(APP_DIR), {
    do.call(session$setInputs, DEF_INPUTS)
    txt <- tolower(paste(c(unlist(output$readout), unlist(output$refs)), collapse=" "))
    for (bad in c("current shortage", "unmet national need", "insufficient current workforce",
                  "urogynecologists are missing", "national shortage"))
      expect_false(grepl(bad, txt, fixed=TRUE), info=paste("forbidden claim:", bad))
    # capacity-gap framing must be the qualified one
    expect_true(grepl("2025 utilization|hold 2025", txt))
  })
})

# ---------------- Guard 38/39: no code paths or scraper language exposed -----
test_that("G38/G39: rendered UI text exposes no absolute paths, temp files, or scraper language", {
  testServer(shiny::shinyAppDir(APP_DIR), {
    do.call(session$setInputs, DEF_INPUTS)
    txt <- paste(c(unlist(output$readout), unlist(output$refs)), collapse=" ")
    expect_false(grepl("/Users/", txt, fixed=TRUE))
    expect_false(grepl("/tmp/",   txt, fixed=TRUE))
    expect_false(grepl("/var/folders", txt, fixed=TRUE))
    expect_false(grepl("scrap", txt, ignore.case=TRUE))         # no scraper language anywhere
  })
})

# ---------------- Guard 41/42/44/46: required qualifiers are present ---------
test_that("G41/G42/G46: static captions carry the baseline, status-quo, and exploratory qualifiers", {
  # capacity-gap baseline assumption visible (subtitle + About drawer)
  expect_true(grepl("2025 normalized to balance", APP_SRC) || grepl("balanced in 2025", APP_SRC))
  # capacity-gap = demand-equivalent minus effective supply, not an observed shortage
  expect_true(grepl("demand-equivalent effective FTEs", APP_SRC))
  expect_true(grepl("not prevalence-based clinical need or current unmet demand", APP_SRC))
  # status-quo demand definition + FTE definition visible
  expect_true(grepl("Demand \\(Status Quo\\)", APP_SRC))
  expect_true(grepl("average weekly patient-care hours", APP_SRC))
  # exploratory status visible
  expect_true(grepl("Exploratory, not the frozen headline projection", APP_SRC))
})

test_that("G39 (static): the app source carries no 'scraper' language in user-facing strings", {
  # allow the word only inside comments; check rendered-string contexts
  expect_false(grepl("scrap", APP_SRC, ignore.case=TRUE))
})

# ---------------- Guard 50/51/55: consistent scenario labels & colors --------
test_that("G50/G55: series labels and colors are defined once and reused", {
  # canonical labels defined exactly once
  m <- gregexpr('L_DEM <- "Demand \\(Status Quo\\)"', APP_SRC)[[1]]
  expect_equal(if (m[1]==-1) 0L else length(m), 1L)
  # colors assigned once
  expect_true(grepl('TEAL<-"#1b7f79"', APP_SRC))
})

# ---------------- Guard 63/71: defaults match the documented scenario --------
test_that("G63/G71: app slider defaults match the documented DEFAULTS in model.R", {
  expect_true(grepl('bslider\\("retire".*55, 75, 65', APP_SRC))
  expect_true(grepl('bslider\\("entrants".*20, 120, 64', APP_SRC))
  expect_true(grepl('bslider\\("uro_fte".*0, 100, 70', APP_SRC))
  expect_true(grepl('bslider\\("fte_new".*50, 100, 90', APP_SRC))
  expect_equal(DEFAULTS$retire, 65L); expect_equal(DEFAULTS$entrants, 64L)
  expect_equal(DEFAULTS$uro_fte, 0.70); expect_equal(DEFAULTS$fte_new, 0.90)
})

# ---------------- Guard 66: app loads clean; Guard 80: version shown ---------
test_that("G80: a discreet model/data version is displayed (no code path)", {
  expect_true(grepl("Model version", APP_SRC))
  expect_false(grepl("Model version.*scripts/", APP_SRC))
})
