#!/usr/bin/env Rscript
# Quick Geocoding for Isochrone Pipeline
# =====================================
# Streamlined geocoding to get coordinates for radiation oncologists

library(dplyr)
library(readr)

# Source the proper Census geocoding functions
source("../../R/census_geocode_enhanced.R")

cat("🗺️ QUICK GEOCODING FOR ISOCHRONE PIPELINE\n")
cat("==========================================\n")

# Load providers and create simple address list
providers <- readr::read_csv("data/colorado_radiation_oncologists_real.csv", show_col_types = FALSE)

# Create simple address dataset for geocoding
addresses_to_geocode <- data.frame(
  id = character(),
  provider_name = character(),
  address = character(),
  stringsAsFactors = FALSE
)

# Extract all addresses
for (i in 1:nrow(providers)) {
  provider <- providers[i, ]

  # Primary address
  if (!is.na(provider$address_1) && provider$address_1 != "") {
    addresses_to_geocode <- rbind(addresses_to_geocode,
                                 data.frame(id = paste0("P", i),
                                           provider_name = provider$name,
                                           address = provider$address_1))
  }

  # Secondary address
  if (!is.na(provider$address_2) && provider$address_2 != "") {
    addresses_to_geocode <- rbind(addresses_to_geocode,
                                 data.frame(id = paste0("S", i),
                                           provider_name = provider$name,
                                           address = provider$address_2))
  }

  # Tertiary address
  if (!is.na(provider$address_3) && provider$address_3 != "") {
    addresses_to_geocode <- rbind(addresses_to_geocode,
                                 data.frame(id = paste0("T", i),
                                           provider_name = provider$name,
                                           address = provider$address_3))
  }
}

cat(sprintf("📍 Geocoding %d addresses from %d providers\n", nrow(addresses_to_geocode), nrow(providers)))

# Simple parsing for Colorado addresses
parse_simple_address <- function(addr) {
  if (is.na(addr) || addr == "") return(list(street=NA, city=NA, state=NA, zip=NA))

  # Extract ZIP
  zip_match <- regmatches(addr, regexpr("\\d{5}(-\\d{4})?", addr))
  zip <- if(length(zip_match) > 0) zip_match else NA
  addr_no_zip <- gsub("\\d{5}(-\\d{4})?", "", addr)

  # Extract state
  state <- if(grepl("\\bCO\\b", addr)) "CO" else NA
  addr_no_state <- gsub("\\bCO\\b", "", addr_no_zip)

  # Split by comma for city/street
  parts <- strsplit(trimws(addr_no_state), ",")[[1]]
  parts <- trimws(parts[parts != ""])

  if (length(parts) >= 2) {
    street <- parts[1]
    city <- parts[length(parts)]
  } else {
    # Try to extract city from known Colorado cities
    cities <- c("DENVER", "COLORADO SPRINGS", "AURORA", "FORT COLLINS", "LAKEWOOD",
               "PUEBLO", "BOULDER", "GRAND JUNCTION", "LONGMONT", "LOVELAND")
    street <- addr_no_state
    city <- NA
    for (c in cities) {
      if (grepl(c, toupper(addr))) {
        city <- str_to_title(c)
        break
      }
    }
  }

  return(list(street=street, city=city, state=state, zip=zip))
}

# Geocode locations
results <- data.frame(
  id = character(),
  provider_name = character(),
  address = character(),
  latitude = numeric(),
  longitude = numeric(),
  geocoded = logical(),
  stringsAsFactors = FALSE
)

cat("🔄 Starting geocoding...\n")

for (i in 1:nrow(addresses_to_geocode)) {
  addr_info <- addresses_to_geocode[i, ]
  parsed <- parse_simple_address(addr_info$address)

  cat(sprintf("   %d/%d: %s\n", i, nrow(addresses_to_geocode), substr(addr_info$provider_name, 1, 20)))

  # Try geocoding
  lat <- NA
  lon <- NA
  success <- FALSE

  if (!is.na(parsed$street) && !is.na(parsed$city)) {
    tryCatch({
      geo_result <- census_geocode_enhanced(
        addr = parsed$street,
        city = parsed$city,
        state = "CO",
        zip = parsed$zip
      )

      if (!is.na(geo_result$lat) && !is.na(geo_result$lon)) {
        lat <- geo_result$lat
        lon <- geo_result$lon
        success <- TRUE
        cat(sprintf("      ✅ (%.4f, %.4f)\n", lat, lon))
      } else {
        cat("      ❌ No result\n")
      }
    }, error = function(e) {
      cat(sprintf("      ❌ Error: %s\n", substr(e$message, 1, 50)))
    })
  } else {
    cat("      ❌ Could not parse address\n")
  }

  results <- rbind(results, data.frame(
    id = addr_info$id,
    provider_name = addr_info$provider_name,
    address = addr_info$address,
    latitude = lat,
    longitude = lon,
    geocoded = success,
    stringsAsFactors = FALSE
  ))

  Sys.sleep(0.1)  # Be nice to Census API
}

# Filter to successful geocodes
geocoded_locations <- results %>%
  filter(geocoded == TRUE) %>%
  mutate(
    specialty = "Radiation Oncology",
    location_type = case_when(
      substr(id, 1, 1) == "P" ~ "Primary",
      substr(id, 1, 1) == "S" ~ "Secondary",
      TRUE ~ "Tertiary"
    )
  )

cat(sprintf("\n✅ Geocoding complete: %d/%d successful (%.1f%%)\n",
           nrow(geocoded_locations), nrow(results),
           nrow(geocoded_locations)/nrow(results)*100))

# Save for isochrone pipeline
output_dir <- "data/geocoded_simple"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

readr::write_csv(geocoded_locations, file.path(output_dir, "colorado_radiation_oncology_simple.csv"))

cat(sprintf("📁 Saved to: %s\n", file.path(output_dir, "colorado_radiation_oncology_simple.csv")))

# Summary
cat("\n📊 GEOCODING SUMMARY:\n")
cat(sprintf("   • Total addresses processed: %d\n", nrow(results)))
cat(sprintf("   • Successfully geocoded: %d\n", nrow(geocoded_locations)))
cat(sprintf("   • Unique providers: %d\n", length(unique(geocoded_locations$provider_name))))

by_type <- table(geocoded_locations$location_type)
for (type in names(by_type)) {
  cat(sprintf("   • %s locations: %d\n", type, by_type[[type]]))
}

cat("\n🚀 Ready for isochrone generation!\n")
cat("   Next: Create isochrones for travel time analysis\n")

head(geocoded_locations)
