# The PR comment previewing how this pull request changes the workflow
# diagrams: the overview, if it changes, and the detail diagrams of
# changed or new workflows in a collapsible section, plus the removed ones
# by name. `blocks` are the blocks after the PR (workflow_graph_blocks()),
# `current` those in the README now (read_marked_blocks()). Says that
# nothing is committed on a PR — the README is updated after the merge, if
# the workflow also runs on push. Starts with `marker`, so
# upsert_pr_comment() finds the comment again. Returns NULL if no diagram
# changes. Capped below GitHub's comment limit.
format_workflow_graphs_preview <- function(blocks, current, marker) {
  changed <- names(blocks)[!vapply(names(blocks), function(id) identical(blocks[[id]], current[[id]]), logical(1))]
  removed <- setdiff(grep("^detail:", names(current), value = TRUE), names(blocks))
  if (length(changed) == 0 && length(removed) == 0) return(NULL)

  details <- setdiff(changed, "overview")
  body <- c(
    marker,
    "**Workflow diagrams after this pull request**",
    "",
    "Nothing is committed on a pull request: `.github/workflows/README.md` is updated once this is merged.",
    "",
    if ("overview" %in% changed) c("#### Overview", "", blocks$overview, ""),
    if (length(details) > 0) c(
      sprintf("<details><summary>Changed workflows (%d)</summary>", length(details)),
      "",
      unlist(lapply(details, function(id) c(blocks[[id]], ""))),
      "</details>",
      ""
    ),
    if (length(removed) > 0) sprintf("Removed: %s", paste0("`", sub("^detail:", "", removed), "`", collapse = ", "))
  )
  body <- paste(body, collapse = "\n")
  if (nchar(body) > 60000) body <- paste0(substr(body, 1, 60000), "\n\n… truncated.")
  body
}
