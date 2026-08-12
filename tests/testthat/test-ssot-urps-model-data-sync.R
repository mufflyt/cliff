# SSOT guard: the URPS model-data snapshot has ONE canonical copy, and every standalone Shiny app replica is
# byte-identical to it. This is a WHOLE-FILE superset of the per-constant guards (BANDS/BAND_LABELS/BAND_EV/PY/
# GRAD_URPS/URPS_AGES/HAZ_WINDOWS): any future drift — an audited constant OR anything else in the file — fails
# here. It closes the structural cause of the second-snapshot gaps patched one-by-one in iters 37-39.
#
# The duplication is unavoidable: both apps deploy to shinyapps.io via rsconnect::deployApp with app-dir-relative
# appFiles, so each app dir must physically contain the file. scripts/sync_urps_model_data.R keeps the replicas
# in sync; this guard proves they are.
library(testthat)
library(here)

CANONICAL <- here::here("shiny_urps_scenarios", "urps_model_data.R")
REPLICAS  <- c(here::here("shiny_urps_adequacy", "data", "urps_model_data.R"))

test_that("[whole-file SSOT] every Shiny replica is byte-identical to the canonical model-data snapshot", {
  expect_true(file.exists(CANONICAL))
  canon_lines <- readLines(CANONICAL, warn = FALSE)
  canon_md5   <- unname(tools::md5sum(CANONICAL))
  for (rep in REPLICAS) {
    expect_true(file.exists(rep), info = rep)
    expect_identical(readLines(rep, warn = FALSE), canon_lines, info = rep)   # line-for-line (human-diffable)
    expect_identical(unname(tools::md5sum(rep)), canon_md5, info = rep)       # and byte-for-byte
  }
})

test_that("[semantic] canonical + replicas define the SAME model constants with identical values", {
  # defence in depth: even if two files hashed the same by accident, the sourced constants must match.
  ce <- new.env(); source(CANONICAL, local = ce)
  keys <- c("URPS_AGES", "BAND_LABELS", "BANDS", "GRAD_URPS", "BAND_EV", "BAND_PY", "HAZ_WINDOWS")
  expect_true(all(keys %in% ls(ce)), info = paste("missing:", paste(setdiff(keys, ls(ce)), collapse = ",")))
  for (rep in REPLICAS) {
    re <- new.env(); source(rep, local = re)
    for (k in keys) expect_identical(get(k, re), get(k, ce), info = paste(basename(dirname(rep)), k))
  }
})

test_that("the sync generator exists, is fail-loud, and names canonical + replicas", {
  s <- readLines(here::here("scripts", "sync_urps_model_data.R"), warn = FALSE)
  expect_true(any(grepl("shiny_urps_scenarios", s)))                 # names the canonical
  expect_true(any(grepl("shiny_urps_adequacy",  s)))                 # names the replica
  expect_true(any(grepl("--check", s, fixed = TRUE)))                # has a CI/preflight verify mode
  expect_true(any(grepl("quit\\(status = 1L\\)|stop\\(", s)))        # fails loudly on drift / bad copy
})

test_that("[adversarial] a replica with one changed byte is detected as drift", {
  # simulate drift in a temp copy and prove the byte-identity check would fail on it (does NOT touch real files).
  canon_lines <- readLines(CANONICAL, warn = FALSE)
  tampered <- canon_lines
  gi <- grep("^GRAD_URPS", tampered)[1]
  tampered[gi] <- sub("c\\(61,66,63,66\\)", "c(61,66,63,67)", tampered[gi])   # flip one completer count
  expect_false(identical(tampered, canon_lines))                              # the guard's comparison would fail
})
