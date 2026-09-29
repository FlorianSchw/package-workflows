# The repair round's addition to the prompt, from `template`
# (prompts/analysis-repair-prompt.md): per failing step, the problems
# found (call checks and test run) and the code that failed.
format_repair_request <- function(problems, answers, template) {
  failed <- vapply(names(problems), function(id) sprintf(
    "### Step `%s`\n\nProblems:\n%s\n\nYour code:\n```r\n%s\n```",
    id, paste("-", problems[[id]], collapse = "\n"), step_code(answers[[id]])
  ), character(1))
  fill_template(template, list(FAILED_STEPS = paste(failed, collapse = "\n\n")))
}
