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
roxygen_review_settings <- config::get(file = resolve_shared_path("config/claude.yml"))
anthropic_config <- roxygen_review_settings$anthropic
accept_reasons <- unlist(roxygen_review_settings$accept_reasons)

api_key    <- Sys.getenv("ANTHROPIC_API_KEY")
gh_token   <- Sys.getenv("GH_TOKEN")
repo       <- Sys.getenv("GITHUB_REPOSITORY")
pr_number  <- Sys.getenv("PR_NUMBER")  # empty in a sweep
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
report_files <- list()  # per file: applied and dropped changes, for the PR description
code_issue_files <- list()  # per file: likely code defects Claude noticed

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

# Applied and not-applied changes go into the suggestion PR's description —
# only when there is a PR at all, so notes alone never open one.
# Possible code bugs: in a PR run a comment on that PR (the author's code;
# posted once), in a sweep a section of the sweep PR's description, and
# without a sweep PR only the log (an issue would need `issues: write`,
# which roxygen callers don't grant).
is_sweep <- !nzchar(pr_number)
if (length(updated_files) > 0) {
  writeLines(format_roxygen_report(report_files, if (is_sweep) code_issue_files else list()), "suggestion_report.md")
}
if (length(code_issue_files) > 0 && !is_sweep) {
  comment_once(pr_number, paste(format_code_issues(code_issue_files), collapse = "\n"), "possible code bugs")
} else if (length(code_issue_files) > 0 && length(updated_files) == 0) {
  message("Possible code bugs (no sweep PR to report them in):\n", paste(format_code_issues(code_issue_files), collapse = "\n"))
}
