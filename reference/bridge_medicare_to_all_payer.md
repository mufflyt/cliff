# Lift a Medicare-observed workload to an all-payer workload, by age band

Apply the age-graded CHIA/Medicare multiplier to a Medicare
fee-for-service workload, band by band, returning the implied all-payer
workload where the bridge is identified and refusing where it is not.

## Usage

``` r
bridge_medicare_to_all_payer(
  medicare_by_band,
  contract = chia_bridge_contract(),
  min_capture = CHIA_BRIDGE_MIN_MEDICARE_CAPTURE
)
```

## Arguments

- medicare_by_band:

  A \`data.frame\` with columns \`age_lower\` (matching the contract's
  bands) and \`medicare_volume\` (a non-negative workload measure, e.g.
  service volume or work RVUs). One row per band.

- contract:

  A bridge contract, defaulting to \[chia_bridge_contract()\]. Validated
  via \[validate_chia_bridge_contract()\].

- min_capture:

  The Medicare-capture floor for identifiability. Defaults to the SSOT
  \[CHIA_BRIDGE_MIN_MEDICARE_CAPTURE\].

## Value

A \`data.frame\`, one row per input band, with \`age_lower\`,
\`medicare_volume\`, \`medicare_capture\`, \`multiplier\`,
\`calibration_status\`, \`all_payer_volume\` (\`NA\` when unidentified),
\`identified\` (logical), and \`reason\` (\`NA\` when identified).

## Details

A band resolves only when its contract row is \`calibrated\` AND its
Medicare capture share is at least \`min_capture\` (equivalently its
multiplier is at most \`1 / min_capture\`). Otherwise the all-payer
volume is \`NA\` and \`identified\` is \`FALSE\` with a \`reason\` — the
bridge never fabricates an all-payer number from a near-empty Medicare
base or from an uncalibrated band.

## See also

\[chia_bridge_all_payer_total()\] to aggregate the identified bands;
\`demand_lifecourse/supply-staffing_conversion.R\` for the workload path
this feeds; \`tests/testthat/test-ssot-chia-medicare-bridge.R\` for the
guard.

Other chia-medicare-bridge:
[`chia_bridge_all_payer_total()`](https://mufflyt.github.io/cliff/reference/chia_bridge_all_payer_total.md),
[`chia_bridge_contract()`](https://mufflyt.github.io/cliff/reference/chia_bridge_contract.md),
[`validate_chia_bridge_contract()`](https://mufflyt.github.io/cliff/reference/validate_chia_bridge_contract.md)

## Examples

``` r
md <- data.frame(age_lower = c(0L, 65L, 75L, 85L),
                 medicare_volume = c(10, 400, 300, 120))
# shipped contract is provisional -> every band is refused:
bridge_medicare_to_all_payer(md)$identified
#> [1] FALSE FALSE FALSE FALSE
```
