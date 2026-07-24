#!/usr/bin/env Rscript
# Proper Geocoding of Colorado Radiation Oncologists using Census Bureau API
# ==========================================================================
# Uses the existing enhanced Census geocoding infrastructure

library(dplyr)
library(readr)
library(sf)

# Source the proper Census geocoding functions
source("../../R/census_geocode_enhanced.R")

cat("🗺️ PROPER GEOCODING: COLORADO RADIATION ONCOLOGISTS\n")
cat("==================================================\n")
cat("Using US Census Bureau geocoding API with enhanced processing\n")

#' Step 1: Load and prepare provider data
cat("\n📋 STEP 1: Loading and expanding provider locations\n")

providers <- readr::read_csv("data/colorado_radiation_oncologists_real.csv",
                            show_col_types = FALSE)

cat(sprintf("✅ Loaded %d radiation oncologists\n", nrow(providers)))

# Expand to all practice locations
expand_provider_locations <- function(data) {
  expanded <- data.frame()

  for (i in 1:nrow(data)) {
    provider <- data[i, ]

    # Process all address fields
    addresses <- c(provider$address_1, provider$address_2, provider$address_3)
    types <- c("Primary", "Secondary", "Tertiary")

    for (j in 1:length(addresses)) {
      if (!is.na(addresses[j]) && addresses[j] != "") {
        location <- data.frame(
          provider_name = provider$name,
          hospital_affiliation = provider$hospital_affiliation,
          raw_address = addresses[j],
          location_type = types[j],
          location_id = sprintf("radOnc_%04d_%s", i, substr(types[j], 1, 1)),
          stringsAsFactors = FALSE
        )
        expanded <- rbind(expanded, location)
      }
    }
  }

  return(expanded)
}

all_locations <- expand_provider_locations(providers)
cat(sprintf("✅ Expanded to %d practice locations\n", nrow(all_locations)))

#' Step 2: Parse addresses using proper address parsing
cat("\n📍 STEP 2: Parsing addresses for Census Bureau geocoding\n")

parse_colorado_addresses <- function(data) {

  data$address <- NA_character_
  data$city <- NA_character_
  data$state <- NA_character_
  data$zip <- NA_character_

  for (i in 1:nrow(data)) {
    raw_addr <- data$raw_address[i]

    if (!is.na(raw_addr)) {
      # Clean and standardize
      addr_clean <- trimws(gsub("\\s+", " ", raw_addr))

      # Extract ZIP code (5 or 9 digit)
      zip_pattern <- "\\b(\\d{5}(-\\d{4})?)\\b"
      zip_match <- regmatches(addr_clean, regexpr(zip_pattern, addr_clean))
      if (length(zip_match) > 0) {
        data$zip[i] <- zip_match
        addr_clean <- gsub(zip_pattern, "", addr_clean)
      }

      # Extract state (should be CO)
      state_pattern <- "\\b(CO|Colorado)\\b"
      if (grepl(state_pattern, addr_clean, ignore.case = TRUE)) {
        data$state[i] <- "CO"
        addr_clean <- gsub(state_pattern, "", addr_clean, ignore.case = TRUE)
      }

      # Split by commas to separate street address and city
      parts <- strsplit(trimws(addr_clean), ",")[[1]]
      parts <- trimws(parts[parts != ""])

      if (length(parts) >= 2) {
        # Last part is likely the city
        data$city[i] <- parts[length(parts)]
        # Everything else is the street address
        data$address[i] <- paste(parts[-length(parts)], collapse = ", ")
      } else if (length(parts) == 1) {
        # Try to extract city from common Colorado patterns
        colorado_cities <- c("DENVER", "COLORADO SPRINGS", "AURORA", "FORT COLLINS",
                           "LAKEWOOD", "THORNTON", "PUEBLO", "BOULDER", "GRAND JUNCTION",
                           "GREELEY", "LONGMONT", "LOVELAND", "DURANGO", "GLENWOOD SPRINGS",
                           "EDWARDS", "GOLDEN", "LONE TREE", "HIGHLANDS RANCH", "LAFAYETTE")

        addr_upper <- toupper(parts[1])
        for (city_name in colorado_cities) {
          if (grepl(city_name, addr_upper)) {
            data$city[i] <- str_to_title(city_name)
            data$address[i] <- gsub(city_name, "", addr_upper, ignore.case = TRUE)
            data$address[i] <- trimws(gsub(",", "", data$address[i]))
            break
          }
        }

        # If no city found, treat entire string as address
        if (is.na(data$city[i])) {
          data$address[i] <- parts[1]
        }
      }
    }
  }

  return(data)
}

parsed_locations <- parse_colorado_addresses(all_locations)

