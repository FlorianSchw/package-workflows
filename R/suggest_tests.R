#!/usr/bin/env Rscript
# Reads files_to_check.txt (produced by the calling workflow), and for each
# function's (first) file: checks whether existing test coverage looks
# adequate, and if not, asks Claude to draft real, runnable test_that()
# blocks. Every candidate test is actually run before being trusted — a
# passing test gets appended to tests/testthat/test-<function>.R (never
# touching existing tests) and listed in updated_files.txt for the workflow
# to commit; a failing candidate is classified (bad_test / real_bug /
# env_misconfiguration) and surfaced for human judgment instead of being
# silently discarded or silently kept.
#
# Sibling to R/suggest_roxygen.R — same conventions: orchestration only
# here, logic in R/functions/, Claude call settings in config/claude.yml,
# deterministic field-based assembly (Claude never writes final test_that()
# syntax directly). See dev-notes/test-coverage-suggest.md for the
# design reasoning, including which pieces are still placeholders
# (per-function coverage data, in particular).

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
anthropic_config <- config::get(file = config_path)$anthropic
failure_classification_config <- config::get(config = "test-failure-classification", file = config_path)$anthropic

api_key    <- Sys.getenv("ANTHROPIC_API_KEY")
gh_token   <- Sys.getenv("GH_TOKEN")
repo       <- Sys.getenv("GITHUB_REPOSITORY")
pr_number  <- Sys.getenv("PR_NUMBER")
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

# --- Main loop ---------------------------------------------------------------

updated_files <- character(0)
sweep_failures <- character(0)

for (f in files) {
  parsed <- tryCatch(parse_r_file(f), error = function(e) {
    message(sprintf("Skipping %s: %s", f, conditionMessage(e)))
    NULL
  })
  if (is.null(parsed)) next

  function_name <- parsed$fn_name
  existing_test_file <- find_existing_test_file(function_name)

  if (has_adequate_coverage(function_name, existing_test_file)) {
    message(sprintf("%s: existing test coverage looks adequate, skipping.", function_name))
    next
  }

  # Re-checked per function: a setup.R generated for an earlier function
  # in this run is reused by later ones.
  has_existing_setup <- is_client && detect_dslite_setup()
  offered_datasets <- if (is_client && !has_existing_setup) dslite_datasets else NULL
  role_text <- build_test_role_guidance(datashield, ds_type, has_existing_setup, offered_datasets, test_role_guidance)

  result <- tryCatch(
    ask_claude_for_tests(parsed, existing_test_file, role_text, offered_datasets),
    error = function(e) {
      message(sprintf("Claude call failed for %s: %s", function_name, conditionMessage(e)))
      NULL
    }
  )
  if (is.null(result)) next

  if (!isTRUE(result$needs_tests) || length(result$tests) == 0) {
    message(sprintf("%s: Claude judged existing coverage already adequate, skipping.", function_name))
    next
  }

  test_blocks <- tryCatch(assemble_test_block(result$tests, function_name), error = function(e) {
    message(sprintf("Failed to assemble test blocks for %s: %s", function_name, conditionMessage(e)))
    NULL
  })
  if (is.null(test_blocks)) next

  created_setup <- NULL
  if (!is.null(offered_datasets) && isTRUE(nzchar(result$dslite_dataset))) {
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

  # Write ALL candidates first so testthat can actually run them.
  written_path <- write_test_blocks(existing_test_file, test_blocks)
  run_results <- tryCatch(run_test_blocks(written_path, package_name), error = function(e) {
    message(sprintf("Running generated tests failed for %s: %s", function_name, conditionMessage(e)))
    NULL
  })

  # Only generated blocks count — the file also contains any pre-existing
  # tests, whose failures are not this workflow's to classify.
  generated <- Filter(function(r) r$description %in% names(test_blocks), run_results)
  passing_names <- vapply(Filter(function(r) isTRUE(r$passed), generated), function(r) r$description, character(1))
  failing <- Filter(function(r) !isTRUE(r$passed), generated)

  # Rewrite from the ORIGINAL content + only passing blocks — a failing
  # candidate is never left in the committed file. A freshly generated
  # setup.R is only kept alongside at least one passing test.
  kept_path <- write_test_blocks(existing_test_file, test_blocks[names(test_blocks) %in% passing_names])
  if (!is.null(kept_path)) {
    updated_files <- c(updated_files, created_setup, kept_path)
    message(sprintf("%s: %d test(s) passed and were added.", function_name, length(passing_names)))
  } else if (!is.null(created_setup)) {
    file.remove(created_setup)
  }

  for (fail in failing) {
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
      sweep_failures <- c(sweep_failures, format_test_failure(function_name, block_text, fail$message, classification))
    } else {
      post_test_failure_comment(function_name, block_text, fail$message, classification)
    }
  }
}

writeLines(updated_files, "updated_files.txt")

if (length(sweep_failures) > 0) {
  report_sweep_failures(sweep_failures, has_sweep_pr = length(updated_files) > 0)
}
