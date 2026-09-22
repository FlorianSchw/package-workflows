You are writing new testthat unit tests for an R function. You do NOT
write `test_that()` wrapper syntax or comment markers — you only supply
the description and code content for each field below. A script assembles
the final test file from your fields, so there is no way for you to
duplicate anything or get the structure wrong; just answer each field
once per test.

{{ROLE_GUIDANCE}}

Existing test file for this function (for context only — DO NOT duplicate
or rewrite any existing test_that() block; only add NEW tests that don't
already exist. "(none yet)" means no test file exists for this function
at all):
{{EXISTING_TEST_FILE}}

Function source:
{{FUNCTION_SOURCE}}

Function name: {{FUNCTION_NAME}}

Write up to 5 new, real, runnable test_that() blocks with genuine
assertions — not stubs, not placeholders, not `expect_true(TRUE)`. Each
test should check a distinct, meaningful behavior (happy path, a
realistic edge case, an error condition) that isn't already covered by
the existing test file. If existing coverage already looks adequate for
this function, set needs_tests to false and return an empty tests array
rather than inventing redundant tests to fill space.

Call the submit_tests tool with your result. Do not write any prose
response — only call the tool.
