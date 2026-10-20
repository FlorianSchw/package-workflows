# Applies one function's proposed test changes, test file by test file
# (`changed_paths`), keeping only what passed (apply_test_file_changes()),
# and records the outcome in `run` (the function's findings for
# merge_test_findings()): new tests that passed, updates kept, deletions,
# and a note per update that still failed. Failed new tests are returned
# for one classification per function, except repeats of a failure
# reported before (counted in run$repeats).
#
# `review` is the function's review in review_test_file(): test_files,
# blocks and reviews by path of its existing test files, the new tests
# (new_tests, targets, new_by_file from place_new_tests()), Claude's
# `result`, `earlier` findings, scheme. Returns list(run, updated, kept_new,
# failures).
apply_function_test_changes <- function(changed_paths, review, run, function_name, package_name) {
  paths <- names(review$test_files)
  new_test_of <- function(description) Find(function(t) identical(t$description, description), review$new_tests)
  updated <- character(0)
  kept_new <- 0
  failures <- list()
  for (path in changed_paths) {
    test_file <- if (path %in% paths) {
      review$test_files[[path]]
    } else {
      read_test_file(path, if (review$scheme$categorised) {
        review$new_tests[review$targets %in% path][[1]]$category
      } else {
        NA_character_
      })
    }
    file_review <- if (path %in% paths) {
      review$reviews[[path]]
    } else {
      list(updates = character(0), deletes = character(0), explanations = character(0))
    }
    test_blocks <- if (is.null(review$new_by_file[[path]])) {
      character(0)
    } else {
      review$new_by_file[[path]]
    }
    applied <- apply_test_file_changes(test_file, if (path %in% paths) {
      review$blocks[[path]]
    } else {
      list()
    },
                                       file_review$updates, file_review$deletes, test_blocks, review$result, function_name, package_name)

    for (d in applied$failed_updates) {
      run$notes[[length(run$notes) + 1]] <- list(file = path, description = d, text = sprintf("an update was proposed (%s) but still failed, so the original test was kept.", file_review$explanations[[d]]))
    }
    if (!is.null(applied$path)) {
      updated <- c(updated, applied$path)
      kept_new <- kept_new + length(applied$passing_new)
      for (d in applied$passing_new) {
        t <- new_test_of(d)
        run$new[[length(run$new) + 1]] <- list(file = path, description = d, reason = t$reason, repeats_earlier = t$repeats_earlier)
      }
      for (d in names(applied$kept_updates)) {
        run$changes[[length(run$changes) + 1]] <- list(file = path, description = d, action = "updated", reason = "contract_changed", explanation = file_review$explanations[[d]])
      }
      for (d in file_review$deletes) {
        run$changes[[length(run$changes) + 1]] <- list(file = path, description = d, action = "deleted", reason = "", explanation = file_review$explanations[[d]])
      }
      message(sprintf("%s: %d new test(s), %d update(s), %d deletion(s) in %s.", function_name, length(applied$passing_new), length(applied$kept_updates), length(file_review$deletes), path))
    }

    # Failed new tests: repeats of earlier failures skipped, the rest
    # collected for one classification per function.
    for (fail in applied$failing_new) {
      if (repeated_failure(fail, new_test_of(fail$description), review$earlier)) {
        message(sprintf("%s: '%s' failed again — reported before.", function_name, fail$description))
        run$repeats <- run$repeats + 1L
        next
      }
      failures[[length(failures) + 1]] <- list(fail = fail, path = path, block = test_blocks[[fail$description]], message = fail$message)
    }
  }
  list(run = run, updated = updated, kept_new = kept_new, failures = failures)
}
