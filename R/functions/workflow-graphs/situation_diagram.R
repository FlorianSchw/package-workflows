# The diagram for one situation (workflow_situations()): the event on the
# left, the workflows it starts (bold name, and the path filter or
# schedule for this event — the file is in the table), what they produce
# (`outcomes`, file -> workflow_outcomes(), fitted to the situation by
# situation_outcomes()), and the workflows they start in turn (dotted
# arrows, `chains`). Each workflow's arrows follow its jobs
# (workflow_flow()) — so Release reads check → PR merged / Issue, and PR
# merged ⇢ Publish Release. An outcome that leads on to something has its
# own box per workflow; the others are shared by wording across workflows
# ("Suggestion PR").
#
# Laid out left to right with the workflows stacked; columns spaced wider
# than Mermaid's default and arrow labels wrapped narrower, so labels fit
# between the arrows. A diagram more than four columns deep
# (diagram_depth()) is drawn top to bottom instead, so GitHub doesn't
# shrink it to fit the page width. Returns the Mermaid code.
situation_diagram <- function(situation, workflows, chains, outcomes) {
  by_file <- stats::setNames(workflows, vapply(workflows, function(wf) wf$file, character(1)))

  # The workflows this event starts, and those they start in turn.
  included <- names(situation$members)
  queue <- included
  while (length(queue) > 0) {
    from <- queue[1]; queue <- queue[-1]
    for (ch in Filter(function(ch) identical(ch$from, from), chains)) {
      if (!ch$to %in% included) { included <- c(included, ch$to); queue <- c(queue, ch$to) }
    }
  }

  flows <- lapply(stats::setNames(included, included), function(f) {
    workflow_flow(by_file[[f]], situation_outcomes(outcomes[[f]], situation$trigger), chains)
  })
  outcome_text <- do.call(c, unname(lapply(flows, function(fl) fl$outcome_text)))
  edges <- do.call(c, unname(lapply(flows, function(fl) fl$edges)))

  # Outcomes leading on to something keep a box of their own; the rest
  # share one box per wording.
  leads_on <- unique(vapply(edges, function(e) e$from, character(1)))
  shared_texts <- unique(unlist(outcome_text[setdiff(names(outcome_text), leads_on)]))
  node_of <- function(key) {
    if (is.null(outcome_text[[key]])) return(key)  # a workflow box
    if (key %in% leads_on) return(sprintf("out_%s", gsub("[^A-Za-z0-9]", "_", key)))
    sprintf("out_%d", match(outcome_text[[key]], shared_texts))
  }

  arrows <- c(lapply(names(situation$members), function(f) c("ev", mermaid_id("wf", f))),
              lapply(edges, function(e) c(node_of(e$from), node_of(e$to))))
  lines <- if (diagram_depth(arrows) > 4) {
    c('%%{init: {"flowchart": {"rankSpacing": 70, "nodeSpacing": 40}}}%%', "flowchart TD")
  } else {
    c('%%{init: {"flowchart": {"rankSpacing": 140, "nodeSpacing": 45}}}%%', "flowchart LR")
  }
  lines <- c(lines, sprintf('  ev(["%s"])', mermaid_label(situation$event)))

  for (f in included) {
    notes <- Filter(nzchar, c(situation$members[[f]], flows[[f]]$box_note))
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
