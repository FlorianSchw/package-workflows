# The test support files (test_support_files()) verbatim for the prompt,
# so Claude uses the objects, symbols and helper functions the package
# actually defines instead of guessing them. Each file is capped at 20000
# characters, and the cut is stated.
format_test_support_files <- function(paths) {
  if (length(paths) == 0) return("(none)")
  parts <- vapply(paths, function(path) {
    content <- paste(readLines(path, warn = FALSE), collapse = "\n")
    if (nchar(content) > 20000) {
      content <- paste0(substr(content, 1, 20000), "\n# … (file continues, cut here)")
    }
    sprintf("File `%s`:\n```r\n%s\n```", path, content)
  }, character(1))
  paste(parts, collapse = "\n\n")
}
