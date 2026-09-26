#!/usr/bin/env Rscript
# Draws Mermaid diagrams of the repository's GitHub Actions workflows into
# .github/workflow-graphs/README.md: an overview (workflows grouped by trigger,
# with the chains between them) and one detail diagram per workflow (its
# jobs in `needs:` order). Deterministic — only the YAML is read, including
# the reusable workflows it calls (resolve_called_workflows()), to find
# the chains that start inside them.
#
# Only the marked blocks of the README are replaced (update_marked_blocks());
# text around them is never touched; the calling workflow commits the
# result. In a pull request (PR_NUMBER set) nothing is written: the
# diagrams the PR changes are posted as a preview comment instead, kept up
# to date on further pushes (upsert_pr_comment()).
#
# This file only wires environment inputs together; all logic lives in
# R/functions/shared/ and R/functions/workflow-graphs/ — one function per
# file, loaded in bulk below.

library(httr2)
library(jsonlite)
library(purrr)

functions_dir <- if (dir.exists(".shared-workflows/R/functions")) ".shared-workflows/R/functions" else "R/functions"
walk(list.files(file.path(functions_dir, c("shared", "workflow-graphs")), pattern = "\\.R$", full.names = TRUE), source)

gh_token      <- Sys.getenv("GH_TOKEN")
repo          <- Sys.getenv("GITHUB_REPOSITORY")
pr_number     <- Sys.getenv("PR_NUMBER")  # set only in a pull request
workflows_dir <- Sys.getenv("WORKFLOWS_DIR", ".github/workflows")
# Not in .github/workflows/: GitHub treats every file there as a workflow,
# and pushing one needs the App's Workflows permission.
readme_path   <- Sys.getenv("README_PATH", ".github/workflow-graphs/README.md")

workflows <- read_workflows(workflows_dir)
message(sprintf("Read %d workflow file(s).", length(workflows)))

called <- resolve_called_workflows(workflows)
unreadable <- Filter(function(c) !isTRUE(c$readable), called)
if (length(unreadable) > 0) {
  # A private repository, or a temporary API problem — either way the
  # diagrams show these calls without their contents and chains.
  message(sprintf("::warning::Could not read %d called workflow(s): %s", length(unreadable),
                  paste(vapply(unreadable, function(c) c$ref$label, character(1)), collapse = ", ")))
}
chains <- workflow_chains(workflows, called)
message(sprintf("%d called workflow(s), %d chain(s) between workflows.", length(called), length(chains)))

# What each workflow produces can't be read from the YAML — it's described
# in config/workflow-outcomes.yml (a caller's own copy wins).
outcomes_path <- resolve_shared_path("config/workflow-outcomes.yml")
outcomes_config <- if (file.exists(outcomes_path)) yaml::read_yaml(outcomes_path) else list()

blocks <- workflow_graph_blocks(workflows, called, chains, outcomes_config)
current <- if (file.exists(readme_path)) readLines(readme_path, warn = FALSE) else NULL

if (nzchar(pr_number)) {
  marker <- "<!-- workflow-graphs:preview -->"
  preview <- format_workflow_graphs_preview(blocks, read_marked_blocks(current), marker)
  message(if (is.null(preview)) "This PR doesn't change the diagrams." else "Posting the diagram preview.")
  upsert_pr_comment(pr_number, preview, marker, "This pull request no longer changes the workflow diagrams.")
  quit(save = "no")
}

updated <- update_marked_blocks(current, blocks, workflow_readme_starter)
if (identical(current, updated)) {
  message("README is up to date.")
} else {
  dir.create(dirname(readme_path), recursive = TRUE, showWarnings = FALSE)
  writeLines(updated, readme_path)
  message(sprintf("Wrote %s.", readme_path))
}
