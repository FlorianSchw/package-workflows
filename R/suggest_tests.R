#!/usr/bin/env Rscript
# Reads files_to_check.txt (produced by the calling workflow), and for each
# function's (first) file: checks whether existing test coverage looks
# adequate, and if not, asks Claude to draft real, runnable test_that()
# blocks. Every candidate test is actually run before being trusted — a
# passing test gets appended to tests/testthat/test-<function>.R (never
# touching existing tests); a failing candidate is classified (bad_test /
# real_bug / env_misconfiguration) and surfaced for human judgment instead
# of being silently discarded or silently kept.
#
# Sibling to roxygen-suggest.yml's R/suggest_roxygen.R — same conventions:
# orchestration only here, logic in R/functions/, Claude call settings in
# config.yml, deterministic field-based assembly (Claude never writes final
# test_that() syntax directly).
#
# See test-coverage-workflow-design-notes.md for the full design reasoning,
# including which pieces are still explicitly marked as placeholders
# pending later work (per-function coverage data, in particular).

library(httr2)
library(jsonlite)
library(purrr)
# config package is used namespaced (config::get()) only — see
# R/suggest_roxygen.R for why library(config) is avoided.

functions_dir <- if (dir.exists("R/functions")) "R/functions" else ".shared-workflows/R/functions"
walk(list.files(functions_dir, pattern = "\\.R$", full.names = TRUE), source)

config_path <- load_config("config.yml", ".shared-workflows/config.yml")
# R_CONFIG_ACTIVE (set via .Renviron by the calling workflow) selects
# "test-review" as the default/active profile for this script; the failure
# classifier is a second, separate Claude-calling function (anticipated
# when config.yml was first designed with named profiles), so its config is
# fetched explicitly by name rather than relying on the active profile.
anthropic_config <- config::get(file = config_path)$anthropic
failure_classification_config <- config::get(config = "test-failure-classification", file = config_path)$anthropic

scan_mode   <- Sys.getenv("SCAN_MODE", "changed")
pr_number   <- Sys.getenv("PR_NUMBER")
pr_head_sha <- Sys.getenv("PR_HEAD_SHA")
repo        <- Sys.getenv("GITHUB_REPOSITORY")
api_key     <- Sys.getenv("ANTHROPIC_API_KEY")
gh_token    <- Sys.getenv("GH_TOKEN")
datashield  <- as.logical(Sys.getenv("DATASHIELD", "false"))
ds_type     <- Sys.getenv("DATASHIELD_TYPE", "")

test_review_prompt_template <- paste(
  readLines(
    load_config("prompts/test-review-prompt.md", ".shared-workflows/prompts/test-review-prompt.md"),
    warn = FALSE
  ),
  collapse = "\n"
)

# DSLite's built-in canned datasets need no server/credentials/per-package
# matching (unlike datashield-example-env.json, which is for the roxygen
# workflow's real-Opal-server usage examples — a different scenario
# entirely, deliberately not reused here after this was verified against a
# real DSLite run).
dslite_datasets <- NULL
if (isTRUE(datashield) && identical(ds_type, "client")) {
  dslite_path <- load_config("dslite-canned-datasets.json", ".shared-workflows/config/dslite-canned-datasets.json")
  if (file.exists(dslite_path)) dslite_datasets <- fromJSON(dslite_path, simplifyVector = FALSE)$datasets
}

package_name <- tryCatch({
  desc <- read.dcf("DESCRIPTION")
  as.character(desc[1, "Package"])
}, error = function(e) NA_character_)

files <- readLines("files_to_check.txt")
files <- files[nzchar(files)]

test_files_updated <- character(0)

# --- Main loop ---------------------------------------------------------------

for (f in files) {
  parsed <- tryCatch(parse_r_file(f), error = function(e) {
    message(sprintf("Skipping %s: %s", f, conditionMessage(e)))
    NULL
  })
  if (is.null(parsed)) next

  function_name <- extract_function_name(parsed)
  function_source <- fn_source(parsed)
  existing_test_file <- find_existing_test_file(function_name)

  if (has_adequate_coverage(function_name, existing_test_file)) {
    message(sprintf("%s: existing test coverage looks adequate, skipping.", function_name))
    next
  }

  has_existing_setup <- FALSE
  needs_dataset_choice <- FALSE
  if (isTRUE(datashield) && identical(ds_type, "client")) {
    has_existing_setup <- detect_dslite_setup()
    needs_dataset_choice <- !has_existing_setup
  }

  role_text <- build_test_role_guidance(
    datashield, ds_type, has_existing_setup,
    if (needs_dataset_choice) dslite_datasets else NULL
  )

  result <- tryCatch(
    ask_claude_for_tests(
      function_name, function_source, existing_test_file, role_text,
      if (needs_dataset_choice) dslite_datasets else NULL
    ),
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

  if (needs_dataset_choice && nzchar(result$dslite_dataset)) {
    dataset_choice <- Find(function(d) identical(d$name, result$dslite_dataset), dslite_datasets)
    if (is.null(dataset_choice)) {
      message(sprintf(
        "%s: Claude returned dslite_dataset '%s', which isn't one of the offered options — skipping DSLite setup.",
        function_name, result$dslite_dataset
      ))
    } else {
      setup_path <- ensure_dslite_setup_file(dataset_choice, package_name)
      if (!is.null(setup_path)) test_files_updated <- c(test_files_updated, setup_path)
    }
  }

  test_blocks <- tryCatch(assemble_test_block(result$tests, function_name), error = function(e) {
    message(sprintf("Failed to assemble test blocks for %s: %s", function_name, conditionMessage(e)))
    NULL
  })
  if (is.null(test_blocks)) next

  # Write ALL candidates first so testthat can actually run them.
  written_path <- write_test_blocks(existing_test_file, test_blocks)
  run_results <- run_test_blocks(written_path)

  passing <- Filter(function(r) isTRUE(r$passed), run_results)
  failing <- Filter(function(r) !isTRUE(r$passed), run_results)

  passing_names <- vapply(passing, function(r) r$description, character(1))
  passing_blocks <- test_blocks[names(test_blocks) %in% passing_names]

  # Rewrite from the ORIGINAL (pre-candidate) content + only passing blocks —
  # a failing candidate is never left in the committed file.
  if (length(passing_blocks) > 0) {
    write_test_blocks(existing_test_file, passing_blocks)
    test_files_updated <- c(test_files_updated, written_path)
    message(sprintf("%s: %d test(s) passed and were added.", function_name, length(passing_blocks)))
  } else if (existing_test_file$exists) {
    # No new passing tests — restore the file to its untouched original state.
    writeLines(existing_test_file$content, existing_test_file$path)
  } else if (file.exists(written_path)) {
    file.remove(written_path)
  }

  for (fail in failing) {
    block_text <- test_blocks[[fail$description]]
    classification <- tryCatch(
      ask_claude_to_classify_failure(function_source, block_text, fail$message),
      error = function(e) {
        message(sprintf("Failure classification call failed for %s: %s", function_name, conditionMessage(e)))
        NULL
      }
    )
    if (is.null(classification)) next

    if (identical(classification$category, "real_bug")) {
      create_bug_issue(function_name, block_text, fail$message, classification)
    } else {
      post_test_failure_comment(function_name, block_text, fail$message, classification)
    }
  }
}

writeLines(test_files_updated, "test_files_updated.txt")
