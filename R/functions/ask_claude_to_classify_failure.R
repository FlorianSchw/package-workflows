# Sends a failing generated test + its failure output to Claude for the
# 3-way classification (bad_test / real_bug / env_misconfiguration) — a
# judgment call made AFTER the test fails, using the actual failure output,
# not guessed upfront. Uses the separate "test-failure-classification"
# config.yml profile (its own model/tool settings), not "test-review" —
# this is the second Claude-calling function anticipated when config.yml
# was first designed with multiple named profiles in mind.
ask_claude_to_classify_failure <- function(function_source, test_block, failure_message) {
  prompt <- sprintf(paste(
    "A generated testthat test failed when actually run. Classify WHY it",
    "failed into exactly one of three categories: the test itself is",
    "wrong (bad_test), the test is correct and caught a genuine bug in",
    "the function (real_bug), or the test environment itself is",
    "misconfigured (env_misconfiguration) — e.g. wrong dataset,",
    "unregistered DataSHIELD server method — rather than either the test",
    "or the function being wrong.",
    "",
    "Function under test:",
    "%s",
    "",
    "Generated test that failed:",
    "%s",
    "",
    "Failure output:",
    "%s",
    "",
    "Call the submit_failure_classification tool with your result. Do not",
    "write any prose response — only call the tool.",
    sep = "\n"
  ), function_source, test_block, failure_message)

  submit_tool <- build_submit_failure_classification_tool()

  call_claude_tool(failure_classification_config, submit_tool, prompt)
}
