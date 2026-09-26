# The detail diagram of one workflow, top to bottom: its triggers in a
# start box, then its jobs in `needs:` order. A job that calls a reusable
# workflow is opened up: a frame titled with the job ID, holding the
# called workflow's own jobs with their steps (step_names()) — what
# actually happens (which workflow is called is in the table). A called
# workflow with a single job doesn't repeat that job's name. A condition
# under which the job runs is a dashed note at the top of the frame, in
# words (job_condition()); a condition on the result of a needed job
# labels the arrow instead. A call that couldn't be read
# (resolve_called_workflows()) stays one box, marked "not readable"; a job
# of this workflow itself lists its steps. Dotted arrows lead to the
# workflows a job starts (`chains`). Frame titles are kept to the job ID:
# GitHub cuts off longer ones. Returns the Mermaid code.
workflow_detail_diagram <- function(workflow, called, chains, workflows) {
  triggers <- vapply(names(workflow$triggers), function(e) describe_trigger(e, workflow$triggers[[e]]), character(1))
  lines <- c("flowchart TD", sprintf('  start(["%s"])', mermaid_label(triggers)))
  # A `name:` built from expressions (matrix jobs) says nothing in a diagram.
  job_title <- function(id, job) if (is.null(job$name) || grepl("${{", job$name, fixed = TRUE)) id else as.character(job$name)
  safe <- function(x) gsub("[^A-Za-z0-9]", "_", x)

  arrows <- function(needs, cond, target) {
    if (length(needs) == 0) return(sprintf("  start --> %s", target))
    vapply(needs, function(n) {
      from <- mermaid_id("job", n)
      if (is.na(cond$edge_label)) sprintf("  %s --> %s", from, target)
      else sprintf('  %s -- "%s" --> %s', from, mermaid_text(cond$edge_label), target)
    }, character(1))
  }

  for (job_id in names(workflow$jobs)) {
    job <- workflow$jobs[[job_id]]
    ref <- parse_workflow_ref(job$uses)
    cond <- job_condition(job)
    id <- mermaid_id("job", job_id)
    title <- job_title(job_id, job)
    inner <- if (!is.null(ref)) called[[ref$key]]$workflow else NULL

    if (!is.null(inner)) {
      lines <- c(lines, sprintf('  subgraph %s ["%s"]', id, mermaid_text(title)), "    direction TB")
      note <- NULL
      if (!is.na(cond$note)) {
        note <- sprintf("%s__cond", id)
        lines <- c(lines, sprintf('    %s["%s"]:::condnote', note, mermaid_label(cond$note)))
      }
      single <- length(inner$jobs) == 1
      for (inner_id in names(inner$jobs)) {
        ij <- inner$jobs[[inner_id]]
        inner_ref <- parse_workflow_ref(ij$uses)
        body <- if (!is.null(inner_ref)) inner_ref$lines else step_names(ij)
        node <- sprintf("%s__%s", id, safe(inner_id))
        lines <- c(lines, sprintf('    %s["%s"]', node, mermaid_label(c(if (!single) job_title(inner_id, ij), job_condition(ij)$note, body))))
        inner_needs <- unlist(ij$needs)
        if (length(inner_needs) > 0) {
          lines <- c(lines, sprintf("    %s__%s --> %s", id, safe(inner_needs), node))
        } else if (!is.null(note)) {
          lines <- c(lines, sprintf("    %s ~~~ %s", note, node))  # keeps the note on top
        }
      }
      lines <- c(lines, "  end")
    } else {
      body <- if (!is.null(ref)) c(ref$lines, "(not readable)") else step_names(job)
      lines <- c(lines, sprintf('  %s["%s"]', id, mermaid_label(c(title, cond$note, body))))
    }
    lines <- c(lines, arrows(unlist(job$needs), cond, id))
  }

  for (ch in Filter(function(ch) identical(ch$from, workflow$file) && !is.na(ch$job), chains)) {
    target <- Find(function(wf) identical(wf$file, ch$to), workflows)
    lines <- c(lines,
      sprintf('  %s(["%s"])', mermaid_id("wf", ch$to), mermaid_label(target$name)),
      sprintf('  %s -. "%s" .-> %s', mermaid_id("job", ch$job), mermaid_text(ch$label), mermaid_id("wf", ch$to))
    )
  }
  paste(c(lines, "  classDef condnote stroke-dasharray: 4 3"), collapse = "\n")
}
