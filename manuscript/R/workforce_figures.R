# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Manuscript figure builders (return ggplot objects; captions live in the Rmd
# fig.cap per journal convention, so these plots carry NO baked-in title/subtitle).
# Palette + theme match scripts/make_cool_cliff_figures.R.
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

#' Figure 1: status-quo workforce trajectory, immediate-entry vs transition-adjusted.
fig_trajectory <- function() {
  traj <- .wf_rd("scenario_projection_trajectories.csv") %>% filter(subspecialty_abbrev %in% c("GO","URPS"))
  sq <- traj %>% filter(tolower(scenario) %in% c("status_quo","status-quo","status quo"))
  if (nrow(sq) == 0) sq <- traj %>% group_by(subspecialty_abbrev) %>%
    filter(scenario == dplyr::nth(unique(scenario), 1)) %>% ungroup()
  ramp <- .wf_rd("graduation_active_transition_projection.csv") %>% filter(subspecialty_abbrev %in% c("GO","URPS"))
  end_yr <- max(sq$year)
  sq   <- sq   %>% mutate(cohort = .wf_lab[subspecialty_abbrev])
  ramp_pts <- ramp %>% transmute(subspecialty_abbrev, year = end_yr, median = projected_2029_ramped,
                                 cohort = .wf_lab[subspecialty_abbrev])
  # transition-adjusted trajectory: a dashed path from each cohort's 2025 baseline to its
  # 2029 transition-adjusted endpoint, so both projections are shown as lines (not just a point).
  base_pts <- sq %>% group_by(subspecialty_abbrev, cohort) %>% dplyr::filter(year == min(year)) %>%
    dplyr::ungroup() %>% dplyr::select(subspecialty_abbrev, cohort, year, median)
  ramp_line <- dplyr::bind_rows(base_pts, dplyr::select(ramp_pts, subspecialty_abbrev, cohort, year, median))
  ggplot(sq, aes(year, median, colour = cohort, fill = cohort)) +
    geom_ribbon(aes(ymin = lo, ymax = hi), alpha = .15, colour = NA) +
    geom_line(data = ramp_line, aes(year, median), linetype = "dashed", linewidth = .9, show.legend = FALSE) +
    geom_line(linewidth = 1.1) + geom_point(size = 2) +
    geom_point(data = ramp_pts, aes(year, median), shape = 21, size = 3.6, stroke = 1.1, fill = "white") +
    geom_text(data = ramp_pts, aes(label = sprintf("transition-\nadjusted: %s", comma(round(median)))),
              hjust = 1.1, vjust = 1.2, size = 8, size.unit = "pt", lineheight = .9, show.legend = FALSE) +
    scale_colour_manual(values = .wf_pal, aesthetics = c("colour","fill")) +
    scale_x_continuous(breaks = unique(sq$year), guide = guide_axis(check.overlap = TRUE)) +
    scale_y_continuous(labels = comma) +
    labs(x = NULL, y = "Active subspecialists") +
    .wf_theme()
}

#' Figure 2: completion-to-departure ratio across the full stress-test set.
fig_robustness <- function() {
  wf <- .wf_rd("workforce_projections_consolidated.csv"); mort <- .wf_rd("mortality_sensitivity.csv")
  cons <- .wf_rd("consistent_definition_baseline_sensitivity.csv"); op <- .wf_rd("open_payments_sensitivity.csv")
  win <- .wf_rd("departure_window_sensitivity.csv"); grid <- .wf_rd("sensitivity_grid_summary.csv")
  g <- function(df, ab, col) df[[col]][df$subspecialty_abbrev == ab]
  rows <- function(ab) tibble(
    scenario = c("Primary","Anchored-definition baseline","Open Payments-inclusive",
                 "+ half expected deaths","+ all expected deaths",
                 "Full window (2016-2023)","3x departure rate","Worst-case combined"),
    ratio = c(g(wf,ab,"replacement_ratio"), g(cons,ab,"ratio_consistent"),
              op$replacement_ratio[op$rule == "op_inclusive" & op$subspecialty_abbrev == ab],
              g(mort,ab,"ratio_adj_half_missed"), g(mort,ab,"ratio_adj_all_missed"),
              win$dynamic_ratio[win$label == "full" & win$subspecialty_abbrev == ab],
              g(grid,ab,"oneway_min"), g(grid,ab,"worst_ratio")),
    ab = ab)
  rob <- bind_rows(rows("GO"), rows("URPS")) %>%
    mutate(scenario = factor(scenario, levels = rev(unique(scenario))), cohort = .wf_lab[ab])
  ggplot(rob, aes(ratio, scenario, colour = cohort)) +
    annotate("rect", xmin = -Inf, xmax = 1, ymin = -Inf, ymax = Inf, fill = "grey90", alpha = .6) +
    geom_vline(xintercept = 1, linetype = "dashed", colour = "grey40") +
    geom_segment(aes(x = 1, xend = ratio, yend = scenario),
                 position = position_dodge(width = .6), linewidth = .9, alpha = .5) +
    geom_point(position = position_dodge(width = .6), size = 3.2) +
    geom_text(aes(label = sprintf("%.1f", ratio)), position = position_dodge(width = .6),
              hjust = -0.35, size = 8, size.unit = "pt", show.legend = FALSE) +
    scale_colour_manual(values = .wf_pal) +
    scale_x_continuous(limits = c(0, max(rob$ratio) * 1.12), breaks = seq(0, 8, 2),
                       expand = expansion(mult = c(0, .02))) +
    labs(x = "Completion-to-departure ratio", y = NULL) +
    .wf_theme()
}
