# Builds the Claude tool-call JSON schema for submit_review — flat, one
# level per field — with per-field descriptions sourced from the selected
# style profile's guidance text. `changes` names every changed field with
# a reason from a fixed list; accepted_roxygen_fields() keeps only the
# accepted reasons. "clarity" and "style" are the honest way out for
# changes that aren't real improvements — see
# dev-notes/suggestion-thresholds.md.
#
# Possible code bugs are asked for reasoning first: explanation, then a
# verdict and a confidence, the one-line summary last — so Claude can't
# commit to a claim in the summary that its own reasoning then refutes
# (seen on dsSurvivalClient PR #37). kept_code_issues() filters them.
#
# `earlier` are this bot's open earlier findings on the function
# (format_earlier_findings()): Claude marks a change or code issue that
# repeats one (`repeats_earlier`, an enum of their ids) and judges each in
# `earlier_findings`; merge_roxygen_findings() applies both.
build_submit_review_tool <- function(parsed, profile, earlier = list()) {
  earlier_ids <- function(kinds) {
    ids <- vapply(Filter(function(e) e$kind %in% kinds, earlier), function(e) sprintf("E%d", e$id), character(1))
    if (length(ids) == 0) return(NULL)
    list(type = "string", enum = as.list(c("", ids)),
         description = "The id of an earlier finding (listed in the prompt) that this one says the same as, also in other words; empty string if it is new.")
  }
  repeats_change <- earlier_ids("dropped")
  repeats_issue <- earlier_ids("bug")
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

  field_keys <- c("title", "description", "details", "return", "examples", paste0("param:", parsed$params))
  changes_schema <- list(
    type = "array",
    description = "One entry per field you changed. Leave out fields you returned unchanged.",
    items = list(
      type = "object",
      properties = list(
        field = list(type = "string", enum = as.list(field_keys)),
        reason = list(
          type = "string",
          enum = as.list(suggestion_reasons("roxygen")),
          description = paste(
            "missing: the field is absent or a placeholder. inaccurate: the existing text states something",
            "the code doesn't do (a default, a type, argument handling, the return shape) — even if the fix is",
            "a small wording change. incomplete: it leaves out something the code does. clarity: correct and",
            "complete, but could be clearer. style: formatting or wording only."
          )
        ),
        explanation = list(type = "string", description = "One sentence: what was wrong or missing, citing the code where it matters.")
      ),
      required = list("field", "reason", "explanation")
    )
  )
  if (!is.null(repeats_change)) {
    changes_schema$items$properties$repeats_earlier <- repeats_change
    changes_schema$items$required <- c(changes_schema$items$required, list("repeats_earlier"))
  }

  issue_properties <- list(
    explanation = list(type = "string", description = "First reason it through: what the code does, citing the relevant lines, and whether that really is wrong (consider R's scoping and evaluation rules). Write this before deciding."),
    verdict = list(type = "string", enum = list("defect", "not_a_defect", "unsure"),
                   description = "Your conclusion from the explanation: a real defect, not a defect after all, or unsure."),
    confidence = list(type = "string", enum = list("high", "medium", "low"),
                      description = "How sure you are of the verdict."),
    summary = list(type = "string", description = "One sentence: what the code does wrong. Must agree with the explanation and verdict.")
  )
  if (!is.null(repeats_issue)) issue_properties$repeats_earlier <- repeats_issue

  top_level_properties <- list(
    needs_changes = list(type = "boolean", description = "Whether any field needs to change."),
    changes = changes_schema,
    title = list(type = "string", description = sprintf("Plain-text title, no markup. %s", profile$title$guidance)),
    description = list(type = "string", description = sprintf("Plain-text description prose. %s", profile$description$guidance)),
    details = list(type = "string", description = sprintf("Plain-text details prose, empty string if not applicable. %s", profile$details$guidance)),
    return_doc = list(type = "string", description = sprintf("Plain-text description of the return value. %s", profile$return$guidance)),
    examples_body = list(type = "string", description = sprintf("Raw runnable example code only, no comment markers, no tag label, no wrapper syntax, empty string if not required. %s", profile$examples$guidance)),
    params = params_schema,
    code_issues = list(
      type = "array",
      description = "Likely defects in the function's code noticed during the review — not documentation problems, not style. Empty array if none.",
      items = list(
        type = "object",
        properties = issue_properties,
        required = as.list(names(issue_properties))
      )
    )
  )
  required <- list("needs_changes", "changes", "title", "description", "return_doc", "params", "code_issues")

  if (length(earlier) > 0) {
    top_level_properties$earlier_findings <- list(
      type = "array",
      description = "Your judgement of each earlier finding listed in the prompt.",
      items = list(
        type = "object",
        properties = list(
          id = list(type = "string", enum = as.list(vapply(earlier, function(e) sprintf("E%d", e$id), character(1)))),
          status = list(type = "string", enum = list("still_valid", "superseded", "resolved"),
                        description = "still_valid: still correct and open. superseded: no longer correct, e.g. the code changed or it was wrong. resolved: the code or documentation now does what it asked for."),
          note = list(type = "string", description = "One sentence why, for superseded or resolved; empty string for still_valid.")
        ),
        required = list("id", "status", "note")
      )
    )
    required <- c(required, list("earlier_findings"))
  }

  input_schema <- list(
    type = "object",
    properties = top_level_properties,
    required = required
  )

  list(
    description = "Submit the roxygen2 documentation review as individual prose fields, never as assembled roxygen text.",
    input_schema = input_schema
  )
}
