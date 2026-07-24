#!/usr/bin/env Rscript
# Four more executive worst-case urogynecology-workforce figures (companion to
# make_exec_workforce_wall.R). All from real data: sensitivity_grid_summary.csv
# URPS worst_ratio = 0.861 (14 unfilled / 86 replaced per 100), which occurs ONLY
# under the provisional 2016-2023 window + tripled departures + 70% conversion.
# Primary projection = 5.6. Every figure carries the worst-case label.
#   A disappearing-team flow   B replacement gauge   C leaking-pipeline funnel   D risk card
suppressPackageStartupMessages({library(readr); library(dplyr); library(ggplot2); library(here)})

g  <- read_csv(here("cliff","data","sensitivity_grid_summary.csv"), show_col_types = FALSE)
wf <- read_csv(here("cliff","data","workforce_projections_consolidated.csv"), show_col_types = FALSE)
wr   <- g$worst_ratio[g$subspecialty_abbrev == "URPS"]
prim <- wf$replacement_ratio[wf$subspecialty_abbrev == "URPS"]
ent  <- wf$annual_entrants[wf$subspecialty_abbrev == "URPS"]
unf  <- round(100 * (1 - wr)); rep86 <- 100 - unf
NAVY <- "#20355e"; RED <- "#d1495b"; GREEN <- "#2a9d8f"; YEL <- "#e9c46a"; GREY <- "grey80"
OUT <- here("cliff","figures","urps_only"); dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
WC <- "Worst-case sensitivity scenario, not the primary projection (primary: 5.6 completions per departure)."

# person icon (body polygon + head circle) centered at (cx,cy), size s
person <- function(cx, cy, s, id, status) {
  b <- data.frame(x = cx + s*c(-0.20,0.20,0.18,0.11,-0.11,-0.18),
                  y = cy + s*c(-0.24,-0.24,0.03,0.17,0.17,0.03), pid = paste0(id,"b"), status = status)
  t <- seq(0, 2*pi, length.out = 30)
  h <- data.frame(x = cx + s*0.12*cos(t), y = cy + s*0.31 + s*0.12*sin(t), pid = paste0(id,"h"), status = status)
  rbind(b, h)
}
person_theme <- function() theme_void(base_size = 15) +
  theme(plot.title = element_text(face = "bold", size = rel(1.3), colour = RED, hjust = .5, margin = margin(b = 4)),
        plot.subtitle = element_text(hjust = .5, colour = "grey30", margin = margin(b = 10)),
        plot.caption = element_text(hjust = .5, colour = "grey45", size = rel(0.72), margin = margin(t = 14)),
        legend.position = "none", plot.margin = margin(20, 22, 16, 22))

# ============================ A: disappearing team (flow) ============================
# each icon = 5 physicians; 100 leave -> 20 icons; 86 arrive -> 17 icons + 3 vacancies (rounded to 20-scale)
mk_row <- function(n_total, n_fill, y, per) {
  do.call(rbind, lapply(seq_len(n_total), function(i)
    person(cx = i, cy = y, s = 0.62, id = paste0(y,"_",i),
           status = ifelse(i <= n_fill, "have", "gap"))))
}
leaveN <- 20; arriveIcons <- round(rep86/5)                # 20 leave, 17 arrive
top <- mk_row(leaveN, leaveN, 3)                            # all filled (leaving)
bot <- do.call(rbind, lapply(seq_len(leaveN), function(i)
  person(i, 0, 0.62, paste0("b",i), ifelse(i <= arriveIcons, "have", "gap"))))
