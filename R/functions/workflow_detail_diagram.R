# The detail diagram of one workflow: its triggers in a start box, then its
# jobs in `needs:` order. A job box shows the job ID, its `name:` if it has
# one, and in small print the reusable workflow it calls (full reference,
# parse_workflow_ref(); "not readable" if resolve_called_workflows()
# couldn't read it) or its number of steps, plus a condition that isn't
# about the jobs it needs (job_condition()). Arrows between jobs carry the
# result they wait for. Dotted arrows lead to the workflows a job starts
# (`chains` from workflow_chains()). Returns the Mermaid code.
workflow_detail_diagram <- function(workflow, called, chains, workflows) {
  triggers <- vapply(names(workflow$triggers), function(e) describe_trigger(e, workflow$triggers[[e]]), character(1))
  lines <- c("flowchart LR", sprintf('  start(["%s"])', mermaid_text(paste(triggers, collapse = " · "))))

  for (job_id in names(workflow$jobs)) {
    job <- workflow$jobs[[job_id]]
    ref <- parse_workflow_ref(job$uses)
    small <- if (!is.null(ref)) {
      readable <- isTRUE(called[[ref$key]]$readable)
      paste0(ref$label, if (readable) "" else " (not readable)")
    } else {
      n <- length(job$steps)
      sprintf("%d step%s", n, if (n == 1) "" else "s")
    }
    cond <- job_condition(job)
    label <- c(
      mermaid_text(job_id),
      if (!is.null(job$name) && !identical(job$name, job_id)) mermaid_text(job$name),
      sprintf("<small>%s</small>", mermaid_text(small)),
      if (!is.na(cond$note)) sprintf("<small>%s</small>", mermaid_text(cond$note))
    )
    node <- mermaid_id("job", job_id)
    lines <- c(lines, sprintf('  %s["%s"]', node, paste(label, collapse = "<br/>")))

    needs <- unlist(job$needs)
    if (length(needs) == 0) {
      lines <- c(lines, sprintf("  start --> %s", node))
    } else {
      for (n in needs) {
        lines <- c(lines, if (is.na(cond$edge_label)) {
          sprintf("  %s --> %s", mermaid_id("job", n), node)
        } else {
          sprintf('  %s -- "%s" --> %s', mermaid_id("job", n), mermaid_text(cond$edge_label), node)
        })
      }
    }
  }

  for (ch in Filter(function(ch) identical(ch$from, workflow$file) && !is.na(ch$job), chains)) {
    target <- Find(function(wf) identical(wf$file, ch$to), workflows)
    lines <- c(lines,
      sprintf('  %s(["%s<br/><small>%s</small>"])', mermaid_id("wf", ch$to), mermaid_text(target$name), mermaid_text(ch$to)),
      sprintf('  %s -. "%s" .-> %s', mermaid_id("job", ch$job), mermaid_text(ch$label), mermaid_id("wf", ch$to))
    )
  }
  paste(lines, collapse = "\n")
}
