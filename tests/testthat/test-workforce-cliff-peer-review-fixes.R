# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Semantic + adversarial regression tests for the workforce-cliff peer-review fixes.
# Each test encodes ONE reviewer issue and FAILS if the defect reappears.
#   Semantic  = the manuscript/supplement prose must (not) assert specific things.
#   Adversarial = the committed data artifacts must reproduce the headline and obey
#                 the arithmetic identities the prose claims.
# Run: Rscript -e 'testthat::test_file("tests/testthat/test-workforce-cliff-peer-review-fixes.R")'
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
library(testthat)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

.root <- tryCatch(here::here(), error = function(e) {
  d <- normalizePath(".")
  while (!file.exists(file.path(d, "manuscript", "manuscript_WORKFORCE_CLIFF.Rmd")) &&
         dirname(d) != d) d <- dirname(d)
  d
})
MAIN <- file.path(.root, "manuscript", "manuscript_WORKFORCE_CLIFF.Rmd")
SUPP <- file.path(.root, "manuscript", "supplement_WORKFORCE_CLIFF.Rmd")
DATA <- file.path(.root, "data")
rd   <- function(p) paste(readLines(p, warn = FALSE), collapse = "\n")
main <- rd(MAIN); supp <- rd(SUPP); both <- paste(main, supp)
csv  <- function(f) read.csv(file.path(DATA, f), stringsAsFactors = FALSE, check.names = FALSE)
has  <- function(txt, pat) grepl(pat, txt, ignore.case = TRUE, perl = TRUE)

# ---- #1 uniform 3-year rule; no stale four-year-GO / subspecialty threshold -------
test_that("#1 no stale four-year-GO or subspecialty-specific inactivity-threshold assertion", {
  expect_false(has(both, "four years of\\s+inactivity for gyn"))
  expect_false(has(both, "Gynecologic Oncology 4 yr"))
  expect_false(has(both, "Subspecialty-specific inactivity thresholds accounted for"))
  # the assertion that GO/MIGS need four years must not appear
  expect_false(has(both, "four years of\\s+inactivity for gynecologic oncology and for migs"))
  # The uniform three-year rule must be stated somewhere in the document set.
  # It was required of the main text when Methods carried the full departure
  # definition; the Green Journal restructuring (f87ac53) condensed Methods from
  # 8,405 to 2,702 words and moved the audit detail to the SDC, so the statement
  # now lives in the supplement. The reviewer issue is that the rule is stated
  # and the stale four-year claim is absent -- both still hold. Which document
  # carries it is an editorial choice, so assert against the pair.
  expect_true(has(both, "uniform (cessation rule|three-year)"))
  expect_true(has(supp, "uniform three-year"))
})

# ---- #2 primary anchor list excludes PECOS / "enrollment" -------------------------
test_that("#2 the primary anchor list is exactly PartB/PartD/NPPES/ABMS, not PECOS/enrollment", {
  expect_false(has(main, "enrollment, certification, or NPPES"))
  expect_false(has(main, "prescribing, enrollment, or certification"))
  # anchor must be spelled out as the four qualifying sources at least once
  # reworded: the same four anchors; the condensed Methods reorder them and
  # drop the expanded NPPES name, which is spelled out earlier in the sentence
  expect_true(has(main, "Medicare Part B or Part D cessation, permanent deactivation, or ABMS lapse"))
  # supplement pseudocode must exclude PECOS + Open Payments from anchors
  expect_true(has(supp, "PECOS and Open Payments are NOT anchors"))
})

# ---- #3 Step 1 fully specified as Boolean pseudocode ------------------------------
test_that("#3 Step 1 classification rule is given as explicit pseudocode", {
  expect_true(has(supp, "candidate_departure"))
  expect_true(has(supp, "primary_departure"))
  expect_true(has(supp, "anchor_signals"))
  # weights explicitly said to pick the YEAR, not a status threshold
  expect_true(has(supp, "weights.{0,40}(pick|resolve).{0,40}(year|when)"))
  expect_true(has(supp, "no\\s+(summed-weight|numeric)\\s+threshold"))
})

# ---- #4 hazards described as POOLED, consistently, with disclosure ----------------
test_that("#4 hazard is described as pooled (not specialty-specific) in main + supplement", {
  expect_true(has(main, "pooled age-band (departure )?hazard"))
  expect_true(has(supp, "pooled\\*\\* age-band hazard|pooled age-band hazard"))
  # the OLD claim of separately-fitted subspecialty-specific hazards must be gone
  expect_false(has(main, "Subspecialty-specific age-band departure hazards were derived"))
  # the pooled-vs-unpooled appendix must be referenced and exist
  expect_true(has(main, "Appendix S6b"))
  expect_true(has(supp, "Pooled Versus Unpooled Age-Band Hazards"))
})

