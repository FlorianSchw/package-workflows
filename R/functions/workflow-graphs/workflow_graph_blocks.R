# The generated block of the README (see update_marked_blocks()):
# "overview" — "All workflows" with the summary table
# (workflow_summary_table()), then "Events" with a short legend and one
# diagram per situation (workflow_situations(), situation_diagram()),
# titled with the event's short form ("PR into dev") and the sentence
# (situation_title()) below it. High level only: which workflows exist,
# when they run, what they produce — the details are in the workflow
# files. `outcomes_config` is config/workflow-outcomes.yml as read by
# yaml. The table follows workflow_order().
workflow_graph_blocks <- function(workflows, called, chains, outcomes_config) {
  # One element per line, so a regenerated block compares equal to the file.
  fence <- function(code) c("```mermaid", strsplit(code, "\n", fixed = TRUE)[[1]], "```")
  workflows <- workflow_order(workflows, chains)
  outcomes <- stats::setNames(lapply(workflows, workflow_outcomes, called = called, config = outcomes_config),
                              vapply(workflows, function(wf) wf$file, character(1)))

  overview <- c(
    "## All workflows",
    "",
    workflow_summary_table(workflows, called, outcomes, chains),
    "",
    "## Events",
    "",
    paste(
      "What each event starts: the workflows (bold), what they produce (dashed boxes)",
      "and the workflows they start in turn (dotted arrows).",
      "**only if:** — happens only under this condition, e.g. when these files changed;",
      "**skipped:** — doesn't happen in this case.",
      "A label on an arrow applies to that arrow only (\"if check fails\")."
    )
  )
  for (s in workflow_situations(workflows, chains)) {
    overview <- c(overview, "", sprintf("### %s", s$event), "", sprintf("*%s.*", s$title), "",
                  fence(situation_diagram(s, workflows, chains, outcomes)))
  }
  list(overview = overview)
}
