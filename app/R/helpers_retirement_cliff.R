# =============================================================================
# helpers_retirement_cliff.R
# Helper functions for retirement cliff simulation in Shiny app
# =============================================================================
# Adapted from /Users/tylermuffly/Documents/iso_retirement_cliff_shiny/R/
# =============================================================================

#' Create Demo Isochrones
#'
#' For demo mode, approximate isochrones as circular buffers around each provider.
#' In production, you'd use precomputed Valhalla isochrones.
#'
#' @param providers tibble with provider_id, lon, lat columns
#' @param drive_minutes numeric drive time threshold
#' @return sf object with isochrone polygons
make_demo_isochrones <- function(providers, drive_minutes) {

  if (nrow(providers) == 0) {
    stop("No providers provided to make_demo_isochrones()")
  }

  # Disable s2 to avoid geometry errors
  old_s2 <- sf::sf_use_s2()
  sf::sf_use_s2(FALSE)
  on.exit(sf::sf_use_s2(old_s2), add = TRUE)

  providers_sf <- sf::st_as_sf(
    providers,
    coords = c("lon", "lat"),
    crs = 4326,
    remove = FALSE
  )

  # Heuristic: convert minutes to distance
  # Assume 60 km/hr average => 1 km per minute
  # Convert km to meters
  buffer_m <- drive_minutes * 1000

  iso_sf <- providers_sf |>
    sf::st_transform(5070) |>
    dplyr::mutate(minutes = drive_minutes) |>
    dplyr::mutate(geometry = sf::st_buffer(geometry, dist = buffer_m)) |>
    sf::st_transform(4326) |>
    sf::st_make_valid() |>
    dplyr::select(provider_id, minutes, geometry)

  iso_sf
}


#' Add Coverage Flag to Tracts
#'
#' Performs spatial intersection to determine which tracts are covered by isochrones.
#'
#' @param tracts sf object with tract polygons (must have population column)
#' @param isochrones sf object with isochrone polygons
#' @return tracts sf object with coverage_status column added
add_coverage_flag <- function(tracts, isochrones) {

  # Disable s2 to avoid geometry errors with complex polygons
 old_s2 <- sf::sf_use_s2()
  sf::sf_use_s2(FALSE)
  on.exit(sf::sf_use_s2(old_s2), add = TRUE)

  # Union isochrones once for faster intersects
  isos_valid <- sf::st_make_valid(isochrones)
  isos_union <- sf::st_union(isos_valid)
  isos_union <- sf::st_make_valid(isos_union)

  covered_lgl <- sf::st_intersects(tracts, isos_union, sparse = FALSE)[, 1]

  tracts |>
    dplyr::mutate(
      coverage_status = dplyr::if_else(covered_lgl, "Covered", "Not covered")
    )
}


