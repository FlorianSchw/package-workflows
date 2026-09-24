# Threshold for roxygen suggestions (see dev-notes/suggestion-thresholds.md):
# a field Claude changed is accepted only if its stated reason is in
# accept_reasons AND its text differs from the existing one by more than
# whitespace, punctuation or case. Fields Claude changed without listing
# them aren't accepted either. Returns the accepted field keys; every
# dropped change is logged with why.
accepted_roxygen_fields <- function(result, parsed, accept_reasons, path) {
  normalize <- function(x) trimws(gsub("[[:space:][:punct:]]+", " ", tolower(paste(x, collapse = " "))))
  accepted <- character(0)

  for (change in result$changes) {
    key <- change$field
    if (!isTRUE(change$reason %in% accept_reasons)) {
      message(sprintf("%s: dropping change to '%s' — reason '%s' is not accepted.", path, key, change$reason))
      next
    }
    original <- original_roxygen_field(parsed, key)
    if (!is.null(original) && identical(normalize(original$text), normalize(roxygen_field_text(result, key)))) {
      message(sprintf("%s: dropping change to '%s' — only whitespace, punctuation or case differ.", path, key))
      next
    }
    accepted <- c(accepted, key)
  }
  unique(accepted)
}
