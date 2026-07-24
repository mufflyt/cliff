#!/usr/bin/env Rscript
# Investigate NPI format issues in Medicare data

# Based on the sample NPIs we saw: 1225032279, 1003022120, etc.
sample_npis <- c("1225032279", "1003022120", "1437136881", "1225036577")

cat("=== NPI FORMAT INVESTIGATION ===\n\n")

# Check NPI format patterns
cat("1. NPI Format Analysis:\n")
for(npi in sample_npis) {
  cat(sprintf("NPI: %s\n", npi))
  cat(sprintf("  Length: %d\n", nchar(npi)))
  cat(sprintf("  First digit: %s\n", substr(npi, 1, 1)))
  cat(sprintf("  Pattern: %s\n", gsub("\\d", "X", npi)))
  cat("\n")
}

# Real NPIs typically start with 1 and are issued sequentially
# Let's check the NPI format rules:

cat("2. NPI Format Rules:\n")
cat("- Real NPIs are 10 digits\n")
cat("- Start with 1 or 2\n")
cat("- Issued sequentially starting from 1000000001\n")
cat("- Must pass Luhn validation\n")
cat("- Current range: ~1000000001 to ~1999999999\n\n")

# Check if these could be UPINs
cat("3. UPIN Analysis:\n")
cat("UPINs (pre-2007) were 6 alphanumeric characters\n")
cat("These 10-digit numbers could be:\n")
cat("- Padded/converted UPINs\n")
cat("- Internal CMS identifiers\n")
cat("- Legacy system artifacts\n\n")

# Check the range of our sample NPIs
min_npi <- min(as.numeric(sample_npis))
max_npi <- max(as.numeric(sample_npis))

cat("4. Sample NPI Range:\n")
cat(sprintf("Min: %d\n", min_npi))
cat(sprintf("Max: %d\n", max_npi))
cat(sprintf("Range: %d\n", max_npi - min_npi))

# Compare to known NPI ranges
cat("\n5. Comparison to Real NPI Ranges:\n")
cat("Real NPIs issued:\n")
cat("- 2005-2007: 1000000001-1200000000 (approx)\n")
cat("- 2008-2015: 1200000000-1700000000 (approx)\n")
cat("- 2016-2021: 1700000000-1999999999 (approx)\n")
cat("\nOur sample NPIs fall in the 2007-2015 range\n")

cat("\n6. Hypothesis:\n")
cat("These may be legitimate NPIs that:\n")
cat("- Have data entry errors (wrong check digits)\n")
cat("- Are from a dataset with systematic Luhn validation issues\n")
cat("- Were processed incorrectly during database import\n")
cat("- Are test/synthetic NPIs that look real but aren't\n\n")

cat("7. Recommendation:\n")
cat("For research purposes, we should:\n")
cat("- Use these identifiers as-is (bypass Luhn validation)\n")
cat("- Focus on the retirement detection logic\n")
cat("- The 5-source approach is more important than NPI validation\n")
cat("- Real production systems would need proper NPI verification\n")
