# Assign an age to its workforce age-band label

Bucket one or more physician ages into the study age bands using the
canonical breakpoints \`WC_BANDS\` and labels \`WC_BAND_LABELS\`
(right-open intervals, so an age equal to a breakpoint falls in the
upper band).

## Usage

``` r
wc_band_of(age)
```

## Arguments

- age:

  Numeric vector of ages in years.

## Value

A character vector of \`WC_BAND_LABELS\` values the same length as
\`age\` (\`"\<45"\`, \`"45-49"\`, ..., \`"70+"\`); \`NA\` for ages
outside the band range.

## See also

\`WC_BANDS\`, \`WC_BAND_LABELS\`; guarded by
\`tests/testthat/test-ssot-age-bands.R\`.

## Examples

``` r
if (FALSE)  wc_band_of(c(42, 47, 71))  # \dontrun{}   # "<45" "45-49" "70+"
```
