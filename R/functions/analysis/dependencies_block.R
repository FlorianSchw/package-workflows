# The bot's block in dependencies.R (the file exists so renv records
# packages without a library() call in the scripts). Three parts: the
# tested client packages, the server packages needed for local DSLite
# testing, and — commented out, so renv ignores them — packages from notes
# that the study servers don't have yet.
dependencies_block <- function(clients, servers, not_on_servers) {
  c(
    "#### Client packages for your studies' server packages (tested)",
    sprintf("library(%s)", clients),
    "#### Server packages, only needed for local testing with DSLite",
    "library(DSLite)",
    sprintf("library(%s)", servers),
    if (length(not_on_servers) > 0) c(
      "#### Not yet installed on your study servers. Uncomment once they are, or to",
      "#### try them locally with DSLite (see the suggestion PR for what they'd enable):",
      sprintf("# library(%s)", not_on_servers)
    )
  )
}
