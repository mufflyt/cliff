# Normalize String for Subspecialty Matching

Lowercases, trims, replaces ampersands with "and", removes non- alpha
characters, and collapses whitespace. Used as a pre- processing step
before subspecialty name comparison.

## Usage

``` r
norm(x)
```

## Arguments

- x:

  \[character vector\]: Raw subspecialty strings.

## Value

Character vector. Normalized lowercase strings.

## Details

\- \*\*Pipeline step\*\*: Called within standardize_subspecialty() -
\*\*Inputs\*\*: \`x\` — raw subspecialty label string or vector -
\*\*Algorithm\*\*: tolower → trimws → "&"→"and" → strip non-alpha →
collapse spaces via gsub - \*\*Performance\*\*: Vectorized; \<1ms per
call - \*\*Reproducibility\*\*: Deterministic - \*\*Failure modes\*\*:
Propagates NA for NA input (no guard)

## Examples

``` r
if (FALSE) { # \dontrun{
norm("Gyn & Oncology")  # returns "gyn and oncology"
norm("Female Pelvic Med")  # returns "female pelvic med"
} # }
```
