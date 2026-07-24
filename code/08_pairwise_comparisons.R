#' @title Step 8: Pairwise Comparisons for Table 1 Variables
#' @description This script programmatically identifies statistically significant variables from
#' Table 1 and performs pairwise comparisons between subspecialties using ANOVA/Tukey HSD
#' for continuous variables and Chi-square/Bonferroni for categorical variables.
#' @author Tyler Muffly, MD / Claude Code
#' @date 2026-01-12
#' @return CSV files containing overall significance results and pairwise comparison results
#' for significant variables.
#' @seealso \code{\link{00_RUN_ALL.R}}, \code{\link{07_create_table1.R}}

#!/usr/bin/env Rscript

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 8: Pairwise Comparisons for Table 1 Variables
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Purpose: Programmatically identify statistically significant variables from
#          Table 1 and perform pairwise comparisons between subspecialties
#
# Author: Tyler Muffly, MD / Claude Code
# Date: 2026-01-12
#
# Usage:
#   Rscript cliff/code/08_pairwise_comparisons.R
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# The 'suppressPackageStartupMessages' function prevents package startup messages from being printed.
suppressPackageStartupMessages({
  # The 'tidyverse' library is a collection of R packages designed for data science.
  # It includes ggplot2, dplyr, tidyr, readr, purrr, and tibble.
  library(tidyverse)
  # The 'here' library helps to create reproducible paths to files.
  library(here)
  # The 'broom' library converts statistical analysis objects into tidy tibbles.
  library(broom)
})

