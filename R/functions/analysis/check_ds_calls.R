# Checks generated R code before it runs: it must parse, every ds.*() and
# datashield.*() function it calls must exist in the installed client
# packages (`reference$functions` from client_function_reference()), and
# every named argument must be one of that function's arguments (unless it
# takes `...`). Returns the problems found (character(0) if none), worded
# for Claude's repair round and the report. Other functions (base R,
# stats, ...) aren't checked here; the test run catches those.
check_ds_calls <- function(code, reference) {
  exprs <- tryCatch(parse(text = code, keep.source = FALSE), error = function(e) e)
  if (inherits(exprs, "error")) return(sprintf("The code does not parse: %s", conditionMessage(exprs)))

  problems <- character(0)
  visit <- function(x) {
    if (!is.call(x)) return(invisible())
    head <- x[[1]]
    name <- if (is.name(head)) as.character(head) else if (is.call(head) && as.character(head[[1]]) %in% c("::", ":::")) as.character(head[[3]]) else NA_character_
    if (!is.na(name) && grepl("^(ds|datashield)\\.", name)) {
      fn <- reference$functions[[name]]
      if (is.null(fn)) {
        problems <<- c(problems, sprintf("%s() does not exist in the installed client packages.", name))
      } else if (!fn$dots) {
        given <- names(x)[-1]
        unknown <- setdiff(given[!is.na(given) & nzchar(given)], fn$args)
        if (length(unknown) > 0) {
          problems <<- c(problems, sprintf(
            "%s() has no argument %s (its arguments: %s).",
            name, paste(sprintf("'%s'", unknown), collapse = ", "), paste(fn$args, collapse = ", ")
          ))
        }
      }
    }
    # Empty arguments (the gap in x[, 1]) can't be passed on; skip them.
    args <- as.list(x)[-1]
    for (i in seq_along(args)) if (!identical(args[[i]], quote(expr = ))) visit(args[[i]])
    invisible()
  }
  for (e in exprs) visit(e)
  unique(problems)
}
