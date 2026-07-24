#!/usr/bin/env Rscript
# abu_npi.r — match scraped ABU (American Board of Urology) physicians to NPIs.
#
# Input : the ABU scrape produced by scripts/abu_scraper.r
#         (default: the urogynecology / female-urology subset).
# Method: parse each ABU "Name" with the MANDATED parser
#         parse_physician_name_enhanced() (CLAUDE.md #3), then query the public
#         NPPES registry (https://npiregistry.cms.hhs.gov/api/) with the same
#         three-tier strategy the pipeline already uses (R/apply_ent_ssot_subspecialty.R):
#           1. first + last + state   (exact)
#           2. first + last           (no state — moves / PO-Box state)
#           3. last  + state          (first name is a single initial)
#         Then VERIFY the candidate is a urologist by taxonomy code so we don't
#         match a same-named physician in another specialty:
#           208800000X  Urology
#           2088F0040X  Female Pelvic Medicine & Reconstructive Surgery (Urology) <- FPMRS
#           2088P0231X  Pediatric Urology
# Output: an ABU->NPI crosswalk (+ unmatched list + receipt) in data/abu_urology/.
#         Confidence is graded by match tier + name agreement + taxonomy + city.
#
# Usage : Rscript scripts/abu_npi.r [input_csv]
#   env   ABU_NPI_INPUT   override input csv (default: latest abu_urogynecology_*.csv)
#         ABU_NPI_LIMIT   process only the first N rows (smoke test)
#         ABU_NPI_RATE_S  seconds between API calls (default 0.5)
# Deps  : httr, jsonlite  (name parser sources standalone).

suppressWarnings(suppressMessages({
  ok <- requireNamespace("httr", quietly = TRUE) && requireNamespace("jsonlite", quietly = TRUE)
}))
if (!ok) stop("abu_npi.r needs 'httr' and 'jsonlite'.", call. = FALSE)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
ROOT <- tryCatch(if (requireNamespace("here", quietly = TRUE)) here::here() else getwd(), error = function(e) getwd())

# ---- mandated name parser (CLAUDE.md #3) ------------------------------------
np <- file.path(ROOT, "R", "name_parsing_protocol_enhanced.R")
if (!file.exists(np)) stop("Cannot find R/name_parsing_protocol_enhanced.R", call. = FALSE)
suppressWarnings(suppressMessages(source(np)))

# ---- config -----------------------------------------------------------------
OUTDIR   <- file.path(ROOT, "data", "abu_urology")
API_BASE <- "https://npiregistry.cms.hhs.gov/api/"
RATE_S   <- as.numeric(Sys.getenv("ABU_NPI_RATE_S", "0.5"))
UROLOGY_TAX <- c("208800000X", "2088F0040X", "2088P0231X")
FPMRS_TAX   <- "2088F0040X"

norm <- function(x) toupper(gsub("[^A-Za-z]", "", as.character(x %||% "")))

pick_input <- function() {
  a <- commandArgs(trailingOnly = TRUE)
  if (length(a) >= 1L && nzchar(a[1])) return(a[1])
  if (nzchar(Sys.getenv("ABU_NPI_INPUT"))) return(Sys.getenv("ABU_NPI_INPUT"))
  cand <- sort(list.files(OUTDIR, pattern = "^abu_urogynecology_.*\\.csv$", full.names = TRUE),
               decreasing = TRUE)
  if (length(cand) == 0L)
    stop("No abu_urogynecology_*.csv found in ", OUTDIR, " — run scripts/abu_scraper.r first.", call. = FALSE)
  cand[1]
}

# ---- NPPES API query (mirrors R/apply_ent_ssot_subspecialty.R) ---------------
nppes_query <- function(params) {
  params$version          <- "2.1"
  params$enumeration_type <- "NPI-1"
  params$limit            <- 20L
  resp <- tryCatch(httr::GET(API_BASE, query = params, httr::timeout(15)), error = function(e) NULL)
  if (is.null(resp) || httr::http_error(resp)) return(NULL)
  parsed <- tryCatch(
    jsonlite::fromJSON(httr::content(resp, as = "text", encoding = "UTF-8"), simplifyVector = FALSE),
    error = function(e) NULL)
  if (is.null(parsed) || (parsed$result_count %||% 0) == 0) return(NULL)
  parsed$results
}

