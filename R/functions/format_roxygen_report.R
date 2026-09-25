# The roxygen suggestion PR's description, as collapsible groups:
# "Applied changes (n)" with one group per file ("R/ds.rse.R (8)") listing
# each change with reason and explanation, and "No changes applied (n)"
# with one group per reason ("clarity (6)"), each listing the dropped
# suggestions per file with Claude's proposed text, so a reviewer can
# adopt one by hand and see where the threshold might be tuned. Optionally
# a "Possible bugs in the code" section (format_code_issues()). `files` is
# a list of list(path, applied, dropped) from accepted_roxygen_fields().
# Capped below GitHub's body limit.
format_roxygen_report <- function(files, code_issues = list()) {
  group <- function(title, lines) c(sprintf("<details><summary><h3>%s</h3></summary>", title), "", lines, "", "</details>", "")
  quote <- function(text) {
    if (is.null(text) || !nzchar(trimws(text))) return(character(0))
    paste0("  > ", strsplit(text, "\n", fixed = TRUE)[[1]])
  }

  with_applied <- Filter(function(f) length(f$applied) > 0, files)
  n_applied <- sum(vapply(with_applied, function(f) length(f$applied), integer(1)))
  applied <- unlist(lapply(with_applied, function(f) {
    group(sprintf("%s (%d)", f$path, length(f$applied)), vapply(f$applied, function(ch) {
      sprintf("- `%s` — `%s`: %s", ch$field, ch$reason, ch$explanation)
    }, character(1)))
  }))

  dropped <- unlist(lapply(files, function(f) lapply(f$dropped, function(ch) c(ch, path = f$path))), recursive = FALSE)
  reasons <- unique(vapply(dropped, function(ch) ch$reason, character(1)))
  not_applied <- unlist(lapply(reasons, function(r) {
    of_reason <- Filter(function(ch) identical(ch$reason, r), dropped)
    paths <- unique(vapply(of_reason, function(ch) ch$path, character(1)))
    lines <- unlist(lapply(paths, function(p) {
      c(sprintf("**`%s`**", p), unlist(lapply(Filter(function(ch) identical(ch$path, p), of_reason), function(ch) {
        c(sprintf("- `%s`: %s", ch$field, ch$explanation), quote(ch$proposed))
      })), "")
    }))
    group(sprintf("%s (%d)", r, length(of_reason)), lines)
  }))

  body <- c(
    if (n_applied > 0) c(sprintf("## Applied changes (%d)", n_applied), "", applied),
    if (length(dropped) > 0) c(
      sprintf("## No changes applied (%d)", length(dropped)),
      "",
      "Suggestions whose reason isn't on the accepted list (`accept_reasons` in `config/claude.yml`). Adopt one by hand if it's worth it.",
      "",
      not_applied
    ),
    if (length(code_issues) > 0) format_code_issues(code_issues)
  )
  body <- paste(body, collapse = "\n")
  if (nchar(body) > 60000) body <- paste0(substr(body, 1, 60000), "\n\n… truncated — see the job log for the rest.")
  body
}
