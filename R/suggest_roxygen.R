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
accept_reasons <- accepted_reasons(Sys.getenv("ACCEPT_REASONS"), roxygen_review_settings$accept_reasons, "roxygen")
code_issue_confidence <- code_issue_confidence_levels(Sys.getenv("CODE_ISSUE_CONFIDENCE"), roxygen_review_settings$code_issue_confidence)

api_key    <- Sys.getenv("ANTHROPIC_API_KEY")
gh_token   <- Sys.getenv("GH_TOKEN")
repo       <- Sys.getenv("GITHUB_REPOSITORY")
pr_number  <- Sys.getenv("PR_NUMBER")  # empty in a sweep
datashield <- as.logical(Sys.getenv("DATASHIELD", "false"))
ds_type    <- Sys.getenv("DATASHIELD_TYPE", "")
# PR and push runs (empty in a sweep): the reviewed commit, the state before
# this run's changes, and the bot branch whose open PR is built on.
reviewed_sha <- substr(Sys.getenv("REVIEWED_SHA"), 1, 7)
base_rev     <- Sys.getenv("BASE_REV")
sub_branch   <- Sys.getenv("SUB_BRANCH")
builds_on_open_pr <- nzchar(sub_branch) && identical(Sys.getenv("OPEN_SUGGESTION_PR", "add"), "add") && !identical(Sys.getenv("REBUILD"), "true")

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

# With an open bot PR to build on, its findings and proposed blocks are
# the starting point: functions are reviewed on top of what it already
# proposes, and its report is merged with this run's findings instead of
# growing an update per run (see dev-notes/roxygen-suggest.md).
pr_body <- if (builds_on_open_pr) fetch_suggestion_pr_body(sub_branch) else NULL
state <- decode_suggestion_state(pr_body)
# The user's checkboxes (dev-notes/suggestion-choices.md): recorded before
# anything else, so the rebuilt description keeps them.
state <- record_suggestion_choices(state, read_suggestion_choices(pr_body))
# code-issue-confidence "none": no possible bugs — not asked for, and
# earlier ones leave the report too.
with_code_issues <- length(code_issue_confidence) > 0
if (!with_code_issues) state$entries <- Filter(function(e) !identical(e$kind, "bug"), state$entries)
bot_ref <- if (!is.null(pr_body)) fetch_bot_branch(sub_branch) else NULL
stats <- c(new = 0L, crossed = 0L, repeats = 0L)

# --- Main loop ---------------------------------------------------------------

updated_files <- character(0)

for (f in files) {
  parsed <- tryCatch(parse_r_file(f), error = function(e) {
    message(sprintf("Skipping %s: %s", f, conditionMessage(e)))
    NULL
  })
  if (is.null(parsed)) next
  source_block <- review_source_block(f, parsed, bot_ref, base_rev)
  parsed <- source_block$parsed
  if (source_block$from_bot) message(sprintf("%s: reviewing the block the open bot PR proposes.", f))
  # Fields the user declined stay as they are, unless the function's code
  # changed since (declined_suggestions()).
  fingerprint <- code_fingerprint(fn_source(parsed))
  declined <- declined_suggestions(state, function(e) identical(e$file, f), fingerprint, reviewed_sha)
  state <- declined$state
  declined_fields <- vapply(Filter(function(e) identical(e$kind, "applied"), declined$declined), function(e) e$field, character(1))
  earlier <-Filter(function(e) identical(e$file, f) && identical(e$status, "active") && e$kind %in% c("dropped", "bug"), state$entries)

  file_role_text <- if (identical(ds_type, "utility") && !uses_ds_connections(parsed)) role_text_local else role_text
  result <- tryCatch(ask_claude_for_review(parsed, select_profile(parsed), file_role_text, earlier, with_code_issues), error = function(e) {
    message(sprintf("Claude call failed for %s: %s", f, conditionMessage(e)))
    warn_failed_call(f, f, e)
    note_retry_file(f)
    NULL
  })
  if (is.null(result)) next

  # Code defects are reported whether or not the documentation changes.
  run <- list(applied = list(), dropped = list(), decisions = result$earlier_findings,
              bugs = kept_code_issues(result$code_issues, code_issue_confidence, f), code = fingerprint)
  if (length(run$bugs) > 0) message(sprintf("%s: %d possible code issue(s) noted.", f, length(run$bugs)))

  if (!isTRUE(result$needs_changes)) {
    message(sprintf("%s: documentation already adequate, skipping.", f))
  } else {
    review <- accepted_roxygen_fields(result, parsed, accept_reasons, f)
    for (key in intersect(review$accepted, declined_fields)) {
      message(sprintf("%s: not changing '%s' again — declined.", f, key))
    }
    review$accepted <- setdiff(review$accepted, declined_fields)
    review$applied <- Filter(function(ch) !ch$field %in% declined_fields, review$applied)
    run$dropped <- review$dropped
    new_block <- if (length(review$accepted) == 0) {
      message(sprintf("%s: no change above the threshold, skipping.", f))
      NULL
    } else {
      tryCatch(build_roxygen_block(result, parsed, f, review$accepted), error = function(e) {
        message(sprintf("Failed to assemble roxygen block for %s: %s", f, conditionMessage(e)))
        NULL
      })
    }
    if (!is.null(new_block)) {
      message(sprintf("%s: updating %s.", f, paste(review$accepted, collapse = ", ")))
      write_in_place(f, parsed, new_block)
      updated_files <- c(updated_files, f)
      run$applied <- review$applied
    }
  }

  merged <- merge_roxygen_findings(state, f, run, reviewed_sha, source_block$user_edited)
  state <- merged$state
  stats <- stats + merged$stats
}

writeLines(updated_files, "updated_files.txt")

# Everything about the suggestions — applied and not-applied changes and
# possible code bugs — goes into the suggestion PR's description, which is
# rebuilt from all findings on every run (commit-updated-files with
# pr-body-mode "replace"), with a one-line statistic on top that the link
# comment on the originating PR repeats (suggestion_summary.md). Written
# when this run changes files or a bot PR is open; notes alone never open
# one. Without a suggestion PR, possible bugs go to a comment on the
# originating PR (posted once), or in a sweep to that month's issue
# (report_sweep_code_issues(); callers grant `issues: write`).
if (length(updated_files) > 0 || !is.null(pr_body)) {
  writeLines(format_roxygen_summary(state), "suggestion_summary.md")
  writeLines(format_roxygen_report(state, list(sha = reviewed_sha, stats = stats), state$legacy), "suggestion_report.md")
} else if (any(vapply(state$entries, function(e) identical(e$kind, "bug"), logical(1)))) {
  bugs <- paste(format_code_issues(state$entries), collapse = "\n")
  if (nzchar(pr_number)) {
    comment_once(pr_number, bugs, "possible code bugs")
  } else {
    report_sweep_code_issues(bugs)
  }
}
