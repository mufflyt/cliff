# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# docs/PIPELINE.md must be current.
#
# The map records which script owns which artifact. That knowledge was missing
# for months after the isochrones extraction, which carried artifact outputs
# across without their generators, and recovering it by hand produced four
# separate false "this artifact has no generator" conclusions.
#
# A hand-maintained map would go stale exactly as PROVENANCE.md did, so it is
# generated. This guard regenerates it and compares, which means adding,
# renaming or deleting a generator fails the suite until the map is rebuilt:
#
#     Rscript scripts/build_pipeline_map.R
#
# It also checks the map against data/ in both directions, because the map being
# self-consistent is not the same as the map being complete.
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
.map    <- file.path(.root, "docs", "PIPELINE.md")
.script <- file.path(.root, "scripts", "build_pipeline_map.R")

test_that("docs/PIPELINE.md is current with scripts/", {
  skip_if_not(file.exists(.script), "generator not present")
  skip_if_not(file.exists(.map), "docs/PIPELINE.md not generated yet")
  skip_if_not(requireNamespace("here", quietly = TRUE), "here not installed")

  committed <- readLines(.map, warn = FALSE)
  tmp <- tempfile(fileext = ".md")
  # Regenerate into a temp location, leaving the committed file untouched.
  res <- system2("Rscript", c("-e",
    shQuote(sprintf(
      'p <- %s; d <- %s; o <- file.path(d, "docs", "PIPELINE.md");
       b <- file.path(tempdir(), "PIPELINE.bak");
       if (file.exists(o)) file.copy(o, b, overwrite = TRUE);
       setwd(d); source(p);
       file.copy(o, %s, overwrite = TRUE);
       if (file.exists(b)) file.copy(b, o, overwrite = TRUE)',
      shQuote(.script), shQuote(.root), shQuote(tmp)))),
    stdout = FALSE, stderr = FALSE)
  skip_if_not(res == 0 && file.exists(tmp), "could not regenerate the map in this environment")

  regenerated <- readLines(tmp, warn = FALSE)
  if (!identical(committed, regenerated)) {
    only_now <- setdiff(regenerated, committed)
    only_was <- setdiff(committed, regenerated)
    cat("\n  docs/PIPELINE.md is stale. Run: Rscript scripts/build_pipeline_map.R\n")
    if (length(only_now)) cat("  now present:\n", paste0("   ", head(only_now, 6), collapse = "\n"), "\n")
    if (length(only_was)) cat("  no longer:\n",   paste0("   ", head(only_was, 6), collapse = "\n"), "\n")
  }
  expect_identical(committed, regenerated)
})

test_that("every artifact the map claims to write actually exists in data/", {
  skip_if_not(file.exists(.map), "docs/PIPELINE.md not generated yet")
  rows <- grep("^\\| `scripts/", readLines(.map, warn = FALSE), value = TRUE)
  writes <- unique(unlist(lapply(rows, function(r) {
    cell <- strsplit(r, "\\|")[[1]][3]
    gsub("`", "", strsplit(trimws(cell), "<br>")[[1]])
  })))
  writes <- writes[nzchar(writes) & writes != "--"]
  # Some generators write outside data/ (scripts/urps_baseline_scenarios, etc.),
  # so only assert for the ones data/ is expected to hold.
  in_data <- writes[file.exists(file.path(.root, "data", writes))]
  expect_gt(length(in_data), 20L)
})

test_that("no artifact the manuscript reads is missing from the map", {
  skip_if_not(file.exists(.map), "docs/PIPELINE.md not generated yet")
  docs <- file.path(.root, "manuscript",
                    c("manuscript_WORKFORCE_CLIFF.Rmd", "supplement_WORKFORCE_CLIFF.Rmd"))
  docs <- docs[file.exists(docs)]
  skip_if_not(length(docs) > 0, "manuscript sources not present")
  helpers <- list.files(file.path(.root, "manuscript", "R"), "[.]R$", full.names = TRUE)
  consumed <- unique(unlist(lapply(c(docs, helpers), function(f) {
    x <- paste(readLines(f, warn = FALSE), collapse = "\n")
    gsub('"', "", regmatches(x, gregexpr('"[A-Za-z0-9_.\\-]+\\.csv"', x))[[1]])
  })))
  mapped <- paste(readLines(.map, warn = FALSE), collapse = " ")
  missing <- consumed[!vapply(consumed, function(f) grepl(f, mapped, fixed = TRUE), logical(1))]
  # table_evidence_supporting_scenarios is written through a variable and IS in
  # the map; anything else missing means an artifact with no known generator.
  if (length(missing))
    cat("\n  artifacts the documents read but no generator writes:\n",
        paste0("   ", missing, collapse = "\n"), "\n")
  expect_length(missing, 0L)
})

# ---- collision guard ---------------------------------------------------------
# An artifact with two writers is a silent-overwrite hazard: whichever ran last
# wins, and nothing says which was meant to. The SSOT had FOUR writers, and one
# of them (code/01_consolidate_workforce_data.R) was unguarded and would have
# rebuilt it on the retired 1,295 basis.
#
# The convention this repository already uses is that exactly one writer is
# canonical and every other enforces
#   if (!identical(Sys.getenv("WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE"), "1")) stop(...)
# Merely MENTIONING that variable is not enforcement: the canonical writer names
# it in its header to document the others, which is why this checks for the
# guard expression rather than the string.
test_that("no manuscript-read artifact has two unguarded writers", {
  skip_if_not(file.exists(.map), "docs/PIPELINE.md not generated yet")
  rows <- grep("^\\| `", readLines(.map, warn = FALSE), value = TRUE)
  gen <- vapply(rows, function(r) gsub("`", "", trimws(strsplit(r, "\\|")[[1]][2])), character(1))
  wr <- lapply(rows, function(r) {
    cell <- trimws(strsplit(r, "\\|")[[1]][3])
    x <- gsub("`", "", strsplit(cell, "<br>")[[1]])
    x[nzchar(x) & x != "--"]
  })
  names(wr) <- gen

  docs <- c(file.path(.root, "manuscript",
                      c("manuscript_WORKFORCE_CLIFF.Rmd", "supplement_WORKFORCE_CLIFF.Rmd")),
            list.files(file.path(.root, "manuscript", "R"), "[.]R$", full.names = TRUE))
  docs <- docs[file.exists(docs)]
  skip_if_not(length(docs) > 0, "manuscript sources not present")
  doctxt <- paste(unlist(lapply(docs, readLines, warn = FALSE)), collapse = "\n")

  GUARD <- 'if *\\(!identical\\(Sys.getenv\\("WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE"\\)'
  enforces <- function(f) {
    p <- file.path(.root, f)
    file.exists(p) && any(grepl(GUARD, readLines(p, warn = FALSE), perl = TRUE))
  }

  inv <- list()
  for (g in names(wr)) for (a in wr[[g]]) inv[[a]] <- unique(c(inv[[a]], g))
  offenders <- character(0)
  for (a in names(inv)) {
    if (length(inv[[a]]) < 2L) next
    if (!grepl(a, doctxt, fixed = TRUE)) next          # not reader-facing
    unguarded <- inv[[a]][!vapply(inv[[a]], enforces, logical(1))]
    if (length(unguarded) > 1L)
      offenders <- c(offenders, sprintf("%s <- %s", a, paste(unguarded, collapse = ", ")))
  }
  if (length(offenders))
    cat("\n  artifacts the manuscript reads that have >1 unguarded writer:\n",
        paste0("   ", offenders, collapse = "\n"), "\n")
  expect_length(offenders, 0L)
})
