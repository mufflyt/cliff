#!/usr/bin/env Rscript
# Geocode Failed Addresses with HERE API
# ======================================
# Takes addresses that failed Census geocoding and processes them with HERE API

library(dplyr)
library(readr)
library(httr)
library(jsonlite)

cat("🗺️ GEOCODING FAILED ADDRESSES WITH HERE API\n")
cat("===========================================\n")

#' Step 1: Identify failed addresses from Census geocoding
cat("\n📋 STEP 1: Identifying failed addresses from Census geocoding\n")

# Load original provider data
providers <- readr::read_csv("data/colorado_radiation_oncologists_real.csv",
                            show_col_types = FALSE)

# Load successful geocoding results
successful_geocodes <- readr::read_csv("data/geocoded_simple/colorado_radiation_oncology_simple.csv",
                                      show_col_types = FALSE)

# Create full address list (same logic as before)
all_addresses <- data.frame(
  id = character(),
  provider_name = character(),
  address = character(),
  stringsAsFactors = FALSE
)

for (i in 1:nrow(providers)) {
  provider <- providers[i, ]

  # Primary address
  if (!is.na(provider$address_1) && provider$address_1 != "") {
    all_addresses <- rbind(all_addresses,
                          data.frame(id = paste0("P", i),
                                    provider_name = provider$name,
                                    address = provider$address_1))
  }

  # Secondary address
  if (!is.na(provider$address_2) && provider$address_2 != "") {
    all_addresses <- rbind(all_addresses,
                          data.frame(id = paste0("S", i),
                                    provider_name = provider$name,
                                    address = provider$address_2))
  }

  # Tertiary address
  if (!is.na(provider$address_3) && provider$address_3 != "") {
    all_addresses <- rbind(all_addresses,
                          data.frame(id = paste0("T", i),
                                    provider_name = provider$name,
                                    address = provider$address_3))
  }
}

cat(sprintf("✅ Total addresses to geocode: %d\n", nrow(all_addresses)))
cat(sprintf("✅ Successfully geocoded by Census: %d\n", nrow(successful_geocodes)))

# Identify failed addresses
failed_addresses <- all_addresses %>%
  anti_join(successful_geocodes, by = c("id", "provider_name")) %>%
  mutate(
    # Clean addresses for HERE API
    address_clean = gsub("\\s+", " ", trimws(address)),
    # Ensure Colorado context
    address_for_api = ifelse(
      grepl("CO", address_clean),
      address_clean,
      paste(address_clean, "Colorado, USA")
    )
  )

cat(sprintf("❌ Failed Census geocoding: %d addresses (%.1f%%)\n",
           nrow(failed_addresses),
           nrow(failed_addresses)/nrow(all_addresses)*100))

if (nrow(failed_addresses) == 0) {
  cat("🎉 All addresses were successfully geocoded by Census!\n")
  quit(status = 0)
}

cat("\n📋 Addresses to geocode with HERE API:\n")
for (i in 1:min(5, nrow(failed_addresses))) {
  cat(sprintf("   %d. %s: %s\n", i, failed_addresses$provider_name[i], failed_addresses$address[i]))
}
if (nrow(failed_addresses) > 5) {
  cat(sprintf("   ... and %d more\n", nrow(failed_addresses) - 5))
}

#' Step 2: Geocode using HERE API
cat("\n🌍 STEP 2: Geocoding with HERE API\n")

# Check for HERE API key
here_api_key <- Sys.getenv("HERE_API_KEY")
if (here_api_key == "") {
  cat("❌ HERE_API_KEY not found in environment\n")
  cat("   Please set your HERE API key: export HERE_API_KEY='your_key'\n")
  quit(status = 1)
}

cat("🔑 HERE API key found - proceeding with geocoding\n")

