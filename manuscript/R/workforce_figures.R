# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Manuscript figure builders (return ggplot objects; captions live in the Rmd
# fig.cap per journal convention, so these plots carry NO baked-in title/subtitle).
# Palette + theme match scripts/make_cool_cliff_figures.R.
#
# PROVENANCE: these builders are called by manuscript_WORKFORCE_CLIFF.Rmd at
# render time and write manuscript/figures/figure1-1.png and figure2-1.png.
# They READ data/workforce_projections_consolidated.csv (via load_workforce_data)
# plus data/graduation_active_transition_projection.csv and, for Figure 2, the
# hierarchical/sensitivity CSVs. These are the CURRENT (1,306, pooled) figures;
# see docs/FIGURE_PROVENANCE.md for how they relate to the code/ pipeline figures.
#   fig_trajectory()  -> Figure 1: 2025-2029 projection, immediate vs transition-adjusted
#   fig_robustness()  -> Figure 2: completion-to-departure ratio across every stress test
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
suppressPackageStartupMessages({library(readr); library(dplyr); library(tidyr)
  library(ggplot2); library(here); library(scales)})

.wf_GO <- "#1b6ca8"; .wf_URPS <- "#d1495b"
.wf_lab <- c(GO = "Gynecologic Oncology", URPS = "Urogynecology (both-pathway)")
.wf_pal <- setNames(c(.wf_GO, .wf_URPS), .wf_lab[c("GO","URPS")])
.wf_rd  <- function(f) read_csv(here("data",f), show_col_types = FALSE)

.wf_theme <- function(base = 11) theme_minimal(base_size = base) +
  theme(plot.title.position = "plot",
        panel.grid.minor = element_blank(),
        legend.position = "top", legend.title = element_blank(),
        legend.margin = margin(b = -4),
        axis.title = element_text(size = rel(0.9)))

#' Figure 1: near-term urogynecology workforce projection, 2025-2029 (URPS only).
#' Immediate-entry (solid) vs empirical entry ramp (dashed); endpoints labeled directly.
fig_trajectory <- function() {
  # Drive Figure 1 from the SSOT (workforce_projections_consolidated.csv via
  # load_workforce_data), NOT the stale producerless scenario_projection_trajectories.csv
  # (which is on a 1,295 baseline). Baseline, 2029 immediate endpoint, and the 95%
  # interval are the SSOT values; the ramp endpoint is the transition CSV. The near-term
  # trajectory is near-linear, so it is drawn baseline -> 2029 endpoint.
  ss <- load_workforce_data(); u <- ss[ss$subspecialty_abbrev == "URPS", ]
  ramp_end <- .wf_rd("graduation_active_transition_projection.csv") %>%
    filter(subspecialty_abbrev == "URPS") %>% pull(projected_2029_ramped) %>% `[`(1)
  yr0 <- 2025L; yr1 <- 2029L; acc <- .wf_URPS
  base_med <- u$baseline_2025; imm_end <- u$projected_2029
  lo29 <- u$ci95_lower; hi29 <- u$ci95_upper
  yrs <- yr0:yr1; f <- (yrs - yr0) / (yr1 - yr0)
  sq <- tibble(year = yrs, median = base_med + f * (imm_end - base_med),
               lo = base_med + f * (lo29 - base_med), hi = base_med + f * (hi29 - base_med))
  ramp_line <- tibble(year = c(yr0, yr1), median = c(base_med, ramp_end))
  ends <- tibble(year = c(yr0, yr1, yr1), median = c(base_med, imm_end, ramp_end),
                 kind = c("baseline","immediate","ramp"))
  lab <- tibble(x = c(yr0, yr1, yr1) + c(0.05, 0.08, 0.08),
                y = c(base_med, imm_end, ramp_end),
                txt = c(sprintf("2025 baseline: %s", comma(round(base_med))),
                        sprintf("Immediate entry: %s", comma(round(imm_end))),
                        sprintf("Empirical entry ramp: %s", comma(round(ramp_end)))),
                h = c(0, 0, 0), v = c(-1.4, -0.6, 1.6))
  ggplot(sq, aes(year, median)) +
    geom_ribbon(aes(ymin = lo, ymax = hi), fill = acc, alpha = .12) +
    geom_line(linewidth = 1.3, colour = acc) +
    geom_line(data = ramp_line, linewidth = 1.1, colour = acc, linetype = "dashed") +
    geom_point(data = ends, aes(shape = kind, fill = kind), size = 2.8, colour = acc, stroke = 1) +
    scale_shape_manual(values = c(baseline = 16, immediate = 16, ramp = 21), guide = "none") +
    scale_fill_manual(values = c(baseline = acc, immediate = acc, ramp = "white"), guide = "none") +
    geom_text(data = lab, aes(x, y, label = txt, hjust = h, vjust = v),
              size = 9, size.unit = "pt", colour = "grey20", inherit.aes = FALSE) +
    scale_x_continuous(breaks = yr0:yr1, limits = c(yr0, yr1 + 0.05)) +
    scale_y_continuous(labels = comma) +
    coord_cartesian(clip = "off") +
    labs(x = NULL, y = "Active urogynecologists") +
    .wf_theme() + theme(legend.position = "none", plot.margin = margin(8, 96, 8, 8))
}

