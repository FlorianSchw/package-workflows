# Actually runs the just-written test file via testthat and reports
# pass/fail per test_that() block, matched by description. This is the
# "every generated test must actually be run before being trusted" step —
# a test either passes or fails mechanically, checked here rather than
# assumed. Returns a list of list(description, passed, message) — message
# is NA for passing tests, the failure/error text otherwise.
run_test_blocks <- function(path) {
  raw <- testthat::test_file(path, reporter = "list")

  lapply(raw, function(item) {
    failure <- Filter(
      function(r) inherits(r, "expectation_failure") || inherits(r, "expectation_error"),
      item$results
    )
    passed <- length(failure) == 0
    message <- if (passed) NA_character_ else conditionMessage(failure[[1]])
    list(description = item$test, passed = passed, message = message)
  })
}
