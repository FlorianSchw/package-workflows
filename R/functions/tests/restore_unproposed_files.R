# Puts back the files materialize_bot_tests() replaced with the bot
# branch's version and this run doesn't propose (not in `updated`): the
# branch's own version, or removed if the branch doesn't have the file.
# Leaves the working tree as checked out, apart from this run's files, so
# commit-updated-files can switch to the bot branch.
restore_unproposed_files <- function(materialized, updated) {
  for (path in setdiff(materialized, updated)) {
    in_head <- suppressWarnings(system2("git", shQuote(c("cat-file", "-e", paste0("HEAD:", path))), stdout = FALSE, stderr = FALSE))
    if (identical(as.integer(in_head), 0L)) {
      system2("git", shQuote(c("checkout", "--quiet", "HEAD", "--", path)))
    } else if (file.exists(path)) {
      file.remove(path)
    }
  }
  invisible(NULL)
}
