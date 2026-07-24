#!/usr/bin/env Rscript
# abu_urps_finalize.r — (1) drop the 4 "Urology — Retired" URPS physicians and
# (2) attach authoritative Male/Female from the NPPES bulk file (Provider Gender
# Code, via the local NPPES DuckDB), then refresh the active-URPS artifacts and
# the ABOG-vs-ABU comparison gender rows.
suppressWarnings(suppressMessages({library(DBI); library(duckdb); library(dplyr)}))
`%||%` <- function(a,b) if (is.null(a)||length(a)==0L) b else a
ROOT <- tryCatch(if (requireNamespace("here",quietly=TRUE)) here::here() else getwd(), error=function(e) getwd())
OUT  <- file.path(ROOT,"data","abu_urology")

# latest file matching a pattern (dates sort lexically) — re-run safe, no hardcoded date
latest <- function(pat) { f <- sort(list.files(OUT, pat, full.names=TRUE), decreasing=TRUE)
  if (!length(f)) stop(sprintf("no file matching %s in %s", pat, OUT), call.=FALSE); f[1] }

urogyn <- read.csv(latest("^abu_urogynecology_.*\\.csv$"), stringsAsFactors=FALSE)
active <- urogyn %>% filter(!grepl("Retired", CertificationType))
retired<- urogyn %>% filter(grepl("Retired", CertificationType))
cat(sprintf("[finalize] URPS scraped=%d  active=%d  retired removed=%d (%s)\n",
    nrow(urogyn), nrow(active), nrow(retired), paste(retired$Name, collapse="; ")))

# matched NPIs (crosswalk + recovered), restricted to ACTIVE (drop the 4 retired by name)
xw <- read.csv(latest("^abu_npi_crosswalk_.*\\.csv$"), colClasses="character")
rc <- read.csv(latest("^abu_npi_recovered_.*\\.csv$"), colClasses="character")
matched <- bind_rows(
  xw %>% transmute(abu_name, npi, city=abu_city, state=abu_state, conf=match_confidence),
  rc %>% transmute(abu_name, npi, city=abu_city, state=abu_state, conf=match_confidence)) %>%
  filter(!is.na(npi) & nzchar(npi)) %>% filter(!(abu_name %in% retired$Name)) %>%
  distinct(npi, .keep_all=TRUE)
cat(sprintf("  active matched unique NPIs: %d\n", nrow(matched)))

# --- authoritative NPPES gender (Provider Gender Code) via DuckDB -------------
# Resolve the NPPES DuckDB via the canonical path resolver (CLAUDE.md #13), never
# hardcode the external-drive path (breaks on " 1" mount drift / other machines).
`%||%` <- function(a,b) if (is.null(a)||length(a)==0L||!nzchar(a)) b else a
nppes_db <- tryCatch({
  suppressWarnings(suppressMessages(source(file.path(ROOT,"R","utils","load_paths.R"))))
  lp <- load_paths(); (lp$nppes_db_path %||% lp$nber_duckdb_main %||% "")
}, error=function(e) "")
if (!nzchar(nppes_db) || !file.exists(nppes_db)) {
  stop("NPPES DuckDB not resolvable via load_paths() (nppes_db_path / nber_duckdb_main). ",
       "Set it in config/paths.local.yml or mount the external drive.", call.=FALSE)
}
con <- dbConnect(duckdb(), nppes_db, read_only=TRUE)
# Pick the latest NPPES bulk table with NPI + "Provider Gender Code" (don't hardcode
# npi_dec_2024 — a DB refresh may add a newer snapshot). Prefer npi_* names, newest last.
.tabs <- DBI::dbListTables(con)
.gender_tabs <- Filter(function(t) {
  cols <- tryCatch(DBI::dbListFields(con, t), error=function(e) character(0))
  "NPI" %in% cols && "Provider Gender Code" %in% cols
}, .tabs)
if (length(.gender_tabs) == 0L) { DBI::dbDisconnect(con, shutdown=TRUE)
  stop("No NPPES table with NPI + 'Provider Gender Code' found in the DuckDB.", call.=FALSE) }
.npi_tab <- { pref <- grep("^npi_", .gender_tabs, value=TRUE, ignore.case=TRUE)
  sort(if (length(pref)) pref else .gender_tabs, decreasing=TRUE)[1] }
message(sprintf("  NPPES gender table: %s", .npi_tab))
npi_list <- paste(sprintf("'%s'", unique(matched$npi)), collapse=",")
g <- dbGetQuery(con, sprintf(
  'SELECT CAST("NPI" AS VARCHAR) AS npi, "Provider Gender Code" AS gender
   FROM "%s" WHERE CAST("NPI" AS VARCHAR) IN (%s)', .npi_tab, npi_list))
dbDisconnect(con, shutdown=TRUE)
matched$gender <- g$gender[match(matched$npi, g$npi)]
matched$gender[is.na(matched$gender) | !(matched$gender %in% c("M","F"))] <- NA
n_g <- sum(!is.na(matched$gender))
cat(sprintf("  gender resolved from NPPES: %d/%d (%.0f%%)  F=%d M=%d\n",
    n_g, nrow(matched), 100*n_g/nrow(matched), sum(matched$gender=="F",na.rm=T), sum(matched$gender=="M",na.rm=T)))

# --- write active-URPS-with-gender + refreshed net-new ------------------------
stamp <- as.character(Sys.Date())
write.csv(matched, file.path(OUT, sprintf("abu_urps_active_with_gender_%s.csv", stamp)), row.names=FALSE, na="")

# refresh net-new (active only) vs ABOG cohort
abog <- readRDS(file.path(ROOT,"data","abog_pipeline","canonical_abog_npi_LATEST.rds"))
abog_all <- unique(na.omit(as.character(abog$npi)))
net_new <- setdiff(unique(matched$npi), abog_all)
writeLines(net_new, file.path(OUT, sprintf("abu_fpmrs_net_new_npis_active_%s.txt", stamp)))
cat(sprintf("  active net-new to ABOG cohort: %d\n", length(net_new)))

# --- gender summary for the comparison ---------------------------------------
cat("\n=== ACTIVE ABU URPS gender (NPPES) ===\n")
print(table(factor(matched$gender, levels=c("F","M")), useNA="ifany"))
cat(sprintf("  female share (of known): %.1f%%\n", 100*sum(matched$gender=="F",na.rm=T)/max(n_g,1)))
