# Weighted Token Similarity Between Two Org Names

Shared tokens are weighted: non-generic words count 1.0, generic words
count 0.25. Returns weighted overlap / total union.

## Usage

``` r
weighted_token_similarity(a, b)
```

## Arguments

- a:

  Normalized uppercase string

- b:

  Normalized uppercase string

## Value

Numeric in \[0, 1\]
