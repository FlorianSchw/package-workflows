# The overview diagram: one lane per main trigger (main_trigger(),
# described by describe_trigger(), lanes in trigger_order()) holding the
# workflows it starts, each as
# a box with its name and — in small print — its file and further triggers
# (trigger_notes()). Dotted arrows are the chains between workflows
# (workflow_chains()). Jobs are left to the detail diagrams. Returns the
# Mermaid code.
workflow_overview_diagram <- function(workflows, chains) {
  box <- function(wf) {
    notes <- trigger_notes(wf, main_trigger(wf))
    sprintf('    %s["%s<br/><small>%s</small>%s"]', mermaid_id("wf", wf$file), mermaid_text(wf$name),
            mermaid_text(wf$file), if (nzchar(notes)) sprintf("<br/><small>%s</small>", mermaid_text(notes)) else "")
  }

  mains <- vapply(workflows, main_trigger, character(1))
  lane_of <- vapply(seq_along(workflows), function(i) describe_trigger(mains[i], workflows[[i]]$triggers[[mains[i]]]), character(1))
  # Lanes in trigger_order(), then in order of appearance.
  lanes <- unique(lane_of[order(match(mains, trigger_order(), nomatch = length(trigger_order()) + 1))])

  lines <- "flowchart LR"
  for (i in seq_along(lanes)) {
    lane <- lanes[i]
    lines <- c(lines,
      sprintf('  ev_%d(["%s"]) --> lane_%d', i, mermaid_text(lane), i),
      sprintf('  subgraph lane_%d [" "]', i),
      "    direction TB",
      vapply(workflows[lane_of == lane], box, character(1)),
      "  end"
    )
  }
  for (ch in unique(lapply(chains, function(ch) ch[c("from", "to", "label")]))) {
    lines <- c(lines, sprintf('  %s -. "%s" .-> %s', mermaid_id("wf", ch$from), mermaid_text(ch$label), mermaid_id("wf", ch$to)))
  }
  paste(lines, collapse = "\n")
}
