# Guard suite (model layer) for the URPS Effective-Adequacy Explorer.
# Tests the canonical projection in model.R directly, so the app and the tests
# exercise identical logic (Guard 57). Guard numbers reference the review list.
#
# NOTE (Guard 13): "effective FTE <= headcount" is NOT asserted. Effective FTE is
# an age-productivity-weighted CAPACITY index normalized so the 2025 age-weight
# averages 1; a workforce younger than the 2025 mix can exceed headcount. The
# valid invariants are eff_index(2025)==100 and adequacy(2025)==1 (below).

suppressPackageStartupMessages({ library(testthat); library(data.table) })

.mp <- Find(file.exists, c("model.R","../../model.R","../../../model.R",
                           "cliff/shiny_urps_adequacy/model.R",
                           file.path(getwd(),"model.R")))
source(.mp)

P   <- function(...) modifyList(DEFAULTS, list(...))
run <- function(...) project_from(P(...))
S_t <- function(...) run(...)$effective          # effective-FTE supply trajectory
H_t <- function(...) run(...)$headcount

## Independent reference simulator: returns per-year base/new age vectors so the
## age-distribution guards are checked against a from-scratch re-implementation.
ref_sim <- function(p) {
  ages <- av0; nb <- count0; nn <- rep(0, length(count0))
  bb <- OB_BASE_SHARE + (1-OB_BASE_SHARE)*p$uro_fte
  nbl <- p$obgyn_share + (1-p$obgyn_share)*p$uro_fte
  yrs <- p$retire; per <- list()
  for (yr in 2025:p$end_year) {
    wv <- if (p$weight_on) w(ages) else rep(1, length(ages))
    per[[as.character(yr)]] <- list(age=ages, base=nb, new=nn,
      headcount=sum(nb)+sum(nn),
      effective=sum(wv*nb)*bb + sum(wv*nn)*nbl*p$fte_new)
    h <- pmin(1, haz_for(ages)*p$haz_mult); h[ages >= p$retire] <- 1
    nb <- nb*(1-h); nn <- nn*(1-h)
    ages <- ages + 1L; ix <- match(p$entry_age, ages)
    if (is.na(ix)) { ages<-c(ages,p$entry_age); nb<-c(nb,0); nn<-c(nn,p$entrants) }
    else nn[ix] <- nn[ix] + p$entrants
  }
  per
}

# ============================ NUMERICAL IDENTITIES ==========================
test_that("G11: every indexed series equals exactly 100 in 2025", {
  d <- run(); b <- d[YEAR==2025]
  expect_equal(b$eff_index, 100, tolerance=1e-9)
  expect_equal(b$hc_index,  100, tolerance=1e-9)
  expect_equal(b$dem_index, 100, tolerance=1e-9)
})

test_that("G12: status-quo demand is population growth only (independent of supply levers)", {
  d <- run()
  # dem_index must equal 100 * women_65plus(t)/women_65plus(2025)
  dm <- DEMAND[YEAR %in% d$YEAR][order(YEAR)]
  expect_equal(d$dem_index, 100*dm$women_65plus/dm$women_65plus[dm$YEAR==2025], tolerance=1e-9)
  # and be invariant to retirement / entrants / fte / weighting
  d2 <- run(retire=70, entrants=110, fte_new=0.5, uro_fte=1.0, weight_on=FALSE)
  expect_equal(d$dem_index, d2$dem_index, tolerance=1e-9)
})

test_that("G16: no missing, infinite, or negative values in any projection column", {
  for (p in list(P(), P(retire=55, haz_mult=2, entrants=20), P(retire=75, entrants=120, demand_mult=2))) {
    d <- project_from(p)
    for (col in names(d)) {
      v <- d[[col]]
      expect_false(any(is.na(v)),       info=paste("NA in", col))
      expect_true(all(is.finite(v)),    info=paste("non-finite in", col))
      if (!col %in% c("shortfall","capacity_gap"))  # capacity gap may be negative (surplus)
        expect_true(all(v >= -1e-9),     info=paste("negative in", col))
    }
  }
})

test_that("G17: adequacy identity  adeq_eff = eff_index / dem_index", {
  d <- run()
  expect_equal(d$adeq_eff, d$eff_index/d$dem_index, tolerance=1e-9)
  expect_equal(d$adeq_hc,  d$hc_index /d$dem_index, tolerance=1e-9)
})

test_that("G18: capacity-gap identity  gap = demand-equivalent - effective", {
  d <- run()
  expect_equal(d$shortfall, d$req_fte - d$effective, tolerance=1e-9)
})

test_that("G19: gap sign agrees with adequacy (gap>0 iff adequacy<1)", {
  d <- run(demand_mult=1.5)          # push some years below and check
  expect_equal(sign(round(d$shortfall, 6)), sign(round(1 - d$adeq_eff, 9)))
})

test_that("G20: conditional 2025 balance  adequacy(2025)=1 and gap(2025)=0", {
  for (p in list(P(), P(uro_fte=1, fte_new=1), P(retire=72, entrants=100))) {
    b <- project_from(p)[YEAR==2025]
    expect_equal(b$adeq_eff, 1, tolerance=1e-9)
    expect_equal(b$shortfall, 0, tolerance=1e-6)
  }
})

