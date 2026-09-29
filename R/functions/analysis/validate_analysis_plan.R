# Checks the fixed core of an analysis plan and returns the problems found
# (character(0) if none). Only what the workflow itself relies on is
# checked: the symbol, the studies with their server packages (mock data,
# installs) and the variables (mock data). Steps only need a title and a
# unique id; everything else in a step is free and goes to Claude as
# written. Unknown top-level entries are allowed. `types` are the
# variable types the settings allow; read_analysis_plan() has already set
# each known type's `kind`.
validate_analysis_plan <- function(plan, types) {
  problems <- character(0)
  add <- function(...) problems <<- c(problems, sprintf(...))
  is_name <- function(x) is.character(x) && length(x) == 1 && identical(make.names(x), x)

  if (!is_name(plan$symbol)) add("symbol must be a plain R name, e.g. D.")

  studies <- plan$studies
  if (!is.list(studies) || length(studies) == 0) {
    add("studies: list at least one study, each with a server name and its packages.")
  } else {
    servers <- vapply(studies, function(s) if (is.character(s$server)) s$server else NA_character_, character(1))
    for (i in seq_along(studies)) {
      s <- studies[[i]]
      label <- if (is.na(servers[i])) sprintf("studies[%d]", i) else sprintf("study %s", servers[i])
      if (!is_name(s$server)) add("%s: server must be a plain R name (letters, digits, . and _), as in 01_DS_Login.R.", label)
      pkgs <- s$packages
      if (!is.list(pkgs) || length(pkgs) == 0 || is.null(names(pkgs)) || any(!nzchar(names(pkgs)))) {
        add("%s: packages must list the installed server packages with their versions, e.g. {dsBase: \"6.3.2\"}.", label)
      } else {
        bad <- names(pkgs)[!vapply(pkgs, function(v) (is.character(v) || is.numeric(v)) && length(v) == 1, logical(1))]
        if (length(bad) > 0) add("%s: give one version per package (%s).", label, paste(bad, collapse = ", "))
      }
    }
    dup <- unique(servers[duplicated(servers) & !is.na(servers)])
    if (length(dup) > 0) add("studies: server names must be unique (%s).", paste(dup, collapse = ", "))
  }

  variables <- plan$variables
  if (!is.list(variables) || length(variables) == 0) {
    add("variables: list the variables the analysis uses, with name, type and categories or range.")
  } else {
    names_seen <- character(0)
    for (i in seq_along(variables)) {
      v <- variables[[i]]
      label <- if (is.character(v$name)) sprintf("variable %s", v$name) else sprintf("variables[%d]", i)
      if (!is_name(v$name)) add("%s: name must be the variable name as in the data.", label)
      names_seen <- c(names_seen, if (is.character(v$name)) v$name)
      if (is.null(v$kind)) {
        add("%s: type must be one of %s.", label, paste(types, collapse = ", "))
      } else if (v$kind == "categorical") {
        if (length(v$categories) < 2) add("%s: categorical variables need at least two categories.", label)
      } else {
        r <- suppressWarnings(as.numeric(unlist(v$range)))
        if (length(r) != 2 || anyNA(r) || r[1] >= r[2]) add("%s: range must be [min, max] with min < max.", label)
      }
    }
    dup <- unique(names_seen[duplicated(names_seen)])
    if (length(dup) > 0) add("variables: names must be unique (%s).", paste(dup, collapse = ", "))
  }

  steps <- plan$steps
  if (!is.list(steps) || length(steps) == 0) {
    add("steps: list at least one step with a title.")
  } else {
    ids <- character(0)
    for (i in seq_along(steps)) {
      s <- steps[[i]]
      if (!is.list(s) || !is.character(s$title) || !nzchar(s$title)) {
        add("steps[%d]: every step needs a title.", i)
        next
      }
      if (!is.character(s$id) || !grepl("^[A-Za-z0-9_-]+$", s$id)) {
        add("step '%s': id may only contain letters, digits, _ and -.", s$title)
      }
      ids <- c(ids, if (is.character(s$id)) s$id)
    }
    dup <- unique(ids[duplicated(ids)])
    if (length(dup) > 0) add("steps: ids must be unique (%s); give steps with the same title an explicit id.", paste(dup, collapse = ", "))
  }

  problems
}
