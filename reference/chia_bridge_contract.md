# The CHIA \<-\> Medicare age-banded bridge contract (provisional)

Return the age-banded all-payer/Medicare bridge as a tidy contract: one
row per age band with the Medicare fee-for-service capture share, the
implied all-payer multiplier (\`1 / capture\`), and a
\`calibration_status\`.

## Usage

``` r
chia_bridge_contract()
```

## Value

A \`data.frame\` with columns \`age_lower\` (integer),
\`medicare_capture\` (double in \`(0, 1\]\`), \`multiplier\` (double,
\`1 / medicare_capture\`), and \`calibration_status\` (character).

## Details

The shipped levels are PROVISIONAL and illustrative
(\`calibration_status = "not_calibrated"\`): they encode the expected
age gradient (capture near zero below 65, then rising 65 -\> 75 -\> 85+
as Medicare Advantage penetration falls and fee-for-service dominates)
but are NOT real CHIA/Medicare figures. Because
\[bridge_medicare_to_all_payer()\] refuses every \`not_calibrated\`
band, these placeholders can never produce an all-payer number; a real
CHIA APCD / Medicare FFS extract for the URPS anchor procedures replaces
\`medicare_capture\` and sets \`calibration_status = "calibrated"\`.

Bands are left-closed \`\[age_lower, next age_lower)\`, split at the
Medicare eligibility boundary (65) so the pre-Medicare band is isolated.
The 65+ split (65/75/85) carries the within-eligible age gradient.

## See also

\[bridge_medicare_to_all_payer()\], \[validate_chia_bridge_contract()\];
\`R/urps_procedure_codes.R\` for the anchor procedures the extract keys
on.

Other chia-medicare-bridge:
[`bridge_medicare_to_all_payer()`](https://mufflyt.github.io/cliff/reference/bridge_medicare_to_all_payer.md),
[`chia_bridge_all_payer_total()`](https://mufflyt.github.io/cliff/reference/chia_bridge_all_payer_total.md),
[`validate_chia_bridge_contract()`](https://mufflyt.github.io/cliff/reference/validate_chia_bridge_contract.md)

## Examples

``` r
chia_bridge_contract()
#>   age_lower medicare_capture multiplier calibration_status
#> 1         0             0.05  20.000000     not_calibrated
#> 2        65             0.72   1.388889     not_calibrated
#> 3        75             0.82   1.219512     not_calibrated
#> 4        85             0.88   1.136364     not_calibrated
```