# taxonomy codes on an NPPES result + primary description
result_tax <- function(r) {
  codes <- vapply(r$taxonomies %||% list(), function(t) as.character(t$code %||% ""), character(1))
  prim  <- ""
  for (t in r$taxonomies %||% list()) if (isTRUE(t$primary)) prim <- as.character(t$desc %||% "")
  list(codes = codes, primary_desc = prim)
}
result_city_state <- function(r) {
  for (a in r$addresses %||% list()) if (identical(a$address_purpose, "LOCATION"))
    return(list(city = a$city %||% NA_character_, state = a$state %||% NA_character_))
  a <- (r$addresses %||% list())[[1]] %||% list()
  list(city = a$city %||% NA_character_, state = a$state %||% NA_character_)
}

# choose the best urology result for one physician; return a one-row list or NULL
choose_match <- function(results, pfirst, plast, pstate, pcity) {
  urol <- Filter(function(r) any(result_tax(r)$codes %in% UROLOGY_TAX), results)
  cand_pool <- if (length(urol) > 0L) urol else list()  # require urology taxonomy
  if (length(cand_pool) == 0L) return(NULL)
  score_one <- function(r) {
    b <- r$basic %||% list(); tx <- result_tax(r); cs <- result_city_state(r)
    last_ok  <- norm(b$last_name) == norm(plast) && nzchar(norm(plast))
    first_ok <- norm(b$first_name) == norm(pfirst) && nzchar(norm(pfirst))
    first_ini<- nzchar(norm(pfirst)) && substr(norm(b$first_name), 1, 1) == substr(norm(pfirst), 1, 1)
    state_ok <- nzchar(norm(pstate)) && norm(cs$state) == norm(pstate)
    city_ok  <- nzchar(norm(pcity)) && norm(cs$city) == norm(pcity)
    fpmrs    <- FPMRS_TAX %in% tx$codes
    s <- 0
    if (last_ok)  s <- s + 3
    if (first_ok) s <- s + 3 else if (first_ini) s <- s + 1
    if (state_ok) s <- s + 2
    if (city_ok)  s <- s + 1
    if (fpmrs)    s <- s + 1
    list(r = r, score = s, last_ok = last_ok, first_ok = first_ok, first_ini = first_ini,
         state_ok = state_ok, city_ok = city_ok, fpmrs = fpmrs, tx = tx, cs = cs, b = b)
  }
  scored <- lapply(cand_pool, score_one)
  scored <- scored[order(-vapply(scored, function(x) x$score, numeric(1)))]
  best <- scored[[1]]
  # require at least a last-name agreement to accept
  if (!isTRUE(best$last_ok)) return(NULL)
  best$n_candidates <- length(cand_pool)
  best$ambiguous <- length(scored) > 1L && scored[[2]]$score == best$score
  best
}

grade <- function(tier, m) {
  if (is.null(m)) return("unmatched")
  if (m$ambiguous) return("ambiguous")
  if (tier == 1 && m$state_ok && (m$first_ok || m$first_ini) && m$last_ok) return("high")
  if (m$first_ok && m$last_ok) return("medium")
  if (m$last_ok && (m$state_ok || m$city_ok)) return("medium")
  "low"
}

# ---- run --------------------------------------------------------------------
input <- pick_input()
if (!file.exists(input)) stop("Input not found: ", input, call. = FALSE)
abu <- utils::read.csv(input, stringsAsFactors = FALSE, colClasses = "character")
lim <- suppressWarnings(as.integer(Sys.getenv("ABU_NPI_LIMIT", "")))
if (!is.na(lim) && lim > 0L) abu <- head(abu, lim)
message(sprintf("[abu_npi] input: %s (%d rows)  rate=%.2fs", input, nrow(abu), RATE_S))