#' Figure 2: selected urogynecology sensitivity analyses (URPS only), log ratio axis.
#' Primary at top (filled), most adverse combined at bottom (outlined); values printed.
fig_robustness <- function() {
  wf <- .wf_rd("workforce_projections_consolidated.csv"); mort <- .wf_rd("mortality_sensitivity.csv")
  cons <- .wf_rd("consistent_definition_baseline_sensitivity.csv"); op <- .wf_rd("open_payments_sensitivity.csv")
  win <- .wf_rd("departure_window_sensitivity.csv"); grid <- .wf_rd("sensitivity_grid_summary.csv")
  g <- function(df, col) df[[col]][df$subspecialty_abbrev == "URPS"]
  labs_v <- c("Primary","Anchored-definition baseline","Open Payments-inclusive",
              "+ half expected deaths","+ all expected deaths",
              "Full window (2016-2023)","Tripled departure rate","Most adverse combined")
  rob <- tibble(
    scenario = labs_v,
    ratio = c(g(wf,"replacement_ratio"), g(cons,"ratio_consistent"),
              op$replacement_ratio[op$rule == "op_inclusive" & op$subspecialty_abbrev == "URPS"],
              g(mort,"ratio_adj_half_missed"), g(mort,"ratio_adj_all_missed"),
              win$dynamic_ratio[win$label == "full" & win$subspecialty_abbrev == "URPS"],
              g(grid,"oneway_min"), g(grid,"worst_ratio"))) %>%
    mutate(scenario = factor(scenario, levels = rev(labs_v)),   # Primary top, adverse bottom
           kind = dplyr::case_when(scenario == "Primary" ~ "primary",
                                   scenario == "Most adverse combined" ~ "adverse", TRUE ~ "other"))
  acc <- .wf_URPS
  ggplot(rob, aes(ratio, scenario)) +
    annotate("rect", xmin = 0.8, xmax = 1, ymin = -Inf, ymax = Inf, fill = "grey90", alpha = .7) +
    geom_vline(xintercept = 1, linetype = "dashed", colour = "grey40") +
    geom_point(aes(shape = kind, fill = kind), size = 3.3, colour = acc, stroke = 1) +
    geom_text(aes(label = sprintf("%.1f", ratio)), hjust = -0.45, size = 9, size.unit = "pt", colour = "grey20") +
    scale_shape_manual(values = c(primary = 21, adverse = 21, other = 21), guide = "none") +
    scale_fill_manual(values = c(primary = acc, adverse = "white", other = acc), guide = "none") +
    scale_x_log10(breaks = c(1, 2, 4), limits = c(0.8, 7)) +
    coord_cartesian(clip = "off") +
    labs(x = "Completion-to-departure ratio (log scale; dashed line = replacement)", y = NULL) +
    .wf_theme() + theme(legend.position = "none", plot.margin = margin(8, 40, 8, 8))
}
