# The path filter of one trigger in words: "only if: R/**, tests/**
# changed", "skipped: only docs/** changed", or "" without a filter. All
# paths are listed — a count like "+3" hides exactly what someone looking
# at the filter wants to know.
event_filter <- function(settings) {
  notes <- c(
    if (!is.null(settings$paths)) sprintf("only if: %s changed", paste(unlist(settings$paths), collapse = ", ")),
    if (!is.null(settings[["paths-ignore"]])) sprintf("skipped: only %s changed", paste(unlist(settings[["paths-ignore"]]), collapse = ", "))
  )
  paste(notes, collapse = ", ")
}
