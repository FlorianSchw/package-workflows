# The README written the first time only, when .github/workflow-graphs/README.md
# doesn't exist yet: a short intro, the overview block and the detail
# blocks under their own headings. Afterwards the text is the repository's
# own — later runs only replace the blocks (update_marked_blocks()).
# `wrapped` is the named list of blocks with their markers.
workflow_readme_starter <- function(wrapped) {
  details <- wrapped[startsWith(names(wrapped), "detail:")]
  c(
    "# Workflows",
    "",
    "The GitHub Actions workflows of this repository, and how they connect.",
    "The diagrams are generated from the workflow files by",
    "[workflow-graphs](https://github.com/FlorianSchw/package-workflows) and",
    "updated when the workflows change. Text outside the marked diagram",
    "blocks is yours: add explanations anywhere, it is never overwritten.",
    "",
    "## Overview",
    "",
    wrapped$overview,
    "",
    "## Workflows",
    unlist(lapply(details, function(b) c("", b)))
  )
}