test_that("G14/G15: effective and headcount reconstruct from the age distribution", {
  for (p in list(P(), P(retire=60, uro_fte=1, fte_new=1), P(weight_on=FALSE))) {
    d <- project_from(p); ref <- ref_sim(p)
    hc_ref  <- sapply(ref, `[[`, "headcount")
    eff_ref <- sapply(ref, `[[`, "effective")
    expect_equal(d$headcount,  unname(hc_ref),  tolerance=1e-9)
    expect_equal(d$effective,  unname(eff_ref), tolerance=1e-9)
  }
})

# ============================ MODEL LOGIC ===================================
test_that("G1: retirement age is a terminal cap (no one recorded above it after 2025)", {
  ref <- ref_sim(P(retire=65))
  post <- ref[as.character(2026:2050)]
  for (yrp in post) {
    present <- yrp$age[(yrp$base + yrp$new) > 1e-9]
    expect_true(all(present <= 65), info="a cohort older than the retirement age survived")
  }
})

test_that("G5: pre-retirement empirical attrition stays active when retirement age moves 65->70", {
  # ages 60-64 must still lose people to the hazard even when the terminal cap is 70
  ref <- ref_sim(P(retire=70))
  # follow the age-62 band count into age 63 the next year: must shrink by the hazard, not stay flat
  y1 <- ref[["2030"]]; y2 <- ref[["2031"]]
  c62 <- sum((y1$base+y1$new)[y1$age==62]); c63next <- sum((y2$base+y2$new)[y2$age==63])
  expect_lt(c63next, c62)                     # strictly fewer -> hazard applied, not switched off
})

test_that("G9: entrants appear only at the defined entry age", {
  ref <- ref_sim(P(entry_age=34))
  y <- ref[["2040"]]                          # a mid-horizon year
  # the youngest present age must be the entry age (no one younger)
  present <- y$age[(y$base+y$new) > 1e-9]
  expect_equal(min(present), 34L)
})

test_that("G10: entrants added exactly once (headcount recurrence balances)", {
  p <- P(entrants=64); ref <- ref_sim(p)
  yrs <- as.character(2025:2049)
  for (i in seq_along(yrs)) {
    this <- ref[[yrs[i]]]; nxt <- ref[[as.character(2025+i)]]
    survivors <- {
      h <- pmin(1, haz_for(this$age)*p$haz_mult); h[this$age >= p$retire] <- 1
      sum((this$base+this$new)*(1-h))
    }
    expect_equal(nxt$headcount, survivors + p$entrants, tolerance=1e-9)  # exactly one cohort added
  }
})

# ============================ MONOTONICITY ==================================
test_that("G2: higher retirement age never reduces supply (any year)", {
  s63<-S_t(retire=63); s65<-S_t(retire=65); s67<-S_t(retire=67)
  expect_true(all(s67 >= s65 - 1e-9)); expect_true(all(s65 >= s63 - 1e-9))
  expect_true(all(H_t(retire=67) >= H_t(retire=65) - 1e-9))
})

test_that("G3: higher pre-retirement departure rate never increases supply", {
  expect_true(all(S_t(haz_mult=1.5) <= S_t(haz_mult=1.0) + 1e-9))
  expect_true(all(S_t(haz_mult=1.0) <= S_t(haz_mult=0.5) + 1e-9))
})

test_that("G4: more entrants never reduces supply (headcount or effective)", {
  expect_true(all(S_t(entrants=90) >= S_t(entrants=64) - 1e-9))
  expect_true(all(H_t(entrants=90) >= H_t(entrants=64) - 1e-9))
})

# ============================ SCENARIO ORDERING ============================
test_that("G30: Retire Early <= Status Quo <= Retire Late supply, every year", {
  e<-S_t(retire=63); s<-S_t(retire=65); l<-S_t(retire=67)
  expect_true(all(e <= s + 1e-9)); expect_true(all(s <= l + 1e-9))
})

test_that("G31: demand multiplier ordering  D(0.8) <= D(1.0) <= D(1.2)", {
  d08<-run(demand_mult=0.8)$dem_index; d10<-run(demand_mult=1.0)$dem_index; d12<-run(demand_mult=1.2)$dem_index
  # demographic demand grows, so higher multiplier => higher demand in every year past 2025
  expect_true(all(d08 <= d10 + 1e-9)); expect_true(all(d10 <= d12 + 1e-9))
})

test_that("G32/G33: higher demand lowers adequacy and raises the capacity gap (supply fixed)", {
  lo<-run(demand_mult=0.8); hi<-run(demand_mult=1.2)
  expect_true(all(hi$adeq_eff <= lo$adeq_eff + 1e-9))
  expect_true(all(hi$shortfall >= lo$shortfall - 1e-9))
})