#' Function to geocode a single address with HERE API
geocode_with_here <- function(address, api_key) {

  # HERE Geocoding API endpoint
  base_url <- "https://geocode.search.hereapi.com/v1/geocode"

  # Parameters for HERE API
  params <- list(
    q = address,
    apiKey = api_key,
    limit = 1,
    `in` = "countryCode:USA"  # Restrict to USA (backticks for reserved word)
  )

  tryCatch({
    response <- httr::GET(base_url, query = params)

    if (httr::status_code(response) == 200) {
      content <- httr::content(response, as = "text", encoding = "UTF-8")
      result <- jsonlite::fromJSON(content)

      if (length(result$items) > 0) {
        item <- result$items[1, ]

        return(list(
          latitude = item$position$lat,
          longitude = item$position$lng,
          matched_address = item$address$label,
          confidence = item$scoring$queryScore,
          country = item$address$countryName,
          state = item$address$stateCode,
          county = item$address$county,
          city = item$address$city,
          success = TRUE,
          error = NA
        ))
      } else {
        return(list(
          latitude = NA,
          longitude = NA,
          matched_address = NA,
          confidence = NA,
          country = NA,
          state = NA,
          county = NA,
          city = NA,
          success = FALSE,
          error = "No results found"
        ))
      }
    } else {
      return(list(
        latitude = NA,
        longitude = NA,
        matched_address = NA,
        confidence = NA,
        country = NA,
        state = NA,
        county = NA,
        city = NA,
        success = FALSE,
        error = sprintf("HTTP %d", httr::status_code(response))
      ))
    }
  }, error = function(e) {
    return(list(
      latitude = NA,
      longitude = NA,
      matched_address = NA,
      confidence = NA,
      country = NA,
      state = NA,
      county = NA,
      city = NA,
      success = FALSE,
      error = e$message
    ))
  })
}

# Geocode all failed addresses
cat(sprintf("📍 Geocoding %d failed addresses with HERE API...\n", nrow(failed_addresses)))

here_results <- data.frame()

for (i in 1:nrow(failed_addresses)) {
  addr_info <- failed_addresses[i, ]

  cat(sprintf("   %d/%d: %s\n", i, nrow(failed_addresses),
             substr(addr_info$provider_name, 1, 25)))
  cat(sprintf("          %s\n", substr(addr_info$address_for_api, 1, 60)))

  # Geocode with HERE
  geo_result <- geocode_with_here(addr_info$address_for_api, here_api_key)

  if (geo_result$success) {
    cat(sprintf("      ✅ (%.6f, %.6f) - %s\n",
               geo_result$latitude, geo_result$longitude, geo_result$city))
  } else {
    cat(sprintf("      ❌ %s\n", geo_result$error))
  }

  # Combine with original address info
  result_row <- data.frame(
    id = addr_info$id,
    provider_name = addr_info$provider_name,
    address = addr_info$address,
    latitude = geo_result$latitude,
    longitude = geo_result$longitude,
    matched_address = geo_result$matched_address,
    confidence = geo_result$confidence,
    country = geo_result$country,
    state = geo_result$state,
    county = geo_result$county,
    city = geo_result$city,
    geocoded = geo_result$success,
    geocoding_method = "HERE API",
    error_message = geo_result$error,
    stringsAsFactors = FALSE
  )

  here_results <- rbind(here_results, result_row)

  # Rate limiting - be nice to HERE API
  Sys.sleep(0.1)
}

#' Step 3: Combine Census and HERE results
cat("\n🔄 STEP 3: Combining Census and HERE geocoding results\n")

# Prepare Census results in same format
census_results <- successful_geocodes %>%
  mutate(
    matched_address = address,  # Census didn't return matched address
    confidence = 1.0,  # Assume high confidence for Census
    country = "USA",
    state = "CO",
    county = NA,  # Will need to derive from coordinates
    city = NA,    # Will need to derive from coordinates
    geocoded = TRUE,
    geocoding_method = "US Census Bureau",
    error_message = NA,
    # Standardize location type
    location_type = case_when(
      substr(id, 1, 1) == "P" ~ "Primary",
      substr(id, 1, 1) == "S" ~ "Secondary",
      TRUE ~ "Tertiary"
    )
  ) %>%
  select(id, provider_name, address, latitude, longitude, matched_address,
         confidence, country, state, county, city, geocoded, geocoding_method, error_message)

