# What a workflow of the repository produces, per config/workflow-outcomes.yml
# (`config`, read with yaml; see resolve_shared_path() for overrides): the
# outcomes listed for the workflow file itself, and per job those of the
# reusable workflow it calls, each with the condition under which the job
# runs (job_run_condition()). An entry is a short name from
# `config$outcomes` or its own wording; "{name}" is filled in with the
# job's input of that name, else the called workflow's default. Returns a
# list of list(text, condition), without duplicates — empty if nothing is
# described.
workflow_outcomes <- function(workflow, called, config) {
  wording <- function(entry, job = NULL, inner = NULL) {
    text <- if (!is.null(config$outcomes[[entry]])) config$outcomes[[entry]] else entry
    for (name in regmatches(text, gregexpr("(?<=\\{)[A-Za-z0-9_-]+(?=\\})", text, perl = TRUE))[[1]]) {
      value <- job$with[[name]]
      if (is.null(value)) value <- inner$triggers$workflow_call$inputs[[name]]$default
      if (!is.null(value)) text <- gsub(sprintf("{%s}", name), as.character(value), text, fixed = TRUE)
    }
    text
  }

  out <- lapply(config$workflows[[file.path(".github/workflows", workflow$file)]], function(e) list(text = wording(e), condition = ""))
  for (job in workflow$jobs) {
    ref <- parse_workflow_ref(job$uses)
    if (is.null(ref) || is.null(config$workflows[[ref$id]])) next
    condition <- job_run_condition(job, called)
    inner <- called[[ref$key]]$workflow
    out <- c(out, lapply(config$workflows[[ref$id]], function(e) list(text = wording(e, job, inner), condition = condition)))
  }
  unique(out)
}
