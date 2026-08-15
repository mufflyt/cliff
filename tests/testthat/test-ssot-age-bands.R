# SSOT guard: the age-band definition (engine WC_BANDS / WC_BAND_LABELS) is the axis of the
# hazard model. It is duplicated across many scripts, the Shiny apps, and the hazard CSV; this
# guards that every reachable copy matches the canonical and cannot silently drift.
library(testthat)
library(here)

# Repository integration test: sources R/ or data/ from the SOURCE TREE via
# here(). An installed package has no R/*.R files, so this is inapplicable
# rather than broken there. See helper-cliff-root.R.
skip_if_no_repo()
suppressPackageStartupMessages(library(readr))

ee <- new.env()
suppressPackageStartupMessages(source(here::here("R", "workforce_cliff_engine.R"), local = ee))

BANDS  <- ee$WC_BANDS
LABELS <- ee$WC_BAND_LABELS

test_that("canonical age bands are well-formed (7 labels, 8 breakpoints, monotone, closed at 0/Inf)", {
  expect_identical(BANDS,  c(0, 45, 50, 55, 60, 65, 70, Inf))
  expect_identical(LABELS, c("<45", "45-49", "50-54", "55-59", "60-64", "65-69", "70+"))
  expect_length(LABELS, length(BANDS) - 1L)      # one label per interval
  expect_true(all(diff(BANDS) > 0))              # strictly increasing
  expect_identical(BANDS[[1]], 0)
  expect_identical(BANDS[[length(BANDS)]], Inf)
})

test_that("frozen hazard-by-band CSV band column matches the canonical labels (order-sensitive)", {
  h <- read_csv(here::here("data", "hazard_by_band_pooled_vs_unpooled.csv"), show_col_types = FALSE)
  expect_identical(as.character(h$band), LABELS)
})

test_that("Shiny self-contained BAND_LABELS + BANDS copies match the canonical (drift guard)", {
  for (p in c("shiny_urps_scenarios/urps_model_data.R",
              "shiny_urps_adequacy/data/urps_model_data.R")) {
    se <- new.env(); source(here::here(p), local = se)
    expect_identical(se$BAND_LABELS, LABELS, info = p)
    expect_identical(se$BANDS, BANDS, info = p)                       # iter37: numeric breakpoints now in the snapshot
    expect_length(se$BANDS, length(se$BAND_LABELS) + 1L)             # one label per interval, in the snapshot itself
  }
})

test_that("bands partition ages correctly (semantic: cut agrees with labels, right-open)", {
  ages <- c(30, 44, 45, 49, 50, 64, 70, 85)
  got  <- as.character(cut(ages, breaks = BANDS, labels = LABELS, right = FALSE))
  expect_identical(got, c("<45", "<45", "45-49", "45-49", "50-54", "60-64", "70+", "70+"))
})

test_that("[adversarial] no engine-sourcing script redefines the age bands as literals", {
  rfiles <- list.files(here::here("scripts"), pattern = "\\.R$", full.names = TRUE)
  offenders <- character()
  for (f in rfiles) {
    ls <- readLines(f, warn = FALSE)
    if (!any(grepl("workforce_cliff_engine\\.R", ls))) next
    hit <- grepl("(^|[^_])(BANDS|BAND_LABELS)\\s*<-\\s*c\\(", ls)
    if (any(hit)) offenders <- c(offenders, sprintf("%s:%s", basename(f), paste(which(hit), collapse = ",")))
  }
  expect_equal(offenders, character(0),
               info = paste("age bands re-hardcoded in engine-sourcing script(s):", paste(offenders, collapse = "; ")))
})

test_that("[adversarial] demand/app consumers read BANDS from the snapshot, not a hardcoded literal (iter37)", {
  # iter37: BANDS was hardcoded c(0,45,50,55,60,65,70,Inf) in four demand/app files while they already
  # sourced urps_model_data.R for BAND_LABELS. BANDS now lives in the snapshot too; no consumer may re-pin it.
  # The two urps_model_data.R snapshots are the allowed home (parity-guarded above) and are exempted.
  consumers <- c(here::here("scripts", "urps_supply_demand_national_2026-07-23.R"),
                 here::here("scripts", "urps_module_a_effective_supply_2026-07-23.R"),
                 here::here("shiny_urps_scenarios", "app.R"),
                 here::here("shiny_urps_adequacy", "model.R"))
  offenders <- character()
  for (f in consumers) {
    ls <- readLines(f, warn = FALSE)
    src <- any(grepl("urps_model_data\\.R", ls))                       # must still source the snapshot
    hit <- any(grepl("(^|[^_])BANDS\\s*<-\\s*c\\(", ls))               # must NOT re-hardcode BANDS
    if (!src || hit) offenders <- c(offenders, sprintf("%s (sources=%s, hardcodes=%s)", basename(f), src, hit))
  }
  expect_equal(offenders, character(0),
               info = paste("BANDS not snapshot-sourced in:", paste(offenders, collapse = "; ")))
})

test_that("[semantic] the snapshot BANDS actually partitions ages identically to the engine", {
  # end-to-end: cut() with the snapshot's own BANDS/BAND_LABELS agrees with the engine's, so wiring the
  # consumers to the snapshot cannot change any age's band assignment.
  se <- new.env(); source(here::here("shiny_urps_scenarios", "urps_model_data.R"), local = se)
  ages <- c(29, 44, 45, 59, 60, 69, 70, 88)
  expect_identical(as.character(cut(ages, se$BANDS, labels = se$BAND_LABELS, right = FALSE)),
                   as.character(cut(ages, BANDS,   labels = LABELS,         right = FALSE)))
})