# ---- #5 baseline gate specified; false "defined consistently" claim removed -------
test_that("#5 baseline gate specified incl. Open Payments; no false consistency claim", {
  expect_false(has(supp, "Stock and flow are thus\\s*\\n?\\s*defined consistently"))
  expect_true(has(supp, "not\\s+identical"))
  expect_true(has(supp, "priority-3 signal|Open Payments is a priority-3"))
  expect_true(has(supp, "retirement_sql_builder"))
})

# ---- #6 S7b uses current 37/35; corroboration flagged tautological ----------------
test_that("#6 S7b reframed: 56/41 = detection layer, 37/35 anchored 100% by construction", {
  expect_true(has(supp, "100% of primary departures are non-Open-Payments-corroborated|100% non-Open-Payments-corroborated by construction"))
  expect_true(has(supp, "detection[- ]layer"))
  # The 36/46 proxy must not be presented as validation of the current
  # classifier. The main text still states the corroboration REQUIREMENT (it is
  # part of the primary departure definition) but no longer reports the 36/46 or
  # 56/41 detection-layer figures at all, so it makes no corroboration-as-
  # validation claim to qualify; the qualifier moved to the supplement with the
  # rest of the audit detail. Guarded below by the absence of those figures.
  expect_true(has(both, "tautology rather than validation|corroborated by construction"))
  expect_false(has(main, "36/46|56/41"))
})

# ---- #7 adjudication framed honestly (provisional, not fabricated) ----------------
test_that("#7 endpoint reported as provisional; classifier not claimed validated", {
  # reworded: the first-person disclaimer became a declarative one; the
  # requirement (no claim of individual validation) is unchanged
  expect_true(has(main, "provisional administrative classification that has not been individually validated"))
  expect_true(has(supp, "we do not present the classifier\\s*\\n?\\s*as individually validated|not.{0,20}individually validated"))
})

# ---- #9 comparator relabeled (not identical classifier); ages softened ------------
test_that("#9 comparator is a crude detection-layer benchmark, ages not 'retirement-like'", {
  expect_false(has(both, "identical classifier"))
  expect_false(has(supp, "same departure classifier"))
  expect_true(has(supp, "crude cross-cohort benchmark"))
  expect_false(has(supp, "retirement-like ages \\(median in the\\s*\\n?\\s*sixth decade\\), supporting the classifier"))
  expect_true(has(supp, "construct-validity"))
})

# ---- #10 no unsupported "conservative" bias claim --------------------------------
test_that("#10 the OP-definition 'conservative' claim is removed", {
  expect_false(has(supp, "denominator conservative"))
  expect_false(has(both, "dependence made the conclusion conservative"))
  expect_false(has(both, "Open Payments dependence makes the conclusion conservative"))
})

# ---- #12 no ABU-specific validation promise --------------------------------------
test_that("#12 ABU-URPS adjudication over-promise removed", {
  expect_false(has(supp, "reported separately for GO, ABOG-URPS, and\\s*\\n?\\s*ABU-URPS"))
  expect_true(has(supp, "(?s)ABU.{0,80}not independently classifiable|(?s)ABU-specific.{0,40}not adjudicated"))
})

# ---- #13 abstract ramp terminology exact -----------------------------------------
test_that("#13 abstract uses certification-to-first-Medicare-activity, not '-to-practice'", {
  expect_false(has(main, "certification-to-practice entry ramp"))
  expect_true(has(main, "certification-to-first-Medicare-activity"))
})

# ---- #14 Figure 1 caption distinguishes immediate-entry from transition-adjusted ----
# (Reviewer #7: transition-adjusted is now the paired lower estimate; Figure 1 shows
#  the immediate-entry line/band with the transition-adjusted 2029 point overlaid.)
test_that("#14 Figure 1 caption distinguishes immediate-entry from transition-adjusted", {
  expect_true(has(main, "immediate-entry projection"))
  # RETIRED on author instruction. The main text no longer carries this; it
  # was cut by the Green Journal condensation (f87ac53, 8,405 -> 2,702 words)
  # and the urogynecology-only revisions after it. Not reinstated in the
  # manuscript. Superseded pattern:
  #   "transition-adjusted 2029 counts"
  expect_true(has(main, "structural upper estimate"))
})

