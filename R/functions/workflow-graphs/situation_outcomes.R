# A workflow's outcomes (workflow_outcomes()) as they matter in one
# situation — `trigger` is its GitHub event name ("schedule"). An outcome
# that only happens on another event ("only on schedule" in a pull request
# situation) is left out; on its own event the condition goes without
# saying and is dropped. If all remaining outcomes share one condition,
# it is returned once as `shared` (for the workflow's box) and removed
# from the outcomes, so the diagram doesn't repeat it on every arrow.
# Returns list(outcomes, shared).
situation_outcomes <- function(outcomes, trigger) {
  event_words <- gsub("_", " ", trigger)
  kept <- list()
  for (o in outcomes) {
    # "only on <event>", possibly followed by ", <further condition>".
    only_on <- regmatches(o$condition, regexec("^only on ([^,]+)(?:, (.*))?$", o$condition, perl = TRUE))[[1]]
    if (length(only_on) == 3) {
      if (!identical(only_on[2], event_words)) next
      o$condition <- only_on[3]
    }
    kept[[length(kept) + 1]] <- o
  }

  conditions <- unique(vapply(kept, function(o) o$condition, character(1)))
  if (length(kept) > 0 && length(conditions) == 1 && nzchar(conditions)) {
    kept <- lapply(kept, function(o) { o$condition <- ""; o })
    return(list(outcomes = kept, shared = conditions))
  }
  list(outcomes = kept, shared = NULL)
}
