# Locates tests/testthat/test-<function_name>.R if it already exists.
# Returns a list(path, exists, content) — content is "" when the file
# doesn't exist yet, never NULL, so callers can always paste() onto it.
find_existing_test_file <- function(function_name) {
  path <- file.path("tests", "testthat", sprintf("test-%s.R", function_name))
  exists <- file.exists(path)
  list(
    path = path,
    exists = exists,
    content = if (exists) paste(readLines(path, warn = FALSE), collapse = "\n") else ""
  )
}
