#!/usr/bin/env Rscript
# Reads files_to_check.txt (produced by the calling workflow) and, for each
# function's (first) file, reviews its tests with Claude: new real,
# runnable test_that() blocks where they add value, and decisions on
# existing tests — update an outdated one, delete an obsolete one, or
# report one that points to a possible bug. Claude sees the existing
# tests' current results and the history evidence (build_test_evidence())
# to tell an outdated test from a bug.
#
# A function can have several test files (test-<function>.R, or
# test-<category>-<function>.R in repositories that sort tests by purpose,
# detect_test_scheme()); each change stays in its own file.
#
# Nothing is trusted unchecked: new tests pass filter_generated_tests(),
# decisions on existing tests pass review_existing_tests(), then every new
# and updated test is actually run. Each test file is rewritten from its
# original content with only what passed (plus deletions) and listed in
# updated_files.txt for the workflow to propose; a failing new test is
# classified (bad_test / real_bug / env_misconfiguration) and surfaced,
# a failing update keeps the original test and is reported.
#
# Sibling to R/suggest_roxygen.R — same conventions: orchestration only
# here, logic in R/functions/shared/ and R/functions/tests/, Claude call
# settings in config/claude.yml,
# deterministic field-based assembly (Claude never writes final test_that()
# syntax directly). See dev-notes/test-suggest.md and
# dev-notes/suggestion-thresholds.md for the design reasoning.

library(httr2)
library(jsonlite)
library(purrr)
# config package is used namespaced (config::get()) only — see
# R/suggest_roxygen.R for why library(config) is avoided.

functions_dir <- if (dir.exists("R/functions")) "R/functions" else ".shared-workflows/R/functions"
walk(list.files(file.path(functions_dir, c("shared", "tests")), pattern = "\\.R$", full.names = TRUE), source)

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
base_rev   <- Sys.getenv("BASE_REV")  # state before this run's changes; empty in a sweep
is_sweep   <- !nzchar(pr_number)  # no PR to comment on (a sweep, or a push without a PR)
# PR and push runs (empty in a sweep): the reviewed commit and the bot
# branch whose open PR is built on.
reviewed_sha <- substr(Sys.getenv("REVIEWED_SHA"), 1, 7)
sub_branch   <- Sys.getenv("SUB_BRANCH")
builds_on_open_pr <- nzchar(sub_branch) && identical(Sys.getenv("OPEN_SUGGESTION_PR", "add"), "add") && !identical(Sys.getenv("REBUILD"), "true")
datashield <- as.logical(Sys.getenv("DATASHIELD", "false"))
ds_type    <- Sys.getenv("DATASHIELD_TYPE", "")
check_datashield_type(datashield, ds_type)
# Client packages always test against DSLite; utility packages only for
# functions that use DataSHIELD connections (decided per function below).
may_use_dslite <- isTRUE(datashield) && ds_type %in% c("client", "utility")
# Whether a function needing connections gets a fresh DSLite setup
# (decide_dslite_setup()).
dslite_setup_mode <- Sys.getenv("DSLITE_SETUP", "auto")
check_dslite_setup_mode(dslite_setup_mode)

test_review_prompt_template           <- read_text_file("prompts/test-review-prompt.md")
failure_classification_prompt_template <- read_text_file("prompts/test-failure-classification-prompt.md")
test_role_guidance                    <- read_json_config("config/test-role-guidance.json", required = TRUE)
category_meanings                     <- read_json_config("config/test-categories.json")$categories
package_name                          <- read_package_name()

# DSLite's built-in canned datasets need no server/credentials/per-package
# matching — unlike datashield-example-env.json, which describes the real
# Opal demo server for roxygen's usage examples, a different scenario.
dslite_datasets <- if (may_use_dslite) read_json_config("config/dslite-canned-datasets.json")$datasets else NULL


files <- readLines("files_to_check.txt")
files <- files[nzchar(files)]

