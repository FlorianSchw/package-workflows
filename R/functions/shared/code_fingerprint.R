# A short fingerprint of a function's code (fn_source()), stored with
# each finding, so a declined suggestion stays declined only until the
# code changes (declined_suggestions()). Whitespace-only changes don't
# count.
code_fingerprint <- function(code) {
  normalized <- gsub("[[:space:]]+", " ", trimws(paste(code, collapse = "\n")))
  tmp <- tempfile()
  on.exit(unlink(tmp))
  writeLines(normalized, tmp, useBytes = TRUE)
  substr(unname(tools::md5sum(tmp)), 1, 12)
}
