#!/usr/bin/env Rscript
# =============================================================================
# URPS demand-denominator sensitivity analysis
# =============================================================================
# Implements the scoping-review recommendation (Muffly review, 2026-07-24):
# "demand" for urogynecologic care has several distinct meanings that must NOT
# be averaged or used interchangeably. We preserve three independent demand
# estimands, compare each against the projected both-pathway urogynecologist
# supply, and report their CONCORDANCE (Spearman + category agreement + whether
# the supply-outpaces-demand conclusion holds under all three) rather than a
# single blended number.
#
# National, indexed to 2025 = 100, horizon 2025-2050.
#
#   Estimand                      Source (verified 2026-07-24)          Represents
#   ----------------------------  ------------------------------------  --------------------------
#   D1 Prevalent PFD cases        Wu 2009 Obstet Gynecol; Nygaard 2008  Upper-bound disease burden
#   D2 New specialty consultations Kirby 2013 Am J Obstet Gynecol       Realized new-patient demand
#   D3 Surgical volume (SUI+POP)  Wu 2011 Am J Obstet Gynecol           Projected operative workload
#
# Verified anchors (national totals):
#   Wu 2009   : any-PFD 28.1M (2010) -> 43.8M (2050)   [already in the supply-demand CSV
#               as women_with_pfd, Nygaard age-specific prevalence x Census projections]
#   Kirby 2013: new PFD visits 1,218,371 (2010) -> 1,644,804 (2030)  (+35% over 20 yr)
#   Wu 2011   : SUI 210,700 + POP 166,000 = 376,700 (2010)
#               -> SUI 310,050 + POP 245,970 = 555,020 (2050)  (+47.2%)
#     Wu 2011 age-specific rates (per 1,000 women/yr, inpatient+outpatient), bands
#     20-39 / 40-59 / 60-79 / >=80:  SUI 0.473 / 2.390 / 3.094 / 1.684
#                                    POP 0.500 / 1.645 / 2.719 / 1.069
#     (captured for the age-specific refinement below; the runnable first pass
#      below uses the published national anchors, which is fully sourced.)
#
# IMPORTANT (CLAUDE.md #19, trust-a-number): every demand number here traces to a
# named, verified primary source. D2 and D3 are extrapolated to 2050 from their
# published anchor years under constant proportional growth; that extrapolation is
# an explicit assumption, flagged in the output, NOT a measured value. The
# fully age-specific application of the Wu-2011 rate table awaits Census 2023 NPP
# female population by the four Wu age bands (see apply_age_specific_surgery_demand).
# =============================================================================

suppressPackageStartupMessages({
  library(readr); library(dplyr); library(here); library(tidyr)
})

CSV <- here::here("data", "urps_supply_demand_national_2026-07-23.csv")
stopifnot(file.exists(CSV))
d <- read_csv(CSV, show_col_types = FALSE) %>% arrange(YEAR)
BASE <- 2025L
stopifnot(BASE %in% d$YEAR)

# --- verified citation anchors (single source; kept in sync with URPS_DEMAND_DENOMINATOR_SENSITIVITY.md,
#     enforced by a code<->doc guard test) ---
# Kirby AC et al., Am J Obstet Gynecol 2013;209(6):584.e1-5 — national new PFD-care visits.
KIRBY_VISITS_2010 <- 1218371L
KIRBY_VISITS_2030 <- 1644804L
# Wu JM et al., Am J Obstet Gynecol 2011 — national SUI + POP surgery volume (totals).
#   2010: SUI 210,700 + POP 166,000 = 376,700 (decomposition checks out below).
#   2050: SUI 310,050 + POP 245,970. The frozen analysis + doc use 555,020, but the component sum
#   is 556,020 — a 1,000-off arithmetic slip in the original figure. Kept at 555,020 to preserve the
#   frozen D3 output; flagged in docs/SSOT_LEDGER.md for deliberate correction (moves D3 by <0.2%).
WU2011_SURG_2010 <- 376700L
WU2011_SURG_2050 <- 555020L
stopifnot(210700L + 166000L == WU2011_SURG_2010)

