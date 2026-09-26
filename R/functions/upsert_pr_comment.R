# Keeps one comment per purpose on a PR up to date: the first comment
# containing `marker` (an HTML comment in the body) is edited, otherwise a
# new one is posted. With body NULL, an existing comment is replaced by
# `gone_text` (e.g. "no longer changes the diagrams") and nothing new is
# posted. Failures are reported via message(), like post_github_json().
upsert_pr_comment <- function(pr_number, body, marker, gone_text) {
  comments <- get_github_json(sprintf("/repos/%s/issues/%s/comments?per_page=100", repo, pr_number))
  mine <- Find(function(c) grepl(marker, c$body, fixed = TRUE), comments)

  if (is.null(body)) {
    if (is.null(mine)) return(invisible(NULL))
    body <- paste(marker, gone_text, sep = "\n")
  }
  if (is.null(mine)) {
    return(post_github_json(sprintf("/repos/%s/issues/%s/comments", repo, pr_number), list(body = body), "workflow graphs preview"))
  }

  req <- request(sprintf("https://api.github.com/repos/%s/issues/comments/%s", repo, mine$id)) |>
    req_method("PATCH") |>
    req_headers("Authorization" = paste("Bearer", gh_token), "Accept" = "application/vnd.github+json") |>
    req_body_json(list(body = body))
  tryCatch(req_perform(req), error = function(e) {
    message(sprintf("Failed to update the preview comment: %s", conditionMessage(e)))
  })
}
