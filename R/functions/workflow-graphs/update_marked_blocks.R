# Updates the generated blocks of .github/workflow-graphs/README.md and
# keeps the text written around them. A block sits between
# `<!-- workflow-graphs:<id>:start -->` and `<!-- workflow-graphs:<id>:end -->`;
# `blocks` is a named list, ID -> content lines ("overview",
# "detail:<file>"), its detail IDs in the order they should appear.
#
# - Other blocks (the overview) are replaced where they are.
# - The detail blocks always follow the order of `blocks`, so a changed
#   order reaches an existing README too. Text written below a detail block
#   — up to the next detail block, or a `#`/`##` heading, which starts a
#   section of its own — belongs to that workflow and moves with it.
# - A deleted workflow's block is removed; text written below it is kept,
#   after the last workflow. A new workflow's block is added in its place
#   in the order.
# - Text above the first detail block, and from such a heading on, stays
#   where it is.
#
# `lines` is the current README (NULL if there is none — then `starter`
# builds the whole file once). Returns the new lines.
update_marked_blocks <- function(lines, blocks, starter) {
  wrap <- function(id) c(sprintf("<!-- workflow-graphs:%s:start -->", id), blocks[[id]], sprintf("<!-- workflow-graphs:%s:end -->", id))
  if (is.null(lines)) return(starter(lapply(stats::setNames(names(blocks), names(blocks)), wrap)))
  is_detail <- function(id) startsWith(id, "detail:")

  # Split the file into items: a block (with its ID) or one line of text.
  items <- list()
  i <- 1
  while (i <= length(lines)) {
    m <- regmatches(lines[i], regexec("^<!-- workflow-graphs:(.+):start -->$", lines[i]))[[1]]
    if (length(m) == 2) {
      end <- which(lines == sprintf("<!-- workflow-graphs:%s:end -->", m[2]))
      end <- end[end > i]
      if (length(end) == 0) stop(sprintf("README block '%s' has no end marker.", m[2]))
      items[[length(items) + 1]] <- list(id = m[2])
      i <- end[1] + 1
    } else {
      items[[length(items) + 1]] <- list(text = lines[i])
      i <- i + 1
    }
  }

  # Other blocks: replaced in place, or dropped if no longer generated.
  render <- function(item) {
    if (!is.null(item$text)) return(item$text)
    if (!is.null(blocks[[item$id]])) wrap(item$id) else character(0)
  }

  starts_section <- function(item) !is.null(item$text) && grepl("^#{1,2} ", item$text)
  first <- Position(function(it) !is.null(it$id) && is_detail(it$id), items)
  detail_ids <- Filter(is_detail, names(blocks))

  if (is.na(first)) {
    # No workflow sections yet: add them at the end.
    head <- unlist(lapply(items, render))
    return(c(head, unlist(lapply(detail_ids, function(id) c("", wrap(id))))))
  }

  # From the first detail block to the next section heading (or another
  # kind of block): each detail block with the text below it.
  units <- list(); orphan_text <- character(0)
  j <- first
  current <- NULL
  while (j <= length(items)) {
    it <- items[[j]]
    if (starts_section(it) || (!is.null(it$id) && !is_detail(it$id))) break
    if (!is.null(it$id)) {
      current <- it$id
      units[[current]] <- character(0)
    } else {
      units[[current]] <- c(units[[current]], it$text)
    }
    j <- j + 1
  }

  for (id in setdiff(names(units), detail_ids)) {
    text <- units[[id]]
    if (any(nzchar(trimws(text)))) orphan_text <- c(orphan_text, text)  # a deleted workflow's notes
  }
  region <- unlist(lapply(detail_ids, function(id) {
    below <- if (!is.null(units[[id]])) units[[id]] else ""
    c(wrap(id), below)
  }))

  head <- unlist(lapply(items[seq_len(first - 1)], render))
  tail <- if (j <= length(items)) unlist(lapply(items[j:length(items)], render)) else character(0)
  c(head, region, orphan_text, tail)
}
