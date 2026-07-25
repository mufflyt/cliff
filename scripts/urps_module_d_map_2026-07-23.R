#!/usr/bin/env Rscript
# Module D (step 2): interactive Leaflet map of urogynecology geographic access.
#   - county choropleth: straight-line miles from county centroid to the nearest
#     active urogynecologist (the deserts glow red)
#   - point layer: the 1,293 active urogynecologists, colored ABU vs ABOG
# Output: cliff/outputs/urps_module_d_access_map_2026-07-23.html (self-contained)
suppressPackageStartupMessages({
  library(data.table); library(tigris); library(sf); library(leaflet); library(htmlwidgets)
})
options(tigris_use_cache = TRUE, tigris_class = "sf")
source("R/conus.R")   # SSOT: is_conus_fips()

acc <- fread("data/urps_module_d_county_access_2026-07-23.csv",
             colClasses=list(character=c("GEOID","state")))
pts <- fread("data/urps_module_d_points_2026-07-23.csv")

cty <- counties(cb=TRUE, resolution=CENSUS_CB_RESOLUTION, year=CENSUS_VINTAGE_YEAR, progress_bar=FALSE)
cty <- st_transform(cty, 4326)
cty <- cty[is_conus_fips(cty$STATEFP), ]
cty <- merge(cty, acc[, .(GEOID, county, state, women_65plus, n_urogyn_in_county,
                          miles_to_nearest, n_urogyn_within_100mi, women65_per_urogyn_100mi)],
             by="GEOID", all.x=TRUE)

# choropleth bins on miles-to-nearest (access); counties with a urogyn = "0-25" floor
bins <- c(0,25,50,100,150,Inf)
labs <- c("&lt; 25 mi","25-50 mi","50-100 mi","100-150 mi","&gt; 150 mi (desert)")
pal  <- colorBin(c("#1a9850","#91cf60","#fee08b","#fc8d59","#d73027"),
                 domain=cty$miles_to_nearest, bins=bins, na.color="#cccccc")
cty$popup <- sprintf(
  "<b>%s County, %s</b><br>Women 65+: %s<br>Urogynecologists in county: %d<br><b>%s mi</b> to nearest<br>%d within 100 mi%s",
  cty$county, cty$state, formatC(cty$women_65plus, big.mark=",", format="d"),
  cty$n_urogyn_in_county, formatC(cty$miles_to_nearest, format="f", digits=0),
  cty$n_urogyn_within_100mi,
  ifelse(is.na(cty$women65_per_urogyn_100mi), "",
         sprintf("<br>%s women 65+ per urogyn (100-mi catchment)",
                 formatC(cty$women65_per_urogyn_100mi, big.mark=",", format="d"))))

pts[, col := ifelse(grepl("ABU", pathway), "#7b3294", "#008837")]  # ABU purple / ABOG green

m <- leaflet(options=leafletOptions(preferCanvas=TRUE)) |>
  addProviderTiles("CartoDB.Positron") |>
  setView(-96, 38.5, zoom=4) |>
  addPolygons(data=cty, fillColor=~pal(miles_to_nearest), fillOpacity=0.65,
              color="#ffffff", weight=0.4, smoothFactor=0.3,
              popup=~popup, group="Access (miles to nearest)",
              highlightOptions=highlightOptions(weight=1.5, color="#333", bringToFront=TRUE)) |>
  addCircleMarkers(data=pts, lng=~lon, lat=~lat, radius=3, stroke=FALSE,
                   fillColor=~col, fillOpacity=0.75, group="Urogynecologists",
                   popup=~sprintf("%s<br>%s", pathway, state)) |>
  addLegend("bottomright", colors=c("#1a9850","#91cf60","#fee08b","#fc8d59","#d73027"),
            labels=labs, title="Miles to nearest<br>urogynecologist", opacity=0.85) |>
  addLegend("bottomleft", colors=c("#7b3294","#008837"),
            labels=c("ABU (urology)","ABOG (OB/GYN)"), title="Board pathway", opacity=0.85) |>
  addLayersControl(overlayGroups=c("Access (miles to nearest)","Urogynecologists"),
                   options=layersControlOptions(collapsed=FALSE)) |>
  addControl(html=paste0(
    "<div style='background:#fff;padding:6px 9px;border-radius:5px;font:12px/1.4 sans-serif;",
    "box-shadow:0 1px 4px rgba(0,0,0,.25);max-width:260px'>",
    "<b>U.S. Urogynecology Geographic Access</b><br>",
    "1,293 active urogynecologists (ABU + ABOG). ",
    "88% of counties have none; 43% of women 65+ live in one. Straight-line access, ",
    "not drive-time.</div>"), position="topright")

dir.create("cliff/outputs", showWarnings=FALSE, recursive=TRUE)
out <- "cliff/outputs/urps_module_d_access_map_2026-07-23.html"
saveWidget(m, file=normalizePath(out, mustWork=FALSE), selfcontained=TRUE,
           title="U.S. Urogynecology Geographic Access, 2025")
cat("Wrote", out, "\n")
cat("Size:", round(file.info(out)$size/1e6,1), "MB\n")