pA <- ggplot(mapping = aes(x, y, group = pid, fill = status, colour = status)) +
  geom_polygon(data = top) + geom_polygon(data = bot) +
  annotate("text", x = 0.3, y = 3, hjust = 1, label = "100 leave", fontface = "bold", size = 14, size.unit = "pt", colour = NAVY) +
  annotate("text", x = 0.3, y = 0, hjust = 1, label = sprintf("%d arrive", rep86), fontface = "bold", size = 14, size.unit = "pt", colour = NAVY) +
  annotate("segment", x = 10.5, xend = 10.5, y = 2.3, yend = 0.9, arrow = arrow(length = unit(0.16,"in"), type = "closed"), colour = "grey55", linewidth = 1.1) +
  scale_fill_manual(values = c(have = NAVY, gap = "white")) +
  scale_colour_manual(values = c(have = NAVY, gap = RED)) +
  coord_equal(clip = "off", xlim = c(-3.2, 21)) +
  labs(title = "The replacement pipeline does not keep up",
       subtitle = "Each figure = 5 urogynecologists. Red outline = position left unfilled.",
       caption = WC) + person_theme()
ggsave(file.path(OUT,"urps_exec_team.png"), pA, width = 10, height = 5.6, dpi = 300, bg = "white")

# ============================ B: replacement gauge ============================
maxp <- 130; ang <- function(p) pi * (1 - pmin(p, maxp)/maxp)
sp <- seq(0, maxp, length.out = 260); r1 <- 0.66; r2 <- 1.0
wedge <- do.call(rbind, lapply(seq_len(length(sp)-1), function(i) {
  a0 <- ang(sp[i]); a1 <- ang(sp[i+1]); mid <- (sp[i]+sp[i+1])/2
  z <- if (mid < 90) "below" else if (mid < 100) "warn" else "ok"
  data.frame(x = c(r1*cos(a0), r2*cos(a0), r2*cos(a1), r1*cos(a1)),
             y = c(r1*sin(a0), r2*sin(a0), r2*sin(a1), r1*sin(a1)), grp = i, zone = z)
}))
val <- 100*wr; av <- ang(val)
tick <- data.frame(p = c(90, 100), lab = c("90%", "Replacement\n100%"))
tick$x <- (r2+0.10)*cos(ang(tick$p)); tick$y <- (r2+0.10)*sin(ang(tick$p))
pB <- ggplot() +
  geom_polygon(data = wedge, aes(x, y, group = grp, fill = zone)) +
  scale_fill_manual(values = c(below = RED, warn = YEL, ok = GREEN)) +
  annotate("segment", x = 0, y = 0, xend = 0.9*cos(av), yend = 0.9*sin(av), colour = NAVY, linewidth = 2.4) +
  annotate("point", x = 0, y = 0, size = 5, colour = NAVY) +
  geom_text(data = tick, aes(x, y, label = lab), size = 10, size.unit = "pt", colour = "grey35", lineheight = .9) +
  annotate("text", x = 0, y = -0.22, label = sprintf("%d%%", round(val)), fontface = "bold", size = 46, size.unit = "pt", colour = RED) +
  annotate("text", x = 0, y = -0.52, label = "Below replacement", fontface = "bold", size = 20, size.unit = "pt", colour = NAVY) +
  coord_equal(clip = "off", xlim = c(-1.25, 1.25), ylim = c(-0.65, 1.2)) +
  labs(title = "Worst-case urogynecology replacement rate",
       caption = WC) +
  theme_void(base_size = 15) +
  theme(plot.title = element_text(face = "bold", size = rel(1.25), colour = NAVY, hjust = .5, margin = margin(b = 6)),
        plot.caption = element_text(hjust = .5, colour = "grey45", size = rel(0.75), margin = margin(t = 6)),
        legend.position = "none", plot.margin = margin(18, 20, 14, 20))
ggsave(file.path(OUT,"urps_exec_gauge.png"), pB, width = 8, height = 6.2, dpi = 300, bg = "white")

# ============================ C: leaking-pipeline funnel ============================
enter <- round(ent * 0.7)
stg <- data.frame(
  i = 1:4, hw = c(1.00, 0.85, 0.70, 0.56), yb = c(3, 2, 1, 0),
  fill = c(NAVY, "#3a5a8c", "#b5657a", RED),
  lab = c(sprintf("%d fellowship graduates per year", ent),
          sprintf("x 70%% enter practice  (~%d)", enter),
          "vs departures tripled",
          sprintf("Ratio %.2f: below 1.0", wr)))
