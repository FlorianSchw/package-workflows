# The full reason list Claude chooses from per task (tool schema enum).
# Which of them actually lead to a proposed change is configured as
# the accept-reasons input, else accept_reasons in config/claude.yml
# (accepted_reasons()) — see
# dev-notes/suggestion-thresholds.md.
suggestion_reasons <- function(task) {
  switch(task,
    roxygen = c("missing", "inaccurate", "incomplete", "clarity", "style"),
    tests   = c("uncovered_branch", "error_handling", "edge_case", "regression", "other"),
    stop(sprintf("Unknown suggestion task '%s'.", task))
  )
}
