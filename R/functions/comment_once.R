# Posts a comment on a PR unless an identical one is already there — for
# notes that would otherwise repeat on every push to the PR.
comment_once <- function(pr_number, body, context) {
  existing <- get_github_json(sprintf("/repos/%s/issues/%s/comments?per_page=100", repo, pr_number))
  if (any(vapply(existing, function(c) identical(trimws(c$body), trimws(body)), logical(1)))) {
    message(sprintf("Same comment already on PR #%s — not posting again (%s).", pr_number, context))
    return(invisible(NULL))
  }
  post_github_json(sprintf("/repos/%s/issues/%s/comments", repo, pr_number), list(body = body), context)
}
