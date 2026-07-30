#!/usr/bin/env Rscript
# ==============================================================================
# URPS baseline scenario analysis (contract v3.0.0) -- SCIENTIFICALLY CONTROLLED
#
# Separates two deliverables that must NOT be conflated:
#   (1) PRESERVATION  -- the frozen published 1,295 projection, retained EXACTLY
#       and NOT recalculated (reproducibility evidence, not a causal comparison).
#   (2) CONTROLLED SENSITIVITY -- every scenario run through cliff's ACTUAL
#       wc_project() engine with identical hazards, entrant assumption, Monte
#       Carlo settings, and seed, so baseline count vs cohort age-composition
#       effects can be separated.
#
# Uses the REAL wc_project() (loaded verbatim from R/workforce_cliff_engine.R via
# wc_engine_loader.R; proven identical in test-wc-engine-equivalence.R) -- NOT a
# reimplementation. Ages are an ESTIMATED age proxy (age_proxy_from_cert), never
# observed age. Writes ONLY to scripts/urps_baseline_scenarios/; never touches
# data/workforce_projections_consolidated.csv.
# ==============================================================================
find_root <- function() {
  if (requireNamespace("here", quietly = TRUE)) return(here::here())
  d <- normalizePath(getwd(), winslash = "/")
  for (i in 1:8) { if (file.exists(file.path(d, "DESCRIPTION"))) return(d)
                   p <- dirname(d); if (identical(p, d)) break; d <- p }
  getwd()
}
root <- find_root()
sdir <- file.path(root, "scripts", "urps_baseline_scenarios")
source(file.path(sdir, "wc_engine_loader.R"))
eng        <- load_real_wc_engine(file.path(root, "R", "workforce_cliff_engine.R"))
wc_project <- eng$wc_project                     # cliff's ACTUAL engine function
ages_tbl   <- utils::read.csv(file.path(sdir, "urps_cohort_ages_v3.0.0.csv"), stringsAsFactors = FALSE)

# ---- fixed model settings (reported in every row) ---------------------------
GRAD_URPS      <- c(61, 66, 63, 66)              # OB/GYN+urology completers AY2020-24
ENTRANTS       <- mean(GRAD_URPS)                # 64
BAND_LABELS    <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
BAND_EV        <- c(13.058, 2.853, 3.508, 4.002, 5.192, 4.388, 0)
BAND_PY        <- c(3854, 973, 811, 488, 221, 53, 3)
HZ_POINT       <- setNames(ifelse(BAND_PY > 0, BAND_EV / BAND_PY, NA), BAND_LABELS)
HAZARD_VERSION <- "fully_obs (BAND_EV/BAND_PY, 2016-2021 primary window)"
ENGINE_VERSION <- "R/workforce_cliff_engine.R::wc_project (loaded verbatim)"
AGE_PROXY      <- "age_proxy_from_cert (certification-timing-derived; ESTIMATED, not observed)"
ENTRANT_ASSUMP <- sprintf("mean(GRAD_URPS)=%g/yr; MC bootstraps GRAD_URPS", ENTRANTS)
SEED           <- 20260718L
DRAWS          <- 2000L
TARGET_YEAR    <- 2029L

# ---- cohort builders (age proxy -> integer age vector) ----------------------
age_vec <- function(counts) rep(ages_tbl$age_proxy, counts)
# largest-remainder scaling of an age-band count vector to an EXACT integer total
scale_to <- function(counts, total) {
  p <- counts / sum(counts) * total; fl <- floor(p); r <- total - sum(fl)
  if (r > 0) { ord <- order(p - fl, decreasing = TRUE); fl[ord[seq_len(r)]] <- fl[ord[seq_len(r)]] + 1L }
  as.integer(fl)
}

# ---- the ACTUAL engine: deterministic + Monte Carlo (published uncertainty) --
# MC uncertainty model = mc_replicate() specialized to fully_obs/mult=1/obs/
# extra_deaths=0: band hazards ~ Beta(ev+0.5, py-ev+0.5) (py==0 -> max), entrants
# bootstrapped from GRAD_URPS. The recurrence is the REAL wc_project().
run_engine <- function(ages, horizon) {
  det <- wc_project(ages, entrants = ENTRANTS, hz = HZ_POINT, horizon = horizon)
  set.seed(SEED)
  fin <- vapply(seq_len(DRAWS), function(i) {
    hz <- stats::rbeta(length(BAND_EV), BAND_EV + 0.5, pmax(BAND_PY - BAND_EV, 0) + 0.5)
    hz[BAND_PY == 0] <- max(hz[BAND_PY > 0]); hz <- setNames(pmin(1, hz), BAND_LABELS)
    ent <- mean(sample(GRAD_URPS, length(GRAD_URPS), replace = TRUE))
    wc_project(ages, entrants = ent, hz = hz, horizon = horizon)$active_2029
  }, numeric(1))
  base <- length(ages); avg_ret <- det$departures_4yr / horizon
  list(baseline = base, projected = det$active_2029, avg_annual_retirements = avg_ret,
       replacement_ratio = ENTRANTS / avg_ret, sd = stats::sd(fin),
       lo = unname(stats::quantile(fin, .025)), hi = unname(stats::quantile(fin, .975)))
}

