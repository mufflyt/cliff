#!/usr/bin/env Rscript
# abu_fetch_addresses.r — pull NPPES LOCATION practice addresses for the ABU
# net-new FPMRS NPIs (from abu_fpmrs_net_new_npis_*.txt), so they can be geocoded
# and coverage-checked against the existing isochrones (CLAUDE.md #17) for the
# "FPMRS incl. urology pathway" access sensitivity arm.
suppressWarnings(suppressMessages(
  ok <- requireNamespace("httr", quietly=TRUE) && requireNamespace("jsonlite", quietly=TRUE)))
if (!ok) stop("needs httr + jsonlite", call.=FALSE)
`%||%` <- function(a,b) if (is.null(a)||length(a)==0L||(length(a)==1L&&is.na(a))) b else a
ROOT <- tryCatch(if (requireNamespace("here",quietly=TRUE)) here::here() else getwd(), error=function(e) getwd())
OUT  <- file.path(ROOT,"data","abu_urology")
API  <- "https://npiregistry.cms.hhs.gov/api/"
RATE <- as.numeric(Sys.getenv("ABU_NPI_RATE_S","0.4"))

# Read the ACTIVE net-new list (from abu_urps_finalize.r) explicitly — the loose
# "..._npis_.*" pattern also matches a legacy non-active list and is order-fragile.
.nn <- sort(list.files(OUT,"^abu_fpmrs_net_new_npis_active_.*\\.txt$",full.names=TRUE),decreasing=TRUE)
if (!length(.nn)) stop("no abu_fpmrs_net_new_npis_active_*.txt in ", OUT, " — run abu_urps_finalize.r first", call.=FALSE)
npis <- readLines(.nn[1])
npis <- npis[nzchar(npis)]
message(sprintf("[addresses] %d net-new NPIs", length(npis)))

loc <- function(r){ for (a in r$addresses %||% list()) if (identical(a$address_purpose,"LOCATION")) return(a)
  (r$addresses %||% list())[[1]] %||% list() }
rows <- list()
for (i in seq_along(npis)) {
  resp <- tryCatch(httr::GET(API, query=list(version="2.1",number=npis[i]), httr::timeout(15)), error=function(e) NULL)
  r <- NULL
  if (!is.null(resp) && !httr::http_error(resp)) {
    p <- tryCatch(jsonlite::fromJSON(httr::content(resp,"text",encoding="UTF-8"),simplifyVector=FALSE),error=function(e) NULL)
    if (!is.null(p) && (p$result_count %||% 0) > 0) r <- p$results[[1]]
  }
  b <- (r$basic %||% list()); a <- if (!is.null(r)) loc(r) else list()
  zip <- as.character(a$postal_code %||% "")
  rows[[i]] <- data.frame(npi=npis[i],
    first_name=b$first_name %||% NA, last_name=b$last_name %||% NA,
    address=a$address_1 %||% NA, city=a$city %||% NA, state=a$state %||% NA,
    zip5=if (nchar(zip)>=5) substr(zip,1,5) else zip,
    primary_taxonomy=paste(unique(sapply(r$taxonomies %||% list(), function(t) t$desc %||% "")), collapse="; "),
    stringsAsFactors=FALSE)
  Sys.sleep(RATE)
  if (i %% 40 == 0 || i == length(npis)) message(sprintf("  %d/%d", i, length(npis)))
}
df <- do.call(rbind, rows)
path <- file.path(OUT, sprintf("abu_fpmrs_net_new_roster_%s.csv", as.character(Sys.Date())))
utils::write.csv(df, path, row.names=FALSE, na="")
cat(sprintf("\n=== DONE ===\n  rows=%d  with_address=%d\n  file: %s\n",
            nrow(df), sum(!is.na(df$address)), path))
cat("  top states:\n"); print(head(sort(table(df$state),decreasing=TRUE),10))
