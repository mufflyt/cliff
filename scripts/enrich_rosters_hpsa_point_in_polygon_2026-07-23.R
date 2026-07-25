#!/usr/bin/env Rscript
# FORMALIZED into mufflyt/cliff from an ephemeral session scratchpad (2026-07-24).
# Large public inputs are fetched by scripts/download_enrichment_inputs.sh
# (HRSA HPSA polygons + CMS Medicare CY2024 PUF) into data/enrichment_inputs/,
# overridable via the MEDICARE_2024_CSV / HPSA_SHP env vars.
# NOTE: also reads isochrones-pipeline outputs -- manuscript/tables/table1_physician_characteristics.csv
# and data/abu_urology/*_geocoded_*.csv -- stage those into cliff (data/) or adjust the here() paths when running standalone.
# TRUE point-in-polygon HPSA underserved variable: test each physician's
# geocoded practice coordinate against the HRSA primary-care HPSA polygon
# layer (HPSA_CMPPC_SHP_DET_CUR_VX.shp, downloaded from data.hrsa.gov).
# This captures whole-area Geographic HPSAs (real polygons) that the
# tabular tract-FIPS join could not place.
# Polygon source: https://data.hrsa.gov/DataDownload/DD_Files/HPSA_CMPPC_SHP.zip
#   (Complete Modeled Primary Care HPSA, current; ~272 MB; 25,480 polygons).
# Emits:
#   pip_in_designated_hpsa   TRUE/FALSE (point falls in a Designated PC HPSA)
#   hpsa_score_pip           max HPSA score among containing polygons (0-26)
#   hpsa_type_pip            designation type(s) of the containing polygon(s)
# Keeps the earlier tract flag + county flag for comparison.
suppressPackageStartupMessages({ library(sf); library(data.table); library(here) })
sf_use_s2(FALSE)

SHP <- Sys.getenv("HPSA_SHP", unset = here::here("data","enrichment_inputs","hpsa_shp","HPSA_CMPPC_SHP_DET_CUR_VX.shp"))

## ── 1. HPSA polygons: Designated primary-care only ──────────────────────────
hp <- st_read(SHP, quiet = TRUE)
hp <- hp[grepl("Designated", hp$HpsStatDes, ignore.case = TRUE), ]
hp <- st_make_valid(hp)
hp$HpsScore <- suppressWarnings(as.numeric(as.character(hp$HpsScore)))
cat(sprintf("Designated PC-HPSA polygons: %d (types: %s)\n", nrow(hp),
            paste(sort(unique(as.character(hp$HpsTypDes))), collapse=", ")))

## ── 2. Physician coordinates (table1 + ABU geocoded) ────────────────────────
rd <- function(p, npi_c, lat_c, lon_c) {
  d <- fread(p, colClasses = list(character = npi_c))
  data.table(npi = as.character(d[[npi_c]]),
             lat = suppressWarnings(as.numeric(d[[lat_c]])),
             lon = suppressWarnings(as.numeric(d[[lon_c]])))
}
coords <- rbindlist(list(
  rd(here("manuscript","tables","table1_physician_characteristics.csv"), "npi", "latitude", "longitude"),
  rd(here("data","abu_urology","abog_fpmrs_geocoded_2026-07-14.csv"),        "npi", "latitude", "longitude"),
  rd(here("data","abu_urology","abu_fpmrs_net_new_geocoded_2026-07-14.csv"), "npi", "latitude", "longitude")
))
coords <- coords[!is.na(lat) & !is.na(lon) & abs(lat) <= 90 & abs(lon) <= 180 & (lat != 0 | lon != 0)]
coords <- unique(coords, by = "npi")   # first (table1) wins
cat(sprintf("Physicians with usable coordinates: %d\n", nrow(coords)))

## ── 3. Point-in-polygon ─────────────────────────────────────────────────────
pts <- st_as_sf(coords, coords = c("lon","lat"), crs = 4326, remove = FALSE)
pts <- st_transform(pts, st_crs(hp))
idx <- st_intersects(pts, hp)          # list: for each point, containing polygon rows
pip <- data.table(
  npi = coords$npi,
  pip_in_designated_hpsa = lengths(idx) > 0,
  hpsa_score_pip = vapply(idx, function(i) if (length(i)) suppressWarnings(max(hp$HpsScore[i], na.rm=TRUE)) else NA_real_, numeric(1)),
  hpsa_type_pip  = vapply(idx, function(i) if (length(i)) paste(sort(unique(as.character(hp$HpsTypDes[i]))), collapse="; ") else NA_character_, character(1))
)
pip[is.infinite(hpsa_score_pip), hpsa_score_pip := NA_real_]
cat(sprintf("Points inside a Designated PC-HPSA polygon: %d / %d\n",
            sum(pip$pip_in_designated_hpsa), nrow(pip)))

## ── 4. Merge into rosters + report ──────────────────────────────────────────
enrich <- function(path, lab) {
  d <- fread(path, colClasses = list(character = "npi"))
  d[, npi := as.character(npi)]
  d <- merge(d, pip, by = "npi", all.x = TRUE)
  fwrite(d, path)
  inm <- d[in_model_baseline %in% c(TRUE,"TRUE","true",1,"1")]
  cov <- sum(!is.na(inm$pip_in_designated_hpsa))
  cat(sprintf("\n== %s in-model n=%d ==\n", lab, nrow(inm)))
  cat(sprintf("  with coordinates matched: %d (%.0f%%)\n", cov, 100*cov/nrow(inm)))
  cat(sprintf("  POINT-in-polygon in a Designated HPSA: %.1f%%   (tract flag %.1f%%, county %.1f%%)\n",
              100*mean(inm$pip_in_designated_hpsa, na.rm=TRUE),
              100*mean(inm$tract_in_designated_hpsa %in% TRUE, na.rm=TRUE),
              100*mean(inm$county_hpsa_primary_care %in% TRUE, na.rm=TRUE)))
  cat(sprintf("  median HPSA score among those in one: %s\n",
              ifelse(any(!is.na(inm$hpsa_score_pip)), as.character(median(inm$hpsa_score_pip, na.rm=TRUE)), "NA")))
  if (any(inm$pip_in_designated_hpsa, na.rm=TRUE))
    print(sort(table(unlist(strsplit(inm$hpsa_type_pip[inm$pip_in_designated_hpsa %in% TRUE], "; "))), decreasing=TRUE))
}
enrich(here("data","abu_all_urps_ENRICHED_2026-07-22.csv"),  "ABU")
enrich(here("data","abog_all_urps_ENRICHED_2026-07-22.csv"), "ABOG")
cat("\nAdded: pip_in_designated_hpsa, hpsa_score_pip, hpsa_type_pip\n")
