# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# GATE: no publication-facing number may be restated by hand.
#
# This file exists because the 1,295 -> 1,306 baseline migration left stale
# copies of the headline numbers in six different KINDS of place, and each kind
# hid from the checks that would have caught the others:
#
#   1. a derived column in the SSOT itself, stored as a rounded literal by its
#      own generator (replacement_ratio 5.38 for 5.384894)
#   2. committed artifacts whose generators were left behind by the isochrones
#      extraction, so nothing could regenerate them (departure_audit_table,
#      baseline_lag_decomposition)
#   3. hand-written prose in the supplement (S4b's "Gynecologic Oncology 7.35,
#      URPS 5.83" -- a third vintage, matching neither the artifact it
#      introduced nor the SSOT)
#   4. a kable() caption -- reader-facing text that lives inside a code chunk,
#      so prose scanners miss it
#   5. cohort counts in the main text whose TOTAL was inline but whose PARTS
#      were literals, so the total would update and leave the parts wrong
#   6. prose embedded in a DATA file (table_evidence_supporting_scenarios.csv),
#      invisible to both prose scanners and numeric artifact checks
#
# The gates below are ordered by that list. See also
# test-ssot-derived-column-identities.R (kind 1) and the Hall of Shame at the
# foot of this file.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
library(testthat)

.root <- local({
  d <- normalizePath(getwd(), winslash = "/")
  for (i in 1:8) {
    if (file.exists(file.path(d, "DESCRIPTION"))) return(d)
    p <- dirname(d); if (identical(p, d)) break; d <- p
  }
  getwd()
})
.data <- function(f) file.path(.root, "data", f)
.doc  <- function(f) file.path(.root, "manuscript", f)
.rd   <- function(p) paste(readLines(p, warn = FALSE), collapse = "\n")

skip_if_no_ssot <- function() skip_if_not(file.exists(.data("workforce_projections_consolidated.csv")),
                                          "SSOT artifact not present")

ssot <- local({
  p <- .data("workforce_projections_consolidated.csv")
  if (file.exists(p)) utils::read.csv(p, stringsAsFactors = FALSE) else NULL
})
sv <- function(ab, col) ssot[[col]][ssot$subspecialty_abbrev == ab]

# Strip code chunks AND inline R, leaving only what a reader sees. The (?s) is
# load-bearing: without it the chunk pattern stops at the first newline and the
# scanner both misses chunk-internal text and miscounts comments as prose.
prose_of <- function(path) {
  x <- .rd(path)
  x <- gsub("(?s)```\\{r.*?```", " ", x, perl = TRUE)   # code chunks
  x <- gsub("(?s)<!--.*?-->",    " ", x, perl = TRUE)   # html comments (not rendered)
  gsub("`r [^`]*`", " ", x, perl = TRUE)                # inline R
}

# ---- GATE 3/5: no headline number restated as a literal in rendered prose ----
test_that("GATE: the headline numbers appear in no rendered prose as literals", {
  skip_if_no_ssot()
  docs <- c("manuscript_WORKFORCE_CLIFF.Rmd", "supplement_WORKFORCE_CLIFF.Rmd")
  skip_if_not(all(file.exists(.doc(docs))), "manuscript sources not present")

  # Every value below is available inline from the SSOT or the consort flow, so
  # a literal is always avoidable and always a drift risk.
  banned <- c(
    sprintf("%.2f", round(sv("URPS", "replacement_ratio"), 2)),   # 5.38
    format(round(sv("URPS", "projected_2029")), big.mark = ","),  # 1,514
    format(sv("URPS", "baseline_2025"), big.mark = ",")           # 1,306
  )
  for (d in docs) {
    txt <- prose_of(.doc(d))
    for (b in banned) {
      pat <- gsub(",", ",?", b, fixed = TRUE)
      expect_false(grepl(pat, txt, perl = TRUE),
                   info = sprintf("%s restates %s; read it from the SSOT instead", d, b))
    }
  }
})

