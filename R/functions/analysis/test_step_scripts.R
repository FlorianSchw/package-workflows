# Checks the new scripts: every DataSHIELD call against the installed
# clients (check_ds_calls()) and every "object$column" string against the
# plan's variables (check_column_references()), then a test run of all
# scripts in file order (run_analysis_scripts()): the new ones
# (`candidate`, step id -> paths) together with `other_files`, the
# project's other bot scripts, so each step runs with the objects of the
# steps before it.
# Returns list(problems, broken_other): problems per step id with any
# (only failing steps), and errors of other_files (named by path).
# Stops if the DSLite setup itself fails: then nothing can be judged.
test_step_scripts <- function(candidate, answers, reference, variables, login_file, other_files) {
  ids <- names(candidate)
  code_of <- function(id) paste(vapply(answers[[id]]$sections, function(s) s$code, character(1)), collapse = "\n")
  all_code <- paste(c(vapply(ids, code_of, character(1)), unlist(lapply(other_files, readLines, warn = FALSE))), collapse = "\n")
  problems <- lapply(setNames(ids, ids), function(id) {
    c(check_ds_calls(code_of(id), reference), check_column_references(code_of(id), all_code, variables))
  })

  run <- run_analysis_scripts(login_file, sort(c(other_files, unlist(candidate, use.names = FALSE))))
  if (!is.na(run$login_error)) {
    stop(sprintf("The DSLite test setup (%s) failed: %s", login_file, run$login_error), call. = FALSE)
  }
  for (id in ids) {
    runtime <- run$errors[candidate[[id]]]
    runtime <- runtime[!is.na(runtime)]
    if (length(runtime) > 0) {
      problems[[id]] <- c(problems[[id]], sprintf("Error when running %s: %s", names(runtime)[1], runtime[[1]]))
    }
  }
  broken <- run$errors[other_files]
  list(problems = Filter(length, problems), broken_other = broken[!is.na(broken)])
}
