# The diagram for one situation (workflow_situations()): the event on the
# left, the workflows it starts (bold name, and the path filter or
# schedule for this event — the file is in the table), what they produce
# (`outcomes`, file -> workflow_outcomes(), fitted to the situation by
# situation_outcomes()), and the workflows they start in turn (dotted
# arrows, `chains`).
#
# Outcomes follow the order of the jobs that produce them: a job that
# needs another starts from that job's outcomes, with the result it waits
# for on the arrow ("if check fails") — so Release reads check → PR merged
# / Issue, and PR merged ⇢ Publish Release. A job without outcomes of its
# own passes its incoming arrows through. An outcome that leads on to
# something has its own box per workflow; the others are shared by wording
# across workflows ("Suggestion PR"). A condition shared by all arrows
# leaving a workflow's box is written once in the box instead.
#
# Laid out left to right with the workflows stacked; columns spaced wider
# than Mermaid's default and arrow labels wrapped narrower, so labels fit
# between the arrows. Returns the Mermaid code.
situation_diagram <- function(situation, workflows, chains, outcomes) {
  by_file <- stats::setNames(workflows, vapply(workflows, function(wf) wf$file, character(1)))
  label_of <- function(parts) paste(Filter(nzchar, parts), collapse = ", ")

  # The workflows this event starts, and those they start in turn.
  included <- names(situation$members)
  queue <- included
  while (length(queue) > 0) {
    from <- queue[1]; queue <- queue[-1]
    for (ch in Filter(function(ch) identical(ch$from, from), chains)) {
      if (!ch$to %in% included) { included <- c(included, ch$to); queue <- c(queue, ch$to) }
    }
  }

  # Per workflow: its outcome keys, and the arrows between box, outcomes
  # and started workflows, before deciding which outcome boxes are shared.
  outcome_text <- list()      # key -> wording
  edges <- list()             # list(from, to, label, dotted)
  box_notes <- list()
  for (f in included) {
    wf <- by_file[[f]]
    box <- mermaid_id("wf", f)
    outs <- situation_outcomes(outcomes[[f]], situation$trigger)
    keys <- sprintf("%s|%s|%d", f, vapply(outs, function(o) if (is.na(o$job)) "" else o$job, character(1)), seq_along(outs))
    for (i in seq_along(outs)) outcome_text[[keys[i]]] <- outs[[i]]$text
    jobs_out <- vapply(outs, function(o) if (is.na(o$job)) "" else o$job, character(1))

    # Where arrows into a job come from: its own outcomes, or — for a job
    # without outcomes — what its needs lead to, down to the workflow box.
    sources <- function(job, seen = character(0)) {
      if (job %in% seen) return(box)
      mine <- keys[jobs_out == job]
      if (length(mine) > 0) return(mine)
      needs <- unlist(wf$jobs[[job]]$needs)
      if (length(needs) == 0) return(box)
      unique(unlist(lapply(needs, sources, seen = c(seen, job))))
    }

    wf_edges <- list()
    for (i in seq_along(outs)) {
      o <- outs[[i]]
      needs <- if (is.na(o$job)) NULL else unlist(wf$jobs[[o$job]]$needs)
      froms <- if (length(needs) == 0) box else unique(unlist(lapply(needs, sources)))
      for (fr in froms) wf_edges[[length(wf_edges) + 1]] <- list(from = fr, to = keys[i], label = label_of(c(o$needs, o$condition)), dotted = FALSE)
    }
    for (ch in Filter(function(ch) identical(ch$from, f), chains)) {
      froms <- if (is.na(ch$job)) box else sources(ch$job)
      for (fr in froms) wf_edges[[length(wf_edges) + 1]] <- list(from = fr, to = mermaid_id("wf", ch$to), label = ch$label, dotted = TRUE)
    }

    # A condition on every arrow leaving the box goes into the box.
    from_box <- Filter(function(e) identical(e$from, box) && !e$dotted, wf_edges)
    shared <- unique(vapply(from_box, function(e) e$label, character(1)))
    if (length(from_box) > 0 && length(shared) == 1 && nzchar(shared)) {
      box_notes[[f]] <- shared
      wf_edges <- lapply(wf_edges, function(e) { if (identical(e$from, box) && !e$dotted) e$label <- ""; e })
    }
    edges <- c(edges, wf_edges)
  }

  # Outcomes leading on to something keep a box of their own; the rest
  # share one box per wording.
  leads_on <- unique(vapply(edges, function(e) e$from, character(1)))
  shared_texts <- unique(unlist(outcome_text[setdiff(names(outcome_text), leads_on)]))
  node_of <- function(key) {
    if (is.null(outcome_text[[key]])) return(key)  # a workflow box
    if (key %in% leads_on) return(sprintf("out_%s", gsub("[^A-Za-z0-9]", "_", key)))
    sprintf("out_%d", match(outcome_text[[key]], shared_texts))
  }

  lines <- c(
    '%%{init: {"flowchart": {"rankSpacing": 140, "nodeSpacing": 45}}}%%',
    "flowchart LR",
    sprintf('  ev(["%s"])', mermaid_label(situation$event))
  )
  for (f in included) {
    notes <- Filter(nzchar, c(situation$members[[f]], box_notes[[f]]))
    lines <- c(lines, sprintf('  %s["<b>%s</b>%s"]', mermaid_id("wf", f), mermaid_label(by_file[[f]]$name),
                              if (length(notes) > 0) paste0("<br/>", mermaid_label(notes)) else ""))
    if (f %in% names(situation$members)) lines <- c(lines, sprintf("  ev --> %s", mermaid_id("wf", f)))
  }
  declared <- character(0)
  for (key in names(outcome_text)) {
    node <- node_of(key)
    if (node %in% declared) next
    declared <- c(declared, node)
    lines <- c(lines, sprintf('  %s(["%s"]):::outcome', node, mermaid_label(outcome_text[[key]])))
  }
  for (e in unique(edges)) {
    from <- node_of(e$from); to <- node_of(e$to)
    lines <- c(lines, if (e$dotted) {
      sprintf('  %s -. "%s" .-> %s', from, mermaid_text(e$label), to)
    } else if (nzchar(e$label)) {
      sprintf('  %s -- "%s" --> %s', from, mermaid_label(e$label, width = 20), to)
    } else {
      sprintf("  %s --> %s", from, to)
    })
  }
  paste(unique(c(lines, "  classDef outcome stroke-dasharray: 4 3")), collapse = "\n")
}