poly <- do.call(rbind, lapply(1:4, function(k) data.frame(
  x = c(-stg$hw[k], stg$hw[k], stg$hw[k]*0.82, -stg$hw[k]*0.82),
  y = c(stg$yb[k]+0.9, stg$yb[k]+0.9, stg$yb[k]+0.1, stg$yb[k]+0.1), grp = k, fill = stg$fill[k])))
pC <- ggplot() +
  geom_polygon(data = poly, aes(x, y, group = grp, fill = I(fill))) +
  geom_text(data = stg, aes(0, yb+0.5, label = lab), colour = "white", fontface = "bold", size = 11, size.unit = "pt") +
  coord_cartesian(clip = "off", xlim = c(-1.15, 1.15)) +
  labs(title = "Even the training pipeline may not keep pace under adverse conditions",
       subtitle = "How the worst-case 0.86 replacement ratio arises",
       caption = WC) +
  theme_void(base_size = 15) +
  theme(plot.title = element_text(face = "bold", size = rel(1.15), colour = RED, hjust = .5, margin = margin(b = 3)),
        plot.subtitle = element_text(hjust = .5, colour = "grey30", margin = margin(b = 10)),
        plot.caption = element_text(hjust = .5, colour = "grey45", size = rel(0.72), margin = margin(t = 12)),
        plot.margin = margin(20, 22, 16, 22))
ggsave(file.path(OUT,"urps_exec_funnel.png"), pC, width = 9, height = 6.0, dpi = 300, bg = "white")

# ============================ D: executive risk card ============================
pD <- ggplot() +
  annotate("rect", xmin = 0, xmax = 10, ymin = 8.4, ymax = 10, fill = RED) +
  annotate("text", x = 0.4, y = 9.2, hjust = 0, label = "WORKFORCE RISK: HIGH", colour = "white", fontface = "bold", size = 22, size.unit = "pt") +
  annotate("rect", xmin = 0, xmax = 10, ymin = 0, ymax = 8.4, fill = NA, colour = "grey80", linewidth = 1) +
  annotate("text", x = 0.5, y = 7.2, hjust = 0, label = sprintf("%d%% replacement", rep86), fontface = "bold", size = 30, size.unit = "pt", colour = NAVY) +
  annotate("text", x = 0.5, y = 6.2, hjust = 0, label = sprintf("%d%% shortfall", unf), fontface = "bold", size = 24, size.unit = "pt", colour = RED) +
  annotate("text", x = 0.5, y = 5.0, hjust = 0, label = "Only under combined worst-case conditions:", size = 14, size.unit = "pt", colour = "grey30") +
  annotate("text", x = 0.8, y = 4.2, hjust = 0, label = "-  Departures tripled from the empirical rate", size = 13, size.unit = "pt", colour = "grey25") +
  annotate("text", x = 0.8, y = 3.5, hjust = 0, label = "-  Only 70% of graduates enter practice", size = 13, size.unit = "pt", colour = "grey25") +
  annotate("text", x = 0.8, y = 2.8, hjust = 0, label = "-  Provisional 2016-2023 departure estimates", size = 13, size.unit = "pt", colour = "grey25") +
  annotate("text", x = 0.5, y = 1.5, hjust = 0, label = "Under these conditions the urogynecology pipeline falls below replacement.", fontface = "italic", size = 13, size.unit = "pt", colour = NAVY) +
  annotate("text", x = 0.5, y = 0.6, hjust = 0, label = "Primary projection: 5.6 completions per departure (far above replacement).", size = 11, size.unit = "pt", colour = "grey50") +
  coord_cartesian(xlim = c(0, 10), ylim = c(0, 10), clip = "off") +
  theme_void() + theme(plot.margin = margin(16, 18, 16, 18))
ggsave(file.path(OUT,"urps_exec_riskcard.png"), pD, width = 8.6, height = 6.4, dpi = 300, bg = "white")

cat("wrote urps_exec_team.png, urps_exec_gauge.png, urps_exec_funnel.png, urps_exec_riskcard.png\n")
