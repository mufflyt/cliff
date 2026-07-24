RENV_LIB <- "/Users/tylermuffly/isochrones/renv/library/R-4.5/x86_64-apple-darwin20"
.libPaths(c(RENV_LIB, .libPaths()))

library(testthat)
library(here)
source(here("R", "safe_divide.R"))
source(here("R", "calculate_retirement_cliff_statistics.R"))

# DEN-055: calculate_replacement_gap() used safe_divide(..., default=0) for
# replacement_ratio. When retiring_count=0 and projected_grads_5yr>0 (infinite
# surplus), fallback 0 < 1.0, so adequate_replacement=FALSE — wrong.
# Fix: use NA_real_ default so adequate_replacement=NA when ratio is undefined.

.make_grads <- function(subspec, grads) {
  data.frame(subspecialty = subspec, graduates = grads, year = 2023L,
             stringsAsFactors = FALSE)
}
.make_retirees <- function(subspec, retiring) {
  data.frame(subspecialty = subspec, retiring_count = retiring,
             stringsAsFactors = FALSE)
}

test_that("DEN-055: retiring_count=0 + grads>0 → replacement_ratio=NA, adequate_replacement=NA", {
  retirees <- .make_retirees("MFM", 0L)
  grads    <- .make_grads("MFM", 10L)
  res <- calculate_replacement_gap(retirees, grads)
  row <- res$by_subspecialty[res$by_subspecialty$subspecialty == "MFM", ]
  expect_true(is.na(row$replacement_ratio),
    info = "replacement_ratio must be NA when retiring_count=0 (undefined, not 0)")
  expect_true(is.na(row$adequate_replacement),
    info = "adequate_replacement must be NA when ratio is NA — infinite surplus is not 'inadequate'")
})

test_that("DEN-055: normal surplus (grads > retirees) → replacement_ratio > 1, adequate=TRUE", {
  retirees <- .make_retirees("REI", 10L)
  grads    <- .make_grads("REI", 5L)   # 5/yr × 5yr = 25 projected
  res <- calculate_replacement_gap(retirees, grads)
  row <- res$by_subspecialty[res$by_subspecialty$subspecialty == "REI", ]
  expect_true(row$replacement_ratio > 1.0,
    info = "25 projected grads / 10 retirees = 2.5 > 1 → adequate")
  expect_true(isTRUE(row$adequate_replacement),
    info = "adequate_replacement must be TRUE when ratio > 1")
})

test_that("DEN-055: shortage (grads < retirees) → replacement_ratio < 1, adequate=FALSE", {
  retirees <- .make_retirees("GO", 20L)
  grads    <- .make_grads("GO", 2L)    # 2/yr × 5yr = 10 projected
  res <- calculate_replacement_gap(retirees, grads)
  row <- res$by_subspecialty[res$by_subspecialty$subspecialty == "GO", ]
  expect_true(row$replacement_ratio < 1.0,
    info = "10 projected grads / 20 retirees = 0.5 < 1 → inadequate")
  expect_false(isTRUE(row$adequate_replacement),
    info = "adequate_replacement must be FALSE when ratio < 1")
})

test_that("DEN-055 harden: retiring=0 AND grads=0 → ratio=NA, adequate=NA (0/0 undefined)", {
  retirees <- .make_retirees("CRS", 0L)
  grads    <- .make_grads("CRS", 0L)
  res <- calculate_replacement_gap(retirees, grads)
  row <- res$by_subspecialty[res$by_subspecialty$subspecialty == "CRS", ]
  expect_true(is.na(row$replacement_ratio),
    info = "0 grads / 0 retirees is 0/0 — must be NA, not 0")
  expect_true(is.na(row$adequate_replacement),
    info = "adequate_replacement must be NA when ratio is NA from 0/0")
})

test_that("DEN-055 harden: mixed subspecialties — NA/FALSE/TRUE in one call", {
  # MFM: 0 retirees, 5 grads → infinite surplus → ratio=NA, adequate=NA
  # GO:  20 retirees, 2 grads → shortage (10/20=0.5) → ratio<1, adequate=FALSE
  # REI: 10 retirees, 5 grads → surplus (25/10=2.5) → ratio>1, adequate=TRUE
  retirees <- rbind(
    .make_retirees("MFM", 0L),
    .make_retirees("GO",  20L),
    .make_retirees("REI", 10L)
  )
  grads <- rbind(
    .make_grads("MFM", 5L),
    .make_grads("GO",  2L),
    .make_grads("REI", 5L)
  )
  res <- calculate_replacement_gap(retirees, grads)
  by_s <- res$by_subspecialty
  mfm <- by_s[by_s$subspecialty == "MFM", ]
  go  <- by_s[by_s$subspecialty == "GO",  ]
  rei <- by_s[by_s$subspecialty == "REI", ]

  expect_true(is.na(mfm$replacement_ratio),
    info = "MFM (0 retirees) → NA ratio")
  expect_true(is.na(mfm$adequate_replacement),
    info = "MFM (0 retirees) → NA adequate (not FALSE)")

  expect_true(go$replacement_ratio < 1.0,
    info = "GO shortage → ratio < 1")
  expect_false(isTRUE(go$adequate_replacement),
    info = "GO shortage → adequate=FALSE")

  expect_true(rei$replacement_ratio > 1.0,
    info = "REI surplus → ratio > 1")
  expect_true(isTRUE(rei$adequate_replacement),
    info = "REI surplus → adequate=TRUE")
})

test_that("DEN-055: overall summary also returns NA replacement_ratio when total_retiring=0", {
  retirees <- .make_retirees("MIGS", 0L)
  grads    <- .make_grads("MIGS", 3L)
  res <- calculate_replacement_gap(retirees, grads)
  expect_true(is.na(res$overall$replacement_ratio),
    info = "overall replacement_ratio must also be NA when total_retiring=0")
})

test_that("DEN-055 harden2: gap_percentage is NA (not 0) when retiring_count=0", {
  # gap_percentage = safe_percentage(net_gap, retiring_count) — also divides by retiring_count.
  # When retiring_count=0, denominator=0 → NA. Previously with ratio=0 this would
  # compute safe_percentage(-50, 0) which is NA anyway, but confirming explicitly.
  retirees <- .make_retirees("UGS", 0L)
  grads    <- .make_grads("UGS", 10L)
  res <- calculate_replacement_gap(retirees, grads)
  row <- res$by_subspecialty[res$by_subspecialty$subspecialty == "UGS", ]
  expect_true(is.na(row$gap_percentage),
    info = "gap_percentage must be NA when retiring_count=0 (safe_percentage divides by 0)")
})

test_that("DEN-055 harden2: net_gap is negative surplus when retiring=0 and grads>0", {
  # net_gap = retiring_count - projected_grads_5yr = 0 - (10*5) = -50 (surplus).
  # This is correct regardless of the NA ratio fix; confirming it is unaffected.
  retirees <- .make_retirees("FPM", 0L)
  grads    <- .make_grads("FPM", 10L)
  res <- calculate_replacement_gap(retirees, grads)
  row <- res$by_subspecialty[res$by_subspecialty$subspecialty == "FPM", ]
  expect_equal(row$net_gap, -50L,
    info = "net_gap = 0 retirees - 50 projected grads = -50 (negative = surplus, not shortage)")
  expect_false(is.na(row$net_gap),
    info = "net_gap is a simple subtraction — must NOT be NA even when ratio is NA")
})
