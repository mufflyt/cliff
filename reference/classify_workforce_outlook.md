# Classify a replacement ratio into a workforce-outlook label

Map a fellowship-replacement ratio (annual graduates / annual
retirements) to the manuscript "Workforce Outlook" category, using the
shared cutpoints \`WORKFORCE_OUTLOOK_ADEQUATE_MIN\` (\>= 1.2) and
\`WORKFORCE_OUTLOOK_MARGINAL_MIN\` (\>= 0.8).

## Usage

``` r
classify_workforce_outlook(ratio)
```

## Arguments

- ratio:

  Numeric vector of replacement ratios (graduates / retirements); \`NA\`
  propagates.

## Value

A character vector the same length as \`ratio\`, each \`"Adequate"\`
(ratio \>= 1.2), \`"Marginal"\` (0.8 \<= ratio \< 1.2), or
\`"Insufficient"\` (ratio \< 0.8).

## Details

This is the manuscript workforce-table scheme (Adequate / Marginal /
Insufficient). It is INTENTIONALLY DISTINCT from the data contract's
replacement classifier \`classify_replacement()\` (Above / At / Below
replacement, cutpoints 0.95 / 1.05, in
\`manuscript/R/workforce_data_contract.R\`): different labels, different
cutpoints, different tables. The two must not be merged.

## See also

\`WORKFORCE_OUTLOOK_ADEQUATE_MIN\`, \`WORKFORCE_OUTLOOK_MARGINAL_MIN\`.
Guarded by \`tests/testthat/test-ssot-workforce-outlook.R\`.

## Examples

``` r
classify_workforce_outlook(c(0.7, 1.0, 1.3))  # "Insufficient" "Marginal" "Adequate"
#> [1] "Insufficient" "Marginal"     "Adequate"    
```
