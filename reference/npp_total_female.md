# Select the total United States female population rows from a Census NPP file

Filter a Census 2023 National Population Projections table
(\`np2023_d1\_\<series\>.csv\`) down to the total female population —
the demand population base BEFORE the women-65+ age selection.

## Usage

``` r
npp_total_female(dt)
```

## Arguments

- dt:

  A \`data.table\` with integer \`SEX\`, \`ORIGIN\`, and \`RACE\`
  columns (as read from an NPP CSV). Missing any of these fails loudly.

## Value

The subset of \`dt\` holding the total-female (all-origins, all-races)
rows, one per projected year.

## Details

The filter is \`SEX == 2\` (female), \`ORIGIN == 0\` (all origins),
\`RACE == 0\` (all races combined), per the Census NPP file layout. This
is an SSOT because a wrong \`ORIGIN\`/\`RACE\` code (e.g. \`ORIGIN ==
1\` Hispanic-only, \`RACE == 1\` White-only) would silently narrow the
demand denominator to a subgroup and corrupt every downstream demand
number. Consumers: \`scripts/urps_demand_module_bc\`,
\`urps_module_bc_corrected\`, \`urps_supply_demand_national\` (each
passes a \`data.table\` with integer \`SEX\`/\`ORIGIN\`/\`RACE\`
columns).

## See also

\[npp_projection_path()\] for the file this reads;
\`tests/testthat/test-ssot-npp-total-female.R\` for the guard.

## Examples

``` r
if (FALSE) { # \dontrun{
npp_total_female(data.table::fread(npp_projection_path("mid")))
} # }
```
