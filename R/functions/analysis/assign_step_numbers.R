# File numbers for the steps to write: a step that has scripts keeps its
# number; new steps continue after the highest number in `dir`, starting
# at `numbering$first` (01 is the login). Numbers from
# `numbering$reserved_from` up (e.g. 99_DSLiteLearning.R in older
# dsAnalysis projects) are left out, or new steps would get 100.
# Returns a named list, step id -> "NN".
assign_step_numbers <- function(to_write, existing, dir, numbering) {
  taken <- as.integer(substr(list.files(dir, pattern = "^[0-9]{2}[a-z]?_.*\\.R$"), 1, 2))
  next_number <- max(c(numbering$first - 1L, taken[taken < numbering$reserved_from])) + 1L
  numbers <- list()
  for (id in to_write) {
    own <- existing$number[existing$step == id]
    if (length(own) > 0) {
      numbers[[id]] <- own[1]
    } else {
      numbers[[id]] <- sprintf("%02d", next_number)
      next_number <- next_number + 1L
    }
  }
  numbers
}
