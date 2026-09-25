# One-line statistic of a roxygen suggestion run, e.g. "8 changes applied
# · 3 not applied · 1 possible bug" — for the link comment on the
# originating PR (suggestion_summary.md) and the top of the suggestion
# PR's description. Zero counts are left out. Same role as
# format_test_summary() for the test workflow.
format_roxygen_summary <- function(files, code_issue_files) {
  plural <- function(n, one, many) sprintf("%d %s", n, if (n == 1) one else many)
  n_applied <- sum(vapply(files, function(f) length(f$applied), integer(1)))
  n_dropped <- sum(vapply(files, function(f) length(f$dropped), integer(1)))
  n_bugs <- sum(vapply(code_issue_files, function(f) length(f$issues), integer(1)))
  parts <- c(
    if (n_applied > 0) plural(n_applied, "change applied", "changes applied"),
    if (n_dropped > 0) sprintf("%d not applied", n_dropped),
    if (n_bugs > 0) plural(n_bugs, "possible bug", "possible bugs")
  )
  if (length(parts) == 0) return("no changes")
  paste(parts, collapse = " · ")
}
