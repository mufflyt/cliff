# Create standardized Part B views with correct column names
# Fixes the NPI column name issue in Part B data
# Created: 2025-09-28

library(DBI)
library(duckdb)

# Connect to database
db_path <- "/Volumes/MufflySamsung/nber_my_duckdb.duckdb"
conn <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path)

# Ensure connection closes on exit
on.exit({
  if (DBI::dbIsValid(conn)) {
    DBI::dbDisconnect(conn)
  }
})

cat("Creating standardized Part B views with correct column names...\n")

years <- 2018:2023
view_creation_success <- 0

for (year in years) {
  table_name <- sprintf("medicare_part_b_%d", year)
  view_name <- sprintf("medicare_part_b_%d_standardized", year)

  # Check if source table exists
  if (table_name %in% DBI::dbListTables(conn)) {

    create_view_sql <- sprintf("
      CREATE OR REPLACE VIEW %s AS
      SELECT
        printf('%%010d', CAST(Rndrng_NPI AS BIGINT)) as npi_char,
        %d as data_year,
        Rndrng_Prvdr_Last_Org_Name as provider_name_last,
        Rndrng_Prvdr_First_Name as provider_name_first,
        Rndrng_Prvdr_MI as provider_middle_initial,
        Rndrng_Prvdr_Crdntls as provider_credentials,
        Rndrng_Prvdr_Gndr as provider_gender,
        Rndrng_Prvdr_St1 as provider_address_line1,
        Rndrng_Prvdr_City as provider_city,
        Rndrng_Prvdr_State_Abrvtn as provider_state,
        Rndrng_Prvdr_Zip5 as provider_zip,
        Rndrng_Prvdr_RUCA as provider_ruca,
        Tot_Srvcs as total_services,
        Tot_Benes as total_beneficiaries,
        Tot_Sbmtd_Chrg as total_submitted_charges,
        Tot_Mdcr_Alowd_Amt as total_medicare_allowed_amount,
        Tot_Mdcr_Pymt_Amt as total_medicare_payment_amount,
        CAST(Rndrng_NPI AS BIGINT) as npi_original
      FROM %s
      WHERE Rndrng_NPI IS NOT NULL;
    ", view_name, year, table_name)

    tryCatch({
      DBI::dbExecute(conn, create_view_sql)
      cat(sprintf("✅ Created standardized view: %s\n", view_name))
      view_creation_success <- view_creation_success + 1
    }, error = function(e) {
      cat(sprintf("❌ Failed to create view %s: %s\n", view_name, e$message))
    })
  }
}

# Create unified Part B view
if (view_creation_success > 0) {
  cat("Creating unified Part B view...\n")

  standardized_views <- sprintf("medicare_part_b_%d_standardized", years)
  existing_views <- DBI::dbListTables(conn)

  # Only include views that were successfully created
  valid_views <- standardized_views[standardized_views %in% existing_views]

  if (length(valid_views) > 0) {
    union_sql <- paste(sprintf("SELECT * FROM %s", valid_views), collapse = "\nUNION ALL\n")

    unified_view_sql <- sprintf("
      CREATE OR REPLACE VIEW medicare_part_b_all_years_standardized AS
      %s
      ORDER BY npi_char, data_year;
    ", union_sql)

    tryCatch({
      DBI::dbExecute(conn, unified_view_sql)
      cat("✅ Created unified Part B view: medicare_part_b_all_years_standardized\n")
    }, error = function(e) {
      cat(sprintf("❌ Failed to create unified view: %s\n", e$message))
    })
  }
}

# Test the unified view
if ("medicare_part_b_all_years_standardized" %in% DBI::dbListTables(conn)) {
  unique_npis <- DBI::dbGetQuery(conn, "
    SELECT COUNT(DISTINCT npi_char) as unique_npis
    FROM medicare_part_b_all_years_standardized
  ")$unique_npis

  cat(sprintf("👥 Unique providers in Part B standardized data: %s\n", format(unique_npis, big.mark = ",")))

  # Sample a few records
  sample_data <- DBI::dbGetQuery(conn, "
    SELECT npi_char, data_year, provider_name_last, provider_name_first,
           provider_state, total_services, total_beneficiaries
    FROM medicare_part_b_all_years_standardized
    WHERE provider_state = 'CA' AND total_services > 1000
    LIMIT 5
  ")

  cat("\nSample Part B data:\n")
  print(sample_data)
}

cat("\n✅ Part B standardized views created successfully!\n")