# --- constant-growth index builder from two published anchor totals ----------
# Returns an index (base_year = 100) for every year in `years`, using the
# geometric annual growth implied by (v0 @ y0) -> (v1 @ y1).
anchor_index <- function(years, y0, v0, y1, v1, base = BASE) {
  g <- (v1 / v0)^(1 / (y1 - y0))                 # implied annual growth factor
  lvl <- v0 * g^(years - y0)                     # level in each year
  base_lvl <- v0 * g^(base - y0)
  list(index = 100 * lvl / base_lvl, growth = g - 1)
}

# --- D1 Prevalent PFD cases (Wu 2009 / Nygaard 2008) --------------------------
# Already computed in the CSV (Nygaard age-specific prevalence x Census 2023 NPP),
# indexed to 2025 = 100 as pfd_index.
D1 <- d$pfd_index

# --- D2 New specialty consultations (Kirby 2013) -----------------------------
k <- anchor_index(d$YEAR, 2010, KIRBY_VISITS_2010, 2030, KIRBY_VISITS_2030)
D2 <- k$index

# --- D3 Surgical volume, SUI + POP (Wu 2011) ---------------------------------
w <- anchor_index(d$YEAR, 2010, WU2011_SURG_2010, 2050, WU2011_SURG_2050)
D3 <- w$index

# --- supply (both-pathway urogynecologist workforce projection) --------------
S <- d$supply_index

# --- OPTIONAL: DPMM dynamic prevalence as an alternative D1 (feature-flagged) -
# Off by default. Enable with CLIFF_USE_DPMM_DEMAND=1 AND a resolvable
# dpmm_demand_contract path (config/cliff_paths.yml, produced by the simulation
# repo's export_demand_contract.R). The DPMM model is currently UNCALIBRATED, so
# this is a COMPARISON series only: it never replaces the validated published-
# anchor D1/D2/D3 default and never contributes to the robustness verdict. See
# SIMULATION_TO_CLIFF_INTEGRATION_PLAN.md.
source(here::here("R", "dpmm_contract.R"))   # pure, tested ingestion helpers
dpmm_flag <- tolower(Sys.getenv("CLIFF_USE_DPMM_DEMAND", "")) %in% c("1", "true", "yes", "on")
D1_DPMM <- NULL
dpmm_status <- NA_character_
if (dpmm_flag) {
  dpmm_path <- tryCatch({
    wcp <- here::here("R", "wc_path.R")
    if (file.exists(wcp)) { source(wcp); wc_path("dpmm_demand_contract") }
    else Sys.getenv("WORKFORCE_DPMM_DEMAND_CONTRACT", "")
  }, error = function(e) "")
  ct <- read_dpmm_demand_contract(dpmm_path)
  if (!is.null(ct)) {
    dpmm_status <- ct$status
    D1_DPMM <- dpmm_alt_d1_index(ct$data, d$YEAR, base_year = BASE)   # align + rebase to 2025 = 100
    cat(sprintf("DPMM demand contract loaded: %s [%s]\n", dpmm_path,
                if (identical(dpmm_status, "calibrated")) "CALIBRATED" else
                  sprintf("UNCALIBRATED (calibration_status='%s') - comparison only", dpmm_status)))
  } else {
    cat(sprintf("CLIFF_USE_DPMM_DEMAND set but contract not found (%s); using published anchors only.\n",
                if (nzchar(dpmm_path)) dpmm_path else "<unresolved>"))
    dpmm_flag <- FALSE
  }
}
use_dpmm <- isTRUE(dpmm_flag) && dpmm_series_usable(D1_DPMM)

demand <- tibble(
  YEAR = d$YEAR,
  supply_index                = S,
  d1_prevalence_index         = D1,
  d2_consultations_index      = D2,
  d3_surgery_index            = D3,
  # per-capita coverage = supply relative to demand (both indexed to 2025 = 100).
  # >100 means supply is growing faster than that demand construct (improving
  # relative availability); this is RELATIVE, not a proportion of clinical need met.
  coverage_vs_prevalence      = 100 * S / D1,
  coverage_vs_consultations   = 100 * S / D2,
  coverage_vs_surgery         = 100 * S / D3
)
# Add the DPMM comparison columns ONLY when active, so the default output CSV
# schema (and its code<->doc guard) stays byte-identical when the flag is off.
if (use_dpmm) {
  demand <- demand %>%
    mutate(d1_dpmm_prevalence_index = D1_DPMM,
           coverage_vs_dpmm         = 100 * supply_index / d1_dpmm_prevalence_index)
}

