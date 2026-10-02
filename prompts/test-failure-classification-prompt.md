A generated testthat test failed when actually run. Classify WHY it
failed into exactly one of three categories: the test itself is wrong
(bad_test), the test is correct and caught a genuine bug in the function
(real_bug), or the test environment itself is misconfigured
(env_misconfiguration) — e.g. wrong dataset, unregistered DataSHIELD
server method — rather than either the test or the function being wrong.

Function under test:
{{FUNCTION_SOURCE}}

Generated test that failed:
{{TEST_BLOCK}}

Failure output:
{{FAILURE_MESSAGE}}

Reason it through in `explanation` first, then give the category and how
confident you are. Choose real_bug only when the test's expectation is
clearly what the function is meant to do; when the intended behaviour is
unclear, say so with a lower confidence.

Call the submit_failure_classification tool with your result. Do not
write any prose response — only call the tool.
