# Posts a plain PR comment (issue-comments endpoint, not a review-comment
# suggestion box — there's nothing to "accept," just something for a human
# to look at) describing a failing generated test classified as bad_test
# or env_misconfiguration. Nothing is auto-applied either way.
post_test_failure_comment <- function(function_name, test_block, failure_message, classification) {
  body <- sprintf(
    paste(
      "**Generated test failed for `%s`** — classified as `%s`, needs human judgment (not auto-applied):",
      "",
      "%s",
      "",
      "```r",
      "%s",
      "```",
      "",
      "**Failure output:**",
      "```",
      "%s",
      "```",
      sep = "\n"
    ),
    function_name, classification$category, classification$explanation, test_block, failure_message
  )

  post_github_json(
    sprintf("/repos/%s/issues/%s/comments", repo, pr_number),
    list(body = body),
    function_name
  )
}
