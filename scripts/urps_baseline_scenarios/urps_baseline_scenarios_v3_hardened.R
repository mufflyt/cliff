#!/usr/bin/env Rscript
# ==============================================================================
# URPS baseline-scenario comparison, HARDENED for scientific comparability.
#
# Fixes the earlier three-row table's comparability defects:
#   * every rerun scenario goes through the REAL engine wc_project()
#     (R/workforce_cliff_engine.R) -- no reimplemented recurrence;
#   * a legacy_1295 cohort is RE-RUN through the same engine (distinct from the
#     frozen published row), using a documented best-effort reconstruction;
#   * horizon is 4 for every rerun; each row states its own index/target year;
#   * the 2025 roster (1339) is labeled a 2025-indexed cohort, never a 2023 baseline;
#   * age is an ESTIMATED PROXY (age_proxy_from_cert), never "real age";
#   * every output row carries full provenance;
#   * a count-vs-age-composition decomposition is produced;
#   * an equivalence test proves the old reimplementation matched wc_project.
#
# Writes ONLY to scripts/urps_baseline_scenarios/. Never touches
# data/workforce_projections_consolidated.csv (the frozen published record).
#
# LEGACY COHORT RECONSTRUCTION (best-effort; decision 1). The published 1,295
# (1,031 ABOG + 264 ABU) used an older ABU scrape (270 net-new identified, 6
# non-datable excluded -> 264). The tracked v3.0.0 rosters carry 270 net-new ABU
# all with a datable cert year, so the exact 6-exclusion is not reproducible. The
# reproducible rule used here is:
#   ABOG in_model_baseline (1,031) + ABU status=="net-new (in model)" (270)
#   = 1,301, ages = age_proxy_from_cert.
# This is +6 vs the published 1,295 (the older scrape's 6 non-datable exclusions
# are not encoded in the tracked rosters). It is a controlled SAME-ENGINE rerun,
# NOT a reproduction of the published number; the authoritative legacy result is
# the frozen published row (Table 1).
# ==============================================================================
suppressPackageStartupMessages({ library(here) })
root <- here::here()
source(file.path(root, "R", "workforce_cliff_engine.R"))   # wc_project, wc_haz_for, WC_* constants
sdir <- file.path(root, "scripts", "urps_baseline_scenarios")

# ---- published, frozen model parameters (documented provenance) --------------
ENTRANTS   <- as.numeric(WC_ENTRANTS[["URPS"]])   # 64 = mean URPS completers AY2020-24 (WC_GRAD$URPS)
ENTRY_AGE  <- WC_ENTRY_AGE
HORIZON    <- 4L                                   # decision 3: horizon 4 for every rerun
AGE_REF    <- WC_REF_YEAR                           # age_proxy_from_cert reference year (2024)
MC_SEED    <- 20260718L                             # published bootstrap seed
MC_DRAWS   <- 4000L
HAZARD_VERSION <- "pooled GO+URPS age-band, events/PY 2016-2021 (primary-cert basis)"
ENGINE_VERSION <- "wc_project @ R/workforce_cliff_engine.R"
AGE_PROXY_METHOD <- "age_proxy_from_cert (ESTIMATED age from certification timing; NOT observed age)"

# published age-band retirement hazards (events / person-years), keyed by band label
BAND_EV <- c(13.058, 2.853, 3.508, 4.002, 5.192, 4.388, 0)
BAND_PY <- c(3854, 973, 811, 488, 221, 53, 3)
HZ      <- setNames(ifelse(BAND_PY > 0, BAND_EV / BAND_PY, 0), WC_BAND_LABELS)

ages_tbl <- utils::read.csv(file.path(sdir, "urps_cohort_ages_v3.0.0.csv"), stringsAsFactors = FALSE)
expand   <- function(col) rep(ages_tbl$age, times = ages_tbl[[col]])

