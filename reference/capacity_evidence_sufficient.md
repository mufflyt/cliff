# Is a capacity-evidence bundle strong enough to resolve absolute adequacy?

The evidence is sufficient only when BOTH conditions hold: the access
fit is identified (a wait-based adequacy exists and was not refused),
and the all-payer demand basis behind it is fully identified (no age
band was dropped).

## Usage

``` r
capacity_evidence_sufficient(bundle)
```

## Arguments

- bundle:

  A \`capacity_evidence_bundle\`.

## Value

A list with \`sufficient\` (logical) and \`reasons\` (character vector
of the failing conditions; empty when sufficient).

## See also

\[resolve_adequacy_gated()\]

Other capacity-evidence:
[`capacity_evidence_bundle()`](https://mufflyt.github.io/cliff/reference/capacity_evidence_bundle.md),
[`chia_calibrated_all_payer_total()`](https://mufflyt.github.io/cliff/reference/chia_calibrated_all_payer_total.md),
[`project_absolute_adequacy()`](https://mufflyt.github.io/cliff/reference/project_absolute_adequacy.md),
[`resolve_adequacy_gated()`](https://mufflyt.github.io/cliff/reference/resolve_adequacy_gated.md),
[`validate_capacity_evidence()`](https://mufflyt.github.io/cliff/reference/validate_capacity_evidence.md)

## Examples

``` r
capacity_evidence_sufficient(
  capacity_evidence_bundle(data.frame(identified = TRUE, adequacy = 1.3),
                           list(fully_identified = TRUE, total = 900)))
#> $sufficient
#> [1] TRUE
#> 
#> $reasons
#> character(0)
#> 
```
