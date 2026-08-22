# Path to a Census 2023 National Population Projections series file

Resolve the path to a Census 2023 National Population Projections (NPP)
series CSV under \`data/census\`, from the repo root via
\[here::here()\]. Single-sourced so the demand producers cannot read the
population base from different files or directories, and a vintage
change (e.g. to \`np2024\_...\`) is one edit.

## Usage

``` r
npp_projection_path(series = c("mid", "low", "hi"))
```

## Arguments

- series:

  One of \`"mid"\` (the primary projection; default), \`"low"\`, or
  \`"hi"\` — the NPP low/mid/high variants that drive the demand
  uncertainty bands. Matched with \[match.arg()\].

## Value

A length-1 character path of the form
\`data/census/np2023_d1\_\<series\>.csv\` (absolute, resolved from the
repo root).

## See also

\[npp_total_female()\], which selects the total-female rows from this
file; \`tests/testthat/test-ssot-npp-projection-path.R\` for the guard.

## Examples

``` r
if (FALSE)  npp_projection_path("mid")  # \dontrun{}
```
