# Reads a text file (e.g. a prompt template) as a single string — see
# resolve_shared_path() for where it's looked up.
read_text_file <- function(rel_path) {
  paste(readLines(resolve_shared_path(rel_path), warn = FALSE), collapse = "\n")
}
