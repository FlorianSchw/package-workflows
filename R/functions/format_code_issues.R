# "Possible bugs in the code (n)": defects Claude noticed while reviewing
# the documentation, one collapsible group per file. Nothing is changed in
# the code. `files` is a list of list(path, issues), issues as returned in
# the roxygen tool's code_issues field; `style` from report_style().
format_code_issues <- function(files, style = report_style()) {
  files <- Filter(function(f) length(f$issues) > 0, files)
  n <- sum(vapply(files, function(f) length(f$issues), integer(1)))
  if (n == 0) return(character(0))

  c(
    report_heading(sprintf("Possible bugs in the code (%d)", n), style),
    "",
    "Noticed while reviewing the documentation — nothing in the code was changed. Please check.",
    "",
    report_groups(lapply(files, function(f) {
      list(title = sprintf("%s (%d)", f$path, length(f$issues)),
           lines = vapply(f$issues, function(i) sprintf("- **%s** %s", i$summary, i$explanation), character(1)))
    }), style)
  )
}
