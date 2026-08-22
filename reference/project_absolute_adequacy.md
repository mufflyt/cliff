# Anchor a relative projection to a gated absolute adequacy

The seam into \`shiny_urps_adequacy/model.R::project()\`. Given a
projection table (project()'s output, or any table with a year column
and a relative adequacy index normalised to 1 at the base year), a
validated access fit, and an all-payer demand basis, run them through
the capacity-evidence gate (\[resolve_adequacy_gated()\]) and — ONLY
when the gate resolves — anchor the relative index to the gate's
absolute adequacy:

## Usage

``` r
project_absolute_adequacy(
  projection,
  access_fit,
  demand_evidence,
  base_year,
  adequacy_col = "adeq_eff",
  year_col = "YEAR",
  effective_col = "effective",
  req_fte_col = "req_fte",
  label = NA_character_,
  tol = 1e-08
)
```

## Arguments

- projection:

  A \`data.frame\`/\`data.table\` with a year column and a relative
  adequacy column. Operated on by copy; the input is not mutated.

- access_fit:

  A one-row access fit (e.g. \[wait_to_adequacy()\] output) with logical
  \`identified\` and numeric \`adequacy\`.

- demand_evidence:

  A demand basis with logical \`fully_identified\` and numeric \`total\`
  (e.g. \[chia_calibrated_all_payer_total()\] or
  \[chia_bridge_all_payer_total()\]).

- base_year:

  The projection base year at which the relative index equals 1.

- adequacy_col:

  Name of the relative adequacy column (default \`"adeq_eff"\`).

- year_col:

  Name of the year column (default \`"YEAR"\`).

- effective_col:

  Name of the effective-FTE supply column (default \`"effective"\`);
  absolute FTE columns are added only if it and \`req_fte_col\` are
  present.

- req_fte_col:

  Name of the relative required-FTE column (default \`"req_fte"\`).

- label:

  Optional label for the capacity-evidence bundle.

- tol:

  Numeric tolerance for the base-year normalisation check.

## Value

A \`data.frame\` copy of \`projection\` with added columns
\`adeq_absolute\`, \`absolute_resolved\`, \`absolute_reason\` (and, when
the FTE columns are present, \`req_fte_absolute\` and
\`capacity_gap_absolute\`). The resolved anchor, resolution flag, and
reason are also attached as attributes \`absolute_anchor\`,
\`absolute_resolved\`, \`absolute_reason\`.

## Details

\$\$adequacy\_{absolute}(y) = adequacy\_{relative}(y) \times anchor\$\$

where \`anchor\` is the gate-resolved absolute adequacy. Because the
relative index is 1 at the base year, \`adeq_absolute(base) == anchor\`.
Where the projection also carries effective-FTE supply and the relative
required FTE, the absolute required FTE (\`req_fte_relative / anchor\`)
and the absolute capacity gap (\`req_fte_absolute - effective\`) are
added too — the real FTE shortage the relative model, pinned to
base-year balance, cannot state.

If the gate REFUSES (access fit not identified, or demand basis not
fully identified), every absolute column is \`NA_real\_\` and the gate's
reason is carried on \`absolute_reason\`. The relative columns are never
touched.

## See also

\[resolve_adequacy_gated()\], \[capacity_evidence_bundle()\],
\[chia_calibrated_all_payer_total()\], \[wait_to_adequacy()\].

Other capacity-evidence:
[`capacity_evidence_bundle()`](https://mufflyt.github.io/cliff/reference/capacity_evidence_bundle.md),
[`capacity_evidence_sufficient()`](https://mufflyt.github.io/cliff/reference/capacity_evidence_sufficient.md),
[`chia_calibrated_all_payer_total()`](https://mufflyt.github.io/cliff/reference/chia_calibrated_all_payer_total.md),
[`resolve_adequacy_gated()`](https://mufflyt.github.io/cliff/reference/resolve_adequacy_gated.md),
[`validate_capacity_evidence()`](https://mufflyt.github.io/cliff/reference/validate_capacity_evidence.md)

## Examples

``` r
proj <- data.frame(YEAR = 2025:2027, adeq_eff = c(1, 0.95, 0.90),
                   effective = c(1000, 990, 980), req_fte = c(1000, 1042, 1089))
af <- data.frame(identified = TRUE, adequacy = 1.25)      # base-year absolute adequacy
de <- list(fully_identified = TRUE, total = 1200)
out <- project_absolute_adequacy(proj, af, de, base_year = 2025)
out$adeq_absolute        # 1.25, 1.1875, 1.125  (relative index x anchor)
#> [1] 1.2500 1.1875 1.1250
```
