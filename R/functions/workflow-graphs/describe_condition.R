# A job's `if:` in words where the pattern is common ("only on schedule",
# "only if the PR comes from dev", "skipped for PRs from bot-suggest/
# branches"), else the expression itself as "if: …". Never cut short —
# labels are wrapped instead (mermaid_label()). `cond` is without ${{ }}.
describe_condition <- function(cond) {
  q <- "'([^']*)'"
  head <- "(?:github\\.head_ref|github\\.event\\.pull_request\\.head\\.ref)"
  base <- "(?:github\\.base_ref|github\\.event\\.pull_request\\.base\\.ref)"
  patterns <- list(
    list(sprintf("^github\\.event_name\\s*==\\s*%s$", q), "only on %s"),
    list(sprintf("^github\\.event_name\\s*!=\\s*%s$", q), "not on %s"),
    list(sprintf("^%s\\s*==\\s*%s$", head, q), "only if the PR comes from %s"),
    list(sprintf("^%s\\s*!=\\s*%s$", head, q), "not if the PR comes from %s"),
    list(sprintf("^%s\\s*==\\s*%s$", base, q), "only for PRs into %s"),
    list(sprintf("^github\\.ref_name\\s*==\\s*%s$", q), "only on branch %s"),
    list(sprintf("^!\\s*startsWith\\(%s,\\s*%s\\)$", head, q), "skipped for PRs from %s branches"),
    list(sprintf("^startsWith\\(%s,\\s*%s\\)$", head, q), "only for PRs from %s branches"),
    list("^github\\.event\\.pull_request\\.merged(\\s*==\\s*true)?$", "only if the PR was merged")
  )
  for (p in patterns) {
    m <- regmatches(cond, regexec(p[[1]], cond, perl = TRUE))[[1]]
    if (length(m) >= 1 && grepl("%s", p[[2]], fixed = TRUE)) {
      if (length(m) == 2) return(sprintf(p[[2]], gsub("_", " ", m[2])))
    } else if (length(m) >= 1) {
      return(p[[2]])
    }
  }
  paste0("if: ", cond)
}
