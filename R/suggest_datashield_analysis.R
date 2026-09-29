#!/usr/bin/env Rscript
# Drafts DataSHIELD analysis scripts from the analyst's plan file
# (config/analysis-plan.yml in a dsAnalysis project) and tests them before
# anything is proposed:
#   1. read and check the plan's core (studies, variables, steps);
#   2. decide per step: new, changed (untouched files, plan changed),
#      unchanged, or edited by the analyst (never overwritten);
#   3. install the studies' server packages and matching clients;
#   4. write mock data from the plan and point the project's DSLite setup
#      at it (dsAnalysis's own functions);
#   5. ask Claude for the steps, check every DataSHIELD call and column
#      against the installed clients and the plan, run all scripts in
#      testing mode; repair rounds for failing steps;
#   6. keep the passing scripts, write the main.R and dependencies.R
#      blocks, the report, and updated_files.txt for the suggestion PR.
# Settings: config/analysis-suggest.yml; wording: config/analysis-texts.yml
# (both overridable per project). Design: dev-notes/analysis-suggest.md.
# Logic lives in R/functions/shared/ and R/functions/analysis/, one
# function per file.

library(httr2)
library(jsonlite)
library(purrr)

functions_dir <- if (dir.exists("R/functions/analysis")) "R/functions" else ".shared-workflows/R/functions"
walk(list.files(file.path(functions_dir, c("shared", "analysis")), pattern = "\\.R$", full.names = TRUE), source)

# R_CONFIG_ACTIVE ("datashield-analysis") picks the profile in config/claude.yml.
anthropic_config <- config::get(file = resolve_shared_path("config/claude.yml"))$anthropic
# Project files at the same paths are merged over the shared defaults.
settings <- read_config_yaml("config/analysis-suggest.yml")
texts <- read_config_yaml("config/analysis-texts.yml")
analysis_prompt_template <- read_text_file("prompts/analysis-script-prompt.md")
repair_prompt_template <- read_text_file("prompts/analysis-repair-prompt.md")

api_key        <- Sys.getenv("ANTHROPIC_API_KEY")
plan_file      <- Sys.getenv("PLAN_FILE", "config/analysis-plan.yml")
dsanalysis_dir <- Sys.getenv("DSANALYSIS_DIR", ".dsanalysis")
summary_file   <- Sys.getenv("GITHUB_STEP_SUMMARY")
paths          <- settings$paths

write_outputs <- function(report, updated) {
  writeLines(updated, "updated_files.txt")
  if (length(report) > 0) {
    writeLines(report, "suggestion_report.md")
    if (nzchar(summary_file)) write(report, summary_file, append = TRUE)
    message(paste(report, collapse = "\n"))
  }
}

# --- 1. The plan -----------------------------------------------------------------

plan <- tryCatch(read_analysis_plan(plan_file, settings$variable_types), error = function(e) {
  msg <- conditionMessage(e)
  if (nzchar(summary_file)) write(c(texts$report$plan_errors_heading, "", "```", msg, "```"), summary_file, append = TRUE)
  stop(msg, call. = FALSE)
})
plan_text <- paste(readLines(plan_file, warn = FALSE), collapse = "\n")

# --- 2. What to write --------------------------------------------------------------

existing <- find_bot_step_files(paths$scripts)
classified <- classify_plan_steps(plan, existing, texts)
steps <- classified$steps
to_write <- classified$to_write
if (length(to_write) == 0) {
  write_outputs(texts$report$nothing_to_do, character(0))
  quit(save = "no")
}
message(sprintf("Steps to write: %s", paste(to_write, collapse = ", ")))

# --- 3. Packages -------------------------------------------------------------------

usable <- usable_server_packages(plan, texts)
catalogue <- read_package_catalogue(if (is.null(plan$`package-catalogue`)) settings$package_catalogue else plan$`package-catalogue`)
installed <- install_study_packages(usable$packages, catalogue, settings$client_suffix, texts)
notes <- c(usable$notes, installed$notes)
if (length(installed$clients) == 0) {
  stop("No client package could be installed for the studies' server packages; see the messages above.", call. = FALSE)
}

# --- 4. Mock data, DSLite setup, login file -----------------------------------------

mock_paths <- write_mock_data(generate_mock_data(plan, settings$mock_data), file.path("utils", "mock_data", settings$mock_data$folder))
login_files <- project_login_files(paths, settings$profiles)
setup_file <- update_dslite_setup(login_files$testing, dsanalysis_dir, settings$mock_data$folder, installed$servers, settings$markers$dslite_mock_data)
if (is.null(setup_file)) stop(sprintf("The project needs the dsAnalysis DSLite setup (%s) for the test run.", login_files$testing), call. = FALSE)
login <- check_login_file(login_files$production, plan, settings$credential_pattern, texts)
notes <- c(notes, login$notes)

# --- 5. Claude, checks and test run ---------------------------------------------------

