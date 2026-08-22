# Assemble a capacity-evidence bundle from an access fit and a demand basis

Package the two pieces of evidence the absolute-adequacy gate needs into
one validated object: an access fit (the shape returned by
\[wait_to_adequacy()\]\[wait_to_adequacy\]) and an all-payer demand
basis (the shape returned by
\[chia_bridge_all_payer_total()\]\[chia_bridge_all_payer_total\]).

## Usage

``` r
capacity_evidence_bundle(access_fit, demand_evidence, label = NA_character_)
```

## Arguments

- access_fit:

  A one-row \`data.frame\` carrying at least logical \`identified\` and
  numeric \`adequacy\` columns (e.g. a row of \[wait_to_adequacy()\]
  output).

- demand_evidence:

  A list carrying at least logical \`fully_identified\` and numeric
  \`total\` (e.g. \[chia_bridge_all_payer_total()\] output).

- label:

  Optional short character label for the unit of analysis (region,
  scenario). Defaults to \`NA_character\_\`.

## Value

An object of class \`capacity_evidence_bundle\`: a list with
\`access_fit\`, \`demand_evidence\`, and \`label\`.

## Details

Construction validates only the SHAPES; whether the evidence is strong
enough to resolve adequacy is decided later by
\[capacity_evidence_sufficient()\] and \[resolve_adequacy_gated()\], so
an incomplete bundle is representable (and will be refused at the gate)
rather than un-constructable.

## See also

\[validate_capacity_evidence()\], \[resolve_adequacy_gated()\].

Other capacity-evidence:
[`capacity_evidence_sufficient()`](https://mufflyt.github.io/cliff/reference/capacity_evidence_sufficient.md),
[`chia_calibrated_all_payer_total()`](https://mufflyt.github.io/cliff/reference/chia_calibrated_all_payer_total.md),
[`project_absolute_adequacy()`](https://mufflyt.github.io/cliff/reference/project_absolute_adequacy.md),
[`resolve_adequacy_gated()`](https://mufflyt.github.io/cliff/reference/resolve_adequacy_gated.md),
[`validate_capacity_evidence()`](https://mufflyt.github.io/cliff/reference/validate_capacity_evidence.md)

## Examples

``` r
af <- data.frame(identified = TRUE, adequacy = 1.4)
de <- list(fully_identified = TRUE, total = 1200)
capacity_evidence_bundle(af, de, label = "national")
#> $access_fit
#>   identified adequacy
#> 1       TRUE      1.4
#> 
#> $demand_evidence
#> $demand_evidence$fully_identified
#> [1] TRUE
#> 
#> $demand_evidence$total
#> [1] 1200
#> 
#> 
#> $label
#> [1] "national"
#> 
#> attr(,"class")
#> [1] "capacity_evidence_bundle"
```