# ---- canonical stochastic layer (decision 2): Binomial draws mirroring --------
# wc_project's recurrence EXACTLY (same entry logic + wc_haz_for), integer counts.
wc_project_mc <- function(ages, entrants, hz, horizon, seed, draws) {
  count0 <- table(ages); av0 <- as.integer(names(count0)); n0 <- as.integer(count0)
  set.seed(seed)
  fin <- vapply(seq_len(draws), function(i) {
    av <- av0; n <- n0
    for (h in seq_len(horizon)) {
      hzz <- wc_haz_for(av, hz); ret <- stats::rbinom(length(n), size = n, prob = hzz)
      sv <- n - ret; av2 <- av + 1L; ix <- match(ENTRY_AGE, av2)
      if (is.na(ix)) { av2 <- c(av2, ENTRY_AGE); sv <- c(sv, entrants) } else sv[ix] <- sv[ix] + entrants
      av <- av2; n <- sv
    }
    sum(n)
  }, numeric(1))
  fin
}

# ---- run one cohort through the REAL engine, return a full-provenance row -----
run <- function(scenario, ages, index_year, obs_status, source_artifact, source_year, note = "") {
  det  <- wc_project(ages, entrants = ENTRANTS, hz = HZ, horizon = HORIZON)   # REAL engine
  fin  <- wc_project_mc(ages, ENTRANTS, HZ, HORIZON, MC_SEED, MC_DRAWS)
  base <- length(ages); avg_ret <- det$departures_4yr / HORIZON
  data.frame(
    scenario_id = scenario, observed_or_synthetic = obs_status,
    source_artifact = source_artifact, source_year = source_year,
    index_year = index_year, target_year = index_year + HORIZON, horizon = HORIZON,
    baseline_count = base, age_proxy_method = AGE_PROXY_METHOD,
    entrant_assumption = sprintf("%.0f/yr at age %d (URPS completers)", ENTRANTS, ENTRY_AGE),
    hazard_version = HAZARD_VERSION, engine_version = ENGINE_VERSION,
    seed = MC_SEED, mc_draws = MC_DRAWS,
    projected_count = round(det$active_2029, 1),
    ci95_lower = round(stats::quantile(fin, .025)), ci95_upper = round(stats::quantile(fin, .975)),
    sd = round(stats::sd(fin), 2),
    pct_change = round(100 * (det$active_2029 - base) / base, 2),
    avg_annual_retirements = round(avg_ret, 2), replacement_ratio = round(ENTRANTS / avg_ret, 2),
    frozen_or_recalculated = "recalculated", note = note, stringsAsFactors = FALSE)
}

# ============================ TABLE 1: frozen preservation =====================
frozen <- utils::read.csv(file.path(root, "data", "workforce_projections_consolidated.csv"),
                          stringsAsFactors = FALSE)
u <- frozen[frozen$subspecialty_abbrev == "URPS", ]; stopifnot(nrow(u) == 1L)
FROZEN_BASELINE <- 1295L; FROZEN_ENDPOINT <- 1505.367   # ssot-ok: FROZEN_BASELINE is the legacy frozen SGS projection cohort (read-only, preserved)
stopifnot("frozen baseline changed"  = as.integer(u$baseline_2025) == FROZEN_BASELINE,
          "frozen endpoint changed"  = abs(as.numeric(u$projected_2029) - FROZEN_ENDPOINT) < 0.01)
table1 <- data.frame(
  scenario_id = "published_legacy_1295", observed_or_synthetic = "published (frozen)",   # ssot-ok: scenario label, not a baseline source (frozen row read from the SSOT CSV)
  source_artifact = "data/workforce_projections_consolidated.csv", source_year = 2025L,
  index_year = 2025L, target_year = 2029L, horizon = 4L,
  baseline_count = as.integer(u$baseline_2025), age_proxy_method = "as published (SGS)",
  entrant_assumption = "as published", hazard_version = "as published",
  engine_version = "frozen archival Monte Carlo (NOT re-run)",
  seed = NA_integer_, mc_draws = NA_integer_,
  projected_count = as.numeric(u$projected_2029),
  ci95_lower = as.numeric(u$ci95_lower), ci95_upper = as.numeric(u$ci95_upper), sd = as.numeric(u$sd_2029),
  pct_change = as.numeric(u$percent_change), avg_annual_retirements = as.numeric(u$avg_annual_retirements),
  replacement_ratio = as.numeric(u$replacement_ratio),
  frozen_or_recalculated = "frozen",
  note = "Published legacy result; retained exactly and NOT recalculated. Reproducibility evidence, not a controlled comparison row.",
  stringsAsFactors = FALSE)