# ---- GATE 4: captions are text too --------------------------------------------
test_that("GATE: kable captions do not hard-code the baseline", {
  skip_if_no_ssot()
  p <- .doc("supplement_WORKFORCE_CLIFF.Rmd")
  skip_if_not(file.exists(p), "supplement not present")
  src <- readLines(p, warn = FALSE)
  caps <- grep("caption\\s*=\\s*\"", src, value = TRUE, perl = TRUE)
  base <- format(sv("URPS", "baseline_2025"), big.mark = ",")
  for (cp in caps)
    expect_false(grepl(gsub(",", ",?", base, fixed = TRUE), cp, perl = TRUE),
                 info = paste("caption hard-codes the baseline:", substr(cp, 1, 90)))
})

# ---- GATE 6: prose embedded in data files ------------------------------------
test_that("GATE: prose inside data files carries no stale ratio", {
  skip_if_no_ssot()
  f <- .data("table_evidence_supporting_scenarios.csv")
  skip_if_not(file.exists(f), "evidence table not present")
  h <- utils::read.csv(.data("hierarchical_hazard_comparison.csv"), stringsAsFactors = FALSE)
  hv <- function(m) h$replacement_ratio[h$subspecialty_abbrev == "URPS" & h$method == m]
  txt <- paste(unlist(utils::read.csv(f, stringsAsFactors = FALSE)), collapse = " ")
  # the pooled/unpooled pair quoted in the evidence column must be the artifact's
  expect_true(grepl(sprintf("unpooled %.2f", hv("unpooled")), txt, fixed = TRUE))
  expect_true(grepl(sprintf("pooled %.2f",   hv("pooled")),   txt, fixed = TRUE))
})

# ---- GATE 2: every SSOT-derived artifact reconciles ---------------------------
# The generators are in scripts/ now, so "it cannot be regenerated" is no longer
# an excuse for drift. Each entry: file, selector, label.
RECONCILERS <- list(
  list("departure_audit_table.csv", function(d)
    d$completion_to_departure_ratio[d$definition == "primary (non-OP anchored)" &
                                    d$subspecialty_abbrev == "URPS"], "audit primary row"),
  list("baseline_lag_decomposition.csv", function(d)
    d$ratio_primary[d$subspecialty_abbrev == "URPS"], "baseline-lag primary"),
  list("age_shift_sensitivity.csv", function(d)
    d$replacement_ratio[d$subspecialty_abbrev == "URPS" & d$age_shift_years == 0], "age-shift +0"),
  list("graduate_growth_scenarios.csv", function(d)
    d$replacement_ratio[d$subspecialty_abbrev == "URPS" & d$scenario == "flat_recent_mean"],
    "graduate flat-recent-mean"),
  list("hierarchical_hazard_comparison.csv", function(d)
    d$replacement_ratio[d$subspecialty_abbrev == "URPS" & d$method == "pooled"], "hierarchical pooled"),
  list("open_payments_sensitivity.csv", function(d)
    d$replacement_ratio[d$rule == "non_op_anchored (primary)" &
                        d$subspecialty_abbrev == "URPS"], "open-payments primary")
)

test_that("GATE: every SSOT-derived artifact reproduces the headline ratio", {
  skip_if_no_ssot()
  want <- round(sv("URPS", "replacement_ratio"), 2)
  for (r in RECONCILERS) {
    p <- .data(r[[1]])
    if (!file.exists(p)) { expect_true(TRUE); next }
    got <- r[[2]](utils::read.csv(p, stringsAsFactors = FALSE))
    expect_equal(round(got, 2), want, tolerance = 5e-3, info = r[[3]])
  }
})

