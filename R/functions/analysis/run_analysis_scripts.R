# Runs the project's scripts the way main.R does in testing mode: the
# DSLite setup first (mock data), then `scripts` in order, all in one
# fresh R session. Returns list(login_error, errors): errors is a named
# character vector, one entry per script, NA when it ran through.
#
# The session starts without the project's .Rprofile (a dsAnalysis
# project activates renv there, which would hide the packages installed
# for this run), and without the API and GitHub tokens: the scripts are
# generated code.
run_analysis_scripts <- function(login_file, scripts, timeout = 1800) {
  child <- function(login_file, scripts) {
    Sys.setenv(R_CONFIG_ACTIVE = "testing")
    run <- function(path) tryCatch({
      source(path, local = globalenv(), echo = FALSE)
      NA_character_
    }, error = function(e) conditionMessage(e))
    login_error <- run(login_file)
    if (!is.na(login_error)) return(list(login_error = login_error, errors = character(0)))
    errors <- vapply(scripts, run, character(1))
    list(login_error = NA_character_, errors = errors)
  }
  env <- callr::rcmd_safe_env()
  env[c("ANTHROPIC_API_KEY", "GH_TOKEN", "GITHUB_TOKEN")] <- ""
  tryCatch(
    callr::r(child, args = list(login_file = login_file, scripts = scripts), user_profile = FALSE, env = env, timeout = timeout),
    error = function(e) list(login_error = sprintf("The test run failed: %s", conditionMessage(e)), errors = character(0))
  )
}
