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
# below GitHub's body limit. `open`: ids of findings whose group is shown
# expanded (the choices workflow passes the ones whose box just changed).
format_test_report <- function(state, latest = NULL, legacy = NULL, open = integer(0)) {
  style <- report_style()
  is_active <- function(e) identical(e$status, "active")
  of_kind <- function(kinds) Filter(function(e) e$kind %in% kinds, state$entries)
  name <- function(e) sprintf("\"%s\"", e$description)
  choices_hint <- "Untick what you don't want: the branch follows within a minute, and an unticked test isn't suggested again while the function's code stays the same."

  # Counted: open findings, not the ones the user declined.
  counts <- function(e) is_active(e) && !identical(suggestion_choice(e), "declined")
  section <- function(title, entries, intro, line, extra = function(e) character(0), sep = character(0), liner = finding_line) {
    if (length(entries) == 0) return(character(0))
    paths <- unique(vapply(entries, function(e) e$file, character(1)))
    c(
      report_heading(sprintf("%s (%d)", title, sum(vapply(entries, counts, logical(1)))), style), "", intro, "",
      report_groups(lapply(paths, function(p) {
        of_file <- Filter(function(e) identical(e$file, p), entries)
        of_file <- c(Filter(is_active, of_file), Filter(Negate(is_active), of_file))
        blocks <- lapply(of_file, function(e) c(liner(e, line(e), name(e)), if (is_active(e)) extra(e)))
        list(title = group_title(p, of_file), lines = Reduce(function(a, b) c(a, sep, b), blocks),
             open = any(vapply(of_file, function(e) as.integer(e$id) %in% open, logical(1))))
      }), style)
    )
  }

  latest_line <- format_latest_review(latest)

  body <- c(
    paste("**Summary:**", format_test_summary(state)),
    if (!is.null(latest_line)) c("", latest_line),
    "",
    section("New tests", of_kind("new"), paste("Each passed a real run.", choices_hint),
            function(e) sprintf("%s — `%s`", name(e), e$reason), liner = choice_line),
    section("Changes to existing tests", of_kind(c("updated", "deleted")), paste("Each change passed a real run. Check the reasons before merging.", choices_hint),
            function(e) sprintf("%s%s — %s", if (identical(e$kind, "deleted")) "delete " else "update ", name(e), e$explanation), liner = choice_line),
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
  finish_suggestion_report(body, state, legacy)
}
