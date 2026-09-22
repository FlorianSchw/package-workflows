# Builds the Claude tool-call JSON schema for submit_failure_classification
# — forces the 3-way classification from test-coverage-workflow-design-notes.md
# into a structural enum rather than trusting free text to stay on-category.
build_submit_failure_classification_tool <- function() {
  list(
    name = failure_classification_config$tool_name,
    description = "Classify why a generated test failed, as exactly one of three distinct categories.",
    input_schema = list(
      type = "object",
      properties = list(
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
        explanation = list(type = "string", description = "1-3 sentences explaining the classification, referencing the actual failure output.")
      ),
      required = list("category", "explanation")
    )
  )
}
