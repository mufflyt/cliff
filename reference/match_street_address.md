# Match Street Addresses

Compares physician address to program address. Returns TRUE if street
number matches AND at least one key street token matches.

## Usage

``` r
match_street_address(phys_addr, prog_addr)
```

## Arguments

- phys_addr:

  Normalized address list (from normalize_street_address)

- prog_addr:

  Normalized address list (from normalize_street_address)

## Value

Logical
