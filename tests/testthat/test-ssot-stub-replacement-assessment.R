# SSOT guard: the TEST_MODE stub in R/manuscript_consolidate_existing_results.R used to hardcode each
# subspecialty's replacement_assessment ("Above replacement") in parallel with its replacement_ratio. The
# assessment is a PURE FUNCTION of the ratio (classify_replacement, manuscript/R/workforce_data_contract.R),
# and the production path already derives it (line ~209). The stub now derives it too, so the fixture cannot
# drift from its own ratios. Production + the frozen CSV are already guarded by the contract validator.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

# canonical classifier, in isolation
ce <- new.env(); suppressMessages(source(here::here("manuscript", "R", "workforce_data_contract.R"), local = ce))
classify <- ce$classify_replacement

# build the stub via the real code path (TEST_MODE), restoring the env afterwards
old <- Sys.getenv("TEST_MODE", unset = NA_character_)
Sys.setenv(TEST_MODE = "1")
suppressMessages(source(here::here("R", "manuscript_consolidate_existing_results.R")))
STUB <- suppressMessages(suppressWarnings(main()))
if (is.na(old)) Sys.unsetenv("TEST_MODE") else Sys.setenv(TEST_MODE = old)

test_that("[self-consistent] stub assessment equals classify_replacement(ratio) for every row", {
  expect_identical(STUB$replacement_assessment, classify(STUB$replacement_ratio))
})

test_that("[behavior-preserving] the derived values equal the prior hardcoded literals + column position", {
  expect_equal(STUB$replacement_assessment, rep("Above replacement", 3L))
  # replacement_assessment must sit immediately after replacement_ratio (unchanged schema order)
  expect_identical(which(names(STUB) == "replacement_assessment"),
                   which(names(STUB) == "replacement_ratio") + 1L)
  expect_true(all(STUB$replacement_assessment %in% ce$WORKFORCE_VALID_ASSESSMENTS))
})

test_that("[semantic] a changed ratio would change the derived label (proves function, not constant)", {
  expect_identical(classify(1.06), "Above replacement")   # > 1.05
  expect_identical(classify(1.00), "At replacement")      # within [0.95, 1.05]
  expect_identical(classify(0.94), "Below replacement")   # < 0.95
})

test_that("[adversarial] the stub no longer hardcodes an assessment literal beside the ratio", {
  ls <- readLines(here::here("R", "manuscript_consolidate_existing_results.R"), warn = FALSE)
  stub_block <- ls[seq_len(which(grepl("return\\(invisible\\(stub\\)\\)", ls))[1])]
  # no "Above replacement" (or any assessment label) typed inside the stub tribble
  expect_false(any(grepl('"Above replacement"|"At replacement"|"Below replacement"', stub_block)))
  # the stub derives it via the canonical function
  expect_true(any(grepl("classify_replacement\\(replacement_ratio\\)", stub_block)))
})
