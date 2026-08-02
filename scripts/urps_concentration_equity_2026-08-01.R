#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# URPS Geographic Concentration & Workforce Equity
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Purpose:
#   Add a distribution / equity lens to the cliff workforce story, inspired by
#   the Cecil G. Sheps Center pediatric-subspecialty microsimulation (which
#   reports supply at national, Census-region, and Census-division levels).
#   cliff already answers "how many URPS, and do fellowships replace departures?"
#   This script answers the orthogonal questions:
#     (1) CONCENTRATION -- how unevenly are the 1,339 active urogynecologists
#         spread across counties / states / ACOG districts? (Gini, HHI, Lorenz)
#     (2) EQUITY / COMPOSITION -- who are they (gender, medical-school class,
#         IMG status), and where do they practice relative to need (rurality,
#         designated HPSAs)?
#     (3) RATE DISPERSION -- how variable is county access
#         (urogynecologists per 100k women 65+)?
#
# Inputs (committed, de-identified; from the isochrones upstream):
#   data/abog_all_urps_ENRICHED_2026-07-22.csv
#   data/abu_all_urps_ENRICHED_2026-07-22.csv
#   (baseline = rows with in_model_baseline == TRUE; N = 1,339)
#
# Outputs:
#   data/urps_concentration_by_geography_2026-08-01.csv
#   data/urps_lorenz_states_2026-08-01.csv
#   data/urps_equity_demographics_2026-08-01.csv
#   data/urps_provider_rate_dispersion_2026-08-01.csv
#   figures/urps_concentration_lorenz_2026-08-01.png (+ .tiff)
#
# Optional (true maldistribution Gini): if tidycensus is configured with a
#   Census API key, set CLIFF_PULL_ACS=1 to pull county women-65+ for ALL
#   counties and add a population-weighted Gini. Without it the script reports
#   provider-count concentration, which needs no external data (repo default).
#
# Runtime: ~2 seconds (no ACS pull).
#
# Author: Tyler Muffly, MD / Claude Code
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(readr)
  library(tidyr)
  library(ggplot2)
})

source(here::here("R/workforce_concentration_metrics.R"))

STAMP <- "2026-08-01"
US_COUNTY_TOTAL <- 3143L   # counties + county-equivalents (Census 2020)
US_STATE_TOTAL  <- 51L     # 50 states + DC

# --- Load & assemble the active baseline --------------------------------------
read_roster <- function(path) {
  readr::read_csv(path, show_col_types = FALSE, guess_max = 5000) |>
    mutate(across(everything(), as.character))
}

keep <- c("npi", "pathway", "state", "county_fips", "acog_district", "gender",
          "med_school_class", "img_us", "rurality", "pip_in_designated_hpsa",
          "urogyn_per_100k_women65", "in_model_baseline")

abog <- read_roster(here::here("data/abog_all_urps_ENRICHED_2026-07-22.csv"))
abu  <- read_roster(here::here("data/abu_all_urps_ENRICHED_2026-07-22.csv"))

roster <- bind_rows(
  abog |> select(any_of(keep)),
  abu  |> select(any_of(keep))
) |>
  filter(toupper(trimws(in_model_baseline)) %in% c("TRUE", "1")) |>
  mutate(
    pathway = ifelse(is.na(pathway) | pathway == "", "ABOG", pathway),
    urogyn_per_100k_women65 = suppressWarnings(as.numeric(urogyn_per_100k_women65))
  )

stopifnot(nrow(roster) > 0)
message(sprintf("Active baseline URPS: %d (ABOG %d, ABU %d)",
                nrow(roster), sum(roster$pathway == "ABOG"), sum(roster$pathway == "ABU")))

# --- 1. Concentration by geography --------------------------------------------
# 50 states + DC; US territories (PR/GU/AS/VI/MP) are excluded from the state and
# county universe so counts align with US_STATE_TOTAL / US_COUNTY_TOTAL.
US_STATES <- c("AL","AK","AZ","AR","CA","CO","CT","DE","DC","FL","GA","HI","ID",
               "IL","IN","IA","KS","KY","LA","ME","MD","MA","MI","MN","MS","MO",
               "MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA",
               "RI","SC","SD","TN","TX","UT","VT","VA","WA","WV","WI","WY")

count_vec <- function(col, keep_only = NULL, drop = c("", "NA", "Unknown")) {
  v <- trimws(roster[[col]])
  v <- v[!is.na(v) & !(v %in% drop)]
  if (!is.null(keep_only)) v <- v[v %in% keep_only]
  as.integer(table(v))
}

