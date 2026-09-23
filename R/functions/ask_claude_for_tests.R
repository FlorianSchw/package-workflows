# Sends the test-generation request to Claude and returns the submit_tests
# tool call's input — individual structured fields only, never assembled
# test_that() syntax.
ask_claude_for_tests <- function(parsed, existing_test_file, role_text, dslite_datasets) {
  prompt <- fill_template(test_review_prompt_template, list(
    ROLE_GUIDANCE      = role_text,
    EXISTING_TEST_FILE = if (nzchar(existing_test_file$content)) existing_test_file$content else "(none yet)",
    FUNCTION_SOURCE    = fn_source(parsed),
    FUNCTION_NAME      = parsed$fn_name
  ))

  call_claude_tool(anthropic_config, build_submit_tests_tool(dslite_datasets), prompt)
}
