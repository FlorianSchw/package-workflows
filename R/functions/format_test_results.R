# The existing tests' results before any change, for the prompt: one line
# per test_that() block, passed or FAILED with the error (trimmed to 1000
# characters). `results` comes from run_test_blocks().
format_test_results <- function(results) {
  if (length(results) == 0) return("(no existing tests)")
  lines <- vapply(results, function(r) {
    if (isTRUE(r$passed)) return(sprintf("- \"%s\": passed", r$description))
    msg <- gsub("\\s+", " ", r$message)
    if (nchar(msg) > 1000) msg <- paste0(substr(msg, 1, 1000), " …")
    sprintf("- \"%s\": FAILED — %s", r$description, msg)
  }, character(1))
  paste(lines, collapse = "\n")
}
