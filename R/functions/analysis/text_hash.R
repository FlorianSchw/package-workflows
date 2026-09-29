# Short, stable hash of some text lines (first 12 hex characters of the
# MD5 of the lines joined with "\n", in UTF-8), used in the marker line of
# generated scripts to notice edits and plan changes. Computed in memory,
# so it is the same on every platform, whatever line endings files have.
text_hash <- function(lines) {
  bytes <- charToRaw(enc2utf8(paste(as.character(lines), collapse = "\n")))
  substr(unname(tools::md5sum(bytes = bytes)), 1, 12)
}
