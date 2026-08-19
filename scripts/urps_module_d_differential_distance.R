#!/usr/bin/env Rscript
# Module D add-on: DIFFERENTIAL DRIVE TIME — the extra DRIVE TIME a woman must
# travel to reach a URPS urogynecologist BEYOND the nearest general OB/GYN.
# Method from Herb et al., Am J Surg 2021 (differential/relative access), now on
# DRIVE TIME rather than straight-line distance. The earlier great-circle metric
# (miles_to_urogyn / miles_to_obgyn / differential_miles) has been RETIRED to
# match the drive-time-only Module D step-1: this script no longer computes
# great-circle distances and there is NO straight-line fallback.
#
#   differential_minutes(county) = drive_minutes(county -> nearest urogynecologist)
#                                - drive_minutes(county -> nearest general OB/GYN)
#
# DRIVE-TIME ONLY / HARD REQUIREMENT. cliff does not route; it consumes two
# precomputed drive-time-to-nearest artifacts (county GEOID -> minutes to the
# nearest provider of that layer), one for urogynecologists and one for general
# OB/GYNs. Both are produced by the project's Valhalla point-to-point routing
# generator (simulation/scripts/data_acquisition/build_drive_time_to_nearest.R
# run with county-centroid origins against each provider layer). If either is
# absent the script STOPS -- it cannot run on a machine without them, and it
# never falls back to straight-line distance.
#
# INPUTS (paths via env; each a GEOID-keyed CSV with a drive_minutes_to_nearest
# column, CONUS counties):
#   URPS_UROGYN_DRIVETIME  county -> nearest urogynecologist
#                          [data/urps_module_d_urogyn_drivetime_to_nearest_2026-07-23.csv]
#   URPS_OBGYN_DRIVETIME   county -> nearest general OB/GYN
#                          [data/urps_module_d_obgyn_drivetime_to_nearest_2026-07-23.csv]
#   County labels + women 65+ come from the Module D county access CSV.
# OUTPUT: data/urps_module_d_differential_distance_2026-07-23.csv
#         columns are now drive-time: drive_minutes_to_urogyn / drive_minutes_to_obgyn
#         / differential_minutes (the committed CSV regenerates on the next run).
#
# Run:  URPS_UROGYN_DRIVETIME=... URPS_OBGYN_DRIVETIME=... \
#         Rscript scripts/urps_module_d_differential_distance.R
suppressPackageStartupMessages({ library(data.table) })
source("R/conus.R")   # SSOT: is_conus_fips() (CONUS GEOID filter)

## ── drive-time-to-nearest reader (county GEOID -> minutes) ────────────────────
read_drivetime_to_nearest <- function(f, label) {
  d <- fread(f, colClasses = list(character = "GEOID"))
  if (!"GEOID" %in% names(d))
    stop(label, " drive-time artifact needs a GEOID column: ", f, call. = FALSE)
  mincol <- intersect(c("drive_minutes_to_nearest", "drive_minutes", "minutes_to_nearest"),
                      names(d))[1]
  if (is.na(mincol))
    stop(label, " drive-time artifact needs a drive_minutes_to_nearest column: ", f,
         call. = FALSE)
  d <- d[is_conus_fips(GEOID)]                            # CONUS only (SSOT: R/conus.R)
  unique(d[, .(GEOID = as.character(GEOID), minutes = as.numeric(get(mincol)))], by = "GEOID")
}

# differential drive time = extra minutes to a urogyn beyond the nearest OB/GYN
compute_differential_drivetime <- function(uro_dt, obgyn_dt) {
  m <- merge(uro_dt[,   .(GEOID, drive_minutes_to_urogyn = minutes)],
             obgyn_dt[, .(GEOID, drive_minutes_to_obgyn  = minutes)], by = "GEOID")
  m[, differential_minutes := round(drive_minutes_to_urogyn - drive_minutes_to_obgyn, 1)]
  m[, `:=`(drive_minutes_to_urogyn = round(drive_minutes_to_urogyn, 1),
           drive_minutes_to_obgyn  = round(drive_minutes_to_obgyn,  1))]
  m[]
}

## ── run (guarded so the pure functions above stay sourceable and unit-testable;
##     under Rscript the top-level environment IS globalenv, so the pipeline runs;
##     when source()d into a test frame it does not) ───────────────────────────
if (identical(environment(), globalenv()) && !interactive()) {
  URO_DT_F   <- Sys.getenv("URPS_UROGYN_DRIVETIME",
                           "data/urps_module_d_urogyn_drivetime_to_nearest_2026-07-23.csv")
  OBGYN_DT_F <- Sys.getenv("URPS_OBGYN_DRIVETIME",
                           "data/urps_module_d_obgyn_drivetime_to_nearest_2026-07-23.csv")
  ACC_F      <- "data/urps_module_d_county_access_2026-07-23.csv"   # county labels + women 65+

  missing <- c(URO_DT_F, OBGYN_DT_F)[!file.exists(c(URO_DT_F, OBGYN_DT_F))]
  if (length(missing))
    stop("Differential distance is drive-time-only and requires per-county ",
         "drive-time-to-nearest artifacts, but these are absent: ",
         paste(missing, collapse = ", "), ". Produce them with the Valhalla ",
         "point-to-point generator (simulation/scripts/data_acquisition/",
         "build_drive_time_to_nearest.R, county-centroid origins) for the ",
         "urogynecologist and general-OB/GYN layers, then set URPS_UROGYN_DRIVETIME / ",
         "URPS_OBGYN_DRIVETIME. There is no straight-line fallback.", call. = FALSE)
  if (!file.exists(ACC_F))
    stop("Run scripts/urps_module_d_geographic_access_2026-07-23.R first ",
         "(need county labels + women 65+): ", ACC_F, call. = FALSE)

  uro_dt   <- read_drivetime_to_nearest(URO_DT_F,   "urogynecologist")
  obgyn_dt <- read_drivetime_to_nearest(OBGYN_DT_F, "general OB/GYN")
  dd  <- compute_differential_drivetime(uro_dt, obgyn_dt)
  acc <- fread(ACC_F, colClasses = list(character = "GEOID"))
  out <- merge(acc[, .(GEOID, county, state, women_65plus)], dd, by = "GEOID")
  setorder(out, -differential_minutes)
  fwrite(out, "data/urps_module_d_differential_distance_2026-07-23.csv")

  W <- sum(out$women_65plus)
  cat(sprintf("Differential drive time computed for %d CONUS counties.\n", nrow(out)))
  cat(sprintf("Median extra DRIVE TIME to a urogynecologist beyond the nearest OB/GYN: %.1f min\n",
              median(out$differential_minutes)))
  cat(sprintf("%% of women 65+ facing >30 extra MINUTES for subspecialty care: %.1f%%\n",
              100 * sum(out$women_65plus[out$differential_minutes > 30]) / W))
  cat("Wrote data/urps_module_d_differential_distance_2026-07-23.csv\n")
}
