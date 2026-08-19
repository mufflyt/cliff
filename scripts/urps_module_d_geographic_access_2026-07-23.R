#!/usr/bin/env Rscript
# Module D (step 1): GEOGRAPHIC local adequacy of the urogynecology workforce.
# The national Modules A-C say capacity roughly tracks demand; Module D asks
# WHERE the ~1,339 urogynecologists actually are relative to where women 65+ live.
#
# DRIVE-TIME ONLY. The access metric is the simulation repo's tract-level E2SFCA
# drive-time access surface -- decay (sigma) and wait response (wait_scale) fitted
# AND geographically validated by the leave-one-region-out holdout -- rolled up to
# counties by population weight. The earlier straight-line (great-circle) distance
# metric (miles_to_nearest, within-50/100mi catchments) has been RETIRED: this
# script no longer computes it and there is no straight-line fallback.
#
# HARD REQUIREMENT: a validated access surface must be present, or the script
# STOPS. It cannot run on a machine without the simulation access_surface_v*.csv
# (see config/cliff_paths.yml::access_surface and
# SIMULATION_TO_CLIFF_INTEGRATION_PLAN.md). "Validated" means an EXPLICIT known-good
# calibration_status; a missing/blank/unrecognised status does NOT qualify. Set
# CLIFF_USE_ACCESS_SURFACE=force to accept an un-validated (incl. un-stamped) surface.
#
# Inputs : data/{abu,abog}_all_urps_ENRICHED_2026-07-22.csv (active only)
#          data/reference/zcta_centroids_2020.csv  (ZIP -> lat/lon, map layer)
#          ACS 2019-2023 5-yr B01001 female 65+ by county (tidycensus)
#          tigris county boundaries (2023; county names + provider-in-county count)
#          REQUIRED simulation access surface (config/cliff_paths.yml::access_surface)
# Outputs: data/urps_module_d_county_access_2026-07-23.csv   (drive_time_access)
#          data/urps_module_d_points_2026-07-23.csv          (map layer)
#          data/urps_module_d_summary_2026-07-23.csv
#          data/urps_module_d_density_by_state_2026-07-23.csv
suppressPackageStartupMessages({
  library(data.table); library(tidycensus); library(tigris); library(sf); library(dplyr)
})
options(tigris_use_cache = TRUE, tigris_class = "sf")
sf::sf_use_s2(TRUE)
source("R/conus.R")    # SSOT: CONUS_EXCLUDE_FIPS / is_conus_fips() / in_conus_bbox()  (AK, HI, PR, territories)
source("R/units.R")    # SSOT: RATE_PER_100K (per-100k rate base)
source("R/in_model_baseline.R")  # SSOT: inmodel() active-baseline cohort filter
source("R/access_surface.R")     # read_access_surface() / county_drive_time_access()

## ── 0. REQUIRE the validated drive-time access surface ────────────────────────
# Loaded first: this is a precondition, not a refinement. No surface -> no access
# metric -> stop (there is no straight-line fallback any more).
surface_forced <- tolower(Sys.getenv("CLIFF_USE_ACCESS_SURFACE", "")) %in%
  c("force", "1", "true", "yes", "on")
surface_path <- if (file.exists("R/wc_path.R")) {
  source("R/wc_path.R"); tryCatch(wc_path("access_surface"), error = function(e) NULL)
} else NULL
surface <- read_access_surface(surface_path)   # fails loudly on a malformed file
if (!access_surface_usable(surface)) {
  stop("Module D is drive-time-only and requires the simulation access surface, ",
       "but none was found at '", if (is.null(surface_path)) "<unresolved>" else surface_path,
       "'. Stage access_surface_v*.csv and point config/cliff_paths.yml::access_surface ",
       "at it (see SIMULATION_TO_CLIFF_INTEGRATION_PLAN.md).", call. = FALSE)
}
cstat  <- if (!is.null(surface$provenance$calibration_status)) surface$provenance$calibration_status else NA_character_
run_id <- if (!is.null(surface$provenance$isochrone_run_id)) surface$provenance$isochrone_run_id else "NA"
# Validated requires an EXPLICIT known-good status. A missing/blank/unrecognised
# calibration_status is NOT validated -- an un-stamped surface must not clear the
# hard gate by default (that would defeat the drive-time-only requirement); it can
# only be used with CLIFF_USE_ACCESS_SURFACE=force.
validated <- !is.na(cstat) && nzchar(cstat) &&
  cstat %in% c("fitted_and_geographically_validated", "calibrated")
