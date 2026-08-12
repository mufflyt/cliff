#!/usr/bin/env Rscript
# Audit the rendered manuscript's word counts against the target journal limits.
#
# Counts, from the rendered .docx (so the numbers match what an editor sees):
#   * the structured abstract (OBJECTIVE/METHODS/RESULTS/CONCLUSIONS), and
#   * the main text (Introduction through the end of the Conclusion), excluding
#     the abstract, tables, figure/table legends, and the reference list, the
#     way a journal main-text limit is applied.
#
# Limits are read from the Rmd YAML (word_count / abstract_word_count) so the
# declared target and the audit share one source. Nonzero exit if either is over.
#
# Usage:
#   Rscript scripts/check_wordcount.R                       # default docx
#   Rscript scripts/check_wordcount.R path/to/manuscript.docx

suppressPackageStartupMessages(library(here))

args <- commandArgs(trailingOnly = TRUE)
docx <- if (length(args) >= 1 && nzchar(args[[1]])) args[[1]] else
        here::here("manuscript", "manuscript_WORKFORCE_CLIFF.docx")
rmd  <- here::here("manuscript", "manuscript_WORKFORCE_CLIFF.Rmd")

if (!file.exists(docx)) {
  stop("Rendered docx not found: ", docx, "\nRender first: Rscript scripts/render_manuscript.R")
}

# ---- read the declared limits from the Rmd YAML ----------------------------
read_yaml_int <- function(rmd_path, key, default = NA_integer_) {
  if (!file.exists(rmd_path)) return(default)
  ln <- grep(paste0("^", key, ":"), readLines(rmd_path, warn = FALSE), value = TRUE)
  if (!length(ln)) return(default)
  n <- suppressWarnings(as.integer(gsub("[^0-9]", "", ln[1])))
  if (is.na(n)) default else n
}
abstract_limit <- read_yaml_int(rmd, "abstract_word_count", 300L)
maintext_limit <- read_yaml_int(rmd, "word_count", 3700L)

# ---- pull plain-text paragraphs out of the docx ----------------------------
xml <- readLines(unz(docx, "word/document.xml"), warn = FALSE, encoding = "UTF-8")
xml <- paste(xml, collapse = "")
xml <- gsub("<w:tbl>.*?</w:tbl>", "", xml)          # drop tables entirely
xml <- gsub("</w:p>", "\n", xml)                     # paragraph breaks
xml <- gsub("<[^>]+>", "", xml)                      # strip remaining tags
# unescape the handful of XML entities pandoc emits
for (e in list(c("&amp;", "&"), c("&lt;", "<"), c("&gt;", ">"),
               c("&quot;", '"'), c("&apos;", "'"), c("&#8217;", "'"),
               c("&#8220;", '"'), c("&#8221;", '"')))
  xml <- gsub(e[1], e[2], xml, fixed = TRUE)
paras <- trimws(strsplit(xml, "\n")[[1]])
paras <- paras[nzchar(paras)]

nwords <- function(x) if (!length(x)) 0L else sum(lengths(regmatches(x, gregexpr("\\S+", x))))

# ---- abstract: the four structured paragraphs ------------------------------
abs_para <- grep("^(OBJECTIVE|METHODS|RESULTS|CONCLUSIONS):", paras)
abstract_words <- nwords(paras[abs_para])

# ---- main text: Introduction .. (before) References ------------------------
intro_i <- which(grepl("^Introduction$", paras))[1]
refs_i  <- which(grepl("^References$", paras))[1]
if (is.na(intro_i)) intro_i <- 1L
if (is.na(refs_i))  refs_i  <- length(paras) + 1L
body <- paras[seq.int(intro_i, refs_i - 1L)]
# drop figure/table legends and the italic table footnotes
body <- body[!grepl("^(Table|Figure|Appendix Table|Appendix S) ?[0-9SIVX]", body)]
maintext_words <- nwords(body)

# ---- report -----------------------------------------------------------------
line <- function(label, n, lim) {
  status <- if (is.na(lim)) "" else if (n <= lim) sprintf("OK (<= %d)", lim) else
            sprintf("OVER by %d (limit %d)", n - lim, lim)
  cat(sprintf("  %-26s %6d   %s\n", label, n, status))
}
cat("Word-count audit:", basename(docx), "\n")
line("Abstract",  abstract_words, abstract_limit)
line("Main text", maintext_words, maintext_limit)

over <- (!is.na(abstract_limit) && abstract_words > abstract_limit) ||
        (!is.na(maintext_limit) && maintext_words > maintext_limit)
if (over) { cat("\nRESULT: OVER LIMIT\n"); quit(status = 1) }
cat("\nRESULT: within limits\n")
