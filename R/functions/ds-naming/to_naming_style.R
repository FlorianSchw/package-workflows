# An argument name in the rules' general style: words split at ".", "_"
# and camelCase boundaries, lower case, joined by `separator` (e.g.
# idCol -> id.col, time_col -> time.col with "."). Leading dots (internal
# names) are kept.
to_naming_style <- function(name, separator) {
  lead <- regmatches(name, regexpr("^\\.*", name))
  core <- sub("^\\.*", "", name)
  core <- gsub("([a-z0-9])([A-Z])", "\\1 \\2", core)
  # an acronym before a word (CIlevel -> ci level), not a plural (NAs -> nas)
  core <- gsub("([A-Z]+)([A-Z][a-z]{2,})", "\\1 \\2", core)
  words <- tolower(strsplit(core, "[._ ]+")[[1]])
  paste0(lead, paste(words[nzchar(words)], collapse = separator))
}