# ============================ TABLE 2: controlled sensitivity ==================
# All rows through the SAME engine (wc_project), horizon 4, same hazards/entrants/seed.
table2 <- rbind(
  run("legacy_primarycert_rerun", expand("n_legacy_primarycert"), index_year = 2025L,
      obs_status = "observed cohort (best-effort legacy reconstruction)",
      source_artifact = "data/abog+abu_all_urps_ENRICHED_2026-07-22.csv", source_year = 2022L,
      note = "Best-effort legacy cohort = ABOG in_model (1031) + ABU net-new (270). N=1301, +6 vs published 1295 (old scrape's 6 non-datable exclusions not encoded in tracked rosters)."),   # ssot-ok: provenance note describing the legacy reconstruction
  run("active_2023_1306", expand("n_active_2023"), index_year = 2023L,   # ssot-ok: scenario identifier label; the baseline value is computed from the age cohort, not this literal
      obs_status = "observed cohort", source_artifact = "mufflyaccess urps_count(2023,board_certified_active)",
      source_year = 2023L, note = "v3.0.0 URPS-subspecialty-cert active workforce."),
  run("roster_2025_1339", expand("n_roster_2025"), index_year = 2025L,   # ssot-ok: scenario identifier label; the baseline value is computed from the age cohort, not this literal
      obs_status = "observed cohort", source_artifact = "mufflyaccess urps_count(2025,roster_snapshot)",
      source_year = 2025L, note = "2025 roster snapshot; index year 2025, NOT a 2023 baseline."))

# ============================ DECOMPOSITION (count vs age) =====================
# Isolate baseline-count effect from age-composition effect, active_2023 -> roster_2025.
ages_a <- expand("n_active_2023"); ages_r <- expand("n_roster_2025")
Na <- length(ages_a); Nr <- length(ages_r)
# age-proportion vectors
pa <- prop.table(table(factor(ages_a, levels = sort(unique(c(ages_a, ages_r))))))
pr <- prop.table(table(factor(ages_r, levels = sort(unique(c(ages_a, ages_r))))))
avs <- as.integer(names(pa))
det_from <- function(N, p) {                         # rebuild an integer age vector at count N with proportions p
  n <- round(N * as.numeric(p)); v <- rep(avs, times = n)
  wc_project(v, entrants = ENTRANTS, hz = HZ, horizon = HORIZON)
}
d_base  <- det_from(Na, pa)                          # reference: active count + active ages
d_count <- det_from(Nr, pa)                          # COUNT effect only: roster count, active age mix
d_age   <- det_from(Na, pr)                          # AGE effect only: active count, roster age mix
d_both  <- det_from(Nr, pr)                          # COMBINED
dec <- function(lbl, N, mix, d) data.frame(effect = lbl, count = N, age_mix = mix,
  avg_annual_retirements = round(d$departures_4yr / HORIZON, 3),
  projected = round(d$active_2029, 1), stringsAsFactors = FALSE)
decomp <- rbind(
  dec("reference (active count, active ages)",     Na, "active_2023", d_base),
  dec("count-only (roster count, active ages)",    Nr, "active_2023", d_count),
  dec("age-only (active count, roster ages)",      Na, "roster_2025", d_age),
  dec("combined (roster count, roster ages)",      Nr, "roster_2025", d_both))

# ============================ EQUIVALENCE TEST (reimpl vs wc_project) ==========
# The earlier script used a hand-reimplemented recurrence. Prove wc_project and
# that reimplementation agree on controlled inputs (report max abs/rel diff).
band_of_re <- function(age) cut(age, breaks = c(-Inf,45,50,55,60,65,70,Inf), right = FALSE, labels = WC_BAND_LABELS)
haz_for_re <- function(age, hzv){ h <- hzv[match(as.character(band_of_re(age)), WC_BAND_LABELS)]; h[is.na(h)] <- 0; h }
project_det_re <- function(age, n, hzv, entrants = ENTRANTS, horizon = HORIZON, entry = ENTRY_AGE) {
  dep <- 0
  for (h in seq_len(horizon)) { hz <- haz_for_re(age, hzv); dep <- dep + sum(n*hz); sv <- n*(1-hz); a2 <- age+1L
    ix <- match(entry, a2); if (is.na(ix)) { a2 <- c(a2, entry); sv <- c(sv, entrants) } else sv[ix] <- sv[ix]+entrants
    age <- a2; n <- sv }
  list(projected = sum(n), departures = dep)
}
eq_cases <- list(
  list(name="zero-hazard",       ages=rep(c(40,55,68), c(50,30,20)), hz=setNames(rep(0,7),WC_BAND_LABELS), ent=64, hz2=TRUE),
  list(name="zero-entrants",     ages=rep(c(40,55,68), c(50,30,20)), ent=0),
  list(name="age-band-boundary", ages=c(44,45,49,50,54,55,59,60,64,65,69,70,71), ent=64),
  list(name="one-age-band",      ages=rep(48,100), ent=64),
  list(name="active-2023-cohort",ages=ages_a, ent=64),
  list(name="roster-cohort",     ages=ages_r, ent=64))