# ---- #15 numerator language exact ------------------------------------------------
test_that("#15 'entrants exceed departures' replaced by completions/classified departures", {
  expect_false(has(main, "entrants exceed departures"))
  # reworded: the ratio is now stated as its definition rather than as a
  # comparative claim
  expect_true(has(main, "fellowship completions divided by mean annual departures"))
})

# ---- #16 official ABOG citation for MIGS designation -----------------------------
test_that("#16 MIGS designation carries an official ABOG citation", {
  # RETIRED on author instruction. The main text no longer carries this; it
  # was cut by the Green Journal condensation (f87ac53, 8,405 -> 2,702 words)
  # and the urogynecology-only revisions after it. Not reinstated in the
  # manuscript. Superseded pattern:
  #   "@abog_fpmigs"
  bib <- rd(file.path(.root, "manuscript", "references_WORKFORCE_CLIFF.bib"))
  expect_true(has(bib, "abog_fpmigs"))
  expect_true(has(bib, "American Board of Obstetrics and Gynecology"))
})

# ==================================================================================
# ADVERSARIAL / NUMERIC: the data artifacts must reproduce the prose
# ==================================================================================

# ---- #3/#4 audit primary row reproduces the SSOT headline ------------------------
test_that("[adversarial] audit-table primary row reproduces the consolidated SSOT", {
  au  <- csv("departure_audit_table.csv")
  ss  <- csv("workforce_projections_consolidated.csv")
  prim <- au[au$definition == "primary (non-OP anchored)", ]
  for (s in c("GO", "URPS")) {
    a <- prim[prim$subspecialty_abbrev == s, ]
    b <- ss[ss$subspecialty_abbrev == s, ]
    expect_equal(round(as.numeric(a$completion_to_departure_ratio), 2),
                 round(as.numeric(b$replacement_ratio), 2), info = s)
    expect_equal(round(as.numeric(a$projected_2029)),
                 round(as.numeric(b$projected_2029)), info = s)
  }
  # exact headline values guard (GO+URPS-only primary hazard, MIGS excluded 2026-07-19)
  expect_equal(round(as.numeric(ss$replacement_ratio[ss$subspecialty_abbrev=="GO"]),2), 7.11)
  expect_equal(round(as.numeric(ss$replacement_ratio[ss$subspecialty_abbrev=="URPS"]),2), 5.38)
})

# ---- #4 pooled vs unpooled hazard: counts + the ordering flip the prose claims ----
test_that("[adversarial] pooled-vs-unpooled hazard artifact matches the disclosed claims", {
  hb <- csv("hazard_by_band_pooled_vs_unpooled.csv")
  expect_equal(sum(hb$go_events), 36)      # hazard-life-table events
  expect_equal(sum(hb$urps_events), 35)
  expect_equal(sum(hb$pooled_events), 71)  # GO 36 + URPS 35 (MIGS excluded from primary)
  expect_equal(sum(hb$pooled_incl_migs_events), 81)  # + MIGS sensitivity
  hr <- csv("hazard_rate_pooled_vs_unpooled.csv")
  go <- hr[hr$subspecialty_abbrev == "GO", ]; up <- hr[hr$subspecialty_abbrev == "URPS", ]
  # unpooled: URPS > GO ; pooled: GO > URPS  (the ordering flip the supplement discloses)
  expect_gt(as.numeric(up$rate_unpooled_pct), as.numeric(go$rate_unpooled_pct))
  expect_gt(as.numeric(go$rate_pooled_pct),   as.numeric(up$rate_pooled_pct))
})

# ---- #11 ABU cohort-flow arithmetic must close ------------------------------------
test_that("[adversarial] ABU cohort-flow arithmetic closes: 1027 + 279 = 1306", {
  cf <- csv("consort_cohort_flow.csv")
  u  <- cf[cf$ab == "URPS", ]
  expect_equal(as.integer(u$abu_identified) - as.integer(u$abu_excluded_nocert),
               as.integer(u$abu_included))
  expect_equal(as.integer(u$active_baseline) + as.integer(u$abu_included),
               as.integer(u$active_baseline_final))
  expect_equal(as.integer(u$active_baseline_final), 1306L)
  # Component counts on the adopted 1306 baseline. The 270/6 pair pinned here
  # previously was the pre-migration 1295 vintage (270 - 6 = 264 net new); the
  # arithmetic assertions above and this test's own title were moved to 1306
  # but these two constants were missed. The identity checks above are the real
  # guard; these pin the composition so a silent recomposition that still
  # happens to close is caught too.
  expect_equal(as.integer(u$abu_identified), 308L)
  expect_equal(as.integer(u$abu_excluded_nocert), 29L)
  # and the composition must agree with the SSOT baseline it feeds
  expect_equal(as.integer(u$active_baseline_final),
               as.integer(csv("workforce_projections_consolidated.csv")$baseline_2025[
                 csv("workforce_projections_consolidated.csv")$subspecialty_abbrev == "URPS"]))
})

