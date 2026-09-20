# Defense in depth: strips any roxygen syntax (comment markers, tag labels)
# that leaks into a Claude-supplied field before it's ever wrapped. Guards
# against the model echoing the "existing roxygen block" context back into
# a field instead of writing new prose, which no amount of prompt wording
# alone has reliably prevented.
sanitize_field <- function(text, field_name, path) {
  if (is.null(text) || !nzchar(trimws(text))) return(text %||% "")
  lines <- strsplit(text, "\n")[[1]]
  is_artifact <- grepl("^\\s*#'", lines) | grepl("^\\s*@[A-Za-z]+\\b", lines)
  if (any(is_artifact)) {
    message(sprintf(
      "%s: field '%s' contained roxygen syntax (comment markers or tag labels) — stripping before assembly. This indicates Claude echoed context instead of writing new prose.",
      path, field_name
    ))
    lines <- lines[!is_artifact]
  }
  paste(lines, collapse = "\n")
}
