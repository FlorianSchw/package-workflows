# Builds the Claude tool-call JSON schema for submit_review — flat, one
# level per field — with per-field descriptions sourced from the selected
# style profile's guidance text.
build_submit_review_tool <- function(parsed, profile) {
  param_properties <- setNames(
    lapply(parsed$params, function(p) {
      list(type = "string", description = sprintf("Documentation prose for parameter '%s'.", p))
    }),
    parsed$params
  )

  params_schema <- list(
    type = "object",
    description = "One entry per function parameter, keyed by exact parameter name.",
    properties = param_properties,
    required = as.list(parsed$params)
  )

  top_level_properties <- list(
    needs_changes = list(type = "boolean", description = "Whether any field needs to change."),
    changed_tags = list(type = "array", items = list(type = "string"), description = "Names of fields actually changed."),
    title = list(type = "string", description = sprintf("Plain-text title, no markup. %s", profile$title$guidance)),
    description = list(type = "string", description = sprintf("Plain-text description prose. %s", profile$description$guidance)),
    details = list(type = "string", description = sprintf("Plain-text details prose, empty string if not applicable. %s", profile$details$guidance)),
    return_doc = list(type = "string", description = sprintf("Plain-text description of the return value. %s", profile$return$guidance)),
    examples_body = list(type = "string", description = sprintf("Raw runnable example code only, no comment markers, no tag label, no wrapper syntax, empty string if not required. %s", profile$examples$guidance)),
    params = params_schema
  )

  input_schema <- list(
    type = "object",
    properties = top_level_properties,
    required = list("needs_changes", "changed_tags", "title", "description", "return_doc", "params")
  )

  list(
    description = "Submit the roxygen2 documentation review as individual prose fields, never as assembled roxygen text.",
    input_schema = input_schema
  )
}