test_that("GATE: every artifact carrying a URPS baseline agrees with the SSOT", {
  skip_if_no_ssot()
  want <- sv("URPS", "baseline_2025")
  checks <- list(
    list("departure_audit_table.csv", function(d)
      d$active_baseline[d$definition == "primary (non-OP anchored)" &
                        d$subspecialty_abbrev == "URPS"]),
    list("baseline_lag_decomposition.csv", function(d) d$baseline_total[d$subspecialty_abbrev == "URPS"]),
    list("consort_cohort_flow.csv",        function(d) d$active_baseline_final[d$ab == "URPS"])
  )
  for (ck in checks) {
    p <- .data(ck[[1]])
    if (!file.exists(p)) { expect_true(TRUE); next }
    expect_equal(as.integer(ck[[2]](utils::read.csv(p, stringsAsFactors = FALSE))),
                 as.integer(want), info = ck[[1]])
  }
})

# ---- known-stale, tracked rather than hidden ---------------------------------
test_that("feminization_sensitivity reconciles to the SSOT", {
  skip_if_no_ssot()
  skip_if_not(file.exists(.data("feminization_sensitivity.csv")), "artifact not present")
  # KNOWN STALE, awaiting a decision (2026-08-14). This artifact carries URPS
  # baseline 1,031 / ratio 5.00 and GO 7.35 -- an even older vintage than the
  # 1,295 one, and the ORIGIN of the "Gynecologic Oncology 7.35" that survived
  # in the S4b sentence. It has no generator in this repository or in isochrones,
  # so regenerating it would mean inventing the sex-composition derivation.
  # It is rendered in the supplement, so this is reader-facing.
  skip("PENDING: feminization_sensitivity.csv is on a pre-1,306 basis and has no generator")
  d <- utils::read.csv(.data("feminization_sensitivity.csv"), stringsAsFactors = FALSE)
  expect_equal(as.integer(d$baseline[d$subspecialty_abbrev == "URPS"]),
               as.integer(sv("URPS", "baseline_2025")))
  expect_equal(round(d$ratio_sexneutral[d$subspecialty_abbrev == "URPS"], 2),
               round(sv("URPS", "replacement_ratio"), 2), tolerance = 5e-3)
})

# ---- Hall of Shame: values that were once published and must never return -----
# Each entry is a number that WAS in a committed artifact or in reader-facing
# prose, was wrong, and was corrected. Anything that resurrects one of these has
# reintroduced a specific, documented defect rather than made a new mistake.
test_that("Hall of Shame: retired numbers do not reappear in any artifact or document", {
  skip_if_no_ssot()
  RETIRED <- list(
    list("5.61",  "URPS completion-to-departure ratio on the retired 1,295 baseline"),
    list("1,505", "URPS projected_2029 on the retired 1,295 baseline"),
    list("5.83",  "URPS ratio quoted in the S4b sentence; matched no artifact, ever"),
    list("1,333", "URPS baseline from rebuilding the cohort off the ABU rosters instead of the v3.0.0 snapshot")
  )
  docs <- c("manuscript_WORKFORCE_CLIFF.Rmd", "supplement_WORKFORCE_CLIFF.Rmd")
  docs <- docs[file.exists(.doc(docs))]
  for (d in docs) {
    txt <- prose_of(.doc(d))
    for (r in RETIRED)
      expect_false(grepl(gsub(",", ",?", r[[1]], fixed = TRUE), txt, perl = TRUE),
                   info = sprintf("%s: %s (%s)", d, r[[1]], r[[2]]))
  }
  # and in the artifacts the documents read
  for (f in vapply(RECONCILERS, `[[`, character(1), 1L)) {
    p <- .data(f)
    if (!file.exists(p)) next
    txt <- paste(unlist(utils::read.csv(p, stringsAsFactors = FALSE)), collapse = " ")
    for (r in RETIRED[c(1, 2, 4)])   # 5.83 never existed in an artifact
      expect_false(grepl(paste0("(?<![0-9.])", gsub(",", ",?", r[[1]], fixed = TRUE), "(?![0-9])"),
                         txt, perl = TRUE),
                   info = sprintf("%s: %s (%s)", f, r[[1]], r[[2]]))
  }
})