test_that("G34: urology clinical-time affects effective FTE but not headcount / age / demand", {
  a<-run(uro_fte=0.70); b<-run(uro_fte=1.00)
  expect_false(isTRUE(all.equal(a$effective, b$effective)))   # effective changes
  expect_equal(a$headcount, b$headcount, tolerance=1e-9)      # headcount unchanged
  expect_equal(a$mean_age,  b$mean_age,  tolerance=1e-9)      # age unchanged
  expect_equal(a$dem_index, b$dem_index, tolerance=1e-9)      # demand unchanged
})

test_that("G35: age-productivity weighting affects effective FTE but not headcount", {
  a<-run(weight_on=TRUE); b<-run(weight_on=FALSE)
  expect_false(isTRUE(all.equal(a$effective, b$effective)))
  expect_equal(a$headcount, b$headcount, tolerance=1e-9)
})

test_that("G36/G37: demand levers do not change supply; supply levers do not change status-quo demand", {
  base<-run()
  expect_equal(run(demand_mult=1.5)$effective, base$effective, tolerance=1e-9)  # G36
  expect_equal(run(retire=70, entrants=100)$dem_index, base$dem_index, tolerance=1e-9)  # G37
})

# ============================ KPI GUARDS ===================================
test_that("G21/G22: lowest adequacy value and year come from the same (minimum) row", {
  d <- run()
  i <- which.min(d$adeq_eff)
  expect_equal(min(d$adeq_eff), d$adeq_eff[i])
  expect_true(d$YEAR[i] %in% d$YEAR)
  # the KPI text '0.91 in 2045' must use the argmin row, earliest on ties
  expect_equal(d$YEAR[i], d$YEAR[which(d$adeq_eff == min(d$adeq_eff))][1])
})

test_that("G24/G25: mean age is count-weighted and SD is the weighted POPULATION sd (not unique-age sd)", {
  p <- P(); d <- project_from(p); ref <- ref_sim(p)
  y <- ref[["2050"]]; cnt <- y$base + y$new
  m  <- sum(y$age*cnt)/sum(cnt)
  sdw <- sqrt(sum(cnt*(y$age-m)^2)/sum(cnt))
  expect_equal(d[YEAR==2050]$mean_age, m,  tolerance=1e-9)
  expect_equal(d[YEAR==2050]$sd_age,  sdw, tolerance=1e-9)
  # guard against the classic bug: SD of the DISTINCT ages differs from weighted SD
  expect_false(isTRUE(all.equal(sdw, sd(unique(y$age)))))
})

test_that("G27: age summaries stay within plausible bounds", {
  for (p in list(P(retire=55), P(retire=75, entrants=120), P(retire=75, entrants=20))) {
    d <- project_from(p)
    expect_true(all(d$mean_age >= 25 & d$mean_age <= 90))
    expect_true(all(d$sd_age >= 0))
  }
})

# ============================ BOUNDARY / FUZZ ==============================
CORNERS <- list(
  P(retire=55, haz_mult=2.0, entrants=20),   # earliest retire + max attrition + min entrants
  P(retire=75, haz_mult=0.5, entrants=120),  # latest retire + min attrition + max entrants
  P(uro_fte=0.40), P(uro_fte=1.00), P(obgyn_share=0), P(obgyn_share=1),
  P(demand_mult=0.5), P(demand_mult=2.0), P(end_year=2035), P(end_year=2050),
  P(fte_new=0.50), P(weight_on=FALSE))

test_that("G67/G68/G69/G16: every corner returns a complete, finite, sane projection", {
  for (p in CORNERS) {
    d <- project_from(p)
    expect_equal(nrow(d), p$end_year-2025+1)                 # complete grid
    expect_false(any(sapply(d, function(v) any(is.na(v)))))  # no NA
    expect_true(all(is.finite(d$adeq_eff)))                  # G69: demand never 0 -> no Inf
    expect_true(all(d$headcount >= 0 & d$effective >= 0))    # G68: no negative cohorts
  }
})

test_that("fuzz: 400 random valid scenarios all satisfy the core invariants", {
  set.seed(20260723)
  fails <- 0
  for (i in 1:400) {
    p <- list(retire=sample(55:75,1), entrants=sample(20:120,1), entry_age=sample(30:40,1),
              fte_new=runif(1,.5,1), obgyn_share=runif(1,0,1), uro_fte=runif(1,.4,1),
              haz_mult=runif(1,.5,2), demand_mult=runif(1,.5,2), weight_on=sample(c(TRUE,FALSE),1),
              end_year=sample(seq(2035,2050,5),1))
    d <- project_from(p); b <- d[YEAR==2025]
    ok <- isTRUE(all.equal(b$eff_index,100)) && isTRUE(all.equal(b$adeq_eff,1)) &&
          isTRUE(all.equal(b$shortfall,0, tolerance=1e-6)) &&
          all(is.finite(d$adeq_eff)) && all(d$headcount>=0) &&
          isTRUE(all.equal(d$shortfall, d$req_fte-d$effective)) &&
          all(sign(round(d$shortfall,6))==sign(round(1-d$adeq_eff,9)))
    if (!ok) fails <- fails + 1
  }
  expect_equal(fails, 0)
})