eq <- do.call(rbind, lapply(eq_cases, function(c) {
  hz <- if (isTRUE(c$hz2)) c$hz else HZ
  for (H in c(1L,4L)) {
    a <- wc_project(c$ages, entrants=c$ent, hz=hz, horizon=H)$active_2029
    tb <- table(c$ages); b <- project_det_re(as.integer(names(tb)), as.numeric(tb), hzv=hz, entrants=c$ent, horizon=H)$projected
    res <- data.frame(case=c$name, horizon=H, wc_project=round(a,6), reimpl=round(b,6),
                      abs_diff=abs(a-b), rel_diff=abs(a-b)/max(1,abs(a)), stringsAsFactors=FALSE)
    if (!exists("acc")) acc <- res else acc <- rbind(acc, res)
  }
  acc
}))
max_abs <- max(eq$abs_diff); max_rel <- max(eq$rel_diff)

# ============================ per-year trajectories (for the shiny overlay) ====
# Deterministic year-by-year active count + per-year MC 95% band, for each
# controlled scenario, plus the published legacy as a straight index->target line.
wc_traj <- function(ages, entrants, hz, horizon) {
  count <- table(ages); av <- as.integer(names(count)); count <- as.numeric(count)
  out <- numeric(horizon + 1L); out[1] <- sum(count)
  for (h in seq_len(horizon)) {
    hzz <- wc_haz_for(av, hz); sv <- count * (1 - hzz)
    av2 <- av + 1L; ix <- match(ENTRY_AGE, av2)
    if (is.na(ix)) { av2 <- c(av2, ENTRY_AGE); sv <- c(sv, entrants) } else sv[ix] <- sv[ix] + entrants
    av <- av2; count <- sv; out[h + 1L] <- sum(count)
  }
  out
}
wc_traj_mc <- function(ages, entrants, hz, horizon, seed, draws) {
  count0 <- table(ages); av0 <- as.integer(names(count0)); n0 <- as.integer(count0)
  set.seed(seed)
  m <- vapply(seq_len(draws), function(i) {
    av <- av0; n <- n0; o <- numeric(horizon + 1L); o[1] <- sum(n)
    for (h in seq_len(horizon)) {
      hzz <- wc_haz_for(av, hz); ret <- stats::rbinom(length(n), size = n, prob = hzz)
      sv <- n - ret; av2 <- av + 1L; ix <- match(ENTRY_AGE, av2)
      if (is.na(ix)) { av2 <- c(av2, ENTRY_AGE); sv <- c(sv, entrants) } else sv[ix] <- sv[ix] + entrants
      av <- av2; n <- sv; o[h + 1L] <- sum(n)
    }
    o
  }, numeric(horizon + 1L))
  data.frame(lo = apply(m, 1, stats::quantile, .025), hi = apply(m, 1, stats::quantile, .975))
}
traj_one <- function(scenario, ages, index_year) {
  det <- wc_traj(ages, ENTRANTS, HZ, HORIZON); ci <- wc_traj_mc(ages, ENTRANTS, HZ, HORIZON, MC_SEED, MC_DRAWS)
  data.frame(scenario_id = scenario, year = index_year + 0:HORIZON,
             active = round(det, 1), ci95_lower = round(ci$lo), ci95_upper = round(ci$hi),
             stringsAsFactors = FALSE)
}
traj <- rbind(
  traj_one("legacy_primarycert_rerun", expand("n_legacy_primarycert"), 2025L),
  traj_one("active_2023_1306",         expand("n_active_2023"),        2023L),   # ssot-ok: scenario identifier label; the trajectory count is computed from the age cohort, not this literal
  traj_one("roster_2025_1339",         expand("n_roster_2025"),        2025L),   # ssot-ok: scenario identifier label; the trajectory count is computed from the age cohort, not this literal
  data.frame(scenario_id = "published_legacy_1295", year = c(2025L, 2029L),   # ssot-ok: scenario label; the frozen values are read from the published record, not this literal
             active = c(FROZEN_BASELINE, FROZEN_ENDPOINT),
             ci95_lower = c(NA, as.numeric(u$ci95_lower)), ci95_upper = c(NA, as.numeric(u$ci95_upper)),
             stringsAsFactors = FALSE))