# With an open bot PR to build on, its findings and the test files it
# proposes are the starting point: they are put in place before anything
# runs, so its tests count as existing, and its report is merged with this
# run's findings instead of growing an update per run (see
# dev-notes/test-suggest.md).
pr_body <- if (builds_on_open_pr) fetch_suggestion_pr_body(sub_branch) else NULL
state <- decode_suggestion_state(pr_body)
bot_ref <- if (!is.null(pr_body)) fetch_bot_branch(sub_branch) else NULL
bot_tests <- materialize_bot_tests(bot_ref, base_rev)
stats <- c(new = 0L, crossed = 0L, repeats = 0L)
merge_run <- function(fn, run) {
  merged <- merge_test_findings(state, fn, run, reviewed_sha)
  state <<- merged$state
  stats <<- stats + merged$stats
}

# How the repository names its test files (test-<function>.R or
# test-<category>-<function>.R) — once per run.
scheme <- detect_test_scheme(package_function_names())
if (scheme$categorised) message("Test files are named by category: ", paste(scheme$categories, collapse = ", "))

# Structure of the test data the package's setup/helper files create —
# once per run, in a separate R process.
test_data <- summarize_test_data(test_support_files(), file.path(functions_dir, "tests"))
message("Test data:\n", test_data)

run_quietly <- function(path, what) {
  tryCatch(run_test_blocks(path, package_name), error = function(e) {
    message(sprintf("Running %s failed: %s", what, conditionMessage(e)))
    list()
  })
}

# --- Main loop ---------------------------------------------------------------

updated_files <- character(0)
new_total <- 0  # new tests kept in this run, for ensure_testthat_setup()

