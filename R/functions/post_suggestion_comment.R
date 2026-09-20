# scan-mode: changed — posts the new roxygen block as a GitHub PR review
# suggestion comment.
post_suggestion_comment <- function(path, parsed, new_block, changed_tags) {
  intro <- if (length(changed_tags) > 0) {
    sprintf("Updated: %s\n\n", paste(unlist(changed_tags), collapse = ", "))
  } else ""

  if (parsed$has_roxygen) {
    start_line <- parsed$roxygen_start
    end_line   <- parsed$roxygen_end
    body <- paste0(intro, "```suggestion\n", new_block, "\n```")
  } else {
    start_line <- parsed$fn_start
    end_line   <- parsed$fn_start
    body <- paste0(
      intro, "```suggestion\n", new_block, "\n", parsed$fn_header, "\n```"
    )
  }

  req <- request(sprintf("https://api.github.com/repos/%s/pulls/%s/comments", repo, pr_number)) |>
    req_headers("Authorization" = paste("Bearer", gh_token), "Accept" = "application/vnd.github+json") |>
    req_body_json(list(
      body = body, commit_id = pr_head_sha, path = path,
      start_line = start_line, line = end_line, side = "RIGHT", start_side = "RIGHT"
    ))

  tryCatch(req_perform(req), error = function(e) {
    message(sprintf("Failed to post suggestion comment for %s: %s", path, conditionMessage(e)))
  })
}
