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
#   5. ask Claude for the steps, check every DataSHIELD call against the
#      installed clients, run all scripts in testing mode; one repair round
#      for failing steps;
#   6. keep the passing scripts, write the main.R and dependencies.R
#      blocks, the report, and updated_files.txt for the suggestion PR.
# Design: dev-notes/analysis-suggest.md. Logic lives in R/functions/shared/
# and R/functions/analysis/, one function per file.

library(httr2)
library(jsonlite)
library(purrr)

functions_dir <- if (dir.exists("R/functions/analysis")) "R/functions" else ".shared-workflows/R/functions"
walk(list.files(file.path(functions_dir, c("shared", "analysis")), pattern = "\\.R$", full.names = TRUE), source)

# R_CONFIG_ACTIVE ("datashield-analysis") picks the profile in config/claude.yml.
anthropic_config <- config::get(file = resolve_shared_path("config/claude.yml"))$anthropic
settings <- yaml::read_yaml(resolve_shared_path("config/analysis-suggest.yml"))
analysis_prompt_template <- read_text_file("prompts/analysis-script-prompt.md")

api_key        <- Sys.getenv("ANTHROPIC_API_KEY")
plan_file      <- Sys.getenv("PLAN_FILE", "config/analysis-plan.yml")
dsanalysis_dir <- Sys.getenv("DSANALYSIS_DIR", ".dsanalysis")
mock_folder    <- "bot-suggest"
summary_file   <- Sys.getenv("GITHUB_STEP_SUMMARY")

write_outputs <- function(report, updated) {
  writeLines(updated, "updated_files.txt")
  if (length(report) > 0) {
    writeLines(report, "suggestion_report.md")
    if (nzchar(summary_file)) write(report, summary_file, append = TRUE)
    message(paste(report, collapse = "\n"))
  }
}

# --- 1. The plan -----------------------------------------------------------------

plan <- tryCatch(read_analysis_plan(plan_file), error = function(e) {
  msg <- conditionMessage(e)
  if (nzchar(summary_file)) write(c("### The analysis plan needs fixing", "", "```", msg, "```"), summary_file, append = TRUE)
  stop(msg, call. = FALSE)
})
plan_text <- paste(readLines(plan_file, warn = FALSE), collapse = "\n")

# --- 2. What to write --------------------------------------------------------------

existing <- find_bot_step_files("R")
classified <- classify_plan_steps(plan, existing)
steps <- classified$steps
to_write <- classified$to_write
if (length(to_write) == 0) {
  write_outputs("Nothing to do: every step of the plan already has an up-to-date script.", character(0))
  quit(save = "no")
}
message(sprintf("Steps to write: %s", paste(to_write, collapse = ", ")))

# --- 3. Packages -------------------------------------------------------------------

usable <- usable_server_packages(plan)
catalogue <- read_package_catalogue(if (is.null(plan$`package-catalogue`)) settings$package_catalogue else plan$`package-catalogue`)
installed <- install_study_packages(usable$packages, catalogue)
notes <- c(usable$notes, installed$notes)
if (length(installed$clients) == 0) {
  stop("No client package could be installed for the studies' server packages; see the messages above.", call. = FALSE)
}

# --- 4. Mock data, DSLite setup, login file -----------------------------------------

mock_paths <- write_mock_data(generate_mock_data(plan, settings$mock_data), file.path("utils", "mock_data", mock_folder))
login_files <- project_login_files()
setup_file <- update_dslite_setup(login_files$testing, dsanalysis_dir, mock_folder, installed$servers)
if (is.null(setup_file)) stop(sprintf("The project needs the dsAnalysis DSLite setup (%s) for the test run.", login_files$testing), call. = FALSE)
login <- check_login_file(login_files$production, plan)
notes <- c(notes, login$notes)

# --- 5. Claude, checks and test run ---------------------------------------------------

reference <- client_function_reference(installed$clients)
plan_variables <- vapply(plan$variables, function(v) v$name, character(1))
catalogue_prompt <- format_catalogue_for_prompt(catalogue, c(installed$servers, installed$clients))
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
  numbers = assign_step_numbers(to_write, existing)
)

# Scripts of steps being rewritten, to restore them if the new version fails.
rewritten <- existing[existing$step %in% to_write, ]
old_content <- setNames(lapply(rewritten$path, readLines, warn = FALSE), rewritten$path)

answers <- list()    # step id -> Claude's step (sections, notes)
candidate <- list()  # step id -> paths of its new scripts
outcome <- list(problems = list(), broken_other = character(0))
requested <- to_write
previous <- ""
for (round in 1:2) {
  for (s in ask_claude_for_scripts(context, requested, previous)) {
    id <- s$step_id
    answers[[id]] <- s
    unlink(c(candidate[[id]], existing$path[existing$step == id]))
    plan_step <- Find(function(p) identical(p$id, id), plan$steps)
    built <- assemble_step_files(plan_step, s$sections, context$numbers[[id]], steps[[id]]$hash,
      settings$max_script_lines, installed$tested_with, plan_file, s$notes)
    for (f in built$files) writeLines(f$lines, f$path)
    candidate[[id]] <- vapply(built$files, function(f) f$path, character(1))
    notes <- c(notes, built$notes)
  }
  if (length(candidate) == 0) break
  # Every other bot script runs too: kept steps, and requested steps that
  # have no new version (yet), so each step finds the objects it needs.
  others <- sort(existing$path[!existing$step %in% names(candidate)])
  outcome <- test_step_scripts(candidate, answers, reference, plan_variables, login_files$testing, others)
  if (length(outcome$problems) == 0 || round == 2) break
  requested <- names(outcome$problems)
  message(sprintf("Repair round for: %s", paste(requested, collapse = ", ")))
  previous <- format_repair_request(outcome$problems, answers)
}
for (f in names(outcome$broken_other)) {
  notes <- c(notes, sprintf("Your existing script `%s` failed in the test run: %s", f, outcome$broken_other[[f]]))
}

# --- 6. Results ------------------------------------------------------------------------

for (id in to_write) {
  answer <- answers[[id]]
  if (is.null(answer)) {
    steps[[id]]$status <- "failed"
    steps[[id]]$error <- "because Claude returned no code or notes for it. It is requested again on the next run."
  } else if (id %in% names(outcome$problems)) {
    steps[[id]]$status <- "failed"
    steps[[id]]$error <- paste("because the code still failed after a second attempt:", paste(outcome$problems[[id]], collapse = " "))
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
  update_marked_block(file.path("R", "main.R"),
    "#### bot-suggest: scripts (updated by datashield-analysis-suggest)", "#### bot-suggest: scripts end",
    sprintf("source(here::here(\"R\", \"%s\"))", basename(sort(find_bot_step_files("R")$path))))
  other_packages <- unique(unlist(lapply(steps, function(s) {
    lapply(s$notes, function(n) if (identical(n$kind, "other_package") && nzchar(n$package)) n$package)
  })))
  update_dependencies_file("dependencies.R", installed$clients, installed$servers, other_packages, catalogue)
  updated <- c(written_files, replaced, mock_paths$written, mock_paths$removed, setup_file, file.path("R", "main.R"), "dependencies.R")
}

report <- format_analysis_report(list(
  # Unchanged steps, and edited ones whose plan entry didn't change, need no mention.
  steps = Filter(function(s) !s$status %in% c("unchanged", "edited") || !is.null(s$error), steps),
  notes = unique(notes), tested_with = installed$tested_with, gap_issue_repo = settings$gap_issue_repo
))
write_outputs(report, updated)
