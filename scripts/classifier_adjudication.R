#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Departure-classifier adjudication support (review point #3). True positive
# predictive value requires human chart review; this script provides (a) an
# AUTOMATED CORROBORATION RATE (a provisional PPV proxy): the fraction of
# classified departures for which an INDEPENDENT signal agrees (NPPES
# deactivation, Medicare billing cessation around the departure year, or an
# ABMS retirement year within +/-2 yr), and (b) a STRATIFIED SAMPLE for manual
# adjudication (all GO+URPS departures, all young departures, billing-continued
# departures, and a control sample classified continuously active).
#
# OUTPUT: cliff/data/classifier_corroboration.csv
#         cliff/data/classifier_adjudication_sample.csv
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(dplyr); library(readr); library(here)})

# PORTED FROM THE ISOCHRONES MONOREPO (2026-08-14). The extraction that created
# this repository carried this script's OUTPUT across but not the script, so the
# artifact sat in data/ with nothing able to regenerate it. Changes on porting:
#   * here::here("cliff", "data", X) -> here::here("data", X); this IS cliff now
#   * monorepo inputs resolve under CLIFF_ISOCHRONES_ROOT and fail loudly when
#     absent, rather than being hardcoded absolute paths that would silently
#     rebuild on whatever happened to be there
ISO <- Sys.getenv("CLIFF_ISOCHRONES_ROOT", unset = path.expand("~/isochrones"))
iso <- function(...) {
  p <- file.path(ISO, ...)
  if (!file.exists(p))
    stop(sprintf("[%s] monorepo input not found:\n  %s", "classifier_adjudication", p), call. = FALSE)
  p
}

set.seed(20260718L)
WIN <- c(2016L, 2021L); AGE_AT_CERT <- 30L
SUBS <- c(GO="Gynecologic Oncology", URPS="Female Pelvic Medicine & Reconstructive Surgery")

d <- read_csv(iso("manuscript", "tables", "table1_physician_characteristics.csv"),
              show_col_types=FALSE, guess_max=1e5) %>%
  filter(subspecialty %in% unname(SUBS), !is.na(cert_year)) %>%
  transmute(npi=as.character(npi), name=physician_name,
            ab=names(SUBS)[match(subspecialty,SUBS)],
            cy=as.integer(cert_year),
            ry=suppressWarnings(as.integer(retirement_year)),
            abms_ry=suppressWarnings(as.integer(abms_retirement_year)),
            last_billing=suppressWarnings(as.integer(last_billing_year)),
            deactivated = !is.na(npi_deactivation_date) & nzchar(as.character(npi_deactivation_date)),
            retired=as.logical(is_retired_for_cohorting)) %>%
  distinct(npi,.keep_all=TRUE) %>% filter(!is.na(ab))

dep <- d %>% filter(!is.na(ry) & ry>=WIN[1] & ry<=WIN[2]) %>%
  mutate(age_at_dep = ry - cy + AGE_AT_CERT,
         sig_nppes = deactivated,
         sig_billing = !is.na(last_billing) & last_billing <= (ry+1L),
         sig_abms = !is.na(abms_ry) & abs(abms_ry - ry) <= 2L,
         corroborated = sig_nppes | sig_billing | sig_abms)

corr <- dep %>% group_by(ab) %>% summarise(
  n_departures = dplyr::n(),
  pct_nppes_deactivated = round(100*mean(sig_nppes),0),
  pct_billing_ceased = round(100*mean(sig_billing),0),
  pct_abms_concordant = round(100*mean(sig_abms),0),
  ppv_proxy_corroborated = round(100*mean(corroborated),0),
  .groups="drop")
corr <- corr[match(c("GO","URPS"), corr$ab), ]
names(corr)[1] <- "subspecialty_abbrev"
write_csv(corr, here::here("data","classifier_corroboration.csv"))

# stratified sample for manual adjudication
strata_dep <- dep %>% mutate(
  stratum = dplyr::case_when(
    age_at_dep < 50 ~ "departure_young(<50)",
    !corroborated ~ "departure_uncorroborated",
    TRUE ~ "departure_corroborated")) %>%
  transmute(subspecialty_abbrev=ab, npi, name, cert_year=cy, departure_year=ry,
            age_at_departure=age_at_dep, last_billing_year=last_billing,
            nppes_deactivated=sig_nppes, abms_retirement_year=abms_ry,
            corroborated, stratum)
# control sample: classified continuously active (n per subspec = 30)
ctrl <- d %>% filter(retired==FALSE) %>% group_by(ab) %>%
  slice_sample(n=30) %>% ungroup() %>%
  transmute(subspecialty_abbrev=ab, npi, name, cert_year=cy, departure_year=NA_integer_,
            age_at_departure=NA_integer_, last_billing_year=last_billing,
            nppes_deactivated=deactivated, abms_retirement_year=abms_ry,
            corroborated=NA, stratum="control_active")
samp <- bind_rows(strata_dep, ctrl) %>% arrange(subspecialty_abbrev, stratum, name)
write_csv(samp, here::here("data","classifier_adjudication_sample.csv"))

cat("=== #3 automated departure-classifier corroboration (provisional PPV proxy) ===\n")
print(as.data.frame(corr), row.names=FALSE)
cat(sprintf("\nStratified adjudication sample: %d rows (%d departures + %d active controls)\n",
            nrow(samp), nrow(strata_dep), nrow(ctrl)))
cat("Strata:\n"); print(table(samp$subspecialty_abbrev, samp$stratum))
cat("Wrote classifier_corroboration.csv + classifier_adjudication_sample.csv\n")
