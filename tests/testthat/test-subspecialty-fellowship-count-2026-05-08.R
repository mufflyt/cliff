# =============================================================================
# REGRESSION TEST — distinct fellowship count must not double-count when the
# same fellowship appears in two columns under different naming conventions
# (2026-05-08)
# =============================================================================
#
# Headline regression: the raw ABOG export stores each fellowship twice:
#   * subspecialty_name : short form, e.g. "Female Pelvic Medicine &
#                         Reconstructive Surgery"
#   * sub1FullDescr     : formal cert form, e.g. "Female Pelvic Medicine and
#                         Reconstructive Surgery Subspecialty Certification"
#
# 2,793 of 2,798 ABOG rows where both columns were populated had the SAME
# fellowship in each.  Any code that counts non-empty cells across the
# (subspecialty_name, sub1FullDescr, sub2FullDescr) trio without first
# canonicalizing will overcount single-fellowship physicians as multi-
# subspecialty by ~60×.
#
# These tests lock in:
#   1. Both naming conventions for every ABOG fellowship canonicalize to
#      the same short code (FPMRS, GO, MFM, MIG, PAG, REI, …).
#   2. A row with the same fellowship in two columns counts as 1, not 2.
#   3. A row with two distinct fellowships counts as 2.
#   4. "Generalist" rows count as 0 (general OB-GYN is the base specialty,
#      not a subspecialty fellowship).
#   5. Edge cases: NA, empty strings, the stray \r\n artifact present in
#      the raw ABOG export, leading/trailing whitespace.
# =============================================================================

suppressPackageStartupMessages({
  library(testthat)
  library(here)
})

source(here::here("R", "utils", "subspecialty_fellowship_count.R"))


# -----------------------------------------------------------------------------
# Test 1 — short form and formal cert form canonicalize to the same code
# -----------------------------------------------------------------------------
test_that("canonicalize_fellowship_code: short and formal forms agree per fellowship", {
  # Per project methodology (see config/subspecialty_synonyms.yml and the
  # 2026-05-08 user clarification):
  #   * Critical Care / Hospice / Palliative ARE merged into GO.
  #   * Complex Family Planning IS a real fellowship (its own code).
  # The test pairs below assert (1) both naming conventions for each
  # fellowship reach the same final code and (2) the final code matches
  # the documented project taxonomy.
  pairs <- list(
    FPMRS     = list(
      strs = c("Female Pelvic Medicine & Reconstructive Surgery",
               "Female Pelvic Medicine and Reconstructive Surgery Subspecialty Certification"),
      code = "FPMRS"
    ),
    FPMRS_alt = list(
      strs = c("Female Pelvic Medicine & Reconstructive Surgery",
               "Urogynecology and Reconstructive Pelvic Surgery Subspecialty Certification"),
      code = "FPMRS"
    ),
    GO        = list(
      strs = c("Gynecologic Oncology",
               "Gynecologic Oncology Subspecialty Certification"),
      code = "GO"
    ),
    MFM       = list(
      strs = c("Maternal-Fetal Medicine",
               "Maternal-Fetal Medicine Subspecialty Certification"),
      code = "MFM"
    ),
    MIG       = list(
      strs = c("MIG",
               "Minimally Invasive Gynecologic Surgery Focused Practice Designation"),
      code = "MIG"
    ),
    PAG       = list(
      strs = c("Pediatric & Adolescent Gynecology",
               "Pediatric Adolescent Gynecology Focused Practice Designation"),
      code = "PAG"
    ),
    REI       = list(
      strs = c("Reproductive Endocrinology and Infertility",
               "Reproductive Endocrinology and Infertility Subspecialty Certification"),
      code = "REI"
    ),
    CFP       = list(
      strs = c("Complex Family Planning",
               "Complex Family Planning Subspecialty Certification"),
      code = "CFP"
    ),
    # Critical Care, Hospice, and Palliative MERGE INTO GO per project
    # methodology — their short and formal forms must both yield "GO".
    CC_into_GO    = list(
      strs = c("Critical Care Medicine",
               "Critical Care Subspecialty Certification"),
      code = "GO"
    ),
    HOSP_into_GO  = list(
      strs = c("Hospice and Palliative Medicine",
               "Hospice and Palliative Medicine Subspecialty Certification"),
      code = "GO"
    )
  )
  for (label in names(pairs)) {
    short_form <- pairs[[label]]$strs[1]
    long_form  <- pairs[[label]]$strs[2]
    expected   <- pairs[[label]]$code
    code_short <- canonicalize_fellowship_code(short_form)
    code_long  <- canonicalize_fellowship_code(long_form)
    expect_equal(
      code_short, code_long,
      info = sprintf("[%s] short '%s' and formal '%s' must canonicalize to the same code",
                     label, short_form, long_form)
    )
    expect_equal(
      code_short, expected,
      info = sprintf("[%s] short form must canonicalize to '%s' per project taxonomy",
                     label, expected)
    )
  }
})


