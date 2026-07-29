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
  prod_dirs <- c("R", "manuscript", "scripts", "src", "inst")
  files <- unlist(lapply(file.path(root, prod_dirs), function(r)
    if (dir.exists(r)) list.files(r, pattern = "\\.[Rr]$", recursive = TRUE,
                                  full.names = TRUE) else character(0)))
  # never scan test / doc / historical / generated locations
  skip_pat <- paste0("(^|/)(tests?|testthat|docs|vignettes|renv|packrat|man|",
                     "data-raw)(/|$)|historical|comparison|CHANGELOG|NEWS")
  files <- files[!grepl(skip_pat, files, ignore.case = TRUE)]

  # the workforce TOTALS that must come from urps_count(), not a literal:
  #   1332 = 2023 board_certified_active / national   1329 = ... / conus
  #   1339 = 2025 roster_snapshot / national          1336 = ... / conus
  totals <- c("1332", "1329", "1339", "1336")
  pat <- paste0("(?<![0-9.])(", paste(totals, collapse = "|"), ")(?![0-9.])")

  hits <- do.call(rbind, Filter(Negate(is.null), lapply(files, function(p) {
    ln  <- readLines(p, warn = FALSE, encoding = "UTF-8")
    idx <- grep(pat, ln, perl = TRUE)
    idx <- idx[!grepl("urps_count|#\\s*ssot-ok", ln[idx])]   # exempt qualified/marked lines
    if (!length(idx)) return(NULL)
    data.frame(file = p, line = idx, text = trimws(ln[idx]), stringsAsFactors = FALSE)
  })))

  if (is.null(hits) || !nrow(hits)) { succeed(); return(invisible(NULL)) }
  fail(paste0(
    "Unqualified canonical URPS workforce total(s) in production code.\n",
    "Use mufflyaccess::urps_count(year, measure, geography, include_urology).\n",
    "Reminder: 1332/1329 = 2023 board_certified_active (national/conus); ",
    "1339/1336 = 2025 roster_snapshot -- not the 2023 active count.\n",
    "If a literal is legitimate (test/doc/historical table), move it out of ",
    "production code or annotate the line `# ssot-ok`.\n",
    paste0("  ", hits$file, ":", hits$line, "  ", hits$text, collapse = "\n")))
})
