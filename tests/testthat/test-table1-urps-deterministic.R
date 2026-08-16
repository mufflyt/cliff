# GATE: the URPS Table 1 p-values must be deterministic.
#
# scripts/build_table1_urps_2026-07-23.R called
#     fisher.test(tb, simulate.p.value = TRUE, B = 1e4)
# with no set.seed() anywhere in the file. The reported Rurality p-value was
# therefore a random draw: eight runs gave eight different values (0.314-0.327,
# sd 0.0047), and the committed artifact could never reproduce. Rurality is the only
# characteristic whose contingency table has an expected cell below 5, so it was the
# only affected row -- which is exactly why this looked like one-cell "drift".
#
# A bigger B does not fix it. Over 20 seeds the simulated p converges correctly on
# the exact value (mean 0.32440 -> 0.32376 -> 0.32360 at B = 1e4, 1e5, 1e6) but still
# spans three distinct third decimals at B = 1e6 (0.323, 0.324, 0.325). At the
# precision this table publishes, another valid seed would change the printed number.
#
# The exact conditional test is feasible here and is deterministic, so it is used.
#
# Adjudication: docs/adjudication/table1_urps_characteristics.md

skip_if_no_repo()

ROOT <- cliff_repo_root()
GEN <- file.path(ROOT, "scripts", "build_table1_urps_2026-07-23.R")
ART <- file.path(ROOT, "data", "table1_urps_characteristics_2026-07-23.csv")

# The observed Rurality contingency table, from the committed ENRICHED inputs.
RURALITY <- as.table(matrix(c(13, 2, 23, 11, 993, 294), nrow = 2,
                            dimnames = list(path = c("ABOG", "ABU"),
                                            rural = c("Rural", "Suburban", "Urban"))))

test_that("the generator prefers the EXACT test and seeds any simulated fallback", {
  skip_if_not(file.exists(GEN), "generator not present")
  src <- readLines(GEN, warn = FALSE)
  code <- src[!grepl("^\\s*#", src)]

  expect_true(any(grepl("set\\.seed\\(", code)),
              info = "no set.seed(): the reported p-value would be a random draw")
  # an unconditional simulate.p.value call with no exact attempt is the defect
  expect_true(any(grepl("fisher\\.test\\(tb\\)", code)),
              info = "the exact test is never attempted; simulation is not a default")
  sim <- grep("simulate\\.p\\.value\\s*=\\s*TRUE", code, value = TRUE)
  if (length(sim)) {
    expect_false(any(grepl("B\\s*=\\s*1e4\\b", sim)),
                 info = "B = 1e4 cannot support a 3-decimal p-value")
  }
})

test_that("the exact Fisher p-value is feasible, deterministic, and reproducible", {
  # feasible: this is the branch the generator now takes
  p <- tryCatch(stats::fisher.test(RURALITY)$p.value, error = function(e) NA_real_)
  expect_false(is.na(p))

  # deterministic: repeated evaluation is bit-identical, with no seed involved
  reps <- replicate(5, stats::fisher.test(RURALITY)$p.value)
  expect_equal(length(unique(reps)), 1L)

  # and it is what the artifact publishes, at the artifact's precision
  expect_equal(sprintf("%.3f", p), "0.324")
})

test_that("a seeded simulation reproduces itself exactly (identical seed + inputs)", {
  f <- function(seed) {
    set.seed(seed)
    suppressWarnings(stats::fisher.test(RURALITY, simulate.p.value = TRUE,
                                        B = 1e4)$p.value)
  }
  expect_equal(f(20260718L), f(20260718L))
  # and an UNSEEDED pair does not, which is the defect this gate exists for
  g <- function() suppressWarnings(
    stats::fisher.test(RURALITY, simulate.p.value = TRUE, B = 1e4)$p.value)
  draws <- replicate(6, g())
  expect_gt(length(unique(draws)), 1L)
})

test_that("the committed artifact carries the deterministic Rurality p-value", {
  skip_if_not(file.exists(ART), "artifact not present")
  d <- utils::read.csv(ART, stringsAsFactors = FALSE, check.names = FALSE)
  row <- d[grepl("^Rurality", d$Characteristic), , drop = FALSE]
  expect_equal(nrow(row), 1L)
  expect_equal(as.character(row$P), "0.324",
               info = paste("Rurality P must be the EXACT test's value. 0.323 was one",
                            "draw of the old unseeded B=1e4 simulation."))
})
