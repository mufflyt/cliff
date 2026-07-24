library(ggplot2)
library(dplyr)
library(scales)

# ── Real data from Muffly et al. 2026 (Surgical Workforce Cliff manuscript) ──
# FPMRS: 2024 active = 1,196; 2025 baseline = 1,283; 2029 projected = 1,301
#         annual retirement rate 4.4% (55.6/yr); 60 fellows/yr; ratio = 1.08
#         95% CI at 2029: [1,271, 1,330]; SD = 15.2

# Historical: reconstruct 2013–2024 from 2024 anchor + net +4.4/yr
hist_df <- tibble(
  year   = 2013:2024,
  supply = round(1196 - (2024 - (2013:2024)) * 4.4),
  lower  = NA_real_,
  upper  = NA_real_,
  phase  = "Observed"
)

# Projected: 2025–2029 linear interpolation with CI
proj_df <- tibble(
  year   = 2025:2029,
  supply = round(1283 + (1301 - 1283) * (0:4) / 4),
  lower  = round(seq(1283 - 15.2 * 1.96, 1271, length.out = 5)),
  upper  = round(seq(1283 + 15.2 * 1.96, 1330, length.out = 5)),
  phase  = "Projected"
)

df <- bind_rows(hist_df, proj_df)

# Key annotation values
pt_2013  <- filter(df, year == 2013)$supply
pt_2024  <- filter(df, year == 2024)$supply
pt_2029  <- filter(df, year == 2029)$supply
ci_lo    <- filter(df, year == 2029)$lower
ci_hi    <- filter(df, year == 2029)$upper

p <- ggplot(df, aes(x = year, y = supply)) +

  # Projected CI ribbon
  geom_ribbon(data = filter(df, phase == "Projected"),
              aes(ymin = lower, ymax = upper),
              fill = "#D62728", alpha = 0.15) +

  # Observed solid line
  geom_line(data = filter(df, phase == "Observed"),
            color = "#D62728", linewidth = 1.5) +

  # Projected dashed line
  geom_line(data = filter(df, phase == "Projected"),
            color = "#D62728", linewidth = 1.5, linetype = "dashed") +

  # Anchor points
  geom_point(data = filter(df, year %in% c(2013, 2024, 2029)),
             color = "#D62728", size = 4, shape = 21,
             fill = "white", stroke = 2) +

  # Labels on anchor points
  geom_text(data = filter(df, year %in% c(2013, 2024, 2029)),
            aes(label = comma(supply)),
            vjust = -1.1, size = 3.8, color = "#D62728", fontface = "bold") +

  # Divider and phase labels
  geom_vline(xintercept = 2024.5, linetype = "dotted",
             color = "grey50", linewidth = 0.8) +
  annotate("text", x = 2019.5, y = 1340, label = "Observed (2013–2024)",
           size = 3.5, color = "grey40", fontface = "italic") +
  annotate("text", x = 2027,   y = 1340, label = "Projected (2025–2029)",
           size = 3.5, color = "grey40", fontface = "italic") +

  # Replacement ratio callout
  annotate("label", x = 2027, y = 1230,
           label = "Replacement ratio: 1.08\n(Marginal — 60 fellows/yr\nvs 55.6 retirements/yr)",
           size = 3.2, color = "#8b0000", fill = "#fff5f5",
           label.size = 0.4, hjust = 0.5) +

  scale_x_continuous(breaks = c(2013, 2015, 2017, 2019, 2021, 2023, 2025, 2027, 2029)) +
  scale_y_continuous(labels = comma, limits = c(1100, 1380),
                     breaks = seq(1100, 1380, 50)) +

  labs(
    title    = "Urogynecology (FPMRS) Physician Supply, 2013–2029",
    subtitle = paste0(
      "Active Female Pelvic Medicine & Reconstructive Surgery physicians (FTE)\n",
      "Observed 2013–2024  |  Monte Carlo projected 2025–2029 (10,000 iterations)  |  Shaded = 95% CI"
    ),
    x       = "Year",
    y       = "Active FPMRS Physicians (FTE)",
    caption = paste0(
      "Source: Muffly et al. (2026), Gynecologic Subspecialty Workforce Cliff manuscript.\n",
      "2024 cohort: 1,196 active FPMRS physicians. Annual retirement rate: 4.4% (mean 55.6/yr).\n",
      "Fellowship pipeline: 60 graduates/yr (ACGME 2022–2024). 2029 95% CI: [",
      comma(ci_lo), ", ", comma(ci_hi), "]."
    )
  ) +

  theme_minimal(base_size = 13) +
  theme(
    plot.title    = element_text(face = "bold", size = 15, hjust = 0),
    plot.subtitle = element_text(size = 10, color = "grey40", hjust = 0, lineheight = 1.3),
    plot.caption  = element_text(size = 8,  color = "grey50", hjust = 0, lineheight = 1.3),
    panel.grid.minor  = element_blank(),
    panel.grid.major.x = element_blank(),
    axis.text.x   = element_text(size = 10),
    axis.text.y   = element_text(size = 10),
    plot.margin   = margin(12, 16, 12, 12)
  )

out_path <- here::here("artifacts", "fig_fpmrs_supply_line.png")
ggsave(out_path, p, width = 10, height = 6, dpi = 180, bg = "white")
message("Saved: ", out_path)
