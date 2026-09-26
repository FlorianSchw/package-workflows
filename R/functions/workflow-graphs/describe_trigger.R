# One trigger (event + its settings from the workflow's `on:`) in words:
# "PR into dev", "PR closed", "Push to main", "Manual run",
# "Dispatch: release-publish", "Monthly (day 1)", … Used for the lanes of
# the overview and the start box of each detail diagram. Path filters are
# not part of it, see trigger_notes().
describe_trigger <- function(event, settings) {
  list_of <- function(x) paste(unlist(x), collapse = ", ")
  switch(event,
    pull_request = , pull_request_target = {
      types <- unlist(settings$types)
      if (identical(types, "closed")) return("PR closed")
      what <- if (length(types) > 0) sprintf("PR %s", list_of(types)) else "PR"
      if (!is.null(settings$branches)) sprintf("%s into %s", what, list_of(settings$branches)) else what
    },
    push = {
      if (!is.null(settings$branches)) sprintf("Push to %s", list_of(settings$branches))
      else if (!is.null(settings$tags)) "Tag push"
      else "Push"
    },
    schedule = {
      crons <- vapply(settings, function(s) s$cron, character(1))
      text <- if (length(crons) == 1) describe_cron(crons) else "on a schedule"
      paste0(toupper(substr(text, 1, 1)), substring(text, 2))
    },
    workflow_dispatch = "Manual run",
    repository_dispatch = if (is.null(settings$types)) "Dispatch" else sprintf("Dispatch: %s", list_of(settings$types)),
    workflow_run = sprintf("After: %s", list_of(settings$workflows)),
    workflow_call = "Called by other workflows",
    release = if (is.null(settings$types)) "Release" else sprintf("Release %s", list_of(settings$types)),
    event
  )
}
