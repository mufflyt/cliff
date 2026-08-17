# GATE: the historical reference state must not float with the current SSOT.
#
# The four scripts/urps_baseline_scenarios/table*_v3.0.0.csv are a DECOMPOSITION of the
# frozen published 1,295-provider projection. The live SSOT now holds 1,306. Those are
# different scientific questions, not a stale input and a fresh one.
#
# urps_scenario_analysis_v3.R used to obtain the frozen 1,295 record by reading
# data/workforce_projections_consolidated.csv -- the LIVE SSOT -- with the comment
# "read from the frozen record (not hardcoded)". After the 1,295 -> 1,306 migration it
# therefore rewrote all four tables with the CURRENT projection while still labelling the
# row "frozen", and Table 3's count-effect contrast collapsed from -10.8 to EXACTLY 0,
# because the reference and comparison counts had become identical. The generator's own
# guard caught it, but sat after all four writes, so the files were corrupted first.
#
# Reproducibility does not mean "run the old analysis with today's inputs". For a
# published historical decomposition, that is reproducible and scientifically wrong.
#
# Adjudication: docs/adjudication/urps_baseline_scenarios_tables.md

skip_if_no_repo()

ROOT <- cliff_repo_root()
SD   <- file.path(ROOT, "scripts", "urps_baseline_scenarios")
GEN  <- file.path(SD, "urps_scenario_analysis_v3.R")
TABLES <- c("table1_published_preservation", "table2_controlled_sensitivity",
            "table3_count_age_decomposition", "table4_same_horizon_h4")
`%||%` <- function(a, b) if (is.null(a)) b else a

# A standalone project containing only what the generator needs. The four artifacts are
# deliberately NOT copied in, so "was anything written?" is answerable by existence.
.sandbox <- function(edit_gen = identity, edit_ssot = identity) {
  dir <- tempfile("scenariosandbox"); dirs <- c("scripts/urps_baseline_scenarios", "R", "data")
  for (d in dirs) dir.create(file.path(dir, d), recursive = TRUE)
  file.create(file.path(dir, ".here"))
  writeLines(edit_gen(readLines(GEN, warn = FALSE)),
             file.path(dir, "scripts/urps_baseline_scenarios/urps_scenario_analysis_v3.R"))
  file.copy(file.path(SD, "wc_engine_loader.R"),
            file.path(dir, "scripts/urps_baseline_scenarios/wc_engine_loader.R"))
  file.copy(file.path(SD, "urps_cohort_ages_v3.0.0.csv"),
            file.path(dir, "scripts/urps_baseline_scenarios/urps_cohort_ages_v3.0.0.csv"))
  file.copy(file.path(ROOT, "R", "workforce_cliff_engine.R"),
            file.path(dir, "R", "workforce_cliff_engine.R"))
  writeLines(edit_ssot(readLines(file.path(ROOT, "data",
             "workforce_projections_consolidated.csv"), warn = FALSE)),
             file.path(dir, "data", "workforce_projections_consolidated.csv"))
  dir
}

.run <- function(dir) {
  rscript <- file.path(R.home("bin"), "Rscript")
  old <- setwd(dir); on.exit(setwd(old), add = TRUE)   # never run in the repo: it writes
  out <- suppressWarnings(system2(rscript,
    c("--no-init-file", "scripts/urps_baseline_scenarios/urps_scenario_analysis_v3.R"),
    stdout = TRUE, stderr = TRUE))
  list(status = attr(out, "status") %||% 0L, output = paste(out, collapse = "\n"))
}
.written <- function(dir) {
  vapply(TABLES, function(t) file.exists(file.path(dir, "scripts/urps_baseline_scenarios",
                                                   paste0(t, "_v3.0.0.csv"))), logical(1))
}
.read <- function(dir, t) utils::read.csv(
  file.path(dir, "scripts/urps_baseline_scenarios", paste0(t, "_v3.0.0.csv")),
  stringsAsFactors = FALSE)
# a fast variant: MC draw count only affects precision, not which baseline is used
.fast <- function(src) sub("^(DRAWS\\s*<-\\s*)\\d+L", "\\125L", src)

# ── 1. the committed artifacts are the authoritative historical decomposition ──
test_that("the committed tables encode the frozen 1,295 reference and a NONZERO contrast", {
  t1 <- utils::read.csv(file.path(SD, "table1_published_preservation_v3.0.0.csv"),
                        stringsAsFactors = FALSE)
  expect_equal(as.integer(t1$baseline_count[1]), 1295L)
  expect_equal(t1$frozen_or_recalculated[1], "frozen")

  t3 <- utils::read.csv(file.path(SD, "table3_count_age_decomposition_v3.0.0.csv"),
                        stringsAsFactors = FALSE)
  ce <- t3[t3$contrast == "count_effect", , drop = FALSE]
  expect_equal(nrow(ce), 1L)
  expect_equal(as.integer(ce$baseline_count), 1295L)
  # THE property. A zero here means the reference and comparison counts collapsed.
  expect_true(abs(as.numeric(ce$d_projected_vs_ref)) > 1,
              info = paste("count_effect contrast is ~0: the frozen reference has been",
                           "replaced by the current SSOT, so the decomposition compares",
                           "a cohort against itself."))
})

