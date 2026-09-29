# The suggestion PR's description (and the job summary): what was written,
# how to try it, what else the plan would need, and what wasn't proposed.
# `r` is the run record built by the entry script: steps (per step: title,
# status, files, notes, error), general notes, tested versions, and the
# settings used for links.
format_analysis_report <- function(r) {
  out <- c(
    "Starter scripts for your DataSHIELD analysis, drafted from your analysis plan. Each script ran in DSLite on mock data generated from the plan. That checks the code runs, not that the analysis is right: please read and adapt it. The analysis stays your responsibility.",
    "",
    sprintf("**Tested with:** %s.", r$tested_with)
  )

  written <- Filter(function(s) s$status %in% c("written", "not_possible"), r$steps)
  if (length(written) > 0) {
    out <- c(out, "", "### Scripts", "")
    for (s in written) {
      out <- c(out, sprintf("- **%s**: %s%s", s$title, paste(sprintf("`%s`", s$files), collapse = ", "),
        if (identical(s$status, "not_possible")) " (notes only: not possible with the installed packages)" else ""))
    }
    out <- c(out, "",
      "**Try it yourself:** set `R_CONFIG_ACTIVE = 'testing'` in `.Renviron`, restart R and run `main.R`. It uses the same DSLite setup and mock data as this test run. You get the same results if you install the versions listed in `dependencies.R`. Switch back to `production` for the real analysis."
    )
  }

  other <- list(); gaps <- list(); limits <- list()
  for (s in r$steps) for (n in s$notes) {
    entry <- c(n, step_title = s$title)
    if (identical(n$kind, "other_package")) other[[length(other) + 1]] <- entry
    else if (identical(n$kind, "missing_function")) gaps[[length(gaps) + 1]] <- entry
    else limits[[length(limits) + 1]] <- entry
  }
  if (length(other) > 0) {
    out <- c(out, "", "### Possible with another package", "",
      "Not installed on your study servers. The packages are listed, commented out, in `dependencies.R`.", "")
    for (n in other) out <- c(out, sprintf("- **%s** (`%s`): %s", n$step_title, n$package, n$text))
  }
  if (length(gaps) > 0) {
    out <- c(out, "", "### Not possible with any known DataSHIELD package", "",
      "The link opens a prefilled issue under your account, so missing functions can be collected. Check the text before you submit it.", "")
    for (n in gaps) out <- c(out, sprintf("- **%s**: %s [Open issue](%s)", n$step_title, n$text, gap_issue_link(r$gap_issue_repo, n$step_title, n$text)))
  }
  if (length(limits) > 0) {
    out <- c(out, "", "### Limitations", "")
    for (n in limits) out <- c(out, sprintf("- **%s**: %s", n$step_title, n$text))
  }

  failed <- Filter(function(s) identical(s$status, "failed"), r$steps)
  kept <- Filter(function(s) s$status %in% c("edited", "removed"), r$steps)
  if (length(failed) + length(kept) + length(r$notes) > 0) {
    out <- c(out, "", "### Not proposed, and other notes", "")
    for (s in failed) out <- c(out, sprintf("- **%s**: not proposed, %s", s$title, s$error))
    for (s in kept) out <- c(out, sprintf("- **%s**: %s", s$title, s$error))
    for (n in r$notes) out <- c(out, sprintf("- %s", n))
  }
  out
}
