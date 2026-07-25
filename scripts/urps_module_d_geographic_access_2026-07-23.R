#!/usr/bin/env Rscript
# Module D (step 1): GEOGRAPHIC local adequacy of the urogynecology workforce.
# The national Modules A-C say capacity roughly tracks demand; Module D asks
# WHERE the ~1,339 urogynecologists actually are relative to where women 65+
# live. Metric: for each CONUS county, straight-line distance (county centroid)
# to the nearest urogynecologist, and the women-65+-per-urogyn catchment ratio.
#
# Straight-line (great-circle) access, NOT drive-time. Drive-time refinement via
# the project's Valhalla isochrone pipeline is the natural Module D v2; this v1
# gives the first defensible national picture of geographic concentration.
#
# Inputs : data/{abu,abog}_all_urps_ENRICHED_2026-07-22.csv (active only)
#          data/reference/zcta_centroids_2020.csv  (ZIP -> lat/lon)
#          ACS 2019-2023 5-yr B01001 female 65+ by county (tidycensus)
#          tigris county cartographic boundaries (2023)
# Outputs: data/urps_module_d_county_access_2026-07-23.csv
#          data/urps_module_d_points_2026-07-23.csv  (map layer)
#          data/urps_module_d_summary_2026-07-23.csv
suppressPackageStartupMessages({
  library(data.table); library(tidycensus); library(tigris); library(sf); library(dplyr)
})
options(tigris_use_cache = TRUE, tigris_class = "sf")
sf::sf_use_s2(TRUE)
source("R/conus.R")    # SSOT: CONUS_EXCLUDE_FIPS / is_conus_fips() / in_conus_bbox()  (AK, HI, PR, territories)
source("R/units.R")    # SSOT: meters_to_miles() / miles_to_meters() (METERS_PER_MILE)

## ── 1. urogynecologist point layer (active; ZIP centroid) ────────────────────
cen <- fread("data/reference/zcta_centroids_2020.csv", colClasses=list(character="zcta5"))
cen <- cen[, .(zip5=sprintf("%05d", as.integer(zcta5)), lat=centroid_lat, lon=centroid_lon)]
load_roster <- function(f, pathway){
  d <- fread(f)
  d <- if ("in_model_baseline" %in% names(d)) d[in_model_baseline==TRUE] else d
  d[, zip5 := ifelse(is.na(business_zip5), NA_character_, sprintf("%05d", business_zip5))]
  d[, .(npi, pathway=pathway, state, county_fips, zip5)]
}
uro <- rbindlist(list(
  load_roster("data/abu_all_urps_ENRICHED_2026-07-22.csv",  "ABU (urology)"),
  load_roster("data/abog_all_urps_ENRICHED_2026-07-22.csv", "ABOG (OB/GYN)")))
n_active <- nrow(uro)
uro <- merge(uro, cen, by="zip5", all.x=TRUE)
n_geo <- uro[!is.na(lat), .N]
uro <- uro[!is.na(lat) & !is.na(lon)]
n_ncon <- uro[!in_conus_bbox(lon, lat), .N]  # AK/HI/PR/territory ZIPs (SSOT: R/conus.R)
uro <- uro[in_conus_bbox(lon, lat)]
message(sprintf("Urogynecologists: %d active, %d ZIP-geocoded, %d non-CONUS dropped, %d on CONUS map",
                n_active, n_geo, n_ncon, nrow(uro)))
uro_sf <- st_as_sf(uro, coords=c("lon","lat"), crs=4326, remove=FALSE)

## ── 2. county women 65+ (ACS 2019-2023) with cache ───────────────────────────
acs_cache <- "data/_cache_acs_county_women65_2023.csv"
if (file.exists(acs_cache)) {
  w65 <- fread(acs_cache)
} else {
  vars <- sprintf("B01001_%03d", 44:49)  # female 65-66,67-69,70-74,75-79,80-84,85+
  acs <- get_acs("county", variables=vars, year=2023, survey="acs5", cache_table=TRUE)
  setDT(acs)
  w65 <- acs[, .(women_65plus=sum(estimate),
                 moe=tidycensus::moe_sum(moe, estimate)), by=.(GEOID)]
  fwrite(w65, acs_cache)
}
w65 <- w65[is_conus_fips(GEOID)]

