#!/usr/bin/env Rscript
# Reads files_to_check.txt (produced by the calling workflow), reviews each
# function's roxygen2 documentation for completeness AND accuracy against
# style guidance (and, for DataSHIELD packages, role-specific guidance),
# rewrites the file in place, and lists every rewritten file in
# updated_files.txt for the workflow to commit.
#
# Claude never assembles the final roxygen text: it returns individual prose
# fields (title, description, per-param docs, return, examples), and this
# script deterministically stitches them into one block in the configured
# tag order. Every other tag in the original block (@export, @import,
# @author, @seealso, ...) is carried forward verbatim and never passes
# through Claude at all.
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

# R_CONFIG_ACTIVE picks the active profile in config/claude.yml ("roxygen-review")
# — set as an env var on the calling workflow step.
anthropic_config <- config::get(file = resolve_shared_path("config/claude.yml"))$anthropic

api_key    <- Sys.getenv("ANTHROPIC_API_KEY")
datashield <- as.logical(Sys.getenv("DATASHIELD", "false"))
ds_type    <- Sys.getenv("DATASHIELD_TYPE", "")

if (isTRUE(datashield) && !ds_type %in% c("client", "server")) {
  message("DATASHIELD is true but DATASHIELD_TYPE is not 'client' or 'server' — skipping role-specific guidance.")
}

style           <- read_json_config("config/roxygen-style.json", required = TRUE)
roxygen_review_prompt_template <- read_text_file("prompts/roxygen-review-prompt.md")
package_name    <- read_package_name()

# Role guidance depends only on the package, not the file — built once.
role_text <- ""
if (isTRUE(datashield)) {
  demo_snippet <- NULL
  if (identical(ds_type, "client")) {
    example_env <- read_json_config("config/datashield-example-env.json")
    group <- find_study_group(example_env, package_name)
    if (is.null(group)) {
      message(sprintf("No compatible demo study group found for package '%s' — skipping canonical example guidance.", package_name))
    } else {
      demo_snippet <- build_demo_login_snippet(package_name, group, example_env$server)
    }
  }
  role_text <- role_guidance(datashield, ds_type, read_json_config("config/datashield-role-guidance.json"), demo_snippet)
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

  result <- tryCatch(ask_claude_for_review(parsed, select_profile(parsed), role_text), error = function(e) {
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

writeLines(updated_files, "updated_files.txt")
