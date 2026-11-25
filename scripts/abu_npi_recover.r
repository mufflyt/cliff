#!/usr/bin/env Rscript
# abu_npi_recover.r — second-pass NPI recovery for ABU physicians the strict
# first pass (abu_npi.r) left unmatched. Parses names with the governed mysterycall parser after
# stripping the trailing credential (", MD" / ", MBBS" ...), then queries NPPES
# and verifies the urology/FPMRS taxonomy so recoveries are not false matches.
#
# Usage: Rscript scripts/abu_npi_recover.r

suppressWarnings(suppressMessages(
  ok <- all(vapply(c("httr","jsonlite","mysterycall","mysterynpi"), requireNamespace, logical(1), quietly = TRUE))))
if (!ok) stop("needs httr + jsonlite + mysterycall + mysterynpi", call. = FALSE)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
ROOT   <- tryCatch(if (requireNamespace("here", quietly = TRUE)) here::here() else getwd(), error = function(e) getwd())
OUTDIR <- file.path(ROOT, "data", "abu_urology")
API    <- "https://npiregistry.cms.hhs.gov/api/"
RATE_S <- as.numeric(Sys.getenv("ABU_NPI_RATE_S", "0.5"))
UROLOGY_TAX <- c("208800000X", "2088F0040X", "2088P0231X"); FPMRS_TAX <- "2088F0040X"
norm <- function(x) toupper(gsub("[^A-Za-z]", "", as.character(x %||% "")))

# strip trailing credential, parse with mysterycall -> first + last (+ compound fallback)
parse_nm <- function(full) {
  clean <- sub(",\\s*(MD|D\\.?O\\.?|MBBS|MBBCh|MPH|MSc|PhD|FACOG|FACS|FPMRS)\\b.*$", "", full, ignore.case = TRUE)
  p <- tryCatch(mysterycall::mysterycall_parse_physician_name(trimws(clean), remove_titles = TRUE),
                error = function(e) NULL)
  if (is.null(p) || !nrow(p)) return(list(first = NA_character_, cands = character(0)))
  pv <- mysterycall::mysterycall_validate_parsed_names(p[1, , drop = FALSE])
  first <- trimws(pv$first_name[1] %||% "")
  last  <- trimws(gsub(",", "", pv$last_name[1] %||% ""))
  mid   <- trimws(gsub(",", "", pv$middle_name[1] %||% ""))
  # compound-surname fallback: last token, and (last middle-token + last)
  mid_tokens <- strsplit(mid, "\\s+")[[1]]
  mid_tokens <- mid_tokens[nzchar(mid_tokens)]
  cands <- unique(c(last, if (length(mid_tokens)) paste(tail(mid_tokens, 1), last)))
  list(first = first, cands = cands[nzchar(cands)])
}

nppes_query <- function(params) {
  params$version <- "2.1"; params$enumeration_type <- "NPI-1"; params$limit <- 50L
  resp <- tryCatch(httr::GET(API, query = params, httr::timeout(15)), error = function(e) NULL)
  if (is.null(resp) || httr::http_error(resp)) return(NULL)
  p <- tryCatch(jsonlite::fromJSON(httr::content(resp, "text", encoding = "UTF-8"), simplifyVector = FALSE),
                error = function(e) NULL)
  if (is.null(p) || (p$result_count %||% 0) == 0) return(NULL)
  p$results
}
result_tax <- function(r) {
  codes <- vapply(r$taxonomies %||% list(), function(t) as.character(t$code %||% ""), character(1))
  prim <- ""; for (t in r$taxonomies %||% list()) if (isTRUE(t$primary)) prim <- as.character(t$desc %||% "")
  list(codes = codes, primary_desc = prim)
}
result_cs <- function(r) {
  for (a in r$addresses %||% list()) if (identical(a$address_purpose, "LOCATION"))
    return(list(city = a$city %||% NA, state = a$state %||% NA))
  a <- (r$addresses %||% list())[[1]] %||% list(); list(city = a$city %||% NA, state = a$state %||% NA)
}
# These are already KNOWN ABU-certified urologists, so prefer a urology-taxonomy
# match for disambiguation but ACCEPT a unique first+last match even when NPPES
# lists a non-urology/generic taxonomy (e.g. Farzeen Firoozi -> 174400000X).
# Name evidence, initial handling, and taxonomy allowlist membership are canonical
# mysterynpi primitives; the acceptance policy remains recovery-specific.
best_urology <- function(results, first, last, st, cy, query_tier = NA_integer_) {
  results <- results %||% list()
  if (!length(results)) return(NULL)

  score_one <- function(x) {
    b <- x$basic %||% list(); tx <- result_tax(x); cs <- result_cs(x)
    evidence <- mysterynpi::npi_match_evidence(
      roster_given = first, roster_surname = last,
      candidate_given = b$first_name %||% NA_character_,
      candidate_surname = b$last_name %||% NA_character_,
      roster_state = st, candidate_state = cs$state,
      roster_city = cy, candidate_city = cs$city
    )
    surname_ok <- evidence$surname_verdict[1] == "corroborates"
    fo <- evidence$given_verdict[1] == "corroborates" &&
      evidence$given_reason[1] == "exact"
    fi <- evidence$given_verdict[1] == "corroborates" &&
      evidence$given_reason[1] == "initial"
    if (!surname_ok || !(fo || fi)) return(NULL)
    so <- evidence$state_verdict[1] == "corroborates"
    co <- evidence$city_verdict[1] == "corroborates"
    urology_ok <- isTRUE(mysterynpi::taxonomy_allowlist_consistent(
      paste(tx$codes, collapse = "|"), UROLOGY_TAX
    ))
    fpmrs <- isTRUE(mysterynpi::taxonomy_allowlist_consistent(
      paste(tx$codes, collapse = "|"), FPMRS_TAX
    ))
    s <- 3 + (if (fo) 3 else if (fi) 1 else 0) + (if (so) 2 else 0) +
         (if (co) 1 else 0) + (if (urology_ok) 2 else 0) + (if (fpmrs) 1 else 0)
    list(r=x,b=b,tx=tx,cs=cs,fo=fo,fi=fi,so=so,co=co,
         fpmrs=fpmrs, urology_ok=urology_ok, score=s, evidence=evidence)
  }

  nm_match <- Filter(Negate(is.null), lapply(results, score_one))
  if (length(nm_match) == 0L) return(NULL)
  urol <- Filter(function(x) isTRUE(x$urology_ok), nm_match)
  pool <- if (length(urol) > 0L) urol else if (length(nm_match) == 1L) nm_match else return(NULL)
  scores <- vapply(pool, function(x) x$score, numeric(1))
  winners <- pool[scores == max(scores)]
  best <- winners[[1L]]
  best$ambiguous <- length(winners) > 1L
  best$n_candidates <- length(pool)
  best$query_tier <- as.integer(query_tier)
  best
}

