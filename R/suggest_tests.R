#!/usr/bin/env Rscript
# Reads files_to_check.txt (produced by the calling workflow) and, for each
# function's (first) file, reviews its tests with Claude: new real,
# runnable test_that() blocks where they add value, and decisions on
# existing tests — update an outdated one, delete an obsolete one, or
# report one that points to a possible bug. Claude sees the existing
# tests' current results and the history evidence (build_test_evidence())
# to tell an outdated test from a bug.
#
# Nothing is trusted unchecked: new tests pass filter_generated_tests(),
# decisions on existing tests pass review_existing_tests(), then every new
# and updated test is actually run. The test file is rewritten from its
# original content with only what passed (plus deletions) and listed in
# updated_files.txt for the workflow to propose; a failing new test is
# classified (bad_test / real_bug / env_misconfiguration) and surfaced,
# a failing update keeps the original test and is reported.
#
# Sibling to R/suggest_roxygen.R — same conventions: orchestration only
# here, logic in R/functions/, Claude call settings in config/claude.yml,
# deterministic field-based assembly (Claude never writes final test_that()
# syntax directly). See dev-notes/test-coverage-suggest.md and
# dev-notes/suggestion-thresholds.md for the design reasoning.

library(httr2)
library(jsonlite)
library(purrr)
# config package is used namespaced (config::get()) only — see
# R/suggest_roxygen.R for why library(config) is avoided.

functions_dir <- if (dir.exists("R/functions")) "R/functions" else ".shared-workflows/R/functions"
walk(list.files(functions_dir, pattern = "\\.R$", full.names = TRUE), source)

# R_CONFIG_ACTIVE (an env var set by the calling workflow step) selects
# "test-review" as the active profile; the failure classifier has its own
# profile, fetched explicitly by name.
config_path <- resolve_shared_path("config/claude.yml")
test_review_settings <- config::get(file = config_path)
anthropic_config <- test_review_settings$anthropic
accept_reasons <- unlist(test_review_settings$accept_reasons)
max_new_tests <- if (is.null(test_review_settings$max_new_tests)) 10L else as.integer(test_review_settings$max_new_tests)
failure_classification_config <- config::get(config = "test-failure-classification", file = config_path)$anthropic

api_key    <- Sys.getenv("ANTHROPIC_API_KEY")
gh_token   <- Sys.getenv("GH_TOKEN")
repo       <- Sys.getenv("GITHUB_REPOSITORY")
pr_number  <- Sys.getenv("PR_NUMBER")
base_ref   <- Sys.getenv("BASE_REF")  # empty in a sweep
is_sweep   <- !nzchar(pr_number)  # no PR to comment on (all mode)
datashield <- as.logical(Sys.getenv("DATASHIELD", "false"))
ds_type    <- Sys.getenv("DATASHIELD_TYPE", "")
is_client  <- isTRUE(datashield) && identical(ds_type, "client")

test_review_prompt_template           <- read_text_file("prompts/test-review-prompt.md")
failure_classification_prompt_template <- read_text_file("prompts/test-failure-classification-prompt.md")
test_role_guidance                    <- read_json_config("config/test-role-guidance.json", required = TRUE)
package_name                          <- read_package_name()

# DSLite's built-in canned datasets need no server/credentials/per-package
# matching — unlike datashield-example-env.json, which describes the real
# Opal demo server for roxygen's usage examples, a different scenario.
dslite_datasets <- if (is_client) read_json_config("config/dslite-canned-datasets.json")$datasets else NULL

files <- readLines("files_to_check.txt")
files <- files[nzchar(files)]

# Structure of the test data the package's setup/helper files create —
# once per run, in a separate R process.
test_data <- summarize_test_data(test_support_files(), functions_dir)
message("Test data:\n", test_data)

run_quietly <- function(path, what) {
  tryCatch(run_test_blocks(path, package_name), error = function(e) {
    message(sprintf("Running %s failed: %s", what, conditionMessage(e)))
    list()
  })
}
passed_in <- function(results, description) {
  isTRUE(Find(function(r) identical(r$description, description), results)$passed)
}

