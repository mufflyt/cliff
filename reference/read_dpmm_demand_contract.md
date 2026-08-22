# Read a DPMM demand-contract CSV and its calibration status

Thin base-R I/O wrapper. Returns \`NULL\` when \`path\` is empty or
missing, so a caller can cleanly fall back to the published-anchor
denominators.

## Usage

``` r
read_dpmm_demand_contract(path)
```

## Arguments

- path:

  path to a \`dpmm_demand_contract_v\*.csv\` (may be \`""\` / absent).

## Value

\`list(data = data.frame, status = character, tier_status = named
character or NULL)\` or \`NULL\`.

## Details

The DMDM contract (from the simulation repo's
\`export_dmdm_demand_contract()\`) may carry a
\`tier_calibration_status\` column, which stamps provenance PER TIER
rather than for the whole artifact: e.g. when the contract is produced
from the literature POP transitions, \`dmdm_pop\` is
\`derived_by_analogy\` while \`dmdm_ui\`/ \`dmdm_ai\` remain
placeholders. \`tier_status\` surfaces that mapping so a consumer can
gate on the provenance of the specific tier it reads. Older contracts
without the column yield \`tier_status = NULL\`; use
\[dpmm_tier_status()\] to read a tier's status with a fall back to the
object-level \`status\`.
