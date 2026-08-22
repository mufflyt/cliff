# Validate a capacity-evidence bundle's shape (hard-fail on any violation)

Enforce that the bundle carries a one-row access fit with the required
\`identified\`/\`adequacy\` fields and a demand-evidence list with the
required \`fully_identified\`/\`total\` fields. Shape only — not
sufficiency.

## Usage

``` r
validate_capacity_evidence(bundle)
```

## Arguments

- bundle:

  A candidate \`capacity_evidence_bundle\`.

## Value

The validated \`bundle\`, invisibly.

## See also

\[capacity_evidence_bundle()\]

Other capacity-evidence:
[`capacity_evidence_bundle()`](https://mufflyt.github.io/cliff/reference/capacity_evidence_bundle.md),
[`capacity_evidence_sufficient()`](https://mufflyt.github.io/cliff/reference/capacity_evidence_sufficient.md),
[`chia_calibrated_all_payer_total()`](https://mufflyt.github.io/cliff/reference/chia_calibrated_all_payer_total.md),
[`project_absolute_adequacy()`](https://mufflyt.github.io/cliff/reference/project_absolute_adequacy.md),
[`resolve_adequacy_gated()`](https://mufflyt.github.io/cliff/reference/resolve_adequacy_gated.md)

## Examples

``` r
validate_capacity_evidence(
  capacity_evidence_bundle(data.frame(identified = FALSE, adequacy = NA_real_),
                           list(fully_identified = FALSE, total = NA_real_)))
```
