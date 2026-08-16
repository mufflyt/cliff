# Mutation test: do gates 39-42 actually catch a broken engine?
#
# Swaps deliberately wrong implementations into the cliff namespace with
# assignInNamespace (no reinstall, nothing on disk is touched), runs the three
# new test files against each mutant, and reports whether they failed.
# A mutant that SURVIVES is a hole in the tests.
setwd(Sys.getenv("CLIFF_ROOT", "."))
suppressMessages({ library(testthat); library(cliff) })
source("tests/testthat/helper-workforce-reference.R")

FILES <- c("tests/testthat/test-workforce-invariants.R",
           "tests/testthat/test-workforce-reference-agreement.R",
           "tests/testthat/test-workforce-adversarial.R")

orig_project  <- cliff:::wc_project
orig_band     <- cliff:::wc_band_of
orig_haz      <- cliff:::wc_haz_for

run_suite <- function() {
  fails <- 0L
  for (f in FILES) {
    r <- tryCatch(
      testthat::test_file(f, reporter = "silent"),
      error = function(e) NULL)
    if (is.null(r)) { fails <- fails + 1L; next }
    d <- as.data.frame(r)
    fails <- fails + sum(d$failed) + sum(vapply(r, function(x)
      sum(vapply(x$results, function(z) inherits(z, "expectation_error"), logical(1))),
      numeric(1)))
  }
  fails
}

restore <- function() {
  assignInNamespace("wc_project",  orig_project, ns = "cliff")
  assignInNamespace("wc_band_of",  orig_band,    ns = "cliff")
  assignInNamespace("wc_haz_for",  orig_haz,     ns = "cliff")
}

mutants <- list(
  "band edges right-closed (off-by-one)" = function() {
    assignInNamespace("wc_band_of", function(age)
      as.character(cut(age, breaks = cliff:::WC_BANDS,
                       labels = cliff:::WC_BAND_LABELS, right = TRUE)),
      ns = "cliff")
  },
  "entrants added BEFORE departures" = function() {
    assignInNamespace("wc_project", function(ages, entrants, hz,
                                             horizon = cliff:::WC_HORIZON,
                                             age_shift = 0L) {
      count <- table(ages); av <- as.integer(names(count)); count <- as.numeric(count); dep <- 0
      for (h in seq_len(horizon)) {
        ix <- match(cliff:::WC_ENTRY_AGE, av)
        if (is.na(ix)) { av <- c(av, cliff:::WC_ENTRY_AGE); count <- c(count, entrants) }
        else count[ix] <- count[ix] + entrants
        hzz <- cliff:::wc_haz_for(av - age_shift, hz)
        dep <- dep + sum(count * hzz); count <- count * (1 - hzz); av <- av + 1L
      }
      list(active_2029 = sum(count), departures_4yr = dep)
    }, ns = "cliff")
  },
  "survivors do not age" = function() {
    assignInNamespace("wc_project", function(ages, entrants, hz,
                                             horizon = cliff:::WC_HORIZON,
                                             age_shift = 0L) {
      count <- table(ages); av <- as.integer(names(count)); count <- as.numeric(count); dep <- 0
      for (h in seq_len(horizon)) {
        hzz <- cliff:::wc_haz_for(av - age_shift, hz); dep <- dep + sum(count * hzz)
        sv <- count * (1 - hzz)
        av2 <- av                      # BUG: no +1L
        ix <- match(cliff:::WC_ENTRY_AGE, av2)
        if (is.na(ix)) { av2 <- c(av2, cliff:::WC_ENTRY_AGE); sv <- c(sv, entrants) }
        else sv[ix] <- sv[ix] + entrants
        av <- av2; count <- sv
      }
      list(active_2029 = sum(count), departures_4yr = dep)
    }, ns = "cliff")
  },
  "departures under-counted (0.9x)" = function() {
    assignInNamespace("wc_project", function(ages, entrants, hz,
                                             horizon = cliff:::WC_HORIZON,
                                             age_shift = 0L) {
      r <- orig_project(ages, entrants, hz, horizon, age_shift)
      r$departures_4yr <- r$departures_4yr * 0.9
      r
    }, ns = "cliff")
  },
  "hazard cap removed (allows h > 1)" = function() {
    assignInNamespace("wc_haz_for", function(age, hz) {
      h <- hz[cliff:::wc_band_of(age)]; h[is.na(h)] <- max(hz, na.rm = TRUE); h
    }, ns = "cliff")
  },
  "entrants ignored entirely" = function() {
    assignInNamespace("wc_project", function(ages, entrants, hz,
                                             horizon = cliff:::WC_HORIZON,
                                             age_shift = 0L)
      orig_project(ages, 0, hz, horizon, age_shift), ns = "cliff")
  }
)

cat("== baseline (unmutated) ==\n")
base_fails <- run_suite()
cat("  failures:", base_fails, if (base_fails == 0) "  OK\n" else "  <- suite is not clean!\n")

cat("\n== mutants ==\n")
survived <- character(0)
for (nm in names(mutants)) {
  restore()
  mutants[[nm]]()
  f <- run_suite()
  restore()
  verdict <- if (f > 0) "KILLED " else "SURVIVED"
  if (f == 0) survived <- c(survived, nm)
  cat(sprintf("  %-8s %-42s %d failing assertion(s)\n", verdict, nm, f))
}

cat("\n")
if (length(survived)) {
  cat("== SURVIVING MUTANTS (holes in the tests) ==\n")
  for (s in survived) cat("  x", s, "\n")
  quit(status = 1)
}
cat("== every mutant killed ==\n")
