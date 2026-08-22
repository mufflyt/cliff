# Aggregate an all-payer bridge result over its identified bands

Sum the identified all-payer volume and report whether every requested
band resolved. The \`fully_identified\` flag is the hook the
capacity-evidence gate keys on: an all-payer workload total is only
admissible when no band was silently dropped.

## Usage

``` r
chia_bridge_all_payer_total(bridged)
```

## Arguments

- bridged:

  The \`data.frame\` returned by \[bridge_medicare_to_all_payer()\].

## Value

A list with \`total\` (sum of \`all_payer_volume\` over identified
bands; \`NA_real\_\` if none), \`fully_identified\` (logical: all input
bands identified), \`n_identified\`, \`n_total\`, and
\`unidentified_bands\` (the \`age_lower\` values that were refused).

## See also

\[bridge_medicare_to_all_payer()\]

Other chia-medicare-bridge:
[`bridge_medicare_to_all_payer()`](https://mufflyt.github.io/cliff/reference/bridge_medicare_to_all_payer.md),
[`chia_bridge_contract()`](https://mufflyt.github.io/cliff/reference/chia_bridge_contract.md),
[`validate_chia_bridge_contract()`](https://mufflyt.github.io/cliff/reference/validate_chia_bridge_contract.md)

## Examples

``` r
md <- data.frame(age_lower = c(65L, 75L), medicare_volume = c(400, 300))
chia_bridge_all_payer_total(bridge_medicare_to_all_payer(md))
#> $total
#> [1] NA
#> 
#> $fully_identified
#> [1] FALSE
#> 
#> $n_identified
#> [1] 0
#> 
#> $n_total
#> [1] 2
#> 
#> $unidentified_bands
#> [1] 65 75
#> 
```
