# Fetches the open bot branch (e.g. bot-suggest/docs/dev), so the blocks it
# already proposes can be read (review_source_block()). Returns the ref to
# read from, or NULL if it can't be fetched.
fetch_bot_branch <- function(branch) {
  ref <- paste0("refs/remotes/origin/", branch)
  status <- suppressWarnings(system2("git", shQuote(c("fetch", "--quiet", "origin", sprintf("+refs/heads/%s:%s", branch, ref))), stdout = FALSE, stderr = FALSE))
  if (!identical(as.integer(status), 0L)) {
    message(sprintf("Could not fetch %s — reviewing the branch's own documentation.", branch))
    return(NULL)
  }
  ref
}
