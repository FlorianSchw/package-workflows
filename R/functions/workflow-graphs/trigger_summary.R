# All triggers of a workflow in one line, in trigger_order(), for the
# summary table: "PR into dev (only R/**) · Monthly (day 1) · Manual run".
trigger_summary <- function(workflow) {
  events <- names(workflow$triggers)
  events <- events[order(match(events, trigger_order(), nomatch = length(trigger_order()) + 1))]
  parts <- vapply(events, function(e) {
    settings <- workflow$triggers[[e]]
    filter <- event_filter(settings)
    text <- describe_trigger(e, settings)
    if (nzchar(filter)) sprintf("%s (%s)", text, filter) else text
  }, character(1))
  paste(parts, collapse = " · ")
}
