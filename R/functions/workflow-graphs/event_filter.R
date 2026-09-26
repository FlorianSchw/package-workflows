# The path filter of one trigger in words: "only R/**, tests/**",
# "not docs/**", or "" without a filter. All paths are listed — a count
# like "+3" hides exactly what someone looking at the filter wants to know.
event_filter <- function(settings) {
  notes <- c(
    if (!is.null(settings$paths)) sprintf("only %s", paste(unlist(settings$paths), collapse = ", ")),
    if (!is.null(settings[["paths-ignore"]])) sprintf("not %s", paste(unlist(settings[["paths-ignore"]]), collapse = ", "))
  )
  paste(notes, collapse = ", ")
}
