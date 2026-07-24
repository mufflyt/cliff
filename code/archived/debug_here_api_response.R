#!/usr/bin/env Rscript
# Debug HERE API Response
# =======================
# Examine what the HERE API is actually returning

library(httr)
library(jsonlite)

cat("🔍 DEBUGGING HERE API ISOLINE RESPONSE\n")
cat("=====================================\n")

# Test with a single location
test_lat <- 39.7392  # Denver
test_lng <- -104.9903
test_time <- 30  # 30 minutes

here_api_key <- Sys.getenv("HERE_API_KEY")
if (here_api_key == "") {
  cat("❌ HERE_API_KEY not found\n")
  quit(status = 1)
}

cat("🔑 HERE API key found\n")
cat(sprintf("📍 Testing with Denver coordinates: %.4f, %.4f\n", test_lat, test_lng))

# Test the exact API call we're making
here_url <- "https://isoline.router.hereapi.com/v8/isolines"

params <- list(
  transportMode = "car",
  origin = paste0(test_lat, ",", test_lng),
  `range[type]` = "time",
  `range[values]` = test_time * 60,  # Convert to seconds
  apikey = here_api_key,
  routingMode = "fast"
)

cat("\n🌍 Making HERE API request...\n")
cat("URL:", here_url, "\n")
cat("Parameters:\n")
for (name in names(params)) {
  cat(sprintf("   %s: %s\n", name, params[[name]]))
}

response <- httr::GET(here_url, query = params)

cat(sprintf("\n📡 Response status: %d\n", httr::status_code(response)))

if (httr::status_code(response) == 200) {
  content_text <- httr::content(response, as = "text", encoding = "UTF-8")

  cat("\n📄 Raw response (first 500 chars):\n")
  cat(substr(content_text, 1, 500), "\n")

  tryCatch({
    iso_data <- jsonlite::fromJSON(content_text)

    cat("\n🔍 Parsed JSON structure:\n")
    cat("Names at root level:", names(iso_data), "\n")

    if ("isolines" %in% names(iso_data)) {
      cat("Number of isolines:", length(iso_data$isolines), "\n")

      if (length(iso_data$isolines) > 0) {
        cat("Examining all isolines:\n")
        for (i in 1:length(iso_data$isolines)) {
          isoline <- iso_data$isolines[[i]]
          cat(sprintf("Isoline %d structure:", i), names(isoline), "\n")

          # Print the full structure for debugging
          cat(sprintf("Isoline %d details:\n", i))
          print(str(isoline, max.level = 3))

          if ("polygons" %in% names(isoline)) {
            cat("Number of polygons:", length(isoline$polygons), "\n")

            if (length(isoline$polygons) > 0) {
              polygon <- isoline$polygons[[1]]
              cat("Polygon structure:", names(polygon), "\n")

              if ("outer" %in% names(polygon)) {
                outer_data <- polygon$outer
                cat("Outer data type:", class(outer_data), "\n")
                cat("Outer data length/size:", length(outer_data), "\n")

                if (is.character(outer_data)) {
                  cat("Outer data (first 100 chars):", substr(outer_data, 1, 100), "\n")
                } else if (is.list(outer_data) || is.matrix(outer_data)) {
                  cat("Outer data structure:", str(outer_data, max.level = 2), "\n")
                }
              }
            }
          }
        }
      }
    }

    if ("notices" %in% names(iso_data)) {
      cat("\nAPI Notices:\n")
      print(iso_data$notices)
    }

    if ("error" %in% names(iso_data)) {
      cat("\nAPI Error:\n")
      print(iso_data$error)
    }

  }, error = function(e) {
    cat("❌ Failed to parse JSON:", e$message, "\n")
  })

} else {
  cat("❌ API request failed\n")
  cat("Response headers:\n")
  print(httr::headers(response))

  error_content <- httr::content(response, as = "text")
  cat("\nError content:\n")
  cat(error_content, "\n")
}

# Also test a different API endpoint format
cat("\n\n🔄 Testing alternative API format...\n")

# Try different parameter format
alt_params <- list(
  transportMode = "car",
  origin = paste0(test_lat, ",", test_lng),
  range = paste0("time:", test_time * 60),
  apikey = here_api_key
)

alt_response <- httr::GET(here_url, query = alt_params)
cat(sprintf("Alternative format status: %d\n", httr::status_code(alt_response)))

if (httr::status_code(alt_response) == 200) {
  alt_content <- httr::content(alt_response, as = "text", encoding = "UTF-8")
  cat("Alternative response (first 200 chars):\n")
  cat(substr(alt_content, 1, 200), "\n")
}

cat("\n🔍 DEBUGGING COMPLETE\n")
cat("Check the response structure above to identify the issue\n")
