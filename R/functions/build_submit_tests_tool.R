# Builds the Claude tool-call JSON schema for submit_tests. Same
# deterministic-assembly principle as roxygen-suggest's
# build_submit_review_tool(): Claude returns discrete fields (never
# assembled test_that() syntax), the R script does the actual stitching.
# The 5-test cap is enforced structurally via maxItems, not just prompt
# wording — same reasoning as roxygen's forced-tool-call design.
#
# dslite_datasets is the loaded config/dslite-canned-datasets.json$datasets
# list (NULL when not a client-side/fresh-setup scenario) — its enum is
# derived from the SAME list build_test_role_guidance() presents in the
# prompt, so the allowed values can never drift from what Claude was
# actually offered.
build_submit_tests_tool <- function(dslite_datasets) {
  test_item_schema <- list(
    type = "object",
    properties = list(
      description = list(type = "string", description = "The test_that() description string — what behavior this test checks."),
      setup_code = list(type = "string", description = "Raw runnable R code needed only for this specific test (e.g. extra assigns), beyond the shared connection/setup. Empty string if nothing extra is needed."),
      assertions_code = list(type = "string", description = "Raw runnable R code containing the actual expect_*() assertion(s) for this test. No comment markers, no test_that() wrapper — the script adds that.")
    ),
    required = list("description", "setup_code", "assertions_code")
  )

  dataset_names <- if (!is.null(dslite_datasets)) {
    c("", vapply(dslite_datasets, function(d) d$name, character(1)))
  } else {
    NULL
  }

  dslite_dataset_schema <- list(
    type = "string",
    description = "For a fresh DSLite client-side setup only: the chosen canned dataset's name from the options given. Empty string for server-side functions, or when reusing an existing setup.R."
  )
  if (!is.null(dataset_names)) dslite_dataset_schema$enum <- as.list(dataset_names)

  input_schema <- list(
    type = "object",
    properties = list(
      needs_tests = list(type = "boolean", description = "Whether this function actually warrants new tests. False if existing coverage is already adequate despite the heuristic that triggered this review."),
      dslite_dataset = dslite_dataset_schema,
      tests = list(
        type = "array",
        description = "Up to 5 new test_that() blocks. Never touches or duplicates any existing test.",
        items = test_item_schema,
        maxItems = 5
      )
    ),
    required = list("needs_tests", "dslite_dataset", "tests")
  )

  list(
    description = "Submit generated testthat tests as individual structured fields, never as assembled test_that() syntax.",
    input_schema = input_schema
  )
}
