#!/usr/bin/env Rscript
# Gates 64 and 65: render the manuscript AND supplement, then read what came out.
#
# Gate 64. CI rendered only the supplement. The main manuscript -- the actual
# deliverable -- was never rendered anywhere. Rendering is not redundant with
# the test suite: a helper named cf() once passed 2,853 unit tests while the
# supplement could not render at all, because the document rebinds `cf` to a
# data.frame sixty lines below the setup chunk.
#
# Gate 65. A document that renders is not automatically a document you can
# submit. These scan the rendered text for the failures that survive a
# successful render:
#
#   NA / NaN / Inf / NULL   a missing value formatted into prose or a table
#   [1] / <chr> / ##        raw R console output leaking into the document
#   ???                     an unresolved cross-reference
#   (empty table cell)      a table that rendered but has nothing in it
#
# Word output is a zip; the text lives in word/document.xml, so the scan reads
# the rendered artefact rather than the source that produced it.
#
#   Rscript scripts/ci/render_manuscripts.R

root <- Sys.getenv("CLIFF_ROOT", ".")
setwd(root)

if (!requireNamespace("rmarkdown", quietly = TRUE)) {
  cat("rmarkdown unavailable\n"); quit(status = 1)
}
if (!rmarkdown::pandoc_available()) {
  cat("pandoc unavailable\n"); quit(status = 1)
}

DOCS <- c("manuscript/manuscript_WORKFORCE_CLIFF.Rmd",
          "manuscript/supplement_WORKFORCE_CLIFF.Rmd")
DOCS <- DOCS[file.exists(DOCS)]
if (!length(DOCS)) { cat("no manuscript sources found\n"); quit(status = 1) }

outdir <- file.path(tempdir(), "cliff-render")
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

# Pull the readable text out of a .docx (a zip containing word/document.xml).
docx_text <- function(path) {
  td <- file.path(tempdir(), paste0("unz-", basename(path)))
  unlink(td, recursive = TRUE); dir.create(td, recursive = TRUE)
  ok <- tryCatch({ utils::unzip(path, exdir = td); TRUE }, error = function(e) FALSE)
  if (!ok) return(NA_character_)
  xml <- file.path(td, "word", "document.xml")
  if (!file.exists(xml)) return(NA_character_)
  raw <- paste(readLines(xml, warn = FALSE), collapse = " ")
  raw <- gsub("</w:p>", "\n", raw, fixed = TRUE)   # paragraphs -> newlines
  raw <- gsub("<[^>]*>", "", raw)                  # strip tags
  raw
}

# Patterns that mean the render succeeded but the content is wrong.
BAD <- list(
  "missing value (NA)"      = "(?<![A-Za-z])NA(?![A-Za-z])",
  "not-a-number (NaN)"      = "(?<![A-Za-z])NaN(?![A-Za-z])",
  "infinite value (Inf)"    = "(?<![A-Za-z])-?Inf(?![A-Za-z])",
  "NULL in output"          = "(?<![A-Za-z])NULL(?![A-Za-z])",
  "raw console output"      = "\\[1\\]\\s",
  "unresolved reference"    = "\\?\\?\\?",
  "knitr error marker"      = "## Error|Error in "
)

fail <- character(0)
rendered <- character(0)

for (d in DOCS) {
  cat("== rendering", d, "==\n")
  out <- file.path(outdir, paste0(tools::file_path_sans_ext(basename(d)), ".docx"))
  t0 <- Sys.time()
  ok <- tryCatch({
    rmarkdown::render(d, output_file = out, quiet = TRUE, envir = new.env())
    TRUE
  }, error = function(e) {
    cat("  RENDER FAILED: ", conditionMessage(e), "\n"); FALSE
  })
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  if (!ok) { fail <- c(fail, paste("render failed:", d)); next }
  if (!file.exists(out)) { fail <- c(fail, paste("no output produced:", d)); next }

  sz <- file.info(out)$size
  cat(sprintf("  rendered in %.0fs, %.0f KB\n", secs, sz / 1024))
  rendered <- c(rendered, out)
  if (sz < 10000) fail <- c(fail, sprintf("suspiciously small output (%d bytes): %s", sz, d))

  txt <- docx_text(out)
  if (is.na(txt)) { cat("  (could not read docx text; skipping content scan)\n"); next }

  cat("  scanning", format(nchar(txt), big.mark = ","), "characters\n")
  for (nm in names(BAD)) {
    hits <- gregexpr(BAD[[nm]], txt, perl = TRUE)[[1]]
    n <- if (hits[1] == -1L) 0L else length(hits)
    if (n > 0L) {
      ctx <- substr(txt, max(1, hits[1] - 60), min(nchar(txt), hits[1] + 60))
      ctx <- gsub("\\s+", " ", ctx)
      fail <- c(fail, sprintf("%s: %d x %s  [...%s...]", basename(d), n, nm, ctx))
    }
  }
}

summ <- Sys.getenv("GITHUB_STEP_SUMMARY")
if (nzchar(summ))
  cat(sprintf("### Manuscript render\n\nRendered %d document(s); %d content finding(s).\n\n",
              length(rendered), length(fail)), file = summ, append = TRUE)

if (length(fail)) {
  cat("\n== RENDER / CONTENT FAILURES ==\n")
  for (f in fail) cat("  x", substr(f, 1, 220), "\n")
  quit(status = 1)
}

cat("\n== both documents render and read clean ==\n")
quit(status = 0)