cat("✅ Address parsing complete\n")
cat("\n📋 Sample parsed addresses:\n")
sample_rows <- head(parsed_locations, 5)
for (i in 1:nrow(sample_rows)) {
  cat(sprintf("   %d. %s (%s)\n", i, sample_rows$provider_name[i], sample_rows$location_type[i]))
  cat(sprintf("      • Raw: %s\n", sample_rows$raw_address[i]))
  cat(sprintf("      • Parsed: %s, %s, %s %s\n",
             sample_rows$address[i], sample_rows$city[i],
             sample_rows$state[i], sample_rows$zip[i]))
}

#' Step 3: Geocode using enhanced Census Bureau API
cat("\n🗺️ STEP 3: Geocoding with US Census Bureau API\n")

geocode_locations <- function(data) {

  # Initialize results list to avoid rbind issues
  results_list <- list()
  total <- nrow(data)
  success_count <- 0

  cat(sprintf("📍 Geocoding %d locations...\n", total))

  for (i in 1:nrow(data)) {
    location <- data[i, ]

    cat(sprintf("   Processing %d/%d: %s\n", i, total, location$provider_name))

    # Use the enhanced Census geocoding function
    tryCatch({
      geo_result <- census_geocode_enhanced(
        addr = location$address,
        city = location$city,
        state = location$state,
        zip = location$zip
      )

      if (!is.na(geo_result$lat) && !is.na(geo_result$lon)) {
        success_count <- success_count + 1
        cat(sprintf("      ✅ Success: (%.6f, %.6f)\n", geo_result$lat, geo_result$lon))

        # Create combined result
        result_row <- data.frame(
          location_id = location$location_id,
          provider_name = location$provider_name,
          hospital_affiliation = location$hospital_affiliation,
          raw_address = location$raw_address,
          location_type = location$location_type,
          address = location$address,
          city = location$city,
          state = location$state,
          zip = location$zip,
          latitude = geo_result$lat,
          longitude = geo_result$lon,
          matched_address = geo_result$matched_address,
          match_indicator = geo_result$match_indicator,
          match_type = geo_result$match_type,
          census_tract = geo_result$census_tract,
          county_fips = geo_result$county_fips,
          county_name = geo_result$county_name,
          state_fips = geo_result$state_fips,
          state_name = geo_result$state_name,
          geocoding_status = "Success",
          stringsAsFactors = FALSE
        )
      } else {
        cat(sprintf("      ❌ Failed to geocode\n"))
        result_row <- data.frame(
          location_id = location$location_id,
          provider_name = location$provider_name,
          hospital_affiliation = location$hospital_affiliation,
          raw_address = location$raw_address,
          location_type = location$location_type,
          address = location$address,
          city = location$city,
          state = location$state,
          zip = location$zip,
          latitude = NA_real_,
          longitude = NA_real_,
          matched_address = NA_character_,
          match_indicator = NA_character_,
          match_type = NA_character_,
          census_tract = NA_character_,
          county_fips = NA_character_,
          county_name = NA_character_,
          state_fips = NA_character_,
          state_name = NA_character_,
          geocoding_status = "Failed",
          stringsAsFactors = FALSE
        )
      }

    }, error = function(e) {
      cat(sprintf("      ❌ Error: %s\n", e$message))
      result_row <- data.frame(
        location_id = location$location_id,
        provider_name = location$provider_name,
        hospital_affiliation = location$hospital_affiliation,
        raw_address = location$raw_address,
        location_type = location$location_type,
        address = location$address,
        city = location$city,
        state = location$state,
        zip = location$zip,
        latitude = NA_real_,
        longitude = NA_real_,
        matched_address = NA_character_,
        match_indicator = NA_character_,
        match_type = NA_character_,
        census_tract = NA_character_,
        county_fips = NA_character_,
        county_name = NA_character_,
        state_fips = NA_character_,
        state_name = NA_character_,
        geocoding_status = "Error",
        stringsAsFactors = FALSE
      )
    })

    results_list[[i]] <- result_row

    # Rate limiting - be nice to the Census API
    Sys.sleep(0.2)
  }

  # Combine all results
  results <- do.call(rbind, results_list)

  cat(sprintf("\n✅ Geocoding complete: %d/%d (%.1f%%) successful\n",
             success_count, total, success_count/total*100))

  return(results)
}

# Perform geocoding
geocoded_results <- geocode_locations(parsed_locations)

#' Step 4: Create final spatial dataset
cat("\n📊 STEP 4: Creating spatial dataset for isochrone analysis\n")

