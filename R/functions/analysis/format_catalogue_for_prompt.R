# The package catalogue as prompt text: one line per server-side package
# that isn't retired and isn't already installed, with its description and
# status. Client packages are left out: notes name the server package (the
# one the study servers need), its client follows by name. Returns
# list(text, names); `names` is the enum for other_package notes.
format_catalogue_for_prompt <- function(catalogue, installed) {
  keep <- names(catalogue)[vapply(catalogue, function(p) !identical(p$status, "retired"), logical(1))]
  keep <- setdiff(keep[!grepl("Client$", keep)], installed)
  if (length(keep) == 0) return(list(text = "(not available)", names = character(0)))
  lines <- vapply(keep, function(n) {
    p <- catalogue[[n]]
    status <- if (nzchar(p$status)) sprintf(" [%s]", p$status) else ""
    sprintf("- %s%s: %s", n, status, p$description)
  }, character(1))
  list(text = paste(lines, collapse = "\n"), names = keep)
}
