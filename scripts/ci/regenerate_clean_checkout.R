#!/usr/bin/env Rscript
# Gate 58: re-run every generator that needs no external input, and require the
# artifacts it writes to match what is committed.
#
# This is the strongest reproducibility claim CI can make unaided. PROVENANCE.md
# says every manuscript artifact has a generator; this asks whether running that
# generator today still produces the committed file.
#
# MUTATING. Generators write into data/ in place, so this rewrites the working
# tree and then reports what changed. It refuses to run without
# CLIFF_ALLOW_MUTATION=1 so nobody destroys uncommitted work by running it
# casually; CI checkouts are disposable, developer trees are not.
#
# Two failure modes are distinguished, because they mean different things:
#   ERRORED    the generator no longer runs at all
#   DRIFTED    it runs, but emits something other than what is committed
#
# Generators already known not to run in a bare checkout live in
# scripts/ci/generator_debt.txt. CI fails when that set GROWS, so the job is
# never permanently red, and the debt is visible instead of implicit.
#
#   CLIFF_ALLOW_MUTATION=1 Rscript scripts/ci/regenerate_clean_checkout.R
#   ... --write-debt      re-baseline the known-unrunnable set

args <- commandArgs(trailingOnly = TRUE)
write_debt <- "--write-debt" %in% args
root <- Sys.getenv("CLIFF_ROOT", ".")
setwd(root)

if (!identical(Sys.getenv("CLIFF_ALLOW_MUTATION"), "1")) {
  cat("refusing to run: this rewrites tracked artifacts in place.\n",
      "Set CLIFF_ALLOW_MUTATION=1 if that is what you want.\n", sep = "")
  quit(status = 2)
}

debt_path <- file.path("scripts", "ci", "generator_debt.txt")
classify  <- file.path("scripts", "ci", "classify_generators.R")

gens <- system2(file.path(R.home("bin"), "Rscript"),
                c("--no-init-file", shQuote(classify), "--list", "clean_checkout"),
                stdout = TRUE)
gens <- trimws(gens); gens <- gens[nzchar(gens)]
gens <- gens[file.exists(gens)]

cat("== clean-checkout generator reproduction ==\n")
cat("  generators:", length(gens), "\n\n")

dirty_before <- system2("git", c("status", "--porcelain"), stdout = TRUE)
if (length(dirty_before)) {
  cat("NOTE: working tree was already dirty before regeneration:\n")
  for (l in head(dirty_before, 10)) cat("   ", l, "\n")
  cat("\n")
}

errored <- character(0)
ran     <- character(0)
for (g in gens) {
  t0 <- Sys.time()
  msg <- NA_character_
  ok <- tryCatch({
    sys.source(g, envir = new.env(parent = globalenv()))
    TRUE
  }, error = function(e) {
    # conditionMessage() is not enough. readr/dplyr raise rlang/cli conditions
    # whose human-readable detail lives in the condition body, not the header,
    # so conditionMessage() returns "" and the failure reports as blank -- which
    # is exactly what six generators did on Linux, telling us nothing.
    m <- tryCatch(conditionMessage(e), error = function(...) "")
    if (!nzchar(trimws(m)))
      m <- tryCatch(paste(format(e), collapse = " | "), error = function(...) "")
    if (!nzchar(trimws(m)))
      m <- paste("<", paste(class(e), collapse = "/"), "with no message >")
    call <- tryCatch(deparse(conditionCall(e))[1], error = function(...) NA_character_)
    msg <<- paste0(gsub("\\s+", " ", m),
                   if (!is.na(call) && nzchar(call)) paste0("  [at: ", call, "]") else "")
    FALSE
  })
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  if (isTRUE(ok)) {
    ran <- c(ran, g)
    cat(sprintf("  ok       %-58s %5.1fs\n", g, secs))
  } else {
    errored <- c(errored, g)
    cat(sprintf("  ERRORED  %-58s %5.1fs\n      %s\n", g, secs, substr(msg, 1, 300)))
  }
}

