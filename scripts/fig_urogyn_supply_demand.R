library(ggplot2)
library(dplyr)
library(scales)
library(patchwork)

# ── National statistics (published sources) ─────────────────────────────────
# Supply: ABOG 2024 workforce report ~1,700 certified FPMRS physicians
# Demand: NIH/NIDDK — ~28 million US women with pelvic floor disorders
# Annual new graduates: ~150 FPMRS fellows/year (ACGME 2023)
# Wait time: median 3–6 months in underserved areas
# Rural access: ~72% of US counties lack a single FPMRS physician

supply <- 1700
demand <- 28e6
ratio  <- round(demand / supply)

# ── Plot 1: Supply vs Demand gap bar ────────────────────────────────────────
gap_data <- tibble(
  category = factor(c("Certified FPMRS\nPhysicians", "Women with\nPelvic Floor Disorders"),
                    levels = c("Certified FPMRS\nPhysicians", "Women with\nPelvic Floor Disorders")),
  value = c(supply, demand),
  fill  = c("#2c7bb6", "#d7191c")
)

p1 <- ggplot(gap_data, aes(x = category, y = value, fill = fill)) +
  geom_col(width = 0.55, show.legend = FALSE) +
  geom_text(aes(label = ifelse(value > 1e6,
                               paste0(round(value / 1e6, 0), "M"),
                               comma(value))),
            vjust = -0.5, size = 5.5, fontface = "bold", color = "black") +
  scale_y_continuous(labels = label_comma(), expand = expansion(mult = c(0, 0.15))) +
  scale_fill_identity() +
  labs(x = NULL, y = "Count") +
  theme_minimal(base_size = 13) +
  theme(axis.text.x = element_text(face = "bold", size = 12),
        axis.title.y = element_text(size = 11),
        panel.grid.major.x = element_blank(),
        plot.margin = margin(10, 10, 10, 10))

# ── Plot 2: Key metrics tile ─────────────────────────────────────────────────
metrics <- tibble(
  label = c(
    paste0("1 : ", comma(ratio)),
    "~150 / year",
    "3 – 6 months",
    "72%"
  ),
  sublabel = c(
    "Physician-to-patient ratio",
    "New FPMRS graduates",
    "Median wait time (rural)",
    "US counties with\nno FPMRS physician"
  ),
  x = c(1, 2, 1, 2),
  y = c(2, 2, 1, 1),
  fill = c("#d7191c", "#fdae61", "#abd9e9", "#2c7bb6")
)

p2 <- ggplot(metrics, aes(x = x, y = y)) +
  geom_tile(aes(fill = fill), width = 0.88, height = 0.82, color = "white", linewidth = 2) +
  geom_text(aes(label = label), fontface = "bold", size = 5.2, color = "white", vjust = 0.2) +
  geom_text(aes(label = sublabel, y = y - 0.22), size = 3.4, color = "white", lineheight = 0.95) +
  scale_fill_identity() +
  scale_x_continuous(limits = c(0.5, 2.5)) +
  scale_y_continuous(limits = c(0.5, 2.5)) +
  labs(x = NULL, y = NULL) +
  theme_void()

# ── Combine ──────────────────────────────────────────────────────────────────
combined <- p1 + p2 +
  plot_annotation(
    title    = "Urogynecology (FPMRS) Workforce: Supply vs. Demand",
    subtitle = "United States, 2024  |  Sources: ABOG, NIH/NIDDK, ACGME",
    caption  = "FPMRS = Female Pelvic Medicine & Reconstructive Surgery",
    theme = theme(
      plot.title    = element_text(face = "bold", size = 16, hjust = 0.5),
      plot.subtitle = element_text(size = 11, hjust = 0.5, color = "grey40"),
      plot.caption  = element_text(size = 9, color = "grey50", hjust = 1)
    )
  )

out_path <- here::here("artifacts", "fig_urogyn_supply_demand.png")
ggsave(out_path, combined, width = 10, height = 5, dpi = 180, bg = "white")
message("Saved: ", out_path)
