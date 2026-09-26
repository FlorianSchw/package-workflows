# The heading above a situation diagram, as a sentence: "When a pull
# request into dev is opened or updated", "When a pull request is closed",
# "On a push to dev", "On a schedule", … — the diagram's start box keeps
# the short form (describe_trigger()).
situation_title <- function(event, settings) {
  list_of <- function(x) paste(unlist(x), collapse = ", ")
  into <- if (!is.null(settings$branches)) sprintf(" into %s", list_of(settings$branches)) else ""
  switch(event,
    pull_request = , pull_request_target = {
      types <- unlist(settings$types)
      if (identical(types, "closed")) sprintf("When a pull request%s is closed", into)
      else if (length(types) > 0) sprintf("When a pull request%s is %s", into, list_of(types))
      else sprintf("When a pull request%s is opened or updated", into)
    },
    push = if (!is.null(settings$branches)) sprintf("On a push to %s", list_of(settings$branches)) else "On a push",
    schedule = "On a schedule",
    repository_dispatch = sprintf("When %s is sent", if (is.null(settings$types)) "a dispatch event" else sprintf("the %s event", list_of(settings$types))),
    workflow_run = sprintf("After %s", list_of(settings$workflows)),
    release = "When a release is published",
    describe_trigger(event, settings)
  )
}
