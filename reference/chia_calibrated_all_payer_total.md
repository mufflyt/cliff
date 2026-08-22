# All-payer demand total from a CALIBRATED CHIA bridge application

Turn the output of \[apply_chia_demand_bridge()\] into the
demand-evidence shape the capacity-evidence gate consumes — the
calibrated-engine analog of \[chia_bridge_all_payer_total()\]. A
Medicare age band counts as identified only when it received a finite
calibrated all-payer workload (i.e. a non-\`NA\` \`bridge_multiplier\`);
bands the calibrated bridge could not cover are reported, never silently
summed over.

## Usage

``` r
chia_calibrated_all_payer_total(applied)
```

## Arguments

- applied:

  The \`data.frame\` returned by \[apply_chia_demand_bridge()\] (must
  carry \`age_band_lower\`, \`bridge_multiplier\`, and
  \`calibrated_all_payer_workload\`).

## Value

A list with \`total\` (summed all-payer workload over identified bands,
\`NA_real\_\` if none), \`fully_identified\` (logical: every band
identified), \`n_identified\`, \`n_total\`, and \`unidentified_bands\`
(the \`age_band_lower\` values with no calibrated multiplier). This is
exactly the shape \[capacity_evidence_bundle()\] expects for
\`demand_evidence\`.

## Details

Because \[apply_chia_demand_bridge()\] itself refuses (errors) unless
the bridge status is \`"calibrated"\`, any result reaching this function
already rests on a calibrated bridge; \`fully_identified\` then
additionally requires that no Medicare band was dropped for lack of a
calibrated CHIA multiplier.

## See also

\[apply_chia_demand_bridge()\], \[chia_bridge_all_payer_total()\],
\[project_absolute_adequacy()\], \[capacity_evidence_bundle()\].

Other capacity-evidence:
[`capacity_evidence_bundle()`](https://mufflyt.github.io/cliff/reference/capacity_evidence_bundle.md),
[`capacity_evidence_sufficient()`](https://mufflyt.github.io/cliff/reference/capacity_evidence_sufficient.md),
[`project_absolute_adequacy()`](https://mufflyt.github.io/cliff/reference/project_absolute_adequacy.md),
[`resolve_adequacy_gated()`](https://mufflyt.github.io/cliff/reference/resolve_adequacy_gated.md),
[`validate_capacity_evidence()`](https://mufflyt.github.io/cliff/reference/validate_capacity_evidence.md)

## Examples

``` r
applied <- data.frame(
  age_band_lower = c(65, 70, 75),
  bridge_multiplier = c(1.8, 1.5, NA),
  calibrated_all_payer_workload = c(900, 700, NA)
)
chia_calibrated_all_payer_total(applied)$fully_identified   # FALSE (75 dropped)
#> [1] FALSE
```
