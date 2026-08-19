#!/usr/bin/env Rscript
# Module D (step 2): interactive Leaflet map of urogynecology geographic access.
#   - county choropleth: DRIVE-TIME access (E2SFCA, population-weighted per county,
#     fitted + geographically validated); low access glows red
#   - point layer: active urogynecologists, colored ABU vs ABOG
# Output: cliff/outputs/urps_module_d_access_map_2026-07-23.html (self-contained)
#
# Consumes data/urps_module_d_county_access_2026-07-23.csv, which is drive-time-
# only (the straight-line miles metric was retired; see the step-1 generator).
suppressPackageStartupMessages({
  library(data.table); library(tigris); library(sf); library(leaflet); library(htmlwidgets)
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

# Choropleth on drive-time access: HIGHER is better, so low access -> red, high ->
# green (the reverse of the retired miles metric). Continuous scale, robust to the
# access units being arbitrary; uncovered counties are grey.
pal <- colorNumeric(c("#d73027","#fee08b","#1a9850"),
                    domain=cty$drive_time_access, na.color="#cccccc")
cty$popup <- sprintf(
  "<b>%s County, %s</b><br>Women 65+: %s<br>Urogynecologists in county: %d<br><b>Drive-time access: %s</b>%s",
  cty$county, cty$state, formatC(cty$women_65plus, big.mark=",", format="d"),
  cty$n_urogyn_in_county,
  ifelse(is.na(cty$drive_time_access), "n/a (uncovered)",
         formatC(cty$drive_time_access, format="f", digits=2)),
  ifelse(is.na(cty$n_tracts), "",
         sprintf("<br>%d tract(s) rolled up", cty$n_tracts)))

pts[, col := ifelse(grepl("ABU", pathway), "#7b3294", "#008837")]  # ABU purple / ABOG green

m <- leaflet(options=leafletOptions(preferCanvas=TRUE)) |>
  addProviderTiles("CartoDB.Positron") |>
  setView(-96, 38.5, zoom=4) |>
  addPolygons(data=cty, fillColor=~pal(drive_time_access), fillOpacity=0.65,
              color="#ffffff", weight=0.4, smoothFactor=0.3,
              popup=~popup, group="Drive-time access",
              highlightOptions=highlightOptions(weight=1.5, color="#333", bringToFront=TRUE)) |>
  addCircleMarkers(data=pts, lng=~lon, lat=~lat, radius=3, stroke=FALSE,
                   fillColor=~col, fillOpacity=0.75, group="Urogynecologists",
                   popup=~sprintf("%s<br>%s", pathway, state)) |>
  addLegend("bottomright", pal=pal, values=cty$drive_time_access,
            title="Drive-time access<br>(higher = better)", opacity=0.85,
            na.label="uncovered") |>
  addLegend("bottomleft", colors=c("#7b3294","#008837"),
            labels=c("ABU (urology)","ABOG (OB/GYN)"), title="Board pathway", opacity=0.85) |>
  addLayersControl(overlayGroups=c("Drive-time access","Urogynecologists"),
                   options=layersControlOptions(collapsed=FALSE)) |>
  addControl(html=paste0(
    "<div style='background:#fff;padding:6px 9px;border-radius:5px;font:12px/1.4 sans-serif;",
    "box-shadow:0 1px 4px rgba(0,0,0,.25);max-width:260px'>",
    "<b>U.S. Urogynecology Geographic Access</b><br>",
    "Active urogynecologists (ABU + ABOG) and county drive-time access to them ",
    "(E2SFCA, fitted + geographically validated). Higher access is better.</div>"),
    position="topright")

dir.create("cliff/outputs", showWarnings=FALSE, recursive=TRUE)
out <- "cliff/outputs/urps_module_d_access_map_2026-07-23.html"
saveWidget(m, file=normalizePath(out, mustWork=FALSE), selfcontained=TRUE,
           title="U.S. Urogynecology Geographic Access, 2025")
cat("Wrote", out, "\n")
cat("Size:", round(file.info(out)$size/1e6,1), "MB\n")