# ---- #10/#12 OP-sensitivity: primary reproduces headline; both above replacement --
test_that("[adversarial] OP sensitivity: primary == headline, both definitions above replacement", {
  os <- csv("open_payments_sensitivity.csv")
  ss <- csv("workforce_projections_consolidated.csv")
  for (s in c("GO", "URPS")) {
    prim <- os[os$rule == "non_op_anchored (primary)" & os$subspecialty_abbrev == s, ]
    opin <- os[os$rule == "op_inclusive" & os$subspecialty_abbrev == s, ]
    expect_equal(round(as.numeric(prim$replacement_ratio), 2),
                 round(as.numeric(ss$replacement_ratio[ss$subspecialty_abbrev == s]), 2), info = s)
    expect_gt(as.numeric(opin$replacement_ratio), 1.05)   # above replacement
    expect_gt(as.numeric(prim$replacement_ratio), as.numeric(opin$replacement_ratio)) # anchoring raises ratio
  }
})

# ---- age-shift +0 baseline reproduces the headline (no conflicting 'primary') -----
test_that("[adversarial] age-shift +0 row reproduces the headline ratios", {
  ag <- csv("age_shift_sensitivity.csv")
  ss <- csv("workforce_projections_consolidated.csv")
  for (s in c("GO", "URPS")) {
    z <- ag[ag$subspecialty_abbrev == s & ag$age_shift_years == 0, ]
    expect_equal(round(as.numeric(z$replacement_ratio), 2),
                 round(as.numeric(ss$replacement_ratio[ss$subspecialty_abbrev == s]), 2), info = s)
  }
})

# ==========================================================================
# Peer review ROUND 3 (2026-07-19): textual-consistency + limitation fixes.
# Semantic checks on the Rmd source; one adversarial tie of the prose to data.
# ==========================================================================

# ---- R4 #7 title (refreshed 2026-07-28 for the supply-and-demand reframe) ----------
# The paper was reframed (commit acbf38e) from a headcount-balance study to a
# supply-and-demand paper; the title now reads "Supply and Demand ... Moving Beyond the
# Head Count". The reviewer HARD constraint that the title must never say "Replacement"
# is retained below.
test_that("R4#7 main title carries the supply-and-demand reframe and never says Replacement", {
  # reworded: the supply-and-demand reframe the reviewer asked for survives in
  # the title as "Supply Relative to Demographic Need"; the paper is now
  # urogynecology-only and framed against demographic need rather than "demand".
  expect_true(has(main, 'title:.*Supply Relative to Demographic Need'))
  # RETIRED on author instruction. The "Moving Beyond the Head Count" subtitle
  # was dropped when the title was rewritten. The idea it protected is carried
  # by the precis ("rising headcount did not establish access or operative
  # capacity"), which is guarded below. Superseded pattern:
  #   'title:.*Moving Beyond the Head Count'
  expect_true(has(main, 'precis:(.|\n)*did not establish\\s+access or operative\\s+capacity'))
  expect_false(has(main, 'title:.*Fellowship Replacement'))
  expect_false(has(main, 'title:.*Replacement'))
  expect_false(has(supp, 'Fellowship Replacement'))
})

# ---- R3 #4 pooled-hazard rates are not called specialty-specific empirical rates --
test_that("R3#4 abstract/results report pooled-hazard-IMPLIED weighted rates", {
  expect_false(has(main, "Empirical age-band departure rates were"))
  # reworded: same requirement: rates are reported as hazard-implied, not read
  # off event counts
  expect_true(has(main, "model-implied weighted annual departure rates"))
  # Discussion: no 'fully-observable GO rate'; use the pooled-hazard phrasing
  expect_false(has(main, "fully.observable gynecologic oncology rate"))
  # reworded: attribution to the pooled hazard is explicit in the current
  # phrasing
  expect_true(has(main, "Applying the pooled hazard to each cohort's estimated 2025 age distribution"))
})

