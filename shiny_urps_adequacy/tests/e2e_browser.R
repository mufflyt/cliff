#!/usr/bin/env Rscript
# Browser end-to-end test for the URPS Effective-Adequacy Explorer.
# Drives the real app in a headless Chrome (shinytest2 AppDriver) and asserts
# that moving the "Urologists: clinical time in urogynecology" slider (uro_fte)
# actually recomputes the effective supply, the adequacy KPI, the scenario
# fingerprint, and redraws the plotly capacity-margin / adequacy charts.
#
#   Rscript tests/e2e_browser.R        (from cliff/shiny_urps_adequacy/)
suppressPackageStartupMessages({ library(shinytest2); library(testthat) })

# Headless-Chrome hardening: --no-sandbox / larger timeout so the debug port
# opens reliably in constrained environments.
Sys.setenv(NOT_CRAN = "true")
try(chromote::set_chrome_args(unique(c(
  tryCatch(chromote::get_chrome_args(), error = function(e) character()),
  "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"))), silent = TRUE)
options(chromote.timeout = 60)

# first standalone number in a rendered string ("1,339" -> 1339, "82%" -> 82)
num1 <- function(x) {
  m <- regmatches(x, regexpr("[0-9][0-9,]*(\\.[0-9]+)?", x))
  if (length(m) == 0) return(NA_real_)
  as.numeric(gsub(",", "", m))
}

app <- AppDriver$new(app_dir = ".", name = "urps-adequacy-e2e",
                     load_timeout = 40000, timeout = 20000,
                     seed = 1, height = 900, width = 1300)
on.exit(app$stop(), add = TRUE)

fails <- 0L
check <- function(desc, expr) {
  ok <- isTRUE(tryCatch(expr, error = function(e) { message("   err: ", conditionMessage(e)); FALSE }))
  cat(sprintf("  [%s] %s\n", if (ok) "PASS" else "FAIL", desc))
  if (!ok) fails <<- fails + 1L
}

# ── 1. app loads and the canonical outputs exist ────────────────────────────
v0 <- app$get_values(output = c("fp", "kpi_eff", "kpi_adeq", "p_shortfall", "p_adeq"))$output
check("app boots: fingerprint output is a non-empty string",
      is.character(v0$fp) && nzchar(v0$fp))
check("capacity-margin chart (p_shortfall) renders a plotly payload",
      !is.null(v0$p_shortfall))
check("adequacy chart (p_adeq) renders a plotly payload",
      !is.null(v0$p_adeq))
eff0  <- num1(v0$kpi_eff);  adeq0 <- num1(v0$kpi_adeq)
cat(sprintf("   baseline (uro_fte=70): eff=%s  adeq=%s  fp=%s\n",
            eff0, adeq0, substr(v0$fp, 1, 12)))

# ── 2. moving uro_fte changes the scenario (recompute happens) ──────────────
app$set_inputs(uro_fte = 40)
v_lo <- app$get_values(output = c("fp", "kpi_eff", "kpi_adeq"))$output
check("lowering uro_fte to 40 changes the scenario fingerprint",
      !identical(v_lo$fp, v0$fp))
check("lowering uro_fte to 40 changes the effective-supply KPI",
      !identical(v_lo$kpi_eff, v0$kpi_eff))
eff_lo <- num1(v_lo$kpi_eff)

app$set_inputs(uro_fte = 95)
v_hi <- app$get_values(output = c("fp", "kpi_eff", "kpi_adeq"))$output
eff_hi <- num1(v_hi$kpi_eff)
cat(sprintf("   eff(uro_fte=40)=%s  eff(uro_fte=95)=%s\n", eff_lo, eff_hi))

# ── 3. behavioral direction: more urology urogyn-time => more effective supply
check("monotonic: effective supply rises as uro_fte goes 40 -> 95",
      is.finite(eff_lo) && is.finite(eff_hi) && eff_hi >= eff_lo)
check("uro_fte=40 and uro_fte=95 are genuinely different fingerprints",
      !identical(v_lo$fp, v_hi$fp))

# ── 4. returning to default restores the baseline scenario (determinism) ────
app$set_inputs(uro_fte = 70)
v_back <- app$get_values(output = c("fp", "kpi_eff"))$output
check("resetting uro_fte to 70 restores the baseline fingerprint (deterministic)",
      identical(v_back$fp, v0$fp))

cat(sprintf("\nE2E BROWSER SUITE: %d checks, FAIL=%d\n", 9L, fails))
quit(status = if (fails > 0) 1L else 0L)
