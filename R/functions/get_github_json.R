# Shared low-level GitHub API GET mechanics — counterpart of
# post_github_json(). Returns the parsed body, or NULL on any HTTP error so
# the caller can skip that item instead of aborting the run.
get_github_json <- function(path) {
  resp <- request(sprintf("https://api.github.com%s", path)) |>
    req_headers("Authorization" = paste("Bearer", gh_token), "Accept" = "application/vnd.github+json") |>
    req_error(is_error = function(resp) FALSE) |>
    req_perform()

  if (resp_status(resp) >= 400) return(NULL)
  resp_body_json(resp)
}