test_that("R3#4/R4#1 the primary pooling population is named as GO + ABOG-URPS only (MIGS excluded)", {
  # reworded: names the pooling population as the two board-certified cohorts
  expect_true(has(main, "pooled the two cohorts into a single shared age-band hazard"))
  # reworded: MIGS exclusion is now stated of the analysis, which subsumes the
  # hazard
  expect_true(has(main, "excluded from the primary analysis"))
  # the round-3 'all three cohorts / MIGS contributes' framing must be gone (reversed in round 4)
  expect_false(has(main, "across all three gynecologic surgical cohorts"))
  expect_false(has(main, "MIGS events contribute to the shared hazard"))
})

# ---- R3 #5 sensitivity wording: 1.03 is AT replacement, not below -----------------
test_that("R3#5 the joint-extreme cell is labelled GO at-replacement, URPS below", {
  expect_false(has(main, "below-replacement cells \\(worst"))
  # retargeted to the document pair: this statement moved to the supplement
  # with the rest of the audit detail in the Green Journal condensation; the
  # reviewer's requirement is that it is stated, not which document states it.
  expect_true(has(both, "Gynecologic Oncology was at replacement.*URPS was below replacement"))
  # The supplement note carries the same corrected labels with the ratios. It used to
  # assert the LITERALS (1.03) and (0.88), which is precisely what let the prose go
  # stale: those were correct for isochrones b0d6c2f96 (2026-07-19) and were never
  # updated when the artifact moved to 1.003/0.861 and then 1.003/0.833. Pinning a
  # frozen number in a test froze the defect too. The prose is now generated from
  # sensitivity_grid_summary.csv, so assert THAT, and that the values agree with the
  # artifact. See docs/adjudication/sensitivity_grid.md.
  expect_true(has(supp, "at replacement \\(`r s17_worst\\(\"GO\"\\)`\\)"))
  expect_true(has(supp, "below replacement\\s*\\n?\\(`r s17_worst\\(\"URPS\"\\)`\\)"))
  g5 <- csv("sensitivity_grid_summary.csv")
  expect_equal(sprintf("%.2f", g5$worst_ratio[g5$subspecialty_abbrev == "GO"]), "1.00")
  expect_equal(sprintf("%.2f", g5$worst_ratio[g5$subspecialty_abbrev == "URPS"]), "0.83")
  # reframe wording: only the joint worst-case sensitivity reaches/dips to replacement
  # RETIRED on author instruction. The main text no longer carries this; it
  # was cut by the Green Journal condensation (f87ac53, 8,405 -> 2,702 words)
  # and the urogynecology-only revisions after it. Not reinstated in the
  # manuscript. Superseded pattern:
  #   "Only the joint worst case reaches or dips to replacement"
})

test_that("R3#5 [adversarial] the grid worst ratios classify exactly as the prose claims", {
  source(file.path(.root, "manuscript", "R", "workforce_data_contract.R"))
  g <- csv("sensitivity_grid_summary.csv")
  go <- g$worst_ratio[g$subspecialty_abbrev == "GO"]
  ur <- g$worst_ratio[g$subspecialty_abbrev == "URPS"]
  expect_equal(classify_replacement(go), "At replacement")     # 1.027 -> At (prose: at replacement)
  expect_equal(classify_replacement(ur), "Below replacement")  # 0.882 -> Below
})

# ---- R3 #6 scenario growth attributed to status-quo immediate-entry only ----------
test_that("R3#6 growth percentages are attributed to the status-quo immediate-entry scenario", {
  # reworded: 'grew' became 'exceeded the 2025 baseline', which is the more
  # precise claim
  expect_true(has(main, "Both cohorts exceeded the 2025 baseline under all three entrant scenarios"))
  # reworded: immediate-entry and transition-adjusted are now reported side by
  # side in the same sentence, so the scenario label no longer carries the
  # qualifier
  expect_true(has(main, "Under the status-quo scenario"))
  expect_false(has(main, "Across the conservative, status-quo, and \\(lagged\\) optimistic entrant scenarios both cohorts grew"))
})

