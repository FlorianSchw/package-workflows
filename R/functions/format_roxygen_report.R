# The roxygen suggestion PR's description: per file, the applied changes
# with reason and explanation, then — collapsed — the changes that were
# not applied (below the threshold), with Claude's proposed text, so a
# reviewer can adopt one by hand and see where the threshold might be
# tuned. `files` is a list of list(path, applied, dropped) from
# accepted_roxygen_fields(). Capped below GitHub's body limit.
format_roxygen_report <- function(files) {
  item <- function(ch, with_text) {
    line <- sprintf("- `%s` — `%s`: %s", ch$field, ch$reason, ch$explanation)
    if (!with_text || is.null(ch$proposed) || !nzchar(trimws(ch$proposed))) return(line)
    quoted <- paste0("  > ", strsplit(ch$proposed, "\n", fixed = TRUE)[[1]], collapse = "\n")
    paste(line, quoted, sep = "\n")
  }
  per_file <- function(key, with_text) {
    parts <- unlist(lapply(files, function(f) {
      if (length(f[[key]]) == 0) return(NULL)
      c(sprintf("**`%s`**", f$path), vapply(f[[key]], item, character(1), with_text = with_text), "")
    }))
    if (is.null(parts)) character(0) else parts
  }

  applied <- per_file("applied", with_text = FALSE)
  dropped <- per_file("dropped", with_text = TRUE)
  n_dropped <- sum(vapply(files, function(f) length(f$dropped), integer(1)))

  body <- c(
    if (length(applied) > 0) c("## Applied changes", "", applied),
    if (n_dropped > 0) c(
      sprintf("<details><summary>Not applied: %d suggestion(s) below the threshold</summary>", n_dropped),
      "",
      "Claude's reason isn't on the accepted list (`accept_reasons` in `config/claude.yml`). Adopt a suggestion by hand if it's worth it.",
      "",
      dropped,
      "</details>"
    )
  )
  body <- paste(body, collapse = "\n")
  if (nchar(body) > 60000) body <- paste0(substr(body, 1, 60000), "\n\n… truncated — see the job log for the rest.")
  body
}
