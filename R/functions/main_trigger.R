# The trigger a workflow is grouped under in the overview — the first of
# its triggers in trigger_order(), i.e. the one that says most about its
# role. Its other triggers are shown as small print (trigger_notes()).
main_trigger <- function(workflow) {
  events <- names(workflow$triggers)
  known <- trigger_order()[trigger_order() %in% events]
  if (length(known) > 0) known[1] else if (length(events) > 0) events[1] else "unknown"
}
