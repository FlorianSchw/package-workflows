#!/usr/bin/env Rscript
# Reads files_to_check.txt (produced by the calling workflow), reviews each
# function's roxygen2 documentation for completeness AND accuracy against
# style guidance (and, for DataSHIELD packages, role-specific guidance), and
# either posts a GitHub PR suggestion comment (SCAN_MODE=changed) or rewrites
# the file in place (SCAN_MODE=all, caller commits + opens a PR).
#
# Claude never assembles the final roxygen text: it returns individual prose
# fields (title, description, per-param docs, return, examples), and this
# script deterministically stitches them into one block in the configured
# tag order. @export/@import/@importFrom lines are carried forward verbatim
# from the original file and never pass through Claude at all.
#
# This file only wires environment/config inputs together and runs the main
# loop. All logic lives in R/functions/ — one function per file, loaded in
# bulk below.

library(httr2)
library(jsonlite)
library(purrr)
# config package is used namespaced (config::get()) only — its own docs warn
# against library(config), since it masks base::get()/base::merge().

functions_dir <- if (dir.exists("R/functions")) "R/functions" else ".shared-workflows/R/functions"
walk(list.files(functions_dir, pattern = "\\.R$", full.names = TRUE), source)

# R_CONFIG_ACTIVE picks the active profile in config.yml (e.g. "roxygen-review")
# — set via a caller-workflow step that writes .Renviron before this script runs.
anthropic_config <- config::get(file = load_config("config.yml", ".shared-workflows/config.yml"))$anthropic

scan_mode     <- Sys.getenv("SCAN_MODE", "changed")
pr_number     <- Sys.getenv("PR_NUMBER")
pr_head_sha   <- Sys.getenv("PR_HEAD_SHA")
repo          <- Sys.getenv("GITHUB_REPOSITORY")
api_key       <- Sys.getenv("ANTHROPIC_API_KEY")
gh_token      <- Sys.getenv("GH_TOKEN")
datashield    <- as.logical(Sys.getenv("DATASHIELD", "false"))
ds_type       <- Sys.getenv("DATASHIELD_TYPE", "")

if (isTRUE(datashield) && !ds_type %in% c("client", "server")) {
  message("DATASHIELD is true but DATASHIELD_TYPE is not 'client' or 'server' — skipping role-specific guidance.")
}

style <- fromJSON(
  load_config("roxygen-style.json", ".shared-workflows/config/roxygen-style.json"),
  simplifyVector = FALSE
)

prompt_template <- paste(
  readLines(
    load_config("prompts/roxygen-review-prompt.md", ".shared-workflows/prompts/roxygen-review-prompt.md"),
    warn = FALSE
  ),
  collapse = "\n"
)

example_env <- NULL
if (isTRUE(datashield) && identical(ds_type, "client")) {
  env_path <- load_config("datashield-example-env.json", ".shared-workflows/config/datashield-example-env.json")
  if (file.exists(env_path)) example_env <- fromJSON(env_path, simplifyVector = FALSE)
}

role_guidance_config <- NULL
if (isTRUE(datashield)) {
  role_guidance_path <- load_config("datashield-role-guidance.json", ".shared-workflows/config/datashield-role-guidance.json")
  if (file.exists(role_guidance_path)) role_guidance_config <- fromJSON(role_guidance_path, simplifyVector = FALSE)
}

package_name <- tryCatch({
  desc <- read.dcf("DESCRIPTION")
  as.character(desc[1, "Package"])
}, error = function(e) NA_character_)

matched_group <- NULL
if (!is.null(example_env) && !is.na(package_name)) {
  for (grp in example_env$study_groups) {
    if (package_name %in% unlist(grp$compatible_packages)) { matched_group <- grp; break }
  }
  if (is.null(matched_group)) {
    message(sprintf("No compatible demo study group found for package '%s' — skipping canonical example guidance.", package_name))
  }
}

files <- readLines("files_to_check.txt")
files <- files[nzchar(files)]

# --- Main loop ---------------------------------------------------------------

updated_files <- character(0)

for (f in files) {
  parsed <- tryCatch(parse_r_file(f), error = function(e) {
    message(sprintf("Skipping %s: %s", f, conditionMessage(e)))
    NULL
  })
  if (is.null(parsed)) next

  profile   <- select_profile(parsed)
  role_text <- role_guidance(datashield, ds_type, matched_group, example_env, role_guidance_config)

  result <- tryCatch(ask_claude(parsed, profile, role_text), error = function(e) {
    message(sprintf("Claude call failed for %s: %s", f, conditionMessage(e)))
    NULL
  })
  if (is.null(result)) next

  if (!isTRUE(result$needs_changes)) {
    message(sprintf("%s: documentation already adequate, skipping.", f))
    next
  }

  new_block <- tryCatch(build_roxygen_block(result, parsed, f), error = function(e) {
    message(sprintf("Failed to assemble roxygen block for %s: %s", f, conditionMessage(e)))
    NULL
  })
  if (is.null(new_block)) next

  message(sprintf("%s: updating %s.", f, paste(unlist(result$changed_tags), collapse = ", ")))

  write_in_place(f, parsed, new_block)
  updated_files <- c(updated_files, f)
}

writeLines(updated_files, "docs_updated_files.txt")
