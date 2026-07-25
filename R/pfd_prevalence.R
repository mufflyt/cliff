# Canonical age-specific pelvic-floor-disorder (PFD) prevalence — single source of truth.
#
# Meaning : proportion of U.S. women with >= 1 symptomatic PFD, by age group. Used to weight
#           female population projections into `women_with_pfd`, the demand denominator of the
#           supply-demand model (drives urogyn-per-PFD-woman and the adequacy claims).
# Units   : proportion in [0, 1]. Age in whole years.
# Source  : Nygaard et al., "Prevalence of Symptomatic Pelvic Floor Disorders in US Women,"
#           JAMA 2008;300(11):1311-1316 (NHANES 2005-2006), age-group prevalence.
# Bands   : the Nygaard prevalence age groups (20/40/60/80) are DISTINCT from the workforce
#           hazard bands (WC_BANDS) and must not be conflated.
#
#   age < 20  : 0.000  (excluded)
#   20 - 39   : 0.097
#   40 - 59   : 0.265
#   60 - 79   : 0.368
#   >= 80     : 0.497

PFD_PREVALENCE_BY_AGE <- data.frame(
  lower = c(0L, 20L, 40L, 60L, 80L),
  prev  = c(0.000, 0.097, 0.265, 0.368, 0.497)
)

# Fail loudly if the lookup is malformed.
stopifnot(
  nrow(PFD_PREVALENCE_BY_AGE) == 5L,
  all(PFD_PREVALENCE_BY_AGE$prev >= 0 & PFD_PREVALENCE_BY_AGE$prev <= 1),
  !is.unsorted(PFD_PREVALENCE_BY_AGE$lower, strictly = TRUE),   # age breaks strictly increasing
  !is.unsorted(PFD_PREVALENCE_BY_AGE$prev)                      # prevalence non-decreasing with age
)

#' Age-specific PFD prevalence (vectorized). Ages below 0 return 0.
pfd_prevalence_by_age <- function(age) {
  idx <- findInterval(age, PFD_PREVALENCE_BY_AGE$lower)
  idx[idx < 1L] <- 1L
  PFD_PREVALENCE_BY_AGE$prev[idx]
}
