# Reports possible code bugs from a roxygen sweep that has no suggestion
# PR to put them in: as an issue "Roxygen sweep: possible bugs in the code
# (YYYY-MM)", so they don't end up only in the job log. A rerun in the
# same month adds its findings to that month's open issue as a comment
# (comment_once(): an identical one isn't posted again) instead of opening
# a second issue. Needs `issues: write` in the caller.
report_sweep_code_issues <- function(bugs) {
  title <- sprintf("Roxygen sweep: possible bugs in the code (%s)", format(Sys.Date(), "%Y-%m"))
  open <- get_github_json(sprintf("/repos/%s/issues?state=open&per_page=100", repo))
  existing <- Find(function(i) identical(i$title, title) && is.null(i$pull_request), open)
  if (is.null(existing)) {
    post_github_json(sprintf("/repos/%s/issues", repo), list(title = title, body = bugs), "possible code bugs (sweep)")
  } else {
    comment_once(existing$number, bugs, "possible code bugs (sweep)")
  }
}
