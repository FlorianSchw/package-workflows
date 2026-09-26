# What a workflow of the repository produces, per config/workflow-outcomes.yml
# (`config`, read with yaml; see resolve_shared_path() for overrides): the
# outcomes listed for the workflow file itself plus those of every
# reusable workflow its jobs call. Returns their wording, e.g. "Suggestion
# PR", without duplicates — empty if nothing is described.
workflow_outcomes <- function(workflow, config) {
  keys <- c(file.path(".github/workflows", workflow$file),
            unlist(lapply(workflow$jobs, function(job) parse_workflow_ref(job$uses)$id)))
  kinds <- unique(unlist(lapply(keys, function(k) config$workflows[[k]])))
  labels <- vapply(kinds, function(k) if (is.null(config$outcomes[[k]])) k else config$outcomes[[k]], character(1))
  unname(labels)
}
