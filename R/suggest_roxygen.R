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
# loop. All logic lives in R/functions/shared/ and R/functions/roxygen/ —
# one function per file, loaded in bulk below.

library(httr2)
library(jsonlite)
library(purrr)
# config package is used namespaced (config::get()) only — its own docs warn
# against library(config), since it masks base::get()/base::merge().

functions_dir <- if (dir.exists("R/functions")) "R/functions" else ".shared-workflows/R/functions"
walk(list.files(file.path(functions_dir, c("shared", "roxygen")), pattern = "\\.R$", full.names = TRUE), source)

# R_CONFIG_ACTIVE picks the active profile in config/claude.yml ("roxygen-review")
# — set as an env var on the calling workflow step.
roxygen_review_settings <- config::get(file = resolve_shared_path("config/claude.yml"))
anthropic_config <- roxygen_review_settings$anthropic
accept_reasons <- unlist(roxygen_review_settings$accept_reasons)

api_key    <- Sys.getenv("ANTHROPIC_API_KEY")
gh_token   <- Sys.getenv("GH_TOKEN")
repo       <- Sys.getenv("GITHUB_REPOSITORY")
pr_number  <- Sys.getenv("PR_NUMBER")  # empty in a sweep
datashield <- as.logical(Sys.getenv("DATASHIELD", "false"))
ds_type    <- Sys.getenv("DATASHIELD_TYPE", "")

check_datashield_type(datashield, ds_type)

style           <- read_json_config("config/roxygen-style.json", required = TRUE)
roxygen_review_prompt_template <- read_text_file("prompts/roxygen-review-prompt.md")
package_name    <- read_package_name()

# Role guidance depends only on the package — built once. A utility package
# also gets a variant without the demo login example, for its functions
# that don't use DataSHIELD connections (chosen per file below); its demo
# study group is found via the packages it depends on (e.g. dsBaseClient).
role_text <- ""
role_text_local <- ""
if (isTRUE(datashield)) {
  demo_snippet <- NULL
  if (ds_type %in% c("client", "utility")) {
    example_env <- read_json_config("config/datashield-example-env.json")
    candidates <- if (identical(ds_type, "utility")) c(package_name, read_package_dependencies()) else package_name
    group <- find_study_group(example_env, candidates)
    if (is.null(group)) {
      message(sprintf("No compatible demo study group found for package '%s' — skipping canonical example guidance.", package_name))
    } else {
      demo_snippet <- build_demo_login_snippet(package_name, group, example_env$server)
    }
  }
  role_config <- read_json_config("config/datashield-role-guidance.json")
  role_text <- role_guidance(datashield, ds_type, role_config, demo_snippet)
  role_text_local <- role_guidance(datashield, ds_type, role_config, NULL)
}

files <- readLines("files_to_check.txt")
files <- files[nzchar(files)]

# --- Main loop ---------------------------------------------------------------

updated_files <- character(0)
report_files <- list()  # per file: applied and dropped changes, for the PR description
code_issue_files <- list()  # per file: likely code defects Claude noticed

for (f in files) {
  parsed <- tryCatch(parse_r_file(f), error = function(e) {
    message(sprintf("Skipping %s: %s", f, conditionMessage(e)))
    NULL
  })
  if (is.null(parsed)) next

  file_role_text <- if (identical(ds_type, "utility") && !uses_ds_connections(parsed)) role_text_local else role_text
  result <- tryCatch(ask_claude_for_review(parsed, select_profile(parsed), file_role_text), error = function(e) {
    message(sprintf("Claude call failed for %s: %s", f, conditionMessage(e)))
    NULL
  })
  if (is.null(result)) next

  # Code defects are reported whether or not the documentation changes.
  if (length(result$code_issues) > 0) {
    code_issue_files[[length(code_issue_files) + 1]] <- list(path = f, issues = result$code_issues)
    message(sprintf("%s: %d possible code issue(s) noted.", f, length(result$code_issues)))
  }

  if (!isTRUE(result$needs_changes)) {
    message(sprintf("%s: documentation already adequate, skipping.", f))
    next
  }

  review <- accepted_roxygen_fields(result, parsed, accept_reasons, f)
  accepted <- review$accepted
  report_files[[length(report_files) + 1]] <- list(path = f, applied = review$applied, dropped = review$dropped)
  if (length(accepted) == 0) {
    report_files[[length(report_files)]]$applied <- list()
    message(sprintf("%s: no change above the threshold, skipping.", f))
    next
  }

  new_block <- tryCatch(build_roxygen_block(result, parsed, f, accepted), error = function(e) {
    message(sprintf("Failed to assemble roxygen block for %s: %s", f, conditionMessage(e)))
    NULL
  })
  if (is.null(new_block)) {
    report_files[[length(report_files)]]$applied <- list()
    next
  }

  message(sprintf("%s: updating %s.", f, paste(accepted, collapse = ", ")))

  write_in_place(f, parsed, new_block)
  updated_files <- c(updated_files, f)
}

writeLines(updated_files, "updated_files.txt")

# Everything about the suggestions — applied and not-applied changes and
# possible code bugs — goes into the suggestion PR's description, with a
# one-line statistic on top that the link comment on the originating PR
# repeats (suggestion_summary.md). Only written when there is a PR, so
# notes alone never open one. Without a suggestion PR, possible bugs go to
# a comment on the originating PR (posted once), or in a sweep only to the
# log (an issue would need `issues: write`, which roxygen callers don't
# grant).
if (length(updated_files) > 0) {
  summary_line <- format_roxygen_summary(report_files, code_issue_files)
  writeLines(summary_line, "suggestion_summary.md")
  writeLines(c(paste("**Summary:**", summary_line), "", format_roxygen_report(report_files, code_issue_files)), "suggestion_report.md")
} else if (length(code_issue_files) > 0) {
  bugs <- paste(format_code_issues(code_issue_files), collapse = "\n")
  if (nzchar(pr_number)) {
    comment_once(pr_number, bugs, "possible code bugs")
  } else {
    message("Possible code bugs (no sweep PR to report them in):\n", bugs)
  }
}
