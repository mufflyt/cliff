#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Full Pipeline Integration Test
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Purpose: Test complete workforce analysis pipeline end-to-end
#
# Tests:
#   1. Main pipeline (default scenario)
#   2. Main pipeline (optimistic scenario)
#   3. Scenario comparison
#   4. Monte Carlo validation
#   5. Retirement sensitivity
#   6. Verify all outputs exist
#
# Author: Tyler Muffly, MD / Claude Code
# Date: 2026-01-12
#
# Usage:
#   cd /Users/tmuffly/isochrones
#   bash cliff/TEST_FULL_PIPELINE.sh
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

set -e  # Exit on error

echo ""
echo "================================================================================"
echo "FULL PIPELINE INTEGRATION TEST"
echo "================================================================================"
echo ""
echo "Started: $(date)"
echo ""

# Change to project directory
cd /Users/tmuffly/isochrones

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Test 1: Main Pipeline (Default Scenario)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

echo "================================================================================"
echo "TEST 1: Main Pipeline - Default Scenario"
echo "================================================================================"
echo ""

Rscript cliff/code/00_RUN_ALL.R default

echo ""
echo "✓ Test 1 passed: Main pipeline (default) completed"
echo ""

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Test 2: Main Pipeline (Optimistic Scenario)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

echo "================================================================================"
echo "TEST 2: Main Pipeline - Optimistic Scenario"
echo "================================================================================"
echo ""

Rscript cliff/code/00_RUN_ALL.R optimistic

echo ""
echo "✓ Test 2 passed: Main pipeline (optimistic) completed"
echo ""

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Test 3: Scenario Comparison
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

echo "================================================================================"
echo "TEST 3: Scenario Comparison Tool"
echo "================================================================================"
echo ""

Rscript cliff/code/04_compare_scenarios.R

echo ""
echo "✓ Test 3 passed: Scenario comparison completed"
echo ""

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Test 4: Monte Carlo Validation
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

echo "================================================================================"
echo "TEST 4: Monte Carlo Validation"
echo "================================================================================"
echo ""

Rscript cliff/code/05_validate_with_monte_carlo.R

echo ""
echo "✓ Test 4 passed: Monte Carlo validation completed"
echo ""

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Test 5: Retirement Sensitivity
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

echo "================================================================================"
echo "TEST 5: Retirement Sensitivity Analysis"
echo "================================================================================"
echo ""

Rscript cliff/code/06_retirement_sensitivity.R

echo ""
echo "✓ Test 5 passed: Retirement sensitivity completed"
echo ""

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Verify Outputs
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

echo "================================================================================"
echo "VERIFYING OUTPUTS"
echo "================================================================================"
echo ""

EXPECTED_FILES=(
  # Data files
  "cliff/data/workforce_projections_consolidated.csv"
  "cliff/data/scenario_comparison.csv"
  "cliff/data/retirement_sensitivity.csv"

  # Manuscript figures
  "cliff/figures/figure1_workforce_trajectories.png"
  "cliff/figures/figure1_workforce_trajectories.tiff"
  "cliff/figures/figure2_replacement_gap.png"
  "cliff/figures/figure2_replacement_gap.tiff"

  # Abstract figure
  "cliff/figures/workforce_crisis_abstract.png"
  "cliff/figures/workforce_crisis_abstract.tiff"

  # Scenario comparison figures
  "cliff/figures/scenario_comparison.png"
  "cliff/figures/scenario_comparison.tiff"
  "cliff/figures/scenario_comparison_change.png"
  "cliff/figures/scenario_comparison_change.tiff"

  # Monte Carlo validation figures
  "cliff/figures/monte_carlo_validation.png"
  "cliff/figures/monte_carlo_validation.tiff"
  "cliff/figures/monte_carlo_validation_scatter.png"
  "cliff/figures/monte_carlo_validation_scatter.tiff"

  # Retirement sensitivity figures
  "cliff/figures/retirement_sensitivity_workforce.png"
  "cliff/figures/retirement_sensitivity_workforce.tiff"
  "cliff/figures/retirement_sensitivity_change.png"
  "cliff/figures/retirement_sensitivity_change.tiff"

  # Manuscripts
  "cliff/manuscript/WORKFORCE_CLIFF_ObGyn.html"
  "cliff/manuscript/WORKFORCE_CLIFF_ObGyn.docx"
)

MISSING_COUNT=0
for file in "${EXPECTED_FILES[@]}"; do
  if [ -f "$file" ]; then
    echo "  ✓ $file"
  else
    echo "  ✗ MISSING: $file"
    MISSING_COUNT=$((MISSING_COUNT + 1))
  fi
done

echo ""

# Count archived runs
RUN_COUNT=$(ls -1 cliff/outputs/runs/ 2>/dev/null | wc -l | tr -d ' ')
echo "Archived runs: $RUN_COUNT"

# Count figures
PNG_COUNT=$(ls -1 cliff/figures/*.png 2>/dev/null | wc -l | tr -d ' ')
TIFF_COUNT=$(ls -1 cliff/figures/*.tiff 2>/dev/null | wc -l | tr -d ' ')
echo "Figures: $PNG_COUNT PNG, $TIFF_COUNT TIFF"

echo ""

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Summary
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

echo "================================================================================"
echo "TEST SUMMARY"
echo "================================================================================"
echo ""

if [ $MISSING_COUNT -eq 0 ]; then
  echo "✓ ALL TESTS PASSED"
  echo ""
  echo "Results:"
  echo "  • All 5 test scenarios completed successfully"
  echo "  • All ${#EXPECTED_FILES[@]} expected files generated"
  echo "  • $RUN_COUNT pipeline runs archived"
  echo "  • $PNG_COUNT PNG figures + $TIFF_COUNT TIFF figures created"
  echo ""
  echo "Pipeline is production-ready ✓"
  exit 0
else
  echo "✗ TESTS FAILED"
  echo ""
  echo "  $MISSING_COUNT files missing"
  echo ""
  exit 1
fi
