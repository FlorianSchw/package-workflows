# The situations the overview draws one diagram each for — "PR into dev",
# "PR into main", "PR closed", "On a schedule", … — with the workflows each
# one starts. A workflow appears in every situation it has a trigger for.
# Manual runs and calls from other workflows get no diagram (the summary
# table lists them). A dispatch or workflow_run situation is left out when
# all its workflows are already shown as started by another workflow
# (`chains`). Ordered by trigger_order(). Returns a list of
# list(title, members), members a named list, file -> note for the box
# (the path filter, or the schedule in words).
workflow_situations <- function(workflows, chains) {
  situations <- list()
  first_event <- character(0)
  for (wf in workflows) {
    for (e in setdiff(names(wf$triggers), c("workflow_dispatch", "workflow_call"))) {
      settings <- wf$triggers[[e]]
      if (e == "schedule") {
        title <- "On a schedule"
        crons <- vapply(settings, function(s) s$cron, character(1))
        note <- paste(vapply(crons, describe_cron, character(1)), collapse = ", ")
      } else {
        title <- describe_trigger(e, settings)
        note <- event_filter(settings)
      }
      if (is.null(situations[[title]])) {
        situations[[title]] <- list(title = title, members = list())
        first_event[title] <- e
      }
      situations[[title]]$members[[wf$file]] <- note
    }
  }

  chain_targets <- unique(vapply(chains, function(ch) ch$to, character(1)))
  keep <- vapply(names(situations), function(t) {
    !(first_event[[t]] %in% c("repository_dispatch", "workflow_run") && all(names(situations[[t]]$members) %in% chain_targets))
  }, logical(1))
  situations <- situations[keep]
  unname(situations[order(match(first_event[names(situations)], trigger_order(), nomatch = length(trigger_order()) + 1))])
}