# Filter to successfully geocoded locations
final_locations <- geocoded_results %>%
  filter(!is.na(lat), !is.na(lon)) %>%
  mutate(
    latitude = lat,
    longitude = lon,
    specialty = "Radiation Oncology",
    data_source = "Colorado Provider Directory 2024",
    geocoded_date = Sys.Date(),
    geocoding_method = "US Census Bureau API"
  ) %>%
  select(
    location_id, provider_name, hospital_affiliation, location_type,
    address, city, state, zip, latitude, longitude,
    matched_address, match_indicator, match_type,
    census_tract, county_fips, county_name, state_fips, state_name,
    specialty, data_source, geocoded_date, geocoding_method
  )

cat(sprintf("✅ Final dataset: %d geocoded locations ready for analysis\n", nrow(final_locations)))

# Summary by county
county_summary <- final_locations %>%
  group_by(county_name) %>%
  summarise(
    locations = n(),
    providers = n_distinct(provider_name),
    .groups = "drop"
  ) %>%
  arrange(desc(locations))

cat("\n📊 Locations by county:\n")
for (i in 1:nrow(county_summary)) {
  cat(sprintf("   • %s: %d locations (%d providers)\n",
             county_summary$county_name[i],
             county_summary$locations[i],
             county_summary$providers[i]))
}

#' Step 5: Save geocoded results
cat("\n💾 STEP 5: Saving geocoded data for isochrone pipeline\n")

output_dir <- "data/geocoded_proper"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Save CSV
readr::write_csv(final_locations, file.path(output_dir, "colorado_radiation_oncology_geocoded.csv"))

# Create spatial data (sf object)
locations_sf <- st_as_sf(final_locations,
                        coords = c("longitude", "latitude"),
                        crs = 4326) %>%
  # Add back coordinate columns for isochrone processing
  mutate(
    longitude = st_coordinates(.)[,1],
    latitude = st_coordinates(.)[,2]
  )

# Save as GeoJSON
sf::st_write(locations_sf,
            file.path(output_dir, "colorado_radiation_oncology_locations.geojson"),
            delete_dsn = TRUE, quiet = TRUE)

# Save as Shapefile for broader compatibility
sf::st_write(locations_sf,
            file.path(output_dir, "colorado_radiation_oncology_locations.shp"),
            delete_dsn = TRUE, quiet = TRUE)

cat(sprintf("✅ Geocoded data saved to: %s\n", output_dir))
cat("   Files created:\n")
cat("   • colorado_radiation_oncology_geocoded.csv\n")
cat("   • colorado_radiation_oncology_locations.geojson\n")
cat("   • colorado_radiation_oncology_locations.shp\n")

#' Step 6: Generate analysis summary
summary_stats <- list(
  geocoding_summary = list(
    total_input_locations = nrow(parsed_locations),
    successfully_geocoded = nrow(final_locations),
    success_rate = nrow(final_locations) / nrow(parsed_locations),
    geocoding_method = "US Census Bureau Enhanced API",
    geocoding_date = as.character(Sys.Date())
  ),
  provider_summary = list(
    total_providers = length(unique(final_locations$provider_name)),
    total_locations = nrow(final_locations),
    counties_covered = length(unique(final_locations$county_name)),
    primary_locations = sum(final_locations$location_type == "Primary"),
    secondary_locations = sum(final_locations$location_type == "Secondary"),
    tertiary_locations = sum(final_locations$location_type == "Tertiary")
  ),
  spatial_extent = list(
    min_latitude = min(final_locations$latitude),
    max_latitude = max(final_locations$latitude),
    min_longitude = min(final_locations$longitude),
    max_longitude = max(final_locations$longitude)
  ),
  next_steps = list(
    ready_for_isochrones = TRUE,
    recommended_isochrone_times = c(30, 60, 120, 180),
    analysis_unit = "County level analysis recommended"
  )
)

jsonlite::write_json(summary_stats,
                    file.path(output_dir, "geocoding_analysis_summary.json"),
                    pretty = TRUE)

cat("\n✅ PROPER GEOCODING COMPLETE!\n")
cat("=============================\n")
cat(sprintf("   📍 %d locations successfully geocoded\n", nrow(final_locations)))
cat(sprintf("   🏥 %d unique radiation oncologists\n", length(unique(final_locations$provider_name))))
cat(sprintf("   🗺️ %d Colorado counties covered\n", length(unique(final_locations$county_name))))
cat(sprintf("   ✅ %.1f%% geocoding success rate\n", summary_stats$geocoding_summary$success_rate * 100))
cat("   🚀 Ready for isochrone generation!\n")

cat("\n🎯 Next Steps:\n")
cat("   1. Generate isochrones for all locations\n")
cat("   2. Calculate travel time accessibility\n")
cat("   3. Compare with female ACS demographic data\n")
cat("   4. Identify underserved areas\n")

return(final_locations)
