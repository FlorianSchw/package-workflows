# Index of the DESCRIPTION author entry matching a contributor's name, or
# NA. Placeholder: a plain text match of the name in the formatted entry —
# to be replaced by proper name matching (given/family split).
find_author <- function(authors, name) {
  hits <- which(vapply(seq_along(authors), function(i) grepl(name, format(authors[i]), fixed = TRUE), logical(1)))
  if (length(hits) > 0) hits[1] else NA_integer_
}