for (f in files) {
  parsed <- tryCatch(parse_r_file(f), error = function(e) {
    message(sprintf("Skipping %s: %s", f, conditionMessage(e)))
    NULL
  })
  if (is.null(parsed)) next
  function_name <- parsed$fn_name
  run <- list(user_edited = bot_tests$user_edited, new = list(), changes = list(), notes = list(), failed = list(), repeats = 0L)

  # Re-checked per function: a DSLite setup generated for an earlier function
  # in this run is reused by later ones.
  uses_connections <- uses_ds_connections(parsed)
  needs_dslite <- may_use_dslite && (identical(ds_type, "client") || uses_connections)
  setup_plan <- if (needs_dslite) decide_dslite_setup(dslite_setup_mode, detect_connection_approaches()) else "not_needed"
  if (identical(setup_plan, "none")) {
    message(sprintf("%s: needs DataSHIELD connections, but the tests have none and dslite-setup is 'never' — not tested.", function_name))
    merge_run(function_name, c(run, list(untested = f)))
    next
  }

  test_files <- find_test_files(function_name, scheme)
  paths <- vapply(test_files, function(t) t$path, character(1))
  names(test_files) <- paths
  blocks <- lapply(test_files, function(t) parse_test_file(t$content))
  baseline <- lapply(test_files, function(t) run_quietly(t$path, sprintf("existing tests in %s", t$path)))
  run$current <- unlist(lapply(paths, function(p) lapply(baseline[[p]], function(r) list(file = p, description = r$description, passed = isTRUE(r$passed)))), recursive = FALSE)
  earlier <- Filter(function(e) identical(e$fn, function_name) && identical(e$status, "active") && e$kind %in% c("note", "failed"), state$entries)

  offered_datasets <- if (identical(setup_plan, "create")) dslite_datasets else NULL
  support_files <- test_support_files()
  context <- list(
    role_text = build_test_role_guidance(datashield, ds_type, identical(setup_plan, "reuse"), offered_datasets, test_role_guidance, uses_connections),
    scheme_text = format_test_scheme_guidance(scheme, category_meanings, function_name, test_files),
    categories = if (scheme$categorised) scheme$categories,
    test_files = test_files,
    examples = if (length(test_files) == 0) example_test_files(scheme) else list(),
    support_files = c(support_files, test_sourced_files(support_files)),
    test_data = test_data,
    test_results = format_test_results(baseline),
    evidence = build_test_evidence(f, paths, base_rev),
    dslite_datasets = offered_datasets,
    max_new_tests = max_new_tests,
    earlier = earlier
  )

  result <- tryCatch(ask_claude_for_tests(parsed, context), error = function(e) {
    message(sprintf("Claude call failed for %s: %s", function_name, conditionMessage(e)))
    NULL
  })
  if (is.null(result)) {
    merge_run(function_name, run)
    next
  }
  run$decisions <- result$earlier_findings

  # Decisions on existing tests, per test file. With a single test file, a
  # decision naming no (or another) file belongs to it.
  decision_file <- function(d) {
    name <- if (is.null(d$test_file)) "" else d$test_file
    hit <- paths[basename(paths) == name]
    if (length(hit) == 1) hit else if (length(paths) == 1) paths else NA_character_
  }
  decision_paths <- vapply(result$existing_tests, decision_file, character(1))
  for (d in result$existing_tests[is.na(decision_paths)]) {
    message(sprintf("%s: ignoring decision on '%s' — unknown test file '%s'.", function_name, d$description, d$test_file))
  }
  reviews <- list()
  for (path in paths) {
    review <- review_existing_tests(result$existing_tests[decision_paths %in% path], blocks[[path]], baseline[[path]], function_name)
    run$notes <- c(run$notes, lapply(review$notes, function(n) c(n, list(file = path))))
    # A failing existing test Claude left without any decision is reported too.
    decided <- vapply(result$existing_tests[decision_paths %in% path], function(d) d$description, character(1))
    for (r in Filter(function(r) !isTRUE(r$passed) && !r$description %in% decided, baseline[[path]])) {
      run$notes[[length(run$notes) + 1]] <- list(file = path, description = r$description, text = sprintf("fails, no change proposed. %s", gsub("\\s+", " ", r$message)))
    }
    reviews[[path]] <- review
  }

  # New tests, each into its file: test-<function>.R, or
  # test-<category>-<function>.R in a categorised repository.
  all_content <- paste(vapply(test_files, function(t) t$content, character(1)), collapse = "\n")
  all_descriptions <- unlist(lapply(blocks, function(b) vapply(b, function(x) x$description, character(1))))
  new_tests <- if (isTRUE(result$needs_tests)) {
    filter_generated_tests(result$tests, all_content, accept_reasons, function_name, all_descriptions)
  } else {
    list()
  }
  target_of <- function(t) {
    if (!scheme$categorised) return(test_file_path(function_name))
    if (!isTRUE(t$category %in% scheme$categories)) {
      message(sprintf("%s: dropping test '%s' — unknown category '%s'.", function_name, t$description, t$category))
      return(NA_character_)
    }
    test_file_path(function_name, t$category)
  }
  targets <- vapply(new_tests, target_of, character(1))
  new_by_file <- list()
  for (path in unique(targets[!is.na(targets)])) {
    blocks_for_file <- tryCatch(assemble_test_block(new_tests[targets %in% path], function_name), error = function(e) {
      message(sprintf("Failed to assemble test blocks for %s: %s", function_name, conditionMessage(e)))
      character(0)
    })
    if (length(blocks_for_file) > 0) new_by_file[[path]] <- blocks_for_file
  }
  new_test_of <- function(description) Find(function(t) identical(t$description, description), new_tests)

  changed_paths <- unique(c(
    names(new_by_file),
    Filter(function(p) length(reviews[[p]]$updates) + length(reviews[[p]]$deletes) > 0, paths)
  ))
  if (length(changed_paths) == 0) {
    message(sprintf("%s: nothing to change.", function_name))
    merge_run(function_name, run)
    next
  }

  created_setup <- NULL
  if (length(new_by_file) > 0 && !is.null(offered_datasets) && isTRUE(nzchar(result$dslite_dataset))) {
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

  # Per test file: run all candidates, keep only what passed
  # (apply_test_file_changes()).
  kept_new_total <- 0
  for (path in changed_paths) {
    test_file <- if (path %in% paths) test_files[[path]] else read_test_file(path, if (scheme$categorised) new_tests[targets %in% path][[1]]$category else NA_character_)
    review <- if (path %in% paths) reviews[[path]] else list(updates = character(0), deletes = character(0), explanations = character(0))
    test_blocks <- if (is.null(new_by_file[[path]])) character(0) else new_by_file[[path]]
    applied <- apply_test_file_changes(test_file, if (path %in% paths) blocks[[path]] else list(), review$updates, review$deletes, test_blocks, result, function_name, package_name)

    for (d in applied$failed_updates) {
      run$notes[[length(run$notes) + 1]] <- list(file = path, description = d, text = sprintf("an update was proposed (%s) but still failed, so the original test was kept.", review$explanations[[d]]))
    }
    if (!is.null(applied$path)) {
      updated_files <- c(updated_files, applied$path)
      kept_new_total <- kept_new_total + length(applied$passing_new)
      for (d in applied$passing_new) {
        t <- new_test_of(d)
        run$new[[length(run$new) + 1]] <- list(file = path, description = d, reason = t$reason, repeats_earlier = t$repeats_earlier)
      }
      for (d in names(applied$kept_updates)) {
        run$changes[[length(run$changes) + 1]] <- list(file = path, description = d, action = "updated", reason = "contract_changed", explanation = review$explanations[[d]])
      }
      for (d in review$deletes) {
        run$changes[[length(run$changes) + 1]] <- list(file = path, description = d, action = "deleted", reason = "", explanation = review$explanations[[d]])
      }
      message(sprintf("%s: %d new test(s), %d update(s), %d deletion(s) in %s.", function_name, length(applied$passing_new), length(applied$kept_updates), length(review$deletes), path))
    }

    for (fail in applied$failing_new) {
      # A test that failed before (same name, or one Claude says it
      # repeats) isn't classified, commented or filed again.
      t <- new_test_of(fail$description)
      repeated_id <- if (!is.null(t$repeats_earlier) && nzchar(t$repeats_earlier)) suppressWarnings(as.integer(sub("^E", "", t$repeats_earlier))) else NA_integer_
      if (any(vapply(earlier, function(e) identical(e$kind, "failed") && (identical(as.integer(e$id), repeated_id) || identical(e$description, fail$description)), logical(1)))) {
        message(sprintf("%s: '%s' failed again — reported before.", function_name, fail$description))
        run$repeats <- run$repeats + 1L
        next
      }
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
      } else if (!is_sweep) {
        post_test_failure_comment(function_name, block_text, fail$message, classification)
      }
      in_report <- is_sweep && !identical(classification$category, "real_bug")
      run$failed[[length(run$failed) + 1]] <- list(
        file = path, description = fail$description, classification = classification$category, in_report = in_report,
        explanation = if (in_report) format_test_failure(function_name, block_text, fail$message, classification) else classification$explanation
      )
    }
  }

  # A freshly generated DSLite setup is only kept alongside at least one
  # passing new test.
  if (!is.null(created_setup)) {
    if (kept_new_total > 0) {
      updated_files <- c(updated_files, created_setup)
      run$setups <- created_setup
    } else {
      file.remove(created_setup)
    }
  }
  new_total <- new_total + kept_new_total
  merge_run(function_name, run)
}

