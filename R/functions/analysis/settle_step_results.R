# Sets each written step's final status from draft_and_test_steps()'s
# result `drafted`: "written", "not_possible" (notes only), or "failed" —
# no answer, or still failing after all attempts. A failed step's new
# scripts are removed and its previous ones restored from
# `old_content` (path -> lines). Returns list(steps, written_files).
settle_step_results <- function(steps, to_write, drafted, rewritten, old_content, texts) {
  candidate <- drafted$candidate
  for (id in to_write) {
    answer <- drafted$answers[[id]]
    if (is.null(answer)) {
      steps[[id]]$status <- "failed"
      steps[[id]]$error <- texts$step$no_answer
    } else if (id %in% names(drafted$outcome$problems)) {
      steps[[id]]$status <- "failed"
      steps[[id]]$error <- fill_template(texts$step$still_failing, list(
        ATTEMPTS = drafted$attempts, PROBLEMS = paste(drafted$outcome$problems[[id]], collapse = " ")
      ))
      unlink(candidate[[id]])
      candidate[[id]] <- NULL
    } else {
      steps[[id]]$status <- if (length(answer$sections) == 0) "not_possible" else "written"
      steps[[id]]$files <- candidate[[id]]
    }
    steps[[id]]$notes <- if (is.null(answer)) list() else answer$notes
    if (steps[[id]]$status == "failed") {
      for (p in rewritten$path[rewritten$step == id]) writeLines(old_content[[p]], p)
    }
  }
  list(steps = steps, written_files = unlist(candidate, use.names = FALSE))
}
