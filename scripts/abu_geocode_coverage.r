#!/usr/bin/env Rscript
# abu_geocode_coverage.r — geocode the ABU net-new FPMRS roster and check how many
# fall within EXISTING isochrone coverage (5 km haversine, CLAUDE.md #17), so we
# know the EC2 isochrone-generation scope for the "FPMRS incl. urology" access arm.
#
# 1) geocode roster addresses via the free US Census batch geocoder (no key)
# 2) parse the consolidated isochrone origins from location_key ("lat_lon")
# 3) match_points_to_isochrones(threshold_km = 5.0)  -> covered vs uncovered
#
# Usage: Rscript scripts/abu_geocode_coverage.r
suppressWarnings(suppressMessages({
  ok <- all(vapply(c("httr","dplyr"), requireNamespace, logical(1), quietly = TRUE))}))
if (!ok) stop("needs httr + dplyr", call. = FALSE)
`%||%` <- function(a,b) if (is.null(a)||length(a)==0L||(length(a)==1L&&is.na(a))) b else a
ROOT <- tryCatch(if (requireNamespace("here",quietly=TRUE)) here::here() else getwd(), error=function(e) getwd())
OUT  <- file.path(ROOT,"data","abu_urology")
NON_CONUS <- c("AK","HI","PR","GU","VI","AS","MP","FS")

roster <- utils::read.csv(sort(list.files(OUT,"^abu_fpmrs_net_new_roster_.*\\.csv$",full.names=TRUE),
                               decreasing=TRUE)[1], stringsAsFactors=FALSE, colClasses="character")
roster <- roster[!is.na(roster$address) & nzchar(roster$address) & !(roster$state %in% NON_CONUS), ]
message(sprintf("[coverage] %d CONUS roster rows to geocode", nrow(roster)))

# ---- 1) Census batch geocoder ------------------------------------------------
gc_csv <- tempfile(fileext = ".csv")
utils::write.table(
  data.frame(id=seq_len(nrow(roster)), street=roster$address, city=roster$city,
             state=roster$state, zip=roster$zip5),
  gc_csv, sep=",", row.names=FALSE, col.names=FALSE, qmethod="double", na="")
resp <- httr::POST("https://geocoding.geo.census.gov/geocoder/locations/addressbatch",
  body=list(addressFile=httr::upload_file(gc_csv), benchmark="Public_AR_Current"),
  encode="multipart", httr::timeout(300))
if (httr::http_error(resp)) stop("Census geocoder HTTP ", httr::status_code(resp), call.=FALSE)
gtxt <- httr::content(resp, as="text", encoding="UTF-8")
g <- utils::read.csv(text=gtxt, header=FALSE, stringsAsFactors=FALSE,
  col.names=c("id","input","match","mtype","matched","lonlat","tiger","side"),
  colClasses="character", fill=TRUE)
parse_ll <- function(s){ p<-strsplit(s,",")[[1]]; if (length(p)==2) as.numeric(p) else c(NA,NA) }
ll <- t(vapply(g$lonlat, parse_ll, numeric(2))); colnames(ll)<-c("longitude","latitude")
g <- cbind(g, ll)
g$id <- as.integer(g$id); g <- g[order(g$id), ]
roster$longitude <- g$longitude[match(seq_len(nrow(roster)), g$id)]
roster$latitude  <- g$latitude[match(seq_len(nrow(roster)), g$id)]
roster$geocode_match <- g$match[match(seq_len(nrow(roster)), g$id)]
n_geo <- sum(!is.na(roster$latitude))
message(sprintf("  geocoded %d / %d (%.0f%%)", n_geo, nrow(roster), 100*n_geo/nrow(roster)))

# ---- 2) isochrone origins from location_key ---------------------------------
iso_raw <- readRDS(file.path(ROOT,"artifacts","isochrones","isochrones_30min_consolidated.rds"))
lk <- unique(as.character(if (requireNamespace("sf",quietly=TRUE) && inherits(iso_raw,"sf"))
                          sf::st_drop_geometry(iso_raw)$location_key else iso_raw$location_key))
lk <- lk[!is.na(lk) & grepl("_", lk)]
sp <- do.call(rbind, strsplit(lk, "_"))
iso_centers <- data.frame(latitude=as.numeric(sp[,1]), longitude=as.numeric(sp[,2]),
                          location_key=lk, stringsAsFactors=FALSE)
iso_centers <- iso_centers[!is.na(iso_centers$latitude) & !is.na(iso_centers$longitude), ]
message(sprintf("  %d unique existing isochrone origins", nrow(iso_centers)))

# ---- 3) 5 km haversine coverage match (canonical matcher, CLAUDE.md #17) -----
source(file.path(ROOT,"R","match_points_to_isochrones.R"))
pts <- roster[!is.na(roster$latitude), ]
m <- match_points_to_isochrones(pts, iso_centers, threshold_km = 5.0, point_id_col = "npi")
# The matcher returns ONLY points within threshold (covered); unmatched are absent.
id_col <- intersect(c("point_id",".point_id"), names(m))[1]
covered_ids <- if (!is.na(id_col)) unique(as.character(m[[id_col]])) else character(0)
n_cov <- length(covered_ids)
roster$within_existing_iso <- as.character(roster$npi) %in% covered_ids

# ---- outputs -----------------------------------------------------------------
stamp <- as.character(Sys.Date())
utils::write.csv(roster, file.path(OUT, sprintf("abu_fpmrs_net_new_geocoded_%s.csv", stamp)), row.names=FALSE, na="")
utils::write.csv(m, file.path(OUT, sprintf("abu_fpmrs_coverage_%s.csv", stamp)), row.names=FALSE, na="")
cat("\n=== COVERAGE (5 km haversine vs existing isochrones) ===\n")
cat(sprintf("  net-new CONUS roster       : %d\n", nrow(roster)))
cat(sprintf("  geocoded                   : %d\n", n_geo))
cat(sprintf("  WITHIN existing coverage   : %d  (no new isochrone needed)\n", n_cov))
cat(sprintf("  NOT covered (need new iso) : %d  -> EC2 Valhalla scope\n", nrow(pts) - n_cov))
cat(sprintf("  ungeocoded (unknown cov.)  : %d  -> address cleanup / fallback geocoder\n", nrow(roster) - n_geo))
cat(sprintf("  outputs: abu_fpmrs_net_new_geocoded_%s.csv, abu_fpmrs_coverage_%s.csv\n", stamp, stamp))
