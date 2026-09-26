# The path filter of one trigger in words: "only R/**", "not docs/**",
# or "" without a filter. More than two paths are shortened to the first
# two plus a count ("only R/**, tests/** (+3)").
event_filter <- function(settings) {
  paths_text <- function(paths) {
    paths <- unlist(paths)
    shown <- paste(utils::head(paths, 2), collapse = ", ")
    if (length(paths) > 2) sprintf("%s (+%d)", shown, length(paths) - 2) else shown
  }
  notes <- c(
    if (!is.null(settings$paths)) sprintf("only %s", paths_text(settings$paths)),
    if (!is.null(settings[["paths-ignore"]])) sprintf("not %s", paths_text(settings[["paths-ignore"]]))
  )
  paste(notes, collapse = ", ")
}
