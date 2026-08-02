# SSOT guard: the active-baseline cohort filter. The predicate reading `in_model_baseline` was written
# FOUR ways across ten call sites — `inmodel(x) <- x %in% c(TRUE,"TRUE","true",1,"1")` redefined verbatim
# in 7 scripts, a bare `d[in_model_baseline == TRUE]` in module_d_geographic_access, a
# `toupper(trimws(x)) %in% c("TRUE","1")` in concentration_equity, and that same body inlined in
# enrich_rosters_hpsa. Now canonical in R/in_model_baseline.R (inmodel()). Guards cover semantics,
# totality (NA -> FALSE, never NA), behaviour preservation against all four prior forms, that no consumer
# re-defines or re-hardcodes the predicate, and that the geographic and concentration analyses agree on
# the 1,339-provider baseline.
library(testthat)
library(here)

be <- new.env(); source(here::here("R", "in_model_baseline.R"), local = be)

# every script that filters on in_model_baseline
CONSUMERS <- c("urps_module_a_age_productivity_2026-07-23.R", "urps_module_bc_corrected_2026-07-23.R",
               "urps_module_bc_gate_audit_2026-07-23.R", "urps_demand_module_bc_2026-07-23.R",
               "urps_plasticity_stage0_audit_2026-07-23.R", "urps_module_d_geographic_access_2026-07-23.R",
               "urps_concentration_equity_2026-08-01.R", "build_table1_urps_2026-07-23.R",
               "enrich_rosters_hpsa_point_in_polygon_2026-07-23.R",
               "enrich_rosters_medicare_procedures_2024_refresh.R")

ROSTERS <- c(abog = "data/abog_all_urps_ENRICHED_2026-07-22.csv",
             abu  = "data/abu_all_urps_ENRICHED_2026-07-22.csv")
BASELINE_N <- c(abog = 1031L, abu = 308L)   # contract-pinned: 1,031 + 308 = rows_national 1,339

test_that("inmodel is a well-formed, total, length-preserving predicate", {
  expect_true(is.function(be$inmodel))
  expect_type(be$inmodel(TRUE), "logical")
  expect_length(be$inmodel(c(TRUE, FALSE, NA)), 3L)
  expect_length(be$inmodel(logical(0)), 0L)
  expect_false(anyNA(be$inmodel(c(TRUE, NA, FALSE, "x"))))   # total: never returns NA
})

test_that("[semantic] accepts the in-baseline forms across storage types, rejects everything else", {
  expect_identical(be$inmodel(c(TRUE, FALSE)), c(TRUE, FALSE))            # logical (how fread reads it)
  expect_identical(be$inmodel(c(1, 0)), c(TRUE, FALSE))                   # numeric
  expect_identical(be$inmodel(c("TRUE", "true", "True")), rep(TRUE, 3L))  # character, any case
  expect_identical(be$inmodel(c(" TRUE ", "\t1")), c(TRUE, TRUE))         # whitespace-padded
  expect_identical(be$inmodel(factor(c("TRUE", "FALSE"))), c(TRUE, FALSE))
  expect_identical(be$inmodel(c("FALSE", "false", "0", "", "no")), rep(FALSE, 5L))
  expect_identical(be$inmodel(c(NA, NA_character_)), c(FALSE, FALSE))     # missing flag is NOT in baseline
})

test_that("[behavior-preserving] reproduces all four prior variants on values they all defined", {
  v_old  <- function(x) x %in% c(TRUE, "TRUE", "true", 1, "1")      # the 7-copy inmodel() + hpsa inline
  v_eq   <- function(x) x == TRUE                                    # module_d_geographic_access
  v_trim <- function(x) toupper(trimws(x)) %in% c("TRUE", "1")       # concentration_equity

  # as the column actually reads off the rosters: clean logical, no NA
  lg <- c(TRUE, FALSE, TRUE, FALSE)
  expect_identical(be$inmodel(lg), v_old(lg))
  expect_identical(be$inmodel(lg), v_eq(lg))
  expect_identical(be$inmodel(lg), v_trim(lg))

  # as it reads after a character re-serialisation (concentration_equity's as.character path)
  ch <- c("TRUE", "FALSE", "true", "1", "0")
  expect_identical(be$inmodel(ch), v_old(ch))
  expect_identical(be$inmodel(ch), v_trim(ch))
  # the divergence the SSOT closes: `== TRUE` alone drops "true"/"1" from a character column
  expect_false(identical(be$inmodel(ch), v_eq(ch)))
})

test_that("[adversarial] no consumer redefines inmodel or re-hardcodes a variant predicate", {
  redefines <- character(); variants <- character(); missing_src <- character()
  for (b in CONSUMERS) {
    ls <- readLines(here::here("scripts", b), warn = FALSE)
    code <- ls[!grepl("^\\s*#", ls)]                       # prose mentions of the rule are fine
    if (any(grepl("inmodel\\s*<-\\s*function", code))) redefines <- c(redefines, b)
    if (any(grepl('in_model_baseline\\s*==\\s*TRUE|toupper\\(trimws\\(in_model_baseline|in_model_baseline\\s*%in%\\s*c\\(', code)))
      variants <- c(variants, b)
    # three sourcing idioms in use: here::here("R","x.R"), here::here("R/x.R"), h("R/x.R"), "R/x.R"
    if (!any(grepl('source\\(.*in_model_baseline\\.R', ls))) missing_src <- c(missing_src, b)
    expect_true(any(grepl("inmodel\\(", code)), info = b)  # uses the canonical helper
  }
  expect_equal(redefines, character(0), info = paste("local inmodel() still in:", paste(redefines, collapse = "; ")))
  expect_equal(variants, character(0), info = paste("variant predicate still in:", paste(variants, collapse = "; ")))
  expect_equal(missing_src, character(0), info = paste("missing source(R/in_model_baseline.R):", paste(missing_src, collapse = "; ")))
})

test_that("[cross-module] the rosters filter to the contract-pinned 1,339 baseline under inmodel()", {
  for (nm in names(ROSTERS)) {
    p <- here::here(ROSTERS[[nm]])
    skip_if_not(file.exists(p), paste("roster not staged:", ROSTERS[[nm]]))
    # read BOTH ways the consumers read it: natural types (fread) and all-character (read_roster)
    d_nat <- data.table::fread(p, colClasses = list(character = "npi"))
    d_chr <- data.table::fread(p, colClasses = "character")
    expect_identical(sum(be$inmodel(d_nat$in_model_baseline)), BASELINE_N[[nm]], info = nm)
    expect_identical(sum(be$inmodel(d_chr$in_model_baseline)), BASELINE_N[[nm]], info = nm)
  }
  expect_identical(sum(BASELINE_N), 1339L)   # rows_national in the isochrones v3.0.0 contract
})
