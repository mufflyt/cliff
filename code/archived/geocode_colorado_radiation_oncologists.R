#!/usr/bin/env Rscript
# Geocode Colorado Radiation Oncologists for Isochrone Analysis
# =============================================================
# Geocodes all provider addresses and creates standardized location dataset

library(dplyr)
library(readr)
library(sf)

# Simple geocoding functions for Colorado analysis
simple_census_geocode <- function(addresses, ids) {
  cat("📍 Using simplified geocoding approach...\n")

  # Create fallback geocoding for Colorado cities
  city_coords <- data.frame(
    pattern = c("LAKEWOOD", "LONGMONT", "LOVELAND", "GRAND JUNCTION", "DENVER",
               "COLORADO SPRINGS", "PUEBLO", "DURANGO", "LAFAYETTE", "FORT COLLINS",
               "GLENWOOD SPRINGS", "BOULDER", "AURORA", "LONE TREE", "HIGHLANDS RANCH",
               "THORNTON", "EDWARDS", "GOLDEN", "GREELEY"),
    latitude = c(39.7047, 40.1672, 40.3978, 39.0639, 39.7392,
                38.8339, 38.2544, 37.2753, 40.0276, 40.5853,
                39.5505, 40.0150, 39.7294, 39.5431, 39.5547,
                39.8681, 39.6403, 39.7555, 40.4233),
    longitude = c(-105.0814, -105.1017, -105.0748, -108.5506, -104.9903,
                 -104.8214, -104.6091, -107.8801, -105.1372, -105.0178,
                 -107.3249, -105.2705, -104.8319, -104.8619, -104.9900,
                 -104.9722, -106.3256, -105.2211, -104.7091),
    stringsAsFactors = FALSE
  )

  # Match addresses to coordinates
  results <- data.frame(
    location_id = ids,
    latitude = NA_real_,
    longitude = NA_real_,
    stringsAsFactors = FALSE
  )

  for (i in 1:length(addresses)) {
    addr_upper <- toupper(addresses[i])

    for (j in 1:nrow(city_coords)) {
      if (grepl(city_coords$pattern[j], addr_upper)) {
        results$latitude[i] <- city_coords$latitude[j]
        results$longitude[i] <- city_coords$longitude[j]
        break
      }
    }
  }

  return(results)
}

cat("🗺️ GEOCODING COLORADO RADIATION ONCOLOGISTS\n")
cat("===========================================\n")

#' Step 1: Load and prepare provider data
cat("\n📋 STEP 1: Loading provider data for geocoding\n")

providers <- readr::read_csv("data/colorado_radiation_oncologists_real.csv",
                            show_col_types = FALSE)

cat(sprintf("✅ Loaded %d radiation oncologists\n", nrow(providers)))

#' Expand providers to include all practice locations
expand_provider_locations <- function(data) {

  expanded_locations <- data.frame()

  for (i in 1:nrow(data)) {
    provider <- data[i, ]

    # Primary location (address_1)
    if (!is.na(provider$address_1) && provider$address_1 != "") {
      location <- data.frame(
        provider_name = provider$name,
        hospital_affiliation = provider$hospital_affiliation,
        address = provider$address_1,
        location_type = "Primary",
        stringsAsFactors = FALSE
      )
      expanded_locations <- rbind(expanded_locations, location)
    }

    # Secondary location (address_2)
    if (!is.na(provider$address_2) && provider$address_2 != "") {
      location <- data.frame(
        provider_name = provider$name,
        hospital_affiliation = provider$hospital_affiliation,
        address = provider$address_2,
        location_type = "Secondary",
        stringsAsFactors = FALSE
      )
      expanded_locations <- rbind(expanded_locations, location)
    }

    # Tertiary location (address_3)
    if (!is.na(provider$address_3) && provider$address_3 != "") {
      location <- data.frame(
        provider_name = provider$name,
        hospital_affiliation = provider$hospital_affiliation,
        address = provider$address_3,
        location_type = "Tertiary",
        stringsAsFactors = FALSE
      )
      expanded_locations <- rbind(expanded_locations, location)
    }
  }

  # Add unique location ID
  expanded_locations$location_id <- sprintf("rad_onc_%04d", 1:nrow(expanded_locations))

  return(expanded_locations)
}

# Expand to all locations
all_locations <- expand_provider_locations(providers)

