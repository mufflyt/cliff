# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Figure 1 (Option A) — Scenario workforce projection, 2025-2029
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Shah-style fixed-entrant scenario forecast: per subspecialty, three graduate-
# inflow scenarios (conservative / status-quo / optimistic) with individual-level
# Monte Carlo 95% bands. Reads data/scenario_projection_trajectories.csv
# (producer: scripts/scenario_projection_trajectories.R); the status-quo 2029
# median matches projected_2029 in the SSOT, so the figure cannot drift from Table 2.
#
# Author: Tyler Muffly, MD / Claude Code   Date: 2026-07-19
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(ggplot2); library(scales); library(here)
})
source(here::here("R", "theme_publication.R"))

.SCEN_LEVELS <- c("conservative", "status-quo", "optimistic")

#' Build Figure 1A: scenario workforce-projection trajectories.
#' @param traj_path Path to the scenario-trajectory CSV.
#' @param show_title Draw an in-figure title (default FALSE for journal submission).
#' @return A ggplot object.
create_figure_scenario_projection <- function(
    traj_path = here::here("data", "scenario_projection_trajectories.csv"),
    show_title = FALSE) {

  # Plot PERCENT CHANGE from the 2025 baseline on a COMMON y-axis (review point
  # #12): with a shared axis, subspecialty growth slopes are directly comparable,
  # unlike the independent-axis absolute-count view. Facet by scenario, colour by
  # subspecialty. Absolute counts remain in Table 2.
  # Main manuscript figure shows the two board-certified subspecialties only;
  # MIGS (exploratory focused-practice designation) is reported in the supplement.
  traj <- readr::read_csv(traj_path, show_col_types = FALSE) %>%
    dplyr::filter(subspecialty_abbrev %in% c("GO", "URPS")) %>%
    dplyr::group_by(subspecialty_abbrev, scenario) %>%
    dplyr::mutate(
      base = median[year == min(year)],
      pct = 100 * (median - base) / base,
      pct_lo = 100 * (lo - base) / base,
      pct_hi = 100 * (hi - base) / base
    ) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      scenario = factor(scenario, levels = .SCEN_LEVELS),
      subspecialty_abbrev = factor(subspecialty_abbrev, levels = c("GO", "URPS"))
    )

  p <- ggplot(traj, aes(x = year, y = pct, colour = subspecialty_abbrev,
                        fill = subspecialty_abbrev)) +
    geom_ribbon(aes(ymin = pct_lo, ymax = pct_hi), alpha = 0.15, colour = NA) +
    geom_line(linewidth = 0.9) +
    geom_point(data = dplyr::filter(traj, year %in% range(traj$year)), size = 1.4) +
    facet_wrap(~scenario, nrow = 1) +
    scale_color_green_journal(name = "Subspecialty") +
    scale_fill_green_journal(name = "Subspecialty") +
    scale_x_continuous(breaks = sort(unique(traj$year)),
                       guide = guide_axis(check.overlap = TRUE)) +
    scale_y_continuous(labels = function(x) paste0("+", x, "%")) +
    labs(
      x = NULL, y = "Change from 2025 baseline",
      title = if (isTRUE(show_title))
        "Scenario workforce projection, 2025-2029 (% change)" else NULL
    ) +
    theme_green_journal() +
    theme(
      strip.text = element_text(face = "bold", size = rel(0.95)),
      strip.background = element_rect(fill = "gray95", colour = "gray80"),
      panel.spacing = unit(1, "lines"),
      plot.title = element_text(size = rel(1.1)),
      plot.title.position = "plot",
      legend.position = "bottom"
    )
  p
}

#' Save Figure 1A at Obstetrics & Gynecology submission specs (title-less TIFF + PNG).
save_figure_scenario_projection <- function(out_dir = here::here("manuscript", "figures")) {
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  fig <- create_figure_scenario_projection(show_title = FALSE)
  tiff_path <- file.path(out_dir, "figure1_scenario_projection.tiff")
  png_path  <- file.path(out_dir, "figure1_scenario_projection.png")
  ggsave(tiff_path, fig, width = 7.5, height = 3.6, dpi = 300,
         units = "in", bg = "white", device = "tiff", compression = "lzw")
  ggsave(png_path, fig, width = 7.5, height = 3.6, dpi = 300, units = "in", bg = "white")
  invisible(c(tiff = tiff_path, png = png_path))
}

if (identical(environment(), globalenv()) && !interactive() && sys.nframe() == 0L) {
  paths <- save_figure_scenario_projection()
  cat("Wrote", paths[["tiff"]], "and", paths[["png"]], "\n")
}
