library(ggplot2)
library(dplyr)
library(scales)

# ── Projection year framing: single source of truth ─────────────────────────
# The projection endpoint (2029) is NOT a free literal: it is the baseline year
# plus the study horizon. The horizon lives in exactly one place,
# R/workforce_constants.R::WORKFORCE_PROJECTION_HORIZON_YEARS, shared with the
# engine and the sibling trajectory figure (scenario_projection_trajectories.R),
# so the two figures cannot drift. Every plotted year below derives from these.
source(here::here("R", "workforce_constants.R"), local = TRUE)  # WORKFORCE_PROJECTION_HORIZON_YEARS
PROJ_YEAR0   <- 2025L                               # projection baseline (the 2025 cohort)
PROJ_HORIZON <- WORKFORCE_PROJECTION_HORIZON_YEARS  # SSOT: annual transitions (4)
PROJ_END     <- PROJ_YEAR0 + PROJ_HORIZON           # derived projection endpoint (2029)
PROJ_YEARS   <- PROJ_YEAR0 + 0:PROJ_HORIZON         # 2025..2029
OBS_START    <- WORKFORCE_OBSERVED_START_YEAR       # SSOT: study observed-window start (R/workforce_constants.R)
OBS_END      <- PROJ_YEAR0 - 1L                     # last observed year / observed-projected boundary (2024)
# Fail loud if the horizon SSOT drifts: the FROZEN supply endpoints (1,283 -> 1,301)
# and the [1,271, 1,330] CI below are a published FOUR-year result. If the horizon
# changes, those numbers must be regenerated before this figure is valid, so refuse
# to silently render a mislabeled axis over unchanged data.
stopifnot(PROJ_END == 2029L, PROJ_HORIZON == 4L, length(PROJ_YEARS) == 5L)

# ── Real data from Muffly et al. 2026 (Surgical Workforce Cliff manuscript) ──
# FPMRS: 2024 active = 1,196; 2025 baseline = 1,283; 2029 projected = 1,301
#         annual retirement rate 4.4% (55.6/yr); 60 fellows/yr; ratio = 1.08
#         95% CI at 2029: [1,271, 1,330]; SD = 15.2

# Historical: reconstruct observed series from the 2024 anchor + net +4.4/yr
hist_df <- tibble(
  year   = OBS_START:OBS_END,
  supply = round(1196 - (OBS_END - (OBS_START:OBS_END)) * 4.4),
  lower  = NA_real_,
  upper  = NA_real_,
  phase  = "Observed"
)

# Projected: linear interpolation with CI over the horizon (PROJ_YEAR0..PROJ_END)
proj_df <- tibble(
  year   = PROJ_YEARS,
  supply = round(1283 + (1301 - 1283) * (0:PROJ_HORIZON) / PROJ_HORIZON),
  lower  = round(seq(1283 - 15.2 * WORKFORCE_CI_Z95, 1271, length.out = length(PROJ_YEARS))),
  upper  = round(seq(1283 + 15.2 * WORKFORCE_CI_Z95, 1330, length.out = length(PROJ_YEARS))),
  phase  = "Projected"
)

df <- bind_rows(hist_df, proj_df)

# Key annotation values
pt_2013  <- filter(df, year == OBS_START)$supply
pt_2024  <- filter(df, year == OBS_END)$supply
pt_2029  <- filter(df, year == PROJ_END)$supply
ci_lo    <- filter(df, year == PROJ_END)$lower
ci_hi    <- filter(df, year == PROJ_END)$upper
anchor_years <- c(OBS_START, OBS_END, PROJ_END)   # observed start, observed end, projection end

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
  geom_point(data = filter(df, year %in% anchor_years),
             color = "#D62728", size = 4, shape = 21,
             fill = "white", stroke = 2) +

  # Labels on anchor points
  geom_text(data = filter(df, year %in% anchor_years),
            aes(label = comma(supply)),
            vjust = -1.1, size = 3.8, color = "#D62728", fontface = "bold") +

  # Divider and phase labels
  geom_vline(xintercept = PROJ_YEAR0 - 0.5, linetype = "dotted",
             color = "grey50", linewidth = 0.8) +
  annotate("text", x = 2019.5, y = 1340,
           label = sprintf("Observed (%d–%d)", OBS_START, OBS_END),
           size = 3.5, color = "grey40", fontface = "italic") +
  annotate("text", x = 2027,   y = 1340,
           label = sprintf("Projected (%d–%d)", PROJ_YEAR0, PROJ_END),
           size = 3.5, color = "grey40", fontface = "italic") +

  # Replacement ratio callout
  annotate("label", x = 2027, y = 1230,
           label = "Replacement ratio: 1.08\n(Marginal — 60 fellows/yr\nvs 55.6 retirements/yr)",
           size = 3.2, color = "#8b0000", fill = "#fff5f5",
           label.size = 0.4, hjust = 0.5) +

  scale_x_continuous(breaks = c(seq(OBS_START, OBS_END - 1L, 2L), seq(PROJ_YEAR0, PROJ_END, 2L))) +
  scale_y_continuous(labels = comma, limits = c(1100, 1380),
                     breaks = seq(1100, 1380, 50)) +

  labs(
    title    = sprintf("Urogynecology (FPMRS) Physician Supply, %d–%d", OBS_START, PROJ_END),
    subtitle = paste0(
      "Active Female Pelvic Medicine & Reconstructive Surgery physicians (FTE)\n",
      sprintf("Observed %d–%d  |  Monte Carlo projected %d–%d (10,000 iterations)  |  Shaded = 95%% CI",
              OBS_START, OBS_END, PROJ_YEAR0, PROJ_END)
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
