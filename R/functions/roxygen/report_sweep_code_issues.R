# Reports possible code bugs from a roxygen sweep that has no suggestion
# PR to put them in: as an issue "Roxygen sweep: possible bugs in the code
# (YYYY-MM)", so they don't end up only in the job log. A rerun in the
# same month adds its findings to that month's open issue as a comment
# instead of opening a second issue (post_issue_once()). Needs
# `issues: write` in the caller.
report_sweep_code_issues <- function(bugs) {
  title <- sprintf("Roxygen sweep: possible bugs in the code (%s)", format(Sys.Date(), "%Y-%m"))
  post_issue_once(title, bugs, "possible code bugs (sweep)")
}
