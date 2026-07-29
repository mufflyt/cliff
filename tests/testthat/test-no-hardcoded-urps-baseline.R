# tests/testthat/test-no-hardcoded-urps-baseline.R
library(testthat)

# Root the scan at the REPO ROOT, not testthat's working directory (which is
# tests/testthat/). Otherwise find_r_files(".") would scan the test files
# themselves — which legitimately carry these literals in assertions — and
# false-fail. here::here() resolves to the package root; rprojroot is a fallback.
.repo_root <- function() {
  tryCatch(
    here::here(),
    error = function(e) rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))
  )
}
find_r_files <- function(root = .repo_root()) {
  list.files(
    root,
    pattern = "\\.[Rr]$",
    recursive = TRUE,
    full.names = TRUE
  )
}
strip_allowed_files <- function(paths, root = .repo_root()) {
  # Match anywhere in the (normalized) path so exclusion is robust to absolute vs
  # relative forms, and test EACH pattern (grepl() with a length>1 pattern vector
  # silently uses only its first element). Non-production trees (tests, docs, the
  # renv/packrat libraries, data-raw) are excluded; the SSOT seam itself is
  # exempt because it DOCUMENTS the forbidden headline values by design.
  excluded_patterns <- c(
    "(^|/)tests/",
    "(^|/)docs/",
    "(^|/)renv/",
    "(^|/)packrat/",
    "(^|/)data-raw/",
    "(^|/)R/urps_baseline\\.R$",
    "test-no-hardcoded-urps-baseline\\.R$"
  )
  norm <- gsub("\\\\", "/", paths)
  keep <- !vapply(
    norm,
    function(path) {
      any(vapply(
        excluded_patterns,
        function(pat) grepl(pat, path),
        logical(1)
      ))
    },
    logical(1)
  )
  paths[keep]
}
find_literal <- function(files, literal) {
  pattern <- paste0(
    "(?<![0-9])",
    literal,
    "(?![0-9])"
  )
  hits <- lapply(files, function(path) {
    lines <- readLines(
      path,
      warn = FALSE,
      encoding = "UTF-8"
    )
    line_numbers <- grep(
      pattern,
      lines,
      perl = TRUE
    )
    if (!length(line_numbers)) {
      return(NULL)
    }
    data.frame(
      file = path,
      line = line_numbers,
      text = trimws(lines[line_numbers]),
      stringsAsFactors = FALSE
    )
  })
  do.call(
    rbind,
    Filter(Negate(is.null), hits)
  )
}
test_that("production code contains no hardcoded SSOT counts", {
  files <- strip_allowed_files(
    find_r_files()
  )
  forbidden_literals <- c(
    "1031",
    "1339",
    "308",
    "1295",
    "264"
  )
  all_hits <- lapply(
    forbidden_literals,
    function(value) {
      hits <- find_literal(files, value)
      if (is.null(hits)) {
        return(NULL)
      }
      hits$literal <- value
      hits
    }
  )
  all_hits <- Filter(
    Negate(is.null),
    all_hits
  )
  if (!length(all_hits)) {
    succeed()
    return(invisible())
  }
  hits <- do.call(rbind, all_hits)
  formatted <- paste0(
    hits$file,
    ":",
    hits$line,
    " contains ",
    hits$literal,
    " — ",
    hits$text,
    collapse = "\n"
  )
  fail(
    paste(
      "Hardcoded URPS workforce values found.",
      "Use mufflyaccess::urps_count() instead.",
      formatted,
      sep = "\n"
    )
  )
})
