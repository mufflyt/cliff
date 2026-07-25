# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Urogynecology Workforce Replacement Explorer (URPS, both pathways).
#
# Tests whether the combined ABOG + ABU fellowship pipeline replaces near-term
# physician departures. National HEADCOUNT model; it does not measure geographic
# access, wait times, demand, or clinical FTE (an explicitly exploratory capacity /
# demand extension lets leaders stress those with their own assumptions).
#
# Self-contained: URPS active-age distribution (n = 1,339), age-band departure
# hazards (three observation windows), pooled band event/person-year counts, and
# the graduate series live in urps_model_data.R (generated exactly from
# R/workforce_cliff_engine.R). Projection == wc_project(); the Monte Carlo interval
# propagates PARAMETER uncertainty (Beta posteriors on band hazards + bootstrap of
# the 4 graduate counts), not year-to-year process noise.
#   Run:  Rscript -e 'shiny::runApp("cliff/shiny_urps_scenarios")'
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
suppressPackageStartupMessages({ library(shiny); library(bslib); library(ggplot2) })

source("urps_model_data.R")   # URPS_AGES, BAND_LABELS, BANDS, HAZ_WINDOWS, BAND_EV, BAND_PY, GRAD_URPS

# BANDS (age-band breakpoints) now comes from urps_model_data.R (SSOT; == engine WC_BANDS)
# plain-language display labels for the age bands (BAND_LABELS stays the model key)
BAND_DISPLAY <- c("<45" = "Under 45", "45-49" = "45 to 49", "50-54" = "50 to 54",
                  "55-59" = "55 to 59", "60-64" = "60 to 64", "65-69" = "65 to 69", "70+" = "70 years or older")
BASELINE <- length(URPS_AGES)
COMPLETIONS_DEFAULT <- 64L
GRAD_MEAN <- mean(GRAD_URPS)
MORTALITY_ALL_MISSED <- 7.8
MC_SEED <- 20260718L                       # matches manuscript_WORKFORCE_CLIFF.Rmd bootstrap seed

# ---- canonical published figures (ONE source of truth) ---------------------
# Read the manuscript's own transition CSVs (data/) so the app's ramp curve
# and the exact numbers shown at the default scenario come from the SAME files the
# paper renders from. A frozen fallback (from manuscript_WORKFORCE_CLIFF.docx dated
# 2026-07-21) keeps the app self-contained if the CSVs are not shipped alongside it.
# CANON$* are what a reader sees at the default; the live model reproduces them (and
# validate_model() fails the launch if it ever stops reproducing them).
.load_canon <- function() {
  imm <- rmp <- defer <- NA_real_; curve <- NULL
  # Prefer the copy bundled INSIDE the app (data/), which is what ships to shinyapps.io;
  # fall back to the repo's data/ for local development. Either resolves to the same
  # source-of-truth CSVs; a frozen fallback below keeps the app self-contained if neither ships.
  find_csv <- function(name) {
    for (p in c(file.path("data", name), file.path("..", "data", name))) if (file.exists(p)) return(p)
    file.path("data", name)   # nonexistent local path -> triggers the frozen fallback
  }
  proj_f  <- find_csv("graduation_active_transition_projection.csv")
  curve_f <- find_csv("graduation_active_transition.csv")
  if (file.exists(proj_f)) {
    p <- utils::read.csv(proj_f, stringsAsFactors = FALSE)
    u <- p[toupper(p$subspecialty_abbrev) == "URPS", , drop = FALSE]
    if (nrow(u) == 1) { imm <- u$projected_2029_immediate; rmp <- u$projected_2029_ramped; defer <- u$pct_of_growth_deferred }
  }
  if (file.exists(curve_f)) {
    c0 <- utils::read.csv(curve_f, stringsAsFactors = FALSE)
    u <- c0[toupper(c0$subspecialty_abbrev) == "URPS", , drop = FALSE]
    u <- u[order(u$k), , drop = FALSE]; if (nrow(u) >= 4) curve <- u$cum_active_fraction
  }
  if (is.na(imm))     imm   <- 1544
  if (is.na(rmp))     rmp   <- 1466
  if (is.na(defer))   defer <- 38
  if (is.null(curve)) curve <- c(0.329, 0.595, 0.881, 0.956, 0.972, 0.984)
  list(baseline = 1339L, completions = 64L, ratio = 5.02, proj_immediate = round(imm),
       proj_ramped = round(rmp), deferred_pct = round(defer), ramp_cum = curve,
       source = if (file.exists(proj_f)) "graduation_active_transition CSVs" else "frozen docx 2026-07-21")
}
CANON <- .load_canon()
RAMP_CUM_URPS <- CANON$ramp_cum   # cumulative active-fraction curve, k = 0..5
NAVY <- "#20355e"; TEAL <- "#2a9d8f"; RED <- "#d1495b"; AMBER <- "#d98b0b"; GOLD <- "#b0813b"
SLATE <- "#5f6673"; USERC <- "#5a4fcf"
PLAUS <- list(comp = c(55, 74), conv = c(70, 100), mult = c(0.75, 1.5), entry = c(33, 35))

APP_GIT_COMMIT <- tryCatch(paste(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE), collapse = ""), error = function(e) "unknown")
ENGINE_COMMIT  <- tryCatch(paste(system2("git", c("log", "-1", "--format=%h", "--", "R/workforce_cliff_engine.R"), stdout = TRUE, stderr = FALSE), collapse = ""), error = function(e) "unknown")
TREE_DIRTY <- tryCatch(length(system2("git", c("status", "--porcelain", "R/workforce_cliff_engine.R", "cliff/shiny_urps_scenarios/urps_model_data.R"), stdout = TRUE, stderr = FALSE)) > 0, error = function(e) NA)
MODELDATA_SHA <- tryCatch(sub("\\s.*", "", system2("shasum", c("-a", "256", "urps_model_data.R"), stdout = TRUE, stderr = FALSE)[1]), error = function(e) "unknown")

# ---- model -----------------------------------------------------------------
band_of <- function(age) as.character(cut(age, breaks = BANDS, labels = BAND_LABELS, right = FALSE))
haz_for <- function(age, hz) { h <- hz[band_of(age)]; h[is.na(h)] <- max(hz, na.rm = TRUE); pmin(1, h) }

#' Band hazards for a window, with an optional treatment of the sparse 70+ band.
#' hz70: "obs" (primary; as observed), "carry" (assign 65-69 hazard), "pool" (65+ combined).
adjusted_haz <- function(win_key, mult = 1, hz70 = "obs") {
  ev <- BAND_EV[[win_key]]; py <- BAND_PY[[win_key]]
  hz <- ifelse(py > 0, ev / py, NA_real_); names(hz) <- BAND_LABELS
  if (hz70 == "carry") hz["70+"] <- hz["65-69"]
  if (hz70 == "pool") { pooled <- (ev[6] + ev[7]) / max(py[6] + py[7], 1); hz["65-69"] <- pooled; hz["70+"] <- pooled }
  hz[is.na(hz)] <- max(hz, na.rm = TRUE)
  hz <- pmin(1, hz * mult)
  names(hz) <- BAND_LABELS   # pmin() strips names; restore so haz_for()'s by-name lookup works
  hz
}

#' @param ramp Optional cumulative active-fraction curve (see RAMP_CUM_URPS). When
#'   supplied, year h admits `entrants * ramp[h]` new graduates instead of the full
#'   cohort, deferring the rest as early-career physicians build practice. NULL
#'   reproduces the immediate-entry projection.
project_traj <- function(ages, entrants, hz, horizon, entry_age = 34L, extra_deaths = 0, ramp = NULL) {
  count <- table(ages); av <- as.integer(names(count)); count <- as.numeric(count)
  traj <- numeric(horizon + 1); traj[1] <- sum(count); dep_yr <- numeric(horizon)
  for (h in seq_len(horizon)) {
    hzz <- haz_for(av, hz); dep_yr[h] <- sum(count * hzz) + extra_deaths
    ent_h <- if (is.null(ramp)) entrants else entrants * ramp[min(h, length(ramp))]
    sv <- count * (1 - hzz); av2 <- av + 1L; ix <- match(entry_age, av2)
    if (is.na(ix)) { av2 <- c(av2, entry_age); sv <- c(sv, ent_h) } else sv[ix] <- sv[ix] + ent_h
    av <- av2; count <- sv; count <- count * (1 - extra_deaths / max(sum(count), 1)); traj[h + 1] <- sum(count)
  }
  list(traj = traj, dep_yr = dep_yr, avg_dep = mean(dep_yr))
}

headcount_at <- function(comp, conv, mult, win, mort, entry, horizon, hz70 = "obs")
  tail(project_traj(URPS_AGES, comp * conv / 100, adjusted_haz(win, mult, hz70), horizon, entry, MORTALITY_ALL_MISSED * mort / 100)$traj, 1)

breakeven_mult <- function(win_key, entrants, horizon, entry_age, extra_deaths, hz70) {
  f <- function(mult) { r <- project_traj(URPS_AGES, entrants, adjusted_haz(win_key, mult, hz70), horizon, entry_age, extra_deaths); entrants / r$avg_dep - 1 }
  if (f(0.1) < 0 || f(40) > 0) return(NA_real_)
  tryCatch(stats::uniroot(f, c(0.1, 40))$root, error = function(e) NA_real_)
}