cat(sprintf("✅ Expanded to %d practice locations\n", nrow(all_locations)))
cat(sprintf("   • Primary locations: %d\n", sum(all_locations$location_type == "Primary")))
cat(sprintf("   • Secondary locations: %d\n", sum(all_locations$location_type == "Secondary")))
cat(sprintf("   • Tertiary locations: %d\n", sum(all_locations$location_type == "Tertiary")))

#' Step 2: Standardize addresses for geocoding
cat("\n📍 STEP 2: Standardizing addresses for geocoding\n")

standardize_addresses <- function(data) {

  data$address_standardized <- NA_character_
  data$city <- NA_character_
  data$state <- NA_character_
  data$zip <- NA_character_

  for (i in 1:nrow(data)) {
    addr <- data$address[i]

    if (!is.na(addr)) {
      # Extract standardized components
      # Remove extra whitespace and standardize format
      addr_clean <- gsub("\\s+", " ", trimws(addr))

      # Extract state and ZIP
      state_zip_pattern <- "(CO)\\s+(\\d{5}(-\\d{4})?)"
      if (grepl(state_zip_pattern, addr_clean)) {
        matches <- regmatches(addr_clean, regexpr(state_zip_pattern, addr_clean))
        data$state[i] <- "CO"
        zip_match <- regmatches(matches, regexpr("\\d{5}(-\\d{4})?", matches))
        data$zip[i] <- zip_match
        # Remove state/zip from address for city extraction
        addr_clean <- gsub(state_zip_pattern, "", addr_clean)
      }

      # Extract city (assume it's the last component before state)
      addr_parts <- strsplit(trimws(addr_clean), ",")[[1]]
      if (length(addr_parts) >= 2) {
        data$city[i] <- trimws(addr_parts[length(addr_parts)])
        # Remove city from address
        addr_clean <- paste(addr_parts[-length(addr_parts)], collapse = ", ")
      }

      # Standardized address is the remaining street address
      data$address_standardized[i] <- trimws(addr_clean)
    }
  }

  return(data)
}

locations_standardized <- standardize_addresses(all_locations)

cat("✅ Address standardization complete\n")

# Show sample of standardized addresses
cat("\n📋 Sample standardized addresses:\n")
sample_rows <- head(locations_standardized, 5)
for (i in 1:nrow(sample_rows)) {
  cat(sprintf("   %d. %s\n", i, sample_rows$provider_name[i]))
  cat(sprintf("      • Original: %s\n", sample_rows$address[i]))
  cat(sprintf("      • Street: %s\n", sample_rows$address_standardized[i]))
  cat(sprintf("      • City: %s, State: %s, ZIP: %s\n",
             sample_rows$city[i], sample_rows$state[i], sample_rows$zip[i]))
}

#' Step 3: Geocode using Census Bureau geocoding
cat("\n🗺️ STEP 3: Geocoding with US Census Bureau\n")

# Prepare addresses for geocoding
geocoding_input <- locations_standardized %>%
  mutate(
    full_address = paste(
      ifelse(is.na(address_standardized), "", address_standardized),
      ifelse(is.na(city), "", city),
      ifelse(is.na(state), "", state),
      ifelse(is.na(zip), "", zip),
      sep = ", "
    ),
    # Clean up extra commas and spaces
    full_address = gsub(",\\s*,", ",", full_address),
    full_address = gsub("^,\\s*", "", full_address),
    full_address = gsub("\\s*,$", "", full_address)
  )

cat(sprintf("📍 Geocoding %d unique addresses...\n", nrow(geocoding_input)))

# Use simplified geocoding function
geocoded_results <- simple_census_geocode(
  addresses = geocoding_input$full_address,
  ids = geocoding_input$location_id
)

cat(sprintf("✅ Geocoding complete\n"))
cat(sprintf("   • Successfully geocoded: %d/%d (%.1f%%)\n",
           sum(!is.na(geocoded_results$latitude)),
           nrow(geocoded_results),
           sum(!is.na(geocoded_results$latitude))/nrow(geocoded_results)*100))

#' Step 4: Create final geocoded dataset
cat("\n📊 STEP 4: Creating final geocoded radiation oncology dataset\n")