# Filter HERE results to successful ones
here_successful <- here_results %>%
  filter(geocoded == TRUE) %>%
  select(id, provider_name, address, latitude, longitude, matched_address,
         confidence, country, state, county, city, geocoded, geocoding_method, error_message)

# Combine all successful geocodes
all_geocoded <- rbind(census_results, here_successful) %>%
  mutate(
    specialty = "Radiation Oncology",
    data_source = "Colorado Provider Directory 2024",
    geocoded_date = Sys.Date(),
    # Add location type
    location_type = case_when(
      substr(id, 1, 1) == "P" ~ "Primary",
      substr(id, 1, 1) == "S" ~ "Secondary",
      TRUE ~ "Tertiary"
    )
  )

# Calculate final success rate
final_success_rate <- nrow(all_geocoded) / nrow(all_addresses)

cat(sprintf("✅ FINAL GEOCODING RESULTS:\n"))
cat(sprintf("   • US Census Bureau: %d successful\n", nrow(census_results)))
cat(sprintf("   • HERE API: %d successful\n", nrow(here_successful)))
cat(sprintf("   • TOTAL GEOCODED: %d/%d (%.1f%%)\n",
           nrow(all_geocoded), nrow(all_addresses), final_success_rate * 100))

# Show remaining failures
still_failed <- nrow(all_addresses) - nrow(all_geocoded)
if (still_failed > 0) {
  cat(sprintf("   • Still failed: %d addresses\n", still_failed))

  failed_final <- here_results %>%
    filter(geocoded == FALSE) %>%
    select(id, provider_name, address, error_message)

  cat("\n❌ Addresses that still failed:\n")
  for (i in 1:nrow(failed_final)) {
    cat(sprintf("   %d. %s: %s (%s)\n", i,
               failed_final$provider_name[i],
               substr(failed_final$address[i], 1, 50),
               failed_final$error_message[i]))
  }
}

#' Step 4: Save complete geocoded dataset
cat("\n💾 STEP 4: Saving complete geocoded dataset\n")

output_dir <- "data/geocoded_complete"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Save complete geocoded data
readr::write_csv(all_geocoded, file.path(output_dir, "colorado_radiation_oncology_complete.csv"))

# Save geocoding summary
geocoding_summary <- list(
  total_addresses = nrow(all_addresses),
  census_successful = nrow(census_results),
  here_successful = nrow(here_successful),
  total_successful = nrow(all_geocoded),
  final_success_rate = final_success_rate,
  still_failed = still_failed,
  geocoding_methods = c("US Census Bureau", "HERE API"),
  files_created = "colorado_radiation_oncology_complete.csv"
)

jsonlite::write_json(geocoding_summary,
                    file.path(output_dir, "complete_geocoding_summary.json"),
                    pretty = TRUE)

cat(sprintf("✅ Complete geocoded dataset saved to: %s\n", output_dir))

# Show final statistics
cat("\n🎯 GEOCODING MISSION COMPLETE!\n")
cat("=============================\n")
cat(sprintf("FINAL SUCCESS RATE: %.1f%%\n", final_success_rate * 100))
cat(sprintf("   📍 %d total provider locations geocoded\n", nrow(all_geocoded)))
cat(sprintf("   🏥 %d unique radiation oncologists\n", length(unique(all_geocoded$provider_name))))
cat(sprintf("   🌍 Used 2 geocoding APIs for maximum coverage\n"))

if (final_success_rate >= 0.95) {
  cat("🎉 EXCELLENT! Achieved >95% geocoding success rate\n")
} else if (final_success_rate >= 0.80) {
  cat("✅ GOOD! Achieved >80% geocoding success rate\n")
} else {
  cat("⚠️  Additional geocoding methods may be needed\n")
}

cat("\n🚀 Ready for 100% complete isochrone analysis!\n")

return(all_geocoded)
