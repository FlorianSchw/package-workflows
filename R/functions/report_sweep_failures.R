# A sweep (all mode) has no PR to comment on, so its bad_test /
# env_misconfiguration failures are collected into one report instead:
# written to sweep_failures.md, which commit-updated-files appends to the
# sweep PR body — or, when no test passed and so no sweep PR will be
# opened, posted as a single issue so the report isn't only in the log.
# Capped below GitHub's 65536-character body limit.
report_sweep_failures <- function(reports, has_sweep_pr) {
  body <- paste(c("## Generated tests that failed", "", paste(reports, collapse = "\n\n---\n\n")), collapse = "\n")
  max_chars <- 60000
  if (nchar(body) > max_chars) {
    body <- paste0(substr(body, 1, max_chars), "\n\n… truncated — see the job log for the rest.")
  }

  if (has_sweep_pr) {
    writeLines(body, "sweep_failures.md")
  } else {
    post_github_json(
      sprintf("/repos/%s/issues", repo),
      list(title = "Test coverage sweep: generated tests failed", body = body),
      "sweep failure report"
    )
  }
}
