# A job's `if:` in words where the pattern is common ("only on schedule",
# "only if the PR comes from dev", "not for bot-suggest/ branches"), else
# the expression itself, cut at 60 characters. `cond` is without ${{ }}.
describe_condition <- function(cond) {
  q <- "'([^']*)'"
  patterns <- list(
    list(sprintf("^github\\.event_name\\s*==\\s*%s$", q), "only on %s"),
    list(sprintf("^github\\.event_name\\s*!=\\s*%s$", q), "not on %s"),
    list(sprintf("^github\\.head_ref\\s*==\\s*%s$", q), "only if the PR comes from %s"),
    list(sprintf("^github\\.ref_name\\s*==\\s*%s$", q), "only on branch %s"),
    list(sprintf("^!startsWith\\(github\\.head_ref,\\s*%s\\)$", q), "not for %s branches"),
    list(sprintf("^startsWith\\(github\\.head_ref,\\s*%s\\)$", q), "only for %s branches")
  )
  for (p in patterns) {
    m <- regmatches(cond, regexec(p[[1]], cond, perl = TRUE))[[1]]
    if (length(m) == 2) return(sprintf(p[[2]], gsub("_", " ", m[2])))
  }
  if (nchar(cond) > 60) paste0("if: ", substr(cond, 1, 57), "...") else paste0("if: ", cond)
}
