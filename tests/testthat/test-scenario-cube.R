# The scenario cube must conform to the mufflyaccess projection contract and cover
# the full registry of 9 scenarios exactly once per (pathway, geography, year).
# The structural checks run without mufflyaccess; the contract/registry ties run
# only when mufflyaccess >= 0.10.0 (the projection contract) is installed.
suppressWarnings(suppressMessages(library(testthat)))

repo_root <- function() {
  d <- normalizePath(getwd(), winslash = "/")
  for (i in 1:8) { if (file.exists(file.path(d, "DESCRIPTION"))) return(d)
                   p <- dirname(d); if (identical(p, d)) break; d <- p }
  getwd()
}
cube_path <- file.path(repo_root(), "data", "workforce_scenario_cube.csv")

# the nine registry scenario_ids (mirror of mufflyaccess::urps_scenario_ids())
REGISTRY_IDS <- c("baseline", "retire_2yr_earlier", "retire_5yr_earlier",
                  "retire_2yr_later", "fellowship_plus_10pct", "fellowship_constrained",
                  "lower_late_career_fte", "combined_pessimistic", "combined_investment")

test_that("the cube carries the projection-contract schema", {
  skip_if_not(file.exists(cube_path), "cube not generated")
  d <- utils::read.csv(cube_path, stringsAsFactors = FALSE)
  expect_setequal(names(d),
    c("year", "scenario_id", "specialty", "certification_pathway", "geography_type",
      "geography_id", "supply_headcount", "supply_clinical_fte", "lower_95", "upper_95",
      "entrants", "exits", "net_change"))
  expect_true(all(d$certification_pathway %in% c("ABOG", "ABU_NET_NEW", "ABOG_PLUS_ABU")))
  expect_true(all(d$geography_type %in% c("national", "conus")))
  expect_true(all(d$specialty == "URPS"))
})

test_that("all 9 registry scenarios are represented exactly once per (pathway, geography, year)", {
  skip_if_not(file.exists(cube_path), "cube not generated")
  d <- utils::read.csv(cube_path, stringsAsFactors = FALSE)
  expect_setequal(unique(d$scenario_id), REGISTRY_IDS)
  # exactly one row per full key -> each scenario appears 3 pathways x 2 geo x 18 yr = 108
  key <- paste(d$year, d$scenario_id, d$certification_pathway, d$geography_type, sep = "|")
  expect_false(anyDuplicated(key) > 0)
  expect_true(all(table(d$scenario_id) == 3L * 2L * 18L))
})

test_that("combined = ABOG + ABU_NET_NEW (additive) within tolerance", {
  skip_if_not(file.exists(cube_path), "cube not generated")
  d <- utils::read.csv(cube_path, stringsAsFactors = FALSE)
  w <- reshape(d[, c("year","scenario_id","geography_type","certification_pathway","supply_headcount")],
               idvar = c("year","scenario_id","geography_type"),
               timevar = "certification_pathway", direction = "wide")
  hc <- function(p) w[[paste0("supply_headcount.", p)]]
  expect_true(all(abs(hc("ABOG_PLUS_ABU") - (hc("ABOG") + hc("ABU_NET_NEW"))) <= 1))
})

test_that("net_change reconciles as entrants - exits (contract flow identity)", {
  skip_if_not(file.exists(cube_path), "cube not generated")
  d <- utils::read.csv(cube_path, stringsAsFactors = FALSE)
  ok <- is.na(d$net_change) | is.na(d$entrants) | is.na(d$exits) |
        abs(d$net_change - (d$entrants - d$exits)) < 1e-6
  expect_true(all(ok))
})

test_that("clinical FTE never exceeds headcount in any cell (a head is at most 1.0 FTE)", {
  skip_if_not(file.exists(cube_path), "cube not generated")
  d <- utils::read.csv(cube_path, stringsAsFactors = FALSE)
  # The model invariant, stated positively: clinical FTE is measured in units of a
  # peak-age, full-clinical-time provider, and both factors that build it
  # (rel_to_peak and the pathway clinical-time share) are in [0, 1]. So per-head
  # FTE is <= 1 by construction, in EVERY pathway/geography/scenario/year cell,
  # not merely in aggregate. mufflyaccess::validate_urps_projection enforces the
  # same rule; this guard catches a break without needing that package installed.
  #
  # A global scale that pinned combined-national-2023 FTE to that cell's headcount
  # used to violate this: it is unsatisfiable when the ABU clinical-time share is
  # 0.70, so the ABOG component absorbed the residual at 1.068 FTE/head and 59 of
  # 972 rows exceeded headcount. Do not reintroduce a normalisation that targets a
  # combined total; normalise per head or not at all.
  expect_true(all(d$supply_clinical_fte <= d$supply_headcount))
  expect_lte(max(d$supply_clinical_fte / d$supply_headcount), 1)
  expect_true(all(d$supply_clinical_fte >= 0))
})