# ---- R3 #7 no unsupported causal 'reducing misclassification'; hedged sourcing -----
test_that("R3#7 misclassification and primary-source claims are appropriately hedged", {
  expect_false(has(main, "reducing the misclassification of"))
    # reworded: the six-source rationale is now stated in the abstract against
  # the single-billing-measure alternative
  expect_true(has(main, "rather than a single billing measure"))
  expect_false(has(main, "draws its core inputs from primary sources rather than assumption"))
  # RETIRED on author instruction. The main text no longer carries this; it
  # was cut by the Green Journal condensation (f87ac53, 8,405 -> 2,702 words)
  # and the urogynecology-only revisions after it. Not reinstated in the
  # manuscript. Superseded pattern:
  #   "combines primary-source workforce and fellowship data with explicit administrative-classification and modeling assumptions"
})

# ---- R3 #8 'adjudicated' reserved for chart review; admin follow-up reworded -------
test_that("R3#8 2022-2023 departures are 'confirmed under the three-year follow-up rule'", {
  expect_false(has(main, "cannot yet be adjudicated"))
  # reworded: 'yet' and 'administrative' dropped in the condensation; the
  # censoring claim is unchanged
  expect_true(has(main, "cannot be confirmed under the three-year follow-up rule"))
})

# ---- R3 #10 applicant-market interpretation softened to a measured comparison ------
test_that("R3#10 applicant-market claim replaced with the measured Match gap", {
  expect_false(has(main, "well beyond plausible near-term applicant declines"))
  # RETIRED on author instruction. The main text no longer carries this; it
  # was cut by the Green Journal condensation (f87ac53, 8,405 -> 2,702 words)
  # and the urogynecology-only revisions after it. Not reinstated in the
  # manuscript. Superseded pattern:
  #   "substantially larger than the applicant-position gaps observed in the most recent Match"
})

# ---- R4 #3 consistent-definition baseline sensitivity is now COMPLETE (supersedes R3#2) ----
# The reviewer's prespecified analysis was run (scripts/build_reviewer_sensitivities.R);
# the manuscript must report the anchored-baseline result, not disclose it as pending.
test_that("R4#3 the consistent-definition baseline sensitivity is reported as complete", {
    # reworded: the sensitivity is now named in the consolidated Results list of
  # one-way sensitivities
  expect_true(has(main, "baseline-definition"))
  # RETIRED on author instruction. The main text no longer carries this; it
  # was cut by the Green Journal condensation (f87ac53, 8,405 -> 2,702 words)
  # and the urogynecology-only revisions after it. Not reinstated in the
  # manuscript. Superseded pattern:
  #   "regenerates the 2025 active stock under the same anchored departure rule"
  # RETIRED on author instruction. The main text no longer carries this; it
  # was cut by the Green Journal condensation (f87ac53, 8,405 -> 2,702 words)
  # and the urogynecology-only revisions after it. Not reinstated in the
  # manuscript. Superseded pattern:
  #   "active-baseline gate and the anchored historical departure-event definition"
  expect_false(has(main, "prespecified but is not yet complete"))   # retired: analysis is done
})

# ---- R4 #2 age-specific mortality sensitivity now bounds the missed-death bias (supersedes R3#3) ----
# Board-confirmed deaths stay blocked, but the reviewer's "at minimum" age-specific
# mortality sensitivity was added; the retired honest-disclosure phrasing (including
# "removes zero deceased physicians", which the O&G reviewer said must not appear) is gone.
test_that("R4#2 the deaths limitation reports the age-specific mortality bound", {
  # retargeted to the document pair: this statement moved to the supplement
  # with the rest of the audit detail in the Green Journal condensation; the
  # reviewer's requirement is that it is stated, not which document states it.
  expect_true(has(both, "age- and sex-specific expected-mortality sensitivity"))
  # retargeted to the document pair: this statement moved to the supplement
  # with the rest of the audit detail in the Green Journal condensation; the
  # reviewer's requirement is that it is stated, not which document states it.
  expect_true(has(both, "conservative upper bound"))
  # RETIRED on author instruction. The main text no longer carries this; it
  # was cut by the Green Journal condensation (f87ac53, 8,405 -> 2,702 words)
  # and the urogynecology-only revisions after it. Not reinstated in the
  # manuscript. Superseded pattern:
  #   "biasing the departure rate downward and the completion-to-departure ratio upward"
  expect_false(has(main, "removes zero deceased physicians"))       # reviewer-mandated removal
})

# ==========================================================================
# Peer review ROUND 4 (2026-07-19): one test per review item as a fix ledger.
# Fixed items assert the corrected state; items blocked on the MIGS-exclusion
# rerun (estimand decision) or the signals DuckDB / human chart review skip()
# with an explicit reason and auto-activate the moment the work lands.
# ==========================================================================

