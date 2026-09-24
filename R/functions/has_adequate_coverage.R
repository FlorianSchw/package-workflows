# PLACEHOLDER pending real per-function coverage data from R-CMD-Check.yml
# (covr::function_coverage() handoff — not wired yet, see
# "Open questions" in dev-notes/test-coverage-suggest.md). Until that exists,
# this uses a coarse presence heuristic: a function counts as "adequately
# tested" only if an existing test file already contains a test_that() call
# whose description or body references the function name. Anything else
# (no test file, or a test file that never mentions this function) is
# treated as under-tested. This will under- and over-count coverage in real
# packages and should be replaced once real coverage data is available.
has_adequate_coverage <- function(function_name, existing_test_file) {
  if (!existing_test_file$exists) return(FALSE)
  grepl(function_name, existing_test_file$content, fixed = TRUE)
}
