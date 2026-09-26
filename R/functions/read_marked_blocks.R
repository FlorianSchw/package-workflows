# The generated blocks currently in the README (see
# update_marked_blocks()), as a named list, ID -> content lines without the
# markers. Used in a pull request to see which diagrams the PR changes.
# Returns an empty list for a README without blocks, or none at all (NULL).
read_marked_blocks <- function(lines) {
  blocks <- list()
  starts <- grep("^<!-- workflow-graphs:.+:start -->$", lines)
  for (s in starts) {
    id <- sub("^<!-- workflow-graphs:(.+):start -->$", "\\1", lines[s])
    end <- which(lines == sprintf("<!-- workflow-graphs:%s:end -->", id))
    end <- end[end > s]
    if (length(end) > 0) blocks[[id]] <- lines[seq_len(end[1] - s - 1) + s]
  }
  blocks
}