utils::write.csv(traj, file.path(sdir, "scenario_trajectories.csv"), row.names = FALSE)

# ============================ write outputs ===================================
utils::write.csv(table1, file.path(sdir, "table1_published_preservation.csv"), row.names = FALSE)
utils::write.csv(table2, file.path(sdir, "table2_controlled_sensitivity.csv"), row.names = FALSE)
utils::write.csv(decomp, file.path(sdir, "decomposition_count_vs_age.csv"), row.names = FALSE)
utils::write.csv(eq, file.path(sdir, "engine_equivalence.csv"), row.names = FALSE)

# ============================ detailed provenance =============================
# A machine-readable provenance record for the scenario analysis: producing code,
# engine, SSOT contract + cells, input hashes, run parameters, the exact cohort-
# definition rules, and output hashes. Follows the codebase provenance contract
# (CLAUDE.md #18 cache provenance / #19 trust-a-number): input fingerprints,
# code_fingerprint, output content shas, tool versions, and run provenance.
.sha <- function(p) if (file.exists(p) && requireNamespace("digest", quietly = TRUE))
  digest::digest(file = p, algo = "sha256") else NA_character_
.git <- function(...) tryCatch(system2("git", c("-C", root, ...), stdout = TRUE, stderr = FALSE),
                               error = function(e) character(0))
this_script <- file.path(sdir, "urps_baseline_scenarios_v3_hardened.R")
engine_file <- file.path(root, "R", "workforce_cliff_engine.R")
in_ages   <- file.path(sdir, "urps_cohort_ages_v3.0.0.csv")
in_frozen <- file.path(root, "data", "workforce_projections_consolidated.csv")
in_abog   <- file.path(root, "data", "abog_all_urps_ENRICHED_2026-07-22.csv")
in_abu    <- file.path(root, "data", "abu_all_urps_ENRICHED_2026-07-22.csv")
mfa_ver <- tryCatch(as.character(utils::packageVersion("mufflyaccess")), error = function(e) NA_character_)
mfa_ctr <- tryCatch(mufflyaccess::urps_provenance()$contract_version,   error = function(e) NA_character_)
mfa_src <- tryCatch(mufflyaccess::urps_provenance()$source_git_commit,  error = function(e) NA_character_)
served  <- tryCatch(as.integer(mufflyaccess::urps_count(2023, "board_certified_active", "national", TRUE)),
                    error = function(e) NA_integer_)
out_hash <- function(f) list(file = f, sha256 = .sha(file.path(sdir, f)))