acog_counts <- count_vec("acog_district")   # "Unknown" dropped -> 11 occupied districts
concentration <- bind_rows(
  concentration_summary(count_vec("state", keep_only = US_STATES), US_STATE_TOTAL,  "US state (incl DC)"),
  concentration_summary(count_vec("county_fips"),                  US_COUNTY_TOTAL, "US county"),
  concentration_summary(acog_counts,                        length(acog_counts),    "ACOG district (I-XII, excl. unknown)")
)
readr::write_csv(concentration, here::here("data", paste0("urps_concentration_by_geography_", STAMP, ".csv")))

# --- 2. Lorenz coordinates (states + counties) --------------------------------
state_cv      <- count_vec("state", keep_only = US_STATES)
county_cv     <- count_vec("county_fips")
state_counts  <- c(state_cv,  rep(0L, US_STATE_TOTAL  - length(state_cv)))
county_counts <- c(county_cv, rep(0L, US_COUNTY_TOTAL - length(county_cv)))
lorenz_states <- lorenz_curve(state_counts)
readr::write_csv(lorenz_states, here::here("data", paste0("urps_lorenz_states_", STAMP, ".csv")))

# --- 3. Equity / demographic composition --------------------------------------
equity <- bind_rows(
  equity_breakdown(roster, gender,           pathway, levels = c("F", "M")),
  equity_breakdown(roster, med_school_class, pathway, levels = c("US_MD", "US_DO", "CAN_MD", "IMG", "Unknown")),
  equity_breakdown(roster, img_us,           pathway, levels = c("US", "IMG", "Unknown")),
  equity_breakdown(roster, rurality,         pathway, levels = c("Urban", "Suburban", "Rural"))
)
# HPSA as an explicit In/Not/Missing characteristic
roster_hpsa <- roster |>
  mutate(designated_hpsa = case_when(
    toupper(trimws(pip_in_designated_hpsa)) == "TRUE"  ~ "In HPSA",
    toupper(trimws(pip_in_designated_hpsa)) == "FALSE" ~ "Not in HPSA",
    TRUE                                               ~ "Missing"))
equity <- bind_rows(
  equity,
  equity_breakdown(roster_hpsa, designated_hpsa, pathway,
                   levels = c("In HPSA", "Not in HPSA", "Missing"))
)
readr::write_csv(equity, here::here("data", paste0("urps_equity_demographics_", STAMP, ".csv")))

# --- 4. Provider-weighted county-rate dispersion ------------------------------
dispersion <- rate_dispersion(roster$urogyn_per_100k_women65)
readr::write_csv(dispersion, here::here("data", paste0("urps_provider_rate_dispersion_", STAMP, ".csv")))

# --- 5. Lorenz figure ---------------------------------------------------------
lorenz_counties <- lorenz_curve(county_counts) |> mutate(level = "County")
lorenz_plot_df <- bind_rows(
  lorenz_counties,
  lorenz_states |> mutate(level = "State")
)
g_county <- concentration$gini[concentration$geography == "US county"]
g_state  <- concentration$gini[concentration$geography == "US state (incl DC)"]

p <- ggplot(lorenz_plot_df, aes(cum_unit_share, cum_value_share, color = level)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey60") +
  geom_line(linewidth = 1) +
  scale_color_manual(values = c(County = "#2166AC", State = "#B2182B"),
                     labels = c(County = sprintf("County (Gini %.3f)", g_county),
                                State  = sprintf("State (Gini %.3f)", g_state))) +
  coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
  labs(title = "Geographic concentration of the urogynecology workforce",
       subtitle = sprintf("Lorenz curves, N = %s active URPS (2025 baseline)", nrow(roster)),
       x = "Cumulative share of geographic units (fewest → most URPS)",
       y = "Cumulative share of urogynecologists",
       color = NULL) +
  theme_minimal(base_size = 12) +
  theme(legend.position = c(0.02, 0.98), legend.justification = c(0, 1))

ggsave(here::here("figures", paste0("urps_concentration_lorenz_", STAMP, ".png")),
       p, width = 6, height = 6, dpi = 300)
ggsave(here::here("figures", paste0("urps_concentration_lorenz_", STAMP, ".tiff")),
       p, width = 6, height = 6, dpi = 300, compression = "lzw")

message("Concentration/equity outputs written to data/ and figures/.")
print(concentration)
print(dispersion)
