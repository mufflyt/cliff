#!/usr/bin/env Rscript
################################################################################
# Deploy the Urogynecology Effective-Adequacy Explorer to shinyapps.io
################################################################################
# Mirrors shiny_urps_scenarios/DEPLOY.R. Bundles only the files the app needs
# (app.R, model.R, and the three data inputs); the shinytest2 test suite is
# excluded here AND via .rscignore, so the build stays light (no chromote /
# websocket / shinytest2 compiled from source).
#
# Prerequisites: a configured shinyapps.io account (rsconnect::accounts() non-empty).
#
# Usage:
#   Rscript DEPLOY.R
#   SHINYAPPS_ACCOUNT=mufflyt Rscript DEPLOY.R
#   SHINYAPPS_APPNAME=urps-adequacy-explorer Rscript DEPLOY.R
################################################################################

suppressPackageStartupMessages(library(rsconnect))

# Force the libcurl HTTP backend (avoids the Homebrew OpenSSL 3 duplicate-CA TLS
# failure the auto-pick can hit on macOS).
options(rsconnect.http = Sys.getenv("RSCONNECT_HTTP", "libcurl"))

app_name  <- Sys.getenv("SHINYAPPS_APPNAME", "urps-adequacy-explorer")
app_title <- "Urogynecology Effective-Adequacy Explorer"
account   <- Sys.getenv("SHINYAPPS_ACCOUNT", "")   # blank -> first configured account

cat("================================================================================\n")
cat("SHINYAPPS.IO DEPLOYMENT: ", app_title, "\n", sep = "")
cat("================================================================================\n\n")

# ---- Step 1: account -------------------------------------------------------
cat("[STEP 1/4] Checking rsconnect configuration...\n")
accounts <- rsconnect::accounts()
if (is.null(accounts) || nrow(accounts) == 0)
  stop("No shinyapps.io account configured. Configure one (rsconnect::setAccountInfo) and re-run.")
if (nzchar(account)) {
  if (!account %in% accounts$name)
    stop(sprintf("Account '%s' is not configured. Available: %s", account, paste(accounts$name, collapse = ", ")))
  acct_row <- accounts[accounts$name == account, ][1, ]
} else {
  acct_row <- accounts[1, ]
}
cat(sprintf("  Using account: %s@%s\n", acct_row$name, acct_row$server))
if (nrow(accounts) > 1) cat(sprintf("  (Other accounts: %s. Set SHINYAPPS_ACCOUNT to choose.)\n",
                                    paste(setdiff(accounts$name, acct_row$name), collapse = ", ")))

# ---- Step 2: files ---------------------------------------------------------
cat("\n[STEP 2/4] Assembling the deployment bundle...\n")
app_files <- c(
  "app.R",
  "model.R",
  "data/urps_model_data.R",
  "data/urps_module_a_age_productivity_2026-07-23.csv",
  "data/urps_supply_demand_national_2026-07-23.csv"
)
missing <- app_files[!file.exists(app_files)]
if (length(missing) > 0) stop(sprintf("Missing required files: %s", paste(missing, collapse = ", ")))
for (f in app_files) cat(sprintf("     - %s (%.1f KB)\n", f, file.size(f) / 1024))

# ---- Step 3: pre-flight validation ----------------------------------------
# Confirm the model builds from the bundled data before shipping a broken app.
cat("\n[STEP 3/4] Pre-flight: confirming model.R loads and computes...\n")
ok <- system2("Rscript", args = c("-e",
  shQuote("tryCatch({source('model.R'); cat('MODEL_OK')}, error=function(e){cat('MODEL_FAIL:', conditionMessage(e))})")),
  stdout = TRUE, stderr = TRUE)
if (!any(grepl("MODEL_OK", ok))) {
  cat(paste(ok, collapse = "\n"), "\n"); stop("model.R did not load cleanly; refusing to deploy.")
}
cat("  Model loaded.\n")

# ---- Step 4: deploy --------------------------------------------------------
cat(sprintf("\n[STEP 4/4] Deploying '%s' to %s (2-5 minutes)...\n\n", app_name, acct_row$server))
ok2 <- tryCatch({
  rsconnect::deployApp(
    appDir = ".", appFiles = app_files, appName = app_name, appTitle = app_title,
    account = acct_row$name, server = acct_row$server,
    forceUpdate = TRUE, launch.browser = FALSE, logLevel = "normal")
  TRUE
}, error = function(e) { cat(sprintf("\nDeployment failed: %s\n", e$message)); FALSE })

if (ok2) {
  cat("\n================================================================================\n")
  cat("DEPLOYMENT SUCCESSFUL\n")
  cat(sprintf("Live at: https://%s.shinyapps.io/%s\n", acct_row$name, app_name))
  cat("To redeploy after changes: Rscript DEPLOY.R\n")
} else {
  cat("\nDeployment failed. Check account quota, network, and credentials, then re-run.\n")
  quit(status = 1)
}
