#!/usr/bin/env Rscript
# National urogynecology supply vs demand, 2025-2050 — static figure styled to
# match the Effective-Adequacy Explorer (Shiny) charts: teal supply, orange
# status-quo demand, red prevalence demand, indexed to 2025 = 100, uncertainty
# ribbons, dashed 2025 reference. Inter font, plot-width title, white background.
suppressPackageStartupMessages({ library(readr); library(dplyr); library(tidyr); library(ggplot2) })

TEAL <- "#1b7f79"; ORANGE <- "#c77d1a"; RED <- "#d1495b"; GREY <- "#8a97a8"; INK <- "#2b2f36"
ft <- tryCatch({
  fams <- systemfonts::system_fonts()$family
  if ("Inter" %in% fams) "Inter" else "sans"
}, error = function(e) "sans")

d <- read_csv(here::here("data","urps_supply_demand_national_2026-07-23.csv"), show_col_types = FALSE)

series <- tibble(
  YEAR = rep(d$YEAR, 3),
  what = factor(rep(c("Supply (workforce)", "Demand — Status Quo (women 65+)",
                      "Demand — pelvic-floor prevalence"), each = nrow(d)),
                levels = c("Supply (workforce)", "Demand — Status Quo (women 65+)",
                           "Demand — pelvic-floor prevalence")),
  idx = c(d$supply_index, d$w65_index, d$pfd_index),
  lo  = c(d$supply_lo_index, d$w65_lo_index, d$pfd_lo_index),
  hi  = c(d$supply_hi_index, d$w65_hi_index, d$pfd_hi_index)
)
pal <- c("Supply (workforce)" = TEAL,
         "Demand — Status Quo (women 65+)" = ORANGE,
         "Demand — pelvic-floor prevalence" = RED)

# endpoint labels (2050)
ends <- series %>% filter(YEAR == max(YEAR))

p <- ggplot(series, aes(YEAR, idx, color = what, fill = what)) +
  geom_hline(yintercept = 100, linetype = "dashed", linewidth = 0.4, color = GREY) +
  geom_ribbon(aes(ymin = lo, ymax = hi), color = NA, alpha = 0.12, show.legend = FALSE) +
  geom_line(linewidth = 1.15) +
  geom_point(data = ends, size = 2.1, show.legend = FALSE) +
  geom_text(data = ends, aes(label = sprintf("%.0f", idx)),
            hjust = -0.25, size = 12, size.unit = "pt", fontface = "bold", show.legend = FALSE) +
  scale_color_manual(values = pal) + scale_fill_manual(values = pal) +
  scale_x_continuous(breaks = seq(2025, 2050, 5), expand = expansion(mult = c(0.02, 0.10))) +
  scale_y_continuous(breaks = seq(90, 200, 10)) +
  labs(
    title = "U.S. urogynecology supply is projected to outpace demographic demand, 2025–2050",
    subtitle = "Indexed to 2025 = 100. Supply = board-certified urogynecologist workforce (both pathways); shaded bands = 95% range.",
    x = NULL, y = "Index (2025 = 100)", color = NULL,
    caption = "Source: ABOG+ABU rosters; U.S. Census 2023 NPP (women 65+); Nygaard/Wu pelvic-floor-disorder prevalence.  DRAFT · illustrative."
  ) +
  theme_minimal(base_size = 13, base_family = ft) +
  theme(
    plot.title = element_text(size = rel(1.12), face = "bold", color = INK),
    plot.title.position = "plot",
    plot.subtitle = element_text(size = rel(0.86), color = "#5b636e", margin = margin(b = 10)),
    plot.caption = element_text(size = rel(0.66), color = "#98a0ab", hjust = 0),
    plot.caption.position = "plot",
    legend.position = "top", legend.justification = "left",
    legend.text = element_text(size = rel(0.86)),
    axis.title.y = element_text(size = rel(0.86), color = "#5b636e"),
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(color = "#ecedf0", linewidth = 0.4),
    plot.margin = margin(14, 18, 10, 14)
  )

out <- here::here("augs_application","figures","urps_supply_demand_figure.png")
ggsave(out, p, width = 9.5, height = 5.6, dpi = 300, bg = "white")
cat("wrote", out, "|", round(file.info(out)$size/1e3), "KB\n")
cat(sprintf("2050 endpoints -> supply=%.0f  demand(w65)=%.0f  demand(pfd)=%.0f\n",
            ends$idx[ends$what=="Supply (workforce)"],
            ends$idx[grepl("Status Quo", ends$what)],
            ends$idx[grepl("prevalence", ends$what)]))
