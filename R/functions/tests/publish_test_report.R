# Publishes the test workflow's report (format_test_report()) — new tests,
# changes to existing tests, tests to look at, and failed generated tests
# (sweeps and pushes without a PR; PR runs comment on them one by one).
# With a suggestion or sweep PR, or an open bot PR (has_pr), it is written
# to suggestion_report.md, which commit-updated-files makes that PR's
# description (pr-body-mode "replace"). Without one, it goes to the
# originating PR as a comment, or in a sweep to a single issue (a comment
# on it while it is open, post_issue_once()), so it isn't only in the log — without the hidden state, which only a bot PR
# carries. Capped below GitHub's 65536-character body limit.
publish_test_report <- function(body, has_pr) {
  if (!has_pr) body <- sub("\n*<!-- bot-suggest-state: [A-Za-z0-9+/=]+ -->\\s*$", "", body)
  max_chars <- 60000
  if (nchar(body) > max_chars) {
    body <- paste0(substr(body, 1, max_chars), "\n\n… truncated — see the job log for the rest.")
  }

  if (has_pr) {
    writeLines(body, "suggestion_report.md")
  } else if (is_sweep) {
    post_issue_once("Test coverage sweep: findings", body, "test report")
  } else {
    post_github_json(sprintf("/repos/%s/issues/%s/comments", repo, pr_number), list(body = body), "test report")
  }
}