# ---- R4 #1 primary pooled hazard should EXCLUDE the noncomparable MIGS cohort ----
test_that("R4#1 primary pooled hazard excludes MIGS (GO + ABOG-URPS only)", {
  h <- csv("hazard_by_band_pooled_vs_unpooled.csv")
  skip_if(any(h$migs_events > 0) && all(h$pooled_events == h$go_events + h$urps_events + h$migs_events),
          "PENDING R4#1: rerun primary hazard without MIGS is an estimand decision awaiting PI sign-off")
  expect_equal(h$pooled_events, h$go_events + h$urps_events)
})

# ---- R4 #2 specialty-ordering caveat is stated in Results ------------------------
test_that("R4#2 the GO-vs-URPS ordering is disclosed as pooling-induced, not a true difference", {
  # RETIRED on author instruction. The main text no longer carries this; it
  # was cut by the Green Journal condensation (f87ac53, 8,405 -> 2,702 words)
  # and the urogynecology-only revisions after it. Not reinstated in the
  # manuscript. Superseded pattern:
  #   "ordering of the two weighted rates was sensitive to pooling"
  # RETIRED on author instruction. The main text no longer carries this; it
  # was cut by the Green Journal condensation (f87ac53, 8,405 -> 2,702 words)
  # and the urogynecology-only revisions after it. Not reinstated in the
  # manuscript. Superseded pattern:
  #   "not be interpreted as evidence of a true difference in specialty-specific departure propensity"
  skip(paste("retired on author instruction:",
             "the paper is urogynecology-only since the post-condensation revisions, so there is no GO-vs-URPS ordering left to disclose."))
})

# ---- R4 #3 Results no longer call pooled outputs 'empirical annual departure rates' --
test_that("R4#3 Results report pooled-hazard-IMPLIED weighted 2025 rates", {
  expect_false(has(main, "Empirical annual departure rates"))
  # reworded: same requirement as R3#4 above
  expect_true(has(main, "model-implied weighted annual departure rates"))
})

# ---- R4 #4A physician-level adjudication results are reported --------------------
test_that("R4#4A chart-adjudication PPV/kappa results are present", {
  p <- file.path(DATA, "classifier_adjudication_results.csv")
  skip_if(!file.exists(p),
          "PENDING R4#4A: two-reviewer chart adjudication results not yet available (human review)")
  adj <- read.csv(p, stringsAsFactors = FALSE)
  expect_true(all(c("ppv", "kappa") %in% names(adj)))
})

# ---- R4 #4B confirmed deaths are incorporated -----------------------------------
test_that("R4#4B board-confirmed deaths are folded into the cohort (removed_deceased > 0)", {
  f <- csv("consort_cohort_flow.csv")
  skip_if(all(f$removed_deceased == 0),
          "PENDING R4#4B: death correction blocked on signals DuckDB access")
  expect_true(any(f$removed_deceased > 0))
})

# ---- R4 #4C consistent-definition baseline rerun artifact exists ----------------
test_that("R4#4C consistent-definition baseline sensitivity has been produced", {
  p <- file.path(DATA, "consistent_definition_baseline_sensitivity.csv")
  skip_if(!file.exists(p),
          "PENDING R4#4C: consistent-definition baseline rerun blocked on signals DuckDB access")
  expect_gt(nrow(read.csv(p)), 0)
})

# ---- R4 #5 internal drafting notes removed from the submission text --------------
test_that("R4#5 no internal 'will replace this paragraph' / 'before final submission' notes", {
  expect_false(has(both, "will replace this paragraph"))
  expect_false(has(both, "before final submission"))
  expect_false(has(main, "remains to be completed before"))
})

# ---- R4 #6 graduates framed as training output / potential entrants -------------
test_that("R4#6 'conservative and correct inflow' replaced with training-output framing", {
  expect_false(has(main, "conservative and correct inflow"))
  # RETIRED on author instruction. The main text no longer carries this; it
  # was cut by the Green Journal condensation (f87ac53, 8,405 -> 2,702 words)
  # and the urogynecology-only revisions after it. Not reinstated in the
  # manuscript. Superseded pattern:
  #   "appropriate measure of training output"
    # reworded: 'confirmed' became 'verified'; the training-output framing the
  # reviewer asked for is unchanged
  expect_true(has(main, "potential rather than verified active-practice entrants"))
})

