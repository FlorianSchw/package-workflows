# The test workflow's report (see publish_test_report() for where it goes),
# laid out like the roxygen report: a section per kind with its count —
# "Changes to existing tests (n)", "Existing tests to look at (n)",
# "Generated tests that failed (n)" — and in each a collapsible group per
# test file. `changes`, `notes` and `failures` are named lists, test file
# path -> entries (Markdown lines, or blocks from format_test_failure()).
# Heading levels and spacing come from config/report-style.yml.
format_test_report <- function(summary_line, changes, notes, failures) {
  style <- report_style()
  section <- function(title, entries, intro, sep = character(0)) {
    if (length(entries) == 0) return(character(0))
    n <- sum(lengths(entries))
    c(
      report_heading(sprintf("%s (%d)", title, n), style), "", intro, "",
      report_groups(lapply(names(entries), function(path) {
        list(title = sprintf("%s (%d)", path, length(entries[[path]])),
             lines = Reduce(function(a, b) c(a, sep, b), entries[[path]]))
      }), style)
    )
  }

  body <- c(
    if (!is.null(summary_line)) c(paste("**Summary:**", summary_line), ""),
    section("Changes to existing tests", changes, "Each change passed a real run. Check the reasons before merging."),
    section("Existing tests to look at", notes, "Not changed automatically."),
    section("Generated tests that failed", failures, "Not proposed; each needs a look.", sep = c("", "---", ""))
  )
  paste(body, collapse = "\n")
}
