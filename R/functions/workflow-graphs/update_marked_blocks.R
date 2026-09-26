# Updates the generated blocks of .github/workflow-graphs/README.md and leaves
# everything else alone. A block sits between
# `<!-- workflow-graphs:<id>:start -->` and `<!-- workflow-graphs:<id>:end -->`
# and is found by its ID, not its position, so text written around the
# blocks and the order of the blocks stay as the user left them.
# `blocks` is a named list, ID -> content lines ("overview",
# "detail:<file>"). Blocks whose ID is no longer in `blocks` (a deleted
# workflow) are removed; new ones are inserted after the last detail block,
# or at the end. `lines` is the current README (NULL if there is none —
# then `starter` builds the whole file once). Returns the new lines.
update_marked_blocks <- function(lines, blocks, starter) {
  wrap <- function(id) c(sprintf("<!-- workflow-graphs:%s:start -->", id), blocks[[id]], sprintf("<!-- workflow-graphs:%s:end -->", id))
  if (is.null(lines)) return(starter(lapply(stats::setNames(names(blocks), names(blocks)), wrap)))

  out <- character(0)
  seen <- character(0)
  last_detail <- NA
  i <- 1
  while (i <= length(lines)) {
    m <- regmatches(lines[i], regexec("^<!-- workflow-graphs:(.+):start -->$", lines[i]))[[1]]
    if (length(m) == 2) {
      id <- m[2]
      end <- which(lines == sprintf("<!-- workflow-graphs:%s:end -->", id))
      end <- end[end > i]
      if (length(end) == 0) stop(sprintf("README block '%s' has no end marker.", id))
      if (!is.null(blocks[[id]])) {
        out <- c(out, wrap(id))
        seen <- c(seen, id)
        if (startsWith(id, "detail:")) last_detail <- length(out)
      } else if (end[1] < length(lines) && !nzchar(lines[end[1] + 1])) {
        end[1] <- end[1] + 1  # drop the blank line after a removed block too
      }
      i <- end[1] + 1
    } else {
      out <- c(out, lines[i])
      i <- i + 1
    }
  }

  new_ids <- setdiff(names(blocks), seen)
  if (length(new_ids) > 0) {
    added <- unlist(lapply(new_ids, function(id) c("", wrap(id))))
    at <- if (is.na(last_detail)) length(out) else last_detail
    out <- append(out, added, after = at)
  }
  out
}
