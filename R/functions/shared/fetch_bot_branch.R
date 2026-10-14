# Fetches the open bot branch (e.g. bot-suggest/docs/dev), so what it
# already proposes can be read (review_source_block(),
# materialize_bot_tests()). Returns the ref to read from, or NULL if it
# can't be fetched.
#
# The test and analysis workflows check out without stored credentials
# (persist-credentials: false), so package and generated code find no token
# in .git/config. The token (GH_TOKEN) is passed for this one command
# instead, the way actions/checkout would have stored it; a public
# repository needs none.
fetch_bot_branch <- function(branch) {
  ref <- paste0("refs/remotes/origin/", branch)
  token <- Sys.getenv("GH_TOKEN")
  header <- "http.https://github.com/.extraheader"
  stored <- suppressWarnings(system2("git", c("config", "--get-all", header), stdout = TRUE, stderr = FALSE))
  auth <- if (nzchar(token) && length(stored) == 0) {  # a checkout that kept its credentials needs none
    c("-c", paste0(header, "=AUTHORIZATION: basic ", gsub("\\s", "", jsonlite::base64_enc(paste0("x-access-token:", token)))))
  }
  status <- suppressWarnings(system2("git", shQuote(c(auth, "fetch", "--quiet", "origin", sprintf("+refs/heads/%s:%s", branch, ref))), stdout = FALSE, stderr = FALSE))
  if (!identical(as.integer(status), 0L)) {
    message(sprintf("Could not fetch %s — reviewing the branch's own files.", branch))
    return(NULL)
  }
  ref
}