meta_row <- function(id, status, source_artifact, source_year, index_year, horizon,
                     age_method, s, frozen = FALSE) data.frame(
  scenario_id = id, observed_or_synthetic = status, source_artifact = source_artifact,
  source_year = source_year, index_year = index_year, target_year = TARGET_YEAR,
  horizon = horizon, baseline_count = s$baseline, age_proxy_method = age_method,
  entrant_assumption = ENTRANT_ASSUMP, hazard_version = HAZARD_VERSION,
  engine_version = if (frozen) "frozen published run (not recalculated)" else ENGINE_VERSION,
  seed = if (frozen) NA_integer_ else SEED, draw_count = if (frozen) NA_integer_ else DRAWS,
  projected_count = round(s$projected, 1), ci_lower = round(s$lo), ci_upper = round(s$hi),
  sd = round(s$sd, 2), avg_annual_retirements = round(s$avg_annual_retirements, 2),
  replacement_ratio = round(s$replacement_ratio, 2),
  frozen_or_recalculated = if (frozen) "frozen" else "recalculated", stringsAsFactors = FALSE)

# ==============================================================================
# TABLE 1 -- PUBLISHED-RESULT PRESERVATION (frozen; NOT recalculated)
# ==============================================================================
frozen <- utils::read.csv(file.path(root, "data", "workforce_projections_consolidated.csv"),
                          stringsAsFactors = FALSE)
u <- frozen[frozen$subspecialty_abbrev == "URPS", ]
stopifnot(nrow(u) == 1L)
LEGACY_N <- as.integer(u$baseline_2025)          # 1295, read from the frozen record (not hardcoded)
legacy_frozen <- list(baseline = LEGACY_N, projected = as.numeric(u$projected_2029),
  avg_annual_retirements = as.numeric(u$avg_annual_retirements),
  replacement_ratio = as.numeric(u$replacement_ratio), sd = as.numeric(u$sd_2029),
  lo = as.numeric(u$ci95_lower), hi = as.numeric(u$ci95_upper))
table1 <- meta_row("legacy_frozen", "observed (published)", "frozen SGS projection CSV",
  "2023->2025 model", 2025L, 4L, "published legacy (primary-cert reconciliation)",
  legacy_frozen, frozen = TRUE)
utils::write.csv(table1, file.path(sdir, "table1_published_preservation_v3.0.0.csv"), row.names = FALSE)

# ==============================================================================
# TABLE 2 -- CONTROLLED SENSITIVITY (all via the REAL engine; index year honest)
# ==============================================================================
active_ages <- age_vec(ages_tbl$n_active_2023)   # 1306, observed 2023 active
roster_ages <- age_vec(ages_tbl$n_roster_2025)   # 1339, observed 2025 roster
legacy_syn  <- age_vec(scale_to(ages_tbl$n_active_2023, LEGACY_N))  # synthetic 1295, 2023-active structure

table2 <- rbind(
  meta_row("legacy_rerun", "SYNTHETIC (count-scaled from 2023-active age structure)",
           "isochrones v3.0.0 (age structure) + frozen count", "2023 (synthetic)", 2023L, 6L,
           AGE_PROXY, run_engine(legacy_syn, 6L)),
  meta_row("active_2023", "observed", "isochrones v3.0.0 provider snapshot",
           "2023", 2023L, 6L, AGE_PROXY, run_engine(active_ages, 6L)),
  meta_row("roster_2025", "observed (2025-indexed, NOT a 2023 baseline)",
           "isochrones v3.0.0 provider snapshot", "2025", 2025L, 4L, AGE_PROXY,
           run_engine(roster_ages, 4L)))
utils::write.csv(table2, file.path(sdir, "table2_controlled_sensitivity_v3.0.0.csv"), row.names = FALSE)