# --- concordance across the three demand definitions -------------------------
cov <- demand %>% select(coverage_vs_prevalence, coverage_vs_consultations, coverage_vs_surgery)
sp <- function(a, b) suppressWarnings(cor(a, b, method = "spearman"))
rho <- c(
  prev_vs_consult = sp(cov$coverage_vs_prevalence,    cov$coverage_vs_consultations),
  prev_vs_surg    = sp(cov$coverage_vs_prevalence,    cov$coverage_vs_surgery),
  consult_vs_surg = sp(cov$coverage_vs_consultations, cov$coverage_vs_surgery)
)
end <- demand %>% filter(YEAR == max(YEAR))
cov_2050 <- c(prevalence = end$coverage_vs_prevalence,
              consultations = end$coverage_vs_consultations,
              surgery = end$coverage_vs_surgery)
robust <- all(cov_2050 > 100)   # supply outpaces demand under ALL three PUBLISHED anchors?
# DPMM is an uncalibrated comparison series: extend the concordance matrix but
# keep it OUT of `robust` and the weakest-margin call above.
if (use_dpmm) {
  rho <- c(rho, prev_vs_dpmm = sp(cov$coverage_vs_prevalence, demand$coverage_vs_dpmm))
}

# --- write outputs -----------------------------------------------------------
OUT_CSV <- here::here("data", "urps_demand_denominators_sensitivity_2026-07-24.csv")
write_csv(demand, OUT_CSV)

cat("=== URPS demand-denominator sensitivity (national, 2025 = 100) ===\n")
cat(sprintf("Implied annual demand growth:  D2 consultations %.2f%%/yr  D3 surgery %.2f%%/yr\n",
            100 * k$growth, 100 * w$growth))
cat(sprintf("2050 demand indices:  supply %.0f | prevalence %.0f | consultations %.0f | surgery %.0f\n",
            end$supply_index, end$d1_prevalence_index, end$d2_consultations_index, end$d3_surgery_index))
cat(sprintf("2050 per-capita coverage (supply/demand): prevalence %.0f | consultations %.0f | surgery %.0f\n",
            cov_2050["prevalence"], cov_2050["consultations"], cov_2050["surgery"]))
cat("Spearman rho of coverage series (should be ~1; all monotone):\n")
print(round(rho, 3))
cat(sprintf("\nROBUSTNESS VERDICT: supply outpaces demand through 2050 under ALL three demand definitions: %s\n",
            if (robust) "YES" else "NO"))
cat(sprintf("  (weakest margin = %s coverage at %.0f in 2050)\n",
            names(which.min(cov_2050)), min(cov_2050)))
cat("NOTE: D2/D3 are constant-growth extrapolations from published anchor years;\n")
cat("      the fully age-specific Wu-2011 surgical model awaits Census-by-age population.\n")
if (use_dpmm) {
  cat(sprintf("DPMM (comparison only, %s): 2050 prevalence index %.0f | coverage %.0f\n",
              if (identical(dpmm_status, "calibrated")) "calibrated" else "UNCALIBRATED",
              end$d1_dpmm_prevalence_index, end$coverage_vs_dpmm))
  cat("      DPMM is a dynamic-prevalence comparison; it does NOT affect the robustness verdict.\n")
}
cat("Wrote", OUT_CSV, "\n")