test_that("clinical FTE stays additive across pathways", {
  skip_if_not(file.exists(cube_path), "cube not generated")
  d <- utils::read.csv(cube_path, stringsAsFactors = FALSE)
  key <- function(x) paste(x$year, x$scenario_id, x$geography_type)
  a <- d[d$certification_pathway == "ABOG", ]
  b <- d[d$certification_pathway == "ABU_NET_NEW", ]
  k <- d[d$certification_pathway == "ABOG_PLUS_ABU", ]
  i <- match(key(k), key(a)); j <- match(key(k), key(b))
  # combined == ABOG + ABU, to the 0.1 the cube is written at (the +1e-9 keeps a
  # deviation of exactly 0.1 from failing on binary representation)
  expect_lte(max(abs(a$supply_clinical_fte[i] + b$supply_clinical_fte[j] -
                       k$supply_clinical_fte)), 0.1 + 1e-9)
  # Headcounts are rounded per pathway independently, so the parts can miss the
  # rounded whole by 1 in a projected year. Exact at the 2023 anchor, which is
  # the cell tied to the SSOT.
  expect_lte(max(abs(a$supply_headcount[i] + b$supply_headcount[j] -
                       k$supply_headcount)), 1L)
  is23 <- k$year == 2023
  expect_equal(a$supply_headcount[i][is23] + b$supply_headcount[j][is23],
               k$supply_headcount[is23])
})

test_that("the 2023 baseline combined cells equal the SSOT active counts", {
  skip_if_not(file.exists(cube_path), "cube not generated")
  d <- utils::read.csv(cube_path, stringsAsFactors = FALSE)
  base23 <- function(g) d$supply_headcount[d$year == 2023 & d$scenario_id == "baseline" &
                          d$certification_pathway == "ABOG_PLUS_ABU" & d$geography_type == g]
  expect_equal(base23("national"), 1306)
  expect_equal(base23("conus"), 1303)
})

test_that("the builder's scenario levers match the mufflyaccess registry", {
  skip_if_not(requireNamespace("mufflyaccess", quietly = TRUE) &&
                utils::packageVersion("mufflyaccess") >= "0.9.0" &&
                "urps_scenarios" %in% getNamespaceExports("mufflyaccess"),
              "requires mufflyaccess >= 0.9.0 (scenario registry)")
  # This cube is a SUPPLY projection: it varies retirement timing, entry and
  # late-career FTE. mufflyaccess 0.10.0 added five family == "demand" scenarios
  # that move the demand side only and carry requires_demand_model == TRUE; they
  # are out of scope for a supply cube. Tie to the supply subset, derived from
  # the registry rather than re-listed here, so a future supply lever added
  # upstream still fails this guard.
  reg <- mufflyaccess::urps_scenarios()
  expect_setequal(REGISTRY_IDS, reg$scenario_id[!reg$requires_demand_model])
  # every demand scenario is genuinely absent from the cube, not silently dropped
  expect_length(intersect(REGISTRY_IDS, reg$scenario_id[reg$requires_demand_model]), 0L)
})

test_that("the cube passes the mufflyaccess projection contract (validate + baseline_tie)", {
  skip_if_not(file.exists(cube_path), "cube not generated")
  skip_if_not(requireNamespace("mufflyaccess", quietly = TRUE) &&
                utils::packageVersion("mufflyaccess") >= "0.10.0" &&
                "validate_urps_projection" %in% getNamespaceExports("mufflyaccess"),
              "requires mufflyaccess >= 0.10.0 (projection contract)")
  d <- utils::read.csv(cube_path, stringsAsFactors = FALSE)
  expect_true(mufflyaccess::validate_urps_projection(d))
  expect_true(mufflyaccess::validate_urps_projection(
    d, baseline_tie = list(year = 2023, measure = "board_certified_active",
                           geography_type = "national", certification_pathway = "ABOG_PLUS_ABU")))
})
