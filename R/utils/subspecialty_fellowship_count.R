#' @title Subspecialty Fellowship Count Utilities
#'
#' @description
#' Distinct-fellowship counter for ABOG-style multi-column subspecialty data,
#' mapping multiple string representations to single canonical fellowship codes.
#'
#' @family data-enrichment
#' @name subspecialty_fellowship_count
NULL

# =============================================================================
# Distinct-fellowship counter for ABOG-style multi-column subspecialty data
# =============================================================================
#
# Background (BUG FIX 2026-05-08):
#   The raw ABOG export stores each fellowship in TWO different naming
#   conventions across two columns:
#     * subspecialty_name : short form, e.g. "Female Pelvic Medicine &
#                           Reconstructive Surgery"
#     * sub1FullDescr     : formal certification name, e.g. "Female Pelvic
#                           Medicine and Reconstructive Surgery Subspecialty
#                           Certification"
#   2,793 of 2,798 ABOG rows where both columns were populated had the SAME
#   fellowship in each — i.e. the formal name is just the short name plus
#   "Subspecialty Certification" (or "Focused Practice Designation").  A
#   naive counter that calls `nchar(.) > 0` on each column counts those
#   rows as 2-fellowship physicians, inflating the multi-subspec cohort
#   by ~60×.
#
#   The fix lives in `standardize_abog_subspecialty()` in
#   R/subspecialty_standardization.R, which now recognizes BOTH naming
#   conventions and collapses them to the same ABOG code.  This file is a
#   thin wrapper that adds the count-distinct semantics on top.
#
#   Tests in tests/testthat/test-subspecialty-fellowship-count-2026-05-08.R
#   lock in the canonical mapping and the regression case (same fellowship
#   in two columns must count as 1, not 2).
# =============================================================================

# Source the canonical standardizer so this file has no other dependency.
# (Sourcing inside the file is safe because R's `source()` is idempotent
# at the function-definition level — re-sourcing just rebinds the
# function in the caller's environment.)
if (!exists("standardize_abog_subspecialty", mode = "function")) {
  source(here::here("R", "subspecialty_standardization.R"), local = FALSE)
}


#' Canonicalize a Subspecialty String to a Stable Fellowship Code
#'
#' Thin wrapper over `standardize_abog_subspecialty()` from
#' R/subspecialty_standardization.R that:
#'   1. Adds an explicit `"GEN"` code for Generalist / general Otolaryngology
#'      strings (the standardizer maps these to `"Other"` along with
#'      Critical Care, Hospice, Complex Family Planning, etc.).
#'   2. Returns `NA_character_` for empty / blank inputs (the standardizer
#'      passes them through unchanged, which would foil the
#'      count-distinct logic below).
#'
#' @param x Character vector of raw subspecialty strings (or `NA`).
#' @return Character vector — `"FPMRS"`, `"GO"`, `"MFM"`, `"MIG"`,
#'   `"PAG"`, `"REI"`, `"GEN"` (Generalist), `"Other"` (Critical
#'   Care / Hospice / Complex Family Planning / etc.), or
#'   `NA_character_` for empty / unrecognized strings.
#' @keywords internal
#' @export
canonicalize_fellowship_code <- function(x) {
  x <- ifelse(is.na(x), "", as.character(x))
  # Collapse internal whitespace (handles the stray \r\n artifact in raw
  # ABOG strings, e.g. "Reproductive Endocr\r\ninology and Infertility ...").
  x_clean <- gsub("\\s+", " ", trimws(x))

  # Empty inputs short-circuit to NA so the distinct-count below does
  # not see them as a "code".
  empty <- nchar(x_clean) == 0L

  # Delegate the real canonicalization to the existing standardizer.
  std <- standardize_abog_subspecialty(x_clean)

  # The standardizer returns "Other" for Generalist (now that it tags
  # general Otolaryngology explicitly).  Distinguish Generalist from Critical
  # Care / Hospice / CFP so callers can exclude only Generalist from
  # fellowship counts (per the user requirement).
  is_gen <- grepl("^\\s*(generalist|general[ \\-]?ob)\\s*$",
                  tolower(x_clean), perl = TRUE)
  std[is_gen] <- "GEN"

  std[empty] <- NA_character_
  std
}


#' Count Distinct Fellowships Held by a Physician
#'
#' Given the (up to three) subspecialty columns from one ABOG row, returns
#' the number of DISTINCT fellowship codes the physician holds, excluding
#' Generalist.  Different naming conventions for the same fellowship
#' (short vs. formal cert vs. focused-practice-designation) collapse to a
#' single code, so single-fellowship physicians return 1 even when both
#' `subspecialty_name` and `sub1FullDescr` are populated with the same
#' fellowship in different forms.
#'
#' @param subspecialty_name Character vector — short-form column.
#' @param sub1FullDescr     Character vector — formal-cert column (sub1).
#' @param sub2FullDescr     Character vector — formal-cert column (sub2),
#'   optional; defaults to all-`NA`.
#' @return Integer vector, length equal to `subspecialty_name`.  Values:
#'   `0L` (Generalist only or all empty), `1L`, `2L`, or `3L`.
#' @export
count_distinct_fellowships <- function(subspecialty_name,
                                       sub1FullDescr,
                                       sub2FullDescr = NA_character_) {
  if (length(sub2FullDescr) == 1L && length(subspecialty_name) > 1L) {
    sub2FullDescr <- rep(sub2FullDescr, length(subspecialty_name))
  }
  stopifnot(length(subspecialty_name) == length(sub1FullDescr))
  stopifnot(length(subspecialty_name) == length(sub2FullDescr))

  c0 <- canonicalize_fellowship_code(subspecialty_name)
  c1 <- canonicalize_fellowship_code(sub1FullDescr)
  c2 <- canonicalize_fellowship_code(sub2FullDescr)

  # For each row, build the distinct set excluding NA and "GEN".
  vapply(seq_along(c0), function(i) {
    codes <- unique(c(c0[i], c1[i], c2[i]))
    codes <- codes[!is.na(codes) & codes != "GEN"]
    length(codes)
  }, integer(1))
}
