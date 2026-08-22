# Validate a CHIA \<-\> Medicare bridge contract (hard-fail on any violation)

Enforce the bridge contract schema: the required columns, strictly
increasing left-closed age bands, capture shares in \`(0, 1\]\`, the
\`multiplier\` being exactly \`1 / medicare_capture\` (the two encodings
can never disagree), and a closed \`calibration_status\` vocabulary.
Returns the contract invisibly so it can wrap a constructor.

## Usage

``` r
validate_chia_bridge_contract(contract)
```

## Arguments

- contract:

  A candidate bridge contract \`data.frame\`.

## Value

The validated \`contract\`, invisibly.

## See also

\[chia_bridge_contract()\]

Other chia-medicare-bridge:
[`bridge_medicare_to_all_payer()`](https://mufflyt.github.io/cliff/reference/bridge_medicare_to_all_payer.md),
[`chia_bridge_all_payer_total()`](https://mufflyt.github.io/cliff/reference/chia_bridge_all_payer_total.md),
[`chia_bridge_contract()`](https://mufflyt.github.io/cliff/reference/chia_bridge_contract.md)

## Examples

``` r
validate_chia_bridge_contract(chia_bridge_contract())
```