# ── 2. all guards precede all writes (no partial artifacts on failure) ────────
test_that("every write happens after every guard", {
  src <- readLines(GEN, warn = FALSE)
  writes <- grep("write\\.csv\\(", src)
  guards <- grep("^stopifnot\\(|^\\s*stop\\(sprintf|^\\.missing_frozen", src)
  expect_gt(length(writes), 0L); expect_gt(length(guards), 0L)
  expect_true(min(writes) > max(guards),
              info = "a write precedes a guard; a failed check would leave corrupt artifacts")
})

# ── 3. the frozen record never reads the live SSOT ────────────────────────────
test_that("the frozen historical record is declared, not looked up", {
  src <- readLines(GEN, warn = FALSE); code <- src[!grepl("^\\s*#", src)]
  expect_true(any(grepl("FROZEN_LEGACY\\s*<-\\s*list\\(", code)),
              info = "no explicit frozen historical record")
  for (f in c("source_commit", "source_date", "published_analysis"))
    expect_true(any(grepl(f, code)), info = paste("frozen record lacks provenance:", f))
  # legacy_frozen must be built from the frozen record, never from the live SSOT row `u`
  lf <- grep("^legacy_frozen\\s*<-", code, value = TRUE)
  expect_gt(length(lf), 0L)
  expect_false(any(grepl("\\bu\\$", lf)),
               info = "legacy_frozen is populated from the live SSOT")
})

# ── 4. a full run reproduces all four committed artifacts byte-identically ────
test_that("all four committed artifacts regenerate byte-identically", {
  dir <- .sandbox()
  r <- .run(dir)
  expect_equal(r$status, 0L, info = r$output)
  expect_true(all(.written(dir)))
  for (t in TABLES) {
    got <- file.path(dir, "scripts/urps_baseline_scenarios", paste0(t, "_v3.0.0.csv"))
    expect_equal(readLines(got, warn = FALSE),
                 readLines(file.path(SD, paste0(t, "_v3.0.0.csv")), warn = FALSE),
                 info = t)
  }
})

# ── 5. changing the CURRENT provider count must not move the frozen side ──────
test_that("mutating the live SSOT baseline leaves the frozen reference untouched", {
  bump <- function(src) sub('^("Urogynecology[^,]*","URPS",)1306', '\\19999', src)
  a <- .sandbox(edit_gen = .fast)
  b <- .sandbox(edit_gen = .fast, edit_ssot = bump)
  expect_equal(.run(a)$status, 0L)
  rb <- .run(b); expect_equal(rb$status, 0L, info = rb$output)

  for (t in c("table1_published_preservation", "table3_count_age_decomposition")) {
    x <- .read(a, t); y <- .read(b, t)
    expect_equal(x$baseline_count, y$baseline_count, info = t)
    expect_equal(x$projected_count, y$projected_count, info = t)
  }
  expect_equal(as.integer(.read(b, "table1_published_preservation")$baseline_count[1]), 1295L)
})

# ── 6. changing the FROZEN reference must move the scientific outputs ─────────
test_that("altering the frozen 1,295 reference changes the decomposition", {
  drop_to <- function(src) sub("baseline\\s*=\\s*1295L", "baseline = 1200L", .fast(src))
  a <- .sandbox(edit_gen = .fast)
  b <- .sandbox(edit_gen = drop_to)
  .run(a); rb <- .run(b)
  # the frozen-endpoint guard is expected to fire once the record is internally
  # inconsistent -- which is itself the fail-closed behaviour under test
  if (rb$status != 0L) {
    expect_match(rb$output, "frozen", ignore.case = TRUE)
    expect_false(any(.written(b)), info = "artifacts written despite a failed frozen guard")
  } else {
    expect_equal(as.integer(.read(b, "table1_published_preservation")$baseline_count[1]), 1200L)
    ca <- .read(a, "table3_count_age_decomposition")
    cb <- .read(b, "table3_count_age_decomposition")
    expect_false(isTRUE(all.equal(ca$d_projected_vs_ref, cb$d_projected_vs_ref)))
  }
})

# ── 7. an incomplete frozen record fails BEFORE anything is written ───────────
test_that("a missing frozen provenance field fails closed, writing nothing", {
  strip <- function(src) grep('source_commit\\s*=', .fast(src), value = TRUE, invert = TRUE)
  dir <- .sandbox(edit_gen = strip)
  r <- .run(dir)
  expect_gt(r$status, 0L)
  expect_match(r$output, "source_commit", fixed = TRUE)
  expect_false(any(.written(dir)),
               info = "an artifact was written despite an incomplete frozen record")
})
