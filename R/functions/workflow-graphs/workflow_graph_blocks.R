# The generated blocks of the README (see update_marked_blocks()):
# "overview" — the summary table (workflow_summary_table()) followed by one
# small diagram per situation (workflow_situations(), situation_diagram())
# — and one "detail:<file>" block per workflow with its heading (name, file)
# and detail diagram. Headings are part of the blocks, so they follow a
# renamed workflow. `outcomes_config` is config/workflow-outcomes.yml as
# read by yaml. Table rows and details follow workflow_order() — also in
# an existing README (update_marked_blocks()).
workflow_graph_blocks <- function(workflows, called, chains, outcomes_config) {
  # One element per line, so a regenerated block compares equal to the file.
  fence <- function(code) c("```mermaid", strsplit(code, "\n", fixed = TRUE)[[1]], "```")
  workflows <- workflow_order(workflows, chains)
  outcomes <- stats::setNames(lapply(workflows, workflow_outcomes, called = called, config = outcomes_config),
                              vapply(workflows, function(wf) wf$file, character(1)))

  overview <- workflow_summary_table(workflows, called, outcomes, chains)
  for (s in workflow_situations(workflows, chains)) {
    overview <- c(overview, "", sprintf("### %s", s$title), "", fence(situation_diagram(s, workflows, chains, outcomes)))
  }

  blocks <- list(overview = overview)
  for (wf in workflows) {
    blocks[[sprintf("detail:%s", wf$file)]] <- c(
      sprintf("### %s", wf$name),
      "",
      sprintf("<sub>`%s`</sub>", wf$file),
      "",
      fence(workflow_detail_diagram(wf, called, chains, workflows))
    )
  }
  blocks
}
