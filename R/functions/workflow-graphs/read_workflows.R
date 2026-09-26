# All workflow files of a repository (`dir`, normally .github/workflows),
# parsed with parse_workflow_yaml() and sorted by file name. A file that
# doesn't parse is skipped with a message, so one broken file doesn't hide
# the diagrams of all the others.
read_workflows <- function(dir = ".github/workflows") {
  paths <- sort(list.files(dir, pattern = "\\.ya?ml$", full.names = TRUE))
  workflows <- lapply(paths, function(p) {
    tryCatch(
      parse_workflow_yaml(paste(readLines(p, warn = FALSE), collapse = "\n"), basename(p)),
      error = function(e) {
        message(sprintf("Skipping %s: %s", basename(p), conditionMessage(e)))
        NULL
      }
    )
  })
  Filter(Negate(is.null), workflows)
}