# ---- R4 #7 abstract conclusion (refreshed 2026-07-28 for the supply-and-demand reframe) ----
# The reframed abstract concludes that supply grows faster than demand (rather than the pre-reframe
# "no imminent cliff" counter-narrative). The underlying reviewer intent is retained in the reframed
# wording: fellowship output exceeds near-term classified departures, and Medicare-defined loss is
# not established as a validated departure signal.
test_that("R4#7 abstract conclusion reports supply outpacing demand and defers replacement", {
  expect_false(has(main, "appears sufficient to replace"))
  # RETIRED on author instruction. The main text no longer carries this; it
  # was cut by the Green Journal condensation (f87ac53, 8,405 -> 2,702 words)
  # and the urogynecology-only revisions after it. Not reinstated in the
  # manuscript. Superseded pattern:
  #   "supply grows faster than demand"
    # reworded: 'estimated' became 'projected' and the cohort is now named, the
  # paper being urogynecology-only
  expect_true(has(main, "exceeded projected near-term urogynecology departures"))
  # RETIRED on author instruction. The main text no longer carries this; it
  # was cut by the Green Journal condensation (f87ac53, 8,405 -> 2,702 words)
  # and the urogynecology-only revisions after it. Not reinstated in the
  # manuscript. Superseded pattern:
  #   "could not be validated against available administrative signals"
})

# ---- R4 #8 external comparison is descriptive, not validating --------------------
test_that("R4#8 all-surgeon attrition comparison is descriptive, not confirmatory", {
  expect_false(has(main, "consistent with these subspecialties being among the lowest-attrition"))
  # RETIRED on author instruction. The main text no longer carries this; it
  # was cut by the Green Journal condensation (f87ac53, 8,405 -> 2,702 words)
  # and the urogynecology-only revisions after it. Not reinstated in the
  # manuscript. Superseded pattern:
  #   "numerically lower than the 1.5% to 1.7%"
    # reworded: same caveat, active voice; the comparison is still declared non-
  # confirmatory
  expect_true(has(main, "differing definitions preclude a direct comparison"))
  # RETIRED on author instruction. The main text no longer carries this; it
  # was cut by the Green Journal condensation (f87ac53, 8,405 -> 2,702 words)
  # and the urogynecology-only revisions after it. Not reinstated in the
  # manuscript. Superseded pattern:
  #   "not independent confirmation of the external hazard ratio"
})

# ---- R4 #9 MIGS framing is internally consistent (resolved by #1) ----------------
test_that("R4#9 MIGS is not simultaneously pooled-into-primary and called not-pooled", {
  skip_if(has(main, "MIGS events contribute to the shared hazard"),
          "PENDING R4#9: resolved by the #1 MIGS-exclusion rerun (estimand decision)")
  expect_false(has(main, "MIGS events contribute to the shared hazard"))
})

# ---- R4 #10 omitted-uncertainty list names the new directional unknowns ----------
test_that("R4#10 the interval caveat lists deaths/baseline/classification/MIGS-pooling", {
  # RETIRED on author instruction. The main text no longer carries this; it
  # was cut by the Green Journal condensation (f87ac53, 8,405 -> 2,702 words)
  # and the urogynecology-only revisions after it. Not reinstated in the
  # manuscript. Superseded pattern:
  #   "death-ascertainment, baseline-definition, physician-level classification, and MIGS-pooling uncertainty"
  # RETIRED on author instruction. The main text no longer carries this; it
  # was cut by the Green Journal condensation (f87ac53, 8,405 -> 2,702 words)
  # and the urogynecology-only revisions after it. Not reinstated in the
  # manuscript. Superseded pattern:
  #   "scenario ranges are a fuller expression"
  skip(paste("retired on author instruction:",
             "the enumerated interval caveat was cut; MIGS is now excluded from the primary analysis entirely."))
})

# ---- R4 #11 tipping point framed as conditional on the model components ----------
test_that("R4#11 tipping-point statement is conditioned on classifier/baseline/hazard model", {
  # RETIRED on author instruction. The main text no longer carries this; it
  # was cut by the Green Journal condensation (f87ac53, 8,405 -> 2,702 words)
  # and the urogynecology-only revisions after it. Not reinstated in the
  # manuscript. Superseded pattern:
  #   "Conditional on the current classifier, active baseline, pooled-hazard model"
  skip(paste("retired on author instruction:",
             "the tipping-point statement itself was removed from the condensed Discussion."))
})
