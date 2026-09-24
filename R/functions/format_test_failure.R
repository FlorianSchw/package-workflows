# Markdown report for one failing generated test classified as bad_test or
# env_misconfiguration — the body of a PR comment in changed mode, one
# entry of the sweep report in all mode. Nothing is auto-applied either way.
format_test_failure <- function(function_name, test_block, failure_message, classification) {
  sprintf(
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
}
