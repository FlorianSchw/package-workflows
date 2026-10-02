# Sends the test-review request to Claude and returns the submit_tests
# tool call's input — individual structured fields only, never assembled
# test_that() syntax. Besides the function and its test files, Claude gets
# the test setup/helper files and the files they source verbatim (to use
# the package's own objects, connection helpers and helpers), example test
# files of other functions when this one has none yet, how the repository
# names its test files, the structure of the test data
# (summarize_test_data()), the existing tests' current results and the
# history evidence, to judge failing tests (outdated vs. possible bug),
# and this bot's open earlier findings (`context$earlier`) to judge and not
# repeat.
# `context` bundles the per-run and per-function inputs; see
# R/suggest_tests.R.
ask_claude_for_tests <- function(parsed, context) {
  prompt <- fill_template(test_review_prompt_template, list(
    ROLE_GUIDANCE         = context$role_text,
    TEST_FILE_SCHEME      = context$scheme_text,
    EXISTING_TEST_FILES   = format_test_files(context$test_files, "(none yet)"),
    EXAMPLE_TEST_FILES    = format_test_files(context$examples, "(not needed: the function has tests)", max_chars = 8000),
    TEST_SUPPORT_FILES    = format_test_support_files(context$support_files),
    TEST_DATA             = context$test_data,
    EXISTING_TEST_RESULTS = context$test_results,
    HISTORY_EVIDENCE      = context$evidence,
    FUNCTION_SOURCE       = fn_source(parsed),
    FUNCTION_NAME         = parsed$fn_name,
    MAX_NEW_TESTS         = as.character(context$max_new_tests),
    EARLIER_FINDINGS      = format_earlier_test_findings(context$earlier)
  ))

  tool <- build_submit_tests_tool(
    context$dslite_datasets, context$max_new_tests,
    categories = context$categories,
    existing_file_names = vapply(context$test_files, function(f) basename(f$path), character(1)),
    earlier = context$earlier
  )
  call_claude_tool(anthropic_config, tool, prompt)
}
