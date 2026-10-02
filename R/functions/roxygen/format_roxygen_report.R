# The roxygen suggestion PR's description, rebuilt on every run from all
# findings the PR carries (merge_roxygen_findings()), so it stays one
# report instead of growing an update per run:
# - "Applied changes (n)", one group per file, each change with reason,
#   explanation and the commit it came from;
# - "No changes applied (n)", one group per reason, each suggestion with
#   Claude's proposed text, so a reviewer can adopt one by hand;
# - "Possible bugs in the code (n)" (format_code_issues()).
# Counts are open findings; crossed-out ones stay visible, struck through
# with when and why (finding_line()). On top: the summary line and, when
# `latest` is given (list(sha, stats)), what the latest review changed.
# Then `legacy` (the description of a bot PR opened before this format) in
# a collapsed section, and the hidden state for the next run
# (encode_suggestion_state()). Heading levels and spacing come from
# config/report-style.yml. Kept below GitHub's body limit.
format_roxygen_report <- function(state, latest = NULL, legacy = NULL) {
  style <- report_style()
  entries <- state$entries
  is_active <- function(e) identical(e$status, "active")
  active_first <- function(x) c(Filter(is_active, x), Filter(Negate(is_active), x))
  of_kind <- function(kind) Filter(function(e) identical(e$kind, kind), entries)
  # Counted: open findings, not the ones the user declined.
  count <- function(x) sum(vapply(x, function(e) is_active(e) && !identical(suggestion_choice(e), "declined"), logical(1)))
  quote <- function(text) {
    if (is.null(text) || !nzchar(trimws(text))) return(character(0))
    paste0("  > ", strsplit(text, "\n", fixed = TRUE)[[1]])
  }

  applied <- of_kind("applied")
  applied_groups <- report_groups(lapply(unique(vapply(applied, function(e) e$file, character(1))), function(p) {
    of_file <- active_first(Filter(function(e) identical(e$file, p), applied))
    list(title = group_title(p, of_file), lines = vapply(of_file, function(e) {
      choice_line(e, sprintf("`%s` — `%s`: %s", e$field, e$reason, e$explanation), sprintf("`%s` — `%s`: %s", e$field, e$reason, e$explanation))
    }, character(1)))
  }), style)

  dropped <- of_kind("dropped")
  dropped_groups <- report_groups(lapply(unique(vapply(dropped, function(e) e$reason, character(1))), function(r) {
    of_reason <- Filter(function(e) identical(e$reason, r), dropped)
    lines <- unlist(lapply(unique(vapply(of_reason, function(e) e$file, character(1))), function(p) {
      c(sprintf("**`%s`**", p), unlist(lapply(active_first(Filter(function(e) identical(e$file, p), of_reason)), function(e) {
        c(choice_line(e, sprintf("`%s`: %s", e$field, e$explanation), sprintf("`%s`: %s", e$field, e$explanation)),
          if (is_active(e)) quote(e$proposed))
      })), "")
    }))
    list(title = group_title(r, of_reason), lines = lines)
  }), style)

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
    paste("**Summary:**", format_roxygen_summary(state)),
    if (!is.null(latest_line)) c("", latest_line),
    "",
    if (length(applied) > 0) c(report_heading(sprintf("Applied changes (%d)", count(applied)), style), "",
                               "Untick what you don't want: the branch follows within a minute, and an unticked change isn't suggested again while the function's code stays the same.", "",
                               applied_groups),
    if (length(dropped) > 0) c(
      report_heading(sprintf("No changes applied (%d)", count(dropped)), style),
      "",
      "Suggestions whose reason isn't on the accepted list (the `accept-reasons` input, or `accept_reasons` in `config/claude.yml`). Tick one to apply it: the branch follows within a minute.",
      "",
      dropped_groups
    ),
    format_code_issues(entries, style)
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