cat("\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("PAIRWISE COMPARISONS FOR TABLE 1 VARIABLES\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("\n")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 1: Load Table 1 Data
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("[", as.character(Sys.time()), "] Loading Table 1 data...\n", sep = "")

# The 'read_csv' function reads a comma-separated value (CSV) file into a tibble.
table1_data <- read_csv(
  here("cliff", "data", "table1_physicians.csv"),
  show_col_types = FALSE
)

# The 'factor' function encodes a vector as a factor.
# Ensure Subspecialty is a factor with proper levels
table1_data$Subspecialty <- factor(
  table1_data$Subspecialty,
  levels = c("FPMRS (Urogynecology)", "Gynecologic Oncology", "MIGS")
)

cat(sprintf("  Sample size: %s physicians\n", format(nrow(table1_data), big.mark = ",")))
cat(sprintf("  Subspecialties: %s\n", paste(levels(table1_data$Subspecialty), collapse = ", ")))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 2: Programmatically Identify Variables and Their Types
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("\n[", as.character(Sys.time()), "] Identifying variables...\n", sep = "")

# The 'setdiff' function returns the elements in x that are not in y.
# Get all column names except Subspecialty (the grouping variable)
all_vars <- setdiff(names(table1_data), "Subspecialty")

# Determine variable types programmatically
continuous_vars <- character()
categorical_vars <- character()

for (var in all_vars) {
  # The 'class' function returns the class of an object.
  var_class <- class(table1_data[[var]])

  if ("numeric" %in% var_class || "integer" %in% var_class) {
    # Check if it has a reasonable number of unique values for continuous
    n_unique <- length(unique(table1_data[[var]][!is.na(table1_data[[var]])]))
    if (n_unique > 10) {
      continuous_vars <- c(continuous_vars, var)
    } else {
      categorical_vars <- c(categorical_vars, var)
    }
  } else if ("factor" %in% var_class || "character" %in% var_class) {
    categorical_vars <- c(categorical_vars, var)
    # Ensure categorical variables are factors
    if ("character" %in% var_class) {
      table1_data[[var]] <- factor(table1_data[[var]])
    }
  }
}

cat(sprintf("  Continuous variables: %d\n", length(continuous_vars)))
if (length(continuous_vars) > 0) {
  for (var in continuous_vars) {
    cat(sprintf("    - %s\n", var))
  }
}

cat(sprintf("  Categorical variables: %d\n", length(categorical_vars)))
if (length(categorical_vars) > 0) {
  for (var in categorical_vars) {
    cat(sprintf("    - %s\n", var))
  }
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 3: Test Overall Significance for Each Variable
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("\n[", as.character(Sys.time()), "] Testing overall significance...\n", sep = "")

results_list <- list()

# Test continuous variables with ANOVA
for (var in continuous_vars) {
  # Check for sufficient non-missing data
  non_missing <- sum(!is.na(table1_data[[var]]))

  if (non_missing > 10) {
    formula_str <- sprintf("`%s` ~ Subspecialty", var)
    aov_result <- aov(as.formula(formula_str), data = table1_data)
    p_value <- summary(aov_result)[[1]][["Pr(>F)"]][1]

    results_list[[var]] <- list(
      variable = var,
      type = "continuous",
      test = "ANOVA",
      p_value = p_value,
      significant = p_value < 0.05
    )

    cat(sprintf("  %s: p = %.4f %s\n",
                var, p_value,
                ifelse(p_value < 0.05, "***", "")))
  }
}

# Test categorical variables with Chi-square
for (var in categorical_vars) {
  # Remove missing values for chi-square test
  test_data <- table1_data %>%
    filter(!is.na(.data[[var]]))

  if (nrow(test_data) > 0) {
    contingency_table <- table(test_data[[var]], test_data$Subspecialty)

    # Only test if we have sufficient data (at least 2 levels for each dimension)
    if (all(dim(contingency_table) > 1)) {
      chisq_result <- tryCatch({
        chisq.test(contingency_table)
      }, warning = function(w) {
        chisq.test(contingency_table, simulate.p.value = TRUE, B = 2000)
      }, error = function(e) {
        NULL
      })

      if (!is.null(chisq_result)) {
        p_value <- chisq_result$p.value

        results_list[[var]] <- list(
          variable = var,
          type = "categorical",
          test = "Chi-square",
          p_value = p_value,
          significant = p_value < 0.05
        )

        cat(sprintf("  %s: p = %.4f %s\n",
                    var, p_value,
                    ifelse(p_value < 0.05, "***", "")))
      }
    }
  }
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 4: Pairwise Comparisons for Significant Variables
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("\n[", as.character(Sys.time()), "] Performing pairwise comparisons...\n", sep = "")

significant_vars <- names(results_list)[sapply(results_list, function(x) x$significant)]

if (length(significant_vars) == 0) {
  cat("  No statistically significant variables found.\n")
} else {
  cat(sprintf("  Found %d significant variable(s)\n\n", length(significant_vars)))
}

pairwise_results <- list()

for (var in significant_vars) {
  cat(paste0(rep("-", 80), collapse = ""), "\n")
  cat(sprintf("Variable: %s\n", var))
  cat(paste0(rep("-", 80), collapse = ""), "\n")

  if (results_list[[var]]$type == "continuous") {
    # Continuous variables: Tukey HSD post-hoc test
    formula_str <- sprintf("`%s` ~ Subspecialty", var)
    aov_result <- aov(as.formula(formula_str), data = table1_data)
    tukey_result <- TukeyHSD(aov_result)

    # Extract pairwise comparisons
    comparisons <- as.data.frame(tukey_result$Subspecialty)
    comparisons$comparison <- rownames(comparisons)
    rownames(comparisons) <- NULL

    pairwise_results[[var]] <- comparisons

    cat("\nPairwise comparisons (Tukey HSD):\n")
    for (i in seq_len(nrow(comparisons))) {
      cat(sprintf("  %s:\n", comparisons$comparison[i]))
      cat(sprintf("    Difference: %.2f (95%% CI: %.2f to %.2f)\n",
                  comparisons$diff[i],
                  comparisons$lwr[i],
                  comparisons$upr[i]))
      cat(sprintf("    p-value: %.4f %s\n",
                  comparisons$`p adj`[i],
                  ifelse(comparisons$`p adj`[i] < 0.05, "***", "")))
    }

    # Calculate descriptive statistics by subspecialty
    descriptive <- table1_data %>%
      group_by(Subspecialty) %>%
      summarise(
        mean = mean(.data[[var]], na.rm = TRUE),
        sd = sd(.data[[var]], na.rm = TRUE),
        n = sum(!is.na(.data[[var]])),
        .groups = "drop"
      )

    cat("\nDescriptive statistics:\n")
    for (i in seq_len(nrow(descriptive))) {
      cat(sprintf("  %s: %.1f ± %.1f (n=%d)\n",
                  descriptive$Subspecialty[i],
                  descriptive$mean[i],
                  descriptive$sd[i],
                  descriptive$n[i]))
    }

  } else {
    # Categorical variables: Pairwise chi-square tests
    subspecialties <- levels(table1_data$Subspecialty)
    comparisons <- combn(subspecialties, 2, simplify = FALSE)

    comparison_results <- data.frame(
      comparison = character(),
      chi_square = numeric(),
      p_value = numeric(),
      stringsAsFactors = FALSE
    )

    for (comp in comparisons) {
      test_data <- table1_data %>%
        filter(Subspecialty %in% comp, !is.na(.data[[var]])) %>%
        mutate(Subspecialty = droplevels(Subspecialty))

      if (nrow(test_data) > 0) {
        contingency_table <- table(test_data[[var]], test_data$Subspecialty)

        chisq_result <- tryCatch({
          chisq.test(contingency_table)
        }, warning = function(w) {
          chisq.test(contingency_table, simulate.p.value = TRUE, B = 2000)
        }, error = function(e) {
          NULL
        })

        if (!is.null(chisq_result)) {
          comparison_results <- rbind(
            comparison_results,
            data.frame(
              comparison = paste(comp, collapse = " vs "),
              chi_square = chisq_result$statistic,
              p_value = chisq_result$p.value,
              stringsAsFactors = FALSE
            )
          )
        }
      }
    }

    # Apply Bonferroni correction
    comparison_results$p_adj <- p.adjust(comparison_results$p_value, method = "bonferroni")

    pairwise_results[[var]] <- comparison_results

    cat("\nPairwise comparisons (Chi-square with Bonferroni correction):\n")
    for (i in seq_len(nrow(comparison_results))) {
      cat(sprintf("  %s:\n", comparison_results$comparison[i]))
      cat(sprintf("    Chi-square: %.2f\n", comparison_results$chi_square[i]))
      cat(sprintf("    p-value (raw): %.4f\n", comparison_results$p_value[i]))
      cat(sprintf("    p-value (adjusted): %.4f %s\n",
                  comparison_results$p_adj[i],
                  ifelse(comparison_results$p_adj[i] < 0.05, "***", "")))
    }

    # Calculate proportions by subspecialty
    cat("\nDistribution by subspecialty:\n")
    prop_table <- table1_data %>%
      filter(!is.na(.data[[var]])) %>%
      count(Subspecialty, .data[[var]]) %>%
      group_by(Subspecialty) %>%
      mutate(
        total = sum(n),
        percent = (n / total) * 100
      ) %>%
      ungroup()

    for (subspec in subspecialties) {
      cat(sprintf("\n  %s:\n", subspec))
      subspec_data <- prop_table %>% filter(Subspecialty == subspec)
      for (j in seq_len(nrow(subspec_data))) {
        cat(sprintf("    %s: %d (%.1f%%)\n",
                    subspec_data[[var]][j],
                    subspec_data$n[j],
                    subspec_data$percent[j]))
      }
    }
  }

  cat("\n")
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 5: Save Results
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("[", as.character(Sys.time()), "] Saving results...\n", sep = "")

# Create output directory
output_dir <- here("cliff", "data")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Save overall significance results
overall_results_df <- bind_rows(lapply(results_list, function(x) {
  data.frame(
    variable = x$variable,
    type = x$type,
    test = x$test,
    p_value = x$p_value,
    significant = x$significant,
    stringsAsFactors = FALSE
  )
})) %>%
  arrange(p_value)

write_csv(
  overall_results_df,
  here(output_dir, "table1_overall_significance.csv")
)

cat(sprintf("  ✓ Saved overall significance: %s\n",
            here(output_dir, "table1_overall_significance.csv")))

# Save pairwise results
for (var in names(pairwise_results)) {
  var_clean <- gsub("[^A-Za-z0-9]", "_", var)
  filename <- sprintf("table1_pairwise_%s.csv", tolower(var_clean))

  write_csv(
    pairwise_results[[var]],
    here(output_dir, filename)
  )

  cat(sprintf("  ✓ Saved pairwise results for '%s': %s\n",
              var, here(output_dir, filename)))
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Summary
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("PAIRWISE COMPARISON ANALYSIS COMPLETE\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("\n")

cat("Summary:\n")
cat(sprintf("  • Variables tested: %d\n", length(results_list)))
cat(sprintf("  • Statistically significant (p < 0.05): %d\n", length(significant_vars)))
cat("\n")

if (length(significant_vars) > 0) {
  cat("Significant variables:\n")
  sig_vars_sorted <- names(results_list)[order(sapply(results_list, function(x) x$p_value))]
  sig_vars_sorted <- sig_vars_sorted[sig_vars_sorted %in% significant_vars]

  for (var in sig_vars_sorted) {
    cat(sprintf("  • %s (p = %.4f)\n", var, results_list[[var]]$p_value))
  }
  cat("\n")

  cat("Output files:\n")
  cat(sprintf("  • Overall significance: %s\n",
              here(output_dir, "table1_overall_significance.csv")))
  for (var in sig_vars_sorted) {
    var_clean <- gsub("[^A-Za-z0-9]", "_", var)
    filename <- sprintf("table1_pairwise_%s.csv", tolower(var_clean))
    cat(sprintf("  • Pairwise for '%s': %s\n", var, here(output_dir, filename)))
  }
}

cat("\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("\n")

if (!interactive()) {
  cat("[", as.character(Sys.time()), "] Script completed successfully\n", sep = "")
}
