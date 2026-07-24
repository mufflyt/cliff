#!/usr/bin/env Rscript
# Correct NPI Luhn validation
# For NPIs, the validation is done on positions 1-9, and position 10 is the check digit

correct_npi_luhn <- function(npi_str) {
  if (nchar(npi_str) != 10) return(FALSE)

  digits <- as.numeric(strsplit(npi_str, "")[[1]])

  # For NPI Luhn: sum odd positions + sum of (even positions * 2, with digit sum if >9)
  # But NPI uses a modified algorithm
  sum_total <- 0

  # Process positions 1-9 (check digit is position 10)
  for(i in 1:9) {
    digit <- digits[i]
    if (i %% 2 == 1) {
      # Odd positions: double the digit
      doubled <- digit * 2
      sum_total <- sum_total + (doubled %/% 10) + (doubled %% 10)
    } else {
      # Even positions: add as-is
      sum_total <- sum_total + digit
    }
  }

  # The check digit should make the total divisible by 10
  calculated_check <- (10 - (sum_total %% 10)) %% 10
  actual_check <- digits[10]

  cat(sprintf("NPI: %s\n", npi_str))
  cat(sprintf("Sum of positions 1-9: %d\n", sum_total))
  cat(sprintf("Calculated check digit: %d\n", calculated_check))
  cat(sprintf("Actual check digit: %d\n", actual_check))
  cat(sprintf("Valid: %s\n\n", calculated_check == actual_check))

  return(calculated_check == actual_check)
}

# Test with known NPIs
test_npis <- c(
  "1234567893",  # Test NPI
  "1225032279",  # From database
  "1003022120",  # From database
  "1437136881"   # From database
)

for(npi in test_npis) {
  correct_npi_luhn(npi)
}

# For comparison, test a definitely valid NPI format
# Let's create a valid NPI
create_valid_npi <- function(first_9_digits) {
  digits <- as.numeric(strsplit(first_9_digits, "")[[1]])
  sum_total <- 0

  for(i in 1:9) {
    digit <- digits[i]
    if (i %% 2 == 1) {
      doubled <- digit * 2
      sum_total <- sum_total + (doubled %/% 10) + (doubled %% 10)
    } else {
      sum_total <- sum_total + digit
    }
  }

  check_digit <- (10 - (sum_total %% 10)) %% 10
  valid_npi <- paste0(first_9_digits, check_digit)

  cat(sprintf("Created valid NPI: %s\n", valid_npi))
  correct_npi_luhn(valid_npi)

  return(valid_npi)
}

cat("Creating a valid NPI:\n")
valid_test <- create_valid_npi("123456789")
