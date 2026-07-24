#!/usr/bin/env Rscript
# abu_scraper.r — scrape the American Board of Urology (ABU) public
# physician-verification portal.
#
# Source:  https://portal.abu.org/static/verification/index.html
# API:     GET https://portal.abu.org/api/public_records?page=N
#          (a Vue2/axios SPA; `page` drives ~120-record alphabetical pages;
#           limit/offset/per_page are ignored; empty `name` => full registry.)
#
# Purpose: capture ABU-certified urologists AND their Subspecialty, so the
# urology-pathway "Urogynecology and Reconstructive Pelvic Surgery" (Female
# Pelvic Medicine / FPMRS) physicians that the OB/GYN (ABOG-only) cohort
# structurally excludes can be identified for a workforce-access sensitivity
# analysis.
#
# Respectful by design: identifies itself + a research contact, one request per
# page, 1.2s spacing, retry-with-backoff (httr::RETRY), stops at the first empty
# page. Record fields: Name, City, State, CertificationType, CertificationYear,
# Subspecialty, ExpirationDisplay, ExpirationDate, ParticipationInCUCOrLL.
#
# Usage:  Rscript scripts/abu_scraper.r
# Deps:   httr, jsonlite (both already used across the pipeline).

suppressWarnings(suppressMessages({
  ok <- requireNamespace("httr", quietly = TRUE) &&
        requireNamespace("jsonlite", quietly = TRUE)
}))
if (!ok) stop("abu_scraper.r needs the 'httr' and 'jsonlite' packages.", call. = FALSE)

# ---- config -----------------------------------------------------------------
BASE      <- "https://portal.abu.org/api/public_records"
UA        <- "Mozilla/5.0 (academic OB-GYN workforce access study; contact tyler.muffly@dhha.org)"
OUTDIR    <- if (requireNamespace("here", quietly = TRUE)) {
  here::here("data", "abu_urology")
} else {
  file.path(getwd(), "data", "abu_urology")
}
DELAY_S   <- 1.2      # spacing between page requests
MAX_PAGES <- 400L     # hard safety bound (registry is ~110 pages)
UROGYN_RE <- "urogyn" # case-insensitive flag for the female-urology subspecialty
COLS <- c("Name", "City", "State", "CertificationType", "Subspecialty",
          "CertificationYear", "ExpirationDisplay", "ExpirationDate",
          "ParticipationInCUCOrLL")

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

# ---- one page, with retry + backoff -----------------------------------------
fetch_page <- function(page, retries = 4L) {
  resp <- httr::RETRY(
    "GET", BASE,
    query   = list(page = page),
    httr::user_agent(UA),
    httr::add_headers(Accept = "application/json"),
    httr::timeout(30),
    times   = retries,
    pause_base = 2, pause_cap = 32,
    terminate_on = c(400, 404),
    quiet   = TRUE
  )
  if (httr::http_error(resp)) {
    stop(sprintf("page %d: HTTP %s", page, httr::status_code(resp)), call. = FALSE)
  }
  jsonlite::fromJSON(httr::content(resp, as = "text", encoding = "UTF-8"),
                     simplifyVector = FALSE)  # list of per-record named lists
}

# dedupe key: (Name, City, State, CertificationType, CertificationYear)
rec_key <- function(r) paste(
  r$Name %||% "", r$City %||% "", r$State %||% "",
  r$CertificationType %||% "", r$CertificationYear %||% "", sep = "")

# flatten one record -> named character vector over COLS (ExpirationDate$date)
flatten_rec <- function(r) {
  ed <- r$ExpirationDate
  ed <- if (is.list(ed)) (ed$date %||% NA_character_) else (ed %||% NA_character_)
  vals <- lapply(COLS, function(c) if (identical(c, "ExpirationDate")) ed else (r[[c]] %||% NA))
  stats::setNames(vapply(vals, function(v) if (is.null(v)) NA_character_ else as.character(v),
                         character(1)), COLS)
}

# ---- scrape loop ------------------------------------------------------------
dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)
seen <- new.env(parent = emptyenv())
records <- list()
empty_streak <- 0L

for (page in seq_len(MAX_PAGES)) {
  data <- tryCatch(fetch_page(page), error = function(e) {
    message(sprintf("  page %d: FAILED (%s)", page, conditionMessage(e))); NULL
  })
  if (is.null(data) || length(data) == 0L) {
    empty_streak <- empty_streak + 1L
    message(sprintf("  page %d: empty (%d)", page, empty_streak))
    if (empty_streak >= 2L) break
    Sys.sleep(DELAY_S); next
  }
  empty_streak <- 0L
  new_n <- 0L
  for (r in data) {
    k <- rec_key(r)
    if (!exists(k, envir = seen, inherits = FALSE)) {
      assign(k, TRUE, envir = seen)
      records[[length(records) + 1L]] <- r
      new_n <- new_n + 1L
    }
  }
  message(sprintf("  page %d: %d rows, +%d new (total %d)", page, length(data), new_n, length(records)))
  Sys.sleep(DELAY_S)
}

if (length(records) == 0L) stop("ABU scrape returned 0 records — API shape may have changed.", call. = FALSE)

# ---- assemble outputs -------------------------------------------------------
stamp <- as.character(Sys.Date())
df <- as.data.frame(do.call(rbind, lapply(records, flatten_rec)),
                    stringsAsFactors = FALSE)

raw_path <- file.path(OUTDIR, sprintf("abu_public_records_%s.json", stamp))
csv_path <- file.path(OUTDIR, sprintf("abu_public_records_%s.csv",  stamp))
ug_path  <- file.path(OUTDIR, sprintf("abu_urogynecology_%s.csv",   stamp))
rcpt_path<- file.path(OUTDIR, sprintf("abu_scrape_receipt_%s.json",  stamp))

jsonlite::write_json(records, raw_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
utils::write.csv(df, csv_path, row.names = FALSE, na = "")

is_urogyn <- grepl(UROGYN_RE, df$Subspecialty, ignore.case = TRUE)
utils::write.csv(df[is_urogyn, , drop = FALSE], ug_path, row.names = FALSE, na = "")

subspec  <- sort(table(df$Subspecialty), decreasing = TRUE)
certtype <- sort(table(df$CertificationType), decreasing = TRUE)
receipt <- list(
  source_url = "https://portal.abu.org/static/verification/index.html",
  api = paste0(BASE, "?page=N"),
  scraped_utc = format(as.POSIXlt(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ"),
  method = paste("paginate ?page=1..N (empty name = full registry); dedupe by",
                 "(Name,City,State,CertificationType,CertificationYear); stop on empty page"),
  total_unique_records = nrow(df),
  urogynecology_count = sum(is_urogyn),
  subspecialty_breakdown = as.list(subspec),
  certification_type_breakdown = as.list(certtype),
  outputs = list(raw_json = raw_path, full_csv = csv_path, urogyn_csv = ug_path)
)
jsonlite::write_json(receipt, rcpt_path, auto_unbox = TRUE, pretty = TRUE)

# ---- summary ----------------------------------------------------------------
cat("\n=== DONE ===\n")
cat(sprintf("  total unique records : %d\n", nrow(df)))
cat(sprintf("  urogynecology (FPMRS): %d\n", sum(is_urogyn)))
cat("  subspecialties       :\n"); print(subspec)
cat("  cert types           :\n"); print(certtype)
cat(sprintf("  outputs in           : %s\n", OUTDIR))