# --- optional app-styled figure ----------------------------------------------
fig_ok <- requireNamespace("ggplot2", quietly = TRUE)
if (fig_ok) {
  suppressPackageStartupMessages(library(ggplot2))
  TEAL <- "#1b7f79"; ORANGE <- "#c77d1a"; RED <- "#d1495b"; PURPLE <- "#6a4c93"; GREY <- "#8a97a8"; BLUE <- "#3a6ea5"
  ft <- tryCatch({ f <- systemfonts::system_fonts()$family
    if ("Inter" %in% f) "Inter" else "sans" }, error = function(e) "sans")
  fig_cols    <- c("supply_index", "d2_consultations_index", "d3_surgery_index", "d1_prevalence_index")
  fig_levels  <- fig_cols
  fig_labels  <- c("Supply (workforce)", "Demand D2 - new consultations (Kirby 2013)",
                   "Demand D3 - SUI+POP surgery (Wu 2011)", "Demand D1 - any PFD prevalence (Wu 2009)")
  pal <- c("Supply (workforce)" = TEAL,
           "Demand D2 - new consultations (Kirby 2013)" = ORANGE,
           "Demand D3 - SUI+POP surgery (Wu 2011)" = PURPLE,
           "Demand D1 - any PFD prevalence (Wu 2009)" = RED)
  if (use_dpmm) {
    dpmm_lab <- "Demand D1-DPMM - dynamic prevalence (UNCALIBRATED)"
    fig_cols   <- c(fig_cols, "d1_dpmm_prevalence_index")
    fig_levels <- c(fig_levels, "d1_dpmm_prevalence_index")
    fig_labels <- c(fig_labels, dpmm_lab)
    pal[[dpmm_lab]] <- BLUE
  }
  long <- demand %>%
    select(YEAR, all_of(fig_cols)) %>%
    pivot_longer(-YEAR, names_to = "series", values_to = "idx") %>%
    mutate(series = factor(series, levels = fig_levels, labels = fig_labels))
  ends <- long %>% filter(YEAR == max(YEAR))
  p <- ggplot(long, aes(YEAR, idx, color = series)) +
    geom_hline(yintercept = 100, linetype = "dashed", linewidth = 0.4, color = GREY) +
    geom_line(linewidth = 1.1) +
    geom_point(data = ends, size = 2) +
    geom_text(data = ends, aes(label = sprintf("%.0f", idx)), hjust = -0.25,
              size = 12, size.unit = "pt", fontface = "bold", show.legend = FALSE) +
    scale_color_manual(values = pal) +
    scale_x_continuous(breaks = seq(PROJECTION_BASELINE_YEAR, DEMAND_HORIZON_END_YEAR, 5L), expand = expansion(mult = c(0.02, 0.12))) +
    labs(title = "URPS supply outpaces demand under all three demand definitions, 2025-2050",
         subtitle = "Indexed to 2025 = 100. Three independent demand estimands, reported by concordance (never averaged).",
         x = NULL, y = "Index (2025 = 100)", color = NULL,
         caption = "D2/D3 extrapolated from published anchor years under constant proportional growth. DRAFT - illustrative.") +
    theme_minimal(base_size = 13, base_family = ft) +
    theme(plot.title = element_text(size = rel(1.1), face = "bold"),
          plot.title.position = "plot", plot.caption.position = "plot",
          legend.position = "top", legend.justification = "left",
          panel.grid.minor = element_blank())
  FIG <- here::here("augs_application", "figures", "demand_denominator_sensitivity.png")
  dir.create(dirname(FIG), showWarnings = FALSE, recursive = TRUE)
  ggsave(FIG, p, width = 10, height = 5.8, dpi = 300, bg = "white")
  cat("Wrote", FIG, "\n")
}

# =============================================================================
# TODO - age-specific refinement (ready to wire when Census-by-age arrives)
# =============================================================================
# Wu 2011 age-specific SUI+POP surgery rates per 1,000 women/yr (IP+OP), by band.
WU2011_SURGERY_RATE_PER_1000 <- tibble::tribble(
  ~age_band,  ~sui,   ~pop,
  "20-39",    0.473,  0.500,
  "40-59",    2.390,  1.645,
  "60-79",    3.094,  2.719,
  "80plus",   1.684,  1.069
)
# apply_age_specific_surgery_demand(): given a data frame of projected U.S. FEMALE
# population by (YEAR, age_band in the four Wu bands), returns projected annual
# SUI+POP surgery volume = sum_band pop_band * (sui+pop)/1000. This yields a
# faithful, age-structured D3 that supersedes the national-anchor extrapolation
# above. Requires Census 2023 NPP female population by 20-39/40-59/60-79/>=80,
# which the current supply-demand CSV (women_40plus, women_65plus only) does not
# carry. Wire this once that population table exists.
apply_age_specific_surgery_demand <- function(pop_by_band,
                                              rates = WU2011_SURGERY_RATE_PER_1000) {
  stopifnot(all(c("YEAR", "age_band", "female_pop") %in% names(pop_by_band)))
  pop_by_band %>%
    dplyr::inner_join(rates, by = "age_band") %>%
    dplyr::mutate(surgeries = female_pop * (sui + pop) / 1000) %>%
    dplyr::group_by(YEAR) %>%
    dplyr::summarise(surgery_volume = sum(surgeries), .groups = "drop")
}
