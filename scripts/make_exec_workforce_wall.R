#!/usr/bin/env Rscript
# Executive "100-person workforce wall": for every 100 urogynecologists who leave
# under the WORST-CASE sensitivity, only 86 are replaced (14 vacancies).
# Number is real: sensitivity_grid_summary.csv URPS worst_ratio = 0.861, which occurs
# ONLY when the provisional 2016-2023 window + tripled departures + 70% graduate
# conversion are combined. Primary projection is 5.6 (far above replacement); this
# figure is explicitly labeled as the worst-case tail, not the headline.
suppressPackageStartupMessages({library(readr); library(dplyr); library(ggplot2); library(here)})

grid <- read_csv(here("cliff","data","sensitivity_grid_summary.csv"), show_col_types = FALSE)
wf   <- read_csv(here("cliff","data","workforce_projections_consolidated.csv"), show_col_types = FALSE)
wr   <- grid$worst_ratio[grid$subspecialty_abbrev == "URPS"]
prim <- wf$replacement_ratio[wf$subspecialty_abbrev == "URPS"]
unfilled <- round(100 * (1 - wr)); replaced <- 100 - unfilled

NAVY <- "#20355e"; RED <- "#d1495b"
circle <- function(cx, cy, r, n = 30) { t <- seq(0, 2*pi, length.out = n); data.frame(x = cx + r*cos(t), y = cy + r*sin(t)) }
body <- data.frame(bx = c(-0.20, 0.20, 0.18, 0.11, -0.11, -0.18),
                   by = c(-0.24, -0.24, 0.03, 0.17,  0.17,  0.03))

cells <- expand.grid(col = 1:10, row = 1:10)
cells$idx <- (cells$row - 1) * 10 + cells$col
cells$status <- ifelse(cells$idx > replaced, "vacancy", "replaced")   # bottom `unfilled` cells = vacancies
polys <- do.call(rbind, lapply(seq_len(nrow(cells)), function(i) {
  cx <- cells$col[i]; cy <- -cells$row[i]; st <- cells$status[i]
  b <- data.frame(x = cx + body$bx, y = cy + body$by, pid = paste0(i, "_b"), status = st)
  h <- circle(cx, cy + 0.31, 0.12); h$pid <- paste0(i, "_h"); h$status <- st
  rbind(b, h)
}))

p <- ggplot(polys, aes(x, y, group = pid, fill = status, colour = status)) +
  geom_polygon(linewidth = 0.6) +
  scale_fill_manual(values = c(replaced = NAVY, vacancy = "white")) +
  scale_colour_manual(values = c(replaced = NAVY, vacancy = RED)) +
  # bottom banner
  annotate("rect", xmin = 0.35, xmax = 10.65, ymin = -11.75, ymax = -10.95, fill = NAVY) +
  annotate("text", x = 5.5, y = -11.35, label = sprintf("Worst case: the pipeline replaces only %d%% of departures", replaced),
           colour = "white", fontface = "bold", size = 13, size.unit = "pt") +
  coord_equal(clip = "off") +
  labs(title = sprintf("%d positions go unfilled for every 100 urogynecologists who leave", unfilled),
       subtitle = "Navy = replaced by a new urogynecologist   |   Red outline = position left unfilled",
       caption = sprintf(paste0("WORST-CASE SENSITIVITY SCENARIO, not the primary projection. A %.2f replacement ratio occurs only when the",
                                "\nprovisional 2016-2023 window, tripled departures, and 70%% graduate conversion are combined. Primary projection: %.1f."),
                         wr, prim)) +
  theme_void(base_size = 15) +
  theme(plot.title = element_text(face = "bold", size = rel(1.35), colour = RED, hjust = 0.5, margin = margin(b = 4)),
        plot.subtitle = element_text(hjust = 0.5, colour = "grey30", margin = margin(b = 12)),
        plot.caption = element_text(hjust = 0.5, colour = "grey45", size = rel(0.72), lineheight = 1.15, margin = margin(t = 16)),
        legend.position = "none", plot.margin = margin(20, 22, 16, 22))

OUT <- here("cliff","figures","urps_only","urps_exec_workforce_wall.png")
ggsave(OUT, p, width = 9, height = 8.4, dpi = 300, bg = "white")
cat(sprintf("worst_ratio %.3f -> %d unfilled / %d replaced | primary %.2f\n", wr, unfilled, replaced, prim))
cat("wrote", OUT, "\n")
