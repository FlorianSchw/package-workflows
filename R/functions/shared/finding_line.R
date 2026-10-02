# One report list item for a stored finding (merge_roxygen_findings(),
# merge_test_findings()):
# "- <text> _(1b4922c)_", with the commit it came from. A crossed-out
# finding shows only `short`, struck through, with when and why:
# "- ~~<short>~~ _(1b4922c · superseded in ed1fbb9: the code changed)_".
finding_line <- function(e, text, short = text) {
  origin <- if (nzchar(e$sha)) e$sha else character(0)
  if (identical(e$status, "active")) {
    return(if (length(origin) > 0) sprintf("- %s _(%s)_", text, origin) else paste("-", text))
  }
  change <- sprintf("%s%s%s", e$status, if (nzchar(e$status_sha)) paste(" in", e$status_sha) else "", if (nzchar(e$status_note)) paste0(": ", e$status_note) else "")
  sprintf("- ~~%s~~ _(%s)_", short, paste(c(origin, change), collapse = " · "))
}
