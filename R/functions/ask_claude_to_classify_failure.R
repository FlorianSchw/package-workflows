# Sends a failing generated test + its failure output to Claude for the
# 3-way classification (bad_test / real_bug / env_misconfiguration) — a
# judgment call made AFTER the test fails, using the actual failure output,
# not guessed upfront. Uses its own "test-failure-classification"
# config/claude.yml profile, not "test-review".
ask_claude_to_classify_failure <- function(function_source, test_block, failure_message) {
  prompt <- fill_template(failure_classification_prompt_template, list(
    FUNCTION_SOURCE = function_source,
    TEST_BLOCK      = test_block,
    FAILURE_MESSAGE = failure_message
  ))

  call_claude_tool(failure_classification_config, build_submit_failure_classification_tool(), prompt)
}
