# Reads the analyst's plan file (YAML) and checks its fixed core with
# validate_analysis_plan(). Stops with every problem at once, before any
# package install or Claude call, so the analyst can fix the file in one
# go. Fills in defaults: symbol "D" (as in the dsAnalysis login
# templates), a step id from the title where none is given, and each
# variable's `kind` (continuous / integer / categorical) from its type via
# `variable_types` (settings: type names -> kind).
read_analysis_plan <- function(path, variable_types) {
  if (!file.exists(path)) stop(sprintf("Analysis plan not found: %s", path), call. = FALSE)
  plan <- tryCatch(yaml::read_yaml(path), error = function(e) {
    stop(sprintf("%s is not valid YAML: %s", path, conditionMessage(e)), call. = FALSE)
  })
  if (!is.list(plan)) stop(sprintf("%s is empty or not a YAML mapping.", path), call. = FALSE)

  if (is.null(plan$symbol)) plan$symbol <- "D"
  plan$steps <- lapply(plan$steps, function(s) {
    if (is.list(s) && is.null(s$id) && is.character(s$title)) s$id <- step_id_from_title(s$title)
    s
  })
  plan$variables <- lapply(plan$variables, function(v) {
    if (is.list(v) && is.character(v$type) && !is.null(variable_types[[v$type]])) v$kind <- variable_types[[v$type]]
    v
  })

  problems <- validate_analysis_plan(plan, names(variable_types))
  if (length(problems) > 0) {
    stop(paste(c(sprintf("%s has %d problem(s):", path, length(problems)), paste("-", problems)), collapse = "\n"), call. = FALSE)
  }
  plan
}
