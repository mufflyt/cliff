#!/usr/bin/env Rscript
# Module D (step 2): interactive Leaflet map of urogynecology geographic access.
#   - county choropleth: DRIVE-TIME access (E2SFCA, population-weighted per county,
#     fitted + geographically validated); low access glows red
#   - point layer: active urogynecologists, colored ABU vs ABOG
# Output: outputs/urps_module_d_access_map_2026-07-23.html (self-contained)
#
# Consumes data/urps_module_d_county_access_2026-07-23.csv, which is drive-time-
# only (the straight-line miles metric was retired; see the step-1 generator).
suppressPackageStartupMessages({
  library(data.table); library(tigris); library(sf); library(leaflet); library(htmlwidgets)
  library(mysterymaps)
})
options(tigris_use_cache = TRUE, tigris_class = "sf")
source("R/conus.R")   # SSOT: is_conus_fips()

acc <- fread("data/urps_module_d_county_access_2026-07-23.csv",
             colClasses=list(character=c("GEOID","state")))
if (!"drive_time_access" %in% names(acc)) {
  stop("urps_module_d_county_access CSV has no drive_time_access column; ",
       "regenerate it with the drive-time-only step-1 generator.", call.=FALSE)
}
pts <- fread("data/urps_module_d_points_2026-07-23.csv")

cty <- counties(cb=TRUE, resolution=CENSUS_CB_RESOLUTION, year=CENSUS_VINTAGE_YEAR, progress_bar=FALSE)
cty <- st_transform(cty, 4326)
cty <- cty[is_conus_fips(cty$STATEFP), ]
cty <- merge(cty, acc[, .(GEOID, county, state, women_65plus, n_urogyn_in_county,
                          drive_time_access, n_tracts)],
             by="GEOID", all.x=TRUE)
cty$tooltip <- sprintf(
  "%s County, %s<br>Women 65+: %s<br>Urogynecologists in county: %d<br><b>Drive-time access: %s</b>%s",
  cty$county, cty$state, formatC(cty$women_65plus, big.mark=",", format="d"),
  cty$n_urogyn_in_county,
  ifelse(is.na(cty$drive_time_access), "n/a (uncovered)",
         formatC(cty$drive_time_access, format="f", digits=2)),
  ifelse(is.na(cty$n_tracts), "",
         sprintf("<br>%d tract(s) rolled up", cty$n_tracts)))
cty$popup <- paste0("<b>", cty$tooltip, "</b>")

pts[, col := ifelse(grepl("ABU", pathway), "#7b3294", "#008837")]  # ABU purple / ABOG green

m <- mysterymaps_county_access_map(
  counties = cty,
  value_col = "drive_time_access",
  label_col = "tooltip",
  popup_col = "popup",
  points = NULL,
  overlay_group = "Urogynecologists",
  legend_title = "Drive-time access<br/>(higher = better)",
  jenks_k = 6L,
  jenks_digits = 2L,
  search = NULL,
  notes = list(
    title = "U.S. Urogynecology Geographic Access — notes",
    sections = list(
      "County shading" = "Drive-time access is the E2SFCA access surface rolled up to counties by population weight.",
      "Providers" = "Active urogynecologists from ABOG and ABU pathways."
    ),
    vintages = data.frame(source = c("ABOG/ABU rosters", "ACS 2019-2023", "E2SFCA access surface"),
                          vintage = c("2025", "2023", "fitted + validated")),
    as_of = "2025"
  ),
  bounds = c(24.5, -125, 49.4, -66.9)
)

m <- m |>
  addCircleMarkers(data=pts, lng=~lon, lat=~lat, radius=3, stroke=FALSE,
                   fillColor=~col, fillOpacity=0.75, group="Urogynecologists",
                   popup=~sprintf("%s<br>%s", pathway, state)) |>
  addLegend("bottomleft", colors=c("#7b3294","#008837"),
            labels=c("ABU (urology)","ABOG (OB/GYN)"), title="Board pathway", opacity=0.85) |>
  addControl(html=paste0(
    "<div style='background:#fff;padding:6px 9px;border-radius:5px;font:12px/1.4 sans-serif;",
    "box-shadow:0 1px 4px rgba(0,0,0,.25);max-width:260px'>",
    "<b>U.S. Urogynecology Geographic Access</b><br>",
    "Active urogynecologists (ABU + ABOG) and county drive-time access to them ",
    "(E2SFCA, fitted + geographically validated). Higher access is better.</div>"),
    position="topright")

dir.create("outputs", showWarnings=FALSE, recursive=TRUE)
out <- "outputs/urps_module_d_access_map_2026-07-23.html"
saveWidget(m, file=normalizePath(out, mustWork=FALSE), selfcontained=TRUE,
           title="U.S. Urogynecology Geographic Access, 2025")
cat("Wrote", out, "\n")
cat("Size:", round(file.info(out)$size/1e6,1), "MB\n")
