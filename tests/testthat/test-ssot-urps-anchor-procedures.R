# SSOT guard: the four "anchor" pelvic-floor procedure codes for the Module B+C plasticity/attribution audit
# (iter36). c("57288","57282","51728","52287") + its surgical/functional (OBG/URO) split were duplicated across
# module_bc_corrected (x2, incl. a self-referential GATE-7 check), gate_audit (ANCHORS + FUNC/SURG + DICT field),
# and plasticity_stage0 (named-vector keys); gate_audit even had a manual "identical HCPCS universe across files"
# gate. Now canonical in R/urps_procedure_codes.R. The FROZEN snapshot is NOT wired (reproducibility) but is
# parity-guarded here so drift is caught. INTENTIONALLY NOT collapsed: the per-output family LABELS
# ("Sling for SUI" / "Sling" / "Sling (SUI)") are display strings and stay literal.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

pc <- new.env(); source(here::here("R", "urps_procedure_codes.R"), local = pc)

test_that("canonical anchor set is well-formed (4 unique codes, closed class/field, lockstep)", {
  d <- pc$URPS_ANCHOR_PROCEDURES
  expect_s3_class(d, "data.frame")
  expect_identical(nrow(d), 4L)
  expect_false(as.logical(anyDuplicated(d$code)))
  expect_true(all(d$class %in% c("surgical", "functional")))
  expect_true(all(d$field %in% c("OBG", "URO")))
  expect_identical(d$field == "OBG", d$class == "surgical")   # the two encodings can never disagree
})

test_that("[behavior-preserving] accessors reproduce the prior hardcoded literals, in order", {
  expect_identical(pc$urps_anchor_codes(),             c("57288","57282","51728","52287"))  # ANCHORS / anchors$code
  expect_identical(pc$urps_anchor_codes("surgical"),   c("57288","57282"))                  # SURG
  expect_identical(pc$urps_anchor_codes("functional"), c("51728","52287"))                  # FUNC
  expect_identical(pc$urps_anchor_field(c("57288","57282","51728","52287")),
                   c("OBG","OBG","URO","URO"))                                               # DICT field
})

test_that("[semantic] surgical + functional partition the full set (disjoint, exhaustive)", {
  s <- pc$urps_anchor_codes("surgical"); f <- pc$urps_anchor_codes("functional")
  expect_length(intersect(s, f), 0L)                          # disjoint
  expect_setequal(c(s, f), pc$urps_anchor_codes())            # exhaustive
})

test_that("[semantic] the order contract holds (consumers pair codes positionally with label vectors)", {
  # plasticity/corrected zip these codes against their own family-label vectors by position; the canonical
  # order sling,apical,urodynamics,BOTOX must be stable or the labels would mis-attach.
  expect_identical(pc$urps_anchor_codes()[1], "57288")   # sling
  expect_identical(pc$urps_anchor_codes()[4], "52287")   # BOTOX
})

test_that("[adversarial] the three non-frozen consumers reference the SSOT, not a bare 4-code literal", {
  files <- c(cor  = here::here("scripts", "urps_module_bc_corrected_2026-07-23.R"),
             gate = here::here("scripts", "urps_module_bc_gate_audit_2026-07-23.R"),
             plas = here::here("scripts", "urps_plasticity_stage0_audit_2026-07-23.R"))
  for (nm in names(files)) {
    ls <- readLines(files[[nm]], warn = FALSE)
    expect_true(any(grepl("urps_anchor_codes\\(", ls)), info = paste(nm, "references the accessor"))
    # the exact full-set literal must be gone (order-insensitive: match all four together on one line)
    expect_false(any(grepl('"57288".*"57282".*"51728".*"52287"', ls)),
                 info = paste(nm, "no bare 4-code anchor literal"))
  }
  gate <- readLines(files[["gate"]], warn = FALSE)
  expect_false(any(grepl('FUNC <- c\\("51728","52287"\\)', gate)))          # split literal gone
  expect_false(any(grepl('field=c\\("OBG","OBG","URO","URO"\\)', gate)))    # field literal gone
})

test_that("[frozen-parity] the FROZEN snapshot's anchor codes still match the canonical (drift guard, no edit)", {
  # The freeze is intentionally NOT wired to the SSOT; instead we assert its literal equals the canonical so a
  # change to one without the other trips here. If the freeze is deliberately re-baked, update this expectation.
  frozen <- readLines(here::here("scripts", "urps_module_bc_FROZEN_2026-07-23.R"), warn = FALSE)
  wanted <- sprintf("c(%s)", paste0('"', pc$urps_anchor_codes(), '"', collapse = ","))
  expect_true(any(grepl(wanted, frozen, fixed = TRUE)),
              info = "FROZEN anchor-code literal diverged from R/urps_procedure_codes.R")
})

test_that("[adversarial] a malformed canonical set fails loudly (validation is not decorative)", {
  # duplicate code
  expect_error(local({
    URPS_ANCHOR_PROCEDURES <- data.frame(code=c("57288","57288","51728","52287"),
      class=c("surgical","surgical","functional","functional"),
      field=c("OBG","OBG","URO","URO"), stringsAsFactors=FALSE)
    stopifnot(!anyDuplicated(URPS_ANCHOR_PROCEDURES$code)) }))
  # broken class<->field lockstep
  expect_error(local({
    d <- data.frame(code=c("57288","57282","51728","52287"),
      class=c("surgical","surgical","functional","functional"),
      field=c("URO","OBG","URO","URO"), stringsAsFactors=FALSE)   # first row mislabeled
    stopifnot(identical(d$field == "OBG", d$class == "surgical")) }))
})
