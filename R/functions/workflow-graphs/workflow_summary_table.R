# The table at the top of the overview — the quickest way in, and always
# readable on GitHub: one row per workflow (in the order given) with its
# name, its file (the only place the file is named; the diagrams leave it
# out), all its triggers (trigger_summary()), the reusable workflows it
# calls (full reference; "not readable" if resolve_called_workflows()
# couldn't read it), and what it produces (`outcomes`, file -> list of
# list(text, condition) from workflow_outcomes()) plus the workflows it
# starts (`chains`). Returns Markdown lines.
workflow_summary_table <- function(workflows, called, outcomes, chains) {
  # Pipes would end the cell, asterisks in "R/**" would turn into bold.
  cell <- function(x) gsub("*", "\\*", gsub("|", "\\|", x, fixed = TRUE), fixed = TRUE)
  name_of <- stats::setNames(vapply(workflows, function(wf) wf$name, character(1)), vapply(workflows, function(wf) wf$file, character(1)))

  rows <- vapply(workflows, function(wf) {
    refs <- unique(unlist(lapply(wf$jobs, function(job) {
      ref <- parse_workflow_ref(job$uses)
      if (is.null(ref)) return(NULL)
      paste0(ref$label, if (isTRUE(called[[ref$key]]$readable)) "" else " (not readable)")
    })))
    produced <- vapply(outcomes[[wf$file]], function(o) {
      if (nzchar(o$condition)) sprintf("%s — *%s*", cell(o$text), cell(o$condition)) else cell(o$text)
    }, character(1))
    starts <- unique(vapply(Filter(function(ch) identical(ch$from, wf$file), chains), function(ch) sprintf("starts **%s**", cell(name_of[[ch$to]])), character(1)))
    produces <- c(produced, starts)
    sprintf("| %s | `%s` | %s | %s | %s |",
            cell(wf$name), wf$file, cell(trigger_summary(wf)),
            if (length(refs) > 0) cell(paste(refs, collapse = "<br>")) else "—",
            if (length(produces) > 0) paste(produces, collapse = "<br>") else "—")
  }, character(1))

  c("| Name | File | Runs on | Calls | Produces |", "|---|---|---|---|---|", rows)
}
