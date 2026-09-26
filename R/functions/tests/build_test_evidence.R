# History evidence for judging a failing existing test: when the function
# file and its test file last changed, which changed later, and — in a PR
# run (base_ref set) — whether this PR changed the function without
# touching its test, plus the function file's diff. A function changed
# after its test hints at an outdated test; a test that is newer than the
# code it fails on hints at a bug. Claude weighs this, R doesn't decide.
build_test_evidence <- function(function_file, test_path, base_ref) {
  # system2() passes arguments through the shell unquoted — quote them.
  git <- function(...) suppressWarnings(system2("git", shQuote(c(...)), stdout = TRUE, stderr = FALSE))
  last_change <- function(path) {
    info <- git("log", "-1", "--format=%ct|%cs %h by %an: %s", "--", path)
    if (length(info) == 0) return(NULL)
    parts <- strsplit(info[1], "|", fixed = TRUE)[[1]]
    list(time = as.numeric(parts[1]), text = paste(parts[-1], collapse = "|"))
  }

  fn_change <- last_change(function_file)
  lines <- sprintf("Function file `%s` last changed: %s", function_file, if (is.null(fn_change)) "not committed yet" else fn_change$text)

  if (file.exists(test_path)) {
    test_change <- last_change(test_path)
    lines <- c(lines, sprintf("Test file `%s` last changed: %s", test_path, if (is.null(test_change)) "not committed yet" else test_change$text))
    if (!is.null(fn_change) && !is.null(test_change)) {
      order <- if (fn_change$time > test_change$time) {
        "The function file changed after the test file."
      } else if (fn_change$time < test_change$time) {
        "The test file changed after the function file."
      } else {
        "Both last changed in the same commit."
      }
      lines <- c(lines, order)
    }
  } else {
    lines <- c(lines, "No test file exists yet.")
  }

  if (nzchar(base_ref)) {
    range <- sprintf("origin/%s...HEAD", base_ref)
    diff <- git("diff", range, "--", function_file)
    test_touched <- length(git("diff", "--name-only", range, "--", test_path)) > 0
    lines <- c(lines, sprintf(
      "In this pull request, the function file %s and the test file %s.",
      if (length(diff) > 0) "changed" else "did not change",
      if (test_touched) "changed as well" else "did not change"
    ))
    if (length(diff) > 0) lines <- c(lines, "", "Diff of the function file in this pull request:", "```diff", diff, "```")
  }

  paste(lines, collapse = "\n")
}
