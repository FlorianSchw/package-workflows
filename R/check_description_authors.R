#!/usr/bin/env Rscript
# Credits every PR commit author in DESCRIPTION — `aut` if any of their
# commits changed files under R/, `ctb` otherwise (credit_contributor()) —
# and lists DESCRIPTION in updated_files.txt for the workflow to commit,
# with the changes and their reasons in suggestion_report.md for the
# suggestion PR's description. Merge commits don't count as contributions.
#
# Each commit is resolved to its GitHub account's profile display name
# (commits API + users API), not the free-text git author name a
# contributor happened to set locally — avoids false positives like a
# GitHub handle not matching an existing "Real Name" entry. Falls back to
# the git author name when a commit isn't linked to any GitHub account, or
# when that account's profile name is blank. Accounts and names listed in
# config/bot-authors.json are skipped.

library(httr2)
library(jsonlite)
library(purrr)

functions_dir <- if (dir.exists("R/functions")) "R/functions" else ".shared-workflows/R/functions"
walk(list.files(functions_dir, pattern = "\\.R$", full.names = TRUE), source)

gh_token <- Sys.getenv("GH_TOKEN")
repo     <- Sys.getenv("GITHUB_REPOSITORY")
base_ref <- Sys.getenv("BASE_REF")

bot_names <- unlist(read_json_config("config/bot-authors.json", required = TRUE)$bot_names)

shas <- unique(system2("git", c("log", "--no-merges", sprintf("origin/%s...HEAD", base_ref), "--format=%H"), stdout = TRUE))

contributors <- list()  # resolved name -> files under R/ they changed
login_names <- list()   # GitHub login -> resolved name, one users API call each

for (sha in shas) {
  commit_data <- get_github_json(sprintf("/repos/%s/commits/%s", repo, sha))
  if (is.null(commit_data)) next

  git_author_name <- commit_data$commit$author$name
  gh_author <- commit_data$author

  if (is.null(gh_author)) {
    if (is.null(git_author_name) || git_author_name %in% bot_names) next
    name <- git_author_name
  } else {
    login <- gh_author$login
    if (login %in% bot_names) next
    if (is.null(login_names[[login]])) {
      user_data <- get_github_json(sprintf("/users/%s", login))
      login_names[[login]] <- if (!is.null(user_data) && !is.null(user_data$name) && nzchar(user_data$name)) {
        user_data$name
      } else {
        git_author_name
      }
    }
    name <- login_names[[login]]
  }
  if (is.null(name)) next

  contributors[[name]] <- union(contributors[[name]], changed_r_files(sha))
}

d <- desc::description$new("DESCRIPTION")
report <- unlist(lapply(names(contributors), function(name) credit_contributor(d, name, contributors[[name]])))

if (length(report) > 0) {
  d$write("DESCRIPTION")
  writeLines("DESCRIPTION", "updated_files.txt")
  writeLines(c("## Changes", "", report), "suggestion_report.md")
}
