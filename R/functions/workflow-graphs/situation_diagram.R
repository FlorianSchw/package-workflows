# The diagram for one situation (workflow_situations()): the event on the
# left, the workflows it starts (name, and the path filter or schedule for
# this event — the file is in the table), the workflows those start in
# turn (dotted arrows, `chains`), and on the right what they produce — one
# box per outcome, shared by the workflows that produce it (`outcomes`,
# file -> list of list(text, condition) from workflow_outcomes()).
# Conditions are fitted to the situation (situation_outcomes()): one that
# holds for all of a workflow's outcomes is written once in its box, only
# differing ones go on the arrows. Laid out left to right with the
# workflows stacked, so it stays narrow enough to read on GitHub; the
# columns are spaced wider than Mermaid's default and arrow labels wrapped
# narrower, so the labels have room between the arrows. Returns the
# Mermaid code.
situation_diagram <- function(situation, workflows, chains, outcomes) {
  by_file <- stats::setNames(workflows, vapply(workflows, function(wf) wf$file, character(1)))

  # The workflows this event starts, and those they start in turn.
  included <- names(situation$members)
  chain_lines <- character(0)
  queue <- included
  while (length(queue) > 0) {
    from <- queue[1]; queue <- queue[-1]
    for (ch in Filter(function(ch) identical(ch$from, from), chains)) {
      if (!ch$to %in% included) {
        included <- c(included, ch$to)
        queue <- c(queue, ch$to)
      }
      chain_lines <- c(chain_lines, sprintf('  %s -. "%s" .-> %s', mermaid_id("wf", from), mermaid_text(ch$label), mermaid_id("wf", ch$to)))
    }
  }
  fitted <- lapply(stats::setNames(included, included), function(f) situation_outcomes(outcomes[[f]], situation$trigger))

  lines <- c(
    '%%{init: {"flowchart": {"rankSpacing": 140, "nodeSpacing": 45}}}%%',
    "flowchart LR",
    sprintf('  ev(["%s"])', mermaid_label(situation$event))
  )
  for (f in included) {
    notes <- c(situation$members[[f]], fitted[[f]]$shared)
    lines <- c(lines, sprintf('  %s["%s"]', mermaid_id("wf", f), mermaid_label(c(by_file[[f]]$name, notes))))
    if (f %in% names(situation$members)) lines <- c(lines, sprintf("  ev --> %s", mermaid_id("wf", f)))
  }
  lines <- c(lines, chain_lines)

  texts <- unique(unlist(lapply(fitted, function(x) vapply(x$outcomes, function(o) o$text, character(1)))))
  for (i in seq_along(texts)) {
    lines <- c(lines, sprintf('  out_%d(["%s"]):::outcome', i, mermaid_label(texts[i])))
  }
  for (f in included) {
    for (o in fitted[[f]]$outcomes) {
      target <- sprintf("out_%d", match(o$text, texts))
      lines <- c(lines, if (nzchar(o$condition)) {
        sprintf('  %s -- "%s" --> %s', mermaid_id("wf", f), mermaid_label(o$condition, width = 20), target)
      } else {
        sprintf("  %s --> %s", mermaid_id("wf", f), target)
      })
    }
  }
  paste(c(lines, "  classDef outcome stroke-dasharray: 4 3"), collapse = "\n")
}
