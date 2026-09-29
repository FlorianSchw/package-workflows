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
#   6. write the passing scripts, the main.R and dependencies.R blocks, the
#      report, and updated_files.txt for the suggestion PR.
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
ids <- vapply(plan$steps, function(s) s$id, character(1))

# --- 2. What to write --------------------------------------------------------------

existing <- find_bot_step_files("R")
notes <- character(0)
steps <- list()  # per step id: title, status, files, notes, error
to_write <- character(0)
for (s in plan$steps) {
  own <- existing[existing$step == s$id, ]
  hash <- step_plan_hash(plan, s)
  status <- if (nrow(own) == 0) "new"
    else if (any(own$edited)) "edited"
    else if (all(own$plan_hash == hash)) "unchanged"
    else "changed"
  steps[[s$id]] <- list(title = s$title, status = status, files = own$path, notes = list(), error = NULL, hash = hash)
  if (status %in% c("new", "changed")) to_write <- c(to_write, s$id)
  if (status == "edited" && !all(own$plan_hash == hash)) {
    steps[[s$id]]$error <- "its plan entry changed, but you have edited its script, so it was left as it is."
  }
}
for (gone in setdiff(unique(existing$step), ids)) {
  steps[[gone]] <- list(title = gone, status = "removed", files = existing$path[existing$step == gone], notes = list(),
    error = "no longer in the plan. Its script was kept; delete it (and its line in `main.R`) if you don't need it.")
}

if (length(to_write) == 0) {
  write_outputs(c("Nothing to do: every step of the plan already has an up-to-date script."), character(0))
  quit(save = "no")
}
message(sprintf("Steps to write: %s", paste(to_write, collapse = ", ")))

# --- 3. Packages -------------------------------------------------------------------

usable <- usable_server_packages(plan)
notes <- c(notes, usable$notes)
catalogue <- read_package_catalogue(if (is.null(plan$`package-catalogue`)) settings$package_catalogue else plan$`package-catalogue`)

servers <- character(0); clients <- character(0); tested <- character(0)
for (i in seq_len(nrow(usable$packages))) {
  p <- usable$packages$package[i]; v <- usable$packages$version[i]
  server <- install_ds_package(p, v, catalogue)
  notes <- c(notes, server$note)
  if (is.na(server$installed)) next
  servers <- c(servers, p)
  client_name <- client_package_name(p, catalogue)
  if (is.na(client_name)) next
  client <- install_ds_package(client_name, v, catalogue)
  notes <- c(notes, client$note)
  if (is.na(client$installed)) next
  clients <- c(clients, client_name)
  tested <- c(tested, sprintf("%s %s (server: %s %s)", client_name, client$installed, p, server$installed))
}
if (length(clients) == 0) stop("No client package could be installed for the studies' server packages; see the notes above.", call. = FALSE)
tested_with <- paste(tested, collapse = ", ")

# --- 4. Mock data, DSLite setup, login file -----------------------------------------

mock_paths <- write_mock_data(generate_mock_data(plan, settings$mock_data), file.path("utils", "mock_data", mock_folder))
login_files <- project_login_files()
setup_file <- update_dslite_setup(login_files$testing, dsanalysis_dir, mock_folder, servers)
if (is.null(setup_file)) stop(sprintf("The project needs the dsAnalysis DSLite setup (%s) for the test run.", login_files$testing), call. = FALSE)
login <- check_login_file(login_files$production, plan)
notes <- c(notes, login$notes)

# --- 5. Claude, checks and test run ---------------------------------------------------

reference <- client_function_reference(clients)
catalogue_prompt <- format_catalogue_for_prompt(catalogue, c(servers, clients))
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
  max_lines = settings$max_script_lines
)

# File numbers: a changed step keeps its number; new steps continue after
# the highest number in R/ (numbers from 90 up, like 99_DSLiteLearning.R,
# are left out), starting at 02.
taken <- as.integer(substr(list.files("R", pattern = "^[0-9]{2}[a-z]?_.*\\.R$"), 1, 2))
next_number <- max(c(1L, taken[taken < 90])) + 1L
numbers <- list()
for (id in to_write) {
  own <- existing$number[existing$step == id]
  numbers[[id]] <- if (length(own) > 0) own[1] else { n <- sprintf("%02d", next_number); next_number <- next_number + 1L; n }
}
context$numbers <- numbers
old_content <- lapply(setNames(existing$path[existing$step %in% to_write], existing$path[existing$step %in% to_write]), readLines, warn = FALSE)

answers <- list()   # step id -> Claude's step
candidate <- list() # step id -> paths written for the test run
place <- function(id) {
  unlink(c(candidate[[id]], existing$path[existing$step == id]))
  step <- plan$steps[[match(id, ids)]]
  built <- assemble_step_files(step, answers[[id]]$sections, numbers[[id]], steps[[id]]$hash, settings$max_script_lines, tested_with, plan_file, answers[[id]]$notes)
  for (f in built$files) writeLines(f$lines, f$path)
  candidate[[id]] <<- vapply(built$files, function(f) f$path, character(1))
  built$notes
}
evaluate <- function() {
  problems <- lapply(setNames(names(candidate), names(candidate)), function(id) {
    check_ds_calls(paste(vapply(answers[[id]]$sections, function(s) s$code, character(1)), collapse = "\n"), reference)
  })
  run <- run_analysis_scripts(login_files$testing, sort(c(kept_files, unlist(candidate))))
  if (!is.na(run$login_error)) stop(sprintf("The DSLite test setup (%s) failed: %s", login_files$testing, run$login_error), call. = FALSE)
  for (id in names(candidate)) {
    runtime <- run$errors[candidate[[id]]]
    runtime <- runtime[!is.na(runtime)]
    if (length(runtime) > 0) problems[[id]] <- c(problems[[id]], sprintf("Error when running %s: %s", names(runtime)[1], runtime[[1]]))
  }
  broken_kept <- run$errors[kept_files]
  list(problems = Filter(length, problems), broken_kept = broken_kept[!is.na(broken_kept)])
}
store <- function(result) {
  for (s in result) {
    answers[[s$step_id]] <<- s
    notes <<- c(notes, place(s$step_id))
  }
}

