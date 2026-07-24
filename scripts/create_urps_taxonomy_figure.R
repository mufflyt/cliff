#!/usr/bin/env Rscript

# =============================================================================
# URPS / FPMRS NPPES taxonomy reliability figure
# =============================================================================
#
# Purpose:
#   Visualize how poorly NPPES taxonomy codes identify ABOG-certified
#   urogynecology / FPMRS physicians, using counts supplied in the CMS draft
#   support email.
#
# Output:
#   manuscript/figures/appendix_urps_nppes_taxonomy_reliability.png
#   manuscript/figures/appendix_urps_nppes_taxonomy_reliability.tiff
# =============================================================================

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tibble)
  library(patchwork)
  library(scales)
  library(here)
  library(grid)
})

output_dir <- here::here("manuscript", "figures")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

output_png <- here::here(
  "manuscript", "figures", "appendix_urps_nppes_taxonomy_reliability.png"
)
output_tiff <- here::here(
  "manuscript", "figures", "appendix_urps_nppes_taxonomy_reliability.tiff"
)

total_abog_npi <- 1172L
found_in_nppes <- 1152L
correct_any <- 600L
correct_primary <- 207L
missing_fpmrs_taxonomy <- 552L
not_found_in_nppes <- total_abog_npi - found_in_nppes

funnel_df <- tibble::tribble(
  ~step, ~n, ~fill, ~text_color, ~label,
  "ABOG-certified FPMRS\nwith NPI", total_abog_npi, "#123B5D", "white",
  "ABOG-certified FPMRS\nwith NPI\n1,172 physicians (100.0%)",
  "Found in NPPES", found_in_nppes, "#2A6F97", "white",
  "Found in NPPES\n1,152 physicians (98.3%)",
  "Correct 207VF0040X\nin any slot (1-5)", correct_any, "#F4B942", "#1E1E1E",
  "Correct 207VF0040X\nin any slot (1-5)\n600 physicians (51.2%)",
  "Correct 207VF0040X\nas primary taxonomy", correct_primary, "#D1495B", "white",
  "Primary taxonomy\n207 physicians\n(17.7%)"
) %>%
  dplyr::mutate(
    pct_total = 100 * n / total_abog_npi,
    xmin = -n / 2,
    xmax = n / 2,
    ymin = dplyr::row_number() - 0.42,
    ymax = dplyr::row_number() + 0.42
  )

slot_df <- tibble::tribble(
  ~slot, ~n,
  "Slot 2 (secondary)", 297L,
  "Slot 1 (primary)", 207L,
  "Slot 3", 75L,
  "Slots 4-5", 21L
) %>%
  dplyr::mutate(
    pct = 100 * n / correct_any,
    slot = factor(slot, levels = rev(slot))
  )

wrong_taxonomy_df <- tibble::tribble(
  ~taxonomy_label, ~n, ~pct,
  "OB/GYN (general)\n207V00000X", 316L, 57.2,
  "Gynecology\n207VG0400X", 75L, 13.6,
  "Student / Trainee\n390200000X", 69L, 12.5,
  "Other non-OB/GYN\nmisc. codes", 43L, 7.8,
  "Specialist (generic)\n174400000X", 22L, 4.0,
  "Urology - Female Pelvic Med\n2088F0040X", 13L, 2.4,
  "Urology\n208800000X", 7L, 1.3,
  "Gynecologic Oncology\n207VX0201X", 4L, 0.7,
  "Obstetrics\n207VX0000X", 3L, 0.5
) %>%
  dplyr::mutate(
    taxonomy_label = factor(taxonomy_label, levels = rev(taxonomy_label))
  )

base_theme <- ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(
    panel.grid.major.y = ggplot2::element_blank(),
    panel.grid.minor = ggplot2::element_blank(),
    plot.background = ggplot2::element_rect(fill = "white", color = NA),
    panel.background = ggplot2::element_rect(fill = "white", color = NA),
    plot.title = ggplot2::element_text(face = "bold", size = 15, color = "#14213D"),
    plot.subtitle = ggplot2::element_text(size = 10.5, color = "#4A5568"),
    axis.title = ggplot2::element_text(face = "bold", color = "#14213D"),
    axis.text = ggplot2::element_text(color = "#243B53"),
    legend.position = "none",
    plot.margin = grid::unit(c(8, 12, 8, 12), "pt")
  )

