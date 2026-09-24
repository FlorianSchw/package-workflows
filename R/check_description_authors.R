#!/usr/bin/env Rscript
# Adds every PR commit author not yet credited in DESCRIPTION (role "aut")
# and lists DESCRIPTION in updated_files.txt for the workflow to commit.
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

shas <- unique(system2("git", c("log", sprintf("origin/%s...HEAD", base_ref), "--format=%H"), stdout = TRUE))

resolved_names <- character(0)
seen_logins <- character(0)

for (sha in shas) {
  commit_data <- get_github_json(sprintf("/repos/%s/commits/%s", repo, sha))
  if (is.null(commit_data)) next

  git_author_name <- commit_data$commit$author$name
  gh_author <- commit_data$author

  if (is.null(gh_author)) {
    if (!is.null(git_author_name) && !git_author_name %in% bot_names) {
      resolved_names <- c(resolved_names, git_author_name)
    }
    next
  }

  login <- gh_author$login
  if (login %in% bot_names || login %in% seen_logins) next
  seen_logins <- c(seen_logins, login)

  user_data <- get_github_json(sprintf("/users/%s", login))
  profile_name <- if (!is.null(user_data) && !is.null(user_data$name) && nzchar(user_data$name)) {
    user_data$name
  } else {
    git_author_name
  }

  if (!is.null(profile_name)) {
    resolved_names <- c(resolved_names, profile_name)
  }
}

d <- desc::description$new("DESCRIPTION")
existing <- format(d$get_authors())

new_people <- Filter(
  function(name) !any(grepl(name, existing, fixed = TRUE)),
  unique(resolved_names)
)

if (length(new_people) > 0) {
  for (name in new_people) {
    d$add_author(given = name, role = "aut")
  }
  d$write("DESCRIPTION")
  writeLines("DESCRIPTION", "updated_files.txt")
}