store(ask_claude_for_scripts(context, to_write))
outcome <- if (length(candidate) > 0) evaluate() else list(problems = list(), broken_kept = character(0))

if (length(outcome$problems) > 0) {
  failing <- names(outcome$problems)
  message(sprintf("Repair round for: %s", paste(failing, collapse = ", ")))
  previous <- paste(c(
    "", "## Your previous attempt failed for these steps", "",
    "Fix the problems and return these steps again, complete.", "",
    vapply(failing, function(id) sprintf(
      "### Step `%s`\n\nProblems:\n%s\n\nYour code:\n```r\n%s\n```",
      id, paste("-", outcome$problems[[id]], collapse = "\n"),
      paste(vapply(answers[[id]]$sections, function(s) s$code, character(1)), collapse = "\n\n")
    ), character(1))
  ), collapse = "\n")
  store(ask_claude_for_scripts(context, failing, previous))
  outcome <- if (length(candidate) > 0) evaluate() else list(problems = list(), broken_kept = character(0))
}

for (f in names(outcome$broken_kept)) {
  notes <- c(notes, sprintf("Your existing script `%s` failed in the test run: %s", f, outcome$broken_kept[[f]]))
}

# --- 6. Results ------------------------------------------------------------------------

for (id in to_write) {
  answer <- answers[[id]]
  steps[[id]]$notes <- if (is.null(answer)) list() else answer$notes
  if (is.null(answer)) {
    steps[[id]]$status <- "failed"; steps[[id]]$error <- "because Claude returned no code or notes for it. It is requested again on the next run."
  } else if (id %in% names(outcome$problems)) {
    steps[[id]]$status <- "failed"
    steps[[id]]$error <- paste("because the code still failed after a second attempt:", paste(outcome$problems[[id]], collapse = " "))
    unlink(candidate[[id]]); candidate[[id]] <- NULL
  } else {
    steps[[id]]$status <- if (length(answer$sections) == 0) "not_possible" else "written"
    steps[[id]]$files <- candidate[[id]]
  }
}
# A changed step whose new version failed keeps its old scripts.
for (path in names(old_content)) if (!file.exists(path) && !path %in% unlist(candidate)) {
  id <- existing$step[existing$path == path]
  if (!identical(steps[[id]]$status, "written")) writeLines(old_content[[path]], path)
}

written_files <- unlist(candidate)
updated <- character(0)
if (length(written_files) > 0) {
  replaced <- setdiff(names(old_content), written_files)
  replaced <- replaced[!file.exists(replaced)]
  bot_scripts <- sort(find_bot_step_files("R")$path)
  update_marked_block(file.path("R", "main.R"),
    "#### bot-suggest: scripts (updated by datashield-analysis-suggest)", "#### bot-suggest: scripts end",
    sprintf("source(here::here(\"R\", \"%s\"))", basename(bot_scripts)))

  # Packages "not yet on the servers": from this run's notes, plus those the
  # block already lists from earlier runs (their steps weren't requested
  # again), until the servers have them.
  deps_start <- "#### bot-suggest: packages (updated by datashield-analysis-suggest)"
  deps_end <- "#### bot-suggest: packages end"
  deps <- if (file.exists("dependencies.R")) readLines("dependencies.R", warn = FALSE) else character(0)
  block <- if (sum(deps == deps_start) == 1 && sum(deps == deps_end) == 1) deps[which(deps == deps_start):which(deps == deps_end)] else character(0)
  listed <- sub("^# library\\((.+)\\)$", "\\1", grep("^# library\\(.+\\)$", block, value = TRUE))
  other <- unique(unlist(lapply(steps, function(s) lapply(s$notes, function(n) if (identical(n$kind, "other_package") && nzchar(n$package)) n$package))))
  not_on_servers <- unlist(lapply(other, function(p) c(client_package_name(p, catalogue), p)))
  not_on_servers <- setdiff(unique(c(listed, not_on_servers[!is.na(not_on_servers)])), c(clients, servers))
  update_marked_block("dependencies.R", deps_start, deps_end, dependencies_block(clients, servers, not_on_servers))

  updated <- c(written_files, replaced, mock_paths$written, mock_paths$removed, setup_file, file.path("R", "main.R"), "dependencies.R")
}

report <- format_analysis_report(list(
  # Unchanged steps, and edited ones whose plan entry didn't change, need no mention.
  steps = Filter(function(s) !s$status %in% c("unchanged", "edited") || !is.null(s$error), steps),
  notes = notes, tested_with = tested_with, gap_issue_repo = settings$gap_issue_repo
))
write_outputs(report, updated)
