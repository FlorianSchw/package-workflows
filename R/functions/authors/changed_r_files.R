# Files under R/ that a commit changed, from local git (the GitHub API
# caps the file list per commit). Decides between `aut` and `ctb` in
# credit_contributor().
changed_r_files <- function(sha) {
  files <- system2("git", c("show", "--name-only", "--format=", sha), stdout = TRUE)
  files[grepl("^R/.+\\.[Rr]$", files)]
}