# ---- Monte Carlo (parameter uncertainty) -----------------------------------
mc_replicate <- function(win_key, comp_scale, mult, horizon, entry_age, extra_deaths, hz70) {
  ev <- BAND_EV[[win_key]]; py <- BAND_PY[[win_key]]
  hz <- stats::rbeta(length(ev), ev + 0.5, pmax(py - ev, 0) + 0.5); hz[py == 0] <- max(hz[py > 0], na.rm = TRUE)
  names(hz) <- BAND_LABELS
  if (hz70 == "carry") hz["70+"] <- hz["65-69"]
  if (hz70 == "pool") { pooled <- stats::rbeta(1, ev[6] + ev[7] + 0.5, pmax(py[6] + py[7] - ev[6] - ev[7], 0) + 0.5); hz["65-69"] <- pooled; hz["70+"] <- pooled }
  hz <- setNames(pmin(1, hz * mult), BAND_LABELS)
  entrants <- mean(sample(GRAD_URPS, length(GRAD_URPS), replace = TRUE)) * comp_scale
  r <- project_traj(URPS_AGES, entrants, hz, horizon, entry_age, extra_deaths)
  c(final = tail(r$traj, 1), ratio = entrants / r$avg_dep)
}
run_mc <- function(win_key, comp_scale, mult, horizon, entry_age, extra_deaths, draws, hz70) {
  set.seed(MC_SEED)
  m <- vapply(seq_len(draws), function(i) mc_replicate(win_key, comp_scale, mult, horizon, entry_age, extra_deaths, hz70), numeric(2))
  final <- m["final", ]; ratio <- m["ratio", ]
  list(final = final, ratio = ratio, draws = draws,
       final_lo = unname(quantile(final, 0.025)), final_hi = unname(quantile(final, 0.975)),
       ratio_lo = unname(quantile(ratio, 0.025)), ratio_hi = unname(quantile(ratio, 0.975)),
       n_decline = sum(final < BASELINE))
}

sensitivity_surface <- function(win_key, comp, horizon, entry_age, extra_deaths, hz70,
                                mult_seq = seq(0.5, 3.0, by = 0.25), conv_seq = seq(0.60, 1.00, by = 0.05)) {
  grid <- expand.grid(mult = mult_seq, conv = conv_seq)
  grid$ratio <- mapply(function(mult, conv) {
    r <- project_traj(URPS_AGES, comp * conv, adjusted_haz(win_key, mult, hz70), horizon, entry_age, extra_deaths)
    (comp * conv) / r$avg_dep }, grid$mult, grid$conv)
  grid
}
age_table <- function(win_key, mult, hz70) {
  hz <- adjusted_haz(win_key, mult, hz70)
  cnt <- table(cut(URPS_AGES, BANDS, labels = BAND_LABELS, right = FALSE))
  n <- as.numeric(cnt); h <- pmin(1, hz[names(cnt)]); expdep <- n * h
  data.frame(band = names(cnt), n = n, pct = 100 * n / sum(n), hazard = h, exp_dep = expdep, pct_dep = 100 * expdep / sum(expdep))
}

# Prespecified sensitivity grid computed at the study's DEFAULT settings (completions = 64,
# primary observation window, 2029 horizon, no extra mortality, 70+ as observed). Fixed at
# load so the "robust in N of N" card always reports the PRESPECIFIED grid, not a
# recomputation anchored to whatever custom scenario the user is currently exploring.
SURF_PRESPEC <- sensitivity_surface("fully_obs", 64, 4, 34, 0, "obs")

# ---- model validation gate (app refuses to present results if these fail) --
#' Run the frozen-primary invariants and behavioral monotonicity checks.
#' Returns list(ok, failures). Any failure => the app shows a failure screen.
validate_model <- function() {
  f <- character(0)
  chk <- function(cond, msg) if (!isTRUE(cond)) f <<- c(f, msg)
  hz <- adjusted_haz("fully_obs", 1, "obs")
  bands_used <- unique(band_of(sort(unique(URPS_AGES))))
  chk(length(BASELINE) == 1 && BASELINE == 1339, sprintf("Baseline workforce is %s, expected 1,339.", BASELINE))
  chk(!any(is.na(hz)) && all(BAND_LABELS %in% names(hz)), "Age-band hazard vector has missing names or NA values.")
  chk(sum(is.na(hz[bands_used])) == 0, "Some age bands do not join to a hazard (by-name lookup failed).")
  pr <- project_traj(URPS_AGES, 64, hz, 4)
  chk(abs(pr$avg_dep - 12.75) < 0.6, sprintf("Primary mean departures %.1f, expected ~12.8.", pr$avg_dep))
  chk(abs(64 / pr$avg_dep - 5.02) < 0.3, sprintf("Primary entrants/departures %.2f, expected ~5.0.", 64 / pr$avg_dep))
  chk(abs(tail(pr$traj, 1) - 1544) < 20, sprintf("Primary 2029 workforce %.0f, expected ~1,544.", tail(pr$traj, 1)))
  # behavioral monotonicity
  dep <- function(m) project_traj(URPS_AGES, 64, adjusted_haz("fully_obs", m, "obs"), 4)$avg_dep
  chk(dep(2.0) > dep(1.0), "A 2.0x multiplier did not increase departures.")
  chk(dep(0.7) < dep(1.0), "A 0.7x multiplier did not decrease departures.")
  wf <- function(conv, comp) headcount_at(comp, conv, 1, "fully_obs", 0, 34, 4, "obs")
  chk(wf(100, 64) >= wf(80, 64) - 1e-6, "Higher conversion reduced the workforce.")
  chk(wf(100, 74) >= wf(100, 55) - 1e-6, "Higher completions reduced the workforce.")
  d4 <- project_traj(URPS_AGES, 64, hz, 4)$dep_yr[1]; d8 <- project_traj(URPS_AGES, 64, hz, 8)$dep_yr[1]
  chk(abs(d4 - d8) < 1e-9, "First-year departures depend on the projection horizon.")
  # deterministic vs Monte Carlo median agree
  q <- run_mc("fully_obs", 1, 1, 4, 34, 0, 400, "obs")
  chk(abs(tail(pr$traj, 1) - median(q$final)) < 30, sprintf("Deterministic (%.0f) and MC median (%.0f) disagree.", tail(pr$traj, 1), median(q$final)))
  # consistency with the published manuscript (the numbers a reader clicks through to).
  # If the app ever stops reproducing the paper's headline figures, refuse to launch.
  pr_ramp <- project_traj(URPS_AGES, 64, hz, 4, ramp = RAMP_CUM_URPS)
  chk(BASELINE == CANON$baseline, sprintf("Baseline %s disagrees with manuscript %s.", BASELINE, CANON$baseline))
  chk(abs(tail(pr$traj, 1) - CANON$proj_immediate) < 5, sprintf("Immediate 2029 %.0f disagrees with manuscript %s.", tail(pr$traj, 1), CANON$proj_immediate))
  # the app's dynamic entry-ramp and the manuscript's deferral method agree to within a
  # few percent; check ramp<immediate and a relative tolerance (CANON's is authoritative).
  chk(tail(pr_ramp$traj, 1) < tail(pr$traj, 1) &&
        abs(tail(pr_ramp$traj, 1) - CANON$proj_ramped) < 0.06 * CANON$proj_ramped,
      sprintf("Transition-adjusted 2029 %.0f disagrees with manuscript %s.", tail(pr_ramp$traj, 1), CANON$proj_ramped))
  chk(abs(64 / pr$avg_dep - CANON$ratio) < 0.15, sprintf("Ratio %.2f disagrees with manuscript %.2f.", 64 / pr$avg_dep, CANON$ratio))
  list(ok = length(f) == 0, failures = f)
}
VALIDATION <- validate_model()

