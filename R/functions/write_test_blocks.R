# Writes new test_that() blocks to tests/testthat/test-<function>.R —
# creates the file if it doesn't exist, or appends after existing content
# if it does. Existing content is NEVER rewritten or touched, only added
# to — same "carry forward untouched" principle roxygen-suggest.yml uses
# for @export/@import/@importFrom/@author. Returns the file path written,
# for the caller to track in the commit manifest.
write_test_blocks <- function(existing_test_file, test_blocks) {
  if (length(test_blocks) == 0) return(invisible(NULL))

  new_content <- paste(test_blocks, collapse = "\n\n")

  if (existing_test_file$exists) {
    dir.create(dirname(existing_test_file$path), recursive = TRUE, showWarnings = FALSE)
    full_content <- paste(existing_test_file$content, new_content, sep = "\n\n")
  } else {
    dir.create(dirname(existing_test_file$path), recursive = TRUE, showWarnings = FALSE)
    full_content <- new_content
  }

  writeLines(full_content, existing_test_file$path)
  existing_test_file$path
}
