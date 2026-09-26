# Publishes the test workflow's report (format_test_report()) — changes to
# existing tests, tests to look at, and failed generated tests (sweeps
# only; PR runs comment on them one by one). With a suggestion or sweep PR
# (has_pr), it is written to suggestion_report.md, which
# commit-updated-files appends to that PR's body. Without one, it goes to
# the originating PR as a comment, or in a sweep to a single issue, so it
# isn't only in the log. Capped below GitHub's 65536-character body limit.
publish_test_report <- function(body, has_pr) {
  max_chars <- 60000
  if (nchar(body) > max_chars) {
    body <- paste0(substr(body, 1, max_chars), "\n\n… truncated — see the job log for the rest.")
  }

  if (has_pr) {
    writeLines(body, "suggestion_report.md")
  } else if (is_sweep) {
    post_github_json(
      sprintf("/repos/%s/issues", repo),
      list(title = "Test coverage sweep: findings", body = body),
      "test report"
    )
  } else {
    post_github_json(sprintf("/repos/%s/issues/%s/comments", repo, pr_number), list(body = body), "test report")
  }
}