out <- vector("list", nrow(abu))
for (i in seq_len(nrow(abu))) {
  nm <- abu$Name[i]; st <- abu$State[i]; cy <- abu$City[i]
  p <- tryCatch(parse_physician_name_enhanced(nm), error = function(e) NULL)
  pf <- if (!is.null(p)) as.character(p$first_name[1]) else NA_character_
  pl <- if (!is.null(p)) as.character(p$last_name[1])  else NA_character_
  is_initial <- grepl("^[A-Za-z]\\.?$", trimws(pf %||% ""))

  m <- NULL; tier <- NA_integer_
  if (!is.na(pl) && nzchar(pl)) {
    # Tier 1: first + last + state
    if (!is_initial && nzchar(norm(st)) && nchar(trimws(st)) == 2) {
      r1 <- nppes_query(list(first_name = pf, last_name = pl, state = trimws(st))); Sys.sleep(RATE_S)
      m <- choose_match(r1 %||% list(), pf, pl, st, cy); if (!is.null(m)) tier <- 1L
    }
    # Tier 2: first + last
    if (is.null(m) && !is_initial) {
      r2 <- nppes_query(list(first_name = pf, last_name = pl)); Sys.sleep(RATE_S)
      m <- choose_match(r2 %||% list(), pf, pl, st, cy); if (!is.null(m)) tier <- 2L
    }
    # Tier 3: last + state (initial first name)
    if (is.null(m) && nzchar(norm(st)) && nchar(trimws(st)) == 2) {
      r3 <- nppes_query(list(last_name = pl, state = trimws(st))); Sys.sleep(RATE_S)
      m <- choose_match(r3 %||% list(), pf, pl, st, cy); if (!is.null(m)) tier <- 3L
    }
  }
  conf <- grade(tier %||% NA_integer_, m)
  out[[i]] <- data.frame(
    abu_name = nm, abu_city = cy, abu_state = st,
    abu_subspecialty = abu$Subspecialty[i] %||% NA, abu_cert_year = abu$CertificationYear[i] %||% NA,
    parsed_first = pf %||% NA, parsed_last = pl %||% NA,
    npi = if (!is.null(m)) as.character(m$r$number) else NA_character_,
    nppes_first = if (!is.null(m)) (m$b$first_name %||% NA) else NA,
    nppes_last  = if (!is.null(m)) (m$b$last_name  %||% NA) else NA,
    nppes_city  = if (!is.null(m)) (m$cs$city  %||% NA) else NA,
    nppes_state = if (!is.null(m)) (m$cs$state %||% NA) else NA,
    nppes_primary_taxonomy = if (!is.null(m)) (m$tx$primary_desc %||% NA) else NA,
    has_urology_taxonomy = if (!is.null(m)) TRUE else NA,
    has_fpmrs_taxonomy   = if (!is.null(m)) m$fpmrs else NA,
    match_tier = tier %||% NA_integer_, match_confidence = conf,
    n_candidates = if (!is.null(m)) m$n_candidates else 0L,
    stringsAsFactors = FALSE)
  if (i %% 25 == 0 || i == nrow(abu))
    message(sprintf("  %d/%d  %-28s -> %s [%s]", i, nrow(abu), substr(nm, 1, 28),
                    out[[i]]$npi %||% "—", conf))
}
res <- do.call(rbind, out)

# ---- write outputs ----------------------------------------------------------
dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)
stamp <- as.character(Sys.Date())
xwalk_path   <- file.path(OUTDIR, sprintf("abu_npi_crosswalk_%s.csv", stamp))
unmatch_path <- file.path(OUTDIR, sprintf("abu_npi_unmatched_%s.csv", stamp))
rcpt_path    <- file.path(OUTDIR, sprintf("abu_npi_receipt_%s.json", stamp))
utils::write.csv(res, xwalk_path, row.names = FALSE, na = "")
utils::write.csv(res[is.na(res$npi) | res$match_confidence %in% c("unmatched", "ambiguous"), , drop = FALSE],
                 unmatch_path, row.names = FALSE, na = "")

conf_tab <- table(factor(res$match_confidence,
                         levels = c("high", "medium", "low", "ambiguous", "unmatched")))
receipt <- list(
  input = input, api = API_BASE, method = "three-tier NPPES query + urology-taxonomy verification",
  name_parser = "parse_physician_name_enhanced() (CLAUDE.md #3)",
  urology_taxonomy_codes = UROLOGY_TAX, run_utc = format(as.POSIXlt(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ"),
  n_input = nrow(res), n_with_npi = sum(!is.na(res$npi)),
  n_fpmrs_taxonomy = sum(isTRUE(res$has_fpmrs_taxonomy) | res$has_fpmrs_taxonomy %in% TRUE, na.rm = TRUE),
  confidence_breakdown = as.list(conf_tab),
  outputs = list(crosswalk = xwalk_path, unmatched = unmatch_path))
jsonlite::write_json(receipt, rcpt_path, auto_unbox = TRUE, pretty = TRUE)

cat("\n=== DONE ===\n")
cat(sprintf("  input rows        : %d\n", nrow(res)))
cat(sprintf("  matched to NPI    : %d (%.0f%%)\n", sum(!is.na(res$npi)), 100 * mean(!is.na(res$npi))))
cat("  confidence        :\n"); print(conf_tab)
cat(sprintf("  crosswalk         : %s\n", xwalk_path))
cat(sprintf("  unmatched/ambig   : %s\n", unmatch_path))
cat("\n  NOTE: join into the cohort with safe_left_join() (CLAUDE.md #6); dedupe vs\n")
cat("  ABOG-pathway FPMRS before adding — dual-boarded (ABOG+ABU) NPIs are already present.\n")