# --- Main loop ---------------------------------------------------------------

updated_files <- character(0)
counts <- c(new = 0, updated = 0, deleted = 0) # for format_test_summary()
created_setups <- character(0)
# Report entries per test file (format_test_report()):
sweep_failures <- list()   # failed new tests in a sweep (no PR to comment on)
existing_changes <- list() # applied updates/deletions, with reasons
existing_notes <- list()   # possible bugs, failing tests left unchanged
add_entry <- function(store, path, entries) {
  if (length(entries) > 0) store[[path]] <- c(store[[path]], entries)
  store
}

for (f in files) {
  parsed <- tryCatch(parse_r_file(f), error = function(e) {
    message(sprintf("Skipping %s: %s", f, conditionMessage(e)))
    NULL
  })
  if (is.null(parsed)) next

  function_name <- parsed$fn_name
  existing_test_file <- find_existing_test_file(function_name)
  blocks <- if (existing_test_file$exists) parse_test_file(existing_test_file$content) else list()
  baseline <- if (existing_test_file$exists) run_quietly(existing_test_file$path, sprintf("existing tests for %s", function_name)) else list()
  evidence <- build_test_evidence(f, existing_test_file$path, base_ref)

  # Re-checked per function: a DSLite setup generated for an earlier function
  # in this run is reused by later ones.
  has_existing_setup <- is_client && detect_dslite_setup()
  offered_datasets <- if (is_client && !has_existing_setup) dslite_datasets else NULL
  role_text <- build_test_role_guidance(datashield, ds_type, has_existing_setup, offered_datasets, test_role_guidance)

  result <- tryCatch(
    ask_claude_for_tests(parsed, existing_test_file, role_text, offered_datasets, format_test_results(baseline), evidence, max_new_tests, test_data),
    error = function(e) {
      message(sprintf("Claude call failed for %s: %s", function_name, conditionMessage(e)))
      NULL
    }
  )
  if (is.null(result)) next

  review <- review_existing_tests(result$existing_tests, blocks, baseline, function_name)
  existing_notes <- add_entry(existing_notes, existing_test_file$path, review$notes)

  # A failing existing test Claude left without any decision is reported too.
  decided <- vapply(result$existing_tests, function(d) d$description, character(1))
  for (r in Filter(function(r) !isTRUE(r$passed) && !r$description %in% decided, baseline)) {
    existing_notes <- add_entry(existing_notes, existing_test_file$path, sprintf("- \"%s\" — fails, no change proposed. %s", r$description, gsub("\\s+", " ", r$message)))
  }

  existing_descriptions <- vapply(blocks, function(b) b$description, character(1))
  new_tests <- if (isTRUE(result$needs_tests)) {
    filter_generated_tests(result$tests, existing_test_file$content, accept_reasons, function_name, existing_descriptions)
  } else {
    list()
  }
  test_blocks <- if (length(new_tests) > 0) {
    tryCatch(assemble_test_block(new_tests, function_name), error = function(e) {
      message(sprintf("Failed to assemble test blocks for %s: %s", function_name, conditionMessage(e)))
      character(0)
    })
  } else {
    character(0)
  }

  if (length(test_blocks) == 0 && length(review$updates) == 0 && length(review$deletes) == 0) {
    message(sprintf("%s: nothing to change.", function_name))
    next
  }

  created_setup <- NULL
  if (length(test_blocks) > 0 && !is.null(offered_datasets) && isTRUE(nzchar(result$dslite_dataset))) {
    dataset_choice <- Find(function(d) identical(d$name, result$dslite_dataset), offered_datasets)
    if (is.null(dataset_choice)) {
      message(sprintf(
        "%s: Claude returned dslite_dataset '%s', which isn't one of the offered options — skipping DSLite setup.",
        function_name, result$dslite_dataset
      ))
    } else {
      created_setup <- ensure_dslite_setup_file(dataset_choice, package_name)
    }
  }

  # Write ALL candidates (new tests, updates, deletions) so testthat can
  # actually run them.
  candidate <- rewrite_test_content(existing_test_file$content, blocks, review$updates, review$deletes, test_blocks)
  write_test_file(existing_test_file, candidate)
  run_results <- run_quietly(existing_test_file$path, sprintf("candidate tests for %s", function_name))

  passing_new <- names(test_blocks)[vapply(names(test_blocks), function(d) passed_in(run_results, d), logical(1))]
  failing_new <- Filter(function(r) r$description %in% setdiff(names(test_blocks), passing_new), run_results)
  kept_updates <- review$updates[vapply(names(review$updates), function(d) passed_in(run_results, d), logical(1))]
  for (d in setdiff(names(review$updates), names(kept_updates))) {
    existing_notes <- add_entry(existing_notes, existing_test_file$path, sprintf("- \"%s\" — an update was proposed (%s) but still failed, so the original test was kept.", d, review$explanations[[d]]))
  }

  # Rewrite from the ORIGINAL content with only what passed — a failing
  # candidate is never left in the proposed file. A freshly generated
  # DSLite setup is only kept alongside at least one passing new test.
  final <- rewrite_test_content(existing_test_file$content, blocks, kept_updates, review$deletes, test_blocks[passing_new])
  kept_path <- write_test_file(existing_test_file, final)
  if (!is.null(kept_path)) {
    updated_files <- c(updated_files, if (length(passing_new) > 0) created_setup, kept_path)
    counts <- counts + c(length(passing_new), length(kept_updates), length(review$deletes))
    if (length(passing_new) > 0 && !is.null(created_setup)) created_setups <- c(created_setups, created_setup)
    for (d in c(names(kept_updates), review$deletes)) {
      existing_changes <- add_entry(existing_changes, existing_test_file$path, sprintf("- \"%s\" — %s", d, review$explanations[[d]]))
    }
    message(sprintf("%s: %d new test(s), %d update(s), %d deletion(s).", function_name, length(passing_new), length(kept_updates), length(review$deletes)))
  }
  if (!is.null(created_setup) && (is.null(kept_path) || length(passing_new) == 0)) file.remove(created_setup)

  for (fail in failing_new) {
    block_text <- test_blocks[[fail$description]]
    classification <- tryCatch(
      ask_claude_to_classify_failure(fn_source(parsed), block_text, fail$message),
      error = function(e) {
        message(sprintf("Failure classification call failed for %s: %s", function_name, conditionMessage(e)))
        NULL
      }
    )
    if (is.null(classification)) next

    if (identical(classification$category, "real_bug")) {
      create_bug_issue(function_name, block_text, fail$message, classification)
    } else if (is_sweep) {
      sweep_failures <- add_entry(sweep_failures, existing_test_file$path, format_test_failure(function_name, block_text, fail$message, classification))
    } else {
      post_test_failure_comment(function_name, block_text, fail$message, classification)
    }
  }
}

# Proposed tests only count if R CMD check runs them: set up testthat in
# packages that don't have it yet.
testthat_setup <- if (counts[["new"]] > 0) ensure_testthat_setup(package_name) else character(0)
updated_files <- c(updated_files, testthat_setup)

writeLines(updated_files, "updated_files.txt")

# One-line summary: in the link comment on the originating PR (read by
# commit-updated-files from suggestion_summary.md) and on top of the
# suggestion PR's description.
summary_line <- format_test_summary(counts, created_setups, testthat_setup)
if (length(updated_files) > 0) writeLines(summary_line, "suggestion_summary.md")

if (length(existing_changes) + length(existing_notes) + length(sweep_failures) > 0 || length(updated_files) > 0) {
  report <- format_test_report(if (length(updated_files) > 0) summary_line, existing_changes, existing_notes, sweep_failures)
  publish_test_report(report, has_pr = length(updated_files) > 0)
}
