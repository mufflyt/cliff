# Resolve an absolute adequacy through the capacity-evidence gate

The gate. Returns the access fit's absolute adequacy ONLY when the
bundle's evidence is sufficient (see
\[capacity_evidence_sufficient()\]); otherwise it refuses with
\`resolved = FALSE\`, \`adequacy = NA\`, and a reason. The absolute
anchor is never reported on incomplete evidence.

## Usage

``` r
resolve_adequacy_gated(bundle)
```

## Arguments

- bundle:

  A \`capacity_evidence_bundle\`.

## Value

A one-row \`data.frame\` with \`label\`, \`resolved\` (logical),
\`adequacy\` (the resolved absolute adequacy, or \`NA_real\_\`),
\`access_identified\`, \`demand_fully_identified\`, and \`reason\`
(\`NA\` when resolved).

## See also

\[capacity_evidence_bundle()\], \[wait_to_adequacy()\],
\[chia_bridge_all_payer_total()\];
\`tests/testthat/test-ssot-capacity-evidence.R\` for the guard.

Other capacity-evidence:
[`capacity_evidence_bundle()`](https://mufflyt.github.io/cliff/reference/capacity_evidence_bundle.md),
[`capacity_evidence_sufficient()`](https://mufflyt.github.io/cliff/reference/capacity_evidence_sufficient.md),
[`chia_calibrated_all_payer_total()`](https://mufflyt.github.io/cliff/reference/chia_calibrated_all_payer_total.md),
[`project_absolute_adequacy()`](https://mufflyt.github.io/cliff/reference/project_absolute_adequacy.md),
[`validate_capacity_evidence()`](https://mufflyt.github.io/cliff/reference/validate_capacity_evidence.md)

## Examples

``` r
good <- capacity_evidence_bundle(data.frame(identified = TRUE, adequacy = 1.4),
                                 list(fully_identified = TRUE, total = 1000),
                                 label = "national")
resolve_adequacy_gated(good)$adequacy        # 1.4
#> [1] 1.4
bad <- capacity_evidence_bundle(data.frame(identified = FALSE, adequacy = NA_real_),
                                list(fully_identified = TRUE, total = 1000))
resolve_adequacy_gated(bad)$resolved         # FALSE
#> [1] FALSE
```