# ---- UI helpers ------------------------------------------------------------
badge <- function(text, col) sprintf("<span style='font-size:10px;font-weight:700;color:#fff;background:%s;border-radius:4px;padding:1px 6px;margin-left:6px;vertical-align:middle;'>%s</span>", col, text)
big_stat <- function(label, value, sub = "", col = NAVY) HTML(sprintf(
  "<div style='padding:6px 0;'><div style='font-size:16px;color:#3a4252;line-height:1.35;'>%s</div>
   <div style='font-size:34px;font-weight:800;color:%s;line-height:1.15;margin:2px 0;'>%s</div>
   <div style='font-size:15px;color:#3a4252;line-height:1.4;'>%s</div></div>", label, col, value, sub))
vbtheme <- function(bg) bslib::value_box_theme(bg = bg, fg = "white")
# Self-contained stat card: explicit inline colors so it renders correctly even
# when returned from renderUI (dynamic bslib::value_box loses its CSS deps and
# goes white-on-white). Used for the color-changing executive cards.
stat_box <- function(title, value, sub, bg, vsize = 30) sprintf(
  "<div style='background:%s;color:#fff;border-radius:8px;padding:20px 22px;height:100%%;overflow:visible;'>
     <div style='font-size:14px;opacity:0.92;line-height:1.35;'>%s</div>
     <div style='font-size:%dpx;font-weight:800;line-height:1.2;margin:6px 0;'>%s</div>
     <div style='font-size:14px;opacity:0.92;line-height:1.4;'>%s</div></div>", bg, title, vsize, value, sub)
dyn_label <- function(text, badge_text, badge_col, tip = NULL) {
  s <- paste0("<span style='font-weight:600;'>", text, "</span>", badge(badge_text, badge_col))
  if (!is.null(tip)) s <- paste0("<span title='", tip, "'>", s, " <span style='color:", SLATE, ";cursor:help;'>&#9432;</span></span>")
  HTML(s)
}
# provenance badge for an input value
badge_comp <- function(v) if (v == 64) c("Observed", TEAL) else if (v == 74) c("Benchmark", SLATE) else c("User-defined", USERC)
badge_conv <- function(v) if (v == 100) c("Assumption", GOLD) else c("User-defined", USERC)
badge_mult <- function(v) if (v == 1) c("Assumption", GOLD) else c("User-defined", USERC)
badge_win  <- function(v) switch(v, fully_obs = c("Estimated (primary)", NAVY), drop2 = c("Estimated (short)", SLATE), full = c("Provisional", AMBER))
badge_mort <- function(v) if (v == 0) c("Assumption", GOLD) else c("User-defined", USERC)

PRESETS <- list(
  # beginner-facing, plain-language
  "Best estimate"                   = list(comp = 64, conv = 100, mult = 1.0, win = "fully_obs", mort = 0),
  "Fewer graduates enter practice"  = list(comp = 64, conv = 85,  mult = 1.0, win = "fully_obs", mort = 0),
  "Severe stress test"              = list(comp = 55, conv = 70,  mult = 2.0, win = "full",      mort = 100),
  # technical
  "Lower pipeline"                  = list(comp = 55, conv = 100, mult = 1.0, win = "fully_obs", mort = 0),
  "Higher departure"                = list(comp = 64, conv = 100, mult = 1.5, win = "fully_obs", mort = 0),
  "Short observation window"        = list(comp = 64, conv = 100, mult = 1.0, win = "drop2",     mort = 0),
  "Maximum mortality adjustment"    = list(comp = 64, conv = 100, mult = 1.0, win = "fully_obs", mort = 100),
  "Combined conservative scenario"  = list(comp = 64, conv = 70,  mult = 1.5, win = "full",      mort = 50),
  "NRMP matched-position benchmark" = list(comp = 74, conv = 100, mult = 1.0, win = "fully_obs", mort = 0))
PRIMARY_PRESET <- "Best estimate"
# plain-language meaning shown when a technical scenario is picked
SCENARIO_HELP <- c(
  "Best estimate" = "Uses the study's observed workforce, recent accredited fellowship completions, and empirically estimated departure rates.",
  "Fewer graduates enter practice" = "Tests what happens when some fellowship graduates do not immediately enter active U.S. clinical practice.",
  "Severe stress test" = "Combines fewer entrants with departure rates substantially above the study estimate.",
  "Lower pipeline" = "Fewer fellowship completions or fewer graduates entering practice.",
  "Higher departure" = "Physicians leave at a rate above the empirical estimate.",
  "Short observation window" = "Departure rates estimated from fewer historical years.",
  "Maximum mortality adjustment" = "Adds the largest prespecified estimate of deaths not captured in activity data.",
  "Combined conservative scenario" = "Simultaneously lowers entrants and raises departures.",
  "NRMP matched-position benchmark" = "Uses filled fellowship positions rather than completed fellowships; comparison only.",
  "Custom scenario" = "You changed the assumptions from a preset.")
PRESET_CHOICES <- list(
  "Common scenarios"    = c("Best estimate", "Fewer graduates enter practice", "Severe stress test"),
  "Technical scenarios" = c("Lower pipeline", "Higher departure", "Short observation window",
                            "Maximum mortality adjustment", "Combined conservative scenario", "NRMP matched-position benchmark"),
  "Custom"              = c("Custom scenario"))
WIN_CHOICES <- c("Primary observation window" = "fully_obs", "Shortened observation window sensitivity" = "drop2", "Full window (2016-2023, provisional)" = "full")
HZ70_CHOICES <- c("As observed (primary)" = "obs", "Assign 65-69 hazard (sensitivity)" = "carry", "Pool 65-69 and 70+" = "pool")

# ---- UI --------------------------------------------------------------------
fail_ui <- bslib::page_fluid(
  theme = bslib::bs_theme(version = 5, primary = NAVY),
  bslib::card(style = "max-width:760px;margin:60px auto;border-left:8px solid #d1495b;",
    bslib::card_header(shiny::h3("Model validation failed. Results are unavailable.")),
    bslib::card_body(
      shiny::p("The app refuses to display results because the frozen-primary invariants did not pass. This prevents presenting incorrect numbers."),
      shiny::HTML(paste0("<ul>", paste0("<li>", VALIDATION$failures, "</li>", collapse = ""), "</ul>")),
      shiny::p(style = "color:#777;font-size:12px;", "Fix the model code until validate_model() passes, then reload."))))

main_ui <- bslib::page_sidebar(
  title = "Urogynecology Workforce Replacement Explorer",
  theme = bslib::bs_theme(version = 5, primary = NAVY),
  fillable = FALSE,   # let the whole page scroll as one, not a fixed-height inner tab area
  sidebar = bslib::sidebar(
    width = 340,
    # --- beginner controls: only three things visible by default ---
    shiny::selectInput("preset", "Scenario", choices = PRESET_CHOICES, selected = PRIMARY_PRESET),
    shiny::uiOutput("scenario_help"),
    shiny::uiOutput("scenario_status"),
    shiny::sliderInput("horizon", "Projection period (years ahead)", 1, 8, 4, step = 1),
    shiny::uiOutput("horizon_year"),
    shiny::actionButton("reset", "Reset to best estimate", class = "btn-sm btn-outline-secondary mb-2"),
    # --- customize assumptions (the three levers most people adjust) ---
    bslib::accordion(open = FALSE,
      bslib::accordion_panel("Customize assumptions",
        shiny::div(shiny::uiOutput("lab_comp"), shiny::sliderInput("comp", NULL, 40, 90, COMPLETIONS_DEFAULT, step = 1)),
        shiny::div(shiny::uiOutput("lab_conv"), shiny::sliderInput("conv", NULL, 50, 100, 100, step = 5)),
        shiny::div(shiny::uiOutput("lab_mult"), shiny::sliderInput("mult", NULL, 0.5, 3.0, 1.0, step = 0.1))),
      # --- researcher settings: the technical knobs ---
      bslib::accordion_panel("Researcher settings",
        shiny::div(shiny::uiOutput("lab_win"), shiny::selectInput("win", NULL, choices = WIN_CHOICES, selected = "fully_obs")),
        shiny::selectInput("hz70", "Departure rate for physicians 70 years or older (limited data)", choices = HZ70_CHOICES, selected = "obs"),
        shiny::div(shiny::uiOutput("lab_mort"), shiny::sliderInput("mort", NULL, 0, 100, 0, step = 10)),
        shiny::numericInput("entry", "Entry age (years)", 34, min = 30, max = 40),
        shiny::numericInput("draws", "Uncertainty simulations", 2000, min = 500, max = 10000, step = 500),
        shiny::div(style = sprintf("font-size:12px;color:%s;line-height:1.35;margin-top:-6px;", SLATE),
                   "The manuscript uses 10,000 simulations (random seed 20260718). Set this to 10,000 to reproduce its published 95% range; 2,000 gives a close, faster approximation."))),
    shiny::downloadButton("dl", "Download scenario data", class = "btn-sm btn-primary"),
    shiny::downloadButton("packet", "Download methods and results", class = "btn-sm btn-outline-primary mt-1")
  ),

  # readability baseline: larger body text, dark navy ink, generous wrapping,
  # and no clipped containers anywhere text lives.
  shiny::tags$head(shiny::tags$style(shiny::HTML(paste0(
    "body { font-size:17px; line-height:1.5; color:#1a2438; }",
    "p, li, td, th, label, .form-label { font-size:17px; line-height:1.45; color:#1a2438; }",
    ".card-header { font-size:17px; }",
    "h1.app-q { font-size:24px; font-weight:700; line-height:1.4; color:#141b2d; max-width:1060px; margin:4px 0 0; }",
    ".app-sub { font-size:17px; line-height:1.45; color:#3a4252; max-width:940px; margin:8px 0 4px; }")))),

  # plain page heading (no shaded alert box; expands and wraps freely)
  shiny::div(style = "padding:14px 22px 2px;",
    shiny::h1(class = "app-q", "Does the combined urogynecology fellowship pipeline replace the urogynecologists expected to leave practice?"),
    shiny::p(class = "app-sub", "This national model counts physicians. It does not measure geographic access, patient demand, wait times, or the amount of clinical work performed."),
    shiny::p(class = "app-sub", style = "margin-top:6px;",
      shiny::HTML(sprintf(
        "The default assumptions and 2029 endpoint reproduce the manuscript analysis. Extending the projection beyond 2029 is exploratory. Move any control to explore your own scenario. %s&ensp;&middot;&ensp;%s",
        as.character(shiny::tags$a(href = "manuscript_WORKFORCE_CLIFF.html", target = "_blank", rel = "noopener",
                                   style = sprintf("color:%s;font-weight:700;text-decoration:underline;", NAVY), "Read the full manuscript")),
        as.character(shiny::tags$a(href = "manuscript_WORKFORCE_CLIFF.docx", download = NA,
                                   style = sprintf("color:%s;font-weight:600;", SLATE), "Download manuscript (.docx)")))))),

  shiny::uiOutput("exec_cards"),
  shiny::uiOutput("verdict"),

  bslib::navset_card_tab(
    id = "tabs",

    # ===== 1. BOTTOM LINE (beginner default) ==============================
    bslib::nav_panel("Bottom line",
      bslib::card_body(
        bslib::card(bslib::card_header("Projected active headcount, 2025 onward"),
          bslib::card_body(shiny::plotOutput("traj_mini", height = "300px"))),
        bslib::card(style = paste0("background:", TEAL, "0d;border-left:6px solid ", TEAL, ";"),
          bslib::card_header("What would have to be true for the workforce to shrink?"),
          bslib::card_body(shiny::uiOutput("reverse"))),
        bslib::layout_columns(col_widths = c(4, 4, 4), fill = FALSE,
          bslib::card(bslib::card_header("How many are practicing?"), bslib::card_body(shiny::uiOutput("story1"))),
          bslib::card(bslib::card_header("Who leaves and enters each year?"), bslib::card_body(shiny::uiOutput("story2"))),
          bslib::card(bslib::card_header("Does the conclusion hold under conservative assumptions?"), bslib::card_body(shiny::uiOutput("story3")))),
        shiny::actionButton("go_explore", "Explore the model →", class = "btn-primary"))),

    # ===== 2. EXPLORE THE MODEL ==========================================
    bslib::nav_panel("Explore the model",
      bslib::navset_pill(
        bslib::nav_panel("Projected departures by age",
          bslib::card_body(
            bslib::layout_columns(fill = FALSE, col_widths = c(4, 4, 4),
              bslib::value_box("Aged 60 or older", shiny::textOutput("age60"), "share of the workforce", theme = vbtheme(SLATE)),
              bslib::value_box("Aged 65 or older", shiny::textOutput("age65"), "share of the workforce", theme = vbtheme(SLATE)),
              bslib::value_box("Aged 70 or older", shiny::textOutput("age70"), "share of the workforce", theme = vbtheme(SLATE))),
            bslib::layout_columns(col_widths = c(6, 6),
              bslib::card(bslib::card_header("Number of active urogynecologists by age"), bslib::card_body(shiny::plotOutput("agefig_n", height = "360px"))),
              bslib::card(bslib::card_header("Expected departures each year by age"), bslib::card_body(shiny::plotOutput("agefig_dep", height = "360px")))),
            shiny::uiOutput("age_note"),
            shiny::tableOutput("agetab"))),
        bslib::nav_panel("Future workforce",
          bslib::card_body(shiny::plotOutput("traj", height = "440px"), shiny::plotOutput("flows", height = "180px"), shiny::tableOutput("projtab"))),
        bslib::nav_panel("What could change the conclusion",
          bslib::card_body(
            bslib::layout_columns(fill = FALSE, col_widths = c(4, 4, 4),
              bslib::value_box("Combinations that stay above replacement", shiny::textOutput("sv_above"), "across departure rate and share entering practice", theme = vbtheme(TEAL)),
              bslib::value_box("Worst case tested", shiny::textOutput("sv_worst"), "new urogynecologists per departure", theme = vbtheme(AMBER)),
              bslib::value_box("Departure rate needed to break even", shiny::textOutput("sv_be"), "multiple of the current rate", theme = vbtheme(SLATE))),
            shiny::uiOutput("sv_note"),
            bslib::card(bslib::card_header("Which assumptions change the projected number of physicians most?"), bslib::card_body(shiny::plotOutput("tornado", height = "320px"))))))),

    # ===== 3. RESEARCH DETAILS ===========================================
    bslib::nav_panel("Research details",
      bslib::navset_pill(
        bslib::nav_panel("Methods & sources", bslib::card_body(shiny::tableOutput("prov_tbl"), shiny::uiOutput("assumptions"))),
        bslib::nav_panel("Limitations", bslib::card_body(shiny::uiOutput("limits"))),
        bslib::nav_panel("Uncertainty",
          bslib::card_body(
            bslib::card(class = "border-0", style = paste0("background:#f7f7f9;border-left:5px solid ", NAVY, ";"),
              bslib::card_body(style = "padding:16px 20px;", shiny::HTML(
                "<b>What varies:</b> the estimated annual departure rates and the past fellowship completion counts. <b>What does not vary:</b> the random year-to-year timing of individual departures. The range therefore reflects uncertainty in the inputs, not random chance."))),
            shiny::plotOutput("mc_hist", height = "380px"), shiny::uiOutput("mc_note"))),
        bslib::nav_panel("Sensitivity analysis",
          bslib::card_body(bslib::card(bslib::card_header("Entrants per departure across departure rate and share entering practice"), bslib::card_body(shiny::plotOutput("heat", height = "400px"))))),
        bslib::nav_panel("Capacity & demand (exploratory)",
          bslib::card_body(
            bslib::card(class = "border-0", style = "background:#fff6e5;border-left:6px solid #b0813b;",
              bslib::card_body(style = "padding:10px 16px;", shiny::HTML(
                "<b>Exploratory extension, not part of the primary replacement analysis.</b> Every value here is a planning assumption, not a study measurement."))),
            bslib::layout_columns(col_widths = c(6, 6),
              bslib::card(bslib::card_header("Capacity assumptions"), bslib::card_body(
                shiny::sliderInput("fte_in", "Average clinical full-time work of new urogynecologists (1.0 = full time)", 0.5, 1.0, 0.9, step = 0.05),
                shiny::sliderInput("fte_out", "Average clinical full-time work of departing physicians (1.0 = full time)", 0.5, 1.0, 1.0, step = 0.05),
                shiny::sliderInput("demand", "Annual growth in demand for care (%)", 0, 3, 1, step = 0.5))),
              bslib::card(bslib::card_header("Replacement under capacity and demand"), bslib::card_body(shiny::uiOutput("cap_out")))))),
        bslib::nav_panel("Downloads",
          bslib::card_body(
            shiny::HTML("<p>Reproducible exports for the current scenario.</p>"),
            shiny::downloadButton("dl2", "Download scenario data (spreadsheet)", class = "btn-primary mb-2"),
            shiny::downloadButton("packet2", "Download methods and results (text)", class = "btn-outline-primary"),
            shiny::uiOutput("dl_note")))))
  )
)

# ---- server ----------------------------------------------------------------
main_server <- function(input, output, session) {
  st <- reactiveValues(base = PRIMARY_PRESET)
  apply_preset <- function(p) {
    updateSliderInput(session, "comp", value = p$comp); updateSliderInput(session, "conv", value = p$conv)
    updateSliderInput(session, "mult", value = p$mult); updateSliderInput(session, "mort", value = p$mort)
    updateSelectInput(session, "win", selected = p$win)
  }
  observeEvent(input$preset, {
    if (identical(input$preset, "Custom scenario")) return()
    st$base <- input$preset; apply_preset(PRESETS[[input$preset]])
    base::message("[app] preset -> ", input$preset)
  }, ignoreInit = TRUE)
  observeEvent(input$reset, {
    st$base <- PRIMARY_PRESET
    updateSelectInput(session, "preset", selected = PRIMARY_PRESET); apply_preset(PRESETS[[PRIMARY_PRESET]])
    updateSliderInput(session, "horizon", value = 4); updateNumericInput(session, "entry", value = 34)
    updateSelectInput(session, "hz70", selected = "obs")
  })
  observeEvent(input$go_explore, bslib::nav_select("tabs", "Explore the model", session = session))
  observeEvent(input$view_ranges, bslib::nav_select("tabs", "Explore the model", session = session))
  matches_preset <- function(name) { p <- PRESETS[[name]]; !is.null(p) && input$comp == p$comp && input$conv == p$conv && input$mult == p$mult && input$win == p$win && input$mort == p$mort }
  # A manual edit that no longer matches the selected preset flips the selector to Custom.
  # Shiny applies all of apply_preset()'s updates in one flush, so selecting a preset lands
  # on matching values and never spuriously trips this.
  observeEvent(list(input$comp, input$conv, input$mult, input$win, input$mort), {
    if (!identical(input$preset, "Custom scenario") && !matches_preset(input$preset)) {
      st$base <- input$preset; updateSelectInput(session, "preset", selected = "Custom scenario")
    }
  }, ignoreInit = TRUE)

  output$scenario_help <- renderUI({
    h <- SCENARIO_HELP[[input$preset]]; if (is.null(h)) return(NULL)
    HTML(sprintf("<div style='font-size:12px;color:#555;margin:-4px 0 6px;line-height:1.35;'>%s</div>", h))
  })
  # plain-language "changes vs the best estimate" (works for presets and custom edits)
  output$scenario_status <- renderUI({
    p0 <- PRESETS[[PRIMARY_PRESET]]; yr <- 2025 + input$horizon
    custom <- identical(input$preset, "Custom scenario")
    extended <- input$horizon != 4   # a longer horizon is a view control, not a changed assumption
    # a manual edit makes the state unmistakable: a Custom header plus compact chips
    # of the current assumptions (changed ones highlighted). Reset button sits alongside.
    chip <- function(txt, changed) sprintf(
      "<span style='display:inline-block;background:%s;color:%s;border:1px solid %s;border-radius:12px;padding:2px 9px;margin:0 5px 5px 0;font-size:12px;font-weight:600;'>%s</span>",
      if (changed) paste0(USERC, "1f") else "#eef1f5", if (changed) USERC else "#3a4252", if (changed) USERC else "#d0d5dd", txt)
    # the through-year chip is never highlighted: changing the horizon extends the view,
    # it does not modify the underlying assumptions.
    chips <- paste0(
      chip(sprintf("%d completions", input$comp), input$comp != p0$comp),
      chip(sprintf("%d%% enter practice", input$conv), input$conv != p0$conv),
      chip(sprintf("%.1fx departures", input$mult), input$mult != p0$mult),
      chip(sprintf("through %d", yr), FALSE))
    # title/subtitle: distinguish a changed ASSUMPTION (Custom) from a changed HORIZON
    # (still the best-estimate assumptions, just projected further out).
    title <- if (custom) "Custom scenario" else if (identical(input$preset, "Best estimate")) "Best-estimate assumptions" else input$preset
    title_col <- if (custom) USERC else NAVY
    sub <- if (custom) "Modified from Best estimate"
           else if (extended) sprintf("Projection extended through %d (exploratory)", yr)
           else if (identical(input$preset, "Best estimate")) "The study's primary assumptions"
           else SCENARIO_HELP[[input$preset]]
    header <- sprintf("<div style='font-size:15px;font-weight:800;color:%s;'>%s</div><div style='font-size:12px;color:%s;margin-bottom:6px;'>%s</div>", title_col, title, SLATE, sub)
    HTML(paste0("<div style='margin:-2px 0 8px;line-height:1.4;'>", header, chips, "</div>"))
  })
  output$horizon_year <- renderUI(HTML(sprintf("<div style='font-size:12px;color:%s;margin:-6px 0 8px;'>Projects through <b>%d</b>.</div>", SLATE, 2025 + input$horizon)))

  entry_age <- reactive(as.integer(if (is.na(input$entry)) 34L else input$entry))
  extra_mort <- reactive(MORTALITY_ALL_MISSED * input$mort / 100)

  model <- reactive({
    hz <- adjusted_haz(input$win, input$mult, input$hz70); ent <- input$comp * input$conv / 100
    r <- project_traj(URPS_AGES, ent, hz, input$horizon, entry_age(), extra_mort())
    r_ramp <- project_traj(URPS_AGES, ent, hz, input$horizon, entry_age(), extra_mort(), ramp = RAMP_CUM_URPS)
    grow <- tail(r$traj, 1) - BASELINE
    list(traj = r$traj, dep_yr = r$dep_yr, avg_dep = r$avg_dep, ratio = ent / r$avg_dep,
         entrants_eff = ent, proj = tail(r$traj, 1), proj_ramped = tail(r_ramp$traj, 1),
         grow = grow, grow_pct = 100 * grow / BASELINE)
  })
  mc <- reactive(run_mc(input$win, input$conv / 100 * input$comp / GRAD_MEAN, input$mult, input$horizon,
                        entry_age(), extra_mort(), as.integer(input$draws), input$hz70)) |> debounce(400)
  surface <- reactive(sensitivity_surface(input$win, input$comp, input$horizon, entry_age(), extra_mort(), input$hz70))

  # ---- dynamic input labels (badges update with the value)
  output$lab_comp <- renderUI({ b <- badge_comp(input$comp); dyn_label("Annual fellowship completions", b[1], b[2], "Accredited fellowship completions, recent 4-year mean (~48 OB/GYN + ~16 urology)") })
  output$lab_conv <- renderUI({ b <- badge_conv(input$conv); dyn_label("Percentage of graduates who enter practice", b[1], b[2], "Counts accredited completions; graduate-to-practice attrition is tested here, not observed") })
  output$lab_mult <- renderUI({ b <- badge_mult(input$mult)
    phrase <- if (input$mult == 1) "study estimate" else if (input$mult < 1) sprintf("%.0f%% fewer departures", 100 * (1 - input$mult)) else sprintf("%.0f%% more departures", 100 * (input$mult - 1))
    HTML(paste0(as.character(dyn_label("How much faster physicians leave than estimated", b[1], b[2], "Scales every age-band departure hazard")),
                sprintf("<div style='font-size:12px;color:%s;'>%.1fx = %s</div>", SLATE, input$mult, phrase))) })
  output$lab_win  <- renderUI({ b <- badge_win(input$win);  dyn_label("Time period used to estimate departure rates", b[1], b[2]) })
  output$lab_mort <- renderUI({ b <- badge_mort(input$mort)
    HTML(paste0(as.character(dyn_label("Additional mortality adjustment (%)", b[1], b[2])),
                sprintf("<div style='font-size:12px;color:%s;line-height:1.35;'>Optional assumption used to test departures not captured in the observed records.</div>", SLATE))) })

  # ---- executive cards (semantic, dynamic color)
  output$exec_cards <- renderUI({
    m <- model(); yr <- 2025 + input$horizon
    enter <- m$entrants_eff; leave <- m$avg_dep; net <- enter - leave
    mx <- max(enter, leave, 1); pe <- 100 * enter / mx; pl <- 100 * leave / mx
    net_txt <- if (net >= 0) sprintf("Net gain: about +%.0f per year", net) else sprintf("Net change: about %.0f per year", net)
    net_col <- if (net >= 0) NAVY else RED
    ratio_col <- if (m$ratio >= 1) TEAL else RED
    # entrants are essentially fixed each year; departures rise as the cohort ages, so the
    # "leave" figure is an AVERAGE across the projection, not a constant. Show that range.
    dep_lo <- m$dep_yr[1]; dep_hi <- m$dep_yr[length(m$dep_yr)]
    # dominant enter-vs-leave flow: two bars on one scale, then supporting counts + ratio badge.
    # a two-line label carries the "each year" / "average" qualifier without crowding the value.
    bar <- function(lbl, sublbl, val, pct, col) sprintf(
      "<div style='display:flex;align-items:center;gap:12px;margin:10px 0;'>
         <div style='width:168px;text-align:right;letter-spacing:.02em;line-height:1.15;'>
           <div style='font-size:14px;font-weight:700;color:#3a4252;'>%s</div>
           <div style='font-size:11px;font-weight:600;color:%s;text-transform:none;letter-spacing:0;'>%s</div></div>
         <div style='flex:1;background:#eef1f5;border-radius:7px;height:34px;'><div style='width:%.1f%%;background:%s;height:34px;border-radius:7px;min-width:6px;'></div></div>
         <div style='width:52px;font-size:24px;font-weight:800;color:%s;'>%.0f</div></div>", lbl, SLATE, sublbl, pct, col, col, val)
    support <- function(num, lbl) sprintf(
      "<div style='display:inline-block;vertical-align:top;margin-right:28px;'><span style='font-size:26px;font-weight:800;color:%s;'>%s</span><div style='font-size:13px;color:%s;line-height:1.3;max-width:190px;'>%s</div></div>",
      NAVY, num, SLATE, lbl)
    HTML(paste0(
      "<div style='max-width:1080px;padding:6px 22px 4px;'>",
      bar("ENTER PRACTICE", "each year", enter, pe, TEAL),
      bar("AVERAGE LEAVING", paste0("each year through ", yr), leave, pl, RED),
      "<div style='margin:6px 0 2px 180px;font-size:19px;font-weight:800;color:", net_col, ";'>", net_txt, "</div>",
      "<div style='margin:0 0 4px 180px;font-size:12px;color:", SLATE, ";line-height:1.35;max-width:560px;'>",
      sprintf("Leaving is the average across 2026 to %d; the yearly number rises from about %.1f to about %.1f as the workforce ages.", yr, dep_lo, dep_hi),
      "</div>",
      "<div style='display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin-top:16px;padding-top:14px;border-top:1px solid #e6e9ef;'>",
      support(format(BASELINE, big.mark = ","), "estimated active headcount in 2025"),
      support(format(round(m$proj), big.mark = ","), paste0("projected active headcount in ", yr)),
      "<span style='display:inline-block;background:", ratio_col, "14;color:", ratio_col, ";border:1px solid ", ratio_col,
      ";border-radius:14px;padding:5px 12px;font-size:14px;font-weight:700;'>Headcount replacement ratio: ", sprintf("%.1f", m$ratio), " to 1</span>",
      "</div></div>"))
  })

  output$verdict <- renderUI({
    m <- model(); yr <- 2025 + input$horizon
    grow_word <- if (m$grow >= 0) "an increase" else "a decrease"
    proj_line <- sprintf("<b>Projected urogynecologists in %d:</b> %s, %s of %s (%+.1f%%).",
                         yr, format(round(m$proj), big.mark = ","), grow_word, format(abs(round(m$grow)), big.mark = ","), m$grow_pct)
    limit_line <- "This finding concerns the national number of urogynecologists. It does not establish that patients have adequate access to care."
    if (m$grow_pct > 1) { col <- TEAL; head <- sprintf("<b>Bottom line: Yes.</b> Under the selected assumptions, new urogynecologists more than replace the number projected to leave practice through %d.", yr) }
    else if (m$grow_pct >= -1) { col <- AMBER; head <- sprintf("<b>Bottom line: About even.</b> Under the selected assumptions, the number entering roughly matches the number projected to leave practice through %d.", yr) }
    else { col <- RED; head <- sprintf("<b>Bottom line: No.</b> Under this stress test, the number entering does not replace the number projected to leave practice through %d.", yr) }
    bslib::card(class = "border-0", style = sprintf("background:%s14;border-left:6px solid %s;", col, col),
      bslib::card_body(style = "padding:20px 24px;overflow:visible;white-space:normal;",
        HTML(sprintf("<div style='font-size:18px;line-height:1.5;color:#141b2d;'>%s</div>
                      <div style='font-size:17px;line-height:1.5;color:#141b2d;margin-top:10px;'>%s</div>
                      <div style='font-size:16px;line-height:1.5;color:#3a4252;margin-top:10px;'>%s</div>",
                     head, proj_line, limit_line))))
  })

  # ---- Bottom line
  output$story1 <- renderUI(big_stat("Active urogynecologists (both pathways)", format(BASELINE, big.mark = ","), "Combined obstetrics and gynecology and urology certification pathways; duplicates removed"))
  output$story2 <- renderUI({ m <- model(); HTML(sprintf("%s<div style='margin-top:8px;'>%s</div>",
    big_stat("Enter practice each year", sprintf("%.0f", m$entrants_eff), "after accounting for the share entering practice", TEAL),
    big_stat("Leave practice each year", sprintf("%.1f", m$avg_dep), "average across age groups", AMBER))) })
  # the robustness card reports the PRESPECIFIED grid (fixed at default settings), not a
  # recomputation around the current custom scenario, so the "N of N" claim is stable and
  # matches the manuscript. A link jumps to the full grid.
  output$story3 <- renderUI({ g <- SURF_PRESPEC; ab <- sum(g$ratio >= 1); col <- if (ab == nrow(g)) TEAL else AMBER
    sub <- sprintf("%d of %d combinations in the study's prespecified sensitivity grid kept the replacement ratio above 1.0.", ab, nrow(g))
    shiny::tagList(
      big_stat("Robust in prespecified sensitivity analyses", sprintf("%d of %d", ab, nrow(g)), sub, col),
      HTML(sprintf("<div style='font-size:13px;color:%s;line-height:1.4;margin:2px 0 8px;'>Applies to the prespecified grid (departure rate 0.5x to 3x the current rate, share entering practice 60%% to 100%%), not the current custom scenario.</div>", SLATE)),
      shiny::actionLink("view_ranges", "View tested ranges →", style = "font-size:14px;font-weight:600;")) })
  output$reverse <- renderUI({ m <- model(); be_conv <- 100 * m$avg_dep / input$comp; be_comp <- m$avg_dep / (input$conv / 100)
    HTML(sprintf("<div style='font-size:17px;line-height:1.7;color:#1a2438;'><b>Holding all other selected assumptions constant, national active headcount reaches break-even if any one of the following occurs:</b>
      <ul style='margin:10px 0;'><li style='margin-bottom:6px;'>the number leaving each year rose about <b>%.1f times</b> (from about %.1f to about %.0f per year), or</li>
      <li style='margin-bottom:6px;'>annual fellowship completions fell from %d to below <b>%.0f</b> per year, or</li>
      <li style='margin-bottom:6px;'>fewer than <b>%.0f%%</b> of graduates entered active practice.</li></ul>
      Each one-factor threshold is outside the ranges tested in the primary sensitivity analyses. Several smaller changes acting together could reach break-even sooner.</div>", m$ratio, m$avg_dep, m$entrants_eff, input$comp, be_comp, be_conv)) })

  # ---- Age & departures
  output$age60 <- renderText(sprintf("%.0f%%", 100 * mean(URPS_AGES >= 60)))
  output$age65 <- renderText(sprintf("%.0f%%", 100 * mean(URPS_AGES >= 65)))
  output$age70 <- renderText(sprintf("%.0f%%", 100 * mean(URPS_AGES >= 70)))
  # two separate, simple horizontal bar charts (clearer than one dual-axis chart)
  age_df <- reactive({
    at <- age_table(input$win, input$mult, input$hz70)
    at$label <- factor(BAND_DISPLAY[at$band], levels = BAND_DISPLAY)  # youngest -> oldest
    # a hazard of exactly 0 means no departures were observed in that band (only the
    # sparse 70+ group under the as-observed setting): mark it, do not show a real 0.
    at$sparse <- at$hazard == 0
    at$dep_label <- ifelse(at$sparse, "not reliably estimated", sprintf("%.1f", at$exp_dep))
    at
  })
  output$agefig_n <- renderPlot({
    at <- age_df()
    ggplot(at, aes(label, n)) +
      geom_col(fill = NAVY, width = 0.72) +
      geom_text(aes(label = format(round(n), big.mark = ",")), hjust = -0.15, size = 4.4, colour = "#141b2d") +
      coord_flip() +
      scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
      labs(x = NULL, y = "Number of urogynecologists") +
      theme_minimal(base_size = 15) +
      theme(panel.grid.major.y = element_blank(), panel.grid.minor = element_blank(),
            axis.text = element_text(colour = "#141b2d"))
  }, height = 360, res = 96, bg = "white")
  output$agefig_dep <- renderPlot({
    at <- age_df()
    ggplot(at, aes(label, exp_dep)) +
      geom_col(fill = RED, width = 0.72) +
      geom_text(aes(label = dep_label), hjust = -0.05, size = 4.0,
                colour = ifelse(at$sparse, SLATE, "#141b2d"),
                fontface = ifelse(at$sparse, "italic", "plain")) +
      coord_flip() +
      scale_y_continuous(expand = expansion(mult = c(0, 0.45))) +
      labs(x = NULL, y = "Expected departures each year") +
      theme_minimal(base_size = 15) +
      theme(panel.grid.major.y = element_blank(), panel.grid.minor = element_blank(),
            axis.text = element_text(colour = "#141b2d"))
  }, height = 360, res = 96, bg = "white")
  output$age_note <- renderUI(HTML(sprintf("<div style='color:#3a4252;font-size:16px;line-height:1.5;margin:10px 0;'>Urogynecologists aged 60 to 69 account for about %.0f%% of projected departures even though they are a small share of the workforce. The estimate for physicians 70 years or older is based on very limited data (in the primary period, no departures were observed among the few in this group); a longer observation period puts their annual departure rate near 8%%. The setting for this group is in Researcher settings.</div>",
    { at <- age_table(input$win, input$mult, input$hz70); 100 * sum(at$exp_dep[at$band %in% c("60-64","65-69")]) / sum(at$exp_dep) })))
  output$agetab <- renderTable({ at <- age_table(input$win, input$mult, input$hz70)
    sparse <- at$hazard == 0   # no departures observed (sparse 70+ under as-observed)
    rate  <- ifelse(sparse, "Not reliably estimated", sprintf("%.1f%%", 100 * at$hazard))
    edep  <- ifelse(sparse, "Not reliably estimated", sprintf("%.1f", at$exp_dep))
    pdep  <- ifelse(sparse, "Not reliably estimated", sprintf("%.0f%%", at$pct_dep))
    data.frame(`Age group` = unname(BAND_DISPLAY[at$band]), `Number of urogynecologists` = format(round(at$n), big.mark = ","),
               `Share of the workforce` = sprintf("%.1f%%", at$pct), `Annual departure rate` = rate,
               `Expected departures each year` = edep, `Share of projected departures` = pdep, check.names = FALSE)
  }, striped = TRUE, hover = TRUE, width = "100%")

  # ---- Headcount projection
  output$traj <- renderPlot({
    m <- model(); q <- mc(); yrs <- 2025 + 0:input$horizon; line_col <- if (m$proj >= BASELINE) NAVY else RED
    ribbon <- data.frame(year = c(min(yrs), max(yrs)), lo = c(BASELINE, q$final_lo), hi = c(BASELINE, q$final_hi))
    df <- data.frame(year = yrs, active = m$traj); end <- df[nrow(df), ]
    ggplot(df, aes(year, active)) +
      geom_ribbon(data = ribbon, aes(x = year, ymin = lo, ymax = hi), inherit.aes = FALSE, fill = NAVY, alpha = 0.18) +
      geom_hline(yintercept = BASELINE, linetype = "dashed", colour = "grey55") +
      geom_line(linewidth = 1.4, colour = line_col) + geom_point(size = 2.8, colour = line_col) +
      annotate("text", x = min(yrs), y = BASELINE, label = sprintf("2025 baseline: %s", format(BASELINE, big.mark = ",")), vjust = 1.6, hjust = 0, colour = "grey40", size = 4.2) +
      annotate("text", x = end$year, y = end$active, label = sprintf("%s  (%+d, %+.1f%%)", format(round(end$active), big.mark = ","), round(m$grow), m$grow_pct), vjust = -1, hjust = 1, colour = line_col, size = 4.6, fontface = "bold") +
      scale_x_continuous(breaks = yrs, expand = expansion(mult = c(0.02, 0.14))) + scale_y_continuous(labels = scales::comma, expand = expansion(mult = c(0.08, 0.18))) +
      labs(x = NULL, y = NULL, title = "Projected active headcount of urogynecologists",
           subtitle = "Shaded band: 95% parameter-uncertainty interval (does not represent unpredictable year-to-year variation).",
           caption = "Note: the vertical axis does not begin at zero. A projection is not an observed future count.") +
      theme_minimal(base_size = 15) + theme(plot.title.position = "plot", panel.grid.minor = element_blank(), plot.caption = element_text(colour = "#5f6673"), axis.text = element_text(colour = "#141b2d"))
  }, height = 440, res = 96, bg = "white")
  # compact projection line for the first screen (Bottom line), same data as output$traj
  output$traj_mini <- renderPlot({
    m <- model(); q <- mc(); yrs <- 2025 + 0:input$horizon; line_col <- if (m$proj >= BASELINE) NAVY else RED
    ribbon <- data.frame(year = c(min(yrs), max(yrs)), lo = c(BASELINE, q$final_lo), hi = c(BASELINE, q$final_hi))
    df <- data.frame(year = yrs, active = m$traj); end <- df[nrow(df), ]
    ggplot(df, aes(year, active)) +
      geom_ribbon(data = ribbon, aes(x = year, ymin = lo, ymax = hi), inherit.aes = FALSE, fill = NAVY, alpha = 0.18) +
      geom_hline(yintercept = BASELINE, linetype = "dashed", colour = "grey55") +
      geom_line(linewidth = 1.4, colour = line_col) + geom_point(size = 2.6, colour = line_col) +
      annotate("text", x = min(yrs), y = BASELINE, label = sprintf("2025: %s", format(BASELINE, big.mark = ",")), vjust = 1.6, hjust = 0, colour = "grey40", size = 4) +
      annotate("text", x = end$year, y = end$active, label = format(round(end$active), big.mark = ","), vjust = -1, hjust = 1, colour = line_col, size = 5, fontface = "bold") +
      scale_x_continuous(breaks = yrs, expand = expansion(mult = c(0.02, 0.14))) + scale_y_continuous(labels = scales::comma, expand = expansion(mult = c(0.10, 0.20))) +
      labs(x = NULL, y = NULL, title = sprintf("Projected active headcount, 2025 to %d", 2025 + input$horizon),
           subtitle = "Shaded band: 95% parameter-uncertainty interval (not year-to-year variation).") +
      theme_minimal(base_size = 14) + theme(plot.title.position = "plot", panel.grid.minor = element_blank(), axis.text = element_text(colour = "#141b2d"))
  }, height = 300, res = 96, bg = "white")
  output$flows <- renderPlot({
    m <- model(); yrs <- 2025 + seq_len(input$horizon)
    ggplot(data.frame(year = yrs, departures = m$dep_yr), aes(year, departures)) +
      geom_col(fill = RED, alpha = 0.85, width = 0.6) + geom_hline(yintercept = m$entrants_eff, colour = NAVY, linewidth = 1.1) +
      annotate("text", x = max(yrs), y = m$entrants_eff, label = sprintf("about %.0f enter per year", m$entrants_eff), vjust = -0.6, hjust = 1, colour = NAVY, size = 4.4) +
      scale_x_continuous(breaks = yrs) + labs(x = NULL, y = "Number of urogynecologists", title = "Urogynecologists entering (line) versus leaving each year (bars)") +
      theme_minimal(base_size = 14) + theme(plot.title.position = "plot", panel.grid.minor = element_blank(), axis.text = element_text(colour = "#141b2d"))
  }, height = 190, res = 96, bg = "white")
  output$projtab <- renderTable({ m <- model(); yrs <- 2025 + 0:input$horizon
    data.frame(Year = yrs, `Number of urogynecologists` = format(round(m$traj), big.mark = ","), `Leaving that year` = c(NA, sprintf("%.1f", m$dep_yr)), check.names = FALSE)
  }, striped = TRUE, hover = TRUE, width = "100%", na = "")

  # ---- Capacity & demand (exploratory)
  output$cap_out <- renderUI({ m <- model()
    cap_ratio <- m$ratio * input$fte_in / input$fte_out
    sd_index <- (m$proj / BASELINE) / (1 + input$demand / 100)^input$horizon
    HTML(sprintf("%s%s%s<div style='color:#3a4252;font-size:15px;line-height:1.45;margin-top:8px;'>The head-count ratio counts physicians. The clinical-work ratio adjusts for how much clinical work new versus departing physicians do. The supply-versus-demand index compares the growth in physicians to the growth in demand for care over %d years; above 1.0 means supply keeps pace.</div>",
      big_stat("Head-count replacement ratio", sprintf("%.1f", m$ratio), "new urogynecologists per departure"),
      big_stat("Clinical-work replacement ratio", sprintf("%.1f", cap_ratio), sprintf("adjusted for clinical full-time work (%.2f in / %.2f out)", input$fte_in, input$fte_out), if (cap_ratio >= 1) TEAL else RED),
      big_stat("Supply versus demand", sprintf("%.2f", sd_index), sprintf("at %.1f%% growth in demand per year", input$demand), if (sd_index >= 1) TEAL else RED), input$horizon)) })

  # ---- Sensitivity
  output$sv_above <- renderText({ g <- surface(); sprintf("%d / %d", sum(g$ratio >= 1), nrow(g)) })
  output$sv_worst <- renderText(sprintf("%.1f", min(surface()$ratio)))
  output$sv_be <- renderText({ be <- breakeven_mult(input$win, input$comp * input$conv / 100, input$horizon, entry_age(), extra_mort(), input$hz70); if (is.na(be)) "> 40x" else sprintf("%.1fx", be) })
  output$sv_note <- renderUI({ be <- breakeven_mult(input$win, input$comp * input$conv / 100, input$horizon, entry_age(), extra_mort(), input$hz70)
    msg <- if (is.na(be) || be > 3.0) "Reaching the break-even point falls outside every combination tested (departure rates from half to three times the current rate): none of them makes the number leaving exceed the number entering." else sprintf("The number leaving would have to be about %.1f times the current rate to reach the break-even point at the current share entering practice.", be)
    HTML(sprintf("<div style='padding:8px 2px 12px;color:#1a2438;font-size:16px;line-height:1.5;'>The grid tests the share entering practice (60%% to 100%%) against the departure rate (half to three times the current rate), 99 combinations in all. %s</div>", msg)) })
  output$tornado <- renderPlot({
    base <- headcount_at(input$comp, input$conv, input$mult, input$win, input$mort, entry_age(), input$horizon, input$hz70)
    H <- function(...) headcount_at(...)
    rows <- list(
      c("Fellowship completions", H(PLAUS$comp[1], input$conv, input$mult, input$win, input$mort, entry_age(), input$horizon, input$hz70), H(PLAUS$comp[2], input$conv, input$mult, input$win, input$mort, entry_age(), input$horizon, input$hz70)),
      c("Share entering practice", H(input$comp, PLAUS$conv[1], input$mult, input$win, input$mort, entry_age(), input$horizon, input$hz70), H(input$comp, PLAUS$conv[2], input$mult, input$win, input$mort, entry_age(), input$horizon, input$hz70)),
      c("Departure rate", H(input$comp, input$conv, PLAUS$mult[2], input$win, input$mort, entry_age(), input$horizon, input$hz70), H(input$comp, input$conv, PLAUS$mult[1], input$win, input$mort, entry_age(), input$horizon, input$hz70)),
      c("Additional deaths", H(input$comp, input$conv, input$mult, input$win, 100, entry_age(), input$horizon, input$hz70), H(input$comp, input$conv, input$mult, input$win, 0, entry_age(), input$horizon, input$hz70)),
      c("Entry age", H(input$comp, input$conv, input$mult, input$win, input$mort, PLAUS$entry[2], input$horizon, input$hz70), H(input$comp, input$conv, input$mult, input$win, input$mort, PLAUS$entry[1], input$horizon, input$hz70)),
      c("Rate for physicians 70+", H(input$comp, input$conv, input$mult, input$win, input$mort, entry_age(), input$horizon, "carry"), H(input$comp, input$conv, input$mult, input$win, input$mort, entry_age(), input$horizon, "obs")))
    df <- do.call(rbind, lapply(rows, function(r) data.frame(param = r[1], lo = as.numeric(r[2]), hi = as.numeric(r[3]))))
    df$span <- abs(df$hi - df$lo); df <- df[order(df$span), ]; df$param <- factor(df$param, levels = df$param)
    ggplot(df, aes(y = param)) + geom_vline(xintercept = base, linetype = "dashed", colour = "grey55") +
      geom_segment(aes(x = pmin(lo, hi), xend = pmax(lo, hi), yend = param), colour = NAVY, linewidth = 7, alpha = 0.85) +
      annotate("text", x = base, y = 0.5, label = sprintf("base %s", format(round(base), big.mark = ",")), hjust = -0.05, vjust = 0, colour = "grey40", size = 3.6) +
      scale_x_continuous(labels = scales::comma) + labs(x = sprintf("Number of urogynecologists in %d", 2025 + input$horizon), y = NULL, subtitle = "Each bar shows the range as that assumption is varied across its plausible range") +
      theme_minimal(base_size = 14) + theme(plot.title.position = "plot", panel.grid.minor = element_blank(), axis.text = element_text(colour = "#141b2d"))
  }, height = 320, res = 96, bg = "white")
  output$heat <- renderPlot({ g <- surface()
    ggplot(g, aes(mult, conv * 100, fill = ratio)) + geom_tile(colour = "white") + geom_text(aes(label = sprintf("%.1f", ratio)), size = 3.2, colour = "grey15") +
      scale_fill_gradient2(midpoint = 1, low = RED, mid = "#e9c46a", high = TEAL, name = "Entering per\ndeparture") +
      geom_vline(xintercept = input$mult, linetype = "dotted") + geom_hline(yintercept = input$conv, linetype = "dotted") +
      scale_x_continuous(breaks = unique(g$mult)) + labs(x = "Departure rate (multiple of current rate)", y = "Share of graduates entering practice (%)", subtitle = "New urogynecologists per departure; dotted lines mark the current settings.") +
      theme_minimal(base_size = 14) + theme(plot.title.position = "plot", panel.grid = element_blank(), axis.text = element_text(colour = "#141b2d"))
  }, height = 400, res = 96, bg = "white")

  # ---- Monte Carlo
  output$mc_hist <- renderPlot({ q <- mc()
    ggplot(data.frame(final = q$final), aes(final)) + geom_histogram(bins = 40, fill = NAVY, alpha = 0.85) +
      geom_vline(xintercept = BASELINE, colour = RED, linewidth = 1) +
      annotate("text", x = BASELINE, y = Inf, label = sprintf("2025 baseline (%s)", format(BASELINE, big.mark = ",")), vjust = 1.6, hjust = 1.03, colour = RED, size = 4) +
      geom_vline(xintercept = c(q$final_lo, q$final_hi), linetype = "dashed", colour = "grey40") + scale_x_continuous(labels = scales::comma) +
      labs(x = sprintf("Number of urogynecologists in %d", 2025 + input$horizon), y = "Number of simulations", title = sprintf("Possible %d workforce across %s uncertainty simulations", 2025 + input$horizon, format(q$draws, big.mark = ",")), subtitle = "Dashed lines = 95% range; solid red line = number of urogynecologists in 2025") +
      theme_minimal(base_size = 14) + theme(plot.title.position = "plot", panel.grid.minor = element_blank())
  }, height = 380, res = 96, bg = "white")
  output$mc_note <- renderUI({ q <- mc()
    HTML(sprintf("<div style='background:#f2f4f8;border-radius:6px;padding:16px 20px;margin-top:8px;font-size:16px;line-height:1.5;color:#141b2d;'><b>%s of %s</b> simulations end below the 2025 number of physicians. Each simulation redraws the annual departure rate for every age group and resamples the recent fellowship completion counts, then reruns the projection. Across the simulations, the number entering exceeds the number leaving by a factor of %.1f to %.1f (95%% range).</div>",
      format(q$n_decline, big.mark = ","), format(q$draws, big.mark = ","), q$ratio_lo, q$ratio_hi)) })

  # ---- Methods
  output$prov_tbl <- renderTable({
    lnk <- function(url, text) sprintf("<a href='%s' target='_blank' rel='noopener' style='color:#20355e;text-decoration:underline;'>%s</a>", url, text)
    data.frame(
    Quantity = c("Fellowship completions", "Annual departure rates", "Share of graduates entering practice", "Additional deaths"),
    Value = c("64 per year", "by age group, about 2% per year overall", "assumption", "assumption"),
    Source = c(
      lnk("https://www.acgme.org/about-us/publications-and-resources/graduate-medical-education-data-resource-book/", "ACGME Data Resource Book"),
      paste0(lnk("https://data.cms.gov/provider-summary-by-type-of-service/medicare-physician-other-practitioners", "Medicare"),
             " and ",
             lnk("https://npiregistry.cms.hhs.gov/", "national provider records")),
      "not observed",
      paste0(lnk("https://www.ssa.gov/oact/STATS/table4c6.html", "Social Security life tables"), ", upper bound")),
    Category = c("Observed", "Estimated", "Assumption", "Assumption"),
    Limitation = c("Recent 4-year average, not a forecast", "Data on the oldest physicians is limited", "Counts accredited completions", "Upper-bound stress test"),
    check.names = FALSE) }, striped = TRUE, hover = TRUE, width = "100%", sanitize.text.function = function(x) x)
  output$assumptions <- renderUI(HTML(
    "<div style='max-width:900px;line-height:1.55;margin-top:8px;font-size:17px;color:#1a2438;'>
     <p><b>Both training pathways.</b> Physicians certified through the American Board of Obstetrics and Gynecology (linked to Medicare records) are combined with the American Board of Urology urogynecology roster, taken in full from the board's public verification portal (12,588 urologists, narrowed to 370 in urogynecology, about 270 added after removing physicians already counted on the obstetrics and gynecology side).</p>
     <p><b>All graduates entering practice in the best estimate.</b> The model counts accredited fellowship completions. The share of graduates who do not immediately enter active U.S. practice (part-time work, delayed entry, moving abroad) is not observed here and is tested separately with the practice-entry slider.</p>
     <p><b>Departures, not retirement alone.</b> A departure is any exit from active clinical practice: stopping Medicare billing or prescribing, removal from the national provider registry, lapse of board certification, or death. Certification-maintenance status is not used. The matched-position benchmark uses filled fellowship positions, not completed fellowships, and is shown only for comparison.</p>
     <p><b>Ramp-up-adjusted 2029 estimate (sensitivity).</b> The primary model finding is the immediate-entry projection of <b>1,544</b> active urogynecologists in 2029. New graduates in reality phase into practice over several years rather than entering immediately; applying that empirical certification-to-first-Medicare-activity entry ramp gives a lower estimate of about <b>1,466</b>. This is a Medicare-observed entry-timing sensitivity, not a measured clinical-capacity count, and is reported here rather than on the headline card.</p>
     <p style='color:#5f6673;font-size:14px;'>The projection uses the same calculation as the study's analysis code (wc_project in R/workforce_cliff_engine.R).</p></div>"))

  output$limits <- renderUI({
    items <- c("This counts physicians nationally. It does not measure geographic access, wait times, demand for care, or how much clinical work each physician performs.",
               "Urology-pathway urogynecologists are assumed to leave practice at the same measured rate as the obstetrics and gynecology pathway, because departure data is not available for the urology side.",
               "The departure rate for physicians 70 years or older is based on very limited data; the Researcher settings let you test alternatives.")
    if (input$conv >= 100) items <- c(items, "This scenario assumes every fellowship graduate enters active U.S. practice immediately, with no part-time work, delayed entry, or moves abroad.")
    if (input$mort == 0) items <- c(items, "No additional unobserved deaths are added in this scenario.")
    if (input$win == "full") items <- c(items, "The full 2016 to 2023 period is provisional; the most recent years are still incomplete, so recent departures may be undercounted.")
    if (input$mult == 1) items <- c(items, "Departure rates are held at the measured level; no speed-up or slow-down is assumed.")
    HTML(paste0("<div style='max-width:900px;line-height:1.6;font-size:17px;color:#1a2438;'><p>Under the current scenario:</p><ul>", paste0("<li style='margin-bottom:6px;'>", items, "</li>", collapse = ""), "</ul></div>"))
  })

  # ---- downloads
  scenario_csv <- function(file) { m <- model(); q <- mc(); yrs <- 2025 + 0:input$horizon
    meta <- data.frame(parameter = c("scenario","modified_from","completions","conversion_pct","departure_multiplier","hazard_window","hz70_treatment","mortality_pct","entry_age","horizon_years","baseline","entrants_effective","mean_annual_departures","entrants_per_departure","ratio_ci_lo","ratio_ci_hi","final_ci_lo","final_ci_hi","simulations","simulations_declining"),
      value = c(input$preset, if (identical(input$preset, "Custom scenario")) st$base else "", input$comp, input$conv, input$mult, input$win, input$hz70, input$mort, entry_age(), input$horizon, BASELINE, round(m$entrants_eff, 2), round(m$avg_dep, 2), round(m$ratio, 3), round(q$ratio_lo, 3), round(q$ratio_hi, 3), round(q$final_lo), round(q$final_hi), q$draws, q$n_decline))
    traj <- data.frame(parameter = paste0("active_", yrs), value = round(m$traj)); utils::write.csv(rbind(meta, traj), file, row.names = FALSE) }
  analysis_packet <- function(file) {
    m <- model(); q <- mc(); at <- age_table(input$win, input$mult, input$hz70)
    be_conv <- 100 * m$avg_dep / input$comp; be_comp <- m$avg_dep / (input$conv / 100)
    modified <- identical(input$preset, "Custom scenario")
    changes <- if (modified) { p <- PRESETS[[st$base]]; d <- c(); if (!is.null(p)) { if (input$comp!=p$comp) d<-c(d,sprintf("completions %d->%d",p$comp,input$comp)); if (input$conv!=p$conv) d<-c(d,sprintf("conversion %d->%d",p$conv,input$conv)); if (input$mult!=p$mult) d<-c(d,sprintf("multiplier %.1f->%.1f",p$mult,input$mult)); if (input$win!=p$win) d<-c(d,sprintf("window %s->%s",p$win,input$win)); if (input$mort!=p$mort) d<-c(d,sprintf("mortality %d->%d",p$mort,input$mort)) }; paste(d, collapse="; ") } else "none"
    prespec <- (!modified) && input$comp>=PLAUS$comp[1] && input$comp<=PLAUS$comp[2] && input$conv>=PLAUS$conv[1] && input$mult>=PLAUS$mult[1] && input$mult<=PLAUS$mult[2] && input$mort==0 && input$hz70=="obs"
    mismatch <- if (isTRUE(TREE_DIRTY)) "WARNING: working tree has uncommitted changes to the engine or model data; results may not match a committed version." else "clean"
    lines <- c(
      "UROGYNECOLOGY WORKFORCE REPLACEMENT EXPLORER  |  REVIEWER ANALYSIS PACKET",
      paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
      paste0("App commit: ", APP_GIT_COMMIT, "    Analytic-engine commit: ", ENGINE_COMMIT, "    (", mismatch, ")"),
      paste0("Model-data SHA-256 (urps_model_data.R): ", MODELDATA_SHA),
      paste0("Random seed: ", MC_SEED, "    Monte Carlo draws: ", q$draws),
      "",
      "SCENARIO:",
      sprintf("  Selected: %s   Status: %s", input$preset, if (prespec) "PRESPECIFIED" else if (modified) "MODIFIED/EXPLORATORY" else "STRESS/EXPLORATORY"),
      sprintf("  Modified from: %s   Changes from preset: %s", if (modified) st$base else "n/a", changes),
      sprintf("  completions=%d  conversion=%d%%  departure_multiplier=%.1f  window=%s  hz70=%s  mortality=%d%%  entry_age=%d  horizon=%d",
              input$comp, input$conv, input$mult, input$win, input$hz70, input$mort, entry_age(), input$horizon),
      "",
      "MODEL (deterministic; identical to wc_project in R/workforce_cliff_engine.R):",
      "  departures_year = sum(count_age * hazard_band(age)) + extra_deaths; survivors age +1;",
      "  entrants added at entry age; proportional mortality drain. ratio = (completions*conversion)/mean_departures.",
      "  Monte Carlo: hazard_band ~ Beta(events+0.5, PY-events+0.5); graduates bootstrap-resampled.",
      "  Interval = PARAMETER uncertainty only (not year-to-year process noise).",
      "",
      "INPUT PROVENANCE (quantity | value | source | date/version | category):",
      "  Active workforce | 1,339 | ABOG + ABU rosters | 2026-07-14 ABU scrape | Observed",
      "  Fellowship completions | 61,66,63,66 | ACGME Data Resource Book | recent 4 AY | Observed",
      "  Departure hazards | age-band | Medicare/NPPES/ABMS consensus | study window | Estimated",
      "  Conversion | user | not observed | n/a | Assumption",
      "  Additional mortality | user | SSA 2020 period life table | 2020 | Assumption",
      "",
      "RESULTS:",
      sprintf("  Effective entrants: %.1f/yr   Mean departures: %.1f/yr   Ratio: %.2f", m$entrants_eff, m$avg_dep, m$ratio),
      sprintf("  Projected %d (model finding): %d (%+d, %+.1f%%)", 2025 + input$horizon, round(m$proj), round(m$grow), m$grow_pct),
      sprintf("  Monte Carlo 95%% ratio: %.2f to %.2f   final: %d to %d   declining draws: %d/%d", q$ratio_lo, q$ratio_hi, round(q$final_lo), round(q$final_hi), q$n_decline, q$draws),
      sprintf("  Reverse break-even: departures x%.1f, or completions < %.0f/yr, or conversion < %.0f%%.", m$ratio, be_comp, be_conv),
      "",
      "PROJECTION TABLE (year  active  departures):",
      paste0("  ", 2025 + 0:input$horizon, "  ", round(m$traj), c("", paste0("  dep=", sprintf("%.1f", m$dep_yr)))),
      "",
      "AGE / DEPARTURE STRUCTURE (band  N  hazard  exp.dep  %dep):",
      paste0("  ", sprintf("%-6s N=%4d  hz=%.4f  expdep=%.1f  %.0f%%", at$band, round(at$n), at$hazard, at$exp_dep, at$pct_dep)),
      "",
      "CITATIONS:",
      "  ACGME Data Resource Book (fellowship completions).",
      "  American Board of Obstetrics and Gynecology certification records.",
      "  American Board of Urology public verification portal (portal.abu.org), scraped 2026-07-14.",
      "  Social Security Administration Period Life Table, 2020.",
      "  J Am Coll Surg 2026 (national surgeon attrition benchmark, 1.5-1.7%/yr).",
      "",
      "SESSION INFO:", paste0("  ", utils::capture.output(print(utils::sessionInfo()))))
    writeLines(lines, file)
  }
  output$dl <- downloadHandler(function() sprintf("urps_scenario_h%dy.csv", input$horizon), scenario_csv)
  output$dl2 <- downloadHandler(function() sprintf("urps_scenario_h%dy.csv", input$horizon), scenario_csv)
  output$packet <- downloadHandler(function() sprintf("urps_analysis_packet_%s.txt", format(Sys.time(), "%Y%m%d_%H%M%S")), analysis_packet)
  output$packet2 <- downloadHandler(function() sprintf("urps_analysis_packet_%s.txt", format(Sys.time(), "%Y%m%d_%H%M%S")), analysis_packet)
  output$dl_note <- renderUI(HTML(sprintf("<div style='color:#777;font-size:12px;margin-top:8px;'>App commit %s, engine commit %s. The packet flags a mismatch if the working tree is dirty.</div>", APP_GIT_COMMIT, ENGINE_COMMIT)))
}

# The validation gate decides which UI/server the app runs. A failed invariant
# yields the failure screen and an inert server, so results are never presented.
if (!VALIDATION$ok) base::message("[app] MODEL VALIDATION FAILED: ", paste(VALIDATION$failures, collapse = " | "))
ui <- if (VALIDATION$ok) main_ui else fail_ui
server <- if (VALIDATION$ok) main_server else function(input, output, session) {}
shinyApp(ui, server)