# 1,295 is deliberately NOT in the Hall of Shame: the supplement cites it as the
# frozen legacy SGS projection cohort, explicitly labelled "not recalculated".
# The repository's `# ssot-ok: legacy frozen SGS projection cohort` annotation
# marks the same distinction in code. Banning it would punish an honest citation.
test_that("the legacy 1,295 cohort is still cited as frozen, not as current", {
  p <- .doc("supplement_WORKFORCE_CLIFF.Rmd")
  skip_if_not(file.exists(p), "supplement not present")
  txt <- prose_of(p)
  if (grepl("1,295", txt, fixed = TRUE))
    expect_true(grepl("(?s)1,295[^.]{0,120}(frozen|legacy|not recalculated)|((frozen|legacy)[^.]{0,120}1,295)",
                      txt, perl = TRUE),
                info = "1,295 appears without being marked frozen/legacy")
  else expect_true(TRUE)
})

# ---- GATE 7: the documents must actually RENDER ------------------------------
# Everything above passed while supplement_WORKFORCE_CLIFF.Rmd could not render:
# the helper was named cf(), and the supplement binds `cf` to a data.frame 60
# lines later, so by the time Table S7's caption called cf("active_baseline")
# it was calling a data.frame. Parsing succeeded, the unit tests succeeded, and
# the document was broken. Only a render finds that class of defect.
#
# Rendering is slow and needs pandoc, so this gate is opt-in: set
# CLIFF_RENDER_TESTS=1 (CI, or before submitting). The cheap always-on proxy
# below catches the specific failure mode without rendering.
test_that("GATE: inline-R helper names are not rebound elsewhere in the document", {
  docs <- c("manuscript_WORKFORCE_CLIFF.Rmd", "supplement_WORKFORCE_CLIFF.Rmd")
  docs <- docs[file.exists(.doc(docs))]
  skip_if_not(length(docs) > 0, "manuscript sources not present")
  for (d in docs) {
    src <- readLines(.doc(d), warn = FALSE)
    # helpers defined in a setup chunk and used from inline `r ...`
    defs <- regmatches(src, regexpr("^\\s*([A-Za-z._][A-Za-z0-9._]*)\\s*<-\\s*function", src))
    names_def <- unique(sub("\\s*<-\\s*function", "", trimws(defs)))
    for (nm in names_def) {
      inline_used <- any(grepl(sprintf("`r [^`]*(?<![A-Za-z0-9._])%s\\(", nm), src, perl = TRUE))
      if (!inline_used) next
      # Every assignment to this name, classified by whether the right-hand side
      # is a function. A non-function assignment shadows the helper for every
      # inline call after it. (Do not express this as a negative lookahead after
      # \\s* -- the \\s* backtracks to width zero and the lookahead then passes on
      # the leading space, which silently flags the definition itself.)
      assign_ln <- grep(sprintf("^\\s*%s\\s*<-", nm), src, perl = TRUE)
      rhs <- sub(sprintf("^\\s*%s\\s*<-\\s*", nm), "", src[assign_ln], perl = TRUE)
      rebinds <- assign_ln[!grepl("^function\\b", rhs, perl = TRUE)]
      expect_length(rebinds, 0L)
      if (length(rebinds))
        cat(sprintf("\n  %s: helper %s() is rebound to a non-function at line(s) %s\n", d, nm,
                    paste(rebinds, collapse = ", ")))
    }
  }
})

test_that("GATE: the supplement renders (opt-in, CLIFF_RENDER_TESTS=1)", {
  skip_if_not(nzchar(Sys.getenv("CLIFF_RENDER_TESTS")), "set CLIFF_RENDER_TESTS=1 to run renders")
  skip_if_not_installed("rmarkdown")
  skip_if_not(rmarkdown::pandoc_available(), "pandoc not available")
  p <- .doc("supplement_WORKFORCE_CLIFF.Rmd")
  skip_if_not(file.exists(p), "supplement not present")
  out <- tempfile(fileext = ".docx")
  expect_error(rmarkdown::render(p, output_file = out, quiet = TRUE, envir = new.env()), NA)
  expect_true(file.exists(out))
})