# -----------------------------------------------------------------------------
# Test 2 — HEADLINE REGRESSION: same fellowship in two columns counts as 1
# -----------------------------------------------------------------------------
test_that("count_distinct_fellowships: same fellowship in two columns counts as 1", {
  # This is the bug the user reported: a single-fellowship physician with
  # `subspecialty_name` in short form and `sub1FullDescr` in formal cert
  # form must NOT be counted as 2 distinct fellowships.
  n <- count_distinct_fellowships(
    subspecialty_name = "Female Pelvic Medicine & Reconstructive Surgery",
    sub1FullDescr     = "Female Pelvic Medicine and Reconstructive Surgery Subspecialty Certification"
  )
  expect_equal(n, 1L,
               info = "Same fellowship in short + formal form must count as ONE, not two")

  # Same regression for every ABOG fellowship — vectorized.
  pairs <- data.frame(
    short = c(
      "Female Pelvic Medicine & Reconstructive Surgery",
      "Gynecologic Oncology",
      "Maternal-Fetal Medicine",
      "MIG",
      "Pediatric & Adolescent Gynecology",
      "Reproductive Endocrinology and Infertility"
    ),
    formal = c(
      "Female Pelvic Medicine and Reconstructive Surgery Subspecialty Certification",
      "Gynecologic Oncology Subspecialty Certification",
      "Maternal-Fetal Medicine Subspecialty Certification",
      "Minimally Invasive Gynecologic Surgery Focused Practice Designation",
      "Pediatric Adolescent Gynecology Focused Practice Designation",
      "Reproductive Endocrinology and Infertility Subspecialty Certification"
    ),
    stringsAsFactors = FALSE
  )
  counts <- count_distinct_fellowships(pairs$short, pairs$formal)
  expect_equal(counts, rep(1L, nrow(pairs)),
               info = "Every short+formal pair for a single fellowship must count as 1")
})


# -----------------------------------------------------------------------------
# Test 3 — true multi-subspecialty physicians count as 2 or 3
# -----------------------------------------------------------------------------
test_that("count_distinct_fellowships: distinct fellowships count correctly", {
  # FPMRS + MIG (the most common real combo per the 2026-05-08 audit)
  n <- count_distinct_fellowships(
    subspecialty_name = "Female Pelvic Medicine & Reconstructive Surgery",
    sub1FullDescr     = "Minimally Invasive Gynecologic Surgery Focused Practice Designation"
  )
  expect_equal(n, 2L,
               info = "FPMRS + MIG (different fellowships) must count as 2")

  # FPMRS + GO + MIG (3 distinct)
  n3 <- count_distinct_fellowships(
    subspecialty_name = "Female Pelvic Medicine & Reconstructive Surgery",
    sub1FullDescr     = "Gynecologic Oncology Subspecialty Certification",
    sub2FullDescr     = "Minimally Invasive Gynecologic Surgery Focused Practice Designation"
  )
  expect_equal(n3, 3L, info = "Three distinct fellowships must count as 3")

  # PAG + REI (the second-most-common real combo, n=7 in production data)
  n_pag_rei <- count_distinct_fellowships(
    subspecialty_name = "Pediatric & Adolescent Gynecology",
    sub1FullDescr     = "Reproductive Endocrinology and Infertility Subspecialty Certification"
  )
  expect_equal(n_pag_rei, 2L, info = "PAG + REI must count as 2")
})


# -----------------------------------------------------------------------------
# Test 4 — Generalist is not a fellowship
# -----------------------------------------------------------------------------
test_that("count_distinct_fellowships: Generalist alone counts as 0", {
  # General OB-GYN is the base specialty, not a fellowship.
  n <- count_distinct_fellowships(
    subspecialty_name = "Generalist",
    sub1FullDescr     = NA_character_
  )
  expect_equal(n, 0L, info = "Generalist with no fellowship must count as 0")

  # Generalist + one fellowship → 1 (Generalist excluded, fellowship counted).
  n <- count_distinct_fellowships(
    subspecialty_name = "Generalist",
    sub1FullDescr     = "Female Pelvic Medicine and Reconstructive Surgery Subspecialty Certification"
  )
  expect_equal(n, 1L,
               info = "Generalist + 1 fellowship must count as 1 (Generalist excluded)")
})


