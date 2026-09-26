# The generated blocks of the README (see update_marked_blocks()):
# "overview" with the overview diagram, and one "detail:<file>" block per
# workflow with its heading (name, file in small print) and detail diagram.
# The heading is part of the block, so it follows a renamed workflow.
# Details are ordered by file name (only matters for a new README).
workflow_graph_blocks <- function(workflows, called, chains) {
  # One element per line, so a regenerated block compares equal to the file.
  fence <- function(code) c("```mermaid", strsplit(code, "\n", fixed = TRUE)[[1]], "```")
  blocks <- list(overview = fence(workflow_overview_diagram(workflows, chains)))
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