# ==============================================================================
# TABLE 3 -- COUNT vs AGE-COMPOSITION DECOMPOSITION
# controlled synthetic experiment at a COMMON 2023 origin / horizon 6 (target 2029)
# ==============================================================================
ref_active  <- run_engine(active_ages, 6L)                                   # n=1306, active structure
count_only  <- run_engine(legacy_syn, 6L)                                    # n=1295, active structure
age_only    <- run_engine(age_vec(scale_to(ages_tbl$n_roster_2025, sum(ages_tbl$n_active_2023))), 6L)  # n=1306, roster structure
combined    <- run_engine(roster_ages, 6L)                                   # n=1339, roster structure
decomp_row <- function(id, note, s) data.frame(
  contrast = id, note = note, baseline_count = s$baseline, index_year = 2023L, horizon = 6L,
  target_year = TARGET_YEAR, projected_count = round(s$projected, 1),
  avg_annual_retirements = round(s$avg_annual_retirements, 2),
  age_structure = if (grepl("roster", id)) "2025-roster" else "2023-active",
  status = "SYNTHETIC controlled (common 2023 origin; not observed estimates)",
  stringsAsFactors = FALSE)
table3 <- rbind(
  decomp_row("reference_active_2023", "2023-active age structure, reference count", ref_active),
  decomp_row("count_effect",     "reduced count, SAME 2023-active structure (isolates count)", count_only),
  decomp_row("age_effect_roster",     "reference count, 2025-roster structure (isolates age composition)", age_only),
  decomp_row("combined_roster",  "roster count, 2025-roster structure (count + age)", combined))
table3$d_projected_vs_ref <- round(table3$projected_count - ref_active$projected, 1)
table3$d_avg_ret_vs_ref   <- round(table3$avg_annual_retirements - ref_active$avg_annual_retirements / 1, 2)
utils::write.csv(table3, file.path(sdir, "table3_count_age_decomposition_v3.0.0.csv"), row.names = FALSE)

# ==============================================================================
# TABLE 4 -- SAME-HORIZON VIEW (all index 2025, horizon 4)
# Removes the horizon confound: the 2023 stocks are ADOPTED as the 2025 baseline
# -- the frozen model's OWN convention (it uses a 2023-derived stock as
# baseline_2025). All three are then projected at horizon 4 to 2029, so they are
# directly comparable to each other AND to the frozen published result (which is
# also index 2025, horizon 4). The 2023 stocks here are a modelling choice, not
# an observed 2025 stock (only the roster is a genuine 2025 stock).
# ==============================================================================
table4 <- rbind(
  meta_row("legacy_h4", "SYNTHETIC (count-scaled 2023-active structure; adopted as 2025 baseline)",
           "isochrones v3.0.0 (age structure) + frozen count", "2023->2025 (synthetic)", 2025L, 4L,
           AGE_PROXY, run_engine(legacy_syn, 4L)),
  meta_row("active_h4", "observed 2023 stock adopted as the 2025 baseline (frozen-model convention)",
           "isochrones v3.0.0 provider snapshot", "2023->2025", 2025L, 4L, AGE_PROXY,
           run_engine(active_ages, 4L)),
  meta_row("roster_h4", "observed 2025 roster (genuine 2025 stock)",
           "isochrones v3.0.0 provider snapshot", "2025", 2025L, 4L, AGE_PROXY,
           run_engine(roster_ages, 4L)))
utils::write.csv(table4, file.path(sdir, "table4_same_horizon_h4_v3.0.0.csv"), row.names = FALSE)

# ---- fail-closed: the frozen published projection must be untouched ----------
FROZEN_LEGACY_BASELINE <- 1295L  # ssot-ok: legacy frozen SGS projection cohort
stopifnot("frozen baseline changed!"  = LEGACY_N == FROZEN_LEGACY_BASELINE,
          "frozen endpoint changed!"  = abs(as.numeric(u$projected_2029) - 1505.367) < 0.01,
          "age-band counts must sum to baseline" =
            length(active_ages) == sum(ages_tbl$n_active_2023) && length(roster_ages) == sum(ages_tbl$n_roster_2025) &&
            length(legacy_syn) == LEGACY_N)

cat("== TABLE 1 (preservation) ==\n");           print(table1[, c("scenario_id","baseline_count","projected_count","frozen_or_recalculated")], row.names = FALSE)
cat("\n== TABLE 2 (controlled sensitivity) ==\n"); print(table2[, c("scenario_id","observed_or_synthetic","index_year","horizon","baseline_count","projected_count","avg_annual_retirements")], row.names = FALSE)
cat("\n== TABLE 3 (decomposition) ==\n");          print(table3[, c("contrast","baseline_count","age_structure","projected_count","avg_annual_retirements","d_projected_vs_ref")], row.names = FALSE)
cat("\n== TABLE 4 (same-horizon view: all index 2025, horizon 4) ==\n"); print(table4[, c("scenario_id","index_year","horizon","baseline_count","projected_count","ci_lower","ci_upper","avg_annual_retirements")], row.names = FALSE)
cat(sprintf("   (frozen published, same index/horizon, for reference: baseline %d -> projected %.1f)\n", LEGACY_N, as.numeric(u$projected_2029)))