# -----------------------------------------------------------------------------
# Test 5 — empty / NA / whitespace edge cases
# -----------------------------------------------------------------------------
test_that("canonicalize_fellowship_code: empty/NA/whitespace return NA", {
  expect_identical(canonicalize_fellowship_code(NA_character_), NA_character_)
  expect_identical(canonicalize_fellowship_code(""),            NA_character_)
  expect_identical(canonicalize_fellowship_code("   "),         NA_character_)
})

test_that("count_distinct_fellowships: all-empty row counts as 0", {
  n <- count_distinct_fellowships(
    subspecialty_name = NA_character_,
    sub1FullDescr     = NA_character_,
    sub2FullDescr     = NA_character_
  )
  expect_equal(n, 0L)
})

test_that("canonicalize_fellowship_code: tolerates ABOG \\r\\n artifact and whitespace", {
  # The raw ABOG export carries a literal \r\n inside the long REI string:
  # "Reproductive Endocr\r\ninology and Infertility Subspecialty Certification"
  expect_equal(
    canonicalize_fellowship_code(
      "Reproductive Endocr\r\ninology and Infertility Subspecialty Certification"
    ),
    "REI"
  )
  # Leading / trailing / extra-internal whitespace must not break matching.
  expect_equal(canonicalize_fellowship_code("   FPMRS  "),                 "FPMRS")
  expect_equal(canonicalize_fellowship_code("Gynecologic    Oncology"),    "GO")
})


# -----------------------------------------------------------------------------
# Test 6 — vectorized contract
# -----------------------------------------------------------------------------
test_that("count_distinct_fellowships is vectorized over inputs", {
  short  <- c("Female Pelvic Medicine & Reconstructive Surgery",
              "Generalist",
              "Pediatric & Adolescent Gynecology")
  formal <- c("Female Pelvic Medicine and Reconstructive Surgery Subspecialty Certification",
              NA_character_,
              "Reproductive Endocrinology and Infertility Subspecialty Certification")
  expect_equal(count_distinct_fellowships(short, formal), c(1L, 0L, 2L))
})


# -----------------------------------------------------------------------------
# Test 7 — full-cohort smoke test against the actual ABOG export (skipped if
# the file isn't present, so the test runs in any checkout)
# -----------------------------------------------------------------------------
test_that("ABOG export: distinct multi-fellowship count matches the 2026-05-08 audit", {
  abog_path <- here::here("data", "abog", "abog_physician_data.csv")
  skip_if_not(file.exists(abog_path), "raw ABOG export not present in this checkout")

  d <- suppressMessages(readr::read_csv(abog_path, show_col_types = FALSE))
  required_cols <- c("subspecialty_name", "sub1FullDescr", "sub2FullDescr",
                     "physician_name", "city", "state")
  skip_if_not(all(required_cols %in% names(d)),
              "ABOG file has different schema in this checkout")

  d$n_fellowships <- count_distinct_fellowships(
    d$subspecialty_name, d$sub1FullDescr, d$sub2FullDescr
  )

  multi_npi_keys <- subset(d, n_fellowships >= 2L,
                           select = c("physician_name", "city", "state"))
  multi_npi_keys <- unique(multi_npi_keys)

  # The 2026-05-08 audit recorded ~47 distinct multi-fellowship physicians.
  # If a future ABOG export drifts this number, that is a data-side change
  # (new certifications, new physicians) and not a bug in this counter —
  # but the LARGE inflation that prompted this test (~2,815 with the naive
  # counter) must never recur.  Use a generous range to avoid being brittle
  # against legitimate cohort growth.
  expect_lt(nrow(multi_npi_keys), 200L,
            label = "Distinct multi-fellowship physicians (sentinel against double-count regression)")
  # Most physicians hold 0 (Generalist only) or 1 fellowship.
  expect_gt(sum(d$n_fellowships <= 1L), 0.95 * nrow(d),
            label = "≥95% of ABOG rows must hold 0 or 1 fellowship after canonicalization")
})
