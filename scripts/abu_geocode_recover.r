#!/usr/bin/env Rscript
# abu_geocode_recover.r — recover the ABU net-new addresses the Census BATCH
# geocoder missed, using tidygeocoder cascade (census oneline -> arcgis -> osm),
# then re-run the 5 km isochrone-coverage match on the full geocoded set.
# Usage: Rscript scripts/abu_geocode_recover.r
suppressWarnings(suppressMessages(
  ok <- all(vapply(c("tidygeocoder","dplyr"), requireNamespace, logical(1), quietly=TRUE))))
if (!ok) stop("needs tidygeocoder + dplyr", call.=FALSE)
`%||%` <- function(a,b) if (is.null(a)||length(a)==0L) b else a
ROOT <- tryCatch(if (requireNamespace("here",quietly=TRUE)) here::here() else getwd(), error=function(e) getwd())
OUT  <- file.path(ROOT,"data","abu_urology")

f <- sort(list.files(OUT,"^abu_fpmrs_net_new_geocoded_.*\\.csv$",full.names=TRUE),decreasing=TRUE)[1]
g <- utils::read.csv(f, stringsAsFactors=FALSE, colClasses=c(zip5="character",npi="character"))
g$latitude  <- suppressWarnings(as.numeric(g$latitude))
g$longitude <- suppressWarnings(as.numeric(g$longitude))
miss <- which(is.na(g$latitude))
message(sprintf("[recover-geo] %d rows missing coords", length(miss)))

mk_addr <- function(r) trimws(gsub("\\s+"," ", paste(r$address, r$city, r$state, r$zip5, sep=", ")))
sub <- g[miss, ]; sub$full <- vapply(seq_len(nrow(sub)), function(i) mk_addr(sub[i,]), character(1))

geo_try <- function(df, method) {
  suppressWarnings(suppressMessages(tryCatch(
    tidygeocoder::geocode(df, address=full, method=method, lat="lat_", long="long_", quiet=TRUE),
    error=function(e){ df$lat_<-NA_real_; df$long_<-NA_real_; df })))
}
for (meth in c("census","arcgis","osm")) {
  na <- is.na(sub$latitude)
  if (!any(na)) break
  message(sprintf("  trying %-7s on %d remaining...", meth, sum(na)))
  r <- geo_try(sub[na, "full", drop = FALSE], meth)
  sub$latitude[na]  <- ifelse(is.na(sub$latitude[na]),  r$lat_,  sub$latitude[na])
  sub$longitude[na] <- ifelse(is.na(sub$longitude[na]), r$long_, sub$longitude[na])
  sub$geocode_match[na & !is.na(sub$latitude)] <- paste0("recovered_", meth)
}
g$latitude[miss]     <- sub$latitude
g$longitude[miss]    <- sub$longitude
g$geocode_match[miss]<- sub$geocode_match
n_geo <- sum(!is.na(g$latitude))
message(sprintf("  recovered %d; total geocoded %d / %d", sum(!is.na(sub$latitude)), n_geo, nrow(g)))

# ---- re-run 5 km coverage on the full geocoded set --------------------------
iso_raw <- readRDS(file.path(ROOT,"artifacts","isochrones","isochrones_30min_consolidated.rds"))
lk <- unique(as.character(if (requireNamespace("sf",quietly=TRUE) && inherits(iso_raw,"sf"))
                          sf::st_drop_geometry(iso_raw)$location_key else iso_raw$location_key))
lk <- lk[!is.na(lk) & grepl("_",lk)]; sp <- do.call(rbind, strsplit(lk,"_"))
iso_centers <- data.frame(latitude=as.numeric(sp[,1]), longitude=as.numeric(sp[,2]), location_key=lk)
iso_centers <- iso_centers[!is.na(iso_centers$latitude) & !is.na(iso_centers$longitude), ]

source(file.path(ROOT,"R","match_points_to_isochrones.R"))
pts <- g[!is.na(g$latitude), ]
m <- match_points_to_isochrones(pts, iso_centers, threshold_km=5.0, point_id_col="npi")
id_col <- intersect(c("point_id",".point_id"), names(m))[1]
covered <- unique(as.character(m[[id_col]]))
g$within_existing_iso <- as.character(g$npi) %in% covered

stamp <- as.character(Sys.Date())
utils::write.csv(g, file.path(OUT, sprintf("abu_fpmrs_net_new_geocoded_%s.csv", stamp)), row.names=FALSE, na="")
n_cov <- sum(g$within_existing_iso & !is.na(g$latitude))
cat("\n=== FINAL COVERAGE (after geocode recovery) ===\n")
cat(sprintf("  net-new CONUS rows        : %d\n", nrow(g)))
cat(sprintf("  geocoded                  : %d (%.0f%%)\n", n_geo, 100*n_geo/nrow(g)))
cat(sprintf("  WITHIN existing coverage  : %d  (reuse existing isochrones)\n", n_cov))
cat(sprintf("  NOT covered (need new iso): %d  -> EC2 Valhalla scope\n", n_geo - n_cov))
cat(sprintf("  still ungeocoded          : %d\n", nrow(g) - n_geo))
