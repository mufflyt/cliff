# Consistency / single-source-of-truth guards.
# Reproduces the failure mode from the screenshots — a model that is numerically
# correct while the interface describes a DIFFERENT scenario — and proves it
# cannot occur: every narrative/KPI value must equal the canonical scenario_summary()
# built from the canonical projection, and carry the matching scenario fingerprint.

suppressPackageStartupMessages({ library(testthat); library(shiny); library(data.table) })

APP_DIR <- Find(function(d) file.exists(file.path(d,"app.R")),
                c(".", "../..", "../../..", "cliff/shiny_urps_adequacy"))
source(Find(file.exists, c(file.path(APP_DIR,"model.R"), "model.R", "../../model.R")))
strip <- function(x) gsub("[ ]+"," ", gsub("<[^>]+>"," ", paste(unlist(x), collapse=" ")))
as_params <- function(s) list(retire=s$retire, entrants=s$entrants, entry_age=s$entry_age,
  fte_new=s$fte_new/100, obgyn_share=s$ob_share/100, uro_fte=s$uro_fte/100,
  haz_mult=s$haz_mult, demand_mult=s$demand_mult, weight_on=s$weight_on, end_year=s$end_year)

SCN <- list(
  reference   = list(retire=65,fte_new=90,ob_share=77,uro_fte=70,entrants=64,haz_mult=1,demand_mult=1,entry_age=34,weight_on=TRUE,end_year=2050,band_var="retire"),
  higher_entr = list(retire=65,fte_new=90,ob_share=77,uro_fte=70,entrants=80,haz_mult=1,demand_mult=1,entry_age=34,weight_on=TRUE,end_year=2050,band_var="retire"),
  surplus     = list(retire=70,fte_new=100,ob_share=100,uro_fte=100,entrants=90,haz_mult=0.8,demand_mult=0.9,entry_age=34,weight_on=TRUE,end_year=2050,band_var="entrants"),
  deficit     = list(retire=60,fte_new=60,ob_share=50,uro_fte=50,entrants=30,haz_mult=1.6,demand_mult=1.5,entry_age=34,weight_on=TRUE,end_year=2040,band_var="demand"))

for (nm in names(SCN)) local({
  s <- SCN[[nm]]
  test_that(paste("SSOT:", nm, "— narrative & KPIs equal the canonical summary, right label"), {
    p  <- as_params(s); d <- project_from(p); sv <- scenario_summary(d, p)
    testServer(shiny::shinyAppDir(APP_DIR), {
      do.call(session$setInputs, s)
      rt <- strip(output$readout)
      # narrative scenario values == the active slider inputs (catches the stale-label bug)
      expect_true(grepl(sprintf("%s entrants", format(s$entrants, big.mark=",")), rt, fixed=TRUE), info="entrants")
      expect_true(grepl(sprintf("%d%% new-physician", s$fte_new), rt, fixed=TRUE), info="fte")
      expect_true(grepl(sprintf("retirement at %d", s$retire), rt, fixed=TRUE), info="retire")
      # narrative numbers == canonical summary
      expect_true(grepl(sprintf("grows %+.0f%% while", sv$eff_growth_pct), rt, fixed=TRUE), info="eff growth")
      expect_true(grepl(sprintf("supplies %d%% of", sv$met_pct), rt, fixed=TRUE), info="met%")
      expect_true(grepl(sprintf("tightest point in %d (%d%%)", sv$trough_year, sv$trough_pct), rt, fixed=TRUE), info="trough")
      # label: Reference only when inputs == defaults, else Current
      expect_true(grepl(if (sv$is_reference) "Reference scenario" else "Current scenario", rt))
      # KPI cards == canonical summary
      expect_true(grepl(formatC(round(sv$effective_end), big.mark=",", format="d"), strip(output$kpi_eff)))
      expect_true(grepl(sprintf("%d%%", sv$met_pct), strip(output$kpi_adeq)))
      expect_true(grepl(as.character(sv$trough_year), strip(output$kpi_trough)))
      expect_true(grepl(sprintf("%.1f years", sv$mean_age_end), strip(output$kpi_age)))
      # fingerprint shown == projection fingerprint
      expect_true(grepl(sv$fingerprint, strip(output$fp), fixed=TRUE))
    })
  })
})

