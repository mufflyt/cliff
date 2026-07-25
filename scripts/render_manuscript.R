#!/usr/bin/env Rscript
# Render the URPS supply-and-demand manuscript to Word.
#
# Uses the Rmd's own YAML output (word_document with the green-journal
# reference_docx + AMA CSL), so the journal styling is preserved. Paths resolve
# through here() from the repo root; package versions are pinned by renv.
#
# Usage:
#   Rscript scripts/render_manuscript.R                 # -> manuscript/manuscript_WORKFORCE_CLIFF.docx
#   Rscript scripts/render_manuscript.R path/to/out.docx
suppressPackageStartupMessages(library(here))
options(warn = 1)

args <- commandArgs(trailingOnly = TRUE)
rmd  <- here::here("manuscript", "manuscript_WORKFORCE_CLIFF.Rmd")
out  <- if (length(args) >= 1 && nzchar(args[[1]])) args[[1]] else
        here::here("manuscript", "manuscript_WORKFORCE_CLIFF.docx")

stopifnot(file.exists(rmd))

ok <- tryCatch({
  rmarkdown::render(
    input       = rmd,
    output_file = out,
    knit_root_dir = here::here(),   # so here()/data reads resolve at the repo root
    quiet       = TRUE
  )
  TRUE
}, error = function(e) { message("RENDER_ERROR: ", conditionMessage(e)); FALSE })

if (isTRUE(ok) && file.exists(out)) {
  cat(sprintf("RENDER_OK -> %s (%.0f KB)\n", out, file.size(out) / 1024))
} else {
  cat("RENDER_FAILED\n"); quit(status = 1)
}
