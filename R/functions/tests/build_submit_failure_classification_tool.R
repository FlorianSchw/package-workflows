# Builds the Claude tool-call JSON schema for submit_failure_classification
# — forces the 3-way classification from dev-notes/test-suggest.md
# into a structural enum rather than trusting free text to stay on-category.
# The explanation comes first, then the category and how sure Claude is —
# so the reasoning leads to the verdict, not the other way round (as for
# the roxygen review's possible bugs). The confidence decides whether a
# real_bug is reported as a possible bug, and whether it gets an issue
# (code-issue-confidence; issues only for "high").
build_submit_failure_classification_tool <- function() {
  list(
    description = "Classify why a generated test failed, as exactly one of three distinct categories.",
    input_schema = list(
      type = "object",
      properties = list(
        explanation = list(type = "string", description = "1-3 sentences reasoning it through first, referencing the actual failure output and the function's code."),
        category = list(
          type = "string",
          enum = list("bad_test", "real_bug", "env_misconfiguration"),
          description = paste(
            "bad_test: the test itself is wrong (bad assertion, misunderstood",
            "behavior). real_bug: the test is correct and caught a genuine",
            "defect in the function under test. env_misconfiguration: the",
            "test environment itself is broken (wrong dataset, unregistered",
            "DataSHIELD server method) rather than the test or the function",
            "being wrong."
          )
        ),
        confidence = list(type = "string", enum = list("high", "medium", "low"), description = "How sure you are of the category.")
      ),
      required = list("explanation", "category", "confidence")
    )
  )
}