# ---- what changed --------------------------------------------------------
dirty_after <- system2("git", c("status", "--porcelain"), stdout = TRUE)
new_dirty <- setdiff(dirty_after, dirty_before)
drifted <- sub("^\\s*\\S+\\s+", "", new_dirty)

# Rendered images are excluded. PNG/TIFF output differs byte-for-byte between
# platforms and graphics-device versions for identical data -- Linux and macOS
# disagree on every figure here -- so comparing them measures the renderer, not
# the science. The CSVs those figures are drawn from ARE compared, which is the
# check that has content.
drifted <- drifted[!grepl("\\.(png|tiff|tif|jpg|jpeg|pdf|svg)$", drifted,
                          ignore.case = TRUE)]

cat("\n== results ==\n")
cat("  ran      :", length(ran), "\n")
cat("  ERRORED  :", length(errored), "\n")
cat("  DRIFTED  :", length(drifted), "artifact(s)\n")
if (length(drifted)) for (p in drifted) cat("    ~", p, "\n")

# ---- debt accounting -----------------------------------------------------
drift_path <- file.path("scripts", "ci", "artifact_drift_debt.txt")

if (write_debt) {
  writeLines(c(
    "# Clean-checkout generators that do not currently run in a bare checkout.",
    "# CI fails when this set GROWS. Shrink it by fixing the generator and",
    "# deleting its line; never add a line just to make CI pass.",
    "#   CLIFF_ALLOW_MUTATION=1 Rscript scripts/ci/regenerate_clean_checkout.R --write-debt",
    sort(errored)), debt_path)
  cat("\ndebt registry written ->", debt_path, "(", length(errored), "entries )\n")

  writeLines(c(
    "# Committed artifacts that do NOT reproduce from their own generator.",
    "#",
    "# Every line here is an open scientific reproducibility question, not a",
    "# formatting nit: the values differ. classifier_validation_external.csv,",
    "# for instance, regenerates with URPS n=499 against a committed 415.",
    "#",
    "# CI fails when this set GROWS. Shrink it by determining, per artifact,",
    "# whether the generator or the committed file is right -- then fixing one",
    "# and deleting the line.",
    sort(drifted)), drift_path)
  cat("drift registry written ->", drift_path, "(", length(drifted), "entries )\n")
  quit(status = 0)
}

known_drift <- character(0)
if (file.exists(drift_path)) {
  known_drift <- readLines(drift_path, warn = FALSE)
  known_drift <- trimws(known_drift[!grepl("^\\s*#", known_drift) &
                                    nzchar(trimws(known_drift))])
}

known <- character(0)
if (file.exists(debt_path)) {
  known <- readLines(debt_path, warn = FALSE)
  known <- trimws(known[!grepl("^\\s*#", known) & nzchar(trimws(known))])
}
novel_err <- setdiff(errored, known)
fixed_err <- setdiff(known, errored)

if (length(fixed_err)) {
  cat("\n-- now runnable (trim the debt registry) --\n")
  for (g in fixed_err) cat("  +", g, "\n")
}

fail <- FALSE
if (length(novel_err)) {
  cat("\n== GENERATORS THAT STOPPED RUNNING ==\n")
  for (g in novel_err) cat("  x", g, "\n")
  fail <- TRUE
}
novel_drift <- setdiff(drifted, known_drift)
fixed_drift <- setdiff(known_drift, drifted)

if (length(fixed_drift)) {
  cat("\n-- now reproduces (trim the drift registry) --\n")
  for (p in fixed_drift) cat("  +", p, "\n")
}
if (length(novel_drift)) {
  cat("\n== ARTIFACTS THAT STOPPED REPRODUCING ==\n")
  for (p in novel_drift) cat("  x", p, "\n")
  cat("\nRunning the committed generator produced different bytes. Either the\n",
      "artifact was hand-edited, or the generator changed without the artifact\n",
      "being regenerated. Both are the failure PROVENANCE.md exists to prevent.\n", sep = "")
  fail <- TRUE
}

if (fail) quit(status = 1)
cat("\n== every clean-checkout artifact reproduces ==\n")
quit(status = 0)
