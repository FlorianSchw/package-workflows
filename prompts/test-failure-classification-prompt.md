Generated testthat tests for one R function failed when actually run.
Classify WHY each one failed into exactly one of three categories: the
test itself is wrong (bad_test), the test is correct and caught a genuine
bug in the function (real_bug), or the test environment itself is
misconfigured (env_misconfiguration) — e.g. wrong dataset, unregistered
DataSHIELD server method — rather than either the test or the function
being wrong.

Function under test:
{{FUNCTION_SOURCE}}

The failed tests, each with its label:

{{FAILURES}}

For each failure, reason it through in `explanation` first, then give
the category and how confident you are. Choose real_bug only when the
test's expectation is clearly what the function is meant to do; when the
intended behaviour is unclear, say so with a lower confidence. Judge
each failure on its own; several can share one cause.

Call the submit_failure_classification tool with one entry per listed
failure. Do not write any prose response — only call the tool.
