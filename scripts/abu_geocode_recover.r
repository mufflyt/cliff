#!/usr/bin/env Rscript
# abu_geocode_recover.r — recover the ABU net-new addresses the Census BATCH
# geocoder missed, using mysterycall's Census + Nominatim/ArcGIS fallback path,
# then re-run the 5 km isochrone-coverage match on the full geocoded set.
# Usage: Rscript scripts/abu_geocode_recover.r
suppressWarnings(suppressMessages({
  ok <- all(vapply(c("mysterycall","dplyr"), requireNamespace, logical(1), quietly=TRUE))}))
if (!ok) stop("needs mysterycall + dplyr", call.=FALSE)
`%||%` <- function(a,b) if (is.null(a)||length(a)==0L) b else a
ROOT <- tryCatch(if (requireNamespace("here",quietly=TRUE)) here::here() else getwd(), error=function(e) getwd())
OUT  <- file.path(ROOT,"data","abu_urology")
source(file.path(ROOT, "scripts", "abu_isochrone_coverage.R"))

f <- sort(list.files(OUT,"^abu_fpmrs_net_new_geocoded_.*\\.csv$",full.names=TRUE),decreasing=TRUE)[1]
if (is.na(f)) stop("no geocoded file; run scripts/abu_geocode_coverage.r first", call.=FALSE)
g <- utils::read.csv(f, stringsAsFactors=FALSE, colClasses=c(zip5="character",npi="character"))
g$latitude  <- suppressWarnings(as.numeric(g$latitude))
g$longitude <- suppressWarnings(as.numeric(g$longitude))
miss <- which(is.na(g$latitude))
message(sprintf("[recover-geo] %d rows missing coords", length(miss)))

if (length(miss)) {
  sub <- g[miss, , drop = FALSE]
  geo <- mysterycall::mysterycall_geocode_address(
    sub,
    street_col = "address", city_col = "city", state_col = "state", zip_col = "zip5",
    fallback = TRUE, verbose = TRUE
  )
  sub$latitude       <- geo$geo_lat
  sub$longitude      <- geo$geo_long
  sub$geocode_match  <- geo$geo_match
  sub$geo_source     <- geo$geo_source
  g$latitude[miss]     <- sub$latitude
  g$longitude[miss]    <- sub$longitude
  g$geocode_match[miss]<- sub$geocode_match
  g$geo_source[miss]   <- sub$geo_source
}
n_geo <- sum(!is.na(g$latitude))
message(sprintf("  recovered %d; total geocoded %d / %d",
                sum(!is.na(g$latitude[miss])), n_geo, nrow(g)))

# ---- re-run 5 km coverage on the full geocoded set --------------------------
iso_raw <- readRDS(file.path(ROOT,"artifacts","isochrones","isochrones_30min_consolidated.rds"))
lk <- unique(as.character(if (requireNamespace("sf",quietly=TRUE) && inherits(iso_raw,"sf"))
                          sf::st_drop_geometry(iso_raw)$location_key else iso_raw$location_key))
lk <- lk[!is.na(lk) & grepl("_",lk)]; sp <- do.call(rbind, strsplit(lk,"_"))
iso_centers <- data.frame(latitude=as.numeric(sp[,1]), longitude=as.numeric(sp[,2]), location_key=lk)
iso_centers <- iso_centers[!is.na(iso_centers$latitude) & !is.na(iso_centers$longitude), ]

pts <- g[!is.na(g$latitude), ]
covered <- abu_covered_ids(pts, iso_centers, id_col = "npi", threshold_km = 5.0)
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
