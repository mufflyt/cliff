#!/usr/bin/env Rscript
################################################################################
# Deploy the Urogynecology Workforce Replacement Explorer to shinyapps.io
################################################################################
# Mirrors app/DEPLOY.R. Bundles only the files the app needs (app.R, the model
# data, the bundled canonical CSVs, and the manuscript in www/); tests and the
# local render helper are excluded.
#
# Prerequisites:
#   A configured shinyapps.io account (rsconnect::accounts() non-empty).
#   Configure once with: Rscript ../../app/setup_shinyapps.R  (or setAccountInfo()).
#
# Usage:
#   Rscript DEPLOY.R                       # deploys with the defaults below
#   SHINYAPPS_ACCOUNT=mufflyt Rscript DEPLOY.R
#   SHINYAPPS_APPNAME=urps-workforce-explorer Rscript DEPLOY.R
################################################################################

suppressPackageStartupMessages(library(rsconnect))

# Force the libcurl (R `curl` package) HTTP backend. The default auto-pick can land on
# RCurl or the system curl binary, which on this Mac link a Homebrew OpenSSL 3 whose CA
# directory has duplicate certs, yielding "x509 ... cert already in hash table" at TLS
# connect. The curl package (LibreSSL) connects to api.shinyapps.io cleanly.
options(rsconnect.http = Sys.getenv("RSCONNECT_HTTP", "libcurl"))

app_name  <- Sys.getenv("SHINYAPPS_APPNAME", "urps-workforce-explorer")
app_title <- "Urogynecology Workforce Replacement Explorer"
account   <- Sys.getenv("SHINYAPPS_ACCOUNT", "")   # blank -> first configured account

cat("================================================================================\n")
cat("SHINYAPPS.IO DEPLOYMENT: ", app_title, "\n", sep = "")
cat("================================================================================\n\n")

# ---- Step 1: account -------------------------------------------------------
cat("[STEP 1/4] Checking rsconnect configuration...\n")
accounts <- rsconnect::accounts()
if (is.null(accounts) || nrow(accounts) == 0) {
  cat("  No shinyapps.io account configured.\n")
  cat("  Configure with: Rscript ", file.path("..", "..", "app", "setup_shinyapps.R"), "\n", sep = "")
  stop("Configuration required. Configure an account and re-run.")
}
if (nzchar(account)) {
  if (!account %in% accounts$name) stop(sprintf("Account '%s' is not configured. Available: %s", account, paste(accounts$name, collapse = ", ")))
  acct_row <- accounts[accounts$name == account, ][1, ]
} else {
  acct_row <- accounts[1, ]
}
cat(sprintf("  Using account: %s@%s\n", acct_row$name, acct_row$server))
if (nrow(accounts) > 1) cat(sprintf("  (Other configured accounts: %s. Set SHINYAPPS_ACCOUNT to choose.)\n",
                                    paste(setdiff(accounts$name, acct_row$name), collapse = ", ")))

# ---- Step 2: files ---------------------------------------------------------
cat("\n[STEP 2/4] Assembling the deployment bundle...\n")
app_files <- c(
  "app.R",
  "urps_model_data.R",
  "data/graduation_active_transition.csv",
  "www/manuscript_WORKFORCE_CLIFF.html",
  "www/manuscript_WORKFORCE_CLIFF.docx"
)
missing <- app_files[!file.exists(app_files)]
if (length(missing) > 0) stop(sprintf("Missing required files: %s", paste(missing, collapse = ", ")))
for (f in app_files) cat(sprintf("     - %s (%.1f KB)\n", f, file.size(f) / 1024))

# ---- Step 3: pre-flight validation ----------------------------------------
# The app refuses to launch if its frozen-primary invariants fail; catch that here
# rather than shipping a broken bundle. Source app.R in a child so shinyApp() does
# not block, and inspect the VALIDATION object it builds at load.
cat("\n[STEP 3/4] Pre-flight: confirming the model-validation gate passes...\n")
ok <- system2("Rscript", args = c("-e",
  shQuote("e<-new.env(); local({shinyApp<-function(...) invisible(NULL); source('app.R', local=environment())}, envir=e); if(isTRUE(e$VALIDATION$ok)) cat('VALIDATION_OK') else {cat('VALIDATION_FAIL:'); cat(paste(e$VALIDATION$failures, collapse='; '))}")),
  stdout = TRUE, stderr = TRUE)
if (!any(grepl("VALIDATION_OK", ok))) {
  cat(paste(ok, collapse = "\n"), "\n")
  stop("Model-validation gate did not pass; refusing to deploy.")
}
cat("  Model-validation gate passed.\n")

# ---- Step 4: deploy --------------------------------------------------------
cat(sprintf("\n[STEP 4/4] Deploying '%s' to %s (2-5 minutes)...\n\n", app_name, acct_row$server))
ok2 <- tryCatch({
  rsconnect::deployApp(
    appDir      = ".",
    appFiles    = app_files,
    appName     = app_name,
    appTitle    = app_title,
    account     = acct_row$name,
    server      = acct_row$server,
    forceUpdate = TRUE,
    launch.browser = FALSE,
    logLevel    = "normal"
  )
  TRUE
}, error = function(e) { cat(sprintf("\nDeployment failed: %s\n", e$message)); FALSE })

if (ok2) {
  app_url <- sprintf("https://%s.shinyapps.io/%s", acct_row$name, app_name)
  cat("\n================================================================================\n")
  cat("DEPLOYMENT SUCCESSFUL\n")
  cat("================================================================================\n\n")
  cat(sprintf("Live at: %s\n\n", app_url))
  cat("The bundled manuscript is reachable from the app header (Read the full manuscript / Download).\n")
  cat("To redeploy after changes: Rscript DEPLOY.R\n")
} else {
  cat("\nDeployment failed. Check the account quota (free tier limits apps),\n")
  cat("network, and credentials, then re-run: Rscript DEPLOY.R\n")
  quit(status = 1)
}
