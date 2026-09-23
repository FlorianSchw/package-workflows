# Makes tests/testthat/test-<function>.R equal its original content plus
# `test_blocks` appended after it. Existing content is never rewritten, only
# added to — same "carry forward untouched" principle roxygen-suggest.yml
# uses for tags Claude doesn't manage. With no blocks, the file is put back
# exactly as found (or removed, if it didn't exist before) — which is how
# rejected candidates get backed out after a run. Returns the path when
# blocks were written, else NULL.
write_test_blocks <- function(existing_test_file, test_blocks) {
  path <- existing_test_file$path

  if (length(test_blocks) == 0) {
    if (existing_test_file$exists) {
      writeLines(existing_test_file$content, path)
    } else if (file.exists(path)) {
      file.remove(path)
    }
    return(invisible(NULL))
  }

  new_content <- paste(test_blocks, collapse = "\n\n")
  if (existing_test_file$exists) new_content <- paste(existing_test_file$content, new_content, sep = "\n\n")

  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(new_content, path)
  path
}
