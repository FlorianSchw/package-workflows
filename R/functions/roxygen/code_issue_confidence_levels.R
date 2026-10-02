# The confidence levels of possible code bugs to report
# (kept_code_issues()): the code-issue-confidence input ("high",
# "high,medium", …) if set, else code_issue_confidence in
# config/claude.yml, else high and medium. Stops the run on an unknown
# level, so a typo fails loudly instead of silently hiding bugs.
code_issue_confidence_levels <- function(input, configured) {
  levels <- if (nzchar(trimws(input))) {
    trimws(strsplit(input, ",", fixed = TRUE)[[1]])
  } else if (!is.null(configured)) {
    unlist(configured)
  } else {
    c("high", "medium")
  }
  levels <- levels[nzchar(levels)]
  unknown <- setdiff(levels, c("high", "medium", "low"))
  if (length(unknown) > 0 || length(levels) == 0) {
    stop(sprintf("code-issue-confidence is '%s' — use high, medium and/or low, separated by commas.", input), call. = FALSE)
  }
  levels
}
