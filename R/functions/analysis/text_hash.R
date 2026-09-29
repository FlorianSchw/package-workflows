# Short, stable hash of some text lines (first 12 hex characters of their
# MD5), used in the marker line of generated scripts to notice edits and
# plan changes.
text_hash <- function(lines) {
  f <- tempfile()
  on.exit(unlink(f))
  writeLines(enc2utf8(as.character(lines)), f, useBytes = TRUE)
  substr(unname(tools::md5sum(f)), 1, 12)
}