recovery_confidence <- function(m) {
  if (is.null(m)) return("unmatched")
  if (m$ambiguous) return("ambiguous")
  if (!m$urology_ok) return("medium_no_urology_tax")  # unique name match, NPPES taxonomy not urology
  as.character(mysterynpi::grade_npi_match_confidence(
    m$evidence, query_tier = m$query_tier, ambiguous = m$ambiguous, matched = TRUE
  ))
}

infile <- sort(list.files(OUTDIR, "^abu_npi_unmatched_.*\\.csv$", full.names = TRUE), decreasing = TRUE)[1]
if (is.na(infile)) stop("no unmatched file", call. = FALSE)
u <- utils::read.csv(infile, stringsAsFactors = FALSE, colClasses = "character")
u <- u[is.na(u$npi) | u$npi == "", , drop = FALSE]
message(sprintf("[recover] %s (%d unmatched)", basename(infile), nrow(u)))

rec <- list()
for (i in seq_len(nrow(u))) {
  full <- u$abu_name[i]; st <- u$abu_state[i]; cy <- u$abu_city[i]
  pn <- parse_nm(full); m <- NULL; used <- NA_character_
  for (lc in pn$cands) {
    qs <- c(if (nzchar(norm(st))) list(list(params=list(first_name=pn$first,last_name=lc,state=trimws(st)), tier=1L)),
            list(list(params=list(first_name=pn$first,last_name=lc), tier=2L)),
            if (nzchar(norm(st))) list(list(params=list(last_name=lc,state=trimws(st)), tier=3L)))
    for (q in qs) {
      mm <- best_urology(nppes_query(q$params), pn$first, lc, st, cy, query_tier=q$tier); Sys.sleep(RATE_S)
      if (!is.null(mm)) { m <- mm; used <- lc; break }
    }
    if (!is.null(m)) break
  }
  conf <- recovery_confidence(m)
  rec[[i]] <- data.frame(abu_name=full, abu_city=cy, abu_state=st, recovered_last=used,
    npi=if(!is.null(m)) as.character(m$r$number) else NA_character_,
    nppes_first=if(!is.null(m)) (m$b$first_name %||% NA) else NA,
    nppes_last =if(!is.null(m)) (m$b$last_name  %||% NA) else NA,
    nppes_city =if(!is.null(m)) (m$cs$city %||% NA) else NA,
    nppes_state=if(!is.null(m)) (m$cs$state %||% NA) else NA,
    nppes_primary_taxonomy=if(!is.null(m)) (m$tx$primary_desc %||% NA) else NA,
    has_urology_taxonomy=if(!is.null(m)) m$urology_ok else NA,
    has_fpmrs_taxonomy=if(!is.null(m)) m$fpmrs else NA,
    match_confidence=conf, stringsAsFactors = FALSE)
  message(sprintf("  %-38s -> %s [%s]", substr(full,1,38), rec[[i]]$npi %||% "—", conf))
}
out <- do.call(rbind, rec)
path <- file.path(OUTDIR, sprintf("abu_npi_recovered_%s.csv", as.character(Sys.Date())))
utils::write.csv(out, path, row.names = FALSE, na = "")
cat(sprintf("\n=== RECOVERY DONE ===\n  recovered %d / %d\n  file: %s\n",
            sum(!is.na(out$npi)), nrow(out), path)); print(table(out$match_confidence))