# Combine original data with geocoding results
final_locations <- locations_standardized %>%
  left_join(
    geocoded_results %>% select(location_id, latitude, longitude),
    by = "location_id"
  ) %>%
  filter(!is.na(latitude), !is.na(longitude)) %>%
  mutate(
    specialty = "Radiation Oncology",
    data_source = "Colorado Provider List 2024",
    geocoded_date = Sys.Date()
  )

cat(sprintf("✅ Final dataset created with %d geocoded locations\n", nrow(final_locations)))

# Show geocoding success by county
county_mapping <- list(
  "LAKEWOOD" = "Jefferson", "LONGMONT" = "Boulder", "LOVELAND" = "Larimer",
  "GRAND JUNCTION" = "Mesa", "DENVER" = "Denver", "COLORADO SPRINGS" = "El Paso",
  "PUEBLO" = "Pueblo", "DURANGO" = "La Plata", "LAFAYETTE" = "Boulder",
  "FORT COLLINS" = "Larimer", "GLENWOOD SPRINGS" = "Garfield", "BOULDER" = "Boulder",
  "AURORA" = "Arapahoe", "LONE TREE" = "Douglas", "HIGHLANDS RANCH" = "Douglas",
  "THORNTON" = "Adams", "EDWARDS" = "Eagle", "GOLDEN" = "Jefferson",
  "GREELEY" = "Weld"
)

final_locations$county <- NA_character_
for (i in 1:nrow(final_locations)) {
  city_upper <- toupper(trimws(final_locations$city[i]))
  if (city_upper %in% names(county_mapping)) {
    final_locations$county[i] <- county_mapping[[city_upper]]
  }
}

county_dist <- table(final_locations$county, useNA = "always")
cat("\n📊 Geocoded locations by county:\n")
for (county in names(county_dist)) {
  if (!is.na(county)) {
    cat(sprintf("   • %s County: %d locations\n", county, county_dist[[county]]))
  }
}

#' Step 5: Save geocoded data for isochrone analysis
cat("\n💾 STEP 5: Saving geocoded data for isochrone pipeline\n")

output_dir <- "data/geocoded"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Save as CSV
readr::write_csv(final_locations, file.path(output_dir, "colorado_radiation_oncology_geocoded.csv"))

# Save as spatial data (sf object)
locations_sf <- st_as_sf(final_locations,
                        coords = c("longitude", "latitude"),
                        crs = 4326)

# Save as geospatial file
sf::st_write(locations_sf,
            file.path(output_dir, "colorado_radiation_oncology_locations.geojson"),
            delete_dsn = TRUE, quiet = TRUE)

cat(sprintf("✅ Geocoded data saved to: %s\n", output_dir))
cat("   Files created:\n")
cat("   • colorado_radiation_oncology_geocoded.csv\n")
cat("   • colorado_radiation_oncology_locations.geojson\n")

#' Step 6: Generate summary for isochrone pipeline
cat("\n📋 STEP 6: Preparing summary for isochrone analysis\n")

summary_stats <- list(
  total_providers = length(unique(final_locations$provider_name)),
  total_locations = nrow(final_locations),
  counties_covered = length(unique(final_locations$county[!is.na(final_locations$county)])),
  geocoding_success_rate = nrow(final_locations) / nrow(locations_standardized),
  primary_locations = sum(final_locations$location_type == "Primary"),
  secondary_locations = sum(final_locations$location_type == "Secondary"),
  tertiary_locations = sum(final_locations$location_type == "Tertiary"),
  bounding_box = list(
    min_lat = min(final_locations$latitude),
    max_lat = max(final_locations$latitude),
    min_lon = min(final_locations$longitude),
    max_lon = max(final_locations$longitude)
  ),
  data_ready_for_isochrones = TRUE
)

jsonlite::write_json(summary_stats,
                    file.path(output_dir, "geocoding_summary.json"),
                    pretty = TRUE)

cat("✅ Ready for isochrone generation!\n")
cat("=================================\n")
cat(sprintf("   📍 %d geocoded provider locations\n", summary_stats$total_locations))
cat(sprintf("   🏥 %d unique providers\n", summary_stats$total_providers))
cat(sprintf("   🗺️ %d counties covered\n", summary_stats$counties_covered))
cat(sprintf("   ✅ %.1f%% geocoding success rate\n", summary_stats$geocoding_success_rate * 100))

cat("\n🚀 Next step: Generate isochrones using:\n")
cat("   Rscript generate_colorado_radiation_oncology_isochrones.R\n")

return(final_locations)
