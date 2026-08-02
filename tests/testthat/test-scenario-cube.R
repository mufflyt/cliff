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
  expect_setequal(REGISTRY_IDS, mufflyaccess::urps_scenario_ids())
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
