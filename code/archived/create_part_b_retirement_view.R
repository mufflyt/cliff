# Create Part B retirement detection view
# Simplified view focusing on core fields for retirement analysis
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

cat("Creating simplified Part B view for retirement detection...\n")

# Create unified Part B retirement detection view
create_view_sql <- "
  CREATE OR REPLACE VIEW medicare_part_b_retirement_detection AS

  -- 2018 data
  SELECT
    printf('%010d', CAST(Rndrng_NPI AS BIGINT)) as npi_char,
    2018 as data_year,
    Rndrng_Prvdr_Last_Org_Name as provider_name_last,
    Rndrng_Prvdr_First_Name as provider_name_first,
    Rndrng_Prvdr_State_Abrvtn as provider_state,
    Tot_Srvcs as total_services,
    Tot_Benes as total_beneficiaries,
    Tot_HCPCS_Cds as total_procedure_codes,
    CAST(Rndrng_NPI AS BIGINT) as npi_original
  FROM medicare_part_b_2018
  WHERE Rndrng_NPI IS NOT NULL

  UNION ALL

  -- 2019 data
  SELECT
    printf('%010d', CAST(Rndrng_NPI AS BIGINT)) as npi_char,
    2019 as data_year,
    Rndrng_Prvdr_Last_Org_Name as provider_name_last,
    Rndrng_Prvdr_First_Name as provider_name_first,
    Rndrng_Prvdr_State_Abrvtn as provider_state,
    Tot_Srvcs as total_services,
    Tot_Benes as total_beneficiaries,
    Tot_HCPCS_Cds as total_procedure_codes,
    CAST(Rndrng_NPI AS BIGINT) as npi_original
  FROM medicare_part_b_2019
  WHERE Rndrng_NPI IS NOT NULL

  UNION ALL

  -- 2020 data
  SELECT
    printf('%010d', CAST(Rndrng_NPI AS BIGINT)) as npi_char,
    2020 as data_year,
    Rndrng_Prvdr_Last_Org_Name as provider_name_last,
    Rndrng_Prvdr_First_Name as provider_name_first,
    Rndrng_Prvdr_State_Abrvtn as provider_state,
    Tot_Srvcs as total_services,
    Tot_Benes as total_beneficiaries,
    Tot_HCPCS_Cds as total_procedure_codes,
    CAST(Rndrng_NPI AS BIGINT) as npi_original
  FROM medicare_part_b_2020
  WHERE Rndrng_NPI IS NOT NULL

  UNION ALL

  -- 2021 data
  SELECT
    printf('%010d', CAST(Rndrng_NPI AS BIGINT)) as npi_char,
    2021 as data_year,
    Rndrng_Prvdr_Last_Org_Name as provider_name_last,
    Rndrng_Prvdr_First_Name as provider_name_first,
    Rndrng_Prvdr_State_Abrvtn as provider_state,
    Tot_Srvcs as total_services,
    Tot_Benes as total_beneficiaries,
    Tot_HCPCS_Cds as total_procedure_codes,
    CAST(Rndrng_NPI AS BIGINT) as npi_original
  FROM medicare_part_b_2021
  WHERE Rndrng_NPI IS NOT NULL

  UNION ALL

  -- 2022 data
  SELECT
    printf('%010d', CAST(Rndrng_NPI AS BIGINT)) as npi_char,
    2022 as data_year,
    Rndrng_Prvdr_Last_Org_Name as provider_name_last,
    Rndrng_Prvdr_First_Name as provider_name_first,
    Rndrng_Prvdr_State_Abrvtn as provider_state,
    Tot_Srvcs as total_services,
    Tot_Benes as total_beneficiaries,
    Tot_HCPCS_Cds as total_procedure_codes,
    CAST(Rndrng_NPI AS BIGINT) as npi_original
  FROM medicare_part_b_2022
  WHERE Rndrng_NPI IS NOT NULL

  UNION ALL

  -- 2023 data
  SELECT
    printf('%010d', CAST(Rndrng_NPI AS BIGINT)) as npi_char,
    2023 as data_year,
    Rndrng_Prvdr_Last_Org_Name as provider_name_last,
    Rndrng_Prvdr_First_Name as provider_name_first,
    Rndrng_Prvdr_State_Abrvtn as provider_state,
    Tot_Srvcs as total_services,
    Tot_Benes as total_beneficiaries,
    Tot_HCPCS_Cds as total_procedure_codes,
    CAST(Rndrng_NPI AS BIGINT) as npi_original
  FROM medicare_part_b_2023
  WHERE Rndrng_NPI IS NOT NULL

  ORDER BY npi_char, data_year;
"

tryCatch({
  DBI::dbExecute(conn, create_view_sql)
  cat("✅ Created Part B retirement detection view\n")
}, error = function(e) {
  cat(sprintf("❌ Failed to create view: %s\n", e$message))
  stop("View creation failed")
})

# Test the view
unique_npis <- DBI::dbGetQuery(conn, "
  SELECT COUNT(DISTINCT npi_char) as unique_npis
  FROM medicare_part_b_retirement_detection
")$unique_npis

total_records <- DBI::dbGetQuery(conn, "
  SELECT COUNT(*) as total_records
  FROM medicare_part_b_retirement_detection
")$total_records

cat(sprintf("👥 Unique providers in Part B retirement view: %s\n", format(unique_npis, big.mark = ",")))
cat(sprintf("📊 Total records in Part B retirement view: %s\n", format(total_records, big.mark = ",")))

# Show sample activity patterns for retirement detection
sample_activity <- DBI::dbGetQuery(conn, "
  SELECT npi_char, data_year, provider_name_last, provider_name_first,
         provider_state, total_services, total_beneficiaries, total_procedure_codes
  FROM medicare_part_b_retirement_detection
  WHERE provider_state = 'CA' AND total_services > 5000
  ORDER BY npi_char, data_year
  LIMIT 10
")

cat("\nSample Part B activity patterns:\n")
print(sample_activity)

# Check year coverage
year_coverage <- DBI::dbGetQuery(conn, "
  SELECT data_year, COUNT(DISTINCT npi_char) as unique_providers,
         COUNT(*) as total_records,
         AVG(total_services) as avg_services,
         AVG(total_beneficiaries) as avg_beneficiaries
  FROM medicare_part_b_retirement_detection
  GROUP BY data_year
  ORDER BY data_year
")

cat("\nYear-by-year coverage in Part B data:\n")
print(year_coverage)

cat("\n✅ Part B retirement detection view ready for 6-source analysis!\n")
