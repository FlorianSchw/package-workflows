# Notes a file whose Claude call failed in retry_files.txt, next to
# updated_files.txt. commit-updated-files keeps these as
# "<!-- bot-suggest: retry <file> -->" lines in the bot PR's description,
# and determine-changes.sh checks the files again on the next run, even
# without new commits — otherwise the "reviewed up to" marker moves past
# them and a failed call (an API outage, a rejected request) is never
# repeated. Design: dev-notes/suggestions-trigger-model.md.
note_retry_file <- function(file, path = "retry_files.txt") {
  cat(file, "\n", file = path, append = TRUE, sep = "")
}
