# When a job runs, in words, for the outcomes it produces: its own `if:`
# ("if check fails" for `needs.check.result == 'failure'`, else
# describe_condition()), plus a condition shared by all jobs of the
# reusable workflow it calls — e.g. cleanup-suggestion-branch.yml only
# runs "only for PRs from bot-suggest/ branches". "" if it always runs.
job_run_condition <- function(job, called) {
  words <- c(success = "succeeds", failure = "fails", cancelled = "is cancelled", always = "finishes")
  parts <- character(0)

  cond <- job_condition(job)
  needs <- unlist(job$needs)
  if (!is.na(cond$edge_label)) {
    what <- if (cond$edge_label %in% names(words)) words[[cond$edge_label]] else cond$edge_label
    parts <- c(parts, sprintf("if %s %s", paste(needs, collapse = " and "), what))
  }
  if (!is.na(cond$note)) parts <- c(parts, cond$note)

  ref <- parse_workflow_ref(job$uses)
  inner <- if (!is.null(ref)) called[[ref$key]]$workflow else NULL
  if (!is.null(inner) && length(inner$jobs) > 0) {
    notes <- unique(vapply(inner$jobs, function(ij) {
      n <- job_condition(ij)$note
      if (is.na(n)) "" else n
    }, character(1)))
    if (length(notes) == 1 && nzchar(notes)) parts <- c(parts, notes)
  }
  paste(parts, collapse = ", ")
}
