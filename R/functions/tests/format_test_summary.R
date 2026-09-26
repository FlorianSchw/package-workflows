# One-line statistic of a test suggestion run, e.g. "7 new tests ·
# 1 existing test updated · 1 existing test deleted · DSLite test setup
# created (`tests/testthat/setup.R`) · testthat set up (`tests/testthat.R`,
# `DESCRIPTION`)". Zero counts are left out. `counts` is a named vector
# (new, updated, deleted), `created_setups` the DSLite setup files and
# `testthat_setup` the files ensure_testthat_setup() created or changed.
format_test_summary <- function(counts, created_setups = character(0), testthat_setup = character(0)) {
  plural <- function(n, one, many) sprintf("%d %s", n, if (n == 1) one else many)
  files <- function(x) paste0("`", x, "`", collapse = ", ")
  parts <- c(
    if (counts[["new"]] > 0) plural(counts[["new"]], "new test", "new tests"),
    if (counts[["updated"]] > 0) plural(counts[["updated"]], "existing test updated", "existing tests updated"),
    if (counts[["deleted"]] > 0) plural(counts[["deleted"]], "existing test deleted", "existing tests deleted"),
    if (length(created_setups) > 0) sprintf("DSLite test setup created (%s)", files(created_setups)),
    if (length(testthat_setup) > 0) sprintf("testthat set up (%s)", files(testthat_setup))
  )
  if (length(parts) == 0) return("no changes")
  paste(parts, collapse = " · ")
}
