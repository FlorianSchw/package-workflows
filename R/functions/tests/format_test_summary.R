# One-line statistic of the open test findings, e.g. "7 new tests ·
# 1 existing test updated · 1 existing test deleted · DSLite test setup
# created (`tests/testthat/setup.R`) · testthat set up (`tests/testthat.R`,
# `DESCRIPTION`) · 1 possible bug" — for the link comment on the originating PR and the top
# of the suggestion PR's description. Crossed-out findings and zero counts
# are left out. `state` from merge_test_findings().
format_test_summary <- function(state) {
  open <- Filter(function(e) identical(e$status, "active"), state$entries)
  n <- function(kind) sum(vapply(open, function(e) identical(e$kind, kind), logical(1)))
  plural <- function(k, one, many) sprintf("%d %s", k, if (k == 1) one else many)
  files <- function(x) paste0("`", x, "`", collapse = ", ")
  setups <- vapply(Filter(function(e) identical(e$kind, "setup"), open), function(e) e$file, character(1))
  dslite <- setups[grepl("^setup", basename(setups))]
  testthat <- setdiff(setups, dslite)
  parts <- c(
    if (n("new") > 0) plural(n("new"), "new test", "new tests"),
    if (n("updated") > 0) plural(n("updated"), "existing test updated", "existing tests updated"),
    if (n("deleted") > 0) plural(n("deleted"), "existing test deleted", "existing tests deleted"),
    if (length(dslite) > 0) sprintf("DSLite test setup created (%s)", files(dslite)),
    if (length(testthat) > 0) sprintf("testthat set up (%s)", files(testthat)),
    if (n("bug") > 0) plural(n("bug"), "possible bug", "possible bugs")
  )
  if (length(parts) == 0) return("no changes")
  paste(parts, collapse = " · ")
}
