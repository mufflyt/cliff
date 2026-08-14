# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# urps_procedure_codes.R — SSOT for the URPS "anchor" pelvic-floor procedure
# codes used by the Module B+C plasticity/attribution audit.
#
# WHAT: one representative HCPCS/CPT code per procedure family (four families),
#   each classified surgical (reconstructive, OB/GYN-field) vs functional
#   (urodynamic/BOTOX, urology-field). This is the small "anchor" set used to
#   estimate urogyn-attributable share; it is DISTINCT from the full six-group
#   service volume list in scripts/urps_demand_module_bc_2026-07-23.R (`grp`),
#   which is single-source there and NOT duplicated.
# UNITS: HCPCS Level-I (CPT) / Level-II codes, character (leading-zero safe).
# SOURCE: CMS Medicare Part B by-Provider-and-Service 2024; family/field
#   assignment per the Module B+C estimand (see urps_module_bc_FROZEN header).
# CONSUMERS (codes sourced from here; display labels stay per-output):
#   scripts/urps_module_bc_corrected_2026-07-23.R  (anchors$code + GATE 7 check)
#   scripts/urps_module_bc_gate_audit_2026-07-23.R (ANCHORS, FUNC/SURG, DICT field)
#   scripts/urps_plasticity_stage0_audit_2026-07-23.R (named-vector keys)
#   scripts/urps_module_bc_FROZEN_2026-07-23.R     — FROZEN snapshot, NOT wired;
#     parity-guarded against this object so drift is caught without editing it.
# DELIBERATELY NOT collapsed: the per-consumer family LABELS ("Sling for SUI" vs
#   "Sling" vs "Sling (SUI)") are output-specific display strings, left literal.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Canonical anchor set. ORDER IS PART OF THE CONTRACT: consumers pair these
# codes positionally with their own family-label vectors, so the order here
# (sling, apical, urodynamics, BOTOX) must not change without updating them.
URPS_ANCHOR_PROCEDURES <- data.frame(
  code  = c("57288",     "57282",     "51728",       "52287"),
  class = c("surgical",  "surgical",  "functional",  "functional"),
  field = c("OBG",       "OBG",       "URO",         "URO"),
  stringsAsFactors = FALSE
)

# Fail loudly if the canonical set is malformed: exactly four unique codes, a
# closed classification vocabulary, and a 1:1 class<->field correspondence
# (surgical<->OBG, functional<->URO) so the two encodings can never disagree.
local({
  d <- URPS_ANCHOR_PROCEDURES
  stopifnot(
    is.data.frame(d), nrow(d) == 4L,
    is.character(d$code), !anyDuplicated(d$code),
    all(nchar(d$code) >= 5L),                                   # HCPCS width sanity
    all(d$class %in% c("surgical", "functional")),
    all(d$field %in% c("OBG", "URO")),
    identical(d$field == "OBG", d$class == "surgical")          # class<->field lockstep
  )
})

#' URPS anchor procedure codes, optionally restricted to one class
#'
#' Return the four "anchor" pelvic-floor HCPCS/CPT codes used by the Module B+C
#' plasticity/attribution audit, in their canonical order (sling, apical
#' suspension, complex urodynamics, bladder BOTOX), optionally filtered to a
#' single procedure class.
#'
#' @param class One of:
#'   \describe{
#'     \item{`"all"`}{(default) all four anchor codes.}
#'     \item{`"surgical"`}{the reconstructive / OB-GYN-field codes (sling, apical suspension).}
#'     \item{`"functional"`}{the urodynamic / urology-field codes (complex urodynamics, bladder BOTOX).}
#'   }
#'   Matched with [match.arg()].
#' @return A character vector of HCPCS codes in canonical order. `"surgical"`
#'   and `"functional"` together partition the full set and are exactly the
#'   gate-audit SURG/FUNC split (equivalently the OBG/URO field split).
#' @seealso [urps_anchor_field()] for a code's OBG/URO field; the underlying
#'   `URPS_ANCHOR_PROCEDURES` lookup table. Guarded by
#'   `tests/testthat/test-ssot-urps-anchor-procedures.R`.
#' @examples
#' urps_anchor_codes()             # c("57288", "57282", "51728", "52287")
#' urps_anchor_codes("surgical")   # c("57288", "57282")
#' urps_anchor_codes("functional") # c("51728", "52287")
#' @export
urps_anchor_codes <- function(class = c("all", "surgical", "functional")) {
  class <- match.arg(class)
  d <- URPS_ANCHOR_PROCEDURES
  if (class == "all") d$code else d$code[d$class == class]
}

#' Specialty field (OBG / URO) for URPS anchor procedure codes
#'
#' Look up the canonical OB-GYN-field vs urology-field classification for a
#' vector of anchor procedure codes, so consumers never re-hardcode the
#' `c("OBG", "OBG", "URO", "URO")` field vector.
#'
#' @param codes Character vector of HCPCS codes (typically a subset of
#'   [urps_anchor_codes()]).
#' @return A character vector the same length as `codes`: `"OBG"` for the
#'   surgical / reconstructive anchors, `"URO"` for the functional / urodynamic
#'   anchors, and `NA` for any code not present in `URPS_ANCHOR_PROCEDURES`.
#' @seealso [urps_anchor_codes()]; the `URPS_ANCHOR_PROCEDURES` lookup table.
#' @examples
#' urps_anchor_field(c("57288", "51728"))   # c("OBG", "URO")
#' @export
urps_anchor_field <- function(codes) {
  URPS_ANCHOR_PROCEDURES$field[match(codes, URPS_ANCHOR_PROCEDURES$code)]
}
