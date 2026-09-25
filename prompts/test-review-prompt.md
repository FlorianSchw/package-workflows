You are reviewing and extending the testthat tests of an R function. You
do NOT write `test_that()` wrapper syntax or comment markers — you only
supply the description and code content for each field below. A script
assembles the final test file from your fields, runs every new and
changed test, and only proposes the ones that pass.

{{ROLE_GUIDANCE}}

Function name: {{FUNCTION_NAME}}

Function source:
{{FUNCTION_SOURCE}}

Existing test file for this function ("(none yet)" means there is none):
{{EXISTING_TEST_FILE}}

Current results of the existing tests, before any change:
{{EXISTING_TEST_RESULTS}}

History of the function and its tests:
{{HISTORY_EVIDENCE}}

## New tests

Write up to {{MAX_NEW_TESTS}} new, real, runnable tests where they add
value — code paths, errors, edge cases or likely regressions the existing
tests don't cover. Give each the reason that honestly fits; use "other" if
none does. If the existing tests already cover the function well, set
needs_tests to false and return an empty tests array rather than
inventing tests to fill space.

Quality rules for every test you write:
- Assert concrete values from the known test data (exact counts, levels,
  dimensions), not just a class or a loose pattern.
- No conditional assertions such as `if (...) expect_...` — every test
  must always assert something.
- Test each error branch once; don't repeat the same check with a
  different bad input unless the input takes a different code path.
- The description states exactly what is asserted, and nothing it
  doesn't assert.

## Existing tests

List in existing_tests only the tests that need action; leave out tests
that are fine.

- A **failing** test: decide from the evidence *why* it fails.
  - The function's behavior was changed on purpose — for example the diff
    of this pull request changes its contract, and the function changed
    after the test — and the test still expects the old behavior: action
    "update", reason "contract_changed". Give the corrected body; the test
    keeps its description.
  - The test describes sensible behavior that the code no longer
    delivers, and nothing shows the change was intended: action "report",
    reason "possible_code_bug". Never adjust a test to match output that
    may be wrong — that would hide the bug.
- A test that duplicates another existing test, tests behavior the
  function no longer has, or asserts nothing meaningful: action "delete"
  with that reason. Don't delete or rewrite a test only because it could
  be written differently.
- Passing tests are not rewritten.

Copy each existing test's description exactly. Fill setup_code and
assertions_code only for "update"; use empty strings otherwise.

Call the submit_tests tool with your result. Do not write any prose
response — only call the tool.