if (!validated && !surface_forced) {
  cstat_shown <- if (is.na(cstat) || !nzchar(cstat)) "<missing>" else cstat
  stop("Module D: access surface calibration_status='", cstat_shown, "' is not ",
       "a recognised geographically-validated status. Re-fit/validate it (and stamp ",
       "calibration_status), or set CLIFF_USE_ACCESS_SURFACE=force to use it anyway.",
       call. = FALSE)
}
message(sprintf("Access surface loaded (isochrone run %s, status %s%s).",
                run_id, cstat, if (!validated && surface_forced) "; FORCED, not validated" else ""))
county_access <- as.data.table(county_drive_time_access(surface))
county_access[, drive_time_access := round(drive_time_access, 3)]

## ── 1. urogynecologist point layer (active; ZIP centroid) ────────────────────
cen <- fread("data/reference/zcta_centroids_2020.csv", colClasses=list(character="zcta5"))
cen <- cen[, .(zip5=sprintf("%05d", as.integer(zcta5)), lat=centroid_lat, lon=centroid_lon)]
load_roster <- function(f, pathway){
  d <- fread(f)
  d <- if ("in_model_baseline" %in% names(d)) d[inmodel(in_model_baseline)] else d
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
  acs <- get_acs("county", variables=vars, year=CENSUS_VINTAGE_YEAR, survey="acs5", cache_table=TRUE)
  setDT(acs)
  w65 <- acs[, .(women_65plus=sum(estimate),
                 moe=tidycensus::moe_sum(moe, estimate)), by=.(GEOID)]
  fwrite(w65, acs_cache)
}
w65 <- w65[is_conus_fips(GEOID)]

## ── 3. county geometry (names/state + provider-in-county count) ───────────────
# Geometry is no longer used for distance; it supplies county names/state and the
# point-in-polygon count of urogynecologists physically located in each county.
cty <- counties(cb=TRUE, resolution=CENSUS_CB_RESOLUTION, year=CENSUS_VINTAGE_YEAR, progress_bar=FALSE)
cty <- st_transform(cty, 4326)
cty <- cty[is_conus_fips(cty$STATEFP), ]   # SSOT (R/conus.R); drops AK/HI + territories = 48 states + DC
cty <- merge(cty, w65, by="GEOID", all.x=TRUE)
cty$women_65plus[is.na(cty$women_65plus)] <- 0
contain <- lengths(st_intersects(cty, uro_sf))   # urogynecologists located in the county

## ── 4. county drive-time access table ─────────────────────────────────────────
out <- data.table(
  GEOID = cty$GEOID, county = cty$NAME, state = cty$STUSPS,
  women_65plus = round(cty$women_65plus),
  women_65plus_moe = round(cty$moe),
  n_urogyn_in_county = contain)
out <- merge(out, county_access[, .(GEOID, drive_time_access, n_tracts)],
             by = "GEOID", all.x = TRUE)
n_cov <- out[!is.na(drive_time_access), .N]
message(sprintf("Drive-time access joined: %d/%d CONUS counties covered by the surface.",
                n_cov, nrow(out)))
setorder(out, drive_time_access)   # worst (lowest) access first
fwrite(out, "data/urps_module_d_county_access_2026-07-23.csv")
fwrite(uro[, .(npi, pathway, state, zip5, lat, lon)],
       "data/urps_module_d_points_2026-07-23.csv")