panel_a <- ggplot2::ggplot(funnel_df) +
  ggplot2::geom_rect(
    ggplot2::aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax, fill = fill),
    color = NA
  ) +
  ggplot2::geom_text(
    ggplot2::aes(x = 0, y = (ymin + ymax) / 2, label = label, color = text_color),
    lineheight = 0.95,
    fontface = "bold",
    size = 4.0
  ) +
  ggplot2::annotate(
    "label",
    x = 570,
    y = 3.58,
    label = sprintf(
      "Primary taxonomy alone misses %s of %s\nFPMRS physicians already in NPPES (82.0%%)",
      scales::comma(found_in_nppes - correct_primary),
      scales::comma(found_in_nppes)
    ),
    hjust = 0,
    vjust = 1,
    fill = "#FDEDEC",
    color = "#8A1C2C",
    size = 3.4,
    fontface = "bold",
    linewidth = 0
  ) +
  ggplot2::annotate(
    "label",
    x = 570,
    y = 2.25,
    label = sprintf(
      "Even searching slots 1-5 finds only %s of %s\nboard-certified physicians (52.1%%)",
      scales::comma(correct_any),
      scales::comma(found_in_nppes)
    ),
    hjust = 0,
    vjust = 1,
    fill = "#FFF4CC",
    color = "#7A5200",
    size = 3.4,
    linewidth = 0
  ) +
  ggplot2::annotate(
    "label",
    x = 570,
    y = 1.15,
    label = sprintf(
      "%s physicians with NPI were not found\nin the analyzed NPPES file",
      scales::comma(not_found_in_nppes)
    ),
    hjust = 0,
    vjust = 1,
    fill = "#EDF2F7",
    color = "#3A506B",
    size = 3.1,
    linewidth = 0
  ) +
  ggplot2::scale_fill_identity() +
  ggplot2::scale_color_identity() +
  ggplot2::coord_cartesian(xlim = c(-650, 980), ylim = c(0.45, 4.8), clip = "off") +
  base_theme +
  ggplot2::theme(
    axis.text = ggplot2::element_blank(),
    axis.title = ggplot2::element_blank(),
    axis.ticks = ggplot2::element_blank(),
    panel.grid = ggplot2::element_blank()
  ) +
  ggplot2::labs(
    title = "A. NPPES rapidly loses the true FPMRS workforce",
    subtitle = "ABOG board certification is the ground truth; NPPES taxonomy is the screen"
  )

panel_b <- ggplot2::ggplot(slot_df, ggplot2::aes(x = slot, y = n, fill = slot)) +
  ggplot2::geom_col(width = 0.72, color = NA) +
  ggplot2::geom_text(
    ggplot2::aes(label = sprintf("%s\n%.1f%%", scales::comma(n), pct)),
    hjust = -0.1,
    size = 3.5,
    fontface = "bold",
    color = "#1F2933"
  ) +
  ggplot2::scale_fill_manual(values = c(
    "Slots 4-5" = "#B8C1CC",
    "Slot 3" = "#89C2D9",
    "Slot 1 (primary)" = "#F4B942",
    "Slot 2 (secondary)" = "#2A9D8F"
  )) +
  ggplot2::coord_flip(clip = "off") +
  ggplot2::scale_y_continuous(
    limits = c(0, 330),
    expand = ggplot2::expansion(mult = c(0, 0.08))
  ) +
  base_theme +
  ggplot2::theme(
    axis.title.y = ggplot2::element_blank(),
    axis.title.x = ggplot2::element_blank(),
    plot.title = ggplot2::element_text(size = 13),
    plot.subtitle = ggplot2::element_text(size = 10)
  ) +
  ggplot2::labs(
    title = "B. When 207VF0040X appears, it is usually not primary",
    subtitle = "Distribution among the 600 physicians with the correct code in any taxonomy slot"
  )

