# Specialty field (OBG / URO) for URPS anchor procedure codes

Look up the canonical OB-GYN-field vs urology-field classification for a
vector of anchor procedure codes, so consumers never re-hardcode the
\`c("OBG", "OBG", "URO", "URO")\` field vector.

## Usage

``` r
urps_anchor_field(codes)
```

## Arguments

- codes:

  Character vector of HCPCS codes (typically a subset of
  \[urps_anchor_codes()\]).

## Value

A character vector the same length as \`codes\`: \`"OBG"\` for the
surgical / reconstructive anchors, \`"URO"\` for the functional /
urodynamic anchors, and \`NA\` for any code not present in
\`URPS_ANCHOR_PROCEDURES\`.

## See also

\[urps_anchor_codes()\]; the \`URPS_ANCHOR_PROCEDURES\` lookup table.

## Examples

``` r
urps_anchor_field(c("57288", "51728"))   # c("OBG", "URO")
#> [1] "OBG" "URO"
```
