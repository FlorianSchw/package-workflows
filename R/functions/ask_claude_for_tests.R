# Sends the test-generation request to Claude and returns the submit_tests
# tool call's input — individual structured fields only, never assembled
# test_that() syntax. Mirrors roxygen-suggest.yml's ask_claude() closely.
ask_claude_for_tests <- function(function_name, function_source, existing_test_file, role_text, dslite_datasets) {
  existing_block <- if (nzchar(existing_test_file$content)) existing_test_file$content else "(none yet)"

  prompt <- test_review_prompt_template
  prompt <- gsub("{{ROLE_GUIDANCE}}", role_text, prompt, fixed = TRUE)
  prompt <- gsub("{{EXISTING_TEST_FILE}}", existing_block, prompt, fixed = TRUE)
  prompt <- gsub("{{FUNCTION_SOURCE}}", function_source, prompt, fixed = TRUE)
  prompt <- gsub("{{FUNCTION_NAME}}", function_name, prompt, fixed = TRUE)

  submit_tests_tool <- build_submit_tests_tool(dslite_datasets)

  call_claude_tool(anthropic_config, submit_tests_tool, prompt)
}
