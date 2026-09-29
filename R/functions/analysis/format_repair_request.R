# The repair round's addition to the prompt: per failing step, the
# problems found (call check and test run) and the code that failed.
format_repair_request <- function(problems, answers) {
  paste(c(
    "", "## Your previous attempt failed for these steps", "",
    "Fix the problems and return these steps again, complete.", "",
    vapply(names(problems), function(id) sprintf(
      "### Step `%s`\n\nProblems:\n%s\n\nYour code:\n```r\n%s\n```",
      id, paste("-", problems[[id]], collapse = "\n"),
      paste(vapply(answers[[id]]$sections, function(s) s$code, character(1)), collapse = "\n\n")
    ), character(1))
  ), collapse = "\n")
}
