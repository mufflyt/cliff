#!/usr/bin/env Rscript
# Run the URPS Effective-Adequacy Explorer guard suite.
#   Rscript tests/run_guards.R      (from cliff/shiny_urps_adequacy/)
suppressPackageStartupMessages(library(testthat))
here <- tryCatch(dirname(sys.frame(1)$ofile), error=function(e) "tests")
td <- Find(dir.exists, c(file.path(here,"testthat"), "tests/testthat", "testthat"))
res <- test_dir(td, reporter="progress", stop_on_failure=FALSE)
df  <- as.data.frame(res)
cat(sprintf("\nGUARD SUITE: PASS=%d  FAIL=%d  SKIP=%d\n", sum(df$passed), sum(df$failed), sum(df$skipped)))
quit(status = if (sum(df$failed) > 0) 1L else 0L)
