# The diagram for one situation (workflow_situations()): the event on the
# left, the workflows it starts (name, and the path filter or schedule for
# this event — the file is in the table), the workflows those start in
# turn (dotted arrows, `chains`), and on the right what they produce — one
# box per outcome, shared by the workflows that produce it, with the
# condition on the arrow (`outcomes`, file -> list of list(text, condition)
# from workflow_outcomes()). Laid out left to right with the workflows
# stacked, so it stays narrow enough to read on GitHub. Returns the
# Mermaid code.
situation_diagram <- function(situation, workflows, chains, outcomes) {
  by_file <- stats::setNames(workflows, vapply(workflows, function(wf) wf$file, character(1)))
  box <- function(file, note = NULL) {
    sprintf('  %s["%s"]', mermaid_id("wf", file), mermaid_label(c(by_file[[file]]$name, note)))
  }

  lines <- c("flowchart LR", sprintf('  ev(["%s"])', mermaid_label(situation$title)))
  included <- names(situation$members)
  for (f in included) {
    lines <- c(lines, box(f, situation$members[[f]]), sprintf("  ev --> %s", mermaid_id("wf", f)))
  }

  # Workflows started by those shown, followed further down.
  queue <- included
  while (length(queue) > 0) {
    from <- queue[1]; queue <- queue[-1]
    for (ch in Filter(function(ch) identical(ch$from, from), chains)) {
      if (!ch$to %in% included) {
        lines <- c(lines, box(ch$to))
        included <- c(included, ch$to)
        queue <- c(queue, ch$to)
      }
      lines <- c(lines, sprintf('  %s -. "%s" .-> %s', mermaid_id("wf", from), mermaid_text(ch$label), mermaid_id("wf", ch$to)))
    }
  }

  texts <- unique(unlist(lapply(outcomes[included], function(os) vapply(os, function(o) o$text, character(1)))))
  for (i in seq_along(texts)) {
    lines <- c(lines, sprintf('  out_%d(["%s"]):::outcome', i, mermaid_label(texts[i])))
  }
  for (f in included) {
    for (o in outcomes[[f]]) {
      target <- sprintf("out_%d", match(o$text, texts))
      lines <- c(lines, if (nzchar(o$condition)) {
        sprintf('  %s -- "%s" --> %s', mermaid_id("wf", f), mermaid_label(o$condition), target)
      } else {
        sprintf("  %s --> %s", mermaid_id("wf", f), target)
      })
    }
  }
  paste(c(lines, "  classDef outcome stroke-dasharray: 4 3"), collapse = "\n")
}