panel_c <- ggplot2::ggplot(
  wrong_taxonomy_df,
  ggplot2::aes(x = taxonomy_label, y = pct, fill = taxonomy_label)
) +
  ggplot2::geom_col(width = 0.72, color = NA) +
  ggplot2::geom_text(
    ggplot2::aes(label = sprintf("%s (%.1f%%)", scales::comma(n), pct)),
    hjust = -0.08,
    size = 3.2,
    color = "#1F2933"
  ) +
  ggplot2::scale_fill_manual(values = c(
    "Obstetrics\n207VX0000X" = "#DCE3EB",
    "Gynecologic Oncology\n207VX0201X" = "#CBD5E1",
    "Urology\n208800000X" = "#BFD7EA",
    "Urology - Female Pelvic Med\n2088F0040X" = "#98C1D9",
    "Specialist (generic)\n174400000X" = "#C7CEEA",
    "Other non-OB/GYN\nmisc. codes" = "#A3B18A",
    "Student / Trainee\n390200000X" = "#E9C46A",
    "Gynecology\n207VG0400X" = "#5DA9E9",
    "OB/GYN (general)\n207V00000X" = "#D1495B"
  )) +
  ggplot2::coord_flip(clip = "off") +
  ggplot2::scale_y_continuous(
    limits = c(0, 62),
    labels = function(x) paste0(x, "%"),
    expand = ggplot2::expansion(mult = c(0, 0.06))
  ) +
  base_theme +
  ggplot2::theme(
    axis.title.y = ggplot2::element_blank(),
    axis.title.x = ggplot2::element_blank(),
    plot.title = ggplot2::element_text(size = 13),
    plot.subtitle = ggplot2::element_text(size = 10)
  ) +
  ggplot2::labs(
    title = "C. Most missed physicians look like general OB/GYNs in NPPES",
    subtitle = "Primary taxonomy among 552 ABOG-certified FPMRS physicians with no 207VF0040X in slots 1-5"
  )

top_row <- patchwork::wrap_plots(panel_a, ncol = 1, heights = 1)
bottom_row <- patchwork::wrap_plots(panel_b, panel_c, ncol = 2, widths = c(0.85, 1.15))

full_plot <- top_row / bottom_row +
  patchwork::plot_annotation(
    title = "NPPES Taxonomy Underidentifies the Urogynecology Workforce",
    subtitle = paste(
      "Among 1,172 ABOG-certified FPMRS physicians with NPIs, only 207",
      "carry 207VF0040X as their primary taxonomy and only 600 are detectable",
      "even after searching NPPES taxonomy slots 1-5."
    ),
    caption = paste(
      "Source: counts supplied in Tyler Muffly summary comparing ABOG board certification",
      "with NPPES taxonomy slots 1-5. Correct taxonomy = 207VF0040X.",
      "Figure generated by scripts/create_urps_taxonomy_figure.R."
    ),
    theme = ggplot2::theme(
      plot.title = ggplot2::element_text(
        face = "bold", size = 20, color = "#081C15", hjust = 0
      ),
      plot.subtitle = ggplot2::element_text(
        size = 11.5, color = "#334E68", hjust = 0, margin = ggplot2::margin(b = 10)
      ),
      plot.caption = ggplot2::element_text(
        size = 8.5, color = "#52606D", hjust = 0, margin = ggplot2::margin(t = 12)
      ),
      plot.margin = ggplot2::margin(12, 14, 12, 14)
    )
  )

ggplot2::ggsave(
  filename = output_png,
  plot = full_plot,
  width = 14,
  height = 10,
  dpi = 300,
  units = "in",
  bg = "white"
)

png_size <- file.size(output_png)
if (!file.exists(output_png)) {
  stop("PNG output not written: ", output_png, call. = FALSE)
}
if (is.na(png_size) || png_size == 0L) {
  stop("PNG output is empty or unreadable: ", output_png, call. = FALSE)
}

ggplot2::ggsave(
  filename = output_tiff,
  plot = full_plot,
  width = 14,
  height = 10,
  dpi = 300,
  units = "in",
  device = "tiff",
  compression = "lzw",
  bg = "white"
)

tiff_size <- file.size(output_tiff)
if (!file.exists(output_tiff)) {
  stop("TIFF output not written: ", output_tiff, call. = FALSE)
}
if (is.na(tiff_size) || tiff_size == 0L) {
  stop("TIFF output is empty or unreadable: ", output_tiff, call. = FALSE)
}

cat(sprintf("Saved PNG : %s (%.1f KB)\n", output_png, png_size / 1024))
cat(sprintf("Saved TIFF: %s (%.1f MB)\n", output_tiff, tiff_size / (1024^2)))