# Proposed tests only count if R CMD check runs them: set up testthat in
# packages that don't have it yet.
testthat_setup <- if (new_total > 0) ensure_testthat_setup(package_name) else character(0)
updated_files <- c(updated_files, testthat_setup)
if (length(testthat_setup) > 0) merge_run("", list(setups = testthat_setup))

writeLines(updated_files, "updated_files.txt")
restore_unproposed_files(bot_tests$materialized, updated_files)

# One-line summary of the open findings: in the link comment on the
# originating PR (read by commit-updated-files from suggestion_summary.md)
# and on top of the suggestion PR's description, which is rebuilt from all
# findings on every run (pr-body-mode "replace"). Written when this run
# changes files or a bot PR is open; without one, notes and sweep failures
# still get published (publish_test_report()). Functions left untested
# (dslite-setup: never) are listed when there is a report anyway, but
# don't make one on their own: the repository chose that, and a comment
# or issue on every run would be noise.
has_pr <- length(updated_files) > 0 || !is.null(pr_body)
open_kinds <- vapply(Filter(function(e) identical(e$status, "active"), state$entries), function(e) e$kind, character(1))
if (length(updated_files) > 0) writeLines(format_test_summary(state), "suggestion_summary.md")
if (has_pr || any(open_kinds == "note") || any(vapply(state$entries, function(e) isTRUE(e$in_report), logical(1)))) {
  report <- format_test_report(state, list(sha = reviewed_sha, stats = stats), state$legacy)
  publish_test_report(report, has_pr = has_pr)
}
