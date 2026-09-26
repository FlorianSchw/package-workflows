# What a job's steps do, as short lines for a diagram box: a step's
# `name:` if it has one; otherwise the action it uses ("check-r-package"
# for r-lib/actions/check-r-package@v2) or the first line of its script
# ("gh issue create …"). Unnamed plumbing — checkout, setup-*, cache — is
# left out. More than `max` lines are cut with "… n more".
step_names <- function(job, max = 8) {
  plumbing <- "^(checkout|setup-.*|cache)$"
  names <- unlist(lapply(job$steps, function(s) {
    if (!is.null(s$name)) return(as.character(s$name))
    if (!is.null(s$uses)) {
      action <- sub("@.*$", "", basename(s$uses))
      return(if (grepl(plumbing, action)) NULL else action)
    }
    first <- trimws(strsplit(as.character(s$run), "\n", fixed = TRUE)[[1]])
    first <- first[nzchar(first)][1]
    if (is.na(first)) return(NULL)
    if (nchar(first) > 30) paste0(substr(first, 1, 29), "…") else first
  }))
  if (length(names) > max) names <- c(names[seq_len(max - 1)], sprintf("… %d more", length(names) - max + 1))
  if (length(names) == 0) return(character(0))
  paste("•", names)
}
