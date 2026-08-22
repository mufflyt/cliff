# Counts and within-stratum percentages of a categorical characteristic

Counts and within-stratum percentages of a categorical characteristic

## Usage

``` r
equity_breakdown(
  df,
  characteristic,
  stratum = NULL,
  levels = NULL,
  missing_label = "Missing"
)
```

## Arguments

- df:

  Roster data frame.

- characteristic:

  Bare or string column name to tabulate (e.g. gender).

- stratum:

  Optional column name defining strata (e.g. pathway ABU/ABOG). Columns
  are produced per stratum plus an Overall column.

- levels:

  Optional character vector fixing the row order; unlisted levels are
  appended by descending overall count.

- missing_label:

  Label for empty/NA values. Default "Missing".

## Value

Long tibble: characteristic, level, then \<stratum\>\_n /
\<stratum\>\_pct pairs and overall_n / overall_pct.
