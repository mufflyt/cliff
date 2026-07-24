# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Figure 2 (Option B) — Workforce-metric comparison dashboard
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Per-subspecialty contrast of the three headcount quantities that drive the
# conclusion, plus the operative-validity flag, in one figure (reviewer request):
#   Panel 1  Annual departure rate (%/yr)
#   Panel 2  Headcount replacement ratio (with the 1.0 reference line)
#   Panel 3  Annual graduates vs mean annual departures (dodged)
# Built directly from the SSOT (workforce_projections_consolidated.csv) via the
# data contract, and from operative_adjudication.csv for the validity caption, so
# the figure cannot drift from Tables 1-2 or Appendix S11.
#
# Author: Tyler Muffly, MD / Claude Code   Date: 2026-07-19
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(ggplot2); library(scales); library(here)
})
source(here::here("manuscript", "R", "workforce_data_contract.R"))
source(here::here("R", "theme_publication.R"))

#' Build Figure 2B: workforce-metric comparison dashboard.
#' @param workforce_summary Validated SSOT table (defaults to load_workforce_data()).
#' @param show_title Draw an in-figure title (default FALSE for journal submission).
#' @return A ggplot object.
create_figure_workforce_comparison <- function(workforce_summary = load_workforce_data(),
                                               show_title = FALSE) {
  ord <- c("GO", "URPS", "MIGS")
  ws <- workforce_summary %>%
    dplyr::mutate(subspecialty_abbrev = factor(subspecialty_abbrev, levels = ord))

  P_RATE <- "Departure rate (%/yr)"
  P_RATIO <- "Headcount replacement ratio"
  P_FLOW <- "Graduates vs departures/yr (n)"
  plevels <- c(P_RATE, P_RATIO, P_FLOW)

  single <- dplyr::bind_rows(
    ws %>% dplyr::transmute(subspecialty_abbrev, panel = P_RATE,
                            series = "value", value = annual_retirement_rate),
    ws %>% dplyr::transmute(subspecialty_abbrev, panel = P_RATIO,
                            series = "value", value = replacement_ratio)
  )
  flow <- dplyr::bind_rows(
    ws %>% dplyr::transmute(subspecialty_abbrev, panel = P_FLOW,
                            series = "Graduates", value = annual_entrants),
    ws %>% dplyr::transmute(subspecialty_abbrev, panel = P_FLOW,
                            series = "Departures", value = avg_annual_retirements)
  )
  d <- dplyr::bind_rows(single, flow) %>%
    dplyr::mutate(panel = factor(panel, levels = plevels),
                  series = factor(series, levels = c("value", "Graduates", "Departures")))

  pal <- palette_green_journal(3)
  fill_cols <- c(value = pal[1], Graduates = pal[2], Departures = pal[3])
  lab <- function(v, panel) ifelse(panel == P_RATIO, sprintf("%.2f", v),
                            ifelse(panel == P_RATE, sprintf("%.1f", v), sprintf("%.0f", v)))

  # 1.0 replacement reference line lives only in the ratio panel.
  href <- data.frame(panel = factor(P_RATIO, levels = plevels), yint = 1)

  p <- ggplot(d, aes(x = subspecialty_abbrev, y = value, fill = series)) +
    geom_col(position = position_dodge2(preserve = "single"), width = 0.7) +
    geom_hline(data = href, aes(yintercept = yint), linetype = "dashed",
               linewidth = 0.4, colour = "grey40") +
    geom_text(aes(label = lab(value, panel),
                  group = series),
              position = position_dodge2(width = 0.7, preserve = "single"),
              vjust = -0.4, size = 12, size.unit = "pt") +
    facet_wrap(~panel, scales = "free_y", nrow = 1) +
    scale_fill_manual(values = fill_cols, breaks = c("Graduates", "Departures"),
                      name = NULL) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
    labs(
      x = NULL, y = NULL,
      # Operative-validity note lives in the manuscript figure caption, not in the
      # image (review point #12): an in-image footnote is unreadable in print.
      title = if (isTRUE(show_title)) "Workforce-metric comparison" else NULL
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

#' Save Figure 2B at Obstetrics & Gynecology submission specs (title-less TIFF + PNG).
save_figure_workforce_comparison <- function(out_dir = here::here("manuscript", "figures")) {
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  fig <- create_figure_workforce_comparison(show_title = FALSE)
  tiff_path <- file.path(out_dir, "figure2_workforce_comparison.tiff")
  png_path  <- file.path(out_dir, "figure2_workforce_comparison.png")
  ggsave(tiff_path, fig, width = 7.5, height = 3.6, dpi = 300,
         units = "in", bg = "white", device = "tiff", compression = "lzw")
  ggsave(png_path, fig, width = 7.5, height = 3.6, dpi = 300, units = "in", bg = "white")
  invisible(c(tiff = tiff_path, png = png_path))
}

if (identical(environment(), globalenv()) && !interactive() && sys.nframe() == 0L) {
  paths <- save_figure_workforce_comparison()
  cat("Wrote", paths[["tiff"]], "and", paths[["png"]], "\n")
}
