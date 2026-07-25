#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Fetch NRMP fellowship "positions filled" for the three gyn surgical subspecialties
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Downloads the authoritative NRMP Specialties Matching Service reports and
# extracts the number of fellowship POSITIONS FILLED (= entering fellows per
# year, the correct "annual entrants" for the workforce model) for:
#   URPS  (NRMP label: Female Pelvic Medicine and Reconstructive Surgery)
#   GO    (Gynecologic Oncology)
#   MIGS  (Minimally Invasive Gynecologic Surgery)
#
# WHY THIS EXISTS: the published SSOT used GO = 50 annual entrants, a value with
# NO documented source in the repo. The authoritative NRMP filled-position count
# is GO = 86 (2024 appointment year), which reverses the manuscript's GO decline
# finding. See scripts/rebuild_ssot_from_nrmp.R.
#
# Reproducibility: re-downloads the source PDFs, extracts the text with
# `pdftotext`, and ASSERTS the extracted counts against values human-verified
# from the source PDFs on 2026-07-15. Any NRMP format/number change fails loud.
#
# Requires: pdftotext (poppler) on PATH.
# Output:  data/nrmp_fellowship_entrants.csv (with full provenance).
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(here)})

if (nchar(Sys.which("pdftotext")) == 0) {
  stop("pdftotext (poppler) not found on PATH; install poppler to run this fetcher.")
}

# --- Authoritative sources -------------------------------------------------
SOURCES <- list(
  obgyn_2024 = list(
    url = "https://www.nrmp.org/wp-content/uploads/2024/09/OBGYN-MRS-Report-2024.pdf",
    report = "NRMP Match Results Statistics, Obstetrics & Gynecology, 2024 Appointment Year",
    appointment_year = 2024L),
  sms_2025 = list(
    url = "https://www.nrmp.org/wp-content/uploads/2025/02/SMS_Results_and_Data_2025.pdf",
    report = "NRMP Results and Data: Specialties Matching Service, 2025 Appointment Year",
    appointment_year = 2025L)
)

# Positions FILLED, read directly from the source PDFs on 2026-07-15.
# GO and MIGS confirmed in BOTH the OB/GYN report (per-specialty pages) and the
# SMS aggregate; URPS (FPMRS matches on a separate NRMP track for AUGS/SUFU) is
# taken from the SMS 2025 aggregate.
VERIFIED <- data.frame(
  subspecialty_abbrev = c("URPS", "GO", "MIGS"),
  subspecialty        = c("Urogynecology and Reconstructive Pelvic Surgery",
                          "Gynecologic Oncology",
                          "Minimally Invasive Gynecologic Surgery"),
  nrmp_label          = c("Female Pelvic Medicine and Reconstructive",
                          "Gynecologic Oncology",
                          "Minimally Invasive Gynecologic Surgery"),
  positions_filled    = c(70L, 86L, 47L),
  # All three confirm in the SMS 2025 aggregate. GO=86 and MIGS=47 are additionally
  # cross-confirmed in the 2024 OB/GYN Match Results Statistics report (per-specialty
  # pages, verified by direct read 2026-07-15).
  source_key          = c("sms_2025", "sms_2025", "sms_2025"),
  stringsAsFactors = FALSE
)

cache_dir <- here::here("data", "nrmp_cache")
dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)

get_text <- function(key) {
  src <- SOURCES[[key]]
  pdf <- file.path(cache_dir, paste0(key, ".pdf"))
  if (!file.exists(pdf)) {
    message("Downloading ", src$url)
    utils::download.file(src$url, pdf, mode = "wb", quiet = TRUE, method = "libcurl")
  }
  if (!file.exists(pdf) || file.info(pdf)$size < 5000) {
    stop("download failed or too small: ", src$url)
  }
  txt <- tempfile(fileext = ".txt")
  system2("pdftotext", c("-layout", shQuote(pdf), shQuote(txt)))
  paste(readLines(txt, warn = FALSE), collapse = "\n")
}

# Confirm the verified filled count actually appears in the current source next
# to the subspecialty label (audit step; fails loud on any NRMP change).
confirm_in_source <- function(text, label, filled) {
  lines <- unlist(strsplit(text, "\n", fixed = TRUE))
  esc   <- gsub("([().*\\[\\]])", "\\\\\\1", label)
  # applicant/summary rows look like: "<label>[**]  <filled> <matched> <usmd> <pct>..."
  pat   <- paste0(esc, ".*?\\b", filled, "\\b.*?\\b", filled, "\\b")
  hits  <- grep(pat, lines, perl = TRUE, value = TRUE)
  if (length(hits) == 0) {
    # fall back to label + filled on the same line
    hits <- grep(paste0(esc, ".*\\b", filled, "\\b"), lines, perl = TRUE, value = TRUE)
  }
  length(hits) > 0
}

texts <- lapply(names(SOURCES), get_text)
names(texts) <- names(SOURCES)

rows <- lapply(seq_len(nrow(VERIFIED)), function(i) {
  v   <- VERIFIED[i, ]
  txt <- texts[[v$source_key]]
  ok  <- confirm_in_source(txt, v$nrmp_label, v$positions_filled)
  if (!ok) {
    stop(sprintf(paste0("NRMP audit FAILED for %s: could not confirm %d filled ",
                        "positions for '%s' in %s.\n  The NRMP report format or ",
                        "numbers may have changed — re-verify against %s before ",
                        "trusting this value."),
                 v$subspecialty_abbrev, v$positions_filled, v$nrmp_label,
                 v$source_key, SOURCES[[v$source_key]]$url))
  }
  src <- SOURCES[[v$source_key]]
  data.frame(
    subspecialty_abbrev = v$subspecialty_abbrev,
    subspecialty        = v$subspecialty,
    annual_entrants     = v$positions_filled,   # NRMP positions filled = entering cohort/yr
    nrmp_label          = v$nrmp_label,
    appointment_year    = src$appointment_year,
    source_report       = src$report,
    source_url          = src$url,
    confirmed           = ok,
    stringsAsFactors = FALSE)
})
out <- do.call(rbind, rows)

out_path <- here::here("data", "nrmp_fellowship_entrants.csv")
utils::write.csv(out, out_path, row.names = FALSE)

cat("\nNRMP fellowship entrants (positions filled), all confirmed in source:\n")
print(out[, c("subspecialty_abbrev", "annual_entrants", "appointment_year", "nrmp_label")],
      row.names = FALSE)
cat("\nWrote", out_path, "\n")
