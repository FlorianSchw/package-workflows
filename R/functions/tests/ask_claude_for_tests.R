# Sends the test-review request to Claude and returns the submit_tests
# tool call's input — individual structured fields only, never assembled
# test_that() syntax. Besides the function and its test file, Claude gets
# the test setup/helper files verbatim (to use the package's own objects
# and helpers), the structure of the test data they create
# (summarize_test_data()), the existing tests' current results and the history
# evidence, to judge failing tests (outdated vs. possible bug).
ask_claude_for_tests <- function(parsed, existing_test_file, role_text, dslite_datasets, test_results, evidence, max_new_tests, test_data) {
  prompt <- fill_template(test_review_prompt_template, list(
    ROLE_GUIDANCE         = role_text,
    EXISTING_TEST_FILE    = if (nzchar(existing_test_file$content)) existing_test_file$content else "(none yet)",
    TEST_SUPPORT_FILES    = format_test_support_files(test_support_files()),
    TEST_DATA             = test_data,
    EXISTING_TEST_RESULTS = test_results,
    HISTORY_EVIDENCE      = evidence,
    FUNCTION_SOURCE       = fn_source(parsed),
    FUNCTION_NAME         = parsed$fn_name,
    MAX_NEW_TESTS         = as.character(max_new_tests)
  ))

  call_claude_tool(anthropic_config, build_submit_tests_tool(dslite_datasets, max_new_tests), prompt)
}