## ── 5. national summary (drive-time access) ──────────────────────────────────
W  <- sum(out$women_65plus); U <- nrow(uro)
cov <- out[!is.na(drive_time_access)]
Wcov <- sum(cov$women_65plus)
wt <- function(mask) round(100*sum(out$women_65plus[mask], na.rm=TRUE)/W, 1)   # % of women 65+
n_counties <- nrow(out); n_nosupply <- out[n_urogyn_in_county==0, .N]
pw_access  <- if (Wcov > 0) round(sum(cov$drive_time_access*cov$women_65plus)/Wcov, 3) else NA_real_
summ <- data.table(
  metric = c("active urogynecologists (in map)","CONUS women 65+","national women-65+ per urogyn",
             "urogynecologists per 100,000 CONUS women 65+",
             "CONUS counties","counties with 0 urogynecologists","% counties with 0 urogynecologists",
             "% women 65+ in a county with 0 urogynecologists",
             "counties covered by drive-time surface","% women 65+ in a covered county",
             "counties NOT covered by drive-time surface","% women 65+ in an uncovered county",
             "population-weighted mean county drive-time access",
             "% women 65+ in a county with zero drive-time access",
             "median county drive-time access","10th-pctile county drive-time access"),
  value = c(U, W, round(W/U),
            round(RATE_PER_100K*U/W, 2),                                    # per-100k benchmark (per literature)
            n_counties, n_nosupply, round(100*n_nosupply/n_counties,1),
            wt(out$n_urogyn_in_county==0),
            n_cov, round(100*Wcov/W, 1),
            n_counties - n_cov, wt(is.na(out$drive_time_access)),
            pw_access,
            wt(!is.na(out$drive_time_access) & out$drive_time_access==0),
            round(median(cov$drive_time_access, na.rm=TRUE), 3),
            round(quantile(cov$drive_time_access, 0.10, na.rm=TRUE), 3)))
fwrite(summ, "data/urps_module_d_summary_2026-07-23.csv")

## per-100k urogynecologist density by state (geographic maldistribution, per Herb 2022)
st <- out[, .(women_65plus=sum(women_65plus), n_urogyn=sum(n_urogyn_in_county)), by=state]
st[, per_100k_w65 := round(RATE_PER_100K*n_urogyn/women_65plus, 2)]
setorder(st, per_100k_w65)
fwrite(st, "data/urps_module_d_density_by_state_2026-07-23.csv")

cat("\n=== MODULE D: drive-time geographic access summary ===\n")
print(summ, nrow=99)
cat(sprintf("\nAccess surface: isochrone run %s, status %s.\n", run_id, cstat))
# Worst-served ranking is over COVERED counties only; counties the surface does
# not cover (drive_time_access = NA) cannot be ranked here, so report how many
# counties and how many women 65+ they hold -- otherwise a reader of the worst-10
# would not see that some (possibly the most remote) counties are missing entirely.
unc <- out[is.na(drive_time_access)]
n_unc <- nrow(unc); w_unc <- sum(unc$women_65plus)
cat(sprintf(paste0("\nUncovered by the surface: %d of %d counties (%s women 65+, %.1f%% ",
                   "of the national total) have NO drive-time access value and are ",
                   "EXCLUDED from the worst-served ranking below.\n"),
            n_unc, n_counties, formatC(w_unc, big.mark = ",", format = "d"),
            if (W > 0) 100 * w_unc / W else 0))
cat("\n--- 10 lowest drive-time-access counties (most women 65+ among the worst-served) ---\n")
print(cov[order(drive_time_access)][1:min(10, nrow(cov)),
         .(county, state, women_65plus, drive_time_access, n_urogyn_in_county)])
cat("\nWrote county / points / summary / density CSVs to data/urps_module_d_*_2026-07-23.csv\n")
