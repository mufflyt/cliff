# Canonical AUGS supply-demand figure palette — single source of truth.
#
# The two AUGS supply-demand figure scripts (augs_application/scripts/make_supply_demand_figure.R
# and cms_supply_demand_10styles.R) share an identical 4-colour SEMANTIC palette:
#   supply = teal, demand (status quo, women 65+) = orange, demand (PFD prevalence) = red,
#   neutral/annotation = grey. It was copy-pasted verbatim in each.
#
# ONLY these four shared colours are canonicalised. File-specific colours stay local and are
# NOT unified (intentional per-figure choices): GREEN in 10styles, INK in make_supply_demand,
# the CMS_* federal-brand ramp, and all per-panel / dark-theme inline hex.
#
# NOTE: the hex #d1495b (RED here) also appears independently as .wf_URPS / primary_fill in the
# workforce-figure and taxonomy scripts — separate figure families with their own named
# constants, intentionally NOT unified here.
#
# NOTE: shiny_urps_adequacy/app.R:22 keeps its OWN inline copy of these four colours ON PURPOSE —
# a deployed Shiny app must be self-contained (it cannot source repo-root R/ modules), and that
# inline copy is pinned by shiny_urps_adequacy/tests/testthat/test-guards-app.R. That copy is a
# deliberate self-containment requirement, NOT drift, and is intentionally NOT collapsed into this SSOT.
#
# Pure constants, no path/data dependencies — safe to source from any cwd.

#   Meaning : semantic colours for the AUGS supply/demand line + area figures.
#   Units   : hex RGB strings "#RRGGBB".
#   Source  : AUGS-application figure design (Supply/Demand/PFD/neutral encoding).
#   Consumers: augs_application/scripts/{make_supply_demand_figure,cms_supply_demand_10styles}.R
AUGS_SD_PALETTE <- c(
  supply           = "#1b7f79",   # teal
  demand_statusquo = "#c77d1a",   # orange
  demand_pfd       = "#d1495b",   # red
  neutral          = "#8a97a8"    # grey
)
stopifnot(
  length(AUGS_SD_PALETTE) == 4L,
  !anyNA(AUGS_SD_PALETTE),
  !is.null(names(AUGS_SD_PALETTE)),
  all(nzchar(names(AUGS_SD_PALETTE))),
  anyDuplicated(names(AUGS_SD_PALETTE)) == 0L,
  all(grepl("^#[0-9A-Fa-f]{6}$", AUGS_SD_PALETTE))
)

# Bare-name constants the figure scripts consume (kept identical to the prior literals so the
# call sites — e.g. c("Supply"=TEAL, ...) — are unchanged and behaviour is byte-for-byte preserved).
TEAL   <- unname(AUGS_SD_PALETTE[["supply"]])
ORANGE <- unname(AUGS_SD_PALETTE[["demand_statusquo"]])
RED    <- unname(AUGS_SD_PALETTE[["demand_pfd"]])
GREY   <- unname(AUGS_SD_PALETTE[["neutral"]])
