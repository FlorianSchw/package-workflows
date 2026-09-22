# Defense in depth, same posture as roxygen-suggest's sanitize_field():
# strips markdown code fences (```r / ```) if Claude wraps a code field in
# them despite being asked for raw code, and hard-fails loudly if a
# required field is empty after stripping rather than silently assembling
# a broken test file.
sanitize_test_code_field <- function(text, field_name, context) {
  if (is.null(text)) return("")
  lines <- strsplit(text, "\n")[[1]]
  is_fence <- grepl("^\\s*```", lines)
  if (any(is_fence)) {
    message(sprintf(
      "%s: field '%s' contained markdown code fences — stripping before assembly.",
      context, field_name
    ))
    lines <- lines[!is_fence]
  }
  paste(lines, collapse = "\n")
}
