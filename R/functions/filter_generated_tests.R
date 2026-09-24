# Threshold for generated tests (see dev-notes/suggestion-thresholds.md):
# keeps a test only if Claude's reason is in accept_reasons and its
# assertions aren't already in the existing test file verbatim (ignoring
# whitespace). Everything dropped is logged with why.
filter_generated_tests <- function(tests, existing_content, accept_reasons, function_name) {
  squash <- function(x) gsub("\\s+", "", x)
  existing <- squash(existing_content)

  Filter(function(t) {
    if (!isTRUE(t$reason %in% accept_reasons)) {
      message(sprintf("%s: dropping test '%s' — reason '%s' is not accepted.", function_name, t$description, t$reason))
      return(FALSE)
    }
    assertions <- squash(t$assertions_code)
    if (nzchar(existing) && nzchar(assertions) && grepl(assertions, existing, fixed = TRUE)) {
      message(sprintf("%s: dropping test '%s' — its assertions already exist.", function_name, t$description))
      return(FALSE)
    }
    TRUE
  }, tests)
}
