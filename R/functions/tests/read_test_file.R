# A test file as list(path, exists, content, category). content is "" when
# the file doesn't exist yet, never NULL, so callers can always paste()
# onto it. category is the test-<category>-<function>.R part, NA for
# test-<function>.R.
read_test_file <- function(path, category = NA_character_) {
  exists <- file.exists(path)
  list(
    path = path,
    exists = exists,
    content = if (exists) paste(readLines(path, warn = FALSE), collapse = "\n") else "",
    category = category
  )
}
