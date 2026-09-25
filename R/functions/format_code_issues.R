# "Possible bugs in the code (n)": defects Claude noticed while reviewing
# the documentation, one collapsible group per file. Nothing is changed in
# the code. `files` is a list of list(path, issues), issues as returned in
# the roxygen tool's code_issues field.
format_code_issues <- function(files) {
  files <- Filter(function(f) length(f$issues) > 0, files)
  n <- sum(vapply(files, function(f) length(f$issues), integer(1)))
  if (n == 0) return(character(0))

  c(
    sprintf("## Possible bugs in the code (%d)", n),
    "",
    "Noticed while reviewing the documentation — nothing in the code was changed. Please check.",
    "",
    unlist(lapply(files, function(f) {
      c(sprintf("<details><summary><h3>%s (%d)</h3></summary>", f$path, length(f$issues)), "",
        vapply(f$issues, function(i) sprintf("- **%s** %s", i$summary, i$explanation), character(1)),
        "", "</details>", "")
    }))
  )
}
