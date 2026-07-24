## code to prepare `abog_provider_dataframe_8_17_2025_1948_only_workforce_directory` dataset goes here

# Set libPaths.
.libPaths("/Users/tmuffly/.exploratory/R/4.4_ARM")

# Load required packages.
library(janitor)
library(lubridate)
library(hms)
library(tidyr)
library(stringr)
library(readr)
library(cpp11)
library(forcats)
library(RcppRoll)
library(dplyr)
library(tibble)
library(bit64)
library(zipangu)
library(purrr)
library(exploratory)
library(crayon)

# Steps to produce the output
exploratory::read_delim_file(
  "/Users/tmuffly/isochrones/data/0-Download/output/abog_provider_dataframe_8_17_2025_1948_only_workforce_directory1.csv",
  delim = NULL,
  quote = "\"" ,
  col_names = TRUE ,
  na = c('') ,
  locale = readr::locale(
    encoding = "UTF-8",
    decimal_mark = ".",
    tz = "America/Denver",
    grouping_mark = ","
  ),
  trim_ws = TRUE ,
  progress = FALSE
) %>%
  readr::type_convert() %>%
  exploratory::clean_data_frame() %>%
  select(
    -...22,
    -...23,
    -Message,
    -filler,
    -`random id`,
    -first,
    -last,
    -TAX,
    -...34,
    -...35,
    -...36,
    -...37,
    -...38,
    -...39,
    -...40,
    -...41,
    -...42,
    -...43,
    -...44,
    -...45,
    -...46,
    -...47,
    -...48,
    -...49,
    -...50,
    -...51,
    -...52,
    -...53,
    -...54,
    -...55,
    -...56,
    -...57,
    -...58,
    -...59,
    -...60,
    -...61,
    -...62,
    -...63,
    -...64,
    -...65,
    -...66,
    -...67,
    -...68,
    -...69,
    -...70,
    -...71,
    -...72,
    -...73,
    -...74,
    -...75,
    -...76,
    -...77,
    -...78,
    -...79,
    -...80,
    -...81,
    -...82,
    -...83,
    -...84,
    -...85,
    -...86,
    -...87,
    -...88,
    -...89,
    -...90,
    -...91,
    -...92,
    -...93,
    -...94,
    -...108,
    -...109,
    -...110,
    -...111,
    -...112,
    -...113,
    -...114,
    -...115,
    -...130,
    -...131,
    -...132,
    -...133,
    -...134,
    -...135,
    -...136,
    -...137,
    -...138,
    -...139,
    -...140,
    -...141,
    -...142,
    -...143,
    -...144,
    -...145,
    -...146,
    -npi,
    -full.name.1,
    -full.name.2,
    -full.name.3,
    -full.name.5,
    -Last.Name
  ) %>%
  select(
    -First.Name,
    -Middle.Name,
    -Gender,
    -Medical.School.Name,
    -Graduation.year,
    -Primary.specialty,
    -Secondary.specialty.1,
    -Secondary.specialty.2,
    -Secondary.specialty.3,
    -Secondary.specialty.4,
    -Line.1.Street.Address,
    -City,
    -State,
    -Zip.Code
  ) %>%
  select(
    -name_test,
    -name_test_1,
    -suffix,
    -firstname,
    -middlename,
    -lastname,
    -ZIP,
    -STCOUNTYFP,
    -CLASSFP,
    -latitude,
    -longitude,
    -residency_program,
    -Last_name,
    -`Provider First Line Business Mailing Address`,
    -`Provider Business Mailing Address City Name`,
    -`Provider Business Mailing Address State Name`,
    -`Provider Business Mailing Address Postal Code`,
    -`Provider Business Mailing Address Country Code (If outside U.S.)`,
    -`Provider Business Practice Location Address City Name`,
    -`Provider Business Practice Location Address Country Code (If outside U.S.)`,
    -`Provider Gender Code`,
    -`Healthcare Provider Taxonomy Code_1`,
    -`Provider License Number_1`,
    -`Provider License Number State Code_1`,
    -`Healthcare Provider Primary Taxonomy Switch_1`,
    -`Healthcare Provider Taxonomy Code_2`
  ) %>%
  mutate(mocStatus = case_when(
    mocStatus == "N/A" ~ as.character(NA) ,
    TRUE ~ as.character(mocStatus)
  )) %>%
  mutate(across(c(
    sub1mocStatus, sub2mocStatus, clinicallyActive
  ), ~ (na_if(., "N/A")))) %>%
  filter(!is.na(physician_name)) %>%
  mutate(startDate = coalesce(startDate, orig_bas, orig_sub, sub1startDate, sub2startDate)) %>%
  select(-orig_sub, -x_sub_orig, -orig_bas, -app_no, -NPI) %>%
  mutate(subspecialty_name = coalesce(subspecialty_name, sub1FullDescr, sub2FullDescr, sub2)) %>%
  mutate(subspecialty_name = impute_na(subspecialty_name, type = "value", val = "Generalist")) %>%
  reorder_cols(
    physician_name,
    subspecialty_name,
    startDate,
    certStatus,
    mocStatus,
    sub1startDate,
    sub1certStatus,
    sub1mocStatus,
    sub2,
    sub2startDate,
    sub2certStatus,
    sub2mocStatus,
    clinicallyActive,
    city,
    state,
    DateTime,
    source_file,
    sub1FullDescr,
    sub1certstatusDescr,
    sub2FullDescr,
    city_state,
    abog_id
  )

usethis::use_data(abog_provider_dataframe_8_17_2025_1948_only_workforce_directory,
                  overwrite = TRUE)
