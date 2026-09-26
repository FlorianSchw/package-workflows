# A job's `if:` split for the detail diagram: a condition that only checks
# the result of one job it needs (`needs.check.result == 'success'`, or the
# status functions success() / failure() / always()) becomes the label of
# the arrow from that job — `edge_label`; anything else is shown as small
# print in the job's box — `note`, cut at 60 characters.
job_condition <- function(job) {
  cond <- if (is.null(job[["if"]])) "" else trimws(gsub("^\\$\\{\\{\\s*|\\s*\\}\\}$", "", as.character(job[["if"]])))
  if (!nzchar(cond)) return(list(edge_label = NA, note = NA))

  result <- regmatches(cond, regexec("^needs\\.[A-Za-z0-9_-]+\\.result\\s*==\\s*'([a-z]+)'$", cond))[[1]]
  if (length(result) == 2) return(list(edge_label = result[2], note = NA))
  status <- regmatches(cond, regexec("^(success|failure|always|cancelled)\\(\\)$", cond))[[1]]
  if (length(status) == 2) return(list(edge_label = status[2], note = NA))

  short <- if (nchar(cond) > 60) paste0(substr(cond, 1, 57), "...") else cond
  list(edge_label = NA, note = sprintf("if: %s", short))
}
