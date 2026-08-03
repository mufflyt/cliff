# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Methods schematic: the dynamic age-structured stock-flow supply forecast.
#
# PROVENANCE: constructed schematic (NO data input) explaining the model design
# described in manuscript_WORKFORCE_CLIFF.Rmd Study Design + Projection Model.
# Called at render time via fig_stock_flow_design(); also writes
# manuscript/figures/figure_stock_flow_design.{png,tiff} when run standalone
#   (Rscript manuscript/R/create_figure_stock_flow_design.R).
# Palette/theme match manuscript/R/workforce_figures.R (.wf_GO / .wf_URPS).
# Created 2026-08-02. See docs/FIGURE_PROVENANCE.md.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
suppressPackageStartupMessages({library(ggplot2); library(tibble); library(here)})

.sf_GO   <- "#1b6ca8"   # matches .wf_GO
.sf_URPS <- "#d1495b"   # matches .wf_URPS
.sf_stock <- "#e8eef3"  # light stock fill
.sf_in    <- "#e6f0ea"  # inflow fill (green-ish)
.sf_out   <- "#f6e7ea"  # outflow fill (red-ish)
.sf_band  <- "#f4f2ee"  # wrapper band fill
.sf_ink   <- "#20303a"  # text ink

#' Figure: dynamic stock-flow supply-forecast schematic (returns a ggplot).
fig_stock_flow_design <- function() {
  # Boxes: xmin,xmax,ymin,ymax,label,fill,border,txtcol,size(pt),face
  boxes <- tibble::tribble(
    ~x0, ~x1, ~y0,  ~y1,  ~fill,       ~border,   ~txt,     ~size, ~face, ~label,
    # inflow / stock / outflow row
    0.20, 3.15, 6.05, 7.75, .sf_in,    .sf_GO,   .sf_ink,   9,  "plain",
      "INFLOW  —  workforce entrants\nACGME fellowship completers\n(recent 4-year mean; enter at entry age;\n70–100% practice-conversion sensitivity)",
    4.05, 7.95, 5.70, 8.10, .sf_stock, "#5b6b76", .sf_ink,  9,  "plain",
      "STOCK  —  active age-structured workforce\nEstimated 2025 baseline carried forward\nfrom latest administrative signals\nGO (single-pathway) · URPS (both-pathway)",
    8.85, 11.80, 6.05, 7.75, .sf_out,  .sf_URPS, .sf_ink,   9,  "plain",
      "OUTFLOW  —  workforce exit\nSustained clinical-practice departure\nEmpirical POOLED age-band hazard\n(2016–2021 life table, GO+URPS)",
    # uncertainty wrapper band
    0.20, 11.80, 2.55, 3.75, .sf_band, "#9aa7b0", .sf_ink,  8.5, "plain",
      "UNCERTAINTY  ·  Monte Carlo (10,000 draws: Beta hazard posteriors + empirical graduate resampling)  +  multidimensional sensitivity\n(observation window  ×  departure-rate multiplier up to 3×  ×  70–100% graduate conversion)  →  scenarios: conservative | status-quo (primary) | optimistic",
    # outputs band
    0.20, 11.80, 0.85, 2.30, "#eef3ee", "#7d9a86", .sf_ink, 8.5, "plain",
      "OUTPUTS  ·  annual headcount trajectory (2025–2029)  ·  fellowship-completion-to-departure ratio\nproductivity-adjusted FTE capacity  ·  supply vs demand (women ≥65 y, pelvic floor disorders)"
  )

  # Annual-iteration banner over the stock
  loop_lab <- "ANNUAL STEP, 2025–2029:   age each cohort +1 yr   →   apply age-band hazard (departures out)   →   add new graduates (entrants in)"

  # Arrows: x,xend,y,yend + label
  arrows <- tibble::tribble(
    ~x, ~xend, ~y, ~yend, ~lab, ~labx, ~laby,
    3.15, 4.05, 6.90, 6.90, "entrants", 3.60, 7.20,   # inflow -> stock
    7.95, 8.85, 6.90, 6.90, "departures", 8.40, 7.20, # stock -> outflow
    6.00, 6.00, 5.70, 4.05, "", 0, 0,                 # stock -> timeline
    6.00, 6.00, 2.55, 2.30, "", 0, 0                  # uncertainty -> outputs (visual flow)
  )

  # Forecast-horizon timeline
  tl_y <- 4.30
  ticks <- tibble::tribble(
    ~x, ~year, ~sub,
    2.30, "2025", "baseline (est.)",
    6.60, "2029", "calibrated horizon\n(back-test ~1%)",
    11.10, "2050", "demand-aligned\n(provisional)"
  )

  ggplot() +
    # boxes
    geom_rect(data = boxes, aes(xmin = x0, xmax = x1, ymin = y0, ymax = y1),
              fill = boxes$fill, colour = boxes$border, linewidth = 0.6) +
    geom_text(data = boxes, aes(x = (x0 + x1) / 2, y = (y0 + y1) / 2, label = label),
              colour = boxes$txt, size = boxes$size, size.unit = "pt", lineheight = 1.05) +
    # annual-step banner
    annotate("rect", xmin = 4.05, xmax = 7.95, ymin = 8.35, ymax = 9.05,
             fill = "#fbf6e9", colour = "#c9a94e", linewidth = 0.5) +
    annotate("text", x = 6.0, y = 8.70, label = loop_lab,
             colour = .sf_ink, size = 7.6, size.unit = "pt", lineheight = 1.05) +
    annotate("segment", x = 6.0, xend = 6.0, y = 8.35, yend = 8.10,
             arrow = arrow(length = unit(6, "pt"), type = "closed"), colour = "#c9a94e", linewidth = 0.5) +
    # flow arrows
    geom_segment(data = arrows, aes(x = x, xend = xend, y = y, yend = yend),
                 arrow = arrow(length = unit(7, "pt"), type = "closed"),
                 colour = "#42525c", linewidth = 0.7) +
    geom_text(data = subset(arrows, nzchar(lab)),
              aes(x = labx, y = laby, label = lab),
              colour = "#42525c", size = 8, size.unit = "pt", fontface = "italic") +
    # timeline
    annotate("segment", x = 1.9, xend = 11.5, y = tl_y, yend = tl_y,
             colour = "#5b6b76", linewidth = 0.7,
             arrow = arrow(length = unit(7, "pt"), type = "closed")) +
    geom_point(data = ticks, aes(x = x, y = tl_y), colour = "#5b6b76", size = 2) +
    geom_text(data = ticks, aes(x = x, y = tl_y + 0.42, label = year),
              colour = .sf_ink, size = 9, size.unit = "pt", fontface = "bold") +
    geom_text(data = ticks, aes(x = x, y = tl_y - 0.42, label = sub),
              colour = "#5b6b76", size = 7.5, size.unit = "pt", lineheight = 1.0) +
    coord_cartesian(xlim = c(0, 12), ylim = c(0.8, 9.2), expand = FALSE, clip = "off") +
    theme_void()
}

# Standalone: write the durable figure files with provenance-friendly settings.
if (identical(environment(), globalenv()) && sys.nframe() == 0L) {
  p <- fig_stock_flow_design()
  outdir <- here::here("manuscript", "figures")
  dir.create(outdir, showWarnings = FALSE, recursive = TRUE)
  png_path  <- file.path(outdir, "figure_stock_flow_design.png")
  tiff_path <- file.path(outdir, "figure_stock_flow_design.tiff")
  ggsave(png_path,  p, width = 9.2, height = 5.0, dpi = 300, bg = "white")
  ggsave(tiff_path, p, width = 9.2, height = 5.0, dpi = 300, bg = "white",
         compression = "lzw")
  cat("WROTE ", png_path, "\n", "WROTE ", tiff_path, "\n", sep = "")
}
