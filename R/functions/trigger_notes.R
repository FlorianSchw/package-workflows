# Small print for a workflow's box in the overview: the path filter of its
# main trigger ("only R/**", "not docs/**") and its other triggers ("also:
# weekly (Mon) · manual"). More than two paths are shortened to the first
# two plus a count. Returns "" when there is nothing to add.
trigger_notes <- function(workflow, main) {
  paths_text <- function(paths) {
    paths <- unlist(paths)
    shown <- paste(utils::head(paths, 2), collapse = ", ")
    if (length(paths) > 2) sprintf("%s (+%d)", shown, length(paths) - 2) else shown
  }

  settings <- workflow$triggers[[main]]
  notes <- character(0)
  if (!is.null(settings$paths)) notes <- c(notes, sprintf("only %s", paths_text(settings$paths)))
  if (!is.null(settings[["paths-ignore"]])) notes <- c(notes, sprintf("not %s", paths_text(settings[["paths-ignore"]])))

  others <- setdiff(names(workflow$triggers), main)
  if (length(others) > 0) {
    also <- vapply(others, function(e) {
      text <- if (e == "workflow_dispatch") "manual" else describe_trigger(e, workflow$triggers[[e]])
      paste0(tolower(substr(text, 1, 1)), substring(text, 2))
    }, character(1))
    notes <- c(notes, sprintf("also: %s", paste(also, collapse = " · ")))
  }
  paste(notes, collapse = " · ")
}
