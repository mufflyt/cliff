# =============================================================================
# Helpers that were never ported out of mufflyt/isochrones
# =============================================================================
# cliff was extracted from the isochrones pipeline, and seven helpers came along
# as `source(here::here(...))` calls rather than as code. The files they point at
# do not exist in this repository:
#
#   R/utils/load_paths.R            load_paths()
#   R/freida_program_loader.R       load_freida_programs(), find_nearest_program()
#   R/utils/sql_state_normalize.R   sql_state_normalize()
#   R/utils/extract_year_safely.R   extract_year_safely()
#   R/string_normalization.R        normalize_string()
#   R/deduplicate_abog_data.R       deduplicate_abog_data()
#
# Two of those source() calls were at TOP LEVEL, so R executed them while
# building the package. R CMD INSTALL therefore failed at lazy-load and cliff
# could not be installed at all -- every function in the package was unavailable
# because of two lines in one file.
#
# A top-level source() is wrong in package code even when the file exists: the
# working directory here::here() resolves against does not exist for an
# installed package, so it can only ever work from a source checkout.
#
# WHY STUBS RATHER THAN COPIES. All seven still live in mufflyt/isochrones. This
# ecosystem has been repeatedly damaged by the same helper existing in several
# repositories, where load order decides which one runs and a fix applied to one
# is a fix applied to none -- see mysterymaps, which had five such duplicates,
# and the gender gate, which had three. Copying these in would add seven more.
#
# So each is defined here only if something else has not already defined it, and
# each fails at CALL time with a message naming the function and where it lives.
# The package installs; the functions that depend on these fail loudly and
# specifically instead of taking the whole package down at build.
#
# TO MAKE THEM WORK, pick one and do it deliberately:
#   1. Port the file from isochrones into this package, with its tests, and
#      delete the corresponding stub. Then isochrones should import it back, so
#      there is still one definition.
#   2. Or source the isochrones file through a path dependency that fails loudly
#      (see midwifery/R/lib/isochrones_dep.R for that pattern).
# =============================================================================

.cliff_unported <- function(fn, file) {
  force(fn); force(file)
  function(...) {
    stop(sprintf(
      paste0("%s() was never ported into cliff.\n",
             "It lives in mufflyt/isochrones at %s.\n",
             "Port that file into this package and delete the stub in ",
             "R/unported_helpers.R, or source it through a path dependency. ",
             "See the header of that file."),
      fn, file), call. = FALSE)
  }
}

if (!exists("load_paths", mode = "function"))
  load_paths <- .cliff_unported("load_paths", "R/utils/load_paths.R")

if (!exists("load_freida_programs", mode = "function"))
  load_freida_programs <- .cliff_unported("load_freida_programs",
                                          "R/freida_program_loader.R")

if (!exists("find_nearest_program", mode = "function"))
  find_nearest_program <- .cliff_unported("find_nearest_program",
                                          "R/freida_program_loader.R")

if (!exists("sql_state_normalize", mode = "function"))
  sql_state_normalize <- .cliff_unported("sql_state_normalize",
                                         "R/utils/sql_state_normalize.R")

if (!exists("extract_year_safely", mode = "function"))
  extract_year_safely <- .cliff_unported("extract_year_safely",
                                         "R/utils/extract_year_safely.R")

if (!exists("normalize_string", mode = "function"))
  normalize_string <- .cliff_unported("normalize_string",
                                      "R/string_normalization.R")

if (!exists("deduplicate_abog_data", mode = "function"))
  deduplicate_abog_data <- .cliff_unported("deduplicate_abog_data",
                                           "R/deduplicate_abog_data.R")
