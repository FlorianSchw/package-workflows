# The suggestion PR's description (and the job summary): what was written,
# how to try it, what else the plan would need, and what wasn't proposed.
# `r` is the run record built by the entry script: steps (per step: title,
# status, files, notes, error), general notes, tested versions, and the
# repository for issue links. Wording from `texts$report`.
format_analysis_report <- function(r, texts) {
  t <- texts$report
  out <- c(t$intro, "", fill_template(t$tested_with, list(TESTED_WITH = r$tested_with)))

  written <- Filter(function(s) s$status %in% c("written", "not_possible"), r$steps)
  if (length(written) > 0) {
    out <- c(out, "", t$scripts_heading, "")
    for (s in written) {
      out <- c(out, sprintf("- **%s**: %s%s", s$title, paste(sprintf("`%s`", s$files), collapse = ", "),
        if (identical(s$status, "not_possible")) t$notes_only_suffix else ""))
    }
    out <- c(out, "", t$try_it)
  }

  by_kind <- function(kind) {
    unlist(lapply(r$steps, function(s) lapply(Filter(function(n) identical(n$kind, kind), s$notes), function(n) c(n, step_title = s$title))), recursive = FALSE)
  }
  other <- by_kind("other_package")
  if (length(other) > 0) {
    out <- c(out, "", t$other_package_heading, "", t$other_package_intro, "")
    for (n in other) out <- c(out, sprintf("- **%s** (`%s`): %s", n$step_title, n$package, n$text))
  }
  gaps <- by_kind("missing_function")
  if (length(gaps) > 0) {
    out <- c(out, "", t$gaps_heading, "", t$gaps_intro, "")
    for (n in gaps) {
      out <- c(out, sprintf("- **%s**: %s [%s](%s)", n$step_title, n$text, t$open_issue, gap_issue_link(r$gap_issue_repo, n$step_title, n$text, texts)))
    }
  }
  limits <- by_kind("limitation")
  if (length(limits) > 0) {
    out <- c(out, "", t$limitations_heading, "")
    for (n in limits) out <- c(out, sprintf("- **%s**: %s", n$step_title, n$text))
  }

  reported <- Filter(function(s) s$status %in% c("failed", "edited", "removed"), r$steps)
  if (length(reported) + length(r$notes) > 0) {
    out <- c(out, "", t$other_notes_heading, "")
    for (s in reported) out <- c(out, sprintf("- **%s**: %s", s$title, s$error))
    for (n in r$notes) out <- c(out, sprintf("- %s", n))
  }
  out
}