## ── 3. county geometry + centroids (CONUS) ───────────────────────────────────
cty <- counties(cb=TRUE, resolution="20m", year=2023, progress_bar=FALSE)
cty <- st_transform(cty, 4326)
cty <- cty[is_conus_fips(cty$STATEFP), ]   # SSOT (R/conus.R); drops AK/HI + territories = 48 states + DC
cty <- merge(cty, w65, by="GEOID", all.x=TRUE)
cty$women_65plus[is.na(cty$women_65plus)] <- 0
sf_use_s2(FALSE); ctr <- suppressWarnings(st_centroid(st_geometry(cty))); sf_use_s2(TRUE)

## ── 4. distance to nearest urogynecologist + catchment counts ────────────────
idx  <- st_nearest_feature(ctr, uro_sf)
dmin <- meters_to_miles(as.numeric(st_distance(ctr, uro_sf[idx,], by_element=TRUE)))
within <- function(mi) lengths(st_is_within_distance(ctr, uro_sf, dist=miles_to_meters(mi)))
n50  <- within(50); n100 <- within(100)
# which counties physically contain >=1 urogyn
contain <- lengths(st_intersects(cty, uro_sf))

out <- data.table(
  GEOID = cty$GEOID, county = cty$NAME, state = cty$STUSPS,
  women_65plus = round(cty$women_65plus),
  women_65plus_moe = round(cty$moe),
  n_urogyn_in_county = contain,
  miles_to_nearest = round(dmin, 1),
  n_urogyn_within_50mi = n50,
  n_urogyn_within_100mi = n100)
out[, women65_per_urogyn_100mi := ifelse(n_urogyn_within_100mi>0,
                                          round(women_65plus / n_urogyn_within_100mi), NA_integer_)]
lon <- st_coordinates(ctr)[,1]; lat <- st_coordinates(ctr)[,2]
out[, `:=`(centroid_lon=round(lon,4), centroid_lat=round(lat,4))]
setorder(out, -miles_to_nearest)
fwrite(out, "data/urps_module_d_county_access_2026-07-23.csv")
fwrite(uro[, .(npi, pathway, state, zip5, lat, lon)],
       "data/urps_module_d_points_2026-07-23.csv")

## ── 5. national summary ──────────────────────────────────────────────────────
W  <- sum(out$women_65plus); U <- nrow(uro)
wt <- function(mask) round(100*sum(out$women_65plus[mask])/W, 1)   # % of women 65+
n_counties <- nrow(out); n_desert <- out[n_urogyn_in_county==0, .N]
# access-inequality: Gini of women-65+ per nearby urogyn is ill-defined w/ 0s;
# use share of women 65+ living >X mi from the nearest urogyn instead.
summ <- data.table(
  metric = c("active urogynecologists (in map)","CONUS women 65+","national women-65+ per urogyn",
             "urogynecologists per 100,000 CONUS women 65+",
             "CONUS counties","counties with 0 urogynecologists","% counties with 0 urogynecologists",
             "% women 65+ in a county with 0 urogynecologists",
             "% women 65+ within 25 mi of a urogynecologist",
             "% women 65+ within 50 mi","% women 65+ within 100 mi",
             "% women 65+ >100 mi from nearest urogynecologist",
             "median county miles to nearest","90th-pctile county miles to nearest"),
  value = c(U, W, round(W/U),
            round(RATE_PER_100K*U/W, 2),                                    # per-100k benchmark (per literature)
            n_counties, n_desert, round(100*n_desert/n_counties,1),
            wt(out$n_urogyn_in_county==0),
            wt(out$miles_to_nearest<=25), wt(out$miles_to_nearest<=50), wt(out$miles_to_nearest<=100),
            wt(out$miles_to_nearest>100),
            round(median(out$miles_to_nearest),1),
            round(quantile(out$miles_to_nearest,0.9),1)))
fwrite(summ, "data/urps_module_d_summary_2026-07-23.csv")

## per-100k urogynecologist density by state (geographic maldistribution, per Herb 2022)
st <- out[, .(women_65plus=sum(women_65plus), n_urogyn=sum(n_urogyn_in_county)), by=state]
st[, per_100k_w65 := round(RATE_PER_100K*n_urogyn/women_65plus, 2)]
setorder(st, per_100k_w65)
fwrite(st, "data/urps_module_d_density_by_state_2026-07-23.csv")

cat("\n=== MODULE D: geographic access summary ===\n")
print(summ, nrow=99)
cat("\n--- 10 most access-poor counties (highest women 65+ furthest from a urogyn) ---\n")
print(out[miles_to_nearest>60][order(-women_65plus)][1:10,
         .(county, state, women_65plus, miles_to_nearest, n_urogyn_within_100mi)])
cat("\nWrote county / points / summary CSVs to data/urps_module_d_*_2026-07-23.csv\n")
