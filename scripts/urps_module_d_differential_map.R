#!/usr/bin/env Rscript
# Choropleth: DIFFERENTIAL DISTANCE to urogynecologic care — extra miles a woman
# must travel to reach a urogynecologist BEYOND the nearest general OB/GYN
# (Herb et al., Am J Surg 2021). Reds = large marginal burden of needing
# subspecialty care; blues = a urogynecologist is as close as / closer than the
# nearest generalist (dense metros).
suppressPackageStartupMessages({ library(data.table); library(sf); library(tigris); library(ggplot2) })
options(tigris_use_cache=TRUE, tigris_class="sf"); sf::sf_use_s2(TRUE)
source("R/conus.R")   # SSOT: is_conus_fips()

dd  <- fread("data/urps_module_d_differential_distance_2026-07-23.csv", colClasses=list(character="GEOID"))
cty <- st_transform(counties(cb=TRUE, resolution="20m", year=2023, progress_bar=FALSE), 4326)
cty <- cty[is_conus_fips(cty$STATEFP), ]
sta <- st_transform(states(cb=TRUE, resolution="20m", year=2023, progress_bar=FALSE), 4326)
sta <- sta[is_conus_fips(sta$STATEFP), ]
m <- merge(cty, dd[, .(GEOID, differential_miles)], by="GEOID", all.x=TRUE)

brk <- c(-Inf, 0, 15, 30, 60, 120, Inf)
lab <- c("≤ 0 (urogyn ≤ OB/GYN)","0–15","15–30","30–60","60–120","> 120 mi")
m$bin <- cut(m$differential_miles, breaks=brk, labels=lab, right=TRUE)
pal <- c("#2c7fb8", "#ffffcc", "#fed976", "#fd8d3c", "#e31a1c", "#800026")  # blue -> deep red

p <- ggplot() +
  geom_sf(data=m, aes(fill=bin), color="white", linewidth=0.04) +
  geom_sf(data=sta, fill=NA, color="grey35", linewidth=0.18) +
  scale_fill_manual(values=setNames(pal, lab), na.value="grey88",
                    name="Extra miles to a\nurogynecologist beyond\nthe nearest OB/GYN",
                    drop=FALSE, guide=guide_legend(reverse=FALSE)) +
  coord_sf(crs=st_crs(5070), datum=NA) +                         # Albers equal-area
  labs(title="Differential distance to urogynecologic care, U.S. counties",
       subtitle="Extra travel to the nearest urogynecologist beyond the nearest general OB/GYN (county centroid; women 65+)",
       caption="Method: Herb et al., Am J Surg 2021. Comparator: 40,495 geocoded general OB/GYNs (ABOG). Median 29 extra miles; 17% of women 65+ face >30.") +
  theme_void(base_size=12) +
  theme(plot.title=element_text(face="bold", size=15), plot.title.position="plot",
        plot.subtitle=element_text(color="#444", size=10.5, margin=margin(b=6)),
        plot.caption=element_text(color="#777", size=8, hjust=0),
        legend.position=c(0.92, 0.30), legend.title=element_text(size=9, face="bold"),
        legend.text=element_text(size=8.5), plot.margin=margin(8,8,8,8))

dir.create("cliff/outputs", showWarnings=FALSE, recursive=TRUE)
out <- "cliff/outputs/urps_differential_distance_map_2026-07-23.png"
ggsave(out, p, width=11, height=7, dpi=200, bg="white")
cat("Wrote", out, "|", round(file.info(out)$size/1e3), "KB\n")
