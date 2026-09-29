# All code of one of Claude's steps, its sections joined, as the checks
# and the repair request see it.
step_code <- function(answer) {
  paste(vapply(answer$sections, function(s) s$code, character(1)), collapse = "\n")
}
