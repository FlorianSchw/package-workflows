# Checks generated R code before it runs: it must parse, every ds.*() and
# datashield.*() function it calls must exist in the installed client
# packages (`reference$functions` from client_function_reference()), and
# every named argument must be one of that function's arguments (unless it
# takes `...`). Returns the problems found (character(0) if none), worded
# for Claude's repair round and the report. Other functions (base R,
# stats, ...) aren't checked here; the test run catches those.
check_ds_calls <- function(code, reference) {
  problems <- character(0)
  parse_error <- walk_code(code, function(x, arg) {
    if (!is.call(x)) return()
    head <- x[[1]]
    name <- if (is.name(head)) as.character(head)
      else if (is.call(head) && as.character(head[[1]]) %in% c("::", ":::")) as.character(head[[3]])
      else NA_character_
    if (is.na(name) || !grepl("^(ds|datashield)\\.", name)) return()
    fn <- reference$functions[[name]]
    if (is.null(fn)) {
      problems <<- c(problems, sprintf("%s() does not exist in the installed client packages, or may not be used.", name))
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
  })
  if (!is.null(parse_error)) return(sprintf("The code does not parse: %s", conditionMessage(parse_error)))
  unique(problems)
}
