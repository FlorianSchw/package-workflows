# Checks the fixed core of an analysis plan and returns the problems found
# (character(0) if none), worded by `texts$plan`. Only what the workflow
# itself relies on is checked: the symbol, the studies with their server
# packages (mock data, installs) and the variables (mock data). Steps only
# need a title and a unique id; everything else in a step is free and goes
# to Claude as written. Unknown top-level entries are allowed. `types` are
# the variable types the settings allow; read_analysis_plan() has already
# set each known type's `kind`.
validate_analysis_plan <- function(plan, types, texts) {
  problems <- character(0)
  add <- function(key, ...) problems <<- c(problems, fill_template(texts$plan[[key]], list(...)))
  label <- function(key, name, section, index) {
    if (is.character(name)) fill_template(texts$plan[[key]], list(NAME = name))
    else fill_template(texts$plan$label_entry, list(SECTION = section, INDEX = index))
  }
  is_name <- function(x) is.character(x) && length(x) == 1 && identical(make.names(x), x)
  duplicated_of <- function(x) paste(unique(x[duplicated(x)]), collapse = ", ")

  if (!is_name(plan$symbol)) add("symbol")

  studies <- plan$studies
  if (!is.list(studies) || length(studies) == 0) {
    add("no_studies")
  } else {
    for (i in seq_along(studies)) {
      s <- studies[[i]]
      l <- label("label_study", s$server, "studies", i)
      if (!is_name(s$server)) add("server_name", LABEL = l)
      pkgs <- s$packages
      if (!is.list(pkgs) || length(pkgs) == 0 || is.null(names(pkgs)) || any(!nzchar(names(pkgs)))) {
        add("packages", LABEL = l)
      } else {
        bad <- names(pkgs)[!vapply(pkgs, function(v) (is.character(v) || is.numeric(v)) && length(v) == 1, logical(1))]
        if (length(bad) > 0) add("one_version", LABEL = l, PACKAGES = paste(bad, collapse = ", "))
      }
    }
    servers <- unlist(lapply(studies, function(s) if (is.character(s$server)) s$server))
    if (anyDuplicated(servers)) add("duplicate_servers", NAMES = duplicated_of(servers))
  }

  variables <- plan$variables
  if (!is.list(variables) || length(variables) == 0) {
    add("no_variables")
  } else {
    for (i in seq_along(variables)) {
      v <- variables[[i]]
      l <- label("label_variable", v$name, "variables", i)
      if (!is_name(v$name)) add("variable_name", LABEL = l)
      if (is.null(v$kind)) {
        add("variable_type", LABEL = l, TYPES = paste(types, collapse = ", "))
      } else if (v$kind == "categorical") {
        if (length(v$categories) < 2) add("categories", LABEL = l)
      } else {
        r <- suppressWarnings(as.numeric(unlist(v$range)))
        if (length(r) != 2 || anyNA(r) || r[1] >= r[2]) add("range", LABEL = l)
      }
    }
    names_seen <- unlist(lapply(variables, function(v) if (is.character(v$name)) v$name))
    if (anyDuplicated(names_seen)) add("duplicate_variables", NAMES = duplicated_of(names_seen))
  }

  steps <- plan$steps
  if (!is.list(steps) || length(steps) == 0) {
    add("no_steps")
  } else {
    for (i in seq_along(steps)) {
      s <- steps[[i]]
      if (!is.list(s) || !is.character(s$title) || !nzchar(s$title)) {
        add("step_title", LABEL = label("", NULL, "steps", i))
      } else if (!is.character(s$id) || !grepl("^[A-Za-z0-9_-]+$", s$id)) {
        add("step_id", TITLE = s$title)
      }
    }
    ids <- unlist(lapply(steps, function(s) if (is.list(s) && is.character(s$id)) s$id))
    if (anyDuplicated(ids)) add("duplicate_steps", NAMES = duplicated_of(ids))
  }

  problems
}
