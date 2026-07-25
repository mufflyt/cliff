#!/usr/bin/env Rscript
# Module D add-on: DIFFERENTIAL DISTANCE — the extra travel a woman must make to
# reach a URPS urogynecologist BEYOND the nearest general OB/GYN.  Method from
# Herb et al., Am J Surg 2021 (differential/relative distance): a better access
# metric than raw distance-to-nearest because it isolates the marginal burden of
# needing subspecialty care, and it maps directly onto our ABOG+ABU pathway split.
#
#   differential_miles(county) = dist(county -> nearest urogynecologist)
#                              - dist(county -> nearest general OB/GYN)
#
# DATA DEPENDENCY (the one thing this needs): a geocoded point layer of ALL
# general OB/GYNs as the generalist comparator. Produce it from NPPES taxonomy
# 207V* via R/import_all_obgyn_isochrones.R / scripts/regeocode_all_obgyn_unknowns.R,
# write lon/lat columns, and point URPS_OBGYN_POINTS at it (CSV with lon,lat).
#
# Run:  URPS_OBGYN_POINTS=path/to/all_obgyn_geocoded.csv Rscript scripts/urps_module_d_differential_distance.R
suppressPackageStartupMessages({ library(data.table); library(sf); library(tigris) })
options(tigris_use_cache=TRUE, tigris_class="sf"); sf::sf_use_s2(TRUE)
source("R/conus.R")    # SSOT: CONUS_EXCLUDE_FIPS / is_conus_fips() / in_conus_bbox()
source("R/units.R")    # SSOT: meters_to_miles() / miles_to_meters() (METERS_PER_MILE)

read_points <- function(f) {
  d <- fread(f)
  loncol <- grep("^lon|longitude", names(d), ignore.case=TRUE, value=TRUE)[1]
  latcol <- grep("^lat|latitude",  names(d), ignore.case=TRUE, value=TRUE)[1]
  if (is.na(loncol) || is.na(latcol)) stop("point file needs lon/lat columns: ", f)
  lo <- d[[loncol]]; la <- d[[latcol]]                        # plain vectors, no dt-scope shadowing
  keep <- !is.na(lo) & !is.na(la) & in_conus_bbox(lo, la)   # CONUS box (SSOT: R/conus.R)
  st_as_sf(d[keep], coords=c(loncol, latcol), crs=4326)
}

# nearest-feature great-circle distance (miles) from each point in A to layer B
nearest_mi <- function(A, B) meters_to_miles(as.numeric(st_distance(A, B[st_nearest_feature(A, B),], by_element=TRUE)))

compute_differential_distance <- function(centroids_sf, geoid, urogyn_sf, obgyn_sf) {
  du <- nearest_mi(centroids_sf, urogyn_sf)
  dg <- nearest_mi(centroids_sf, obgyn_sf)
  data.table(GEOID=geoid, miles_to_urogyn=round(du,1), miles_to_obgyn=round(dg,1),
             differential_miles=round(du - dg, 1))
}

## ── inputs ───────────────────────────────────────────────────────────────────
URO_F   <- "data/urps_module_d_points_2026-07-23.csv"          # from Module D
OBGYN_F <- Sys.getenv("URPS_OBGYN_POINTS", "data/all_obgyn_geocoded.csv")
if (!file.exists(URO_F))  stop("Run scripts/urps_module_d_geographic_access_2026-07-23.R first (need URPS points).")
if (!file.exists(OBGYN_F)) {
  message("STOP: general-OB/GYN comparator layer not found at '", OBGYN_F, "'.")
  message("Produce it (NPPES taxonomy 207V*, geocoded, with lon/lat) via ",
          "R/import_all_obgyn_isochrones.R, then set URPS_OBGYN_POINTS. ",
          "This script is complete and will run as soon as that layer exists.")
  quit(status = 0)
}

uro_sf   <- read_points(URO_F)
obgyn_sf <- read_points(OBGYN_F)
cty <- st_transform(counties(cb=TRUE, resolution=CENSUS_CB_RESOLUTION, year=CENSUS_VINTAGE_YEAR, progress_bar=FALSE), 4326)
cty <- cty[is_conus_fips(cty$STATEFP), ]
sf_use_s2(FALSE); ctr <- suppressWarnings(st_centroid(st_geometry(cty))); sf_use_s2(TRUE)

dd <- compute_differential_distance(ctr, cty$GEOID, uro_sf, obgyn_sf)
acc <- fread("data/urps_module_d_county_access_2026-07-23.csv", colClasses=list(character="GEOID"))
out <- merge(acc[, .(GEOID, county, state, women_65plus)], dd, by="GEOID")
setorder(out, -differential_miles)
fwrite(out, "data/urps_module_d_differential_distance_2026-07-23.csv")

W <- sum(out$women_65plus)
cat(sprintf("Differential distance computed for %d CONUS counties.\n", nrow(out)))
cat(sprintf("Median extra travel to a urogynecologist beyond the nearest OB/GYN: %.1f mi\n",
            median(out$differential_miles)))
cat(sprintf("%% of women 65+ facing >30 extra miles for subspecialty care: %.1f%%\n",
            100*sum(out$women_65plus[out$differential_miles > 30])/W))
cat("Wrote data/urps_module_d_differential_distance_2026-07-23.csv\n")
