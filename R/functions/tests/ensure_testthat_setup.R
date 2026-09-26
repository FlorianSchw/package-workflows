# Makes sure R CMD check actually runs the proposed tests: without
# tests/testthat.R it ignores tests/testthat/ entirely, and testthat must
# be a declared dependency. Creates tests/testthat.R if missing, adds
# testthat (>= 3.0.0) to Suggests if it isn't a dependency yet, and sets
# Config/testthat/edition: 3 — the latter only when tests/testthat.R is
# created fresh, since switching the edition of an existing test suite can
# change how its tests behave. Returns the paths it changed.
ensure_testthat_setup <- function(package_name) {
  changed <- character(0)

  runner <- file.path("tests", "testthat.R")
  fresh <- !file.exists(runner)
  if (fresh) {
    writeLines(c(
      "# Runs the tests in tests/testthat/ during R CMD check.",
      "# Standard testthat setup (see https://testthat.r-lib.org/articles/special-files.html).",
      "",
      "library(testthat)",
      sprintf("library(%s)", package_name),
      "",
      sprintf("test_check(\"%s\")", package_name)
    ), runner)
    changed <- c(changed, runner)
  }

  d <- desc::description$new("DESCRIPTION")
  deps <- d$get_deps()
  description_changed <- FALSE
  if (!"testthat" %in% deps$package) {
    d$set_dep("testthat", "Suggests", ">= 3.0.0")
    description_changed <- TRUE
  }
  if (fresh && !d$has_fields("Config/testthat/edition")) {
    d$set("Config/testthat/edition", "3")
    description_changed <- TRUE
  }
  if (description_changed) {
    d$write("DESCRIPTION")
    changed <- c(changed, "DESCRIPTION")
  }

  changed
}