# ---- fingerprint covers every model-changing input --------------------------
test_that("fingerprint changes when ANY model-changing input changes", {
  base <- scenario_fp(DEFAULTS)
  for (chg in list(list(retire=66), list(entrants=65), list(entry_age=35), list(fte_new=0.91),
                   list(obgyn_share=0.80), list(uro_fte=0.71), list(haz_mult=1.1),
                   list(demand_mult=1.1), list(weight_on=FALSE), list(end_year=2045)))
    expect_false(identical(base, scenario_fp(modifyList(DEFAULTS, chg))), info=names(chg))
})

# ---- reference classification requires EXACT equality -----------------------
test_that("is_reference_scenario is TRUE only for the exact defaults", {
  expect_true(is_reference_scenario(DEFAULTS))
  for (chg in list(list(retire=66), list(entrants=80), list(fte_new=1.0), list(uro_fte=0.71),
                   list(demand_mult=1.1), list(end_year=2045)))
    expect_false(is_reference_scenario(modifyList(DEFAULTS, chg)), info=names(chg))
})

# ---- contract validator catches stale summaries -----------------------------
test_that("validate_scenario_contract rejects stale label / trough / value / fingerprint", {
  p <- modifyList(DEFAULTS, list(entrants=80)); d <- project_from(p); s <- scenario_summary(d, p)
  expect_invisible(validate_scenario_contract(d, p, s))                       # clean passes
  expect_error(validate_scenario_contract(d, p, modifyList(s, list(is_reference=TRUE))),  "reference")
  expect_error(validate_scenario_contract(d, p, modifyList(s, list(trough_year=9999))),   "trough year")
  expect_error(validate_scenario_contract(d, p, modifyList(s, list(effective_end=1))),    "effective")
  expect_error(validate_scenario_contract(d, p, modifyList(s, list(fingerprint="x"))),    "fingerprint")
})

# ---- reset reproduces the reference fingerprint -----------------------------
test_that("the documented reset target reproduces the reference fingerprint", {
  reset_target <- list(retire=65, entrants=64, entry_age=34, fte_new=0.90,
    obgyn_share=OB_BASE_SHARE, uro_fte=URO_FTE_DEFAULT, haz_mult=1.0, demand_mult=1.0,
    weight_on=TRUE, end_year=2050)
  expect_equal(scenario_fp(reset_target), scenario_fp(DEFAULTS))
  expect_true(is_reference_scenario(reset_target))
})

# ---- randomized: summary always reconstructs & contract always holds --------
test_that("fuzz: 300 random scenarios — summary reconstructs and contract passes", {
  set.seed(424242); fails <- 0
  for (i in 1:300) {
    p <- list(retire=sample(55:75,1), entrants=sample(20:120,1), entry_age=sample(30:45,1),
              fte_new=runif(1,.5,1), obgyn_share=runif(1,0,1), uro_fte=runif(1,0,1),
              haz_mult=runif(1,.5,2), demand_mult=runif(1,.5,2), weight_on=sample(c(TRUE,FALSE),1),
              end_year=sample(seq(2035,2050,5),1))
    d <- project_from(p); s <- scenario_summary(d, p)
    ok <- tryCatch({ validate_scenario_contract(d, p, s)
      e <- d[YEAR==p$end_year]
      isTRUE(all.equal(s$effective_end, e$effective)) &&
      isTRUE(all.equal(s$adequacy_end, e$adeq_eff)) &&
      isTRUE(all.equal(s$capacity_gap_end, e$capacity_gap)) &&
      identical(s$fingerprint, attr(d,"scenario_fp")) }, error=function(e) FALSE)
    if (!ok) fails <- fails + 1
  }
  expect_equal(fails, 0)
})