reference <- client_function_reference(installed$clients, unlist(settings$excluded_functions))
plan_variables <- vapply(plan$variables, function(v) v$name, character(1))
catalogue_prompt <- format_catalogue_for_prompt(catalogue, c(installed$servers, installed$clients), settings$client_suffix)
kept_files <- sort(existing$path[!existing$step %in% to_write])
context <- list(
  connections = login$connections,
  symbol = plan$symbol,
  servers = vapply(plan$studies, function(s) s$server, character(1)),
  function_reference = reference$text,
  catalogue_text = catalogue_prompt$text,
  catalogue_names = catalogue_prompt$names,
  existing_steps = if (length(kept_files) == 0) "(none yet)" else paste(vapply(kept_files, function(f) {
    sprintf("File %s:\n```r\n%s\n```", f, paste(readLines(f, warn = FALSE), collapse = "\n"))
  }, character(1)), collapse = "\n\n"),
  plan_text = plan_text,
  max_lines = settings$max_script_lines,
  numbers = assign_step_numbers(to_write, existing, paths$scripts, settings$numbering)
)
header_values <- list(PLAN_FILE = plan_file, TESTED_WITH = installed$tested_with)

# Scripts of steps being rewritten, to restore them if the new version fails.
rewritten <- existing[existing$step %in% to_write, ]
old_content <- setNames(lapply(rewritten$path, readLines, warn = FALSE), rewritten$path)

answers <- list()    # step id -> Claude's step (sections, notes)
candidate <- list()  # step id -> paths of its new scripts
outcome <- list(problems = list(), broken_other = character(0))
requested <- to_write
previous <- ""
attempts <- 1 + settings$repair_rounds
for (round in seq_len(attempts)) {
  for (s in ask_claude_for_scripts(context, requested, previous)) {
    id <- s$step_id
    answers[[id]] <- s
    unlink(c(candidate[[id]], existing$path[existing$step == id]))
    plan_step <- Find(function(p) identical(p$id, id), plan$steps)
    built <- assemble_step_files(plan_step, s$sections, context$numbers[[id]], steps[[id]]$hash, paths$scripts,
      settings$max_script_lines, header_values, s$notes, texts)
    for (f in built$files) writeLines(f$lines, f$path)
    candidate[[id]] <- vapply(built$files, function(f) f$path, character(1))
    notes <- c(notes, built$notes)
  }
  if (length(candidate) == 0) break
  # Every other bot script runs too: kept steps, and requested steps that
  # have no new version (yet), so each step finds the objects it needs.
  others <- sort(existing$path[!existing$step %in% names(candidate)])
  outcome <- test_step_scripts(candidate, answers, reference, plan_variables, login_files$testing, others, settings, texts)
  if (length(outcome$problems) == 0 || round == attempts) break
  requested <- names(outcome$problems)
  message(sprintf("Repair round for: %s", paste(requested, collapse = ", ")))
  previous <- format_repair_request(outcome$problems, answers, repair_prompt_template)
}
for (f in names(outcome$broken_other)) {
  notes <- c(notes, fill_template(texts$notes$existing_failed, list(FILE = f, ERROR = outcome$broken_other[[f]])))
}

# --- 6. Results ------------------------------------------------------------------------

for (id in to_write) {
  answer <- answers[[id]]
  if (is.null(answer)) {
    steps[[id]]$status <- "failed"
    steps[[id]]$error <- texts$step$no_answer
  } else if (id %in% names(outcome$problems)) {
    steps[[id]]$status <- "failed"
    steps[[id]]$error <- fill_template(texts$step$still_failing, list(ATTEMPTS = attempts, PROBLEMS = paste(outcome$problems[[id]], collapse = " ")))
    unlink(candidate[[id]])
    candidate[[id]] <- NULL
  } else {
    steps[[id]]$status <- if (length(answer$sections) == 0) "not_possible" else "written"
    steps[[id]]$files <- candidate[[id]]
  }
  steps[[id]]$notes <- if (is.null(answer)) list() else answer$notes
  # A step that wasn't written keeps its previous scripts.
  if (steps[[id]]$status == "failed") {
    for (p in rewritten$path[rewritten$step == id]) writeLines(old_content[[p]], p)
  }
}

written_files <- unlist(candidate, use.names = FALSE)
updated <- character(0)
if (length(written_files) > 0) {
  replaced <- setdiff(rewritten$path[!file.exists(rewritten$path)], written_files)
  update_marked_block(paths$main, settings$markers$main_start, settings$markers$main_end,
    sprintf("source(here::here(\"%s\", \"%s\"))", paths$scripts, basename(sort(find_bot_step_files(paths$scripts)$path))))
  other_packages <- unique(unlist(lapply(steps, function(s) {
    lapply(s$notes, function(n) if (identical(n$kind, "other_package") && nzchar(n$package)) n$package)
  })))
  update_dependencies_file(paths$dependencies, installed$clients, installed$servers, other_packages, catalogue, settings, texts)
  updated <- c(written_files, replaced, mock_paths$written, mock_paths$removed, setup_file, paths$main, paths$dependencies)
}

report <- format_analysis_report(list(
  # Unchanged steps, and edited ones whose plan entry didn't change, need no mention.
  steps = Filter(function(s) !s$status %in% c("unchanged", "edited") || !is.null(s$error), steps),
  notes = unique(notes), tested_with = installed$tested_with, gap_issue_repo = settings$gap_issue_repo
), texts)
write_outputs(report, updated)