#' Compute Coverage Statistics
#'
#' Calculate overall coverage % and equity breakdown (rural vs urban).
#'
#' @param tracts sf object with population and rural_urban columns
#' @param isochrones sf object with isochrone polygons
#' @return list with headline, headline_detail, stats_long, equity_table
compute_coverage_stats <- function(tracts, isochrones) {

  tracts_cov <- add_coverage_flag(tracts = tracts, isochrones = isochrones)

  stats_long <- tracts_cov |>
    sf::st_drop_geometry() |>
    dplyr::group_by(.data$coverage_status) |>
    dplyr::summarise(
      population = sum(.data$population, na.rm = TRUE),
      n_tracts = dplyr::n(),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      population_pct = .data$population / sum(.data$population, na.rm = TRUE)
    )

  pop_total <- sum(stats_long$population, na.rm = TRUE)

  pop_cov <- stats_long |>
    dplyr::filter(.data$coverage_status == "Covered") |>
    dplyr::pull(.data$population)

  if (length(pop_cov) == 0) {
    pop_cov <- 0
  }

  pct_cov <- pop_cov / pop_total

  headline <- paste0(
    scales::percent(pct_cov, accuracy = 0.1),
    " of women live within the selected drive-time band"
  )

  headline_detail <- paste0(
    "Covered population: ",
    formatC(pop_cov, big.mark = ",", format = "f", digits = 0),
    " of ",
    formatC(pop_total, big.mark = ",", format = "f", digits = 0),
    " (synthetic demo dataset)"
  )

  # Equity table: rural vs urban breakdown
  equity_table <- tracts_cov |>
    sf::st_drop_geometry() |>
    dplyr::group_by(.data$rural_urban, .data$coverage_status) |>
    dplyr::summarise(
      population = sum(.data$population, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::group_by(.data$rural_urban) |>
    dplyr::mutate(
      pct = .data$population / sum(.data$population, na.rm = TRUE)
    ) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      population_formatted = formatC(.data$population, big.mark = ",", format = "f", digits = 0),
      pct_formatted = scales::percent(.data$pct, accuracy = 0.1)
    ) |>
    dplyr::arrange(.data$rural_urban, dplyr::desc(.data$coverage_status))

  list(
    headline = headline,
    headline_detail = headline_detail,
    pct_covered = pct_cov,
    pop_covered = pop_cov,
    pop_total = pop_total,
    stats_long = stats_long,
    equity_table = equity_table
  )
}


#' Compute Retirement Cliff Curve
#'
#' Simulate removing physicians from 0% to 50% (oldest-first) and calculate
#' coverage at each step.
#'
#' @param tracts sf object with population column
#' @param providers tibble with age, lon, lat, provider_id columns
#' @param drive_minutes numeric drive time threshold
#' @return tibble with removed_pct and covered_pct columns
compute_cliff_curve <- function(tracts, providers, drive_minutes) {

  providers_sorted <- providers |>
    dplyr::arrange(dplyr::desc(.data$age))

  n <- nrow(providers_sorted)
  if (n == 0) {
    return(dplyr::tibble(removed_pct = numeric(0), covered_pct = numeric(0)))
  }


  # Simulate removing 0% to 50% (oldest-first) in larger steps for speed
  # Using 10% steps instead of 5% to reduce computation time
  steps <- seq(0, 0.5, by = 0.10)

  curve_tbl <- purrr::map_dfr(steps, function(step) {

    k_remove <- floor(n * step)
    if (k_remove >= n) {
      providers_keep <- providers_sorted[0, ]
    } else {
      providers_keep <- providers_sorted[(k_remove + 1):n, ]
    }

    if (nrow(providers_keep) == 0) {
      covered_pct <- 0
    } else {
      isos <- make_demo_isochrones(
        providers = providers_keep,
        drive_minutes = drive_minutes
      )

      tracts_cov <- add_coverage_flag(tracts = tracts, isochrones = isos)

      pop_total <- sum(tracts_cov$population, na.rm = TRUE)
      pop_cov <- sum(
        tracts_cov$population[tracts_cov$coverage_status == "Covered"],
        na.rm = TRUE
      )
      covered_pct <- pop_cov / pop_total
    }

    dplyr::tibble(
      removed_pct = step,
      covered_pct = covered_pct
    )
  })

  curve_tbl
}


#' Generate Demo Provider Data
#'
#' Creates synthetic provider data with ages and locations for demo purposes.
#' Points are filtered to fall only within continental US land boundaries.
#'
#' @param n number of providers to generate (default 500)
#' @param seed random seed for reproducibility
#' @return tibble with provider_id, subspecialty, age, lon, lat
generate_demo_providers <- function(n = 200L, seed = 42L) {
  set.seed(seed)

  subspecialties <- c(
    "Urogynecology (FPMRS)",
    "Gynecologic Oncology",
    "MIGS",
    "Maternal-Fetal Medicine",
    "Reproductive Endocrinology",
    "Pediatric & Adolescent Gyn",
    "Complex Family Planning"
  )

 # Get US states polygon to filter out ocean points
  # Disable s2 for this operation to avoid geometry errors
  old_s2 <- sf::sf_use_s2()
  sf::sf_use_s2(FALSE)
  on.exit(sf::sf_use_s2(old_s2), add = TRUE)

  us_states <- sf::st_as_sf(maps::map("state", plot = FALSE, fill = TRUE))
  us_states <- sf::st_make_valid(us_states)
  us_states <- sf::st_transform(us_states, 4326)
  us_union <- sf::st_union(sf::st_make_valid(us_states))

  # Generate more candidates than needed (some will be filtered out)
  n_candidates <- n * 3L

  candidates <- dplyr::tibble(
    lon = stats::runif(n_candidates, -124, -68),
    lat = stats::runif(n_candidates, 25, 48)
  )

  # Convert to sf and filter to land only
  candidates_sf <- sf::st_as_sf(candidates, coords = c("lon", "lat"), crs = 4326)
  on_land <- sf::st_intersects(candidates_sf, us_union, sparse = FALSE)[, 1]
  candidates_land <- candidates[on_land, ]

  # Take first n points (or all if fewer available)
  n_final <- min(n, nrow(candidates_land))
  candidates_final <- candidates_land[seq_len(n_final), ]

  providers <- dplyr::tibble(
    provider_id = sprintf("P%04d", seq_len(n_final)),
    subspecialty = sample(subspecialties, n_final, replace = TRUE),
    age = round(stats::rnorm(n_final, mean = 52, sd = 10)),
    lon = candidates_final$lon,
    lat = candidates_final$lat
  ) |>
    dplyr::filter(age >= 30, age <= 85)  # Realistic age bounds

  providers
}


#' Generate Demo Tract Data
#'
#' Creates a coarse grid of synthetic tract polygons for demo purposes.
#'
#' @param seed random seed for reproducibility
#' @return sf object with tract polygons including population and rural_urban
generate_demo_tracts <- function(seed = 42L) {
  set.seed(seed)

  # Create a coarse grid covering continental US
  grid_bbox <- sf::st_bbox(
    c(xmin = -124.5, ymin = 25, xmax = -67, ymax = 49.5),
    crs = sf::st_crs(4326)
  )

  # Use a coarser grid (15x6 = 90 cells) for faster spatial operations
  grid_sf <- sf::st_as_sfc(grid_bbox) |>
    sf::st_make_grid(n = c(15, 6), what = "polygons") |>
    sf::st_sf(geometry = _)

  n_tracts <- nrow(grid_sf)

  tracts_sf <- grid_sf |>
    dplyr::mutate(
      tract_id = sprintf("T%04d", seq_len(n_tracts)),
      population = round(stats::runif(n_tracts, min = 200, max = 12000)),
      rural_urban = base::ifelse(stats::runif(n_tracts) < 0.25, "Rural", "Urban"),
      source = "synthetic_demo"
    )

  tracts_sf
}


#' Load or Create Demo Payload for Retirement Cliff
#'
#' Loads existing demo data or creates new synthetic data for the retirement
#' cliff simulation.
#'
#' @param data_dir directory to store/load demo data
#' @param seed random seed for reproducibility
#' @return list with providers tibble and tracts sf object
load_or_create_retirement_demo <- function(data_dir = NULL, seed = 42L) {

  # If no data directory, just generate in-memory
  if (is.null(data_dir)) {
    return(list(
      providers = generate_demo_providers(n = 200L, seed = seed),
      tracts = generate_demo_tracts(seed = seed)
    ))
  }

  # Try to use existing data directory
  if (!base::dir.exists(data_dir)) {
    base::dir.create(data_dir, recursive = TRUE)
  }

  providers_path <- base::file.path(data_dir, "retirement_demo_providers.csv")
  tracts_path <- base::file.path(data_dir, "retirement_demo_tracts.gpkg")

  if (base::file.exists(providers_path) && base::file.exists(tracts_path)) {
    providers_tbl <- utils::read.csv(providers_path, stringsAsFactors = FALSE) |>
      dplyr::as_tibble()
    tracts_sf <- sf::st_read(tracts_path, quiet = TRUE)

    return(list(
      providers = providers_tbl,
      tracts = tracts_sf
    ))
  }

  # Generate new demo data
  providers_tbl <- generate_demo_providers(n = 200L, seed = seed)
  tracts_sf <- generate_demo_tracts(seed = seed)

  # Save for future use
  utils::write.csv(providers_tbl, providers_path, row.names = FALSE)
  sf::st_write(tracts_sf, dsn = tracts_path, delete_dsn = TRUE, quiet = TRUE)

  list(
    providers = providers_tbl,
    tracts = tracts_sf
  )
}


#' Load Real Provider Data for Retirement Cliff
#'
#' Loads real physician data from the isochrones cache and ABMS certification
#' data to estimate ages. Falls back to demo data if real data unavailable.
#'
#' @param isochrone_rds_path Path to isochrones RDS file with subspecialty tags
#' @param duckdb_path Path to DuckDB with ABMS certification data
#' @param current_year Year for age estimation (default 2024)
#' @param cert_age_estimate Average age at certification (default 32)
#' @return list with providers tibble and tracts sf object
load_real_retirement_data <- function(
    isochrone_rds_path = "/Volumes/MufflySamsung/isochrone_working_files/checkpoints/isochrones_with_subspecialty_tags.rds",
    duckdb_path = "/Volumes/MufflySamsung/DuckDB/nber_my_duckdb.duckdb",
    current_year = 2024L,
    cert_age_estimate = 32L,
    max_providers = 500L  # Limit for interactive performance
) {

  # Check if files exist
  if (!file.exists(isochrone_rds_path)) {
    message("Real isochrone data not found. Using demo data.")
    return(load_or_create_retirement_demo(data_dir = NULL, seed = 42L))
  }

  message("Loading real provider data from isochrones cache...")

  # Load isochrones and extract unique providers
  iso_sf <- readRDS(isochrone_rds_path)

  # Get unique providers with their locations (use first row per NPI)
  providers_raw <- iso_sf |>
    sf::st_drop_geometry() |>
    dplyr::filter(!is.na(npi)) |>
    dplyr::group_by(npi) |>
    dplyr::slice_head(n = 1) |>
    dplyr::ungroup() |>
    dplyr::select(
      npi,
      provider_name,
      lon = center_lng,
      lat = center_lat,
      subspecialty
    ) |>
    dplyr::filter(!is.na(lon), !is.na(lat))

  message(sprintf("Found %d unique providers with coordinates", nrow(providers_raw)))

  # Try to load ABMS certification data for age estimation
  providers_with_age <- tryCatch({
    if (!file.exists(duckdb_path)) {
      stop("DuckDB path not found")
    }

    con <- DBI::dbConnect(duckdb::duckdb(), duckdb_path, read_only = TRUE)
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

    # Get certification year data
    abms_data <- DBI::dbGetQuery(con, "
      SELECT
        npi,
        most_recent_cert_year,
        abms_retired_flag,
        abms_retirement_year
      FROM credentials.abms_npi_matches
      WHERE npi IS NOT NULL
    ")

    message(sprintf("Loaded %d ABMS records with certification data", nrow(abms_data)))

    # Join with providers
    providers_joined <- providers_raw |>
      dplyr::left_join(abms_data, by = "npi") |>
      dplyr::mutate(
        # Estimate age from certification year
        # Assume average age at certification is ~32 (after med school + residency + fellowship)
        age = dplyr::case_when(
          !is.na(most_recent_cert_year) ~ current_year - most_recent_cert_year + cert_age_estimate,
          TRUE ~ NA_integer_
        ),
        # For providers without cert year, assign random age in typical range
        age = dplyr::if_else(is.na(age), sample(40:65, dplyr::n(), replace = TRUE), age),
        # Clamp age to reasonable bounds
        age = pmax(30L, pmin(85L, age)),
        # Mark as retired if ABMS says so
        is_retired = dplyr::coalesce(abms_retired_flag, FALSE)
      ) |>
      # Filter out retired physicians for active workforce simulation
      dplyr::filter(!is_retired) |>
      dplyr::select(
        provider_id = npi,
        subspecialty,
        age,
        lon,
        lat
      )

    providers_joined

  }, error = function(e) {
    message("Could not load ABMS data: ", e$message)
    message("Estimating ages randomly...")

    # Fallback: assign random ages
    providers_raw |>
      dplyr::mutate(
        age = sample(35:70, dplyr::n(), replace = TRUE)
      ) |>
      dplyr::select(
        provider_id = npi,
        subspecialty,
        age,
        lon,
        lat
      )
  })

  # Standardize subspecialty names
  providers_final <- providers_with_age |>
    dplyr::mutate(
      subspecialty = dplyr::case_when(
        subspecialty %in% c("FPMRS", "Female Pelvic Medicine & Reconstructive Surgery") ~ "Urogynecology (FPMRS)",
        subspecialty %in% c("GO", "Gynecologic Oncology") ~ "Gynecologic Oncology",
        subspecialty %in% c("MFM", "Maternal-Fetal Medicine") ~ "Maternal-Fetal Medicine",
        subspecialty %in% c("REI", "Reproductive Endocrinology and Infertility") ~ "Reproductive Endocrinology",
        subspecialty %in% c("MIGS", "MIG") ~ "MIGS",
        subspecialty %in% c("PAG", "Pediatric & Adolescent Gynecology") ~ "Pediatric & Adolescent Gyn",
        subspecialty %in% c("CFP", "Complex Family Planning") ~ "Complex Family Planning",
        subspecialty %in% c("CRI") ~ "Reproductive Endocrinology",  # CRI is often REI
        is.na(subspecialty) ~ "Generalist",
        TRUE ~ subspecialty
      )
    ) |>
    dplyr::filter(!is.na(subspecialty), subspecialty != "Generalist")

  message(sprintf("Found %d subspecialists total", nrow(providers_final)))

  # Sample providers for interactive performance if needed
  if (nrow(providers_final) > max_providers) {
    set.seed(42L)  # For reproducibility
    # Stratified sample to maintain subspecialty distribution
    providers_final <- providers_final |>
      dplyr::group_by(subspecialty) |>
      dplyr::slice_sample(prop = max_providers / nrow(providers_final)) |>
      dplyr::ungroup()
    message(sprintf("Sampled %d providers for interactive performance", nrow(providers_final)))
  }

  message("Subspecialty distribution:")
  print(table(providers_final$subspecialty))

  # Generate tract grid (use demo tracts for now - could load real census tracts later)
  tracts_sf <- generate_demo_tracts(seed = 42L)

  list(
    providers = providers_final,
    tracts = tracts_sf
  )
}
