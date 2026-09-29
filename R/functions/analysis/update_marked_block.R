# Replaces the lines between a start and an end marker line in a file
# (markers kept), or appends a new marked block at the end if the file has
# none. Everything outside the block stays as the analyst wrote it.
# Creates the file if it doesn't exist. Returns TRUE if the file changed.
update_marked_block <- function(path, start_marker, end_marker, content) {
  old <- if (file.exists(path)) readLines(path, warn = FALSE) else character(0)
  start <- which(old == start_marker)
  end <- which(old == end_marker)
  block <- c(start_marker, content, end_marker)

  new <- if (length(start) == 1 && length(end) == 1 && end > start) {
    c(old[seq_len(start - 1)], block, old[-seq_len(end)])
  } else {
    c(old, if (length(old) > 0 && nzchar(old[length(old)])) "", block)
  }
  if (identical(new, old)) return(FALSE)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(new, path)
  TRUE
}
