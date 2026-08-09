# Narrow, SEMANTIC docs guard for the URPS baseline.
#
# WHY: code is already guarded (test-no-unqualified-urps-baseline.R scans
# production R and forbids hand-typed baselines), but that guard deliberately
# skips docs -- and SIMULATION_TO_CLIFF_INTEGRATION_PLAN.md drifted once,
# presenting the RETIRED v2.1.0 cell 1,332 as the current mufflyaccess contract.
# This closes exactly that hole and nothing wider.
#
# SCOPE (deliberately narrow):
#   * Scans ONLY authoritative, current-facing docs (CURRENT_DOCS), not archived
#     notes, handoffs, method references, or dated records -- those may
#     legitimately discuss the retired cells.
#   * Fails only when a retired cell (1,332 national / 1,329 CONUS) appears
#     UNLABELED, i.e. without a same-line history/version marker. A line that
#     says "1,332/1,329 are RETIRED v2.1.0 cells" is allowed.
#   * Pins the CURRENT contract pair 1,306 / 1,303.
#   * Does NOT touch or adjudicate the open 1,295-vs-1,339 PI baseline question.
#   * Does NOT alter urps_baseline() or any SSOT code.
#
# Long term the current-facing docs should RENDER the baseline from the contract
# rather than hand-type it; until then this prevents recurrence.

suppressPackageStartupMessages({library(testthat); library(here)})

# Authoritative current-facing docs (repo-root relative). Add new current-facing
# docs here; do NOT add historical/archived notes.
CURRENT_DOCS <- c("README.md", "SIMULATION_TO_CLIFF_INTEGRATION_PLAN.md")

# Current canonical contract (mufflyaccess v3.0.0, 2023 board_certified_active).
CURRENT_NATIONAL <- "1,306"
CURRENT_CONUS    <- "1,303"

# Retired v2.1.0 cells, matched formatted or unformatted, not inside a longer
# digit run.
STALE_RE <- "(?<![0-9])1,?33[0-9](?![0-9])"          # 1,33x family (332/329 live here)
STALE_EXACT <- c("1,332", "1332", "1,329", "1329")
# A same-line marker that makes a mention explicitly historical/versioned.
HIST_LABEL <- paste(
  "retired", "supersed", "historical", "history", "former", "obsolete",
  "deprecat", "no longer", "must never", "never used", "do not use", "don't use",
  "v2\\.1", "2\\.1\\.0", "pre-v3", "prior to v3", "was the", "used to",
  sep = "|")

.read_doc <- function(f) {
  p <- here::here(f)
  if (file.exists(p)) readLines(p, warn = FALSE) else character(0)
}

# TRUE iff the line names a retired cell WITHOUT a same-line history/version label.
.is_unlabeled_stale <- function(ln) {
  has_stale <- any(vapply(STALE_EXACT, function(s) grepl(s, ln, fixed = TRUE), logical(1)))
  has_stale && !grepl(HIST_LABEL, ln, ignore.case = TRUE)
}

test_that("current-facing docs never present retired v2.1.0 URPS cells as current", {
  offenders <- character(0)
  for (f in CURRENT_DOCS) {
    lines <- .read_doc(f)
    for (i in seq_along(lines)) {
      if (.is_unlabeled_stale(lines[i]))
        offenders <- c(offenders, sprintf("%s:%d: %s", f, i, trimws(lines[i])))
    }
  }
  expect_equal(
    length(offenders), 0L,
    info = paste0(
      "Retired v2.1.0 URPS cell(s) (1,332 national / 1,329 CONUS) appear UNLABELED in a ",
      "current-facing doc. Either remove them or mark them retired/v2.1.0. The current ",
      "contract is ", CURRENT_NATIONAL, " (national) / ", CURRENT_CONUS, " (CONUS). Offenders:\n",
      paste(offenders, collapse = "\n")))
})

test_that("the current national contract value is stated in a current-facing doc", {
  txt <- unlist(lapply(CURRENT_DOCS, .read_doc))
  skip_if(length(txt) == 0L, "no current-facing docs found")
  expect_true(
    any(grepl(CURRENT_NATIONAL, txt, fixed = TRUE)),
    info = paste0("No current-facing doc states the canonical national baseline ",
                  CURRENT_NATIONAL, "."))
  # If a doc cites a CONUS baseline, it must be the current 1,303 (not a stale cell).
  conus_lines <- grep("CONUS", txt, ignore.case = TRUE, value = TRUE)
  conus_baseline <- conus_lines[grepl("1,3[0-9][0-9]", conus_lines)]
  if (length(conus_baseline))
    expect_true(any(grepl(CURRENT_CONUS, conus_baseline, fixed = TRUE)),
                info = "A current-facing doc cites a CONUS baseline that is not 1,303.")
})

test_that("negative control: the guard flags an unlabeled stale cell and exempts a labeled one", {
  # would fail the guard (asserts a retired cell as current)
  expect_true(.is_unlabeled_stale("The current mufflyaccess contract is 1,332 (2023 active)."))
  expect_true(.is_unlabeled_stale("URPS baseline 1,329 CONUS."))
  # allowed: explicitly labeled historical / versioned
  expect_false(.is_unlabeled_stale("1,332/1,329 are RETIRED v2.1.0 cells."))
  expect_false(.is_unlabeled_stale("Historically the v2.1.0 cell was 1,332."))
  # unrelated numbers and the current pair never trip it
  expect_false(.is_unlabeled_stale("national 1,306 / CONUS 1,303 (v3.0.0)."))
  expect_false(.is_unlabeled_stale("the 1,295-vs-1,339 clash is a PI decision"))
})
