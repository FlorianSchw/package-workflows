# Loads every function of R/functions/ into the global environment, the
# way the entry scripts do (they source their folders with purrr::walk()),
# and offers helpers for the made-up fixtures in tests/fixtures/.
suppressPackageStartupMessages({
  library(httr2)     # attached by the entry scripts, used without httr2::
  library(jsonlite)
  library(purrr)
})
repo_root <- normalizePath(file.path(testthat::test_path(), "..", ".."), winslash = "/")
for (f in list.files(file.path(repo_root, "R", "functions"), pattern = "\\.R$", recursive = TRUE, full.names = TRUE)) {
  sys.source(f, envir = globalenv())
}

# A fresh copy of a fixture (tests/fixtures/<name>) in a temporary folder,
# removed when the calling test ends.
local_fixture <- function(name, env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  file.copy(file.path(repo_root, "tests", "fixtures", name), dir, recursive = TRUE)
  file.path(dir, basename(name))
}

# Runs one of this repository's entry scripts in `dir` as a separate
# Rscript process, with the shared repository copied into
# .shared-workflows as in CI. `env` is a named character vector of
# environment variables. Returns list(status, output).
run_entry_script <- function(script, dir, env = character(0)) {
  shared <- file.path(dir, ".shared-workflows")
  dir.create(shared, showWarnings = FALSE)
  for (part in c("R", "config", "prompts")) file.copy(file.path(repo_root, part), shared, recursive = TRUE)
  out <- withr::with_dir(dir, withr::with_envvar(env, suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"), shQuote(file.path(".shared-workflows", "R", script)),
    stdout = TRUE, stderr = TRUE
  ))))
  list(status = attr(out, "status") %||% 0L, output = out)
}

# A response of the Messages API for httr2::with_mocked_responses().
claude_response <- function(content, stop_reason = "tool_use") {
  httr2::response(
    status_code = 200,
    headers = list("content-type" = "application/json"),
    body = charToRaw(jsonlite::toJSON(list(content = content, stop_reason = stop_reason,
                                           usage = list(input_tokens = 10, output_tokens = 5)),
                                      auto_unbox = TRUE, null = "null"))
  )
}

# The JSON body of a request as the API receives it.
request_body <- function(req) {
  body <- httr2::req_get_body(req)
  if (is.raw(body)) body <- rawToChar(body)
  if (is.list(body)) body <- jsonlite::toJSON(body, auto_unbox = TRUE, null = "null", digits = 22)
  jsonlite::fromJSON(body, simplifyVector = FALSE)
}
