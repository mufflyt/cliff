# GATE: a change in scientific SCOPE must not propagate as valid-looking output.
#
# This exists because of one adjudicated failure, not as general policy.
#
# MIGS was intentionally withdrawn from data/departure_window_sensitivity.csv (it is
# an exploratory focused-practice cohort, not pooled with the board-certified ones --
# reviewer decision 2026-07-19). That upstream scope change was correct.
# scripts/sensitivity_grid.R did not adapt: it reindexes with
#
#     summ[match(c("GO","URPS","MIGS"), summ$subspecialty_abbrev), ]
#
# so match() returns NA for the withdrawn cohort and the reindex MANUFACTURES a row
# of NAs. Nothing errors. The row is written to data/sensitivity_grid_summary.csv and
# manuscript/supplement_WORKFORCE_CLIFF.Rmd:1078 performs the same reindex, so
# Appendix Table S17 would render it as though it were a result.
#
# The invariant: a cohort absent from the source data must cause an explicit failure
# or an intentional omission -- never an NA row that looks like a published result.
#
# Adjudication: docs/adjudication/sensitivity_grid.md

skip_if_no_repo()

ROOT <- cliff_repo_root()
COHORTS <- c("URPS", "GO", "MIGS")

# ── 1. OUTCOME invariant: no committed artifact may carry an NA cohort row ──────
# This is the property that actually matters. It is cheap, universal, and it fails
# the moment a corrupt regeneration is committed, whatever produced it.
test_that("no committed artifact carries an NA cohort key or an all-NA row", {
  csvs <- c(list.files(file.path(ROOT, "data"), "\\.csv$", full.names = TRUE),
            list.files(file.path(ROOT, "scripts"), "\\.csv$",
                       full.names = TRUE, recursive = TRUE))
  skip_if_not(length(csvs) > 0, "no artifacts found")

  offenders <- character()
  for (p in csvs) {
    d <- tryCatch(utils::read.csv(p, stringsAsFactors = FALSE,
                                  na.strings = c("NA", "")),
                  error = function(e) NULL)
    if (is.null(d) || !nrow(d)) next
    key <- grep("subspecialty_abbrev|^ab$|^subspec$", names(d), value = TRUE)[1]
    if (is.na(key)) next
    # an NA cohort key is always corrupt: every row of these tables is per-cohort
    if (any(is.na(d[[key]]))) {
      offenders <- c(offenders, sprintf("%s (NA in column '%s')",
                                        sub(paste0("^", ROOT, "/"), "", p), key))
    }
  }
  expect_equal(offenders, character(0),
               info = paste0(
                 "Artifact(s) contain a row whose cohort key is NA. This is the\n",
                 "signature of a hardcoded reindex against a cohort the source data\n",
                 "no longer contains -- see docs/adjudication/sensitivity_grid.md.\n",
                 "A withdrawn cohort must be omitted or must stop() the generator,\n",
                 "never emitted as an NA row.\n  ",
                 paste(offenders, collapse = "\n  ")))
})

# ── 2. STATIC invariant: the defective pattern must not spread ──────────────────
# Registry-based: fails on GROWTH, so it is never permanently red while the three
# known sites await their scientific decision.
test_that("hardcoded cohort reindexing does not spread to new files", {
  reg <- file.path(ROOT, "scripts", "ci", "cohort_reindex_debt.txt")
  skip_if_not(file.exists(reg), "debt registry not present")
  known <- readLines(reg, warn = FALSE)
  known <- trimws(known[!grepl("^\\s*#", known) & nzchar(trimws(known))])

  files <- c(list.files(file.path(ROOT, "scripts"), "\\.R$",
                        full.names = TRUE, recursive = TRUE),
             list.files(file.path(ROOT, "R"), "\\.R$", full.names = TRUE),
             list.files(file.path(ROOT, "manuscript"), "\\.(R|Rmd)$",
                        full.names = TRUE, recursive = TRUE))
  found <- character()
  for (p in files) {
    src <- readLines(p, warn = FALSE)
    code <- src[!grepl("^\\s*#", src)]
    # match() against a literal vector naming >= 2 cohorts, used as a row index
    hit <- grepl("\\[\\s*match\\(\\s*c\\(", code) &
           vapply(code, function(l) sum(vapply(COHORTS,
                    function(x) grepl(paste0('"', x, '"'), l), logical(1))) >= 2L,
                  logical(1))
    if (any(hit)) found <- c(found, sub(paste0("^", ROOT, "/"), "", p))
  }
  new_sites <- setdiff(unique(found), known)
  expect_equal(new_sites, character(0),
               info = paste0(
                 "New hardcoded cohort reindex(es). `x[match(c(...), x$key), ]`\n",
                 "silently yields an NA row when a named cohort is absent.\n",
                 "Intersect against the cohorts actually present and stop() if one\n",
                 "the manuscript names is missing.\n  ",
                 paste(new_sites, collapse = "\n  ")))
})

# ── 3. The specific known-firing case, pinned ──────────────────────────────────
test_that("sensitivity_grid.R is still the only FIRING site, and its input is 2-cohort", {
  win <- file.path(ROOT, "data", "departure_window_sensitivity.csv")
  skip_if_not(file.exists(win), "window sensitivity artifact not present")
  d <- utils::read.csv(win, stringsAsFactors = FALSE)
  present <- sort(unique(d$subspecialty_abbrev))

  # Pin the scope decision so that MIGS silently REAPPEARING is also caught.
  expect_setequal(present, c("GO", "URPS"))

  # And the committed grid summary must not yet have been regenerated against it
  # without the generator being fixed first.
  gs <- file.path(ROOT, "data", "sensitivity_grid_summary.csv")
  if (file.exists(gs)) {
    g <- utils::read.csv(gs, stringsAsFactors = FALSE, na.strings = c("NA", ""))
    expect_false(any(is.na(g$subspecialty_abbrev)),
                 info = paste("sensitivity_grid_summary.csv now carries an NA row.",
                              "The generator must be made fail-closed BEFORE this",
                              "artifact is regenerated -- see",
                              "docs/adjudication/sensitivity_grid.md."))
  }
  succeed()
})
