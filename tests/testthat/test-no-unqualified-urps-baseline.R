# [APPLY IN: cliff AND twostep -- copy verbatim into tests/testthat/]
#
# Fails when a v2.1.0 canonical URPS WORKFORCE TOTAL appears as an UNQUALIFIED
# baseline in PRODUCTION code. It does NOT ban these values everywhere: they may
# legitimately appear in tests, docs, vignettes, historical / comparison tables,
# or NEWS. It flags their use as an unqualified canonical count.
#
# A flagged line is exempt when it either routes through
# `mufflyaccess::urps_count(...)` or is explicitly annotated `# ssot-ok`.
#
# Correct usage instead of a literal:
#   mufflyaccess::urps_count(year = 2023, measure = "board_certified_active",
#                            geography = "national", include_urology = TRUE)  # 1332
library(testthat)

test_that("no unqualified canonical URPS workforce total in production code", {
  # testthat runs with the working dir at tests/testthat -- anchor at the repo
  # root (nearest ancestor with a DESCRIPTION) so production dirs resolve.
  find_root <- function() {
    d <- normalizePath(getwd(), winslash = "/")
    for (i in 1:8) {
      if (file.exists(file.path(d, "DESCRIPTION"))) return(d)
      parent <- dirname(d); if (identical(parent, d)) break; d <- parent
    }
    normalizePath(getwd(), winslash = "/")
  }
  root <- find_root()
  # scan ALL production R across the repo (apps, scripts, manuscript, pkg code),
  # excluding tests / docs / vendored / generated / data locations.
  all_r <- list.files(root, pattern = "\\.[Rr]$", recursive = TRUE, full.names = TRUE)
  rel <- sub(paste0(root, "/"), "", all_r, fixed = TRUE)   # path relative to repo root
  skip_pat <- paste0("(^|/)(tests?|testthat|docs|vignettes|renv|packrat|man|",
                     "data-raw|data)(/|$)|historical|comparison|CHANGELOG|NEWS|\\.Rcheck(/|$)")
  files <- all_r[!grepl(skip_pat, rel, ignore.case = TRUE)]

  # the workforce TOTALS that must come from urps_count(), not a literal:
  #   contract v3.0.0 CURRENT:  1306 = 2023 board_certified_active / national
  #                             1303 = ... / conus
  #   2025 roster_snapshot:     1339 = national   1336 = conus
  #   RETIRED v2.1.0 cells:     1332 = national   1329 = conus (never present as current)
  #   1295 = the LEGACY frozen SGS projection cohort (1031 ABOG + 264 ABU); NOT a
  #     mufflyaccess canonical cell, permitted ONLY on a line annotated
  #     `# ssot-ok: legacy frozen SGS projection cohort` (see the exemption below).
  totals <- c("1306", "1303", "1339", "1336", "1332", "1329", "1295")
  pat <- paste0("(?<![0-9.])(", paste(totals, collapse = "|"), ")(?![0-9.])")

  hits <- do.call(rbind, Filter(Negate(is.null), lapply(files, function(p) {
    ln   <- readLines(p, warn = FALSE, encoding = "UTF-8")
    code <- sub("#.*$", "", ln)                              # ignore trailing comments / doc mentions
    idx  <- grep(pat, code, perl = TRUE)                     # a total used in actual CODE
    idx  <- idx[!grepl("urps_count|#\\s*ssot-ok", ln[idx])]  # exempt qualified / explicitly-marked lines
    if (!length(idx)) return(NULL)
    data.frame(file = p, line = idx, text = trimws(ln[idx]), stringsAsFactors = FALSE)
  })))

  if (is.null(hits) || !nrow(hits)) { succeed(); return(invisible(NULL)) }
  fail(paste0(
    "Unqualified canonical URPS workforce total(s) in production code.\n",
    "Use mufflyaccess::urps_count(year, measure, geography, include_urology).\n",
    "Reminder: 1306/1303 = current 2023 board_certified_active (national/conus); ",
    "1339/1336 = 2025 roster_snapshot; 1332/1329 = RETIRED v2.1.0 cells (never ",
    "present as current); 1295 = the legacy frozen SGS projection cohort.\n",
    "If a literal is legitimate (test/doc/historical table), move it out of ",
    "production code or annotate the line `# ssot-ok` (for 1295 use ",
    "`# ssot-ok: legacy frozen SGS projection cohort`).\n",
    paste0("  ", hits$file, ":", hits$line, "  ", hits$text, collapse = "\n")))
})
