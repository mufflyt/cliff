# SSOT guard: the shared AUGS supply-demand figure palette. TEAL/ORANGE/RED/GREY (#1b7f79/#c77d1a/
# #d1495b/#8a97a8) were copy-pasted verbatim in both AUGS supply-demand scripts. Now canonical in
# R/augs_palette.R. File-specific colours (GREEN, INK, CMS_*, inline hex) stay local and must NOT be unified.
library(testthat)
library(here)

pe <- new.env(); source(here::here("R", "augs_palette.R"), local = pe)
AUGS <- c("make_supply_demand_figure.R", "cms_supply_demand_10styles.R")

test_that("AUGS_SD_PALETTE is 4 named valid hex colours", {
  expect_length(pe$AUGS_SD_PALETTE, 4L)
  expect_setequal(names(pe$AUGS_SD_PALETTE), c("supply","demand_statusquo","demand_pfd","neutral"))
  expect_true(all(grepl("^#[0-9A-Fa-f]{6}$", pe$AUGS_SD_PALETTE)))
  expect_equal(anyDuplicated(names(pe$AUGS_SD_PALETTE)), 0L)
})

test_that("[behavior-preserving] the bare constants equal the exact prior literals", {
  expect_identical(pe$TEAL,   "#1b7f79")
  expect_identical(pe$ORANGE, "#c77d1a")
  expect_identical(pe$RED,    "#d1495b")
  expect_identical(pe$GREY,   "#8a97a8")
  # and they are derived from the named palette (single origin)
  expect_identical(pe$TEAL,   unname(pe$AUGS_SD_PALETTE[["supply"]]))
  expect_identical(pe$RED,    unname(pe$AUGS_SD_PALETTE[["demand_pfd"]]))
})

test_that("[adversarial] neither AUGS script re-defines the shared palette; both source the SSOT", {
  redefiners <- character(); missing_src <- character()
  for (b in AUGS) {
    ls <- readLines(here::here("augs_application", "scripts", b), warn = FALSE)
    if (any(grepl('(TEAL|ORANGE|RED|GREY)\\s*<-\\s*"#', ls))) redefiners <- c(redefiners, b)
    if (!any(grepl('source\\(here::here\\("R", ?"augs_palette\\.R"\\)\\)', ls))) missing_src <- c(missing_src, b)
  }
  expect_equal(redefiners, character(0), info = paste("shared palette re-hardcoded in:", paste(redefiners, collapse="; ")))
  expect_equal(missing_src, character(0), info = paste("missing source(augs_palette.R):", paste(missing_src, collapse="; ")))
})

test_that("[intentional differences preserved] file-specific colours stay local, other families untouched", {
  ten  <- readLines(here::here("augs_application","scripts","cms_supply_demand_10styles.R"), warn = FALSE)
  make <- readLines(here::here("augs_application","scripts","make_supply_demand_figure.R"),  warn = FALSE)
  expect_true(any(grepl('GREEN\\s*<-\\s*"#2e8b57"', ten)))   # 10styles-only
  expect_true(any(grepl('CMS_DK\\s*<-\\s*"#112e51"', ten)))  # CMS brand ramp local
  expect_true(any(grepl('INK\\s*<-\\s*"#2b2f36"', make)))    # make-only
  # the separate workforce-figure family keeps its own #d1495b constant, NOT wired to this module
  wf <- here::here("manuscript","R","workforce_figures.R")
  if (file.exists(wf)) {
    w <- readLines(wf, warn = FALSE)
    expect_true(any(grepl('\\.wf_URPS\\s*<-\\s*"#d1495b"', w)))
    expect_false(any(grepl("augs_palette", w)))
  }
  # the deployed Shiny app MUST keep its own inline copy (self-contained; cannot source repo modules)
  sh <- here::here("shiny_urps_adequacy","app.R")
  if (file.exists(sh)) {
    s <- readLines(sh, warn = FALSE)
    expect_true(any(grepl('TEAL<-"#1b7f79"', s)))        # inline copy retained by design
    expect_false(any(grepl("augs_palette", s)))          # NOT wired to the SSOT module
  }
})
