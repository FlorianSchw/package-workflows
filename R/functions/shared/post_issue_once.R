# Opens an issue `title` with `body` — unless an open issue with that exact
# title exists: then `body` goes there as a comment, unless the issue or
# one of its comments already says exactly that (comment_once()). So a
# bot finding that comes up again, e.g. after its suggestion PR was
# closed, doesn't open a second issue. Returns the issue's URL (for a link
# in the report), or NULL if it couldn't be opened. Needs `issues: write`
# in the caller.
post_issue_once <- function(title, body, context) {
  open <- get_github_json(sprintf("/repos/%s/issues?state=open&per_page=100", repo))
  existing <- Find(function(i) identical(i$title, title) && is.null(i$pull_request), open)
  if (is.null(existing)) {
    resp <- post_github_json(sprintf("/repos/%s/issues", repo), list(title = title, body = body), context)
    url <- tryCatch(httr2::resp_body_json(resp)$html_url, error = function(e) NULL)
    return(invisible(url))
  }
  if (identical(trimws(if (is.null(existing$body)) "" else existing$body), trimws(body))) {
    message(sprintf("Issue #%s \"%s\" already says this — nothing added (%s).", existing$number, title, context))
  } else {
    message(sprintf("Issue #%s \"%s\" is already open — adding to it (%s).", existing$number, title, context))
    comment_once(existing$number, body, context)
  }
  invisible(existing$html_url)
}
