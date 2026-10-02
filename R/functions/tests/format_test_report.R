# The test workflow's report (see publish_test_report() for where it goes),
# rebuilt on every run from all findings the bot PR carries
# (merge_test_findings()), so it stays one report instead of growing an
# update per run. Laid out like the roxygen report: a section per kind
# with its count of open findings — "New tests", "Changes to existing
# tests", "Possible bugs in the code" (from reported existing tests and
# failed generated tests, medium confidence labelled, with a link to the
# issue where one was opened), "Existing tests to look at", "Generated
# tests that failed"
# (those reported here rather than as PR comments, with test code and
# output), "Functions not tested" — and in each a collapsible group per
# file. Each finding carries the commit it came from; crossed-out ones
# stay visible, struck through with when and why (finding_line()). On
# top: the summary line and, when `latest` is given (list(sha, stats)),
# what the latest review changed; then `legacy` (a description from
# before this format) collapsed, and the hidden state for the next run.
# Heading levels and spacing come from config/report-style.yml. Kept
# below GitHub's body limit.
format_test_report <- function(state, latest = NULL, legacy = NULL) {
  style <- report_style()
  is_active <- function(e) identical(e$status, "active")
  of_kind <- function(kinds) Filter(function(e) e$kind %in% kinds, state$entries)
  name <- function(e) sprintf("\"%s\"", e$description)

  section <- function(title, entries, intro, line, extra = function(e) character(0), sep = character(0)) {
    if (length(entries) == 0) return(character(0))
    paths <- unique(vapply(entries, function(e) e$file, character(1)))
    c(
      report_heading(sprintf("%s (%d)", title, sum(vapply(entries, is_active, logical(1)))), style), "", intro, "",
      report_groups(lapply(paths, function(p) {
        of_file <- Filter(function(e) identical(e$file, p), entries)
        of_file <- c(Filter(is_active, of_file), Filter(Negate(is_active), of_file))
        blocks <- lapply(of_file, function(e) c(finding_line(e, line(e), name(e)), if (is_active(e)) extra(e)))
        list(title = group_title(p, of_file), lines = Reduce(function(a, b) c(a, sep, b), blocks))
      }), style)
    )
  }

  latest_line <- if (!is.null(latest) && nzchar(latest$sha)) {
    s <- latest$stats
    parts <- c(
      sprintf("%d new", s[["new"]]),
      if (s[["crossed"]] > 0) sprintf("%d crossed out", s[["crossed"]]),
      if (s[["repeats"]] > 0) sprintf("%d %s of earlier findings skipped", s[["repeats"]], if (s[["repeats"]] == 1) "repeat" else "repeats")
    )
    sprintf("**Latest review** (`%s`): %s", latest$sha, paste(parts, collapse = " · "))
  }

  body <- c(
    paste("**Summary:**", format_test_summary(state)),
    if (!is.null(latest_line)) c("", latest_line),
    "",
    section("New tests", of_kind("new"), "Each passed a real run.",
            function(e) sprintf("%s — `%s`", name(e), e$reason)),
    section("Changes to existing tests", of_kind(c("updated", "deleted")), "Each change passed a real run. Check the reasons before merging.",
            function(e) sprintf("%s — %s", name(e), e$explanation)),
    section("Possible bugs in the code", of_kind("bug"), "Noticed while testing — nothing in the code was changed. Please check.",
            function(e) sprintf("%s%s%s — %s%s", name(e),
                                if (identical(e$origin, "failure")) " (a generated test, not proposed)" else "",
                                if (identical(e$confidence, "medium")) " _(medium confidence)_" else "",
                                e$explanation,
                                if (nzchar(e$issue)) sprintf(" — [issue](%s)", e$issue) else "")),
    section("Existing tests to look at", of_kind("note"), "Not changed automatically.",
            function(e) sprintf("%s — %s", name(e), e$explanation)),
    section("Generated tests that failed", Filter(function(e) isTRUE(e$in_report), of_kind("failed")), "Not proposed; each needs a look.",
            function(e) sprintf("%s — `%s`", name(e), e$classification),
            extra = function(e) c("", e$explanation), sep = c("", "---", "")),
    section("Functions not tested", of_kind("untested"), "They need DataSHIELD connections, but the tests have no way to connect and `dslite-setup` is `never`.",
            function(e) sprintf("`%s`", e$fn))
  )
  hidden <- encode_suggestion_state(state)
  body <- paste(body, collapse = "\n")
  room <- 62000 - nchar(hidden)
  if (!is.null(legacy)) {
    legacy <- substr(legacy, 1, max(0, min(20000, room - nchar(body) - 200)))
    if (nzchar(legacy)) body <- paste0(body, "\n\n<details><summary>Earlier reports (before this report format)</summary>\n\n", legacy, "\n\n</details>")
  }
  if (nchar(body) > room) body <- paste0(substr(body, 1, room), "\n\n… truncated — see the job log for the rest.")
  paste0(body, "\n\n", hidden)
}
