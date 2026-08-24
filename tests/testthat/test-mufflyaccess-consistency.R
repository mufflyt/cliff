# Cross-repo divergence guard: cliff consumes the safe-division family from the
# shared mufflyaccess package (R/safe_divide.R is now a shim). This test fails
# loudly if the package is missing, the shim stops exporting a function, or a
# zero/NA-denominator contract drifts. Analogue of isochrones' and twostep's
# test-mufflyaccess-consistency.R.
#
# Resolution is deliberately namespace-based rather than search-path based.
# R/safe_divide.R used to end in library(mufflyaccess), so bare get("safe_divide")
# resolved off the search path; that file-scope attach was removed (#34) because
# it runs at build time and hides undeclared dependencies. The guard is unchanged
# in intent -- the functions must exist, must come from mufflyaccess, and must
# honour the zero-denominator contract -- but it now asks the namespace directly,
# which is also what package code does (every call site is mufflyaccess::-qualified).
suppressWarnings(suppressMessages(library(testthat)))

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

SAFE_FNS <- c("safe_divide", "safe_divide_manu", "safe_pct_manu",
              "safe_percent", "safe_rate", "safe_ratio")

# Resolve from the namespace, never the search path.
ma_get <- function(fn) getExportedValue("mufflyaccess", fn)

test_that("the shim loads mufflyaccess and every safe-division fn is reachable", {
  source(testthat::test_path("..", "..", "R", "safe_divide.R"))
  expect_true("mufflyaccess" %in% loadedNamespaces())
  for (fn in SAFE_FNS) expect_true(is.function(ma_get(fn)), info = fn)
})

test_that("the shim itself declares no local override of the family", {
  # A local definition would shadow the shared implementation and reintroduce
  # exactly the divergence this guard exists to prevent.
  shim <- new.env(parent = baseenv())
  sys.source(testthat::test_path("..", "..", "R", "safe_divide.R"), envir = shim)
  expect_length(intersect(ls(shim, all.names = TRUE), SAFE_FNS), 0L)
})

test_that("safe-division fns come from the mufflyaccess namespace (no local override)", {
  source(testthat::test_path("..", "..", "R", "safe_divide.R"))
  for (fn in c("safe_divide", "safe_percent", "safe_ratio"))
    expect_identical(environmentName(environment(ma_get(fn))), "mufflyaccess", info = fn)
})

test_that("zero / NA denominator returns the default, never Inf/NaN (frozen contract)", {
  source(testthat::test_path("..", "..", "R", "safe_divide.R"))
  safe_divide <- ma_get("safe_divide")
  expect_true(is.na(safe_divide(1, 0)))          # default NA_real_
  expect_equal(safe_divide(1, 0, default = -1), -1)
  expect_equal(safe_divide(6, 3), 2)
  expect_false(any(is.nan(safe_divide(c(1, 0), c(0, 0)))))
  expect_false(any(is.infinite(safe_divide(c(1, 0), c(0, 0)))))
})
