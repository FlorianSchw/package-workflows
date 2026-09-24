# Posts a plain PR comment (issue-comments endpoint, not a review-comment
# suggestion box — there's nothing to "accept," just something for a human
# to look at) describing a failing generated test classified as bad_test
# or env_misconfiguration. Changed mode only — a sweep has no PR, see
# publish_test_report().
post_test_failure_comment <- function(function_name, test_block, failure_message, classification) {
  post_github_json(
    sprintf("/repos/%s/issues/%s/comments", repo, pr_number),
    list(body = format_test_failure(function_name, test_block, failure_message, classification)),
    function_name
  )
}