prov <- list(
  schema       = "cliff-urps-scenario-provenance/1",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  producer = list(
    script = "scripts/urps_baseline_scenarios/urps_baseline_scenarios_v3_hardened.R",
    script_sha256 = .sha(this_script),
    git_commit = .git("rev-parse", "HEAD")[1],
    git_tree_dirty = length(.git("status", "--porcelain")) > 0),
  engine = list(
    file = "R/workforce_cliff_engine.R", file_sha256 = .sha(engine_file),
    fn = "wc_project", loader = "wc_engine_loader.R (pure projection defs only)",
    version = ENGINE_VERSION,
    equivalence_vs_reimplementation = list(max_abs = max_abs, max_rel = max_rel)),
  ssot = list(
    package = "mufflyaccess", installed_version = mfa_ver, contract_version = mfa_ctr,
    artifact_source_commit = mfa_src,
    analysis_cells = list(active_2023_national = 1306L, roster_2025_national = 1339L),   # ssot-ok: provenance: records the v3.0.0 SSOT cells verified against mufflyaccess
    ssot_tie_verified = isTRUE(served == 1306L),   # ssot-ok: provenance: verifies the installed SSOT serves the v3.0.0 cell
    note = if (isTRUE(served == 1306L)) "installed mufflyaccess serves the v3.0.0 cells"   # ssot-ok: provenance: notes whether the installed SSOT matches v3.0.0
           else sprintf("installed mufflyaccess serves %s (pre-v3.0.0); analysis cells taken from the v3.0.0 provider-snapshot age file, verified once 0.7.x installs", served)),
  parameters = list(
    entrants_per_year = ENTRANTS, entry_age = ENTRY_AGE, horizon = HORIZON,
    age_proxy_reference_year = AGE_REF, mc_seed = MC_SEED, mc_draws = MC_DRAWS,
    hazard_version = HAZARD_VERSION, band_labels = WC_BAND_LABELS,
    band_events = BAND_EV, band_person_years = BAND_PY, band_hazard = unname(HZ)),
  cohorts = list(
    legacy_primarycert_rerun = list(
      n = sum(ages_tbl$n_legacy_primarycert), age_basis = "age_proxy_from_cert (estimated proxy)",
      rule = "ABOG in_model_baseline (1031) + ABU status=='net-new (in model)' (270)",
      source = "data/{abog,abu}_all_urps_ENRICHED_2026-07-22.csv",
      caveat = "best-effort reconstruction; +6 vs published 1295 (old scrape's 6 non-datable exclusions not encoded in the tracked rosters); authoritative legacy result is the frozen published row"),   # ssot-ok: provenance caveat text; the legacy value is read from the frozen record
    active_2023_1306 = list(   # ssot-ok: provenance cohort key; the count is summed from the age cohort, not this literal
      n = sum(ages_tbl$n_active_2023), age_basis = "age_proxy_from_cert (estimated proxy)",
      rule = "isochrones v3.0.0 provider snapshot, active_2023 == TRUE",
      source = "mufflyaccess urps_count(2023, board_certified_active, national, TRUE)"),
    roster_2025_1339 = list(   # ssot-ok: provenance cohort key; the count is summed from the age cohort, not this literal
      n = sum(ages_tbl$n_roster_2025), age_basis = "age_proxy_from_cert (estimated proxy)",
      rule = "isochrones v3.0.0 provider snapshot, 2025 roster (in_model_baseline)",
      source = "mufflyaccess urps_count(2025, roster_snapshot, national, TRUE)")),
  inputs = list(
    list(name = "cohort_ages",       path = "scripts/urps_baseline_scenarios/urps_cohort_ages_v3.0.0.csv", sha256 = .sha(in_ages)),
    list(name = "frozen_projection", path = "data/workforce_projections_consolidated.csv",                 sha256 = .sha(in_frozen)),
    list(name = "abog_roster",       path = "data/abog_all_urps_ENRICHED_2026-07-22.csv",                  sha256 = .sha(in_abog)),
    list(name = "abu_roster",        path = "data/abu_all_urps_ENRICHED_2026-07-22.csv",                   sha256 = .sha(in_abu))),
  outputs = lapply(c("table1_published_preservation.csv", "table2_controlled_sensitivity.csv",
                     "decomposition_count_vs_age.csv", "scenario_trajectories.csv",
                     "engine_equivalence.csv", "table_evidence_supporting_scenarios.csv"), out_hash))
jsonlite::write_json(prov, file.path(sdir, "scenario_provenance.json"),
                     pretty = TRUE, auto_unbox = TRUE, digits = 10, null = "null")
cat("wrote scenario_provenance.json (", length(prov$inputs), "inputs,", length(prov$outputs), "outputs hashed)\n")

cat("== equivalence wc_project vs reimplementation: max abs =", signif(max_abs,3),
    " max rel =", signif(max_rel,3), "==\n")
cat("\n== TABLE 1 (frozen published, preserved) ==\n")
print(table1[, c("scenario_id","baseline_count","projected_count","replacement_ratio","frozen_or_recalculated")], row.names=FALSE)
cat("\n== TABLE 2 (controlled, same engine, horizon 4) ==\n")
print(table2[, c("scenario_id","index_year","target_year","baseline_count","projected_count","avg_annual_retirements","replacement_ratio")], row.names=FALSE)
cat("\n== DECOMPOSITION (count vs age composition) ==\n")
print(decomp, row.names=FALSE)
