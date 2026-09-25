# Builds the Claude tool-call JSON schema for submit_tests. Same
# deterministic-assembly principle as roxygen-suggest's
# build_submit_review_tool(): Claude returns discrete fields (never
# assembled test_that() syntax), the R script does the actual stitching.
# The cap on new tests is enforced structurally via maxItems
# (max_new_tests in config/claude.yml), not just prompt wording.
#
# Each new test carries a `reason` from a fixed list; filter_generated_tests()
# keeps only the reasons accepted in config/claude.yml. "other" is the
# honest way out for a test that adds no real value. Decisions on existing
# tests (update / delete / report) are checked by review_existing_tests() —
# see dev-notes/suggestion-thresholds.md.
#
# dslite_datasets is the loaded config/dslite-canned-datasets.json$datasets
# list (NULL when not a client-side/fresh-setup scenario) — its enum is
# derived from the SAME list build_test_role_guidance() presents in the
# prompt, so the allowed values can never drift from what Claude was
# actually offered.
build_submit_tests_tool <- function(dslite_datasets, max_new_tests) {
  code_fields <- list(
    setup_code = list(type = "string", description = "Raw runnable R code needed only for this specific test (e.g. extra assigns), beyond the shared connection/setup. Empty string if nothing extra is needed."),
    assertions_code = list(type = "string", description = "Raw runnable R code containing the actual expect_*() assertion(s) for this test. No comment markers, no test_that() wrapper — the script adds that.")
  )

  test_item_schema <- list(
    type = "object",
    properties = c(list(
      description = list(type = "string", description = "The test_that() description — says exactly what is asserted."),
      reason = list(
        type = "string",
        enum = as.list(suggestion_reasons("tests")),
        description = paste(
          "Why this test adds value. uncovered_branch: a code path no existing test reaches.",
          "error_handling: an error or warning the function raises. edge_case: unusual but valid input",
          "(NA, empty, boundary values). regression: pins down behavior likely to break on change.",
          "other: none of these."
        )
      )
    ), code_fields),
    required = list("description", "reason", "setup_code", "assertions_code")
  )

  existing_item_schema <- list(
    type = "object",
    properties = c(list(
      description = list(type = "string", description = "The existing test_that() description, copied exactly."),
      action = list(
        type = "string",
        enum = list("update", "delete", "report"),
        description = "update: replace the test's body (keeps its description). delete: remove the test. report: leave it unchanged and report it."
      ),
      reason = list(
        type = "string",
        enum = list("contract_changed", "duplicate", "behavior_removed", "trivial", "possible_code_bug"),
        description = paste(
          "contract_changed (with update): the function's behavior was changed on purpose and the test still",
          "expects the old behavior. duplicate / behavior_removed / trivial (with delete): another test checks",
          "the same thing / the tested behavior no longer exists / asserts nothing meaningful.",
          "possible_code_bug (with report): the test describes sensible behavior the code no longer delivers."
        )
      ),
      explanation = list(type = "string", description = "One or two sentences why, citing the evidence (history, diff, failure output).")
    ), code_fields),
    required = list("description", "action", "reason", "explanation", "setup_code", "assertions_code")
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
      needs_tests = list(type = "boolean", description = "Whether new tests would add real value. False if the existing tests already cover the function's behavior well."),
      dslite_dataset = dslite_dataset_schema,
      tests = list(
        type = "array",
        description = sprintf("Up to %d new test_that() blocks. Never duplicates an existing test.", max_new_tests),
        items = test_item_schema,
        maxItems = max_new_tests
      ),
      existing_tests = list(
        type = "array",
        description = "Decisions on existing tests that need action. Leave out tests that are fine — an empty array is the normal case.",
        items = existing_item_schema
      )
    ),
    required = list("needs_tests", "dslite_dataset", "tests", "existing_tests")
  )

  list(
    description = "Submit new and changed testthat tests as individual structured fields, never as assembled test_that() syntax.",
    input_schema = input_schema
  )
}
