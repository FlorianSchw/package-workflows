# What becomes of a generated test that failed (`fail`: its run result,
# `test`: Claude's fields for it, `block_text`: the assembled block, `path`:
# its test file):
# - it failed before (same name, or one Claude says it repeats, among the
#   function's open `earlier` findings): a repeat — not classified,
#   commented or filed again;
# - Claude classifies it (ask_claude_to_classify_failure()) as a real bug
#   with a confidence in `confidences` (code-issue-confidence): a possible
#   bug in the code, with an issue only at high confidence;
# - anything else: a failed test, commented on the PR, or in a sweep (no PR
#   to comment on) listed in the report.
# Returns list(kind = "repeat" / "bug" / "failed", entry), or NULL if the
# classification call failed.
handle_failed_new_test <- function(fail, test, block_text, path, earlier, function_source, function_name, confidences, is_sweep) {
  repeated_id <- if (!is.null(test$repeats_earlier) && nzchar(test$repeats_earlier)) suppressWarnings(as.integer(sub("^E", "", test$repeats_earlier))) else NA_integer_
  failed_before <- function(e) identical(e$kind, "failed") || (identical(e$kind, "bug") && identical(e$origin, "failure"))
  if (any(vapply(earlier, function(e) failed_before(e) && (identical(as.integer(e$id), repeated_id) || identical(e$description, fail$description)), logical(1)))) {
    message(sprintf("%s: '%s' failed again — reported before.", function_name, fail$description))
    return(list(kind = "repeat"))
  }

  classification <- tryCatch(
    ask_claude_to_classify_failure(function_source, block_text, fail$message),
    error = function(e) {
      message(sprintf("Failure classification call failed for %s: %s", function_name, conditionMessage(e)))
      NULL
    }
  )
  if (is.null(classification)) return(NULL)

  if (identical(classification$category, "real_bug") && isTRUE(classification$confidence %in% confidences)) {
    issue <- if (identical(classification$confidence, "high")) create_bug_issue(function_name, block_text, fail$message, classification)
    return(list(kind = "bug", entry = list(
      file = path, description = fail$description, origin = "failure", explanation = classification$explanation,
      confidence = classification$confidence, issue = if (is.null(issue)) "" else issue
    )))
  }
  if (!is_sweep) post_test_failure_comment(function_name, block_text, fail$message, classification)
  list(kind = "failed", entry = list(
    file = path, description = fail$description, classification = classification$category, in_report = is_sweep,
    explanation = if (is_sweep) format_test_failure(function_name, block_text, fail$message, classification) else classification$explanation
  ))
}
