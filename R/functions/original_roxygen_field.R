# The existing block's content for one Claude-managed field ("title",
# "description", "details", "return", "examples" or "param:<name>"):
# `lines` are the raw roxygen lines to carry forward unchanged, `text` the
# plain prose for comparison (markers, tag label and \dontrun wrapper
# removed). NULL if the existing block has no such tag.
original_roxygen_field <- function(parsed, key) {
  is_param <- startsWith(key, "param:")
  chunks <- Filter(function(ch) ch$tag == if (is_param) "param" else key, parsed$tag_chunks)
  if (is_param) {
    name <- sub("^param:", "", key)
    chunks <- Filter(function(ch) identical(sub("^\\s*#'\\s*@param\\s+(\\S+).*$", "\\1", ch$lines[1]), name), chunks)
  }
  if (length(chunks) == 0) return(NULL)

  lines <- chunks[[1]]$lines
  text <- sub("^\\s*#'\\s?", "", lines)
  text[1] <- sub(if (is_param) "^@param\\s+\\S+\\s*" else "^@[A-Za-z]+\\s*", "", text[1])
  text <- text[!grepl("^\\s*(\\\\dontrun\\{|\\})\\s*$", text)]
  list(lines = lines, text = paste(text, collapse = "\n"))
}
