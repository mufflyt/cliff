# URPS anchor procedure codes, optionally restricted to one class

Return the four "anchor" pelvic-floor HCPCS/CPT codes used by the Module
B+C plasticity/attribution audit, in their canonical order (sling,
apical suspension, complex urodynamics, bladder BOTOX), optionally
filtered to a single procedure class.

## Usage

``` r
urps_anchor_codes(class = c("all", "surgical", "functional"))
```

## Arguments

- class:

  One of:

  \`"all"\`

  :   (default) all four anchor codes.

  \`"surgical"\`

  :   the reconstructive / OB-GYN-field codes (sling, apical
      suspension).

  \`"functional"\`

  :   the urodynamic / urology-field codes (complex urodynamics, bladder
      BOTOX).

  Matched with \[match.arg()\].

## Value

A character vector of HCPCS codes in canonical order. \`"surgical"\` and
\`"functional"\` together partition the full set and are exactly the
gate-audit SURG/FUNC split (equivalently the OBG/URO field split).

## See also

\[urps_anchor_field()\] for a code's OBG/URO field; the underlying
\`URPS_ANCHOR_PROCEDURES\` lookup table. Guarded by
\`tests/testthat/test-ssot-urps-anchor-procedures.R\`.

## Examples

``` r
urps_anchor_codes()             # c("57288", "57282", "51728", "52287")
#> [1] "57288" "57282" "51728" "52287"
urps_anchor_codes("surgical")   # c("57288", "57282")
#> [1] "57288" "57282"
urps_anchor_codes("functional") # c("51728", "52287")
#> [1] "51728" "52287"
```
