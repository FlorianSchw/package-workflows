# The generated block of the README (see update_marked_blocks()):
# "overview" — the summary table (workflow_summary_table()), then under
# "What runs when" one small diagram per situation (workflow_situations(),
# situation_diagram()), each under a heading in words (situation_title()).
# High-level only: which workflows exist, when they run, what they
# produce. The details are in the workflow files themselves.
# `outcomes_config` is config/workflow-outcomes.yml as read by yaml. The
# table follows workflow_order().
workflow_graph_blocks <- function(workflows, called, chains, outcomes_config) {
  # One element per line, so a regenerated block compares equal to the file.
  fence <- function(code) c("```mermaid", strsplit(code, "\n", fixed = TRUE)[[1]], "```")
  workflows <- workflow_order(workflows, chains)
  outcomes <- stats::setNames(lapply(workflows, workflow_outcomes, called = called, config = outcomes_config),
                              vapply(workflows, function(wf) wf$file, character(1)))

  overview <- c(
    "### All workflows",
    "",
    workflow_summary_table(workflows, called, outcomes, chains),
    "",
    "### What runs when",
    "",
    "What each event starts: the workflows, the workflows those start in turn (dotted arrows), and what comes out of it — with the condition on the arrow where there is one."
  )
  for (s in workflow_situations(workflows, chains)) {
    overview <- c(overview, "", sprintf("#### %s", s$title), "", fence(situation_diagram(s, workflows, chains, outcomes)))
  }
  list(overview = overview)
}
